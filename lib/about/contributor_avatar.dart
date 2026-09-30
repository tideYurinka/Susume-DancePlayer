import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../help/help_documents.dart' show helpAssetBundleProvider;
import 'contributor_roster.dart';

/// **贡献者**头像：盘上有他那张头像就画它（圆形裁切），没有就画一个规整的
/// 占位件——名单与个人介绍页里还没提供头像的那位也不留空白、不画坏图。
class ContributorAvatar extends ConsumerWidget {
  const ContributorAvatar({
    super.key,
    required this.contributor,
    this.size = 48,
  });

  final Contributor contributor;

  /// 头像边长；名单行与个人介绍页的档案头各取一档。
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = contributor.avatarAsset;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: asset == null
            ? _AvatarPlaceholder(contributor: contributor, size: size)
            : Image.asset(
                asset,
                bundle: ref.watch(helpAssetBundleProvider),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _AvatarPlaceholder(contributor: contributor, size: size),
              ),
      ),
    );
  }
}

/// 缺头像时的占位件：一枚同一中轴的人形图标，底色取自主题。
class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.contributor, required this.size});

  final Contributor contributor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: Key('contributor_avatar_placeholder_${contributor.id}'),
      color: colors.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.person_outline,
        size: size * 0.56,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}
