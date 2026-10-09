import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/player/engine_seek.dart';
import 'package:dance_learning_app/player/cast_mirror.dart'
    show CastMirror, NoCastMirror;
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/recording_playback_takeover.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录每一次镜像的假投屏镜像口（投屏态内本机动作 → 接收端）。
class _RecordingCastMirror implements CastMirror {
  final List<String> calls = [];
  final List<Duration> seeks = [];

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
    seeks.add(position);
  }
}

/// EngineSeek 模块面测试：不 pump widget、不注
/// 容器，直接驱动引擎与 seek/scrub 域，断言它交出的外部可观察事实——接管
/// 事实、seek 提交次序与钳制、拖动会话起止、引擎生命周期与流订阅。
void main() {
  late FakePlaybackEngine engine;
  late GestureFeedbackController feedback;
  late ValueNotifier<Duration> scrubTarget;
  late List<String> events;
  late List<Duration> committed;
  late int interruptCalls;
  late List<bool> playingEdges;
  late int completedCalls;
  late int positionTicks;

  RecordingPlaybackTakeover buildTakeover() => RecordingPlaybackTakeover(
    disableRecordingLoop: () {},
    restoreLearningSegmentLoop: () {},
    setRecordingMarker: (_) {},
    endScrubSession: () async {},
    interruptPendingDelayedPlay: () {},
    stopRecordingSession: () async {},
  );

  EngineSeek build({RecordingPlaybackTakeover? takeover, CastMirror? mirror}) {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 100));
    feedback = GestureFeedbackController();
    scrubTarget = ValueNotifier(Duration.zero);
    events = <String>[];
    committed = <Duration>[];
    interruptCalls = 0;
    playingEdges = <bool>[];
    completedCalls = 0;
    positionTicks = 0;
    final resolved = takeover ?? buildTakeover();
    return EngineSeek(
      engine: engine,
      takeoverOf: () => resolved,
      timeline: () =>
          AnnotationTimeline.wholeVideo(const Duration(seconds: 100)),
      clearLoops: (_, _) => events.add('clearLoops'),
      interruptPendingDelayedPlay: () => interruptCalls++,
      onScrubCommitted: committed.add,
      feedback: feedback,
      scrubTarget: scrubTarget,
      onPlayingEdge: playingEdges.add,
      onPosition: () => positionTicks++,
      onCompleted: () async => completedCalls++,
      isMounted: () => true,
      castMirrorOf: () => mirror ?? const NoCastMirror(),
    );
  }

  tearDown(() {
    feedback.dispose();
    scrubTarget.dispose();
  });

  group('接管事实', () {
    test('takenOver 取自接管域：engage 后为真、disengage 后为假', () {
      final takeover = buildTakeover();
      final domain = build(takeover: takeover);
      expect(domain.takenOver, isFalse);
      takeover.engage(suppressLoop: true);
      expect(domain.takenOver, isTrue);
      takeover.disengage();
      expect(domain.takenOver, isFalse);
    });
  });

  group('拖动会话起止', () {
    test('在播 beginScrub：先 pause 再可 seek，scrubbing 为真且相位就位', () async {
      final domain = build();
      await engine.play();
      engine.callLog.clear();

      expect(await domain.beginScrub(), isTrue);
      expect(domain.scrubbing, isTrue);
      expect(feedback.isScrubbing, isTrue);
      expect(engine.callLog, ['pause']);
      expect(engine.isPlaying, isFalse);
      expect(scrubTarget.value, engine.position);
    });

    test('moveScrubBy 经提交口落点：目标 = 定格基准 + 累计，钳制下界', () async {
      final domain = build();
      await engine.seek(const Duration(seconds: 10));
      engine.seekCalls.clear();
      await domain.beginScrub();

      domain.moveScrubBy(const Duration(seconds: 5));
      domain.moveScrubBy(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(engine.seekCalls.last, const Duration(seconds: 20));

      domain.moveScrubBy(const Duration(seconds: -30));
      await pumpEventQueue();
      expect(engine.seekCalls.last, Duration.zero);
      expect(scrubTarget.value, Duration.zero);
    });

    test('未起会话 moveScrubBy：丢弃（不 seek）', () {
      final domain = build();
      domain.moveScrubBy(const Duration(seconds: 5));
      expect(engine.seekCalls, isEmpty);
    });

    test('逐帧正增量：目标单调不减（真机回归：目标不来回横跳）', () async {
      final domain = build();
      await engine.seek(const Duration(seconds: 10));
      engine.seekCalls.clear();
      await domain.beginScrub();
      for (var i = 0; i < 5; i++) {
        domain.moveScrubBy(const Duration(seconds: 2));
      }
      await pumpEventQueue();
      expect(engine.seekCalls, isNotEmpty);
      for (var i = 1; i < engine.seekCalls.length; i++) {
        expect(
          engine.seekCalls[i] - engine.seekCalls[i - 1],
          greaterThanOrEqualTo(Duration.zero),
        );
      }
      expect(engine.seekCalls.last, const Duration(seconds: 20));
    });

    test('endScrub 恢复手势前播放态并收相位；重复 end 幂等', () async {
      final domain = build();
      await engine.play();
      engine.callLog.clear();
      await domain.beginScrub();
      await domain.endScrub();
      expect(engine.callLog, ['pause', 'play']);
      expect(engine.isPlaying, isTrue);
      expect(domain.scrubbing, isFalse);
      expect(feedback.isScrubbing, isFalse);

      engine.callLog.clear();
      await domain.endScrub();
      expect(engine.callLog, isEmpty);
    });

    test('取消收口：回退到定格基准、回报被跳过', () async {
      final domain = build();
      await engine.seek(const Duration(seconds: 30));
      engine.seekCalls.clear();
      await domain.beginScrub();
      domain.moveScrubBy(const Duration(seconds: 10));
      await domain.endScrub(cancel: true);

      expect(engine.seekCalls.last, const Duration(seconds: 30));
      expect(committed, isEmpty);
    });

    test('非取消收口回报落点', () async {
      final domain = build();
      await engine.seek(const Duration(seconds: 30));
      await domain.beginScrub();
      domain.moveScrubBy(const Duration(seconds: 10));
      await domain.endScrub();
      expect(committed, [const Duration(seconds: 40)]);
    });
  });

  group('seek 提交', () {
    test('seek 经唯一提交口：钳制 + clearLoops 先于入队 + 打断在途延迟播放', () async {
      final domain = build();
      domain.seek(const Duration(seconds: 150));
      expect(events, ['clearLoops']);
      expect(interruptCalls, 1);
      await pumpEventQueue();
      expect(engine.seekCalls, [const Duration(seconds: 100)]);
    });

    test('seek 钳制下界到 0', () async {
      final domain = build();
      domain.seek(const Duration(seconds: -5));
      await pumpEventQueue();
      expect(engine.seekCalls, [Duration.zero]);
    });

    test('seekAndSettle 等待目标实际发往引擎', () async {
      final domain = build();
      await domain.seekAndSettle(const Duration(seconds: 42));
      expect(engine.seekCalls, [const Duration(seconds: 42)]);
    });
  });

  group('投屏遥控镜像（投屏态内本机动作同时作用于接收端）', () {
    test('播放 / 暂停：本机照常 + 接收端各收一条', () async {
      final mirror = _RecordingCastMirror();
      final domain = build(mirror: mirror);

      await domain.play();
      await domain.pause();

      expect(engine.callLog, ['play', 'pause'], reason: '本机动作照常');
      expect(mirror.calls, ['play', 'pause']);
    });

    test('seek 单发：落点（钳制后）镜像给接收端', () async {
      final mirror = _RecordingCastMirror();
      final domain = build(mirror: mirror);

      domain.seek(const Duration(seconds: 150));
      await pumpEventQueue();

      expect(mirror.seeks, [const Duration(seconds: 100)]);
    });

    test('seekAndSettle（学习段跳段首一类）：落点同样镜像', () async {
      final mirror = _RecordingCastMirror();
      final domain = build(mirror: mirror);

      await domain.seekAndSettle(const Duration(seconds: 42));

      expect(mirror.seeks, [const Duration(seconds: 42)]);
    });

    test('拖进度：拖动期间不镜像、离手后只按收口落点镜像一次', () async {
      final mirror = _RecordingCastMirror();
      final domain = build(mirror: mirror);
      await engine.seek(const Duration(seconds: 10));

      await domain.beginScrub();
      domain.moveScrubBy(const Duration(seconds: 2));
      domain.moveScrubBy(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(mirror.seeks, isEmpty, reason: '逐帧拖动不发往接收端');

      await domain.endScrub();
      await pumpEventQueue();
      expect(mirror.seeks, hasLength(1));
      expect(mirror.seeks.single, scrubTarget.value);
    });

    test('未接投屏（空操作那份）：本机动作照常、无任何镜像', () async {
      final domain = build();
      await domain.play();
      await domain.pause();
      expect(engine.callLog, ['play', 'pause']);
    });
  });

  group('引擎生命周期', () {
    test('open 委托引擎：源与起播参数原样传递', () async {
      final domain = build();
      await domain.open(Uri.parse('file:///a.mp4'), play: true);
      expect(engine.source, Uri.parse('file:///a.mp4'));
      expect(engine.isPlaying, isTrue);
    });

    test('attach 转发播放态边沿与播放完成事件', () async {
      final domain = build();
      domain.attach();
      await engine.play();
      engine.simulateCompleted();
      await pumpEventQueue();
      expect(playingEdges, [true, false]);
      expect(completedCalls, 1);
    });

    test('attach 转发位置报位；detach 后位置报位不再转发', () async {
      final domain = build();
      domain.attach();
      await engine.seek(const Duration(seconds: 3));
      await pumpEventQueue();
      expect(positionTicks, 1);
      expect(engine.position, const Duration(seconds: 3));

      domain.detach();
      await engine.seek(const Duration(seconds: 8));
      await pumpEventQueue();
      expect(positionTicks, 1);
    });

    test('detach 取消订阅：其后播放态变化不再转发', () async {
      final domain = build();
      domain.attach();
      await engine.play();
      await pumpEventQueue();
      expect(playingEdges, [true]);

      domain.detach();
      await engine.pause();
      await pumpEventQueue();
      expect(playingEdges, [true]);
    });

    test('收尾停播：pause 停引擎且此后不转发播放态边沿', () async {
      final domain = build();
      domain.attach();
      await engine.play();
      await pumpEventQueue();
      domain.detach();
      await domain.pause();
      expect(engine.isPlaying, isFalse);
      expect(playingEdges, [true]);
    });
  });
}
