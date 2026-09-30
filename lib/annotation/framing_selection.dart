/// 取景选区纯域件：取景的取值形状
/// ——**取景选区**（源画面上圈出的矩形，四边按**源画面原相**归一化、恒落在
/// 整帧之内、边不小于**最小边**）——以及它的全部纯规则：「选区 + 本态几何 →
/// 显示变换」的 contain 派生、**唯一一条**「四边硬钳在整帧内 + 最小边」的
/// 钳制（建框／整体平移／控制点三条拖动路径共用）、逐轴自适应控制点命中、
/// 建框是否成框、单指拖动会话的基准规则。取景只有源画面一份、只剩这一条
/// 数学。
///
/// 零 Flutter 依赖（不 import widget 层、不引 dart:ui），几何一律用调用方
/// 换算好的双精度像素/归一化数。归一化参照系是**源画面原相**——[0, 1] 即整
/// 帧，与路径、容器、屏面无关；取值不存在（`null`）即**未调过 = 整帧**。
library;

import 'dart:math' as math;

/// 最小边的屏幕尺度下限（逻辑像素 = dp）：选区宽高按画面坐标系换算后不得
/// 小于该值，保证取景控制点不互相叠在一起、始终抓得住。
const double kFramingSelectionMinEdgeDp = 24.0;

/// 「选区 + 本态几何 → 显示变换」的结果：等比缩放 + 平移（渲染层按「平移 ∘
/// 绕可用区中心缩放」应用；镜像不在取景内，故只有一个等比缩放）。
class FramingSelectionTransform {
  const FramingSelectionTransform({
    required this.scale,
    required this.translateX,
    required this.translateY,
  });

  /// 无变换：画面按 contain 基座原样显示。
  const FramingSelectionTransform.identity()
      : scale = 1,
        translateX = 0,
        translateY = 0;

  /// 等比缩放（1 = 画面 contain 基座本身）。
  final double scale;

  /// X 轴平移（像素，屏幕方向）。
  final double translateX;

  /// Y 轴平移（像素，屏幕方向）。
  final double translateY;

  @override
  bool operator ==(Object other) =>
      other is FramingSelectionTransform &&
      other.scale == scale &&
      other.translateX == translateX &&
      other.translateY == translateY;

  @override
  int get hashCode => Object.hash(scale, translateX, translateY);

  @override
  String toString() =>
      'FramingSelectionTransform(s=$scale, t=($translateX, $translateY))';
}

/// 源画面的**取景选区**（不可变值对象，词条）：源画面上被
/// 圈中的矩形区域，四边按**源画面原相**归一化（1 = 整帧）。取值不存在
/// （`null`）= **未调过**（显示整帧、取景态内不画框）；**复位 = 清除取值**。
///
/// 合法域：恒落在 `[0, 1]`、宽高不小于**最小边**（屏幕 24dp 在画面坐标系里
/// 的等效量）。写侧只写合法值——三个拖动入口（[framingSelectionFromDiagonal]
/// / [framingSelectionTranslated] / [framingSelectionResized]）即钳。
class FramingSelection {
  const FramingSelection({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// 整帧选区 `[0, 1]`：未调过的显示等价物（但作为已存值在取景态里画框）。
  const FramingSelection.fullFrame()
      : left = 0.0,
        top = 0.0,
        right = 1.0,
        bottom = 1.0;

  /// 左缘（源画面归一化）。
  final double left;

  final double top;

  final double right;

  final double bottom;

  double get width => right - left;

  double get height => bottom - top;

  double get centerX => (left + right) / 2;

  double get centerY => (top + bottom) / 2;

  /// 选区**内容**的宽高比（宽/高）：四边按源画面原相归一化，故内容像素比 =
  /// 归一化宽高比 × [sourceAspectRatio]。落位判定与
  /// 显示变换之外的下游读数都由它承载「选区里那一块当成重新导入的视频」。
  double contentAspectRatio(double sourceAspectRatio) =>
      (width / height) * sourceAspectRatio;

  @override
  bool operator ==(Object other) =>
      other is FramingSelection &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'FramingSelection($left, $top, $right, $bottom)';
}

/// 八个**取景控制点**：四角同时调两轴、四边中点只调那一条边。
enum FramingSelectionHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

/// 控制点的结构事实：**四角**同时调两轴、四边中点只调那一条边。`角点 / 边中点`
/// 这个二分类只此一处声明，渲染与命中判定读它，不在枚举之外各自再列一遍名单。
extension FramingSelectionHandleFacts on FramingSelectionHandle {
  /// 是否角点（四角之一）。
  bool get isCorner => switch (this) {
    FramingSelectionHandle.topLeft ||
    FramingSelectionHandle.topRight ||
    FramingSelectionHandle.bottomRight ||
    FramingSelectionHandle.bottomLeft => true,
    FramingSelectionHandle.top ||
    FramingSelectionHandle.right ||
    FramingSelectionHandle.bottom ||
    FramingSelectionHandle.left => false,
  };
}

/// 最小边 = 屏幕 24dp 按画面 contain 尺寸换算到画面坐标系（取画面较短边，
/// 保证两轴在屏幕上都不小于 24dp）。画面尺寸非正（不可映射）时安静降级为
/// 0（无约束）。
double framingSelectionMinEdge({
  required double pictureWidth,
  required double pictureHeight,
}) {
  final shorter = math.min(pictureWidth, pictureHeight);
  if (shorter <= 0) return 0;
  return kFramingSelectionMinEdgeDp / shorter;
}

/// 本态几何：可用区（裁切边界）、源画面宽高比（`null` = 未知，相机预览与
/// 未就绪占位）与竖屏编辑态的贴底分支。
class FramingSelectionGeometry {
  const FramingSelectionGeometry({
    required this.availableWidth,
    required this.availableHeight,
    required this.aspectRatio,
    this.sticksToBottom = false,
  });

  final double availableWidth;

  final double availableHeight;

  /// 源画面宽高比（`null` / `<= 0` = 未知：画面即容器、无变换）。
  final double? aspectRatio;

  /// 竖屏编辑态贴底分支：纵向把选区下缘对到可用区下缘。
  final bool sticksToBottom;

  /// 宽高比是否已知（未知时派生安静降级为无变换）。
  bool get aspectKnown => aspectRatio != null && aspectRatio! > 0;

  /// 源画面在该可用区里 contain 后的宽（宽高比未知时即可用区宽）。
  double get pictureWidth => aspectKnown
      ? math.min(availableWidth, availableHeight * aspectRatio!)
      : availableWidth;

  /// 源画面在该可用区里 contain 后的高。
  double get pictureHeight => aspectKnown
      ? math.min(availableHeight, availableWidth / aspectRatio!)
      : availableHeight;

  /// 该路径的最小边（随可用区尺寸而变）。
  double get minEdge => framingSelectionMinEdge(
    pictureWidth: pictureWidth,
    pictureHeight: pictureHeight,
  );
}

double _clamp01(double value) {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

/// 一条轴的最小边约束：跨度过小时保住**未被拖动的边**、把被拖的那条边停在
/// 最小边处；贴到整帧缘而放不下时另一条边也一并让位。该轴没有边被拖动时
/// （边中点控制点的另一轴）保持原值——已存值不在拖动当期被强撑。
(double, double) _enforceMinEdge({
  required double lo,
  required double hi,
  required double minEdge,
  required bool loDragged,
  required bool hiDragged,
}) {
  final edge = minEdge.clamp(0.0, 1.0);
  if (hi - lo >= edge) return (lo, hi);
  if (hiDragged && !loDragged) {
    final anchored = lo + edge;
    return anchored > 1 ? (1 - edge, 1.0) : (lo, anchored);
  }
  if (loDragged && !hiDragged) {
    final anchored = hi - edge;
    return anchored < 0 ? (0.0, edge) : (anchored, hi);
  }
  return (lo, hi);
}

/// 该轴上被拖动的边；`handle` 为空（整体平移/建框）时不给单边信息。
(bool, bool) _draggedXEdges(FramingSelectionHandle? handle) => switch (handle) {
  FramingSelectionHandle.topLeft ||
  FramingSelectionHandle.bottomLeft ||
  FramingSelectionHandle.left => (true, false),
  FramingSelectionHandle.topRight ||
  FramingSelectionHandle.bottomRight ||
  FramingSelectionHandle.right => (false, true),
  _ => (false, false),
};

(bool, bool) _draggedYEdges(FramingSelectionHandle? handle) => switch (handle) {
  FramingSelectionHandle.topLeft ||
  FramingSelectionHandle.topRight ||
  FramingSelectionHandle.top => (true, false),
  FramingSelectionHandle.bottomLeft ||
  FramingSelectionHandle.bottomRight ||
  FramingSelectionHandle.bottom => (false, true),
  _ => (false, false),
};

/// 取景选区的文件形状读取兜底（公开标记文件 `meta` 段）：四边齐全、皆为有限
/// 数值、落在整帧 `[0, 1]` 内且宽高为正才收；任一不满足即按**未调过**
/// （`null`）兜底。写侧只写合法值，读到的越界或退化形状只可能来自手改或损坏
/// 文件。最小边是**按路径几何换算**的量，不在
/// 这一层判——已存值照常显示。
FramingSelection? framingSelectionFromJson(Object? raw) {
  if (raw is! Map) return null;
  final left = raw['left'];
  final top = raw['top'];
  final right = raw['right'];
  final bottom = raw['bottom'];
  if (left is! num || top is! num || right is! num || bottom is! num) {
    return null;
  }
  final l = left.toDouble();
  final t = top.toDouble();
  final r = right.toDouble();
  final b = bottom.toDouble();
  if (!l.isFinite || !t.isFinite || !r.isFinite || !b.isFinite) return null;
  if (l < 0 || t < 0 || r > 1 || b > 1) return null;
  if (r <= l || b <= t) return null;
  return FramingSelection(left: l, top: t, right: r, bottom: b);
}

/// 取景选区 → 文件形状（选区四边）；未调过（`null`）由调用侧省键。
Map<String, Object?> framingSelectionToJson(FramingSelection selection) => {
  'left': selection.left,
  'top': selection.top,
  'right': selection.right,
  'bottom': selection.bottom,
};

/// 选区在给定**画面矩形**（屏幕坐标）内占的矩形四边：四边按画面矩形的宽高
/// 线性映射。渲染覆盖层与命中判定共用这一处映射，不在渲染件里重写归一化。
({double left, double top, double right, double bottom})
framingSelectionRectOnPicture({
  required FramingSelection selection,
  required double pictureLeft,
  required double pictureTop,
  required double pictureWidth,
  required double pictureHeight,
}) => (
  left: pictureLeft + selection.left * pictureWidth,
  top: pictureTop + selection.top * pictureHeight,
  right: pictureLeft + selection.right * pictureWidth,
  bottom: pictureTop + selection.bottom * pictureHeight,
);

/// 建框是否成框：松手时的取景选区不小于最小边才成框，否则保留手势前状态
/// （不留下一个垃圾框）。
bool isFramingSelectionLargeEnough({
  required FramingSelection selection,
  required double minEdge,
}) => selection.width >= minEdge && selection.height >= minEdge;

/// 八个**取景控制点**在画面矩形（屏幕坐标）里的中心点：四角取选区四角、四边
/// 中点取四边中点。渲染覆盖层与命中判定共用这一处映射，不在渲染件里重写。
/// 顺序即命中优先级：四角在前、四边中点在后。
List<({FramingSelectionHandle handle, double x, double y})>
framingSelectionHandleCenters({
  required FramingSelection selection,
  required double pictureLeft,
  required double pictureTop,
  required double pictureWidth,
  required double pictureHeight,
}) => _handleCentersInRect(
  framingSelectionRectOnPicture(
    selection: selection,
    pictureLeft: pictureLeft,
    pictureTop: pictureTop,
    pictureWidth: pictureWidth,
    pictureHeight: pictureHeight,
  ),
);

/// 控制点在已映射好的选区矩形里的中心点（本文件内唯一一处列八个点的名单）。
List<({FramingSelectionHandle handle, double x, double y})> _handleCentersInRect(
  ({double left, double top, double right, double bottom}) rect,
) {
  final midX = (rect.left + rect.right) / 2;
  final midY = (rect.top + rect.bottom) / 2;
  return [
    (handle: FramingSelectionHandle.topLeft, x: rect.left, y: rect.top),
    (handle: FramingSelectionHandle.topRight, x: rect.right, y: rect.top),
    (handle: FramingSelectionHandle.bottomRight, x: rect.right, y: rect.bottom),
    (handle: FramingSelectionHandle.bottomLeft, x: rect.left, y: rect.bottom),
    (handle: FramingSelectionHandle.top, x: midX, y: rect.top),
    (handle: FramingSelectionHandle.right, x: rect.right, y: midY),
    (handle: FramingSelectionHandle.bottom, x: midX, y: rect.bottom),
    (handle: FramingSelectionHandle.left, x: rect.left, y: midY),
  ];
}

/// 落点命中的**取景控制点**：命中盒中心即控制点、**逐轴**取
/// `min([maxHitSize], 该轴框长 ÷ 2)`（命中盒下限 [maxHitSize] 由
/// 调用侧传屏幕 48dp），无命中返回 `null`。逐轴自适应让框中央**恒留一条不
/// 小于半框长的空带**——短边小于 96dp 的框上「框内拖 = 整体平移」依然点得
/// 到。四角先于四边中点（两者在短框上相触，取更「强」的那一个）。
FramingSelectionHandle? framingSelectionHandleAt({
  required FramingSelection selection,
  required double pictureLeft,
  required double pictureTop,
  required double pictureWidth,
  required double pictureHeight,
  required double x,
  required double y,
  required double maxHitSize,
}) {
  final rect = framingSelectionRectOnPicture(
    selection: selection,
    pictureLeft: pictureLeft,
    pictureTop: pictureTop,
    pictureWidth: pictureWidth,
    pictureHeight: pictureHeight,
  );
  final halfX = math.min(maxHitSize, (rect.right - rect.left) / 2) / 2;
  final halfY = math.min(maxHitSize, (rect.bottom - rect.top) / 2) / 2;
  for (final center in _handleCentersInRect(rect)) {
    if ((x - center.x).abs() <= halfX && (y - center.y).abs() <= halfY) {
      return center.handle;
    }
  }
  return null;
}

/// **四边硬钳在整帧内 + 最小边**的**唯一**钳制算式（私有一处）：[raw] 四边
/// 由三条拖动路径各自的公开入口（[framingSelectionFromDiagonal] /
/// [framingSelectionTranslated] / [framingSelectionResized]）造出后喂进来，
/// 全仓不出现第二份钳制算术。
///
/// - `base` 与 `handle` 皆空 = **建框**：四边钳回 `[0, 1]`，不撑最小边——
///   是否成框由 [isFramingSelectionLargeEnough] 判；
/// - `handle` 空、`base` 非空 = **整体平移**：框作为整体刚性移动，贴到整帧
///   缘即停、往回拖即随手指回缩，尺寸不变（无越界量、无尺寸记忆）；
/// - `handle` 非空 = **控制点**：只动被拖的那条边，宽或高不足最小边时被拖的
///   边让位、另一条边不动。
FramingSelection _resolveFramingSelection({
  required ({double left, double top, double right, double bottom}) raw,
  required double minEdge,
  FramingSelection? base,
  FramingSelectionHandle? handle,
}) {
  if (handle == null && base != null) {
    // 整体平移：四边同加位移，位移钳在「整帧装得下框」的范围内——贴到边即
    // 停、往回拖即随手指回缩，尺寸原样。
    final dx = (raw.left - base.left).clamp(-base.left, 1 - base.right);
    final dy = (raw.top - base.top).clamp(-base.top, 1 - base.bottom);
    return FramingSelection(
      left: base.left + dx,
      top: base.top + dy,
      right: base.right + dx,
      bottom: base.bottom + dy,
    );
  }
  var left = _clamp01(raw.left);
  var right = _clamp01(raw.right);
  var top = _clamp01(raw.top);
  var bottom = _clamp01(raw.bottom);
  if (handle != null) {
    final (xLoDragged, xHiDragged) = _draggedXEdges(handle);
    final (yLoDragged, yHiDragged) = _draggedYEdges(handle);
    (left, right) = _enforceMinEdge(
      lo: left,
      hi: right,
      minEdge: minEdge,
      loDragged: xLoDragged,
      hiDragged: xHiDragged,
    );
    (top, bottom) = _enforceMinEdge(
      lo: top,
      hi: bottom,
      minEdge: minEdge,
      loDragged: yLoDragged,
      hiDragged: yHiDragged,
    );
  }
  return FramingSelection(left: left, top: top, right: right, bottom: bottom);
}

/// **建框**：起手点与当帧点围成的对角矩形，四边硬钳回整帧（**不撑**最小边
/// ——是否成框由 [isFramingSelectionLargeEnough] 判，免得误触留下垃圾框）。
FramingSelection framingSelectionFromDiagonal({
  required double x0,
  required double y0,
  required double x1,
  required double y1,
}) => _resolveFramingSelection(
  raw: (
    left: math.min(x0, x1),
    top: math.min(y0, y1),
    right: math.max(x0, x1),
    bottom: math.max(y0, y1),
  ),
  minEdge: 0,
);

/// **整体平移**：四边同加位移，位移钳在「整帧装得下框」的范围内——贴到边
/// 即停、往回拖即随手指回缩，尺寸原样（无越界量、无尺寸记忆）。
FramingSelection framingSelectionTranslated({
  required FramingSelection base,
  required double dx,
  required double dy,
  required double minEdge,
}) => _resolveFramingSelection(
  raw: (
    left: base.left + dx,
    top: base.top + dy,
    right: base.right + dx,
    bottom: base.bottom + dy,
  ),
  minEdge: minEdge,
  base: base,
);

/// **控制点**：四角同时调两轴、四边中点只调那一条边；宽或高不足最小边时被
/// 拖的边让位、另一条边不动。handle → 被拖的边只有 [_draggedXEdges] /
/// [_draggedYEdges] 一处声明，钳制锚定读同一份。
FramingSelection framingSelectionResized({
  required FramingSelection base,
  required FramingSelectionHandle handle,
  required double dx,
  required double dy,
  required double minEdge,
}) {
  final (xLo, xHi) = _draggedXEdges(handle);
  final (yLo, yHi) = _draggedYEdges(handle);
  return _resolveFramingSelection(
    raw: (
      left: base.left + (xLo ? dx : 0),
      top: base.top + (yLo ? dy : 0),
      right: base.right + (xHi ? dx : 0),
      bottom: base.bottom + (yHi ? dy : 0),
    ),
    minEdge: minEdge,
    base: base,
    handle: handle,
  );
}

/// 「选区 + 本态几何 → 显示变换」的纯派生（contain：缩放在可用区内
/// 最大且不变形；平移把选区中心对到可用区中心；竖屏编辑态贴底分支纵向把
/// 选区下缘对到可用区下缘）。
///
/// `selection` 为 `null` = 未调过 = 整帧，派生出该路径的 contain 基座本身。
/// 画面宽高比未知（画面即容器）或几何尺寸非正时安静降级为**无变换**，不报
/// 错。
FramingSelectionTransform framingSelectionTransform({
  required FramingSelection? selection,
  required FramingSelectionGeometry geometry,
}) {
  const identity = FramingSelectionTransform.identity();
  if (!geometry.aspectKnown) return identity;
  final availableWidth = geometry.availableWidth;
  final availableHeight = geometry.availableHeight;
  final pictureWidth = geometry.pictureWidth;
  final pictureHeight = geometry.pictureHeight;
  if (availableWidth <= 0 ||
      availableHeight <= 0 ||
      pictureWidth <= 0 ||
      pictureHeight <= 0) {
    return identity;
  }
  final resolved = selection ?? const FramingSelection.fullFrame();
  final contentWidth = resolved.width * pictureWidth;
  final contentHeight = resolved.height * pictureHeight;
  if (contentWidth <= 0 || contentHeight <= 0) return identity;
  final scale = math.min(
    availableWidth / contentWidth,
    availableHeight / contentHeight,
  );
  final translateX = scale * pictureWidth * (0.5 - resolved.centerX);
  final translateY = geometry.sticksToBottom
      ? availableHeight / 2 - scale * pictureHeight * (resolved.bottom - 0.5)
      : scale * pictureHeight * (0.5 - resolved.centerY);
  return FramingSelectionTransform(
    scale: scale,
    translateX: translateX,
    translateY: translateY,
  );
}

/// 单指拖动会话（不可变值对象）：当前手指数 + **基准选区** + 基准焦点。
/// **逐手势态**（一次 burst 内有效，抬手即弃）；取值按「基准 + 当帧位移」
/// 绝对式求值，何时取/何时重设由 [resolveFramingSelectionGestureSession]
/// 这条纯规则决定。
class FramingSelectionGestureSession {
  const FramingSelectionGestureSession({
    required this.pointerCount,
    required this.base,
    required this.focalX,
    required this.focalY,
  });

  final int pointerCount;

  /// 基准选区 = 起手时的已提交选区（未调过时为 `null`）。
  final FramingSelection? base;

  /// 基准焦点 X（像素，屏幕方向）。
  final double focalX;

  /// 基准焦点 Y（像素，屏幕方向）。
  final double focalY;

  @override
  bool operator ==(Object other) =>
      other is FramingSelectionGestureSession &&
      other.pointerCount == pointerCount &&
      other.base == base &&
      other.focalX == focalX &&
      other.focalY == focalY;

  @override
  int get hashCode => Object.hash(pointerCount, base, focalX, focalY);

  @override
  String toString() =>
      'FramingSelectionGestureSession($pointerCount, $base, $focalX, $focalY)';
}

/// 单指拖动会话的**基准规则**（纯件，无 IO、无 widget 环境）：
///
/// ① **起手取基准**：尚无会话 → 基准 = 已提交选区、焦点 = 落点；
/// ② **重设基准**：识别器重启（[recognizerRestarted]）**或**手指数变化 →
///    基准 = 已提交选区、焦点 = 当前焦点、手指数 = 当前手指数；
/// ③ 既非起手也非重设（普通更新帧）原样返回 [current]。
FramingSelectionGestureSession resolveFramingSelectionGestureSession({
  required FramingSelectionGestureSession? current,
  required FramingSelection? committed,
  required double focalX,
  required double focalY,
  required int pointerCount,
  required bool recognizerRestarted,
}) {
  if (current == null ||
      recognizerRestarted ||
      current.pointerCount != pointerCount) {
    return FramingSelectionGestureSession(
      pointerCount: pointerCount,
      base: committed,
      focalX: focalX,
      focalY: focalY,
    );
  }
  return current;
}
