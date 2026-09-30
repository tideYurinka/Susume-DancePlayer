import 'dart:async';

import 'package:dance_learning_app/beat/beat_pipeline.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

/// 节拍分析 fake（seam 注入）：管线
/// 抽象注入，不依赖真实 ffmpeg/ONNX/DBN。
class FakeBeatPipeline implements BeatAnalysisPipeline {
  FakeBeatPipeline({
    this.result = const [
      BeatPoint(t: 0.5, down: true),
      BeatPoint(t: 1.0, down: false),
      BeatPoint(t: 1.5, down: false),
      BeatPoint(t: 2.0, down: false),
    ],
    this.error,
    this.hangUntilCancelled = false,
    this.pcmRmsValue,
  });

  /// 成功时返回的拍点序列。
  final List<BeatPoint> result;

  /// 非空时 analyze 抛 [BeatAnalysisException]（失败路径）。
  final String? error;

  /// 非空时模拟「解码顺带测量」：analyze 内以该 RMS 触发
  /// `request.onPcmRms`。
  final double? pcmRmsValue;

  /// 为 true 时 analyze 挂起直到被取消或解除（字段实时读取，测试可中途
  /// 置 false 解除挂起）。
  bool hangUntilCancelled;

  int calls = 0;
  final List<String> paths = [];
  final List<Completer<void>> _inFlight = [];

  /// 等待当前所有在途 analyze 结束（测试收尾防泄漏）。
  Future<void> get settled => Future.wait(_inFlight.map((c) => c.future));

  @override
  Future<List<BeatPoint>> analyze(BeatAnalysisRequest request) async {
    calls++;
    paths.add(request.videoPath);
    final completer = Completer<void>();
    _inFlight.add(completer);
    try {
      if (hangUntilCancelled) {
        // 挂起直到被取消或解除挂起（字段实时读取，测试可中途解除）。
        while (hangUntilCancelled &&
            !(request.isCancelled?.call() ?? false)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        if (request.isCancelled?.call() ?? false) {
          throw const BeatAnalysisCancelled();
        }
      }
      if (error != null) {
        throw BeatAnalysisException(error!);
      }
      if (pcmRmsValue != null) {
        request.onPcmRms?.call(pcmRmsValue!);
      }
      return result;
    } finally {
      completer.complete();
      _inFlight.remove(completer);
    }
  }
}
