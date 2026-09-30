// 计划日期纯件：存储串与剩余天数 / 临期口径。
// 本地日归一与日键取 `lib/core/local_day.dart`——计划文档编解码
// （`practice_plan.dart`）与舞库纯值层（`dance_library.dart` 的紧急度与
// 角标）共用同一处口径。

import '../core/local_day.dart';

/// 临期上界（剩余自然日 ≤ 3 天，26）。
const int kPlanNearDeadlineDays = 3;

/// 本地日 ↔ 存储串（`yyyy-MM-dd`，无时刻无时区，跨重启与跨时区读回同一日）。
String planDayKey(DateTime day) => localDayKey(day);

DateTime? tryParsePlanDay(Object? raw) {
  if (raw is! String) return null;
  final parsed = DateTime.tryParse(raw);
  return parsed == null ? null : localDay(parsed);
}

/// 目标本地日 − 今日的自然日差：今天到期为 0、昨天为负。
int planRemainingDays({required DateTime dueDay, required DateTime now}) =>
    localDay(dueDay).difference(localDay(now)).inDays;

/// 剩余 [remainingDays] 天是否临期（0–3 天）。
bool planIsNearDeadline(int remainingDays) =>
    remainingDays >= 0 && remainingDays <= kPlanNearDeadlineDays;
