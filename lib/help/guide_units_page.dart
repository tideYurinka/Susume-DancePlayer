import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_registry.dart';
import 'guide_copy.dart';
import 'guide_state.dart';
import 'help_boxes.dart';
import 'help_documents.dart';

/// 新手引导页 = 状态 + 重置：页顶一个总览
/// 方框（「已完成的引导」+ 已完成数 / 总项数 + 百分比 + 进度条；有已完成项
/// 时框内出现「重置所有教程」）；其下「起步 / 播放页 / 功能提示」三组各一个
/// 图例方框，框顶写组名与组内已完成数 / 组内项数。每行 = 状态方框 + 标题 +
/// 一句说明 + 「已完成 / 未完成」小字；**只有已完成的行才有「重置」**（未完成
/// 的行本来就会在自己的触发点重演，没有可重置的东西，这一条同时让"做没做过"
/// 一眼可辨）。
///
/// 「已完成」与状态位是同一个事实：跳过即置位，所以跳过过的项也显示「已完成」。
/// 重置即时生效且页面不退出，可以连着清多项；重置本身不演出任何东西。想再看
/// 某一条，就把该项重置、再走到它的触发点。
class GuideUnitsPage extends ConsumerWidget {
  const GuideUnitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 刷新期间沿用上一份读数（Riverpod 的 `value` 保留前值），重置后不会闪
    // 一下「全部未完成」。
    final seen =
        ref.watch(guideUnitsSeenProvider).value ?? const <String, bool>{};
    // 文案随包（assets/help/onboarding.yaml）；尚未装载完时按全空渲染，装完
    // 即重建出真文案。
    final copy =
        ref.watch(helpContentProvider).value?.guideCopy ?? GuideCopy.empty;
    final title = copy.ui.guideUnitsTitle;
    final doneCount = _doneCount(seen, helpGuideUnits);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        key: const Key('guide_units_list'),
        padding: const EdgeInsets.all(16),
        children: [
          HelpProgressBox(
            key: const Key('guide_summary'),
            title: '已完成的引导',
            done: doneCount,
            total: helpGuideUnits.length,
            action: doneCount == 0
                ? null
                : TextButton(
                    key: const Key('guide_reset_all'),
                    style: helpTapTargetButtonStyle,
                    onPressed: () => _resetAll(context, ref, copy),
                    child: Text(copy.ui.resetAll),
                  ),
          ),
          for (final group in GuideUnitGroup.values) ...[
            const SizedBox(height: 12),
            _GuideGroupBox(
              group: group,
              seen: seen,
              copy: copy,
              onReset: (unitId) =>
                  ref.read(guideResetProvider).resetUnit(unitId),
            ),
          ],
        ],
      ),
    );
  }

  /// 「重置所有教程」：先弹一次确认（误触不该把整套引导重弹一遍），确认后
  /// 一次清掉全部单元；取消则一位不变。
  Future<void> _resetAll(
    BuildContext context,
    WidgetRef ref,
    GuideCopy copy,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('guide_reset_all_dialog'),
        title: Text(copy.ui.resetDialogTitle),
        content: Text(copy.ui.resetDialogBody),
        actions: [
          TextButton(
            key: const Key('guide_reset_all_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(copy.ui.resetDialogCancel),
          ),
          TextButton(
            key: const Key('guide_reset_all_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(copy.ui.resetDialogConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(guideResetProvider).resetAll();
  }
}

/// 一组「组内已完成数 / 组内项数」与总览读数的唯一计数算法。
int _doneCount(Map<String, bool> seen, Iterable<GuideUnit> units) =>
    units.where((unit) => seen[unit.id] ?? false).length;

/// 一组引导单元：图例方框（组名 + 组内计数）+ 框内本组各行。
class _GuideGroupBox extends StatelessWidget {
  const _GuideGroupBox({
    required this.group,
    required this.seen,
    required this.copy,
    required this.onReset,
  });

  final GuideUnitGroup group;
  final Map<String, bool> seen;
  final GuideCopy copy;
  final void Function(String unitId) onReset;

  @override
  Widget build(BuildContext context) {
    final units = helpGuideUnits.where((unit) => unit.group == group).toList();
    return HelpLegendBox(
      key: Key('guide_group_${group.name}'),
      legend: group.label,
      trailing: helpCountLabel(_doneCount(seen, units), units.length),
      child: Column(
        children: [
          for (final unit in units)
            _GuideUnitTile(
              unit: unit,
              copy: copy,
              seen: seen[unit.id] ?? false,
              onReset: () => onReset(unit.id),
            ),
        ],
      ),
    );
  }
}

/// 一行引导单元：状态方框 + 标题 + 一句说明 + 「已完成 / 未完成」小字，
/// 已完成的行多一个「重置」。
class _GuideUnitTile extends StatelessWidget {
  const _GuideUnitTile({
    required this.unit,
    required this.copy,
    required this.seen,
    required this.onReset,
  });

  final GuideUnit unit;
  final GuideCopy copy;
  final bool seen;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = guideUnitRowCopy(copy, unit);
    return Padding(
      key: Key('guide_unit_${unit.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: HelpStatusBox(
              key: Key('guide_status_box_${unit.id}'),
              done: seen,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HelpTitleDescription(
                  title: row.title,
                  description: row.description,
                ),
                const SizedBox(height: 2),
                Text(
                  seen ? '已完成' : '未完成',
                  key: Key('guide_status_${unit.id}'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: seen
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          if (seen)
            TextButton(
              key: Key('guide_reset_${unit.id}'),
              style: helpTapTargetButtonStyle,
              onPressed: onReset,
              child: const Text('重置'),
            ),
        ],
      ),
    );
  }
}
