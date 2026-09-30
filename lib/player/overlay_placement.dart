part of 'overlay.dart';

/// 未自定义格的默认纵向位置：视口高 × 12%。
const double kDefaultOverlayOffsetHeightFactor = 0.12;

/// 浮层位的格：姿态二值（横屏／竖屏）× 对比二值（对比／普通）。
/// 横屏左右两向共用一格、竖屏上下两向共用一格。
enum OverlayPlacementCell {
  portraitNormal,
  landscapeNormal,
  portraitCompare,
  landscapeCompare,
}

/// 姿态 × 对比到格的唯一映射：对比态落对比格、非对比态落普通格。
OverlayPlacementCell resolveOverlayPlacementCell({
  required bool landscape,
  required bool compare,
}) {
  return switch ((landscape, compare)) {
    (false, false) => OverlayPlacementCell.portraitNormal,
    (false, true) => OverlayPlacementCell.portraitCompare,
    (true, false) => OverlayPlacementCell.landscapeNormal,
    (true, true) => OverlayPlacementCell.landscapeCompare,
  };
}

/// 未自定义格的默认位：贴左（横向恒 0，不牵进浮层自身宽度）、纵向 =
/// 视口高 × 12%，按当前视口现算。四格同款。
Offset defaultOverlayOffset(Size viewport) =>
    Offset(0, viewport.height * kDefaultOverlayOffsetHeightFactor);

/// 四格浮层位容器：缺席的格 = 未自定义（显示时按 [defaultOverlayOffset]
/// 现算）；矩形宽系数与摆锤等比系数两形态各一份、四格共用。
///
/// 值对象：相等性按内容判定，可安全用于相等性防环。
class OverlayPlacements {
  const OverlayPlacements({
    this.offsets = const {},
    this.rectWidthFactor = 1.0,
    this.pendulumScale = 1.0,
  });

  /// 各格的自定义偏移；键缺席即该格未自定义。调用方不得改写传入的
  /// map——容器按不可变值传递，写入一律经 [withOffset] 产出新实例。
  final Map<OverlayPlacementCell, Offset> offsets;

  /// 矩形宽系数（矩形形态内容宽 = 基准宽 × 此系数）。
  final double rectWidthFactor;

  /// 摆锤等比系数（摆锤形态内容整体 = 基准尺寸 × 此系数）。
  final double pendulumScale;

  /// 该格的自定义偏移；null = 未自定义。
  Offset? offsetFor(OverlayPlacementCell cell) => offsets[cell];

  /// 写入该格的偏移；[value] 为 null 即清除该格（回未自定义）。
  OverlayPlacements withOffset(OverlayPlacementCell cell, Offset? value) {
    final next = Map<OverlayPlacementCell, Offset>.of(offsets);
    if (value == null) {
      next.remove(cell);
    } else {
      next[cell] = value;
    }
    return OverlayPlacements(
      offsets: next,
      rectWidthFactor: rectWidthFactor,
      pendulumScale: pendulumScale,
    );
  }

  /// 改两个共用尺寸系数；未传的系数保持现值。
  OverlayPlacements withFactors({
    double? rectWidthFactor,
    double? pendulumScale,
  }) => OverlayPlacements(
    offsets: offsets,
    rectWidthFactor: rectWidthFactor ?? this.rectWidthFactor,
    pendulumScale: pendulumScale ?? this.pendulumScale,
  );

  @override
  bool operator ==(Object other) =>
      other is OverlayPlacements &&
      other.rectWidthFactor == rectWidthFactor &&
      other.pendulumScale == pendulumScale &&
      _sameOffsets(other.offsets, offsets);

  @override
  int get hashCode => Object.hash(
    rectWidthFactor,
    pendulumScale,
    Object.hashAllUnordered(
      offsets.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

bool _sameOffsets(
  Map<OverlayPlacementCell, Offset> a,
  Map<OverlayPlacementCell, Offset> b,
) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
