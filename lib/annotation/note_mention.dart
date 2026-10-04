/// 点名语法解析纯件：
/// 备注 text 里 `@` + 名册里确实存在的名字（**最长优先**）+ 紧随其后的
/// 第一个空格（若有）= 一个不可分的**语法单元**；渲染时整体隐藏 `@` 与
/// 那个空格，名字段按该舞者的代表色着色。
///
/// - **文本是唯一真源**：点名不另存字段，渲染（与量测）时按**当前名册**
///   解析——名册的增 / 删 / 改色实时反映到所有既有备注。
/// - **不构成单元的 `@` 原样显示**：`@` 后面不是名册里的名字、或后面
///   什么都没有时，`@` 就是普通字符；因此孤立 `@` 永远打得出来。
/// - 不做转义、不报错：空名册、空名、异常输入都有定义良好的结果。
library;

/// 一个可见分段：[text] 为可见文本；[name] 非 null = 点名段（名字 =
/// 名册名，着色的键），null = 普通段（正文恒白）。
class NoteMentionSegment {
  const NoteMentionSegment(this.text, {this.name});

  /// 可见文本（语法字符——`@` 与紧随的分隔空格——不在此列）。
  final String text;

  /// 点名段的名册名；普通段为 null。
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is NoteMentionSegment && other.text == text && other.name == name;

  @override
  int get hashCode => Object.hash(text, name);
}

/// 一个隐藏区间（半开 `[start, end)`，[start] / [end] 为源文本下标）：
/// 属于语法、渲染与量测都不见的字符（`@` 或紧随名字后的第一个空格）。
class NoteMentionHiddenRange {
  const NoteMentionHiddenRange(this.start, this.end);

  final int start;
  final int end;
}

/// 解析结果：[segments]（可见分段，按源顺序拼接 = 贴纸实际显示的文本）
/// 与 [hiddenRanges]（隐藏区间，升序、互不重叠）。
class NoteMentionParse {
  const NoteMentionParse({required this.segments, required this.hiddenRanges});

  /// 可见分段（点名段 + 普通段），覆盖源文本的全部非语法字符。
  final List<NoteMentionSegment> segments;

  /// 隐藏区间（升序、互不重叠、半开）。
  final List<NoteMentionHiddenRange> hiddenRanges;
}

/// 按 [rosterNames] 解析 [text] 中的点名语法。名册为空 / 空名不参与
/// 识别；候选名按长度降序尝试（最长优先）。
NoteMentionParse parseNoteMentions(String text, Iterable<String> rosterNames) {
  // 最长优先：同一起点先试长名（长名匹配成功即整体消费，短名不再试）。
  final names = [
    for (final name in rosterNames)
      if (name.isNotEmpty) name,
  ]..sort((a, b) => b.length.compareTo(a.length));
  final segments = <NoteMentionSegment>[];
  final hidden = <NoteMentionHiddenRange>[];
  final buffer = StringBuffer();
  void flushPlain() {
    if (buffer.isEmpty) return;
    segments.add(NoteMentionSegment(buffer.toString()));
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    if (text.codeUnitAt(i) == 0x40 /* @ */ ) {
      String? matched;
      for (final name in names) {
        if (text.startsWith(name, i + 1)) {
          matched = name;
          break;
        }
      }
      if (matched != null) {
        final nameStart = i + 1;
        final nameEnd = nameStart + matched.length;
        // 紧随其后的第一个空格（若有）属于语法单元、被隐藏。
        final hasTrailingSpace =
            nameEnd < text.length && text.codeUnitAt(nameEnd) == 0x20;
        final unitEnd = nameEnd + (hasTrailingSpace ? 1 : 0);
        flushPlain();
        hidden.add(NoteMentionHiddenRange(i, nameStart));
        if (hasTrailingSpace) {
          hidden.add(NoteMentionHiddenRange(nameEnd, unitEnd));
        }
        segments.add(NoteMentionSegment(matched, name: matched));
        i = unitEnd;
        continue;
      }
    }
    buffer.writeCharCode(text.codeUnitAt(i));
    i++;
  }
  flushPlain();
  return NoteMentionParse(segments: segments, hiddenRanges: hidden);
}
