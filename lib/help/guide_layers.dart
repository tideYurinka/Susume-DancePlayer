/// 引导覆层件：四形态（动手演练 / 一次性图文 / 就地讲解）的渲染件、锚点高亮
/// 与遮罩绘制。
///
/// 只画与算几何；状态迁移由宿主给出的回调驱动。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_registry.dart';
import 'drill_task_bar.dart';
import 'guide_bubble_placement.dart';
import 'guide_copy.dart';
import 'guide_state.dart';
import 'help_document_page.dart';
import 'help_documents.dart';
import 'help_markdown.dart';
import 'help_markdown_body.dart';
import 'help_root_navigator.dart';

/// 一次性图文：不锚定的模态卡片——自带暗背景、只有
/// 卡片自己的按钮可点、点外面关不掉。按钮取值记入首启分支并推进本步。
///
/// 卡里的跨节锚点与跨条目链接都从这里打开正文页：**只压一条路由，不消耗这
/// 一步**——首页被压住时卡随「当前表面」机制撤下（锚点不在当前表面即撤下），
/// 返回后原样回来，仍等那两个按钮之一；滚到位之外不做别的动作。
void _openFullDocument(
  BuildContext context,
  String documentId,
  String? anchor,
) {
  helpRootNavigatorState()?.push(
    MaterialPageRoute<void>(
      builder: (_) =>
          HelpDocumentPage(documentId: documentId, initialAnchor: anchor),
    ),
  );
}

class OneShotGuideLayer extends ConsumerWidget {
  const OneShotGuideLayer({
    super.key,
    required this.step,
    required this.copy,
    required this.onAction,
  });

  final GuideStep step;
  final GuideStepCopy copy;

  /// 卡片按钮的一次出口动作：记下首启分支并推进本步（由宿主给）。
  final Future<void> Function(FirstRunChoice) onAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 内容取自装载结果（与帮助中心「教程 → 下载视频」同一条目同源）：正文
    // 只给第一个二级标题那一节——那个小节标题、提示块、步骤与截图都在；
    // 引言段与其后的方法不出现。一个二级标题都没有时正文为空（只剩卡头与
    // 两个出口按钮）。
    final sourceDocumentId = step.sourceDocumentId;
    final content = sourceDocumentId == null
        ? null
        : loadedHelpDocument(ref, sourceDocumentId);
    final section =
        content?.firstSectionSegments ?? const <HelpMarkdownSegment>[];
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black54,
      child: Listener(
        // 吞掉卡片外的一切点击：关不掉，也不让底下界面收到。用 [Listener]
        // 而不是带 onTap 的 GestureDetector——底板不声明任何手势，就不会在
        // 无障碍树里留下一个无名可点节点。
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {},
        child: Center(
          // 一次性图文是一次性的模态出口：整个卡声明为一条路由（对话框），
          // 读屏用户进卡就是进了一个独立界面区域（与自建菜单同口径）。
          child: Semantics(
            role: SemanticsRole.dialog,
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            child: Material(
              key: const Key('guide_one_shot'),
              color: theme.colorScheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                // maxHeight：卡高有上限——内容
                // 超高时正文区内部滚动，出口按钮（`cardChoices`）在滚动区
                // 之外、始终在屏上。上下各留 24 屏边。
                constraints: BoxConstraints(
                  maxWidth: 320,
                  maxHeight: MediaQuery.sizeOf(context).height - 48,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                content?.title ?? copy.title ?? copy.message,
                                key: const Key('guide_one_shot_title'),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 12),
                              if (section.isNotEmpty)
                                HelpMarkdownBody(
                                  document: content!,
                                  segments: section,
                                  compact: true,
                                  padding: EdgeInsets.zero,
                                  onOpenDocumentAnchor: sourceDocumentId == null
                                      ? null
                                      : (anchor) => _openFullDocument(
                                          context,
                                          sourceDocumentId,
                                          anchor,
                                        ),
                                  // 跨条目链接与「打开完整正文」走同一条通路：
                                  // 推入目标条目的文档页，返回回到这张卡。
                                  onOpenEntry: (link) => _openFullDocument(
                                    context,
                                    link.documentId,
                                    link.anchor,
                                  ),
                                )
                              else if (content == null)
                                for (final line in copy.message.split(
                                  '\n',
                                )) ...[Text(line), const SizedBox(height: 4)],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 撑满卡片内宽再右对齐：`Wrap` 在松约束下会收缩到内容
                      // 宽，单靠 [WrapAlignment.end] 排不到右边。窄屏大字号
                      // 放不下时换行，不横向溢出（320 宽 + 2.0 倍字号）。
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.end,
                          runSpacing: 4,
                          children: [
                            // 按钮与分支按**取值**配对：文案从随包文件按分支取，
                            // 作者调整文件里的先后顺序不会错位。
                            for (final choice in step.cardChoices)
                              if (copy.cardActionLabels[choice]
                                  case final label?)
                                TextButton(
                                  key: Key(
                                    'guide_one_shot_action_${choice.name}',
                                  ),
                                  onPressed: () => onAction(choice),
                                  child: Text(label),
                                ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 就地讲解的高亮框与洞的**最小边长**（与
/// 学习段命中区的兜底同数）：细到 1px 的线也看得见、也点得着。
const double guideHoleMinSize = 24;

/// 高亮框与洞共用的外扩（描边、遮罩挖透、按下判定同一矩形同一外扩）。
const double guideHoleInflate = 2;

/// 短暂提示的停留时长（约 4 秒自散）。
const Duration kGuideTransientHintHold = Duration(seconds: 4);

/// 短暂提示浮层（列）：贴在被指控件**左侧、与它同高**的
/// 一句话小浮层——浅底深字（与引导其它卡片同一族的浅色面 + 圆角 + 投影，
/// 在深色输入条上一眼分得开）、宽钳在锚点左侧可用空间内、最多两行；不压暗、
/// 整层 [IgnorePointer]（什么都不挡）、无任何控件——到点由宿主撤下。
class GuideTransientHint extends StatelessWidget {
  const GuideTransientHint({
    super.key,
    required this.message,
    required this.anchorRect,
  });

  final String message;
  final Rect anchorRect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _TransientHintLayout(anchorRect: anchorRect),
          child: Material(
            key: const Key('guide_transient_hint'),
            color: theme.colorScheme.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 短暂提示的贴位：宽度钳在锚点**左侧**的可用空间内（屏幕左缘留 [edge]、
/// 与锚点之间留 [gap]），竖向上与锚点同高，并整体钳回屏内。
class _TransientHintLayout extends SingleChildLayoutDelegate {
  const _TransientHintLayout({required this.anchorRect});

  final Rect anchorRect;

  /// 浮层与锚点之间的间距。
  static const double gap = 8;

  /// 浮层与屏幕边缘的最小边距。
  static const double edge = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: (anchorRect.left - gap - edge).clamp(
          0.0,
          constraints.maxWidth,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = anchorRect.left - gap - childSize.width;
    // 竖向上与锚点同高：浮层中心对齐锚点中心；但浮层比锚点高时不许高过
    // 锚点上沿（否则会探进锚点上面那一行——竖屏正是备注输入框所在处）。
    // 竖向空间不够时宁可让下沿越出屏底，也不越过锚点上沿去压输入框。
    final minTop = anchorRect.top < edge ? edge : anchorRect.top;
    final maxTop = size.height - childSize.height - edge;
    final top = (anchorRect.center.dy - childSize.height / 2).clamp(
      minTop,
      maxTop > minTop ? maxTop : minTop,
    );
    return Offset(left.clamp(edge, size.width), top);
  }

  @override
  bool shouldRelayout(_TransientHintLayout oldDelegate) =>
      oldDelegate.anchorRect != anchorRect;
}

/// 锚点矩形 → 高亮框/洞矩形：短边不足 [guideHoleMinSize] 时以中心扩到下限，
/// 长边原样保留。**绘制与命中透传共用本函数的同一个结果**——看着框住的范围
/// 与点得着的范围差一像素，就会出现「看着能点、其实点在边上还是被吞」。
Rect guideHoleRect(Rect anchorRect) {
  final width = anchorRect.width.clamp(guideHoleMinSize, double.infinity);
  final height = anchorRect.height.clamp(guideHoleMinSize, double.infinity);
  return Rect.fromCenter(
    center: anchorRect.center,
    width: width,
    height: height,
  );
}

/// 动手步判据（编辑态上手 ①）：第一段段体在屏上、
/// 且渲染宽度 ≥ 44 逻辑像素。双指捏合与轨道设置条上的缩放滑条都通过段体
/// 矩形变宽体现，判据同一；只放大别处时本矩形不变，不算。
bool editorIntroZoomDone(Rect? firstSegmentRect) =>
    firstSegmentRect != null && firstSegmentRect.width >= 44;

/// 某步在单元里的位置：与「N/M」、进度点同一次派生。单元里的步按注册表序，
/// 一次性图文有自己的卡片演出、不占讲解步数；分支外的步不上场，同样不占。
class GuideStepPosition {
  const GuideStepPosition({required this.index, required this.count});

  /// 本步位次（0 起；步不在清单里时退回 0，不该发生）。
  final int index;

  /// 单元里占步数的步数（进度点的枚数）。
  final int count;

  /// 「N/M」步数指示；剩不足两步时为 null（就地讲解单步只有 ✕，待办条不显
  /// 步数）。
  String? get indicator => count <= 1 ? null : '${index + 1}/$count';
}

/// 按单元步表取本步位次（「N/M」与进度点共用的唯一派生）。
GuideStepPosition guideStepPosition(GuideStep step, FirstRunChoice? choice) {
  final steps = [
    for (final s in guideStepsOfUnit(step.unitId))
      if (s.form != GuideUnitForm.oneShotCard &&
          guideStepRunsUnderChoice(s, choice))
        s,
  ];
  final index = steps.indexWhere((s) => s.id == step.id);
  return GuideStepPosition(index: index < 0 ? 0 : index, count: steps.length);
}

/// 「N/M」步数指示（[guideStepPosition] 的一视图；就地讲解气泡用）。
String? guideStepIndicator(GuideStep step, FirstRunChoice? choice) =>
    guideStepPosition(step, choice).indicator;

/// 动手演练步的演出层（动手演练列）：锚点矩形外一圈描边
/// 跟着锚点走（**不压暗、不挖洞、不拦触摸**）＋ 待办条。条子贴框与否由
/// [barAnchored] 裁决（锚点在屏且非驻留锚点的步贴框，否则停靠安全区顶）。
/// 条身除「跳过」外不吃触摸，画在其下的手势照常生效。
class HandsOnDrillLayer extends StatelessWidget {
  const HandsOnDrillLayer({
    super.key,
    required this.step,
    required this.copy,
    required this.ui,
    required this.anchorRect,
    required this.barAnchored,
    required this.choice,
    required this.checked,
    required this.onSkip,
  });

  final GuideStep step;
  final GuideStepCopy copy;
  final GuideUiCopy ui;
  final Rect anchorRect;

  /// 条子是否贴框（贴框时条子自带 `Positioned`，直接作本层 Stack 的子）。
  final bool barAnchored;
  final FirstRunChoice? choice;
  final bool checked;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    // 高亮框与洞共用同一矩形（含 24 逻辑像素最小边长，见 [guideHoleRect]）：
    // 细到 1px 的线也看得见。
    final highlight = guideHoleRect(anchorRect);
    final position = guideStepPosition(step, choice);
    final bar = DrillTaskBar(
      icon: guideStepActionIcon(step),
      message: copy.message,
      stepIndicator: position.indicator,
      stepCount: position.count,
      currentStep: position.index,
      checked: checked,
      skipLabel: ui.skip,
      onSkip: onSkip,
      // 贴框基准 = 画出来的高亮框矩形（不是原始锚点矩形）。
      anchorRect: barAnchored ? highlight : null,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              key: const Key('drill_anchor_highlight'),
              painter: _DrillHighlightPainter(highlight),
            ),
          ),
        ),
        // 锚点在屏：条子贴框，自己带 Positioned；否则停靠，铺满整层的宿主
        // 只给它贴安全区顶的位置。
        if (barAnchored) bar else Positioned.fill(child: bar),
      ],
    );
  }
}

/// 动手步的锚点高亮：只描一圈边，不压暗、不挖洞、不参与命中。描边色与
/// 就地讲解的高亮框同为白色——两者都画在视频画面上，主题主色在其上看不清。
class _DrillHighlightPainter extends CustomPainter {
  const _DrillHighlightPainter(this.anchorRect);

  final Rect anchorRect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      anchorRect.inflate(guideHoleInflate),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DrillHighlightPainter oldDelegate) =>
      oldDelegate.anchorRect != anchorRect;
}

class GuideCover extends ConsumerWidget {
  const GuideCover({
    super.key,
    required this.step,
    required this.copy,
    required this.ui,
    required this.anchorRects,
    required this.onAdvance,
    required this.onSkip,
  });

  final GuideStep step;
  final GuideStepCopy copy;
  final GuideUiCopy ui;

  /// 推进本步 / 跳过整单元：状态迁移的属主在宿主，本件只画。
  final VoidCallback onAdvance;
  final VoidCallback onSkip;

  /// 本步**在场**锚点的原始矩形（主播点在前，其余按步声明序）：每一枚各圈
  /// 一圈、同一款式；气泡与箭头只指第一枚（主播点）。
  final List<Rect> anchorRects;

  /// 多步 = 单元里除一次性图文外还有别的步：「点压暗处 = 下一步」与「下一步」
  /// 钮只在多步时推进；单步讲解点压暗处不推进也不收场。
  bool _isMultiStep(FirstRunChoice? choice) =>
      guideStepIndicator(step, choice) != null;

  String _stepIndicator(FirstRunChoice? choice) =>
      guideStepIndicator(step, choice)!;

  /// 高亮框内任一指针按下即算这一步做到：判定取按下，拖动起手也算；
  /// 单步 / 末步整单元置位，多步推进下一步。穿透语义不变——同一下照常
  /// 交给被指的控件。命中范围与遮罩的挖透范围同一矩形同一外扩：
  /// 看着框住的范围与按下去算数的范围一致。
  void _onHolePress(
    BuildContext context,
    WidgetRef ref,
    PointerDownEvent event,
    List<Rect> holes,
  ) {
    if (ref.read(guideSessionProvider).stepsDone.contains(step.id)) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    // 洞矩形是全局坐标、指针位置是本层局部坐标：与 _RenderMaskLayer.hitTest
    // 同一套换算（本层原点的全局位置求出后平移洞矩形），cover 不在窗口原点
    // 时判定也不偏移。
    final origin = box.globalToLocal(Offset.zero);
    final inside = holes.any(
      (hole) =>
          hole.shift(origin).inflate(guideHoleInflate).contains(event.position),
    );
    if (inside) onAdvance();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = MediaQuery.sizeOf(context);
    final choice = ref.watch(guideSessionProvider).firstRunChoice;
    final multiStep = _isMultiStep(choice);
    // 高亮框与洞共用同一份矩形（含 24 逻辑像素最小边长）：绘制与命中透传
    // 不各算一份。
    final holes = anchorRects.map(guideHoleRect).toList();
    return Stack(
      children: [
        // 框内按下即做到： translucent 的监听层只在洞内被命中（本层必须排
        // 在压暗遮罩之前，洞外由遮罩先命中并吞掉），同一下照常落到被指的
        // 控件上。
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _onHolePress(context, ref, event, holes),
          ),
        ),
        // 其余界面整体压暗 + 吞掉触摸；每枚高亮框在命中测试上也挖透——框里
        // 那个控件保持可用（气泡讲的就是它，指了却按不动等于把人锁在原地）。
        // 点压暗处：多步 = 下一步；单步 = 无效果（不推进也不收场）。
        Positioned.fill(
          child: _MaskLayer(
            holes: holes,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: multiStep ? onAdvance : null,
              child: CustomPaint(
                key: const Key('guide_highlight'),
                painter: _HighlightPainter(holes),
              ),
            ),
          ),
        ),
        _GuideBubble(
          copy: copy,
          ui: ui,
          anchorRect: holes.first,
          screen: screen,
          stepIndicator: multiStep ? _stepIndicator(choice) : null,
          onNext: onAdvance,
          onSkip: onSkip,
          onFinish: onAdvance,
        ),
      ],
    );
  }
}

/// 遮罩层：全部高亮框矩形在命中测试上挖透，其余整块吞掉。遮罩铺满窗口，锚点
/// 矩形是全局坐标，故按本层原点换算到本地再比。
class _MaskLayer extends SingleChildRenderObjectWidget {
  const _MaskLayer({required this.holes, super.child});

  final List<Rect> holes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMaskLayer(holes);

  @override
  void updateRenderObject(BuildContext context, _RenderMaskLayer renderObject) {
    renderObject.holes = holes;
  }
}

class _RenderMaskLayer extends RenderProxyBox {
  _RenderMaskLayer(this.holes);

  List<Rect> holes;

  /// 与画法上的洞同一矩形（含描边宽度）：视觉挖透与触摸挖透差一像素，就会
  /// 出现「看着能点、其实点在边上还是被吞」。

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final origin = globalToLocal(Offset.zero);
    for (final hole in holes) {
      if (hole.shift(origin).inflate(guideHoleInflate).contains(position)) {
        return false;
      }
    }
    return super.hitTest(result, position: position);
  }
}

/// 高亮描边：每一枚锚点矩形各挖透（不留暗罩）+ 各一圈白色描边，同一款式。
class _HighlightPainter extends CustomPainter {
  const _HighlightPainter(this.anchorRects);

  final List<Rect> anchorRects;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = Colors.black54);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final rect in anchorRects) {
      canvas.drawRect(rect.inflate(guideHoleInflate), clear);
    }
    canvas.restore();
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final rect in anchorRects) {
      canvas.drawRect(rect.inflate(guideHoleInflate), stroke);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter oldDelegate) =>
      !listEquals(oldDelegate.anchorRects, anchorRects);
}

class _GuideBubble extends StatelessWidget {
  const _GuideBubble({
    required this.copy,
    required this.ui,
    required this.anchorRect,
    required this.screen,
    required this.stepIndicator,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
  });

  final GuideStepCopy copy;
  final GuideUiCopy ui;
  final Rect anchorRect;
  final Size screen;

  /// 「N/M」步数指示，多步才有；单步为 null。
  final String? stepIndicator;

  /// 「下一步」：推进到该单元下一步（最后一步即收场）。
  final VoidCallback onNext;

  /// 「跳过」：一键收掉整单元（与走完同样置位）。
  final VoidCallback onSkip;

  /// 单步的 ✕：收场即置位（与多步最后一步的「下一步」同一收场语义）。
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    // 布点取自唯一一份纯派生：气泡按屏幕
    // 内钳位，且不遮住高亮框自身；水平以框中心为中心、钳回屏幕内。
    final placement = placeGuideBubble(
      anchorRect: anchorRect,
      screen: screen,
      maxWidth: guideBubbleMaxWidth,
    );
    final below = placement.below;
    final arrow = _Arrow(direction: GuideArrowDirection.up);
    final downArrow = _Arrow(direction: GuideArrowDirection.down);

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
              child: arrow,
            ),
          _card(context),
          if (!below)
            Padding(
              padding: EdgeInsets.only(left: placement.arrowLeft),
              child: downArrow,
            ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('guide_bubble'),
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(copy.message, style: theme.textTheme.bodyMedium),
            ),
            // 多步单元：「N/M」+「下一步」推进（最后一步即收场）+「跳过」
            // 一键收掉整单元（与走完同样置位）；单步单元只有 ✕。
            if (stepIndicator != null) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(stepIndicator!, style: theme.textTheme.labelSmall),
              ),
              TextButton(
                key: const Key('guide_next'),
                onPressed: onNext,
                child: Text(ui.next),
              ),
              TextButton(
                key: const Key('guide_skip'),
                onPressed: onSkip,
                child: Text(ui.skip),
              ),
            ] else
              IconButton(
                key: const Key('guide_close'),
                onPressed: onFinish,
                icon: const Icon(Icons.close, semanticLabel: '关闭引导'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 气泡指向锚点的小三角（形状与取色见共用件 [GuideArrowPainter]）。
class _Arrow extends StatelessWidget {
  const _Arrow({required this.direction});

  final GuideArrowDirection direction;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: const Key('guide_arrow'),
      size: const Size(guideArrowWidth, guideArrowHeight),
      painter: GuideArrowPainter(
        direction,
        Theme.of(context).colorScheme.surface,
      ),
    );
  }
}
