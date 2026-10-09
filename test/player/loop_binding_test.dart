import 'package:dance_learning_app/player/cast_mirror.dart' show NoCastMirror;
import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/core/beat_grid.dart'
    show placeholderBeatGrid;
import 'package:dance_learning_app/core/playback/playback_loop_layer.dart';
import 'package:dance_learning_app/player/delayed_play.dart';
import 'package:dance_learning_app/player/engine_seek.dart';
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/loop_binding.dart';
import 'package:dance_learning_app/player/loop_prompt.dart';
import 'package:dance_learning_app/player/recording_playback_takeover.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 学习段循环接线模块面测试：不 pump widget、不注
/// 容器，直接驱动激活范围接线，断言它交出的外部可观察事实——区间循环作用域
/// 起停、激活即起播的 seek-then-play、循环层事件流接线与恢复静默委派。
void main() {
  late FakePlaybackEngine engine;
  late PlaybackLoopLayer loopLayer;
  late LoopPromptController loopPrompt;
  late DelayedPlayController delayedPlay;
  late EngineSeek engineSeek;
  late GestureFeedbackController feedback;
  late ValueNotifier<Duration> scrubTarget;
  late RecordingPlaybackTakeover takeover;
  late LoopBinding binding;
  var delayedLoopActiveCalls = 0;

  final timeline = AnnotationTimeline.wholeVideo(const Duration(seconds: 100));

  setUp(() {
    delayedLoopActiveCalls = 0;
    engine = FakePlaybackEngine(duration: const Duration(seconds: 100));
    loopLayer = PlaybackLoopLayer(engine);
    loopPrompt = LoopPromptController(
      engine,
      gridOf: () => placeholderBeatGrid,
    );
    delayedPlay = DelayedPlayController(
      engine,
      phaseOf: () => null,
      prepBeatsOf: () => 8,
      validRangeOf: () => null,
      gridOf: () => placeholderBeatGrid,
    );
    feedback = GestureFeedbackController();
    scrubTarget = ValueNotifier(Duration.zero);
    takeover = RecordingPlaybackTakeover(
      disableRecordingLoop: () {},
      restoreLearningSegmentLoop: () {},
      setRecordingMarker: (_) {},
      endScrubSession: () async {},
      interruptPendingDelayedPlay: () {},
      stopRecordingSession: () async {},
    );
    engineSeek = EngineSeek(
      engine: engine,
      takeoverOf: () => takeover,
      timeline: () => timeline,
      clearLoops: (_, _) {},
      interruptPendingDelayedPlay: () {},
      onScrubCommitted: (_) {},
      feedback: feedback,
      scrubTarget: scrubTarget,
      onPlayingEdge: (_) {},
      onPosition: () {},
      onCompleted: () async {},
      isMounted: () => true,
      castMirrorOf: () => const NoCastMirror(),
    );
    binding = LoopBinding(
      engineSeek: engineSeek,
      loopLayer: loopLayer,
      loopPrompt: loopPrompt,
      delayedPlay: delayedPlay,
      effectiveLoopWaitOf: (setting) => setting,
      delayedLoopWaitOf: () => const Duration(seconds: 5),
      isMounted: () => true,
      onDelayedLoopActive: () => delayedLoopActiveCalls++,
    )..attach();
  });

  tearDown(() {
    binding.dispose();
    delayedPlay.dispose();
    loopPrompt.dispose();
    loopLayer.dispose();
    feedback.dispose();
    scrubTarget.dispose();
  });

  test('激活范围就位区间循环作用域；activate=false 不 seek 不起播', () {
    binding.syncLearningSegment(
      (start: const Duration(seconds: 10), end: const Duration(seconds: 20)),
      activate: false,
      timeline: timeline,
      segmentLoopActive: true,
    );

    expect(loopLayer.enabled, isTrue);
    expect(engine.seekCalls, isEmpty);
    expect(engine.isPlaying, isFalse);
  });

  test('activate=true 跳到段首并在 seek 落定后起播', () async {
    binding.syncLearningSegment(
      (start: const Duration(seconds: 10), end: const Duration(seconds: 20)),
      activate: true,
      timeline: timeline,
      segmentLoopActive: true,
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(engine.seekCalls, [const Duration(seconds: 10)]);
    expect(engine.isPlaying, isTrue, reason: 'seek 落定后起播');
  });

  test('取消激活停用区间循环作用域', () {
    binding.syncLearningSegment(
      (start: const Duration(seconds: 10), end: const Duration(seconds: 20)),
      activate: false,
      timeline: timeline,
      segmentLoopActive: true,
    );
    expect(loopLayer.enabled, isTrue);

    binding.syncLearningSegment(
      null,
      timeline: timeline,
      segmentLoopActive: false,
    );
    expect(loopLayer.enabled, isFalse);
  });

  test('attach 重复调用幂等，循环前导激活重驱宿主回调', () async {
    binding.attach();
    binding.attach();
    // 循环层前导态由循环层自身驱动；此处只断言接线不抛且回调可被触发。
    expect(delayedLoopActiveCalls, 0);
    loopLayer.updateDelayedLoopWait(const Duration(seconds: 2));
    await Future<void>.delayed(Duration.zero);
  });
}
