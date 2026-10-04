import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/note_editor_harness.dart';

/// 「备注文本单行化 + 换行归一」编辑器 widget 缝直测：输入框单行
/// （`maxLines` = 1，回车不产生换行）；换行字符进不了标注编辑模块——
/// 存盘文本不含任何换行字符。入框层 LF 由框架单行 formatter 剔除、CR
/// 由 [NoteSingleLineFormatter] 归一为空格；提交载荷再经
/// [normalizeNoteText] 归一（纯函数直测见 note_text_normalize_test）。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = noteEditorContainer();
    addTearDown(container.dispose);
  });

  Future<void> pumpPanel(WidgetTester tester) =>
      pumpNoteEditorPanel(tester, container);

  testWidgets('输入框单行：maxLines = 1', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    final field = tester.widget<TextField>(
      find.byKey(const Key('note_text_editor_field')),
    );
    expect(field.maxLines, 1);
  });

  testWidgets('含换行的文本收起即存：存盘文本不含任何换行字符', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '这里注意手\n转身收脚',
    );
    await tester.tap(find.byKey(const Key('note_editor_done')));
    await tester.pump();

    final saved = container.read(noteStickersProvider).single.text;
    expect(saved, '这里注意手转身收脚');
    expect(saved, isNot(contains('\n')));
    expect(saved, isNot(contains('\r')));
  });

  testWidgets('CRLF / CR / 连续换行同样进不了存盘文本', (tester) async {
    seedAndOpenNoteEditor(container);
    await pumpPanel(tester);

    await tester.enterText(
      find.byKey(const Key('note_text_editor_field')),
      '\r\n注意\r\n\r\n收脚\r',
    );
    await tester.tap(find.byKey(const Key('note_editor_done')));
    await tester.pump();

    // 独立真值 = 输入字面量剥去 \n、\r 各归一为空格（换行字符一个不剩）。
    expect(container.read(noteStickersProvider).single.text, ' 注意  收脚 ');
    expect(
      container.read(noteStickersProvider).single.text,
      isNot(contains('\n')),
    );
    expect(
      container.read(noteStickersProvider).single.text,
      isNot(contains('\r')),
    );
  });

  test('formatter：归一使文本变短时选区钳回新文本域、不越界', () {
    const formatter = NoteSingleLineFormatter();
    const input = TextEditingValue(
      text: '这里注意手\r\n转身收脚',
      selection: TextSelection.collapsed(offset: 10),
    );
    final out = formatter.formatEditUpdate(const TextEditingValue(), input);
    expect(out.text, '这里注意手 转身收脚');
    expect(out.selection.baseOffset, lessThanOrEqualTo(out.text.length));
    expect(out.selection.extentOffset, lessThanOrEqualTo(out.text.length));

    // 无换行输入原样返回（同一值，不动选区）。
    const clean = TextEditingValue(
      text: '这里注意手',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(formatter.formatEditUpdate(const TextEditingValue(), clean), clean);
  });
}
