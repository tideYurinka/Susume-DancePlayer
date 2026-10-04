/// 轨道手柄带域模块级套件。
///
/// 直测接缝只开在模块自己的 widget 边界上：直接 pump 本模块、只给它那一个
/// 输入值对象（几何与选中事实 + 该层回调 + 拖动域句柄）。断言的都是外部可
/// 观察事实——三类手柄的槽位与摆位、把手取色、点按选中/端标选中、拖动经
/// 拖动域句柄的落点回写与实时预览钩子、键盘微调与焦点描边、预览线接管
/// 三段式（本域仍以回调注入）、两族声明经按族入口登记进拖动域。
///
/// 唯一的容器注入是 `ProviderScope`：控制柄承载的角标锚点包装件
/// （`GuideAnchor`）自带它，本域自身不读 provider、不碰容器句柄。
library;

import 'package:dance_learning_app/annotation/segment_line.dart'
    show SegmentLine;
import 'package:dance_learning_app/help/guide_anchor.dart' show GuideAnchor;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationGestureTarget, DurationDragSession;
import 'package:dance_learning_app/player/annotation_selection.dart'
    show VideoRangeBoundary;
import 'package:dance_learning_app/player/track_band_drag.dart';
import 'package:dance_learning_app/player/track_handle_strip.dart';
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowId, TrackRowTable;
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假模块拖动会话：记录每一次 [moveTo] 的请求，按落点原样返回（非空 ⇒ 逐帧
/// 落点钩子触发一次）。
class _FakeDragSession implements DurationDragSession {
  final List<Duration> requests = <Duration>[];
  int ends = 0;

  @override
  Duration? moveTo(Duration target) {
    requests.add(target);
    return target;
  }

  @override
  void end() => ends++;
}

/// 域 + 输入值对象的一次装配：记录器收全部回调事实，拖动域用真件（两族声明
/// 由被 pump 的模块自己经按族入口登记）。
class _Harness {
  _Harness() {
    dragDomain = TrackBandDragSession(
      families: families,
      isPinchActive: () => pinchActive,
      isMixedBurstActive: () => false,
      loadGateActive: () => false,
      gestureStartRejected: (target) => rejected.contains(target),
      promptOnReject: prompts.add,
      bandWidth: () => 800,
    );
  }

  final families = TrackBandDragFamilies();
  late final TrackBandDragSession dragDomain;

  bool pinchActive = false;
  final rejected = <AnnotationGestureTarget>{};
  final prompts = <AnnotationGestureTarget>[];

  /// 分段线会话工厂交回的真件（族声明里 beginSession 的产物）。
  _FakeDragSession? segmentSession;
  _FakeDragSession? rangeSession;
  final begunSegments = <int>[];
  final begunBoundaries = <VideoRangeBoundary>[];

  /// 逐帧落点钩子收到的落点与实时预览起手/收口次数。
  final previewFrames = <Duration>[];
  int previewBegins = 0;
  int previewEnds = 0;

  /// 视觉簿记：带级收到「拖动中线下标」的交回值（null = 收口）与首尾端标
  /// 拖动在场事实。
  final dragVisuals = <int?>[];
  final rangeDragActive = <bool>[];

  /// 点按与键盘微调事实。
  final tappedSegments = <int>[];
  final tappedBoundaries = <VideoRangeBoundary>[];
  final nudgedSegments = <(int, int)>[];
  final nudgedBoundaries = <(VideoRangeBoundary, int)>[];

  /// 最近线解析的答案（null = 未命中，回落命中层下标）。
  int? nearest;

  /// 第九族（预览线拖动）在测试里的装配（与带级同形）：无模块事务，准入读
  /// 起手的带内局部 x，换算与落点、收口三条钩子记录事实。
  void registerPreviewLineFamily() {
    families.register(
      AnnotationGestureTarget.previewLineDrag,
      TrackBandDragDeclaration(
        toTime: (localX, bandWidth) {
          takeoverTargets.add((localX, bandWidth));
          return Duration(milliseconds: localX.round());
        },
        admit: (target, localX) {
          takeoverAdmits.add(localX);
          return takeOverBegin;
        },
        onBegin: (_) => takeoverBegins++,
        onFrame: takeoverFrames.add,
        onEnd: () => takeoverEnds++,
      ),
    );
  }

  /// 第九族被接下（准入通过）与逐帧/收口事实。
  bool takeOverBegin = false;
  int takeoverBegins = 0;
  final takeoverAdmits = <double>[];
  final takeoverTargets = <(double, double)>[];
  final takeoverFrames = <Duration>[];
  int takeoverEnds = 0;

  TrackHandleStripInput input({
    List<SegmentLine> segmentLines = const <SegmentLine>[
      SegmentLine(position: Duration(milliseconds: 5000)),
    ],
    double bandWidth = 800,
    double contentLeft = 0,
    TimelineWindow? window,
    int? selectedSegmentLineIndex,
    int? draggingSegmentLineIndex,
    int? segmentSelectIndex,
  }) {
    final win =
        window ??
        TimelineWindow(
          total: Duration(milliseconds: 10_000),
          start: Duration.zero,
          end: Duration(milliseconds: 10_000),
        );
    return TrackHandleStripInput(
      rowRect: TrackRowTable.normal.rectOf(TrackRowId.handleStrip),
      axis: TimelineAxis(
        total: Duration(milliseconds: 10_000),
        width: bandWidth,
        contentLeft: contentLeft,
        window: win,
      ),
      window: win,
      bandWidth: bandWidth,
      segmentLines: segmentLines,
      rangeStart: Duration.zero,
      rangeEnd: Duration(milliseconds: 10_000),
      selectedSegmentLineIndex: selectedSegmentLineIndex,
      draggingSegmentLineIndex: draggingSegmentLineIndex,
      segmentSelectIndex: segmentSelectIndex,
      dragDomain: dragDomain,
      segmentToTime: (localX, width) => Duration(milliseconds: localX.round()),
      rangeToTime: (localX, width) => Duration(milliseconds: localX.round()),
      beginSegmentLineSession: (index) {
        begunSegments.add(index);
        return segmentSession ??= _FakeDragSession();
      },
      beginRangeSession: (boundary) {
        begunBoundaries.add(boundary);
        return rangeSession ??= _FakeDragSession();
      },
      onSegmentLineDragVisual: dragVisuals.add,
      onRangeDragActive: rangeDragActive.add,
      onBeginLineDragPreview: () => previewBegins++,
      onLineDragPreviewFrame: previewFrames.add,
      onEndLineDragPreview: () => previewEnds++,
      bandLocalX: (globalPosition) => globalPosition.dx,
      resolveSegmentLineIndex: (_) => nearest,
      onSegmentHandleTap: tappedSegments.add,
      onRangeHandleTap: tappedBoundaries.add,
      onSegmentHandleNudge: (index, direction) =>
          nudgedSegments.add((index, direction)),
      onRangeHandleNudge: (boundary, direction) =>
          nudgedBoundaries.add((boundary, direction)),
    );
  }
}

/// 模块的盒子 = 整条带（带侧 `Positioned.fill`）：测试里给同一个尺寸，
/// 于是把手的屏上坐标与带内坐标同值。
final double _bandHeight = TrackRowTable.normal.totalHeight;

Future<void> _pump(WidgetTester tester, TrackHandleStripInput input) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 800,
            height: _bandHeight,
            child: TrackHandleStrip(input: input),
          ),
        ),
      ),
    ),
  );
}

/// 把手上控制柄胶囊的屏上矩形（位置键即胶囊键）。
Rect _barRect(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

/// 位置键下那枚胶囊的填充色。
Color _barColor(WidgetTester tester, Key key) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(of: find.byKey(key), matching: find.byType(DecoratedBox))
        .first,
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  const startKey = Key('video_range_start_marker');
  const endKey = Key('video_range_end_marker');
  const segment0Key = Key('segment_line_0_handle');

  group('三类手柄的槽位与摆位', () {
    testWidgets('首/尾线各一枚控制柄：槽贴带缘、把手条宽随槽、行内垂直居中', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      final rowRect = TrackRowTable.normal.rectOf(TrackRowId.handleStrip);

      // 线心 x = 0 / 400 / 800（带宽 800、窗口全片、内容区占满）。
      // 首线槽 = [0, 与邻线中点 200) ∩ [线心−24, 线心+24] = [0,24] →
      // 条宽 min(32, 24) = 24、左缘顶到带左缘。
      final start = _barRect(tester, startKey);
      expect(start.left, 0);
      expect(start.width, 24);
      expect(start.height, 18);
      expect(start.top, rowRect.top + (rowRect.height - 18) / 2);

      // 尾线槽 = [中点 600, 带右缘 800] ∩ [776, 824] = [776, 800] →
      // 条宽 24、右缘顶到带右缘。
      final end = _barRect(tester, endKey);
      expect(end.right, 800);
      expect(end.width, 24);
      expect(end.top, start.top);

      // 分段线（5000ms → x = 400）：两侧都空 ⇒ 槽保目标宽 48、把手 32 居中。
      final segment = _barRect(tester, segment0Key);
      expect(segment.center.dx, 400);
      expect(segment.width, 32);
      expect(segment.top, start.top);
    });

    testWidgets('槽位互斥分区：密排线槽被两侧中点截断、把手随槽收窄且不重叠', (tester) async {
      final harness = _Harness();
      // 2500ms → x=200、2600ms → x=208：两点中点 204 截断两条槽。
      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 2500)),
            SegmentLine(position: Duration(milliseconds: 2600)),
          ],
        ),
      );
      final first = _barRect(tester, segment0Key);
      final second = _barRect(tester, const Key('segment_line_1_handle'));
      expect(first.width, 28, reason: '槽宽 28 → 条取 min(32, 槽宽)');
      expect(second.width, 28);
      expect(first.right, closeTo(second.left, 0.001), reason: '互斥不重叠');
    });

    testWidgets('放大后间距增大：槽恢复目标宽、把手恢复 32', (tester) async {
      final harness = _Harness();
      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 2500)),
            SegmentLine(position: Duration(milliseconds: 2600)),
          ],
        ),
      );
      final dense = _barRect(tester, segment0Key);

      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 2500)),
            SegmentLine(position: Duration(milliseconds: 2600)),
          ],
          window: TimelineWindow(
            total: Duration(milliseconds: 10_000),
            start: Duration(milliseconds: 2000),
            end: Duration(milliseconds: 3000),
          ),
        ),
      );
      final zoomed = _barRect(tester, segment0Key);
      expect(zoomed.width, 32);
      expect(zoomed.width, greaterThan(dense.width));
    });

    testWidgets('线不在窗口内即不渲染其控制柄（槽位仍受它约束）', (tester) async {
      final harness = _Harness();
      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 12_000)),
          ],
        ),
      );
      expect(find.byKey(startKey), findsOneWidget);
      expect(find.byKey(endKey), findsOneWidget);
      expect(find.byKey(segment0Key), findsNothing);
    });
  });

  group('点按选中与端标选中', () {
    testWidgets('点按分段线控制柄：最近线解析的答案交回该层回调', (tester) async {
      final harness = _Harness();
      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 2500)),
            SegmentLine(position: Duration(milliseconds: 7500)),
          ],
        ),
      );
      harness.nearest = 1;
      await tester.tap(find.byKey(segment0Key));
      expect(harness.tappedSegments, [1], reason: '密集线重叠时取解析答案而不是命中层下标');
    });

    testWidgets('点按分段线控制柄：未命中即回落命中层携带的下标', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      harness.nearest = null;
      await tester.tap(find.byKey(segment0Key));
      expect(harness.tappedSegments, [0]);
    });

    testWidgets('点按首/尾线控制柄：端别原样交回该层回调', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      await tester.tap(find.byKey(startKey));
      await tester.tap(find.byKey(endKey));
      expect(harness.tappedBoundaries, [
        VideoRangeBoundary.start,
        VideoRangeBoundary.end,
      ]);
    });
  });

  group('两族拖动经拖动域句柄', () {
    testWidgets('两族声明经按族入口登记进拖动域：门禁目标与提示开关逐位一致', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());

      expect(harness.families.gates, [
        AnnotationGestureTarget.segmentLineMove,
        AnnotationGestureTarget.rangeBoundaryDrag,
      ]);
      for (final gate in harness.families.gates) {
        expect(
          harness.families.declarationFor(gate)?.promptOnGateReject,
          isTrue,
          reason: '两族被门禁拒时都弹一次提示',
        );
      }
    });

    testWidgets('分段线拖动：落点回写、视觉簿记与实时预览钩子按声明各一次', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());

      harness.nearest = 0;
      await tester.drag(find.byKey(segment0Key), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(harness.begunSegments, [0], reason: '起手经族声明的会话工厂');
      expect(harness.dragVisuals, [0, null], reason: '起手/收口的视觉簿记各交回一次');
      expect(harness.previewBegins, 1);
      expect(harness.previewEnds, greaterThanOrEqualTo(1));
      expect(
        harness.segmentSession!.requests,
        isNotEmpty,
        reason: '逐帧经域句柄落点回写',
      );
      expect(harness.segmentSession!.ends, 1, reason: '收口经域句柄且幂等一次');
      expect(harness.previewFrames, isNotEmpty, reason: '写后真实落点驱动实时预览');
    });

    testWidgets('起手按下位置用于最近线解析（不是过 slop 后的位置）', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());

      harness.nearest = 0;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(segment0Key)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      harness.nearest = 0;
      await gesture.up();
      await tester.pumpAndSettle();

      expect(harness.begunSegments, [0]);
    });

    testWidgets('首尾端标拖动：落点回写与收口按声明走', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());

      await tester.drag(find.byKey(startKey), const Offset(60, 0));
      await tester.pumpAndSettle();

      expect(harness.begunBoundaries, [VideoRangeBoundary.start]);
      expect(harness.rangeSession!.requests, isNotEmpty);
      expect(harness.rangeSession!.ends, 1);
      expect(harness.previewBegins, 1);
      expect(harness.previewEnds, greaterThanOrEqualTo(1));
    });

    testWidgets('门禁拒绝起手：不建会话、弹一次提示、收口照旧收实时预览', (tester) async {
      final harness = _Harness();
      harness.rejected.add(AnnotationGestureTarget.segmentLineMove);
      await _pump(tester, harness.input());

      harness.nearest = 0;
      await tester.drag(find.byKey(segment0Key), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(harness.prompts, [AnnotationGestureTarget.segmentLineMove]);
      expect(harness.begunSegments, isEmpty);
      expect(harness.previewBegins, 0);
      expect(harness.dragVisuals, [null], reason: '无会话可收时视觉照旧清一次');
      expect(harness.previewEnds, greaterThanOrEqualTo(1));
    });

    testWidgets('双指在场让位：不建会话、不留痕（视觉收尾照旧）', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      harness.pinchActive = true;

      harness.nearest = 0;
      await tester.drag(find.byKey(segment0Key), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(harness.begunSegments, isEmpty);
      expect(harness.dragVisuals, [null]);
    });
  });

  group('预览线拖动族（第九族）', () {
    testWidgets('起手被这一族接下：不进既有拖线逻辑，逐帧与收口只经它', (tester) async {
      final harness = _Harness()..takeOverBegin = true;
      harness.registerPreviewLineFamily();
      await _pump(tester, harness.input());

      harness.nearest = 0;
      await tester.drag(find.byKey(segment0Key), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(harness.takeoverAdmits, isNotEmpty, reason: '准入读起手的带内局部 x');
      expect(harness.takeoverBegins, 1);
      expect(harness.begunSegments, isEmpty, reason: '接管后不进既有拖线逻辑');
      expect(harness.takeoverTargets, isNotEmpty, reason: '逐帧交回那一族的换算');
      expect(harness.takeoverFrames, isNotEmpty);
      expect(harness.takeoverEnds, 1, reason: '抬指收口一次');
      expect(harness.dragVisuals, [null], reason: '视觉收尾照旧清一次');
    });

    testWidgets('起手未接下（准入拒绝 / 这一族没人接）：既有拖线逻辑照常', (tester) async {
      // 拒绝的一条：族登记了但准入否决。
      final refused = _Harness();
      refused.registerPreviewLineFamily();
      await _pump(tester, refused.input());

      refused.nearest = 0;
      await tester.drag(find.byKey(segment0Key), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(refused.begunSegments, [0]);
      expect(refused.segmentSession!.requests, isNotEmpty);
      expect(refused.takeoverBegins, 0);
      expect(refused.takeoverFrames, isEmpty);

      // 未登记的一条：这一族没人接（域内「未注册的族起手为空」在带级的表现）。
      final nobody = _Harness();
      await _pump(tester, nobody.input());

      nobody.nearest = 0;
      await tester.drag(find.byKey(segment0Key), const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(nobody.begunSegments, [0]);
      expect(nobody.segmentSession!.requests, isNotEmpty);
    });
  });

  group('端点键盘微调件', () {
    testWidgets('分段线控制柄：左右方向键各交回一次微调方向', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      await tester.tap(find.byKey(segment0Key));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(harness.nudgedSegments, [(0, 1), (0, -1)]);
    });

    testWidgets('首/尾线控制柄：方向键各交回端别与方向', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      await tester.tap(find.byKey(startKey));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);

      expect(harness.nudgedBoundaries, [(VideoRangeBoundary.start, -1)]);
    });

    testWidgets('落焦才叠出焦点描边：与把手同几何、外扩 2dp', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      const ringKey = Key('video_range_start_focus_ring');
      expect(find.byKey(ringKey), findsNothing);

      await tester.tap(find.byKey(startKey));
      await tester.pump();

      expect(find.byKey(ringKey), findsOneWidget);
      final ring = tester.getRect(find.byKey(ringKey));
      final bar = _barRect(tester, startKey);
      expect(ring.left, bar.left - 2);
      expect(ring.width, bar.width + 4);
      expect(ring.height, bar.height + 4);
    });
  });

  group('带级事实驱动观感与锚点', () {
    testWidgets('分段线把手取色：默认 / 选中 / 拖动中 / flag 四档', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      final plain = _barColor(tester, segment0Key);

      await _pump(tester, harness.input(selectedSegmentLineIndex: 0));
      final selected = _barColor(tester, segment0Key);
      expect(selected, isNot(plain));

      await _pump(tester, harness.input(draggingSegmentLineIndex: 0));
      expect(_barColor(tester, segment0Key), selected, reason: '拖动中与选中同档色');

      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 5000), flagged: true),
          ],
        ),
      );
      final flagged = _barColor(tester, segment0Key);
      expect(flagged, isNot(plain));
      expect(flagged, isNot(selected));
    });

    testWidgets('首/尾线把手取色：起始与结束各一档', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      expect(_barColor(tester, startKey), isNot(_barColor(tester, endKey)));
    });

    testWidgets('引导锚点：第 0 条柄恒承载「编辑态上手第一条」，本会话新落线序号另包一枚', (tester) async {
      final harness = _Harness();
      await _pump(tester, harness.input());
      Finder anchorsOf(String key) => find.byWidgetPredicate(
        (widget) => widget is GuideAnchor && widget.anchorKey == key,
      );
      expect(anchorsOf('segment_line_0_handle'), findsOneWidget);
      expect(anchorsOf('segment_line_1_handle'), findsNothing);

      await _pump(
        tester,
        harness.input(
          segmentLines: const <SegmentLine>[
            SegmentLine(position: Duration(milliseconds: 2500)),
            SegmentLine(position: Duration(milliseconds: 7500)),
          ],
          segmentSelectIndex: 1,
        ),
      );
      expect(anchorsOf('segment_line_0_handle'), findsOneWidget);
      expect(anchorsOf('segment_line_1_handle'), findsOneWidget);
    });
  });
}
