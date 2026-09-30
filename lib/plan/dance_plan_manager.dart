import '../core/local_day.dart';
import '../persistence/practice_plan.dart';
import 'agenda_list.dart' show stableSorted;

/// 各舞计划管理页纯件：分组、组内次序、标题过滤、
/// 「只看未设计划」筛选与行内文案。零 IO、零 Flutter，时钟不参与——本页
/// 不判断逾期 / 临期，逾期仍按 DDL 日期排在「已有计划」组前段。

/// 管理页一行输入（由舞库读面与计划条目合成）。
class DancePlanManagerDance {
  const DancePlanManagerDance({
    required this.videoId,
    required this.title,
    this.masteryPercent,
    this.fullyMastered = false,
    this.ddl,
    this.socialLibrary = true,
    this.reviewReminders = true,
  });

  final String videoId;
  final String title;

  /// 熟练度百分比（均值 × 25）；无分段线时为 null（不显示）。
  final double? masteryPercent;

  /// 完全掌握（行内以勾替百分比）。
  final bool fullyMastered;

  /// 该舞 DDL；null = 未设计划。
  final DanceDdl? ddl;

  /// 随舞曲库开关（缺项 = 开）。
  final bool socialLibrary;

  /// 复习提醒开关（缺项 = 开）。
  final bool reviewReminders;
}

/// 管理页两组：已有计划（有 DDL）与未设计划。
class DancePlanManagerGroups {
  const DancePlanManagerGroups({
    required this.withPlan,
    required this.withoutPlan,
  });

  /// 有 DDL 的舞，按 DDL 日期升序（逾期仍按日期在前）。
  final List<DancePlanManagerDance> withPlan;

  /// 无 DDL 的舞，完全掌握沉底、其余按舞库次序。
  final List<DancePlanManagerDance> withoutPlan;
}

/// 分组 + 过滤（一次算完，页面只渲染）。[query] 按标题做大小写不敏感子串
/// 匹配（去首尾空白后为空 = 不过滤）；[onlyWithoutPlan] 只留无 DDL 的舞。
DancePlanManagerGroups dancePlanManagerGroups({
  required List<DancePlanManagerDance> dances,
  String query = '',
  bool onlyWithoutPlan = false,
}) {
  final needle = query.trim().toLowerCase();
  final filtered = [
    for (final dance in dances)
      if (needle.isEmpty || dance.title.toLowerCase().contains(needle))
        dance,
  ];
  final withPlan = <DancePlanManagerDance>[
    if (!onlyWithoutPlan)
      for (final dance in filtered)
        if (dance.ddl != null) dance,
  ];
  return DancePlanManagerGroups(
    withPlan: stableSorted(
      withPlan,
      (dance) => localDay(dance.ddl!.date).millisecondsSinceEpoch,
    ),
    withoutPlan: stableSorted([
      for (final dance in filtered)
        if (dance.ddl == null) dance,
    ], (dance) => dance.fullyMastered ? 1 : 0),
  );
}

/// 行内 DDL 摘要：日期与场合；未设 DDL 时标「未设 DDL」。
String dancePlanDdlSummary(DanceDdl? ddl) {
  if (ddl == null) return '未设 DDL';
  final day = planDayKey(ddl.date);
  return ddl.occasion.isEmpty ? day : '$day · ${ddl.occasion}';
}

/// 落档结论文案（唯一出处）：按时 / 逾期。
String dancePlanSettlementOutcomeLabel(DdlSettlementOutcome outcome) =>
    switch (outcome) {
      DdlSettlementOutcome.onTime => '按时',
      DdlSettlementOutcome.overdue => '逾期',
    };

/// 行内落档只读文案；未落档不显示（null）。
String? dancePlanSettlementLabel(DdlSettlement? settlement) =>
    settlement == null
    ? null
    : '落档：${dancePlanSettlementOutcomeLabel(settlement.outcome)}';

/// 行内两个开关的状态提示：只列关掉的那侧；都开 = 无提示。
List<String> dancePlanSwitchHints({
  required bool socialLibrary,
  required bool reviewReminders,
}) => [
  if (!socialLibrary) '曲库关',
  if (!reviewReminders) '提醒关',
];
