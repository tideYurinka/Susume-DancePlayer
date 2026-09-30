/// 更新提示条：根壳左下角一条常驻浮层——有新
/// 版本才出现，写明包体积，带「下载」与关闭 ✕；未获「安装未知应用」授权时改
/// 为「需要允许安装未知应用」+「前往设置」。它不是「短暂提示」：有按钮、无停
/// 留定时、不走短暂提示模块；与它共用的是更底层的黑底胶囊视觉语言。
///
/// 它是更新状态机（`lib/update/update_state.dart`）的一个读面——与**版本行**读
/// 同一台机器，所以两处说的永远是同一件事，也不会各查一次、各下一份包。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notice_badge.dart';
import '../core/notice_tokens.dart';
import 'update_state.dart';

/// 包体积的显示串：字节按 1024 进制换 MB、一位小数（`81234567` → `77.5 MB`）。
String formatUpdateSize(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// 更新提示条：只读状态机的「有新版」那几态与用户按过 ✕ 没有，不持有自己的
/// 显隐定时。
class UpdatePromptBar extends ConsumerWidget {
  const UpdatePromptBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    if (!state.promptVisible) return const SizedBox.shrink();
    final controller = ref.read(updateProvider.notifier);
    return NoticeBadge(
      key: const Key('update_prompt_bar'),
      padding: kCornerPromptCardPadding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.phase == UpdateDownloadPhase.downloading) ...[
            SizedBox(
              width: 72,
              child: LinearProgressIndicator(
                key: const Key('update_prompt_progress'),
                value: state.total > 0 ? state.progress : null,
              ),
            ),
            const SizedBox(width: kCornerPromptCardGap),
          ],
          Text(
            _message(state),
            key: const Key('update_prompt_message'),
            style: kCornerPromptCardTextStyle,
          ),
          const SizedBox(width: kCornerPromptCardGap),
          if (state.phase != UpdateDownloadPhase.downloading)
            TextButton(
              key: const Key('update_prompt_action'),
              style: kCornerPromptCardButtonStyle,
              // 交系统安装器那一下在飞时不再接受第二次按下。
              onPressed: state.inFlight == UpdateInFlight.installing
                  ? null
                  : () => _onAction(controller, state.phase),
              child: Text(_actionLabel(state.phase)),
            ),
          IconButton(
            key: const Key('update_prompt_dismiss'),
            tooltip: '关闭',
            iconSize: 18,
            onPressed: controller.dismiss,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

/// 按下那一颗按钮：可下载/失败重试走下载；等授权才去设置页（不自动跳转）。
void _onAction(UpdateController controller, UpdateDownloadPhase phase) {
  switch (phase) {
    case UpdateDownloadPhase.needsInstallPermission:
      controller.openInstallSettings();
    case UpdateDownloadPhase.available:
    case UpdateDownloadPhase.failed:
      controller.download();
    case UpdateDownloadPhase.none:
    case UpdateDownloadPhase.downloading:
      break;
  }
}

/// 提示条那颗按钮当前的字。
String _actionLabel(UpdateDownloadPhase phase) => switch (phase) {
  UpdateDownloadPhase.failed => '重试',
  UpdateDownloadPhase.needsInstallPermission => '前往设置',
  _ => '下载',
};

/// 提示条当前那一句话：可下载写体积、下载中写百分比、失败写人话、等授权写
/// 缺哪一项。
String _message(UpdateState state) {
  final manifest = state.manifest;
  if (manifest == null) return '';
  switch (state.phase) {
    case UpdateDownloadPhase.available:
      return '新版本 ${manifest.versionName}'
          '（${formatUpdateSize(manifest.size)}）';
    case UpdateDownloadPhase.downloading:
      return state.total > 0
          ? '下载中 ${(state.progress * 100).round()}%'
          : '下载中 ${formatUpdateSize(state.received)}';
    case UpdateDownloadPhase.failed:
      return '下载失败，请检查网络后重试';
    case UpdateDownloadPhase.needsInstallPermission:
      return '需要允许安装未知应用';
    case UpdateDownloadPhase.none:
      return '';
  }
}
