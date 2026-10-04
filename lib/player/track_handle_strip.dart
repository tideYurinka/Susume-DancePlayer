/// 轨道手柄带域：轨道带底行（轨道手柄带行）
/// 里三类控制柄的**槽位求值与摆位**、widget 装配与手势接线，外加端点键盘
/// 微调件与线段取色。
///
/// 收一个显式输入值对象 [TrackHandleStripInput]：行矩形、时间轴与窗口、带宽、
/// 分段线几何与选中、首/尾线时间、带级事实（拖动中线下标、引导角标序号）与
/// 「该层回调」一次给全，外加**拖动域句柄**（[TrackBandDragSession]）。控制柄槽按
/// 等分互斥分区分配（[assignHandleSlots]），把手几何走 [planHandleBar]、落位
/// 走 [handleBarLeft]、设备像素吸附走 [snapToDevicePixel] / [snapRectToDevicePixels]
/// ——本域不另算几何。三类手柄：首线、尾线、分段线。
///
/// ## 两族拖动（首尾端标 / 分段线）
///
/// 本域是这两族的族主：两族的 [TrackBandDragDeclaration] 条目住在本域，经
/// 拖动域的按族登记入口 [TrackBandDragFamilies.register] 登记（族与它的渲染
/// 同处）。逐帧与收口只经 [TrackBandDragHandle]；起手被拒、被预览线接管或
/// 双指让位时域里没有会话，收口照旧把视觉簿记与实时预览各收一次（与换手前
/// 一致）。两族的句柄字段与起手/逐帧/收口包装因此住在**本域**，带级 State
/// 不再持有它们。
///
/// ## 预览线拖动族（第九族）
///
/// 起手落在预览线命中列内即转预览线拖动——本域是这一族的**手势起手方**：控制柄
/// 的 drag start 先问拖动域「预览线拖动族接不接」（族的准入 = 本次起手的带内
/// 局部 x 落在预览线命中列内，声明住带级装配），接下则本手势整场只经那一族的
/// 句柄，否则回落既有拖线/拖首尾语义。
///
/// ## 依赖方向（单向）
///
/// 本域 → 拖动域（按族登记入口、目标身份与句柄）+ 控制柄纯件
/// `handle_strip.dart` + 轨道行表值对象 `track_row_table.dart` + 几何与时间
/// 值对象 `track_time.dart` + 标注编辑模块（拖动会话协议与门禁目标）+
/// 分段线值对象 + 帮助域两件（控制柄承载的角标锚点 key 与锚点包装件）+
/// 集中视觉常量，**单向**：不 import 轨道带 / 控制层 / 演出层 / 播放页，
/// 不读 provider、不碰容器句柄、不注容器（角标包装件 `GuideAnchor` 自带它，
/// 属被包内容的既有实现）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;

import '../annotation/segment_line.dart' show SegmentLine;
import '../help/content_registry.dart'
    show segmentLine0HandleAnchorKey, segmentLineHandleAnchorKey;
import '../help/guide_anchor.dart' show GuideAnchor;
import 'annotation_editor.dart'
    show AnnotationGestureTarget, DurationDragSession;
import 'annotation_selection.dart' show VideoRangeBoundary;
import 'handle_strip.dart';
import 'track_band_drag.dart';
import 'track_row_table.dart' show TrackRowRect;
import 'track_time.dart' show TimelineAxis, TimelineWindow;
import 'visual_tokens.dart'
    show
        kKeyboardFocusHighlight,
        kSegmentLineColor,
        kSegmentLineFlaggedColor,
        kSegmentLineSelectedColor,
        kVideoRangeEndLineColor,
        kVideoRangeStartLineColor;

/// 控制柄的键盘焦点描边：与把手同几何外扩的
/// 内距与线宽——纯视觉、`IgnorePointer` 包住，不占命中、不改视觉尺寸。
const double kHandleFocusRingInset = 2;
const double kHandleFocusRingWidth = 2;

/// 轨道手柄带域的显式输入值对象：本帧的几何与选中事实 + 带级事实 +「该层
/// 回调」+ 拖动域句柄。加一项输入只改这里与带侧那一处装配。
class TrackHandleStripInput {
  const TrackHandleStripInput({
    required this.rowRect,
    required this.axis,
    required this.window,
    required this.bandWidth,
    required this.segmentLines,
    required this.rangeStart,
    required this.rangeEnd,
    required this.selectedSegmentLineIndex,
    required this.draggingSegmentLineIndex,
    required this.segmentSelectIndex,
    required this.dragDomain,
    required this.segmentToTime,
    required this.rangeToTime,
    required this.beginSegmentLineSession,
    required this.beginRangeSession,
    required this.onSegmentLineDragVisual,
    required this.onRangeDragActive,
    required this.onBeginLineDragPreview,
    required this.onLineDragPreviewFrame,
    required this.onEndLineDragPreview,
    required this.bandLocalX,
    required this.resolveSegmentLineIndex,
    required this.onSegmentHandleTap,
    required this.onRangeHandleTap,
    required this.onSegmentHandleNudge,
    required this.onRangeHandleNudge,
  });

  /// 轨道手柄带行矩形（带内顶/高）：控制柄的唯一载体，行不在本行集内时带侧
  /// 一并不渲染本域。
  final TrackRowRect rowRect;

  /// 带内横向几何（线 x 求值、内容区左缘）。
  final TimelineAxis axis;

  /// 本帧可视窗口：线在窗与否的判据（槽位求值仍用全部线）。
  final TimelineWindow window;

  /// 带宽（控制柄槽分区与把手钳制的边界）。
  final double bandWidth;

  /// 分段线（含 flag）：槽位求值、在窗判据与控制柄取色的几何来源。
  final List<SegmentLine> segmentLines;

  /// 首线时间。
  final Duration rangeStart;

  /// 尾线时间。
  final Duration rangeEnd;

  /// 选中的分段线下标（null = 未选中）。
  final int? selectedSegmentLineIndex;

  /// 拖动中的分段线下标（null = 无）：带级持有该事实（同一序号同时驱动线身
  /// 与把手的选中观感），本域只读它取色。
  final int? draggingSegmentLineIndex;

  /// 本会话记下的新落线序号（null = 取不到）：该柄多包一枚角标锚点。
  final int? segmentSelectIndex;

  /// 拖动域句柄：两族声明经它的按族登记入口提交，起手/逐帧/收口经它。
  final TrackBandDragSession dragDomain;

  /// 分段线族的逐帧换算（带内局部 x → 请求时间；轴来源在带侧现势求值、
  /// 与首尾端标族共用同一条）。
  final Duration? Function(double localX, double bandWidth) segmentToTime;

  /// 首尾端标族的逐帧换算（与分段线族同源：带侧现势求值总时长与生效窗口）。
  final Duration? Function(double localX, double bandWidth) rangeToTime;

  /// 分段线族的模块会话工厂（起手判定全部通过后才调用）。
  final DurationDragSession Function(int index) beginSegmentLineSession;

  /// 首尾端标族的模块会话工厂。
  final DurationDragSession Function(VideoRangeBoundary boundary)
  beginRangeSession;

  /// 视觉簿记：分段线拖动中下标（起手写、收口清 null）。
  final void Function(int? index) onSegmentLineDragVisual;

  /// 首尾端标拖动在场事实（起手成立写 true、收口写 false）：带级的两处手势
  /// 仲裁（scale 会话起点是否清选中、空白横滑是否让位）读它——与族句柄同源，
  /// 不读拖动域的活动槽（那会把别的族也算进来）。
  final void Function(bool active) onRangeDragActive;

  /// 拖线实时预览起手。
  final VoidCallback onBeginLineDragPreview;

  /// 拖线实时预览逐帧（写后真实落点）。
  final void Function(Duration landing) onLineDragPreviewFrame;

  /// 拖线实时预览收尾（声明收口钩子与「无会话可收」两条路径共用）。
  final VoidCallback onEndLineDragPreview;

  /// 全局位置 → 带内局部 x（无渲染盒 = 空）。
  final double? Function(Offset globalPosition) bandLocalX;

  /// 按下瞬间位置命中的分段线下标（null = 未命中，回落命中层携带的下标）。
  final int? Function(Offset globalPosition) resolveSegmentLineIndex;

  /// 分段线控制柄点按（交回解析后的线下标）。
  final void Function(int index) onSegmentHandleTap;

  /// 首/尾线控制柄点按（交回端别）。
  final void Function(VideoRangeBoundary boundary) onRangeHandleTap;

  /// 分段线控制柄键盘微调（方向 −1 = 左、+1 = 右）。
  final void Function(int index, int direction) onSegmentHandleNudge;

  /// 首/尾线控制柄键盘微调。
  final void Function(VideoRangeBoundary boundary, int direction)
  onRangeHandleNudge;
}

/// 轨道手柄带域：三类控制柄的槽位求值与摆位 + 手势接线 + 键盘替代路径。
///
/// 带侧把它放进整条带大小的盒子里（`Positioned.fill`），于是本域内部坐标与
/// 带内坐标同值；带只组装，不转发族内调用。
class TrackHandleStrip extends StatefulWidget {
  const TrackHandleStrip({super.key, required this.input});

  final TrackHandleStripInput input;

  @override
  State<TrackHandleStrip> createState() => _TrackHandleStripState();
}

class _TrackHandleStripState extends State<TrackHandleStrip> {
  /// 本族起手交回的域句柄：逐帧与收口只经本族自己的句柄（跨族覆盖后旧句柄
  /// 由域的世代守卫变成空操作）。同族的首线/尾线共用一个槽。
  TrackBandDragHandle? _segmentLineDragHandle;
  TrackBandDragHandle? _rangeDragHandle;

  /// 第九族（预览线拖动）本手势的句柄：非空 = 本次手势已转预览线拖动，逐帧
  /// 与收口只经它（「吃掉本帧」因此是持句柄这条结构事实，不是第二份布尔）。
  TrackBandDragHandle? _previewLineDragHandle;

  /// 控制柄命中区内**按下瞬间**的位置：拖动识别器过 slop 后才回调 drag
  /// start，其 globalPosition 已含 slop 前位移——最近线判定必须用按下位置，
  /// 密集线重叠时才取到真正更近的一条。
  Offset _lineDownPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _registerFamilies();
  }

  @override
  void didUpdateWidget(TrackHandleStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 登记表按门禁目标成唯一键：重登记即覆盖同一条（声明本体读的是本 State
    // 的当前 widget，运行中的句柄各自持有起手时的声明快照，不受影响）。
    _registerFamilies();
  }

  /// 两族的声明条目经拖动域的**按族登记入口**提交：门禁目标、准入门、轴来源、
  /// 模块会话工厂与视觉/落点钩子逐族如实声明，不统一任何差别。
  void _registerFamilies() {
    widget.input.dragDomain.families
      ..register(
        AnnotationGestureTarget.segmentLineMove,
        TrackBandDragDeclaration(
          toTime: widget.input.segmentToTime,
          // 被分段锁拒绝时弹一次「已锁定分段」（对比态/组员方案只读静默）。
          promptOnGateReject: true,
          beginSession: (target) =>
              widget.input.beginSegmentLineSession(target.index),
          onBegin: (target) {
            widget.input.onSegmentLineDragVisual(target.index);
            widget.input.onBeginLineDragPreview();
          },
          onFrame: (landing) => widget.input.onLineDragPreviewFrame(landing),
          onEnd: () {
            widget.input.onSegmentLineDragVisual(null);
            widget.input.onEndLineDragPreview();
          },
        ),
      )
      ..register(
        AnnotationGestureTarget.rangeBoundaryDrag,
        TrackBandDragDeclaration(
          toTime: widget.input.rangeToTime,
          // 被门禁拒时弹一次提示；不预检索引、不记偏移。
          promptOnGateReject: true,
          beginSession: (target) => widget.input.beginRangeSession(
            (target as RangeDragTarget).boundary,
          ),
          onBegin: (_) => widget.input.onBeginLineDragPreview(),
          onFrame: (landing) => widget.input.onLineDragPreviewFrame(landing),
          onEnd: widget.input.onEndLineDragPreview,
        ),
      );
  }

  /// 第九族起手（语义：按下**瞬间**位置落在预览线命中列内即接管）：
  /// 命中列准入是那一族的声明（住带级装配），本域只把起手的带内局部 x 交给
  /// 拖动域、按域的回答决定接不接——接下即本手势整场转预览线拖动。
  bool _beginPreviewLineDrag() {
    final localX = widget.input.bandLocalX(_lineDownPosition);
    if (localX == null) return false;
    final handle = widget.input.dragDomain.begin(
      const TrackBandDragTarget.previewLine(),
      localX,
    );
    if (handle == null) return false;
    _previewLineDragHandle = handle;
    return true;
  }

  /// 第九族逐帧：只经本族句柄（钳制、换算、吸附、贴边平移与 seek 落点都在域与
  /// 声明的钩子里）；本域不判是否接管——持着句柄就是接管。
  void _updatePreviewLineDrag(Offset globalPosition) {
    final localX = widget.input.bandLocalX(globalPosition);
    if (localX == null) return;
    _previewLineDragHandle?.moveTo(localX);
  }

  /// 第九族收口（幂等；抬指与取消同路）：吸附复位与贴边平移停止在声明的收口
  /// 钩子里。
  void _endPreviewLineDrag() {
    final handle = _previewLineDragHandle;
    _previewLineDragHandle = null;
    handle?.end();
  }

  /// 分段线控制柄起手（无长按先决）：按下瞬间的最近线判定留在带侧
  /// （本域只收解析答案），起手门序言、模块会话、视觉簿记与实时预览起手全部
  /// 经拖动域（双指让位 → 装载门 → 门禁表 → 准入 → 边界 → 模块会话 →
  /// 起手钩子只写一次）。
  void _beginSegmentLineDrag(int fallbackIndex, Offset globalPosition) {
    final index =
        widget.input.resolveSegmentLineIndex(_lineDownPosition) ??
        fallbackIndex;
    _segmentLineDragHandle = widget.input.dragDomain.begin(
      TrackBandDragTarget.segmentLine(index),
      widget.input.bandLocalX(globalPosition) ?? 0,
    );
  }

  /// 分段线逐帧更新：只经本族句柄（跨族覆盖由域的世代守卫吸收；无会话或
  /// 预览线接管时为空操作）。
  void _updateSegmentLineDrag(Offset globalPosition) => _segmentLineDragHandle
      ?.moveTo(widget.input.bandLocalX(globalPosition) ?? 0);

  /// 分段线拖动收口：句柄收口（幂等；onDragEnd 与取消同走 end）——模块会话、
  /// 视觉清除与实时预览收尾都经域与声明钩子。起手被门禁拒或被预览线接管时
  /// 域里没有会话，视觉字段与实时预览照旧清一次（与换手前的无条件收尾一致）。
  void _endSegmentLineDrag() {
    final handle = _segmentLineDragHandle;
    _segmentLineDragHandle = null;
    if (handle == null) {
      _clearSegmentLineDragVisuals();
      return;
    }
    handle.end();
  }

  /// 分段线拖动的视觉收尾（声明收口钩子与「无会话可收」两条路径共用）。
  void _clearSegmentLineDragVisuals() {
    widget.input.onSegmentLineDragVisual(null);
    widget.input.onEndLineDragPreview();
  }

  /// 首尾端标拖动起手（门序言、模块会话与实时预览
  /// 全部经拖动域；被门禁拒时由声明的提示钩子弹一次「已锁定分段」）。
  void _beginRangeDrag(VideoRangeBoundary boundary) {
    final handle = widget.input.dragDomain.begin(
      TrackBandDragTarget.range(boundary),
      0,
    );
    _rangeDragHandle = handle;
    // 起手成立才报在场（起手被拒/被接管时与「无句柄」同义）。
    if (handle != null) widget.input.onRangeDragActive(true);
  }

  /// 首尾端标拖动更新：逐帧只经本族句柄（换算、钳制与实时预览钩子在域内）。
  void _updateRangeDrag(Offset globalPosition) =>
      _rangeDragHandle?.moveTo(widget.input.bandLocalX(globalPosition) ?? 0);

  /// 首/尾线拖动结束：句柄收口（幂等；无净变化不入史）；无会话（起手被拒）
  /// 时也收一次实时预览。
  void _endRangeDrag() {
    final handle = _rangeDragHandle;
    _rangeDragHandle = null;
    widget.input.onRangeDragActive(false);
    if (handle == null) {
      widget.input.onEndLineDragPreview();
      return;
    }
    handle.end();
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    // 设备像素对齐：等距缝除不尽（32dp 下 4.4dp）时把
    // 条左缘与纹路左右缘都吸附到设备像素栅格——条缘先吸（条在带内的
    // 屏上原点归栅格），纹在吸后的条内再吸局部坐标，1× 下不出现 4/5
    // 交替的「不匀」。只吸边缘、不改纯函数输出的几何计划。
    final dpr = View.of(context).devicePixelRatio;
    Rect snapGroove(Rect r) => snapRectToDevicePixels(r, dpr);

    // 槽位换算：全部线（首边界 + 分段线 + 尾边界）的 x 序列，按时间升序。
    // 首尾与近邻共同参与等分互斥分区（窗口外的线也约束相邻槽宽）。
    final positions = <double>[
      input.axis.timeToX(input.rangeStart),
      for (final line in input.segmentLines) input.axis.timeToX(line.position),
      input.axis.timeToX(input.rangeEnd),
    ];
    final slots = assignHandleSlots(
      positions: positions,
      bandWidth: input.bandWidth,
      contentLeft: input.axis.contentLeft,
    );

    /// 单个控制柄：槽区（补偿后的 [slot] 命中区间）承载手势；把手视觉
    /// （几何取自 [planHandleBar]）以线心居中、钳在槽内、行内垂直居中。
    Widget handle({
      required HandleSlot slot,
      required double barCenter,
      required Key barKey,
      required Color barColor,
      required GestureTapUpCallback onTapUp,
      required GestureDragStartCallback onDragStart,
      required GestureDragUpdateCallback onDragUpdate,
      required VoidCallback onDragEnd,
      required ValueChanged<int> onNudge,
      required Key focusRingKey,
      List<String> guideAnchorKeys = const [],
    }) {
      // 密集线把手随槽收缩（语义保留）：条宽 = min(上限, 槽宽)，
      // 纹数随条宽退化，几何全部取自 [planHandleBar] 纯函数，渲染件不
      // 自己算几何；乱序/退化槽防御性归一：
      // [handleBarLeft] 先归一再钳制，避免 build 阶段下界>上界红屏。
      final plan = planHandleBar(
        slotWidth: math.max(0.0, slot.hitWidth),
        maxBarWidth: kHandleBarWidth,
        barHeight: kHandleBarHeight,
        rowHeight: input.rowRect.height,
        stroked: true,
      );
      final barLeft = snapToDevicePixel(
        handleBarLeft(
          barCenter: barCenter,
          barWidth: plan.barWidth,
          hitLeft: slot.hitLeft,
          hitRight: slot.hitRight,
          bandWidth: input.bandWidth,
        ),
        dpr,
      );
      return Positioned(
        left: slot.hitLeft,
        width: slot.hitWidth,
        // 命中区纵向几何取自行集的手柄带行矩形（顶 + 高）；
        // 非缺省行集可把手柄带行放在带内任意位置。
        top: input.rowRect.top,
        height: input.rowRect.height,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          // 按下瞬间位置（密集线槽重叠时最近线判定用，语义保留）。
          onPointerDown: (event) => _lineDownPosition = event.position,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onTapUp,
            //  预览线优先三段式（分段线/首尾线控制柄一致，唯一落点；
            //  起整段走拖动域第九族）：起手落在预览线命中列内 → 本
            // 手势转预览线拖动（族在域里接下），不再进既有拖线/拖首尾逻辑；
            // 持着那一族句柄期间逐帧一律吃掉本帧（双指冻结期也不回落到拖线）；
            // 结束统一收口。
            onHorizontalDragStart: (details) {
              if (_beginPreviewLineDrag()) return;
              onDragStart(details);
            },
            onHorizontalDragUpdate: (details) {
              if (_previewLineDragHandle != null) {
                _updatePreviewLineDrag(details.globalPosition);
                return;
              }
              onDragUpdate(details);
            },
            onHorizontalDragEnd: (_) {
              _endPreviewLineDrag();
              onDragEnd();
            },
            onHorizontalDragCancel: () {
              _endPreviewLineDrag();
              onDragEnd();
            },
            child: _EndpointKeyboardHandle(
              onNudge: onNudge,
              // 焦点描边（键盘替代路径的可见性）：与把手同几何、
              // 外扩 [kHandleFocusRingInset]，`IgnorePointer` 包住不参与
              // 命中——视觉尺寸与手势仲裁逐位不变。
              focusRing: Positioned(
                left: barLeft - slot.hitLeft - kHandleFocusRingInset,
                top: plan.rowOffsetY - kHandleFocusRingInset,
                width: plan.barWidth + 2 * kHandleFocusRingInset,
                height: plan.barHeight + 2 * kHandleFocusRingInset,
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: focusRingKey,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: kKeyboardFocusHighlight,
                        width: kHandleFocusRingWidth,
                      ),
                      borderRadius: BorderRadius.circular(
                        plan.cornerRadius + kHandleFocusRingInset,
                      ),
                    ),
                  ),
                ),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: barLeft - slot.hitLeft,
                    top: plan.rowOffsetY,
                    width: plan.barWidth,
                    height: plan.barHeight,
                    // 把手（控制柄）承载的锚点各包一层：被包把手的行为与外观
                    // 逐位不变；同一根柄上可同时挂两枚（分段第 ① 步与编辑态上手
                    // 第 3 步），逐层嵌套、互不顶替。
                    child: _guideAnchoredAll(
                      guideAnchorKeys,
                      KeyedSubtree(
                        key: barKey,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(
                              plan.cornerRadius,
                            ),
                            border: plan.strokeWidth > 0
                                ? Border.fromBorderSide(
                                    BorderSide(
                                      width: plan.strokeWidth,
                                      color: plan.strokeColor,
                                    ),
                                  )
                                : null,
                          ),
                          // 描边画在框内 ⇒ 纹路按内容盒摆位（不重复计入
                          // 描边宽）；条收窄后纹数为 0 时只留实心胶囊。
                          child: plan.grooves.isEmpty
                              ? null
                              : Padding(
                                  padding: EdgeInsets.all(plan.strokeWidth),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      plan.cornerRadius - plan.strokeWidth,
                                    ),
                                    child: Stack(
                                      children: [
                                        for (final groove in plan.grooves.map(
                                          snapGroove,
                                        ))
                                          Positioned(
                                            left: groove.left,
                                            top: groove.top,
                                            width: groove.width,
                                            height: groove.height,
                                            child: const ColoredBox(
                                              color: kHandleGrooveColor,
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
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 栈序（既有命中优先级「线 > 首尾 > 段体」保留）：首/尾线控制柄
    // 在底、分段线控制柄在上——分段线与首/尾线控制柄槽重叠（近距 < min24）时
    // 按下命中分段线控制柄；分段线之间的重叠仍由最近线解析裁决。
    final children = <Widget>[
      // 首线控制柄（边缘线：外扩仍可抓，槽经贴屏边向内补偿）。
      if (input.window.contains(input.rangeStart))
        handle(
          slot: slots.first,
          barCenter: positions.first,
          barKey: const Key('video_range_start_marker'),
          focusRingKey: const Key('video_range_start_focus_ring'),
          barColor: kVideoRangeStartLineColor,
          onTapUp: (_) => input.onRangeHandleTap(VideoRangeBoundary.start),
          onDragStart: (_) => _beginRangeDrag(VideoRangeBoundary.start),
          onDragUpdate: (details) => _updateRangeDrag(details.globalPosition),
          onDragEnd: _endRangeDrag,
          onNudge: (direction) =>
              input.onRangeHandleNudge(VideoRangeBoundary.start, direction),
        ),
      // 尾线控制柄。
      if (input.window.contains(input.rangeEnd))
        handle(
          slot: slots.last,
          barCenter: positions.last,
          barKey: const Key('video_range_end_marker'),
          focusRingKey: const Key('video_range_end_focus_ring'),
          barColor: kVideoRangeEndLineColor,
          onTapUp: (_) => input.onRangeHandleTap(VideoRangeBoundary.end),
          onDragStart: (_) => _beginRangeDrag(VideoRangeBoundary.end),
          onDragUpdate: (details) => _updateRangeDrag(details.globalPosition),
          onDragEnd: _endRangeDrag,
          onNudge: (direction) =>
              input.onRangeHandleNudge(VideoRangeBoundary.end, direction),
        ),
      // 分段线控制柄（最上层：线 > 首尾）。
      for (var i = 0; i < input.segmentLines.length; i++)
        if (input.window.contains(input.segmentLines[i].position))
          handle(
            slot: slots[i + 1],
            barCenter: positions[i + 1],
            // 定位 key 与锚点 key 同字面量（同一拼法，见
            // [segmentLineHandleAnchorKey]）：两者不会各写一份而分家。
            barKey: Key(segmentLineHandleAnchorKey(i)),
            focusRingKey: Key('segment_line_${i}_handle_focus_ring'),
            // 控制柄承载的锚点：分段第 ① 步框住**刚落那条线的控制柄**
            // （锚点 key 按本会话记下的新落线序号拼出，连着落两条时改指第二
            // 条）与编辑态上手第 3 步（恒锚第 1 条，注册表声明
            // `segment_line_0_handle`）各报各的，共用同一根柄、互不顶替。
            guideAnchorKeys: [
              if (input.segmentSelectIndex == i) segmentLineHandleAnchorKey(i),
              if (i == 0) segmentLine0HandleAnchorKey,
            ],
            barColor: _segmentLineBarColor(
              input.segmentLines[i],
              selected:
                  input.selectedSegmentLineIndex == i ||
                  input.draggingSegmentLineIndex == i,
            ),
            onTapUp: (details) => input.onSegmentHandleTap(
              input.resolveSegmentLineIndex(details.globalPosition) ?? i,
            ),
            onDragStart: (details) =>
                _beginSegmentLineDrag(i, details.globalPosition),
            onDragUpdate: (details) =>
                _updateSegmentLineDrag(details.globalPosition),
            onDragEnd: _endSegmentLineDrag,
            onNudge: (direction) => input.onSegmentHandleNudge(i, direction),
          ),
    ];
    // 本域的盒子 = 整条带（带侧 Positioned.fill）：把手坐标与带内坐标同值；
    // 只有控制柄命中区吃指针，其余整片让给下层（`Stack` 自身不吸收命中）。
    return Stack(clipBehavior: Clip.none, children: children);
  }
}

/// 分段线控制柄取色（线段取色随域搬走）：flag 粗线一档、选中/拖线中一档、
/// 默认细线一档。
Color _segmentLineBarColor(SegmentLine line, {required bool selected}) {
  return line.flagged
      ? kSegmentLineFlaggedColor
      : selected
      ? kSegmentLineSelectedColor
      : kSegmentLineColor;
}

/// 非空锚点 key 时给 [child] 包一层锚点包装器（null 原样返回）——菜单类角标
/// 只在实物就是刚落成的那一个时才包，其余时刻被包内容逐位不变。
Widget _guideAnchored(String? anchorKey, Widget child) =>
    anchorKey == null ? child : GuideAnchor(anchorKey: anchorKey, child: child);

/// 多个锚点 key 逐层包住 [child]（顺序即嵌套序，被包内容逐位不变）：同一个
/// 实物（如一根分段线控制柄）可以同时承载两枚角标锚点，各报各的矩形、互不
/// 顶替（调用方只在本会话记着的序号对上时才给 key）。
Widget _guideAnchoredAll(List<String> anchorKeys, Widget child) {
  var wrapped = child;
  for (final anchorKey in anchorKeys) {
    wrapped = _guideAnchored(anchorKey, wrapped);
  }
  return wrapped;
}

/// 端点控制柄的键盘替代路径：控制柄落焦时
/// 左右方向键微调端点，焦点用 [focusRing] 描出（纯视觉、`IgnorePointer`）。
/// 触摸路径零改动——本件只叠一层 Focus/Listener，指针手势仍走原 GestureDetector。
class _EndpointKeyboardHandle extends StatefulWidget {
  const _EndpointKeyboardHandle({
    required this.onNudge,
    required this.focusRing,
    required this.child,
  });

  /// 方向键步进：-1 = 左（早）、+1 = 右（晚）。
  final ValueChanged<int> onNudge;

  /// 落焦时叠在把手上的焦点描边（几何与把手同源）。
  final Widget focusRing;

  final Widget child;

  @override
  State<_EndpointKeyboardHandle> createState() =>
      _EndpointKeyboardHandleState();
}

class _EndpointKeyboardHandleState extends State<_EndpointKeyboardHandle> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'track_endpoint');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      widget.onNudge(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      widget.onNudge(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Listener(
        // 点按控制柄一并落焦：键盘用户不必先 Tab 走一圈即可用方向键微调。
        onPointerDown: (_) => _focusNode.requestFocus(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [widget.child, if (_focused) widget.focusRing],
        ),
      ),
    );
  }
}
