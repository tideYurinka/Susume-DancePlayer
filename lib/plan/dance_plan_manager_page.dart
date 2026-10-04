import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/device_clock.dart';
import '../dance/dance_library_providers.dart';
import '../dance/mastery_label.dart';
import '../persistence/practice_plan.dart';
import '../persistence/practice_plan_providers.dart';
import 'dance_plan_editor.dart';
import 'dance_plan_manager.dart';

/// 「各舞计划」管理页：计划 Tab 右上角入口 push 的独立
/// 路由。一行一支舞——舞名、DDL 摘要（日期与场合，或「未设 DDL」）、熟练度
/// 百分比（完全掌握以勾替）、落档只读标记与两个开关的状态提示；分「已有计划」
/// （有 DDL，按 DDL 日期升序，逾期仍按日期在前）与「未设计划」（完全掌握沉底、
/// 其余按舞库次序）两组；顶部按标题搜索，另可只看未设计划。点行开计划编辑框
/// （与舞详情计划区同源控件），保存经 store 落盘并作废读面，本页与计划页同步
/// 刷新。分组与排序取纯件同一出处。
class DancePlanManagerPage extends ConsumerStatefulWidget {
  const DancePlanManagerPage({super.key});

  @override
  ConsumerState<DancePlanManagerPage> createState() =>
      _DancePlanManagerPageState();
}

class _DancePlanManagerPageState extends ConsumerState<DancePlanManagerPage> {
  final _search = TextEditingController();
  bool _onlyWithoutPlan = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(practicePlanEntriesProvider);
    final library = ref.watch(danceLibrarySnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('各舞计划')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // store 读失败已在存储侧静默兜底为空集，错误分支不预期；按空态呈现。
        error: (_, _) => const _ManageEmptyLibrary(),
        data: (list) {
          // 舞库读面未落定不当空库：加载中给读数中，落定后才谈「舞库为空」。
          if (library.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final dances = library.asData?.value.dances ?? const [];
          if (dances.isEmpty) return const _ManageEmptyLibrary();
          final entryByVideoId = <String, DancePlanEntry>{
            for (final entry in list) entry.videoId: entry,
          };
          final groups = dancePlanManagerGroups(
            dances: [
              for (final dance in dances)
                DancePlanManagerDance(
                  videoId: dance.videoId,
                  title: dance.title,
                  masteryPercent: dance.masteryPercent,
                  fullyMastered: dance.fullyMastered,
                  ddl: entryByVideoId[dance.videoId]?.ddl,
                  socialLibrary:
                      entryByVideoId[dance.videoId]?.socialLibrary ?? true,
                  reviewReminders:
                      entryByVideoId[dance.videoId]?.reviewReminders ?? true,
                ),
            ],
            query: _search.text,
            onlyWithoutPlan: _onlyWithoutPlan,
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  key: const Key('plan_manage_search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '按标题搜索',
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: FilterChip(
                    key: const Key('plan_manage_only_unset'),
                    label: const Text('只看未设计划'),
                    selected: _onlyWithoutPlan,
                    onSelected: (selected) =>
                        setState(() => _onlyWithoutPlan = selected),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (groups.withPlan.isNotEmpty) ...[
                      _groupHeader('已有计划', 'plan_manage_group_with_plan'),
                      for (final dance in groups.withPlan)
                        _row(dance, entryByVideoId[dance.videoId]),
                    ],
                    if (groups.withoutPlan.isNotEmpty) ...[
                      _groupHeader('未设计划', 'plan_manage_group_without_plan'),
                      for (final dance in groups.withoutPlan)
                        _row(dance, entryByVideoId[dance.videoId]),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _groupHeader(String label, String key) => Padding(
    key: Key(key),
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _row(DancePlanManagerDance dance, DancePlanEntry? entry) {
    final theme = Theme.of(context);
    final settlement = dancePlanSettlementLabel(dance.ddl?.settlement);
    final hints = dancePlanSwitchHints(
      socialLibrary: dance.socialLibrary,
      reviewReminders: dance.reviewReminders,
    );
    return ListTile(
      key: Key('plan_manage_row_${dance.videoId}'),
      contentPadding: EdgeInsets.zero,
      title: Text(dance.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dancePlanDdlSummary(dance.ddl),
            key: Key('plan_manage_ddl_${dance.videoId}'),
          ),
          if (settlement != null)
            Text(
              settlement,
              key: Key('plan_manage_settlement_${dance.videoId}'),
            ),
          if (hints.isNotEmpty)
            Text(
              hints.join(' · '),
              key: Key('plan_manage_hints_${dance.videoId}'),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      // 完全掌握行尾配可读标签：勾与百分比之外要读得出真值。
      trailing: dance.fullyMastered
          ? Semantics(
              container: true,
              excludeSemantics: true,
              label: kMasteredLabel,
              child: Icon(
                Icons.check_circle,
                key: Key('plan_manage_mastery_${dance.videoId}'),
                color: theme.colorScheme.primary,
              ),
            )
          : dance.masteryPercent == null
          ? null
          : Text(
              '${dance.masteryPercent!.round()}%',
              key: Key('plan_manage_mastery_${dance.videoId}'),
            ),
      onTap: () => _editDance(dance, entry),
    );
  }

  /// 点行开计划编辑页（与舞详情计划区共用 [DanceDdlEditorPage]）：一次编辑
  /// DDL、准备清单与两个开关；保存经 store 落盘，成功即作废读面（本页与计划
  /// 页同读一份条目读面）。
  Future<void> _editDance(
    DancePlanManagerDance dance,
    DancePlanEntry? entry,
  ) async {
    final saved = await Navigator.of(context).push<DancePlanEditorResult>(
      MaterialPageRoute(
        builder: (_) => DanceDdlEditorPage(
          videoId: dance.videoId,
          initial: entry?.ddl,
          title: '计划 · ${dance.title}',
          today: ref.read(deviceClockProvider)(),
          showPlanExtras: true,
          socialLibrary: entry?.socialLibrary ?? true,
          reviewReminders: entry?.reviewReminders ?? true,
          checklistKeyPrefix: 'plan_manage_',
        ),
      ),
    );
    if (saved == null || !mounted) return;
    // 首次设置「提前 N 天」时系统询问通知权限；被拒后保存照常。
    await ensureDancePlanReminderPermission(
      ref,
      ddl: saved.ddl,
      previous: entry?.ddl,
    );
    if (!mounted) return;
    await runPlanWrite(context, ref, dance.videoId, (store) async {
      if (!await store.setDdl(videoId: dance.videoId, ddl: saved.ddl)) {
        return false;
      }
      if (!await store.setSocialLibrary(
        videoId: dance.videoId,
        enabled: saved.socialLibrary,
      )) {
        return false;
      }
      return store.setReviewReminders(
        videoId: dance.videoId,
        enabled: saved.reviewReminders,
      );
    });
  }
}

/// 舞库为空：页内引导提示（没有可编辑的舞）。
class _ManageEmptyLibrary extends StatelessWidget {
  const _ManageEmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('plan_manage_empty_library'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.library_music_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('舞库还没有舞', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('先在首页导入一支舞，这里就能给它设 DDL', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
