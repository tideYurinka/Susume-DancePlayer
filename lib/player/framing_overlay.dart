/// 取景覆盖层：取景态内把**选区之外**的部分压暗（只压画面矩形之内、
/// 画面外的黑边不参与），在选区边界画一圈白线，并在八个**取景控制点**上画
/// 圆点——四角 ∅16dp、四边中点 ∅10dp（命中盒 48dp 不在这里画，见
/// `framing_session.dart`）。未调过（无选区）时不画任何覆盖层。
///
/// 控件本身铺满所在可用区，[pictureRect] 是画面矩形相对本控件左上角的矩形，
/// 选区四边按源画面原相归一化——两者相乘即屏幕上的选区矩形。
library;

import 'package:flutter/material.dart';

import '../annotation/framing_selection.dart'
    show
        FramingSelection,
        FramingSelectionHandleFacts,
        framingSelectionHandleCenters,
        framingSelectionRectOnPicture;

/// 选区外的压暗不透明度（约 55% 黑）。
const double kFramingOverlayDimOpacity = 0.55;

/// 选区边界白线宽（dp）。
const double kFramingSelectionBorderWidth = 1.5;

/// 选区边界与控制点的颜色。
const Color kFramingSelectionBorderColor = Colors.white;

/// 四角取景控制点的直径（dp）。
const double kFramingCornerHandleDiameter = 16;

/// 四边中点取景控制点的直径（dp）。
const double kFramingEdgeHandleDiameter = 10;

/// 取景态覆盖层：[selection] 为空即未调过，不画；否则在 [pictureRect] 之内
/// 压暗选区外、在选区边界画白框。
class FramingSelectionOverlay extends StatelessWidget {
  const FramingSelectionOverlay({
    super.key,
    required this.selection,
    required this.pictureRect,
  });

  /// 已提交的取景选区；null = 未调过。
  final FramingSelection? selection;

  /// 画面矩形（相对本控件左上角）。
  final Rect pictureRect;

  @override
  Widget build(BuildContext context) {
    final selection = this.selection;
    if (selection == null || pictureRect.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const Key('framing_selection_overlay'),
          painter: _FramingSelectionOverlayPainter(
            selection: selection,
            pictureRect: pictureRect,
          ),
        ),
      ),
    );
  }
}

class _FramingSelectionOverlayPainter extends CustomPainter {
  const _FramingSelectionOverlayPainter({
    required this.selection,
    required this.pictureRect,
  });

  final FramingSelection selection;
  final Rect pictureRect;

  /// 选区在屏幕（本控件）坐标下的矩形。
  Rect get selectionRect {
    final rect = framingSelectionRectOnPicture(
      selection: selection,
      pictureLeft: pictureRect.left,
      pictureTop: pictureRect.top,
      pictureWidth: pictureRect.width,
      pictureHeight: pictureRect.height,
    );
    return Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..color = Colors.black.withValues(alpha: kFramingOverlayDimOpacity);
    // 只压画面矩形之内、选区之外；画面外的黑边不参与。
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(pictureRect),
        Path()..addRect(selectionRect),
      ),
      dim,
    );
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kFramingSelectionBorderWidth
      ..color = kFramingSelectionBorderColor;
    canvas.drawRect(selectionRect, edge);
    // 八个取景控制点：四角 ∅16dp、四边中点 ∅10dp（四角先画，与命中优先级
    // 一致）。
    final handle = Paint()
      ..style = PaintingStyle.fill
      ..color = kFramingSelectionBorderColor;
    for (final center in framingSelectionHandleCenters(
      selection: selection,
      pictureLeft: pictureRect.left,
      pictureTop: pictureRect.top,
      pictureWidth: pictureRect.width,
      pictureHeight: pictureRect.height,
    )) {
      canvas.drawCircle(
        Offset(center.x, center.y),
        // 视觉件居中在 48dp 命中盒里：四角 ∅16dp、四边
        // 中点 ∅10dp。
        (center.handle.isCorner
                ? kFramingCornerHandleDiameter
                : kFramingEdgeHandleDiameter) /
            2,
        handle,
      );
    }
  }

  @override
  bool shouldRepaint(_FramingSelectionOverlayPainter oldDelegate) =>
      oldDelegate.selection != selection ||
      oldDelegate.pictureRect != pictureRect;
}
