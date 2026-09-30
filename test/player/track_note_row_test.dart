import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSelectionDomainProvider,
        annotationSaveSinkProvider,
        noteStickersProvider,
        selectedNoteFragmentIndexProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/note_editor.dart'
    show noteTextEditorTargetProvider;
import 'package:dance_learning_app/player/track_band_drag.dart';
import 'package:dance_learning_app/player/track_geometry.dart';
import 'package:dance_learning_app/player/track_note_row.dart';
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowRect;
import 'package:dance_learning_app/player/track_time.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';

class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 带级注入回调的记录器（本域直测断言「回调恰好触发一次」）。
class _RowCalls {
  int blankTaps = 0;
  int previewBegins = 0;
  int previewFrames = 0;
  int previewEnds = 0;
  bool mixedPinch = false;
  bool trackPinch = false;
}

/// 本域直测布景：**直接 pump 备注轨域**，
/// 只注本域必需的少数 provider（播放内核、保存 sink、节拍网格）——不造整条
/// 带的布景。行长与带宽取固定测试面（800 × 36）。
class _RowHarness {
  _RowHarness({
    required this.container,
    required this.total,
    required this.drag,
    required this.calls,
  });

  static const double width = 800;
  static const double height = 36;

  final ProviderContainer container;
  final Duration total;
  final TrackBandDragSession drag;
  final _RowCalls calls;

  /// 本行几何（轴 + 生效窗口）：与带同一口径（内容区左缘让出轨道片头带）。
  ({TimelineAxis axis, TimelineWindow window}) geometry(
    TimelineWindow? window, {
    Duration? geometryTotal,
  }) {
    final g = TrackBandGeometry.eval(
      total: geometryTotal ?? total,
      window: window,
      width: width,
      prefixWidth: kTrackPrefixWidth,
    );
    return (axis: g.axis, window: g.effectiveWindow);
  }

  /// 直接 pump 本模块。
  Future<void> pump(
    WidgetTester tester, {
    TimelineWindow? window,
    Duration? geometryTotal,
    int? highlightedStartMs,
    Map<String, int> rosterColors = const {},
  }) async {
    final g = geometry(window, geometryTotal: geometryTotal);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                height: height,
                child: TrackNoteRow(
                  input: TrackNoteRowInput(
                    notes: container.read(noteStickersProvider),
                    rowRect: const TrackRowRect(top: 0, height: height),
                    axis: g.axis,
                    window: g.window,
                    selectedIndex: container.read(
                      selectedNoteFragmentIndexProvider,
                    ),
                    highlightedStartMs: highlightedStartMs,
                    rosterColors: rosterColors,
                    drag: drag,
                    onBlankTapFallthrough: (_) => calls.blankTaps++,
                    mixedPinchBurst: () => calls.mixedPinch,
                    trackPinchActive: () => calls.trackPinch,
                    onDragPreviewBegin: () => calls.previewBegins++,
                    onDragPreviewFrame: (_) => calls.previewFrames++,
                    onDragPreviewEnd: () => calls.previewEnds++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 本行全局矩形（域与带同左缘、同宽：域内局部 x 即此处减去 [Rect.left]）。
  Rect rowRect(WidgetTester tester) =>
      tester.getRect(find.byType(TrackNoteRow));

  /// 时间 → 屏上 x（走共享测试入口，不重写换算公式）。
  double xOf(WidgetTester tester, Duration time, {TimelineWindow? window}) {
    final rect = rowRect(tester);
    return rect.left +
        bandXOf(time, total: total, width: rect.width, window: window);
  }

  /// 时间差 → 像素差。
  double pxFor(WidgetTester tester, Duration span, {TimelineWindow? window}) =>
      xOf(tester, span, window: window) - xOf(tester, Duration.zero, window: window);

  /// 在该行空白处点按一次。
  Future<void> tapAt(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pumpAndSettle();
  }
}

/// 起手一次水平拖动：先用一跳越过触摸 slop（起手点因此是确定的一处），再
/// 按 [dx] 精确推进——落点断言因此不依赖分步数与 slop 的巧合：相对平移的
/// 请求 = 片段（或端点）起点 + [dx] 换算的时间，与抓取点在块上的位置无关。
Future<void> _dragByExact(
  WidgetTester tester,
  Offset from,
  double dx,
) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 100));
  await gesture.moveBy(const Offset(kTouchSlop + 1, 0));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveBy(Offset(dx, 0));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  const total = Duration(minutes: 1);

  late _RecordingSaveSink sink;

  setUp(() {
    sink = _RecordingSaveSink();
  });

  /// 建布景：容器 + 拖动域句柄 + 回调记录器，并把备注文档恢复到容器。
  Future<_RowHarness> harness(
    WidgetTester tester, {
    required List<NoteSticker> notes,
    Duration rowTotal = total,
    Duration? geometryTotal,
    TimelineWindow? window,
  }) async {
    final rowEngine = FakePlaybackEngine(duration: rowTotal);
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(rowEngine),
        annotationSaveSinkProvider.overrideWithValue(sink),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) =>
              uniformReadyBeatState(seconds: rowTotal.inMilliseconds / 1000),
        ),
      ],
    );
    container.read(annotationEditorProvider).restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(rowTotal),
        notes: notes,
      ),
    );
    // 拖动域句柄：域的两族声明由本模块自己的登记点提交（不在本测试里拼）。
    final drag = TrackBandDragSession(
      families: TrackBandDragFamilies(),
      isPinchActive: () => false,
      isMixedBurstActive: () => false,
      loadGateActive: () => false,
      gestureStartRejected: (_) => false,
      promptOnReject: (_) {},
      bandWidth: () => _RowHarness.width,
    );
    final row = _RowHarness(
      container: container,
      total: geometryTotal ?? rowTotal,
      drag: drag,
      calls: _RowCalls(),
    );
    await row.pump(
      tester,
      window: window,
      geometryTotal: geometryTotal ?? rowTotal,
    );
    return row;
  }

  /// 同样式（框内文本具名字号）下整句的自然宽度（独立真源：测试侧自行
  /// 排版，不读实现）。
  double naturalWidth(String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(inherit: false, fontSize: kNoteInlineTextFontSize),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final width = tp.size.width;
    tp.dispose();
    return width;
  }

  RenderParagraph inlineParagraph(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(
        find
            .descendant(
              of: find.byKey(const ValueKey('note_fragment_0_text')),
              matching: find.byType(RichText),
            )
            .first,
      );

  group('框内文本三档退化', () {
    // 3 分钟片 + 2s 满窗：1s ≈ 380px，块宽可按毫秒精确摆布。
    const textTotal = Duration(minutes: 3);
    const textWindow = TimelineWindow(
      total: textTotal,
      start: Duration(seconds: 60),
      end: Duration(seconds: 62),
    );

    testWidgets('放得下全句：全显（不截断）', (tester) async {
      final row = await harness(
        tester,
        rowTotal: textTotal,
        notes: const [
          NoteSticker(startMs: 60000, endMs: 61000, text: '这里注意手腕'),
        ],
        window: textWindow,
      );
      expect(find.byKey(const ValueKey('note_fragment_0_text')), findsOneWidget);
      expect(
        inlineParagraph(tester).didExceedMaxLines,
        isFalse,
        reason: '放得下全句：整句显出、无省略号',
      );
      expect(find.text('这里注意手腕'), findsOneWidget);
      row.container.dispose();
    });

    testWidgets('放不下全句、放得下省略号：省略号截断', (tester) async {
      final row = await harness(
        tester,
        rowTotal: textTotal,
        notes: const [
          NoteSticker(startMs: 60000, endMs: 60100, text: '这里注意手腕'),
        ],
        // 2s 满窗下 100ms 块 ≈ 38px；扣内边距后可用宽落在
        // [省略号宽, 整句自然宽) 区间。
        window: textWindow,
      );
      final block = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0')),
      );
      final available = block.width - 2 * kNoteInlineTextHorizontalPadding;
      expect(available, greaterThanOrEqualTo(naturalWidth('…')));
      expect(available, lessThan(naturalWidth('这里注意手腕')));
      expect(find.byKey(const ValueKey('note_fragment_0_text')), findsOneWidget);
      expect(
        inlineParagraph(tester).didExceedMaxLines,
        isTrue,
        reason: '放不下全句：按实测宽度转省略号档',
      );
      expect(
        inlineParagraph(tester).size.width,
        lessThanOrEqualTo(available + 0.01),
        reason: '渲染宽不越出实测可用宽（量测与渲染同源）',
      );
      row.container.dispose();
    });

    testWidgets('连省略号也放不下：完全不显示内容', (tester) async {
      final row = await harness(
        tester,
        rowTotal: textTotal,
        notes: const [
          NoteSticker(startMs: 60000, endMs: 60015, text: '这里注意手腕'),
        ],
        window: textWindow,
      );
      final block = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0')),
      );
      expect(
        block.width - 2 * kNoteInlineTextHorizontalPadding,
        lessThanOrEqualTo(0),
        reason: '可用宽非正 = 「不显示」档的早退口径',
      );
      expect(find.byKey(const ValueKey('note_fragment_0_text')), findsNothing);
      expect(find.text('这里注意手腕'), findsNothing);
      row.container.dispose();
    });
  });

  group('端点柄的可达宽度与钳制', () {
    testWidgets('未选中：两端命中带 = 未选中带宽、贴在块外空隙内', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      final rect = row.rowRect(tester);
      final block = tester.getRect(find.byKey(const ValueKey('note_fragment_0')));
      final startBand = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0_edge_start')),
      );
      final endBand = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0_edge_end')),
      );
      expect(startBand.width, kNoteEdgeHitWidth);
      expect(endBand.width, kNoteEdgeHitWidth);
      expect(startBand.right, closeTo(block.left, 0.5), reason: '起点带贴块左缘外侧');
      expect(endBand.left, closeTo(block.right, 0.5), reason: '终点带贴块右缘外侧');
      expect(startBand.left, greaterThanOrEqualTo(rect.left - 0.5));
      expect(endBand.right, lessThanOrEqualTo(rect.right + 0.5));
      row.container.dispose();
    });

    testWidgets('选中：两端给端点柄、命中带更长，柄条落在自身命中带内', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      expect(find.byKey(const ValueKey('note_fragment_0_handle_start')), findsNothing);

      row.container
          .read(annotationSelectionDomainProvider)
          .select(NoteFragmentSelection(0));
      await row.pump(tester);

      final startBand = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0_edge_start')),
      );
      final endBand = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0_edge_end')),
      );
      expect(startBand.width, kNoteSelectedEdgeHitWidth);
      expect(endBand.width, kNoteSelectedEdgeHitWidth);
      final handle = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0_handle_start')),
      );
      expect(startBand.contains(handle.center), isTrue, reason: '所见即所拖');
      row.container.dispose();
    });

    testWidgets('贴邻片段冲突让位：朝向邻块的一侧带宽为 0（不渲染）', (tester) async {
      final row = await harness(
        tester,
        notes: const [
          NoteSticker(startMs: 10000, endMs: 18000),
          NoteSticker(startMs: 18000, endMs: 26000),
        ],
      );
      expect(
        find.byKey(const ValueKey('note_fragment_0_edge_end')),
        findsNothing,
        reason: '右邻贴邻（半开共享端点）→ end 侧无空隙、整段让出',
      );
      expect(
        find.byKey(const ValueKey('note_fragment_1_edge_start')),
        findsNothing,
        reason: '左邻贴邻 → start 侧整段让出',
      );
      row.container.dispose();
    });

    testWidgets('贴带缘不越界：块外空隙不足时端点带宽按可用空间收窄', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 1000, endMs: 7000)],
      );
      final rect = row.rowRect(tester);
      final startBand = tester.getRect(
        find.byKey(const ValueKey('note_fragment_0_edge_start')),
      );
      final block = tester.getRect(find.byKey(const ValueKey('note_fragment_0')));
      expect(startBand.left, greaterThanOrEqualTo(rect.left - 0.5));
      expect(
        startBand.width,
        lessThan(kNoteEdgeHitWidth),
        reason: '块左缘外空隙不足一整条带宽时按可用空间收窄',
      );
      expect(startBand.right, closeTo(block.left, 0.5));
      row.container.dispose();
    });
  });

  group('两族拖动的落点相对平移', () {
    testWidgets('整体移：请求 = 片段起点 + 手指位移（相对平移、宽度不变）', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      expect(row.calls.previewBegins, 0);
      // 抓在块中段（14s）右移 2.5s（就绪网格 0.5s 的整倍数 → 落点可精确
      // 断言：相对平移的请求 = 起点 + 位移，与抓取点无关）。
      await _dragByExact(
        tester,
        Offset(row.xOf(tester, const Duration(seconds: 14)), 18),
        row.pxFor(tester, const Duration(milliseconds: 2500)),
      );
      final note = row.container
          .read(noteStickersProvider)
          .single;
      expect(note.startMs, 12500, reason: '请求 = 起点 + 手指位移（抓取偏移守恒）');
      expect(note.endMs - note.startMs, 8000, reason: '整体移保持原宽');
      expect(row.calls.previewBegins, 1, reason: '起手视觉恰好一次');
      expect(row.calls.previewEnds, 1, reason: '收口视觉恰好一次');
      row.container.dispose();
    });

    testWidgets('端点拖：只改被拖端点，落点同样相对平移', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      final blockLeft = row.xOf(tester, const Duration(seconds: 10));
      await _dragByExact(
        tester,
        Offset(blockLeft - kNoteEdgeHitWidth / 2, 18),
        row.pxFor(tester, const Duration(milliseconds: 2500)),
      );
      final note = row.container
          .read(noteStickersProvider)
          .single;
      expect(note.startMs, 12500, reason: '端点拖请求 = 端点 + 手指位移');
      expect(note.endMs, 18000, reason: '另一端不动');
      row.container.dispose();
    });

    testWidgets('内容锁：起手静默不参与、不建会话', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      await _dragByExact(
        tester,
        Offset(row.xOf(tester, const Duration(seconds: 14)), 18),
        row.pxFor(tester, const Duration(seconds: 3)),
      );
      expect(
        row.container.read(noteStickersProvider).single,
        const NoteSticker(startMs: 10000, endMs: 18000, locked: true),
      );
      expect(row.calls.previewBegins, 0, reason: '未起手：不驱动画面预览');
      row.container.dispose();
    });
  });

  group('行级点按与长按', () {
    testWidgets('单击选中、再单击已选中 = 打开编辑器（编辑器以备注起点标识目标）', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
      );
      final x = row.xOf(tester, const Duration(seconds: 14));
      await row.tapAt(tester, Offset(x, 18));
      expect(
        row.container.read(annotationSelectionProvider),
        isA<NoteFragmentSelection>().having((s) => s.index, 'index', 0),
      );
      expect(row.calls.blankTaps, 0, reason: '片段命中不是空白：不落穿');

      await row.pump(tester);
      await row.tapAt(tester, Offset(x, 18));
      expect(
        row.container.read(noteTextEditorTargetProvider),
        10000,
        reason: '再单击已选中的片段 = 打开编辑器',
      );
      expect(row.container.read(annotationSelectionProvider), isNull);
      row.container.dispose();
    });

    testWidgets('长按切内容锁（解锁再长按复位）', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      final x = row.xOf(tester, const Duration(seconds: 14));
      await tester.longPressAt(Offset(x, 18));
      await tester.pumpAndSettle();
      expect(
        row.container.read(noteStickersProvider).single.locked,
        isTrue,
      );
      await tester.longPressAt(Offset(x, 18));
      await tester.pumpAndSettle();
      expect(
        row.container.read(noteStickersProvider).single.locked,
        isFalse,
      );
      row.container.dispose();
    });

    testWidgets('轨道空白单击落穿到带级仲裁（回调恰好一次）', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      await row.tapAt(
        tester,
        Offset(row.xOf(tester, const Duration(seconds: 40)), 18),
      );
      expect(row.calls.blankTaps, 1);
      expect(row.container.read(annotationSelectionProvider), isNull);
      row.container.dispose();
    });
  });

  group('选择簿记（域归属的两条自动清选）', () {
    testWidgets('窗口平移离场即清选', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      );
      row.container
          .read(annotationSelectionDomainProvider)
          .select(NoteFragmentSelection(0));
      await row.pump(tester);
      expect(
        row.container.read(annotationSelectionProvider),
        isA<NoteFragmentSelection>(),
      );
      // 窗口平移到 30–40s：这条备注整段离场（选中框与展开浮条没有承载物）。
      await row.pump(
        tester,
        window: const TimelineWindow(
          total: total,
          start: Duration(seconds: 30),
          end: Duration(seconds: 40),
        ),
      );
      expect(row.container.read(annotationSelectionProvider), isNull);
      row.container.dispose();
    });

    test('播放头越过自身时间窗即清选（域公开簿记入口；走进窗内不清）', () {
      // 播放头一路的触发是带级位置 tick（帧步进 / 微调 scrub / 预览线拖动
      // 的写点不算），故它是域公开的簿记入口而不是本域订阅的显示值：判定与
      // 写点在这里，带侧只提供触发与现势读数。
      const notes = [NoteSticker(startMs: 10000, endMs: 18000)];
      var clears = 0;
      void judge(Duration previous, Duration next) =>
          noteRowClearSelectionIfPlayheadLeftOwnWindow(
            notes: notes,
            selectedIndex: 0,
            previous: previous,
            next: next,
            clearSelection: () => clears++,
          );

      // 从窗外走进窗内：不是「跨越出窗」，不清（在播时点选播放头不在其中的
      // 片段是常规操作）。
      judge(const Duration(seconds: 2), const Duration(seconds: 12));
      expect(clears, 0);
      // 窗内推进：不清。
      judge(const Duration(seconds: 12), const Duration(seconds: 17));
      expect(clears, 0);
      // 越过 18s 尾缘 → 离开自身时间窗：清一次。
      judge(const Duration(seconds: 17), const Duration(seconds: 20));
      expect(clears, 1);
      // 未选中 / 索引越界：空操作。
      noteRowClearSelectionIfPlayheadLeftOwnWindow(
        notes: notes,
        selectedIndex: null,
        previous: const Duration(seconds: 17),
        next: const Duration(seconds: 20),
        clearSelection: () => clears++,
      );
      noteRowClearSelectionIfPlayheadLeftOwnWindow(
        notes: notes,
        selectedIndex: 7,
        previous: const Duration(seconds: 17),
        next: const Duration(seconds: 20),
        clearSelection: () => clears++,
      );
      expect(clears, 1);
    });
  });

  group('退化输入', () {
    testWidgets('空列表：不渲染块体，整行点按落穿带级仲裁', (tester) async {
      final row = await harness(tester, notes: const []);
      expect(find.byKey(const ValueKey('note_fragment_0')), findsNothing);
      await row.tapAt(tester, Offset(row.xOf(tester, const Duration(seconds: 5)), 18));
      expect(row.calls.blankTaps, 1);
      row.container.dispose();
    });

    testWidgets('窗口不含该片段：不渲染块体、点按为空白', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
        window: const TimelineWindow(
          total: total,
          start: Duration(seconds: 30),
          end: Duration(seconds: 40),
        ),
      );
      expect(find.byKey(const ValueKey('note_fragment_0')), findsNothing);
      await row.tapAt(tester, Offset(row.xOf(tester, const Duration(seconds: 35)), 18));
      expect(row.calls.blankTaps, 1);
      row.container.dispose();
    });

    testWidgets('几何不可用（总时长未知）：整行安静不渲染、不参与命中', (tester) async {
      final row = await harness(
        tester,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
        geometryTotal: Duration.zero,
      );
      expect(find.byKey(const ValueKey('note_fragment_0')), findsNothing);
      expect(find.byKey(const ValueKey('note_fragment_0_text')), findsNothing);
      // 域自身不吸收命中（子树空）：带级手势层照常接住这次点按，故本域
      // 的落穿回调不被调用。
      await row.tapAt(tester, Offset(row.xOf(tester, const Duration(seconds: 5)), 18));
      expect(row.calls.blankTaps, 0);
      row.container.dispose();
    });
  });
}
