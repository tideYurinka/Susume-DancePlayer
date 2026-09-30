// 计划日期 / 时间滚轮纯件：档位与值 / 空档互转、
// 年列范围边界与新建默认日期。零 Flutter 零 IO——三个编辑页与「各舞计划」
// 编辑框共用同一处口径。

/// 滚轮每档高度（逻辑像素）：滚动 [indexDelta] 档即位移
/// `indexDelta × kPlanWheelItemExtent`。
const double kPlanWheelItemExtent = 40;

/// 日期滚轮年列范围：今天往前 1 年 … 往后 3 年。
const int kPlanWheelYearsBack = 1;
const int kPlanWheelYearsForward = 3;

/// 时间滚轮分列步长（分钟）。
const int kPlanWheelMinuteStep = 5;

/// 提前 N 天滚轮上界；其首档是「不提醒」。
const int kPlanWheelMaxLeadDays = 30;

/// 年列档数（今天往前 1 年 … 往后 3 年）。
const int kPlanWheelYearCount =
    kPlanWheelYearsBack + kPlanWheelYearsForward + 1;

/// 年列档位值（升序）。
List<int> planWheelYears(DateTime today) => [
  for (var offset = -kPlanWheelYearsBack; offset <= kPlanWheelYearsForward; offset++)
    today.year + offset,
];

/// 年列标签（四位年）。
List<String> planWheelYearLabels(DateTime today) => [
  for (final year in planWheelYears(today)) year.toString().padLeft(4, '0'),
];

int planWheelDaysInMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

List<String> planWheelMonthLabels() => [
  for (var month = 1; month <= 12; month++) month.toString().padLeft(2, '0'),
];

List<String> planWheelDayLabels(int year, int month) => [
  for (var day = 1; day <= planWheelDaysInMonth(year, month); day++)
    day.toString().padLeft(2, '0'),
];

/// 时列：首档「不设」+ 00–23。
List<String> planWheelHourLabels() => [
  '不设',
  for (var hour = 0; hour < 24; hour++) hour.toString().padLeft(2, '0'),
];

/// 分列档数（00–55 每 5 分钟）。
const int kPlanWheelMinuteCount = 60 ~/ kPlanWheelMinuteStep;

List<String> planWheelMinuteLabels() => [
  for (var minute = 0; minute < 60; minute += kPlanWheelMinuteStep)
    minute.toString().padLeft(2, '0'),
];

/// 提前天数单列：首档「不提醒」+ 0–30。
List<String> planWheelLeadLabels() => [
  '不提醒',
  for (var days = 0; days <= kPlanWheelMaxLeadDays; days++) '$days',
];

/// 日期滚轮三列档位：年列 [yearIndex] 对 [planWheelYears] 的偏移、月 0–11、
/// 日 0–(当月天数−1)。提交日期滚轮复用本形状，其年列 0 另表「不填」。
class PlanDateWheel {
  const PlanDateWheel({
    required this.yearIndex,
    required this.monthIndex,
    required this.dayIndex,
  });

  final int yearIndex;
  final int monthIndex;
  final int dayIndex;
}

/// 本地日 → 三列档位。年超出范围时夹到最近边界，日超出该月天数时夹到月末。
PlanDateWheel planDateWheelFromDay(DateTime day, {required DateTime today}) {
  final years = planWheelYears(today);
  final rawYearIndex = years.indexOf(day.year);
  final yearIndex = rawYearIndex >= 0
      ? rawYearIndex
      : day.year < years.first
      ? 0
      : years.length - 1;
  final monthIndex = day.month - 1;
  final maxDay = planWheelDaysInMonth(years[yearIndex], monthIndex + 1);
  return PlanDateWheel(
    yearIndex: yearIndex,
    monthIndex: monthIndex,
    dayIndex: day.day <= maxDay ? day.day - 1 : maxDay - 1,
  );
}

/// 三列档位 → 本地日；超出档位范围的输入夹到边界。
DateTime planDateWheelToDay({
  required int yearIndex,
  required int monthIndex,
  required int dayIndex,
  required DateTime today,
}) {
  final years = planWheelYears(today);
  final year = years[yearIndex.clamp(0, years.length - 1)];
  final month = monthIndex.clamp(0, 11) + 1;
  final maxDay = planWheelDaysInMonth(year, month);
  return DateTime(year, month, dayIndex.clamp(0, maxDay - 1) + 1);
}

/// 本地日夹到年列范围内的最近合法日（月 / 日超界一并夹到边界）。
DateTime planDateWheelClampDay(DateTime day, {required DateTime today}) {
  final wheel = planDateWheelFromDay(day, today: today);
  return planDateWheelToDay(
    yearIndex: wheel.yearIndex,
    monthIndex: wheel.monthIndex,
    dayIndex: wheel.dayIndex,
    today: today,
  );
}

/// 时间滚轮两列档位：时列 0 = 不设、1–24 = 00–23；分列 0–11 = 00–55。
class PlanTimeWheel {
  const PlanTimeWheel({required this.hourIndex, required this.minuteIndex});

  final int hourIndex;
  final int minuteIndex;
}

/// 当日分钟数 → 两列档位：null（无开始时间）停在「不设」；分列夹到最近 5 分钟档。
PlanTimeWheel planTimeWheelFromMinutes(int? minutes) {
  if (minutes == null) return const PlanTimeWheel(hourIndex: 0, minuteIndex: 0);
  final hour = (minutes ~/ 60).clamp(0, 23);
  final minute = (minutes % 60).clamp(0, 59);
  final minuteIndex =
      ((minute + kPlanWheelMinuteStep ~/ 2) ~/ kPlanWheelMinuteStep)
          .clamp(0, kPlanWheelMinuteCount - 1);
  return PlanTimeWheel(hourIndex: hour + 1, minuteIndex: minuteIndex);
}

/// 两列档位 → 当日分钟数；时列停在「不设」即无开始时间，忽略分列。
int? planTimeWheelToMinutes({
  required int hourIndex,
  required int minuteIndex,
}) {
  if (hourIndex <= 0) return null;
  final hour = hourIndex - 1;
  final minute = minuteIndex.clamp(0, kPlanWheelMinuteCount - 1) *
      kPlanWheelMinuteStep;
  return hour * 60 + minute;
}

/// 当日分钟数 → `HH:mm`。
String planHhMmText(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// 提前 N 天档位 → 值（null = 不提醒）。
int? planLeadWheelToValue(int index) => index <= 0 ? null : index - 1;

/// 提前 N 天值 → 档位（null 停「不提醒」；超界夹到 0–30）。
int planLeadWheelFromValue(int? days) =>
    days == null ? 0 : days.clamp(0, kPlanWheelMaxLeadDays) + 1;

/// 提交日期滚轮三列档位：年列 0 = 不填、1–[kPlanWheelYearCount] = 年列各档；
/// 月日同日期滚轮。
PlanDateWheel planSubmittedWheelFromDay(
  DateTime? day, {
  required DateTime fallback,
  required DateTime today,
}) {
  final base = planDateWheelFromDay(day ?? fallback, today: today);
  if (day == null) {
    return PlanDateWheel(
      yearIndex: 0,
      monthIndex: base.monthIndex,
      dayIndex: base.dayIndex,
    );
  }
  return PlanDateWheel(
    yearIndex: base.yearIndex + 1,
    monthIndex: base.monthIndex,
    dayIndex: base.dayIndex,
  );
}

/// 提交日期三列档位 → 值；年列停在「不填」写回 null。
DateTime? planSubmittedWheelToDay({
  required int yearIndex,
  required int monthIndex,
  required int dayIndex,
  required DateTime today,
}) {
  if (yearIndex <= 0) return null;
  return planDateWheelToDay(
    yearIndex: yearIndex - 1,
    monthIndex: monthIndex,
    dayIndex: dayIndex,
    today: today,
  );
}
