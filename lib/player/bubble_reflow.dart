/// 气泡族重排判定（**唯一来源**）：统一规则「容不下并排即改纵向堆叠」——
/// 并排所需宽在可用宽内放得下即并排，否则纵向堆叠。
///
/// 判定与设备方向无关：本件签名只吃宽度，横竖屏切换经可用宽变化自然重排，
/// 不读设备方向、不新增方向枚举。当前消费者为倍速气泡
/// （`mergedSpeedBubbleColumns`）；气泡族的并排/堆叠判定都收在此处，杜绝
/// 各处手写宽高比较。
///
/// 宽度上限、高随内容、超高滚动兜底、屏内钳位不在本件范围，全部沿用各
/// 气泡既有口径。
library;

enum BubbleReflow {
  sideBySide,

  stacked,
}

/// 气泡重排判定纯函数（[BubbleReflow] 的唯一出口；零 widget 环境直测）。
///
/// - [availableWidth]：可用宽 = 屏宽 − 气泡左右留边（气泡屏幕锚定，锚点
///   不额外裁剪可用宽）。
/// - [sideBySideWidth]：并排所需宽（气泡内容宽 + 气泡盒边距）。
///
/// 边界取「等于即并排」（`>=`）：可用宽恰等于并排所需宽时仍并排，差 1px
/// 才堆叠——沿用倍速气泡既有断点口径，不留「并排但缩一点」的中间态。
BubbleReflow bubbleReflowFor({
  required double availableWidth,
  required double sideBySideWidth,
}) => availableWidth >= sideBySideWidth
    ? BubbleReflow.sideBySide
    : BubbleReflow.stacked;
