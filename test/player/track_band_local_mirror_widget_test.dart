import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_time.dart' show TimelineWindow;
import 'package:dance_learning_app/player/track_band_session.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';

class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「局部镜像轨 widget 层」：常驻轨与片段块呈现（琥珀/灰/选中）、
/// 单击 = 选中并取反启停（经模块 verb）、删除后派生选中失效。
void main() {
  const total = Duration(minutes: 1);

  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  /// 泵出一个带就绪节拍网格 + 局部镜像片段的 TrackBand。
  Future<ProviderContainer> pumpBandWithMirror({
    required WidgetTester tester,
    required List<LocalMirrorFragment> fragments,
    Duration? videoDuration,
    TrackBandSession? session,
    AnnotationTimeline? timeline,
    List<NoteSticker> notes = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
        if (notes.isNotEmpty)
          noteStickersProvider.overrideWithBuild((ref, _) => notes),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) => uniformReadyBeatState(
            seconds: (videoDuration ?? total).inMilliseconds / 1000,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session:
                    session ??
                    buildTrackBandSession(
                      engine: engine,
                      container: container,
                    ),
                rowTable: TrackRowTable.normal,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 经模块 restore（非史装载）就位片段 lane。
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            timeline:
                timeline ??
                AnnotationTimeline.wholeVideo(videoDuration ?? total),
            localMirrorFragments: fragments,
          ),
        );
    await tester.pumpAndSettle();
    return container;
  }

  /// 在全局 [from] 处起手、向右水平拖动 [dx] 像素（分步移动以越过拖动
  /// slop 触发水平拖动识别，片段拖动逐帧读手指位置）。
  Future<void> dragFromRight(
    WidgetTester tester,
    Offset from,
    double dx,
  ) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('局部镜像轨常驻显示与片段块呈现', () {
    testWidgets('空轨亦占 30dp 常驻；总开关开 = 全部片段块琥珀呈现', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          LocalMirrorFragment(startMs: 8000, endMs: 12000),
          LocalMirrorFragment(startMs: 20000, endMs: 24000),
        ],
      );
      // 轨行常驻；空轨行高问行表。
      expect(find.byKey(const Key('track_mirror')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('track_mirror'))).height,
        TrackRowTable.normal.rectOf(TrackRowId.localMirror).height,
      );
      // 片段块键。
      expect(find.byKey(const Key('mirror_fragment_0_icon')), findsOneWidget);
      expect(find.byKey(const Key('mirror_fragment_1_icon')), findsOneWidget);
      final f0 = tester.widget<Icon>(
        find.byKey(const Key('mirror_fragment_0_icon')),
      );
      final f1 = tester.widget<Icon>(
        find.byKey(const Key('mirror_fragment_1_icon')),
      );
      expect(f0.color, kLocalMirrorEnabledIconColor, reason: '总开关开 = 琥珀图标');
      expect(
        f1.color,
        kLocalMirrorEnabledIconColor,
        reason: '总开关开 = 全部琥珀',
      );
      container.dispose();
    });

    testWidgets('局部镜像总开关关：全部片段块按不生效视觉（灰）呈现', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          LocalMirrorFragment(startMs: 8000, endMs: 12000),
          LocalMirrorFragment(startMs: 20000, endMs: 24000),
        ],
      );
      container.read(localMirrorEnabledProvider.notifier).replace(false);
      await tester.pumpAndSettle();

      // 总开关关 = 全部片段不生效视觉（灰），与片段自身无关（片段 = 纯区间）。
      final f0 = tester.widget<Icon>(
        find.byKey(const Key('mirror_fragment_0_icon')),
      );
      final f1 = tester.widget<Icon>(
        find.byKey(const Key('mirror_fragment_1_icon')),
      );
      expect(f0.color, Colors.white38, reason: '总开关关 → 不生效视觉（灰图标）');
      expect(f1.color, Colors.white38, reason: '总开关关 → 全部灰');

      // 再开：全部片段恢复琥珀。
      container.read(localMirrorEnabledProvider.notifier).replace(true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Icon>(find.byKey(const Key('mirror_fragment_0_icon')))
            .color,
        kLocalMirrorEnabledIconColor,
      );
      container.dispose();
    });

    testWidgets('单击片段 = 选中并取反启停（经模块 verb、入史入队）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 12000)],
      );
      // 定位片段块中心（0..60s 映射到内容区 [40, 800] → 10s ≈ 167px）。
      final blockRect = tester.getRect(find.byKey(const Key('track_mirror')));
      final tapPos = Offset(
        bandXOf(
          const Duration(seconds: 10),
          total: total,
          width: blockRect.width,
          bandLeft: blockRect.left,
        ),
        blockRect.center.dy,
      );
      await tester.tapAt(tapPos);
      await tester.pumpAndSettle();

      final sel = container.read(annotationSelectionProvider);
      expect(sel, isA<LocalMirrorFragmentSelection>());
      expect((sel! as LocalMirrorFragmentSelection).index, 0);
      expect(
        container.read(annotationEditHistoryProvider).length,
        0,
        reason: '点选只选中，不产生编辑/撤销步',
      );
      container.dispose();
    });

    testWidgets('平移窗口后视口内片段仍呈现（裁切按 ms 与窗口对齐）', (tester) async {
      // 窗口初始 = 整片；片段 8s..12s 在窗口内。
      final session = buildTrackBandSession(engine: engine);
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 12000)],
        session: session,
      );
      expect(find.byKey(const Key('mirror_fragment_0_icon')), findsOneWidget);

      // 把可视窗口平移到 10s..20s（片段 8..12s 仍部分可见）。
      session.updateWindow(
        TimelineWindow(
          total: total,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('mirror_fragment_0_icon')),
        findsOneWidget,
        reason: '窗口平移后片段块应仍呈现（裁切不误用 1000× 单位）',
      );
      container.dispose();
    });
  });

  group('片段拖动语义', () {
    // 时间→带内全局 x（经共享测试入口，内容区左缘让出片头带）。
    double xOf(Rect rect, int ms) => bandXOf(
      Duration(milliseconds: ms),
      total: total,
      width: rect.width,
      bandLeft: rect.left,
    );

    // 镜像整体移的相对平移语义（请求 = 手指时间 − 片段起点）由域直测承担：
    // track_band_drag_test.dart「镜像与备注四族 / 抓取偏移与相对平移」；
    // 带侧边界来源装配由 track_band_fragment_drag_boundary_test.dart 承担。
    // 本文件余下的是命中解析、渲染与窄块起手可达类断言（起手落在块体还
    // 是端点带、块体拖动不被端点带吞掉）。

    testWidgets('片段边界与分段线同位仍可拖动边界（bug1：分段命中列不遮局部镜像轨）', (tester) async {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: total,
        segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
      );
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 12000)],
        timeline: timeline,
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      // 片段起点 8s 与分段线 8s 同位；起手在片段 start 边界命中带。
      final grabX = xOf(rect, 8000) + kLocalMirrorEdgeHitWidth / 2;
      const deltaMs = 3000;
      await dragFromRight(
        tester,
        Offset(grabX, rect.center.dy),
        xOf(rect, deltaMs) - xOf(rect, 0),
      );
      final f = container.read(localMirrorFragmentsProvider).single;
      expect(f.endMs, 12000, reason: 'start 边界拖只动 start 端，end 不变');
      expect(
        f.startMs,
        greaterThan(8000),
        reason: '边界与分段线同位仍能起手拖 start 端（分段命中列不应截走该指针）',
      );
      container.dispose();
    });
  });

  group('窄块不绘图标', () {
    /// 取片段块体内的填充 [Container]（块级 key 定位，图标可缺）。
    Container blockContainer(WidgetTester tester, int index) =>
        tester.widget<Container>(
          find.descendant(
            of: find.byKey(Key('mirror_fragment_$index')),
            matching: find.byType(Container),
          ),
        );

    testWidgets('窄块不绘制反相图标；宽块仍绘图标（行为不变）', (tester) async {
      await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          // 窄块：视觉宽 50ms ≈ 0.7px < 40dp 阈值。
          LocalMirrorFragment(startMs: 8000, endMs: 8050),
          // 宽块：4000ms，行为不变。
          LocalMirrorFragment(startMs: 20000, endMs: 24000),
        ],
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_icon')),
        findsNothing,
        reason: '窄块只绘填充 + 描边，不绘反相图标',
      );
      expect(
        find.byKey(const Key('mirror_fragment_1_icon')),
        findsOneWidget,
        reason: '非窄块仍绘制图标（行为不变）',
      );
    });

    testWidgets('窄块仍以填充/描边区分生效/不生效与选中（不依赖图标）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          LocalMirrorFragment(startMs: 8000, endMs: 8050),
          LocalMirrorFragment(startMs: 9000, endMs: 9050),
        ],
      );
      // 总开关开（缺省）= 生效窄块琥珀填充。
      final enabledBox = blockContainer(tester, 0).decoration! as BoxDecoration;
      expect(enabledBox.color, kLocalMirrorEnabledFill);
      // 选中窄块 = 琥珀填充（选中描边白色、与开关无关）。
      final disabledBox =
          blockContainer(tester, 1).decoration! as BoxDecoration;
      expect(disabledBox.color, kLocalMirrorEnabledFill);
      // 生效描边（琥珀，40% 透明度，非选中描边）。
      expect(
        (enabledBox.border! as Border).top.color,
        kLocalMirrorEnabledColor.withValues(alpha: 0.4),
      );
      expect(
        (disabledBox.border! as Border).top.color,
        kLocalMirrorEnabledColor.withValues(alpha: 0.4),
      );
      // 选中窄块 = 白描边承担选中态。
      container
          .read(annotationSelectionDomainProvider)
          .select(LocalMirrorFragmentSelection(0));
      await tester.pumpAndSettle();
      final selectedBox =
          blockContainer(tester, 0).decoration! as BoxDecoration;
      expect(
        selectedBox.border,
        isA<Border>().having((b) => b.top.color, '描边色', Colors.white),
        reason: '选中态由描边承担（图标可缺）',
      );
      container.dispose();
    });
  });

  group('窄块基座', () {
    // 时间→带内全局 x（经共享测试入口，内容区左缘让出片头带）。
    double xOf(Rect rect, int ms) => bandXOf(
      Duration(milliseconds: ms),
      total: total,
      width: rect.width,
      bandLeft: rect.left,
    );

    testWidgets('窄块挂块级 key、不渲染端点命中带，块体点按可达（只选中）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          // 视觉宽 50ms ≈ 0.7px < 2×14dp：窄块（旧端点带覆盖整块的死区根因）。
          LocalMirrorFragment(startMs: 8000, endMs: 8050),
        ],
      );
      // 块级 key 定位（图标可缺时仍可定位块，依赖）。
      expect(find.byKey(const Key('mirror_fragment_0')), findsOneWidget);
      // 端点命中带不渲染。
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsNothing,
        reason: '窄块不渲染 start 端点命中带',
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_end')),
        findsNothing,
        reason: '窄块不渲染 end 端点命中带',
      );
      // 块体点按可达：点窄块中心 = 选中并取反启停（不再被端点带吞掉）。
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      await tester.tapAt(Offset(xOf(rect, 8025), rect.center.dy));
      await tester.pumpAndSettle();
      final sel = container.read(annotationSelectionProvider);
      expect(
        sel,
        isA<LocalMirrorFragmentSelection>(),
        reason: '窄块体点按直达块体层 = 只选中（消解死区）',
      );
      container.dispose();
    });

    testWidgets('窄块块体拖动可达：起手进入整体平移（端点带不再吞拖动起手）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 8050)],
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      const deltaMs = 3000;
      await dragFromRight(
        tester,
        Offset(xOf(rect, 8025), rect.center.dy),
        xOf(rect, deltaMs) - xOf(rect, 0),
      );
      final f = container.read(localMirrorFragmentsProvider).single;
      expect(f.endMs - f.startMs, 50, reason: '窄块体拖动 = 整体平移，保持原宽');
      // 容差 2000ms = 拖动 slop（≈18px @ 800px/60s ≈ 1350ms）与起手吸附余量。
      expect(
        f.startMs,
        inInclusiveRange(8000 + deltaMs - 2000, 8000 + deltaMs),
        reason: '窄块块体拖动起手可达（旧端点带覆盖死区已消解）',
      );
      container.dispose();
    });

    testWidgets('阈值边界：块宽恰为 40dp 不算窄块，端点命中带仍在', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      );
      // 实测带几何 → 换算 40dp 对应毫秒（ceil + 1ms 补偿毫秒粒度/浮点
      // 误差，使块宽不小于阈值），经 restore 重设片段。
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      // 阈值毫秒按本带几何（内容区宽）换算。
      final narrowMs =
          (kLocalMirrorNarrowWidth *
                  total.inMilliseconds /
                  bandContentWidth(rect.width))
              .ceil();
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            AnnotationRestoreDocument(
              timeline: AnnotationTimeline.wholeVideo(total),
              localMirrorFragments: [
                LocalMirrorFragment(startMs: 8000, endMs: 8000 + narrowMs + 1),
              ],
            ),
          );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('mirror_fragment_0'))).width,
        moreOrLessEquals(kLocalMirrorNarrowWidth, epsilon: 0.05),
        reason: '前置：片段块宽恰达阈值（毫秒粒度内取上整）',
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsOneWidget,
        reason: 'width < 40 才是窄块：宽恰达 40dp 仍渲染端点带',
      );
      container.dispose();
    });

    testWidgets('非窄块端点命中带仍在、端点拖仍生效（start 拖只动 start）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      );
      expect(find.byKey(const Key('mirror_fragment_0')), findsOneWidget);
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsOneWidget,
        reason: '宽块保留端点命中带',
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_end')),
        findsOneWidget,
      );
      // 从 start 端点带起手拖 +3000ms：start 动、end 不动。
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      const deltaMs = 3000;
      await dragFromRight(
        tester,
        Offset(xOf(rect, 8000) + kLocalMirrorEdgeHitWidth / 2, rect.center.dy),
        xOf(rect, deltaMs) - xOf(rect, 0),
      );
      final f = container.read(localMirrorFragmentsProvider).single;
      expect(f.endMs, 16000, reason: '端点拖只动 start 端');
      expect(
        f.startMs,
        inInclusiveRange(8000 + deltaMs - 2000, 8000 + deltaMs),
        reason: 'start 端随手指右移（扣拖动 slop）',
      );
      container.dispose();
    });
  });
  group('行级点按放宽', () {
    // 时间→带内全局 x（经共享测试入口，内容区左缘让出片头带）。
    double xOf(Rect rect, int ms) => bandXOf(
      Duration(milliseconds: ms),
      total: total,
      width: rect.width,
      bandLeft: rect.left,
    );

    testWidgets('小片段点附近即切：点块体外 250ms 处也选中并取反启停（无死区）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          // 视觉宽 50ms ≈ 0.7px，远小于最小命中宽 [kLocalMirrorTapHitWidth]。
          LocalMirrorFragment(startMs: 8000, endMs: 8050),
        ],
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      // 点在块体**外**（片段终点右侧 250ms，块体本身仅 50ms 宽，点不中块体），
      // 落在对称扩展命中域（40dp ≈ 3750ms）内。
      await tester.tapAt(Offset(xOf(rect, 8300), rect.center.dy));
      await tester.pumpAndSettle();
      final sel = container.read(annotationSelectionProvider);
      expect(sel, isA<LocalMirrorFragmentSelection>(), reason: '点附近即选中');
      container.dispose();
    });

    testWidgets('宽片段点块体仍选中（行级解析与块体同一条路径，行为不变）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      await tester.tapAt(Offset(xOf(rect, 12000), rect.center.dy));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationSelectionProvider),
        isA<LocalMirrorFragmentSelection>(),
        reason: '宽片段点块体 = 只选中（行为不变）',
      );
      container.dispose();
    });

    testWidgets('点轨道空白不误触：选中不变、不入史', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      // 40s 处无片段（最近片段中心 12s，远超命中域）。
      await tester.tapAt(Offset(xOf(rect, 40000), rect.center.dy));
      await tester.pumpAndSettle();
      expect(container.read(annotationSelectionProvider), isNull);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      container.dispose();
    });

    testWidgets('同一次 tap 只选中一次：块体上点按仅经行级层判定、无双重作用', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 8050)],
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      // 经块级 key 定位块（图标可缺时仍可定位），点其几何中心。
      final block = tester.getRect(find.byKey(const Key('mirror_fragment_0')));
      await tester.tapAt(Offset(block.center.dx, rect.center.dy));
      await tester.pumpAndSettle();
      expect(
        (container.read(annotationSelectionProvider)!
                as LocalMirrorFragmentSelection)
            .index,
        0,
        reason: '恰选中一次（若块体/行级两层各自触发仍只是重复选中同块）',
      );
      expect(container.read(annotationEditHistoryProvider).length, 0);
      container.dispose();
    });
  });

  group('窄块基座', () {
    // 时间→带内全局 x（经共享测试入口，内容区左缘让出片头带）。
    double xOf(Rect rect, int ms) => bandXOf(
      Duration(milliseconds: ms),
      total: total,
      width: rect.width,
      bandLeft: rect.left,
    );

    testWidgets('窄块挂块级 key、不渲染端点命中带，块体点按可达（只选中）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [
          // 视觉宽 50ms ≈ 0.7px < 2×14dp：窄块（旧端点带覆盖整块的死区根因）。
          LocalMirrorFragment(startMs: 8000, endMs: 8050),
        ],
      );
      // 块级 key 定位（图标可缺时仍可定位块，依赖）。
      expect(find.byKey(const Key('mirror_fragment_0')), findsOneWidget);
      // 端点命中带不渲染。
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsNothing,
        reason: '窄块不渲染 start 端点命中带',
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_end')),
        findsNothing,
        reason: '窄块不渲染 end 端点命中带',
      );
      // 块体点按可达：点窄块中心 = 选中并取反启停（不再被端点带吞掉）。
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      await tester.tapAt(Offset(xOf(rect, 8025), rect.center.dy));
      await tester.pumpAndSettle();
      final sel = container.read(annotationSelectionProvider);
      expect(
        sel,
        isA<LocalMirrorFragmentSelection>(),
        reason: '窄块体点按直达块体层 = 只选中（消解死区）',
      );
      container.dispose();
    });

    testWidgets('窄块块体拖动可达：起手进入整体平移（端点带不再吞拖动起手）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 8050)],
      );
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      const deltaMs = 3000;
      await dragFromRight(
        tester,
        Offset(xOf(rect, 8025), rect.center.dy),
        xOf(rect, deltaMs) - xOf(rect, 0),
      );
      final f = container.read(localMirrorFragmentsProvider).single;
      expect(f.endMs - f.startMs, 50, reason: '窄块体拖动 = 整体平移，保持原宽');
      // 容差 2000ms = 拖动 slop（≈18px @ 800px/60s ≈ 1350ms）与起手吸附余量。
      expect(
        f.startMs,
        inInclusiveRange(8000 + deltaMs - 2000, 8000 + deltaMs),
        reason: '窄块块体拖动起手可达（旧端点带覆盖死区已消解）',
      );
      container.dispose();
    });

    testWidgets('阈值边界：块宽恰为 40dp 不算窄块，端点命中带仍在', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      );
      // 实测带几何 → 换算 40dp 对应毫秒（ceil + 1ms 补偿毫秒粒度/浮点
      // 误差，使块宽不小于阈值），经 restore 重设片段。
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      // 阈值毫秒按本带几何（内容区宽）换算。
      final narrowMs =
          (kLocalMirrorNarrowWidth *
                  total.inMilliseconds /
                  bandContentWidth(rect.width))
              .ceil();
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            AnnotationRestoreDocument(
              timeline: AnnotationTimeline.wholeVideo(total),
              localMirrorFragments: [
                LocalMirrorFragment(startMs: 8000, endMs: 8000 + narrowMs + 1),
              ],
            ),
          );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('mirror_fragment_0'))).width,
        moreOrLessEquals(kLocalMirrorNarrowWidth, epsilon: 0.05),
        reason: '前置：片段块宽恰达阈值（毫秒粒度内取上整）',
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsOneWidget,
        reason: 'width < 40 才是窄块：宽恰达 40dp 仍渲染端点带',
      );
      container.dispose();
    });

    testWidgets('非窄块端点命中带仍在、端点拖仍生效（start 拖只动 start）', (tester) async {
      final container = await pumpBandWithMirror(
        tester: tester,
        fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      );
      expect(find.byKey(const Key('mirror_fragment_0')), findsOneWidget);
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsOneWidget,
        reason: '宽块保留端点命中带',
      );
      expect(
        find.byKey(const Key('mirror_fragment_0_edge_end')),
        findsOneWidget,
      );
      // 从 start 端点带起手拖 +3000ms：start 动、end 不动。
      final rect = tester.getRect(find.byKey(const Key('track_mirror')));
      const deltaMs = 3000;
      await dragFromRight(
        tester,
        Offset(xOf(rect, 8000) + kLocalMirrorEdgeHitWidth / 2, rect.center.dy),
        xOf(rect, deltaMs) - xOf(rect, 0),
      );
      final f = container.read(localMirrorFragmentsProvider).single;
      expect(f.endMs, 16000, reason: '端点拖只动 start 端');
      expect(
        f.startMs,
        inInclusiveRange(8000 + deltaMs - 2000, 8000 + deltaMs),
        reason: 'start 端随手指右移（扣拖动 slop）',
      );
      container.dispose();
    });
  });

  group('两轨块几何与窄块判据同源', () {
    testWidgets('镜像块渲染像素 = 共用件 intervalBlockRect 求值（窗外裁切逐位一致）', (tester) async {
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 20),
        end: Duration(seconds: 40),
      );
      final session = buildTrackBandSession(engine: engine);
      final container = await pumpBandWithMirror(
        tester: tester,
        session: session,
        fragments: const [
          LocalMirrorFragment(startMs: 10000, endMs: 25000),
          LocalMirrorFragment(startMs: 30000, endMs: 35000),
        ],
      );
      session.updateWindow(win);
      await tester.pumpAndSettle();

      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      // 窗口起点 > 0 时让位收回，期望口径与渲染同读一份几何。
      final geometry =
          bandGeometryOf(total: total, window: win, width: bandRect.width);
      const windowMs = IntervalSpan(startMs: 20000, endMs: 40000);
      const spans = [
        IntervalSpan(startMs: 10000, endMs: 25000),
        IntervalSpan(startMs: 30000, endMs: 35000),
      ];
      for (var i = 0; i < spans.length; i++) {
        final expected = intervalBlockRect(
          span: spans[i],
          window: windowMs,
          trackWidth: geometry.contentWidth,
          contentLeft: geometry.contentLeft,
        )!;
        final rendered = tester.getRect(find.byKey(Key('mirror_fragment_$i')));
        expect(
          rendered.left - bandRect.left,
          closeTo(expected.left, 0.01),
          reason: '镜像片段 $i 左缘与共用件几何一致',
        );
        expect(
          rendered.width,
          closeTo(expected.width, 0.01),
          reason: '镜像片段 $i 宽与共用件几何一致（窗口外裁切）',
        );
      }
      // 第一条裁切后左缘恰贴可视窗口左缘（= 内容区左缘，让位
      // 收回后内容区左缘 = 带左缘）。
      expect(
        tester.getRect(find.byKey(const Key('mirror_fragment_0'))).left,
        bandRect.left + geometry.contentLeft,
      );
      container.dispose();
    });

    testWidgets('窗口起点带亚毫秒成分：两轨块像素差不超过零点几像素', (tester) async {
      // 起点 20s + 500µs：毫秒截断后两轨同窗求值，像素差 < 0.5px。
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 20, microseconds: 500),
        end: Duration(seconds: 40),
      );
      final session = buildTrackBandSession(engine: engine);
      final container = await pumpBandWithMirror(
        tester: tester,
        session: session,
        fragments: const [LocalMirrorFragment(startMs: 25000, endMs: 30000)],
        notes: const [NoteSticker(startMs: 25000, endMs: 30000)],
      );
      session.updateWindow(win);
      await tester.pumpAndSettle();

      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      final mirrorRect = tester.getRect(
        find.byKey(const Key('mirror_fragment_0')),
      );
      final noteRect = tester.getRect(find.byKey(const Key('note_fragment_0')));
      expect(
        mirrorRect.left - noteRect.left,
        lessThan(0.5),
        reason: '亚毫秒窗口起点下两轨块左缘像素差 < 0.5px',
      );
      expect(
        (mirrorRect.width - noteRect.width).abs(),
        lessThan(0.5),
        reason: '亚毫秒窗口起点下两轨块宽像素差 < 0.5px',
      );
      // 同源口径：两轨渲染像素都与共用件毫秒截断窗求值一致（< 0.5px）；
      // 内容区口径与渲染同读一份几何。
      final geometry =
          bandGeometryOf(total: total, window: win, width: bandRect.width);
      final expected = intervalBlockRect(
        span: const IntervalSpan(startMs: 25000, endMs: 30000),
        window: const IntervalSpan(startMs: 20000, endMs: 40000),
        trackWidth: geometry.contentWidth,
        contentLeft: geometry.contentLeft,
      )!;
      expect(mirrorRect.left - bandRect.left, closeTo(expected.left, 0.5));
      expect(mirrorRect.width, closeTo(expected.width, 0.5));
      container.dispose();
    });

    testWidgets('窄块：镜像轨端点带整段抑制、备注轨命中域让位到块外空隙', (tester) async {
      // 1s 块在 60s 满窗内 ≈ 十几像素（< 40dp 窄块阈值）：镜像轨端点带
      // 整段抑制（共用区域划分规则）；备注轨按分配规则把命中域
      // 让位到块外空隙、端点带照常给出。
      const win = TimelineWindow(
        total: total,
        start: Duration.zero,
        end: total,
      );
      final session = buildTrackBandSession(engine: engine);
      final container = await pumpBandWithMirror(
        tester: tester,
        session: session,
        fragments: const [LocalMirrorFragment(startMs: 1000, endMs: 2000)],
        notes: const [NoteSticker(startMs: 1000, endMs: 2000)],
      );
      session.updateWindow(win);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('mirror_fragment_0_edge_start')),
        findsNothing,
        reason: '镜像窄块端点带抑制',
      );
      expect(find.byKey(const Key('mirror_fragment_0_edge_end')), findsNothing);
      final noteRect = tester.getRect(find.byKey(const Key('note_fragment_0')));
      final startBand = tester.getRect(
        find.byKey(const Key('note_fragment_0_edge_start')),
      );
      final endBand = tester.getRect(
        find.byKey(const Key('note_fragment_0_edge_end')),
      );
      expect(
        startBand.right,
        closeTo(noteRect.left, 0.5),
        reason: '备注端点带让位到块外空隙（start 带贴块左缘外侧）',
      );
      expect(
        endBand.left,
        closeTo(noteRect.right, 0.5),
        reason: '备注端点带让位到块外空隙（end 带贴块右缘外侧）',
      );
      expect(startBand.left, greaterThanOrEqualTo(0), reason: '不越出带内左缘');
      container.dispose();
    });
  });
}
