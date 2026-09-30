import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/team_check_gate.dart';
import 'package:flutter_test/flutter_test.dart';

Set<LearningMastery> masteries(List<LearningMastery> list) => list.toSet();

void main() {
  group('达标门读取与序列化', () {
    test('门名合法读取：mastered / familiar / unset', () {
      expect(teamCheckGateFromName('mastered'), TeamCheckGate.mastered);
      expect(teamCheckGateFromName('familiar'), TeamCheckGate.familiar);
      expect(teamCheckGateFromName('unset'), TeamCheckGate.unset);
    });

    test('门名缺失或未知按「不设」兜底（旧事件缺字段）', () {
      expect(teamCheckGateFromName(null), TeamCheckGate.unset);
      expect(teamCheckGateFromName(''), TeamCheckGate.unset);
      expect(teamCheckGateFromName('bogus'), TeamCheckGate.unset);
    });

    test('门的要求档位：不设为 null，其余映射对应档位', () {
      expect(TeamCheckGate.unset.requirement, isNull);
      expect(TeamCheckGate.familiar.requirement, LearningMastery.familiar);
      expect(TeamCheckGate.mastered.requirement, LearningMastery.mastered);
    });
  });

  group('舞级达标判定', () {
    test('全部学习段达到较熟门 → 达标', () {
      expect(
        danceGateStatus(
          gate: TeamCheckGate.familiar,
          segmentMasteries: masteries([
            LearningMastery.familiar,
            LearningMastery.mastered,
          ]),
        ),
        DanceGateStatus.met,
      );
    });

    test('一段未达较熟门 → 未达标（门槛之上不计入豁免）', () {
      expect(
        danceGateStatus(
          gate: TeamCheckGate.familiar,
          segmentMasteries: masteries([
            LearningMastery.mastered,
            LearningMastery.keepingUp,
          ]),
        ),
        DanceGateStatus.unmet,
      );
    });

    test('全部段达到掌握门 → 达标；有段只到较熟 → 未达标', () {
      expect(
        danceGateStatus(
          gate: TeamCheckGate.mastered,
          segmentMasteries: masteries([
            LearningMastery.mastered,
            LearningMastery.mastered,
          ]),
        ),
        DanceGateStatus.met,
      );
      expect(
        danceGateStatus(
          gate: TeamCheckGate.mastered,
          segmentMasteries: masteries([LearningMastery.familiar]),
        ),
        DanceGateStatus.unmet,
      );
    });

    test('门为「不设」不参与判定（即使全段掌握也不出达标）', () {
      expect(
        danceGateStatus(
          gate: TeamCheckGate.unset,
          segmentMasteries: masteries([LearningMastery.mastered]),
        ),
        DanceGateStatus.notJudged,
      );
    });

    test('零段舞不参与判定并在事件里标注', () {
      expect(
        danceGateStatus(
          gate: TeamCheckGate.familiar,
          segmentMasteries: masteries([]),
        ),
        DanceGateStatus.notJudged,
      );
    });

    test('门名经序列化往返不变', () {
      for (final gate in TeamCheckGate.values) {
        expect(teamCheckGateFromName(gate.name), gate);
      }
    });
  });

  group('事件级达标汇总', () {
    DanceGateStatus s(TeamCheckGate gate, List<LearningMastery> list) =>
        danceGateStatus(
          gate: gate,
          segmentMasteries: masteries(list),
        );

    test('全部参与判定的舞都达标 → 事件达标', () {
      expect(
        eventGateStatus({
          'v1': s(TeamCheckGate.familiar, [LearningMastery.familiar]),
          'v2': s(TeamCheckGate.mastered, [LearningMastery.mastered]),
        }),
        TeamCheckEventStatus.met,
      );
    });

    test('一段未达标 → 事件未达标', () {
      expect(
        eventGateStatus({
          'v1': s(TeamCheckGate.familiar, [LearningMastery.familiar]),
          'v2': s(TeamCheckGate.familiar, [LearningMastery.keepingUp]),
        }),
        TeamCheckEventStatus.unmet,
      );
    });

    test('不设与零段舞不参与：其余全达标仍事件达标', () {
      expect(
        eventGateStatus({
          'v1': s(TeamCheckGate.familiar, [LearningMastery.mastered]),
          'v2': s(TeamCheckGate.unset, [LearningMastery.mastered]),
          'v3': s(TeamCheckGate.familiar, []),
        }),
        TeamCheckEventStatus.met,
      );
    });

    test('全部舞都不参与判定 → 事件不判达标（不拿空数据冒充达标）', () {
      expect(
        eventGateStatus({
          'v1': s(TeamCheckGate.unset, [LearningMastery.mastered]),
          'v2': s(TeamCheckGate.familiar, []),
        }),
        TeamCheckEventStatus.notJudged,
      );
    });

    test('无关联舞 → 事件不判达标', () {
      expect(
        eventGateStatus(const {}),
        TeamCheckEventStatus.notJudged,
      );
    });
  });
}
