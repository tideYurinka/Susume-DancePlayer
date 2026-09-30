/// 可拖浮层选中态的虚线矩形框画笔（数拍浮层与备注贴纸共用）。
library;

import 'package:flutter/material.dart';

/// 选中框虚线段长与空隙（观感值，真机看版项）。
const double kSelectionDashWidth = 6;
const double kSelectionDashGap = 4;

/// 沿矩形四边画虚线：段长 [kSelectionDashWidth]、空隙 [kSelectionDashGap]。
///
/// [inset] = 路径相对盒边的内缩量（`> 0` 时描边落在盒边内，`0` = 沿盒边
/// 描）；[strokeWidth] 与 [color] 由调用点给，两处浮层各自取值。
class DashedSelectionBoxPainter extends CustomPainter {
  DashedSelectionBoxPainter({
    required this.color,
    required this.strokeWidth,
    this.inset = 0,
  }) : _paint = Paint()
         ..color = color
         ..style = PaintingStyle.stroke
         ..strokeWidth = strokeWidth;

  final Color color;
  final double strokeWidth;
  final double inset;

  final Paint _paint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height).deflate(inset);
    const step = kSelectionDashWidth + kSelectionDashGap;
    void dashedLine(Offset a, Offset b) {
      final distance = (b - a).distance;
      if (distance <= 0) return;
      final direction = (b - a) / distance;
      var drawn = 0.0;
      while (drawn < distance) {
        final end = (drawn + kSelectionDashWidth).clamp(0.0, distance);
        canvas.drawLine(a + direction * drawn, a + direction * end, _paint);
        drawn += step;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomLeft, rect.bottomRight);
    dashedLine(rect.topLeft, rect.bottomLeft);
  }

  @override
  bool shouldRepaint(DashedSelectionBoxPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.inset != inset;
}
