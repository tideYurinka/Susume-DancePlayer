/// 学习段轨域：学习段轨的自带 widget 子树——
/// 轨道本体（段体、段内八拍数、重点星标、循环端标、快慢标记）、线段点按
/// 命中层、长按圈选识别层，以及本行直用的两个标记件与临时衔接段覆盖层。
///
/// **依赖方向（单向）**：学习段轨域 → 标注纯件（时间线 / 学习段 / 分段线 /
/// 临时衔接段）+ 轨道行表、时间轴与横向几何值对象 + 节拍刻度分级（段内八拍
/// 数）+ 标注编辑、播放会话、倍频气泡的 provider + 帮助域角标；**不 import
/// 带级文件**（track_band.dart），带级只组装、不转发。
///
/// **不碰容器句柄**：本域的全部外部事实经 [TrackLearningRowInput] 一次给全，
/// 构造参数里没有 Ref / ProviderContainer / WidgetRef；行内画法与命中只认这
/// 份输入与它自己渲染必需的那几个 provider 读面。
///
/// **零行为变化**：本库的实现自 track_band.dart 原样搬移——段体
/// 几何与取色、八拍数缩字三档、重点星标、快慢标记、循环端标、临时段边框、
/// 线段命中列与长按准入逐位不变，段体与标记件的 Key 字符串逐位不变。
///
/// **长按圈选族（拖动域第十族）**：本域是这一族
/// 的**手势起手方**——识别器的准入、起手、逐帧与提交/取消两条收口都经拖动域
/// 句柄驱动，族声明（自家帧）住带级装配（它读 provider 与选中域）。命中解析
/// 仍在带级：本域只收「某全局落点解析出哪个段序」与「全局 → 带内局部落点」
/// 两问的答案，不自己判定落点落在哪一段上。
library;

import 'package:flutter/gestures.dart'
    show LongPressGestureRecognizer, PointerDownEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/annotation_timeline.dart';
import '../annotation/learning_segment_attributes.dart';
import '../annotation/learning_segments.dart';
import '../annotation/transition_segment.dart';
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatPhaseProvider;
import '../core/text_extent.dart';
import '../help/content_registry.dart'
    show editorIntroUnitId, learningSegment0AnchorKey;
import '../help/guide_anchor.dart' show GuideAnchor, GuideBadgeTrigger;
import '../player_session/player_session.dart' show playerSessionProvider;
import 'annotation_editor.dart' show segmentDensitiesProvider;
import 'beat_track_tiers.dart' show formatEightBeatCount, segmentEightBeatCount;
import 'speed_bubble.dart' show SpeedBubbleMode, speedBubbleSessionProvider;
import 'track_band_drag.dart';
import 'track_geometry.dart' show kSegmentLineHitWidth;
import 'track_row_table.dart';
import 'track_time.dart';
import 'visual_tokens.dart';

/// 学习段内居中八拍数说明的显示层级：全句 → 仅数字 → 隐藏。
enum LearningCaptionFit { full, digits, hidden }

/// 学习段说明字号：说明样式 [kLearningCaptionTextStyle] 的唯一定值处。
const double kLearningCaptionFontSize = 10;

/// 学习段说明唯一样式：量测（[learningCaptionFit] 的文本实测）与渲染
/// （说明 [Text]）共用同一实例，不设第二份取值——**测的与画的同源**。
///
/// [TextStyle.inherit] 恒 false，切断环境 [DefaultTextStyle]：`Text` 会与
/// 调用处默认样式（Material `bodyMedium` 带字距与行高）合并，而文本量测
/// 不合并；两侧不同源时渲染宽于量测宽（每字形多一份字距），「全句放得下」
/// 的判定就在临界段宽上把**末字**挤进被 `maxLines: 1` 丢掉的那一行——
/// 的真机症状：「4 个八拍」显示成「4 个八」（无省略号，看着像数字错）。行高
/// 同理会把正文顶出预留盒下缘。
///
/// 语义档（随系统字号）：说明承载语义、随系统字号缩放。量测与渲染
/// 两侧吃**同一个缩放值**（调用处的 `MediaQuery.textScalerOf`）。
///
/// 对比度承载：白字压在段体熟练度色上，可读性由字形自身的单层深色阴影
/// （与重点星标同款：`black87`、`blurRadius 2`、无偏移）承担，段体熟练度色
/// 整块连续。[TextStyle.shadows] 不参与文本量测，「判定放得下即
/// 渲染放得下」逐位成立，无需为阴影另设判定项。
const TextStyle kLearningCaptionTextStyle = TextStyle(
  inherit: false,
  fontSize: kLearningCaptionFontSize,
  height: 1,
  color: kLearningCaptionTextColor,
  shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
);

/// 按可用宽实选说明文案层级：
/// 文本实测宽，[maxWidth] 为计入段内左右间距后的格框内宽；
/// 放得下全句显示全句，否则仅数字，数字也放不下整行隐藏。
///
/// 量测样式与缩放**结构上**唯一：样式取 [kLearningCaptionTextStyle]（渲染侧
/// 同一实例）、缩放取调用处传入的 [textScaler]（渲染侧同一值），
/// 故判定宽与渲染宽逐位一致——「判定放得下」即「渲染放得下」，不靠调用
/// 纪律（样式/字号/缩放值都无第二份取值）。
LearningCaptionFit learningCaptionFit({
  required double maxWidth,
  required String fullText,
  required String digitsText,
  required TextScaler textScaler,
}) {
  double textWidth(String text) => measureTextExtent(
    text,
    kLearningCaptionTextStyle,
    scaler: textScaler,
  ).width;

  if (textWidth(digitsText) > maxWidth) return LearningCaptionFit.hidden;
  if (textWidth(fullText) <= maxWidth) return LearningCaptionFit.full;
  return LearningCaptionFit.digits;
}

/// 学习段格框的段间半缝内缩（发光层 margin 与格框 Padding 共用同一值，
/// 缝宽调整时两处保持一致）。
const EdgeInsets _segmentGapInset = EdgeInsets.symmetric(
  horizontal: kSegmentBoxGap / 2,
);

/// 学习段轨域的显式输入：「这一行需要什么」是一份可读清单——
/// 行矩形、时间轴与窗口、时间线与熟练度/重点/激活段、临时衔接段与该行的
/// 全部回调一次给全，带级只构造它、组装域件，不转发任何调用。
///
/// 按字段判等（[==]）：输入相等时本域内容子树不重建（见 [TrackLearningRow]）。
class TrackLearningRowInput {
  const TrackLearningRowInput({
    required this.rowRect,
    required this.axis,
    required this.window,
    required this.timeline,
    required this.mastery,
    required this.emphasizedSegments,
    required this.activatedSegments,
    this.transition,
    required this.onSegmentDragStart,
    required this.onSegmentTapUp,
    required this.onSegmentTapDown,
    required this.onSegmentTapCancel,
    required this.onSegmentLineTap,
    required this.dragDomain,
    required this.resolveSpanOrder,
    required this.bandLocalAt,
  });

  /// 学习段轨行矩形（带内顶与高）：本行的内容层、覆盖层与线段命中层的
  /// 纵向几何都问它。
  final TrackRowRect rowRect;

  /// 时间轴（时间 ↔ 带内像素的唯一换算口径）。
  final TimelineAxis axis;

  /// 生效可视窗口（段体可见性与线段命中层的窗口判定共用）。**必填**：
  /// 「窗口是什么」由组装点一次给全，域内不再从时间轴回退（时间轴上的窗口
  /// 是同一份事实的第二条路，只留输入这一条）。
  final TimelineWindow window;

  /// 生效时间线（分段线派生学习段；练习区间首尾）。
  final AnnotationTimeline timeline;

  /// 段序 → 熟练度（段体填充色）。
  final Map<int, LearningMastery> mastery;

  /// 重点段序集合（左上角星标）。
  final Set<int> emphasizedSegments;

  /// 激活（循环范围）段序集合（青色描边 + 外发光 + 两端循环字形）。
  final Set<int> activatedSegments;

  /// 临时衔接段；空 = 无临时段，不画覆盖层。
  final TransitionSegment? transition;

  /// 段体横向快滑起手（清空后只选中这一段）。
  final ValueChanged<int> onSegmentDragStart;

  /// 段体抬手点选（带级命中解析后的落点）。
  final GestureTapUpCallback onSegmentTapUp;

  /// 段体按下即选（按下事件就是写点）。
  final ValueChanged<int> onSegmentTapDown;

  /// 段体按下会话被其它识别器接管（静默回滚到按下前）。
  final ValueChanged<int> onSegmentTapCancel;

  /// 线段命中列点按：线下标 + 全局落点。
  final void Function(int index, Offset globalPosition) onSegmentLineTap;

  /// 拖动域句柄：长按圈选族（第十族）的起手、逐帧与提交/取消两条收口都经它。
  final TrackBandDragSession dragDomain;

  /// 长按圈选的落点准入（全局坐标）：解析出可圈的学习段序才准入；空 = 该落点
  /// 不参与（区间外空白、学习轨行外）。命中解析归带级的适配层，本域只收答案。
  final int? Function(Offset globalPosition) resolveSpanOrder;

  /// 全局位置 → 带内局部落点（无渲染盒 = 空）：拖动域收带内局部坐标，换算住
  /// 带级（它需要带级渲染盒）。
  final Offset? Function(Offset globalPosition) bandLocalAt;

  @override
  bool operator ==(Object other) =>
      other is TrackLearningRowInput &&
      other.rowRect == rowRect &&
      other.axis == axis &&
      other.window == window &&
      other.timeline == timeline &&
      other.mastery == mastery &&
      other.emphasizedSegments == emphasizedSegments &&
      other.activatedSegments == activatedSegments &&
      other.transition == transition &&
      other.onSegmentDragStart == onSegmentDragStart &&
      other.onSegmentTapUp == onSegmentTapUp &&
      other.onSegmentTapDown == onSegmentTapDown &&
      other.onSegmentTapCancel == onSegmentTapCancel &&
      other.onSegmentLineTap == onSegmentLineTap &&
      other.dragDomain == dragDomain &&
      other.resolveSpanOrder == resolveSpanOrder &&
      other.bandLocalAt == bandLocalAt;

  @override
  int get hashCode => Object.hashAll([
    rowRect,
    axis,
    window,
    timeline,
    mastery,
    emphasizedSegments,
    activatedSegments,
    transition,
    onSegmentDragStart,
    onSegmentTapUp,
    onSegmentTapDown,
    onSegmentTapCancel,
    onSegmentLineTap,
    dragDomain,
    resolveSpanOrder,
    bandLocalAt,
  ]);
}

/// 学习段轨内容层（轨道本体）：有分段线时派生 n+1 个片段（颜色=熟练度）；
/// 无分段线时空轨。
///
/// 片段的点选/按下/横向快滑经 [TrackLearningRowInput] 的回调交回带级（命中
/// 解析归带级的横向几何 seam，本层只按段自身身份报事件）。长按圈选的识别器
/// 不在此件内（判定区＝学习轨整行，识别器住本域的覆盖层
/// [TrackLearningRowOverlay]）。
///
/// 输入不变时不重建子树（[TrackLearningRowInput] 按字段判等）；输入真变才
/// 重建。本层自订阅的 provider（节拍网格与相位、段内倍频档、待命与气泡态）
/// 变化时仍由自身的订阅重建，不因父级复用而复旧。
class TrackLearningRow extends StatefulWidget {
  const TrackLearningRow({super.key, required this.input});

  /// 本行的全部显式依赖（见 [TrackLearningRowInput]）。
  final TrackLearningRowInput input;

  @override
  State<TrackLearningRow> createState() => _TrackLearningRowState();
}

class _TrackLearningRowState extends State<TrackLearningRow> {
  Widget? _subtree;

  @override
  Widget build(BuildContext context) =>
      _subtree ??= _TrackLearningRowContent(input: widget.input);

  @override
  void didUpdateWidget(TrackLearningRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input != widget.input) {
      _subtree = null;
    }
  }
}

class _TrackLearningRowContent extends ConsumerWidget {
  const _TrackLearningRowContent({required this.input});

  final TrackLearningRowInput input;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = input.axis;
    // 轴恒非空——空态由调用方以几何模块单一谓词判定；本早退
    // 保留为防御（轴自带空态仍是换算安全的最后防线）。
    if (a.isEmpty) return const SizedBox.shrink();
    final segments = deriveLearningSegments(input.timeline);
    final window = input.window;
    // 段内八拍数：仅真实网格就绪时按派生网格（单一来源）
    // 计数，段首/段尾非八拍整点（旧数据）不显示（纯函数 seam 返回 null）。
    // 与轨上大线**同相位**（网格 + 八拍锚点），锚点重定相后本数
    // 随之重算；按八拍点区间加权 → 允许 0.5 分度（如 4.5）。
    final grid = ref.watch(beatGridProvider);
    final phase = ref.watch(beatPhaseProvider);
    // 快慢标记：只在**段内倍频待命态**与
    // **节拍倍频气泡打开**两处显示，其余时刻不画（关气泡即收）。
    final showDensityMarks =
        ref.watch(
          playerSessionProvider.select((s) => s.isSegmentDensityStandby),
        ) ||
        ref.watch(
          speedBubbleSessionProvider.select(
            (s) => s.open == SpeedBubbleMode.beatDensity,
          ),
        );
    final segmentDensities = ref.watch(segmentDensitiesProvider);
    final children = <Widget>[];
    // 编辑态上手第 1 步：第一个学习段体既是触达面（挂载且可用 =
    // 该单元首次触达），也是该步的锚点；其余段体逐位不变。
    Widget editorIntroAnchor(int index, Widget child) => index == 0
        ? GuideBadgeTrigger(
            unitId: editorIntroUnitId,
            child: GuideAnchor(
              anchorKey: learningSegment0AnchorKey,
              child: child,
            ),
          )
        : child;
    for (final segment in segments) {
      // 缩放/平移后窗口外的片段不占布局；横跨窗口的片段裁剪到带内。
      if (segment.end <= window.start || segment.start >= window.end) {
        continue;
      }
      final left = a.timeToX(segment.start).clamp(0.0, a.width);
      final right = a.timeToX(segment.end).clamp(0.0, a.width);
      final index = segment.order;
      final eightCount = segmentEightBeatCount(
        grid: grid,
        start: segment.start,
        end: segment.end,
        phase: phase,
      );
      // 缩字：按格框内可用宽（段宽 − 段间缝左右内缩）实测选
      // 全句/仅数字/隐藏，段宽随缩放/平移逐帧重算。文案：值
      // 允许 0.5 分度（「2.5 个八拍」/ 窄段「2.5」），整数不带小数位。
      final captionText = eightCount == null
          ? null
          : formatEightBeatCount(eightCount);
      final captionFit = captionText == null
          ? null
          : learningCaptionFit(
              // 可用宽 = 段盒宽 − 段间缝；白字直接压在段体熟练度色上，
              // 判定与渲染同源纪律不变。
              maxWidth: right - left - kSegmentBoxGap,
              fullText: '$captionText 个八拍',
              digitsText: captionText,
              textScaler: MediaQuery.textScalerOf(context),
            );
      final segmentMastery = learningSegmentMastery(input.mastery, index);
      final emphasized = input.emphasizedSegments.contains(index);
      final activated = input.activatedSegments.contains(index);
      // 快慢标记：该段设有段内档且处于显示
      // 时机才画；档位只认两档（0.5 → 蓝 ×½、2 → 红 ×2），档位表外的值
      // 一律不画（防御：读侧虽已收窄，不画比误画语义更安全）。段首小字
      // 放得下判据与八拍数同源（文本实测）：可用宽 = 段盒内宽 −
      // 标记两侧内缩 −（有重点星时为其预留的左上角位）。
      final segmentDensity = showDensityMarks ? segmentDensities[index] : null;
      final isMarked = segmentDensity == 0.5 || segmentDensity == 2.0;
      final densityFaster = segmentDensity == 2.0;
      final densityLabel = densityFaster ? '×2' : '×½';
      final densityStarReservation = emphasized
          ? kSegmentDensityLabelStarIndent
          : 0.0;
      final densityLabelFits =
          isMarked &&
          learningCaptionFit(
                maxWidth:
                    right -
                    left -
                    kSegmentBoxGap -
                    2 * kSegmentDensityLabelInset -
                    densityStarReservation,
                fullText: densityLabel,
                digitsText: densityLabel,
                textScaler: MediaQuery.textScalerOf(context),
              ) !=
              LearningCaptionFit.hidden;
      // 循环范围两端：激活段序集合按相邻序派生合并范围——首段
      // 承担 start 端、末段承担 end 端（单段承担两端）；中段只保留描边。
      final loopStart =
          activated && !input.activatedSegments.contains(index - 1);
      final loopEnd = activated && !input.activatedSegments.contains(index + 1);
      // 放得下判据：段盒宽（格框满铺宽 − 段间缝）≥ 13 × 端数；
      // 不成立只省字形，帧不受影响。
      final glyphFits = segmentLoopGlyphFits(
        boxWidth: right - left - kSegmentBoxGap,
        ends: (loopStart ? 1 : 0) + (loopEnd ? 1 : 0),
      );
      children.add(
        Positioned(
          left: left,
          width: right - left,
          top: 0,
          bottom: 0,
          child: editorIntroAnchor(
            index,
            GestureDetector(
              key: ValueKey('learning_segment_$index'),
              behavior: HitTestBehavior.opaque,
              // 点选经命中 seam 解析最近段（短段扩展/最近中心）；tap
              // 识别器守住段体单击（不被带级 sweep 判给拖动）。长按圈选的
              // 识别器不挂段体也不挂行级层：判定区＝学习轨整行，
              // 识别器住本域的覆盖层——线与首尾线的命中窗只约束单击，段窄到
              // 线命中列互相重叠时长按仍可达。
              onTapUp: input.onSegmentTapUp,
              // 按下即选：按下事件就是写点（未选中的段静默只选中
              // 这一段）；本识别器被长按/横滑/缩放抢走或系统打断时 onCancel
              // 静默回滚到按下前——取消与抬手共用 tap 识别器的两种结局。
              onTapDown: (_) => input.onSegmentTapDown(index),
              onTapCancel: () => input.onSegmentTapCancel(index),
              onHorizontalDragStart: (_) => input.onSegmentDragStart(index),
              onHorizontalDragUpdate: (_) {},
              child: Stack(
                children: [
                  // 激活静态外发光层：始终占位渲染，阴影只在激活时
                  // 存在——发光画在格框之下（先入 Stack），不覆盖熟练度主色。
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        key: ValueKey('learning_segment_${index}_glow'),
                        margin: _segmentGapInset,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            kSegmentBoxBorderRadius,
                          ),
                          boxShadow: activated
                              ? [
                                  BoxShadow(
                                    color: kCyanAccentColor.withValues(
                                      alpha: kSegmentGlowOpacity,
                                    ),
                                    blurRadius: kSegmentGlowBlurRadius,
                                    spreadRadius: kSegmentGlowSpreadRadius,
                                  ),
                                ]
                              : const [],
                        ),
                      ),
                    ),
                  ),
                  // 圆角格框：段间留缝（左右各让 gap/2）、半透明白
                  // 1px 描边——未练灰相邻段也界限分明；派生几何（Positioned
                  // 仍首尾相接满铺）不变，格框只是视觉内缩。填充恒为熟练度色；
                  // 描边只承载学习段选中（选中只有一个状态，青色
                  // 加粗整框即唯一选中视觉）与默认两态。
                  Positioned.fill(
                    child: Padding(
                      padding: _segmentGapInset,
                      child: DecoratedBox(
                        key: ValueKey('learning_segment_${index}_box'),
                        decoration: BoxDecoration(
                          color: learningMasteryColor(segmentMastery),
                          borderRadius: BorderRadius.circular(
                            kSegmentBoxBorderRadius,
                          ),
                          border: activated
                              ? Border.all(
                                  color: kCyanAccentColor,
                                  width: kSegmentSelectedBorderWidth,
                                )
                              : Border.all(
                                  color: kSegmentBoxStrokeColor,
                                  width: kSegmentBoxStrokeWidth,
                                ),
                        ),
                        child: Stack(
                          children: [
                            // 快慢标记：红/蓝
                            // 边框画在青色选中框之内（再内缩一档，不与它同宽
                            // 同位）、段首小字表达精确档位；层级在本 Stack
                            // 首位——星标/八拍数/循环字形画在其上，标记不
                            // 覆盖它们；IgnorePointer 不参与命中。
                            if (isMarked)
                              _SegmentDensityMark(
                                baseKey: 'learning_segment_$index',
                                faster: densityFaster,
                                label: densityLabel,
                                showLabel: densityLabelFits,
                                labelIndent: emphasized
                                    ? kSegmentDensityLabelStarIndent
                                    : 0.0,
                              ),
                            // 段内八拍数：居中淡字「N 个八拍」，
                            // 字号/透明度小而不抢段体熟练度色；窄段按实测宽
                            // 两级缩：仅数字或整行隐藏，key 随
                            // 文案变体；星标在左上角、数字居中，两者不重叠。
                            // 样式/缩放与判定侧同源（[kLearningCaptionTextStyle]
                            // + 调用处缩放值，同一份取值，语义档（随系统字号））+
                            // `softWrap: false`：判定说放得下就必然单行画全，
                            // 绝不静默吞掉末字（软换行的第二行会被 maxLines
                            // 丢掉）。
                            if (captionFit != null &&
                                captionText != null &&
                                captionFit != LearningCaptionFit.hidden)
                              Align(
                                alignment: Alignment.center,
                                // 白字直接压段体熟练度色，可读性由
                                // [kLearningCaptionTextStyle] 的单层深色字阴影
                                // 承担；说明自身不占额外横向空间，可用宽判定
                                // 即段盒内宽。
                                child: Text(
                                  captionFit == LearningCaptionFit.full
                                      ? '$captionText 个八拍'
                                      : captionText,
                                  key: ValueKey(
                                    'learning_segment_${index}_eight_count_'
                                    '${captionFit.name}',
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  textScaler: MediaQuery.textScalerOf(context),
                                  style: kLearningCaptionTextStyle,
                                ),
                              ),
                            if (emphasized)
                              Align(
                                alignment: Alignment.topLeft,
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Icon(
                                    Icons.star,
                                    key: ValueKey(
                                      'learning_segment_${index}_emphasis',
                                    ),
                                    size: 16,
                                    color: kHighlightAmber,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // 循环范围两端标志：放得下时的
                            // repeat 字形；帧由格框装饰承担，端点与中段
                            // 逐像素同形，不画任何短钩或填角。
                            if (loopStart || loopEnd)
                              _SegmentLoopEndMarks(
                                baseKey: 'learning_segment_$index',
                                glyphStart: glyphFits && loopStart,
                                glyphEnd: glyphFits && loopEnd,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // 长按拖动圈选：识别器住本域的覆盖层，本件只出
    // 内容层——段体单击/横向快滑的识别器各自在段体上。
    return Stack(children: children);
  }
}

/// 线段点按命中层（40dp 宽命中带贯穿学习段轨及其下各行）：不注册拖动
/// 识别器，带内空白跟手滑预览条可跨过线列不被抢。仅学习轨行内的点击触发
/// 临时衔接段（经带级命中 seam 取最近线），节拍轨行与轨间隙的点击不触发线
/// 操作；选中 toggle 由轨道手柄带控制柄承担。
///
/// 座位在预览线、首尾线与控制柄之下（本层吸收线心点按的裁决权归预览线 2dp
/// 柱），命中列**不**覆盖其上的局部镜像轨行——否则片段边界与分段线同位时该列
/// （不透明、叠于片段块之上）会截获指针、片段边界无法起手拖动。
class TrackLearningLineHitLayer extends StatelessWidget {
  const TrackLearningLineHitLayer({super.key, required this.input});

  /// 本行的全部显式依赖（见 [TrackLearningRowInput]）。
  final TrackLearningRowInput input;

  @override
  Widget build(BuildContext context) {
    final a = input.axis;
    final lines = input.timeline.segmentLines;
    return Positioned(
      left: 0,
      top: input.rowRect.top,
      width: a.width,
      bottom: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < lines.length; i++)
            if (input.window.contains(lines[i].position))
              Positioned(
                left: a.timeToX(lines[i].position) - kSegmentLineHitWidth / 2,
                //  修（边界与分段线同位可拖）：命中列从学习段轨顶起，
                // 覆盖学习段轨及其下各行（分段操作本就只在学习段轨行内生效）。
                top: 0,
                bottom: 0,
                width: kSegmentLineHitWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      input.onSegmentLineTap(i, details.globalPosition),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
        ],
      ),
    );
  }
}

/// 学习段轨的覆盖层（本行矩形内）：临时衔接段边框与长按圈选识别层。
///
/// 长按判定区＝学习轨整行（[TrackLearningRowInput.rowRect]），识别器只在按下
/// 落点能解析出可圈的学习段时才加入 arena（[TrackLearningRowInput
/// .onLongPressAllowsAt]）——线与首尾线的命中窗不遮蔽长按（落点按段体解析），
/// 区间外空白落点不参与（轨道片头由带级空白守卫吸收）。座位在预览线/首尾线/
/// 半拍线命中层之上、轨道片头空白守卫之下：段窄到分段线命中列互相重叠时长按
/// 仍可达，而空白横滑的精细调整与空白单击收起保持按下即胜出的既有仲裁。
class TrackLearningRowOverlay extends StatefulWidget {
  const TrackLearningRowOverlay({super.key, required this.input});

  /// 本行的全部显式依赖（见 [TrackLearningRowInput]）。
  final TrackLearningRowInput input;

  @override
  State<TrackLearningRowOverlay> createState() =>
      _TrackLearningRowOverlayState();
}

class _TrackLearningRowOverlayState extends State<TrackLearningRowOverlay> {
  /// 本族起手交回的域句柄：逐帧与收口只经本族自己的句柄（跨族覆盖后旧句柄
  /// 由域的世代守卫变成空操作）——「谁在拖」的簿记因此不在本域留第二份布尔。
  TrackBandDragHandle? _spanHandle;

  /// 起手（长按成立那一刻，越过阈值；准入由识别器的 [isPointerAllowed] 在
  /// 按下时就问过）：落点段序与带内局部落点一次解析，起手判定与帧事务在域里。
  void _beginSpan(Offset globalPosition) {
    final input = widget.input;
    final order = input.resolveSpanOrder(globalPosition);
    final local = input.bandLocalAt(globalPosition);
    if (order == null || local == null) return;
    _spanHandle = input.dragDomain.begin(
      TrackBandDragTarget.learningSpan(order),
      local.dx,
    );
  }

  /// 逐帧：只经本族句柄，交回带内局部落点（段的命中按行归属解析，纵坐标参与
  /// 判定）；句柄陈旧（跨族覆盖/已收口）或几何不可用时为空操作。
  void _updateSpan(Offset globalPosition) {
    final local = widget.input.bandLocalAt(globalPosition);
    if (local == null) return;
    _spanHandle?.moveToPoint(local);
  }

  /// 收口：提交路径（松手）。句柄收口（幂等），族的两条收口路径在域里。
  void _endSpan() {
    final handle = _spanHandle;
    _spanHandle = null;
    handle?.end();
  }

  /// 收口：取消路径（系统打断或被其它识别器抢走）——回到起手前。
  void _cancelSpan() {
    final handle = _spanHandle;
    _spanHandle = null;
    handle?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final transition = input.transition;
    return Positioned(
      left: 0,
      top: input.rowRect.top,
      width: input.axis.width,
      height: input.rowRect.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 临时衔接段青边框：跨段框住临时范围（[start, end] 按时间
          // 轴映射，天然跨真实学习段）。z 序置顶后保持在预览线之上；
          // 纯视觉不参与命中。
          if (transition != null)
            _TransitionRangeOverlay(axis: input.axis, transition: transition),
          Positioned.fill(
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              excludeFromSemantics: true,
              gestures: {
                _LearningTrackLongPressRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      _LearningTrackLongPressRecognizer
                    >(
                      () => _LearningTrackLongPressRecognizer(
                        allowsPosition: (globalPosition) =>
                            input.resolveSpanOrder(globalPosition) != null,
                      ),
                      (recognizer) {
                        recognizer.onLongPressStart = (details) {
                          _beginSpan(details.globalPosition);
                        };
                        recognizer.onLongPressMoveUpdate = (details) {
                          _updateSpan(details.globalPosition);
                        };
                        recognizer.onLongPressEnd = (details) => _endSpan();
                        recognizer.onLongPressCancel = _cancelSpan;
                      },
                    ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 学习轨长按圈选识别器：判定区＝学习轨整行，但只在按下落点
/// 能解析出可圈的学习段时才加入 arena（[allowsPosition]）——线与首尾线的
/// 命中窗不遮蔽长按（落点按段体解析），区间外空白落点不参与（轨道片头由
/// 更上层的空白守卫吸收）。
///
/// 准入为什么必要：本识别器加入 arena 后，带级 scale 识别器要等位移过阈才
/// 胜出，起手那段位移落在它 start 之前——带内空白横滑的精细调整与空白单击
/// 收起（scaleEnd 上报仲裁）都以「按下即胜出」为前提，故只有真能起圈选的
/// 落点才准入。
class _LearningTrackLongPressRecognizer extends LongPressGestureRecognizer {
  _LearningTrackLongPressRecognizer({required this.allowsPosition});

  /// 落点准入（全局坐标）。
  final bool Function(Offset globalPosition) allowsPosition;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      super.isPointerAllowed(event) && allowsPosition(event.position);
}

/// 临时衔接段青边框 overlay：按 [TransitionSegment.start]/[.end]
/// 的时间轴映射跨段框住临时范围（天然跨真实学习段——时间区间与段边界
/// 无关），叠于学习段轨静态层之上。复用激活段边框 token（青色激活边框），
/// 纯视觉（[IgnorePointer]）不参与命中。临时段激活时在同一
/// `Stack` 内叠加两端 `repeat` 字形（[_SegmentLoopEndMarks]，与
/// 学习段共用同一份几何），发光保持关闭。
class _TransitionRangeOverlay extends StatelessWidget {
  const _TransitionRangeOverlay({required this.axis, required this.transition});

  final TimelineAxis axis;
  final TransitionSegment transition;

  @override
  Widget build(BuildContext context) {
    // 父级分支已判可映射；本早退保留为防御。
    if (axis.isEmpty) return const SizedBox.shrink();
    final left = axis.timeToX(transition.start).clamp(0.0, axis.width);
    final right = axis.timeToX(transition.end).clamp(0.0, axis.width);
    if (right - left <= 0) return const SizedBox.shrink();
    // 两端标志：临时段永远自己承担循环范围的 start / end 两端，
    // repeat 字形与学习段共用同一份几何（[_SegmentLoopEndMarks]）；
    // 放得下判据同一条公式，不成立只省字形。
    final glyphFits = segmentLoopGlyphFits(boxWidth: right - left, ends: 2);
    return Positioned(
      left: left,
      width: right - left,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                key: const Key('transition_segment_overlay'),
                decoration: BoxDecoration(
                  border: Border.fromBorderSide(
                    BorderSide(
                      color: kCyanAccentColor,
                      width: kSegmentSelectedBorderWidth,
                    ),
                  ),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(kSegmentBoxBorderRadius),
                  ),
                ),
              ),
            ),
            _SegmentLoopEndMarks(
              baseKey: 'transition_segment',
              glyphStart: glyphFits,
              glyphEnd: glyphFits,
            ),
          ],
        ),
      ),
    );
  }
}

/// 循环范围两端的标志：放得下时该端内侧画一枚 10dp 的
/// `Icons.repeat`（距端 3dp、距底 3dp）；放不下时该端不画字形、不留
/// 半个符号——激活帧始终是完整圆角整框（由格框装饰承担，本件不画帧）。
/// 学习段体与临时衔接段 overlay共用同一份几何，不复制。
/// 纯视觉不参与命中（[IgnorePointer]，点选仍落在段体自身手势上）。
class _SegmentLoopEndMarks extends StatelessWidget {
  const _SegmentLoopEndMarks({
    required this.baseKey,
    required this.glyphStart,
    required this.glyphEnd,
  });

  /// 选择器键前缀：`<baseKey>_loop_glyph_start` / `_loop_glyph_end`。
  final String baseKey;
  final bool glyphStart;
  final bool glyphEnd;

  /// 一端的 repeat 字形：贴端 3dp、距底 3dp。
  Widget _glyph({required bool isStart}) {
    return Positioned(
      key: Key('$baseKey${isStart ? '_loop_glyph_start' : '_loop_glyph_end'}'),
      left: isStart ? kSegmentLoopGlyphInset : null,
      right: isStart ? null : kSegmentLoopGlyphInset,
      bottom: kSegmentLoopGlyphInset,
      child: Icon(
        Icons.repeat,
        size: kSegmentLoopGlyphSize,
        color: kCyanAccentColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            if (glyphStart) _glyph(isStart: true),
            if (glyphEnd) _glyph(isStart: false),
          ],
        ),
      ),
    );
  }
}

/// 学习段快慢标记：红边框 = 变快（×2）、
/// 蓝边框 = 变慢（×½），画在青色选中框**之内**（相对格框再内缩一档，
/// 不与它同宽同位）；段首小字表达精确档位，段窄到放不下就不画小字，
/// **框始终完整**。颜色语义固定不按档位分色；不覆盖熟练度填充、重点星
/// 与段内八拍数（本层画在其下 + IgnorePointer）。
class _SegmentDensityMark extends StatelessWidget {
  const _SegmentDensityMark({
    required this.baseKey,
    required this.faster,
    required this.label,
    required this.showLabel,
    required this.labelIndent,
  });

  /// 选择器键前缀：`<baseKey>_density_mark` / `<baseKey>_density_label`。
  final String baseKey;

  /// true = 变快（×2，红）；false = 变慢（×½，蓝）。
  final bool faster;

  /// 段首小字文案（`×2` / `×½`）与是否放得下。
  final String label;
  final bool showLabel;

  /// 有重点星时小字的让位缩进（星占左上角，小字右移不与其重叠）。
  final double labelIndent;

  @override
  Widget build(BuildContext context) {
    final color = faster
        ? kSegmentDensityFasterColor
        : kSegmentDensitySlowerColor;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                margin: const EdgeInsets.all(kSegmentDensityBorderInset),
                child: DecoratedBox(
                  key: Key('${baseKey}_density_mark'),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      kSegmentBoxBorderRadius - kSegmentDensityBorderInset,
                    ),
                    border: Border.all(
                      color: color,
                      width: kSegmentDensityBorderWidth,
                    ),
                  ),
                ),
              ),
            ),
            if (showLabel)
              Positioned(
                left: kSegmentDensityLabelInset + labelIndent,
                top: kSegmentDensityLabelInset,
                child: Text(
                  label,
                  key: Key('${baseKey}_density_label'),
                  maxLines: 1,
                  softWrap: false,
                  textScaler: MediaQuery.textScalerOf(context),
                  style: kLearningCaptionTextStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
