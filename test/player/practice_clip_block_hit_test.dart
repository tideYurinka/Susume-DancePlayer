import 'dart:ui' as ui;

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        activeLoopRangeProvider,
        annotationTimelineProvider,
        practiceClipActivationProvider,
        practiceClipsProvider,
        selectedPracticeClipIdProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/device_viewport.dart';

/// 练习片段块体**处处可点**：设备等效视口下块体
/// 两端 14dp 的截取端点带、被播放头竖线压住的块首/块尾、以及几 dp 的手指
/// 偏移都算激活；端点带的横向拖动语义不变（仍是截取）；片段块登记为
/// 「编辑内容」——带级空白手势不在块体上生效。测试只断言用户可见外部行为。
void main() {
  // 设备等效视口（真机横屏 2736×1264 @ dpr 3.5 ⇒ 781.7×361.1dp）下，一支
  // 180 秒的舞里录 10 秒 = 块宽约 43dp，扣掉两端各 14dp 只有中间约 15dp
  // 是活的——这种窄块在真机上是默认状态，不是边缘情形。
  const total = Duration(minutes: 3);
  const clip = PracticeClip(
    id: 'c1',
    materialId: 'm1',
    materialSourceStartMs: 100000,
    inMs: 0,
    outMs: 10000,
    materialDurationMs: 30000,
  );

  late FakePlaybackEngine engine;

  /// 设备等效视口 + 真机手指容差：`physicalSize`/`dpr` 取开发真机横屏；
  /// 手势容差取平台口径（touch slop ≈ 8dp，physical = 8 × dpr）——测试
  /// 视图默认报空手势设置、回落到常量 18dp，与真机不是一个数。
  void setDeviceView(WidgetTester tester) {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 8 * 3.5,
    );
    addTearDown(tester.view.reset);
  }

  /// 泵对比行集的轨道带（设备等效视口下整宽）；返回宿主容器与片段块矩形。
  Future<ProviderContainer> pumpBand(
    WidgetTester tester, {
    List<PracticeClip> clips = const [clip],
    AnnotationTimeline? timeline,
    Duration? playhead,
    VoidCallback? onCollapse,
    VoidCallback? onDoubleTap,
    VoidCallback? onTwoFingerDoubleTap,
  }) async {
    if (playhead != null) await engine.seek(playhead);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatTrackStateProvider.overrideWithBuild(
            (ref, _) => uniformReadyBeatState(seconds: 180),
          ),
          annotationTimelineProvider.overrideWithBuild(
            (ref, _) => timeline ?? AnnotationTimeline.wholeVideo(total),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: buildTrackBandSession(
                  engine: engine,
                  timeline: timeline,
                ),
                rowTable: TrackRowTable.compare,
                onCollapse: onCollapse,
                onDoubleTap: onDoubleTap,
                onTwoFingerDoubleTap: onTwoFingerDoubleTap,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackBand)),
      listen: false,
    );
    container.read(practiceClipsProvider.notifier).restore(clips);
    await tester.pumpAndSettle();
    return container;
  }

  Rect blockRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('practice_clip_c1')));

  /// 块体外层装饰（激活 = 块缘白色 2px 描边）。
  BoxDecoration blockDecoration(WidgetTester tester) =>
      tester
              .widget<DecoratedBox>(
                find
                    .descendant(
                      of: find.byKey(const Key('practice_clip_c1')),
                      matching: find.byType(DecoratedBox),
                    )
                    .first,
              )
              .decoration
          as BoxDecoration;

  /// 点按 [point]（点，不再抬起后移动）；越过双击判定窗口稳定状态。
  Future<void> tapAt(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
  }

  /// 断言「该处单击 = 激活同一结果」：块体换激活填充 + 加粗白描边、单一循
  /// 环范围 = 片段源区间、选中槽切到该片段。返回后片段处于激活 + 选中态。
  void expectActivated(WidgetTester tester, ProviderContainer container) {
    expect(container.read(practiceClipActivationProvider)?.clipId, 'c1');
    final range = container.read(activeLoopRangeProvider);
    expect(range, isNotNull);
    expect(range!.start, const Duration(milliseconds: 100000));
    expect(range.end, const Duration(milliseconds: 110000));
    expect(container.read(selectedPracticeClipIdProvider), 'c1');
    final decoration = blockDecoration(tester);
    expect(
      decoration.color,
      kPracticeClipActiveBlockColor,
      reason: '激活 = 填充换激活色',
    );
    final border = decoration.border as Border?;
    expect(border?.top.color, Colors.white, reason: '激活 = 块缘白色描边');
    expect(border?.top.width, kPracticeClipActiveBorderWidth);
  }

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
  });

  group('片段块体处处可点：设备等效视口下的三处单击', () {
    testWidgets('左端 14dp 内 / 正中 / 右端 14dp 内三处单击都激活，结果一致', (
      tester,
    ) async {
      setDeviceView(tester);
      final container = await pumpBand(tester);
      final block = blockRect(tester);
      // 真机形状：块宽 ≈ 43dp，两端各 14dp 是端点带。
      // 块宽按内容区宽（带宽让出轨道片头带）。
      expect(
        block.width,
        closeTo(bandContentWidth(781.7) * 10000 / 180000, 1.5),
      );

      final left = Offset(block.left + 7, block.center.dy);
      final center = Offset(block.center.dx, block.center.dy);
      final right = Offset(block.right - 7, block.center.dy);
      // 三处都真实落在块的横向范围内（非中心落点）。
      expect(left.dx - block.left, lessThan(14));
      expect(block.right - right.dx, lessThan(14));

      await tapAt(tester, left);
      expectActivated(tester, container);
      await tapAt(tester, left);
      expect(
        container.read(practiceClipActivationProvider),
        isNull,
        reason: '同一处再点仍走同一条 toggle 路径（取消激活）',
      );

      await tapAt(tester, center);
      expectActivated(tester, container);
      await tapAt(tester, center);
      expect(container.read(practiceClipActivationProvider), isNull);

      await tapAt(tester, right);
      expectActivated(tester, container);
    });

    testWidgets('真机手指容差下点偏几 dp 仍激活、不把控制层收起来', (tester) async {
      setDeviceView(tester);
      var collapses = 0;
      final container = await pumpBand(
        tester,
        onCollapse: () => collapses++,
      );
      final block = blockRect(tester);

      // 首端带内按下 → 滚了约 6dp → 抬起：真机平台上这仍是点按（8dp slop）。
      final gesture = await tester.startGesture(
        Offset(block.left + 7, block.center.dy),
      );
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(1, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      expectActivated(tester, container);
      expect(collapses, 0, reason: '块体上的点按不是空白单击');
    });

    testWidgets('越过 8dp 容差的偏移不再是点按，但也不是空白单击（布景真按设备容差在跑）', (
      tester,
    ) async {
      setDeviceView(tester);
      var collapses = 0;
      final container = await pumpBand(
        tester,
        onCollapse: () => collapses++,
      );
      final block = blockRect(tester);

      // 块体正中按下 → 滚 12dp：真机 8dp 容差下**已经不是点按**（若测试视图
      // 报空手势设置、回落到常量 18dp，12dp 仍会被判成点按而激活——故本条
      // 同时钉住「布景用的是设备容差」这件事），但绝不能变成空白单击把
      // 控制层收起来（块体是编辑内容）。
      final gesture = await tester.startGesture(block.center);
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      expect(
        container.read(practiceClipActivationProvider),
        isNull,
        reason: '12dp > 8dp 设备容差 ⇒ 不算点按',
      );
      expect(collapses, 0, reason: '也不是空白单击（块体是编辑内容）');
    });

    testWidgets('端点带按下后横向移动 18–36px 仍是截取拖动：不激活、不改选中', (
      tester,
    ) async {
      setDeviceView(tester);
      final container = await pumpBand(tester);
      final block = blockRect(tester);
      final before = container.read(practiceClipsProvider).single;

      // 从尾端点带中心按下，横移 24px（> 18px 下界、< 36px 上界）。
      final gesture = await tester.startGesture(
        Offset(block.right - 7, block.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      final after = container.read(practiceClipsProvider).single;
      expect(after.id, before.id);
      expect(after.inMs, before.inMs, reason: '另一端不动');
      expect(
        after.outMs,
        greaterThan(before.outMs),
        reason: '仍进截取拖动会话（素材内 out 变长）',
      );
      expect(
        container.read(practiceClipActivationProvider),
        isNull,
        reason: '拖动不误触激活',
      );
      expect(
        container.read(selectedPracticeClipIdProvider),
        isNull,
        reason: '拖动不改变选中',
      );
    });

    testWidgets('播放头压在块首 / 块尾时点该处仍激活', (tester) async {
      setDeviceView(tester);
      // 播放头停在片段源区间首（刚激活后停的位置）。
      final container = await pumpBand(
        tester,
        playhead: const Duration(milliseconds: 100000),
      );
      final block = blockRect(tester);
      var line = tester.getCenter(find.byKey(const Key('preview_line')));
      expect(
        line.dx,
        closeTo(block.left, 1),
        reason: '播放头正压在块首',
      );

      await tapAt(tester, Offset(line.dx, block.center.dy));
      expectActivated(tester, container);

      // 退出激活，再把播放头挪到块尾（刚录完停录的位置）。
      await tapAt(tester, Offset(line.dx, block.center.dy));
      expect(container.read(practiceClipActivationProvider), isNull);

      await engine.seek(const Duration(milliseconds: 110000));
      await tester.pumpAndSettle();
      line = tester.getCenter(find.byKey(const Key('preview_line')));
      expect(line.dx, closeTo(block.right, 1), reason: '播放头正压在块尾');

      await tapAt(tester, Offset(line.dx, block.center.dy));
      expectActivated(tester, container);
    });

    testWidgets('播放头压在块上时不是空白单击：不收控制层', (tester) async {
      setDeviceView(tester);
      var collapses = 0;
      await pumpBand(
        tester,
        playhead: const Duration(milliseconds: 100000),
        onCollapse: () => collapses++,
      );
      final block = blockRect(tester);
      final line = tester.getCenter(find.byKey(const Key('preview_line')));

      await tapAt(tester, Offset(line.dx, block.center.dy));
      expect(collapses, 0);

      // 带级空白对照：节拍轨行的空白处单击仍收起（语义保持）。
      final beatY = tester.getCenter(find.byKey(const Key('track_beat'))).dy;
      await tapAt(tester, Offset(block.right + 60, beatY));
      expect(collapses, 1, reason: '带级空白单击语义不变');
    });
  });

  group('片段块算「编辑内容」：块上多指操作不触发空白手势', () {
    /// 双指 tap：两指按下 → 50ms → 相继抬起（两指都落在块体上）。
    Future<void> twoFingerTapAt(
      WidgetTester tester,
      Offset p1,
      Offset p2,
    ) async {
      final g1 = await tester.startGesture(p1);
      final g2 = await tester.startGesture(p2);
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('块体上双指双击不触发延迟播放、不收控制层', (tester) async {
      setDeviceView(tester);
      var collapses = 0;
      var twoFingerDoubleTaps = 0;
      await pumpBand(
        tester,
        onCollapse: () => collapses++,
        onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
      );
      final block = blockRect(tester);
      // 两指都落在块体上（块宽 ≈ 43dp，两指相距 20dp 仍在块内、且分居
      // 正中两侧——避开端点带，钉的是块体本身的「编辑内容」身份）。
      final p1 = Offset(block.center.dx - 5, block.center.dy);
      final p2 = Offset(block.center.dx + 15, block.center.dy);

      await twoFingerTapAt(tester, p1, p2);
      await twoFingerTapAt(tester, p1, p2);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      expect(twoFingerDoubleTaps, 0, reason: '块体不是空白带');
      expect(collapses, 0);
    });

    testWidgets('块体与学习段体 x 区间重叠时仍算编辑内容（段体命中不得吃掉块）', (
      tester,
    ) async {
      setDeviceView(tester);
      var collapses = 0;
      var twoFingerDoubleTaps = 0;
      // 分段线 00:30 / 01:00 / 01:30：片段区间 01:40–01:50 整段落在第 3 段
      // 段体内（真实舞曲的常态——段体命中与块体 x 区间必然重叠）。
      await pumpBand(
        tester,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 30)),
            SegmentLine(position: Duration(seconds: 60)),
            SegmentLine(position: Duration(seconds: 90)),
          ],
        ),
        onCollapse: () => collapses++,
        onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
      );
      final block = blockRect(tester);
      final p1 = Offset(block.center.dx - 5, block.center.dy);
      final p2 = Offset(block.center.dx + 15, block.center.dy);

      await twoFingerTapAt(tester, p1, p2);
      await twoFingerTapAt(tester, p1, p2);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      expect(twoFingerDoubleTaps, 0, reason: '块体压在段体上仍是内容');
      expect(collapses, 0);
    });

    testWidgets('块体上双指操作（带位移）不收控制层、不触发延迟播放', (tester) async {
      setDeviceView(tester);
      var collapses = 0;
      var twoFingerDoubleTaps = 0;
      await pumpBand(
        tester,
        onCollapse: () => collapses++,
        onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
      );
      final block = blockRect(tester);

      final g1 = await tester.startGesture(
        Offset(block.center.dx - 5, block.center.dy),
      );
      final g2 = await tester.startGesture(
        Offset(block.center.dx + 15, block.center.dy),
      );
      await tester.pump(const Duration(milliseconds: 30));
      for (var i = 0; i < 6; i++) {
        await g1.moveBy(const Offset(2, 0));
        await g2.moveBy(const Offset(2, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      expect(collapses, 0);
      expect(twoFingerDoubleTaps, 0);
    });
  });
}
