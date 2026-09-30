/// 带内拖动手势域。
///
/// 收「**谁在拖、拖到哪**」一件事：一个起手入口、一个会话槽、一个世代号，
/// 外加每族一条声明。十族的差异（门禁目标、准入、抓取偏移、换算、
/// 视觉簿记与逐帧落点钩子）搬进声明，**逐族如实声明、不强行统一**。本域覆盖
/// 分段线 / 半拍线 / 首尾端标 / 镜像两族 / 备注两族 / 练习片段截取共八族，
/// 外加并入的**预览线拖动**（第九族）与**学习段圈选**（第十族）。其中几处「不合群」的
/// 差异如实入表：混区 burst 让位只出现在练习片段截取族与学习段圈选族，实时
/// 预览与视觉簿记的对齐形态逐族不同，学习段圈选是唯一读二维落点、唯一带取消
/// 路径的族。
/// **唯一的归一**：逐帧横向钳制收成一条规则、一处
/// 实现——横向族一律把带内局部 x 钳到 [0, 带宽]，口径不在族的声明里另立开关。
///
/// ## 接口
///
/// 运行时只有一处入口与一个句柄：[TrackBandDragSession.begin] 收一个目标身份与
/// 带内局部 x，成功给 [TrackBandDragHandle]，失败给空；句柄的三条运行时出口
/// ——[TrackBandDragHandle.moveTo]（横向族：交回写后真实落点或空）、
/// [TrackBandDragHandle.moveToPoint]（二维落点族：交带内局部落点）、
/// 收口的提交与取消两条路径（[TrackBandDragHandle.end] /
/// [TrackBandDragHandle.cancel]，都幂等）。逐帧与收口只能经句柄发生；族的装配面
/// 走下一节的按族注册入口。
///
/// ## 两支帧事务（十族如实分成两支）
///
/// 一族的逐帧出口由**谁**解释，是这十族最大的差异，声明表因此有两支：
///
///   - **模块事务族**（八族）：[TrackBandDragDeclaration.toTime] 把局部 x 换算成
///     请求时间，交 [TrackBandDragDeclaration.beginSession] 的模块拖动会话提交，
///     落点取模块写后真值，经 [TrackBandDragDeclaration.onFrame] 交回族；
///   - **自家帧族**（学习段圈选）：[TrackBandDragDeclaration.beginFrame] 给一个
///     [TrackBandDragFrame]，逐帧读带内局部落点（二维）、提交与取消两条路径都
///     由族自己解释——它改的是选中集合，不是时间落点。
///
/// 预览线拖动（第九族）介于两者之间、如实入表：它**没有模块事务**（seek 不是
/// 编辑命令），故 [TrackBandDragDeclaration.beginSession] 留空——请求即落点，
/// 逐帧真值由 [TrackBandDragDeclaration.toTime] 与
/// [TrackBandDragDeclaration.onFrame] 两条钩子自己解释。
///
/// 两条**既有差异**另有逐族开关，不顺手统一：装载门只挡写盘入口，故
/// [TrackBandDragDeclaration.respectLoadGate] 在预览线拖动为假；双指在场的逐帧
/// 语义逐族不同（让位冻结 / 半途加入回滚取消），故
/// [TrackBandDragDeclaration.freezeOnPinch] 在学习段圈选为假、由它自己的帧回答。
///
/// ## 按族注册（外部装配入口）
///
/// 族的声明条目不由本域内置，也不由带侧一次性拼装成表：[TrackBandDragFamilies]
/// 是本域的**按族登记入口**，外部装配方逐族提交该族的声明条目（门禁目标 +
/// [TrackBandDragDeclaration]），域按门禁目标取用。
///
/// 两条登记语义：**未登记的族起手为空**（不抛错、不弹提示、不留痕——族不在
/// 表内就是「本装配没接这条手势」）；**同一族重复登记时后登记者覆盖先登记者**
/// （注册表按门禁目标成唯一键，不追加第二份）。
///
/// ## 依赖方向（单向）
///
/// 本域 → 标注编辑模块（拖动会话协议与门禁目标枚举）+ 选中域（端标类型
/// [VideoRangeBoundary]，随单值槽搬走）+ 区间片段行共用纯件（端点词条
/// [IntervalEdge]，零 import 的共用件），别无其它 import：不读
/// provider、不碰构建上下文、不注容器、不 import 轨道带 / 控制层 / 演出层 /
/// 播放页，可在无 `ProviderScope`、无 widget pump 下直测。
/// 模型读取（片段 / 备注 / 练习片段 / 时间线 / 锁状态）与模块会话工厂都由
/// 带侧以闭包注入；`globalToLocal` 与「局部 x → 时间」的换算也留在带内装配。
/// 第九、第十族同样不越过这条线：它们只经模块既有门禁词汇取得门禁目标
/// （[AnnotationGestureTarget.previewLineDrag] /
/// [AnnotationGestureTarget.learningTrackTap]，两者在模块门禁表里都是**显式
/// 空清单**），选中写入、命中解析与贴边平移都由带侧注入的闭包承担。
///
/// ## 单槽与世代
///
/// 域持单槽：每次起手递增世代并由句柄携带，新起手直接覆盖旧槽（不隐式收口
/// 旧句柄）。陈旧句柄的逐帧与收口都是空操作，跨族覆盖不会误伤新会话。模块
/// 侧的会话令牌仍是事务唯一性的权威，本域的世代只管隔离。
library;

import 'dart:ui' show Offset;

import '../annotation/interval_fragment_row.dart' show IntervalEdge;
import 'annotation_editor.dart'
    show AnnotationGestureTarget, DurationDragSession;
import 'annotation_selection.dart' show VideoRangeBoundary;

/// 目标身份（带载荷的封闭类型）：域据此穷尽分派，并把它对应的模块门禁目标
/// 交回带侧（门禁仍走模块那张表，本域不另声明一套）。
sealed class TrackBandDragTarget {
  const TrackBandDragTarget();

  /// 分段线移动。
  const factory TrackBandDragTarget.segmentLine(int index) =
      SegmentLineDragTarget;

  /// 半拍线移动。
  const factory TrackBandDragTarget.halfBeat(int index) = HalfBeatDragTarget;

  /// 首尾端标拖动（无下标：命中解析不产出下标）。
  const factory TrackBandDragTarget.range(VideoRangeBoundary boundary) =
      RangeDragTarget;

  /// 镜像片段整体移。
  const factory TrackBandDragTarget.mirrorMove(int index) =
      MirrorMoveDragTarget;

  /// 镜像片段端点拖。
  const factory TrackBandDragTarget.mirrorEdge(int index, IntervalEdge edge) =
      MirrorEdgeDragTarget;

  /// 备注片段整体移。
  const factory TrackBandDragTarget.noteMove(int index) = NoteMoveDragTarget;

  /// 备注片段端点拖。
  const factory TrackBandDragTarget.noteEdge(int index, IntervalEdge edge) =
      NoteEdgeDragTarget;

  /// 练习片段端点截取。
  const factory TrackBandDragTarget.clipTrim(int index, IntervalEdge edge) =
      ClipTrimDragTarget;

  /// 预览线拖动（第九族）：命中列内的控制柄起手转预览线。
  const factory TrackBandDragTarget.previewLine() = PreviewLineDragTarget;

  /// 学习段圈选（第十族）：命中解析留在带侧，这里只承载其结果的段序。
  const factory TrackBandDragTarget.learningSpan(int order) =
      LearningSpanDragTarget;

  /// 命中解析留在带侧，这里只承载其结果的片段下标。
  int get index;

  /// 本目标在标注编辑模块里的门禁目标（起手门禁表的键）。
  AnnotationGestureTarget get gateTarget;
}

/// 分段线移动的目标身份。
final class SegmentLineDragTarget extends TrackBandDragTarget {
  const SegmentLineDragTarget(this.index);

  /// 线下标（命中解析留在带侧，这里只承载结果）。
  @override
  final int index;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.segmentLineMove;
}

/// 半拍线移动的目标身份。
final class HalfBeatDragTarget extends TrackBandDragTarget {
  const HalfBeatDragTarget(this.index);

  /// 线下标（命中解析留在带侧，这里只承载结果）。
  @override
  final int index;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.halfBeatLineMove;
}

/// 首尾端标拖动的目标身份（端标沿用模块词汇 [VideoRangeBoundary]）。
final class RangeDragTarget extends TrackBandDragTarget {
  const RangeDragTarget(this.boundary);

  /// 被拖端标。
  final VideoRangeBoundary boundary;

  /// 首尾端标无下标（命中解析不产出下标）：声明钩子不读本值。
  @override
  int get index => -1;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.rangeBoundaryDrag;
}

/// 镜像片段整体移的目标身份。
final class MirrorMoveDragTarget extends TrackBandDragTarget {
  const MirrorMoveDragTarget(this.index);

  /// 片段下标（命中解析留在带侧，这里只承载结果）。
  @override
  final int index;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.localMirrorMove;
}

/// 镜像片段端点拖的目标身份（端点沿用区间片段行共用纯件的词条
/// [IntervalEdge]）。
final class MirrorEdgeDragTarget extends TrackBandDragTarget {
  const MirrorEdgeDragTarget(this.index, this.edge);

  /// 片段下标。
  @override
  final int index;

  /// 被拖端点。
  final IntervalEdge edge;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.localMirrorEdgeDrag;
}

/// 备注片段整体移的目标身份。
final class NoteMoveDragTarget extends TrackBandDragTarget {
  const NoteMoveDragTarget(this.index);

  /// 片段下标。
  @override
  final int index;

  @override
  AnnotationGestureTarget get gateTarget => AnnotationGestureTarget.noteMove;
}

/// 备注片段端点拖的目标身份（端点沿用模块既有词汇 [IntervalEdge]）。
final class NoteEdgeDragTarget extends TrackBandDragTarget {
  const NoteEdgeDragTarget(this.index, this.edge);

  /// 片段下标。
  @override
  final int index;

  /// 被拖端点。
  final IntervalEdge edge;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.noteEdgeDrag;
}

/// 练习片段端点截取的目标身份（端点沿用模块既有词汇 [IntervalEdge]）。
final class ClipTrimDragTarget extends TrackBandDragTarget {
  const ClipTrimDragTarget(this.index, this.edge);

  /// 片段下标。
  @override
  final int index;

  /// 被拖端点。
  final IntervalEdge edge;

  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.practiceClipTrim;
}

/// 预览线拖动（第九族）的目标身份：无下标（命中解析不产出下标，接管由带侧
/// 声明的准入裁决）。
final class PreviewLineDragTarget extends TrackBandDragTarget {
  const PreviewLineDragTarget();

  /// 预览线拖动无下标：声明钩子不读本值。
  @override
  int get index => -1;

  /// 模块门禁表里本目标显式空清单（seek 语义，无门），如实取既有词汇。
  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.previewLineDrag;
}

/// 学习段圈选（第十族）的目标身份：承载落点解析出的起始段序（命中解析留在
/// 带侧，这里只承载其结果）。
final class LearningSpanDragTarget extends TrackBandDragTarget {
  const LearningSpanDragTarget(this.order);

  /// 起手段序。
  final int order;

  /// 段序即本族承载的下标。
  @override
  int get index => order;

  /// 模块门禁表里本目标显式空清单（学习段轨点选与激活同一族词汇），如实
  /// 取既有词汇。
  @override
  AnnotationGestureTarget get gateTarget =>
      AnnotationGestureTarget.learningTrackTap;
}

/// 一族拖动的全部差异。
///
/// 逐帧出口两支（见库头「两支帧事务」）：**模块事务族**声明 [toTime] 与
/// [beginSession]（[readGrabOffsetMs] 与 [onFrame] 可选），**自家帧族**声明
/// [beginFrame]；[toTime]/[beginSession] 都留空而无 [beginFrame] 的第三种是
/// 预览线拖动——没有模块事务、请求即落点。
class TrackBandDragDeclaration {
  const TrackBandDragDeclaration({
    this.toTime,
    this.beginSession,
    this.beginFrame,
    this.promptOnGateReject = false,
    this.yieldOnMixedBurst = false,
    this.respectLoadGate = true,
    this.freezeOnPinch = true,
    this.admit,
    this.readGrabOffsetMs,
    this.onBegin,
    this.onFrame,
    this.onEnd,
  }) : assert(
         toTime != null || beginFrame != null,
         '一族要么有换算（横向族）、要么有自家帧（二维落点族）',
       ),
       assert(
         beginFrame == null || beginSession == null,
         '自家帧族不经模块拖动会话：两支帧事务二选一',
       );

  /// 带内局部 x → 请求时间（逐族装配：轴来源不同）。[bandWidth] 是本次起手
  /// 读到的同一带宽，钳制口径与换算因此同源；几何不可用（时长/窗口未知）
  /// 返回空，逐帧据此成为空操作。自家帧族不声明它（逐帧读二维落点）。
  final Duration? Function(double localX, double bandWidth)? toTime;

  /// 模块会话工厂（起手判定全部通过后才调用）。**留空 = 本族没有模块事务**
  /// （预览线拖动：seek 不经标注编辑模块），此时请求即落点。
  final DurationDragSession Function(TrackBandDragTarget target)? beginSession;

  /// 自家帧族的帧工厂（学习段圈选）：逐帧与提交、取消两条收口都由它解释。
  /// 返回空 = 这次起手不成立（不建句柄、不起手钩子）。与 [beginSession]
  /// 二选一。
  final TrackBandDragFrame? Function(TrackBandDragTarget target)? beginFrame;

  /// 被门禁拒绝时弹不弹一次提示（分段线与首尾端标为真，其余静默）。
  final bool promptOnGateReject;

  /// 起手是否让位给混区 burst（练习片段截取族与学习段圈选族为真，其余族
  /// 无此判定）。
  final bool yieldOnMixedBurst;

  /// 起手是否受「装载未完成」门约束（八族为真：写盘入口在装载落定前一律不
  /// 参与；预览线拖动为假——seek 不是写盘入口，起从不读这道门）。
  final bool respectLoadGate;

  /// 双指在场时逐帧是否由域冻结（八族与预览线拖动为真：让位、不驱动画面；
  /// 学习段圈选为假——它半途加入即回滚取消，这条既有差异由族自己的帧回答）。
  final bool freezeOnPinch;

  /// 准入形状（越界 / 内容锁 / 落点是否在命中列内 / 无）：空 = 不预检。
  /// [localX] 是本次起手的带内局部 x（落点类准入读它，索引类准入不读）。
  final bool Function(TrackBandDragTarget target, double localX)? admit;

  /// 起手边界读取与抓取偏移（返回 null = 放弃本次起手；空 = 不记偏移、
  /// 请求即手指时间）。
  final int? Function(TrackBandDragTarget target, Duration finger)?
  readGrabOffsetMs;

  /// 起手视觉钩子。
  final void Function(TrackBandDragTarget target)? onBegin;

  /// 逐帧落点钩子（仅写后真实落点非空时触发一次）。
  final void Function(Duration landing)? onFrame;

  /// 收口视觉钩子（提交路径与取消路径都会走到）。
  final void Function()? onEnd;
}

/// 一族拖动的**自家帧**（域内形状）：不经标注编辑模块拖动会话的族把逐帧与
/// 两条收口交给它。三件事各一条注入闭包——本域不知道学习段、选中集合与窗口，
/// 只借它的生命周期与单槽世代。
///
/// 落点由族自己解释（学习段圈选 = 选中段集合），故 [moveTo] 不交回落点；
/// 「已圈到头、贴边平移不可能再改变落点」这条事实由族在自己的贴边平移驱动
/// 闭包里回答（见带侧装配）。
class TrackBandDragFrame {
  const TrackBandDragFrame({
    required this.moveTo,
    required this.end,
    required this.cancel,
  });

  /// 逐帧：带内局部落点（二维——段的命中按行归属解析，纵坐标参与判定）。
  final void Function(Offset local) moveTo;

  /// 提交路径（松手）。
  final void Function() end;

  /// 取消路径（系统打断 / 被别的识别器抢走）：回到起手前。
  final void Function() cancel;
}

/// 按族注册入口：外部装配方**逐族**提交该族的声明条目，域据此分派起手。
///
/// 注册表按门禁目标成唯一键：[register] 同一族第二次登记即覆盖第一次；没登记
/// 过的门禁目标 [declarationFor] 取回空，对应的目标身份起手为空。
class TrackBandDragFamilies {
  final Map<AnnotationGestureTarget, TrackBandDragDeclaration> _byGate =
      <AnnotationGestureTarget, TrackBandDragDeclaration>{};

  /// 登记一族：门禁目标 + 该族的声明条目。同一门禁目标重复登记时后者生效。
  void register(
    AnnotationGestureTarget gate,
    TrackBandDragDeclaration declaration,
  ) {
    _byGate[gate] = declaration;
  }

  /// 该族的声明（未登记 = 空）。
  TrackBandDragDeclaration? declarationFor(AnnotationGestureTarget gate) =>
      _byGate[gate];

  /// 已登记的门禁目标（按登记次序）。
  Iterable<AnnotationGestureTarget> get gates => _byGate.keys;
}

/// 带内拖动手势域：跨帧状态只有单槽与世代。
class TrackBandDragSession {
  TrackBandDragSession({
    required this.families,
    required this.isPinchActive,
    required this.isMixedBurstActive,
    required this.loadGateActive,
    required this.gestureStartRejected,
    required this.promptOnReject,
    required this.bandWidth,
  });

  /// 已登记的族：门禁目标 → 该族声明（注册入口见 [TrackBandDragFamilies]）。
  final TrackBandDragFamilies families;

  /// 双指在场（让位）读取。
  final bool Function() isPinchActive;

  /// 混区 burst 在场读取（让位；仅声明了 `yieldOnMixedBurst` 的
  /// 练习片段截取族参与判定）。
  final bool Function() isMixedBurstActive;

  /// 装载未完成门读取。
  final bool Function() loadGateActive;

  /// 起手纯读门禁判定（按模块门禁表）。
  final bool Function(AnnotationGestureTarget target) gestureStartRejected;

  /// 被拒时的提示（逐族声明是否触发）。
  final void Function(AnnotationGestureTarget target) promptOnReject;

  /// 带宽读取（几何不可用 = 空）。
  final double? Function() bandWidth;

  /// 每次起手递增；句柄携带快照。
  int _generation = 0;

  /// 单会话槽（null = 无拖动在跑）。
  TrackBandDragHandle? _slot;

  /// 当前会话句柄（无 = null）。带侧据此驱动逐帧与收口——「同一时刻只有
  /// 一个拖动在跑」因此是结构事实。
  TrackBandDragHandle? get activeHandle => _slot;

  /// 起手：门序言依次「双指在场让位 → 混区 burst 让位（逐族声明）→ 装载门
  /// → 门禁表 → 准入 → 边界读取与抓取偏移 → 帧事务（模块会话或自家帧）→
  /// 起手钩子」。任一步拒绝即空返回且不留痕。
  ///
  /// 目标身份的门禁目标没有登记过对应声明时同样空返回：族不在注册表内 =
  /// 本装配没接这条手势，不是接线错误。
  TrackBandDragHandle? begin(TrackBandDragTarget target, double localX) {
    if (isPinchActive()) return null;
    final declaration = families.declarationFor(target.gateTarget);
    if (declaration == null) return null;
    if (declaration.yieldOnMixedBurst && isMixedBurstActive()) return null;
    if (declaration.respectLoadGate && loadGateActive()) return null;
    if (gestureStartRejected(target.gateTarget)) {
      if (declaration.promptOnGateReject) promptOnReject(target.gateTarget);
      return null;
    }
    final admit = declaration.admit;
    if (admit != null && !admit(target, localX)) return null;
    var grabOffsetMs = 0;
    final readGrabOffsetMs = declaration.readGrabOffsetMs;
    if (readGrabOffsetMs != null) {
      final finger = _requestTime(declaration, localX);
      if (finger == null) return null;
      final offset = readGrabOffsetMs(target, finger);
      if (offset == null) return null;
      grabOffsetMs = offset;
    }
    // 两支帧事务二选一：自家帧族的工厂返回空 = 本次起手不成立（如只读拒绝）；
    // 模块事务族建会话；两者都不声明 = 本族没有模块事务（请求即落点）。
    final beginFrame = declaration.beginFrame;
    final TrackBandDragFrame? frame;
    final DurationDragSession? session;
    if (beginFrame != null) {
      frame = beginFrame(target);
      if (frame == null) return null;
      session = null;
    } else {
      frame = null;
      session = declaration.beginSession?.call(target);
    }
    final handle = TrackBandDragHandle._(
      this,
      declaration,
      target,
      session,
      frame,
      ++_generation,
      grabOffsetMs,
    );
    _slot = handle;
    declaration.onBegin?.call(target);
    return handle;
  }

  /// 带内局部 x → 请求时间：带宽不可用（几何缺失）即空；横向钳制在此唯一
  /// 实现（横向族一律钳到 [0, 带宽]）。
  Duration? _requestTime(TrackBandDragDeclaration declaration, double localX) {
    final width = bandWidth();
    if (width == null) return null;
    final toTime = declaration.toTime;
    if (toTime == null) return null;
    return toTime(localX.clamp(0.0, width).toDouble(), width);
  }

  /// [handle] 是否仍是单槽里的当前会话（陈旧句柄的守卫）。
  bool _isCurrent(TrackBandDragHandle handle) =>
      identical(_slot, handle) && handle._generation == _generation;
}

/// 带世代的拖动句柄：逐帧与收口只经它发生。
class TrackBandDragHandle {
  TrackBandDragHandle._(
    this._owner,
    this._declaration,
    this._target,
    this._session,
    this._frame,
    this._generation,
    this._grabOffsetMs,
  );

  final TrackBandDragSession _owner;
  final TrackBandDragDeclaration _declaration;
  final TrackBandDragTarget _target;
  final DurationDragSession? _session;
  final TrackBandDragFrame? _frame;
  final int _generation;
  final int _grabOffsetMs;

  /// 本族的目标身份：带侧据此回答「跑的是哪一族」（如窗口自管的判据），
  /// 不另立第二份「谁在拖」的布尔簿记。
  TrackBandDragTarget get target => _target;

  /// 逐帧（横向族）：带内局部 x 经声明换算（按本族钳制口径）后提交帧事务；
  /// 写后真实落点非空时触发一次落点钩子并原样交回，无净变化、句柄陈旧、
  /// 双指在场或几何不可用时返回空且不驱动任何画面。
  ///
  /// 自家帧族读二维落点，用 [moveToPoint]；经本入口调用时纵坐标记 0。
  Duration? moveTo(double localX) {
    if (_frame != null) {
      moveToPoint(Offset(localX, 0));
      return null;
    }
    if (!_owner._isCurrent(this)) return null;
    if (_declaration.freezeOnPinch && _owner.isPinchActive()) return null;
    final request = _owner._requestTime(_declaration, localX);
    if (request == null) return null;
    final to = _grabOffsetMs == 0
        ? request
        : Duration(milliseconds: request.inMilliseconds - _grabOffsetMs);
    // 没有模块事务的族（预览线拖动）：请求即落点，落点钩子照常触发一次。
    final session = _session;
    final landing = session == null ? to : session.moveTo(to);
    if (landing == null) return null;
    _declaration.onFrame?.call(landing);
    return landing;
  }

  /// 逐帧（二维落点族）：交带内局部落点给自家帧（命中按行归属解析，纵坐标
  /// 参与判定）。句柄陈旧或双指在场时为空操作；横向族的落点是 x，不经本入口。
  void moveToPoint(Offset local) {
    if (!_owner._isCurrent(this)) return;
    final frame = _frame;
    if (frame != null) {
      // 自家帧族自己回答双指在场语义（冻结或回滚取消，逐族声明）。
      if (_declaration.freezeOnPinch && _owner.isPinchActive()) return;
      frame.moveTo(local);
      return;
    }
    if (_owner.isPinchActive()) return;
    moveTo(local.dx);
  }

  /// 收口（提交路径，幂等）：先收帧事务，再触发收口视觉钩子；陈旧句柄为
  /// 空操作。
  void end() => _close(commit: true);

  /// 取消路径（幂等）：自家帧族走它自己的取消（回到起手前）；模块事务族今天
  /// 只有一条收口路径，取消与收口同路。陈旧句柄为空操作。
  void cancel() => _close(commit: false);

  void _close({required bool commit}) {
    if (!_owner._isCurrent(this)) return;
    _owner._slot = null;
    final frame = _frame;
    if (frame != null) {
      if (commit) {
        frame.end();
      } else {
        frame.cancel();
      }
    } else {
      _session?.end();
    }
    _declaration.onEnd?.call();
  }
}
