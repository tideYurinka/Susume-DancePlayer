import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../help/help_document_page.dart' show openHelpDocumentPage;
import '../help/help_markdown_body.dart';
import 'contributor_avatar.dart';
import 'contributor_roster.dart';

/// **个人介绍页**：顶端该**贡献者**的小块档案（头像、显示名、角色），其下是
/// 他自己那份个人介绍正文。正文按 id 从名单装载结果取；装载中或他不在了时
/// 页面标题退回 id、正文区为空，不崩不白屏。
class ContributorIntroPage extends ConsumerWidget {
  const ContributorIntroPage({super.key, required this.contributorId});

  /// 贡献者的稳定 id（目录名、名单里那条记录与本文落点都取它）。
  final String contributorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contributor = ref
        .watch(contributorRosterProvider)
        .asData
        ?.value
        .contributor(contributorId);
    return Scaffold(
      appBar: AppBar(title: Text(contributor?.displayName ?? contributorId)),
      body: contributor == null
          ? const SizedBox.shrink()
          : _IntroBody(contributor: contributor),
    );
  }
}

/// 档案头 + 正文同处一个滚动体（正文里的锚点由渲染件靠这个滚动祖先定位）。
class _IntroBody extends StatelessWidget {
  const _IntroBody({required this.contributor});

  final Contributor contributor;

  @override
  Widget build(BuildContext context) {
    final intro = contributor.intro;
    return SingleChildScrollView(
      key: const Key('contributor_intro_scroll'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeader(contributor: contributor),
          // 一级标题已显示在标题栏与档案头，正文从标题之后渲染；正文与帮助
          // 文档共用渲染件与方言（分节、图片、折叠块、条目链接、外部网址）。
          if (intro.bodySegments.isNotEmpty)
            HelpMarkdownBody(
              key: const Key('contributor_intro_markdown'),
              document: intro,
              segments: intro.bodySegments,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              // 条目链接与帮助文档页走同一条推入通路：返回即回到本页。
              onOpenEntry: (link) => openHelpDocumentPage(context, link),
            ),
        ],
      ),
    );
  }
}

/// 顶端的小块档案：头像 + 显示名 + 角色。
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.contributor});

  final Contributor contributor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('contributor_profile_header'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          ContributorAvatar(contributor: contributor, size: 64),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contributor.displayName,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  contributor.role,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
