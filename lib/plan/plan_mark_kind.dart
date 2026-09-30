/// 计划标记类型：舞 DDL / 随舞事件 / 团内检查三类
/// 的唯一类型声明，是时间轴竖线、图例、日历圆点、点日下栏与日程列表行首图标
/// 的共同论域。零 IO、零 Flutter：配色映射、页面几何与提醒规则都从这里取类型。
library;

import '../persistence/practice_plan.dart';

/// 计划标记类型。
enum PlanMarkKind {
  /// 舞 DDL。
  ddl,

  /// 随舞事件。
  social,

  /// 团内检查。
  teamCheck,
}

/// 事件类型 → 计划标记类型（未知 / 损坏类型 = null）：日历圆点归集
/// （`planMarksByKind`）与「待复习」目标类型（`danceGoalMarkKind`）共用这一处
/// 映射，新增事件类型只改这里。
PlanMarkKind? eventMarkKind(String eventType) => switch (eventType) {
  kPlanEventTypeTeamCheck => PlanMarkKind.teamCheck,
  kPlanEventTypeSocial => PlanMarkKind.social,
  _ => null,
};
