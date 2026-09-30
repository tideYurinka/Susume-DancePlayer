import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../annotation/learning_segment_attributes.dart'
    show LearningMastery, learningMasteryLabel;
import '../annotation/learning_segments.dart';
import '../core/bubble_position.dart';
import '../core/clock_text.dart';
import '../core/mastery_colors.dart';
import '../core/text_extent.dart';
import '../dance/practice_distribution.dart';
import '../dance/segment_practice_aggregation.dart' show SegmentPractice;
import '../stats/practice_stats_axis.dart';
import '../stats/practice_stats_daily.dart' show StatsMetric;
import '../stats/practice_stats_format.dart' show statsDurationText;

/// 练习分布曲线的纵轴刻度：复用统计页既有的整齐刻度纯件
/// （时长按分钟向上取整、次数直取，步长 ≤5 档），不另写一套。
BarChartAxis practiceDistributionAxis(
  List<PracticeDistributionBucket> buckets,
  PracticeDistributionMetric metric,
) {
  const microsPerMinute = Duration.microsecondsPerMinute;
  final statsMetric = metric == PracticeDistributionMetric.duration
      ? StatsMetric.time
      : StatsMetric.count;
  final maxValue = buckets.fold<int>(
    0,
    (max, bucket) => switch (metric) {
      // 时长口径以整分钟向上取参与取档，保证上界盖住真实桶值。
      PracticeDistributionMetric.duration => math.max(
        max,
        (bucket.duration.inMicroseconds + microsPerMinute - 1) ~/
            microsPerMinute,
      ),
      PracticeDistributionMetric.count => math.max(max, bucket.count),
    },
  );
  return barChartAxis(maxValue: maxValue, metric: statsMetric);
}

/// 曲线纵轴上界换算回内部表示（时长 = 微秒，次数 = 场次数），供曲线归一
/// 使用，与刻度线同尺。
double _upperInValue(BarChartAxis axis, PracticeDistributionMetric metric) =>
    metric == PracticeDistributionMetric.duration
    ? (axis.upperBound * Duration.microsecondsPerMinute).toDouble()
    : axis.upperBound.toDouble();

/// 舞详情「练习分布」曲线卡：只读的练习量曲线——横轴是绝对歌曲
/// 时间（`m:ss`，最多 4 档标签），每个采样点是一个四拍桶（横坐标取桶区间
/// 中点、按真实时间几何摆位），曲线只连线、不画数据点。「练习时长 / 练习
/// 次数」与「累计 / 近 7 天 / 今日」两行芯片照常驱动曲线。派生口径全在
/// [PracticeDistribution] 纯件，这里只渲染。
///
/// 交互单位是**学习段**：点按或横向滑动图中任意处即选中该时刻
/// 所属的学习段，选中段被 2dp 主题主色的左右两条竖边夹住，气泡
/// 显示段标签、秒级时间区间、练习时长、练习遍数与熟练度档位（读数随纵轴
/// 口径变化；范围口径由页面换算进 [segmentPractices]）。点无段覆盖处清除
/// 选中；点气泡本身不清除；气泡对拖动透明（拖动由图上那层手势接管）。
class PracticeDistributionCard extends StatefulWidget {
  const PracticeDistributionCard({
    super.key,
    required this.buckets,
    required this.metric,
    required this.range,
    required this.beatGridNotReady,
    this.segments = const [],
    this.masteries = const {},
    this.segmentPractices = const [],
    required this.onSegmentMasteryChanged,
    this.actions,
    required this.onMetricChanged,
    required this.onRangeChanged,
  });

  /// 四拍桶采样点（自左向右按时间升序）。
  final List<PracticeDistributionBucket> buckets;

  final PracticeDistributionMetric metric;
  final PracticeDistributionRange range;

  /// 该时段无节拍数据（网格未就绪）：无采样点，显示既有空态文案。
  final bool beatGridNotReady;

  /// 学习段几何（色带铺位与段级选中共用；色带不随纵轴与范围切换变化）。
  final List<LearningSegment> segments;

  /// 段序 → 熟练度档位（缺项按未练）。
  final Map<int, LearningMastery> masteries;

  /// 逐段练习值（与 [segments] 按下标对齐；页面按当前范围口径换算）。
  final List<SegmentPractice> segmentPractices;

  /// 就地改档回调（选中段的段序 + 新档位），必传——按钮只在有分段时出现，
  /// 出现即必须有可写的落点；改档经详情页与播放器标注工具区写同一份
  /// `session.mastery` 文档段，读面作废后色带就地换色。
  final void Function(int order, LearningMastery mastery)
  onSegmentMasteryChanged;

  /// 卡片标题行右侧的动作（如「一键完全掌握」）；null = 无动作。
  final Widget? actions;

  final ValueChanged<PracticeDistributionMetric> onMetricChanged;
  final ValueChanged<PracticeDistributionRange> onRangeChanged;

  @override
  State<PracticeDistributionCard> createState() =>
      _PracticeDistributionCardState();
}

const double _chartHeight = 140;

const double _labelRowHeight = 18;

/// 绘图区左右内缩（曲线与时间标签共用同一份，保证对齐）。
const double _plotPad = 18;

/// 时间标签盒宽与半宽（钳边用）。
const double _labelWidth = 60;

/// 刻度列最小宽（排版容量——实际宽按系统字号放大，与统计页同款）。
const double _axisMinWidth = 28;

class _PracticeDistributionCardState extends State<PracticeDistributionCard> {
  /// 当前选中的段序；null = 未选中。
  int? _selectedSegment;

  /// 最近一次手势的手指 y（绘图区局部坐标），气泡纵向跟手用。
  double _fingerY = 0;

  /// 气泡在绘图区内的矩形（打开时记录），点按豁免判定用。
  Rect? _bubbleRect;

  void _selectAt(
    double dx,
    double dy,
    double plotWidth, {
    required bool isTap,
  }) {
    if (widget.segments.isEmpty || widget.buckets.isEmpty) return;
    // 时间域与曲线/色带同一份（桶中点首/末），不另推一套。
    final mids = _geometry(plotWidth).mids;
    final time = timeAtPixel(
      dx,
      domainStart: mids.first,
      domainEnd: mids.last,
      width: plotWidth,
      pad: _plotPad,
    );
    final index = segmentIndexAtTime(widget.segments, time);
    setState(() {
      _fingerY = dy;
      if (index == null) {
        // 滑动经过空隙不改变选中；点按空隙（且不在气泡上）清除选中。
        if (isTap && !(_bubbleRect?.contains(Offset(dx, dy)) ?? false)) {
          _selectedSegment = null;
          _bubbleRect = null;
        }
        return;
      }
      _selectedSegment = index;
      _bubbleRect = null; // 重建后由气泡自己再登记。
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final tickStyle = _tickStyle(theme);
    final axis = practiceDistributionAxis(widget.buckets, widget.metric);
    final axisWidth = _axisWidthFor(axis.ticks, tickStyle, textScaler);
    return Card(
      key: const Key('practice_distribution_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('练习分布', style: theme.textTheme.titleMedium),
                const Spacer(),
                ?widget.actions,
              ],
            ),
            const SizedBox(height: 8),
            _chips(
              keyPrefix: 'practice_metric',
              options: PracticeDistributionMetric.values,
              label: _metricLabel,
              selected: widget.metric,
              onSelected: widget.onMetricChanged,
            ),
            _chips(
              keyPrefix: 'practice_range',
              options: PracticeDistributionRange.values,
              label: _rangeLabel,
              selected: widget.range,
              onSelected: widget.onRangeChanged,
            ),
            const SizedBox(height: 8),
            if (widget.buckets.isEmpty)
              KeyedSubtree(
                key: const Key('practice_distribution_empty'),
                child: Text(
                  widget.beatGridNotReady ? '该时段无节拍数据' : '暂无数据',
                  style: theme.textTheme.bodySmall,
                ),
              )
            else ...[
              _chartWithAxis(context, axis, tickStyle, axisWidth),
              Padding(
                // 标签行与绘图区左对齐（刻度列 + 间隙不计入横轴）。
                padding: EdgeInsets.only(left: axisWidth + 4),
                child: SizedBox(
                  key: const Key('practice_time_label_row'),
                  height: _labelRowHeightFor(tickStyle, textScaler),
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        _timeLabels(constraints.maxWidth, theme),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            // 卡片底部一行：左侧五档图例（色点 + 档位名），右侧熟练度菜单
            // 按钮（这支舞没有任何分段时按钮不出现，图例仍显示）。
            Row(
              children: [
                Expanded(child: _masteryLegend(theme)),
                if (widget.segments.isNotEmpty) _masteryMenuButton(theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 五档图例：色点取 `learningMasteryColor`（与色带同一个入口）+ 档位名。
  Widget _masteryLegend(ThemeData theme) {
    final labelStyle = theme.textTheme.bodySmall;
    return Wrap(
      key: const Key('practice_mastery_legend'),
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final mastery in LearningMastery.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: Key('practice_legend_dot_${mastery.name}'),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: learningMasteryColor(mastery),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(learningMasteryLabel(mastery), style: labelStyle),
            ],
          ),
      ],
    );
  }

  /// 熟练度菜单按钮：显示当前选中段（卡片内部选中态）的档位名；
  /// 未选中任何段时置灰不可点；菜单为既有五档菜单（当前档高亮）。改档经
  /// [PracticeDistributionCard.onSegmentMasteryChanged] 走详情页写面，读面
  /// 更新后色带、选中边框与气泡就地换新，气泡保持打开。
  Widget _masteryMenuButton(ThemeData theme) {
    final selected = _selectedSegment;
    // 选中按下标对齐段表，段序才是写面身份。
    final order = selected != null && selected < widget.segments.length
        ? widget.segments[selected].order
        : null;
    // 未选中任何段时按钮置灰并显示「熟练度」占位——「未选中」不等于「未练」，
    // 不借未练档位名顶位。
    final current = order == null
        ? LearningMastery.unlearned
        : (widget.masteries[order] ?? LearningMastery.unlearned);
    final enabled = order != null;
    final labelStyle = theme.textTheme.bodyMedium;
    return PopupMenuButton<LearningMastery>(
      key: const Key('practice_mastery'),
      enabled: enabled,
      onSelected: (value) =>
          widget.onSegmentMasteryChanged(order!, value),
      itemBuilder: (context) => [
        for (final candidate in LearningMastery.values)
          CheckedPopupMenuItem<LearningMastery>(
            key: Key('practice_mastery_${candidate.name}'),
            value: candidate,
            checked: candidate == current,
            child: Text(learningMasteryLabel(candidate)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? theme.colorScheme.outline : theme.disabledColor,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              enabled ? learningMasteryLabel(current) : '熟练度',
              style: enabled
                  ? labelStyle
                  : labelStyle?.copyWith(color: theme.disabledColor),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: enabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.disabledColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chips<T extends Enum>({
    required String keyPrefix,
    required List<T> options,
    required String Function(T) label,
    required T selected,
    required ValueChanged<T> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            key: Key('${keyPrefix}_${option.name}'),
            label: Text(label(option)),
            selected: option == selected,
            // 只响应「选中」：再点当前档不改变状态。
            onSelected: (isSelected) {
              if (isSelected) onSelected(option);
            },
          ),
      ],
    );
  }

  /// 横坐标几何：桶中点序列与其在 [width] 内的真实时间 x（曲线与标签共用，
  /// 不各算一次）。
  ({List<Duration> mids, List<double> xs}) _geometry(double width) {
    final mids = [for (final bucket in widget.buckets) bucket.midpoint];
    return (mids: mids, xs: timeLerpX(mids, width: width, pad: _plotPad));
  }

  /// 刻度列实际宽：按系统字号实测最宽刻度（量测与渲染吃同一个
  /// [TextScaler]）；`textScaler < 1` 不收缩，与统计页同口径。
  double _axisWidthFor(
    List<int> ticks,
    TextStyle style,
    TextScaler textScaler,
  ) {
    var width = _axisMinWidth;
    for (final tick in ticks) {
      width = math.max(
        width,
        measureTextExtent('$tick', style, scaler: textScaler).width + 4,
      );
    }
    return width;
  }

  TextStyle _tickStyle(ThemeData theme) => theme.textTheme.bodySmall!.copyWith(
    color: theme.colorScheme.onSurfaceVariant,
  );

  /// 时间标签行高：排版容量随系统字号放大（下限固定高、缩小档不收缩），
  /// 与统计页 x 轴标签行同款。
  double _labelRowHeightFor(TextStyle style, TextScaler textScaler) {
    final fontSize = style.fontSize!;
    return math.max(
      _labelRowHeight,
      math.max(fontSize, textScaler.scale(fontSize)) * 1.4,
    );
  }

  /// 图 + 左侧刻度列：刻度列宽随系统字号放大；绘图区铺长横虚线（每档一条、
  /// 含 0 基线，与统计页柱状图同款 6/4 节拍），曲线按同一上界归一。绘图区
  /// 上叠一整层透明手势层（点按 + 横向拖动）与段级气泡（对指针
  /// 透明，拖动由手势层接管）。
  Widget _chartWithAxis(
    BuildContext context,
    BarChartAxis axis,
    TextStyle tickStyle,
    double axisWidth,
  ) {
    return SizedBox(
      key: const Key('practice_distribution_chart'),
      height: _chartHeight,
      child: Row(
        children: [
          SizedBox(
            key: const Key('practice_axis_column'),
            width: axisWidth,
            height: _chartHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 刻度自上而下：上界在顶、0 在底（与虚线同尺）。
                for (final tick in axis.ticks.reversed)
                  Text(
                    '$tick',
                    key: Key('practice_axis_tick_$tick'),
                    style: tickStyle,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: _chartHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  const height = _chartHeight;
                  final geometry = _geometry(width);
                  final xs = geometry.xs;
                  // 熟练度色带：按段的真实时间铺位，时间域与曲线同一份（桶
                  // 中点首/末）；不随纵轴与范围切换变化——只由段几何与档位
                  // 决定。
                  final bands = masteryBands(
                    segments: widget.segments,
                    masteries: widget.masteries,
                    domainStart: geometry.mids.first,
                    domainEnd: geometry.mids.last,
                    width: width,
                    pad: _plotPad,
                  );
                  final upperValue = _upperInValue(axis, widget.metric);
                  final offsets = <Offset>[
                    for (var i = 0; i < widget.buckets.length; i++)
                      Offset(
                        xs[i],
                        height -
                            widget.buckets[i].valueFor(widget.metric) /
                                upperValue *
                                height,
                      ),
                  ];
                  // 选中段的像素区间：选中边框与气泡锚点共用一份几何。
                  final selected = _selectedSegment;
                  final selectedRange =
                      selected != null && selected < widget.segments.length
                      ? segmentPixelRange(
                          widget.segments[selected],
                          domainStart: geometry.mids.first,
                          domainEnd: geometry.mids.last,
                          width: width,
                          pad: _plotPad,
                        )
                      : null;
                  // 气泡矩形登记（点按豁免判定的唯一事实）：每次重建就地
                  // 刷新，无气泡帧清空——不留上帧残留。
                  final bubble =
                      selectedRange != null &&
                          selected! < widget.segmentPractices.length
                      ? _bubble(
                          context,
                          plotWidth: width,
                          plotHeight: height,
                          segment: widget.segments[selected],
                          practice: widget.segmentPractices[selected],
                          segmentRange: selectedRange,
                        )
                      : null;
                  _bubbleRect = bubble?.rect;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        size: Size(width, height),
                        key: const Key('practice_gridlines'),
                        painter: DistributionPainter(
                          offsets: offsets,
                          bands: bands,
                          color: Theme.of(context).colorScheme.primary,
                          ticks: axis.ticks,
                          upperBound: axis.upperBound,
                          gridColor: Theme.of(context).dividerColor,
                          selection: selectedRange,
                        ),
                      ),
                      // 透明手势层：点按与横向拖动统一换算成时刻 → 所属学习段。
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapUp: (details) => _selectAt(
                            details.localPosition.dx,
                            details.localPosition.dy,
                            width,
                            isTap: true,
                          ),
                          onHorizontalDragStart: (details) => _selectAt(
                            details.localPosition.dx,
                            details.localPosition.dy,
                            width,
                            isTap: false,
                          ),
                          onHorizontalDragUpdate: (details) => _selectAt(
                            details.localPosition.dx,
                            details.localPosition.dy,
                            width,
                            isTap: false,
                          ),
                        ),
                      ),
                      if (bubble != null) bubble.widget,
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 段级气泡：段标签 + 秒级时间区间 + 练习时长 / 遍数（跟随纵轴
  /// 口径）+ 熟练度档位。定位交给全 App 唯一的气泡避让纯件
  /// [avoidingBubblePosition]——纵向中心对齐手指 y 并钳在绘图区内，
  /// 横向避让选中段的像素区间（段中心在绘图区左半时气泡贴其右缘、右半时贴
  /// 左缘，与该段不留缝；左右都放不下时钳在绘图区内为止、允许压住选中段）。
  /// 对指针透明：点它不清除、拖动不被它截住。返回气泡件与它在绘图区内的
  /// 矩形（点按豁免判定的唯一事实）。
  ({Widget widget, Rect rect}) _bubble(
    BuildContext context, {
    required double plotWidth,
    required double plotHeight,
    required LearningSegment segment,
    required SegmentPractice practice,
    required ({double left, double right}) segmentRange,
  }) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall!;
    final headline =
        '第 ${segment.order + 1} 段 · '
        '${clockMss(segment.start)}–${clockMss(segment.end)}';
    final durationText = statsDurationText(practice.practiceDuration);
    final practiceLine = widget.metric == PracticeDistributionMetric.duration
        ? '练习 $durationText · ${practice.practiceCount} 遍'
        : '${practice.practiceCount} 遍 · 练习 $durationText';
    final masteryText = learningMasteryLabel(
      widget.masteries[segment.order] ?? LearningMastery.unlearned,
    );
    const horizontalPadding = 10.0;
    const verticalPadding = 4.0;
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    // 量测与渲染同源：气泡宽由最长行撑开，不做额外宽度收缩。
    double textWidth(String text) =>
        measureTextExtent(text, style,
            direction: textDirection, scaler: textScaler).width;

    final bubbleWidth =
        [headline, practiceLine, masteryText].map(textWidth).reduce(math.max) +
        2 * horizontalPadding;
    final bodyText = '$headline\n$practiceLine\n$masteryText';
    final bodySize = measureTextExtent(
      bodyText,
      style,
      direction: textDirection,
      scaler: textScaler,
      maxWidth: bubbleWidth - 2 * horizontalPadding,
    );
    final bubbleHeight = bodySize.height + 2 * verticalPadding;
    final position = avoidingBubblePosition(
      fingerY: _fingerY,
      bubbleWidth: bubbleWidth,
      bubbleHeight: bubbleHeight,
      plotWidth: plotWidth,
      plotHeight: plotHeight,
      target: Rect.fromLTRB(
        segmentRange.left,
        0,
        segmentRange.right,
        plotHeight,
      ),
    );
    return (
      rect: Rect.fromLTWH(
        position.left,
        position.top,
        bubbleWidth,
        bubbleHeight,
      ),
      widget: Positioned(
        key: const Key('practice_segment_bubble'),
        left: position.left,
        top: position.top,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: style, maxLines: 1),
                Text(practiceLine, style: style, maxLines: 1),
                Text(masteryText, style: style, maxLines: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部时间标签：最多 4 档（首 / 约 1/3 / 约 2/3 / 末），`m:ss`，与曲线
  /// 共用同一份真实时间横坐标。
  Widget _timeLabels(double width, ThemeData theme) {
    final geometry = _geometry(width);
    final mids = geometry.mids;
    final xs = geometry.xs;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final i in timeTickIndices(widget.buckets.length))
          Positioned(
            key: Key('practice_time_label_$i'),
            left: (xs[i] - _labelWidth / 2).clamp(
              0.0,
              (width - _labelWidth).clamp(0.0, double.infinity),
            ),
            width: _labelWidth,
            top: 0,
            child: Text(
              clockMss(mids[i]),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// 熟练度色带（淡色填充、段界窄过渡、无段时段不填色）+ 长横虚线（每档一条、
/// 含 0 基线，节拍 6dp 实 / 4dp 空，与统计页柱状图同款——横向是读数参照）
/// + 选中边框（左右两条 2dp 主色竖边）+ 折线（只连线，不画数据点）。色带铺位
/// 由 [masteryBands] 纯件给出，颜色取 `learningMasteryColor`（与播放器段体
/// 同一套五档色）。
class DistributionPainter extends CustomPainter {
  const DistributionPainter({
    required this.offsets,
    required this.bands,
    required this.color,
    required this.ticks,
    required this.upperBound,
    required this.gridColor,
    this.selection,
  });

  final List<Offset> offsets;

  /// 曲线背后的熟练度色带铺位（像素区间 + 档位 + 过渡带宽）。
  final List<MasteryBand> bands;

  final Color color;

  /// 刻度值列表与整齐上界（虚线每档一条、按同一上界定位）。
  final List<int> ticks;
  final int upperBound;
  final Color gridColor;

  /// 选中段的像素区间：选中边框的两条竖边由它算出，与气泡锚点、
  /// 色带同源；null = 无选中。
  final ({double left, double right})? selection;

  /// 色带淡色填充透明度：颜色只作背景参照，不抢曲线读数。
  static const double _bandAlpha = 0.25;

  /// 选中边框竖边宽度：边的外沿贴段界，半个线宽即向段内缩 1dp。
  static const double _selectionEdgeWidth = 2;

  /// 色带与选中边框共用的纵向铺满区间（上下各内缩 `_plotPad`）。
  static ({double top, double bottom}) _plotVerticalBounds(double height) =>
      (top: _plotPad, bottom: height - _plotPad);

  @override
  void paint(Canvas canvas, Size size) {
    _paintBands(canvas, size);
    if (upperBound > 0) {
      final grid = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      const dash = 6.0;
      const gap = 4.0;
      for (final tick in ticks) {
        final y = size.height * (1 - tick / upperBound);
        for (var x = 0.0; x < size.width; x += dash + gap) {
          canvas.drawLine(
            Offset(x, y),
            Offset(math.min(x + dash, size.width), y),
            grid,
          );
        }
      }
    }
    if (offsets.isEmpty) return;
    _paintSelection(canvas, size);
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final offset in offsets.skip(1)) {
      path.lineTo(offset.dx, offset.dy);
    }
    canvas.drawPath(path, line);
  }

  /// 选中边框：选中段的像素区间上画左右两条 2dp 主色竖边，纵向与
  /// 色带同一份上下内缩（`_plotPad`）。边的外沿贴段界，半个线宽即横向向段
  /// 内缩 1dp——两条边的外沿跨度因此等于该段像素区间，首末段贴绘图区边缘
  /// 时也不越出绘图区；不画上下边（那两条边会与长横虚线、y 轴刻度列争位
  /// 置）。段极窄时两条边各画各的：宽度不足 2dp 就收到段内，两条边重合成
  /// 一条也不省略、不越出段界。
  void _paintSelection(Canvas canvas, Size size) {
    final selection = this.selection;
    if (selection == null) return;
    final (:top, :bottom) = _plotVerticalBounds(size.height);
    final border = Paint()..color = color;
    canvas.drawRect(
      Rect.fromLTRB(
        selection.left,
        top,
        math.min(selection.left + _selectionEdgeWidth, selection.right),
        bottom,
      ),
      border,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        math.max(selection.right - _selectionEdgeWidth, selection.left),
        top,
        selection.right,
        bottom,
      ),
      border,
    );
  }

  void _paintBands(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    // 竖向铺满绘图区，与选中边框共用同一份上下内缩（`_plotPad`）。
    final (:top, :bottom) = _plotVerticalBounds(size.height);
    Color bandColor(MasteryBand band) =>
        learningMasteryColor(band.mastery).withValues(alpha: _bandAlpha);
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      // 固色区：两端各让出过渡带的一半（过渡带以段界为中心）。
      final solidLeft = band.left + band.leadTransition / 2;
      final solidRight = band.right - band.trailTransition / 2;
      if (solidRight > solidLeft) {
        canvas.drawRect(
          Rect.fromLTRB(solidLeft, top, solidRight, bottom),
          Paint()..color = bandColor(band),
        );
      }
      // 段界过渡：与左邻共界时，在界两侧各半宽的区间画线性渐变；矩形钳
      // 在绘图区内（相邻段同被钳到同一端点时渐变不越进轴区）。
      if (i > 0 && band.leadTransition > 0) {
        final previous = bands[i - 1];
        final rect = Rect.fromLTRB(
          (band.left - band.leadTransition / 2).clamp(
            _plotPad,
            size.width - _plotPad,
          ),
          top,
          (band.left + band.leadTransition / 2).clamp(
            _plotPad,
            size.width - _plotPad,
          ),
          bottom,
        );
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              colors: [bandColor(previous), bandColor(band)],
            ).createShader(rect),
        );
      }
    }
  }

  @override
  bool shouldRepaint(DistributionPainter oldDelegate) =>
      oldDelegate.offsets != offsets ||
      oldDelegate.bands != bands ||
      oldDelegate.color != color ||
      oldDelegate.upperBound != upperBound ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.selection != selection ||
      !listEquals(oldDelegate.ticks, ticks);
}

String _metricLabel(PracticeDistributionMetric metric) => switch (metric) {
  PracticeDistributionMetric.duration => '练习时长',
  PracticeDistributionMetric.count => '练习次数',
};

String _rangeLabel(PracticeDistributionRange range) => switch (range) {
  PracticeDistributionRange.cumulative => '累计',
  PracticeDistributionRange.last7Days => '近 7 天',
  PracticeDistributionRange.today => '今日',
};
