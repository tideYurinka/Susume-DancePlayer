/// 气泡水平钳制测试断言（共享 helper）：
/// 几何（完整进屏、左右缘留边）与可达（命中测试命中控件自身）。
library;

import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show HitTestResult;
import 'package:flutter_test/flutter_test.dart';

/// 气泡全局矩形（经钳制平移后的可见矩形）。
Rect bubbleGlobalRect(RenderBox bubble) => Rect.fromPoints(
  bubble.localToGlobal(Offset.zero),
  bubble.localToGlobal(bubble.size.bottomRight(Offset.zero)),
);

/// 几何断言：气泡完整位于屏内（右缘不溢出、左缘留边合理）。
/// 传 [screenHeight] 时同时断上下缘（四边各留 [speedBubbleScreenMargin]，
/// 对既有调用方是加强）。
void expectBubbleClampedOnScreen(
  RenderBox bubble, {
  required double screenWidth,
  double? screenHeight,
  String? reason,
}) {
  final rect = bubbleGlobalRect(bubble);
  const margin = speedBubbleScreenMargin;
  expect(
    rect.right,
    lessThan(screenWidth - margin + 1e-9),
    reason: reason ?? '右缘不溢出（屏宽 $screenWidth）',
  );
  expect(rect.left, greaterThan(margin - 1e-9), reason: '左缘留边合理');
  if (screenHeight != null) {
    expect(
      rect.bottom,
      lessThan(screenHeight - margin + 1e-9),
      reason: reason ?? '底缘不溢出（屏高 $screenHeight）',
    );
    expect(rect.top, greaterThan(margin - 1e-9), reason: '顶缘留边合理');
  }
}

/// 可达断言：控件中心的命中测试命中其自身
/// （不被遮罩挡住/裁出屏——平移后最右内容仍可达可拖的前提）。
void expectHitReachable(RenderBox box) {
  final center = box.localToGlobal(box.size.center(Offset.zero));
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(
    result,
    center,
    WidgetsBinding.instance.platformDispatcher.views.first.viewId,
  );
  expect(
    result.path.any((e) => e.target == box),
    isTrue,
    reason: '命中可达（不被遮罩挡住/裁出屏）',
  );
}
