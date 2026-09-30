/// 备注轨域。
///
/// 备注轨整行是一个模块：自带 widget 子树——端点柄、框内文本三档、块体
/// 渲染（经公开共享件 [TrackFragmentRowShell]）、展开内容浮条（含它
/// 的锚上报件与 [OverlayPortal] 装配）、行级点按与长按、选择簿记（窗口
/// 离场清选、播放头越过自身时间窗清选），以及本行两族拖动（整体移 / 端点
/// 拖，含各自的句柄槽与起手/逐帧/收口包装）。带侧只组装。
///
/// ## 接口
///
/// 入口收一个显式输入值对象 [TrackNoteRowInput]（备注列表、该行矩形、时间
/// 轴与窗口、当前选中、定位高亮、名册配色、带级注入的回调）加**拖动域句柄**
/// （[TrackNoteRowInput.drag]）。本域不碰容器句柄、不读带级 State。
///
/// ## 选择簿记
///
/// 三条清除路径里，**窗口平移/缩放离场**由本域自己判（重建即现势窗口），
/// **播放头越过自身时间窗**是域公开的簿记入口
/// [noteRowClearSelectionIfPlayheadLeftOwnWindow]（触发是带级位置 tick：帧
/// 步进、微调 scrub 与预览线拖动的写点不算，见该函数文档），**打开编辑器**
/// 是本行的点按出口。
///
/// ## 拖动（两族经按族注册入口登记）
///
/// 两族的声明条目**随本域走**：本域在首次挂载时经拖动域的按族注册入口
/// [TrackBandDragFamilies.register] 把 `noteMove` / `noteEdgeDrag` 两条声明
/// 登记进去（门禁目标、准入形状、抓取偏移、逐帧换算与视觉钩子都在本域），
/// 起手/逐帧/收口全程经 [TrackBandDragSession.begin] 交回的
/// [TrackBandDragHandle]。「局部 x → 时间」的换算交规范层纯件
/// [dragTimeAt]，轴取本域自己的输入时间轴——行域之间不互借换算方法，共享的
/// 是规范层纯件。
///
/// ## 留在带级的东西（以回调注入本域）
///
///   - **空白落穿到带级仲裁**：本行空白命中的单击经
///     [TrackNoteRowInput.onBlankTapFallthrough] 交回带级空白 tap 仲裁实例
///     （同一份判定窗口，本域不含第二份）；
///   - **手势守卫**：跨面双指 burst 与带内双指会话期间的点按/长按让位
///     （[TrackNoteRowInput.mixedPinchBurst] /
///     [TrackNoteRowInput.trackPinchActive]）；
///   - **拖线实时预览**：本行两族的起手/逐帧/收口画面预览与其余各族共用
///     带级一条会话（[TrackNoteRowInput.onDragPreviewBegin] /
///     [TrackNoteRowInput.onDragPreviewFrame] /
///     [TrackNoteRowInput.onDragPreviewEnd]）；
///   - **行背景**：`track_notes` 行底与行高由带级行渲染件承担，本域只画行
///     内容。
///
/// ## 依赖方向（单向）
///
/// 本域 → 拖动域（会话与按族注册入口）+ 标注编辑模块（两族拖动会话、内容锁
/// 切换、起手门禁）+ 选中域（备注片段单选槽写点）+ 备注编辑器（编辑器目标
/// 与定位高亮）+ 装载门 + 区间片段行共用纯件 + 块体骨架 + 展开浮条 + 轨道
/// 行表 + 时间轴/窗口纯值 + 集中视觉常量；**不 import 轨道带 / 控制层 /
/// 演出层 / 播放页**，反向边只有轨道带一处 import 本域。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/interval_fragment_row.dart'
    show
        IntervalBlockRect,
        IntervalEdge,
        IntervalSpan,
        allocateIntervalEdgeHitDomains,
        intervalBlockRect,
        resolveIntervalHit;
import '../annotation/note_sticker.dart' show NoteSticker;
import '../core/text_extent.dart';
import 'annotation_edit.dart' show ToggleNoteLock;
import 'annotation_editor.dart'
    show
        AnnotationGestureTarget,
        annotationEditorProvider,
        annotationSelectionDomainProvider;
import 'annotation_selection.dart' show NoteFragmentSelection;
import 'load_gate.dart' show loadGateActiveProvider;
import 'note_editor.dart'
    show noteFragmentHighlightProvider, noteTextEditorTargetProvider;
import 'note_sticker_overlay.dart' show NoteMentionSpans;
import 'track_band_drag.dart'
    show
        TrackBandDragHandle,
        TrackBandDragSession,
        TrackBandDragTarget,
        TrackBandDragDeclaration,
        NoteEdgeDragTarget;
import 'track_fragment_bubble.dart'
    show FragmentActionBubble, FragmentBubbleHost;
import 'track_fragment_row_shell.dart' show TrackFragmentRowShell;
import 'track_geometry.dart' show dragTimeAt;
import 'track_row_table.dart' show TrackRowRect;
import 'track_time.dart' show TimelineAxis, TimelineWindow;
import 'visual_tokens.dart';

/// 备注轨域的显式输入值对象（带侧组装点每帧构造一次）。
///
/// 数据面一次给全（备注列表、行矩形、时间轴与窗口、选中、定位高亮、名册
/// 配色），动作面只收带级自己拥有的三件事：空白落穿、手势守卫与拖线实时
/// 预览。（播放头一路不走本输入值对象：它的触发是带级位置 tick，见顶层
/// [noteRowClearSelectionIfPlayheadLeftOwnWindow]。）
class TrackNoteRowInput {
  const TrackNoteRowInput({
    required this.notes,
    required this.rowRect,
    required this.axis,
    required this.window,
    required this.selectedIndex,
    required this.highlightedStartMs,
    required this.rosterColors,
    required this.drag,
    required this.onBlankTapFallthrough,
    required this.mixedPinchBurst,
    required this.trackPinchActive,
    required this.onDragPreviewBegin,
    required this.onDragPreviewFrame,
    required this.onDragPreviewEnd,
  });

  /// 本行备注片段（时间窗，按起点升序、两两不重叠）。
  final List<NoteSticker> notes;

  /// 本行行矩形（**域内坐标**：域的渲染盒即该行矩形，行顶由带级
  /// `Positioned` 让出，故本域 `rowRect.top` 恒为 0）。
  final TrackRowRect rowRect;

  /// 带内容区的时间轴（时间↔内容区像素的唯一换算入口）。
  final TimelineAxis axis;

  /// 生效可视窗口（带几何归一后的非空窗口）。
  final TimelineWindow window;

  /// 当前选中的备注片段下标（null = 未选中或索引越界）。
  final int? selectedIndex;

  /// 定位高亮的备注起点（null = 无高亮；与备注起点匹配的片段渲染高亮）。
  final int? highlightedStartMs;

  /// 名册只读面（点名着色；文本唯一真源，与画面贴纸同一份解析与配色）。
  final Map<String, int> rosterColors;

  /// 拖动域句柄：本域两族的声明经它的按族注册入口登记，起手经它交出句柄。
  final TrackBandDragSession drag;

  /// 行级层空白命中的落穿（全局位置）：交回带级空白 tap 仲裁。
  final void Function(Offset globalPosition) onBlankTapFallthrough;

  /// 跨面双指 burst 在场（点按/长按让位）。
  final bool Function() mixedPinchBurst;

  /// 带内双指会话在场（点按/长按让位）。
  final bool Function() trackPinchActive;

  /// 拖线实时预览起手（与其余各族共用带级一条画面预览会话）。
  final VoidCallback onDragPreviewBegin;

  /// 拖线实时预览单帧（写后真实落点非空时触发一次）。
  final void Function(Duration landing) onDragPreviewFrame;

  /// 拖线实时预览收尾。
  final VoidCallback onDragPreviewEnd;
}

/// 备注轨行级命中解析（域公开的命中入口）：内容区局部 x + 备注列表 + 时间
/// 轴与窗口 → 命中备注下标（null = 轨道空白）。共用件 [resolveIntervalHit]
/// 承担命中算法（对称扩展至不小于 [kNoteTapHitWidth] 像素 + 多候选取距中心
/// 最近），本函数只装配入参。本域的行级点按/长按与带级的编辑内容判定共用
/// 这一条解析，不复制第二份判定窗口。
int? noteRowHitAt({
  required double localX,
  required List<NoteSticker> notes,
  required TimelineAxis axis,
  required TimelineWindow window,
}) {
  final spanMs = window.end.inMilliseconds - window.start.inMilliseconds;
  if (spanMs <= 0 || axis.contentWidth <= 0) return null;
  final time = axis.xToTime(localX.clamp(0.0, axis.width).toDouble());
  return resolveIntervalHit(
    spans: [
      for (final note in notes)
        IntervalSpan(startMs: note.startMs, endMs: note.endMs),
    ],
    positionMs: time.inMilliseconds,
    // 像素→时间按内容区宽折算（片头不吃命中宽度口径）。
    minHitWidthMs: (kNoteTapHitWidth * spanMs / axis.contentWidth).round(),
  );
}

/// 可视窗口 → 区间 span（块矩形纯件的入参形态：毫秒半开区间）。
IntervalSpan _windowSpan(TimelineWindow window) => IntervalSpan(
  startMs: window.start.inMilliseconds,
  endMs: window.end.inMilliseconds,
);

/// 选择簿记（域公开面）：播放头**越过**选中备注自身的时间窗即清选。
///
/// 判据取**跨越**（上一 tick 在窗内、本 tick 在窗外）——在播时点选一条播放头
/// 不在其中的片段是常规操作，按「不在窗内」会被下一次 tick 立刻清掉。触发是
/// 带级位置 tick（手势会话与拖线预览期间的 tick 不写播放头显示值，故不进本判
/// 定；帧步进、微调 scrub 与预览线拖动另有写点，同样不是本判定），判定与写点
/// 归本域：带侧在位置 tick 上调用本函数一次，交现势读数与清除写缝。
void noteRowClearSelectionIfPlayheadLeftOwnWindow({
  required List<NoteSticker> notes,
  required int? selectedIndex,
  required Duration previous,
  required Duration next,
  required void Function() clearSelection,
}) {
  if (selectedIndex == null ||
      selectedIndex < 0 ||
      selectedIndex >= notes.length) {
    return;
  }
  final note = notes[selectedIndex];
  final wasInside =
      previous.inMilliseconds >= note.startMs &&
      previous.inMilliseconds < note.endMs;
  final isInside =
      next.inMilliseconds >= note.startMs && next.inMilliseconds < note.endMs;
  if (!(wasInside && !isInside)) return;
  clearSelection();
}

/// 备注轨域：整行的呈现与交互（块体、端点柄、文本三档、展开浮条、点按/
/// 长按与两族拖动）。
class TrackNoteRow extends ConsumerStatefulWidget {
  const TrackNoteRow({super.key, required this.input});

  /// 显式输入值对象（带侧组装）。
  final TrackNoteRowInput input;

  @override
  ConsumerState<TrackNoteRow> createState() => _TrackNoteRowState();
}

class _TrackNoteRowState extends ConsumerState<TrackNoteRow> {
  /// 本行两族的单槽句柄：整体移与端点拖互斥、共用一槽（同族两条声明的
  /// 抓取偏移与准入各自独立，句柄只记「谁在拖」）。
  TrackBandDragHandle? _dragHandle;

  /// 本帧是否已排入窗口离场清选（同一帧多次重建只排一次）。
  bool _leftWindowClearScheduled = false;

  @override
  void initState() {
    super.initState();
    _registerDragFamilies();
  }

  @override
  void didUpdateWidget(TrackNoteRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.input.drag, widget.input.drag)) {
      _registerDragFamilies();
    }
    // 窗口平移/缩放离场即清选：写点在帧尾（构建期不改 provider）。
    if (oldWidget.input.window != widget.input.window) {
      _scheduleClearIfFragmentLeftWindow();
    }
  }

  // ---- 选择簿记（域归属的窗口离场清选；播放头一路见顶层公开入口） ----

  /// 现势选中的备注（null = 未选中或索引越界）。
  NoteSticker? _selectedNote() {
    final index = widget.input.selectedIndex;
    if (index == null) return null;
    final notes = widget.input.notes;
    if (index < 0 || index >= notes.length) return null;
    return notes[index];
  }

  /// 选中的片段随窗口平移/缩放离场即清选（片段不在可视窗内了，选中框与
  /// 展开浮条没有承载物）。判定读**本帧的输入**（重建后现势窗口），写点排
  /// 到帧尾——构建期改 provider 不合法。
  void _scheduleClearIfFragmentLeftWindow() {
    if (_leftWindowClearScheduled) return;
    _leftWindowClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _leftWindowClearScheduled = false;
      if (!mounted) return;
      final note = _selectedNote();
      if (note == null) return;
      final win = widget.input.window;
      final visible =
          win.end.inMilliseconds > note.startMs &&
          note.endMs > win.start.inMilliseconds;
      if (visible) return;
      _clearSelection();
    });
  }

  /// 清备注片段选中（选中进标注选中单选槽，清除走同一条写缝）。
  void _clearSelection() =>
      ref.read(annotationSelectionDomainProvider).clear();

  // ---- 拖动：两族的声明条目随族经按族注册入口登记 ----

  /// 两族登记进拖动域的按族注册入口（本域唯一登记点：声明条目住本域）。
  void _registerDragFamilies() {
    final families = widget.input.drag.families;
    families.register(
      AnnotationGestureTarget.noteMove,
      TrackBandDragDeclaration(
        toTime: _noteDragTime,
        beginSession: (target) => ref
            .read(annotationEditorProvider)
            .beginNoteMoveDrag(target.index),
        admit: _admitNoteDrag,
        readGrabOffsetMs: _noteMoveGrabOffset,
        onBegin: _beginNoteDragVisuals,
        onFrame: _frameNoteDrag,
        onEnd: _endNoteDragVisuals,
      ),
    );
    families.register(
      AnnotationGestureTarget.noteEdgeDrag,
      TrackBandDragDeclaration(
        toTime: _noteDragTime,
        beginSession: (target) => ref
            .read(annotationEditorProvider)
            .beginNoteEdgeDrag(
              target.index,
              (target as NoteEdgeDragTarget).edge,
            ),
        admit: _admitNoteDrag,
        readGrabOffsetMs: _noteEdgeGrabOffset,
        onBegin: _beginNoteDragVisuals,
        onFrame: _frameNoteDrag,
        onEnd: _endNoteDragVisuals,
      ),
    );
  }

  /// 本族的逐帧换算装配（拖动域按族取用）：换算交规范层 [dragTimeAt]，轴取
  /// build 期的本行输入。本域与带同左缘、同宽，故本域局部 x 与带内局部 x
  /// 逐位相等，拖动域交下的带宽因此不必二次消费。
  Duration? _noteDragTime(double localX, double _) =>
      dragTimeAt(widget.input.axis, localX);

  /// 本域渲染盒（局部坐标读取的唯一一处）。
  RenderBox? _box() {
    final box = context.findRenderObject();
    return box is RenderBox ? box : null;
  }

  /// 局部手势位置 → 本域局部 x。
  double? _localX(Offset globalPosition) =>
      _box()?.globalToLocal(globalPosition).dx;

  /// 备注片段整体移起手：判定与相对平移同镜像整体移，另受该条备注的内容
  /// 锁（声明准入里静默不参与）。
  void _beginNoteMoveDrag(int index, DragStartDetails details) {
    _dragHandle = widget.input.drag.begin(
      TrackBandDragTarget.noteMove(index),
      _localX(details.globalPosition) ?? 0,
    );
  }

  /// 备注片段端点拖起手：判定同整体移；抓取偏移相对被拖端点。
  void _beginNoteEdgeDrag(
    int index,
    IntervalEdge edge,
    DragStartDetails details,
  ) {
    _dragHandle = widget.input.drag.begin(
      TrackBandDragTarget.noteEdge(index, edge),
      _localX(details.globalPosition) ?? 0,
    );
  }

  /// 两族的逐帧更新：只经本族自己的句柄（钳制、抓取偏移、落点钩子都在
  /// 域内只写一次）。
  void _updateNoteDrag(DragUpdateDetails details) =>
      _dragHandle?.moveTo(_localX(details.globalPosition) ?? 0);

  /// 两族的收口（onDragEnd / onDragCancel 共用）：句柄收口幂等；没有会话
  /// （起手被拒）时仍收一次实时预览。
  void _endNoteDrag() {
    final handle = _dragHandle;
    _dragHandle = null;
    if (handle == null) {
      widget.input.onDragPreviewEnd();
      return;
    }
    handle.end();
  }

  /// 两族的准入：按备注列表长度越界 + 该条备注的内容锁，静默不
  /// 参与（落点类准入不适用本族，起手局部 x 不读）。
  bool _admitNoteDrag(TrackBandDragTarget target, double _) {
    final notes = widget.input.notes;
    final index = target.index;
    return index >= 0 && index < notes.length && !notes[index].locked;
  }

  /// 整体移的抓取偏移：手指 − 片段起点。
  int _noteMoveGrabOffset(TrackBandDragTarget target, Duration finger) =>
      finger.inMilliseconds - widget.input.notes[target.index].startMs;

  /// 端点拖的抓取偏移：手指 − 被拖端点当前时刻。
  int _noteEdgeGrabOffset(TrackBandDragTarget target, Duration finger) {
    final edgeTarget = target as NoteEdgeDragTarget;
    final note = widget.input.notes[edgeTarget.index];
    final boundary = edgeTarget.edge == IntervalEdge.start
        ? note.startMs
        : note.endMs;
    return finger.inMilliseconds - boundary;
  }

  /// 拖动起手视觉：清定位高亮（用户已到位）+ 起共用拖线实时预览。
  void _beginNoteDragVisuals(TrackBandDragTarget target) {
    ref.read(noteFragmentHighlightProvider.notifier).clear();
    widget.input.onDragPreviewBegin();
  }

  /// 拖动逐帧视觉：共用拖线实时预览单帧。
  void _frameNoteDrag(Duration landing) =>
      widget.input.onDragPreviewFrame(landing);

  /// 拖动收口视觉（幂等）：共用拖线实时预览收尾。
  void _endNoteDragVisuals() => widget.input.onDragPreviewEnd();

  // ---- 行级命中 / 点按 / 长按 ----

  /// 备注轨行级命中解析（单击与长按共用一条路径）：x（全局像素）→ 本域
  /// 局部坐标 → 域公开的命中入口 [noteRowHitAt]（共用件承担区间扩展与多候
  /// 选取距中心最近，不复制第二份判定）。本域与带同左缘、同宽，故本域局部
  /// x 与带内局部 x 逐位相等。
  int? _resolveRowHit(Offset globalPosition) {
    final x = _localX(globalPosition);
    if (x == null) return null;
    return noteRowHitAt(
      localX: x,
      notes: widget.input.notes,
      axis: widget.input.axis,
      window: widget.input.window,
    );
  }

  /// 备注轨行级点按：命中片段 = **选中**（经选中域写进标注选中单选槽），
  /// 选中即在该片段上方展开内容浮条；**再单击已选中的片段 = 打开编辑器**
  /// （以备注起点标识目标），选中槽随之清除。轨道空白返回 false 落穿带级
  /// 空白仲裁（本层不含第二份判定窗口）。守卫沿既有：跨面双指 burst 与
  /// 捏合期间不判定；锁定分段不拦单击（锁只护几何、编辑文本豁免）。定位
  /// 高亮：片段被点按即清（用户已到位）。
  bool _handleRowTap(TapUpDetails details) {
    // 对比态只读：备注轨只渲染不参与命中——命中与空白同路（落穿带级空白
    // 仲裁），不选中、不进编辑器、静默（起手门禁）。
    if (ref
        .read(annotationEditorProvider)
        .gestureStartRejected(AnnotationGestureTarget.noteRowTap)) {
      widget.input.onBlankTapFallthrough(details.globalPosition);
      return false;
    }
    if (widget.input.mixedPinchBurst()) return false;
    if (widget.input.trackPinchActive()) return false;
    final hit = _resolveRowHit(details.globalPosition);
    if (hit == null) {
      // 空白命中：不吞指针——交回带级空白 tap 仲裁（同一实例、同一份判定
      // 窗口），单击收起 / 双击只切播放与带内其它位置自动一致。
      widget.input.onBlankTapFallthrough(details.globalPosition);
      return false;
    }
    ref.read(noteFragmentHighlightProvider.notifier).clear();
    if (hit == widget.input.selectedIndex) {
      _clearSelection();
      ref
          .read(noteTextEditorTargetProvider.notifier)
          .open(widget.input.notes[hit].startMs);
      return true;
    }
    ref
        .read(annotationSelectionDomainProvider)
        .select(NoteFragmentSelection(hit));
    return true;
  }

  /// 备注轨行级长按：命中即经标注编辑模块取反该备注的内容锁——单步可撤
  /// 销、不受锁定分段管（两把锁都不挡锁定开关）。守卫沿既有（同点按）；
  /// 装载未完成时内容锁切换会写盘，手势类入口静默不参与。
  void _handleRowLongPress(LongPressEndDetails details) {
    if (ref
        .read(annotationEditorProvider)
        .gestureStartRejected(AnnotationGestureTarget.noteLockLongPress)) {
      return;
    }
    if (ref.read(loadGateActiveProvider)) return;
    if (widget.input.mixedPinchBurst()) return;
    if (widget.input.trackPinchActive()) return;
    final hit = _resolveRowHit(details.globalPosition);
    if (hit == null) return;
    // 定位高亮：命中片段即清（用户已到位）；长按空白无动作、不清高亮。
    ref.read(noteFragmentHighlightProvider.notifier).clear();
    ref.read(annotationEditorProvider).submit(ToggleNoteLock(index: hit));
  }

  // ---- 渲染 ----

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final axis = input.axis;
    final window = input.window;
    // 几何不可映射（总时长未知 / 内容区无宽）＝本行不画任何东西、不参与
    // 命中：本层不设判定窗口，命中直接落到带级手势层。
    if (axis.isEmpty) return const SizedBox.shrink();
    final notes = input.notes;
    final selected = input.selectedIndex;
    // 域内纵向原点即行顶（行顶由带级 `Positioned` 让出）：行内摆位直接吃
    // 行矩形，块矩形左缘是带内内容区坐标。
    final rowRect = input.rowRect;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (notes.isNotEmpty)
          for (var i = 0; i < notes.length; i++)
            _noteFragmentBlock(
              index: i,
              notes: notes,
              axis: axis,
              window: window,
              note: notes[i],
              rowRect: rowRect,
              rosterColors: input.rosterColors,
              highlighted: input.highlightedStartMs == notes[i].startMs,
              selected: selected == i,
            ),
        // 展开内容浮条：选中备注片段上方按文本实测宽展开完整内容（允许
        // 超出片段宽度、屏幕边缘钳制、超屏省略），带明示「编辑」入口与
        // 小尾巴指回片段。经 [OverlayPortal] 住根浮层。
        if (selected != null)
          if (selected >= 0 && selected < notes.length)
            _expandBubble(
              note: notes[selected],
              axis: axis,
              window: window,
              rowRect: rowRect,
            ),
        // 行级点按层：整行解析点按 x → 命中 → 命中 = 选中 / 再单击已选中
        // = 打开编辑器；长按 = 锁定/解锁，同一条命中解析。**空白命中不吞
        // 指针**：经输入回调交回带级空白 tap 仲裁（同一实例、同一份判定
        // 窗口）。translucent：块体整体拖/端点拖起手仍
        // 达块内手势层，本层只认 tap / long press。
        Positioned(
          left: 0,
          top: 0,
          width: axis.width,
          height: rowRect.height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleRowTap,
            onLongPressEnd: _handleRowLongPress,
          ),
        ),
      ],
    );
  }

  /// 端点柄条（选中态）：一枚竖条，贴本侧端点命中带的内缘——起点
  /// 端靠带体右缘（紧贴块左缘）、终点端靠带体左缘，竖向按块体纪律留白。
  /// 纯呈现：它画在带体层内部，命中仍归带体那层手势。
  Widget _noteEdgeHandle({required int index, required IntervalEdge edge}) =>
      Align(
        key: ValueKey('note_fragment_${index}_handle_${edge.name}'),
        alignment: edge == IntervalEdge.start
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: kNoteBlockVerticalPadding + kNoteHandleEdgeInset,
          ),
          child: SizedBox(
            width: kNoteHandleWidth,
            height: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: kNoteFragmentSelectedColor,
                borderRadius: BorderRadius.circular(kNoteHandleWidth / 2),
              ),
            ),
          ),
        ),
      );

  /// 备注片段框内文本三档判定：**纯实测宽度**——放得
  /// 下全句 → 全显；放不下 → 省略号截断；连省略号自身也放不下 → 完全
  /// 不显示内容。**没有与时间轴脱钩的最小显示宽**；省略号截断在字形
  /// 边界收口，不出现半个字的残字。量测与渲染同源：同一组分段 span、
  /// 同一基准样式（[noteStickerTextStyle] 同款纪律——`inherit` 关断，
  /// 不与环境默认样式合并）、**同一个缩放值**（语义档（随系统字号）：
  /// 量测吃渲染侧同一 `MediaQuery.textScalerOf`）。
  _NoteInlineTextFit _fitNoteInlineText(
    List<TextSpan> spans,
    TextStyle baseStyle,
    double maxWidth,
    TextScaler textScaler,
  ) {
    final full = measureTextSpanExtent(
      TextSpan(children: spans, style: baseStyle),
      scaler: textScaler,
      maxLines: 1,
    ).width;
    if (full <= maxWidth) return _NoteInlineTextFit.full;
    final dots = measureTextExtent(
      '…',
      baseStyle,
      scaler: textScaler,
      maxLines: 1,
    ).width;
    return dots <= maxWidth
        ? _NoteInlineTextFit.ellipsized
        : _NoteInlineTextFit.hidden;
  }

  /// 备注片段框内文本层：与画面贴纸**同源**——走同一装配入口
  /// [NoteMentionSpans]（按当前名册解析、`@` 与紧随空格隐藏、点名段代表
  /// 色、正文段恒白）；**不画描边**（描边是为压在视频画面上可读，
  /// 轨道文字已在深色块里）。字号取具名常量。锁定标识优先占位：先扣掉
  /// 角标占位，再按剩余宽度三档判定。
  List<Widget> _noteInlineText({
    required int index,
    required NoteSticker note,
    required double blockWidth,
    required Map<String, int> rosterColors,
    required TextScaler textScaler,
  }) {
    final mentionSpans = NoteMentionSpans(note, rosterColors);
    if (mentionSpans.mention.segments.isEmpty) return const [];
    final reserve = note.locked
        ? kNoteBlockCornerRadius + kNoteLockBadgeSize + kNoteLockTextGap
        : 0.0;
    final available =
        blockWidth - reserve - 2 * kNoteInlineTextHorizontalPadding;
    if (available <= 0) return const [];
    final baseStyle = TextStyle(
      inherit: false,
      fontSize: kNoteInlineTextFontSize,
    );
    final spans = mentionSpans.fillSpans;
    switch (_fitNoteInlineText(spans, baseStyle, available, textScaler)) {
      case _NoteInlineTextFit.hidden:
        return const [];
      case _NoteInlineTextFit.full || _NoteInlineTextFit.ellipsized:
        return [
          Positioned(
            key: ValueKey('note_fragment_${index}_text'),
            left: reserve + kNoteInlineTextHorizontalPadding,
            right: kNoteInlineTextHorizontalPadding,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(children: spans, style: baseStyle),
                  textScaler: textScaler,
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ];
    }
  }

  /// 端点命中域一侧的可用空间（像素）：块缘向外到最近占用（相邻
  /// 片段块缘或带缘）的空闲。朝相邻片段一侧让半——对方的端点带同样要
  /// 伸进这条空隙，各取一半即互不侵占；朝带缘一侧全给。相邻片段在窗外
  /// （块矩形降级为空）时不构成冲突、视同带缘。
  double _noteEdgeAvailablePx({
    required IntervalBlockRect block,
    required TimelineAxis axis,
    required TimelineWindow window,
    required IntervalEdge side,
    NoteSticker? prev,
    NoteSticker? next,
  }) {
    IntervalBlockRect? neighborBlock(NoteSticker? neighbor) {
      if (neighbor == null) return null;
      return intervalBlockRect(
        span: IntervalSpan(startMs: neighbor.startMs, endMs: neighbor.endMs),
        window: _windowSpan(window),
        trackWidth: axis.contentWidth,
        contentLeft: axis.contentLeft,
      );
    }

    final b = side == IntervalEdge.start
        ? neighborBlock(prev)
        : neighborBlock(next);
    final double gap;
    if (side == IntervalEdge.start) {
      gap = block.left - (b == null ? axis.contentLeft : b.left + b.width);
    } else {
      gap = (b?.left ?? axis.width) - (block.left + block.width);
    }
    if (gap <= 0) return 0;
    // 邻块在窗外（块矩形降级为空）时不构成冲突、视同带缘、全给。
    return b != null ? gap / 2 : gap;
  }

  /// 备注片段块体：时间窗 → 行内块矩形，几何全部消费共用件
  /// [intervalBlockRect]——窗口外裁切、零宽与倒置降级不渲染。视觉沿用区间
  /// 片段行的块体纪律（圆角、竖向内边距，取值走集中视觉 token），填充/描边
  /// 取具名常量。框内文本与贴纸同一份点名解析、同一套隐藏规则与配色，三档
  /// 适配（[_fitNoteInlineText]），不画描边。
  ///
  /// 命中与交互（都由**行级层**统一解析，块体不另挂点按）：
  ///   - **单击** = 选中并在上方展开内容、再单击已选中的片段 = 打开编辑器；
  ///   - **长按** = 内容锁开关；
  ///   - **整体水平拖动**（块体）= 平移时间窗、宽度不变；
  ///   - **端点拖动** = 两端各自的命中带起手（命中域让位到块外
  ///     空隙、按可用空间自适应分配；选中后给端点柄、命中域更长），拖动
  ///     改起止（落点吸附拍点 / 互斥钳制）；柄条画在本侧命中带内，所见即
  ///     所拖。
  Widget _noteFragmentBlock({
    required int index,
    required List<NoteSticker> notes,
    required TimelineAxis axis,
    required TimelineWindow window,
    required NoteSticker note,
    required TrackRowRect rowRect,
    required Map<String, int> rosterColors,
    bool highlighted = false,
    bool selected = false,
  }) {
    final block = intervalBlockRect(
      span: IntervalSpan(startMs: note.startMs, endMs: note.endMs),
      window: _windowSpan(window),
      trackWidth: axis.contentWidth,
      contentLeft: axis.contentLeft,
    );
    if (block == null) return const SizedBox.shrink();
    // 端点命中域分配：命中域让位到块外空隙——
    // 未选中两端各按可用空间自适应分配（冲突处让出、最坏退化整块归
    // 移动），选中后两端给端点柄（目标带宽更长）。块体恒整块归移动，
    // 任何块宽下都不出现死区。
    final allocation = allocateIntervalEdgeHitDomains(
      startAvailable: _noteEdgeAvailablePx(
        block: block,
        axis: axis,
        window: window,
        side: IntervalEdge.start,
        prev: index > 0 ? notes[index - 1] : null,
      ),
      endAvailable: _noteEdgeAvailablePx(
        block: block,
        axis: axis,
        window: window,
        side: IntervalEdge.end,
        next: index + 1 < notes.length ? notes[index + 1] : null,
      ),
      bandWidth: kNoteEdgeHitWidth,
      selectedBandWidth: kNoteSelectedEdgeHitWidth,
      selected: selected,
    );
    final color = kNoteFragmentColor;
    return TrackFragmentRowShell(
      blockKey: ValueKey('note_fragment_$index'),
      block: block,
      rowRect: rowRect,
      startEdgeBandWidth: allocation.startWidth,
      endEdgeBandWidth: allocation.endWidth,
      edgeBandsOutward: true,
      edgeKey: (edge) => ValueKey('note_fragment_${index}_edge_${edge.name}'),
      // 端点柄：选中后两端各一枚柄条，画在本侧命中带内、贴着块
      // 缘的空隙一侧——看见的柄就是拖得动的带。
      edgeBandChild: selected
          ? (edge) => _noteEdgeHandle(index: index, edge: edge)
          : null,
      // 块体层：填充/描边取具名常量，圆角与竖向内边距走集中视觉 token
      // （视觉归调用点，块壳不认颜色）。选中描边为白色加粗（与区间片段行
      // 同款视觉纪律）。
      body: Container(
        margin: const EdgeInsets.symmetric(vertical: kNoteBlockVerticalPadding),
        decoration: BoxDecoration(
          color: color.withValues(alpha: kNoteBlockFillAlpha),
          borderRadius: BorderRadius.circular(kNoteBlockCornerRadius),
          border: selected
              ? Border.all(
                  color: kNoteFragmentSelectedColor,
                  width: kNoteFragmentSelectedBorderWidth,
                )
              : Border.all(
                  color: color.withValues(alpha: kNoteBlockBorderAlpha),
                ),
        ),
      ),
      payload: [
        // 框内文本：块有多大就显示多少，三档适配；锁定标识
        // 优先占位（先扣角标位置再判文本）。纯呈现，IgnorePointer 不
        // 参与命中。
        ..._noteInlineText(
          index: index,
          note: note,
          blockWidth: block.width,
          rosterColors: rosterColors,
          textScaler: MediaQuery.textScalerOf(context),
        ),
        // 锁定标识：与备注内容锁字段一致——locked 即渲染、
        // 解锁即时消失；一眼可辨「这条备注的几何拖不动」。纯呈现，
        // IgnorePointer 不参与命中（点选 / 角工具不受锁影响）。
        if (note.locked)
          Positioned(
            key: ValueKey('note_fragment_${index}_lock'),
            left: kNoteBlockCornerRadius,
            top: kNoteBlockVerticalPadding,
            child: IgnorePointer(
              child: Icon(
                Icons.lock_rounded,
                size: kNoteLockBadgeSize,
                color: color,
              ),
            ),
          ),
        // 定位高亮：贴纸左下角跳转后在对应片段上的高亮描边（不拦手势）；
        // 用户对该片段点按 / 拖动起手即清（见各交互入口）。
        if (highlighted)
          Positioned.fill(
            key: const Key('note_fragment_highlight'),
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.symmetric(
                  vertical: kNoteBlockVerticalPadding,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kNoteBlockCornerRadius),
                  border: Border.all(
                    color: kNoteFragmentHighlightColor,
                    width: kNoteFragmentHighlightWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
      onMoveDragStart: (details) => _beginNoteMoveDrag(index, details),
      onEdgeDragStart: (edge, details) =>
          _beginNoteEdgeDrag(index, edge, details),
      onDragUpdate: _updateNoteDrag,
      onDragEnd: _endNoteDrag,
      onDragCancel: _endNoteDrag,
    );
  }

  /// 展开内容浮条：选中备注片段上方展开这条备注的完整内容。组成 = 带内一个
  /// 透明的锚定 reporting 块（其渲染盒全局矩形即片段全局矩形，帧末上报）+ 根
  /// 浮层子树里的浮条本体，装配收在 [FragmentBubbleHost]。宽度按
  /// 文本实测、允许超出片段宽度，屏幕边缘钳制、超屏省略；带一枚明示的
  /// 「编辑」入口与一个小尾巴指回片段。
  Widget _expandBubble({
    required NoteSticker note,
    required TimelineAxis axis,
    required TimelineWindow window,
    required TrackRowRect rowRect,
  }) {
    final block = intervalBlockRect(
      span: IntervalSpan(startMs: note.startMs, endMs: note.endMs),
      window: _windowSpan(window),
      trackWidth: axis.contentWidth,
      contentLeft: axis.contentLeft,
    );
    if (block == null) {
      // 片段不在窗内：锚上报块不渲染（其 dispose 清锚）→ 浮条隐藏。
      return const SizedBox.shrink();
    }
    return FragmentBubbleHost(
      anchorRect: Rect.fromLTWH(block.left, 0, block.width, rowRect.height),
      text: note.text,
      bubbleBuilder: (anchorRect, text) => FragmentActionBubble(
        anchorRect: anchorRect,
        text: text,
        actionLabel: '编辑',
        actionKey: const Key('note_expand_bubble_edit'),
        actionHitKey: const Key('note_expand_bubble_edit_hit'),
        bubbleKey: const Key('note_expand_bubble'),
        onAction: _openSelectedEditor,
      ),
    );
  }

  /// 浮条「编辑」入口：清选中槽并打开该备注的编辑器（与再单击已选中片段
  /// 同一出口）。
  void _openSelectedEditor() {
    final note = _selectedNote();
    if (note == null) return;
    _clearSelection();
    ref.read(noteTextEditorTargetProvider.notifier).open(note.startMs);
  }
}

/// 框内文本三档：全显 / 省略号截断 / 完全不显示。
enum _NoteInlineTextFit { full, ellipsized, hidden }
