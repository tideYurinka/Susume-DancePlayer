// 备注文本清空即删除该备注」反转）：
// 编辑器收起（「完成」钮 / 系统返回键）时归一后 trim 为空 → 不写文本、
// 改提交既有删除命令；受锁定分段门禁拒绝时原文本保留；撤销一次恢复整条
// 备注连同原文本。
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/note_editor_harness.dart';

void main() {
  Future<void> collapse(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('note_editor_done')));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) =>
      tester.enterText(find.byKey(const Key('note_text_editor_field')), text);

  testWidgets('清空既有文本后收起：删除这条备注、面板收起、编辑目标清空', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();

    await type(tester, '');
    await collapse(tester);

    expect(container.read(noteStickersProvider), isEmpty);
    expect(container.read(noteTextEditorTargetProvider), isNull);
    expect(find.byKey(const Key('note_text_editor')), findsNothing);
  });

  testWidgets('纯空格文本视为空：收起同样删除（换行已归一为空格，空格不是内容）', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();

    await type(tester, '  \n ');
    await collapse(tester);

    expect(container.read(noteStickersProvider), isEmpty);
  });

  testWidgets('新建后一个字没写就收起：片段不留（「先占位」反转）', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    // 缺省种入的就是空文本备注——「添加」条目建出备注后即刻弹编辑器那条路。
    seedAndOpenNoteEditor(container);
    await tester.pump();
    expect(container.read(noteStickersProvider).single.text, '');

    await collapse(tester);

    expect(container.read(noteStickersProvider), isEmpty);
    expect(find.byKey(const Key('note_text_editor')), findsNothing);
  });

  testWidgets('系统返回键与「完成」同路：清空后按返回也删除', (tester) async {
    final container = noteEditorContainer();
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: NoteTextEditorPanel()),
        ),
      ),
    );
    await tester.pump();
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();

    await type(tester, '');
    await navigatorKey.currentState!.maybePop();
    await tester.pump();

    expect(container.read(noteStickersProvider), isEmpty);
  });

  testWidgets('点输入条以外任意处收起同路：清空后点条外也删除', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();

    await type(tester, '');
    // 出口②的铺满手势面在输入条之上：点屏幕上方（远离输入条）即收起。
    await tester.tapAt(const Offset(400, 20));
    await tester.pump();

    expect(container.read(noteStickersProvider), isEmpty);
  });

  testWidgets('非空文本收起仍写文本：不删（既有「收起即存」路径不变）', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();

    await type(tester, '注意脚');
    await collapse(tester);

    expect(container.read(noteStickersProvider).single.text, '注意脚');
  });

  testWidgets('撤销一次恢复整条备注：连同原文本（不是恢复成空文本）', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();

    await type(tester, '');
    await collapse(tester);
    expect(container.read(noteStickersProvider), isEmpty);

    container.read(annotationEditorProvider).undo();
    await tester.pump();

    // 撤销 = 一步回到删除前：备注（含时间窗与文本）原样回来。
    expect(container.read(noteStickersProvider).single.text, '注意手');
    expect(container.read(noteStickersProvider).single.startMs, 10000);
  });

  testWidgets('锁定分段下清空照常删备注（备注删除不受锁）', (tester) async {
    final container = noteEditorContainer();
    await pumpNoteEditorPanel(tester, container);
    seedAndOpenNoteEditor(container, text: '注意手');
    await tester.pump();
    container.read(layoutLockedProvider.notifier).replace(true);
    await tester.pump();
    final stepsBefore = container.read(annotationEditHistoryProvider).length;

    await type(tester, '');
    await collapse(tester);

    // 归一国空即删：备注删除不受锁定分段管，一步可撤销。
    expect(container.read(noteStickersProvider), isEmpty);
    expect(container.read(annotationEditHistoryProvider).length, stepsBefore + 1);
  });
}
