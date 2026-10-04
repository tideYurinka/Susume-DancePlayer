import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/learning_segment_attributes.dart';
import '../core/device_clock.dart';
import '../core/hit_layer.dart';
import '../core/hit_target.dart' show hitTargetStart, kHitTargetMinSize;
import '../core/local_day.dart';
import '../dance/dance_library_providers.dart';
import '../home/dance_detail_page.dart';
import '../persistence/practice_plan.dart';
import '../persistence/practice_plan_providers.dart';
import 'agenda_list.dart';
import 'dance_plan_editor.dart';
import 'dance_plan_manager_page.dart';
import 'plan_day_panel.dart';
import 'plan_event_editors.dart';
import 'plan_mark_kind.dart';
import 'plan_marker_palette.dart';
import 'plan_page_layout.dart';
import 'practice_reminders.dart';
import 'system_push_provider.dart';
import '../persistence/team_check_gate.dart';

/// 计划 Tab：一年时间轴条 →
/// 月视图日历 → 点日下栏 → 日程列表三组。时间轴固定覆盖当前月起
/// 12 个月、段内分类型竖线与图例；无任何计划时不出整页空态，只在页内
/// 提示条，时间轴与月视图常显。
class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({super.key});

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  /// 选中的本地日；null = 未选（下栏不出）。
  DateTime? _selectedDay;

  /// 日历所示月（零点，与选中日分离）：初值为页面装载时的当前月。
  late DateTime _shownMonth;

  @override
  void initState() {
    super.initState();
    _shownMonth = planMonthOf(ref.read(deviceClockProvider)());
  }

  /// 切月：更新所示月；真正换了月才清除选中日（下栏随之收起）。
  void _showMonth(DateTime month) {
    final target = planMonthOf(month);
    setState(() {
      if (target != _shownMonth) _selectedDay = null;
      _shownMonth = target;
    });
  }

  /// 按 [delta] 个月翻月（上/下一月、网格手势共用）。
  void _shiftMonth(int delta) => _showMonth(planShiftMonth(_shownMonth, delta));

  /// 回当前月并选中今天（「今天」按钮）。
  void _backToToday(DateTime now) {
    setState(() {
      _shownMonth = planMonthOf(now);
      _selectedDay = localDay(now);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(practicePlanEntriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('计划'),
        actions: [
          IconButton(
            key: const Key('plan_manage_entry'),
            tooltip: '各舞计划',
            icon: const Icon(Icons.tune_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DancePlanManagerPage(),
              ),
            ),
          ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // store 读失败已在存储侧静默兜底为空集，错误分支不预期；按无计划呈现。
        error: (_, _) => _planBody(const []),
        data: _planBody,
      ),
    );
  }

  Widget _planBody(List<DancePlanEntry> list) {
    final eventList =
        ref.watch(practicePlanEventsProvider).asData?.value ??
        const <PlanEvent>[];
    final library = ref.watch(danceLibrarySnapshotProvider);
    final dances = library.asData?.value.dances ?? const [];
    final titleByVideoId = <String, String>{
      for (final dance in dances) dance.videoId: dance.title,
    };
    final masteriesByVideoId = <String, Set<LearningMastery>>{
      for (final dance in dances)
        dance.videoId: {for (final segment in dance.segments) segment.mastery},
    };
    final entryByVideoId = <String, DancePlanEntry>{
      for (final entry in list) entry.videoId: entry,
    };
    // 三类计划日分列：时间轴标记、日历圆点与空态判定同一份归集。
    final marks = planMarksByKind(list, events: eventList);
    final now = ref.watch(deviceClockProvider)();
    final currentMonth = planMonthOf(now);
    final shownMonth = _shownMonth;
    final selectedDay = _selectedDay;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (marks.values.every((days) => days.isEmpty)) const _PlanEmptyHint(),
        _TimelineBar(
          timeline: buildPlanTimeline(marks, now: now),
          shownMonth: shownMonth,
          onSelectMonth: _showMonth,
        ),
        const SizedBox(height: 12),
        _MonthGridCard(
          grid: buildPlanMonthGrid(shownMonth),
          marks: marks,
          selectedDay: selectedDay,
          showToday: shownMonth != currentMonth,
          onDayTap: (day) => setState(() {
            // 点跨月补位日即切到它所在的月并选中它。
            _shownMonth = planMonthOf(day);
            _selectedDay = day;
          }),
          onPreviousMonth: () => _shiftMonth(-1),
          onNextMonth: () => _shiftMonth(1),
          onToday: () => _backToToday(now),
          onSwipe: (swipe) => switch (swipe) {
            PlanMonthSwipe.previous => _shiftMonth(-1),
            PlanMonthSwipe.next => _shiftMonth(1),
            PlanMonthSwipe.none => null,
          },
        ),
        if (selectedDay != null) ...[
          const SizedBox(height: 12),
          DayPanel(
            day: selectedDay,
            ddls: ddlsOnDay(list, day: selectedDay),
            events: eventsOnDay(eventList, day: selectedDay),
            masteriesByVideoId: masteriesByVideoId,
            titleByVideoId: titleByVideoId,
            onAddEvent: () => _openEventEditor(selectedDay),
            onEditEvent: (event) =>
                _openEventEditor(selectedDay, initial: event),
            onAddTeamCheck: () => _openTeamCheckEditor(selectedDay),
            onEditTeamCheck: (event) =>
                _openTeamCheckEditor(selectedDay, initial: event),
          ),
        ],
        const SizedBox(height: 12),
        _AgendaSection(
          due: agendaDueItems(
            entries: list,
            events: eventList,
            teamCheckAchieved: (event) => teamCheckAchieved(
              event: event,
              gateStatusOf: (videoId) => danceGateStatus(
                gate: teamCheckGateFromName(event.danceGates[videoId]),
                segmentMasteries: masteriesByVideoId[videoId] ?? const {},
              ),
            ),
            now: now,
          ),
          review: agendaReviewItems(
            dances: [
              for (final dance in dances)
                AgendaReviewDance(
                  videoId: dance.videoId,
                  level: danceReminderLevel(
                    masteriesByVideoId[dance.videoId] ?? const {},
                  ),
                  lastPracticeDay: dance.lastPracticedAt,
                  goalKind: danceGoalMarkKind(
                    ddl: entryByVideoId[dance.videoId]?.ddl,
                    events: eventList,
                    videoId: dance.videoId,
                    now: now,
                  ),
                ),
            ],
            now: now,
          ),
          social: agendaSocialItems(events: eventList, now: now),
          titleByVideoId: titleByVideoId,
          onOpenDance: (videoId) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DanceDetailPage(videoId: videoId),
            ),
          ),
          onEditEvent: (event) => _openEventEditor(event.date, initial: event),
        ),
      ],
    );
  }

  /// 新建 / 编辑随舞事件：进全屏编辑页，保存经 store 落盘并作废读面。
  /// 新建时默认关联清单 = 随舞曲库开关为「开」的舞。
  Future<void> _openEventEditor(DateTime day, {PlanEvent? initial}) async {
    final library = ref.read(danceLibrarySnapshotProvider).asData?.value;
    final disabled = await ref
        .read(practicePlanStoreProvider)
        .socialLibraryDisabledIds();
    if (!mounted) return;
    final defaultIds = defaultEventDanceIds([
      for (final dance in library?.dances ?? const []) dance.videoId,
    ], disabledIds: disabled);
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => EventEditorPage(
          day: day,
          today: ref.read(deviceClockProvider)(),
          dances: [
            for (final dance in library?.dances ?? const [])
              PlanEditorDance(
                videoId: dance.videoId,
                title: dance.title,
                checked:
                    initial?.danceIds.contains(dance.videoId) ??
                    defaultIds.contains(dance.videoId),
              ),
          ],
          initial: initial,
        ),
      ),
    );
    if (!mounted) return;
    await _persistEventResult(result, initial);
  }

  /// 新建 / 编辑团内检查：进全屏编辑页，保存经 store 落盘并作废读面。
  Future<void> _openTeamCheckEditor(DateTime day, {PlanEvent? initial}) async {
    final library = ref.read(danceLibrarySnapshotProvider).asData?.value;
    if (!mounted) return;
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => TeamCheckEditorPage(
          day: day,
          today: ref.read(deviceClockProvider)(),
          dances: [
            for (final dance in library?.dances ?? const [])
              PlanEditorDance(
                videoId: dance.videoId,
                title: dance.title,
                checked: initial?.danceIds.contains(dance.videoId) ?? false,
              ),
          ],
          initial: initial,
        ),
      ),
    );
    if (!mounted) return;
    await _persistEventResult(result, initial);
  }

  /// 编辑页结果落盘（保存 / 删除 / 取消），写后作废条目、事件与提醒读面
  /// （与计划 DDL 写路径同一条作废口径）。两类事件编辑页共用同一尾段。
  Future<void> _persistEventResult(Object? result, PlanEvent? initial) async {
    if (result is PlanEvent) {
      // 首次设置「提前 N 天」时系统询问通知权限：只在这一条路径、
      // 且此前未设提前量时弹；被拒后保存照常（降级为仅应用内提醒）。
      if (result.leadDays != null && initial?.leadDays == null) {
        await ref.read(planPushPlannerProvider).ensureReminderPermission();
      }
      final written = await ref
          .read(practicePlanStoreProvider)
          .saveEvent(result);
      if (!mounted) return;
      if (!written) {
        showPlanWriteFailure(context);
      }
    } else if (result is EventDeleted && initial != null) {
      await ref.read(practicePlanStoreProvider).deleteEvent(initial.id);
    } else {
      return;
    }
    invalidatePlanReadFaces(ref);
  }
}

/// 日程列表三组：即将到期 / 待复习 / 随舞临近。分组与排序取纯件
/// 同一出处；空组整块不渲染。点 DDL 与待复习行进舞详情，点团检与随舞行
/// 进事件编辑框。
class _AgendaSection extends StatelessWidget {
  const _AgendaSection({
    required this.due,
    required this.review,
    required this.social,
    required this.titleByVideoId,
    required this.onOpenDance,
    required this.onEditEvent,
  });

  final List<AgendaDueItem> due;
  final List<AgendaReviewItem> review;
  final List<PlanEvent> social;
  final Map<String, String> titleByVideoId;
  final ValueChanged<String> onOpenDance;
  final ValueChanged<PlanEvent> onEditEvent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('plan_agenda'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (due.isNotEmpty) ...[
          _groupHeader(theme, '即将到期', 'plan_agenda_due_header'),
          for (final item in due) _dueTile(item),
        ],
        if (review.isNotEmpty) ...[
          _groupHeader(theme, '待复习', 'plan_agenda_review_header'),
          for (final item in review)
            ListTile(
              key: Key('plan_agenda_review_${item.videoId}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.replay_outlined,
                color: planMarkColor(item.goalKind),
              ),
              title: Text(titleByVideoId[item.videoId] ?? item.videoId),
              subtitle: Text(
                '${item.exceedDays == null ? '未练' : '超 ${item.exceedDays} 天'} · '
                '${item.level == null ? '未练' : learningMasteryLabel(item.level!)}',
              ),
              onTap: () => onOpenDance(item.videoId),
            ),
        ],
        if (social.isNotEmpty) ...[
          _groupHeader(theme, '随舞临近', 'plan_agenda_social_header'),
          for (final event in social)
            ListTile(
              key: Key('plan_agenda_social_${event.id}'),
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.celebration_outlined,
                color: planMarkColor(PlanMarkKind.social),
              ),
              title: Text(event.location.isEmpty ? '随舞' : event.location),
              subtitle: Text(
                '${event.date.month}月${event.date.day}日 · '
                '${event.danceIds.length} 支舞',
              ),
              onTap: () => onEditEvent(event),
            ),
        ],
      ],
    );
  }

  /// 一行内只判一次来源，icon / 标题 / 去向同源（颜色取标记类型映射）。
  Widget _dueTile(AgendaDueItem item) {
    final isDdl = item.source == AgendaDueSource.ddl;
    return ListTile(
      key: Key('plan_agenda_due_${item.key}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isDdl ? Icons.flag_outlined : Icons.groups_outlined,
        color: planMarkColor(isDdl ? PlanMarkKind.ddl : PlanMarkKind.teamCheck),
      ),
      title: Text(
        isDdl
            ? titleByVideoId[item.videoId] ?? item.videoId!
            : item.event!.location.isEmpty
            ? '团检'
            : '团检 · ${item.event!.location}',
      ),
      subtitle: Text(
        '${item.targetLabel} · ${_remainingText(item.remainingDays)}',
      ),
      onTap: isDdl
          ? () => onOpenDance(item.videoId!)
          : () => onEditEvent(item.event!),
    );
  }

  Widget _groupHeader(ThemeData theme, String label, String key) => Padding(
    key: Key(key),
    padding: const EdgeInsets.only(top: 8, bottom: 2),
    child: Text(label, style: theme.textTheme.titleMedium),
  );

  String _remainingText(int days) => days == 0 ? '今天到期' : '剩 $days 天';
}

/// 一屏 12 个月的年视图时间轴条：等宽月列铺满卡宽、不横向
/// 滚动；轨道上方按年分段标出年份、月间灰色竖虚线、列下月号（空月淡显）；计划日
/// 按类型画 2px 竖线（同类同日一条、多类以当天位置为中心并排），「今天」竖线落在
/// 当月列内真实位置，卡内一行图例恒显三类。点某个月列即切月，日历所示月列带浅色
/// 高亮。
class _TimelineBar extends StatelessWidget {
  const _TimelineBar({
    required this.timeline,
    required this.shownMonth,
    required this.onSelectMonth,
  });

  final PlanTimeline timeline;

  /// 日历所示月（高亮带落位）。
  final DateTime shownMonth;
  final ValueChanged<DateTime> onSelectMonth;

  /// 竖线轨道（月分隔虚线、今天线与计划标记）的高度。
  static const double _trackHeight = 34;

  /// 同日多类并排竖线的左缘间距与单条线宽。
  static const double _markGap = 3;
  static const double _markWidth = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('plan_timeline'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _yearRow(theme),
            // 月列切月命中层（「命中盒：唯一声明与外扩」）：12 列各约 26dp
            // 宽，列本身撑不到 48；故在整行上叠一层
            // 按列宽几何换算出的大命中区（每列一枚 48×48 透明层，第一/末列钳
            // 进行内），点按按最近列换算到目标月——命中矩形 ≥48，视觉列宽与
            // 高亮带逐位不变。语义落在透明层上（按钮角色 + 中文月名），视觉列
            // 自己的手势从无障碍树排除，免得同一入口报出两个节点。
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final pitch = width / timeline.segments.length;
                double hitLeftOf(int i) =>
                    hitTargetStart((i + 0.5) * pitch, width);
                return Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < timeline.segments.length; i++)
                          Expanded(
                            child: _column(
                              theme,
                              timeline.segments[i],
                              todayFraction: i == 0
                                  ? timeline.todayFraction
                                  : null,
                            ),
                          ),
                      ],
                    ),
                    for (var i = 0; i < timeline.segments.length; i++)
                      Positioned(
                        left: hitLeftOf(i),
                        top: 0,
                        width: kHitTargetMinSize,
                        height: kHitTargetMinSize,
                        child: HitTargetLayer(
                          key: Key(
                            'plan_timeline_hit_'
                            '${planMonthKey(timeline.segments[i].month)}',
                          ),
                          label:
                              '切到${timeline.segments[i].month.year}年'
                              '${timeline.segments[i].month.month}月',
                          onActivate: () =>
                              onSelectMonth(timeline.segments[i].month),
                          onTapUpLocal: (local) {
                            final x = hitLeftOf(i) + local.dx;
                            final index = (x / pitch).floor().clamp(
                              0,
                              timeline.segments.length - 1,
                            );
                            onSelectMonth(timeline.segments[index].month);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            _legend(theme),
          ],
        ),
      ),
    );
  }

  /// 年份分段行（卡级、在轨道上方）：按年分段、段宽按该年列数，年份贴段左缘。
  Widget _yearRow(ThemeData theme) => Row(
    children: [
      for (final span in timeline.yearSpans)
        Expanded(
          key: Key('plan_timeline_year_${span.year}'),
          flex: span.columnCount,
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${span.year}',
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _column(
    ThemeData theme,
    PlanTimelineSegment segment, {
    required double? todayFraction,
  }) {
    final isShownMonth = segment.month == shownMonth;
    DateTime dayOf(int dayNumber) =>
        DateTime(segment.month.year, segment.month.month, dayNumber);
    return GestureDetector(
      key: Key('plan_timeline_segment_${planMonthKey(segment.month)}'),
      behavior: HitTestBehavior.opaque,
      // 切月语义只报在 48dp 透明命中层上（见 _TimelineBar.build），视觉列
      // 自己的手势从无障碍树排除，免得同一入口两个节点。
      excludeFromSemantics: true,
      onTap: () => onSelectMonth(segment.month),
      // 高亮是整列底带：轨道与月号都在列内。
      child: Container(
        key: isShownMonth ? const Key('plan_timeline_selected_month') : null,
        color: isShownMonth
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : null,
        child: Column(
          children: [
            SizedBox(
              height: _trackHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  // 列内某日的横向位置（月首 0、月末 (天数-1)/天数）。
                  double xOf(int dayNumber) =>
                      segment.markerFraction(dayNumber) * width;
                  // 同日多类：整组以当天位置为中心并排；单类落在当天位置。
                  double markLeft(int dayNumber, int count, int rank) =>
                      count == 1
                      ? xOf(dayNumber)
                      : xOf(dayNumber) -
                            ((count - 1) * _markGap + _markWidth) / 2 +
                            rank * _markGap;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (segment.hasLeadingDivider)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: SizedBox(
                            key: Key(
                              'plan_timeline_divider_'
                              '${planDayKey(segment.month)}',
                            ),
                            width: 1,
                            child: CustomPaint(
                              painter: _DashedVerticalLinePainter(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ),
                      if (todayFraction != null)
                        Positioned(
                          left: todayFraction * width,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            key: const Key('plan_timeline_now'),
                            width: 2,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      for (final entry in segment.marksByDay.entries)
                        for (var rank = 0; rank < entry.value.length; rank++)
                          Positioned(
                            left: markLeft(entry.key, entry.value.length, rank),
                            top: 0,
                            bottom: 0,
                            child: Container(
                              key: Key(
                                planTimelineMarkerKey(
                                  entry.value[rank],
                                  planDayKey(dayOf(entry.key)),
                                ),
                              ),
                              width: _markWidth,
                              color: planMarkColor(entry.value[rank]),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
            Text(
              '${segment.month.month}',
              key: Key(
                'plan_timeline_month_label_${planMonthKey(segment.month)}',
              ),
              maxLines: 1,
              style: segment.hasMarks
                  ? theme.textTheme.bodySmall
                  : theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.35,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 图例一行排不下（窄档 + 大字号，包线遍历揭出）时整行等比缩小、
  // 不溢出不裁字（与标注工具行同一口径：内容论证、与视口无关）；
  // 宽裕时零缩放、取值不变。外层撑满卡宽（「铺满卡宽」的钉子），
  // 缩的是行内内容。
  Widget _legend(ThemeData theme) => SizedBox(
    key: const Key('plan_timeline_legend'),
    width: double.infinity,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          for (final kind in PlanMarkKind.values) ...[
            Container(
              key: Key('plan_timeline_legend_${planMarkSlug(kind)}'),
              width: 10,
              height: 10,
              color: planMarkColor(kind),
            ),
            const SizedBox(width: 4),
            Text(planMarkLabel(kind), style: theme.textTheme.bodySmall),
            if (kind != PlanMarkKind.values.last) const SizedBox(width: 12),
          ],
        ],
      ),
    ),
  );
}

/// 月分隔的灰色竖虚线。
class _DashedVerticalLinePainter extends CustomPainter {
  const _DashedVerticalLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width;
    const dash = 3.0;
    const gap = 3.0;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      canvas.drawLine(
        Offset(0, y),
        Offset(0, (y + dash).clamp(0.0, size.height).toDouble()),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedVerticalLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 月视图日历卡：以所示月铺网格，周一为首列；有计划的日子出
/// 圆点（三类一色）；头部左右按钮与网格左右滑动都能翻月、翻月
/// 不设边界；点某日即选中（选中日描边）。所示月非当前月时标题旁出「今天」。
class _MonthGridCard extends StatefulWidget {
  const _MonthGridCard({
    required this.grid,
    required this.marks,
    required this.selectedDay,
    required this.showToday,
    required this.onDayTap,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    required this.onSwipe,
  });

  final PlanMonthGrid grid;

  /// 各计划标记类型下有计划的日子（一类一色圆点，同一份归集）。
  final Map<PlanMarkKind, Set<DateTime>> marks;
  final DateTime? selectedDay;

  /// 所示月 ≠ 当前月时出「今天」。
  final bool showToday;
  final ValueChanged<DateTime> onDayTap;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final ValueChanged<PlanMonthSwipe> onSwipe;

  @override
  State<_MonthGridCard> createState() => _MonthGridCardState();
}

class _MonthGridCardState extends State<_MonthGridCard> {
  final PlanMonthSwipeTracker _swipe = PlanMonthSwipeTracker();

  static const List<String> _weekdayLabels = [
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grid = widget.grid;
    return Card(
      key: const Key('plan_month_grid'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('plan_month_prev'),
                  onPressed: widget.onPreviousMonth,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '上一月',
                ),
                Expanded(
                  child: Text(
                    '${grid.month.year}年${grid.month.month}月',
                    key: const Key('plan_month_title'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (widget.showToday)
                  TextButton(
                    key: const Key('plan_month_today'),
                    onPressed: widget.onToday,
                    child: const Text('今天'),
                  ),
                IconButton(
                  key: const Key('plan_month_next'),
                  onPressed: widget.onNextMonth,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '下一月',
                ),
              ],
            ),
            // 网格左右滑动翻月：手势阈值与方向由纯件判定。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _swipe.start(),
              onHorizontalDragUpdate: (details) {
                final swipe = _swipe.update(details.delta.dx, details.delta.dy);
                if (swipe != PlanMonthSwipe.none) widget.onSwipe(swipe);
              },
              onHorizontalDragEnd: (details) => widget.onSwipe(
                _swipe.finish(velocityX: details.velocity.pixelsPerSecond.dx),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (final label in _weekdayLabels)
                        Expanded(
                          child: Center(
                            child: Text(
                              label,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final week in grid.weeks)
                    Row(
                      children: [for (final day in week) _dayCell(theme, day)],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(ThemeData theme, DateTime day) {
    final dayKey = planDayKey(day);
    final inMonth = widget.grid.isInMonth(day);
    final selected =
        widget.selectedDay != null && localDay(widget.selectedDay!) == day;
    return Expanded(
      child: InkWell(
        key: Key('plan_day_$dayKey'),
        onTap: () => widget.onDayTap(day),
        child: Container(
          key: selected ? Key('plan_day_selected_$dayKey') : null,
          decoration: selected
              ? BoxDecoration(
                  border: Border.all(color: theme.colorScheme.primary),
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${day.day}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: inMonth
                      ? null
                      : theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 6,
                // 各计划标记类型各一枚圆点，取计划标记配色同一出处。
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final kind in PlanMarkKind.values)
                      if (widget.marks[kind]!.contains(day))
                        Container(
                          key: Key(
                            'plan_day_dot_${planMarkSlug(kind)}_$dayKey',
                          ),
                          width: 6,
                          margin: const EdgeInsets.only(right: 2),
                          decoration: BoxDecoration(
                            color: planMarkColor(kind),
                            shape: BoxShape.circle,
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页内空态提示条：无任何计划时时间轴与月视图照常显示，只出一条
/// 引导；新建入口改由点某日后的下栏承担。
class _PlanEmptyHint extends StatelessWidget {
  const _PlanEmptyHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('plan_empty_hint'),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.event_note_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '还没有练舞计划：在舞详情页给一支舞设个 DDL，或点某一天新建随舞 / 团检',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
