import 'package:dance_learning_app/annotation/note_mention.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「点名语法」解析纯件直测：语法单元 =
/// `@` + 名册里确实存在的名字（**最长优先**）+ 紧随其后的第一个空格
///（若有）；输出「隐藏区间 + 可见分段」。不构成单元的 `@` 原样保留。
void main() {
  /// 可见文本拼接（点名段以「[名]」标记）。
  String visible(NoteMentionParse parse) => [
        for (final segment in parse.segments)
          segment.name == null ? segment.text : '[${segment.text}]',
      ].join();

  test('基本单元：@果 走位偏左 → 「果」着名、「@」与紧随空格隐藏', () {
    final parse = parseNoteMentions('@果 走位偏左', const {'果'});
    expect(visible(parse), '[果]走位偏左');
    expect(parse.segments, const [
      NoteMentionSegment('果', name: '果'),
      NoteMentionSegment('走位偏左'),
    ]);
    // 隐藏区间 = 「@」（0..1）与紧随的第一个空格（2..3）。
    expect(
      parse.hiddenRanges.map((r) => (r.start, r.end)),
      const [(0, 1), (2, 3)],
    );
  });

  test('单元末尾无空格：@果 在文本末尾 → 只隐藏「@」', () {
    final parse = parseNoteMentions('走位@果', const {'果'});
    expect(visible(parse), '走位[果]');
    expect(
      parse.hiddenRanges.map((r) => (r.start, r.end)),
      const [(2, 3)],
    );
  });

  test('最长优先：名册同时有「果」与「果果」→ @果果 识别为「果果」', () {
    final parse = parseNoteMentions('@果果 上场', const {'果', '果果'});
    expect(visible(parse), '[果果]上场');
  });

  test('长名不在时回落短名：@果果 只配到「果」→ 余下的「果」是普通文字', () {
    final parse = parseNoteMentions('@果果 上场', const {'果'});
    expect(visible(parse), '[果]果 上场');
  });

  test('不构成单元：@ 后接不在名册的名字 → 原样显示、无隐藏区间', () {
    final parse = parseNoteMentions('@小明 上场', const {'果'});
    expect(visible(parse), '@小明 上场');
    expect(parse.hiddenRanges, isEmpty);
    expect(parse.segments, const [NoteMentionSegment('@小明 上场')]);
  });

  test('孤立 @：原样显示、无隐藏区间、不报错', () {
    final parse = parseNoteMentions('邮箱 a@b.com', const {'果'});
    expect(visible(parse), '邮箱 a@b.com');
    expect(parse.hiddenRanges, isEmpty);
  });

  test('名册为空 → 不产生任何点名', () {
    final parse = parseNoteMentions('@果 上场', const <String>{});
    expect(visible(parse), '@果 上场');
    expect(parse.hiddenRanges, isEmpty);
  });

  test('名册里的空名不参与识别', () {
    final parse = parseNoteMentions('@ 上场', const {'', '果'});
    expect(visible(parse), '@ 上场');
    expect(parse.hiddenRanges, isEmpty);
  });

  test('多个点名连排：@果 @鸟 @海 → 可见文本「果鸟海」（分隔空格被隐藏）', () {
    final parse = parseNoteMentions('@果 @鸟 @海 ', const {'果', '鸟', '海'});
    expect(visible(parse), '[果][鸟][海]');
    // 全部语法字符（3 个 @ + 3 个分隔空格）都被隐藏。
    expect(parse.hiddenRanges, hasLength(6));
  });

  test('点名后面是普通文字里的空格（非紧随）→ 空格保留', () {
    final parse = parseNoteMentions('@果  双空格', const {'果'});
    expect(visible(parse), '[果] 双空格');
  });

  test('空文本 → 空分段', () {
    final parse = parseNoteMentions('', const {'果'});
    expect(parse.segments, isEmpty);
    expect(parse.hiddenRanges, isEmpty);
  });
}
