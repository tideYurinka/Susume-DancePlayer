/// 点日下栏：当天到期 DDL、当日练习时长与当日事件（随舞 / 团检）。
///
/// 段档位与舞标题都由装配层传入，行内不自开读面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/learning_segment_attributes.dart';
import '../home/dance_detail_page.dart';
import '../persistence/practice_plan.dart';
import '../persistence/team_check_gate.dart';
import '../stats/practice_stats_daily.dart';
import '../stats/practice_stats_format.dart';
import '../stats/practice_stats_records_provider.dart';
import 'plan_mark_kind.dart';
import 'plan_marker_palette.dart';
import 'plan_page_layout.dart';

/// 点日下栏：当天到期 DDL 的舞（可点进详情）+ 当日练习时长（恒按时间口径，
/// 取既有按日会话合计）+ 当日事件（随舞 / 团检，分类型呈现）。
class DayPanel extends ConsumerWidget {
  const DayPanel({
    super.key,
    required this.day,
    required this.ddls,
    required this.events,
    required this.masteriesByVideoId,
    required this.titleByVideoId,
    required this.onAddEvent,
    required this.onEditEvent,
    required this.onAddTeamCheck,
    required this.onEditTeamCheck,
  });

  final DateTime day;
  final List<DdlOnDay> ddls;
  final List<PlanEvent> events;

  /// 各舞段档位集合（页面装配处从舞库快照合成，与日程组达标判定同源）。
  final Map<String, Set<LearningMastery>> masteriesByVideoId;

  /// 各舞标题（与日程组同一份快照派生；行内不再自开读面）。
  final Map<String, String> titleByVideoId;

  final VoidCallback onAddEvent;
  final ValueChanged<PlanEvent> onEditEvent;
  final VoidCallback onAddTeamCheck;
  final ValueChanged<PlanEvent> onEditTeamCheck;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final records = ref.watch(practiceStatsRecordsProvider);
    final recordsList = records.asData?.value ?? const [];
    final detail = dailyPracticeDetail(recordsList, day);
    return Card(
      key: const Key('plan_day_panel'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${day.month}月${day.day}日',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                const Text('当日练习', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                Text(
                  key: const Key('plan_panel_practice'),
                  statsDurationText(detail.total),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  key: const Key('plan_panel_add_event'),
                  onPressed: onAddEvent,
                  icon: const Icon(Icons.celebration_outlined, size: 18),
                  label: const Text('新建随舞'),
                ),
                TextButton.icon(
                  key: const Key('plan_panel_add_teamcheck'),
                  onPressed: onAddTeamCheck,
                  icon: const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('新建团检'),
                ),
              ],
            ),
            if (ddls.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('这天没有到期的舞'),
              )
            else
              for (final ddl in ddls)
                ListTile(
                  key: Key('plan_panel_ddl_${ddl.videoId}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.flag_outlined,
                    color: planMarkColor(PlanMarkKind.ddl),
                  ),
                  title: Text(titleByVideoId[ddl.videoId] ?? ddl.videoId),
                  subtitle: Text(
                    ddl.occasion.isEmpty
                        ? 'DDL 到期'
                        : '${ddl.occasion} · DDL 到期',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DanceDetailPage(videoId: ddl.videoId),
                    ),
                  ),
                ),
            // 随舞事件行：点进编辑框；无事件日不占行。
            for (final event in events)
              if (event.type == kPlanEventTypeSocial)
                ListTile(
                  key: Key('plan_panel_event_${event.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.celebration_outlined,
                    color: planMarkColor(PlanMarkKind.social),
                  ),
                  title: Text(
                    event.location.isEmpty ? '随舞' : '随舞 · ${event.location}',
                  ),
                  subtitle: Text(
                    [
                      if (event.startTime != null) event.startTime!,
                      if (event.remark.isNotEmpty) event.remark,
                      if (event.danceIds.isNotEmpty)
                        '${event.danceIds.length} 支舞',
                    ].join(' · '),
                  ),
                  onTap: () => onEditEvent(event),
                )
              else if (event.type == kPlanEventTypeTeamCheck)
                TeamCheckRow(
                  event: event,
                  titleByVideoId: titleByVideoId,
                  masteriesByVideoId: masteriesByVideoId,
                  onEdit: () => onEditTeamCheck(event),
                ),
          ],
        ),
      ),
    );
  }
}

/// 团内检查事件行：整体达标状态、逐舞达标 / 未达标 / 不参与判定
/// 与录视频提交的「已提交」标记（到场排练不显示）。点行进编辑框。
/// 段档位由装配层读面传入，行内不自开读面。
class TeamCheckRow extends StatelessWidget {
  const TeamCheckRow({
    super.key,
    required this.event,
    required this.titleByVideoId,
    required this.masteriesByVideoId,
    required this.onEdit,
  });

  final PlanEvent event;
  final Map<String, String> titleByVideoId;
  final Map<String, Set<LearningMastery>> masteriesByVideoId;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statuses = <String, DanceGateStatus>{
      for (final videoId in event.danceIds)
        videoId: danceGateStatus(
          gate: teamCheckGateFromName(event.danceGates[videoId]),
          segmentMasteries: masteriesByVideoId[videoId] ?? const {},
        ),
    };
    final overall = eventGateStatus(statuses);
    final isVideo = event.checkMode == kTeamCheckModeVideoSubmission;
    return ListTile(
      key: Key('plan_panel_teamcheck_${event.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.groups_outlined,
        color: planMarkColor(PlanMarkKind.teamCheck),
      ),
      title: Row(
        children: [
          const Text('团检'),
          const Spacer(),
          Text(
            key: Key('plan_panel_teamcheck_${event.id}_status'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: overall == TeamCheckEventStatus.met
                  ? theme.colorScheme.primary
                  : overall == TeamCheckEventStatus.unmet
                  ? theme.colorScheme.error
                  : null,
            ),
            switch (overall) {
              TeamCheckEventStatus.met => '达标',
              TeamCheckEventStatus.unmet => '未达标',
              TeamCheckEventStatus.notJudged => '待定',
            },
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.remark.isNotEmpty) Text(event.remark),
          for (final videoId in event.danceIds)
            Row(
              children: [
                Expanded(child: Text(titleByVideoId[videoId] ?? videoId)),
                Text(
                  key: Key('plan_panel_teamcheck_${event.id}_dance_$videoId'),
                  style: theme.textTheme.bodySmall,
                  switch (statuses[videoId]) {
                    DanceGateStatus.met => '达标',
                    DanceGateStatus.unmet => '未达标',
                    DanceGateStatus.notJudged || null => '不参与判定',
                  },
                ),
              ],
            ),
          // 提交标记只在录视频提交类出现，且带日期。
          if (isVideo)
            Text(
              '已提交${event.submittedOn == null ? '' : ' · ${planDayKey(event.submittedOn!)}'}',
              key: Key('plan_panel_teamcheck_${event.id}_submitted'),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      onTap: onEdit,
    );
  }
}
