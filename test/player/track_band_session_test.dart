/// 轨道带会话域模块级套件，覆盖唯一求值点的三处收口：窗口跟随只在位置
/// tick 一处、捏合锚点取预览线显示值、按下中点簿记只有一份。
///
/// 行为接缝只开在 [TrackBandSession] 自己的公开接口上：不 pump widget、不注
/// 容器，用假引擎与记录器直接驱动。断言的都是会话域交出的外部可观察事实
/// ——窗口读写的结果、预览线显示值与拖动标记的取值、微调 scrub 的起手定格与
/// 恢复落点、跨面捏合的锚点与让位、两套捏合带宽口径各按自己的宽度。
library;

import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/core/playback/playback_engine.dart';
import 'package:dance_learning_app/player/track_band_session.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 时长可变的内核（陈旧窗口归一路径：时长事后刷新/换片使旧窗口不可用）。
class _MutableDurationEngine extends FakePlaybackEngine {
  _MutableDurationEngine({required super.duration});

  Duration? _durationOverride;

  void replaceDuration(Duration? value) => _durationOverride = value;

  @override
  Duration? get duration => _durationOverride ?? super.duration;
}

/// 总时长未知（尚未装载完成）的内核。
class _NullDurationEngine extends FakePlaybackEngine {
  _NullDurationEngine() : super(duration: const Duration(minutes: 1));

  @override
  Duration? get duration => null;
}

/// 窗口几何判等（[TimelineWindow] 是实例语义的值对象：按三个字段逐一断言，
/// 与生产代码的 `identical` 判定同口径）。
void expectWindow(
  TimelineWindow? actual, {
  required Duration start,
  required Duration end,
  Duration? total,
}) {
  expect(actual, isNotNull);
  expect(actual!.start, start);
  expect(actual.end, end);
  if (total != null) expect(actual.total, total);
}

void main() {
  const total = Duration(minutes: 3);

  late FakePlaybackEngine engine;
  late _MutableDurationEngine mutableEngine;
  late TrackBandSession session;

  TrackBandSession build({
    PlaybackEngine? withEngine,
    AnnotationTimeline? timeline,
    ValueChanged<Duration>? onScrubCommitted,
  }) => TrackBandSession(
    engine: withEngine ?? engine,
    timeline: () => timeline ?? AnnotationTimeline.wholeVideo(total),
    clearLoops: (_, _) {},
    layerWidth: () => 800,
    onScrubCommitted: onScrubCommitted,
  );

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    mutableEngine = _MutableDurationEngine(duration: total);
    session = build();
  });

  group('窗口读写面', () {
    test('初始全宽（null）；写入后可读、监听者被通知一次', () {
      expect(session.window, isNull);
      var notifications = 0;
      session.windowChanges.addListener(() => notifications++);
      final window = TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 90),
      );
      session.updateWindow(window);
      expect(session.window, window);
      expect(notifications, 1);
    });

    test('几何等值写入不通知（高频拖动路径不触发多余重建）', () {
      final window = TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 90),
      );
      session.updateWindow(window);
      var notifications = 0;
      session.windowChanges.addListener(() => notifications++);
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      expect(notifications, 0);
      expect(session.window, window);
    });

    test('seek 提交口只写显示值：落点越出可视窗口也不动窗口', () {
      final zoom = TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 90),
      );
      session.updateWindow(zoom);
      final landed = session.submit(const Duration(seconds: 30));
      expect(landed, const Duration(seconds: 30));
      expect(session.previewLine.value, const Duration(seconds: 30));
      expect(
        identical(session.window, zoom),
        isTrue,
        reason: 'seek 提交口退成纯预览线显示值写入——跟随只在位置 tick 一处',
      );
    });

    test('位置 tick：落点越窗 → 窗口跟随平移保持落点可见', () {
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      session.submit(const Duration(seconds: 30));
      session.followPosition(const Duration(seconds: 30));
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 22500),
        end: const Duration(milliseconds: 52500),
        total: total,
      );
    });

    test('位置 tick：落点在窗内 → 窗口不动', () {
      final zoom = TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 90),
      );
      session.updateWindow(zoom);
      session.followPosition(const Duration(seconds: 75));
      expect(
        identical(session.window, zoom),
        isTrue,
        reason: '落点在可视窗口内 → 跟随为 no-op（预览线拖动路径依赖此事实）',
      );
    });

    test('位置 tick：陈旧窗口归一（时长刷新后旧窗口不可用 → 回全宽）', () {
      final stale = build(withEngine: mutableEngine);
      stale.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      // 换片/时长刷新：旧窗口与总时长不匹配（不可用）。
      mutableEngine.replaceDuration(const Duration(minutes: 2));
      stale.followPosition(const Duration(seconds: 30));
      expectWindow(
        stale.window,
        start: Duration.zero,
        end: const Duration(minutes: 2),
        total: const Duration(minutes: 2),
      );
    });

    test('位置 tick：全宽（未缩放）无窗口可归一与跟随', () {
      session.followPosition(const Duration(seconds: 30));
      expect(session.window, isNull);
    });
  });

  group('落半拍线后收拢视野', () {
    test('collapseAround：窗口收拢到锚点附近（可视宽 = span），与收拢前状态无关', () {
      // 已在全宽（window == null）时收拢同样生效。
      session.collapseAround(
        const Duration(minutes: 1),
        span: const Duration(seconds: 8),
      );
      expectWindow(
        session.window,
        start: const Duration(seconds: 56),
        end: const Duration(seconds: 64),
        total: total,
      );

      // 已在放大态时收拢同样生效（行为一致，不依赖当前缩放程度）。
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 100),
          end: const Duration(seconds: 110),
        ),
      );
      session.collapseAround(
        const Duration(seconds: 30),
        span: const Duration(seconds: 8),
      );
      expectWindow(
        session.window,
        start: const Duration(seconds: 26),
        end: const Duration(seconds: 34),
        total: total,
      );
    });

    test('收拢后仍可继续缩放与平移（窗口保持可写）', () {
      session.collapseAround(
        const Duration(minutes: 1),
        span: const Duration(seconds: 8),
      );
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        ),
      );
      expectWindow(
        session.window,
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 20),
        total: total,
      );
    });

    test('总时长未知：不动作（窗口无从谈起）', () {
      final stale = build(withEngine: _NullDurationEngine());
      stale.collapseAround(Duration.zero, span: const Duration(seconds: 8));
      expect(stale.window, isNull);
    });
  });

  group('预览线显示值与拖动进行中标记', () {
    test('初始值：显示位零、拖动标记关', () {
      expect(session.previewLine.value, Duration.zero);
      expect(session.dragActive.value, isFalse);
    });

    test('编辑态落点写显示位（与入队目标同源）', () {
      final landed = session.submit(const Duration(seconds: 42));
      expect(landed, const Duration(seconds: 42));
      expect(session.previewLine.value, const Duration(seconds: 42));
      expect(engine.seekCalls, [const Duration(seconds: 42)]);
    });

    test('落点越界钳到 [0, total] 后写显示位', () {
      session.submit(const Duration(minutes: 5));
      expect(session.previewLine.value, total);
    });

    test('拖线实时预览只入队：显示位不随动', () async {
      session.submit(const Duration(seconds: 42));
      final landed = session.submitPicturePreview(const Duration(seconds: 10));
      expect(landed, const Duration(seconds: 10));
      expect(
        session.previewLine.value,
        const Duration(seconds: 42),
        reason: '拖线预览帧不写预览线显示值',
      );
      // 入队照常（串行队列 latest-wins，节流窗口过后发出）。
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(engine.seekCalls.last, const Duration(seconds: 10));
    });

    test('微调帧点亮拖动标记，收尾熄灭', () async {
      await engine.seek(const Duration(seconds: 30));
      await session.fineScrubFrame(0);
      expect(session.dragActive.value, isTrue);
      expect(session.fineScrubbing, isTrue);
      await session.endFineScrub();
      expect(session.dragActive.value, isFalse);
      expect(session.fineScrubbing, isFalse);
    });

    test('时长未知时微调静默不起会话（拖动标记不点亮）', () async {
      final noDurationSession = TrackBandSession(
        engine: _DurationlessEngine(),
        timeline: () => AnnotationTimeline.wholeVideo(Duration.zero),
        clearLoops: (_, _) {},
        layerWidth: () => 800,
      );
      await noDurationSession.fineScrubFrame(10);
      expect(noDurationSession.fineScrubbing, isFalse);
      expect(noDurationSession.dragActive.value, isFalse);
      await noDurationSession.endFineScrub();
      expect(noDurationSession.fineScrubbing, isFalse);
    });
  });

  group('编辑态微调 scrub', () {
    test('在播起手：先暂停定格，基准 = 定格点快照，帧目标 = 基准 + 累计位移', () async {
      await engine.seek(const Duration(seconds: 30));
      await engine.play();
      engine.callLog.clear();
      engine.seekCalls.clear();

      await session.fineScrubFrame(0);
      expect(engine.callLog.first, 'pause', reason: '起手先暂停定格（pause 先于任何 seek）');
      expect(engine.seekCalls, [
        const Duration(seconds: 30),
      ], reason: '基准 = 定格点快照（零位移帧也照常重提交）');

      await session.fineScrubFrame(20); // 20px × 50ms/px = 1000ms
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(engine.seekCalls.last, const Duration(seconds: 31));
      expect(session.previewLine.value, const Duration(seconds: 31));

      await session.fineScrubFrame(20); // 累计位移 40px → +2000ms
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(engine.seekCalls.last, const Duration(seconds: 32));
    });

    test('松手按手势前播放态续播，落点回报一次', () async {
      final commits = <Duration>[];
      final committed = build(onScrubCommitted: commits.add);
      await engine.seek(const Duration(seconds: 30));
      await engine.play();
      await committed.fineScrubFrame(0);
      await committed.fineScrubFrame(20);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      engine.callLog.clear();
      await committed.endFineScrub();
      expect(engine.callLog, ['play'], reason: '原在播且落点在区间内 → 续播');
      expect(commits, [const Duration(seconds: 31)]);
    });

    test('越出有效区间为暂停查看态（不续播）', () async {
      final restricted = build(
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 40),
          rangeEnd: const Duration(seconds: 60),
        ),
      );
      await engine.seek(const Duration(seconds: 30));
      await engine.play();
      await restricted.fineScrubFrame(0);
      await restricted.fineScrubFrame(20); // 落点 31s，在生效区间 [40s,60s] 外
      await Future<void>.delayed(const Duration(milliseconds: 40));
      engine.callLog.clear();
      await restricted.endFineScrub();
      expect(engine.callLog, isEmpty, reason: '区间外为暂停查看态');
    });

    test('原暂停起手：松手不续播', () async {
      await engine.seek(const Duration(seconds: 30));
      await session.fineScrubFrame(0);
      await session.fineScrubFrame(20);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      engine.callLog.clear();
      await session.endFineScrub();
      expect(engine.callLog, isEmpty);
    });

    test('未起会话时收尾为 no-op（幂等）', () async {
      await session.endFineScrub();
      expect(engine.callLog, isEmpty);
    });
  });

  group('跨面捏合会话', () {
    test('让位判定：活跃 ≥2 指且至少一指在带内；本 burst 证据落闩', () {
      session.trackBandPointerDown(1, const Offset(100, 100));
      expect(session.mixedActive, isFalse, reason: '单指不激活');
      expect(session.burstEverMixed, isFalse);
      session.blankPointerDown(2, const Offset(100, 300));
      expect(session.mixedActive, isTrue, reason: '一指带内一指空白即混区激活');
      expect(session.burstEverMixed, isTrue);
      session.blankPointerUp(2);
      expect(
        session.burstEverMixed,
        isTrue,
        reason: 'burst 证据保留到下一次 burst 首指（识别器重启的少指会话仍读）',
      );
      session.trackBandPointerUp(1);
      session.trackBandPointerDown(3, const Offset(100, 100));
      expect(session.burstEverMixed, isFalse, reason: '新 burst 起复位证据');
    });

    test('两指同落空白面不激活（该面捏合归面内 scale 路径）', () {
      session.blankPointerDown(1, const Offset(100, 300));
      session.blankPointerDown(2, const Offset(200, 300));
      expect(session.mixedActive, isFalse);
      expect(session.burstEverMixed, isFalse);
    });

    test('混区捏合：锚点取预览线显示值（不是引擎播放位置、也不是手指焦点）', () async {
      // 预览线显示值 = 65s，而引擎播放位置在 200s、双指中点 x=400 对应窗口
      // 60..90s 的中点 75s——三者不同，锚点取值由此可判。
      await engine.seek(const Duration(seconds: 200));
      session.setPreviewLine(const Duration(seconds: 65));
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      session.trackBandPointerDown(1, const Offset(300, 100));
      session.blankPointerDown(2, const Offset(500, 100));
      // 对称张合 2×（跨度 200 → 400，焦点 x 不动 → 无平移）：以 65s 为锚 →
      // 可视 15s、65s 在 [60s,90s] 中的相对位置 1/6 保持 → [62.5s, 77.5s]。
      session.trackBandPointerMove(1, const Offset(200, 100));
      session.blankPointerMove(2, const Offset(600, 100));
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 62500),
        end: const Duration(milliseconds: 77500),
        total: total,
      );
    });

    test('预览线不在窗内时锚点退回手指焦点时间', () async {
      session.setPreviewLine(const Duration(seconds: 200));
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      session.trackBandPointerDown(1, const Offset(300, 100));
      session.blankPointerDown(2, const Offset(500, 100));
      // 焦点不动、张合 2×：锚点退回手指焦点时间 75s（窗口中点）→
      // 窗口 [67.5s, 82.5s]。
      session.trackBandPointerMove(1, const Offset(200, 100));
      session.blankPointerMove(2, const Offset(600, 100));
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 67500),
        end: const Duration(milliseconds: 82500),
        total: total,
      );
    });
  });

  group('面内捏合的锚点与两套带宽口径', () {
    // 起手入参统一走 [TrackBandSession.beginPinch] 的按下中点求值：
    // downXs = 按下瞬间各指针的面内局部 x（≥2 个取均值），fallbackFocalX =
    // 按下点快照不足两个时的退回值（scale 会话起手焦点 x）。
    test('带内口径：换算带宽 = 带内容区宽（片头让位）', () {
      // 窗口贴零点时片头让位 40px → 内容区宽 760px（窗口平移后
      // 让位随片头滑出收回，故口径差只在贴零点时可见）。
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: Duration.zero,
          end: const Duration(seconds: 30),
        ),
      );
      final base = session.window!;
      session.beginPinch(
        surface: TrackPinchSurface.band,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      // 纯焦点位移（倍率 1）：-100px → 窗口右移 100 × (30s ÷ 760px)。
      session.pinchFrame(factor: 1, focalX: 300);
      expect(
        session.window!.start,
        Duration(
          microseconds: (100 * base.visible.inMicroseconds / 760).round(),
        ),
        reason: '带内口径按内容区宽 760px 换算',
      );
    });

    test('空白面口径：换算带宽 = 控制层宽（不让位片头）', () {
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: Duration.zero,
          end: const Duration(seconds: 30),
        ),
      );
      final base = session.window!;
      session.beginPinch(
        surface: TrackPinchSurface.blank,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 1, focalX: 300);
      expect(
        session.window!.start,
        Duration(
          microseconds: (100 * base.visible.inMicroseconds / 800).round(),
        ),
        reason: '空白面口径按控制层宽 800px 换算',
      );
    });

    test('锚点按预览线显示值取值（不是引擎播放位置）', () async {
      // 引擎播放位置 75s、预览线显示值 65s：锚点取显示值 → 缩放后窗口
      // [62.5s, 77.5s]；若取引擎播放位置则为 [67.5s, 82.5s]。
      await engine.seek(const Duration(seconds: 75));
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      session.setPreviewLine(const Duration(seconds: 65));
      session.beginPinch(
        surface: TrackPinchSurface.blank,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 2, focalX: 400); // 焦点不动、张合 2×。
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 62500),
        end: const Duration(milliseconds: 77500),
        total: total,
      );
    });

    test('按下中点簿记：≥2 个按下点取均值', () {
      // 按下中点 400（±100 的两个按下点）→ 焦点时间 75s；显示值 65s 在窗内
      // → 锚点 65s → [62.5s, 77.5s]。
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      session.setPreviewLine(const Duration(seconds: 65));
      session.beginPinch(
        surface: TrackPinchSurface.band,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 2, focalX: 400);
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 62500),
        end: const Duration(milliseconds: 77500),
        total: total,
      );
    });

    test('按下中点簿记：不足两个按下点退回起手焦点 x', () {
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      session.setPreviewLine(const Duration(seconds: 65));
      // 按下点快照只剩一个（识别器重启的抬指瞬间）：退回起手焦点 x=400。
      session.beginPinch(
        surface: TrackPinchSurface.blank,
        width: 800,
        downXs: const [100],
        fallbackFocalX: 400,
      );
      session.pinchFrame(factor: 2, focalX: 400);
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 62500),
        end: const Duration(milliseconds: 77500),
        total: total,
      );
    });

    test('两次捏合不因触发面不同而算出不同锚点', () {
      // 窗口不在零点 → 片头让位收回，带内与空白面的内容区宽同值（800）；
      // 两次捏合同参（同一按下中点、同一宽度、同一焦点）→ 窗口逐位相同。
      TimelineWindow zoomed() => TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 90),
      );
      session.setPreviewLine(const Duration(seconds: 65));

      session.updateWindow(zoomed());
      session.beginPinch(
        surface: TrackPinchSurface.band,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 2, focalX: 400);
      final band = session.window!;
      session.endPinch();

      session.updateWindow(zoomed());
      session.beginPinch(
        surface: TrackPinchSurface.blank,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 2, focalX: 400);
      final blank = session.window!;

      expect(blank.start, band.start, reason: '触发面不同不改变锚点');
      expect(blank.end, band.end);
      expect(band.start, const Duration(milliseconds: 62500));
    });

    test('窄带：带内容区宽 ≤ 0 时窗口不动', () {
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      final base = session.window;
      session.beginPinch(
        surface: TrackPinchSurface.band,
        width: 20,
        downXs: const [5, 15],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 2, focalX: 10);
      expect(
        identical(session.window, base),
        isTrue,
        reason: '内容区宽 ≤ 0 → 不可映射，窗口不动',
      );
    });

    test('收尾后帧事件 no-op', () {
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      final base = session.window;
      session.beginPinch(
        surface: TrackPinchSurface.band,
        width: 800,
        downXs: const [300, 500],
        fallbackFocalX: 0,
      );
      session.endPinch();
      session.pinchFrame(factor: 2, focalX: 400);
      expect(identical(session.window, base), isTrue);
    });

    test('宽度非正不起会话（帧事件 no-op）', () {
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      final base = session.window;
      session.beginPinch(
        surface: TrackPinchSurface.blank,
        width: 0,
        downXs: const [],
        fallbackFocalX: 0,
      );
      session.pinchFrame(factor: 2, focalX: 100);
      expect(identical(session.window, base), isTrue);
    });
  });
}

/// 时长未知的内核（微调时长门用例）。
class _DurationlessEngine extends FakePlaybackEngine {
  @override
  Duration? get duration => null;
}
