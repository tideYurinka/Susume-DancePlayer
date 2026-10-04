import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatGridProvider;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/gestures.dart'
    show kLongPressDoubleSpeedRate, kLongPressDoubleSpeedTimeout;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTimingOf;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';

void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    UniformBeatGrid grid = const UniformBeatGrid(),
    FakeSystemMediaVolumeController? volume,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          // 系统媒体音量 seam：注入 fake 断言三指不改音量。
          systemMediaVolumeControllerProvider.overrideWithValue(
            volume ?? FakeSystemMediaVolumeController(),
          ),
          beatGridProvider.overrideWithValue(grid),
        ],
        child: MaterialApp(home: PlayerPage(source: Uri.file('/videos/a.mp4'))),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 单指双击：两次 tap 间隔 < kDoubleTapTimeout（300ms）。
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 一次双指 tap：两指按下 → 50ms → 两指抬起。
  Future<void> twoFingerTap(WidgetTester tester, Offset center) async {
    final g1 = await tester.startGesture(center);
    final g2 = await tester.startGesture(center + const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 双指双击：两次双指 tap（间隔 100ms < 300ms 窗口）。
  Future<void> twoFingerDoubleTap(WidgetTester tester, Offset center) async {
    await twoFingerTap(tester, center);
    await tester.pump(const Duration(milliseconds: 50));
    await twoFingerTap(tester, center);
    await tester.pump();
  }

  /// 三指水平滑动：三指按下后按 [delta] 步进一次并抬起。
  Future<void> threeFingerSwipe(
    WidgetTester tester, {
    required Offset start,
    required Offset delta,
  }) async {
    final g1 = await tester.startGesture(start);
    final g2 = await tester.startGesture(start + const Offset(40, 0));
    final g3 = await tester.startGesture(start + const Offset(80, 0));
    await tester.pump();
    await g1.moveBy(delta);
    await g2.moveBy(delta);
    await g3.moveBy(delta);
    await tester.pump();
    await g1.up();
    await g2.up();
    await g3.up();
    await tester.pumpAndSettle();
  }

  /// 暂停播放（单指双击）。
  Future<void> pauseViaDoubleTap(WidgetTester tester) async {
    await doubleTap(tester, find.byKey(const Key('player_surface')));
    await tester.pumpAndSettle();
  }

  group('双指双击延迟播放', () {
    testWidgets('双指双击触发延迟播放，一个八拍后开始播放', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);
      expect(engine.isPlaying, isFalse);

      await twoFingerDoubleTap(tester, const Offset(400, 300));
      await tester.pump();
      // 触发后：进入预备（尚未播放）；预备期树上不存在「延迟播放中…」
      // 徽章键与文案。
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(find.text('延迟播放中…'), findsNothing);
      expect(engine.isPlaying, isFalse);

      // 一个八拍（默认 120 BPM → 4s）后开始播放，提示消失。
      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      await tester.pump();
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('延迟期间三指滑动同样中断延迟播放', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);

      await twoFingerDoubleTap(tester, const Offset(400, 300));
      await tester.pump();

      await tester.pump(const Duration(seconds: 2));
      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(-60, 0),
      );
      expect(engine.position, Duration.zero); // 三指左滑跳转视频首

      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      expect(engine.isPlaying, isFalse); // 延迟播放已被中断
    });

    testWidgets('双指双击与单指双击互斥：先单指后双指不触发任何动作', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位

      await tester.tap(find.byKey(const Key('player_surface'))); // 单指 tap
      await tester.pump(const Duration(milliseconds: 50));
      await twoFingerTap(tester, const Offset(400, 300)); // 双指 tap（手指数不一致）
      await tester.pump(const Duration(milliseconds: 400)); // 越过双击窗口

      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(engine.isPlaying, isTrue); // 未暂停
    });

    testWidgets('双指双击与单指双击互斥：先双指后单指不触发任何动作', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30));

      await twoFingerTap(tester, const Offset(400, 300)); // 双指 tap
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('player_surface'))); // 单指 tap
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(engine.isPlaying, isTrue); // 未暂停
    });

    testWidgets('两次双指 tap 间隔超过 300ms 窗口不触发延迟播放', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);

      await twoFingerTap(tester, const Offset(400, 300)); // 第一 tap
      await tester.pump(const Duration(milliseconds: 400)); // 越过 300ms 窗口
      await twoFingerTap(tester, const Offset(400, 300)); // 第二 tap（新序列第一 tap）
      await tester.pump();

      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(engine.isPlaying, isFalse); // 仍暂停
    });

    testWidgets('八拍时长可按 BPM 换算（widget 级，bpm 240 → 2s 后开始播放）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(
        tester,
        engine: engine,
        grid: const UniformBeatGrid(bpm: 240),
      );
      await pauseViaDoubleTap(tester);

      await twoFingerDoubleTap(tester, const Offset(400, 300));
      await tester.pump();

      // 未到八拍（240 BPM → 一拍 250ms → 一个八拍 2s）不播放。
      await tester.pump(const Duration(seconds: 1));
      expect(engine.isPlaying, isFalse);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(engine.isPlaying, isTrue);
    });
  });

  group('三指滑动跳转', () {
    testWidgets('三指左滑跳转视频首（当前无分段线 → 回退跳首）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位
      await pauseViaDoubleTap(tester);
      final before = engine.position;
      expect(before, greaterThan(Duration.zero));

      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(-60, 0),
      );

      expect(engine.position, Duration.zero);
      expect(engine.position, lessThan(before));
    });

    testWidgets('三指右滑跳转视频尾（当前无分段线 → 回退跳尾）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);

      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(60, 0),
      );

      expect(engine.position, const Duration(minutes: 3));
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('三指滑动只产生跳转：不改音量/倍速/镜像/播放态（无标记变更）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await pumpPlayer(tester, engine: engine, volume: volume);
      await pauseViaDoubleTap(tester);
      final rateBefore = engine.rate;
      final volumeBefore = volume.currentVolume;

      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(-60, 0),
      );

      expect(engine.position, Duration.zero); // 只发生跳转
      expect(engine.rate, rateBefore);
      expect(volume.currentVolume, volumeBefore);
      expect(
        find.byKey(const Key('mirrored_surface')),
        findsNothing,
        reason: '三指滑动不改变镜像状态',
      );
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('三指垂直滑不触发跳转（未绑定动作）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);
      final before = engine.position;

      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(0, -60),
      );

      expect(engine.position, before);
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
    });
  });

  group('三指跳转短提示', () {
    /// 屏幕正中三指跳转短提示浮层。
    Finder toastFinder() => find.byKey(const Key('three_finger_toast'));

    /// 收尾：推进提示走完「0.6s 停留 + 淡出」并断言已消失（收敛各用例
    /// 重复的收尾序列；停留/淡出边界由专门用例断言）。
    Future<void> fadeOutAndGone(WidgetTester tester) async {
      final timing = noticeTimingOf(NoticeId.threeFingerToast);
      await tester.pump(
        timing.hold + timing.fade + const Duration(milliseconds: 200),
      );
      expect(toastFinder(), findsNothing);
    }

    testWidgets('右滑跳转瞬间提示出现：屏幕正中、前进图标 + 通用文案「已跳转」', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester); // 冻结 position（不随播放漂移）

      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(60, 0),
      );

      // 跳转生效 + 提示出现于屏幕正中。
      expect(engine.position, const Duration(minutes: 3));
      expect(toastFinder(), findsOneWidget);
      final center = tester.getCenter(toastFinder());
      expect(center.dx, closeTo(400, 1));
      expect(center.dy, closeTo(300, 1));
      // 方向图标与滑动方向对应（右滑 = 前进）。
      expect(
        find.descendant(
          of: toastFinder(),
          matching: find.byIcon(Icons.fast_forward),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: toastFinder(),
          matching: find.byIcon(Icons.fast_rewind),
        ),
        findsNothing,
      );
      // 文案通用：不带首/尾断言（跳最近分段线仍正确）。
      expect(find.text('已跳转'), findsOneWidget);
      expect(find.textContaining('开头'), findsNothing);
      expect(find.textContaining('结尾'), findsNothing);

      await fadeOutAndGone(tester);
    });

    testWidgets('左滑跳转瞬间提示方向图标 = 后退（文案与右滑一致）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位（左滑跳首前须在 0 右侧）
      await pauseViaDoubleTap(tester);
      expect(engine.position, greaterThan(Duration.zero));

      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(-60, 0),
      );

      expect(engine.position, Duration.zero);
      expect(toastFinder(), findsOneWidget);
      expect(
        find.descendant(
          of: toastFinder(),
          matching: find.byIcon(Icons.fast_rewind),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: toastFinder(),
          matching: find.byIcon(Icons.fast_forward),
        ),
        findsNothing,
      );
      expect(find.text('已跳转'), findsOneWidget);

      await fadeOutAndGone(tester);
    });

    testWidgets('提示停留到点后自动淡出（fake 时钟 pump 推进断言）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);
      expect(engine.isPlaying, isFalse);

      // 手动三指滑动（全程零时长 pump，精确控制提示出现时刻）。
      final g1 = await tester.startGesture(const Offset(320, 300));
      final g2 = await tester.startGesture(const Offset(360, 300));
      final g3 = await tester.startGesture(const Offset(400, 300));
      await tester.pump();
      for (final g in [g1, g2, g3]) {
        await g.moveBy(const Offset(60, 0));
      }
      await tester.pump();
      expect(engine.position, const Duration(minutes: 3), reason: '右滑已跳转');
      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump();

      // 跳转瞬间提示出现（t = 0）。
      expect(toastFinder(), findsOneWidget);

      // < 0.6s：仍在停留期、不消失。
      await tester.pump(
        noticeTimingOf(NoticeId.threeFingerToast).hold -
            const Duration(milliseconds: 1),
      );
      expect(toastFinder(), findsOneWidget);

      // 0.6s 到点：进入淡出相位（部件仍挂载，透明度动画中）。
      await tester.pump(const Duration(milliseconds: 1));
      expect(toastFinder(), findsOneWidget);

      // 淡出动画到点：回 hidden、浮层卸载。
      await tester.pump(noticeTimingOf(NoticeId.threeFingerToast).fade);
      expect(toastFinder(), findsNothing);

      // 再走更久也不重现（提示只出现一次）。
      await tester.pump(const Duration(seconds: 5));
      expect(toastFinder(), findsNothing);
    });

    testWidgets('提示纯视觉：可见期间单指拖动照常调进度（不拦截触摸/连续操作）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await pauseViaDoubleTap(tester);

      // 三指右滑跳尾 → 提示出现（画面停在尾）。
      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(60, 0),
      );
      expect(engine.position, const Duration(minutes: 3));
      expect(toastFinder(), findsOneWidget);
      final seekCallsBefore = engine.seekCalls.length;

      // 提示仍可见期间，单指从提示正中（屏幕中央）左滑：应照常 seek——
      // 若浮层拦截触摸则拖动不生效。
      final gesture = await tester.startGesture(const Offset(400, 300));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(-30, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(
        engine.seekCalls.length,
        greaterThan(seekCallsBefore),
        reason: '提示浮层不得拦截拖动（seek 持续生效）',
      );
      expect(engine.position, lessThan(const Duration(minutes: 3)));
      // 拖动全程提示未被触摸打断，仍按定时淡出。
      expect(toastFinder(), findsOneWidget);
      await fadeOutAndGone(tester);
    });

    testWidgets('一次三指滑动只跳转一次、提示只出现一次（长滑/反向续滑不重复）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位
      await pauseViaDoubleTap(tester);
      expect(engine.position, greaterThan(Duration.zero));

      // 一次三指会话：帧 0 越阈（3 × 60px）→ 只跳转一次 + 提示出现。
      final g1 = await tester.startGesture(const Offset(300, 300));
      final g2 = await tester.startGesture(const Offset(340, 300));
      final g3 = await tester.startGesture(const Offset(380, 300));
      await tester.pump();
      for (final g in [g1, g2, g3]) {
        await g.moveBy(const Offset(60, 0));
      }
      await tester.pump();
      expect(engine.seekCalls, hasLength(1), reason: '长滑只跳转一次');
      expect(engine.position, const Duration(minutes: 3));
      expect(toastFinder(), findsOneWidget);

      // 同向续滑 9 帧（每帧 100ms → t≈900ms）：不得再跳转；提示若按自身
      // 定时（跳转起 0.6s + 淡出）已消失；若每次续滑都重触发提示，最后一次
      // 触发在 t≈800ms、消失要到 1600ms——此刻应仍可见（区分「只出现一次」）。
      for (var i = 0; i < 9; i++) {
        for (final g in [g1, g2, g3]) {
          await g.moveBy(const Offset(60, 0));
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();
      expect(engine.seekCalls, hasLength(1), reason: '越阈后继续同向长滑不重复跳转');
      expect(engine.position, const Duration(minutes: 3));
      expect(toastFinder(), findsNothing, reason: '提示只出现一次：续滑不重排/重现，已按定时淡出');

      // 反向续滑（t → ~1800ms）：同样不触发第二次跳转、不重现提示。
      for (var i = 0; i < 9; i++) {
        for (final g in [g1, g2, g3]) {
          await g.moveBy(const Offset(-60, 0));
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();
      expect(engine.seekCalls, hasLength(1), reason: '一次手势内反向续滑不触发第二次跳转');
      expect(engine.position, const Duration(minutes: 3));
      expect(toastFinder(), findsNothing);

      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump(const Duration(seconds: 5));
      expect(toastFinder(), findsNothing);
      expect(engine.seekCalls, hasLength(1));

      // 下一次独立三指滑动：跳转与提示重新可用（一次手势守卫随会话复位）。
      await threeFingerSwipe(
        tester,
        start: const Offset(400, 300),
        delta: const Offset(-60, 0),
      );
      expect(engine.seekCalls, hasLength(2));
      expect(engine.position, Duration.zero);
      expect(toastFinder(), findsOneWidget);
      expect(
        find.descendant(
          of: toastFinder(),
          matching: find.byIcon(Icons.fast_rewind),
        ),
        findsOneWidget,
      );
      await fadeOutAndGone(tester);
    });
  });

  group('系统手势让路区内的点按类手势照常', () {
    /// 顶区让路带内一点（y=10 < 固定下限 48）；组合根默认零上报时下限生效。
    const inZone = Offset(400, 10);

    /// 在 [at] 处做两次 tap（间隔 50ms < 双击窗口）。
    Future<void> doubleTapAt(WidgetTester tester, Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('单击唤出控制层', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await tester.tapAt(inZone);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('双击暂停/播放', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await doubleTapAt(tester, inZone);
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('双指双击延迟播放：一个八拍后开始播放', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await doubleTapAt(tester, inZone); // 先暂停
      await tester.pumpAndSettle();
      await twoFingerTap(tester, inZone);
      await tester.pump(const Duration(milliseconds: 50));
      await twoFingerTap(tester, inZone);
      await tester.pump();
      expect(engine.isPlaying, isFalse, reason: '触发后先进入预备');
      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      await tester.pump();
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('长按 2×：阈值到进入临时倍率，松开恢复', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      final gesture = await tester.startGesture(inZone);
      await tester.pump(
        kLongPressDoubleSpeedTimeout + const Duration(milliseconds: 50),
      );
      expect(engine.rate, kLongPressDoubleSpeedRate);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.0);
    });
  });
}
