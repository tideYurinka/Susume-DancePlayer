/// 练习片段轨域：练习视频轨整行的模块。
///
/// 一行里的四件事收在本域：**块体矩形求值与开关**（源区间经共用纯件
/// [intervalBlockRect] 映射为行内像素）、**该行的命中解析**（行内局部坐标 →
/// 片段，带级「编辑内容」判定与压在块上的播放头竖线共用同一次求值）、
/// **播放头点按**（压在块缘上的那 2dp 走与块体同一条点选路径）、**块体渲染与
/// 截取拖动族**（端点带起手 + 会话句柄 + 抓取偏移 + 准入，逐族经拖动域的按族
/// 注册入口登记）。行背景、块体与回看浮条的根浮层装配都在本域的自带 widget
/// 子树里；本域只收一个显式输入值对象 [TrackPracticeRowInput]（片段列表、
/// 行矩形与整带高、时间轴、播放头读数、该行回调）加一个截取拖动句柄
/// [TrackPracticeRowTrim]；块体的激活与选中两槽随其 provider 在域内现读。
///
/// 依赖方向：本域 → 拖动域（按族注册入口与句柄）+ 轨道行表（行身份与行矩形）
/// + 时间纯件（[TimelineAxis] / [TimelineWindow]）
/// + 标注编辑模块（`annotation_editor.dart`：片段模型、激活与选中 provider、
/// 标注编辑会话与门禁目标）+ `../annotation/` 下的区间片段行共用纯件（块矩形
/// 求值与端点词条）+ 集中视觉常量 `visual_tokens.dart` +
/// 浮条域（回看浮条）+ 画面方向（在屏面判据），**单向**：不 import 轨道带 /
/// 控制层 / 演出层 / 播放页，反向只有轨道带一处组装本域；本域之间也没有互相
/// import。块体视觉常量（`kPracticeClip*`）随本域走，由轨道带 export 保持既有
/// 引用面。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/compare_materials.dart' show PracticeClip;
import '../annotation/interval_fragment_row.dart'
    show
        IntervalBlockRect,
        IntervalEdge,
        IntervalHitRegion,
        IntervalSpan,
        intervalBlockRect,
        intervalHitRegion;
import '../core/clock_text.dart';
import '../surface_direction/surface_direction.dart' show SurfaceFace;
import 'annotation_editor.dart'
    show
        AnnotationGestureTarget,
        DurationDragSession,
        exitPracticeClipReview,
        practiceClipActivationProvider,
        practiceClipById,
        practiceOnscreenFaceProvider,
        selectedPracticeClipIdProvider;
import 'track_band_drag.dart'
    show
        ClipTrimDragTarget,
        TrackBandDragDeclaration,
        TrackBandDragFamilies,
        TrackBandDragHandle,
        TrackBandDragSession,
        TrackBandDragTarget;
import 'track_fragment_bubble.dart';
import 'track_row_table.dart';
import 'track_time.dart';
import 'visual_tokens.dart';

/// 练习片段块的视觉常量（见词条「练习片段」）。
const Color kPracticeClipBlockColor = Color(0xCC7E57C2);
const double kPracticeClipBlockRadius = 3;

/// 回看中（激活）的块体填充与描边宽：常态为半透明紫、无描边；回看中换成
/// 不透明紫 + 加粗白描边——块窄时描边几乎看不见，填充变化才是可辨的那一
/// 半；与选中的内缩细描边（1px）仍可区分。
const Color kPracticeClipActiveBlockColor = Color(0xFF7E57C2);
const double kPracticeClipActiveBorderWidth = 3;

/// 选中练习片段的块体描边色（与学习段选中同族的高亮白）。
const Color kPracticeClipSelectedBorderColor = Color(0xFFFFFFFF);

/// 练习片段块矩形：源时间区间经共用纯件 [intervalBlockRect] 映射为行内像素
/// （含窗口求交裁切，「几何与判据同源」）。位置固定——只算摆位，无
/// 交互会话参与；块与窗口无交（裁后零宽）返回空（不渲染）。
IntervalBlockRect? practiceClipBlockRect(
  PracticeClip clip, {
  required TimelineAxis axis,
}) {
  final window =
      axis.window ??
      TimelineWindow(total: axis.total, start: Duration.zero, end: axis.total);
  return intervalBlockRect(
    span: IntervalSpan(startMs: clip.sourceStartMs, endMs: clip.sourceEndMs),
    window: IntervalSpan(
      startMs: window.start.inMilliseconds,
      endMs: window.end.inMilliseconds,
    ),
    trackWidth: axis.contentWidth,
    contentLeft: axis.contentLeft,
  );
}

/// 练习片段块命中解析（带内局部坐标 → 片段；空 = 不在任何块上）。
///
/// 带级「编辑内容」判定与压在块上的播放头竖线**共用本入口**（「命中只
/// 留一个答案」）：块矩形出自从 build 期同一份几何（[practiceClipBlockRect]），
/// 不复制第二份块框算法。纵带判定问行集（行区间含两端、行优先于间隙的口径由
/// 行表钉死），不手写包含式比较。
PracticeClip? practiceClipHitAtLocal(
  Offset local, {
  required TimelineAxis axis,
  required TrackRowTable rowTable,
  required List<PracticeClip> clips,
}) {
  if (rowTable.rowAt(local.dy) != TrackRowId.practiceVideo) return null;
  for (final clip in clips) {
    final rect = practiceClipBlockRect(clip, axis: axis);
    if (rect == null) continue;
    // 闭区间：右缘也算压在块上——刚录完的停录点、以及激活后的片段首都可能
    // 正好落在块的边界上（块框半开是渲染盒细节，不是用户语义；边界两侧相差
    // 不足一个像素，取「压在块上」更贴合「处处可点」）。
    if (local.dx >= rect.left && local.dx <= rect.left + rect.width) {
      return clip;
    }
  }
  return null;
}

/// 练习片段轨域的输入值对象：片段列表、行矩形与整带高、时间轴、播放头读数与
/// 该行回调，加一个截取拖动句柄（[trim]）。行集只作命中入口的入参（见
/// [practiceClipHitAtLocal]），不进本值对象——本域不拿它作答。
///
/// 播放头读数取**回调**而不是快照：播放头位置只经会话域的 [ValueListenable]
/// 驱动预览线叶子层重绘（分层刷新），本行只在一次点按发生的那一刻读
/// 它的现值——读回调让「点按落在哪根线/哪一块上」与当时屏上的预览线同源，
/// 又不把整行拖进逐帧重建。
class TrackPracticeRowInput {
  const TrackPracticeRowInput({
    required this.clips,
    required this.rowRect,
    required this.bandHeight,
    required this.axis,
    required this.playhead,
    required this.onToggleClip,
    required this.trim,
  });

  /// 练习视频轨的在轨片段（按源起点升序、两两不重叠；空列表 = 空轨）。
  final List<PracticeClip> clips;

  /// 本行矩形（行表给出的顶与高；本域自带子树落位在整带坐标系里）。
  final TrackRowRect rowRect;

  /// 整带高（行表 [TrackRowTable.totalHeight]）：本域子树占满带高，行内各件
  /// 因此沿用「块矩形与行矩形同为带内坐标」的既有落位口径，纵向越出行高的
  /// 子树（端点带、浮条锚）也不被行高裁掉。
  final double bandHeight;

  /// 时间轴（含内容区左缘——轨道片头带让位的口径由几何模块一处给出）。
  final TimelineAxis axis;

  /// 播放头显示位置读数（拖动中 = 拖动目标；点按那一刻取其现值）。
  final Duration Function() playhead;

  /// 片段点选一次点按的双写（激活槽 + 选中槽；两槽再点同片段各自取消）。
  final void Function(PracticeClip clip) onToggleClip;

  /// 本行截取拖动族句柄。
  final TrackPracticeRowTrim trim;
}

/// 练习片段截取拖动族（带级三个成员的出边之一：拖动域句柄）。
///
/// 句柄字段与起手/逐帧/收口三件包装都住在**本域**（带级 State 零残留）；
/// 族声明条目在 [install] 处经拖动域的按族注册入口登记，声明里的
/// `beginSession` 工厂由带侧注入（模块会话住标注编辑模块），抓取偏移与准入
/// 直接问本域持有的片段列表读数。
class TrackPracticeRowTrim {
  TrackPracticeRowTrim({
    required this.dragDomain,
    required this.toTimeMs,
    required this.clips,
    required this.beginSession,
  });

  /// 拖动域（起手门序言、单槽 + 世代、逐帧钳制都在域里）。
  final TrackBandDragSession dragDomain;

  /// 带内局部 x → 请求时间（带级几何唯一构造入口给出的换算，几何不可用返
  /// 回空）；钳制由拖动域在换算前统一做。[bandWidth] 由拖动域交下，与本帧
  /// 钳制同源。
  final Duration? Function(double localX, double bandWidth) toTimeMs;

  /// 片段列表读数（现读现写，不闭包捕获某一帧的值）。
  final List<PracticeClip> Function() clips;

  /// 模块会话工厂（标注编辑模块的 `beginPracticeClipTrimDrag`）。
  final DurationDragSession Function(TrackBandDragTarget target) beginSession;

  /// 本族句柄（单槽里的当前会话；空 = 无截取在跑）。
  TrackBandDragHandle? _handle;

  /// 逐族经拖动域的按族注册入口登记本族声明（条目随族走；本域唯一登记点）。
  void install(TrackBandDragFamilies families) {
    families.register(
      AnnotationGestureTarget.practiceClipTrim,
      TrackBandDragDeclaration(
        toTime: toTimeMs,
        // 练习片段截取独享混区 burst 让位；**不走实时预览**（族声明里没有起手/
        // 逐帧/收口视觉钩子，如实随迁），逐帧落点由句柄交回调用方。
        yieldOnMixedBurst: true,
        beginSession: (target) => beginSession(target),
        admit: _admit,
        readGrabOffsetMs: _grabOffsetMs,
      ),
    );
  }

  /// 端点截取起手（门序言、混区 burst 让位、越界准入、抓取偏移与模块会话全部
  /// 经拖动域）。吸附/钳制/有效练习区间约束全在模块内，widget 不预吸附；落点
  /// 即写 provider（块矩形当帧跟随）。
  void begin(int index, IntervalEdge edge, double localX) {
    _handle = dragDomain.begin(
      TrackBandDragTarget.clipTrim(index, edge),
      localX,
    );
  }

  /// 端点截取逐帧（只经本族句柄；陈旧句柄在域内为空操作）：交回**写后真实
  /// 落点**（无净变化 = 空），与其余各族句柄同一条口径。
  Duration? update(double localX) => _handle?.moveTo(localX);

  /// 端点截取结束（句柄收口，幂等；本族无起手/收口视觉副作用）。
  void end() {
    final handle = _handle;
    _handle = null;
    handle?.end();
  }

  /// 抓取偏移：手指 − 被拖端点当前时刻（同镜像端点拖口径）。
  int _grabOffsetMs(TrackBandDragTarget target, Duration finger) {
    final trim = target as ClipTrimDragTarget;
    final clip = clips()[trim.index];
    final boundary = trim.edge == IntervalEdge.start
        ? clip.sourceStartMs
        : clip.sourceEndMs;
    return finger.inMilliseconds - boundary;
  }

  /// 准入：按片段列表长度越界即静默返回（落点类准入不适用本族，起手局部
  /// x 不读）。
  bool _admit(TrackBandDragTarget target, double _) {
    final index = target.index;
    return index >= 0 && index < clips().length;
  }
}

/// 练习片段轨（自带 widget 子树）：本行的行背景、块体与回看浮条。
///
/// 片段列表与选中/激活两槽在域内现读（widget 自带 provider 读面）；行矩形、
/// 行集、时间轴、播放头读数与截取句柄经输入值对象给全，不碰容器句柄、不出
/// 本行。
class TrackPracticeRow extends ConsumerStatefulWidget {
  const TrackPracticeRow({super.key, required this.input});

  /// 显式输入值对象 + 截取拖动句柄。
  final TrackPracticeRowInput input;

  @override
  ConsumerState<TrackPracticeRow> createState() => _TrackPracticeRowState();
}

class _TrackPracticeRowState extends ConsumerState<TrackPracticeRow> {
  /// 本行渲染盒：带内局部坐标的读取处（本行左缘与带左缘同 x，局部 x 即带内
  /// x）。域内的命中判定与拖动都不经它，只有一次点按的落点换算用。
  RenderBox? get _box {
    final box = context.findRenderObject();
    return box is RenderBox ? box : null;
  }

  /// 一次端点带起手（全局位置 → 带内局部 x）。
  void _startTrim(int index, IntervalEdge edge, Offset globalPosition) {
    final box = _box;
    if (box == null) return;
    widget.input.trim.begin(index, edge, box.globalToLocal(globalPosition).dx);
  }

  /// 逐帧（只经本族句柄）。
  void _moveTrim(Offset globalPosition) {
    final box = _box;
    if (box == null) return;
    widget.input.trim.update(box.globalToLocal(globalPosition).dx);
  }

  @override
  Widget build(BuildContext context) {
    // 片段列表经显式输入值对象给全（带级 watch provider 后下传）；本域自读的
    // 只有**本行自己的两槽**（选中与激活）——它们的写入口也在带级，读面归行。
    final clips = widget.input.clips;
    final selectedClipId = ref.watch(selectedPracticeClipIdProvider);
    // 激活的练习片段：片段块激活描边。在屏是哪一路读唯一派生
    // ——回放件在屏时激活 id 取激活源现值。
    final activeClipId =
        ref.watch(practiceOnscreenFaceProvider) == SurfaceFace.clipPlayback
        ? ref.watch(practiceClipActivationProvider)?.clipId
        : null;
    final rowRect = widget.input.rowRect;
    final axis = widget.input.axis;
    final reviewClip = activeClipId == null
        ? null
        : practiceClipById(clips, activeClipId);
    // 本域子树是**整带坐标系**里的一帧（带级组装点填满行容器）：行内各件
    // （块体、端点带、浮条锚）因此沿用「块矩形与行矩形同为带内坐标」的既有
    // 落位口径；纵向越出行高的子树不被裁剪（与搬迁前同）。
    return SizedBox(
      width: axis.width,
      height: widget.input.bandHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 行背景：练习视频轨常驻显示，空轨亦占高（块体是行内装饰，不是行存在
          // 的条件）。行键仍由带级行容器持有（逐位不变）。
          Positioned(
            left: 0,
            top: rowRect.top,
            width: axis.width,
            height: rowRect.height,
            child: ColoredBox(color: Colors.white.withValues(alpha: 0.06)),
          ),
          for (var i = 0; i < clips.length; i++)
            if (practiceClipBlockRect(clips[i], axis: axis) case final rect?)
              _buildClipBlock(
                index: i,
                clip: clips[i],
                rect: rect,
                active: clips[i].id == activeClipId,
                selected: clips[i].id == selectedClipId,
              ),
          if (reviewClip != null) _buildReviewBubble(reviewClip),
        ],
      ),
    );
  }

  /// 练习片段块：块体只做视觉（位置固定、块体拖动无效——
  /// 语义不变）；两端各挂端点命中带（窄块整段抑制，沿用 [intervalHitRegion]
  /// 的窄块判据与 [kLocalMirrorEdgeHitWidth] 既有口径），端点带**拖动**起手 =
  /// 截取拖动会话，点按仍走块体同一条点选路径（带体不再吞掉点按）。
  Widget _buildClipBlock({
    required int index,
    required PracticeClip clip,
    required IntervalBlockRect rect,
    required bool active,
    required bool selected,
  }) {
    final rowRect = widget.input.rowRect;
    // 窄块判据（与镜像轨同一条规则）：块宽被共用区域划分的窄块阈值抑制了
    // 端点带即不挂端点带。本轨的块体不经共享块壳（颜色与描边自成一套），
    // 故这里直接问区域划分，不另立第二份判据。
    final isNarrow =
        intervalHitRegion(
          blockWidth: rect.width,
          offsetInBlock: 0,
          edgeBandWidth: kLocalMirrorEdgeHitWidth,
          narrowWidth: kLocalMirrorNarrowWidth,
        ) !=
        IntervalHitRegion.startEdge;
    return Positioned(
      key: Key('practice_clip_${clip.id}'),
      left: rect.left,
      top: rowRect.top,
      width: rect.width,
      height: rowRect.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 块体点选：点按 = 选中（再点同片段取消），写进对比态单一
          // 选中槽——「删除」槽的作用对象；选中态块体描边可见。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.input.onToggleClip(clip),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active
                      ? kPracticeClipActiveBlockColor
                      : kPracticeClipBlockColor,
                  borderRadius: BorderRadius.circular(kPracticeClipBlockRadius),
                  // 两态并存且可区分：回看中 = 不透明填充 + 块缘白色 3dp 描边
                  // （窄块靠填充可辨）；选中 = 内缩一圈 1dp 细描边。叠加时同现。
                  border: active
                      ? Border.all(
                          color: Colors.white,
                          width: kPracticeClipActiveBorderWidth,
                        )
                      : null,
                ),
                child: selected
                    ? Padding(
                        padding: const EdgeInsets.all(2),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              kPracticeClipBlockRadius - 2,
                            ),
                            border: Border.all(
                              color: kPracticeClipSelectedBorderColor,
                              width: 1,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          // 端点命中带：所见即所拖，带体贴块内側两角。点按与块体同一
          // 条路径——带体此前只挂拖动识别器，点上去时块体的点按识别
          // 器不在命中路径里（本带 opaque 且后写）、带体的拖动识别器又因未越
          // slop 自我出局 ⇒ 零回调的死区。
          if (!isNarrow)
            for (final edge in IntervalEdge.values)
              Positioned(
                key: Key('practice_clip_${clip.id}_edge_${edge.name}'),
                left: edge == IntervalEdge.start ? 0 : null,
                right: edge == IntervalEdge.end ? 0 : null,
                top: 0,
                width: kLocalMirrorEdgeHitWidth,
                height: rowRect.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.input.onToggleClip(clip),
                  onHorizontalDragStart: (details) =>
                      _startTrim(index, edge, details.globalPosition),
                  onHorizontalDragUpdate: (details) =>
                      _moveTrim(details.globalPosition),
                  onHorizontalDragEnd: (_) => widget.input.trim.end(),
                  onHorizontalDragCancel: widget.input.trim.end,
                ),
              ),
        ],
      ),
    );
  }

  /// 回看浮条：回看中的片段上方「回看中 · 区间 + 退出回看」，住根浮层。组成 =
  /// 带内一个透明的锚定 reporting 块（其渲染盒全局矩形即片段全局矩形，帧末上
  /// 报）+ 根浮层子树里的浮条本体，装配收在 [FragmentBubbleHost]。
  Widget _buildReviewBubble(PracticeClip clip) {
    final rowRect = widget.input.rowRect;
    final block = practiceClipBlockRect(clip, axis: widget.input.axis);
    if (block == null) {
      // 块不在窗内：锚上报块不渲染（其 dispose 清锚）→ 浮条隐藏。
      return const SizedBox.shrink();
    }
    final text =
        '回看中 · ${clockMss(Duration(milliseconds: clip.sourceStartMs))}–'
        '${clockMss(Duration(milliseconds: clip.sourceEndMs))}';
    return FragmentBubbleHost(
      anchorRect: Rect.fromLTWH(
        block.left,
        rowRect.top,
        block.width,
        rowRect.height,
      ),
      text: text,
      bubbleBuilder: (anchorRect, text) => FragmentActionBubble(
        anchorRect: anchorRect,
        text: text,
        actionLabel: '退出回看',
        actionKey: const Key('clip_review_bubble_exit'),
        actionHitKey: const Key('clip_review_bubble_exit_hit'),
        bubbleKey: const Key('clip_review_bubble'),
        onAction: () => exitPracticeClipReview(ref),
      ),
    );
  }
}
