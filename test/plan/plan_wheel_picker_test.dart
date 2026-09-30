import 'package:dance_learning_app/plan/plan_wheel.dart';
import 'package:dance_learning_app/plan/plan_wheel_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/plan_wheel_driver.dart';

/// 滚轮选择件本身：滑选只产出合法值、空档写回 null。
void main() {
  final today = DateTime(2026, 9, 16);

  testWidgets('日期滚轮：换月换日滑选后值正确、天数随月变', (tester) async {
    var value = DateTime(2026, 10, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlanDateWheelField(
              value: value,
              today: today,
              onChanged: (day) => setState(() => value = day),
              columnPrefix: 'w',
            ),
          ),
        ),
      ),
    );

    await selectPlanDate(
      tester,
      'w',
      target: DateTime(2026, 11, 11),
      today: today,
    );
    expect(value, DateTime(2026, 11, 11));

    // 滑到 2 月：日档位夹到月末。
    await selectPlanDate(
      tester,
      'w',
      target: DateTime(2028, 2, 29),
      today: today,
    );
    expect(value, DateTime(2028, 2, 29));
  });

  testWidgets('选中档位落在高亮带正中：候选数字与带同中轴', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanDateWheelField(
            value: DateTime(2026, 10, 1),
            today: today,
            onChanged: (_) {},
            columnPrefix: 'w',
          ),
        ),
      ),
    );

    final bandCenterY = tester
        .getCenter(find.byKey(const Key('plan_wheel_selection_band')))
        .dy;
    // 年 / 月 / 日三列当前档的数字都应落在高亮带的中轴上。
    for (final (columnKey, label) in [
      ('w_year', '2026'),
      ('w_month', '10'),
      ('w_day', '01'),
    ]) {
      expect(
        tester
            .getCenter(
              find.descendant(
                of: find.byKey(Key(columnKey)),
                matching: find.text(label),
              ),
            )
            .dy,
        closeTo(bandCenterY, 0.5),
        reason: '候选档 $label 应落在高亮带正中',
      );
    }
  });

  testWidgets('时间滚轮：滑回「不设」即 null，分列 5 分钟一步', (tester) async {
    int? value = 19 * 60;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlanTimeWheelField(
              minutes: value,
              onChanged: (minutes) => setState(() => value = minutes),
              columnPrefix: 't',
            ),
          ),
        ),
      ),
    );

    await selectPlanTime(tester, 't', target: 7 * 60 + 25);
    expect(value, 7 * 60 + 25);

    await selectPlanTime(tester, 't', target: null);
    expect(value, isNull);

    // 时列停在不设：忽略分列。
    await tester.drag(
      find.byKey(const Key('t_minute')),
      const Offset(0, -kPlanWheelItemExtent * 3),
    );
    await tester.pumpAndSettle();
    expect(value, isNull);
  });

  testWidgets('提前 N 天滚轮：0 与「不提醒」是两个不同档', (tester) async {
    int? value = 3;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlanLeadWheelField(
              days: value,
              onChanged: (days) => setState(() => value = days),
              columnKey: const Key('lead'),
            ),
          ),
        ),
      ),
    );

    await selectPlanLead(tester, const Key('lead'), target: 0);
    expect(value, 0);

    await selectPlanLead(tester, const Key('lead'), target: null);
    expect(value, isNull);
  });

  testWidgets('提交日期滚轮：年列「不填」写回 null，选年即回日期', (tester) async {
    DateTime? value;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlanSubmittedDateWheelField(
              value: value,
              fallback: DateTime(2026, 10, 1),
              today: today,
              onChanged: (day) => setState(() => value = day),
              columnPrefix: 's',
            ),
          ),
        ),
      ),
    );

    // 停在「不填」：滑分列不改值。
    await tester.drag(
      find.byKey(const Key('s_month')),
      const Offset(0, -kPlanWheelItemExtent),
    );
    await tester.pumpAndSettle();
    expect(value, isNull);

    // 年列下滑两档到 2026（首档之后是 2025）：写回具体日期（沿用默认月 / 日）。
    await tester.drag(
      find.byKey(const Key('s_year')),
      const Offset(0, -kPlanWheelItemExtent * 2),
    );
    await tester.pumpAndSettle();
    expect(value, DateTime(2026, 10, 1));

    // 滑回「不填」：写回 null。
    await tester.drag(
      find.byKey(const Key('s_year')),
      const Offset(0, kPlanWheelItemExtent * 2),
    );
    await tester.pumpAndSettle();
    expect(value, isNull);
  });
}
