/// 计划页几何与归集纯件：月视图网格与翻月
/// 手势判定、时间轴月列与当前时间位置、有计划日子的归集。全部零 Flutter、
/// 零 IO，时钟由调用方注入（`now`）；日期一律本地日（`localDay` 归一口径）。
library;

import '../core/local_day.dart';
import '../persistence/practice_plan.dart';
import 'plan_mark_kind.dart';

/// 月视图网格（周一为首列）。
class PlanMonthGrid {
  const PlanMonthGrid({required this.month, required this.weeks});

  /// 所示月份（零点）。
  final DateTime month;

  /// 整周行（每行 7 天，首尾以跨月日补位，行内升序）。
  final List<List<DateTime>> weeks;

  /// 该日是否落在所示月份内（跨月补位日为 false）。
  bool isInMonth(DateTime day) =>
      day.year == month.year && day.month == month.month;
}

/// 以 [month] 所在月建网格：周一为首列，跨月补位成整周。
PlanMonthGrid buildPlanMonthGrid(DateTime month) {
  final first = planMonthOf(month);
  // DateTime.weekday：周一 = 1 … 周日 = 7，与「周一为首列」的列偏移一致。
  final leading = first.weekday - 1;
  final gridStart = DateTime(first.year, first.month, 1 - leading);
  final nextMonth = planShiftMonth(first, 1);
  final dayCount = nextMonth.difference(first).inDays;
  // 尾部以跨月日补位成整周（7 的倍数）。
  final cellCount = dayCount + leading;
  final trailing = (7 - cellCount % 7) % 7;
  final cells = [
    for (var i = 0; i < cellCount + trailing; i++)
      DateTime(gridStart.year, gridStart.month, gridStart.day + i),
  ];
  final weeks = <List<DateTime>>[
    for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
  ];
  return PlanMonthGrid(month: planMonthOf(month), weeks: weeks);
}

/// 所属月（零点）：点跨月补位日即切到它所在的月。
DateTime planMonthOf(DateTime day) => DateTime(day.year, day.month);

/// 月键（时间轴月段键口径）：补零 `yyyyMM`。
String planMonthKey(DateTime month) =>
    '${month.year.toString().padLeft(4, '0')}'
    '${month.month.toString().padLeft(2, '0')}';

/// 按 [delta] 个月平移（翻月目标月）：跨年由 `DateTime` 归一，翻月不设边界。
DateTime planShiftMonth(DateTime month, int delta) =>
    DateTime(month.year, month.month + delta);

/// 翻月方向：左滑（水平位移 / 速度为负）→ 下一月，右滑 → 上一月。
enum PlanMonthSwipe { none, previous, next }

/// 累计水平位移阈值（px）。
const double kPlanMonthSwipeDistance = 40;

/// 水平速度阈值（px/s）。
const double kPlanMonthSwipeVelocity = 300;

/// 一次手势的累计水平位移 [totalDx] 与水平速度 [velocityX] → 翻月方向：
/// 位移 ≥ [kPlanMonthSwipeDistance] 或速度 ≥ [kPlanMonthSwipeVelocity] 才切；
/// 垂直分量占优（|dy| > |dx|）不切；两者都够时取位移方向。
PlanMonthSwipe planMonthSwipe({
  required double totalDx,
  required double totalDy,
  required double velocityX,
}) {
  if (totalDy.abs() > totalDx.abs()) return PlanMonthSwipe.none;
  final byDistance = totalDx.abs() >= kPlanMonthSwipeDistance;
  final byVelocity = velocityX.abs() >= kPlanMonthSwipeVelocity;
  if (!byDistance && !byVelocity) return PlanMonthSwipe.none;
  final horizontal = byDistance ? totalDx : velocityX;
  return horizontal < 0 ? PlanMonthSwipe.next : PlanMonthSwipe.previous;
}

/// 翻月手势的累计判定：一次手势只切一月——[update] 越过位移阈值即给出方向
/// 并把本手势标记为已结算，其后本手势的内外更新都不再触发。
class PlanMonthSwipeTracker {
  double _dx = 0;
  double _dy = 0;
  bool _settled = false;

  /// 手势起手：清零累计、重新允许结算。
  void start() {
    _dx = 0;
    _dy = 0;
    _settled = false;
  }

  /// 累计一次拖动增量，返回本增量是否越过位移阈值（越过后本手势已结算）。
  PlanMonthSwipe update(double dx, double dy) {
    _dx += dx;
    _dy += dy;
    if (_settled) return PlanMonthSwipe.none;
    final swipe = planMonthSwipe(totalDx: _dx, totalDy: _dy, velocityX: 0);
    if (swipe != PlanMonthSwipe.none) _settled = true;
    return swipe;
  }

  /// 手势结束：位移未达阈值时按速度补判；已结算的手势不再触发。
  PlanMonthSwipe finish({required double velocityX}) {
    if (_settled) return PlanMonthSwipe.none;
    _settled = true;
    return planMonthSwipe(totalDx: _dx, totalDy: _dy, velocityX: velocityX);
  }
}

/// 计划标记类型（[PlanMarkKind]）与事件类型映射（[eventMarkKind]）住在
/// `plan_mark_kind.dart`：类型声明只此一处，页面几何、配色与提醒规则共用。

/// 时间轴条的一段（一个月列）。
class PlanTimelineSegment {
  const PlanTimelineSegment({
    required this.month,
    this.markedDaysByKind = const {},
    this.hasLeadingDivider = false,
  });

  /// 该月（零点）。
  final DateTime month;

  /// 列内有计划的日子（几号），按标记类型分列、升序去重。
  final Map<PlanMarkKind, Set<int>> markedDaysByKind;

  /// 列左边界是否画月分隔虚线（首列之前不画）。
  final bool hasLeadingDivider;

  int get daysInMonth => DateTime(month.year, month.month + 1, 0).day;

  /// 该月是否有任何计划日（列下月号淡显与否）。
  bool get hasMarks => markedDaysByKind.values.any((days) => days.isNotEmpty);

  /// 列内某日的横向分数（0 = 月首、1 = 月末），竖线按它落位。
  double markerFraction(int dayNumber) => (dayNumber - 1) / daysInMonth;

  /// 该类型在该列内的计划日号（无则空集）。
  Set<int> markedDaysOf(PlanMarkKind kind) =>
      markedDaysByKind[kind] ?? const {};

  /// 列内有标记的日子 → 该日出现的标记类型（日号升序、类型按声明序），
  /// 页面据此给同日多类并排竖线排位次。
  Map<int, List<PlanMarkKind>> get marksByDay {
    final dayNumbers = {
      for (final days in markedDaysByKind.values) ...days,
    }.toList()..sort();
    return {
      for (final dayNumber in dayNumbers)
        dayNumber: [
          for (final kind in PlanMarkKind.values)
            if (markedDaysOf(kind).contains(dayNumber)) kind,
        ],
    };
  }
}

/// 时间轴上的年份分段：窗口内同一年的连续列合为一段。
class PlanYearSpan {
  const PlanYearSpan({required this.year, required this.columnCount});

  final int year;

  /// 该年在窗口内占的列数（段宽 = 该列数 ÷ 窗口列数）。
  final int columnCount;
}

/// 时间轴条布局：固定当前月起 12 个月列，列内标计划标记与今天。
class PlanTimeline {
  const PlanTimeline({
    required this.segments,
    required this.yearSpans,
    required this.todayDayNumber,
  });

  /// 月列（恒 12 列、升序，首列 = 当前月）。
  final List<PlanTimelineSegment> segments;

  /// 年份分段（升序，首段恒有，跨年处断段），列数合计 = 窗口列数。
  final List<PlanYearSpan> yearSpans;

  /// 今天的日号（恒落在首列 = 当前月内）。
  final int todayDayNumber;

  /// 「今天」竖线在当月列内的横向分数（真实位置，非固定靠左）。
  double get todayFraction => segments.first.markerFraction(todayDayNumber);
}

/// 计划标记按类型归集（本地日、去重）：舞 DDL 日 / 随舞事件日 / 团内检查日
/// 三类分列，日历圆点、时间轴竖线与「有没有任何计划」共用这一份归集。
Map<PlanMarkKind, Set<DateTime>> planMarksByKind(
  Iterable<DancePlanEntry> entries, {
  Iterable<PlanEvent> events = const [],
}) {
  final marks = {
    PlanMarkKind.ddl: <DateTime>{},
    PlanMarkKind.social: <DateTime>{},
    PlanMarkKind.teamCheck: <DateTime>{},
  };
  for (final entry in entries) {
    if (entry.ddl != null) {
      marks[PlanMarkKind.ddl]!.add(localDay(entry.ddl!.date));
    }
  }
  for (final event in events) {
    final kind = eventMarkKind(event.type);
    if (kind != null) marks[kind]!.add(localDay(event.date));
  }
  return marks;
}

/// 固定当前月起 12 个月列建时间轴：早于当前月与超出窗口（当前月 + 12 个月，
/// 不含端点月）的计划日不入列。窗口以当前月为锚，随月份推移重算。年份按同一年的
/// 连续列分段（首段恒有，1 月处断段），段宽由该年列数给出。
PlanTimeline buildPlanTimeline(
  Map<PlanMarkKind, Iterable<DateTime>> marks, {
  required DateTime now,
}) {
  final currentMonth = planMonthOf(now);
  final windowEnd = planShiftMonth(currentMonth, 12);
  final byMonth = <DateTime, Map<PlanMarkKind, Set<int>>>{};
  for (final entry in marks.entries) {
    for (final rawDay in entry.value) {
      final day = localDay(rawDay);
      if (day.isBefore(currentMonth) || !day.isBefore(windowEnd)) continue;
      byMonth
          .putIfAbsent(planMonthOf(day), () => {})
          .putIfAbsent(entry.key, () => {})
          .add(day.day);
    }
  }
  final segments = <PlanTimelineSegment>[];
  final yearSpans = <PlanYearSpan>[];
  for (var offset = 0; offset < 12; offset++) {
    final month = planShiftMonth(currentMonth, offset);
    segments.add(
      PlanTimelineSegment(
        month: month,
        markedDaysByKind: byMonth[month] ?? const {},
        hasLeadingDivider: offset > 0,
      ),
    );
    final last = yearSpans.isEmpty ? null : yearSpans.last;
    if (last != null && last.year == month.year) {
      yearSpans[yearSpans.length - 1] = PlanYearSpan(
        year: last.year,
        columnCount: last.columnCount + 1,
      );
    } else {
      yearSpans.add(PlanYearSpan(year: month.year, columnCount: 1));
    }
  }
  return PlanTimeline(
    segments: segments,
    yearSpans: yearSpans,
    todayDayNumber: localDay(now).day,
  );
}

/// 某日到期 DDL 的一行：舞标识 + 场合标签（下栏行的渲染输入）。
class DdlOnDay {
  const DdlOnDay({required this.videoId, required this.occasion});

  final String videoId;

  /// 场合标签（可空串 = 未设）。
  final String occasion;
}

/// 某日到期 DDL 的舞（videoId 升序，页面下栏行的次序口径）。
List<DdlOnDay> ddlsOnDay(
  Iterable<DancePlanEntry> entries, {
  required DateTime day,
}) {
  final target = localDay(day);
  final rows = [
    for (final entry in entries)
      if (entry.ddl != null && localDay(entry.ddl!.date) == target)
        DdlOnDay(videoId: entry.videoId, occasion: entry.ddl!.occasion),
  ]..sort((a, b) => a.videoId.compareTo(b.videoId));
  return rows;
}

/// 某日的事件（按开始时间升序、无时间排后；同时刻按 id 定序）。
List<PlanEvent> eventsOnDay(
  Iterable<PlanEvent> events, {
  required DateTime day,
}) {
  final target = localDay(day);
  final rows =
      [
        for (final event in events)
          if (localDay(event.date) == target) event,
      ]..sort((a, b) {
        final at = a.startTime;
        final bt = b.startTime;
        if (at == null && bt != null) return 1;
        if (at != null && bt == null) return -1;
        final byTime = (at ?? '').compareTo(bt ?? '');
        if (byTime != 0) return byTime;
        return a.id.compareTo(b.id);
      });
  return rows;
}

/// 新建随舞事件的默认关联清单：随舞曲库开关为「开」的舞（缺项按开），
/// 按曲库次序、去空 id。
List<String> defaultEventDanceIds(
  Iterable<String> danceIds, {
  required Set<String> disabledIds,
}) => [
  for (final id in danceIds)
    if (id.isNotEmpty && !disabledIds.contains(id)) id,
];
