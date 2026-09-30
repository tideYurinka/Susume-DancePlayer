/// 节拍刻度域：节拍轨整行呈现自足模块——三级
/// 刻度（八拍大线 / 四拍中线 / 一拍小线）、八拍锚点第二视觉、八拍数标注，
/// 以及分析态横幅（占位不定态进度条 / 异常暖色底）与它的状态件。
///
/// **接口**：一个显式输入件 [BeatTicksRow]——收行矩形（行高）与横向时间轴
/// （总时长 × 带宽 × 可视窗口）。行内其余读面随域订阅：节拍轨三态、派生网格
/// 与八拍相位、待命态（仅待命态画锚点第二视觉）、生效标注时间线（八拍数标注
/// 按学习段段内相对编号）。带级只按行矩形组装它，不转发任何行内画法。
///
/// **依赖方向**：单向。本域 → 时间轴与窗口纯件（`track_time.dart`）、横向
/// 几何纯件（`track_geometry.dart`：每像素微秒、轨道片头带宽与拖动换算）、
/// 节拍刻度分级与八拍数标注纯件（`beat_track_tiers.dart`）、学习段派生纯件
/// （`annotation/learning_segments.dart`）、网格与相位值类型
/// （`core/beat_grid.dart`、`core/eight_beat_phase.dart`）、共享视觉常量
/// （`visual_tokens.dart`）、节拍网格/相位/三态读面（`beat_track_state`）、
/// 标注编辑模块读面与会话（`annotation_editor.dart`）、标注选中域
/// （`annotation_selection.dart`）、拖动域（`track_band_drag.dart`）、轨道行
/// 矩形值对象（`track_row_table.dart`）、角标锚点包装件
/// （`help/guide_anchor.dart`）、播放会话待命态读面（`player_session`）。
/// 零 import 带级库（带级 import 本域，方向不可逆）；本域不写带级状态、不碰
/// 容器句柄。
///
/// **本域的公开面**：除行件 [BeatTicksRow] 与半拍线覆盖层
/// [TrackHalfBeatOverlay] 外，还有三处供量测与测试缝的公开成员——刻度让位
/// 量测 [kEightCountLabelSlotHeight] / [kEightCountLabelSlotWidth]（标注槽
/// 几何）、半拍线拖动密度下限 [kHalfBeatDragMinSpacingDp]，以及本域自持的
/// 占位光带流动开关 [beatAnalyzingFlowProvider]（测试缝：流动是永不停歇的
/// 循环动画，会让 `pumpAndSettle` 永不收敛）。
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/learning_segments.dart' show deriveLearningSegments;
import '../beat_track_state/beat_track_state.dart'
    show
        BeatTrackPhase,
        beatGridProvider,
        beatPhaseProvider,
        beatTrackStateProvider;
import '../core/beat_grid.dart' show BeatGrid, BeatGridReads;
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../help/guide_anchor.dart' show GuideAnchor;
import '../player_session/player_session.dart' show playerSessionProvider;
import 'annotation_editor.dart'
    show
        AnnotationGestureTarget,
        annotationEditorProvider,
        annotationSelectionDomainProvider,
        effectiveAnnotationTimelineProvider,
        selectedHalfBeatLineIndexProvider;
import 'annotation_selection.dart' show HalfBeatLineSelection;
import 'beat_track_tiers.dart'
    show
        BeatTickTier,
        beatEightCountLabels,
        beatTickWidthOf,
        beatTrackTicks;
import 'track_band_drag.dart'
    show
        TrackBandDragDeclaration,
        TrackBandDragFamilies,
        TrackBandDragHandle,
        TrackBandDragSession,
        TrackBandDragTarget;
import 'track_geometry.dart'
    show TrackBandGeometry, dragTimeAt, kSegmentLineHitWidth, kTrackPrefixWidth;
import 'track_row_table.dart' show TrackRowRect;
import 'track_time.dart' show TimelineAxis, TimelineWindow;
import 'visual_tokens.dart'
    show
        kBeatAnchorLineColor,
        kBeatAnchorMarkerSize,
        kBeatTrackAnalyzingColor,
        kBeatTrackErrorBackground,
        kBeatTrackErrorTextColor,
        kHalfBeatLineColor,
        kHalfBeatLineHeight,
        kHalfBeatLineThickness,
        kSegmentLineSelectedColor;

/// 节拍轨行（三态形态）：按节拍轨三态渲染——
///
/// - 占位（分析中/未开始）：整行**不定态进度条**（持续流动的光带，不表达
///   百分比），行内居中「节拍分析中……」；不画任何均匀占位刻度；
/// - 就绪：真实拍时刻刻度，经 [beatTrackTicks] 分级为八拍大线 >
///   四拍中线 > 一拍小线（八拍相位从 downbeat 序列派生，弱起拍只按
///   拍点呈现）；不显示"分析完成"过渡，刻度出现即交接；
/// - 异常：整行暖色底，行内居中「节拍识别失败」，不画任何假刻度。
///
/// 三态都是不可点的纯显示。不显示半拍刻度线（半拍只在「插入半拍线」与
/// 节拍动画中呈现）。刻度位置经 [TimelineAxis.timeToX] 换算。轴不可映射
/// （轴恒非空，空态由几何模块单一谓词在调用方判定）→ 空刻度
/// 占位（轨仍在）。
class BeatTicksRow extends StatelessWidget {
  const BeatTicksRow({super.key, required this.axis, required this.height});

  final TimelineAxis axis;

  /// 行高（从行集的行声明传入，刻度内缩等行内装饰留在此处）。
  final double height;

  @override
  Widget build(BuildContext context) {
    // 轴恒非空——早退保留为防御（同学习段轨）。
    return SizedBox(
      key: const Key('track_beat'),
      height: height,
      child: axis.isEmpty
          ? const SizedBox.shrink()
          : _TicksBody(axis: axis, rowHeight: height),
    );
  }
}

class _TicksBody extends ConsumerWidget {
  const _TicksBody({required this.axis, required this.rowHeight});

  final TimelineAxis axis;

  /// 节拍轨行高（由行集给出）。
  final double rowHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(beatTrackStateProvider);
    final window = axis.window ?? TimelineWindow.full(axis.total);
    // 【白名单，】异常态裸直判的两支许可 UI 文案之一（另一处在
    // `control_layer.dart` `_showBeatReadinessPrompt`）——其余可用性判读
    // 一律走两个谓词。
    // 占位态 = 整行不定态进度条 + 居中「节拍分析中……」（不画
    // 均匀占位刻度）；异常态 = 整行暖色底 + 居中「节拍识别失败」（不画
    // 假刻度）。两态各自带语义标签（读屏可读），不带百分比语义，均不可点。
    if (track.phase == BeatTrackPhase.placeholder) {
      return const _BeatTrackAnalyzingBanner();
    }
    if (track.phase == BeatTrackPhase.error) {
      return Semantics(
        key: const Key('beat_track_failed'),
        label: '节拍识别失败',
        child: ColoredBox(
          color: kBeatTrackErrorBackground,
          child: const Center(
            child: Text(
              '节拍识别失败',
              key: Key('beat_track_failed_label'),
              style: TextStyle(fontSize: 11, color: kBeatTrackErrorTextColor),
            ),
          ),
        ),
      );
    }
    // 就绪/占位共用三级刻度分级（beat_track_tiers 纯函数）：
    // 刻度线是纯几何、无文本，不属字号两档（读不到它不丢失信息）。三级：
    // 八拍大线（最长、不透明度 0.95）> 四拍中线（中长、0.62）> 一拍小线
    // （最短、0.34），刻度宽按层级（大线 1.5px、中/小线 1px），
    // 垂直居中、非半拍全白；不显示半拍。
    final grid = ref.watch(beatGridProvider);
    // 八拍相位：网格 + 八拍锚点的单一派生源——大线/中线与
    // 八拍数小数字同相位（锚点重定相当帧随 provider 刷新）。
    final phase = ref.watch(beatPhaseProvider);
    final ticks = beatTrackTicks(grid, window.start, window.end, phase: phase);
    // 八拍锚点视觉（改**仅待命态**；
    //  改读模式谓词）：待命态下锚点所在强拍以**第二色大线**呈现（与
    // 白色自动大线一眼可分——锚点在其自身相位下恒为八拍大线层级，故几何同
    // 大线、只换色），并在轨顶加一枚小标记、该处让位不画八拍数小数字；非
    // 待命态完全不画锚点（普通大线 + 照常显示八拍数小数字，与完全无锚点
    // 渲染一致）。锚点不做拖动。
    final anchorVisible = ref
        .watch(playerSessionProvider)
        .isBeatCorrectionStandby;
    final anchorTimes = anchorVisible
        ? _anchorTimesInWindow(phase, grid, window)
        : const <Duration>{};
    // 八拍数标注：仅真实网格就绪（占位/异常不标），序号为
    // 所在学习段段内相对编号（段首八拍 = 1、跨段重数），同位（分段/首/
    // 尾线）跳过、间距不足不标；窗口平移/缩放随 axis/时间线变化逐帧重
    // 派生（纯函数 seam，单一来源）。待命态锚点让位——该处
    // 不显示但序号照常占位（hiddenAtTimes）。
    final timeline = ref.watch(effectiveAnnotationTimelineProvider);
    final labels = beatEightCountLabels(
      grid: grid,
      segments: deriveLearningSegments(timeline),
      windowStart: window.start,
      windowEnd: window.end,
      microsecondsPerPixel: TrackBandGeometry.eval(
        total: axis.total,
        window: axis.window,
        width: axis.width,
        prefixWidth: kTrackPrefixWidth,
      ).microsecondsPerPixel,
      phase: phase,
      hiddenAtTimes: anchorTimes,
    );
    return Stack(
      children: [
        for (final tick in ticks)
          Positioned(
            // 键 = 拍时刻微秒（窗口平移/缩放后可见拍集合可断言）。
            key: ValueKey('beat_tick_${tick.time.inMicroseconds}'),
            left: axis.timeToX(tick.time) - beatTickWidthOf(tick.tier) / 2,
            top: _tickTopInsetOf(tick.tier, rowHeight),
            bottom: _tickBottomInsetOf(tick.tier, rowHeight),
            width: beatTickWidthOf(tick.tier),
            child: ColoredBox(
              color: anchorTimes.contains(tick.time)
                  ? kBeatAnchorLineColor
                  : Colors.white.withValues(alpha: _tickAlphaOf(tick.tier)),
            ),
          ),
        // 轨顶小标记（锚点第二视觉标识；不参与命中、纯视觉）。
        for (final time in anchorTimes)
          Positioned(
            key: ValueKey('beat_anchor_marker_${time.inMicroseconds}'),
            left: axis.timeToX(time) - kBeatAnchorMarkerSize / 2,
            top: 0,
            width: kBeatAnchorMarkerSize,
            height: kBeatAnchorMarkerSize,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: kBeatAnchorLineColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        // 八拍数小字（字号 9，真机看版）：绘制在大线刻度上方（节拍轨行
        // 顶部），纯视觉不参与命中；槽位居中大线（槽宽见
        // [kEightCountLabelSlotWidth]，OverflowBox 不裁切超宽两位数）。
        // 八拍数承载语义，属语义档（随系统字号）：样式只此一份、无覆写即吃
        // 环境缩放，与学习段段说明同档。
        for (final label in labels)
          Positioned(
            key: ValueKey('beat_count_${label.time.inMicroseconds}'),
            left: axis.timeToX(label.time) - kEightCountLabelSlotWidth / 2,
            top: 0,
            width: kEightCountLabelSlotWidth,
            height: kEightCountLabelSlotHeight,
            child: OverflowBox(
              maxWidth: double.infinity,
              // minWidth 归零（修）：OverflowBox 缺省继承入射
              // minWidth（= 槽宽 20），单/双位数字被拉宽到整槽且按 textAlign
              // 左排 → 真机数字明显偏左。归零后 Text 收缩到
              // 内容宽、由 alignment 真正水平居中在大线上。
              minWidth: 0,
              alignment: Alignment.center,
              child: Text(
                '${label.count}',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 9,
                  height: 1,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 占位态光带流动开关（测试缝）：流动是永不停歇的循环动画，会
/// 让 `pumpAndSettle` 永不收敛，而全仓 widget 测试以 `pumpAndSettle` 为
/// 停稳基准。应用/真机恒流动；widget 测试环境（`FLUTTER_TEST`）默认静止
/// （静态带体居中，可观察形态逐位相同），需要断言流动的用例经本 provider
/// 覆盖为 true。这不是功能开关。
final beatAnalyzingFlowProvider = Provider<bool>(
  (ref) => !Platform.environment.containsKey('FLUTTER_TEST'),
);

/// 占位光带带体宽（行宽比例）：绘制位移系数由它推出。
const double _kAnalyzingShimmerWidthFactor = 0.4;

/// 占位光带整周期的绘制位移（行宽倍数）：位移 = 系数 ×(进度 − 0.5)
/// × 整行宽。1.68 行宽 ≥ 带体从左出视口走到右出视口所需行程
///（1 + [_kAnalyzingShimmerWidthFactor]），循环间不出现视口内折返。
const double _kAnalyzingShimmerTravel = 1.68;

/// 节拍轨占位态整行形态：不定态进度条——一条持续流动的光带
/// （自左向右循环，不表达百分比、不承诺进度），行内居中「节拍分析中……」。
/// 纯显示不可点；语义标签供读屏读出「节拍分析中」。
class _BeatTrackAnalyzingBanner extends ConsumerStatefulWidget {
  const _BeatTrackAnalyzingBanner();

  @override
  ConsumerState<_BeatTrackAnalyzingBanner> createState() =>
      _BeatTrackAnalyzingBannerState();
}

class _BeatTrackAnalyzingBannerState
    extends ConsumerState<_BeatTrackAnalyzingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (ref.read(beatAnalyzingFlowProvider)) {
      _flow.repeat();
    } else {
      // 静止形态：带体停在行内居中位（形态逐位同流动帧）。
      _flow.value = 0.5;
    }
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('beat_track_placeholder'),
      label: '节拍分析中',
      child: Stack(
        children: [
          // 流动光带：横向渐变带沿整行循环平移（带体越出视口让出入动画
          // 发生，ClipRect 裁掉行外部分）。
          //
          // 平移只走**绘制变换**（[FractionalTranslation]）——带体
          // 槽位（Align 居中）在整段动画里恒定，动画帧不触发整行重新布局；
          // 位移 = [_kAnalyzingShimmerTravel] ×(进度 − 0.5)× 整行宽。
          Positioned.fill(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _flow,
                builder: (context, child) => FractionalTranslation(
                  translation: Offset(
                    _kAnalyzingShimmerTravel * (_flow.value - 0.5),
                    0,
                  ),
                  child: child,
                ),
                child: const Align(
                  alignment: Alignment.center,
                  child: FractionallySizedBox(
                    key: Key('beat_track_shimmer'),
                    widthFactor: _kAnalyzingShimmerWidthFactor,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            kBeatTrackAnalyzingColor,
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Center(
            child: Text(
              '节拍分析中……',
              key: Key('beat_track_analyzing_label'),
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

/// 窗口内的八拍锚点时刻集合：锚点身份 = 拍序号，时刻经派生
/// 网格求值（节拍对齐平移随行）。序号合法性由 [BeatPhase] 构造时按**同一
/// 网格**规范化保证（越界/非强拍已丢弃），此处不再重复守卫。
Set<Duration> _anchorTimesInWindow(
  BeatPhase phase,
  BeatGrid grid,
  TimelineWindow window,
) {
  return {
    for (final anchor in phase.anchors)
      if (_inWindow(grid.beatTime(anchor), window)) grid.beatTime(anchor),
  };
}

bool _inWindow(Duration time, TimelineWindow window) =>
    time >= window.start && time <= window.end;

/// 八拍数标注槽位几何：行顶居中大线的定宽槽（OverflowBox
/// 不裁切两位数）× 行顶小字槽高。
const double kEightCountLabelSlotWidth = 20;
const double kEightCountLabelSlotHeight = 10;

double _tickAlphaOf(BeatTickTier tier) => switch (tier) {
  BeatTickTier.eightBar => 0.95,
  BeatTickTier.fourBar => 0.62,
  BeatTickTier.beat => 0.34,
};

/// 刻度让位：标注槽占行顶 [kEightCountLabelSlotHeight]，刻度列
/// 整体下移到槽底 +2px 间隙以下（轨底仍留 1px），与数字底缘不重叠。
const double _tickColumnTop = kEightCountLabelSlotHeight + 2;
const double _tickColumnBottomInset = 1;

/// 让位列内三级刻度长度（11 / 8 / 5，分级八拍 > 四拍 > 一拍），共用中心。
const double _tickLengthEightBar = 11;
const double _tickLengthFourBar = 8;
const double _tickLengthBeat = 5;

double _tickLengthOf(BeatTickTier tier) => switch (tier) {
  BeatTickTier.eightBar => _tickLengthEightBar,
  BeatTickTier.fourBar => _tickLengthFourBar,
  BeatTickTier.beat => _tickLengthBeat,
};

double _tickTopInsetOf(BeatTickTier tier, double rowHeight) =>
    _tickColumnTop +
    ((rowHeight - _tickColumnTop - _tickColumnBottomInset) -
            _tickLengthOf(tier)) /
        2;

double _tickBottomInsetOf(BeatTickTier tier, double rowHeight) =>
    (rowHeight -
            _tickColumnTop -
            _tickColumnBottomInset -
            _tickLengthOf(tier)) /
        2 +
    _tickColumnBottomInset;

/// 密度护栏下限：当前可视窗口下该半拍线所在相邻拍点区间的半拍格点屏上间距
/// 低于此值（dp，Flutter 逻辑像素即 dp）时，命中列不注册水平拖动——识别器
/// 不进手势竞争，横拖自然落到整条轨道的进度拖动；点按选中、删除与步进照常。
const double kHalfBeatDragMinSpacingDp = 3;

/// 半拍线覆盖层的显式输入：本帧的几何与半拍线事实 + 族的拖动域句柄 +
/// 拖线实时预览三条回调。「这一层需要什么」是一份可读清单，带级只构造它。
class TrackHalfBeatOverlayInput {
  const TrackHalfBeatOverlayInput({
    required this.axis,
    required this.window,
    required this.halfBeatLines,
    required this.beatRowRect,
    required this.anchorKeyOf,
    required this.dragFamilies,
    required this.dragDomain,
    required this.onDragVisualsBegin,
    required this.onDragPreviewFrame,
    required this.onDragVisualsEnd,
  });

  /// 带内横向几何（线 x 求值、换算与密度护栏的标尺）。
  final TimelineAxis axis;

  /// 本帧可视窗口：线在窗与否的判据。
  final TimelineWindow window;

  /// 半拍线时刻表（按时间升序）。
  final List<Duration> halfBeatLines;

  /// 节拍轨行矩形（带内顶/高）：命中列的唯一载体；行不在本行集内时为 null
  /// （整层不渲染）。
  final TrackRowRect? beatRowRect;

  /// 线下标 → 角标锚点键（null = 本会话未记着该序号，不包）。
  final String? Function(int index) anchorKeyOf;

  /// 带内拖动手势域的共享注册表：本族的声明条目经它按族登记。
  final TrackBandDragFamilies dragFamilies;

  /// 带内拖动手势域：本族起手经它交回句柄。
  final TrackBandDragSession dragDomain;

  /// 拖动起手视觉（拖线实时预览起手）。
  final VoidCallback onDragVisualsBegin;

  /// 拖动逐帧落点视觉（拖线实时预览单帧）。
  final void Function(Duration landing) onDragPreviewFrame;

  /// 拖动收口视觉（拖线实时预览收尾；句柄缺席时也收一次）。
  final VoidCallback onDragVisualsEnd;
}

/// 半拍线覆盖层：插入半拍线的整族——线身视觉、节拍轨行内的点选与水平拖动、
/// 密度护栏与族声明登记，与节拍刻度同域。
///
/// **族随渲染走**：本域是半拍线族（`halfBeatLineMove`）的族主，声明条目经
/// 拖动域的按族登记入口登记；句柄字段与起手/逐帧/收口三件都住本域，带级
/// 只按行矩形与时间轴组装它。密度护栏是节拍域事实（读同一份节拍网格）；选中
/// toggle 经标注选中域写入，选中读面在本域订阅（刷新粒度收窄到本层）。
///
/// **坐标**：带侧以整条带大小的盒子组装本域（`Positioned.fill`），本域局部
/// 坐标因此与带内坐标同值；命中列纵向几何取输入的行矩形。
class TrackHalfBeatOverlay extends ConsumerStatefulWidget {
  const TrackHalfBeatOverlay({super.key, required this.input});

  final TrackHalfBeatOverlayInput input;

  @override
  ConsumerState<TrackHalfBeatOverlay> createState() =>
      _TrackHalfBeatOverlayState();
}

class _TrackHalfBeatOverlayState extends ConsumerState<TrackHalfBeatOverlay> {
  /// 本族起手交回的域句柄：逐帧与收口只经本族自己的句柄（跨族覆盖后旧句柄
  /// 由域的世代守卫变成空操作）。
  TrackBandDragHandle? _dragHandle;

  /// 拖动中的线下标（驱动视觉反馈）。
  int? _draggingIndex;

  @override
  void initState() {
    super.initState();
    _registerFamily();
  }

  @override
  void didUpdateWidget(TrackHalfBeatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 重登记即覆盖同一条（声明本体读本 State 的当前 widget）。
    _registerFamily();
  }

  /// 本族的声明条目经拖动域的按族登记入口提交：钳到带内、静默准入、不记
  /// 偏移；收口是**条件刷新**——无拖动视觉簿记时不动 setState。
  void _registerFamily() {
    widget.input.dragFamilies.register(
      AnnotationGestureTarget.halfBeatLineMove,
      TrackBandDragDeclaration(
        toTime: (localX, _) => dragTimeAt(widget.input.axis, localX),
        beginSession: (target) =>
            ref.read(annotationEditorProvider).beginHalfBeatDrag(target.index),
        onBegin: (target) {
          setState(() => _draggingIndex = target.index);
          widget.input.onDragVisualsBegin();
        },
        onFrame: widget.input.onDragPreviewFrame,
        onEnd: _endVisuals,
      ),
    );
  }

  /// 起手（命中解析留在带侧，这里只把线下标包成目标身份）。
  void _beginDrag(int index) {
    _dragHandle = widget.input.dragDomain.begin(
      TrackBandDragTarget.halfBeat(index),
      0,
    );
  }

  /// 逐帧：只经本族句柄（钳制、换算、落点钩子在域内只写一次）。
  void _updateDrag(Offset globalPosition) {
    final box = context.findRenderObject();
    _dragHandle?.moveTo(
      box is RenderBox ? box.globalToLocal(globalPosition).dx : 0,
    );
  }

  /// 拖动结束：句柄收口（幂等）；无会话（起手被拒）时也收一次视觉与实时预览
  /// （收尾无条件）。
  void _endDrag() {
    final handle = _dragHandle;
    _dragHandle = null;
    if (handle == null) {
      _endVisuals();
      return;
    }
    handle.end();
  }

  /// 收口视觉（声明收口钩子与「无会话可收」两条路径共用）：**条件刷新**
  /// ——无拖动视觉簿记时不动 setState。
  void _endVisuals() {
    if (_draggingIndex != null) {
      setState(() => _draggingIndex = null);
    }
    widget.input.onDragVisualsEnd();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final rect = input.beatRowRect;
    if (rect == null) return const SizedBox.shrink();
    // 密度护栏读同一份节拍网格；选中读面只驱动本层重绘。
    final grid = ref.watch(beatGridProvider);
    final selectedIndex = ref.watch(selectedHalfBeatLineIndexProvider);
    final axis = input.axis;
    // 半拍格点屏上间距的标尺：只看当前渲染窗口的几何事实。
    final spanUs =
        ((axis.window?.end ?? axis.total) -
                (axis.window?.start ?? Duration.zero))
            .inMicroseconds;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < input.halfBeatLines.length; i++)
          if (input.window.contains(input.halfBeatLines[i]))
            _buildLine(
              index: i,
              position: input.halfBeatLines[i],
              rect: rect,
              grid: grid,
              selected: selectedIndex == i,
              spanUs: spanUs,
              axis: axis,
            ),
      ],
    );
  }

  /// 插入半拍线：冷灰蓝短线（同拍 1 粗、比拍 1 略长）垂直居中。命中区 =
  /// **节拍轨行内**的线身及其 ±[kSegmentLineHitWidth]/2 命中列（范围仅限节拍
  /// 轨行，学习段行/轨道手柄带不响应）：单击 = 选中 toggle（与分段线/首尾端标
  /// 共用单选槽；选中视觉 = 主青高亮）；水平拖动精调（复用分段线拖动会话/
  /// 预览 seam——模块 MoveHalfBeatLine 管线 + 拖线实时预览；拖动逐帧原始指针
  /// 位置，模块内吸附最近半拍格点并做合法域/越邻钳制，写后真实落点驱动预览）。
  /// **不受锁定分段**（锁只护分段结构）：锁定时拖动照常参与、照常写；点选
  /// 不受锁。
  Widget _buildLine({
    required int index,
    required Duration position,
    required TrackRowRect rect,
    required BeatGrid grid,
    required bool selected,
    required int spanUs,
    required TimelineAxis axis,
  }) {
    final x = axis.timeToX(position);
    const hitWidth = kSegmentLineHitWidth;
    // 密度护栏——只看当前渲染窗口的几何事实：该线所在相邻拍点区间的半拍
    // 格点屏上间距（区间拍长之半按窗口像素标尺换算；占位网格与异常兜底网格
    // 同值均匀，照常取值）。低于下限不注册水平拖动（识别器不进手势竞争 →
    // 横拖落到整条轨道的进度拖动）；有界网格末拍取前一相邻区间的拍长。拍边界
    // 求值走 beatBoundaryAt 单一守卫（含负序号钳制与末拍 nextBeat = null），
    // 不另写钳制。
    final boundary = grid.beatBoundaryAt(position);
    final beatLen = boundary.nextBeat != null
        ? boundary.nextBeat! - boundary.beatStart
        // 有界网格首拍即末拍（单拍网格）：无相邻区间，保守判密不可拖。
        : boundary.index > 0
        ? boundary.beatStart - grid.beatTime(boundary.index - 1)
        : Duration.zero;
    // 间距按窗口标尺线性换算，不走 timeToX 差值：区间搭在窗缘时 timeToX
    // 的越界钳制会把间距算小（误判密），标尺换算不受窗缘影响。
    final halfBeatSpacingPx = spanUs > 0 && !axis.isEmpty
        ? beatLen.inMicroseconds / spanUs * axis.contentWidth / 2
        : 0.0;
    final draggable = halfBeatSpacingPx >= kHalfBeatDragMinSpacingDp;
    // 线身（角标锚点包在这一层：上报矩形恰是新落的那根半拍线，不含命中列）。
    final line = _guideAnchored(
      widget.input.anchorKeyOf(index),
      ColoredBox(
        key: ValueKey('half_beat_line_$index'),
        color: selected ? kSegmentLineSelectedColor : kHalfBeatLineColor,
        child: SizedBox(
          width: kHalfBeatLineThickness,
          height: _draggingIndex == index
              ? kHalfBeatLineHeight + 4
              : kHalfBeatLineHeight,
        ),
      ),
    );
    return Positioned(
      key: ValueKey('half_beat_line_hit_$index'),
      left: x - hitWidth / 2,
      // 命中列仅限节拍轨行（学习段轨 → 轨间隙 → 节拍轨行）。
      top: rect.top,
      height: rect.height,
      width: hitWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 对比态只读：只读选中不参与，静默。
        onTap: () {
          if (ref
              .read(annotationEditorProvider)
              .gestureStartRejected(AnnotationGestureTarget.halfBeatLineTap)) {
            return;
          }
          ref
              .read(annotationSelectionDomainProvider)
              .toggle(HalfBeatLineSelection(index));
        },
        onHorizontalDragStart: draggable
            ? (_) => _beginDrag(index)
            : null,
        onHorizontalDragUpdate: draggable
            ? (details) => _updateDrag(details.globalPosition)
            : null,
        onHorizontalDragEnd: draggable ? (_) => _endDrag() : null,
        onHorizontalDragCancel: draggable ? _endDrag : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [Center(child: IgnorePointer(child: line))],
        ),
      ),
    );
  }
}

/// 非空锚点 key 时给 [child] 包一层锚点包装器（null 原样返回）——角标只在
/// 本会话记着的序号对上时才包，其余时刻被包内容逐位不变。
Widget _guideAnchored(String? anchorKey, Widget child) => anchorKey == null
    ? child
    : GuideAnchor(anchorKey: anchorKey, child: child);
