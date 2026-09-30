/// 轨道手柄带控制柄槽分配（**等分互斥分区**）。
///
/// 轨道带底行是**轨道手柄带**：分段线与首/尾线在此各有把手控制柄
/// （32×18dp 胶囊把手），拖动仅由控制柄起手触发。控制柄槽按**等分互斥分区**分配：
///
///   - 槽区间**互斥不重叠**：相邻线的分界 = 两线位置的中点；
///   - 每条槽目标宽 ≤ [kHandleSlotMaxWidth]（48dp，以线心居中）；
///   - 槽宽不足目标时**优先向两侧空余空间扩展**——该侧邻线远时扩到目标
///     半宽；尾线（最右一条）右侧无邻线，右界取 `min(线心 + 目标半宽,
///     带右缘)`，不越出带；
///   - **首线左界顶到带左缘**：最左一条左侧无邻线，其天然左界
///     （线心 − 目标半宽）落在内容区之左（轨道片头让位出的那一段）里时，左界
///     取带左缘——片头让位后首线站在内容区左缘，那一段因此也归它可抓；
///     首线被拖进内容区之后不再向带左缘伸手（内容区的空白横滑区不动）；
///   - 仅当左右两侧都无空余（如三条密排线的中间一条，两侧分界都落在
///     目标半宽内）才收缩到两侧中点之间；
///   - 放大后间距增大 → 分界中点越出目标半宽 → 槽恢复目标宽。
library;

import 'dart:math' as math;
import 'dart:ui' show Color, Rect;

/// 控制柄槽目标宽上限（dp）：相邻线很远时槽不再加宽；线密时槽先尝试向
/// 两侧空余扩展到该宽，实在无空才收缩。
const double kHandleSlotMaxWidth = 48;

/// 控制柄把手视觉宽（dp）：定稿 32dp 胶囊。
const double kHandleBarWidth = kHandleCapsuleWidth;

/// 控制柄把手视觉高（dp）：行高 30dp 内垂直居中的定稿高度。
const double kHandleBarHeight = kHandleCapsuleHeight;

/// 单条线的控制柄槽。
class HandleSlot {
  const HandleSlot({
    required this.center,
    required this.hitLeft,
    required this.hitRight,
  });

  /// 线心 x（槽名义中心；边缘线可越出带缘）。
  final double center;

  /// 命中区间左缘（互斥分区后落在带内）。
  final double hitLeft;

  /// 命中区间右缘（互斥分区后落在带内）。
  final double hitRight;

  double get hitWidth => hitRight - hitLeft;

  /// x 是否落在命中区内。
  bool contains(double x) => x >= hitLeft && x <= hitRight;
}

/// 等分互斥分区槽分配：[positions] 为按时间升序的各线 x（含首/尾边界线），
/// [bandWidth] 为轨道带宽，[contentLeft] 为内容区左缘（轨道片头让位后的
/// 时间轴零点屏上 x；0 = 内容区占满带宽）。返回与 [positions] 同序的槽列表。
///
/// 每条槽先取线心 ± 目标半宽（24dp）；相邻槽重叠时以两线中点为分界
/// （各让半距），线向自由一侧保住目标半宽。首线（最左一条）的天然左界落在
/// [contentLeft] 之左（片头列）里时，左界顶到带左缘；尾线
/// （最右一条）右界不越出带右缘。
List<HandleSlot> assignHandleSlots({
  required List<double> positions,
  required double bandWidth,
  required double contentLeft,
}) {
  final targetHalf = kHandleSlotMaxWidth / 2;
  return [
    for (var i = 0; i < positions.length; i++)
      _slotAt(positions, i, bandWidth, contentLeft, targetHalf),
  ];
}

HandleSlot _slotAt(
  List<double> positions,
  int i,
  double bandWidth,
  double contentLeft,
  double targetHalf,
) {
  final pos = positions[i];
  // 两侧分界：有邻线取中点；无邻线（首/尾线）贴屏幕/区间边缘向外顶满
  // 到带缘（钳在带内）。
  final leftBound = i == 0 ? 0.0 : (positions[i - 1] + pos) / 2;
  final rightBound =
      i + 1 == positions.length ? bandWidth : (pos + positions[i + 1]) / 2;
  // 槽 = 目标区间 [pos-24, pos+24] 与两侧分界围出的区间的交集：邻线远
  // （分界越出目标半宽）→ 槽保目标宽；邻线近 → 分界中点截断（互斥），
  // 槽向另一侧（或带缘）扩展补足目标，两侧都被占才收缩。
  // 首线的天然左界落在片头列里 → 左界顶到带左缘（[leftBound]），
  // 把片头让位出的那一段也纳进首线触发区；天然左界已在内容区里则不伸手。
  final left = i == 0 && pos - targetHalf <= contentLeft
      ? leftBound
      : math.max(pos - targetHalf, leftBound);
  final right = math.min(pos + targetHalf, rightBound);
  return HandleSlot(center: pos, hitLeft: left, hitRight: right);
}

/// 控制柄视觉短条的左缘 x（「缩放链路防御性 clamp」）：
/// 分段线乱序/槽区间退化（[HandleSlot.hitLeft] > [HandleSlot.hitRight]、
/// 右界 - 条宽低于下界等）时**先归一再钳制**——下界 lo = max(0, hitLeft)、
/// 上界 hi = max(lo, min(带宽, hitRight) - 条宽)——不直接 clamp（下界>
/// 上界会在 build 阶段抛 [ArgumentError] 红屏）。静默钳制、不抛错。
double handleBarLeft({
  required double barCenter,
  required double barWidth,
  required double hitLeft,
  required double hitRight,
  required double bandWidth,
}) {
  final lo = math.max(0.0, hitLeft);
  final hi = math.max(lo, math.min(bandWidth, hitRight) - barWidth);
  return (barCenter - barWidth / 2).clamp(lo, hi);
}

/// 控制柄胶囊定稿几何；[kHandleBarWidth]/[kHandleBarHeight] 即取这两个值。
const double kHandleCapsuleWidth = 32;
const double kHandleCapsuleHeight = 18;

/// 控制柄描边宽（dp）：描边画在框内 ⇒ 内容盒 = 条 − 2×描边宽。
const double kHandleStrokeWidth = 1;

/// 抓握纹最小缝（dp）：纹数递减判据 `n×纹宽 + (n+1)×缝 ≤ 内容盒宽`
/// 用的缝下限，与描边宽无关。
const double kHandleGrooveMinGap = 1;

/// 控制柄描边色（黑 40%，固定色，不随三态变）。
const Color kHandleStrokeColor = Color(0x66000000);

/// 控制柄抓握纹色（黑 45%，固定色，不随三态变）。
const Color kHandleGrooveColor = Color(0x73000000);

/// 一次 [planHandleBar] 的输出：控制柄的完整视觉计划。
class HandleBarPlan {
  const HandleBarPlan({
    required this.barWidth,
    required this.barHeight,
    required this.rowOffsetY,
    required this.cornerRadius,
    required this.strokeWidth,
    required this.grooves,
  });

  /// 条宽（dp）：`min(条宽上限, 槽宽)`，被互斥槽压窄后即此值。
  final double barWidth;

  /// 条高（dp）。
  final double barHeight;

  /// 手柄带行内条顶纵向偏移（dp）：`(行高 − 条高) / 2`，不小于 0。
  final double rowOffsetY;

  /// 圆角半径（dp）= 条高 / 2（全胶囊）。
  final double cornerRadius;

  /// 描边宽（dp）；描边关闭时为 0（内容盒 = 条本身）。
  final double strokeWidth;

  /// 抓握纹矩形，各相对**内容盒**左上角（不重复计入描边宽）；
  /// 无纹（实心胶囊）时为空。
  final List<Rect> grooves;

  /// 内容盒宽（dp）＝ 条宽 − 2×描边宽。
  double get contentWidth => barWidth - 2 * strokeWidth;

  /// 内容盒高（dp）＝ 条高 − 2×描边宽。
  double get contentHeight => barHeight - 2 * strokeWidth;

  /// 描边色（[kHandleStrokeColor]，固定）。
  Color get strokeColor => kHandleStrokeColor;

  /// 纹色（[kHandleGrooveColor]，固定）。
  Color get grooveColor => kHandleGrooveColor;
}

/// 控制柄视觉几何纯函数：给定槽宽、条宽上限、条高、行高与描边开关，输出这根
/// 控制柄长什么样（条矩形、圆角、描边、每条纹相对内容盒的矩形、
/// 行内纵向偏移）。规则：
///
///   - 条宽 = min(条宽上限, 槽宽)；圆角 = 条高/2；行内垂直居中；
///   - 描边画在框内 ⇒ 内容盒 = 条 − 2×[kHandleStrokeWidth]；描边关闭
///     时内容盒 = 条本身（两态各按自己的内容盒重算落位）；
///   - 纹宽随内容盒高分档：≥14 → 2dp、≥10 → 1.5dp、否则 1dp；
///   - 纹高与内容盒高**同奇偶**、≈ 内容盒高/2；
///   - 纹数按条宽分档：≥40 → 5、≥30 → 4、≥18 → 3、≥12 → 2、否则 0；
///     放不下（n×纹宽 + (n+1)×1dp > 内容盒宽）或纹高不足 1dp 就继续
///     减；n=0 只留实心胶囊；
///   - 等距落位：gap = (内容盒宽 − n×纹宽) / (n+1)（端距 = 内缝，
///     除不尽保留小数、绝不取整到某一侧），xᵢ = gap + i×(纹宽+gap)。
HandleBarPlan planHandleBar({
  required double slotWidth,
  required double maxBarWidth,
  required double barHeight,
  required double rowHeight,
  required bool stroked,
}) {
  final barWidth = math.min(maxBarWidth, slotWidth);
  final strokeWidth = stroked ? kHandleStrokeWidth : 0.0;
  final contentWidth = barWidth - 2 * strokeWidth;
  final contentHeight = barHeight - 2 * strokeWidth;

  // 纹高：与内容盒高同奇偶、≈ 内容盒高/2（同奇偶优先向下调）。
  var grooveHeight = (contentHeight / 2).floorToDouble();
  if (grooveHeight.toInt().isOdd != contentHeight.toInt().isOdd) {
    grooveHeight -= 1;
  }

  // 纹数：条宽分档起步，放不下就 n--。
  var n = barWidth >= 40
      ? 5
      : barWidth >= 30
          ? 4
          : barWidth >= 18
              ? 3
              : barWidth >= 12
                  ? 2
                  : 0;
  var grooveWidth = contentHeight >= 14
      ? 2.0
      : contentHeight >= 10
          ? 1.5
          : 1.0;
  while (n > 0 &&
      (grooveHeight < 1 ||
          n * grooveWidth + (n + 1) * kHandleGrooveMinGap > contentWidth)) {
    n -= 1;
  }

  final grooves = <Rect>[];
  if (n > 0) {
    final gap = (contentWidth - n * grooveWidth) / (n + 1);
    for (var i = 0; i < n; i++) {
      grooves.add(Rect.fromLTWH(
        gap + i * (grooveWidth + gap),
        (contentHeight - grooveHeight) / 2,
        grooveWidth,
        grooveHeight,
      ));
    }
  }

  return HandleBarPlan(
    barWidth: barWidth,
    barHeight: barHeight,
    rowOffsetY: math.max(0.0, (rowHeight - barHeight) / 2),
    cornerRadius: barHeight / 2,
    strokeWidth: strokeWidth,
    grooves: grooves,
  );
}

/// 绘制期设备像素对齐：等距缝
/// 除不尽（32dp 下 4.4dp）时，把 [r] 的左右缘按 [devicePixelRatio] 吸附到
/// 设备像素栅格，1× 下不出现 4/5 交替的「不匀」。只吸左右缘、不改几何
/// 计划；调用方须保证 [r] 的坐标系原点已落在设备像素栅格上（条左缘与
/// 描边宽一并吸附后，内容盒原点即在栅格上）。
Rect snapRectToDevicePixels(Rect r, double devicePixelRatio) {
  final left = (r.left * devicePixelRatio).roundToDouble() / devicePixelRatio;
  final right = (r.right * devicePixelRatio).roundToDouble() / devicePixelRatio;
  return Rect.fromLTRB(left, r.top, right, r.bottom);
}

/// 把标量 [v] 按 [devicePixelRatio] 吸附到设备像素栅格（条左缘用：
/// 条缘不落在栅格上时，纹路局部吸附仍会整体错半像素）。
double snapToDevicePixel(double v, double devicePixelRatio) =>
    (v * devicePixelRatio).roundToDouble() / devicePixelRatio;
