import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/beat_regularization.dart';
import '../persistence/marker_document.dart' show BeatPoint;
import 'dbn.dart';
import 'loudness_probe.dart' show pcmRms;
import 'preprocess.dart';

/// 节拍分析请求。
class BeatAnalysisRequest {
  const BeatAnalysisRequest({
    required this.videoPath,
    this.isCancelled,
    this.onPcmRms,
  });

  /// 源视频路径（任意含音轨的音视频文件）。
  final String videoPath;

  /// 取消探测（管线在阶段边界轮询；返回 true 时尽快放弃且不产出结果）。
  final bool Function()? isCancelled;

  /// 解码顺带响度测量回调（解码完成后以整轨 PCM RMS 调用一次；
  /// null = 不测量）。
  final void Function(double pcmRms)? onPcmRms;
}

/// 分析被取消（中断/新分析接管）：不产出结果、不落盘。
class BeatAnalysisCancelled implements Exception {
  const BeatAnalysisCancelled();
}

/// 分析失败（解码失败、无有效音轨、无有效拍点等）。
class BeatAnalysisException implements Exception {
  const BeatAnalysisException(this.message);

  final String message;

  @override
  String toString() => 'BeatAnalysisException: $message';
}

/// 节拍分析管线 seam：ffmpeg 解码 → Dart 前处理 → 纯 RNN ONNX → Dart DBN。
///
/// 生产实现为 [OnnxBeatAnalysisPipeline]（真机验证过的方案 C 管线）；
/// 单元测试注入 fake（不依赖真实解码/推理）。
abstract interface class BeatAnalysisPipeline {
  /// 分析 [request.videoPath] 的节拍。成功返回拍点序列（t 秒 + downbeat）；
  /// 被取消抛 [BeatAnalysisCancelled]；失败抛 [BeatAnalysisException]。
  Future<List<BeatPoint>> analyze(BeatAnalysisRequest request);
}

/// 随包模型资产。
const String kBeatModelAsset = 'assets/models/madmom_downbeat_rnn_full.onnx';
const String kBeatFilterbankAsset = 'assets/models/filterbanks_f32.bin';

/// DBN 解码移入后台 isolate。独立顶层函数：闭包只捕获本函数参数
/// （纯 TypedData），不携带 analyze() 局部作用域里的不可发送对象
/// （ffmpeg session / 插件 completer 等）。
Future<List<({double t, int beatNumber})>> _dbnDecodeInIsolate(
  Float32List beatAct,
  Float32List downbeatAct,
  int fps,
) => Isolate.run(() => dbnDecode(beatAct, downbeatAct, fps: fps));

/// DBN 解码产物 → 节拍规整 → 落盘拍点（阶段 4 与 [BeatPoint] 构造之间）。
///
/// 规整在识别之后、拍点落盘之前执行一次：时刻量化到整毫秒后经
/// [regularizeBeatTimes] 有界相位等时化；规格不合（拍点不足、非严格递增、
/// 内部异常）时整条原样输出，分析照常成功。`beatNumber` 原样透传，
/// down 标志仍由 `beatNumber == 1` 得出；落盘拍点因此就是规整产物，产品内
/// 不存在第二套网格。
List<BeatPoint> regularizeDecodedBeats(
  List<({double t, int beatNumber})> decoded,
) {
  final recognized = [
    for (final beat in decoded) Duration(milliseconds: (beat.t * 1000).round()),
  ];
  final regularized = regularizeBeatTimes(recognized).times;
  return [
    for (var i = 0; i < decoded.length; i++)
      BeatPoint(
        t: regularized[i].inMilliseconds / 1000.0,
        down: decoded[i].beatNumber == 1,
      ),
  ];
}

/// 方案 C 端侧推理管线（迁移自 throwaway/beat-mobile-prototype 真机验证
/// 实现）：ffmpeg 一次性解码单声道 f32le PCM 到临时文件（分析完即删，不做
/// PCM 缓存）→ Dart 前处理（多 isolate 并行，段首 lookback 保证逐位一致）
/// → 纯 RNN 整轨单趟推理 → Dart DBN 解码（fps=kBeatFps，固定 4/4 先验）。
///
/// 纯 RNN 形态的原因：图内含 STFT/DFT 前端的完整模型在 onnxruntime-android
/// 上 SIGSEGV（原型验证结论），前处理必须留在 Dart 侧。
class OnnxBeatAnalysisPipeline implements BeatAnalysisPipeline {
  @override
  Future<List<BeatPoint>> analyze(BeatAnalysisRequest request) async {
    final isCancelled = request.isCancelled ?? () => false;
    void checkCancelled() {
      if (isCancelled()) throw const BeatAnalysisCancelled();
    }

    final tempDir = await Directory.systemTemp.createTemp('beat_pcm_');
    final tempPcm = File('${tempDir.path}/pcm_f32.raw');
    try {
      // 阶段 1：ffmpeg 一次性解码 → 单声道 f32le PCM 临时文件。
      // executeWithArgumentsAsync + 轮询：离开页面等取消令牌置位即调
      // FFmpegKit.cancel 中止在途解码，
      // 不等长片解码自然跑完。
      final decoded = Completer<void>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        [
          '-y',
          '-loglevel',
          'error',
          '-i',
          request.videoPath,
          '-vn',
          '-ac',
          '1',
          '-ar',
          '$kSampleRate',
          '-f',
          'f32le',
          tempPcm.path,
        ],
        (doneSession) {
          if (!decoded.isCompleted) decoded.complete();
        },
      );
      while (!decoded.isCompleted) {
        if (isCancelled()) {
          await FFmpegKit.cancel(session.getSessionId());
          throw const BeatAnalysisCancelled();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await decoded.future;
      checkCancelled();
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getAllLogsAsString();
        throw BeatAnalysisException('ffmpeg 解码失败: $logs');
      }
      final bytes = await tempPcm.readAsBytes();
      if (bytes.isEmpty) {
        throw const BeatAnalysisException('无有效音轨（解码输出为空）');
      }
      final pcm = Float32List.view(bytes.buffer, 0, bytes.lengthInBytes ~/ 4);
      checkCancelled();
      // 节拍分析解码顺带测量歌曲响度（整轨 RMS，一次调用）。
      request.onPcmRms?.call(pcmRms(pcm));

      // 阶段 2：加载纯 RNN ONNX 会话与 filterbank 常量。
      final ort = OnnxRuntime();
      OrtSession? ortSession;
      final values = <OrtValue>[];
      try {
        ortSession = await ort.createSessionFromAsset(kBeatModelAsset);
        final inputName = ortSession.inputNames.first;
        final fbBytes = await rootBundle.load(kBeatFilterbankAsset);
        final filterbanks = Filterbank.unpack(
          Filterbank.payloadFromBytes(fbBytes.buffer.asUint8List()),
        );
        checkCancelled();

        // 阶段 3a：Dart 前处理（多 isolate 并行，数值与串行逐位一致）。
        final features = await preprocessPcmParallel(pcm, filterbanks);
        checkCancelled();

        // 阶段 3b：纯 RNN 整轨单趟推理，输出扁平 [n*2]（偶数位 beat、
        // 奇数位 downbeat 概率）。flutter_onnxruntime 走 platform channels，
        // 只能在 root isolate 调用，推理因此留在主 isolate 异步执行（多
        // isolate 推理在该插件约束下不可达；真机冒烟验证不阻塞播放）。
        final nFrames = features.length ~/ kFeatureDim;
        final input = await OrtValue.fromList(features, [nFrames, kFeatureDim]);
        values.add(input);
        final outputs = await ortSession.run({inputName: input});
        values.addAll(outputs.values);
        final flat = await outputs.values.first.asFlattenedList();
        checkCancelled();

        // 阶段 4：Dart DBN 解码（固定 4/4 先验，fps=kBeatFps）。Viterbi 解码
        // 在后台 isolate 执行：真机实测 20k 帧 DBN 解码约 50s，留在主
        // isolate 会完全冻结 UI（ANR）。解码为纯函数，结果与主 isolate
        // 逐位一致。概率提取留主 isolate（~40ms）：插件返回的 list 内部持有
        // 不可发送对象，不能跨 isolate 传递。
        final beatAct = Float32List(nFrames);
        final downAct = Float32List(nFrames);
        for (var i = 0; i < nFrames; i++) {
          beatAct[i] = (flat[i * 2] as num).toDouble();
          downAct[i] = (flat[i * 2 + 1] as num).toDouble();
        }
        final beats = await _dbnDecodeInIsolate(beatAct, downAct, kBeatFps);
        if (beats.isEmpty) {
          throw const BeatAnalysisException('无有效拍点');
        }
        return regularizeDecodedBeats(beats);
      } finally {
        // 张量与会话按生命周期释放（失败/取消路径同样不残留原生内存）。
        for (final value in values) {
          await value.dispose();
        }
        await ortSession?.close();
      }
    } finally {
      // 分析完即删（成功/失败/取消均不残留 PCM），临时目录一并清理。
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } on Object {
        // 临时文件清理失败不掩盖分析结果。
      }
    }
  }
}
