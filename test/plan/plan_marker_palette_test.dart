import 'package:dance_learning_app/plan/plan_mark_kind.dart';
import 'package:dance_learning_app/plan/plan_marker_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('三类计划标记各取一色、互不相同', () {
    final colors = {
      for (final kind in PlanMarkKind.values) planMarkColor(kind),
    };
    expect(colors, hasLength(PlanMarkKind.values.length));
  });

  test('图例名称三类齐备、互不相同', () {
    final labels = {
      for (final kind in PlanMarkKind.values) planMarkLabel(kind),
    };
    expect(labels, {'舞 DDL', '随舞事件', '团内检查'});
  });

  test('时间轴竖线键：舞 DDL 沿用旧键，其余带类型后缀', () {
    expect(
      planTimelineMarkerKey(PlanMarkKind.ddl, '2026-10-05'),
      'plan_timeline_marker_2026-10-05',
    );
    expect(
      planTimelineMarkerKey(PlanMarkKind.social, '2026-10-05'),
      'plan_timeline_marker_social_2026-10-05',
    );
    expect(
      planTimelineMarkerKey(PlanMarkKind.teamCheck, '2026-10-05'),
      'plan_timeline_marker_teamcheck_2026-10-05',
    );
  });
}
