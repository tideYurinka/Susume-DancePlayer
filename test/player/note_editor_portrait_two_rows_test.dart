import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/note_editor_harness.dart';

/// 「备注输入条竖屏两行」widget 缝直测：竖屏下输入条两行——上行输入框满宽（仍
/// 单行 / 自动聚焦 / 回车不换行），下行动作区一排（舞者快捷区、名册、删除、
/// 完成）且名册条占满剩余宽、沿用条内横向滚动；名册态同样的两行里可达；
/// 键盘弹起仍不被遮。
///
/// 横屏一条横排「逐位不变」由既有 `note_editor_single_row_test` /
/// `note_editor_roster_palette_swap_test` / `note_editor_keyboard_dock_test`
/// 一行不改当护栏。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = noteEditorContainer();
    addTearDown(container.dispose);
  });

  /// 该次量测所用视口 = (1264×2736, 3.5) → 361.1×781.7dp，即 `compact` 档；
  /// 断言的是备注编辑器两行在小视口下可达，与具体设备无关。
  void setPortraitView(WidgetTester tester) =>
      useNamedViewport(tester, ViewportTier.compact);

  Future<void> pumpPanel(WidgetTester tester) =>
      pumpNoteEditorPanel(tester, container);

  Future<void> seedDancer(String name) async {
    await container
        .read(dancerRosterControllerProvider)
        .addDancer(name, color: 0xFF81C784);
  }

  double screenWidth(WidgetTester tester) =>
      tester.view.physicalSize.width / tester.view.devicePixelRatio;

  double screenHeight(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  const fieldKey = Key('note_text_editor_field');
  const barKey = Key('note_text_editor');
  const stripKey = Key('note_editor_roster_strip');

  testWidgets('竖屏输入条两行、无横向溢出、输入框宽度非零', (tester) async {
    setPortraitView(tester);
    await seedDancer('小舞');
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    expect(tester.takeException(), isNull, reason: '无 RenderFlex 横向溢出');

    final barRect = tester.getRect(find.byKey(barKey));
    expect(barRect.left, greaterThanOrEqualTo(0));
    expect(barRect.right, lessThanOrEqualTo(screenWidth(tester)));
    expect(barRect.width, lessThanOrEqualTo(screenWidth(tester)));

    final fieldRect = tester.getRect(find.byKey(fieldKey));
    expect(fieldRect.width, greaterThan(0), reason: '输入框不再被挤到零宽');

    // 上行输入框与下行动作区上下两行（垂直方向不重叠）。
    final deleteRect = tester.getRect(find.text('删除'));
    expect(fieldRect.bottom, lessThanOrEqualTo(deleteRect.top),
        reason: '输入框在上行、动作区在下行');
  });

  testWidgets('上行输入框满宽、单行、自动聚焦、回车与粘贴换行归一为空格',
      (tester) async {
    setPortraitView(tester);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    final field = tester.widget<TextField>(find.byKey(fieldKey));
    expect(field.maxLines, 1, reason: '单行');
    expect(field.autofocus, isTrue, reason: '自动聚焦');
    expect(
      tester.binding.focusManager.primaryFocus?.hasFocus,
      isTrue,
      reason: '打开即拿到焦点',
    );

    // 满宽 = 输入条内宽（横屏里输入框与动作区并排、只能是剩余宽）。
    final barRect = tester.getRect(find.byKey(barKey));
    final fieldRect = tester.getRect(find.byKey(fieldKey));
    const innerInset = 16 * 2 /* margin */ + 8 * 2 /* padding */;
    expect(
      fieldRect.width,
      closeTo(barRect.width - innerInset, 1),
      reason: '上行只有输入框、占满整行',
    );

    // 粘贴进来的换行进不了输入框：CRLF 经 [NoteSingleLineFormatter] 归一为
    // 空格，LF 由单行框框架层剔除（与横屏同一口径，见
    // note_editor_single_line_text_test）。
    await tester.enterText(find.byKey(fieldKey), '第一行\r\n第二行');
    final textField = tester.widget<TextField>(find.byKey(fieldKey));
    expect(textField.controller!.text, '第一行 第二行');
    expect(textField.controller!.text, isNot(contains('\n')));

    await tester.enterText(find.byKey(fieldKey), '第一行\n第二行');
    expect(
      tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
      isNot(contains('\n')),
      reason: '回车 / 粘贴换行不留在输入框里',
    );
  });

  testWidgets('下行动作区含快捷区、名册、删除、完成；快捷区占满剩余宽且条内横滚',
      (tester) async {
    setPortraitView(tester);
    await seedDancer('小舞');
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    final barRect = tester.getRect(find.byKey(barKey));
    final stripRect = tester.getRect(find.byKey(stripKey));
    final rosterRect = tester.getRect(find.byKey(const Key('note_editor_roster')));
    final deleteRect = tester.getRect(find.text('删除'));
    final doneRect = tester.getRect(find.text('完成'));

    // 四者同排（垂直方向区间重叠）。
    bool sameRow(Rect a, Rect b) => a.top < b.bottom && b.top < a.bottom;
    for (final rect in [rosterRect, deleteRect, doneRect]) {
      expect(sameRow(stripRect, rect), isTrue, reason: '下行动作区一排');
    }

    // 快捷区占满动作行剩余宽：左缘贴输入条内缘、右缘紧贴「名册」钮。
    // 条自身的 260dp 上限在横屏那一行由既有用例锁定（dancer_roster_chips_test
    // 的 width == 260、note_editor_roster_palette_swap_test 的 <= 260）；
    // 竖屏这里由 [Expanded] 的紧约束接管宽度，因此「上限只在横屏那一行」
    // 的两半各有着落。
    expect(stripRect.left, closeTo(barRect.left + 16 + 8, 1));
    expect((rosterRect.left - stripRect.right).abs(), lessThan(1),
        reason: '快捷区吃掉按钮之外的全部剩余宽、不留空隙');

    // 条内横向滚动：名字超长时内容溢出视口仍不报错（沿用条内横滚）。
    await seedDancer('舞者名字很长很长很长很长很长');
    await tester.pump();
    final longChip = tester.getRect(
      find.byKey(const Key('roster_chip_舞者名字很长很长很长很长很长')),
    );
    expect(longChip.right, greaterThan(stripRect.right),
        reason: '内容超出视口宽度 = 条内横滚');
    expect(tester.takeException(), isNull);
  });

  testWidgets('名册态在竖屏下同样两行可达：新建与返回备注编辑都可操作',
      (tester) async {
    setPortraitView(tester);
    await seedDancer('小舞');
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.tap(find.byKey(const Key('note_editor_roster')));
    await tester.pump();

    expect(find.byKey(fieldKey), findsNothing, reason: '左段换成舞者输入框');
    final dancerField = find.byKey(const Key('note_editor_dancer_field'));
    expect(dancerField, findsOneWidget);
    expect(find.byKey(const Key('note_editor_roster_new')), findsOneWidget);
    expect(find.text('返回备注编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 舞者输入框与「新建」在上行，动作区在下行。
    final dancerRect = tester.getRect(dancerField);
    final newRect = tester.getRect(
      find.byKey(const Key('note_editor_roster_new')),
    );
    final stripRect = tester.getRect(find.byKey(stripKey));
    expect(dancerRect.bottom, lessThanOrEqualTo(stripRect.top),
        reason: '输入框在上行');
    expect(newRect.top, lessThan(stripRect.top), reason: '「新建」随输入框在上行');

    // 「返回备注编辑」与「删除」「完成」同处下行且可点。
    final backRect = tester.getRect(find.text('返回备注编辑'));
    final doneRect = tester.getRect(find.text('完成'));
    expect(backRect.top < doneRect.bottom && doneRect.top < backRect.bottom,
        isTrue,
        reason: '「返回备注编辑」在下行动作区');

    await tester.tap(find.text('返回备注编辑'));
    await tester.pump();
    expect(find.byKey(fieldKey), findsOneWidget, reason: '回到备注态');
    expect(find.text('名册'), findsOneWidget);
  });

  testWidgets('键盘弹起：两行形态不变、整条位移到键盘上沿之上', (tester) async {
    setPortraitView(tester);
    await seedDancer('小舞');
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    final restRect = tester.getRect(find.byKey(barKey));
    final fieldRect = tester.getRect(find.byKey(fieldKey));
    final deleteRect = tester.getRect(find.text('删除'));

    const keyboardHeight = 300.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboardHeight * 3.5);
    await tester.pump();

    final dockedRect = tester.getRect(find.byKey(barKey));
    expect(
      dockedRect.bottom,
      lessThanOrEqualTo(screenHeight(tester) - keyboardHeight),
      reason: '整条落在键盘上沿之上、不被遮',
    );
    expect(dockedRect.height, restRect.height, reason: '键盘开合只是位移、形态不变');
    expect(
      tester.getRect(find.byKey(fieldKey)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('删除')).top),
      reason: '停靠后仍是两行',
    );
    // 停靠后上行的输入框与下行的删除钮都还在原位关系里。
    expect(restRect.height, greaterThan(fieldRect.height));
    expect(deleteRect.width, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
