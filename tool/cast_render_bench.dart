/// 投屏渲染计时入口（Android 设备侧）：在**已连接的安卓目标**（真机或模拟器）上
/// 用**已链接的 ffmpeg 包**跑完整滤镜图，量墙钟、留档编码器、验产物。
///
/// 它不经任何生产路径：以 `-t` 换入口跑（`tool/cast_render_bench.sh` 就是这么
/// 打包运行的），生产 `main.dart` 与本入口互不引用、互不影响。
///
/// 命令与判定全部来自 `tool/cast_render_bench/bench_core.dart`——与宿主对照
/// （`tool/cast_render_bench_host.dart`）**同一份滤镜图、同一组判定**。
///
/// 输入优先用**宿主准备好的固定三件套**（`tool/cast_render_bench.sh` 生成并
/// 推入应用支持目录下的 `cast_bench_inputs/`，哈希随读数留档）；推送缺失时
/// 回落到本机生成（同样一串参数，编解码器换成设备这份包里的硬编）。
///
/// 用法：
///   `tool/cast_render_bench.sh -d <serial> [--runs 3] [--out <本机目录>]`
/// 输出：
///   日志里的 `CAST_BENCH ...` 行 + 设备上
///   应用支持目录下 `cast_bench/cast_render_bench_device.json`（脚本会拉回来）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'cast_render_bench/bench_core.dart';

/// 每档跑几遍。真机连跑三次看发热与降频的默认值；改它只影响跑几遍。
const int kBenchRuns = int.fromEnvironment('CAST_BENCH_RUNS', defaultValue: 3);

/// 用哪个视频编码器。默认是**已链接包在 Android 上唯一的 H.264 硬编**
/// （`h264_mediacodec`）——那是本关卡要量的那一档。换它只为在没有硬编的目标上
/// 验滤镜图与流程（例如只有软件编码的模拟器），读数**不是**真机吞吐结论。
const String kBenchEncoderName = String.fromEnvironment(
  'CAST_BENCH_ENCODER',
  defaultValue: kDeviceEncoder,
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BenchApp());
}

/// 计时入口的壳：跑一遍、把读数摊在屏上（也逐行打到日志里）。
class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> {
  final List<String> _lines = <String>[];
  String _status = '准备中';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  void _log(String line) {
    debugPrint('CAST_BENCH $line');
    if (mounted) {
      setState(() => _lines.add(line));
    }
  }

  Future<void> _run() async {
    final runner = _DeviceBench(log: _log);
    try {
      final report = await runner.run();
      final ok = report['ok'] == true;
      _log('JSON ${jsonEncode(report)}');
      if (mounted) {
        setState(() => _status = ok ? '完成：读数成立' : '完成：有读数不成立');
      }
    } on Object catch (error, stack) {
      _log('FAILED $error');
      _log('$stack');
      if (mounted) {
        setState(() => _status = '失败：$error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('投屏渲染计时入口 · $_status')),
        body: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: _lines.length,
          itemBuilder: (context, index) => Text(
            _lines[index],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ),
    );
  }
}

/// 设备侧的一次完整计时。
class _DeviceBench {
  _DeviceBench({required this.log});

  final void Function(String line) log;

  Future<Map<String, Object?>> run() async {
    final support = await getApplicationSupportDirectory();
    final pushedInputs = Directory('${support.path}/cast_bench_inputs');
    final work = Directory('${support.path}/cast_bench')
      ..createSync(recursive: true);
    final artifacts = Directory('${work.path}/artifacts')
      ..createSync(recursive: true);

    final version = await FFmpegKitConfig.getFFmpegVersion();
    log('ffmpeg(已链接包) $version');

    // 离线命令逃生口：应用支持目录里放了 `command.json` 就只跑它。
    // 迭代诊断（换编码器、换滤镜写法）因此不必每次重打包。
    final commandFile = File('${work.path}/command.json');
    if (commandFile.existsSync()) {
      return _runCommand(commandFile, work);
    }

    final inputs = pushedInputs.existsSync()
        ? _Inputs(
            origin: 'pushed',
            source: '${pushedInputs.path}/source_1080p_30s.mp4',
            sticker: '${pushedInputs.path}/sticker_alpha.png',
            beat: '${pushedInputs.path}/beat_120bpm_30s.wav',
          )
        : await _generateInputs(work);

    for (final path in <String>[
      inputs.source,
      inputs.sticker,
      inputs.beat,
    ]) {
      if (!File(path).existsSync()) {
        throw StateError('输入缺失：$path');
      }
    }
    log('输入来源 ${inputs.origin}'
        '（源片 ${File(inputs.source).lengthSync()} 字节）');

    final capability = await _encoderCapability();
    final pick = await _encoderProbe('${work.path}/encoder_probe.log');

    // 先点一把火：同一张图、同一个编码器，但只产出前一秒。链路上但凡少一个
    // 滤镜、少一个编码器或贴纸解不开，这里几秒内就说话——不必等整片渲染。
    final smoke = await _smoke(
      sourcePath: inputs.source,
      stickerPath: inputs.sticker,
      beatPath: inputs.beat,
      outputPath: '${work.path}/smoke_1s.mp4',
      logPath: '${work.path}/smoke_1s.log',
    );
    if (!smoke.$1) {
      log('冒烟失败：${smoke.$2}');
      final failed = <String, Object?>{
        'runner': 'android-device',
        'ffmpeg': version,
        'encoder': kBenchEncoderName,
        'encoderIsGatePath': kBenchEncoderName == kDeviceEncoder,
        'inputs': inputs.toJson(),
        'encoderCapability': capability,
        'codecPick': pick == null
            ? null
            : <String, Object?>{
                'component': pick.component,
                'hardwareAccelerated': pick.hardwareAccelerated,
              },
        'smokeOk': false,
        'smokeLogTail': smoke.$2,
        'smokeLogFile': '${work.path}/smoke_1s.log',
        'runs': <Object?>[],
        'summary': <String, Object?>{},
        'ok': false,
        'finishedAt': DateTime.now().toIso8601String(),
      };
      File('${work.path}/cast_render_bench_device.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(failed),
      );
      return failed;
    }
    log('冒烟通过（前一秒的完整滤镜图已出片）');

    final runs = <BenchRunResult>[];
    for (final resolution in BenchResolution.values) {
      for (var i = 1; i <= kBenchRuns; i++) {
        final output = '${artifacts.path}/bench_${resolution.name}_$i.mp4';
        final result = await _runOnce(
          resolution: resolution,
          sourcePath: inputs.source,
          stickerPath: inputs.sticker,
          beatPath: inputs.beat,
          outputPath: output,
        );
        runs.add(result);
        log('${resolution.name} 第 $i 跑：${result.wallClockMs}ms，'
            '渲染 ${result.rendered ? '成功' : '失败'}，'
            '产物 ${result.artifact.ok ? '可播' : '不可播（${result.artifact.problems.join('；')}）'}，'
            '整片解码 ${result.fullyDecodable == true ? '通过' : '未通过'}');
      }
    }

    final summary = summarizeBenchRuns(runs);
    final report = <String, Object?>{
      'runner': 'android-device',
      'ffmpeg': version,
      'encoder': kBenchEncoderName,
      'encoderIsGatePath': kBenchEncoderName == kDeviceEncoder,
      'androidSdk': Platform.operatingSystemVersion,
      'inputs': inputs.toJson(),
      'inputsFixed': <String, Object?>{
        'durationSeconds': kBenchDurationSeconds,
        'fps': kBenchFps,
        'sourceWidth': kBenchSourceWidth,
        'sourceHeight': kBenchSourceHeight,
        'localMirrorWindows': kBenchLocalMirrorWindows
            .map((w) => <double>[w.start, w.end])
            .toList(),
        'stickerWindow': <double>[
          kBenchStickerWindow.start,
          kBenchStickerWindow.end,
        ],
        'stickerRectNormalized': <double>[
          kBenchStickerLeft,
          kBenchStickerTop,
          kBenchStickerWidth,
          kBenchStickerHeight,
        ],
        'framingRectNormalized': <double>[
          kBenchFramingLeft,
          kBenchFramingTop,
          kBenchFramingWidth,
          kBenchFramingHeight,
        ],
        'gop': kBenchGop,
        'bitrate1080p': BenchResolution.p1080.bitrate,
        'bitrate720p': BenchResolution.p720.bitrate,
      },
      'encoderCapability': capability,
      'codecPick': pick == null
          ? null
          : <String, Object?>{
              'component': pick.component,
              'hardwareAccelerated': pick.hardwareAccelerated,
            },
      'runs': runs.map(_runJson).toList(),
      'summary': <String, Object?>{
        'p1080': _timingJson(summary.p1080),
        'p720': _timingJson(summary.p720),
        'resolutionCoefficient': summary.resolutionCoefficient,
        'rejectedRuns': summary.rejected.length,
      },
      'ok': summary.p1080 != null &&
          summary.p720 != null &&
          summary.rejected.isEmpty,
      'finishedAt': DateTime.now().toIso8601String(),
    };

    File('${work.path}/cast_render_bench_device.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    log('报告落在 ${work.path}/cast_render_bench_device.json');
    log('1080p 中位 ${summary.p1080?.medianMs}ms，'
        '720p 中位 ${summary.p720?.medianMs}ms，'
        '分辨率影响系数 ${summary.resolutionCoefficient}');
    return report;
  }

  /// 前一秒的完整滤镜图，**带 verbose 日志**：它是出不了片时唯一的现场。
  /// 返回（是否出片，日志尾巴）；完整日志落 `smoke_1s.log`，随报告一起拉回。
  Future<(bool, String)> _smoke({
    required String sourcePath,
    required String stickerPath,
    required String beatPath,
    required String outputPath,
    required String logPath,
  }) async {
    final args = renderArgs(
      resolution: BenchResolution.p1080,
      sourcePath: sourcePath,
      stickerPath: stickerPath,
      beatPath: beatPath,
      outputPath: outputPath,
      encoder: kBenchEncoderName,
      limitSeconds: 1,
    );
    final session = await FFmpegKit.executeWithArguments(
      <String>['-loglevel', 'verbose', ...args],
    );
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    final logs = '${await session.getAllLogsAsString()}';
    File(logPath).writeAsStringSync(logs);
    final reading = await _probeArtifactReading(outputPath);
    if (!ok || reading == null || !reading.hasVideoStream) {
      return (false, _tail(logs));
    }
    return (true, '');
  }

  /// 离线命令：跑完写 `command_result.json`（返回码、墙钟、完整日志）。
  Future<Map<String, Object?>> _runCommand(
    File commandFile,
    Directory work,
  ) async {
    final spec = jsonDecode(commandFile.readAsStringSync())
        as Map<String, Object?>;
    final args = (spec['args'] as List<Object?>).cast<String>();
    final label = '${spec['label'] ?? 'command'}';
    log('离线命令：$label');
    final stopwatch = Stopwatch()..start();
    final session = await FFmpegKit.executeWithArguments(args);
    stopwatch.stop();
    final returnCode = await session.getReturnCode();
    final logs = '${await session.getAllLogsAsString()}';
    final result = <String, Object?>{
      'label': label,
      'args': args,
      'returnCode': returnCode == null ? null : '${returnCode.getValue()}',
      'ok': ReturnCode.isSuccess(returnCode),
      'wallClockMs': stopwatch.elapsedMilliseconds,
      'logs': logs,
    };
    File('${work.path}/command_result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(result),
    );
    log('返回码 ${returnCode?.getValue()}，墙钟 ${stopwatch.elapsedMilliseconds}ms');
    log('日志尾部 ${_tail(logs)}');
    return result;
  }

  /// 只读产物事实（不判可播性），冒烟与产物判定共用。
  Future<ArtifactReading?> _probeArtifactReading(String path) async {
    if (!File(path).existsSync()) {
      return null;
    }
    final session = await FFprobeKit.executeWithArguments(<String>[
      '-v', 'quiet',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      path,
    ]);
    return parseFfprobeOutput('${await session.getAllLogsAsString()}');
  }

  Future<_Inputs> _generateInputs(Directory work) async {
    final inputs = Directory('${work.path}/inputs')..createSync(recursive: true);
    log('没有推送的固定输入，落到设备侧生成');
    final source = '${inputs.path}/source_1080p_30s.mp4';
    final sticker = '${inputs.path}/sticker_alpha.png';
    final beat = '${inputs.path}/beat_120bpm_30s.wav';
    await _mustExecute(
      sourceGenerationArgs(
        outputPath: source,
        encoder: kBenchEncoderName,
      ),
      what: '生成源片',
    );
    await _mustExecute(
      stickerGenerationArgs(outputPath: sticker),
      what: '生成贴纸',
    );
    await _mustExecute(beatGenerationArgs(outputPath: beat), what: '生成拍声');
    return _Inputs(
      origin: 'generated-on-device',
      source: source,
      sticker: sticker,
      beat: beat,
    );
  }

  Future<Map<String, Object?>> _encoderCapability() async {
    final session = await FFmpegKit.executeWithArguments(
      encoderCapabilityArgs(encoder: kBenchEncoderName),
    );
    final logs = '${await session.getAllLogsAsString()}';
    final name = encoderCapabilityName(logs.split('\n'));
    log('编码器能力：${name ?? '认不出($kBenchEncoderName)'}');
    return <String, Object?>{
      'encoder': kBenchEncoderName,
      'found': name != null,
      'name': name,
      'raw': logs.split('\n').where((l) => l.trim().isNotEmpty).take(40).join('\n'),
    };
  }

  Future<MediaCodecPick?> _encoderProbe(String logPath) async {
    final session = await FFmpegKit.executeWithArguments(
      encoderProbeArgs(encoder: kBenchEncoderName),
    );
    final logs = '${await session.getAllLogsAsString()}';
    File(logPath).writeAsStringSync(logs);
    final pick = parseMediaCodecPick(logs.split('\n'));
    log(pick == null
        ? '组件名：日志里没读出（不猜）'
        : '组件名：${pick.component}'
            '（${pick.hardwareAccelerated ? '硬编' : '软件实现'}）');
    return pick;
  }

  Future<BenchRunResult> _runOnce({
    required BenchResolution resolution,
    required String sourcePath,
    required String stickerPath,
    required String beatPath,
    required String outputPath,
  }) async {
    final args = renderArgs(
      resolution: resolution,
      sourcePath: sourcePath,
      stickerPath: stickerPath,
      beatPath: beatPath,
      outputPath: outputPath,
      encoder: kBenchEncoderName,
    );
    final stopwatch = Stopwatch()..start();
    final session = await FFmpegKit.executeWithArguments(args);
    stopwatch.stop();
    final success = ReturnCode.isSuccess(await session.getReturnCode());
    final logs = '${await session.getAllLogsAsString()}';

    final decoded = success ? await _decodeCheck(outputPath) : (false, null);
    final artifact = await _probeArtifact(
      outputPath,
      resolution,
      decodedFrames: decoded.$2,
    );
    return BenchRunResult(
      resolution: resolution,
      wallClockMs: stopwatch.elapsedMilliseconds,
      rendered: success,
      artifact: artifact,
      fullyDecodable: success && decoded.$1,
      decodedFrames: decoded.$2,
      codecPick: parseMediaCodecPick(logs.split('\n')),
      stdoutTail: _tail(logs),
    );
  }

  Future<ArtifactVerdict> _probeArtifact(
    String path,
    BenchResolution resolution, {
    int? decodedFrames,
  }) async {
    final reading = await _probeArtifactReading(path);
    if (reading == null) {
      return const ArtifactVerdict(
        ok: false,
        problems: <String>['产物文件不存在或 ffprobe 读不出来'],
      );
    }
    return judgeArtifact(
      reading,
      expected: resolution,
      decodedFrames: decodedFrames,
    );
  }

  /// 整片解码一遍（`-f null -`）：产物「能播、且没丢帧」的强证据。
  /// 返回（是否无解码错误，解码帧数）。
  Future<(bool, int?)> _decodeCheck(String path) async {
    final session = await FFmpegKit.executeWithArguments(decodeCheckArgs(path));
    final ok = ReturnCode.isSuccess(await session.getReturnCode());
    final logs = '${await session.getAllLogsAsString()}';
    return (ok && !hasDecodeErrors(logs), parseDecodedFrameCount(logs));
  }

  Future<void> _mustExecute(
    List<String> args, {
    required String what,
  }) async {
    final session = await FFmpegKit.executeWithArguments(args);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      throw StateError('$what 失败：${_tail('${await session.getAllLogsAsString()}')}');
    }
  }

  String _tail(String text) {
    final lines = text.trim().split('\n');
    return lines.length <= 4
        ? lines.join(' / ')
        : lines.sublist(lines.length - 4).join(' / ');
  }

  Map<String, Object?> _runJson(BenchRunResult run) => <String, Object?>{
        'resolution': run.resolution.name,
        'wallClockMs': run.wallClockMs,
        'rendered': run.rendered,
        'artifactOk': run.artifact.ok,
        'artifactProblems': run.artifact.problems,
        'fullyDecodable': run.fullyDecodable,
        'decodedFrames': run.decodedFrames,
        'codecPick': run.codecPick == null
            ? null
            : <String, Object?>{
                'component': run.codecPick!.component,
                'hardwareAccelerated': run.codecPick!.hardwareAccelerated,
              },
        'logTail': run.stdoutTail,
      };

  Map<String, Object?>? _timingJson(ResolutionTiming? timing) => timing == null
      ? null
      : <String, Object?>{
          'samplesMs': timing.samplesMs,
          'medianMs': timing.medianMs,
          'minMs': timing.minMs,
          'maxMs': timing.maxMs,
          'realtimeFactor': timing.realtimeFactor,
        };
}

/// 输入三件套的来路与路径。
class _Inputs {
  _Inputs({
    required this.origin,
    required this.source,
    required this.sticker,
    required this.beat,
  });

  final String origin;
  final String source;
  final String sticker;
  final String beat;

  Map<String, Object?> toJson() => <String, Object?>{
        'origin': origin,
        'source': <String, Object?>{
          'path': source,
          'bytes': File(source).lengthSync(),
        },
        'sticker': <String, Object?>{
          'path': sticker,
          'bytes': File(sticker).lengthSync(),
        },
        'beat': <String, Object?>{
          'path': beat,
          'bytes': File(beat).lengthSync(),
        },
        'note': 'origin=pushed 时字节与宿主生成的那一份相同（哈希见宿主报告）',
      };
}
