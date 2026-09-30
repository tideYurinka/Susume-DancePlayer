import '../annotation/learning_segment_attributes.dart';

/// 团内检查达标门判定纯件：零 IO、零 Flutter。
/// 输入只读当前熟练度档位集合，不写任何持久化状态。

/// 达标门：某支关联舞在一场团内检查里的最低熟练度
/// 档位要求；默认较熟，可按事件调为掌握 / 较熟 / 不设。
enum TeamCheckGate {
  mastered,
  familiar,
  unset;

  /// 该门的最低档位要求；「不设」为 null（不参与达标判定）。
  LearningMastery? get requirement => switch (this) {
    TeamCheckGate.mastered => LearningMastery.mastered,
    TeamCheckGate.familiar => LearningMastery.familiar,
    TeamCheckGate.unset => null,
  };
}

/// 存储门名 → 达标门；缺失或未知按「不设」兜底（旧事件缺字段）。
TeamCheckGate teamCheckGateFromName(String? name) {
  for (final gate in TeamCheckGate.values) {
    if (gate.name == name) return gate;
  }
  return TeamCheckGate.unset;
}

/// 达标门显示名（选择器文案）。
String teamCheckGateLabel(TeamCheckGate gate) => switch (gate) {
  TeamCheckGate.mastered => '掌握',
  TeamCheckGate.familiar => '较熟',
  TeamCheckGate.unset => '不设',
};

/// 新建团检的选择器默认门（默认较熟）。
const TeamCheckGate kTeamCheckGateDefault = TeamCheckGate.familiar;

/// 舞级达标判定结论：达标 / 未达标 / 不参与判定。
enum DanceGateStatus { met, unmet, notJudged }

/// 舞级达标判定：该舞全部学习段档位都达到
/// 达标门即达标；门为「不设」或没有任何学习段的舞不参与判定。
DanceGateStatus danceGateStatus({
  required TeamCheckGate gate,
  required Set<LearningMastery> segmentMasteries,
}) {
  final requirement = gate.requirement;
  if (requirement == null || segmentMasteries.isEmpty) {
    return DanceGateStatus.notJudged;
  }
  return segmentMasteries.every(
    (mastery) => mastery.index >= requirement.index,
  )
      ? DanceGateStatus.met
      : DanceGateStatus.unmet;
}

/// 事件级达标汇总结论：达标 / 未达标 / 不判达标。
enum TeamCheckEventStatus { met, unmet, notJudged }

/// 事件级达标汇总：全部参与判定的舞都达标即事件达标，
/// 有一段未达标即未达标；没有任何舞参与判定（全是不设 / 零段，或无关联
/// 舞）时不判达标——不拿空数据冒充达标。
TeamCheckEventStatus eventGateStatus(
  Map<String, DanceGateStatus> statuses,
) {
  final judged = statuses.values
      .where((status) => status != DanceGateStatus.notJudged)
      .toList();
  if (judged.isEmpty) return TeamCheckEventStatus.notJudged;
  return judged.any((status) => status == DanceGateStatus.unmet)
      ? TeamCheckEventStatus.unmet
      : TeamCheckEventStatus.met;
}
