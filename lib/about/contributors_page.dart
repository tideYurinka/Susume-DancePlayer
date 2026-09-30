import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'about_page.dart';
import 'contributor_avatar.dart';
import 'contributor_intro_page.dart';
import 'contributor_roster.dart';

/// **贡献者名单**页：开头是与**关于页**逐位相同的**应用信息头**，其下一条横线
/// （该页独有，用来分开只读头部与名单），再是组名与逐位名单——每位一行：头像
/// 或占位、显示名与角色。
class ContributorsPage extends ConsumerWidget {
  const ContributorsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(contributorRosterProvider).asData?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('贡献者名单')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
        children: [
          const AboutAppInfoHeader(),
          const SizedBox(height: 28),
          // 该页独有的一条横线：上面是只读的应用信息头，下面是可以点的人。
          const Divider(key: Key('contributors_header_divider')),
          const SizedBox(height: 8),
          const _GroupName(label: '贡献者'),
          if (roster == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  key: Key('contributors_roster_loading'),
                ),
              ),
            )
          else
            for (final contributor in roster.contributors)
              _ContributorRow(contributor: contributor),
        ],
      ),
    );
  }
}

/// 名单的组名：横线之下、名单之上的一行。
class _GroupName extends StatelessWidget {
  const _GroupName({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 名单里的一位：头像或占位 + 显示名 + 角色。
class _ContributorRow extends StatelessWidget {
  const _ContributorRow({required this.contributor});

  final Contributor contributor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('contributor_row_${contributor.id}'),
      contentPadding: EdgeInsets.zero,
      leading: ContributorAvatar(contributor: contributor),
      title: Text(contributor.displayName),
      subtitle: Text(contributor.role),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ContributorIntroPage(contributorId: contributor.id),
        ),
      ),
    );
  }
}
