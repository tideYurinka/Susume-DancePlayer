/// 停靠式待办条（帮助域的动手演练演出件）。
///
/// 动手演练这一形态的条子形状与触摸语义收在本文件：动作图标 + 待做勾选框 +
/// 一句话 +「N/M」+ 一排进度点 + 带底的「跳过」，末步的多个子勾以勾片排在
/// 文案下方；条身除「跳过」外不吃触摸。演练的判据与推进留在各自宿主
/// （引导宿主的编辑态上手两步、播放页的手势演练）。
library;

import 'package:flutter/material.dart';

import '../core/hit_layer.dart';
import '../core/hit_target.dart' show kHitTargetMinSize;
import 'guide_bubble_placement.dart';

/// 停靠式待办条的停靠基准（注）：安全区顶 8 逻辑像素，
/// 左右各 16 逻辑像素边距。
const double kDrillTaskBarTopInset = 8;
const double kDrillTaskBarSideInset = 16;

/// 条内容层左右内边距：透明命中层与「跳过」右缘共用这一份事实，两者不会
/// 错开（命中盒外扩见 [DrillTaskBar] 条内「跳过」命中层注释）。
const double kDrillTaskBarContentPadding = 12;

/// 做到之后在下一步之前的停留时长（动手演练列：做到当场
/// 打勾、停约 0.4 秒再推进）——勾被填上是给用户看的确认。
const Duration kDrillTaskBarAdvanceHold = Duration(milliseconds: 400);

/// 待办条上的一枚子勾（末步的点击类动作）：做对一个亮一个。
class DrillTaskSubCheck {
  const DrillTaskSubCheck({
    required this.id,
    required this.label,
    required this.done,
  });

  final String id;
  final String label;
  final bool done;
}

/// 待办条（动手演练列）：动作图标 + 待做勾选框 +
/// 一句话 +「N/M」+ 一排进度点 + 带底的「跳过」；末步的多个子勾以勾片排在
/// 文案下方。
///
/// 两种落位：[anchorRect] 为 null（该步不声明锚点，或
/// 只剩驻留的历史矩形）时停靠安全区顶；锚点当前在屏上在场时贴着它的那圈
/// 高亮框放——[anchorRect] 就是**画出来的**高亮框矩形，一根箭头指框中心，
/// 框中心在屏幕上半放框下方、在下半放框上方，水平以框中心为中心并钳进屏内，
/// 条子与框永不相交。
///
/// 条身除「跳过」外一整条不吃触摸：底、图标、勾选框、文案、步数、进度点、
/// 子勾片全部包 [IgnorePointer]，只有「跳过」是真命中件——手势照常落到画在
/// 其下的画面上（画面中心与右下角入口都不受影响）。
class DrillTaskBar extends StatelessWidget {
  const DrillTaskBar({
    super.key,
    required this.icon,
    required this.message,
    required this.stepCount,
    required this.currentStep,
    required this.checked,
    required this.skipLabel,
    required this.onSkip,
    this.stepIndicator,
    this.subChecks = const [],
    this.anchorRect,
  });

  final IconData icon;

  final String message;

  /// 单元步数（进度点的枚数）。
  final int stepCount;

  /// 当前是第几步（0 起；进度点按它点亮）。
  final int currentStep;

  /// 本步是否刚刚做到（做到即填勾，停留期间保持填上）。
  final bool checked;

  /// 「跳过」：整单元一次收场。
  final VoidCallback onSkip;

  /// 「跳过」钮的文案（随包文案 `ui.skip`）。
  final String skipLabel;

  /// 「N/M」步数指示；单元剩不足两步时为空、不显示（就地讲解单步只有 ✕）。
  final String? stepIndicator;

  /// 末步的子勾片（其余步为空）。
  final List<DrillTaskSubCheck> subChecks;

  /// 贴框基准：**画出来的**高亮框矩形（含 24 逻辑像素最小短边）。
  /// null = 停靠安全区顶。
  final Rect? anchorRect;

  @override
  Widget build(BuildContext context) {
    final anchorRect = this.anchorRect;
    if (anchorRect == null) {
      // 停靠：宿主整层是 Positioned.fill（两轴都紧）：条子只按内容高、贴
      // 安全区顶，不随宿主拉满整屏。
      return SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(
              top: kDrillTaskBarTopInset,
              left: kDrillTaskBarSideInset,
              right: kDrillTaskBarSideInset,
            ),
            child: SizedBox(width: double.infinity, child: _bar(context)),
          ),
        ),
      );
    }
    // 贴框：条块（箭头 + 条子）的坐标取自唯一一份布点派生（「放置派生收成
    // 一份纯函数」），与就地讲解气泡同一套朝向、钳位与间距。
    final placement = placeGuideBubble(
      anchorRect: anchorRect,
      screen: MediaQuery.sizeOf(context),
      maxWidth: guideBubbleMaxWidth,
    );
    final below = placement.below;
    return Positioned(
      left: placement.left,
      top: placement.top,
      bottom: placement.bottom,
      width: placement.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (below)
            Padding(
              padding: EdgeInsets.only(left: placement.arrowLeft),
              child: const _DrillBarArrow(GuideArrowDirection.up),
            ),
          _bar(context),
          if (!below)
            Padding(
              padding: EdgeInsets.only(left: placement.arrowLeft),
              child: const _DrillBarArrow(GuideArrowDirection.down),
            ),
        ],
      ),
    );
  }

  /// 条子本体（条底、48 命中层与内容）：停靠与贴框两种落位共用同一件。
  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        // 条子底：只画不参与命中（整条不吃触摸）。
        Positioned.fill(
          child: IgnorePointer(
            child: Material(
              key: const Key('drill_task_bar'),
              color: theme.colorScheme.surface,
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        // 「跳过」的透明命中层（「命中盒：唯一声明与外扩」）：按钮本身做成
        // 48 会撑高整条、改变观感，故
        // 在同一 Stack 内叠一枚右缘与按钮对齐的 48×48 透明命中层，视觉
        // 件与条高逐位不变。层先画、内容后画——按钮自身命中优先；层只
        // 覆盖按钮右侧与下方（下方是 IgnorePointer 的进度点），不抢走
        // 条身其它位置穿透到画面的手势。
        Positioned(
          top: 0,
          right: kDrillTaskBarContentPadding,
          width: kHitTargetMinSize,
          height: kHitTargetMinSize,
          // 语义由带「跳过」文字的按钮承担，本层只补命中域。
          child: HitTargetLayer(
            key: const Key('drill_task_skip_hit'),
            semantics: false,
            onActivate: onSkip,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kDrillTaskBarContentPadding,
            vertical: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IgnorePointer(
                    child: Icon(
                      icon,
                      key: const Key('drill_task_icon'),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IgnorePointer(
                    child: Icon(
                      checked ? Icons.check_box : Icons.check_box_outline_blank,
                      key: const Key('drill_task_checkbox'),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: IgnorePointer(
                      child: Text(message, style: theme.textTheme.bodyMedium),
                    ),
                  ),
                  if (stepIndicator != null)
                    IgnorePointer(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          stepIndicator!,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: const Key('drill_task_skip'),
                    onPressed: onSkip,
                    style: TextButton.styleFrom(
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                    ),
                    child: Text(skipLabel, style: theme.textTheme.labelMedium),
                  ),
                ],
              ),
              if (subChecks.isNotEmpty)
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final sub in subChecks)
                          _SubCheckChip(
                            key: Key('drill_task_sub_${sub.id}'),
                            sub: sub,
                          ),
                      ],
                    ),
                  ),
                ),
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ProgressDots(count: stepCount, current: currentStep),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 贴框待办条指向高亮框的小三角：形状与尺寸取共用的 [GuideArrowPainter]，
/// 色取条子面（与条子连成一体）。整条不吃触摸——箭头也包 [IgnorePointer]：
/// `CustomPaint` 默认在自身范围内命中（`hitTestSelf` 为 true），不包就会在
/// 那 20×10 的小块里拦下本该落到画面/段体上的手势。
class _DrillBarArrow extends StatelessWidget {
  const _DrillBarArrow(this.direction);

  final GuideArrowDirection direction;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        key: const Key('drill_task_arrow'),
        size: const Size(guideArrowWidth, guideArrowHeight),
        painter: GuideArrowPainter(
          direction,
          Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

/// 一排进度点：已走过的点与当前点填亮，其余空心。
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      key: const Key('drill_task_dots'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            key: Key('drill_task_dot_$i'),
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current ? scheme.primary : scheme.outlineVariant,
            ),
          ),
      ],
    );
  }
}

/// 一枚子勾片：做对一个亮一个。
class _SubCheckChip extends StatelessWidget {
  const _SubCheckChip({super.key, required this.sub});

  final DrillTaskSubCheck sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          sub.done ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 14,
          color: sub.done
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: 2),
        Text(sub.label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
