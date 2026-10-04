import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notice_badge.dart';
import 'resume_position.dart'
    show resumePromptAutoDismiss, resumePromptProvider;
import 'visual_tokens.dart';

/// 「已从上次位置继续 · 从头播放？」左下角非模态小卡：打开续播且位置有效时出现；
/// 点「从头播放？」跳回 0 并
/// 继续播放，不点约数秒自动消失（[resumePromptAutoDismiss]）；只接管
/// 自身点击，不拦截播放手势、不打断播放。
///
/// 落位由入参 [anchor] 给出（演出层每帧算一次、与循环提示共用一份，已换算
/// 成 `Positioned` 语义）；卡自身不读系统手势内缩、不写固定内缩。[anchor]
/// 为空 = 本次放不下、不渲染。
class ResumePromptOverlay extends ConsumerWidget {
  const ResumePromptOverlay({super.key, required this.anchor});

  /// 卡左下角（`Positioned` 语义：`left` 距屏幕左缘、`bottom` 距屏幕底）；
  /// null = 本次不画。
  final ({double left, double bottom})? anchor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(resumePromptProvider);
    final anchor = this.anchor;
    if (!visible || anchor == null) return const SizedBox.shrink();
    return Positioned(
      key: const Key('resume_prompt_card'),
      left: anchor.left,
      bottom: anchor.bottom,
      child: NoticeBadge(
        // 紧凑档取值（内边距/字号/间距/按钮样式）只在 visual_tokens 一处
        // 定义、两卡共用。
        padding: kCornerPromptCardPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('已从上次位置继续', style: kCornerPromptCardTextStyle),
            const SizedBox(width: kCornerPromptCardGap),
            TextButton(
              key: const Key('resume_prompt_restart'),
              onPressed: () =>
                  ref.read(resumePromptProvider.notifier).restartFromHead(),
              style: kCornerPromptCardButtonStyle,
              child: const Text('从头播放？'),
            ),
          ],
        ),
      ),
    );
  }
}
