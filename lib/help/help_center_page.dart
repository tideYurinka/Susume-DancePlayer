import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_registry.dart';
import 'guide_units_page.dart';
import 'help_boxes.dart';
import 'help_document_page.dart';
import 'help_documents.dart';

/// 帮助中心的单条目录项：图标方框（与顶部「新手引导」入口卡同款 64×44）+
/// 标题 + 一句说明 + 右箭头，整行可点。图标按条目 id 查常量表，缺登记时
/// 由调用方按分组给兜底。
class HelpEntryTile extends StatelessWidget {
  const HelpEntryTile({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: HelpIconBox(icon: icon),
      title: Text(title),
      subtitle: Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onTap == null
          ? null
          : Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
      onTap: onTap,
    );
  }
}

/// 帮助中心：一页目录，两层结构不做两级导航——① 顶部主色「新手引导」入口
/// 卡；② 分组「教程」；③ 分组「使用手册」。教程排在手册之前，开页即见；
/// 使用手册往下滚。两组条目由扫到的内容目录现算（标题、一句说明从正文推导，
/// 图标按条目 id 查表，条数现算）；装载完成前显示加载态。不做搜索。
class HelpCenterPage extends ConsumerWidget {
  const HelpCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(helpContentProvider);
    final loaded = content.asData?.value;
    final Widget body;
    if (loaded == null) {
      // 装载未完成（含读不出资产清单的失败）保持加载态；失败在开发期由断言
      // 打出原因，不静默变成一副空目录。
      assert(() {
        final error = content.error;
        if (error != null) debugPrint('帮助内容装载失败，保持加载态：$error');
        return true;
      }());
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _HelpDirectory(
        manualChapters: loaded.manualChapters,
        tutorials: loaded.tutorials,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('帮助中心')),
      body: body,
    );
  }
}

/// 帮助中心目录主体：新手引导入口卡 + 教程分组 + 使用手册分组。
class _HelpDirectory extends StatelessWidget {
  const _HelpDirectory({
    required this.manualChapters,
    required this.tutorials,
  });

  final List<HelpDocumentContent> manualChapters;
  final List<HelpDocumentContent> tutorials;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('help_center_list'),
      padding: const EdgeInsets.all(16),
      children: [
        const _GuideEntryCard(),
        const SizedBox(height: 16),
        _HelpGroupBox(
          key: const Key('help_group_tutorials'),
          legend: '教程',
          countUnit: '条',
          documents: tutorials,
          fallbackIcon: helpTutorialEntryFallbackIcon,
        ),
        const SizedBox(height: 16),
        _HelpGroupBox(
          key: const Key('help_group_manual'),
          legend: '使用手册',
          countUnit: '章',
          documents: manualChapters,
          fallbackIcon: helpManualEntryFallbackIcon,
        ),
      ],
    );
  }
}

/// 打开一份帮助文档（手册章节与教程同一条路径）。
void _openDocument(BuildContext context, HelpDocumentContent document) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => HelpDocumentPage(documentId: document.id),
    ),
  );
}

/// 新手引导入口卡：主色卡 + 图标方框 + 标题 + 一句说明 + 「查看」按钮；
/// 点卡片或点按钮都进新手引导页。
class _GuideEntryCard extends StatelessWidget {
  const _GuideEntryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    void openGuideUnits() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GuideUnitsPage()),
    );

    return Card(
      key: helpEntryKey('guide'),
      color: colors.primary,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: openGuideUnits,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HelpIconBox(
                key: const Key('help_entry_icon_box'),
                icon: Icons.school_outlined,
                color: colors.onPrimary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '新手引导',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '按「起步 / 播放页 / 功能提示」三组逐条查看，随时重置。',
                      key: const Key('help_entry_guide_description'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('help_entry_view_guide'),
                style: helpTapTargetButtonStyle.copyWith(
                  foregroundColor: WidgetStatePropertyAll(colors.onPrimary),
                ),
                onPressed: openGuideUnits,
                child: const Text('查看'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一条分组的通栏描边方框：框顶一行写组名与条数（条数由 [documents] 现算，
/// 不与清单分开给），框内每条带分隔线、整行可点。行图标按条目 id 查表，
/// 缺登记取该分组自己那枚兜底图标（[fallbackIcon]）。
class _HelpGroupBox extends StatelessWidget {
  const _HelpGroupBox({
    super.key,
    required this.legend,
    required this.countUnit,
    required this.documents,
    required this.fallbackIcon,
  });

  final String legend;

  /// 条数的单位（「条」/「章」）。
  final String countUnit;

  final List<HelpDocumentContent> documents;

  /// 条目缺登记图标时的兜底图标（手册 / 教程各一枚，由调用方给）。
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    return HelpLegendBox(
      legend: legend,
      trailing: '${documents.length} $countUnit',
      child: Column(
        children: [
          for (var i = 0; i < documents.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            HelpEntryTile(
              key: helpEntryKey(documents[i].id),
              title: documents[i].displayTitle,
              description: documents[i].listDescription ?? '',
              icon: helpEntryIcon(
                documents[i].id,
                fallbackIcon: fallbackIcon,
              ),
              onTap: () => _openDocument(context, documents[i]),
            ),
          ],
        ],
      ),
    );
  }
}
