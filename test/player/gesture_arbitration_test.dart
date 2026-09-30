import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/player/framing_session_state.dart';
import 'package:dance_learning_app/player/editor_entry.dart';
import 'package:dance_learning_app/player/engine_seek.dart';
import 'package:dance_learning_app/player/framing_session.dart';
import 'package:dance_learning_app/player/gesture_arbitration.dart';
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/gestures.dart'
    show SystemGestureYieldInsets, systemGestureYieldInsets;
import 'package:dance_learning_app/player/level_control.dart';
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show MetronomeOverlayController;
import 'package:dance_learning_app/player/notice.dart' show NoticeId;
import 'package:dance_learning_app/player/presentation_session.dart'
    show PresentationSession;
import 'package:dance_learning_app/player/recording_playback_takeover.dart';
import 'package:dance_learning_app/player/segment_jump.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_volume.dart';

/// 播放手势仲裁域模块面测试：不 pump widget、
/// 不注容器（除模式取值 owner 外），直接驱动手势仲裁，断言它交出的外部
/// 可观察事实——轴锁与灵敏度、突发指针锁定、取消区回退、三指跳转、长按
/// 二倍速、取景分支、单击与录制期拒绝。
void main() {
  late FakePlaybackEngine engine;
  late GestureFeedbackController feedback;
  late ValueNotifier<Duration> scrubTarget;
  late FakeScreenBrightnessController brightness;
  late FakeSystemMediaVolumeController volume;
  late RecordingPlaybackTakeover takeover;
  late ProviderContainer container;
  late EditorEntry editorEntry;
  late FramingSessionHost framing;
  late LevelControl level;

  late List<String> framingCalls;
  late List<ThreeFingerSwipeDirection> writtenDirections;
  late List<NoticeId> shownNotices;
  late int beginRateCalls;
  late int endRateCalls;
  late int doubleTapCalls;
  late int twoFingerDoubleTapCalls;
  late int sessionStartCalls;
  late int sessionEndCalls;
  late List<int> rawPointerUps;
  late bool framingActive;
  late bool controlOpen;
  late _RecordingPresentationSession presentation;
  late AnnotationTimeline jumpTimeline;

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 100));
    feedback = GestureFeedbackController();
    scrubTarget = ValueNotifier(Duration.zero);
    brightness = FakeScreenBrightnessController(initialBrightness: 0.5);
    volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
    level = LevelControl(
      brightnessController: brightness,
      volumeController: volume,
    );
    container = ProviderContainer();
    jumpTimeline = AnnotationTimeline.wholeVideo(const Duration(seconds: 100));
    framingCalls = <String>[];
    writtenDirections = <ThreeFingerSwipeDirection>[];
    shownNotices = <NoticeId>[];
    beginRateCalls = 0;
    endRateCalls = 0;
    doubleTapCalls = 0;
    twoFingerDoubleTapCalls = 0;
    sessionStartCalls = 0;
    sessionEndCalls = 0;
    rawPointerUps = <int>[];
    framingActive = false;
    controlOpen = false;
    takeover = RecordingPlaybackTakeover(
      disableRecordingLoop: () {},
      restoreLearningSegmentLoop: () {},
      setRecordingMarker: (_) {},
      endScrubSession: () async {},
      interruptPendingDelayedPlay: () {},
      stopRecordingSession: () async {},
    );
    framing = FramingSessionHost(
      readViewport: () => const FramingViewport(
        size: Size(800, 600),
        landscape: false,
        sourceAspectRatio: 1.0,
      ),
      isActive: () => framingActive,
      readCommitted: () => const FramingState(),
      applySource: (_) => framingCalls.add('apply'),
      exitFraming: () => framingCalls.add('exit'),
    );
    editorEntry = EditorEntry(
      session: container.read(playerSessionProvider.notifier),
      readSession: () => container.read(playerSessionProvider),
      blocksWrite: () => false,
      takenOver: () => takeover.active,
      avSyncActive: () => false,
      requestCameraPermission: () async => true,
      readTimeline: () =>
          AnnotationTimeline.wholeVideo(const Duration(seconds: 100)),
      readVideoDuration: () => const Duration(seconds: 100),
      resetTimeline: (_) {},
      clearExclusiveSelections: () {},
      isMounted: () => true,
    );
    final metronome = MetronomeOverlayController();
    presentation = _RecordingPresentationSession(
      metronome: metronome,
      isControlOpen: () => controlOpen,
      metronomeVisible: () => true,
    );
  });

  tearDown(() {
    feedback.dispose();
    scrubTarget.dispose();
    container.dispose();
  });

  EngineSeek buildEngineSeek() => EngineSeek(
    engine: engine,
    takeoverOf: () => takeover,
    timeline: () => AnnotationTimeline.wholeVideo(const Duration(seconds: 100)),
    clearLoops: (_, _) {},
    interruptPendingDelayedPlay: () {},
    onScrubCommitted: (_) {},
    feedback: feedback,
    scrubTarget: scrubTarget,
    onPlayingEdge: (_) {},
    onPosition: () {},
    onCompleted: () async {},
    isMounted: () => true,
  );

  /// 画面矩形：默认铺满 800×600 视口——
  /// 圆心在屏幕原点，既有用例坐标语义不变。
  Rect pictureRect = Rect.fromLTWH(0, 0, 800, 600);

  /// 系统手势内缩：默认全零上报 → 四边取固定下限；置 null 模拟
  /// 「宿主未给出让路区」。
  SystemGestureYieldInsets? yieldSystemInsets =
      systemGestureYieldInsets(system: EdgeInsets.zero);

  GestureArbitration build({
    bool Function(Offset?)? onOverlayTap,
    bool Function(Offset?)? onOverlayDoubleTap,
  }) {
    presentation.recordSessionStart = () {
      sessionStartCalls++;
    };
    presentation.recordSessionEnd = () {
      sessionEndCalls++;
    };
    presentation.recordRawPointerUp = rawPointerUps.add;
    presentation.overlayTapResult = onOverlayTap ?? (_) => false;
    presentation.overlayDoubleTapResult =
        onOverlayDoubleTap ?? (_) => false;
    return GestureArbitration(
      input: GestureArbitrationInput(
        engineSeek: buildEngineSeek(),
        level: level,
        framing: framing,
        editorEntry: editorEntry,
        takeover: takeover,
        feedback: feedback,
        isFramingActive: () => framingActive,
        isControlOpen: () => controlOpen,
        isMounted: () => true,
        viewportSize: () => const Size(800, 600),
        pictureRect: () => pictureRect,
        yieldSystemInsets: () => yieldSystemInsets,
        readTimeline: () => jumpTimeline,
        beginTransientRate: () async => beginRateCalls++,
        endTransientRate: () async => endRateCalls++,
        onDoubleTap: () async => doubleTapCalls++,
        onTwoFingerDoubleTap: () => twoFingerDoubleTapCalls++,
        writeThreeFingerDirection: writtenDirections.add,
        showNotice: shownNotices.add,
        presentation: presentation,
      ),
    );
  }

  ScaleStartDetails start({int pointerCount = 1, Offset focal = Offset.zero}) =>
      ScaleStartDetails(
        focalPoint: focal,
        localFocalPoint: focal,
        pointerCount: pointerCount,
      );

  ScaleUpdateDetails update({
    required double dx,
    required double dy,
    int pointerCount = 1,
    double scale = 1.0,
    Offset? focal,
  }) => ScaleUpdateDetails(
    focalPoint: focal ?? const Offset(400, 300),
    localFocalPoint: focal ?? const Offset(400, 300),
    pointerCount: pointerCount,
    focalPointDelta: Offset(dx, dy),
    scale: scale,
  );

  group('轴锁与灵敏度', () {
    test('单指横向越阈锁轴：起拖动会话并按低灵敏度入队 seek', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 10));
      engine.seekCalls.clear();
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 11, milliseconds: 500),
      );
      expect(feedback.isScrubbing, isTrue);
    });

    test('双指横向：灵敏度为单指三倍', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 10));
      engine.seekCalls.clear();
      arb.onScaleStart(start(pointerCount: 2, focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0, pointerCount: 2));
      await pumpEventQueue();
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 14, milliseconds: 500),
      );
    });

    test('纵向占优不锁横轴：不进入拖动会话', () async {
      final arb = build();
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 5, dy: 60));
      expect(engine.seekCalls, isEmpty);
      expect(feedback.isScrubbing, isFalse);
    });

    test('右半屏纵向滑调系统音量、左半屏调亮度', () async {
      level.start();
      await pumpEventQueue();
      final arb = build();
      arb.onScaleStart(start(focal: const Offset(700, 300)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100));
      expect(feedback.levelKind, LevelAdjustKind.volume);
      expect(feedback.levelValue, closeTo(0.5 + 100 / 600, 1e-9));
      expect(brightness.setCalls, isEmpty);

      final arbLeft = build();
      arbLeft.onScaleStart(start(focal: const Offset(100, 300)));
      await arbLeft.onScaleUpdate(update(dx: 0, dy: -60));
      expect(feedback.levelKind, LevelAdjustKind.brightness);
      expect(feedback.levelValue, closeTo(0.5 + 60 / 600, 1e-9));
    });
  });

  group('突发指针锁定', () {
    test('burst 未结束（识别器重启 onEnd）不结束会话；全部抬起才收尾', () async {
      final arb = build();
      final down = PointerDownEvent(
        pointer: 1,
        position: const Offset(400, 300),
      );
      arb.onPointerDown(down);
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      expect(feedback.isScrubbing, isTrue);

      await arb.onScaleEnd(ScaleEndDetails());
      expect(feedback.isScrubbing, isTrue, reason: 'burst 仍有指针按下，不得收尾');

      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(400, 300)),
      );
      await pumpEventQueue();
      expect(feedback.isScrubbing, isFalse);
      expect(rawPointerUps, [1]);
    });

    test('同 burst 内识别器重启的第二次 onStart 不重开会话', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      final before = engine.seekCalls.length;
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      expect(sessionStartCalls, 1, reason: '重启不再触发会话起手钩子');
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      expect(engine.seekCalls.length, before + 1);
    });
  });

  group('取消区语义', () {
    test('焦点进入取消区松手：回退到定格快照并恢复播放', () async {
      final arb = build();
      await engine.play();
      await engine.seek(const Duration(seconds: 20));
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 21, milliseconds: 500),
      );

      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(10, 10)),
      );
      expect(feedback.cancelArmed, isTrue);
      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(10, 10)),
      );
      await pumpEventQueue();
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 20),
        reason: '回退到定格快照',
      );
      expect(engine.isPlaying, isTrue, reason: '恢复手势前播放态');
    });

    test('取消区外松手：正常落点、不取消', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 20));
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      expect(feedback.cancelArmed, isFalse);
      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(430, 300)),
      );
      await pumpEventQueue();
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 21, milliseconds: 500),
      );
    });

    test('原已暂停在取消区松开：保持暂停在暂停点快照、不额外 play', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 15));
      engine.callLog.clear();
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(10, 10)),
      );
      expect(feedback.cancelArmed, isTrue);
      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(10, 10)),
      );
      await pumpEventQueue();
      expect(engine.isPlaying, isFalse, reason: '原已暂停则取消后仍保持暂停');
      expect(engine.position, const Duration(seconds: 15));
      expect(engine.callLog.where((c) => c == 'play'), isEmpty);
    });

    test('双指在取消区松开：同样回退到暂停点快照并恢复播放', () async {
      final arb = build();
      await engine.play();
      await engine.seek(const Duration(seconds: 20));
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(300, 250)),
      );
      arb.onPointerDown(
        PointerDownEvent(pointer: 2, position: const Offset(340, 250)),
      );
      arb.onScaleStart(start(pointerCount: 2, focal: const Offset(320, 250)));
      await arb.onScaleUpdate(update(dx: 40, dy: 0, pointerCount: 2));
      await pumpEventQueue();
      expect(feedback.isScrubbing, isTrue);

      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, pointerCount: 2, focal: const Offset(46, 30)),
      );
      expect(feedback.cancelArmed, isTrue);
      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(46, 30)),
      );
      arb.onPointerUp(
        PointerUpEvent(pointer: 2, position: const Offset(46, 30)),
      );
      await pumpEventQueue();
      expect(engine.position, const Duration(seconds: 20));
      expect(engine.isPlaying, isTrue);
    });

    test('进入取消区后移出恢复原样：区外松手走正常落点', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 20));
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(20, 50)),
      );
      expect(feedback.cancelArmed, isTrue);
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(20, 140)),
      );
      expect(feedback.cancelArmed, isFalse, reason: '移出取消区恢复原样');
      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(20, 140)),
      );
      await pumpEventQueue();
      expect(engine.position, engine.seekCalls.last, reason: '不误触发回退');
      expect(engine.position, isNot(const Duration(seconds: 20)));
    });

    test('扇形判定：方形角区内但扇形外的角落不待取消', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 20));
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      // (86, 86)：两轴都在 88 内（旧方形角区语义会待取消），但
      // 86² + 86² > 88²，扇形外 → 不待取消。
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(86, 86)),
      );
      expect(feedback.cancelArmed, isFalse, reason: '扇外角落不待取消');
      // 扇内参照：(80, 20) 在扇内（86² + 20² 超界，80² + 20² 不超）。
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(80, 20)),
      );
      expect(feedback.cancelArmed, isTrue);
    });

    test('半径边界等号档：恰好在弧上待取消', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 20));
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      await arb.onScaleUpdate(update(dx: 0, dy: 0, focal: const Offset(88, 0)));
      expect(feedback.cancelArmed, isTrue, reason: 'dx² + dy² = r² 等号档待取消');
    });

    test('画面外（圆心左侧）不待取消：dx 为负', () async {
      pictureRect = const Rect.fromLTWH(100, 40, 800, 600);
      final arb = build();
      await engine.seek(const Duration(seconds: 20));
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(10, 10)),
      );
      expect(feedback.cancelArmed, isFalse, reason: '画面左外的屏幕角落不待取消');
    });

    test('圆心跟随画面矩形：矩形左上角偏移后按画面坐标判定', () async {
      pictureRect = const Rect.fromLTWH(100, 40, 300, 200);
      final arb = build();
      await engine.seek(const Duration(seconds: 20));
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      // 画面坐标 (40, 30)：40² + 30² = 2500 ≤ 88² → 待取消。
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(140, 70)),
      );
      expect(feedback.cancelArmed, isTrue, reason: '圆心落在画面左上角');
      // 同样屏幕坐标落在屏幕角但离画面圆心远 → 不待取消。
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(10, 10)),
      );
      expect(feedback.cancelArmed, isFalse);
      // 半径随画面收缩：画面 40×30 → r = 30，画面坐标 (40, 10) 在扇外。
      pictureRect = const Rect.fromLTWH(0, 0, 40, 30);
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(40, 10)),
      );
      expect(feedback.cancelArmed, isFalse, reason: '扁画面半径收缩');
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, focal: const Offset(20, 20)),
      );
      expect(feedback.cancelArmed, isTrue, reason: '20² + 20² ≤ 30²');
    });
  });

  group('三指跳转', () {
    test('横向累计过阈一次性左跳最近分段线/首边界并显示提示', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 30));
      engine.seekCalls.clear();
      arb.onScaleStart(start(pointerCount: 3, focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: -50, dy: 0, pointerCount: 3));
      await pumpEventQueue();
      expect(engine.seekCalls, [Duration.zero]);
      expect(writtenDirections, [
        ThreeFingerSwipeDirection.left,
      ], reason: '方向写入注入点');
      expect(shownNotices, [
        NoticeId.threeFingerToast,
      ], reason: '触发面只报身份');

      await arb.onScaleUpdate(update(dx: 100, dy: 0, pointerCount: 3));
      await pumpEventQueue();
      expect(engine.seekCalls.length, 1, reason: '每会话只跳一次');
    });

    test('录制期三指不跳转', () async {
      final arb = build();
      takeover.engage(suppressLoop: false);
      arb.onScaleStart(start(pointerCount: 3, focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 50, dy: 0, pointerCount: 3));
      expect(engine.seekCalls, isEmpty);
      expect(shownNotices, isEmpty);
    });

    test('未标记分段线不成为跳转目标：跳到标记线或回退首/尾', () async {
      jumpTimeline = AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 100),
        segmentLines: const [
          SegmentLine(position: Duration(seconds: 10), flagged: true),
          SegmentLine(position: Duration(seconds: 20)),
          SegmentLine(position: Duration(seconds: 40), flagged: true),
        ],
      );
      final arb = build();

      // 右滑：右侧最近的线是未标记的 20s → 跳过，落到标记线 40s。
      await engine.seek(const Duration(seconds: 15));
      engine.seekCalls.clear();
      arb.onScaleStart(start(pointerCount: 3));
      await arb.onScaleUpdate(update(dx: 50, dy: 0, pointerCount: 3));
      await pumpEventQueue();
      expect(engine.seekCalls, [const Duration(seconds: 40)]);
      await arb.onScaleEnd(ScaleEndDetails());

      // 左滑：左侧最近的线是未标记的 20s → 跳过，落到标记线 10s。
      await engine.seek(const Duration(seconds: 15));
      engine.seekCalls.clear();
      arb.onScaleStart(start(pointerCount: 3));
      await arb.onScaleUpdate(update(dx: -50, dy: 0, pointerCount: 3));
      await pumpEventQueue();
      expect(engine.seekCalls, [const Duration(seconds: 10)]);
      await arb.onScaleEnd(ScaleEndDetails());

      // 左滑方向无标记线（标记线 20s 在当前位置右侧）：回退首边界 0。
      jumpTimeline = AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 100),
        segmentLines: const [
          SegmentLine(position: Duration(seconds: 20), flagged: true),
        ],
      );
      await engine.seek(const Duration(seconds: 5));
      engine.seekCalls.clear();
      arb.onScaleStart(start(pointerCount: 3));
      await arb.onScaleUpdate(update(dx: -50, dy: 0, pointerCount: 3));
      await pumpEventQueue();
      expect(engine.seekCalls, [Duration.zero]);
    });
  });

  group('起始手指数读面', () {
    test('会话开始把起始手指数写进反馈控制器；既有手势行为不变', () async {
      final arb = build();
      arb.onScaleStart(start(pointerCount: 2));
      expect(feedback.startPointerCount, 2);

      // 下一会话重写。
      await arb.onScaleEnd(ScaleEndDetails());
      arb.onScaleStart(start(pointerCount: 1, focal: const Offset(400, 300)));
      expect(feedback.startPointerCount, 1);
    });
  });

  group('录制期播放类手势整体停用', () {
    test('接管期横向拖动不进入拖动会话', () async {
      final arb = build();
      takeover.engage(suppressLoop: true);
      arb.onScaleStart(start());
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      expect(engine.seekCalls, isEmpty);
      expect(feedback.isScrubbing, isFalse);
    });

    test('接管期纵向音量照常', () async {
      final arb = build();
      takeover.engage(suppressLoop: true);
      arb.onScaleStart(start(focal: const Offset(700, 300)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100));
      expect(feedback.levelKind, LevelAdjustKind.volume);
    });
  });

  group('取景手势分支', () {
    test('取景态整场交给取景域：不起播放会话、不 seek', () async {
      framingActive = true;
      final arb = build();
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      expect(framingCalls, isEmpty, reason: '起手只取基准，不写取值');
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      expect(engine.seekCalls, isEmpty);
      await arb.onScaleEnd(ScaleEndDetails());
      expect(sessionStartCalls, 0);
      expect(sessionEndCalls, 1);
    });

    test('取景态单击交给取景域（点画面外退出），不唤出编辑器入口', () {
      framingActive = true;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(10, 10)),
      );
      arb.doubleTapRecognizer.onSingleTap!.call();
      expect(framingCalls, contains('exit'));
      expect(container.read(playerSessionProvider).pendingEntry, isNull);
    });
  });

  group('取景态拖动建框与让路', () {
    test('起手在画面内且不在让路区：单指拖动照常写取景取值', () async {
      framingActive = true;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 100)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 100)));
      await arb.onScaleUpdate(
        update(dx: 30, dy: 20, focal: const Offset(430, 120)),
      );
      expect(framingCalls, ['apply']);
    });

    test('顶区起手单指拖动：取景吞帧但不写取值，不回落播放分支', () async {
      framingActive = true;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 10)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(
        update(dx: 30, dy: 20, focal: const Offset(430, 30)),
      );
      expect(framingCalls, isEmpty, reason: '让路期间取值分毫不动');
      expect(engine.seekCalls, isEmpty);
      expect(brightness.setCalls, isEmpty);
      expect(volume.setCalls, isEmpty);
    });

    test('黑边起手：拖动不写取值、不回落播放分支', () async {
      framingActive = true;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 350)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 350)));
      await arb.onScaleUpdate(
        update(dx: 30, dy: 20, focal: const Offset(430, 370)),
      );
      expect(framingCalls, isEmpty, reason: '黑边起手不动作');
      expect(engine.seekCalls, isEmpty);
    });

    test('多指：一律不写取值、不产生缩放或旋转等新语义', () async {
      framingActive = true;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 100)),
      );
      arb.onPointerDown(
        PointerDownEvent(pointer: 2, position: const Offset(440, 100)),
      );
      arb.onScaleStart(start(pointerCount: 2, focal: const Offset(420, 100)));
      await arb.onScaleUpdate(
        update(dx: 0, dy: 0, pointerCount: 2, scale: 1.5,
            focal: const Offset(420, 100)),
      );
      expect(framingCalls, isEmpty);
    });

    test('取景态单击退出不受让路判定影响', () {
      framingActive = true;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(10, 10)),
      );
      arb.doubleTapRecognizer.onSingleTap!.call();
      expect(framingCalls, ['exit']);
      expect(container.read(playerSessionProvider).pendingEntry, isNull);
    });
  });

  group('长按二倍速', () {
    test('长按阈值到进入临时倍率、松开恢复', () async {
      final arb = build();
      arb.longPressRecognizer.onLongPressStart!(LongPressStartDetails());
      expect(beginRateCalls, 1);
      arb.longPressRecognizer.onLongPressEnd!(LongPressEndDetails());
      expect(endRateCalls, 1);
    });

    test('取景态长按不触发临时倍率', () async {
      framingActive = true;
      final arb = build();
      arb.longPressRecognizer.onLongPressStart!(LongPressStartDetails());
      expect(beginRateCalls, 0);
    });
  });

  group('单击唤出编辑器入口', () {
    test('孤立单击：浮层未接手即请求进入编辑面', () {
      final arb = build();
      arb.doubleTapRecognizer.onSingleTap!.call();
      expect(container.read(playerSessionProvider).pendingEntry, isNotNull);
    });

    test('控制层已展开不重复请求', () {
      controlOpen = true;
      final arb = build();
      arb.doubleTapRecognizer.onSingleTap!.call();
      expect(container.read(playerSessionProvider).pendingEntry, isNull);
    });

    test('浮层仲裁接手时不唤出编辑器入口', () {
      final arb = build(onOverlayTap: (_) => true);
      arb.doubleTapRecognizer.onSingleTap!.call();
      expect(container.read(playerSessionProvider).pendingEntry, isNull);
    });
  });

  group('双击类识别器', () {
    test('单指双击与双指双击各自转发', () async {
      final arb = build();
      arb.doubleTapRecognizer.onDoubleTap!.call();
      arb.doubleTapRecognizer.onTwoFingerDoubleTap!.call();
      expect(doubleTapCalls, 1);
      expect(twoFingerDoubleTapCalls, 1);
    });

    test('取景调节态：单指双击不转发', () {
      framingActive = true;
      final arb = build();
      arb.doubleTapRecognizer.onDoubleTap!.call();
      expect(doubleTapCalls, 0);
    });

    test('命中选中浮层：单指双击不进播放语义（不转发）', () {
      final arb = build(onOverlayDoubleTap: (_) => true);
      arb.doubleTapRecognizer.onDoubleTap!.call();
      expect(doubleTapCalls, 0);
    });
  });

  group('系统指针取消', () {
    test('结束滞留的拖动会话并结束临时倍率', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      expect(feedback.isScrubbing, isTrue);
      arb.onSystemPointerCancel();
      await pumpEventQueue();
      expect(feedback.isScrubbing, isFalse);
      expect(endRateCalls, 1);
    });
  });

  group('被系统抢走即回滚', () {
    PointerDownEvent downAt(Offset position, {int pointer = 1}) =>
        PointerDownEvent(pointer: pointer, position: position);

    /// 新建仲裁域并驱动一路竖滑调节会话（亮度左半屏、音量右半屏；
    /// [dy] 负为增）。
    Future<GestureArbitration> levelGestureAt(Offset at, {double dy = -100}) async {
      level.start();
      await pumpEventQueue();
      final arb = build();
      arb.onPointerDown(downAt(at));
      arb.onScaleStart(start(focal: at));
      await arb.onScaleUpdate(update(dx: 0, dy: dy, focal: at));
      return arb;
    }

    test('画面层指针取消：音量写回起手值、浮层收起、无提示', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();
      expect(volume.setCalls, isNotEmpty);

      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();

      expect(volume.setCalls.last, closeTo(0.5, 1e-9), reason: '写回起手音量');
      expect(level.volume, closeTo(0.5, 1e-9));
      expect(feedback.isLevelAdjusting, isFalse, reason: '反馈浮层收起');
      expect(shownNotices, isEmpty, reason: '回滚全程静默');
    });

    test('画面层指针取消：亮度写回起手值', () async {
      final arb = await levelGestureAt(const Offset(100, 300), dy: -60);
      await pumpEventQueue();
      expect(brightness.setCalls, isNotEmpty);

      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();

      expect(brightness.setCalls.last, closeTo(0.5, 1e-9));
      expect(feedback.isLevelAdjusting, isFalse);
    });

    test('画面层指针取消：进度退回定格基准、播放态按手势前恢复', () async {
      final arb = build();
      await engine.play();
      await engine.seek(const Duration(seconds: 20));
      engine.seekCalls.clear();
      arb.onPointerDown(downAt(const Offset(400, 300)));
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();
      expect(engine.seekCalls.last,
          const Duration(seconds: 21, milliseconds: 500));

      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();

      expect(engine.seekCalls.last, const Duration(seconds: 20),
          reason: '退回起手前位置');
      expect(engine.isPlaying, isTrue, reason: '原在播续播');
      expect(feedback.isScrubbing, isFalse);
    });

    test('原已暂停被取消：保持暂停、无 play 调用', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 15));
      engine.seekCalls.clear();
      arb.onPointerDown(downAt(const Offset(400, 300)));
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0));
      await pumpEventQueue();

      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();

      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 15));
      expect(engine.callLog.where((c) => c == 'play'), isEmpty);
    });

    test('页面层兜底回调先于画面层取消：置位顺序无关、结果幂等', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();

      arb.onSystemPointerCancel();
      await pumpEventQueue();
      expect(volume.setCalls.last, closeTo(0.5, 1e-9));
      expect(feedback.isLevelAdjusting, isFalse);
      final calls = List<double>.of(volume.setCalls);

      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();
      expect(volume.setCalls, calls, reason: '已收尾再取消不重复写');
    });

    test('页面层兜底回调单独触发：滞留会话按取消清理', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();

      arb.onSystemPointerCancel();
      await pumpEventQueue();

      expect(volume.setCalls.last, closeTo(0.5, 1e-9));
      expect(feedback.isLevelAdjusting, isFalse);
    });

    test('兜底是唯一取消信号：burst 簿记随之清理，下一手势不受滞留影响', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();
      arb.onSystemPointerCancel();
      await pumpEventQueue();
      final rollbackWrites = volume.setCalls.length;

      // 兜底之后再无画面层指针事件：burst 必须已被兜底收尾。
      expect(sessionEndCalls, 1, reason: '滞留会话随兜底收尾');

      // 下一手势从顶区起手：让路判定必须用新 burst 的首指位置。
      arb.onPointerDown(downAt(const Offset(400, 10)));
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(400, 10)));
      await pumpEventQueue();

      expect(volume.setCalls.length, rollbackWrites,
          reason: '顶区起手让路：不产生新的音量调节写');
      expect(feedback.isLevelAdjusting, isFalse);
    });

    test('收尾后重复取消与重复指针取消均幂等', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();
      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();
      final calls = List<double>.of(volume.setCalls);

      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      arb.onSystemPointerCancel();
      arb.onSystemPointerCancel();
      await pumpEventQueue();

      expect(volume.setCalls, calls);
    });

    test('正常松手不回滚：新值保留', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();

      arb.onPointerUp(
        PointerUpEvent(pointer: 1, position: const Offset(700, 200)),
      );
      await pumpEventQueue();

      expect(volume.setCalls, [closeTo(0.5 + 100 / 600, 1e-9)]);
      expect(level.volume, closeTo(0.5 + 100 / 600, 1e-9));
    });

    test('被取消的会话之后新手势从写回后的基线起算', () async {
      final arb = await levelGestureAt(const Offset(700, 300));
      await pumpEventQueue();
      arb.onPointerCancel(PointerCancelEvent(pointer: 1));
      await pumpEventQueue();
      final rollbackWrites = volume.setCalls.length;

      arb.onScaleStart(start(focal: const Offset(700, 300)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100));
      await pumpEventQueue();

      expect(volume.setCalls.length, rollbackWrites + 1);
      expect(volume.setCalls.last, closeTo(0.5 + 100 / 600, 1e-9),
          reason: '从回滚后的 0.5 起算，而非滞留的旧值');
    });
  });

  group('会话起手钩子', () {
    test('非取景起手转发钩子一次', () {
      final arb = build();
      arb.onScaleStart(start());
      expect(sessionStartCalls, 1);
    });
  });

  group('系统手势让路', () {
    /// 顶区起手（y=10 < 48 下限）。
    test('顶区起手竖滑 → 亮度与音量写面零调用、不出现反馈相位', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 10)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(400, 10)));
      expect(brightness.setCalls, isEmpty);
      expect(volume.setCalls, isEmpty);
      expect(feedback.isLevelAdjusting, isFalse);
    });

    test('底区起手竖滑 → 同样零调用', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 595)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 595)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(400, 595)));
      expect(brightness.setCalls, isEmpty);
      expect(volume.setCalls, isEmpty);
      expect(feedback.isLevelAdjusting, isFalse, reason: '不出现亮度/音量反馈滑条');
    });

    test('顶区起手横滑 → 进度拖动照常推进', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 10));
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 10)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0, focal: const Offset(400, 10)));
      await pumpEventQueue();
      expect(engine.seekCalls.last, const Duration(seconds: 11, milliseconds: 500));
      expect(feedback.isScrubbing, isTrue);
    });

    test('左区起手竖滑 → 亮度照常', () async {
      level.start();
      await pumpEventQueue();
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(8, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(8, 300)));
      await arb.onScaleUpdate(update(dx: 0, dy: -60, focal: const Offset(8, 300)));
      expect(feedback.levelKind, LevelAdjustKind.brightness);
      expect(brightness.setCalls, isNotEmpty);
    });

    test('左区起手横滑 → 进度零调用', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(8, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(8, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0, focal: const Offset(8, 300)));
      await pumpEventQueue();
      expect(engine.seekCalls, isEmpty);
      expect(feedback.isScrubbing, isFalse);
    });

    test('右区起手横滑 → 进度零调用', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(795, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(795, 300)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0, focal: const Offset(795, 300)));
      await pumpEventQueue();
      expect(engine.seekCalls, isEmpty);
    });

    test('左区起手三指横滑 → 不触发跳转', () async {
      final arb = build();
      await engine.seek(const Duration(seconds: 30));
      engine.seekCalls.clear();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(8, 300)),
      );
      arb.onScaleStart(
        start(pointerCount: 3, focal: const Offset(8, 300)),
      );
      await arb.onScaleUpdate(update(dx: -50, dy: 0, pointerCount: 3));
      await pumpEventQueue();
      expect(engine.seekCalls, isEmpty);
      expect(writtenDirections, isEmpty);
      expect(shownNotices, isEmpty);
    });

    test('锁到让路轴的会话整场无动作、不退化为另一轴', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 10)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 0, dy: 100, focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 60, dy: 0, focal: const Offset(400, 10)));
      await pumpEventQueue();
      expect(engine.seekCalls, isEmpty);
      expect(brightness.setCalls, isEmpty);
      expect(volume.setCalls, isEmpty);
    });

    test('判定点是本 burst 首指按下位置：按下在中心、识别器焦点在顶区不禁', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(400, 10)));
      expect(feedback.isLevelAdjusting, isTrue);
    });

    test('拖动中途移进让路区不影响本次判定', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 300)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 300)));
      // 纵向先锁轴（亮度照常），逐帧移进顶区后仍照常。
      await arb.onScaleUpdate(update(dx: 0, dy: -60, focal: const Offset(400, 20)));
      expect(feedback.isLevelAdjusting, isTrue);
    });

    test('起手点缺失（无原始指针按下）时不让路', () async {
      final arb = build();
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(400, 10)));
      expect(feedback.isLevelAdjusting, isTrue);
    });

    test('顶区与侧区重叠起手 → 两轴同时被禁', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(8, 20)),
      );
      arb.onScaleStart(start(focal: const Offset(8, 20)));
      await arb.onScaleUpdate(update(dx: 30, dy: 0, focal: const Offset(8, 20)));
      await pumpEventQueue();
      expect(engine.seekCalls, isEmpty);
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(8, 20)));
      expect(feedback.isLevelAdjusting, isFalse);
    });

    test('宿主未给出让路区时一律不让路', () async {
      yieldSystemInsets = null;
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 10)),
      );
      arb.onScaleStart(start(focal: const Offset(400, 10)));
      await arb.onScaleUpdate(update(dx: 0, dy: -100, focal: const Offset(400, 10)));
      expect(feedback.isLevelAdjusting, isTrue);
    });

    test('让路区内的单击、双击、双指双击、长按全部照常触发', () async {
      final arb = build();
      arb.onPointerDown(
        PointerDownEvent(pointer: 1, position: const Offset(400, 10)),
      );
      arb.doubleTapRecognizer.onSingleTap!.call();
      expect(container.read(playerSessionProvider).pendingEntry, isNotNull);
      arb.doubleTapRecognizer.onDoubleTap!.call();
      arb.doubleTapRecognizer.onTwoFingerDoubleTap!.call();
      expect(doubleTapCalls, 1);
      expect(twoFingerDoubleTapCalls, 1);
      arb.longPressRecognizer.onLongPressStart!(LongPressStartDetails());
      expect(beginRateCalls, 1);
    });
  });
}

/// 记录演出层会话钩子的测试替身：手势域应在对应时机调用这些钩子，断言读的是
/// 同一个演出层会话面。
class _RecordingPresentationSession extends PresentationSession {
  _RecordingPresentationSession({
    required super.metronome,
    required super.isControlOpen,
    required super.metronomeVisible,
  });

  void Function() recordSessionStart = () {};
  void Function() recordSessionEnd = () {};
  void Function(int pointer) recordRawPointerUp = (_) {};
  bool Function(Offset? down) overlayTapResult = (_) => false;
  bool Function(Offset? down) overlayDoubleTapResult = (_) => false;

  @override
  void onGestureSessionStarted(ScaleStartDetails details) =>
      recordSessionStart();

  @override
  void onGestureSessionEnded() => recordSessionEnd();

  @override
  void onRawPointerUp(int pointer) => recordRawPointerUp(pointer);

  @override
  bool onOverlayTap(Offset? down) => overlayTapResult(down);

  @override
  bool consumesOverlayDoubleTap(Offset? down) => overlayDoubleTapResult(down);
}
