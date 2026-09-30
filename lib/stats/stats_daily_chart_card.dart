/// 每日柱状图卡：窗口内按天聚合的柱与网格线绘制。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/local_day.dart';
import '../core/text_extent.dart';
import '../persistence/song_signature.dart';
import 'practice_stats_axis.dart';
import 'heatmap_selection.dart';
import 'practice_stats_daily.dart';
import 'practice_stats_format.dart';

/// 每日柱状图卡：y 轴整齐刻度与横向网格线、底部 4 个
/// `M/d` 日期标签；柱高按窗口内最大值取的整齐上界归一（柱顶与刻度线
/// 同尺），近 7 天窗口在柱顶标数值；标题写明单位与窗口合计；选中柱高亮
/// 并叠加竖向虚线，空日高 0 但整列仍是触控目标。点按或横向拖动都能选日
/// （拖动经过的柱依次选中，图不滚动、无需长按），选中日出两行气泡：首行
/// 「日期 + 合计」+ 最多前 3 支舞的分解行，水平用热力图气泡的偏移与钳制
/// 纯件夹在图区内。窗口与排序键来自筛选行，卡内无控件。
class DailyBarChartCard extends StatelessWidget {
  const DailyBarChartCard({
    super.key,
    required this.bars,
    required this.metric,
    required this.window,
    required this.selectedDay,
    required this.detail,
    required this.bubbleFingerY,
    required this.onDayTap,
  });

  final List<DailyPracticeBar> bars;
  final StatsMetric metric;
  final PracticeStatsWindow window;
  final DateTime? selectedDay;

  /// 选中日的按舞明细（气泡分解行来源）；未选日为 null。
  final DailyPracticeDetail? detail;

  /// 气泡的手指 y（绘图区本地坐标）；null 时气泡贴绘图区顶部。
  final double? bubbleFingerY;
  final void Function(DateTime day, double fingerY) onDayTap;

  /// 图表总高：顶部留白给柱顶数值，其余为柱与网格线的绘图区。
  static const double _chartHeight = 120;

  /// 柱顶数值的留白高。
  static const double _valueHeadroom = 14;

  /// 绘图区（柱、网格线、y 轴刻度共同的高）。
  double get _plotHeight => _chartHeight - _valueHeadroom;

  /// 有练习日的最小可见柱高：不设下限时极短的一天归一后不足 1px，会被读成
  /// 断档；空日仍为 0。
  static const double _minBarHeight = 2;

  /// y 轴刻度列的最小宽（这是**排版容量**不是
  /// 视觉尺寸——实际宽按系统字号放大，见 [_axisWidthFor]）。
  static const double _axisWidth = 28;

  /// y 轴刻度列实际宽：按系统字号实测最宽刻度（量测与渲染吃同一个
  /// [TextScaler]），字号放大时刻度列随之变宽、
  /// 不与图表重叠；`textScaler < 1` 不收缩（沿用定宽不随缩小档收的口径）。
  double _axisWidthFor(
    List<int> ticks,
    TextStyle style,
    TextScaler textScaler,
  ) {
    var width = _axisWidth;
    for (final tick in ticks) {
      width = math.max(
        width,
        measureTextExtent('$tick', style, scaler: textScaler).width + 4,
      );
    }
    return width;
  }

  /// 柱顶数值贴柱顶时的行内退让高（超出绘图区的满高柱退到柱内贴顶）。
  static const double _valueInset = 13;

  /// x 轴日期标签的行高倍数。
  static const double _xLabelLineHeight = 1.4;

  /// x 轴标签行高：**排版容量**随系统字号放大（未缩放字号为下限，
  /// `textScaler < 1` 不收缩）——字号放大时行高变大，不与图表重叠。
  double _xLabelHeightFor(TextStyle style, TextScaler textScaler) {
    final fontSize = style.fontSize!;
    return math.max(fontSize, textScaler.scale(fontSize)) *
        _xLabelLineHeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axis = barChartAxisForBars(bars, metric);
    final upper = axis.upperInValue(metric);
    final totalDuration = bars.fold<Duration>(
      Duration.zero,
      (sum, bar) => sum + bar.total,
    );
    final totalSessions = bars.fold<int>(0, (sum, bar) => sum + bar.sessions);
    final title = switch (metric) {
      StatsMetric.time => '每日练习时长（分钟） · 合计 ${statsDurationText(totalDuration)}',
      StatsMetric.count => '每日练习次数 · 合计 $totalSessions 次',
    };
    final textScaler = MediaQuery.textScalerOf(context);
    final tickStyle = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Card(
      key: const Key('daily_chart_card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              key: const Key('daily_chart_title'),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            SizedBox(
              key: const Key('daily_chart'),
              height: _chartHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    width: _axisWidthFor(axis.ticks, tickStyle, textScaler),
                    height: _plotHeight,
                    // 大字号下刻度列总高超出一行绘图区时整列等比缩小（与标注
                    // 工具行同一口径：刻度缩小仍可读，溢出则绘图区崩）；
                    // 名义档内零缩放、取值不变。
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // 刻度自上而下：上界在顶、0 在底（与网格线同尺）。
                          for (final tick in axis.ticks.reversed)
                            Text(
                              '$tick',
                              key: Key('daily_axis_tick_$tick'),
                              style: tickStyle,
                              maxLines: 1,
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: _plotHeight,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final plotWidth = constraints.maxWidth;
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  key: const Key('daily_gridlines'),
                                  painter: GridlinePainter(
                                    ticks: axis.ticks,
                                    upperBound: axis.upperBound,
                                    color: theme.dividerColor,
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    for (final bar in bars)
                                      _barColumn(theme, bar, upper),
                                  ],
                                ),
                              ),
                              // 点按与横向拖动都能选日：拖动经过的柱依次
                              // 选中；柱列等宽，坐标
                              // 按比例换算后钳在首末柱。透明层盖在柱列之
                              // 上，点按与拖动统一由这一层换算选日。
                              Positioned.fill(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTapUp: (details) => _selectBarAt(
                                    details.localPosition.dx,
                                    details.localPosition.dy,
                                    plotWidth,
                                  ),
                                  onHorizontalDragStart: (details) =>
                                      _selectBarAt(
                                        details.localPosition.dx,
                                        details.localPosition.dy,
                                        plotWidth,
                                      ),
                                  onHorizontalDragUpdate: (details) =>
                                      _selectBarAt(
                                        details.localPosition.dx,
                                        details.localPosition.dy,
                                        plotWidth,
                                      ),
                                ),
                              ),
                              if (selectedDay != null && detail != null)
                                _bubble(theme, plotWidth, _plotHeight, context),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: _xLabelHeightFor(
                theme.textTheme.bodySmall!,
                textScaler,
              ),
              child: Row(children: _xLabels(theme)),
            ),
          ],
        ),
      ),
    );
  }

  /// x 轴 4 个日期标签（首日 / 约 1/3 / 约 2/3 / 末日，`M/d`）：首标签
  /// 左对齐、末标签右对齐，中间两个居中在各自 1/3 附近。
  List<Widget> _xLabels(ThemeData theme) {
    final count = bars.length;
    if (count == 0) return const [];
    int index(int position) => ((count - 1) * position / 3).round();
    final style = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      for (final position in [0, 1, 2, 3])
        Expanded(
          child: Text(
            _mdText(bars[index(position)].day),
            key: Key('daily_x_label_${localDayKey(bars[index(position)].day)}'),
            textAlign: switch (position) {
              0 => TextAlign.left,
              3 => TextAlign.right,
              _ => TextAlign.center,
            },
            style: style,
            maxLines: 1,
          ),
        ),
    ];
  }

  /// 手势坐标 → 所在柱的日期（等宽柱列，钳在首末柱，seam
  /// [barChartIndexAt]）；手指 y 随选中日带出，供气泡纵向跟手。
  void _selectBarAt(double dx, double dy, double plotWidth) {
    if (bars.isEmpty) return;
    onDayTap(bars[barChartIndexAt(dx, plotWidth, bars.length)].day, dy);
  }

  /// 选中柱旁的两行气泡：首行「日期 + 合计」，
  /// 随后最多前 3 支舞的分解行（按当前单位降序，与明细行同口径同文案）；
  /// 二维定位用纯件 [barChartBubblePosition]——纵向中心对齐手指
  /// y 并钳在绘图区内，横向朝远离目标柱的方向避让（气泡矩形与目标柱矩形
  /// 不相交，允许遮挡非目标柱；柱顶数值在目标柱列内，随之不被遮挡）。
  Widget _bubble(
    ThemeData theme,
    double plotWidth,
    double plotHeight,
    BuildContext context,
  ) {
    final day = selectedDay!;
    final index = bars.indexWhere((bar) => bar.day == day);
    if (index < 0) return const SizedBox.shrink();
    final detail = this.detail!;
    final headline = '${day.month}月${day.day}日 合计 ${detail.textFor(metric)}';
    final rows = [
      for (final dance in detail.dancesSortedBy(metric).take(3))
        (
          videoId: dance.videoId,
          text:
              '${signatureDisplayText(dance.signature, dance.videoId)} '
              '${dance.textFor(metric)}',
        ),
    ];
    final style = theme.textTheme.bodySmall!;
    // 量测与渲染同源（规则 2）：量测侧吃与渲染相同的 TextScaler。
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    double textWidth(String text) =>
        measureTextExtent(text, style,
            direction: textDirection, scaler: textScaler).width;

    const horizontalPadding = 10.0;
    const verticalPadding = 4.0;
    final bubbleWidth =
        [
          headline,
          for (final row in rows) row.text,
        ].map(textWidth).reduce(math.max) +
        2 * horizontalPadding;
    final bodyText = [headline, for (final row in rows) '\n${row.text}'].join();
    final bodySize = measureTextExtent(
      bodyText,
      style,
      direction: textDirection,
      scaler: textScaler,
      maxWidth: bubbleWidth - 2 * horizontalPadding,
    );
    final bubbleHeight = bodySize.height + 2 * verticalPadding;
    final position = barChartBubblePosition(
      fingerY: bubbleFingerY ?? 0,
      bubbleWidth: bubbleWidth,
      bubbleHeight: bubbleHeight,
      plotWidth: plotWidth,
      plotHeight: plotHeight,
      targetIndex: index,
      barCount: bars.length,
    );
    return Positioned(
      key: const Key('bar_chart_bubble'),
      left: position.left,
      top: position.top,
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
            Text(headline, style: style),
            for (final row in rows)
              Text(
                row.text,
                key: Key('bar_chart_bubble_row_${row.videoId}'),
                style: style,
              ),
          ],
        ),
      ),
    );
  }

  Widget _barColumn(ThemeData theme, DailyPracticeBar bar, int upper) {
    final dayKey = localDayKey(bar.day);
    final quantity = bar.valueFor(metric);
    final fraction = upper <= 0 || quantity <= 0 ? 0.0 : quantity / upper;
    final height = math.max(_minBarHeight, _plotHeight * fraction);
    final selected = bar.day == selectedDay;
    final showValue = window == PracticeStatsWindow.last7 && quantity > 0;
    final valueText = switch (metric) {
      // 按时间标分钟数（四舍五入），按次数标整数；单位在卡片标题里。
      StatsMetric.time =>
        '${(Duration(microseconds: quantity).inSeconds / 60).round()}',
      StatsMetric.count => '$quantity',
    };
    return Expanded(
      child: Stack(
        children: [
          Positioned.fill(
            child: InkWell(
              key: Key('daily_bar_$dayKey'),
              // 点按坐标里的手指 y 带给气泡做纵向跟手。
              onTapUp: (details) =>
                  onDayTap(bar.day, details.localPosition.dy),
              // 整列都是触控目标：柱体作为命中区内容（含空日）。
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  key: Key('daily_bar_fill_$dayKey'),
                  width: double.infinity,
                  height: quantity <= 0 ? 0.0 : height,
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  key: Key('daily_bar_dashes_$dayKey'),
                  painter: DashedLinePainter(color: theme.colorScheme.primary),
                ),
              ),
            ),
          if (showValue)
            Positioned(
              left: 0,
              right: 0,
              // 满高柱的柱顶数值退到柱内贴顶显示，避免被绘图区裁掉。
              bottom: math.min(height + 1, _plotHeight - _valueInset),
              child: Text(
                valueText,
                key: Key('daily_bar_value_$dayKey'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _mdText(DateTime day) => '${day.month}/${day.day}';

/// 横向网格线：长横虚线（每条刻度一条，含 0 基线），节拍 6dp 实 / 4dp 空；
/// 与选中柱的竖向短虚线（3/3）节拍刻意不同——横向是读数参照、竖向是选中标记。
class GridlinePainter extends CustomPainter {
  const GridlinePainter({
    required this.ticks,
    required this.upperBound,
    required this.color,
  });

  final List<int> ticks;

  /// 刻度所在的整齐上界（与 [ticks] 同单位，分钟或场次）。
  final int upperBound;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (upperBound <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 6.0;
    const gap = 4.0;
    for (final tick in ticks) {
      final y = size.height * (1 - tick / upperBound);
      for (var x = 0.0; x < size.width; x += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + dash, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(GridlinePainter oldDelegate) =>
      oldDelegate.upperBound != upperBound ||
      oldDelegate.color != color ||
      !listEquals(oldDelegate.ticks, ticks);
}

/// 选中柱的竖向虚线：贯穿绘图区的居中竖线。
class DashedLinePainter extends CustomPainter {
  const DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 3.0;
    const gap = 3.0;
    final x = size.width / 2;
    for (var y = 0.0; y < size.height; y += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dash, size.height)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
