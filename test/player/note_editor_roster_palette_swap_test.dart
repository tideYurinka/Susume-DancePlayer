import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/note_editor_harness.dart';

/// 「名册态与舞者快捷区」widget 缝直测：
/// 点「名册」钮**原地换装**——左段备注输入框换成舞者输入
/// 框、钮文案变「返回备注编辑」，不另开面、不弹面板；回车与「新建」同
/// 一条新建路径，只建人、不自动把点名写进备注；建完立刻弹 24 色选色浮层
/// （那期间键盘收起），选完 / 取消 / 删除后浮层关闭、焦点交回舞者输入框；
/// 再点「返回备注编辑」回备注态、已打文本原样保留。
void main() {
  late ProviderContainer container;
  late InMemoryVideoDocumentStorage storage;

  setUp(() {
    container = noteEditorContainer();
    addTearDown(container.dispose);
    storage = InMemoryVideoDocumentStorage();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await container
        .read(dancerRosterControllerProvider)
        .startForVideo(VideoDocumentCoordinator(storage));
    seedAndOpenNoteEditor(container);
    await pumpNoteEditorPanel(tester, container);
  }

  Future<void> enterRosterMode(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('note_editor_roster')));
    await tester.pump();
  }

  FocusNode dancerFocusNode(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('note_editor_dancer_field')))
      .focusNode!;

  List<String> persistedNames() => [
    for (final e
        in (storage.markersSnapshot['roster']?['dancers'] as List? ?? const []))
      (e as Map)['name'] as String,
  ];

  testWidgets('点「名册」原地换装：左段变舞者输入框、钮文案变「返回备注编辑」，同一条不换面', (tester) async {
    await pumpPanel(tester);
    final barRectBefore = tester.getRect(
      find.byKey(const Key('note_text_editor')),
    );

    await enterRosterMode(tester);

    expect(find.byKey(const Key('note_editor_dancer_field')), findsOneWidget);
    expect(
      find.byKey(const Key('note_text_editor_field')),
      findsNothing,
      reason: '左段原地换成舞者输入框',
    );
    expect(
      find.byKey(const Key('note_editor_roster_new')),
      findsOneWidget,
      reason: '「新建」只在名册态出现',
    );
    expect(find.text('返回备注编辑'), findsOneWidget);
    expect(find.text('名册'), findsNothing);
    expect(
      tester.getRect(find.byKey(const Key('note_text_editor'))),
      barRectBefore,
      reason: '原地换装：同一面板、同一矩形',
    );
    expect(find.byType(Dialog), findsNothing, reason: '不弹面板');

    // 再点回备注态。
    await tester.tap(find.byKey(const Key('note_editor_roster')));
    await tester.pump();
    expect(find.byKey(const Key('note_text_editor_field')), findsOneWidget);
    expect(find.text('名册'), findsOneWidget);
    expect(find.byKey(const Key('note_editor_roster_new')), findsNothing);
  });

  testWidgets('换装不改备注文本：回备注态后已打文本原样保留', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '先打几个字',
    );
    await enterRosterMode(tester);
    await tester.tap(find.byKey(const Key('note_editor_roster')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('note_text_editor_field')),
    );
    expect(field.controller!.text, '先打几个字');
  });

  testWidgets('「新建」建人：只建人不自动写点名、落盘只触碰名册段', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);

    await tester.enterText(
      find.byKey(const Key('note_editor_dancer_field')),
      '海',
    );
    await tester.tap(find.byKey(const Key('note_editor_roster_new')));
    await tester.pumpAndSettle();

    final controller = container.read(dancerRosterControllerProvider);
    expect(controller.roster.where((e) => e.name == '海'), isNotEmpty);
    expect(persistedNames(), contains('海'), reason: '新建直写落盘');
    expect(
      container.read(noteStickersProvider).single.text,
      '',
      reason: '只建人、不自动把点名写进备注',
    );
    expect(find.byKey(const Key('note_editor_dancer_field')), findsOneWidget);
  });

  testWidgets('回车与「新建」同一条新建路径', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);

    await tester.enterText(
      find.byKey(const Key('note_editor_dancer_field')),
      '鸟',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      container
          .read(dancerRosterControllerProvider)
          .roster
          .where((e) => e.name == '鸟'),
      isNotEmpty,
    );
    // 回车建完同样进选色浮层。
    expect(find.byKey(const Key('roster_color_sheet')), findsOneWidget);
  });

  testWidgets('建完立刻弹选色浮层、那期间键盘收起；选完浮层关、焦点交回舞者输入框', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);

    await tester.enterText(
      find.byKey(const Key('note_editor_dancer_field')),
      '果',
    );
    expect(dancerFocusNode(tester).hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('note_editor_roster_new')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('roster_color_sheet')),
      findsOneWidget,
      reason: '建完自动弹选色浮层',
    );
    expect(dancerFocusNode(tester).hasFocus, isFalse, reason: '那期间键盘收起（焦点已撤）');
    expect(find.text('果'), findsOneWidget, reason: '输入框清了、词条在');

    await tester.tap(find.byKey(const Key('roster_palette_color_9')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('roster_color_sheet')), findsNothing);
    expect(
      container
          .read(dancerRosterControllerProvider)
          .roster
          .firstWhere((e) => e.name == '果')
          .color,
      kRosterPalette[9],
      reason: '颜色由选色浮层决定，不再新建时写死',
    );
    expect(
      dancerFocusNode(tester).hasFocus,
      isTrue,
      reason: '焦点交回舞者输入框，可连续输入下一个名字',
    );
  });

  testWidgets('浮层里「删除」：删掉这位舞者并落盘、回到舞者输入框', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);

    await tester.enterText(
      find.byKey(const Key('note_editor_dancer_field')),
      '山',
    );
    await tester.tap(find.byKey(const Key('note_editor_roster_new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roster_palette_delete_山')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roster_palette_delete_confirm')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(dancerRosterControllerProvider)
          .roster
          .where((e) => e.name == '山'),
      isEmpty,
    );
    expect(persistedNames(), isNot(contains('山')));
    expect(find.byKey(const Key('roster_color_sheet')), findsNothing);
    expect(dancerFocusNode(tester).hasFocus, isTrue);
  });

  testWidgets('浮层取消（点浮层外）：舞者保留、不改色、焦点交回输入框', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);

    await tester.enterText(
      find.byKey(const Key('note_editor_dancer_field')),
      '海',
    );
    await tester.tap(find.byKey(const Key('note_editor_roster_new')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('roster_color_sheet')), findsNothing);
    expect(
      container
          .read(dancerRosterControllerProvider)
          .roster
          .where((e) => e.name == '海'),
      isNotEmpty,
      reason: '取消不删人',
    );
    expect(
      container
          .read(dancerRosterControllerProvider)
          .roster
          .firstWhere((e) => e.name == '海')
          .color,
      kRosterPalette.first,
    );
    expect(dancerFocusNode(tester).hasFocus, isTrue);
  });

  testWidgets('连续新建两次都取消选色：两人默认色不同（不再建出一堆同色的人）', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);
    for (final name in ['海', '鸟']) {
      await tester.enterText(
        find.byKey(const Key('note_editor_dancer_field')),
        name,
      );
      await tester.tap(find.byKey(const Key('note_editor_roster_new')));
      await tester.pumpAndSettle();
      // 点浮层外取消：人保留、颜色就是建人时给的默认色。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    }

    final colors = {
      for (final e in container.read(dancerRosterControllerProvider).roster)
        e.name: e.color,
    };
    expect(colors.keys, containsAll(<String>['海', '鸟']));
    expect(colors['海'], isNot(colors['鸟']), reason: '默认色取色板里未被占用的第一色');
  });

  testWidgets('名册态一行放得下：舞者输入框、新建、快捷区、全部钮同排且在屏内', (tester) async {
    await pumpPanel(tester);
    await enterRosterMode(tester);
    // 多词条：快捷区横滚不撑破一行。
    await container
        .read(dancerRosterControllerProvider)
        .addDancer('舞者名字很长很长一', color: 0xFF123456);
    await tester.pump();

    bool sameRow(Rect a, Rect b) => a.top < b.bottom && b.top < a.bottom;
    final barRect = tester.getRect(find.byKey(const Key('note_text_editor')));
    final stripRect = tester.getRect(
      find.byKey(const Key('note_editor_roster_strip')),
    );
    expect(sameRow(stripRect, barRect), isTrue);
    expect(stripRect.width, lessThanOrEqualTo(260), reason: '快捷区上限 260dp');
    expect(tester.takeException(), isNull);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(barRect.right, lessThanOrEqualTo(screenWidth));
  });
}
