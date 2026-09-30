/// 区间片段行块体骨架直测：给定块矩形与行
/// 矩形渲染出的摆位与层序（块体层 → 载荷层 → 端点带层）、端点带宽为 `0`
/// 时不渲染该侧、四个水平拖动回调的挂法、以及键全部由调用点提供。
///
/// 直接 pump 本件（只注一个 `MaterialApp` 布景），不牵整条轨道带。
library;

import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/help/guide_anchor.dart' show GuideAnchor;
import 'package:dance_learning_app/player/track_fragment_row_shell.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stack_paint_order.dart';

void main() {
  const blockKey = Key('shell_block');
  const payloadKey = Key('shell_payload');
  const bodyKey = Key('shell_body');
  const originKey = Key('shell_origin');
  const edgeChildKey = Key('shell_edge_inner');
  const rowRect = TrackRowRect(top: 12, height: 36);
  const block = IntervalBlockRect(left: 120, width: 60);

  Key edgeKeyOf(IntervalEdge edge) => Key('shell_edge_${edge.name}');

  /// 布景：一个铺满屏幕的 Stack（带 `originKey` 参照）里放一块骨架。
  ///
  /// [withVerticalCompetitor] 在骨架之上再挂一个纵向拖动识别器：手势要能
  /// 被打断，竞技场里就必须有第二个参与者（只有一个识别器时它按下即胜出，
  /// 拖动不再是「可能态」，取消走的就是收口而不是 cancel）。
  Widget harness({
    IntervalBlockRect blockRect = block,
    TrackRowRect row = rowRect,
    double startBand = 0,
    double endBand = 0,
    bool outward = false,
    bool withVerticalCompetitor = false,
    String? guideAnchorKey,
    List<Widget> payload = const [],
    Widget? edgeChild,
    void Function(DragStartDetails details)? onMoveDragStart,
    void Function(IntervalEdge edge, DragStartDetails details)? onEdgeDragStart,
    void Function(DragUpdateDetails details)? onDragUpdate,
    VoidCallback? onDragEnd,
    VoidCallback? onDragCancel,
  }) {
    final stack = Stack(
      children: [
        const Positioned.fill(child: SizedBox(key: originKey)),
        TrackFragmentRowShell(
          blockKey: blockKey,
          block: blockRect,
          rowRect: row,
          startEdgeBandWidth: startBand,
          endEdgeBandWidth: endBand,
          edgeBandsOutward: outward,
          body: const SizedBox.expand(key: bodyKey),
          payload: payload,
          edgeBandChild: edgeChild == null ? null : (_) => edgeChild,
          edgeKey: edgeKeyOf,
          guideAnchorKey: guideAnchorKey,
          onMoveDragStart: onMoveDragStart ?? (_) {},
          onEdgeDragStart: onEdgeDragStart ?? (_, _) {},
          onDragUpdate: onDragUpdate ?? (_) {},
          onDragEnd: onDragEnd ?? () {},
          onDragCancel: onDragCancel ?? () {},
        ),
      ],
    );
    return MaterialApp(
      home: withVerticalCompetitor
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragStart: (_) {},
              child: stack,
            )
          : stack,
    );
  }

  Offset originOf(WidgetTester tester) =>
      tester.getTopLeft(find.byKey(originKey));

  group('摆位', () {
    testWidgets('块体矩形 = 块矩形横向 + 行矩形纵向（贴块内侧不扩展外层）', (tester) async {
      await tester.pumpWidget(harness(startBand: 24));
      final origin = originOf(tester);
      expect(
        tester.getRect(find.byKey(blockKey)),
        Rect.fromLTWH(
          origin.dx + block.left,
          origin.dy + rowRect.top,
          block.width,
          rowRect.height,
        ),
      );
    });

    testWidgets('贴块外侧：外层铺到块 ± 两侧带宽，块体仍在原块矩形上', (tester) async {
      await tester.pumpWidget(
        harness(startBand: 24, endBand: 16, outward: true),
      );
      final origin = originOf(tester);
      expect(
        tester.getRect(find.byKey(blockKey)),
        Rect.fromLTWH(
          origin.dx + block.left,
          origin.dy + rowRect.top,
          block.width,
          rowRect.height,
        ),
      );
      expect(
        tester.getRect(find.byKey(edgeKeyOf(IntervalEdge.start))),
        Rect.fromLTWH(
          origin.dx + block.left - 24,
          origin.dy + rowRect.top,
          24,
          rowRect.height,
        ),
      );
      expect(
        tester.getRect(find.byKey(edgeKeyOf(IntervalEdge.end))),
        Rect.fromLTWH(
          origin.dx + block.left + block.width,
          origin.dy + rowRect.top,
          16,
          rowRect.height,
        ),
      );
    });

    testWidgets('贴块内侧：端点带叠在块内两端（带体宽度逐位不变）', (tester) async {
      await tester.pumpWidget(harness(startBand: 24, endBand: 16));
      final origin = originOf(tester);
      expect(
        tester.getRect(find.byKey(edgeKeyOf(IntervalEdge.start))),
        Rect.fromLTWH(
          origin.dx + block.left,
          origin.dy + rowRect.top,
          24,
          rowRect.height,
        ),
      );
      expect(
        tester.getRect(find.byKey(edgeKeyOf(IntervalEdge.end))),
        Rect.fromLTWH(
          origin.dx + block.left + block.width - 16,
          origin.dy + rowRect.top,
          16,
          rowRect.height,
        ),
      );
    });
  });

  group('层序：块体层 → 载荷层 → 端点带层', () {
    testWidgets('载荷压在块体之上、端点带压在载荷与块体之上', (tester) async {
      await tester.pumpWidget(
        harness(
          startBand: 24,
          payload: const [
            Positioned.fill(child: SizedBox(key: payloadKey)),
          ],
        ),
      );
      final body = tester.element(find.byKey(bodyKey));
      final payload = tester.element(find.byKey(payloadKey));
      final edge = tester.element(find.byKey(edgeKeyOf(IntervalEdge.start)));

      final innerStack = sharedStackOf(
        tester,
        find.byKey(bodyKey),
        find.byKey(payloadKey),
      );
      expect(
        paintIndexOf(innerStack, body),
        lessThan(paintIndexOf(innerStack, payload)),
        reason: '载荷层应压在块体层之上',
      );

      final layerStack = sharedStackOf(
        tester,
        find.byKey(bodyKey),
        find.byKey(edgeKeyOf(IntervalEdge.start)),
      );
      expect(
        paintIndexOf(layerStack, body),
        lessThan(paintIndexOf(layerStack, edge)),
        reason: '端点带层应压在块体层之上',
      );
      expect(
        paintIndexOf(layerStack, payload),
        lessThan(paintIndexOf(layerStack, edge)),
        reason: '端点带层应压在载荷层之上',
      );
    });
  });

  group('端点带宽为 0 时不渲染该侧', () {
    testWidgets('start 为 0：只有 end 带在渲染树里', (tester) async {
      await tester.pumpWidget(harness(startBand: 0, endBand: 24));
      expect(find.byKey(edgeKeyOf(IntervalEdge.start)), findsNothing);
      expect(find.byKey(edgeKeyOf(IntervalEdge.end)), findsOneWidget);
    });

    testWidgets('end 为 0：只有 start 带在渲染树里', (tester) async {
      await tester.pumpWidget(harness(startBand: 24, endBand: 0));
      expect(find.byKey(edgeKeyOf(IntervalEdge.start)), findsOneWidget);
      expect(find.byKey(edgeKeyOf(IntervalEdge.end)), findsNothing);
    });

    testWidgets('两端都为 0：一条带都不渲染（块体照常渲染）', (tester) async {
      await tester.pumpWidget(harness(startBand: 0, endBand: 0));
      expect(find.byKey(edgeKeyOf(IntervalEdge.start)), findsNothing);
      expect(find.byKey(edgeKeyOf(IntervalEdge.end)), findsNothing);
      expect(find.byKey(blockKey), findsOneWidget);
    });

    testWidgets('带内的装饰件画在本侧带体内部（所见即所拖）', (tester) async {
      await tester.pumpWidget(
        harness(
          startBand: 24,
          endBand: 0,
          edgeChild: const SizedBox.expand(key: edgeChildKey),
        ),
      );
      expect(
        tester.getRect(find.byKey(edgeChildKey)),
        tester.getRect(find.byKey(edgeKeyOf(IntervalEdge.start))),
      );
    });
  });

  group('键全部由调用点提供', () {
    testWidgets('非空引导锚点键：包一层锚点上报件，块矩形与键字符串逐位不变', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: harness(startBand: 24, guideAnchorKey: 'note_anchor_probe'),
        ),
      );
      expect(
        tester.widget<GuideAnchor>(find.byType(GuideAnchor)).anchorKey,
        'note_anchor_probe',
      );
      final origin = originOf(tester);
      expect(
        tester.getRect(find.byKey(blockKey)),
        Rect.fromLTWH(
          origin.dx + block.left,
          origin.dy + rowRect.top,
          block.width,
          rowRect.height,
        ),
      );
    });

    testWidgets('空引导锚点键：不包锚点上报件，被包内容逐位不变', (tester) async {
      await tester.pumpWidget(harness(startBand: 24));
      expect(find.byType(GuideAnchor), findsNothing);
      expect(find.byKey(blockKey), findsOneWidget);
    });
  });

  group('四个水平拖动回调的挂法', () {
    /// 起手点：块体中部（两端带之外）或某一侧端点带中部。
    Offset bodyGrab(WidgetTester tester) =>
        tester.getCenter(find.byKey(blockKey));
    Offset edgeGrab(WidgetTester tester, IntervalEdge edge) =>
        tester.getRect(find.byKey(edgeKeyOf(edge))).center;

    /// 三个拖动用例共用的记录布景：记下五支回调的调用序并驱动一次手势。
    /// [cancel] 走「起手即被打断」，否则走「起手 → 逐帧 → 收口」。
    Future<List<String>> dragRecording(
      WidgetTester tester, {
      required Offset Function(WidgetTester tester) grabAt,
      bool cancel = false,
      bool withVerticalCompetitor = false,
      double startBand = 24,
      double endBand = 24,
    }) async {
      final events = <String>[];
      await tester.pumpWidget(
        harness(
          startBand: startBand,
          endBand: endBand,
          withVerticalCompetitor: withVerticalCompetitor,
          onMoveDragStart: (_) => events.add('moveStart'),
          onEdgeDragStart: (edge, _) => events.add('edgeStart:${edge.name}'),
          onDragUpdate: (_) => events.add('update'),
          onDragEnd: () => events.add('end'),
          onDragCancel: () => events.add('cancel'),
        ),
      );
      final gesture = await tester.startGesture(grabAt(tester));
      await tester.pump();
      if (cancel) {
        await gesture.cancel();
      } else {
        await gesture.moveBy(const Offset(30, 0));
        await tester.pump();
        await gesture.up();
      }
      await tester.pump();
      return events;
    }

    testWidgets('块体拖动：起手 → 逐帧 → 收口，端点起手不参与', (tester) async {
      final events = await dragRecording(tester, grabAt: bodyGrab);

      expect(events.where((e) => e == 'moveStart').length, 1);
      expect(events.where((e) => e.startsWith('edgeStart')).length, 0);
      expect(events.contains('update'), isTrue);
      expect(events.where((e) => e == 'end').length, 1);
      expect(events.last, 'end');
    });

    testWidgets('start 端点带拖动：端点起手带出该侧，块体起手不参与', (tester) async {
      final events = await dragRecording(
        tester,
        grabAt: (t) => edgeGrab(t, IntervalEdge.start),
      );

      expect(events.where((e) => e == 'edgeStart:start').length, 1);
      expect(events.where((e) => e == 'moveStart').length, 0);
      expect(events.first, 'edgeStart:start');
      expect(events.contains('update'), isTrue);
      expect(events.where((e) => e == 'end').length, 1);
      expect(events.last, 'end');
    });

    testWidgets('end 端点带拖动：端点起手带出 end 侧', (tester) async {
      final events = await dragRecording(
        tester,
        grabAt: (t) => edgeGrab(t, IntervalEdge.end),
      );

      expect(events.where((e) => e == 'edgeStart:end').length, 1);
      expect(events.where((e) => e.startsWith('edgeStart:start')).length, 0);
      expect(events.where((e) => e == 'moveStart').length, 0);
      expect(events.last, 'end');
    });

    testWidgets('块体拖动被打断：走 cancel 回调而不是 end', (tester) async {
      final events = await dragRecording(
        tester,
        grabAt: bodyGrab,
        cancel: true,
        withVerticalCompetitor: true,
      );

      expect(events.where((e) => e == 'cancel').length, 1);
      expect(events.contains('end'), isFalse);
      expect(events.contains('moveStart'), isFalse);
    });

    testWidgets('端点带拖动被打断：同样走 cancel 回调', (tester) async {
      final events = await dragRecording(
        tester,
        grabAt: (t) => edgeGrab(t, IntervalEdge.start),
        cancel: true,
        withVerticalCompetitor: true,
      );

      expect(events.where((e) => e == 'cancel').length, 1);
      expect(events.contains('end'), isFalse);
      expect(events.where((e) => e.startsWith('edgeStart')), isEmpty);
    });
  });
}
