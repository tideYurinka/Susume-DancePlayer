import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import 'help_documents.dart';
import 'help_image_save.dart';
import 'help_image_viewer.dart';
import 'help_markdown.dart';
import 'help_snack_bar.dart';
import 'platform_help_actions.dart' show helpExternalLinkOpenerProvider;

/// 条目 Markdown 正文的渲染件：文档页与一次性图文卡走同一套解析、图片画法
/// 与链接行为。正文按装载侧切好的段渲染——普通段整段交渲染器，折叠块包一层
/// 「一行标题 + 展开箭头」的展开件、默认收起、点开才出现块内内容。
/// 图片按宽度铺满、保持原比例，不裁切；折叠块里的图取可用宽度的
/// 六成并居中（赞赏码这类图铺满会占掉整屏），可用宽度按渲染件拿到的约束算；
/// 缺图（引用但不在盘上的、不属于本方言的地址）不渲染、不留空框。单击一张已
/// 渲染的图弹全屏查看器（**大图查看**，见 [HelpImageViewer]）。链接点一下
/// 只有这一处决策（卡与文档页共用）：`#…` 锚点滚到本文那条标题——先预载该条目
/// 的图片再滚，落点不被图片撑高带偏；解析到但目标标题不在当前渲染范围内时交
/// [onOpenDocumentAnchor]（卡用它打开完整正文页）；仓内相对路径解析到一个
/// 帮助条目时交 [onOpenEntry]（宿主推入目标条目的文档页，可带锚点）；解析不到
/// 就不滚、不报错；其余按
/// **外部网址**处理——带 `http`/`https` scheme 的交系统浏览器打开，打不开时
/// 复制地址并提示「打不开，已复制地址」；不带 scheme（如群号）或带其它
/// scheme 的复制地址并提示「已复制」，不弹「即将离开应用」的二次确认。折叠块内
/// 的标题照常渲染成标题，但不登记锚点（收起时块内内容不在渲染树里）。
///
/// [compact] 为 true 时用一次性图文卡内的一档收紧字号（卡宽 320，渲染器
/// 默认的二级标题会大过卡头）：二级标题 15 加粗、三级标题 14 加粗、正文与
/// 列表 14、提示块 14；文档页宽，保持渲染器默认。
class HelpMarkdownBody extends ConsumerStatefulWidget {
  const HelpMarkdownBody({
    super.key,
    required this.document,
    required this.segments,
    this.compact = false,
    this.padding = const EdgeInsets.all(16),
    this.initialAnchor,
    this.onOpenDocumentAnchor,
    this.onOpenEntry,
  });

  /// 正文所属条目：图片按它的目录归位同目录资产、按它的图片集判断存在、
  /// 锚点按它的标题表解析。
  final HelpDocumentContent document;

  /// 要渲染的正文段（装载侧按折叠块标记切好；文档页 = 去一级标题正文，
  /// 卡 = 第一个二级标题那一节的切片）。
  final List<HelpMarkdownSegment> segments;

  final bool compact;

  /// 正文区内边距；文档页给页边距，一次性图文卡内为不另加（卡自带内边距）。
  final EdgeInsetsGeometry padding;

  /// 进入时的落点锚点（已去掉 `#`）：文档页被带锚点打开时用它停到那条标题，
  /// 只在首帧生效；null = 不滚。
  final String? initialAnchor;

  /// 锚点解析到本文、但目标标题**不在本渲染范围内**（如卡里切片外的节）时
  /// 的回调：一次性图文卡用它打开完整正文页并停在目标标题。null 时不滚、
  /// 不报错。
  final void Function(String anchor)? onOpenDocumentAnchor;

  /// 正文链接解析到一个帮助条目时的回调：宿主推入该条目的文档页并停在它带的
  /// 锚点（可空 = 目标页顶部）。null 时该链接按外部链接处理。
  final void Function(HelpEntryLink link)? onOpenEntry;

  @override
  ConsumerState<HelpMarkdownBody> createState() => _HelpMarkdownBodyState();
}

class _HelpMarkdownBodyState extends ConsumerState<HelpMarkdownBody> {
  /// 渲染范围内每条标题的落点（slug → 标题块）：锚点跳转按它定位滚动。
  /// 重复 slug 只有第一个标题登记，锚点滚到第一处。
  final Map<String, GlobalKey> _headingKeys = {};

  @override
  void initState() {
    super.initState();
    // 带锚点进入（如从图文卡打开完整正文）：标题落点等首帧渲染完才登记，
    // 帧尾再走同一条「先预载图、后滚动」的链路。
    if (widget.initialAnchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToAnchor(widget.initialAnchor!);
      });
    }
  }

  @override
  void didUpdateWidget(covariant HelpMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了正文（如卡内切片变化）后旧标题的落点全部失效，登记清空重建。
    if (!identical(oldWidget.segments, widget.segments)) _headingKeys.clear();
  }

  @override
  Widget build(BuildContext context) {
    final bundle = ref.watch(helpAssetBundleProvider);
    final styleSheet = widget.compact
        ? _compactStyleSheet(Theme.of(context))
        : null;
    // [MarkdownBody] 不自带滚动：文档页整页滚，一次性图文卡在卡内滚——
    // 都由各自的滚动容器承担。段与段之间按渲染器的块间距隔开。
    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          for (final segment in widget.segments)
            switch (segment) {
              // 块内标题不登记锚点（收起时不在渲染树里，锚点跳过去会落空）。
              HelpFoldSegment(:final title, :final markdown) => _FoldBlock(
                title: title,
                child: _markdown(bundle, markdown, styleSheet, folded: true),
              ),
              HelpTextSegment(:final markdown) => _markdown(
                bundle,
                markdown,
                styleSheet,
                builders: {
                  for (final level in const {'h1', 'h2', 'h3'})
                    level: _AnchorHeadingBuilder(_headingKeys),
                },
              ),
            },
        ],
      ),
    );
  }

  /// 一段 Markdown 的渲染：图片画法与链接行为两处共用；[builders] 为空时
  /// 标题按渲染器默认渲染（折叠块内的标题不登记落点）；[folded] 为 true 时
  /// 图片按六成宽度居中（见 [_image]）。
  Widget _markdown(
    AssetBundle bundle,
    String data,
    MarkdownStyleSheet? styleSheet, {
    Map<String, MarkdownElementBuilder> builders = const {},
    bool folded = false,
  }) {
    return MarkdownBody(
      data: data,
      styleSheet: styleSheet,
      onTapLink: (text, href, title) => _onTapLink(href),
      imageBuilder: (uri, title, alt) => _image(
        ref,
        bundle,
        context,
        widget.document,
        uri,
        alt: alt,
        folded: folded,
      ),
      builders: builders,
    );
  }

  /// 链接处理唯一决策点：
  /// 本文内锚点滚过去，仓内相对路径推入目标条目，其余按外部网址处理——带
  /// `http`/`https` 的交系统浏览器打开、打不开走复制，其余 scheme 与无 scheme
  /// 直接复制。
  Future<void> _onTapLink(String? href) async {
    if (href == null) return;
    if (href.startsWith('#')) {
      _scrollToAnchor(decodeHelpLinkPart(href.substring(1)));
      return;
    }
    final content = await _helpContentForEntryLinks();
    if (!mounted) return;
    final entry = content == null
        ? null
        : resolveHelpEntryLink(
            content: content,
            directory: widget.document.directory,
            href: href,
          );
    final onOpenEntry = widget.onOpenEntry;
    if (entry != null && onOpenEntry != null) {
      onOpenEntry(entry);
      return;
    }
    await _openExternalLink(href);
  }

  /// 解析**条目链接**要读的那份帮助内容注册表：按需取，不因为正文被挂上屏就
  /// 把它拉起来——渲染件是共享件，宿主不必为它多背一条装载依赖。装载还没完成
  /// 就等它（第一次点那种链接也不至于退成外部链接）；装载失败按「解析不到
  /// 条目」处理，链接回到外部网址那一路。
  Future<HelpContent?> _helpContentForEntryLinks() async {
    try {
      return await ref.read(helpContentProvider.future);
    } on Object {
      return null;
    }
  }

  /// 其余链接的落点（第三路）：`http`/`https` 交端口打开，
  /// 打开件说没交出去（设备上没有浏览器、系统拒绝等）就复制地址并提示
  /// 「打不开，已复制地址」；不带 scheme 与其它 scheme 一律复制并提示
  /// 「已复制」。点链接不加「即将离开应用」的二次确认。
  Future<void> _openExternalLink(String href) async {
    final scheme = Uri.tryParse(href)?.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      copyHelpLink(context, href);
      return;
    }
    final opened = await ref.read(helpExternalLinkOpenerProvider).open(href);
    if (!mounted) return;
    if (opened) return;
    copyHelpLink(context, href, message: helpLinkOpenFailedMessage);
  }

  /// 滚到锚点那条标题：先按标题表解析（slug 命中 / 原文前缀兜底）。解析到
  /// 但目标标题不在**本篇渲染范围内**（卡内切片里没有的标题）时交给
  /// [HelpMarkdownBody.onOpenDocumentAnchor]（卡用它打开完整正文页）；解析
  /// 不到、或无人接手就不滚、不报错。滚之前把该条目的图片全部预载，等图片
  /// 排进布局的那一帧过了再按最终布局落点，不被图片撑高带偏。
  Future<void> _scrollToAnchor(String anchor) async {
    final slug = resolveHelpAnchor(widget.document.headings, anchor);
    final headingKey = slug == null ? null : _headingKeys[slug];
    if (headingKey == null) {
      if (slug != null) widget.onOpenDocumentAnchor?.call(anchor);
      return;
    }
    final bundle = ref.read(helpAssetBundleProvider);
    for (final asset in widget.document.imageAssets) {
      if (!mounted) return;
      await precacheImage(AssetImage(asset, bundle: bundle), context);
    }
    if (!mounted) return;
    // 图齐后的第一帧把图片排进布局，滚动量按最终布局算。
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final headingContext = headingKey.currentContext;
    if (headingContext == null || !headingContext.mounted) return;
    final scrollable = Scrollable.of(headingContext);
    final position = scrollable.position;
    final headingBox = headingContext.findRenderObject()! as RenderBox;
    final viewportBox = scrollable.context.findRenderObject()! as RenderBox;
    // 标题顶端在滚动内容里的位置 = 当前偏移 + 它比视口顶端深出的距离。
    final delta =
        headingBox.localToGlobal(Offset.zero).dy -
        viewportBox.localToGlobal(Offset.zero).dy;
    await position.animateTo(
      (position.pixels + delta).clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
}

/// 正文里的一块折叠块：一行标题 + 展开箭头，默认收起、
/// 不记展开状态（每次进页面都是收起）；点一下标题或箭头展开、再点收起，
/// 块内内容按同一套渲染件渲染（图片画法与链接行为与正文共用）。
class _FoldBlock extends StatefulWidget {
  const _FoldBlock({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_FoldBlock> createState() => _FoldBlockState();
}

class _FoldBlockState extends State<_FoldBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[const SizedBox(height: 8), widget.child],
      ],
    );
  }
}

/// 标题块的锚点登记：渲染范围内每条一至三级标题包在一个带 GlobalKey 的子树
/// 下，锚点跳转靠它定位；标题样式仍走渲染器的样式表。
class _AnchorHeadingBuilder extends MarkdownElementBuilder {
  _AnchorHeadingBuilder(this._headingKeys);

  final Map<String, GlobalKey> _headingKeys;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => null;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent.trim();
    final slug = helpHeadingSlug(text);
    final key = _headingKeys.putIfAbsent(slug, GlobalKey.new);
    return KeyedSubtree(
      key: key,
      child: Text(text, style: preferredStyle),
    );
  }
}

/// 一次性图文卡内的一档收紧字号。
MarkdownStyleSheet _compactStyleSheet(ThemeData theme) {
  final body = theme.textTheme.bodyMedium!;
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    h2: theme.textTheme.titleMedium!.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
    h3: body.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
    p: body.copyWith(fontSize: 14),
    listBullet: body.copyWith(fontSize: 14),
    blockquote: body.copyWith(fontSize: 14),
  );
}

/// 折叠块里图片占可用宽度的比例：赞赏码这类图铺满会占掉整屏。
const double _foldedImageWidthFactor = 0.6;

/// 正文里的一张图：相对文件名解析到同目录资产 key，只有确实存在的那张才
/// 渲染；不存在的（以及不属于本方言的绝对地址）什么都不画，不留空框，也就
/// 没有可点区域。宽度按**可用宽度**算——[folded] 为 true（折叠块内）时取
/// 六成、水平居中，否则铺满；两种都按原比例、不裁切。可用宽度是渲染件拿到的
/// 约束宽度（文档页是页宽，一次性图文卡是卡内宽），不另读屏幕宽度。点一下
/// 弹全屏查看器（**大图查看**），查看器顶部用这张图的 [alt]；长按直接把这张图
/// 存进系统相册（[saveHelpImage]），与全屏大图那处长按同一条链路。
Widget _image(
  WidgetRef ref,
  AssetBundle bundle,
  BuildContext context,
  HelpDocumentContent content,
  Uri uri, {
  String? alt,
  bool folded = false,
}) {
  final key = helpImageAssetKey(content.directory, uri.toString());
  if (key == null || !content.imageAssets.contains(key)) {
    return const SizedBox.shrink();
  }
  final image = Image(
    image: AssetImage(key, bundle: bundle),
    // 宽度撑满外面给的宽度（块外整宽、块内六成），保持比例不裁切。
    width: double.infinity,
    fit: BoxFit.fitWidth,
    errorBuilder: (_, _, _) => const SizedBox.shrink(),
  );
  final tappable = GestureDetector(
    onTap: () =>
        HelpImageViewer.open(context, assetKey: key, bundle: bundle, alt: alt),
    onLongPress: () =>
        saveHelpImage(ref, context, bundle: bundle, assetKey: key),
    child: image,
  );
  if (!folded) return tappable;
  return Center(
    child: FractionallySizedBox(
      widthFactor: _foldedImageWidthFactor,
      child: tappable,
    ),
  );
}

/// 复制成功的提示语（**唯一来源**）：正文链接不归前两路时都以它收尾。
const String helpLinkCopiedMessage = '已复制';

/// 外部网址打开失败（没交出去）时的提示语：地址已复制，读者可自己粘到别处。
const String helpLinkOpenFailedMessage = '打不开，已复制地址';

/// 正文里的链接复制到剪贴板并出声：[message] 缺省是复制成功那句，外部网址
/// 打开失败时传 [helpLinkOpenFailedMessage]。
void copyHelpLink(
  BuildContext context,
  String? href, {
  String message = helpLinkCopiedMessage,
}) {
  if (href == null) return;
  Clipboard.setData(ClipboardData(text: href));
  showHelpSnackBar(context, message);
}
