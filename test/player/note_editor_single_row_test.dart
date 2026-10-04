import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/note_editor_harness.dart';

/// 「编辑面改单行形态并撤掉样式入口」：那一行只有
/// `输入框 | 名册词条 | 删除 | 完成`——颜色
/// 色板 / 描边开关 / 最近样式三枚钮与彩色圆点消失，留下的每枚钮都带
/// 文字；名册词条条常驻这一行（不再有第二排）；编辑面打开期间整页点击
/// 归编辑面（点条外收起即存、下层收不到）；键盘开合只是位移、行高不变。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = noteEditorContainer();
    addTearDown(container.dispose);
  });

  Future<void> pumpPanel(WidgetTester tester) =>
      pumpNoteEditorPanel(tester, container);

  /// 种一位舞者（词条条非空态）。
  Future<void> seedDancer() async {
    await container
        .read(dancerRosterControllerProvider)
        .addDancer('小舞', color: 0xFF81C784);
  }

  /// 两个控件是否同排（垂直方向区间重叠）。
  bool sameRow(Rect a, Rect b) => a.top < b.bottom && b.top < a.bottom;

  testWidgets('那一行没有样式入口：色板 / 描边 / 最近全数退场，钮全带文字', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    expect(find.byKey(const Key('note_style_swatch_0')), findsNothing);
    expect(find.byKey(const Key('note_style_outline')), findsNothing);
    expect(find.byKey(const Key('note_style_recent')), findsNothing);
    expect(find.text('描边'), findsNothing);
    expect(find.text('最近'), findsNothing);
    // 留下的工具钮全部带文字。
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
  });

  testWidgets('名册词条条常驻这一行：键盘关时也同排，点名插入照常', (tester) async {
    await seedDancer();
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    // 词条与「删除」钮在同一行（垂直方向重叠）——不再有第二排。
    final chipRect = tester.getRect(find.byKey(const Key('roster_chip_小舞')));
    final deleteRect = tester.getRect(find.text('删除'));
    expect(sameRow(chipRect, deleteRect), isTrue, reason: '词条条与工具钮同一行');

    await tester.tap(find.byKey(const Key('roster_chip_小舞')));
    final field = tester.widget<TextField>(
      find.byKey(const Key('note_text_editor_field')),
    );
    expect(field.controller!.text, '@小舞 ');
  });

  testWidgets('键盘升起：仍同行、行高不变、整条在键盘上沿之上', (tester) async {
    await seedDancer();
    addTearDown(tester.view.reset);
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);
    final restBarRect = tester.getRect(
      find.byKey(const Key('note_text_editor')),
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    final dockedBarRect = tester.getRect(
      find.byKey(const Key('note_text_editor')),
    );

    expect(dockedBarRect.height, restBarRect.height, reason: '行高不变');
    expect(
      dockedBarRect.bottom,
      lessThanOrEqualTo(600 - 300),
      reason: '整条位移到键盘上沿之上',
    );
    // 停靠态词条条也在这一行。
    final chipRect = tester.getRect(find.byKey(const Key('roster_chip_小舞')));
    final doneRect = tester.getRect(find.text('完成'));
    expect(sameRow(chipRect, doneRect), isTrue);
  });

  testWidgets('编辑面打开期间整页点击归编辑面：点条外收起即存、下层收不到', (tester) async {
    var probeTapped = 0;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    key: const Key('underlying_probe'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => probeTapped++,
                    child: const SizedBox(width: 120, height: 60),
                  ),
                ),
                const NoteTextEditorPanel(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    seedAndOpenNoteEditor(container);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '条外收起',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('underlying_probe')));
    await tester.pump();

    expect(probeTapped, 0, reason: '下层控制层收不到这次点击');
    expect(
      find.byKey(const Key('note_text_editor')),
      findsNothing,
      reason: '点条外收起',
    );
    expect(
      container.read(noteStickersProvider).single.text,
      '条外收起',
      reason: '收起即存',
    );
  });

  testWidgets('点删除：备注消失、编辑器收起、可撤销恢复', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.tap(find.byKey(const Key('note_editor_delete')));
    await tester.pump();

    expect(container.read(noteStickersProvider), isEmpty);
    expect(find.byKey(const Key('note_text_editor')), findsNothing);

    container.read(annotationEditorProvider).undo();
    expect(container.read(noteStickersProvider), hasLength(1));
  });

  testWidgets('长文本不把这一行撑破：编辑器宽不超屏、无异常', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '超长备注' * 60,
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final editorRect = tester.getRect(
      find.byKey(const Key('note_text_editor')),
    );
    expect(editorRect.width, lessThanOrEqualTo(screenWidth));
    expect(editorRect.left, greaterThanOrEqualTo(0));
    expect(editorRect.right, lessThanOrEqualTo(screenWidth));
  });

  testWidgets('「完成」收起即存：净变化才提交', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '转身收手',
    );
    await tester.tap(find.byKey(const Key('note_editor_done')));
    await tester.pump();
    expect(container.read(noteStickersProvider).single.text, '转身收手');
    expect(find.byKey(const Key('note_text_editor')), findsNothing);

    // 未改动文本再开再完成：不发起命令（撤销栈深度不变）。
    container.read(noteTextEditorTargetProvider.notifier).open(10000);
    await pumpPanel(tester);
    final stepsBefore = container.read(annotationEditHistoryProvider).length;
    await tester.tap(find.byKey(const Key('note_editor_done')));
    await tester.pump();
    expect(
      container.read(annotationEditHistoryProvider).length,
      stepsBefore,
      reason: '文本未变，收起不入史',
    );
  });
}
