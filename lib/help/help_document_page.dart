import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../feedback/issue_report_page.dart';
import 'help_documents.dart';
import 'help_markdown_body.dart';

/// 「问题反馈」教程条目 id（目录名 `03-问题反馈` 去掉数字前缀；与
/// `helpDocumentIdOfDirectory` 的推导一致，测试按真实目录名复核）。本域唯
/// 一一条出站边 help → feedback（表单页）：只有该条目在正文下方出动作区。
const String feedbackTutorialId = '问题反馈';

/// 章节页与教程页共用一条路径：条目目录里的 Markdown 正文渲染成纵向滚动的
/// 文档——标题层级、有序与无序列表、引用块（提示块）、粗体、图片、可点链接。
/// 图片按相对文件名解析到同目录资产，缺图不渲染、不留空框，正文照常。
///
/// 条目按 id 从装载结果取（目录名去数字前缀）；装载中或条目不在时页面标题
/// 退回 id、正文区为空，不崩不白屏。
class HelpDocumentPage extends ConsumerWidget {
  const HelpDocumentPage({
    super.key,
    required this.documentId,
    this.initialAnchor,
  });

  final String documentId;

  /// 进入时的落点锚点（已去掉 `#`）：带上打开时正文停在那条标题；null = 顶部。
  final String? initialAnchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref
        .watch(helpContentProvider)
        .asData
        ?.value
        .document(documentId);
    return Scaffold(
      appBar: AppBar(title: Text(document?.displayTitle ?? documentId)),
      body: _MarkdownDocument(
        documentId: documentId,
        initialAnchor: initialAnchor,
      ),
    );
  }
}

/// 条目正文：装载中的一瞬出加载态，装满即渲染 Markdown；缺正文（目录里没有
/// Markdown）时正文为空，不崩不白屏。
class _MarkdownDocument extends ConsumerWidget {
  const _MarkdownDocument({required this.documentId, this.initialAnchor});

  final String documentId;

  /// 进入时的落点锚点；交给渲染件的首帧滚到位。
  final String? initialAnchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(helpContentProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const SizedBox.shrink(),
          data: (content) {
            final document = content.document(documentId);
            final hasAction = documentId == feedbackTutorialId;
            final body = document == null || document.markdown.isEmpty
                ? null
                : HelpMarkdownBody(
                    key: const Key('help_document_markdown'),
                    document: document,
                    // 一级标题已显示在标题栏，正文从标题之后渲染；正文按折叠块
                    // 切段，折叠块由渲染件包一层展开件。
                    segments: document.bodySegments,
                    initialAnchor: initialAnchor,
                    onOpenEntry: (link) => openHelpDocumentPage(context, link),
                  );
            if (body == null && !hasAction) return const SizedBox.shrink();
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?body,
                  // 动作区落在正文下方，只有「问题反馈」条目有：别的条目一个
                  // 像素都不多渲染。
                  if (hasAction)
                    Padding(
                      key: const Key('help_document_action_area'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: FilledButton(
                        key: Key('help_document_action_$issueReportTitle'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const IssueReportPage(),
                          ),
                        ),
                        child: const Text(issueReportTitle),
                      ),
                    ),
                ],
              ),
            );
          },
        );
  }
}

/// 推入一个帮助条目的文档页并停在它带的锚点（**条目链接**的推入通路，文档页
/// 与关于页共用）：压一条路由、返回即上一篇——不引路由表、不引返回栈。
Future<void> openHelpDocumentPage(BuildContext context, HelpEntryLink link) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HelpDocumentPage(
          documentId: link.documentId,
          initialAnchor: link.anchor,
        ),
      ),
    );
