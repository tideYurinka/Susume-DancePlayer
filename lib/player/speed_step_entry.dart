/// 倍速步进的启用入口（弹窗 + 编排）。
///
/// [enableSpeedStepForPreview] 是步进面板开关的公共入口：按预览位置取
/// [resolveSpeedStepScope]
/// （纯函数域见 `speed_step_scope.dart`）的判定——范围内直接启用；范围外
/// 弹三选一（「激活当前学习段并启用步进倍速」「对全片启用步进倍速」
/// 「取消」）。启用成功提示「已启用步进倍速」。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'annotation_selection.dart' show selectedLearningSegmentsProvider;
import 'annotation_editor.dart'
    show annotationSelectionDomainProvider, annotationTimelineProvider;
import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'visual_tokens.dart' show kNoticeTextStyle;
import 'speed_control.dart';
import 'speed_step_scope.dart';

/// 三选一弹窗的选项。
enum SpeedStepScopeChoice { selectSegment, wholeVideo, cancel }

/// 步进启用提示声明：一行声明 = 身份 + 内容 +
/// 定位 key。触发面由提示模块持有（启用成功经 `noticeTriggerProvider(
/// NoticeId.stepEnabled)` 只报身份）；挂载由演出层的唯一宿主承担。
Widget stepEnabledNoticeContent(BuildContext _) =>
    const Text('已启用步进倍速', style: kNoticeTextStyle);

/// 步进启用提示声明清单项（组合根装配）。
const stepEnabledNoticeSpec = NoticeSpec(
  id: NoticeId.stepEnabled,
  content: stepEnabledNoticeContent,
  noticeKey: Key('step_enabled_prompt'),
);

/// 范围三选一弹窗（预览位于激活范围外时）。
///
/// [candidateOrder] 为 null 时第一项置灰（预览不在任何学习段内且其后无段）。
Future<SpeedStepScopeChoice?> showSpeedStepScopeDialog(
  BuildContext context, {
  required int? candidateOrder,
}) {
  return showDialog<SpeedStepScopeChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('speed_step_scope_dialog'),
      title: const Text('启用步进倍速'),
      content: const Text('当前预览位置不在激活的学习段内，请选择步进倍速的作用范围。'),
      actions: [
        TextButton(
          key: const Key('speed_step_scope_select_segment'),
          onPressed: candidateOrder == null
              ? null
              : () =>
                    Navigator.of(dialogContext)
                        .pop(SpeedStepScopeChoice.selectSegment),
          child: const Text('激活当前学习段并启用步进倍速'),
        ),
        TextButton(
          key: const Key('speed_step_scope_whole_video'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(SpeedStepScopeChoice.wholeVideo),
          child: const Text('对全片启用步进倍速'),
        ),
        TextButton(
          key: const Key('speed_step_scope_cancel'),
          onPressed: () =>
              Navigator.of(dialogContext).pop(SpeedStepScopeChoice.cancel),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

/// 按预览位置启用步进倍速（两条步进面板开关的公共入口）。
///
/// 已启用时为 no-op；预览在激活范围内直接启用（作用于激活段）；范围外先弹
/// 三选一：「激活当前学习段」→ 激活候选段（进度随之跳段首并进入段内循环）
/// 后启用；「对全片」→ 以首/尾有效练习区间为范围启用；「取消」→ 不做任何
/// 事。启用成功提示「已启用步进倍速」。
Future<void> enableSpeedStepForPreview(
  BuildContext context,
  WidgetRef ref,
) async {
  final control = ref.read(speedControlProvider);
  if (control.stepEnabled) return;
  final notifier = ref.read(speedControlProvider.notifier);
  final decision = resolveSpeedStepScope(
    timeline: ref.read(annotationTimelineProvider),
    selected: ref.read(selectedLearningSegmentsProvider),
    position: ref.read(playbackEngineProvider).position,
  );
  if (!decision.withinActiveScope) {
    final choice = await showSpeedStepScopeDialog(
      context,
      candidateOrder: decision.candidateOrder,
    );
    switch (choice) {
      case SpeedStepScopeChoice.selectSegment:
        final order = decision.candidateOrder;
        if (order == null) return;
        // 「激活当前段」直连选中域（含与临时衔接段的互斥清除）。
        ref.read(annotationSelectionDomainProvider).selectOnly(order);
        await notifier.setStepEnabled(true);
      case SpeedStepScopeChoice.wholeVideo:
        await notifier.setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      case SpeedStepScopeChoice.cancel || null:
        return;
    }
  } else {
    await notifier.setStepEnabled(true);
  }
  ref.read(noticeTriggerProvider(NoticeId.stepEnabled).notifier).show();
}
