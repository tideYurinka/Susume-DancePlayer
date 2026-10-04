import 'package:dance_learning_app/plan/plan_wheel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 9, 16);

  group('日期滚轮档位', () {
    test('年列范围今天往前 1 年 … 往后 3 年', () {
      expect(planWheelYears(today), [2025, 2026, 2027, 2028, 2029]);
      expect(planWheelYearLabels(today), [
        '2025',
        '2026',
        '2027',
        '2028',
        '2029',
      ]);
    });

    test('值 ↔ 三列档位往返', () {
      final wheel = planDateWheelFromDay(DateTime(2026, 10, 1), today: today);
      expect(wheel.yearIndex, 1);
      expect(wheel.monthIndex, 9);
      expect(wheel.dayIndex, 0);
      expect(
        planDateWheelToDay(
          yearIndex: wheel.yearIndex,
          monthIndex: wheel.monthIndex,
          dayIndex: wheel.dayIndex,
          today: today,
        ),
        DateTime(2026, 10, 1),
      );
    });

    test('换到天数更少的月份：日档位夹到月末', () {
      expect(
        planDateWheelToDay(
          yearIndex: 1,
          monthIndex: 1,
          dayIndex: 30,
          today: today,
        ),
        DateTime(2026, 2, 28),
      );
      final fromDay = planDateWheelFromDay(DateTime(2026, 1, 31), today: today);
      expect(fromDay.dayIndex, 30);
    });

    test('闰年 2 月 29 可表示', () {
      expect(
        planDateWheelToDay(
          yearIndex: 3,
          monthIndex: 1,
          dayIndex: 28,
          today: today,
        ),
        DateTime(2028, 2, 29),
      );
    });

    test('既有值年超出范围：夹到最近边界且日不越月', () {
      expect(
        planDateWheelFromDay(DateTime(2035, 3, 5), today: today).yearIndex,
        4,
      );
      expect(
        planDateWheelFromDay(DateTime(2000, 3, 5), today: today).yearIndex,
        0,
      );
      expect(
        planDateWheelFromDay(DateTime(2035, 2, 28), today: today).dayIndex,
        27,
      );
      expect(planWheelDaysInMonth(2026, 2), 28);
      expect(planWheelDaysInMonth(2028, 2), 29);
    });

    test('既有值夹到年列范围：所见即所存', () {
      expect(
        planDateWheelClampDay(DateTime(2035, 3, 5), today: today),
        DateTime(2029, 3, 5),
      );
      expect(
        planDateWheelClampDay(DateTime(2000, 3, 5), today: today),
        DateTime(2025, 3, 5),
      );
      expect(
        planDateWheelClampDay(DateTime(2026, 10, 1), today: today),
        DateTime(2026, 10, 1),
      );
      expect(kPlanWheelYearCount, 5);
    });
  });

  group('时间滚轮档位', () {
    test('时列首档不设；分列每 5 分钟', () {
      expect(planWheelHourLabels().first, '不设');
      expect(planWheelHourLabels().length, 25);
      expect(planWheelMinuteLabels().first, '00');
      expect(planWheelMinuteLabels().last, '55');
      expect(planWheelMinuteLabels().length, 12);
    });

    test('空值停在「不设」且忽略分列', () {
      final wheel = planTimeWheelFromMinutes(null);
      expect(wheel.hourIndex, 0);
      expect(
        planTimeWheelToMinutes(hourIndex: wheel.hourIndex, minuteIndex: 7),
        isNull,
      );
    });

    test('值 ↔ 两列档位往返，非 5 倍分钟夹到最近档', () {
      final wheel = planTimeWheelFromMinutes(19 * 60);
      expect(wheel.hourIndex, 20);
      expect(wheel.minuteIndex, 0);
      expect(
        planTimeWheelToMinutes(
          hourIndex: wheel.hourIndex,
          minuteIndex: wheel.minuteIndex,
        ),
        19 * 60,
      );
      expect(planTimeWheelFromMinutes(9 * 60 + 3).minuteIndex, 1);
      expect(planTimeWheelFromMinutes(9 * 60 + 2).minuteIndex, 0);
      expect(planHhMmText(19 * 60 + 5), '19:05');
      expect(planHhMmText(0), '00:00');
    });
  });

  group('提前 N 天滚轮档位', () {
    test('首档不提醒；0 与不提醒是不同档', () {
      expect(planWheelLeadLabels().first, '不提醒');
      expect(planWheelLeadLabels()[1], '0');
      expect(planWheelLeadLabels().last, '30');
      expect(planLeadWheelFromValue(null), 0);
      expect(planLeadWheelFromValue(0), 1);
      expect(planLeadWheelToValue(0), isNull);
      expect(planLeadWheelToValue(1), 0);
      expect(planLeadWheelToValue(31), 30);
      expect(planLeadWheelFromValue(40), 31);
    });
  });

  group('提交日期滚轮档位', () {
    test('年列首档不填，空值回 null', () {
      final wheel = planSubmittedWheelFromDay(
        null,
        fallback: DateTime(2026, 10, 1),
        today: today,
      );
      expect(wheel.yearIndex, 0);
      expect(wheel.monthIndex, 9);
      expect(
        planSubmittedWheelToDay(
          yearIndex: wheel.yearIndex,
          monthIndex: wheel.monthIndex,
          dayIndex: wheel.dayIndex,
          today: today,
        ),
        isNull,
      );
    });

    test('既有提交日期先滚到该值', () {
      final wheel = planSubmittedWheelFromDay(
        DateTime(2026, 1, 2),
        fallback: DateTime(2026, 10, 1),
        today: today,
      );
      // 年列 0 = 不填，1 = 2025，2 = 2026。
      expect(wheel.yearIndex, 2);
      expect(
        planSubmittedWheelToDay(
          yearIndex: wheel.yearIndex,
          monthIndex: wheel.monthIndex,
          dayIndex: wheel.dayIndex,
          today: today,
        ),
        DateTime(2026, 1, 2),
      );
    });
  });
}
