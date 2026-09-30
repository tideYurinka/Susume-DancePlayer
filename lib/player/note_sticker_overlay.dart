/// 备注贴纸浮层（显隐渲染 / 选中框 / 四角工具 /
/// 点名着色 / 描边按底色派生）：窗内显隐 + 恒定样式渲染文本。
///
/// - **显隐只看「播放头 ∈ 时间窗」**（[noteStickerAt]，半开时间窗），
///   与播放 / 暂停无关；播放头位置由宿主按
///   `playbackPositionProvider` 驱动注入，本组件不读播放状态。
/// - **文本恒定样式渲染**：正文恒白、描边恒开且颜色按段由底色
///   派生（[noteSegmentStrokeColor]）；字号
///   由贴纸整体缩放承担（基准字号 × 等比系数），不设字号档。
/// - **点名语法着色**：
///   渲染时按**当前名册**解析 `@` 语法（[parseNoteMentions]，文本是唯一
///   真源）——语法字符（`@` 与紧随名字后的第一个空格）被隐藏、名字段用
///   该舞者的代表色、其余段恒白；不构成单元的 `@` 原样显示。
///   名册的增 / 删 / 改色实时反映（解析在 build 期以当前名册进行）。
/// - **落点与钳制**：像素矩形由归一化几何（[noteStickerRect]）换算——
///   默认落点 = 具名常量（水平居中、自内容矩形顶边下移约 12%、系数
///   1.0），按实际排版尺寸钳进视频内容矩形。
/// - **随面**：[NoteStickerOverlay.faceDirection] 是该面此刻的方向
///   （画面方向库的 `directionOf(sourceVideo)`），贴纸按它做水平坐标换算
///   ——渲染矩形与命中矩形是同一个 [noteStickerRect] 返回值，不存在「画在
///   一处、点在另一处」；文字与角工具图标不套翻转变换（保持正向）。
/// - **贴纸几何手势**：窗口内的播放态、选中态下，贴纸主体接
///   单指平移与双指等比缩放——像素 → 归一化换算单点
///   （[noteGeometryFromGesture]）、钳制在模块内单点（[clampNoteGeometry]），
///   经模块第 8 个拖动会话族逐帧提交、一次手势一个净变化收口；未选中
///   穿透手势、编辑态（[NoteStickerOverlay.readOnly]）与窗外不可调；
///   手势中出窗经注册接线的 onWindowExit 走会话结束路径中断（幂等）。
/// - 选中态与命中面归 [NoteStickerOverlayRegistration]；**四角工具**：
///   选中态渲染四个工具（左上删除 / 右上打开编辑器 / 左下跳转 /
///   右下锁定），次序 = [OverlayCorner] 枚举序。取消选中即消失。
library;

import 'dart:async' show scheduleMicrotask;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/framing_selection.dart' show FramingSelection;
import '../annotation/note_mention.dart';
import '../annotation/note_sticker.dart';
import '../annotation/dancer_roster.dart' show DancerRosterEntry;
import '../core/text_extent.dart';
import '../surface_direction/surface_direction.dart' show FaceDirection;
import 'annotation_editor.dart'
    show AnnotationDragSession, annotationEditorProvider, noteStickersProvider;
import 'dancer_roster_controller.dart' show dancerRosterProvider;
import 'dashed_selection_box.dart' show DashedSelectionBoxPainter;
import 'note_sticker_layout.dart'
    show
        kNoteStickerBaseFontSize,
        noteGeometryFromGesture,
        noteStickerAt,
        noteStickerIndexAt,
        noteStickerRect;
import 'note_sticker_overlay_registration.dart'
    show NoteStickerOverlayRegistration;
import 'overlay.dart' show OverlayCorner;
import 'visual_tokens.dart' show kHitTargetMinSize;

/// 贴纸描边粗细（观感值，真机看版项）。
const double kNoteStickerOutlineWidth = 2;

/// 纯白点名段的内层白边线宽：总边框外沿与其它字一致——外层黑
/// 边直接复用 [kNoteStickerOutlineWidth]（描边以字形轮廓为中心向内外各
/// 溢半个线宽，可见外沿 1px），内层白边占 2/3。必须窄于外层，否则白边
/// 正好盖住黑边、可见黑为 0。观感值，真机看版项。
const double kNoteStickerWhiteMentionStrokeWidth =
    kNoteStickerOutlineWidth * 2 / 3;

/// 选中态描边颜色：青色（「青色虚线框」）。
const Color kNoteStickerSelectionColor = Color(0xFF00E5FF);

/// 选中框相对贴纸矩形的外扩留白（不遮字）。
const double kNoteStickerSelectionPadding = 6;

/// 角工具命中区边长：每角一个独立命中区，贴纸四角各外扩一圈
/// （不遮字、互不重叠；Stack 命中判定不越自身界，故外扩区必须是本
/// Stack 的一部分）。
///
/// 命中盒下限：取 [kHitTargetMinSize] 48——
/// 四角各是一个 48×48 透明命中盒，贴纸文字在其内不被覆盖；外扩量同取 48，
/// 因此上下/左右两角的命中域恒以贴纸边为界、永不互吞（与贴纸尺寸无关）。
const double kNoteStickerToolHitExtent = kHitTargetMinSize;

/// 角工具图标边长（观感值，真机看版项）：命中盒外扩不改变它。
const double kNoteStickerToolIconSize = 24;

/// 角工具图标距命中盒内侧角的内边距（观感值，真机看版项）：图标因此距贴纸
/// 边 [kNoteStickerToolIconInset] dp，不随命中盒外扩而外移。
const double kNoteStickerToolIconInset = 4;

/// 贴纸文本基准样式（**量测与渲染的同源唯一样式**）：[TextStyle.inherit]
/// 恒 false，切断环境 [DefaultTextStyle]——`Text` 会与调用处默认样式合并
/// （Material `bodyMedium` 带 `letterSpacing: 0.3`、`height: 1.4`），而
/// 文本量测不合并；两侧不同源时渲染宽于量测宽，末字会软换行到
/// 被裁的第二行（贴纸盒按量测宽高固定）。颜色由填充层与描边层各自写入，
/// 正文字号由贴纸整体缩放承担（缩放已含在 [fontSize] 里，不设字号档）。
/// 语义档（随系统字号）：正文与点名承载语义、随系统字号缩放，
/// 量测与渲染两侧吃**同一个缩放值**（调用处 `MediaQuery.textScalerOf`），
/// 贴纸盒按缩放后的量测值重算。
TextStyle noteStickerTextStyle(double fontSize) =>
    TextStyle(inherit: false, fontSize: fontSize);

/// 备注贴纸浮层：播放头 [positionMs] 落在某条时间窗内时渲染该贴纸，
/// 否则不渲染（窗外消失）。
///
/// 选中态与命中面：传入 [registration] 时，本组件把**渲染出的
/// 像素矩形（或窗外 null）按播放头驱动同步进注册接线**（命中判定与渲染
/// 同源），并监听选中变化重建选中框——宿主点选仲裁
/// （[resolvePlaybackOverlayTap]）与出窗清选中由此在宿主侧可达。
///
/// 坐标系契约：[contentRect] 与渲染输出同用全局逻辑坐标，宿主的浮层
/// Stack 须全屏且位于全局原点（与节拍动画浮层同款契约）。
class NoteStickerOverlay extends ConsumerStatefulWidget {
  const NoteStickerOverlay({
    super.key,
    required this.positionMs,
    required this.contentRect,
    required this.faceDirection,
    this.framingSelection,
    this.readOnly = false,
    this.registration,
    this.onDelete,
    this.onOpenEditor,
    this.onJumpToFragment,
    this.onToggleLock,
  });

  /// 当前播放头位置（毫秒，宿主从播放位置流驱动）。
  final int positionMs;

  /// 视频内容矩形（信箱内画面区；归一化几何的参考系与钳制框）。
  final Rect contentRect;

  /// 本面此刻的方向（宿主经画面方向库读 `directionOf(sourceVideo)`）：
  /// 贴纸按它做水平坐标换算，渲染与命中共用同一次换算。
  final FaceDirection faceDirection;

  /// 取景选区：非空时归一化几何先按**选区窗口**换算再映射到
  /// [contentRect]（此时 [contentRect] 是取景后的画面矩形）；null = 未调过。
  final FramingSelection? framingSelection;

  /// 注册接线（宿主注入）；null = 纯展示（无命中面、无选中框）。
  final NoteStickerOverlayRegistration? registration;

  /// 编辑态（控制层展开）：窗内贴纸**只读常显**（便于边编辑边对照
  /// 画面）且**完全不参与命中**——清注册接线的矩形与选中、无选中框；点其
  /// 矩形无反应、透传宿主（宿主侧由控制层覆盖层接管，与节拍动画浮层
  /// `readOnly` 同款口径）。播放态（false）行为不变。true 时贴纸
  /// 完全不接几何手势（单指平移 / 双指缩放均不起手）。
  final bool readOnly;

  /// 左上删除：宿主经标注编辑模块提交 [RemoveNote]（入撤销史、
  /// 不受锁定分段管——锁只护分段结构）。
  final void Function(NoteSticker note)? onDelete;

  /// 右上打开编辑器：宿主打开唯一编辑器面（与轨片段单击同一面）。
  final void Function(NoteSticker note)? onOpenEditor;

  /// 左下跳转：宿主走播放会话模式唯一写路径进编辑态并打定位
  /// 高亮。
  final void Function(NoteSticker note)? onJumpToFragment;

  /// 右下锁角：宿主经标注编辑模块提交 [ToggleNoteLock]（取反
  /// 内容锁，入撤销史、不受锁定分段管）。图标随锁定态切换
  /// （锁定 = 闭锁 / 未锁定 = 开锁），点击无动作 = 回调未注入。
  final void Function(NoteSticker note)? onToggleLock;

  @override
  ConsumerState<NoteStickerOverlay> createState() => _NoteStickerOverlayState();
}

class _NoteStickerOverlayState extends ConsumerState<NoteStickerOverlay> {
  /// 进行中的贴纸几何拖动会话（第 8 个拖动会话族）：单指平移与
  /// 双指缩放共用一条会话（ScaleGestureRecognizer 双语义），逐帧经
  /// [AnnotationDragSession.moveTo] 提交（模块内单点钳制）、收口一次净
  /// 变化。null = 无会话；非 null 时同带起手几何与起手焦点（换算起点）。
  ({
    AnnotationDragSession<NoteGeometry, NoteGeometry> session,
    NoteGeometry start,
    Offset focal,
  })?
  _geometryDrag;

  /// 贴纸排版缓存：命中键 + 装配结果。播放头驱动的逐帧重建只在
  /// 键变化时重新装配与量测，其余帧直接吃缓存值。
  _StickerLayoutKey? _layoutKey;

  _StickerLayout? _layout;

  /// 按当前（文本、字号、系统字号缩放、名册取色）装配可见分段、取量测与
  /// 渲染共用的样式并量测盒尺寸；命中缓存即复用，不跑文本量测。
  _StickerLayout _stickerLayout({
    required NoteSticker note,
    required double fontSize,
    required TextScaler textScaler,
    required Map<String, int> rosterColors,
  }) {
    final key = _StickerLayoutKey(
      text: note.text,
      fontSize: fontSize,
      textScaler: textScaler,
      rosterColors: rosterColors,
    );
    final cached = _layout;
    if (cached != null && _layoutKey == key) return cached;
    final spans = NoteMentionSpans(note, rosterColors);
    final style = noteStickerTextStyle(fontSize);
    final assembled = _StickerLayout(
      spans: spans,
      style: style,
      size: measureTextExtent(
        TextSpan(children: spans.fillSpans).toPlainText(),
        style,
        scaler: textScaler,
        maxLines: 1,
      ),
    );
    _layoutKey = key;
    _layout = assembled;
    return assembled;
  }

  @override
  void initState() {
    super.initState();
    widget.registration?.addListener(_onRegistrationChanged);
    // 手势进行中出窗：走既有会话结束路径中断（幂等，净变化照常提交）。
    widget.registration?.onWindowExit = _endGeometrySession;
  }

  @override
  void didUpdateWidget(NoteStickerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.registration, widget.registration)) {
      if (oldWidget.registration?.onWindowExit == _endGeometrySession) {
        oldWidget.registration?.onWindowExit = null;
      }
      oldWidget.registration?.removeListener(_onRegistrationChanged);
      widget.registration?.addListener(_onRegistrationChanged);
      widget.registration?.onWindowExit = _endGeometrySession;
    }
  }

  void _onRegistrationChanged() {
    // 自己 build 内触发的窗内→窗外通知会落在这里：同元素 markNeedsBuild
    // 合法（本来就在重建），其余时机即时刷新选中框。
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // 会话中断走既有结束路径（幂等；净变化由会话照常提交、不半写）。
    _endGeometrySession();
    widget.registration?.onWindowExit = null;
    widget.registration?.removeListener(_onRegistrationChanged);
    super.dispose();
  }

  /// 几何手势是否活着：窗口内的播放态 + 选中态（未选中穿透手势、编辑态
  /// 纯展示，可见性条目）。
  bool get _geometryGestureArmed =>
      !widget.readOnly && (widget.registration?.selected ?? false);

  void _onGeometryScaleStart(ScaleStartDetails details) {
    if (!_geometryGestureArmed) return;
    final notes = ref.read(noteStickersProvider);
    final index = noteStickerIndexAt(notes, widget.positionMs);
    if (index == null) return;
    // 内容锁：已锁备注的贴纸几何手势起手前只读判定、静默不参与
    // （不开始会话、不弹提示，照「锁定分段」对拖动起手的既有口径）。
    if (notes[index].locked) return;
    final start = notes[index].geometry;
    final focal = details.localFocalPoint;
    _geometryDrag = (
      session: ref.read(annotationEditorProvider).beginNoteGeometryDrag(index),
      start: start,
      focal: focal,
    );
  }

  void _onGeometryScaleUpdate(ScaleUpdateDetails details) {
    final drag = _geometryDrag;
    if (drag == null) return;
    // 像素 → 归一化换算单点（noteGeometryFromGesture；按面方向反相 =
    // 渲染换算的逆）；钳制在模块内单点收口（clampNoteGeometry），此处只
    // 陈述请求。
    drag.session.moveTo(
      noteGeometryFromGesture(
        start: drag.start,
        contentRect: widget.contentRect,
        panDelta: details.localFocalPoint - drag.focal,
        pinchRatio: details.scale,
        faceDirection: widget.faceDirection,
        selection: widget.framingSelection,
      ),
    );
  }

  void _onGeometryScaleEnd(ScaleEndDetails details) => _endGeometrySession();

  /// 收口几何会话（幂等）：一次手势至多一个净变化撤销步。收口写
  /// provider（历史/保存），可能被 build 期路径触发（出窗同步在宿主
  /// build 内到达）——end 推迟到微任务，不在 build 期写状态。
  void _endGeometrySession() {
    final drag = _geometryDrag;
    _geometryDrag = null;
    if (drag != null) {
      scheduleMicrotask(drag.session.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final registration = widget.registration;
    final positionMs = widget.positionMs;
    final note = noteStickerAt(ref.watch(noteStickersProvider), positionMs);
    // 编辑态：只读常显、完全不参与命中——清矩形与选中；窗外照旧不渲染。
    if (widget.readOnly) {
      registration?.enterEditingReadOnly();
      if (note == null) return const SizedBox.shrink();
    } else if (note == null) {
      // 播放头出窗：同步 null（清选中 + 中断会话边沿）。
      registration?.setRect(null);
      return const SizedBox.shrink();
    }
    // 排版测量按渲染字号（基准 × 系数）一次成型、且与渲染**同一样式**
    //（[noteStickerTextStyle]）：测量尺寸即渲染尺寸，不依赖「排版对字号
    // 线性」假设、也不受环境默认样式影响；maxLines 1 = 单行标签的本义
    //（贴纸不换行，末字不落到被裁的第二行）。positioning 用 scale = 1 的
    // 同落点几何（缩放已含在测量尺寸里，noteStickerRect 只做归一化定位与
    // 钳制）。
    final fontSize = kNoteStickerBaseFontSize * note.geometry.scale;
    // 点名语法：按**当前名册**解析——文本是唯一真源；语法字符被隐藏、
    // 名字段用代表色。量测与渲染吃**同一组分段 span**（可见分段），盒尺寸
    // 与显示文本逐位一致。
    // 语义档（随系统字号）：量测吃调用处的系统字号缩放值，渲染侧
    //（[NoteStickerText]）取同一环境值——两侧同源，贴纸盒按缩放后的量测
    // 尺寸重算。
    //
    // 装配与量测按（文本、字号、系统字号缩放、名册取色）缓存——
    // 播放头驱动的逐帧重建命中缓存、不再跑文本量测。
    final rosterColors = noteMentionRosterColors(
      ref.watch(dancerRosterProvider),
    );
    final layout = _stickerLayout(
      note: note,
      fontSize: fontSize,
      textScaler: MediaQuery.textScalerOf(context),
      rosterColors: rosterColors,
    );
    final mentionSpans = layout.spans;
    final textStyle = layout.style;
    final stickerSize = layout.size;
    final placed = note.geometry.scale == 1
        ? note.geometry
        : NoteGeometry(
            centerX: note.geometry.centerX,
            centerY: note.geometry.centerY,
          );
    final rect = noteStickerRect(
      geometry: placed,
      contentRect: widget.contentRect,
      stickerSize: stickerSize,
      faceDirection: widget.faceDirection,
      selection: widget.framingSelection,
    );
    // 窗内（播放态）：渲染矩形即命中矩形（注册接线与渲染同源，不重测）；
    // 编辑态不注册（无命中面）。
    if (!widget.readOnly) registration?.setRect(rect);
    final selected = !widget.readOnly && (registration?.selected ?? false);
    // 外层垫一圈角工具命中区（[kNoteStickerToolHitExtent] 每边）：角工具
    // 挂在贴纸四角外侧、各占一个独立命中区（互不重叠、不遮字；Stack 命
    // 中判定不越自身界，故外扩区必须是本 Stack 的一部分）。文本居中在原
    // 贴纸矩形内，全局坐标与注册接线的矩形一致。透明外扩区
    // （SizedBox 无 child 命中）不拦手势。
    const extent = kNoteStickerToolHitExtent;
    const pad = kNoteStickerSelectionPadding;
    return Positioned(
      left: rect.left - extent,
      top: rect.top - extent,
      child: SizedBox(
        width: stickerSize.width + extent * 2,
        height: stickerSize.height + extent * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: extent,
              top: extent,
              // 贴纸主体 = 几何手势面：单指落主体即平移、双指等比
              // 缩放；只在窗口内播放态 + 选中态起手——未选中 / 编辑态直接
              // 不挂识别器（穿透手势，不参与竞技场），
              // 回调内 armed 守卫仅作防御。逐帧经模块拖动会话提交——渲染由
              // provider 驱动、与写后真实落点同源。
              child: IgnorePointer(
                ignoring: !_geometryGestureArmed,
                child: GestureDetector(
                  onScaleStart: _onGeometryScaleStart,
                  onScaleUpdate: _onGeometryScaleUpdate,
                  onScaleEnd: _onGeometryScaleEnd,
                  behavior: HitTestBehavior.opaque,
                  child: SizedBox(
                    width: stickerSize.width,
                    height: stickerSize.height,
                    child: NoteStickerText(
                      segments: mentionSpans.mention.segments,
                      baseStyle: textStyle,
                      rosterColors: rosterColors,
                    ),
                  ),
                ),
              ),
            ),
            // 选中态：贴纸矩形外圈的青色虚线框。IgnorePointer：纯
            // 视觉，不挡贴纸主体的几何手势面。
            if (selected)
              Positioned(
                left: extent - pad,
                top: extent - pad,
                width: stickerSize.width + pad * 2,
                height: stickerSize.height + pad * 2,
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const Key('note_sticker_selected'),
                    painter: _selectionBorderPainter(),
                  ),
                ),
              ),
            // 选中态四角工具（次序 = [OverlayCorner] 枚举序）；
            // 取消选中即消失。
            if (selected) ..._cornerTools(note),
          ],
        ),
      ),
    );
  }

  /// 四角工具（键 / 图标 / 点击回调在此收敛；次序 = [OverlayCorner]
  /// 枚举序）：左上删除 / 右上打开编辑器 / 左下跳转 / 右下锁定。回调
  /// 未注入 = 该工具点击无动作（仍照常渲染）。
  List<Widget> _cornerTools(NoteSticker note) {
    // 回调统一先取局部：非空才包成工具点击（未注入 = 点击无动作）。
    final onDelete = widget.onDelete;
    final onOpenEditor = widget.onOpenEditor;
    final onJumpToFragment = widget.onJumpToFragment;
    final onToggleLock = widget.onToggleLock;
    final byCorner = <OverlayCorner, Widget>{
      OverlayCorner.topLeft: _cornerTool(
        alignment: Alignment.topLeft,
        key: const Key('note_sticker_tool_delete'),
        icon: Icons.delete_outline,
        label: '删除这段备注',
        onTap: onDelete == null ? null : () => onDelete(note),
      ),
      OverlayCorner.topRight: _cornerTool(
        alignment: Alignment.topRight,
        key: const Key('note_sticker_tool_open_editor'),
        icon: Icons.edit,
        label: '编辑这段备注的文字',
        onTap: onOpenEditor == null ? null : () => onOpenEditor(note),
      ),
      OverlayCorner.bottomLeft: _cornerTool(
        alignment: Alignment.bottomLeft,
        key: const Key('note_sticker_tool_jump'),
        icon: Icons.center_focus_weak,
        label: '定位到该备注片段',
        onTap: onJumpToFragment == null ? null : () => onJumpToFragment(note),
      ),
      // 锁角：图标随内容锁字段即时反映——与备注片段锁定
      // 标识同源（同一 locked 字段）；再点解锁（锁是保护不是锁死）。
      OverlayCorner.bottomRight: _cornerTool(
        alignment: Alignment.bottomRight,
        key: const Key('note_sticker_tool_lock'),
        icon: note.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
        label: note.locked ? '解锁备注贴纸' : '锁定备注贴纸',
        onTap: onToggleLock == null ? null : () => onToggleLock(note),
      ),
    };
    return [for (final corner in OverlayCorner.values) byCorner[corner]!];
  }

  Widget _cornerTool({
    required AlignmentGeometry alignment,
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    // 命中盒 48×48：外扩量同取 48，故命中域贴纸边为界、恒不互吞；
    // 图标 24 按内侧角对齐、距贴纸边 4dp——命中盒向贴纸外扩，不盖正文。
    final innerAlignment = switch (alignment) {
      Alignment.topLeft => Alignment.bottomRight,
      Alignment.topRight => Alignment.bottomLeft,
      Alignment.bottomLeft => Alignment.topRight,
      _ => Alignment.topLeft,
    };
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: SizedBox(
          width: kNoteStickerToolHitExtent,
          height: kNoteStickerToolHitExtent,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Semantics(
              button: true,
              enabled: onTap != null,
              label: label,
              child: Align(
                alignment: innerAlignment,
                child: Padding(
                  padding: const EdgeInsets.all(kNoteStickerToolIconInset),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: kNoteStickerToolIconSize,
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

/// 贴纸排版缓存键：装配与量测结果只随这四项变化——文本、字号、
/// 系统字号缩放、名册取色（点名着色决定可见分段、故进键）。键即装配与量测
/// 的全部入参，两者不会各读一套。
class _StickerLayoutKey {
  const _StickerLayoutKey({
    required this.text,
    required this.fontSize,
    required this.textScaler,
    required this.rosterColors,
  });

  final String text;

  final double fontSize;

  final TextScaler textScaler;

  final Map<String, int> rosterColors;

  @override
  bool operator ==(Object other) =>
      other is _StickerLayoutKey &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.textScaler == textScaler &&
      mapEquals(other.rosterColors, rosterColors);

  @override
  int get hashCode {
    var rosterHash = 0;
    for (final entry in rosterColors.entries) {
      rosterHash ^= Object.hash(entry.key, entry.value);
    }
    return Object.hash(text, fontSize, textScaler, rosterHash);
  }
}

/// 一条贴纸排版装配：点名分段、量测与渲染共用样式、量测盒尺寸。
class _StickerLayout {
  const _StickerLayout({
    required this.spans,
    required this.style,
    required this.size,
  });

  final NoteMentionSpans spans;

  final TextStyle style;

  final Size size;
}

/// 选中框画笔：贴纸矩形外圈的青色虚线矩形，取值 = 描边宽
/// [kNoteStickerOutlineWidth]、线宽内缩半个线宽让描边落在矩形边内。
DashedSelectionBoxPainter _selectionBorderPainter() =>
    DashedSelectionBoxPainter(
      color: kNoteStickerSelectionColor,
      strokeWidth: kNoteStickerOutlineWidth,
      inset: kNoteStickerOutlineWidth / 2,
    );

/// 名册只读面 → 「名字 → 代表色」表（点名着色的取色源；贴纸与备注
/// 片段框内文本两处消费同源）。
Map<String, int> noteMentionRosterColors(Iterable<DancerRosterEntry> roster) =>
    {for (final entry in roster) entry.name: entry.color};

/// 一条备注的点名校装配结果（贴纸与备注片段框内文本共用的
/// **唯一装配入口**）：[mention] = 按当前名册的解析（文本唯一真源），
/// [fillSpans] = 量测与渲染共用的分段填充 span——两处消费各取所需，
/// 装配序列只此一份。
class NoteMentionSpans {
  factory NoteMentionSpans(NoteSticker note, Map<String, int> rosterColors) {
    final mention = parseNoteMentions(note.text, rosterColors.keys);
    return NoteMentionSpans._(
      mention,
      noteStickerFillSpans(
        segments: mention.segments,
        rosterColors: rosterColors,
      ),
    );
  }

  const NoteMentionSpans._(this.mention, this.fillSpans);

  final NoteMentionParse mention;

  final List<TextSpan> fillSpans;
}

/// 一个段的填充底色（fill 与 stroke 两层共用的一份取色）：正文段恒白、
/// 点名段用名册代表色（名字已不在名册 = 白，优雅降级）。
int _segmentFillColor(
  NoteMentionSegment segment,
  Map<String, int> rosterColors,
) => segment.name == null
    ? kNoteBodyColor
    : rosterColors[segment.name] ?? kNoteBodyColor;

/// 贴纸填充层的分段 span（**量测与渲染的同源唯一样式来源**）：
/// 正文段恒白（[kNoteBodyColor]）、点名段用名册代表色（名字已不在名册
/// = 白，优雅降级）。调用方（浮层 build）对同一组分段既造量测 span 也造
/// 渲染 span，盒尺寸与渲染逐位一致。
List<TextSpan> noteStickerFillSpans({
  required List<NoteMentionSegment> segments,
  required Map<String, int> rosterColors,
}) => [
  for (final segment in segments)
    TextSpan(
      text: segment.text,
      style: TextStyle(color: Color(_segmentFillColor(segment, rosterColors))),
    ),
];

/// 贴纸描边层的分段 span：描边恒开、颜色**按段**由该段底色
/// 派生（[noteSegmentStrokeColor]）——正文段固定黑边（继承根样式画笔，
/// 不写内层样式）、点名段按判据取黑/白（内层 span 覆写根画笔；纯白点名
/// 固定白边）。纯白点名段的线宽收窄为 [kNoteStickerWhiteMentionStrokeWidth]
/// ——让位给外层黑边（[noteStickerOuterStrokeSpans]）。
List<TextSpan> noteStickerStrokeSpans({
  required List<NoteMentionSegment> segments,
  required Map<String, int> rosterColors,
}) => [
  for (final segment in segments)
    TextSpan(
      text: segment.text,
      style: _segmentStrokeStyle(segment, rosterColors),
    ),
];

/// 一个点名段的描边样式（正文段返回 null——继承根样式画笔；起
/// 纯白点名段线宽收窄，颜色判据不变）。
TextStyle? _segmentStrokeStyle(
  NoteMentionSegment segment,
  Map<String, int> rosterColors,
) {
  if (segment.name == null) return null;
  final fill = _segmentFillColor(segment, rosterColors);
  final whiteMention =
      noteSegmentOuterStrokeColor(fill, mention: true) != null;
  return TextStyle(
    foreground: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = whiteMention
          ? kNoteStickerWhiteMentionStrokeWidth
          : kNoteStickerOutlineWidth
      ..color = Color(noteSegmentStrokeColor(fill, mention: true)),
  );
}

/// 纯白点名段的**外层黑边** span：仅纯白点名段带共用线宽的
/// 黑描边画笔（[kNoteStickerOutlineWidth]，可见外沿与其它字一致），
/// 其余段不带样式。不存在纯白点名段时返回 null——调用方不挂外层。
TextSpan? noteStickerOuterStrokeSpans({
  required List<NoteMentionSegment> segments,
  required Map<String, int> rosterColors,
}) {
  final children = [
    for (final segment in segments)
      TextSpan(
        text: segment.text,
        style: segment.name != null &&
                noteSegmentOuterStrokeColor(
                  _segmentFillColor(segment, rosterColors),
                  mention: true,
                ) !=
                null
            ? TextStyle(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = kNoteStickerOutlineWidth
                  ..color = const Color(kNoteStrokeBlackColor),
              )
            : null,
      ),
  ];
  if (!children.any((s) => s.style != null)) return null;
  return TextSpan(children: children);
}

/// 贴纸文本：描边层（stroke 前景画笔、颜色按段派生；纯白点名段
/// 线宽收窄）在下、填充层在上——填充层按**点名语法可见分段**
/// 着色——正文段恒白、点名段用名册代表色。存在纯白点名段时其下再挂一层
/// 外黑边。语法字符（`@` 与紧随的分隔空格）不在
/// [segments] 里 = 不参与排版与量测（文本唯一真源、渲染时按当前
/// 名册解析）。
///
/// [baseStyle] 由调用方传入量测用的同一样式（[noteStickerTextStyle]）：
/// 两层都以它为基准、且 [TextStyle.inherit] 为 false（不再与环境默认样式
/// 合并），保证渲染尺寸与量测尺寸逐位一致；文本为单行标签（不软换行、
/// 溢出可见），因此即便有亚像素偏差也不会把末字换行裁掉。
class NoteStickerText extends StatelessWidget {
  const NoteStickerText({
    super.key,
    required this.segments,
    required this.baseStyle,
    this.rosterColors = const {},
  });

  /// 点名语法解析出的可见分段（含正文段与点名段）。
  final List<NoteMentionSegment> segments;

  /// 量测与渲染同源的基准样式（字号已按等比系数解析）。
  final TextStyle baseStyle;

  /// 名册代表色表（名字 → ARGB）。
  final Map<String, int> rosterColors;

  @override
  Widget build(BuildContext context) {
    final fill = noteStickerFillSpans(
      segments: segments,
      rosterColors: rosterColors,
    );
    // 外层黑边：纯白点名段的白边之外再包一层更细黑边（线宽 =
    // [kNoteStickerOutlineWidth]，总外沿与其它字一致）。只在该段存在时
    // 挂载（不多付一次文本排版）；深色点名与正文段的描边逐位不变。
    final outerStroke = noteStickerOuterStrokeSpans(
      segments: segments,
      rosterColors: rosterColors,
    );
    return Stack(
      // 描边画笔在字形外沿各溢出半个线宽，不裁（尺寸与量测同源，裁只裁
      // 描边墨迹）。
      clipBehavior: Clip.none,
      children: [
        if (outerStroke != null)
          Text.rich(
            outerStroke,
            style: baseStyle,
            textScaler: MediaQuery.textScalerOf(context),
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
        Text.rich(
          // 描边层恒开：根样式带黑色 stroke 前景画笔（正文段固定
          // 黑边、不走判据），点名段 span 内层覆写为按其底色派生的描边色。
          // 样式必须走 `style:` 参数——`Text` 把它作为段落根样式、`inherit`
          // 为 false 时不再与环境默认样式合并，量测/渲染才保持同源。
          TextSpan(
            children: noteStickerStrokeSpans(
              segments: segments,
              rosterColors: rosterColors,
            ),
          ),
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = kNoteStickerOutlineWidth
              ..color = const Color(kNoteStrokeBlackColor),
          ),
          textScaler: MediaQuery.textScalerOf(context),
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
        Text.rich(
          TextSpan(children: fill),
          // 根样式带正文白：正文段颜色在根、点名段由内层 span 覆写；颜色
          // 不参与排版，量测/渲染仍同源。
          style: baseStyle.copyWith(color: const Color(kNoteBodyColor)),
          textScaler: MediaQuery.textScalerOf(context),
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.visible,
        ),
      ],
    );
  }
}
