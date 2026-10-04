import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine.dart';
import 'package:dance_learning_app/persistence/practice_accounting.dart';

/// 练习记账事实源替身：把引擎的 isPlaying
/// 边沿搬进事实流，其余事实（回看在飞 / 录制准备期）由测试手动翻转——
/// 与生产组装（`player/practice_accounting_providers.dart` 的
/// `practiceAccountingFactsProvider`）同一
/// 形状：引擎边沿一条事件、手动翻转一条事件。
class FakePracticeFactsSource {
  FakePracticeFactsSource(PlaybackEngine engine) : _engine = engine {
    engine.isPlayingStream.listen(emit);
  }

  final PlaybackEngine _engine;

  bool clipReviewInFlight = false;
  bool recordingPreparing = false;
  bool delayedPlayPreparing = false;

  final StreamController<PracticeAccountingFacts> _controller =
      StreamController<PracticeAccountingFacts>();

  Stream<PracticeAccountingFacts> get stream => _controller.stream;

  /// 翻转专属事实并发出一条事实事件（引擎播放态取当前现值）。
  void set({
    bool? clipReviewInFlight,
    bool? recordingPreparing,
    bool? delayedPlayPreparing,
  }) {
    if (clipReviewInFlight != null) {
      this.clipReviewInFlight = clipReviewInFlight;
    }
    if (recordingPreparing != null) {
      this.recordingPreparing = recordingPreparing;
    }
    if (delayedPlayPreparing != null) {
      this.delayedPlayPreparing = delayedPlayPreparing;
    }
    emit(_engine.isPlaying);
  }

  void emit(bool enginePlaying) => _controller.add(
    PracticeAccountingFacts(
      enginePlaying: enginePlaying,
      clipReviewInFlight: clipReviewInFlight,
      recordingPreparing: recordingPreparing,
      delayedPlayPreparing: delayedPlayPreparing,
    ),
  );
}
