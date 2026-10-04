/// 局部镜像轨域：局部镜像轨整行的自带 widget
/// 子树——片段块体、行级点按命中层，以及镜像两族拖动（整体移与端点拖）的
/// 句柄簿记与起手/逐帧/收口接线（行背景仍归带级组装，行键与行高由行表给）。
///
/// **依赖方向（单向）**：局部镜像轨域 → 拖动域（[TrackBandDragSession] /
/// [TrackBandDragFamilies] / 两族目标身份与声明）+ 区间片段行共用纯件
/// （[intervalBlockRect] / [IntervalSpan] / [IntervalEdge]）+ 块体骨架共享件
/// （[TrackFragmentRowShell]）+ 局部镜像纯件（[LocalMirrorFragment] /
/// [resolveLocalMirrorTapHit]）+ 轨道行表 / 时间轴与横向几何值对象 / 集中
/// 视觉常量；**不 import 带级文件**（track_band.dart），带级只组装、不转发。
///
/// **不碰容器句柄**：本域的全部外部事实经 [TrackMirrorRowInput] 一次给全
/// ——片段表、行矩形、时间轴与窗口、总开关与选中片序、角标锚点键、拖动域句
/// 柄与该行回调；构造参数里没有 Ref / ProviderContainer / WidgetRef，本域不
/// 读任何 provider。带内局部 x 的读取与「局部 x → 时间」的换算都留在带内装
/// 配、以回调注入（后者按族装配进本族的拖动声明，本域不向他族借方法）。
///
/// **命中入口公开**：行级片段命中解析是域公开面 [mirrorRowHitAt]（行内局部
/// x + 片段表 + 时间轴与窗口 → 片段下标），行级点按与命中解析适配层
/// （`track_hit_resolution.dart`）共用这一条解析；内层算法仍归纯件
/// [resolveLocalMirrorTapHit]。
///
/// **空白落穿留在带级**：行级点按命中空白时不吞指针，经
/// [TrackMirrorRowInput.onTapBlank] 把本次单击交回带级空白 tap 仲裁；本域不
/// 复刻第二份判定窗口。
///
/// **零行为变化**：本库的实现自 track_band.dart 原样搬移——块体
/// 矩形与端点带（含窄块整段抑制与贴块内侧）、整体移与端点拖的相对平移、行级
/// 点按命中与空白落穿、空片段表与窗口不含时的退化逐位不变；四处 Key 字符串
/// （`track_mirror` / `mirror_fragment_$index` /
/// `mirror_fragment_${index}_edge_${edge.name}` /
/// `mirror_fragment_${index}_icon`）逐位不变。
library;

import 'package:flutter/material.dart';

import '../annotation/interval_fragment_row.dart'
    show
        IntervalBlockRect,
        IntervalEdge,
        IntervalHitRegion,
        IntervalSpan,
        intervalBlockRect,
        intervalHitRegion;
import '../annotation/local_mirror.dart'
    show LocalMirrorFragment, resolveLocalMirrorTapHit;
import 'annotation_editor.dart' show DurationDragSession;
import 'track_band_drag.dart';
import 'track_fragment_row_shell.dart' show TrackFragmentRowShell;
import 'track_geometry.dart'
    show TrackBandGeometry, dragTimeAt, kTrackPrefixWidth;
import 'track_row_table.dart' show TrackRowRect;
import 'track_time.dart' show TimelineAxis, TimelineWindow;
import 'visual_tokens.dart';

/// 局部镜像轨域的显式输入：「这一行需要什么」是一份可读清单——
/// 片段表、行矩形、时间轴与窗口、总开关与选中片序、角标锚点键、拖动域句柄
/// 与该行的全部回调一次给全，带级只构造它、组装域件，不转发任何调用。
///
/// 按字段判等（[==]，含回调）：字段全等的两份输入（实例不同）不触发本域内容
/// 子树重建（见 [TrackMirrorRow]）。判等对回调按身份比较，故组装点传稳定
/// tear-off/字段时命中缓存，传逐帧新建的闭包时会照常重建——缓存是省重建的
/// 一道闸，不是「组装点必须传稳定回调」的契约。
class TrackMirrorRowInput {
  const TrackMirrorRowInput({
    required this.rowRect,
    required this.axis,
    required this.window,
    required this.fragments,
    required this.masterSwitchOn,
    required this.selectedIndex,
    required this.guideAnchorKeys,
    required this.dragFamilies,
    required this.dragSession,
    required this.beginSession,
    required this.localXOf,
    required this.onTapFragment,
    required this.onTapBlank,
    required this.onEditContentHit,
    required this.onDragVisualsBegin,
    required this.onDragFrame,
    required this.onDragVisualsEnd,
  });

  /// 局部镜像轨行矩形（带内顶与高）。
  final TrackRowRect rowRect;

  /// 时间轴（时间 ↔ 带内像素的唯一换算口径）。
  final TimelineAxis axis;

  /// 生效可视窗口（片段可见性与命中宽度换算共用）。
  final TimelineWindow window;

  /// 片段表（按起点升序、两两不重叠；空表 = 空轨）。
  final List<LocalMirrorFragment> fragments;

  /// 局部镜像总开关：片段块视觉全由它驱动（片段 = 纯区间，无自带启停位）。
  final bool masterSwitchOn;

  /// 选中片段下标（null = 无选中）。
  final int? selectedIndex;

  /// 片段序 → 非空锚点键（菜单类角标「刚落成的实物」序号对上时才包）。
  final String? Function(int index) guideAnchorKeys;

  /// 带内拖动手势域的**共享注册表**：两族声明经它按族登记（会话按它分派
  /// 起手），本域不私持第二份注册表。
  final TrackBandDragFamilies dragFamilies;

  /// 带内拖动手势域：两族起手经 [TrackBandDragSession.begin] 交回本族句柄。
  final TrackBandDragSession dragSession;

  /// 某一族的模块拖动会话工厂（起手判定全部通过后才调用）；门禁、钳制与
  /// 落点解析都在标注编辑模块内，本域只按族把它接进声明。
  final DurationDragSession Function(TrackBandDragTarget target) beginSession;

  /// 全局位置 → 带内局部 x（无渲染盒 = 空）；`globalToLocal` 与带宽读取都
  /// 留在带内装配（它们需要带级渲染盒）。
  final double? Function(Offset globalPosition) localXOf;

  /// 行级点按命中片段：片段下标（只选中）。
  final void Function(int index) onTapFragment;

  /// 行级点按落在轨道空白（全局位置）：不吞指针，交回带级空白 tap 仲裁。
  final void Function(Offset globalPosition) onTapBlank;

  /// 全局位置的行内片段命中（带级「编辑内容」判定问本行，与行级点按同一
  /// 条命中解析）：纵向带由组装点按行矩形先限定，本域只答横向命中。
  final bool Function(Offset globalPosition) onEditContentHit;

  /// 拖动起手视觉（实时预览起手）。
  final void Function() onDragVisualsBegin;

  /// 拖动逐帧落点视觉（拖线实时预览单帧）。
  final void Function(Duration landing) onDragFrame;

  /// 拖动收口视觉（实时预览收口；句柄缺席时也收一次，与换手前一致）。
  final void Function() onDragVisualsEnd;

  @override
  bool operator ==(Object other) =>
      other is TrackMirrorRowInput &&
      other.rowRect == rowRect &&
      other.axis == axis &&
      other.window == window &&
      other.fragments == fragments &&
      other.masterSwitchOn == masterSwitchOn &&
      other.selectedIndex == selectedIndex &&
      other.guideAnchorKeys == guideAnchorKeys &&
      other.dragFamilies == dragFamilies &&
      other.dragSession == dragSession &&
      other.beginSession == beginSession &&
      other.localXOf == localXOf &&
      other.onTapFragment == onTapFragment &&
      other.onTapBlank == onTapBlank &&
      other.onEditContentHit == onEditContentHit &&
      other.onDragVisualsBegin == onDragVisualsBegin &&
      other.onDragFrame == onDragFrame &&
      other.onDragVisualsEnd == onDragVisualsEnd;

  @override
  int get hashCode => Object.hashAll([
    rowRect,
    axis,
    window,
    fragments,
    masterSwitchOn,
    selectedIndex,
    guideAnchorKeys,
    dragFamilies,
    dragSession,
    beginSession,
    localXOf,
    onTapFragment,
    onTapBlank,
    onEditContentHit,
    onDragVisualsBegin,
    onDragFrame,
    onDragVisualsEnd,
  ]);
}

/// 局部镜像轨行级片段命中解析（域公开的命中入口）：行内局部 x + 片段列表 +
/// 时间轴与窗口 → 命中片段下标（null = 轨道空白）。
///
/// 内层算法仍归既有纯件 [resolveLocalMirrorTapHit]（最小命中宽对称扩展 + 多候
/// 选取距中心最近）；本函数只装配入参——由轴与窗口重新求横向几何（轨道片头
/// 让位的唯一常量 [kTrackPrefixWidth] 同源），不可映射即安静返回空。行级点按
/// 与命中解析适配层（`track_hit_resolution.dart`）共用本入口，不复制第二份
/// 判定窗口。
int? mirrorRowHitAt({
  required double localX,
  required List<LocalMirrorFragment> fragments,
  required TimelineAxis axis,
  required TimelineWindow window,
}) {
  final total = axis.total;
  if (total <= Duration.zero || axis.width <= 0) return null;
  final geometry = TrackBandGeometry.eval(
    total: total,
    window: window,
    width: axis.width,
    prefixWidth: kTrackPrefixWidth,
  );
  if (!geometry.isMappable) return null;
  final spanMs = window.end.inMilliseconds - window.start.inMilliseconds;
  // 像素→时间按内容区宽折算（片头不吃命中宽度口径）。
  if (spanMs <= 0 || axis.contentWidth <= 0) return null;
  return resolveLocalMirrorTapHit(
    fragments: fragments,
    timeMs: geometry.axis.xToTime(localX).inMilliseconds,
    minHitWidthMs: (kLocalMirrorTapHitWidth * spanMs / axis.contentWidth)
        .round(),
  );
}

/// 局部镜像轨整行子树（片段块体层 + 行级点按命中层）。
///
/// 两族的句柄簿记住在本 State 里（起手/逐帧/收口只经本族自己的句柄，跨族
/// 覆盖后旧句柄由域的世代守卫变成空操作）；两族的声明按族经
/// [TrackBandDragFamilies] 登记一次。输入按字段判等（[TrackMirrorRowInput]）：
/// 输入不变时整行子树不重建，输入真变才重建——拖动在跑的句柄住 State，不随
/// 子树缓存走。
class TrackMirrorRow extends StatefulWidget {
  const TrackMirrorRow({super.key, required this.input});

  /// 本行的全部显式依赖（见 [TrackMirrorRowInput]）。
  final TrackMirrorRowInput input;

  @override
  State<TrackMirrorRow> createState() => _TrackMirrorRowState();
}

class _TrackMirrorRowState extends State<TrackMirrorRow> {
  /// 镜像两族共用的域句柄（同族的整体移与端点拖互斥，共用一个槽）。
  TrackBandDragHandle? _dragHandle;

  /// 两族的目标身份模板（下标在每次起手时按命中结果给出）。
  static const TrackBandDragTarget _moveTarget = TrackBandDragTarget.mirrorMove(
    0,
  );
  static const TrackBandDragTarget _edgeTarget = TrackBandDragTarget.mirrorEdge(
    0,
    IntervalEdge.start,
  );

  @override
  void initState() {
    super.initState();
    // 两族的声明条目**随族**经按族注册入口登记进拖动域的共享注册表：抓取
    // 偏移与准入形状按本域持有的片段表如实声明，换算按本族装配。
    widget.input.dragFamilies.register(
      _moveTarget.gateTarget,
      _moveDeclaration,
    );
    widget.input.dragFamilies.register(
      _edgeTarget.gateTarget,
      _edgeDeclaration,
    );
  }

  /// 本族的片段表（准入与抓取偏移的判据源；随输入刷新）。
  List<LocalMirrorFragment> get _fragments => widget.input.fragments;

  /// 整体移族的声明：抓取偏移 = 手指 − 片段起点（拖动中请求的新起点 = 手指
  /// 时间 − 该偏移，保持抓取点在片段上的相对位置不变 = 相对平移，而非把片段
  /// 首锚到手指）。
  TrackBandDragDeclaration get _moveDeclaration => TrackBandDragDeclaration(
    toTime: _timeAt,
    beginSession: (target) => widget.input.beginSession(target),
    admit: _admitDrag,
    readGrabOffsetMs: (target, finger) =>
        finger.inMilliseconds - _fragments[target.index].startMs,
    onBegin: (_) => widget.input.onDragVisualsBegin(),
    onFrame: widget.input.onDragFrame,
    onEnd: widget.input.onDragVisualsEnd,
  );

  /// 端点拖族的声明：抓取偏移相对**被拖端点**记录（手指 − 该端当前时刻），
  /// 保持抓取点在该端上的相对位置。
  TrackBandDragDeclaration get _edgeDeclaration => TrackBandDragDeclaration(
    toTime: _timeAt,
    beginSession: (target) => widget.input.beginSession(target),
    admit: _admitDrag,
    readGrabOffsetMs: (target, finger) {
      final fragment = _fragments[target.index];
      final boundary =
          (target as MirrorEdgeDragTarget).edge == IntervalEdge.start
          ? fragment.startMs
          : fragment.endMs;
      return finger.inMilliseconds - boundary;
    },
    onBegin: (_) => widget.input.onDragVisualsBegin(),
    onFrame: widget.input.onDragFrame,
    onEnd: widget.input.onDragVisualsEnd,
  );

  /// 两族的越界准入：按片段列表长度静默返回（落点类准入不适用本族，
  /// 起手局部 x 不读）。
  bool _admitDrag(TrackBandDragTarget target, double _) {
    final index = target.index;
    return index >= 0 && index < _fragments.length;
  }

  /// 带内局部 x → 时间（本域唯一换算入口，拖动逐族换算与命中解析共用同一
  /// 条几何口径）：换算交规范层 [dragTimeAt]，总时长未知 / 带宽非正 / 几何
  /// 不可映射一律安静返回空（逐帧据此成为空操作）。轴取 build 期的本行输入。
  Duration? _timeAt(double localX, double bandWidth) {
    final geometry = TrackBandGeometry.eval(
      total: widget.input.axis.total,
      window: widget.input.window,
      width: bandWidth,
      prefixWidth: kTrackPrefixWidth,
    );
    return dragTimeAt(geometry.axis, localX);
  }

  /// 本行渲染盒（全局 → 行内局部坐标的唯一一处）。
  RenderBox? _box() {
    final box = context.findRenderObject();
    return box is RenderBox ? box : null;
  }

  /// 行级命中解析：全局位置 → 片段下标（null = 轨道空白）。
  ///
  /// 入参装配与内层算法归域公开的命中入口 [mirrorRowHitAt]（本行的
  /// `globalToLocal` 与带同宽、同横原点，故行内局部 x 即带内局部 x）；本处
  /// 只做全局 → 行内局部的换算。
  int? _resolveHit(Offset globalPosition, TrackMirrorRowInput input) {
    final x = _localX(globalPosition);
    if (x == null) return null;
    return mirrorRowHitAt(
      localX: x,
      fragments: input.fragments,
      axis: input.axis,
      window: input.window,
    );
  }

  /// 全局位置 → 行内局部横向坐标（无渲染盒 = 空）。
  double? _localX(Offset globalPosition) =>
      _box()?.globalToLocal(globalPosition).dx;

  /// 两族的起手：把下标与端点包成目标身份，带内局部 x（组装点的换算）交
  /// 域起手——门序言、准入、抓取偏移与模块会话全在域内，交回的句柄住本行。
  void _beginDrag(TrackBandDragTarget target, DragStartDetails details) {
    _dragHandle = widget.input.dragSession.begin(
      target,
      widget.input.localXOf(details.globalPosition) ?? 0,
    );
  }

  /// 两族的逐帧：经本族自己的句柄（钳制、抓取偏移、落点钩子都在域内只写
  /// 一次）。
  void _updateDrag(Offset globalPosition) {
    final handle = _dragHandle;
    if (handle == null) return;
    final x = widget.input.localXOf(globalPosition);
    if (x == null) return;
    handle.moveTo(x);
  }

  /// 两族的收口（onDragEnd / onDragCancel 共用）：句柄收口幂等；没有会话
  /// （起手被拒）时照旧收一次实时预览（与换手前的无条件收尾一致）。
  void _endDrag() {
    final handle = _dragHandle;
    _dragHandle = null;
    if (handle == null) {
      widget.input.onDragVisualsEnd();
      return;
    }
    handle.end();
  }

  /// 行级点按：命中即报片段下标；空白命中报全局位置落穿带级空白仲裁
  /// ——本层不复刻第二份判定窗口。
  void _handleTap(TapUpDetails details) {
    final hit = _resolveHit(details.globalPosition, widget.input);
    if (hit == null) {
      widget.input.onTapBlank(details.globalPosition);
      return;
    }
    widget.input.onTapFragment(hit);
  }

  /// 已建好的整行子树（输入按字段判等：输入不变时不重建，输入真变才重建）。
  Widget? _subtree;

  @override
  void didUpdateWidget(TrackMirrorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input != widget.input) _subtree = null;
  }

  @override
  Widget build(BuildContext context) => _subtree ??= _buildRow(widget.input);

  Widget _buildRow(TrackMirrorRowInput input) {
    final fragments = input.fragments;
    return Positioned(
      left: 0,
      top: input.rowRect.top,
      width: input.axis.width,
      height: input.rowRect.height,
      child: Stack(
        children: [
          // 片段块体层：几何经共用件求值（窗口外裁切、零宽与倒置降级不
          // 渲染），每块自带摆位与块体/端点带接线。
          for (var i = 0; i < fragments.length; i++)
            _TrackMirrorFragmentBlock(
              index: i,
              block: intervalBlockRect(
                span: IntervalSpan(
                  startMs: fragments[i].startMs,
                  endMs: fragments[i].endMs,
                ),
                window: IntervalSpan(
                  startMs: input.window.start.inMilliseconds,
                  endMs: input.window.end.inMilliseconds,
                ),
                trackWidth: input.axis.contentWidth,
                contentLeft: input.axis.contentLeft,
              ),
              // 外层 Positioned 已按行矩形落位，块壳只吃纵向高（顶归零）。
              rowRect: TrackRowRect(top: 0, height: input.rowRect.height),
              masterSwitchOn: input.masterSwitchOn,
              selected: input.selectedIndex == i,
              guideAnchorKey: input.guideAnchorKeys(i),
              onMoveDragStart: (details) =>
                  _beginDrag(TrackBandDragTarget.mirrorMove(i), details),
              onEdgeDragStart: (edge, details) =>
                  _beginDrag(TrackBandDragTarget.mirrorEdge(i, edge), details),
              onDragUpdate: _updateDrag,
              onDragEnd: _endDrag,
            ),
          // 行级点按层：整行解析点按 x → 命中纯函数
          //（[resolveLocalMirrorTapHit]）→ 命中即选中；空白落穿带级仲裁。
          Positioned(
            left: 0,
            top: 0,
            width: input.axis.width,
            height: input.rowRect.height,
            child: GestureDetector(
              // translucent：块体整体拖/端点拖起手仍达块内手势层，本层只认
              // tap（drag 起手后 tap 让位）。
              behavior: HitTestBehavior.translucent,
              onTapUp: _handleTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// 局部镜像片段块：叠于局部镜像轨的一枚区间块（[block] 为共用件求值结果，
/// null = 窗口外/零宽/带宽非正，不渲染）。
class _TrackMirrorFragmentBlock extends StatelessWidget {
  const _TrackMirrorFragmentBlock({
    required this.index,
    required this.block,
    required this.rowRect,
    required this.masterSwitchOn,
    required this.selected,
    required this.guideAnchorKey,
    required this.onMoveDragStart,
    required this.onEdgeDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final int index;

  /// 共用件 [intervalBlockRect] 求值出的块矩形；null = 不渲染。
  final IntervalBlockRect? block;

  final TrackRowRect rowRect;

  /// 局部镜像总开关：生效视觉 = 总开关开。
  final bool masterSwitchOn;

  final bool selected;

  final String? guideAnchorKey;

  final void Function(DragStartDetails details) onMoveDragStart;
  final void Function(IntervalEdge edge, DragStartDetails details)
  onEdgeDragStart;
  final void Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final block = this.block;
    if (block == null) return const SizedBox.shrink();
    // 生效视觉 = 总开关开（视觉全由总开关驱动）。生效 = 琥珀、
    // 不生效 = 灰（半透明白）。图标恒在（不生效也显示图标便于辨认是
    // 片段），生效在图标色区分。
    final active = masterSwitchOn;
    final baseColor = active
        ? kLocalMirrorEnabledColor
        : kLocalMirrorDisabledColor;
    final fillColor = active
        ? kLocalMirrorEnabledFill
        : kLocalMirrorDisabledFill;
    final barColor = selected ? Colors.white : baseColor;
    final width = block.width;
    // 窄块不绘反相图标：窄条里图标被压小/裁切变形。信息不丢——
    // 生效/不生效由总开关驱动的填充 + 描边色承载（琥珀/灰）、选中
    // 由描边承担；宽块仍绘图标（行为不变）。判据取共用谓词（块壳内同一
    // 条规则决定端点带渲染）。
    final isNarrow = _isNarrowBlock(
      blockWidth: width,
      edgeBandWidth: kLocalMirrorEdgeHitWidth,
      narrowWidth: kLocalMirrorNarrowWidth,
    );
    return TrackFragmentRowShell(
      blockKey: ValueKey('mirror_fragment_$index'),
      guideAnchorKey: guideAnchorKey,
      block: block,
      rowRect: rowRect,
      // 端点带贴块内侧、窄块整段抑制（既有口径，行为零变化；的
      // 命中域让位只改备注轨）。
      startEdgeBandWidth: isNarrow ? 0 : kLocalMirrorEdgeHitWidth,
      endEdgeBandWidth: isNarrow ? 0 : kLocalMirrorEdgeHitWidth,
      edgeBandsOutward: false,
      edgeKey: (edge) => ValueKey('mirror_fragment_${index}_edge_${edge.name}'),
      // 块体层：填充/描边色由总开关与选中态驱动（视觉归调用点，块壳不认
      // 颜色与选中）。块体不另挂点按——点按上移到行级点按层（本行
      // 子树的整行点按层），宽/窄片段同一条解析路径，同一次 tap 不会块内/
      // 块外两套逻辑各切一次。
      body: Container(
        margin: const EdgeInsets.symmetric(
          vertical: kLocalMirrorBlockVerticalPadding,
        ),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(kLocalMirrorBlockCornerRadius),
          border: selected
              ? Border.all(color: barColor, width: 1.5)
              : Border.all(color: baseColor.withValues(alpha: 0.4)),
        ),
        // 窄块不绘反相图标。
        alignment: isNarrow ? null : Alignment.center,
        child: isNarrow
            ? null
            : Icon(
                Icons.flip,
                key: ValueKey('mirror_fragment_${index}_icon'),
                size: 14,
                color: active
                    ? kLocalMirrorEnabledIconColor
                    : kLocalMirrorDisabledIconColor,
              ),
      ),
      onMoveDragStart: onMoveDragStart,
      onEdgeDragStart: onEdgeDragStart,
      onDragUpdate: (details) => onDragUpdate(details.globalPosition),
      onDragEnd: onDragEnd,
      onDragCancel: onDragEnd,
    );
  }
}

/// 窄块判据（两轨同一条规则）：块宽是否被共用区域
/// 划分 [intervalHitRegion] 的窄块阈值抑制了端点带（块左缘划分结果不为
/// 端点带 = 窄）。
bool _isNarrowBlock({
  required double blockWidth,
  required double edgeBandWidth,
  required double narrowWidth,
}) {
  return intervalHitRegion(
        blockWidth: blockWidth,
        offsetInBlock: 0,
        edgeBandWidth: edgeBandWidth,
        narrowWidth: narrowWidth,
      ) !=
      IntervalHitRegion.startEdge;
}
