import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dance/dance_library_providers.dart';
import '../home/dance_detail_page.dart';
import '../persistence/song_signature.dart';
import 'dance_ranking.dart';
import 'practice_stats_daily.dart';
import 'practice_stats_format.dart';
import 'practice_stats_heatmap.dart';
import 'practice_stats_records_provider.dart';
import 'practice_stats_summary.dart';
import 'selection_haptic.dart';
import 'stats_daily_chart_card.dart';
import 'stats_year_heatmap_card.dart';

/// 统计 Tab：常驻仪表盘、年热力图、每日练习时长
/// 柱状图、当天明细与单舞排行，区块次序固定。点柱或点格在页内展开当天各舞
/// 明细，明细行与排行行 push 舞详情；无任何练习记录时整页空态引导，不出空
/// 图表。仪表盘恒按时长，不随柱状图范围等筛选变化。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  /// 时间维度：默认近 30 天；驱动柱状图窗口与排行范围。
  PracticeStatsWindow _window = PracticeStatsWindow.last30;

  /// 单位：默认按时间；驱动热力图、柱状图、明细与排行。
  StatsMetric _metric = StatsMetric.time;

  /// 已展开明细的本地日；null = 未选。
  DateTime? _selectedDay;

  /// 柱状图气泡的手指 y（图区本地坐标）：由柱状图的点按 / 拖动带
  /// 入、纵向跟手；null（热力图选中、或尚未点过柱状图）时气泡贴绘图区顶部。
  double? _barBubbleFingerY;

  /// 热力图滑动选择模式（模式归页面持有）；
  /// 模式内点热力图以外任意处退出。
  bool _heatmapSelecting = false;

  final GlobalKey _heatmapCardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(practiceStatsRecordsProvider);
    // 排行口径 = 现存索引条目：舞库快照只含现存舞，已删舞的历史没有条目可挂。
    final library = ref.watch(danceLibrarySnapshotProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: records.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // store 读失败已在存储侧静默兜底为空集，错误分支不预期；按空态呈现。
        error: (_, _) => const _StatsEmpty(),
        data: (list) {
          // 「无练习」按内容判定：全为 0 秒的记录不渲染零值汇总卡与图表。
          if (!list.any((record) => record.wallSeconds > 0)) {
            return const _StatsEmpty();
          }
          final now = DateTime.now();
          final summary = summarizePracticeStats(list, now: now);
          final selectedDay = _selectedDay;
          final librarySnapshot = library.asData?.value;
          // 选中日明细：柱状图气泡与日下钻卡共用同一份（两图共用选中日）。
          final detail = selectedDay == null
              ? null
              : dailyPracticeDetail(list, selectedDay);
          // 动态分档边界：供热力图色深定档。
          final heatmapBounds = heatmapQuantileBounds(
            list,
            now: now,
            metric: _metric,
          );
          // 滑动选择模式下，热力图以外的按下即退出。
          // 单击空白（未被数据点、行与控件认领的按下→抬起）取消选择：一次
          // 退出滑动选择模式、清空选中日并收起明细；拖动与长按
          // 不构成单击，图卡内的标题/图例/轴标签条与卡外任意位置没有更深
          // 的手势认领，单击自然落到这一层。
          return Listener(
            onPointerDown: _exitSelectionIfOutsideHeatmap,
            behavior: HitTestBehavior.translucent,
            child: GestureDetector(
              onTap: _clearSelection,
              behavior: HitTestBehavior.translucent,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _DashboardCard(summary: summary),
                  const SizedBox(height: 12),
                  _FilterRow(
                    window: _window,
                    metric: _metric,
                    onWindowChanged: _selectWindow,
                    onMetricChanged: _selectMetric,
                  ),
                  const SizedBox(height: 12),
                  YearHeatmapCard(
                    cardKey: _heatmapCardKey,
                    weeks: yearHeatmapWeeks(
                      list,
                      now: now,
                      metric: _metric,
                      bounds: heatmapBounds,
                    ),
                    metric: _metric,
                    selectedDay: selectedDay,
                    selecting: _heatmapSelecting,
                    onDayTap: (day) => setState(() {
                      _selectedDay = day;
                      _barBubbleFingerY = null;
                    }),
                    onBlankTap: _clearSelection,
                    onSelectionModeChanged: (selecting) {
                      // 进模式经原生震动通道震一次；
                      // 通道缺失时静默无操作。
                      if (selecting) {
                        unawaited(
                          ref.read(selectionHapticProvider).selectionImpact(),
                        );
                      }
                      setState(() => _heatmapSelecting = selecting);
                    },
                  ),
                  const SizedBox(height: 12),
                  DailyBarChartCard(
                    bars: dailyPracticeBars(list, now: now, window: _window),
                    metric: _metric,
                    window: _window,
                    selectedDay: selectedDay,
                    detail: detail,
                    bubbleFingerY: _barBubbleFingerY,
                    onDayTap: (day, fingerY) => setState(() {
                      _selectedDay = day;
                      _barBubbleFingerY = fingerY;
                    }),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 12),
                    _DayDetailCard(detail: detail, metric: _metric, now: now),
                  ],
                  // 舞库快照未就绪（加载中/读失败）时不出排行：不把「未装入」
                  // 冒充成「没有现存舞」。
                  if (librarySnapshot != null) ...[
                    const SizedBox(height: 12),
                    _DanceRankingCard(
                      rows: windowDanceRanking(
                        librarySnapshot.dances,
                        list,
                        now: now,
                        window: _window,
                        metric: _metric,
                      ),
                      metric: _metric,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 单击空白取消选择：一次退出滑动选择模式、清空选中日并收起
  /// 明细。无选中日时无副作用。
  void _clearSelection() {
    setState(() {
      _heatmapSelecting = false;
      _selectedDay = null;
    });
  }

  /// 滑动选择模式下，按下点落在热力图卡以外即退出模式；
  /// 选中日与明细保留，只回普通浏览。
  void _exitSelectionIfOutsideHeatmap(PointerDownEvent event) {
    if (!_heatmapSelecting) return;
    final box = _heatmapCardKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(event.position);
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx > box.size.width ||
        local.dy > box.size.height) {
      setState(() => _heatmapSelecting = false);
    }
  }

  /// 窗口切换只换柱状图与排行的范围：已选日可能落在新窗口外，一并清空
  /// （不展示窗口外明细）。仪表盘与热力图窗口不受影响；滑动选择模式一并
  /// 退出（旧窗口的模式不留在新窗口）。
  void _selectWindow(PracticeStatsWindow window) {
    setState(() {
      _window = window;
      _selectedDay = null;
      _barBubbleFingerY = null;
      _heatmapSelecting = false;
    });
  }

  /// 单位切换重算热力图、柱状图、明细与排行的量；选中日、气泡与滑动选择
  /// 模式一并清空退出。
  void _selectMetric(StatsMetric metric) {
    setState(() {
      _metric = metric;
      _selectedDay = null;
      _barBubbleFingerY = null;
      _heatmapSelecting = false;
    });
  }
}

/// 筛选行：时间维度（近 7/30/90 天）与单位
/// （按时间/按次数）两组控件；随页滚动、不吸顶。范围与排序键只由本行
/// 提供，柱状图与排行卡内不再保留各自的控件。
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.window,
    required this.metric,
    required this.onWindowChanged,
    required this.onMetricChanged,
  });

  final PracticeStatsWindow window;
  final StatsMetric metric;
  final ValueChanged<PracticeStatsWindow> onWindowChanged;
  final ValueChanged<StatsMetric> onMetricChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('filter_row'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final option in PracticeStatsWindow.values)
              ChoiceChip(
                key: Key('filter_window_${option.days}'),
                label: Text('近 ${option.days} 天'),
                selected: option == window,
                // 只响应「选中」：再点当前范围不清掉已展开的明细。
                onSelected: (selected) {
                  if (selected) onWindowChanged(option);
                },
              ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('filter_unit_time'),
              label: const Text('按时间'),
              selected: metric == StatsMetric.time,
              onSelected: (selected) {
                if (selected) onMetricChanged(StatsMetric.time);
              },
            ),
            ChoiceChip(
              key: const Key('filter_unit_count'),
              label: const Text('按次数'),
              selected: metric == StatsMetric.count,
              onSelected: (selected) {
                if (selected) onMetricChanged(StatsMetric.count);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 常驻仪表盘：上行两张宽卡「今日练习 / 累计练习」，下行
/// 三张窄卡「本周练习 / 当前连续天数 / 最长连续天数」。恒按时长，不受筛选
/// 影响。
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.summary});

  final PracticeStatsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('dashboard_card'),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DashboardCardFace(
                cardKey: const Key('dashboard_today'),
                caption: '今日练习',
                value: statsDurationText(summary.today),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DashboardCardFace(
                cardKey: const Key('dashboard_total'),
                caption: '累计练习',
                value: statsDurationText(summary.total),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DashboardCardFace(
                cardKey: const Key('dashboard_week'),
                caption: '本周练习',
                value: statsDurationText(summary.week),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DashboardCardFace(
                cardKey: const Key('dashboard_current_streak'),
                caption: '当前连续天数',
                value: '${summary.currentStreakDays} 天',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DashboardCardFace(
                cardKey: const Key('dashboard_longest_streak'),
                caption: '最长连续天数',
                value: '${summary.longestStreakDays} 天',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 单张仪表盘卡面：大号加粗数字在上（窄屏单行缩放不溢出），灰色小字口径
/// 说明在下。
class _DashboardCardFace extends StatelessWidget {
  const _DashboardCardFace({
    required this.cardKey,
    required this.caption,
    required this.value,
  });

  final Key cardKey;
  final String caption;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: cardKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.titleLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单舞排行卡：排序与范围只认筛选行选中的窗口 × 单位；
/// 行显示舞名与当前单位的一个数值；窗口内当前单位为 0 的舞不出行，空列表
/// 文案「这段时间没有练习」；点行 push 舞详情。
class _DanceRankingCard extends StatelessWidget {
  const _DanceRankingCard({required this.rows, required this.metric});

  final List<DanceRankingRow> rows;
  final StatsMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = rankingMaxValue(rows, metric);
    return Card(
      key: const Key('ranking_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('单舞排行', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              const Padding(
                key: Key('ranking_empty'),
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('这段时间没有练习'),
              )
            else
              for (final row in rows)
                _ValueBarRow(
                  keyPrefix: 'ranking',
                  valueKeyPrefix: 'ranking_row_key',
                  videoId: row.videoId,
                  title: row.title,
                  valueText: row.valueTextFor(metric),
                  fraction: max > 0 ? row.valueFor(metric) / max : 0,
                ),
          ],
        ),
      ),
    );
  }
}

/// 日下钻卡：当天日期与合计（当前单位）+ 各舞按当前单位降序；空日显示
/// 空文案，明细行 push 该舞详情（已删除的舞进详情页由其自身的「已不在
/// 舞库」兜底）。
class _DayDetailCard extends StatelessWidget {
  const _DayDetailCard({
    required this.detail,
    required this.metric,
    required this.now,
  });

  final DailyPracticeDetail detail;
  final StatsMetric metric;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dances = detail.dancesSortedBy(metric);
    final max = dayDetailMaxValue(dances, metric);
    return Card(
      key: const Key('day_detail'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  dayLabel(detail.day, now: now),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                Text(
                  detail.textFor(metric),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (detail.dances.isEmpty)
              const Padding(
                key: Key('day_detail_empty'),
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('这天没有练习'),
              )
            else
              for (final dance in dances)
                _ValueBarRow(
                  keyPrefix: 'day_detail',
                  valueKeyPrefix: 'day_detail_value',
                  videoId: dance.videoId,
                  title: signatureDisplayText(dance.signature, dance.videoId),
                  valueText: dance.textFor(metric),
                  fraction: max > 0 ? dance.valueFor(metric) / max : 0,
                ),
          ],
        ),
      ),
    );
  }
}

/// 明细行版式：标题单行省略 + 右侧一列——数值在上（titleMedium、水平居中于
/// 进度条中心）、固定宽度 96 的进度条在下（minHeight 6、圆角 3、主题主色），
/// 按传入的归一比例填充；点行 push 该舞详情。
class _ValueBarRow extends StatelessWidget {
  const _ValueBarRow({
    required this.keyPrefix,
    required this.valueKeyPrefix,
    required this.videoId,
    required this.title,
    required this.valueText,
    required this.fraction,
  });

  /// 行与进度条键前缀：`${keyPrefix}_row_$videoId` / `${keyPrefix}_bar_$videoId`。
  final String keyPrefix;

  /// 数值文本键前缀：`${valueKeyPrefix}_$videoId`。
  final String valueKeyPrefix;
  final String videoId;
  final String title;
  final String valueText;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      key: Key('${keyPrefix}_row_$videoId'),
      contentPadding: EdgeInsets.zero,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: SizedBox(
        key: Key('${keyPrefix}_bar_$videoId'),
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              valueText,
              key: Key('${valueKeyPrefix}_$videoId'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DanceDetailPage(videoId: videoId),
        ),
      ),
    );
  }
}

/// 无任何练习记录：整页空态引导（不渲染零值图表）。
class _StatsEmpty extends StatelessWidget {
  const _StatsEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('stats_empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('还没有练习记录', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('先去练一次，这里就有数据了', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
