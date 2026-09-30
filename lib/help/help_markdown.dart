/// 帮助正文的 Markdown 文法：段切与折叠块识别、内容校验，以及标题 slug 与
/// 锚点解析。
///
/// 不依赖装载侧（[help_documents.dart]）：装载与渲染共用这一份识别与解析
/// 口径。
library;

import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

/// ATX 标题行的判定（与 Markdown 解析器同一规则）：最多三个前导空格、恰好
/// [level] 个 `#`、后跟空白或行尾。本方言没有代码块，
/// 正文里的 `#` 行不会是别的东西。
RegExp atxHeadingLine(int level) =>
    RegExp('^ {0,3}${'#' * level}([ \\t].*)?\$');

/// 去掉首个一级标题行之后的正文（一级标题归标题栏，正文里不重复出现）：
/// 只去掉那一行，其余各行原样保留。没有一级标题时返回原文。
String helpBodyMarkdown(String markdown) {
  final titleLine = atxHeadingLine(1);
  final lines = const LineSplitter().convert(markdown);
  for (var i = 0; i < lines.length; i++) {
    if (titleLine.hasMatch(lines[i])) {
      final body = ([...lines]..removeAt(i)).join('\n');
      if (body.isEmpty) return '';
      // LineSplitter 不产出末尾空行，原文以换行收尾时补回。
      return markdown.endsWith('\n') ? '$body\n' : body;
    }
  }
  return markdown;
}

/// 一次性图文的正文切片：第一个二级标题那一行起、到下一个二级标题之前；
/// 没有下一个二级标题时到篇末；一个二级标题都没有
/// 时为空串。切分只取行，不改动文字。
///
/// 折叠块整体跳过：块内的 `##` 不充当节边界（块内标题不参与节的切分），于是
/// 折叠块跟着它所在的那一节走、卡里与文档页同形。
String helpFirstSectionMarkdown(String markdown) {
  final headingLine = atxHeadingLine(2);
  final lines = const LineSplitter().convert(markdown);
  var start = -1;
  var line = 0;
  while (line < lines.length) {
    final fold = _foldBlockAt(lines, line);
    if (fold != null) {
      line = fold.nextLine;
      continue;
    }
    if (headingLine.hasMatch(lines[line])) {
      if (start < 0) {
        start = line;
      } else {
        return lines.sublist(start, line).join('\n').trimRight();
      }
    }
    line++;
  }
  return start < 0 ? '' : lines.sublist(start).join('\n').trimRight();
}

/// 正文里的一段：普通段整段交渲染件；折叠段带自己的标题与块内 Markdown，
/// 由渲染件包一层展开件。
sealed class HelpMarkdownSegment {
  const HelpMarkdownSegment();
}

/// 普通段：一段可含多个 Markdown 块，原样交渲染件。
final class HelpTextSegment extends HelpMarkdownSegment {
  const HelpTextSegment(this.markdown);

  final String markdown;
}

/// 折叠块：一行标题 + 块内 Markdown，默认收起。
final class HelpFoldSegment extends HelpMarkdownSegment {
  const HelpFoldSegment({required this.title, required this.markdown});

  /// 一行标题（`<summary>` 里的纯文本，不解析 Markdown）。
  final String title;

  /// 块内 Markdown 原文（一字不改）。
  final String markdown;
}

/// `<details>` / `</details>` 整行的判定：不缩进（缩进在列表或引用块里的
/// 折叠块不认）、行内只有这一对标记。
final RegExp _detailsOpenLine = RegExp(r'^<details>[ \t]*$');
final RegExp _detailsCloseLine = RegExp(r'^</details>[ \t]*$');

/// `<summary>` 整行的判定：标题是行内纯文本。
final RegExp _summaryLine = RegExp(r'^<summary>(.*)</summary>[ \t]*$');

/// 块内出现 `<details` 即视为嵌套——缩进或引用块形式的嵌套也算。
final RegExp _nestedDetails = RegExp(r'<details(?:\s|>|$)');

/// 按 GitHub 的折叠块写法把正文切成段：
///
/// - 只认**独立成段**的 `<details>`：自己不缩进、前后有空行（或篇首/篇末）；
/// - `<summary>` 紧跟下一行、单行、标题非空；
/// - 块内不再出现 `<details>`（不支持嵌套）。
///
/// 认出来的部分切成 [HelpFoldSegment]，其余行原样留在 [HelpTextSegment] 里；
/// 认不出的 HTML 留在正文里，由渲染件按根级 HTML 丢弃。识别规则只有这一份。
List<HelpMarkdownSegment> helpMarkdownSegments(String markdown) {
  final lines = const LineSplitter().convert(markdown);
  final segments = <HelpMarkdownSegment>[];
  var text = <String>[];

  void flushText() {
    if (text.isEmpty) return;
    final joined = text.join('\n');
    if (joined.trim().isNotEmpty) segments.add(HelpTextSegment(joined));
    text = <String>[];
  }

  var line = 0;
  while (line < lines.length) {
    final fold = _foldBlockAt(lines, line);
    if (fold == null) {
      text.add(lines[line]);
      line++;
      continue;
    }
    flushText();
    segments.add(fold.segment);
    line = fold.nextLine;
  }
  flushText();
  return segments;
}

/// 折叠块的识别结果：认出来（块 + 标题行 + 闭合行），或认出写坏（出错的那一
/// 行 + 原因）。装载切段与内容校验都读同一份判定。
sealed class _FoldOutcome {
  const _FoldOutcome();
}

final class _FoldRecognized extends _FoldOutcome {
  const _FoldRecognized({
    required this.segment,
    required this.summaryLine,
    required this.closeLine,
  });

  final HelpFoldSegment segment;

  /// `<summary>` 那一行的行号（0 起）。
  final int summaryLine;

  /// `</details>` 那一行的行号（0 起）。
  final int closeLine;

  /// 块后第一行（0 起）。
  int get nextLine => closeLine + 1;
}

/// 写坏的折叠块：出错的那一行（0 起）与原因。
final class _FoldBroken extends _FoldOutcome {
  const _FoldBroken({required this.line, required this.reason});

  final int line;
  final String reason;
}

/// [line] 处的 `<details>` 判定一次：认出来给 [_FoldRecognized]，认不出给
/// [_FoldBroken]（哪一行、为什么）。装载切段（[helpMarkdownSegments]）与内容
/// 校验（[helpMarkdownIssues]）都走这一份，折叠块文法只有这一处。
_FoldOutcome _foldOutcomeAt(List<String> lines, int line) {
  _FoldBroken broken(int at, String reason) =>
      _FoldBroken(line: at, reason: reason);
  if (!_detailsOpenLine.hasMatch(lines[line])) {
    return broken(line, '折叠块要独立成段：`<details>` 自己占一行、不缩进、不带属性，前后留空行');
  }
  // 自己占一块：篇首或前面有空行。
  if (line > 0 && lines[line - 1].trim().isNotEmpty) {
    return broken(line, '`<details>` 前面要空一行（不能紧接上一段）');
  }
  final summaryLine = line + 1;
  if (summaryLine >= lines.length ||
      !_summaryLine.hasMatch(lines[summaryLine])) {
    if (summaryLine < lines.length &&
        lines[summaryLine].contains('<summary')) {
      return broken(
        summaryLine,
        '`<summary>标题</summary>` 要单行写完，并紧跟 `<details>` 的下一行',
      );
    }
    for (var misplaced = summaryLine; misplaced < lines.length; misplaced++) {
      if (_summaryLine.hasMatch(lines[misplaced])) {
        return broken(misplaced, '`<summary>` 要紧跟 `<details>` 的下一行');
      }
      if (_detailsCloseLine.hasMatch(lines[misplaced])) break;
    }
    return broken(line, '折叠块缺 `<summary>`');
  }
  final title = _summaryLine.firstMatch(lines[summaryLine])!.group(1)!.trim();
  if (title.isEmpty) return broken(summaryLine, '`<summary>` 的标题不能为空');
  int? malformedClose;
  for (var close = summaryLine + 1; close < lines.length; close++) {
    // 嵌套的折叠块不认（缩进或引用块形式的也算）。
    if (_nestedDetails.hasMatch(lines[close])) {
      return broken(close, '不支持嵌套的折叠块');
    }
    if (!_detailsCloseLine.hasMatch(lines[close])) {
      malformedClose ??= _hasTag(lines[close], 'details', closing: true)
          ? close
          : null;
      continue;
    }
    // 后面也要有空行（或篇末）。
    if (close + 1 < lines.length && lines[close + 1].trim().isNotEmpty) {
      return broken(close, '`</details>` 后面要空一行（不能紧跟正文）');
    }
    return _FoldRecognized(
      segment: HelpFoldSegment(
        title: title,
        markdown: lines.sublist(summaryLine + 1, close).join('\n'),
      ),
      summaryLine: summaryLine,
      closeLine: close,
    );
  }
  if (malformedClose != null) {
    return broken(malformedClose, '`</details>` 要独立成行（不缩进、不带其它字符）');
  }
  return broken(line, '折叠块漏 `</details>`');
}

/// [line] 处是一个折叠块时给出它与块后第一行的行号；否则 null。
({HelpFoldSegment segment, int nextLine})? _foldBlockAt(
  List<String> lines,
  int line,
) {
  final outcome = _foldOutcomeAt(lines, line);
  return outcome is _FoldRecognized
      ? (segment: outcome.segment, nextLine: outcome.nextLine)
      : null;
}

/// 一个「算标签」的 HTML 记号：`<tag …>` / `</tag>` 成形才算；
/// 普通文字里的尖括号（`1 < 2`）不成记号。注释另有 [_htmlComment]。
final RegExp _htmlTag = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9-]*)(?:\s[^<>]*)?/?>');

/// HTML 注释的开头；注释不是折叠块那一对标签，由校验报出。
final RegExp _htmlComment = RegExp('<!--');

/// 该行 ATX 标题的级别（本方言只认一至三级）；不是标题时 0。
int _atxHeadingLevel(String line) {
  for (var level = 1; level <= 3; level++) {
    if (atxHeadingLine(level).hasMatch(line)) return level;
  }
  return 0;
}

/// 行内有没有某个 HTML 标签（[closing] 区分开闭）。
bool _hasTag(String line, String name, {required bool closing}) => _htmlTag
    .allMatches(line)
    .any(
      (match) =>
          match.group(2)!.toLowerCase() == name &&
          (match.group(1) == '/') == closing,
    );

/// 一条内容问题：出错的条目 + 正文行号（1 起）+ 原因。
class HelpMarkdownIssue {
  const HelpMarkdownIssue({
    required this.entryName,
    required this.line,
    required this.reason,
  });

  /// 条目名。
  final String entryName;

  /// 正文行号，1 起。
  final int line;

  final String reason;

  /// 「条目名 + 行号 + 原因」一行；测试失败信息与提测前的报错都读它。
  String get message => '「$entryName」第 $line 行：$reason';

  @override
  String toString() => message;
}

/// 校验一个条目的正文原文：写坏的折叠块与折叠块以外的 HTML 各报
/// 一条，带条目名与行号；空列表 = 通过。
///
/// 折叠块的识别口径与装载切段是同一份（[_foldBlockAt]，即
/// [helpMarkdownSegments] 用的那份）：认不出的 `<details>` 逐处报出原因——
/// 它在 App 里是无声消失，这道校验是唯一防线。
List<HelpMarkdownIssue> helpMarkdownIssues({
  required String entryName,
  required String markdown,
}) {
  final lines = const LineSplitter().convert(markdown);
  final byLine = <int, List<String>>{};
  void report(int index, String reason) =>
      (byLine[index] ??= <String>[]).add(reason);

  // 折叠块占用的行范围：认出的块与认不出的「试图写成块」的块。范围内不再单独
  // 报 `<summary>` / `</details>` 游离——整块已经有一条原因了。
  final folds = <({int open, int close})>[];
  for (var line = 0; line < lines.length; line++) {
    if (!_hasTag(lines[line], 'details', closing: false)) continue;
    switch (_foldOutcomeAt(lines, line)) {
      case _FoldRecognized(
        summaryLine: final summaryLine,
        closeLine: final closeLine,
        nextLine: final nextLine,
      ):
        folds.add((open: line, close: closeLine));
        for (var body = summaryLine + 1; body < closeLine; body++) {
          final level = _atxHeadingLevel(lines[body]);
          if (level > 0) {
            report(body, '折叠块内不许出现 $level 级标题：收起时块内不在渲染树里，锚点会落空');
          }
          if (_summaryLine.hasMatch(lines[body])) {
            report(body, '折叠块内多了一行 `<summary>`：它会被当成根级 HTML 丢弃');
          }
        }
        line = nextLine - 1;
        continue;
      case _FoldBroken(line: final brokenLine, reason: final reason):
        final close = _attemptedFoldClose(lines, line);
        folds.add((open: line, close: close));
        report(brokenLine, reason);
        line = close;
    }
  }

  bool inFold(int index) =>
      folds.any((fold) => index > fold.open && index <= fold.close);

  for (var line = 0; line < lines.length; line++) {
    final source = lines[line];
    for (final match in _htmlTag.allMatches(source)) {
      final name = match.group(2)!.toLowerCase();
      if (name == 'details' || name == 'summary') continue;
      report(line, '正文里出现折叠块以外的 HTML 标签 `${match.group(0)}`');
    }
    if (_htmlComment.hasMatch(source)) {
      report(line, '正文里出现 HTML 注释：内嵌 HTML 只认折叠块那一对标签');
    }
    if (inFold(line)) continue;
    if (_hasTag(source, 'details', closing: false)) continue;
    if (_hasTag(source, 'summary', closing: false)) {
      report(line, '`<summary>` 不属于任何折叠块');
    } else if (_hasTag(source, 'details', closing: true)) {
      report(line, '`</details>` 没有对应的 `<details>`');
    }
  }

  final reported = byLine.keys.toList()..sort();
  return [
    for (final index in reported)
      for (final reason in byLine[index]!)
        HelpMarkdownIssue(entryName: entryName, line: index + 1, reason: reason),
  ];
}

/// 一处认不出的 `<details>` 占到哪一行为止：下一个带 `</details>` 的行（或
/// 下一个 `<details>` 之前，或篇末）——闭合行写得不合形状时也不能吞掉后文。
int _attemptedFoldClose(List<String> lines, int open) {
  for (var line = open + 1; line < lines.length; line++) {
    if (_hasTag(lines[line], 'details', closing: true)) return line;
    if (_hasTag(lines[line], 'details', closing: false)) return line - 1;
  }
  return lines.length - 1;
}

/// 一条标题的锚点信息：原文与 slug。
class HelpHeading {
  const HelpHeading({required this.text, required this.slug});

  /// 标题原文（行内标记已被解析器剥掉后的纯文本）。
  final String text;

  /// 按与 VSCode 预览、GitHub 同一套算法从原文算出的 slug。
  final String slug;
}

/// 标题的 slug（与 VSCode 预览、GitHub 同一套）：trim、全小写、去掉标点与
/// 符号（字母、数字与下划线一律保留），空白变 `-`。`方法三：电脑下载B站视频`
/// 得 `方法三电脑下载b站视频`。
String helpHeadingSlug(String text) {
  final lowered = text.trim().toLowerCase();
  final stripped = lowered.replaceAll(
    RegExp(r'[^\p{L}\p{N}\s_-]', unicode: true),
    '',
  );
  return stripped.replaceAll(RegExp(r'\s'), '-');
}

/// Markdown 正文里的标题表：一级到三级标题按出现顺序给出原文与 slug。折叠块
/// 块体内的行不参与——块内内容收起时不在渲染树里、不登记锚点，
/// 标题表就是锚点真能落点的那一份：指向块内标题的链接因此解析不到，走越界兜底。
List<HelpHeading> helpHeadings(String markdown) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final result = <HelpHeading>[];
  void visit(List<md.Node> nodes) {
    for (final node in nodes) {
      if (node is! md.Element) continue;
      if (const {'h1', 'h2', 'h3'}.contains(node.tag)) {
        final text = node.textContent.trim();
        result.add(HelpHeading(text: text, slug: helpHeadingSlug(text)));
      }
      visit(node.children ?? const []);
    }
  }

  final lines = LineSplitter().convert(_withoutFoldBodies(markdown));
  visit(document.parseLines(lines));
  return result;
}

/// 把折叠块块体内的行换成空行：`<details>` / `<summary>` / `</details>` 三行
/// 保留，块的识别与装载切段走同一份判定（[_foldOutcomeAt]）。
String _withoutFoldBodies(String markdown) {
  final lines = LineSplitter().convert(markdown);
  for (var line = 0; line < lines.length; line++) {
    final outcome = _foldOutcomeAt(lines, line);
    if (outcome is! _FoldRecognized) continue;
    for (var body = outcome.summaryLine + 1; body < outcome.closeLine; body++) {
      lines[body] = '';
    }
    line = outcome.nextLine - 1;
  }
  return lines.join('\n');
}

/// 解析正文里的一个锚点（已去掉 `#`）：标题 slug 精确命中优先；匹配不到再
/// 退一步按标题原文**前缀**匹配，唯一命中才算（这一手只在 App 内有效）；
/// 都找不到、或前缀命中多条标题时返回 null——调用方不滚、不报错。
String? resolveHelpAnchor(List<HelpHeading> headings, String anchor) {
  final slugHits = [
    for (final heading in headings)
      if (heading.slug == anchor) heading,
  ];
  if (slugHits.length == 1) return slugHits.single.slug;
  if (slugHits.length > 1) return null;
  final prefixHits = [
    for (final heading in headings)
      if (heading.text.startsWith(anchor)) heading,
  ];
  return prefixHits.length == 1 ? prefixHits.single.slug : null;
}

/// 用与渲染器同一份解析器取一级标题、列表页那句说明与图片引用；正文本身
/// 不改。
///
/// 「段落」只认**正文级**节点：引用块与列表项里的段落不算（一句说明 =
/// 一级标题之后的第一段），否则第二个教程的提示块会被当成列表页那句说明。
({String? title, String? listParagraph, List<String> imageSources})
parseHelpMarkdown(String markdown) {
  final document = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  );
  final nodes = document.parseLines(const LineSplitter().convert(markdown));
  final imageSources = <String>[];
  String? title;
  String? listParagraph;
  void visit(List<md.Node> nodes, {required bool inBody}) {
    for (final node in nodes) {
      if (node is! md.Element) continue;
      if (inBody) {
        if (node.tag == 'h1') {
          title ??= node.textContent;
        } else if (node.tag == 'p') {
          final text = node.textContent.trim();
          if (text.isNotEmpty && title != null) listParagraph ??= text;
        }
      }
      if (node.tag == 'img') {
        final source = node.attributes['src'];
        if (source != null) imageSources.add(source);
      }
      visit(node.children ?? const [], inBody: false);
    }
  }

  visit(nodes, inBody: true);
  return (
    title: title,
    listParagraph: listParagraph,
    imageSources: imageSources,
  );
}
