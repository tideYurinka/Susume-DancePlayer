import '../annotation/learning_segment_attributes.dart';
import '../core/local_day.dart';
import '../persistence/practice_plan.dart';
import 'plan_mark_kind.dart';
import '../persistence/team_check_gate.dart';

/// 应用内提醒规则表：零 IO 纯件、时钟经 [now] 注入。
/// 阈值表（掌握 30 / 较熟 14 / 能跟上 7 / 学习中 3 / 未练 3 天）、冷却与
/// 同日一次、随舞临近与团检临期条件、DDL 剩余 × 档位加权次序、「有目标」
/// 判定都在本文件定义一次；计划 Tab 红点与日程列表都从同一处取值。
/// 持久化载体是计划文档条目上的 [DanceReminderState]（每舞一条，缺项 = 从
/// 未提醒过）。

/// 遗忘复习阈值：按舞的当前档位给「未练多少天触发」。
/// 档位取该舞学习段的最低档（最弱的段决定要不要复习）；无段 / 全未练按
/// 未练档。
int reviewReminderThresholdDays(LearningMastery? level) => switch (level) {
  LearningMastery.mastered => 30,
  LearningMastery.familiar => 14,
  LearningMastery.keepingUp => 7,
  LearningMastery.learning => 3,
  LearningMastery.unlearned || null => 3,
};

/// 舞的当前档位：全部学习段档位的最低档；无段按 null（未练）。
LearningMastery? danceReminderLevel(Set<LearningMastery> segmentMasteries) {
  LearningMastery? lowest;
  for (final mastery in segmentMasteries) {
    if (lowest == null || mastery.index < lowest.index) lowest = mastery;
  }
  return lowest;
}

/// 舞的活跃目标类型：DDL 优先，其次按事件清单次序取首个未到日事件
/// 的类型（团内检查 / 随舞事件）；无目标 = null。判定范围与次序与「有目标」
/// 同一份事实——[danceHasGoal] 由它派生，日程列表「待复习」行首图标据此取色。
PlanMarkKind? danceGoalMarkKind({
  required DanceDdl? ddl,
  required List<PlanEvent> events,
  required String videoId,
  required DateTime now,
}) {
  if (ddl != null &&
      ddl.settlement == null &&
      planRemainingDays(dueDay: ddl.date, now: now) >= 0) {
    return PlanMarkKind.ddl;
  }
  for (final event in events) {
    if (event.danceIds.contains(videoId) &&
        planRemainingDays(dueDay: event.date, now: now) >= 0) {
      final kind = eventMarkKind(event.type);
      if (kind != null) return kind;
    }
  }
  return null;
}

/// 「有目标」（`lib/stats/CONTEXT.md` 词条）：存在未过且未落档的 DDL，
/// 或关联了未到日的团内检查 / 随舞事件。已逾期、已落档、已过日的不算。
bool danceHasGoal({
  required DanceDdl? ddl,
  required List<PlanEvent> events,
  required String videoId,
  required DateTime now,
}) =>
    danceGoalMarkKind(ddl: ddl, events: events, videoId: videoId, now: now) !=
    null;

/// 超过档位阈值未练：从未练视为已超阈值（「未练 3 天未练触发」的退化
/// 口径——没有练习锚点时无从起算，按待复习处理，触发后进冷却）。
bool unpracticedBeyondThreshold({
  required DateTime? lastPracticeDay,
  required LearningMastery? level,
  required DateTime now,
}) {
  if (lastPracticeDay == null) return true;
  final days = localDay(now).difference(localDay(lastPracticeDay)).inDays;
  return days >= reviewReminderThresholdDays(level);
}

/// 冷却与同日一次：上次提醒是今天 → 不再提醒；否则
/// 处于冷却——直到该舞再被练习（最近练习日比触发依据的练习日前移，含从
/// 未练变为练过）或档位变化才重新计时。
bool reviewReminderDue({
  required DanceReminderState? state,
  required DateTime? lastPracticeDay,
  required LearningMastery? level,
  required DateTime now,
}) {
  final today = localDay(now);
  if (state != null && state.lastRemindedOn == today) return false;
  final practiceDay = lastPracticeDay == null
      ? null
      : localDay(lastPracticeDay);
  final reArmed =
      state == null ||
      state.level != level ||
      state.sincePracticeOn != practiceDay;
  if (!reArmed) return false;
  return unpracticedBeyondThreshold(
    lastPracticeDay: lastPracticeDay,
    level: level,
    now: now,
  );
}

/// 触发后落下的提醒状态：记下当日本地日、触发依据的练习日与档位，供
/// 冷却与重新计时判定（[reviewReminderDue]）。
DanceReminderState danceReminderStateAfterFire({
  required DateTime? lastPracticeDay,
  required LearningMastery? level,
  required DateTime now,
}) => DanceReminderState(
  lastRemindedOn: localDay(now),
  sincePracticeOn: lastPracticeDay == null ? null : localDay(lastPracticeDay),
  level: level,
);

/// 随舞临近提醒：事件 ≤3 天未到日，且关联舞超过其
/// 档位阈值未练。
bool socialNearReminderDue({
  required PlanEvent event,
  required DateTime? lastPracticeDay,
  required LearningMastery? level,
  required DateTime now,
}) {
  if (!planIsNearDeadline(planRemainingDays(dueDay: event.date, now: now))) {
    return false;
  }
  return unpracticedBeyondThreshold(
    lastPracticeDay: lastPracticeDay,
    level: level,
    now: now,
  );
}

/// 团检临期提醒：事件 ≤3 天未到日，且目标舞未达标，
/// 或录视频提交类未提交（提交与否不依赖达标门）。
bool teamCheckNearReminderDue({
  required PlanEvent event,
  required DanceGateStatus gateStatus,
  required DateTime now,
}) {
  if (!planIsNearDeadline(planRemainingDays(dueDay: event.date, now: now))) {
    return false;
  }
  if (event.checkMode == kTeamCheckModeVideoSubmission &&
      event.submittedOn == null) {
    return true;
  }
  return gateStatus == DanceGateStatus.unmet;
}

/// 团检是否已达成（日程列表「即将到期」的排除口径）：
/// 录视频提交类已提交，或事件级达标。`notJudged`（无可判定数据）不算达成。
bool teamCheckAchieved({
  required PlanEvent event,
  required DanceGateStatus Function(String videoId) gateStatusOf,
}) {
  if (event.checkMode == kTeamCheckModeVideoSubmission &&
      event.submittedOn != null) {
    return true;
  }
  return eventGateStatus({
        for (final videoId in event.danceIds) videoId: gateStatusOf(videoId),
      }) ==
      TeamCheckEventStatus.met;
}

/// DDL 提醒加权：越接近期限且档位越低权重越小、排得
/// 越前（提醒越频）。档位乘子取档序 + 1（未练 1 → 掌握 5）；无段按未练。
int ddlReminderWeight({
  required int remainingDays,
  required LearningMastery? level,
}) =>
    remainingDays *
    switch (level) {
      LearningMastery.mastered => 5,
      LearningMastery.familiar => 4,
      LearningMastery.keepingUp => 3,
      LearningMastery.learning => 2,
      LearningMastery.unlearned || null => 1,
    };

/// 提醒条目类别：遗忘复习、随舞临近、团检临期。
enum ReminderKind { review, socialNear, teamCheckNear }

/// 一条待提醒项：舞 + 类别 + 事件 id（事件类）+ 排序键（DDL 加权次序，
/// 越小越前；日程列表三组的组内次序从同一处取值）。
class ReminderItem {
  const ReminderItem({
    required this.videoId,
    required this.kind,
    required this.sortKey,
    this.eventId,
  });

  final String videoId;
  final ReminderKind kind;

  /// 产生提醒的事件 id（随舞临近 / 团检临期）。
  final String? eventId;

  /// 排序键：DDL 加权（无活跃 DDL 的舞给 int 上限哨兵，排在 DDL 舞之后，
  /// 组内按 videoId 稳定次序）。
  final int sortKey;

  @override
  bool operator ==(Object other) =>
      other is ReminderItem &&
      other.videoId == videoId &&
      other.kind == kind &&
      other.sortKey == sortKey &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(videoId, kind, sortKey, eventId);
}

/// 单舞评估输入（调用方从舞库读面 + 计划文档合成）。
class ReminderDanceInput {
  const ReminderDanceInput({
    required this.videoId,
    required this.level,
    required this.lastPracticeDay,
    required this.reviewReminders,
    required this.hasGoal,
    this.state,
    this.ddlRemainingDays,
  });

  final String videoId;

  /// 当前档位（最低段档；无段 = null）。
  final LearningMastery? level;

  /// 最近练习的本地日；null = 从未练。
  final DateTime? lastPracticeDay;

  /// 该舞的复习提醒开关（默认开；关 = 不参与遗忘复习与随舞临近提醒）。
  final bool reviewReminders;

  final bool hasGoal;

  /// 上次触发落下的提醒状态；null = 从未提醒。
  final DanceReminderState? state;

  /// 活跃 DDL 的剩余自然日（无活跃 DDL = null）。
  final int? ddlRemainingDays;
}

/// 一次评估的结果：待提醒项 + 各触发舞应落下的新状态（状态有变化才含）。
class ReminderEvaluation {
  const ReminderEvaluation({required this.items, required this.nextStates});

  final List<ReminderItem> items;
  final Map<String, DanceReminderState> nextStates;
}

/// 全量评估（评估时机 = 进入 App / 回到前台 / 进入计划 Tab，调用方负责）：
/// 只有「有目标」的舞参与；逾期项不进（逾期 DDL / 已过日事件本来就不算
/// 目标）。复习提醒开关只管遗忘复习与随舞临近提醒；团检临期
/// 不受它管。冷却与同日一次只挂在这两类「未练程度」提醒上——只有它们
/// 触发才落提醒状态；团检临期独立触发、不消费也不压制状态。排序 = DDL
/// 加权升序，无活跃 DDL 的靠后、按 videoId 稳定。
ReminderEvaluation evaluateReminders({
  required List<ReminderDanceInput> dances,
  required List<PlanEvent> events,
  required DanceGateStatus Function(PlanEvent event, String videoId)
  gateStatusOf,
  required DateTime now,
}) {
  final items = <ReminderItem>[];
  final nextStates = <String, DanceReminderState>{};
  for (final dance in dances) {
    if (!dance.hasGoal) continue;
    final weight = dance.ddlRemainingDays == null
        ? null
        : ddlReminderWeight(
            remainingDays: dance.ddlRemainingDays!,
            level: dance.level,
          );
    final sortKey = weight ?? 0x7fffffff;
    var stateFired = false;
    if (dance.reviewReminders) {
      if (reviewReminderDue(
        state: dance.state,
        lastPracticeDay: dance.lastPracticeDay,
        level: dance.level,
        now: now,
      )) {
        items.add(
          ReminderItem(
            videoId: dance.videoId,
            kind: ReminderKind.review,
            sortKey: sortKey,
          ),
        );
        stateFired = true;
      }
      for (final event in events) {
        if (event.type != kPlanEventTypeSocial ||
            !event.danceIds.contains(dance.videoId)) {
          continue;
        }
        if (socialNearReminderDue(
          event: event,
          lastPracticeDay: dance.lastPracticeDay,
          level: dance.level,
          now: now,
        )) {
          items.add(
            ReminderItem(
              videoId: dance.videoId,
              kind: ReminderKind.socialNear,
              sortKey: sortKey,
              eventId: event.id,
            ),
          );
          stateFired = true;
        }
      }
    }
    for (final event in events) {
      if (event.type != kPlanEventTypeTeamCheck ||
          !event.danceIds.contains(dance.videoId)) {
        continue;
      }
      if (teamCheckNearReminderDue(
        event: event,
        gateStatus: gateStatusOf(event, dance.videoId),
        now: now,
      )) {
        items.add(
          ReminderItem(
            videoId: dance.videoId,
            kind: ReminderKind.teamCheckNear,
            sortKey: sortKey,
            eventId: event.id,
          ),
        );
      }
    }
    if (stateFired) {
      nextStates[dance.videoId] = danceReminderStateAfterFire(
        lastPracticeDay: dance.lastPracticeDay,
        level: dance.level,
        now: now,
      );
    }
  }
  items.sort((a, b) {
    final byKey = a.sortKey.compareTo(b.sortKey);
    if (byKey != 0) return byKey;
    final byDance = a.videoId.compareTo(b.videoId);
    if (byDance != 0) return byDance;
    return a.kind.index.compareTo(b.kind.index);
  });
  return ReminderEvaluation(items: items, nextStates: nextStates);
}
