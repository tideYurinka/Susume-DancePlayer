import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/system_page_text_colors.dart';
import '../share/dance_share.dart' show susumeShareDirectoryProvider;
import '../share_channel/share_channel.dart' show shareChannelProvider;
import 'whole_machine_backup.dart';

/// 备份面：首页「⋯」→「备份」弹出的那
/// 一面——范围说明 + 媒体勾选 + 确认递出。
///
/// 默认值与分享面**刻意相反**：媒体默认**不含**（这些视频是
/// 用户自己导进来的、能重新拿到）。备份数据范围在 [collectWholeMachineBackup]
/// 里收口；本面向用户言明范围——备份包含全部舞的方案与私密设置、练舞统计
/// 与四拍桶明细随包走（换机恢复后统计完整）。确认后装配到 `susume_share/`
/// （出站 FileProvider 覆盖的位置），经 [shareChannelProvider] 递出原文件；
/// 装配或递出失败 SnackBar 出声。
class BackupSheet extends ConsumerStatefulWidget {
  const BackupSheet({super.key});

  @override
  ConsumerState<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<BackupSheet> {
  bool _includeMedia = false;
  bool _sending = false;

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final collected = await collectWholeMachineBackup(
        ref.read(backupPortsProvider),
        includeMedia: _includeMedia,
      );
      final output = await assembleWholeMachineBackup(
        outputDir: await ref.read(susumeShareDirectoryProvider.future),
        payload: collected.payload,
        media: collected.media,
        now: DateTime.now(),
      );
      await ref.read(shareChannelProvider).shareFile(output);
      if (!mounted) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('备份失败，包未递出')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('backup_sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('备份', style: Theme.of(context).textTheme.titleMedium),
            // Flexible + 内部滚动：内容超高
            // （如系统大字号）时说明与勾选区滚动，「取消 / 开始备份」在滚
            // 动区之外、始终在屏上。
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      '把全部舞的我的标注方案、组员方案、练舞统计与私密设置打成一个包',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const KeyedSubtree(
                      key: Key('backup_sheet_stats_note'),
                      child: Text(
                        '练舞统计与四拍桶明细随包走，换机恢复后统计完整',
                        style: TextStyle(color: kBackupNoteTextColor),
                      ),
                    ),
                    CheckboxListTile(
                      key: const Key('backup_sheet_media'),
                      title: const Text('带媒体（源视频与练习录像）'),
                      subtitle: const Text('默认不带；这些视频你能重新导入'),
                      value: _includeMedia,
                      onChanged: _sending
                          ? null
                          : (v) => setState(() => _includeMedia = v ?? false),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const Key('backup_sheet_cancel'),
                  onPressed:
                      _sending ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('backup_sheet_send'),
                  onPressed: _sending ? null : _send,
                  child: Text(_sending ? '正在打包…' : '开始备份'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
