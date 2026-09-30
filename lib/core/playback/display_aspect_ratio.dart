/// 显示比例换算纯件：编码宽高 + 旋转量 → 显示朝向的比例（宽/高）。
///
/// 屏幕上的画面矩形由 media_kit 播放器的 `state.width/height` 决定，它在
/// `dw`/`dh` 之上按 `params.rotate ?? 0` 交换宽高；本件照抄这一条——
/// `rotate` 为 0 或 180 不换、其余交换、缺失按 0。两处判据必须同源，否则
/// App 算出的比例与实际画出的画面不是同一个形状。
///
/// 宽高任一缺失或非正 → `null`（未知；消费方对 `null` 与非正的处置同款）。
/// 零 Flutter 依赖。
library;

/// 显示朝向的比例（宽/高）；[width] / [height] 任一缺失或非正时为 `null`。
double? displayAspectRatio({int? width, int? height, int? rotation}) {
  final swapsAxes = rotation != null && rotation != 0 && rotation != 180;
  final displayedWidth = swapsAxes ? height : width;
  final displayedHeight = swapsAxes ? width : height;
  if (displayedWidth == null ||
      displayedHeight == null ||
      displayedWidth <= 0 ||
      displayedHeight <= 0) {
    return null;
  }
  return displayedWidth / displayedHeight;
}
