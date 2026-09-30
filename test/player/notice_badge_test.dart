import 'package:dance_learning_app/core/notice_badge.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpBadge(
    WidgetTester tester, {
    Key? badgeKey,
    Widget? child,
    EdgeInsetsGeometry? padding,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: NoticeBadge(
              key: badgeKey,
              padding: padding,
              child: child ?? const Text('x'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('胶囊底座取 NoticeBadge 视觉 token', (tester) async {
    await pumpBadge(tester);

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(NoticeBadge),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, kNoticeBackground);
    expect(material.elevation, kNoticeElevation);
    expect(material.borderRadius, BorderRadius.circular(kNoticeRadius));
    expect(
      material.shape,
      isNull,
      reason: '圆角胶囊走 borderRadius，不与 shape 同时生效',
    );

    final padding = tester.widget<Padding>(
      find.descendant(
        of: find.byType(NoticeBadge),
        matching: find.byType(Padding),
      ),
    );
    expect(
      padding.padding,
      EdgeInsets.symmetric(
        horizontal: kNoticePaddingH,
        vertical: kNoticePaddingV,
      ),
    );
  });

  testWidgets('内容槽原样渲染 child（文本/含按钮 Row 均可）', (tester) async {
    const badgeKey = Key('double_speed_badge');
    await pumpBadge(
      tester,
      badgeKey: badgeKey,
      child: const Text('2 倍速'),
    );

    // key 落在 Material（NoticeBadge 根）上，供测试定位。
    expect(find.byKey(badgeKey), findsOneWidget);
    expect(find.text('2 倍速'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('2 倍速'), matching: find.byType(NoticeBadge)),
      findsOneWidget,
    );
  });

  testWidgets('内边距覆盖口：传什么用什么，不传即全站默认档', (tester) async {
    // 默认档：覆盖口为空。
    await pumpBadge(tester);
    expect(
      tester.widget<NoticeBadge>(find.byType(NoticeBadge)).padding,
      isNull,
    );
    expect(
      tester
          .widget<Padding>(
            find.descendant(
              of: find.byType(NoticeBadge),
              matching: find.byType(Padding),
            ),
          )
          .padding,
      EdgeInsets.symmetric(
        horizontal: kNoticePaddingH,
        vertical: kNoticePaddingV,
      ),
    );

    // 覆盖档（角落提示卡紧凑档）：只改这一枚的内边距。
    await pumpBadge(tester, padding: kCornerPromptCardPadding);
    expect(
      tester
          .widget<Padding>(
            find.descendant(
              of: find.byType(NoticeBadge),
              matching: find.byType(Padding),
            ),
          )
          .padding,
      kCornerPromptCardPadding,
    );
  });

  testWidgets('视觉 token 取值与既有 pill 常量一致（行为零变化）', (tester) async {
    expect(kNoticeBackground, Colors.black87);
    expect(kNoticeElevation, 4);
    expect(kNoticeRadius, 8);
    expect(kNoticePaddingH, 16);
    expect(kNoticePaddingV, 10);
    expect(kNoticeTextColor, Colors.white);
    expect(kNoticeFontSize, 14);
    // 角落提示卡紧凑档：只服务两张
    // 左下角提示卡，全站默认档取值不受影响。
    expect(kCornerPromptCardPaddingH, 12);
    expect(kCornerPromptCardPaddingV, 0);
    expect(kCornerPromptCardFontSize, 12);
    expect(kCornerPromptCardGap, 8);
    // 卡片级 token（mirror 询问卡的两栏依据大按钮）。
    expect(kNoticeCardRadius, 20);
    expect(kNoticeCardPadding, 20);
    expect(kNoticeCardTitleSize, 19);
  });
}
