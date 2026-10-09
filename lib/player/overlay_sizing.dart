part of 'overlay.dart';

/// 浮层内容基准尺寸（系数 1.0 时的逻辑尺寸；命中区/选中框同源）。
/// 宽 = 矩形形态默认内容宽 320；
/// 高容纳数拍数字 + 节拍动画，全形态固定（高向预算 ≥
/// 胶囊内边距 20 + 数字行 56 + 间距 6 + 动画 32 = 114，120 有 6px 余量）。
const Size kOverlayBaseContentSize = Size(320, 120);

/// 摆锤形态专属内容基准宽（约 220×120，
/// 收窄只收宽——摆锤不沿用矩形共享的 320 宽、视觉不那么空旷）。
/// 高与共享 [kOverlayBaseContentSize.height] 同为 120（收窄不压缩高向
/// 预算）；const Size 字面量不能经属性访问引用共享 Size 成员，故此处
/// 高度按共享值并列书写。仅 pendulum 分支使用，bar 分支继续乘共享基准。
const Size kPendulumBaseContentSize = Size(220, 120);

/// 矩形宽系数下限（最小宽度保证 8 格与数字不触发渲染溢出）。
const double kMinRectWidthFactor = 0.5;

/// 矩形宽系数上限（0.5–2.5×）。
const double kMaxRectWidthFactor = 2.5;

/// 摆锤等比系数下限。
const double kMinPendulumScale = 0.5;

/// 摆锤等比系数上限（与矩形宽系数同口径收缩）。
const double kMaxPendulumScale = 2.5;

/// 矩形宽系数钳制。
double clampRectWidthFactor(double value) =>
    value.clamp(kMinRectWidthFactor, kMaxRectWidthFactor).toDouble();

/// 摆锤等比系数钳制。
double clampPendulumScale(double value) =>
    value.clamp(kMinPendulumScale, kMaxPendulumScale).toDouble();

/// 浮层实际内容尺寸解析：矩形形态只消费矩形宽系数（高度固定）；
/// 摆锤形态只消费等比系数（整体含数字等比）。命中区/拖拽区随此尺寸。
/// 传入 [viewport]时生效上限联动视口（min(相对上限,
/// 视口/基准)，铺满视口为止）；不传时维持内容相对上限语义。
Size resolveOverlaySize({
  required BeatAnimationStyle style,
  required double rectWidthFactor,
  required double pendulumScale,
  Size? viewport,
}) {
  final maxWidth = viewport == null
      ? kMaxRectWidthFactor
      : effectiveMaxRectWidthFactor(viewport);
  final maxScale = viewport == null
      ? kMaxPendulumScale
      : effectiveMaxPendulumScale(viewport);
  final barFactor = min(clampRectWidthFactor(rectWidthFactor), maxWidth);
  final pendulumFactor = min(clampPendulumScale(pendulumScale), maxScale);
  return switch (style) {
    BeatAnimationStyle.bar => Size(
      kOverlayBaseContentSize.width * barFactor,
      kOverlayBaseContentSize.height,
    ),
    BeatAnimationStyle.pendulum => Size(
      kPendulumBaseContentSize.width * pendulumFactor,
      kPendulumBaseContentSize.height * pendulumFactor,
    ),
  };
}

/// 矩形宽系数的视口联动生效上限（纯函数 seam）：
/// min(内容相对上限, 当前视口宽 / 基准内容宽)。
/// 极窄视口下生效上限可低于内容相对下限——铺满视口为准。
double effectiveMaxRectWidthFactor(Size viewport) {
  final viewportCap = viewport.width / kOverlayBaseContentSize.width;
  return viewportCap < kMaxRectWidthFactor ? viewportCap : kMaxRectWidthFactor;
}

/// 摆锤等比系数的视口联动生效上限：min(内容相对上限, 视口宽/基准宽,
/// 视口高/基准高)——宽高双维取更紧者。基准用摆锤专属
/// [kPendulumBaseContentSize]（同源，避免比例漂移）。
double effectiveMaxPendulumScale(Size viewport) {
  final widthCap = viewport.width / kPendulumBaseContentSize.width;
  final heightCap = viewport.height / kPendulumBaseContentSize.height;
  final viewportCap = widthCap < heightCap ? widthCap : heightCap;
  return viewportCap < kMaxPendulumScale ? viewportCap : kMaxPendulumScale;
}

/// 位置屏内钳制：内容 ≤ 视口时整体钳在视口内（右/下贴边、
/// 负偏移钳 0）；任一维贴满视口时该维左上对齐（0）。
Offset clampOverlayOffset({
  required Offset offset,
  required Size contentSize,
  required Size viewport,
}) {
  final maxDx = viewport.width - contentSize.width;
  final maxDy = viewport.height - contentSize.height;
  return Offset(
    maxDx <= 0 ? 0 : offset.dx.clamp(0.0, maxDx),
    maxDy <= 0 ? 0 : offset.dy.clamp(0.0, maxDy),
  );
}

/// 浮层这一刻的**生效几何**（偏移 + 内容尺寸）——控制器与投屏装配共用的
/// **唯一一处解析**（两处各自写一遍就是两份口径）。
///
/// - **尺寸**按形态系数解析（矩形只消费宽系数、摆锤只消费等比系数），
///   视口联动生效上限（铺满视口为止）；
/// - **偏移**取当前格的自定义值（缺席 = 未自定义 → 按视口现算的默认位：
///   贴左、纵向视口高 12%），再钳回视口内（钳制只进生效面，容器里的存值
///   一字不改）。
///
/// [viewport] 为 null（宿主未接线）时不钳、默认位回落原点——与
/// [MetronomeOverlayController] 的既有语义逐位一致。
({Offset offset, Size size}) resolveOverlayGeometry({
  required OverlayPlacements placements,
  required OverlayPlacementCell cell,
  required BeatAnimationStyle style,
  required Size? viewport,
}) {
  final size = resolveOverlaySize(
    style: style,
    rectWidthFactor: placements.rectWidthFactor,
    pendulumScale: placements.pendulumScale,
    viewport: viewport,
  );
  final raw =
      placements.offsetFor(cell) ??
      (viewport == null ? Offset.zero : defaultOverlayOffset(viewport));
  if (viewport == null) return (offset: raw, size: size);
  return (
    offset: clampOverlayOffset(
      offset: raw,
      contentSize: size,
      viewport: viewport,
    ),
    size: size,
  );
}

/// 浮层内容区的竖向容量倍率（系统字号 ≤ 1 不收缩，沿用槽位定宽的既有
/// 口径）——`MetronomeOverlay._sizedContent` 与投屏装配同读本函数。
double overlayContentHeightScale(double textScale) =>
    textScale > 1 ? textScale : 1;

/// 浮层**内容区**的尺寸：`宽 × 高·字号容量倍率`——两形态的外框同形
/// （摆锤的等比缩放发生在框内），故这一条对两形态是同一个式子。
Size overlayContentSize({required Size box, required double textScale}) => Size(
  box.width,
  box.height * overlayContentHeightScale(textScale),
);
