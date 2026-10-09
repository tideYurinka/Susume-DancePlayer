/// **数拍浮层的落位换算**（纯件，零 IO；`#30`）：把「手机上按视口取值的浮层位」
/// 折成**画面区域上的归一化落位**，好让投屏副本（它没有视口，帧就是画面区）
/// 把同一行数字画在同一处。
///
/// ## 口径：相对画面区域
///
/// 手机上的浮层位是**视口坐标**（[OverlayPlacements] 的四格记忆 + 尺寸系数，
/// 经 [resolveOverlayGeometry] 解析、钳进视口）；电视上没有视口——副本的
/// **帧就是画面区域**。于是定义：看手机时数拍那一行相对**画面区域**的位置，
/// 与电视上相对帧的位置一致。换算即
/// `(手机上的矩形 − 画面矩形左上角) ÷ 画面矩形尺寸`。
///
/// ## 落在画面之外时贴边（不是"看不见"）
///
/// 浮层可以停在信箱黑边上（竖屏 + 横片是最常见的默认情形），而那片黑边在
/// 副本里**根本不存在**——照直换算会得到画面外的坐标，电视上那一行数字就此
/// 消失。故与**备注贴纸**同款处理：把数字那一块的中心逐轴钳进画面区域
/// （该轴装不下时居中，与 `noteStickerRect` 的钳制退化一致）。
/// 画面之内的落位因此逐位一致；画面之外的那一档贴到最近的画面边。
///
/// ## 与上屏同源
///
/// 浮层框的生效几何读 [resolveOverlayGeometry]（控制器解析生效几何的同一处）、
/// 内容区尺寸读 [overlayContentSize]、数字在框里的位置读
/// [beatNumbersCenterInContent]——都不是照着上屏再写一遍。
library;

import 'dart:ui' show Rect, Size;

import '../cast/cast_beat_count.dart' show castOverlayPlacementUsable;
import 'beat_animation.dart' show BeatAnimationStyle;
import 'beat_count_layout.dart'
    show beatNumbersCanvasSize, beatNumbersCenterInContent;
import 'overlay.dart'
    show
        OverlayPlacementCell,
        OverlayPlacements,
        overlayContentSize,
        resolveOverlayGeometry;

/// 数拍那一行（含它的底衬）在**画面区域**上的归一化落位。
class CastBeatPlacement {
  const CastBeatPlacement({
    required this.centerX,
    required this.centerY,
    required this.widthFraction,
    required this.heightFraction,
  });

  /// 落位中心横坐标（画面区域归一化，0 = 左缘、1 = 右缘）。
  final double centerX;

  /// 落位中心纵坐标。
  final double centerY;

  /// 落位宽占画面区域宽的比例。
  final double widthFraction;

  /// 落位高占画面区域高的比例。
  final double heightFraction;

  /// 可用：四个数都有限、尺寸为正（否则不装这一层，宁可不画也不画错）。
  ///
  /// 判定只有一条（[castOverlayPlacementUsable]，投屏域声明）：数拍层的
  /// `CastBeatCountOverlay.usable` 与这里调的是同一个函数。
  bool get usable => castOverlayPlacementUsable(
    centerX: centerX,
    centerY: centerY,
    widthFraction: widthFraction,
    heightFraction: heightFraction,
  );

  /// 进缓存键的记号：位置一动产物就变（用户把浮层挪一下再投，不该命中旧副本）。
  String get token =>
      'bo:${centerX.toStringAsFixed(6)},${centerY.toStringAsFixed(6)},'
      '${widthFraction.toStringAsFixed(6)},${heightFraction.toStringAsFixed(6)}';

  @override
  bool operator ==(Object other) =>
      other is CastBeatPlacement && other.token == token;

  @override
  int get hashCode => token.hashCode;

  @override
  String toString() => 'CastBeatPlacement($token)';
}

/// 浮层**内容区**在屏幕（视口坐标）上的矩形：框的生效几何经
/// [overlayContentSize] 取内容区尺寸。宿主未接线视口时不成立（返回 null）。
Rect? castBeatContentRect({
  required OverlayPlacements placements,
  required OverlayPlacementCell cell,
  required BeatAnimationStyle style,
  required Size viewport,
  double textScale = 1,
}) {
  if (!_usableSize(viewport)) return null;
  final geometry = resolveOverlayGeometry(
    placements: placements,
    cell: cell,
    style: style,
    viewport: viewport,
  );
  final content = overlayContentSize(box: geometry.size, textScale: textScale);
  if (!_usableSize(content)) return null;
  return geometry.offset & content;
}

/// 手机上的数拍那一行 → 副本画面上那一块（归一化）。
///
/// [pictureRect] 是手机上**画面区域**（取景后那块画面）的屏幕矩形；
/// [numbersSize] 是量出来的数字行逻辑尺寸（`cast_beat_sheet.dart` 那一处量测）；
/// [textScale] 是系统字号（内容区竖向容量与数字尺寸同读它）。
/// 画面矩形量不到（空 / 非有限）时返回 null：宁可不装这一层。
CastBeatPlacement? castBeatPlacementOf({
  required OverlayPlacements placements,
  required OverlayPlacementCell cell,
  required BeatAnimationStyle style,
  required Size viewport,
  required Rect pictureRect,
  required Size numbersSize,
  double textScale = 1,
}) {
  final contentRect = castBeatContentRect(
    placements: placements,
    cell: cell,
    style: style,
    viewport: viewport,
    textScale: textScale,
  );
  if (contentRect == null) return null;
  if (!_usableSize(pictureRect.size) || !_usableSize(numbersSize)) return null;
  final center =
      contentRect.topLeft +
      beatNumbersCenterInContent(
        contentSize: contentRect.size,
        numbersSize: numbersSize,
        style: style,
        textScale: textScale,
      );
  final canvas = beatNumbersCanvasSize(
    contentSize: contentRect.size,
    numbersSize: numbersSize,
    style: style,
    textScale: textScale,
  );
  if (!_usableSize(canvas)) return null;
  final rect = Rect.fromCenter(
    center: center,
    width: canvas.width,
    height: canvas.height,
  );
  return CastBeatPlacement(
    centerX: (rect.center.dx - pictureRect.left) / pictureRect.width,
    centerY: (rect.center.dy - pictureRect.top) / pictureRect.height,
    widthFraction: rect.width / pictureRect.width,
    heightFraction: rect.height / pictureRect.height,
  );
}

/// 逐轴钳制（与 `noteStickerRect` 同款退化）：
/// 该轴上装得下 → 中心钳进画面（整块留在画面内）；装不下 → 该轴居中。
/// 画面之内原样返回，故「相对画面区域的位置一致」在画面之内逐位成立。
CastBeatPlacement castBeatPlacementClamped({
  required CastBeatPlacement placement,
  required Rect pictureRect,
}) {
  if (!placement.usable || !_usableSize(pictureRect.size)) return placement;
  final width = placement.widthFraction * pictureRect.width;
  final height = placement.heightFraction * pictureRect.height;
  final left = pictureRect.left + placement.centerX * pictureRect.width;
  final top = pictureRect.top + placement.centerY * pictureRect.height;
  final dx = width >= pictureRect.width
      ? pictureRect.center.dx
      : left.clamp(
          pictureRect.left + width / 2,
          pictureRect.right - width / 2,
        );
  final dy = height >= pictureRect.height
      ? pictureRect.center.dy
      : top.clamp(
          pictureRect.top + height / 2,
          pictureRect.bottom - height / 2,
        );
  return CastBeatPlacement(
    centerX: (dx - pictureRect.left) / pictureRect.width,
    centerY: (dy - pictureRect.top) / pictureRect.height,
    widthFraction: placement.widthFraction,
    heightFraction: placement.heightFraction,
  );
}

/// 上面两步的合体：换算出落位并逐轴钳进画面区域（调用方只用这一个）。
CastBeatPlacement? castBeatPlacementInPicture({
  required OverlayPlacements placements,
  required OverlayPlacementCell cell,
  required BeatAnimationStyle style,
  required Size viewport,
  required Rect pictureRect,
  required Size numbersSize,
  double textScale = 1,
}) {
  final placement = castBeatPlacementOf(
    placements: placements,
    cell: cell,
    style: style,
    viewport: viewport,
    pictureRect: pictureRect,
    numbersSize: numbersSize,
    textScale: textScale,
  );
  if (placement == null) return null;
  return castBeatPlacementClamped(
    placement: placement,
    pictureRect: pictureRect,
  );
}

bool _usableSize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;
