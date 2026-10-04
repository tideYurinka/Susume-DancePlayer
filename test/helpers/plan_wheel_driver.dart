import 'package:dance_learning_app/plan/plan_wheel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 计划滚轮测试驱动：按档位滑选某一列，等价于用户滑选。
///
/// 一次 `drag` 后松手会带一点甩动惯性，落点受列内容长度影响可能差一档；
/// 这里滑选到目标档位后按实际落点补齐，保证用例断言的是值而非手感。

/// 本地日（测试统一取今天零点）。
DateTime localToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// 把全屏编辑页的 ListView 滚到某个控件可见：compact 档视口更矮，编辑页
/// 内滚轮多且可贴到屏幕上下缘，捏不到不落在滚轮上的起拖点，故直接驱动
/// 列表的滚动位置逐段下滚，让惰性列表项逐段构建。
Future<void> scrollPlanEditorTo(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  // ListView 自身的 Scrollable 在其子树内且是最浅的那个（滚轮各自的
  // Scrollable 都更深），据此取列表滚动位置。
  final listEl = find.byKey(const Key('plan_editor_scroll')).evaluate().single;
  int depth(Element el) {
    var d = 0;
    var cur = el;
    cur.visitAncestorElements((a) {
      d++;
      return a != listEl;
    });
    return d;
  }

  final scrollableEl = find
      .descendant(
        of: find.byKey(const Key('plan_editor_scroll')),
        matching: find.byType(Scrollable),
      )
      .evaluate()
      .reduce((a, b) => depth(a) <= depth(b) ? a : b);
  final scrollableState =
      (scrollableEl as StatefulElement).state as ScrollableState;
  final position = scrollableState.position;

  var guard = 0;
  while (finder.evaluate().isEmpty && guard < 60) {
    position.jumpTo(position.pixels + 200);
    await tester.pumpAndSettle();
    guard++;
  }
  if (finder.evaluate().isEmpty) {
    throw StateError('scrollPlanEditorTo: 滚到底仍未滚到 $key');
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

FixedExtentScrollController _controllerOf(WidgetTester tester, Key columnKey) =>
    tester.widget<ListWheelScrollView>(find.byKey(columnKey)).controller
        as FixedExtentScrollController;

Future<void> _scrollTo(
  WidgetTester tester,
  Key columnKey,
  int targetIndex,
) async {
  var current = _controllerOf(tester, columnKey).selectedItem;
  if (current == targetIndex) return;
  await tester.drag(
    find.byKey(columnKey),
    Offset(0, -kPlanWheelItemExtent * (targetIndex - current)),
  );
  await tester.pumpAndSettle();
  current = _controllerOf(tester, columnKey).selectedItem;
  if (current != targetIndex) {
    _controllerOf(tester, columnKey).jumpToItem(targetIndex);
    await tester.pumpAndSettle();
  }
}

/// 日期滚轮滑到 [target]（年 → 月 → 日，逐列滑到目标档）。
Future<void> selectPlanDate(
  WidgetTester tester,
  String columnPrefix, {
  required DateTime target,
  required DateTime today,
}) async {
  final wheel = planDateWheelFromDay(target, today: today);
  await _scrollTo(tester, Key('${columnPrefix}_year'), wheel.yearIndex);
  await _scrollTo(tester, Key('${columnPrefix}_month'), wheel.monthIndex);
  await _scrollTo(tester, Key('${columnPrefix}_day'), wheel.dayIndex);
}

/// 时间滚轮滑到 [target] 分钟数（null = 时列「不设」）。
Future<void> selectPlanTime(
  WidgetTester tester,
  String columnPrefix, {
  required int? target,
}) async {
  final wheel = planTimeWheelFromMinutes(target);
  await _scrollTo(tester, Key('${columnPrefix}_hour'), wheel.hourIndex);
  await _scrollTo(tester, Key('${columnPrefix}_minute'), wheel.minuteIndex);
}

/// 提前 N 天滚轮滑到 [target]（null = 首档「不提醒」）。
Future<void> selectPlanLead(
  WidgetTester tester,
  Key columnKey, {
  required int? target,
}) async {
  await _scrollTo(tester, columnKey, planLeadWheelFromValue(target));
}

/// 提交日期滚轮滑到 [target]（年列首档「不填」）。
Future<void> selectPlanSubmittedDate(
  WidgetTester tester,
  String columnPrefix, {
  required DateTime target,
  required DateTime fallback,
  required DateTime today,
}) async {
  final wheel = planSubmittedWheelFromDay(
    target,
    fallback: fallback,
    today: today,
  );
  await _scrollTo(tester, Key('${columnPrefix}_year'), wheel.yearIndex);
  await _scrollTo(tester, Key('${columnPrefix}_month'), wheel.monthIndex);
  await _scrollTo(tester, Key('${columnPrefix}_day'), wheel.dayIndex);
}

/// 滑回提交日期年列首档「不填」。
Future<void> clearPlanSubmittedDate(
  WidgetTester tester,
  String columnPrefix,
) async {
  await _scrollTo(tester, Key('${columnPrefix}_year'), 0);
}
