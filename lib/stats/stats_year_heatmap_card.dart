/// 年热力图卡：滚动近 53 周的日子网格、分档色深与格气泡。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/hit_layer.dart';
import '../core/hit_target.dart' show hitTargetStart, kHitTargetMinSize;
import '../core/local_day.dart';
import '../core/text_extent.dart';
import 'heatmap_selection.dart';
import 'practice_stats_daily.dart';
import 'practice_stats_format.dart';
import 'practice_stats_heatmap.dart';

/// 年热力图卡：滚动近 53 周，列 = 周、行 = 周一→周日；
/// 上方中文月份标签随网格滚动，左侧周一/周三/周五三行星期标签；未来日不
/// 渲染矩形但保留占位；色深按窗口内非零日动态分档；标题单行「过去一年已
/// 练习 …」（合计跟随单位），底部「少 ▢▢▢▢▢ 多」图例。
/// 打开时滚到最近一周，今天所在格直接可见。
/// 点格出单行气泡（卡片内 Stack + Positioned，算术偏移 + 钳制）；长按进入
/// 滑动选择模式（一次震动反馈），滑到哪格选中哪格、气泡与明细实时跟随，
/// 抬手保留，点卡外或对已选格再长按退出；模式内横向滚动不生效；
/// 进模式只经原生震动通道震一次，
/// 卡片渲染模式内外一致。
class YearHeatmapCard extends StatefulWidget {
  const YearHeatmapCard({
    super.key,
    required this.cardKey,
    required this.weeks,
    required this.metric,
    required this.selectedDay,
    required this.selecting,
    required this.onDayTap,
    required this.onBlankTap,
    required this.onSelectionModeChanged,
  });

  /// 页面持有的卡级 key：滑动选择模式下用于判定「点在热力图以外」。
  final Key cardKey;

  final List<HeatmapWeek> weeks;
  final StatsMetric metric;

  final DateTime? selectedDay;
  final bool selecting;
  final ValueChanged<DateTime> onDayTap;

  /// 未渲染的未来格位置算空白：单击它取消选择。
  final VoidCallback onBlankTap;
  final ValueChanged<bool> onSelectionModeChanged;

  @override
  State<YearHeatmapCard> createState() => YearHeatmapCardState();
}

class YearHeatmapCardState extends State<YearHeatmapCard> {
  /// 格边长与格间距：53 列宽于卡片，横向滚动查看（纯件同一几何）。
  static const double _cellSize = heatmapCellSize;
  static const double _cellGap = heatmapCellGap;

  /// 一列（含格间距）与月份标签行的高度。
  static const double _pitch = heatmapCellPitch;
  static const double _monthLabelHeight = 16;

  /// 左侧星期标签列宽与到网格的间距（布局与气泡偏移共用同一来源）。
  static const double _weekdayLabelWidth = 24;
  static const double _weekdayLabelGap = 4;

  /// 网格区内（气泡所在 Stack）的前置宽。
  static const double _gridLeadingInset = _weekdayLabelWidth + _weekdayLabelGap;

  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    // 布局完成后滚到最右（最近一周）：默认读面是今天，不是最早的一周。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
    // 气泡随横向滚动偏移重排。
    _controller.addListener(_onScrollChanged);
  }

  void _onScrollChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 手势本地坐标 → 格子；越出网格边缘时钳在首列/末列、首行/末行。
  HeatmapCell _cellAt(Offset local) {
    final index = heatmapCellIndexAt(
      local,
      columnCount: widget.weeks.length,
      rowCount: 7,
    );
    return widget.weeks[index.column].cells[index.row];
  }

  /// 图区点按：未来格不渲染矩形，其占位算空白，单击取消选择；
  /// 其余格照常选日。滑动选日走 [_onLongPressMoveUpdate]，不经过这里，
  /// 拖过未来格不会被当成单击空白。
  void _onGridTapUp(Offset local) {
    final cell = _cellAt(local);
    if (cell.isFuture) {
      widget.onBlankTap();
      return;
    }
    _selectCell(cell);
  }

  void _selectCell(HeatmapCell cell) {
    if (cell.isFuture) return;
    widget.onDayTap(cell.day);
  }

  void _onLongPressStart(LongPressStartDetails details) {
    final cell = _cellAt(details.localPosition);
    if (cell.isFuture) return;
    if (widget.selecting) {
      if (cell.day == widget.selectedDay) {
        // 对已选格再长按一次退出。
        widget.onSelectionModeChanged(false);
      } else {
        widget.onDayTap(cell.day);
      }
      return;
    }
    // 进入滑动选择模式：震动由页面经 selectionHapticProvider 发出。
    widget.onSelectionModeChanged(true);
    widget.onDayTap(cell.day);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!widget.selecting) return;
    _selectCell(_cellAt(details.localPosition));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowTotal = heatmapWindowTotal(widget.weeks);
    final totalText = switch (widget.metric) {
      StatsMetric.time => statsDurationText(windowTotal.total),
      StatsMetric.count => '${windowTotal.sessions} 次',
    };
    return KeyedSubtree(
      key: widget.cardKey,
      child: Card(
        key: const Key('heatmap_card'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '过去一年已练习 $totalText',
                key: const Key('heatmap_total'),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _weekdayLabels(theme),
                        const SizedBox(width: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _controller,
                            scrollDirection: Axis.horizontal,
                            // 模式内拖动只用于选日，不触发横向滚动（用户故事 51）。
                            physics: widget.selecting
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _monthLabelRow(theme),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) =>
                                      _onGridTapUp(details.localPosition),
                                  onLongPressStart: _onLongPressStart,
                                  onLongPressMoveUpdate: _onLongPressMoveUpdate,
                                  // 整片网格 = 「大命中区按最近格换算」：点按
                                  // 任何位置都落到最近那格（见 _cellHitLayers）。
                                  child: Stack(
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          for (final week in widget.weeks)
                                            _weekColumn(theme, week),
                                        ],
                                      ),
                                      ..._cellHitLayers(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.selectedDay != null)
                      _bubble(theme, constraints.maxWidth),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _legend(theme),
            ],
          ),
        ),
      ),
    );
  }

  /// 选中格正上方的单行气泡：偏移 = 网格几何 + 当前横向滚动偏移（纯件
  /// [heatmapBubbleLeftInCard]），左右靠边时钳在卡片内；纵向贴在格顶上方，
  /// 首行之上不越出 Stack（钳回 0）。
  Widget _bubble(ThemeData theme, double gridWidth) {
    final selectedDay = widget.selectedDay!;
    final column = widget.weeks.indexWhere(
      (week) => week.cells.any((cell) => cell.day == selectedDay),
    );
    if (column < 0) return const SizedBox.shrink();
    final row = widget.weeks[column].cells.indexWhere(
      (cell) => cell.day == selectedDay,
    );
    final cell = widget.weeks[column].cells[row];
    final text = heatmapBubbleText(
      widget.metric,
      cell.day,
      total: cell.total,
      sessions: cell.sessions,
    );
    final style = theme.textTheme.bodySmall!;
    final textSize = measureTextExtent(
      text,
      style,
      direction: Directionality.of(context),
    );
    const horizontalPadding = 10.0;
    const verticalPadding = 4.0;
    final bubbleWidth = textSize.width + 2 * horizontalPadding;
    final bubbleHeight = textSize.height + 2 * verticalPadding;
    final left = heatmapBubbleLeftInCard(
      cellCenterX: (column + 0.5) * _pitch,
      scrollOffset: _controller.hasClients ? _controller.offset : 0,
      leadingInset: _gridLeadingInset,
      bubbleWidth: bubbleWidth,
      cardWidth: gridWidth,
    );
    return Positioned(
      key: const Key('heatmap_bubble'),
      left: left,
      top: math.max(0, _monthLabelHeight + row * _pitch - bubbleHeight - 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: style),
      ),
    );
  }

  /// 左侧星期标签：顶部让出月份标签行的高度，使三行钉在网格的第 1/3/5 行
  /// （周一/周三/周五）上；不随横向滚动。
  Widget _weekdayLabels(ThemeData theme) {
    Widget row(String? label) => SizedBox(
      height: _pitch,
      width: _weekdayLabelWidth,
      child: label == null
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: _monthLabelHeight),
      child: Column(
        children: [
          row('周一'),
          row(null),
          row('周三'),
          row(null),
          row('周五'),
          row(null),
          row(null),
        ],
      ),
    );
  }

  /// 月份标签行：贴在每月第一列顶部（跨列共存时按第一次出现处标注），
  /// 与周列同一个横向滚动容器，随网格一起滚动。
  Widget _monthLabelRow(ThemeData theme) {
    return Row(
      key: const Key('heatmap_month_labels'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final week in widget.weeks)
          SizedBox(
            width: _pitch,
            height: _monthLabelHeight,
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              // 无 1 号的周不出标签，但占位与列宽一致。
              child: Text(
                _monthLabel(week) ?? '',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String? _monthLabel(HeatmapWeek week) {
    for (final cell in week.cells) {
      if (cell.day.day == 1) return '${cell.day.month}月';
    }
    return null;
  }

  /// 每格 48×48 命中层（「命中盒：唯一声明与外扩」）：日格视觉只有 12dp，
  /// 靠透明外扩撑到下限——网格上按每格中心几何
  /// 叠一枚透明 48×48 可点层（首/末列与首/末行钳进网格内），报出日期与练习量、
  /// 并可经无障碍点按选日。相邻层密集重叠，指针点按按**最近格**换算到目标日
  /// （不是谁压在最上面谁赢）；视觉格与网格几何逐位不变。
  List<Widget> _cellHitLayers() {
    final gridWidth = widget.weeks.length * _pitch;
    final gridHeight = 7 * _pitch;
    return [
      for (var column = 0; column < widget.weeks.length; column++)
        for (var row = 0; row < 7; row++)
          _cellHitLayer(column, row, gridWidth, gridHeight),
    ];
  }

  /// 一格一枚 48×48 命中层：定位与「按最近格换算」共用同一份钳界结果。
  Widget _cellHitLayer(
    int column,
    int row,
    double gridWidth,
    double gridHeight,
  ) {
    final cell = widget.weeks[column].cells[row];
    final left = hitTargetStart((column + 0.5) * _pitch, gridWidth);
    final top = hitTargetStart((row + 0.5) * _pitch, gridHeight);
    return Positioned(
      left: left,
      top: top,
      width: kHitTargetMinSize,
      height: kHitTargetMinSize,
      child: HitTargetLayer(
        key: Key('heatmap_hit_${localDayKey(cell.day)}'),
        button: !cell.isFuture,
        label: heatmapCellDateLabel(cell.day),
        value: cell.isFuture
            ? '未来日期'
            : heatmapCellValueLabel(
                widget.metric,
                total: cell.total,
                sessions: cell.sessions,
              ),
        onActivate: cell.isFuture ? null : () => widget.onDayTap(cell.day),
        // 未来格无异动，指针落到下层整片网格 -> 空白单击（清选择）。
        onTapUpLocal: cell.isFuture
            ? null
            : (local) => _onGridTapUp(Offset(left + local.dx, top + local.dy)),
      ),
    );
  }

  Widget _weekColumn(ThemeData theme, HeatmapWeek week) {
    return Column(
      key: Key('heatmap_week_${localDayKey(week.start)}'),
      mainAxisSize: MainAxisSize.min,
      children: [for (final cell in week.cells) _cell(theme, cell)],
    );
  }

  Widget _cell(ThemeData theme, HeatmapCell cell) {
    return GestureDetector(
      // 未来日不是「那一天」：无需下钻，也不冒充没有练习的空日。
      onTap: cell.isFuture ? null : () => widget.onDayTap(cell.day),
      // 未来日不渲染矩形，但占位保持星期行对齐。
      child: Container(
        key: Key('heatmap_cell_${localDayKey(cell.day)}'),
        width: _cellSize,
        height: _cellSize,
        margin: const EdgeInsets.all(_cellGap / 2),
        decoration: cell.isFuture
            ? null
            : BoxDecoration(
                color: heatmapColor(theme, cell.level),
                borderRadius: BorderRadius.circular(2),
              ),
      ),
    );
  }

  /// 图例：「少 ▢▢▢▢▢ 多」色块行。
  Widget _legend(ThemeData theme) {
    return Row(
      key: const Key('heatmap_legend'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('少'),
        const SizedBox(width: 4),
        for (var level = 0; level <= 4; level++) ...[
          Container(
            key: Key('heatmap_legend_swatch_$level'),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: heatmapColor(theme, level),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
        ],
        const Text('多'),
      ],
    );
  }
}

/// 色深档 → 颜色：0 为空格底色，1–4 用主题主色递增不透明度。
Color heatmapColor(ThemeData theme, int level) {
  if (level <= 0) return theme.colorScheme.surfaceContainerHighest;
  final alpha = switch (level) {
    1 => 0.25,
    2 => 0.45,
    3 => 0.7,
    _ => 1.0,
  };
  return theme.colorScheme.primary.withValues(alpha: alpha);
}
