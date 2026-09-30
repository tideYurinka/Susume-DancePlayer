import 'package:flutter/material.dart';

import 'plan_wheel.dart';

/// 计划日期 / 时间滚轮选择件：三处事件编辑页与
/// DanceDdlEditorPage 共用同一份滚轮控件，档位口径全在 `plan_wheel.dart`。

/// 一列滚轮：可选档位、当前档位与选中回调。
class PlanWheelColumn {
  const PlanWheelColumn({
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    this.columnKey,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Key? columnKey;
}

/// 多列滚轮并排（列等宽），中央一条选中高亮带。
class PlanWheelPicker extends StatelessWidget {
  const PlanWheelPicker({super.key, required this.columns, this.labels});

  final List<PlanWheelColumn> columns;

  /// 各列下方的单位标签（可选，长度与 [columns] 对齐）。
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 高亮带与各列滚轮同处一个 5 档高的滚轮区：档位与带都在该区居中，标签
    // 另占一行在其下方，不参与滚轮区高度（否则档位会高于带的中轴）。
    final wheel = SizedBox(
      height: kPlanWheelItemExtent * 5,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const Key('plan_wheel_selection_band'),
                  height: kPlanWheelItemExtent,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              children: [
                for (final column in columns)
                  Expanded(child: _WheelColumnView(column: column)),
              ],
            ),
          ),
        ],
      ),
    );
    if (labels == null) return wheel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        wheel,
        Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              Expanded(
                child: Text(
                  i < labels!.length ? labels![i] : '',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 单列：`ListWheelScrollView` + 固定档高，滑选即回调；外部改档位时滚到该档。
class _WheelColumnView extends StatefulWidget {
  const _WheelColumnView({required this.column});

  final PlanWheelColumn column;

  @override
  State<_WheelColumnView> createState() => _WheelColumnViewState();
}

class _WheelColumnViewState extends State<_WheelColumnView> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.column.selectedIndex);

  /// 外部改档位触发的同步 jump 不再回调，避免 build 期 setState。
  bool _jumping = false;

  @override
  void didUpdateWidget(covariant _WheelColumnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.column.selectedIndex;
    if (target != oldWidget.column.selectedIndex &&
        _controller.hasClients &&
        _controller.selectedItem != target) {
      _jumping = true;
      _controller.jumpToItem(target);
      _jumping = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.column.options;
    return ListWheelScrollView.useDelegate(
      key: widget.column.columnKey,
      controller: _controller,
      itemExtent: kPlanWheelItemExtent,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) {
        if (_jumping) return;
        if (index >= 0 && index < options.length) {
          widget.column.onSelected(index);
        }
      },
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: options.length,
        builder: (context, index) => Center(child: Text(options[index])),
      ),
    );
  }
}

/// 年 / 月 / 日三列骨架：年列档位与档位号由调用方给出（提交日期年列多一档
/// 「不填」），[displayYear] 是日列天数所依据的年份（提交日期停「不填」时取
/// 默认日年份）。[toDay] 把三列档位还原为值（日期滚轮必填、提交日期可空）。
List<PlanWheelColumn> _dateWheelColumns({
  required String columnPrefix,
  required List<String> yearLabels,
  required int yearIndex,
  required int monthIndex,
  required int dayIndex,
  required int displayYear,
  required DateTime? Function(int yearIndex, int monthIndex, int dayIndex)
  toDay,
  required ValueChanged<DateTime?> onChanged,
}) {
  return [
    PlanWheelColumn(
      columnKey: Key('${columnPrefix}_year'),
      options: yearLabels,
      selectedIndex: yearIndex,
      onSelected: (index) => onChanged(toDay(index, monthIndex, dayIndex)),
    ),
    PlanWheelColumn(
      columnKey: Key('${columnPrefix}_month'),
      options: planWheelMonthLabels(),
      selectedIndex: monthIndex,
      onSelected: (index) => onChanged(toDay(yearIndex, index, dayIndex)),
    ),
    PlanWheelColumn(
      columnKey: Key('${columnPrefix}_day'),
      options: planWheelDayLabels(displayYear, monthIndex + 1),
      selectedIndex: dayIndex,
      onSelected: (index) => onChanged(toDay(yearIndex, monthIndex, index)),
    ),
  ];
}

/// 日期滚轮字段：年 / 月 / 日三列（年列今天往前 1 年 … 往后 3 年）。
class PlanDateWheelField extends StatelessWidget {
  const PlanDateWheelField({
    super.key,
    required this.value,
    required this.today,
    required this.onChanged,
    required this.columnPrefix,
  });

  final DateTime value;
  final DateTime today;
  final ValueChanged<DateTime> onChanged;

  /// 列键前缀：列键为 `<columnPrefix>_year` / `_month` / `_day`。
  final String columnPrefix;

  @override
  Widget build(BuildContext context) {
    final wheel = planDateWheelFromDay(value, today: today);
    return PlanWheelPicker(
      labels: const ['年', '月', '日'],
      columns: _dateWheelColumns(
        columnPrefix: columnPrefix,
        yearLabels: planWheelYearLabels(today),
        yearIndex: wheel.yearIndex,
        monthIndex: wheel.monthIndex,
        dayIndex: wheel.dayIndex,
        displayYear: planWheelYears(today)[wheel.yearIndex],
        toDay: (yearIndex, monthIndex, dayIndex) => planDateWheelToDay(
          yearIndex: yearIndex,
          monthIndex: monthIndex,
          dayIndex: dayIndex,
          today: today,
        ),
        onChanged: (day) {
          if (day != null) onChanged(day);
        },
      ),
    );
  }
}

/// 开始时间滚轮字段：时 / 分两列，时列首档「不设」（24 小时制、5 分钟一步）。
class PlanTimeWheelField extends StatelessWidget {
  const PlanTimeWheelField({
    super.key,
    required this.minutes,
    required this.onChanged,
    required this.columnPrefix,
  });

  /// 当日分钟数；null = 无开始时间（时列「不设」）。
  final int? minutes;
  final ValueChanged<int?> onChanged;

  /// 列键前缀：列键为 `<columnPrefix>_hour` / `_minute`。
  final String columnPrefix;

  @override
  Widget build(BuildContext context) {
    final wheel = planTimeWheelFromMinutes(minutes);
    return PlanWheelPicker(
      labels: const ['时', '分'],
      columns: [
        PlanWheelColumn(
          columnKey: Key('${columnPrefix}_hour'),
          options: planWheelHourLabels(),
          selectedIndex: wheel.hourIndex,
          onSelected: (index) => onChanged(
            planTimeWheelToMinutes(
              hourIndex: index,
              minuteIndex: wheel.minuteIndex,
            ),
          ),
        ),
        PlanWheelColumn(
          columnKey: Key('${columnPrefix}_minute'),
          options: planWheelMinuteLabels(),
          selectedIndex: wheel.minuteIndex,
          onSelected: (index) => onChanged(
            planTimeWheelToMinutes(
              hourIndex: wheel.hourIndex,
              minuteIndex: index,
            ),
          ),
        ),
      ],
    );
  }
}

/// 提前 N 天滚轮字段：单列，首档「不提醒」+ 0–30。
class PlanLeadWheelField extends StatelessWidget {
  const PlanLeadWheelField({
    super.key,
    required this.days,
    required this.onChanged,
    required this.columnKey,
  });

  /// 提前天数；null = 不提醒。
  final int? days;
  final ValueChanged<int?> onChanged;
  final Key columnKey;

  @override
  Widget build(BuildContext context) {
    return PlanWheelPicker(
      columns: [
        PlanWheelColumn(
          columnKey: columnKey,
          options: planWheelLeadLabels(),
          selectedIndex: planLeadWheelFromValue(days),
          onSelected: (index) => onChanged(planLeadWheelToValue(index)),
        ),
      ],
    );
  }
}

/// 提交日期滚轮字段：年列首档「不填」+ 年列各档，再月 / 日两列。
class PlanSubmittedDateWheelField extends StatelessWidget {
  const PlanSubmittedDateWheelField({
    super.key,
    required this.value,
    required this.fallback,
    required this.today,
    required this.onChanged,
    required this.columnPrefix,
  });

  /// 提交日期；null = 不填。
  final DateTime? value;

  /// 未填时月 / 日列的默认日（取事件日）。
  final DateTime fallback;
  final DateTime today;
  final ValueChanged<DateTime?> onChanged;

  /// 列键前缀：列键为 `<columnPrefix>_year` / `_month` / `_day`。
  final String columnPrefix;

  @override
  Widget build(BuildContext context) {
    final wheel = planSubmittedWheelFromDay(
      value,
      fallback: fallback,
      today: today,
    );
    final years = planWheelYears(today);
    return PlanWheelPicker(
      labels: const ['年', '月', '日'],
      columns: _dateWheelColumns(
        columnPrefix: columnPrefix,
        yearLabels: ['不填', ...planWheelYearLabels(today)],
        yearIndex: wheel.yearIndex,
        monthIndex: wheel.monthIndex,
        dayIndex: wheel.dayIndex,
        displayYear:
            years[(wheel.yearIndex - 1).clamp(0, kPlanWheelYearCount - 1)],
        toDay: (yearIndex, monthIndex, dayIndex) => planSubmittedWheelToDay(
          yearIndex: yearIndex,
          monthIndex: monthIndex,
          dayIndex: dayIndex,
          today: today,
        ),
        onChanged: onChanged,
      ),
    );
  }
}
