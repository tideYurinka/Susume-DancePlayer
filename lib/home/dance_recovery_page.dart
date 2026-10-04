import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dance/dance_library.dart';
import '../dance/dance_library_providers.dart';
import 'dance_delete_dialog.dart';

/// 找回面：一支**副本丢失**的舞在这里被修好或送走。
///
/// 播放页不是判定丢失的地方——两个进播放页的入口（首页卡片、舞详情）都先
/// 读舞库读面带出的丢失事实，丢失时在这里会合（见 `dance_open.dart`）。
///
/// 这一版给两条出路：
/// - **删除这支舞**：与详情页同一份删除动作（索引先写、文件 best-effort、
///   素材连带、练舞统计保留）；副本本就不在，删除其中的删文件一步是空操作，
///   因此删一支丢失的舞照常成立，不留半个残骸；
/// - **暂不找回**：原样离开，这支舞保持丢失状态留在库里——丢的是视频副本，
///   标注、熟练度、统计与计划照常，卡片上的标记会一直等着修好它。
///
/// 「选择视频文件」那条路（核对**视频标识**后把副本放回条目记录的原路径）归
/// 找回动作，由导入域自持。
class DanceRecoveryPage extends ConsumerWidget {
  const DanceRecoveryPage({super.key, required this.dance});

  /// 副本丢失的那支舞（读面快照）：标题、身份与条目记录的原路径都取自它。
  final DanceSnapshot dance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('dance_recovery_page'),
      appBar: AppBar(title: Text(dance.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.videocam_off_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  '视频副本丢失',
                  key: const Key('dance_recovery_status'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '这支舞的视频副本不在本机了。标注、分段熟练度、练习素材、'
                  '续播位置与署名都还在原处，把它留在库里不会丢。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  key: const Key('dance_recovery_later'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('暂不找回'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('dance_recovery_delete'),
                  onPressed: () => _delete(context, ref),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('删除这支舞'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 删除这支舞：二次确认（默认不删）后走舞库自持写路径，成功后退出找回面
  /// 回舞库（卡片随读面作废消失）；失败如实告知并留在本页。
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    if (!await confirmDanceDeletion(context)) return;
    try {
      await deleteDanceFrom(ref, dance.videoId);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败')));
      return;
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }
}
