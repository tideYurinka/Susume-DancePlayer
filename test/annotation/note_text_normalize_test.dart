import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「备注文本单行化 + 换行归一」纯函数直测：换行（`\n` / `\r\n` /
/// `\r` / 连续换行 / 首尾换行）在进标注编辑模块之前被归一为空格；本就
/// 无换行的文本原样返回。
void main() {
  test('LF 换行归一为空格', () {
    expect(normalizeNoteText('这里\n注意手'), '这里 注意手');
  });

  test('CRLF 换行归一为单个空格', () {
    expect(normalizeNoteText('这里\r\n注意手'), '这里 注意手');
  });

  test('CR 换行归一为空格', () {
    expect(normalizeNoteText('这里\r注意手'), '这里 注意手');
  });

  test('连续换行逐个归一为空格（不合并）', () {
    expect(normalizeNoteText('这里\n\n注意手'), '这里  注意手');
    expect(normalizeNoteText('这里\r\n\r\n注意手'), '这里  注意手');
  });

  test('首尾换行归一为空格（不裁剪）', () {
    expect(normalizeNoteText('\n注意手'), ' 注意手');
    expect(normalizeNoteText('注意手\n'), '注意手 ');
    expect(normalizeNoteText('\r\n\r\n注意手\r\n'), '  注意手 ');
  });

  test('无换行的文本原样返回', () {
    expect(normalizeNoteText('这里注意手'), '这里注意手');
    expect(normalizeNoteText(''), '');
  });
}
