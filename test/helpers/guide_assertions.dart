import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 断言引导演出层**真的指向** [anchor] 这个控件：气泡紧贴锚点、箭头夹在
/// 气泡与锚点之间且对准锚点中心、高亮层在场。
///
/// 这是外部行为断言——只测「屏幕上指向哪里」，不测像素、颜色与遮罩实现。
/// 注意别用 `tester.getRect(find.byKey(const Key('guide_highlight')))` 去断言
/// 指向：那是 `Positioned.fill` 的整屏矩形，`contains(锚点中心)` 恒真，等于
/// 没测（真机上曾因此漏掉「洞画在屏幕左上角」的错位）。
void expectGuidePointsAt(WidgetTester tester, Finder anchor) {
  expect(find.byKey(const Key('guide_highlight')), findsOneWidget);
  expect(find.byKey(const Key('guide_bubble')), findsOneWidget);

  final anchorRect = tester.getRect(anchor);
  final cardRect = tester.getRect(find.byKey(const Key('guide_bubble')));
  final arrowRect = tester.getRect(find.byKey(const Key('guide_arrow')));
  // 气泡与箭头算一整个提示块：它必须紧贴锚点，而不是飘在屏幕别处。
  final blockRect = cardRect.expandToInclude(arrowRect);

  final gap = blockRect.bottom <= anchorRect.top
      ? anchorRect.top - blockRect.bottom
      : blockRect.top - anchorRect.bottom;
  expect(
    gap,
    inInclusiveRange(0, 40),
    reason: '提示块应紧贴锚点（提示块 $blockRect / 锚点 $anchorRect）',
  );

  // 箭头夹在气泡与锚点之间，而不是飘在别处。
  final between =
      (arrowRect.top >= cardRect.bottom - 1 &&
          arrowRect.bottom <= anchorRect.top + 1) ||
      (arrowRect.top >= anchorRect.bottom - 1 &&
          arrowRect.bottom <= cardRect.top + 1);
  expect(between, isTrue, reason: '箭头应落在气泡与锚点之间');

  // 箭头对准锚点中心：气泡比锚点宽得多，箭头固定贴左端就会指偏。
  expect(
    tester.getCenter(find.byKey(const Key('guide_arrow'))).dx,
    closeTo(anchorRect.center.dx, 1),
    reason: '箭头应对准锚点中心（锚点 $anchorRect / 箭头 $arrowRect）',
  );
}

/// 断言动手演练的待办条**贴在高亮框旁**：框中心在屏幕
/// 上半 → 条子在框下方 + 朝上箭头，在下半 → 在框上方 + 朝下箭头；条块（条子
/// 与箭头）与框的竖直间距 = 间距 12 + 箭头 10；两者永不相交；水平以框中心
/// 为中心并钳进屏内；箭头横向对准框中心（钳在条宽内）。
///
/// 12 / 10 / 16 是定死的取值（独立于实现里的常量），故在此直写。
void expectDrillBarAnchoredTo(WidgetTester tester, Rect highlightRect) {
  final bar = find.byKey(const Key('drill_task_bar'));
  final arrow = find.byKey(const Key('drill_task_arrow'));
  expect(bar, findsOneWidget);
  expect(arrow, findsOneWidget);
  final barRect = tester.getRect(bar);
  final arrowRect = tester.getRect(arrow);
  // 条块 = 条子与它那根箭头（箭头是条子的指向部分）。
  final block = barRect.expandToInclude(arrowRect);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  const margin = 16.0;
  const gapAndArrow = 12.0 + 10.0;

  if (highlightRect.center.dy < screen.height / 2) {
    expect(
      block.top - highlightRect.bottom,
      closeTo(gapAndArrow, 1),
      reason:
          '框在屏幕上半，条子应放在框下方且间距 = 12 + 10'
          '（框 $highlightRect / 条块 $block）',
    );
  } else {
    expect(
      highlightRect.top - block.bottom,
      closeTo(gapAndArrow, 1),
      reason:
          '框在屏幕下半，条子应放在框上方且间距 = 12 + 10'
          '（框 $highlightRect / 条块 $block）',
    );
  }
  expect(
    block.overlaps(highlightRect),
    isFalse,
    reason: '条子与高亮框永不相交（框 $highlightRect / 条块 $block）',
  );
  // 水平：钳进屏内、不破两边 16 的边距。
  expect(barRect.left, greaterThanOrEqualTo(margin - 0.5));
  expect(barRect.right, lessThanOrEqualTo(screen.width - margin + 0.5));
  // 未触发钳位时以框中心为中心；触发钳位时条子贴住那一侧的边距。
  final unclampedLeft = highlightRect.center.dx - barRect.width / 2;
  final clamped =
      unclampedLeft < margin - 0.5 ||
      unclampedLeft > screen.width - margin - barRect.width + 0.5;
  if (clamped) {
    expect(
      unclampedLeft < margin - 0.5
          ? barRect.left
          : screen.width - barRect.right,
      closeTo(margin, 1),
      reason: '水平钳位后条子贴住屏边距（框 $highlightRect / 条子 $barRect）',
    );
  } else {
    expect(
      block.center.dx,
      closeTo(highlightRect.center.dx, 1),
      reason: '水平以框中心为中心（框 $highlightRect / 条块 $block）',
    );
  }
  // 箭头横向对准框中心，并被钳在条宽内。
  const arrowHalf = 10.0;
  expect(
    tester.getCenter(arrow).dx,
    closeTo(
      highlightRect.center.dx.clamp(
        barRect.left + arrowHalf,
        barRect.right - arrowHalf,
      ),
      1,
    ),
    reason: '箭头应对准框中心（框 $highlightRect / 箭头 $arrowRect）',
  );
}
