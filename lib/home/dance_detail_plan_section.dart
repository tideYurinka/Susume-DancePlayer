import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../plan/dance_plan_editor.dart';
import '../plan/dance_plan_manager.dart' show dancePlanSettlementOutcomeLabel;
import '../persistence/practice_plan.dart';
import '../persistence/practice_plan_providers.dart';

/// 舞详情计划区：
/// DDL 编辑与清除——无 DDL 时给出一枚可设入口；有 DDL 时读出日期、场合标签、
/// 备注、提前 N 天、准备清单（逐项打勾、可删、可加）与落档（只读，状态 + 判定
/// 日期），并给「改期 / 清除」两枚入口；带随舞曲库开关（默认开，关掉后
/// 不被新建随舞事件默认带入）与复习提醒开关（默认开，关掉后
/// 这支舞不参与遗忘复习与随舞临近提醒）。
///
/// DDL 编辑框、两个开关与清单编辑器由 `dance_plan_editor.dart` 提供，与「各舞
/// 计划」管理页同源（同一批控件与同一条写路径）。
///
/// 装载补判经 store（[practicePlanStoreProvider] 注入段档位读入口）：
/// 打开详情页读 DDL 即完成已过未落档条目的补判，页面不自己判定。
///
/// 全部写经 [PracticePlanStore]（页面不自己拼 JSON），写成功即作废本舞
/// 读面；写失败如实提示（存储静默承接，内存态不回滚）。
class DancePlanSection extends ConsumerWidget {
  const DancePlanSection({super.key, required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ddl = ref.watch(dancePlanDdlProvider(videoId)).asData?.value;
    final socialLibrary =
        ref.watch(dancePlanSocialLibraryProvider(videoId)).asData?.value ??
        true;
    final reviewReminders =
        ref.watch(dancePlanReviewRemindersProvider(videoId)).asData?.value ??
        true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('计划', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        DancePlanSwitchTiles(
          videoId: videoId,
          socialLibrary: socialLibrary,
          reviewReminders: reviewReminders,
        ),
        if (ddl == null)
          FilledButton.icon(
            key: const Key('dance_plan_set'),
            onPressed: () => _editDdl(context, ref, current: null),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('设截止（DDL）'),
          )
        else ...[
          _DdlView(ddl: ddl),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                key: const Key('dance_plan_edit'),
                onPressed: () => _editDdl(context, ref, current: ddl),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('dance_plan_clear'),
                onPressed: () => _clearDdl(context, ref),
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: const Text('清除'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DancePlanChecklistEditor(
            items: ddl.checklist,
            keyPrefix: 'dance_plan_',
            onToggle: (index, checked) => runPlanWrite(
              context,
              ref,
              videoId,
              (store) => store.setChecklistItemChecked(
                videoId: videoId,
                index: index,
                checked: checked,
              ),
            ),
            onRemove: (index) => runPlanWrite(
              context,
              ref,
              videoId,
              (store) =>
                  store.removeChecklistItem(videoId: videoId, index: index),
            ),
            onAdd: (text) => runPlanWrite(
              context,
              ref,
              videoId,
              (store) => store.addChecklistItem(videoId: videoId, text: text),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _editDdl(
    BuildContext context,
    WidgetRef ref, {
    required DanceDdl? current,
  }) async {
    final saved = await Navigator.of(context).push<DancePlanEditorResult>(
      MaterialPageRoute(
        builder: (_) => DanceDdlEditorPage(videoId: videoId, initial: current),
      ),
    );
    if (saved == null || !context.mounted) return;
    final ddl = saved.ddl;
    // 首次设置「提前 N 天」时系统询问通知权限；被拒后保存照常。
    await ensureDancePlanReminderPermission(ref, ddl: ddl, previous: current);
    if (!context.mounted) return;
    await runPlanWrite(
      context,
      ref,
      videoId,
      (store) => store.setDdl(videoId: videoId, ddl: ddl),
    );
  }

  Future<void> _clearDdl(BuildContext context, WidgetRef ref) async {
    // 二次确认：取消 = DDL 不动，确认后才落盘。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('dance_plan_clear_dialog'),
        content: const Text('清除这支舞的截止日？已设的日期、场合与准备清单会一并抹掉'),
        actions: [
          TextButton(
            key: const Key('dance_plan_clear_cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('dance_plan_clear_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await runPlanWrite(
      context,
      ref,
      videoId,
      (store) => store.clearDdl(videoId),
    );
  }
}

/// DDL 读面：日期、场合标签、备注、提前 N 天与落档逐行展示（空值不出
/// 行）。落档只读：状态 + 判定日期，逾期只显不催、不产生提醒。
class _DdlView extends StatelessWidget {
  const _DdlView({required this.ddl});

  final DanceDdl ddl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyedSubtree(
          key: const Key('dance_plan_date'),
          child: Text(planDayKey(ddl.date), style: theme.textTheme.titleSmall),
        ),
        if (ddl.occasion.isNotEmpty)
          KeyedSubtree(
            key: const Key('dance_plan_occasion'),
            child: Text(ddl.occasion),
          ),
        if (ddl.remark.isNotEmpty) Text(ddl.remark),
        if (ddl.leadDays != null) Text('提前 ${ddl.leadDays} 天'),
        if (ddl.settlement != null)
          KeyedSubtree(
            key: const Key('dance_plan_settlement'),
            child: Text(_settlementText(ddl.settlement!)),
          ),
      ],
    );
  }

  String _settlementText(DdlSettlement settlement) {
    final outcome = dancePlanSettlementOutcomeLabel(settlement.outcome);
    return '落档：$outcome（判定 ${planDayKey(settlement.judgedOn)}）';
  }
}
