/// 贴框布点的唯一派生（帮助域）。
///
/// 给高亮框矩形、屏幕尺寸与件宽上限，给出一份坐标：气泡左缘、上缘或下缘、
/// 条宽与箭头横向位置。就地讲解气泡与动手步待办条共用这一份——坐标只此一处；
/// 指向高亮框的三角也共用同一件 [GuideArrowPainter]。
library;

import 'package:flutter/rendering.dart';

/// 气泡与屏幕边缘的最小边距。
const double _guideBubbleMargin = 16;

/// 气泡与高亮框之间的间距。
const double _guideBubbleGap = 12;

/// 指向高亮框的三角：宽用于把箭头横向对准框中心，高同时是气泡与框之间的
/// 附加间距（间距 = [_guideBubbleGap] + [guideArrowHeight]）。
const double guideArrowWidth = 20;
const double guideArrowHeight = 10;

/// 三角的朝向：up = 指向屏幕上方（件在框下方），down = 指向下方（件在框
/// 上方）。
enum GuideArrowDirection { up, down }

/// 指向高亮框的三角：就地讲解气泡与贴框待办条共用同一形状、尺寸与取色，
/// 谁都不再各画一份。
class GuideArrowPainter extends CustomPainter {
  const GuideArrowPainter(this.direction, this.color);

  final GuideArrowDirection direction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final up = direction == GuideArrowDirection.up;
    final path = Path()
      ..moveTo(0, up ? size.height : 0)
      ..lineTo(size.width, up ? size.height : 0)
      ..lineTo(size.width / 2, up ? 0 : size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(GuideArrowPainter oldDelegate) =>
      oldDelegate.direction != direction || oldDelegate.color != color;
}

/// 气泡件宽上限（贴框的条子不近满宽）。
const double guideBubbleMaxWidth = 320;

/// 一次贴框布点的结果。
class GuideBubblePlacement {
  const GuideBubblePlacement({
    required this.left,
    required this.top,
    required this.bottom,
    required this.width,
    required this.arrowLeft,
  });

  /// 气泡左缘（已钳回屏内）。
  final double left;

  /// 气泡上缘；气泡在框上方时为 null（此时用 [bottom]）。
  final double? top;

  /// 气泡下缘（距屏底）；气泡在框下方时为 null（此时用 [top]）。
  final double? bottom;

  final double width;

  /// 箭头左缘在气泡内的横向位置（箭头对准框中心并被钳在条宽内）。
  final double arrowLeft;

  /// 气泡是否放在框下方（箭头朝上）。放上方时为 false，箭头朝下。
  bool get below => top != null;
}

/// 唯一一份贴框布点：框中心在屏幕上半 → 气泡放框下方 + 朝上箭头；在下半 →
/// 放框上方 + 朝下箭头；水平以框中心为中心、钳进 `[margin, 屏宽 − margin −
/// 条宽]`；箭头横向钳在条宽内、对准框中心。
GuideBubblePlacement placeGuideBubble({
  required Rect anchorRect,
  required Size screen,
  required double maxWidth,
}) {
  final width = (screen.width - _guideBubbleMargin * 2).clamp(0.0, maxWidth);
  final below = anchorRect.center.dy < screen.height / 2;
  final left = (anchorRect.center.dx - width / 2).clamp(
    _guideBubbleMargin,
    screen.width - _guideBubbleMargin - width,
  );
  final top = below
      ? anchorRect.bottom + _guideBubbleGap + guideArrowHeight
      : null;
  final bottom = below
      ? null
      : screen.height - anchorRect.top + _guideBubbleGap + guideArrowHeight;
  // 箭头对准框中心（钳在气泡宽度内）：气泡比框宽得多，箭头若固定贴在气泡
  // 左端，就指不到框上了。
  final arrowLeft = (anchorRect.center.dx - left - guideArrowWidth / 2).clamp(
    0.0,
    width - guideArrowWidth,
  );
  return GuideBubblePlacement(
    left: left,
    top: top,
    bottom: bottom,
    width: width,
    arrowLeft: arrowLeft,
  );
}
