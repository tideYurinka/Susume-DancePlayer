import 'package:dance_learning_app/player/track_fragment_bubble.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';

/// 片段浮条域直测：直接 pump 该模块，只注它
/// 自带的输入——不建整条带、不开 `ProviderScope`、不造标注数据。
///
/// 断言全落在外部可观察行为上：按输入渲染出的动作条目（文案、键、回调恰好
/// 一次）；浮条相对锚点的落位与朝向（不覆盖它描述的那一块）；贴屏缘的横向
/// 钳制与超屏省略；锚上报件的上报/重报/清锚；空内容的退化形态。
void main() {
  /// 视口取具名档（`test/` 的视口赋值唯一入口），浮条的「屏幕」= 整档逻辑
  /// 尺寸（全局坐标与浮条坐标同源）。
  const tier = ViewportTier.small;
  final screenSize = tier.logicalSize;

  Future<void> pumpBubble(
    WidgetTester tester, {
    required Rect anchorRect,
    String text = '这条备注的完整内容',
    String actionLabel = '编辑',
    VoidCallback? onAction,
    Key bubbleKey = const Key('bubble'),
    Key actionKey = const Key('bubble_action'),
    Key actionHitKey = const Key('bubble_action_hit'),
  }) async {
    useNamedViewport(tester, tier);
    await tester.pumpWidget(
      MaterialApp(
        home: FragmentActionBubble(
          anchorRect: anchorRect,
          text: text,
          actionLabel: actionLabel,
          onAction: onAction ?? () {},
          bubbleKey: bubbleKey,
          actionKey: actionKey,
          actionHitKey: actionHitKey,
        ),
      ),
    );
  }

  Finder tailOf(WidgetTester tester) => find.descendant(
    of: find.byType(Column),
    matching: find.byType(CustomPaint),
  );

  group('动作条目', () {
    testWidgets('按输入渲染内容与动作入口：文案、键逐项一致', (tester) async {
      await pumpBubble(
        tester,
        anchorRect: const Rect.fromLTWH(300, 400, 100, 30),
        text: '手要再抬高一点',
        actionLabel: '退出回看',
      );

      expect(find.byKey(const Key('bubble')), findsOneWidget);
      expect(find.text('手要再抬高一点'), findsOneWidget);
      expect(find.text('退出回看'), findsOneWidget);
      expect(find.byKey(const Key('bubble_action')), findsOneWidget);
      expect(find.byKey(const Key('bubble_action_hit')), findsOneWidget);
    });

    testWidgets('浮条内动作入口：点一下回调恰好一次', (tester) async {
      var taps = 0;
      await pumpBubble(
        tester,
        anchorRect: const Rect.fromLTWH(300, 400, 100, 30),
        onAction: () => taps++,
      );

      await tester.tap(find.byKey(const Key('bubble_action')));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('动作入口的透明命中盒：字高之外的溢出区仍接点按且恰好一次', (tester) async {
      var taps = 0;
      await pumpBubble(
        tester,
        anchorRect: const Rect.fromLTWH(300, 400, 100, 30),
        onAction: () => taps++,
      );

      final hitRect = tester.getRect(
        find.byKey(const Key('bubble_action_hit')),
      );
      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));
      // 命中盒补到 48 下限：向下溢出浮条下缘——溢出区照样接点按。
      expect(hitRect.height, greaterThanOrEqualTo(kHitTargetMinSize));
      expect(hitRect.bottom, greaterThan(bubbleRect.bottom));

      await tester.tapAt(Offset(hitRect.center.dx, hitRect.bottom - 2));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('锚定与朝向', () {
    testWidgets('上方放得下：浮条在锚点上方、留出间隙，尾尖在两者之间朝下', (tester) async {
      const anchorRect = Rect.fromLTWH(300, 400, 100, 30);
      await pumpBubble(tester, anchorRect: anchorRect);

      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));
      final tailRect = tester.getRect(tailOf(tester));

      // 不覆盖它描述的那一块：整体落在锚点上方。
      expect(bubbleRect.bottom, lessThanOrEqualTo(anchorRect.top));
      // 尾尖尺寸与位置由集中 token 定：间隙 + 尾尖把浮条顶到锚点上缘。
      expect(
        tailRect.size,
        const Size(kNoteBubbleTailWidth, kNoteBubbleTailHeight),
      );
      expect(
        bubbleRect.bottom + kNoteBubbleTailHeight + kNoteBubbleGap,
        closeTo(anchorRect.top, 0.01),
      );
      expect(tailRect.top, greaterThanOrEqualTo(bubbleRect.bottom - 0.01));
    });

    testWidgets('上方放不下（锚点在最上一行）：改放锚点下方，尾尖整条翻转', (tester) async {
      const anchorRect = Rect.fromLTWH(300, 0, 100, 30);
      await pumpBubble(tester, anchorRect: anchorRect);

      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));
      final tailRect = tester.getRect(tailOf(tester));

      // 改放锚点下方：浮条上缘与锚点下缘留出间隙（不覆盖片段）。
      expect(bubbleRect.top, closeTo(anchorRect.bottom + kNoteBubbleGap, 0.01));
      expect(bubbleRect.top, greaterThanOrEqualTo(anchorRect.bottom));
      // 尾尖仍在浮条下缘那一格，只是整条纵向翻转（朝上）。
      expect(tailRect.top, greaterThanOrEqualTo(bubbleRect.bottom - 0.01));
      expect(
        find.descendant(
          of: find.byType(Column),
          matching: find.byType(Transform),
        ),
        findsOneWidget,
      );
    });

    testWidgets('贴左缘：浮条钳在屏缘留边', (tester) async {
      await pumpBubble(
        tester,
        anchorRect: const Rect.fromLTWH(-50, 400, 100, 30),
      );

      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));

      expect(bubbleRect.left, closeTo(kNoteBubbleEdgeMargin, 0.01));
    });

    testWidgets('贴右缘：浮条钳在屏缘留边', (tester) async {
      await pumpBubble(
        tester,
        anchorRect: const Rect.fromLTWH(780, 400, 100, 30),
      );

      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));

      expect(
        bubbleRect.right,
        closeTo(screenSize.width - kNoteBubbleEdgeMargin, 0.01),
      );
    });

    testWidgets('超屏文本：浮条仍不越屏缘，正文单行省略', (tester) async {
      final longText = '长' * 200;
      await pumpBubble(
        tester,
        anchorRect: const Rect.fromLTWH(400, 400, 100, 30),
        text: longText,
      );

      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));
      final body = tester.widget<Text>(find.text(longText));

      expect(
        bubbleRect.width,
        lessThanOrEqualTo(screenSize.width - kNoteBubbleEdgeMargin * 2 + 0.01),
      );
      expect(body.maxLines, 1);
      expect(body.overflow, TextOverflow.ellipsis);
      expect(body.softWrap, isFalse);
    });
  });

  group('退化形态', () {
    testWidgets('内容为空：浮条仍渲染动作条目、仍可点，宽度退到最小', (tester) async {
      var taps = 0;
      const anchorRect = Rect.fromLTWH(300, 400, 100, 30);

      await pumpBubble(
        tester,
        anchorRect: anchorRect,
        text: '',
        onAction: () => taps++,
      );
      final emptyWidth = tester.getRect(find.byKey(const Key('bubble'))).width;

      await pumpBubble(
        tester,
        anchorRect: anchorRect,
        text: '这条备注的完整内容',
        onAction: () => taps++,
      );
      final filledWidth = tester.getRect(find.byKey(const Key('bubble'))).width;

      expect(emptyWidth, lessThan(filledWidth));
      expect(find.byKey(const Key('bubble_action')), findsOneWidget);

      await tester.tap(find.byKey(const Key('bubble_action')));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('锚矩形退化（零宽高）：不抛异常，浮条仍在屏内', (tester) async {
      await pumpBubble(tester, anchorRect: Rect.zero);

      final bubbleRect = tester.getRect(find.byKey(const Key('bubble')));
      expect(bubbleRect.left, greaterThanOrEqualTo(0));
      expect(bubbleRect.right, lessThanOrEqualTo(screenSize.width));
    });
  });

  group('锚上报件', () {
    testWidgets('帧末上报渲染盒全局矩形与文本；重建时跟随；卸载即清锚', (tester) async {
      useNamedViewport(tester, tier);
      final anchor = ValueNotifier<({Rect rect, String text})?>(null);
      addTearDown(anchor.dispose);

      Widget host({required double left, required String text}) => MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: left,
              top: 120,
              width: 100,
              height: 30,
              child: FragmentBubbleAnchorReporter(anchor: anchor, text: text),
            ),
          ],
        ),
      );

      await tester.pumpWidget(host(left: 40, text: '甲'));
      expect(anchor.value, isNotNull);
      expect(anchor.value!.rect, const Rect.fromLTWH(40, 120, 100, 30));
      expect(anchor.value!.text, '甲');

      await tester.pumpWidget(host(left: 220, text: '乙'));
      expect(anchor.value!.rect, const Rect.fromLTWH(220, 120, 100, 30));
      expect(anchor.value!.text, '乙');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(anchor.value, isNull);
    });
  });
}
