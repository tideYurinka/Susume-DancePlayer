import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';

/// 语义断言助手：一次断言「角色 + 名字 + 可点与否」。
///
/// 按键取语义层：键直接挂在 `Semantics` 上时取自身；否则向下找第一个
/// 声明为按钮的 `Semantics`（如熟练度键挂在 `PopupMenuButton` 上的形状）。
Semantics semanticsOfKey(WidgetTester tester, Key key) {
  final root = tester.widget(find.byKey(key));
  if (root is Semantics) return root;
  final buttonLayer = find.descendant(
    of: find.byKey(key),
    matching: find.byWidgetPredicate(
      (w) => w is Semantics && (w.properties.button ?? false),
    ),
  );
  expect(buttonLayer, findsOneWidget, reason: '$key 子树未找到按钮语义层');
  return tester.widget<Semantics>(buttonLayer.first);
}

/// 断言 [key] 所指的件是按钮；传入则一并核对语义名字 [label]、可点门控
/// [enabled] 与选中态 [selected]。不传的维度不断言。
void expectButtonSemantics(
  WidgetTester tester,
  Key key, {
  String? label,
  bool? enabled,
  bool? selected,
  String? reason,
}) {
  final properties = semanticsOfKey(tester, key).properties;
  expect(properties.button, isTrue, reason: reason ?? '$key 应报按钮语义');
  if (label != null) {
    expect(_semanticName(tester, key), label, reason: reason ?? '$key 的语义名字');
  }
  if (enabled != null) {
    expect(properties.enabled, enabled, reason: reason ?? '$key 的可点门控');
  }
  if (selected != null) {
    expect(properties.selected, selected, reason: reason ?? '$key 的选中态');
  }
}

/// 语义名字取**按键所在的那个语义节点**的可读名（与读屏实际听到的一致）：
/// `Semantics(label:)`、`Icon.semanticLabel`、`IconButton.tooltip` 三种来源
/// 都会合并到该节点上，不必在测试里手工拆语义属性。
String? _semanticName(WidgetTester tester, Key key) {
  final node = tester.getSemantics(find.byKey(key));
  if (node.label.isNotEmpty) return node.label;
  return node.tooltip.isNotEmpty ? node.tooltip : null;
}

/// 断言 [key] 所在件的语义节点报出名字：`label` 全等、`labelContains` 包含
/// （合并节点里只多出一个状态词时用后者）；传 `liveRegion` 时一并核对
/// 「可播报区域」旗标。不要求按钮角色——状态播报件（角标/真值/手势读数）
/// 不是按钮。
void expectSemanticsLabel(
  WidgetTester tester,
  Key key, {
  String? label,
  String? labelContains,
  bool? liveRegion,
  String? reason,
}) {
  final node = tester.getSemantics(find.byKey(key));
  if (label != null) {
    expect(node.label, label, reason: reason ?? '$key 的语义名字');
  }
  if (labelContains != null) {
    expect(
      node.label,
      contains(labelContains),
      reason: reason ?? '$key 的语义名字应包含 $labelContains',
    );
  }
  if (liveRegion != null) {
    expect(
      node.flagsCollection.isLiveRegion,
      liveRegion,
      reason: reason ?? '$key 的可播报区域旗标',
    );
  }
}

/// 沿无障碍激活路径触发 [key] 的 tap（等价读屏双击）：先要求该件的语义节点
/// 真的暴露 tap 动作，再由语义宿主派发一次。用指针 `tap` 走的不是这条路径，
/// 因此「角色在场但没有动作」的哑按钮只能被本助手照出来。
void activateBySemantics(WidgetTester tester, Key key) {
  final node = tester.getSemantics(find.byKey(key));
  expect(
    node.getSemanticsData().hasAction(SemanticsAction.tap),
    isTrue,
    reason: '$key 的语义节点应暴露 tap 动作（读屏双击才有落点）',
  );
  // 测试绑定的语义树挂在 binding.pipelineOwner（rootPipelineOwner 之外）。
  // ignore: deprecated_member_use
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
}
