/// 片段浮条域：区间片段动作浮条的纯展示叶子。
///
/// 四件：锚上报块 [FragmentBubbleAnchorReporter]、宿主装配
/// [FragmentBubbleHost]、浮条本体 [FragmentActionBubble]、尾尖 painter
/// （域内私有）。域收显式依赖——锚点（上报件收的 [ValueNotifier] 槽 / 本体
/// 收的锚矩形）、内容文本、动作条目与回调、调用点给的键；视觉常量全部取自
/// 集中 token（visual_tokens.dart），域不带常量走。
///
/// 依赖方向：本域 → `dart:math`（浮条宽高按实测取 max/min）、
/// `package:flutter/material.dart`（自带的 widget 子树）、集中视觉常量
/// `visual_tokens.dart`（浮条间距/内距/尾尖尺寸，以及它从
/// `../core/hit_target.dart` 转出的 48 命中盒下限），**单向**。使用者
/// （轨道带内备注轨与练习片段轨的两处调用点）给锚块、文本与浮条内容，
/// portal 控制器与帧末显隐由 [FragmentBubbleHost] 收口；本域不碰容器句柄、
/// 不读 provider、不 import 轨道带。
///
/// 本体是纯展示件：正文与动作入口承载语义，属语义档（随系统字号）：量测
///（`measureTextExtent`）与渲染吃调用处同一 `MediaQuery.textScalerOf`，浮条宽高
/// 按缩放后的实测值算。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/text_extent.dart';
import 'visual_tokens.dart';

/// 展开浮条的锚上报块：透明占位，其渲染盒全局矩形 = 选中片段的
/// 全局矩形，帧末上报到 [anchor]；卸载（选中清除 / 片段离窗）即清锚 →
/// 根浮层子树收起浮条。文本变化（编辑器写入）经 didUpdateWidget 重报。
class FragmentBubbleAnchorReporter extends StatefulWidget {
  const FragmentBubbleAnchorReporter({
    super.key,
    required this.anchor,
    required this.text,
  });

  final ValueNotifier<({Rect rect, String text})?> anchor;

  final String text;

  @override
  State<FragmentBubbleAnchorReporter> createState() =>
      _FragmentBubbleAnchorReporterState();
}

class _FragmentBubbleAnchorReporterState
    extends State<FragmentBubbleAnchorReporter> {
  void _scheduleReport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        widget.anchor.value = (
          rect: box.localToGlobal(Offset.zero) & box.size,
          text: widget.text,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _scheduleReport();
  }

  @override
  void didUpdateWidget(FragmentBubbleAnchorReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleReport();
  }

  @override
  void dispose() {
    widget.anchor.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// 片段浮条宿主：把「锚上报块 + 根浮层 portal + 帧末 show + notifier 生命
/// 周期」的装配收成一件体——两处调用点（备注轨、练习片段轨）各给锚块、
/// 文本与浮条内容，不再各抄一遍。
///
/// [anchorRect] 是宿主所在 Stack 坐标系里的锚块矩形；[bubbleBuilder] 收锚
/// 实测矩形与文本，返回浮条本体。
class FragmentBubbleHost extends StatefulWidget {
  const FragmentBubbleHost({
    super.key,
    required this.anchorRect,
    required this.text,
    required this.bubbleBuilder,
  });

  final Rect anchorRect;

  final String text;

  final Widget Function(Rect anchorRect, String text) bubbleBuilder;

  @override
  State<FragmentBubbleHost> createState() => _FragmentBubbleHostState();
}

class _FragmentBubbleHostState extends State<FragmentBubbleHost> {
  /// 锚的全局矩形 + 文本；null = 无锚（根浮层子树收起浮条）。
  final ValueNotifier<({Rect rect, String text})?> _anchor = ValueNotifier(
    null,
  );

  final OverlayPortalController _portal = OverlayPortalController();

  @override
  void dispose() {
    _anchor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 根浮层入口的显隐同步：show/hide 不能在 build 期调用，帧末对齐。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_portal.isShowing) _portal.show();
    });
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: widget.anchorRect.left,
          top: widget.anchorRect.top,
          width: widget.anchorRect.width,
          height: widget.anchorRect.height,
          child: FragmentBubbleAnchorReporter(
            anchor: _anchor,
            text: widget.text,
          ),
        ),
        OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => ValueListenableBuilder(
            valueListenable: _anchor,
            builder: (context, anchor, _) => anchor == null
                ? const SizedBox.shrink()
                : widget.bubbleBuilder(anchor.rect, anchor.text),
          ),
        ),
      ],
    );
  }
}

/// 区间片段动作浮条（备注展开浮条与回看浮条共用）：宽度按文本
/// 实测、允许超出片段宽度，屏幕边缘钳制、超屏省略；带一枚明示的动作入口
/// （[actionLabel]）与一个小尾巴指回片段。锚定 = [anchorRect]（片段全局矩
/// 形，随窗口帧末刷新跟随）。
///
/// 正文与动作入口承载语义，属语义档（随系统字号）：量测（[measureTextExtent]）与
/// 渲染吃调用处同一 `MediaQuery.textScalerOf`，浮条宽高按缩放后的实测值算。
class FragmentActionBubble extends StatelessWidget {
  const FragmentActionBubble({
    super.key,
    required this.anchorRect,
    required this.text,
    required this.actionLabel,
    required this.onAction,
    required this.actionHitKey,
    this.bubbleKey,
    this.actionKey,
  });

  /// 片段全局矩形（浮条锚定在其上方、小尾巴指回其中心）。
  final Rect anchorRect;

  final String text;

  /// 动作入口文案（备注 = 「编辑」，回看 = 「退出回看」）。
  final String actionLabel;

  final VoidCallback onAction;

  /// 浮条本体与动作入口的键（调用点给；测试按各自语义查找）。
  final Key? bubbleKey;
  final Key? actionKey;

  /// 动作入口的透明命中盒键：入口文案盒本身
  /// 只有一行字高，命中盒在浮条内外的透明区补到下限 48 高。
  final Key actionHitKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = constraints.biggest;
        final textScaler = MediaQuery.textScalerOf(context);
        // 动作入口宽度按实测、不小于 [kNoteBubbleEditButtonWidth]：入口文案
        // 不止「编辑」一种，固定槽宽会把长文案折行并把浮条顶高（实际高度
        // 与定位算得的高度不符，小尾巴随之偏位）。
        final actionWidth = math.max(
          kNoteBubbleEditButtonWidth,
          measureTextExtent(
            actionLabel,
            kNoteBubbleEditTextStyle,
            scaler: textScaler,
            maxLines: 1,
          ).width,
        );
        final contentWidth =
            kNoteBubbleHorizontalPadding * 2 + kNoteBubbleEditGap + actionWidth;
        final maxBubbleWidth = (screenSize.width - kNoteBubbleEdgeMargin * 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        final maxTextWidth = (maxBubbleWidth - contentWidth)
            .clamp(0.0, double.infinity)
            .toDouble();
        // 文本实测（单行、不换行）：实测宽决定浮条宽——放得下全句就全显，
        // 超屏部分经 ConstrainedBox 收窄 + 省略号省略。
        final textSize = measureTextExtent(
          text,
          kNoteBubbleTextStyle,
          scaler: textScaler,
          maxLines: 1,
          maxWidth: maxTextWidth,
        );
        final textWidth = textSize.width;
        final textHeight = textSize.height;
        final bubbleWidth = math.min(maxBubbleWidth, textWidth + contentWidth);
        // 正文盒宽 = 浮条宽 − 入口区宽（浮条窄于内容时正文被省略号裁）。
        final textBoxWidth = bubbleWidth - contentWidth;
        final bubbleLeft = (anchorRect.center.dx - bubbleWidth / 2)
            .clamp(
              kNoteBubbleEdgeMargin,
              math.max(
                kNoteBubbleEdgeMargin,
                screenSize.width - kNoteBubbleEdgeMargin - bubbleWidth,
              ),
            )
            .toDouble();
        // 小尾巴水平钳进浮条内（片段贴近屏幕边缘、浮条被钳移时仍指回片
        // 段方向）。
        final tailLeft = (anchorRect.center.dx - kNoteBubbleTailWidth / 2)
            .clamp(
              bubbleLeft + kNoteBubbleTailEdgeInset,
              bubbleLeft +
                  bubbleWidth -
                  kNoteBubbleTailEdgeInset -
                  kNoteBubbleTailWidth,
            )
            .toDouble();
        // 纵向：优先放在片段上方 [kNoteBubbleGap] 处；上方放不下（片段落在
        // 最上一行）时改放**下方**——浮条不覆盖它描述的那一块：压住片段既
        // 会吞掉「点块再点取消」这类点击，也让浮条与它说明的对象打架。
        final bubbleHeight =
            textHeight + kNoteBubbleVerticalPadding * 2 + kNoteBubbleTailHeight;
        final fitsAbove = anchorRect.top - kNoteBubbleGap - bubbleHeight >= 0;
        final bubbleTop = fitsAbove
            ? anchorRect.top - kNoteBubbleGap - bubbleHeight
            : (anchorRect.bottom + kNoteBubbleGap)
                  .clamp(0.0, math.max(0.0, screenSize.height - bubbleHeight))
                  .toDouble();
        // 小尾巴：在上方时朝下指回片段；在下方时整条纵向翻转即朝上。
        final tail = CustomPaint(
          size: const Size(kNoteBubbleTailWidth, kNoteBubbleTailHeight),
          painter: _NoteBubbleTailPainter(
            leftInset: tailLeft - bubbleLeft,
            color: kNoteEditorPanelColor,
          ),
        );
        // 动作入口命中盒：文案盒只有一行字高，
        // 在其上下补透明区到下限 48 高（宽已 ≥48）；命中盒画在浮条之下，
        // 浮条上的原入口仍优先，只有溢出区由本层接。左缘与浮条 Row 同源
        // （正文盒宽 + 两侧内距 + 间距）。
        final actionLeft =
            bubbleLeft +
            kNoteBubbleHorizontalPadding +
            textBoxWidth +
            kNoteBubbleEditGap;
        final actionCenterY =
            bubbleTop + kNoteBubbleVerticalPadding + textHeight / 2;
        final actionHitHeight = math.max(kHitTargetMinSize, textHeight);
        final actionHitTop = (actionCenterY - actionHitHeight / 2)
            .clamp(0.0, math.max(0.0, screenSize.height - actionHitHeight))
            .toDouble();
        return Stack(
          children: [
            Positioned(
              left: actionLeft,
              top: actionHitTop,
              width: actionWidth,
              height: actionHitHeight,
              child: GestureDetector(
                key: actionHitKey,
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: bubbleLeft,
              top: bubbleTop,
              width: bubbleWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: bubbleKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: kNoteBubbleHorizontalPadding,
                      vertical: kNoteBubbleVerticalPadding,
                    ),
                    decoration: BoxDecoration(
                      color: kNoteEditorPanelColor,
                      borderRadius: BorderRadius.circular(
                        kNoteEditorPanelRadius,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: textBoxWidth,
                          height: textHeight,
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: kNoteBubbleTextStyle,
                          ),
                        ),
                        const SizedBox(width: kNoteBubbleEditGap),
                        GestureDetector(
                          key: actionKey,
                          behavior: HitTestBehavior.opaque,
                          onTap: onAction,
                          child: SizedBox(
                            width: actionWidth,
                            child: Text(
                              actionLabel,
                              textAlign: TextAlign.center,
                              style: kNoteBubbleEditTextStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!fitsAbove) Transform.flip(flipY: true, child: tail),
                  if (fitsAbove) tail,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 浮条小尾巴：矩形浮条下缘伸出的倒三角，水平位置由 [leftInset]
/// 指定（画布 = 尾巴最大行宽，倒三角只画在 inset 处——布局层不用再为钳
/// 移单独摆位）。
class _NoteBubbleTailPainter extends CustomPainter {
  const _NoteBubbleTailPainter({required this.leftInset, required this.color});

  final double leftInset;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(leftInset, 0)
      ..lineTo(leftInset + kNoteBubbleTailWidth, 0)
      ..lineTo(leftInset + kNoteBubbleTailWidth / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_NoteBubbleTailPainter oldDelegate) =>
      oldDelegate.leftInset != leftInset || oldDelegate.color != color;
}
