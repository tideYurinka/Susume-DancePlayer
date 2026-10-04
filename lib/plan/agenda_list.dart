import '../annotation/learning_segment_attributes.dart';
import '../core/local_day.dart';
import '../persistence/practice_plan.dart';
import 'plan_mark_kind.dart';
import 'practice_reminders.dart';

/// 日程列表三组的分组与组内排序：零 IO 纯件、时钟经
/// [now] 注入。三组 = 即将到期 / 待复习 / 随舞临近；空组由调用方按空列表
/// 不渲染。排序全部稳定：键并列时保持输入次序。

/// 即将到期条目来源：舞 DDL 或团内检查。
enum AgendaDueSource { ddl, teamCheck }

/// 「即将到期」一条：DDL 行指 [videoId]，团检行指 [event]。
class AgendaDueItem {
  const AgendaDueItem({
    required this.source,
    this.videoId,
    this.event,
    required this.targetLabel,
    required this.remainingDays,
  });

  final AgendaDueSource source;

  /// 舞 DDL 行的舞 id；团检行为 null。
  final String? videoId;

  /// 团检行的事件；DDL 行为 null。
  final PlanEvent? event;

  /// 目标类型显示文案：DDL 的场合标签（空场合兜底「DDL」）或「团检」。
  final String targetLabel;

  /// 剩余自然日（今天到期为 0）。
  final int remainingDays;

  /// 行定位键（DDL = videoId，团检 = 事件 id）。
  String get key => source == AgendaDueSource.ddl ? videoId! : event!.id;
}

/// 「即将到期」：未过且未达成的 DDL 与团内检查，按剩余
/// 自然日升序。已落档 / 已逾期的 DDL 不进；[teamCheckAchieved] 返回 true 的
/// 团检（事件级达标，或录视频提交已交）视为已达成不进。
List<AgendaDueItem> agendaDueItems({
  required List<DancePlanEntry> entries,
  required List<PlanEvent> events,
  required bool Function(PlanEvent event) teamCheckAchieved,
  required DateTime now,
}) {
  final items = <AgendaDueItem>[];
  for (final entry in entries) {
    final ddl = entry.ddl;
    if (ddl == null || ddl.settlement != null) continue;
    final remaining = planRemainingDays(dueDay: ddl.date, now: now);
    if (remaining < 0) continue;
    items.add(
      AgendaDueItem(
        source: AgendaDueSource.ddl,
        videoId: entry.videoId,
        targetLabel: ddl.occasion.isEmpty ? 'DDL' : ddl.occasion,
        remainingDays: remaining,
      ),
    );
  }
  for (final event in events) {
    if (event.type != kPlanEventTypeTeamCheck) continue;
    final remaining = planRemainingDays(dueDay: event.date, now: now);
    if (remaining < 0 || teamCheckAchieved(event)) continue;
    items.add(
      AgendaDueItem(
        source: AgendaDueSource.teamCheck,
        event: event,
        targetLabel: '团检',
        remainingDays: remaining,
      ),
    );
  }
  // 剩余自然日升序；并列保持输入次序（entries 在前、events 在后）。
  return stableSorted(items, (item) => item.remainingDays);
}

/// 「待复习」单舞输入（调用方从舞库读面与计划文档合成）。
class AgendaReviewDance {
  const AgendaReviewDance({
    required this.videoId,
    required this.level,
    required this.lastPracticeDay,
    required this.goalKind,
  });

  final String videoId;

  /// 当前档位（最低段档；无段 = null）。
  final LearningMastery? level;

  /// 最近练习的本地日；null = 从未练。
  final DateTime? lastPracticeDay;

  /// 该舞活跃目标的标记类型（[danceGoalMarkKind]）；null = 无目标。行首
  /// 图标据此取配色。
  final PlanMarkKind? goalKind;
}

/// 「待复习」一条：超出档位阈值未练的有目标舞。
class AgendaReviewItem {
  const AgendaReviewItem({
    required this.videoId,
    required this.level,
    required this.exceedDays,
    required this.goalKind,
  });

  final String videoId;

  final LearningMastery? level;

  /// 超出阈值的天数；从未练无从起算为 null（显示「未练」、排末尾）。
  final int? exceedDays;

  /// 该舞活跃目标的标记类型（行首图标取色）。
  final PlanMarkKind goalKind;
}

/// 「待复习」：超出档位阈值的有目标舞，按超出天数从多
/// 到少；从未练视为超阈值、排末尾（与提醒口径一致）。阈值与超阈判定取
/// 提醒规则表同一处（[unpracticedBeyondThreshold]）。
List<AgendaReviewItem> agendaReviewItems({
  required List<AgendaReviewDance> dances,
  required DateTime now,
}) {
  final items = <AgendaReviewItem>[];
  for (final dance in dances) {
    final goalKind = dance.goalKind;
    if (goalKind == null) continue;
    if (!unpracticedBeyondThreshold(
      lastPracticeDay: dance.lastPracticeDay,
      level: dance.level,
      now: now,
    )) {
      continue;
    }
    final exceed = dance.lastPracticeDay == null
        ? null
        : localDay(now).difference(localDay(dance.lastPracticeDay!)).inDays -
              reviewReminderThresholdDays(dance.level);
    items.add(
      AgendaReviewItem(
        videoId: dance.videoId,
        level: dance.level,
        exceedDays: exceed,
        goalKind: goalKind,
      ),
    );
  }
  // 超出天数从多到少；从未练（null）排末尾；并列保持输入次序。
  return stableSorted(items, (item) => -(item.exceedDays ?? -1));
}

/// 「随舞临近」：未到日的随舞事件，按日期升序。
List<PlanEvent> agendaSocialItems({
  required List<PlanEvent> events,
  required DateTime now,
}) => stableSorted([
  for (final event in events)
    if (event.type == kPlanEventTypeSocial &&
        planRemainingDays(dueDay: event.date, now: now) >= 0)
      event,
], (event) => localDay(event.date).millisecondsSinceEpoch);

/// 键升序、键并列时保持原次序的稳定排序（Dart 的 List.sort 不保证稳定）。
List<T> stableSorted<T>(List<T> items, int Function(T item) key) {
  final indexed = [for (var i = 0; i < items.length; i++) (items[i], i)];
  indexed.sort((a, b) {
    final byKey = key(a.$1).compareTo(key(b.$1));
    return byKey != 0 ? byKey : a.$2 - b.$2;
  });
  return [for (final (item, _) in indexed) item];
}
