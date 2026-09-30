/// 帮助内容装载：随包文件 → 渲染模型。
///
/// 对外的输入是一个可注入的 [AssetBundle]（默认 [rootBundle]，测试经
/// [helpAssetBundleProvider] 覆盖成假资产）；对外只暴露一个 Riverpod 异步
/// provider [helpContentProvider]：引导文案查表与帮助文档条目表同住这条缝。
///
/// 正文的 Markdown 文法（段切、折叠块、标题锚点）住在 [help_markdown.dart]，
/// 本件只把扫到的资产按那份口径切成渲染模型。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_registry.dart';
import 'guide_copy.dart';
import 'help_markdown.dart';

const String onboardingCopyAssetKey = 'assets/help/onboarding.yaml';

/// 使用手册与教程两组条目的资产根目录（目录条目不递归，条目 = 其下的一个
/// 子目录）。
const String helpGuideAssetDirectory = 'assets/help/guide';
const String helpTutorialsAssetDirectory = 'assets/help/tutorials';

/// 装载用的资产包注入点（默认随包资产；测试喂假资产）。帮助内容与关于页内容
/// 共用这一处，不各设一个同形注入点。
final helpAssetBundleProvider = Provider<AssetBundle>((ref) => rootBundle);

/// 帮助内容（单一异步 provider 的载荷）：引导文案查表 +
/// 使用手册条目表 + 教程条目表。两组条目都由扫到的内容目录现算。
class HelpContent {
  const HelpContent({
    required this.guideCopy,
    required this.manualChapters,
    required this.tutorials,
  });

  final GuideCopy guideCopy;

  /// 使用手册条目（`assets/help/guide/` 下每条一个目录），按目录名数字前缀排序。
  final List<HelpDocumentContent> manualChapters;

  /// 教程条目（`assets/help/tutorials/` 下每条一个目录），按数字前缀排序。
  final List<HelpDocumentContent> tutorials;

  /// 全部条目的合并清单（手册在前、教程次之），按 id 查条目与全量遍历共用。
  List<HelpDocumentContent> get allDocuments => [...manualChapters, ...tutorials];

  /// 全部条目合起来按 id 查条目；找不到为 null。
  HelpDocumentContent? document(String id) {
    for (final entry in allDocuments) {
      if (entry.id == id) return entry;
    }
    return null;
  }
}

/// 一个帮助条目的渲染模型：正文原文 + 从正文推导出的内容。缺正文时正文为
/// 空串、标题为 null；引用但不在盘上的图片不进 [imageAssets]，渲染时跳过、
/// 不留空框。
class HelpDocumentContent {
  const HelpDocumentContent({
    required this.id,
    required this.directory,
    required this.markdown,
    required this.bodyMarkdown,
    required this.bodySegments,
    required this.firstSectionMarkdown,
    required this.firstSectionSegments,
    required this.title,
    required this.imageAssets,
    required this.listParagraph,
    required this.headings,
  });

  /// 条目 id = 目录名去掉数字前缀。
  final String id;

  /// 条目目录资产 key（`assets/help/tutorials/01-下载视频`）。
  final String directory;

  /// 正文原文（一字不改）；目录里没有 Markdown 时为空串。
  final String markdown;

  /// 去掉首个一级标题行之后的正文；页面渲染它、内容校验拿 [markdown] 原文。
  /// 没有一级标题时与 [markdown] 相同；目录里没有 Markdown 时为空串。
  final String bodyMarkdown;

  /// [bodyMarkdown] 的段序列（装载侧按折叠块标记切段）：普通段与折叠段交替。
  final List<HelpMarkdownSegment> bodySegments;

  /// 一次性图文卡正文的原文：第一个二级标题那一行起、到下一个二级标题之前
  /// （没有下一个时到篇末）；一个二级标题都没有时为空串——卡里只剩卡头与
  /// 两个出口按钮。
  final String firstSectionMarkdown;

  /// [firstSectionMarkdown] 的段序列；卡只渲染这一节，折叠块跟着它所在的
  /// 那一节走。
  final List<HelpMarkdownSegment> firstSectionSegments;

  /// 正文的一级标题文本；没有一级标题时为 null。
  final String? title;

  /// 正文引用且**确实存在**的同目录图片资产 key，按正文出现顺序。
  final Set<String> imageAssets;

  /// 一级标题之后的第一个正文级段落；没有一级标题、或其后没有段落时为 null
  /// （列表页那句说明取它）。引用块与列表项里的段落不算。
  final String? listParagraph;

  /// 本文的标题表：正文里各级标题的原文与 slug，按出现顺序；正文里的 `#…`
  /// 锚点按它解析。
  final List<HelpHeading> headings;

  /// 列表与页标题的显示名：正文一级标题，缺标题时退回条目 id（目录名去数字
  /// 前缀）——缺正文、无一级标题的条目照常出现在列表里。
  String get displayTitle => title ?? id;

  /// 列表页的一句说明：一级标题之后的第一段；无一级标题或其后无段落时留空。
  String? get listDescription => title == null ? null : listParagraph;
}

/// 列表行图标按条目 id 查的常量表：已登记的条目按表取
/// 图标；缺登记的条目取调用方给的兜底图标，新加条目不登记也照常显示。
/// 「分段」与播放器「自动分段」槽、「节拍」与播放器节拍提示槽同枚。
const Map<String, IconData> helpEntryIcons = {
  'Susume使用概览': Icons.dashboard_outlined,
  '快捷手势': Icons.touch_app_outlined,
  '控制界面概述': Icons.tune,
  '节拍': Icons.graphic_eq,
  '分段': Icons.view_week,
  '备注与镜像': Icons.sticky_note_2_outlined,
  '对比练习': Icons.compare,
  '统计': Icons.bar_chart_outlined,
  '计划': Icons.event_note_outlined,
  '分享与备份': Icons.ios_share_outlined,
  '下载视频': Icons.file_download_outlined,
  '免费视频变清晰': Icons.auto_fix_high,
  '问题反馈': Icons.feedback_outlined,
  '已知的问题': Icons.bug_report_outlined,
};

/// 使用手册条目缺登记时的兜底图标。
const IconData helpManualEntryFallbackIcon = Icons.menu_book_outlined;

/// 教程条目缺登记时的兜底图标。
const IconData helpTutorialEntryFallbackIcon = Icons.school_outlined;

/// 一条帮助条目的列表行图标：按 id 查 [helpEntryIcons]，缺登记时取调用方给的
/// [fallbackIcon]（帮助中心的教程分组给教程那枚、使用手册分组给手册那枚）。
IconData helpEntryIcon(String id, {required IconData fallbackIcon}) =>
    helpEntryIcons[id] ?? fallbackIcon;

/// 帮助内容装载的注入点（默认随包资产）。
final helpContentProvider = FutureProvider<HelpContent>(
  (ref) => loadHelpContent(ref.watch(helpAssetBundleProvider)),
);

/// 装载结果里该条目的渲染模型；装载中或装载失败时为 null（调用方取兜底）。
HelpDocumentContent? loadedHelpDocument(WidgetRef ref, String id) =>
    ref.watch(helpContentProvider).asData?.value.document(id);

/// 装载帮助内容：读 `assets/help/onboarding.yaml` 解析成引导文案，并扫
/// `assets/help/guide/` 与 `assets/help/tutorials/` 下登记的条目目录，各读其
/// Markdown 正文。
///
/// 文案文件读不出 / 解析失败即引导文案全空、帮助中心照常；某个条目读不出正文
/// 按「缺正文」处理（正文空串），不牵连其它条目。两者都在开发期由断言打出原因。
Future<HelpContent> loadHelpContent(AssetBundle bundle) async {
  GuideCopy guide;
  try {
    guide = parseGuideCopy(
      await bundle.loadString(onboardingCopyAssetKey, cache: false),
    );
  } on Object catch (error) {
    assert(() {
      debugPrint('引导文案装载失败，按全空处理：$error');
      return true;
    }());
    guide = GuideCopy.empty;
  }
  final keys = await loadAssetKeys(bundle);
  return HelpContent(
    guideCopy: guide,
    manualChapters: await _scanGroup(bundle, keys, helpGuideAssetDirectory),
    tutorials: await _scanGroup(bundle, keys, helpTutorialsAssetDirectory),
  );
}

/// 资产清单的 key 全集；读不出时按空处理（调用方照常开得了、只是没有条目），
/// 开发期由断言打出原因。扫目录的装载件共用这一份清单。
Future<List<String>> loadAssetKeys(AssetBundle bundle) async {
  try {
    return (await AssetManifest.loadFromAssetBundle(bundle)).listAssets();
  } on Object catch (error) {
    assert(() {
      debugPrint('资产清单装载失败，帮助条目按空处理：$error');
      return true;
    }());
    return const [];
  }
}

/// 扫 [groupDirectory] 下的条目目录（每个直接子目录一条），按目录名数字前缀
/// 排序后逐条装载正文。
Future<List<HelpDocumentContent>> _scanGroup(
  AssetBundle bundle,
  List<String> keys,
  String groupDirectory,
) async {
  final directories = <String>[];
  for (final key in keys) {
    if (!key.startsWith('$groupDirectory/')) continue;
    final rest = key.substring(groupDirectory.length + 1);
    final slash = rest.indexOf('/');
    // 组根目录下的文件不构成条目；条目 = 至少再深一层的子目录。
    if (slash <= 0) continue;
    final directory = '$groupDirectory/${rest.substring(0, slash)}';
    if (!directories.contains(directory)) directories.add(directory);
  }
  directories.sort(_byNumericPrefix);
  return [
    for (final directory in directories)
      await _loadDocumentContent(
        bundle,
        keys,
        id: helpDocumentIdOfDirectory(directory),
        directory: directory,
      ),
  ];
}

/// 目录名数字前缀的比较：前缀小的在前；无前缀的排最后，其余按目录名定序。
int _byNumericPrefix(String a, String b) {
  final byPrefix = _numericPrefixOf(a).compareTo(_numericPrefixOf(b));
  return byPrefix != 0 ? byPrefix : a.compareTo(b);
}

int _numericPrefixOf(String directory) {
  final match = RegExp(r'^(\d+)').firstMatch(directory.split('/').last);
  return match == null ? 1 << 30 : int.parse(match.group(1)!);
}

/// 条目目录下的那份 Markdown 资产 key：目录里可能有任意命名的 `.md`，取
/// 字典序第一份（「恰好一份」由内容校验测试守）；一份都没有时 null（按缺正文
/// 处理）。
String? _markdownKeyInDirectory(List<String> keys, String directory) {
  final inDirectory = [
    for (final key in keys)
      if (key.startsWith('$directory/') && key.endsWith('.md')) key,
  ]..sort();
  return inDirectory.isEmpty ? null : inDirectory.first;
}

/// 装一条帮助文档：在 [directory] 下找那一份 Markdown，读原文并按同一份
/// 解析器取一级标题与图片引用；引用的相对图片名拼成同目录资产 key，只把
/// 确实存在的收进 [HelpDocumentContent.imageAssets]。
Future<HelpDocumentContent> loadHelpDocumentContent(
  AssetBundle bundle, {
  required String id,
  required String directory,
}) async {
  return _loadDocumentContent(
    bundle,
    await loadAssetKeys(bundle),
    id: id,
    directory: directory,
  );
}

Future<HelpDocumentContent> _loadDocumentContent(
  AssetBundle bundle,
  List<String> keys, {
  required String id,
  required String directory,
}) async {
  var markdown = '';
  try {
    final markdownKey = _markdownKeyInDirectory(keys, directory);
    if (markdownKey != null) {
      markdown = await bundle.loadString(markdownKey, cache: false);
      final parsed = parseHelpMarkdown(markdown);
      final body = helpBodyMarkdown(markdown);
      final bodySegments = helpMarkdownSegments(body);
      final firstSection = helpFirstSectionMarkdown(body);
      final imageAssets = _existingImageAssets(
        directory,
        [
          ...parsed.imageSources,
          // 折叠块在 Markdown 解析器眼里是整块 HTML，拿不到 img 节点；按同一份
          // 切段结果单独解析块内 Markdown，块内图片照常解析到同目录资产。
          for (final segment in bodySegments)
            if (segment is HelpFoldSegment)
              ...parseHelpMarkdown(segment.markdown).imageSources,
        ],
        keys,
      );
      return HelpDocumentContent(
        id: id,
        directory: directory,
        markdown: markdown,
        bodyMarkdown: body,
        bodySegments: bodySegments,
        firstSectionMarkdown: firstSection,
        firstSectionSegments: helpMarkdownSegments(firstSection),
        title: parsed.title,
        imageAssets: imageAssets,
        listParagraph: parsed.listParagraph,
        // 标题表取整篇（含一级标题）：指向本文自身一级标题的锚点也解析得到。
        headings: helpHeadings(markdown),
      );
    }
  } on Object catch (error) {
    assert(() {
      debugPrint('帮助文档装载失败，$directory 按缺正文处理：$error');
      return true;
    }());
  }
  return HelpDocumentContent(
    id: id,
    directory: directory,
    markdown: markdown,
    bodyMarkdown: markdown,
    // 正文读到过、但解析中途出错时，把已读到的正文按整段普通文本渲染，不因
    // 解析失败整篇消失。
    bodySegments: _rawTextSegments(markdown),
    firstSectionMarkdown: markdown,
    firstSectionSegments: _rawTextSegments(markdown),
    title: null,
    imageAssets: const {},
    listParagraph: null,
    headings: const [],
  );
}

/// 解析失败时的降级正文段：整篇按一段普通 Markdown 交渲染件；没有正文时为空。
List<HelpMarkdownSegment> _rawTextSegments(String markdown) =>
    markdown.isEmpty ? const [] : [HelpTextSegment(markdown)];

/// 正文里的相对图片名 → 同目录资产 key；带 scheme 的地址不属于本方言，
/// 返回 null（不解析成资产）。`./` 前缀按目录内相对路径归位。
String? helpImageAssetKey(String directory, String source) {
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme.isNotEmpty) return null;
  var path = uri.path;
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  if (path.isEmpty) return null;
  return '$directory/$path';
}

/// 正文引用的图片里，确实在清单上的那些（缺图不入集，渲染时跳过）。
Set<String> _existingImageAssets(
  String directory,
  List<String> sources,
  List<String> keys,
) {
  final existing = <String>{};
  for (final source in sources) {
    final key = helpImageAssetKey(directory, source);
    if (key != null && keys.contains(key)) existing.add(key);
  }
  return existing;
}

/// 正文里一条能跨条目跳转的链接：目标条目 id 与（可空的）目标锚点（已去掉
/// `#`）。
class HelpEntryLink {
  const HelpEntryLink({required this.documentId, this.anchor});

  /// 目标条目 id（目录名去数字前缀）。
  final String documentId;

  /// 目标条目的锚点；链接不带 `#` 时为 null（落在目标页面顶部）。
  final String? anchor;
}

/// 把一个正文链接地址解析到另一个帮助条目：地址相对本文
/// 所在目录 [directory]（形如 `assets/help/guide/02-控制界面概述`），可带
/// `#标题` 锚点。解析不到条目（写错路径、或不是仓内相对路径）、或锚点**在目标
/// 条目的标题表里不唯一命中**时返回 null——调用方按外部链接处理，不弹错。
///
/// `#` 之后的锚点交给 [resolveHelpAnchor]（唯一命中 slug，退回唯一前缀命中）；
/// 渲染器交回的地址是百分号转义的，解析前先解回。
HelpEntryLink? resolveHelpEntryLink({
  required HelpContent content,
  required String directory,
  required String href,
}) {
  if (href.isEmpty || href.startsWith('#') || href.startsWith('//')) {
    return null;
  }
  final hash = href.indexOf('#');
  final rawPath = hash < 0 ? href : href.substring(0, hash);
  final rawAnchor = hash < 0 ? null : href.substring(hash + 1);
  if (rawPath.isEmpty) return null;
  if (Uri.tryParse(rawPath)?.scheme.isNotEmpty ?? false) return null;
  final path = decodeHelpLinkPart(rawPath);
  if (!path.toLowerCase().endsWith('.md')) return null;

  final segments = directory.split('/')..removeWhere((part) => part.isEmpty);
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (segments.isEmpty) return null;
      segments.removeLast();
      continue;
    }
    segments.add(part);
  }
  // 去掉正文文件名那一段，剩下的是目标条目目录。
  if (segments.length < 2) return null;
  final targetDirectory = segments.sublist(0, segments.length - 1).join('/');
  final document = content.document(helpDocumentIdOfDirectory(targetDirectory));
  if (document == null) return null;

  final anchor = rawAnchor == null ? null : decodeHelpLinkPart(rawAnchor);
  if (anchor != null && resolveHelpAnchor(document.headings, anchor) == null) {
    return null;
  }
  return HelpEntryLink(documentId: document.id, anchor: anchor);
}

/// 链接地址里的一段：百分号转义解回中文；含不完整转义序列或非 URI 字符的原文
/// 原样返回，不报错（`Uri.decodeComponent` 对中文原文抛 [ArgumentError]）。
/// 解析与渲染两侧共用——渲染器交回的都是同一个转义形式。
String decodeHelpLinkPart(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } on FormatException {
    return raw;
  } on ArgumentError {
    return raw;
  }
}

/// 正文里的一条行内链接：`[文字](地址)`；图片语法 `![…](…)` 由第一个捕获组
/// 区分出来，不算。
final RegExp _helpInlineLink = RegExp(r'(!?)\[[^\]]*\]\(([^)\s]+)\)');

/// 内容校验：正文里两类链接各自的落点都得成立——
/// `](#锚点)` 必须在本文标题表里唯一命中；`](相对路径.md)` 必须解析到一个已被
/// 扫到的条目，且带的锚点在**目标条目**的标题表里唯一命中。外部网址（带
/// scheme）与图片语法不算。一条链接一处问题，带条目名与行号。
List<HelpMarkdownIssue> helpLinkIssues({
  required HelpContent content,
  required HelpDocumentContent entry,
}) {
  final lines = const LineSplitter().convert(entry.markdown);
  final issues = <HelpMarkdownIssue>[];
  for (var index = 0; index < lines.length; index++) {
    for (final match in _helpInlineLink.allMatches(lines[index])) {
      if (match.group(1) == '!') continue;
      final reason = _linkIssueReason(content, entry, match.group(2)!);
      if (reason == null) continue;
      issues.add(
        HelpMarkdownIssue(entryName: entry.id, line: index + 1, reason: reason),
      );
    }
  }
  return issues;
}

/// 一条链接写坏的原因；这条链接落点成立、或不属于本方言时 null。
///
/// 只有两类链接受校验：本文锚点 `#…`，与仓内相对 Markdown 路径 `…​.md`。带
/// scheme 的网址与不以 `.md` 收尾的相对地址都不属于**条目链接**方言——运行时
/// 按链接第三路处理（外部网址交系统浏览器，其余复制到剪贴板），这里也不拦
/// （校验与运行时同一条口径）。
String? _linkIssueReason(
  HelpContent content,
  HelpDocumentContent entry,
  String href,
) {
  if (href.startsWith('#')) {
    final anchor = href.substring(1);
    return resolveHelpAnchor(entry.headings, anchor) == null
        ? '本文锚点 `#$anchor` 在本文标题表里找不到唯一命中的标题'
        : null;
  }
  if (Uri.tryParse(href)?.scheme.isNotEmpty ?? false) return null;
  final path = href.split('#').first;
  if (!path.toLowerCase().endsWith('.md')) return null;
  final link = resolveHelpEntryLink(
    content: content,
    directory: entry.directory,
    href: href,
  );
  return link == null
      ? '`$href` 解析不到一个已被扫到的帮助条目，或它带的锚点在目标条目里不唯一命中'
      : null;
}
