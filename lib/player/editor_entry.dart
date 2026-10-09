/// 编辑器入口编排域：播放页那套「进入编辑面」的
/// 编排——入口请求、入口门禁、画布准备、待办串联、收起与退出——收在本域。
///
/// ## 接口
///
/// - [requestEntry]：宿主自身发起的进入请求（单击画面）。门禁逐条：未挂载、
///   控制层已展开、装载未完成、录制接管期——任一成立即静默拦截、待办不落。
///   目标取值由当前模式决定：对比-播放态 → 对比-控制层，投屏-观看态 →
///   投屏-控制层（点画面展开回来，不重跑投屏准备），其余 → 编辑态。
/// - [orchestratePendingEntry]：待办槽的编排与提交。发起路径可多、提交点唯一
///   （[PlayerSessionModel.commit]）——校准会话互斥、录制接管互斥、相机授权门、
///   投屏准备门、画布准备都在这里；不成立则
///   [PlayerSessionModel.cancelPendingEntry]（模式值一位不动）。
/// - [collapse]：收起控制层（回观看态，或对比-控制层回对比-播放态）。
/// - [exitCompare]：退出对比态（回观看态）。
/// - [exitFraming]：退出取景调节态（对比取景回对比-控制层；单画面取景回
///   编辑态）。
///
/// ## 模式取值
///
/// 模式取值仍归其既有单一 owner [PlayerSessionModel]（`player_session` 小库）；
/// 本域只消费该 owner 的读面与写缝，不自持第二份模式值。模式取值上的判据逐条
/// 穷尽 switch（加取值即编译报错）；相机授权门与投屏准备门都直接读
/// owner 的进入前置声明表（[playerSessionEntryDeclarationTable]，
/// §决定2：进入前置是目标取值的属性）。异步门返回后的复查（页面是否仍在
/// 树上、待办是否仍在槽）是「失败零副作用」的实现。
///
/// ## 画布准备
///
/// 进入编辑面前以当前引擎时长兜底重建零时长时间线（标注工具依赖有效练习
/// 区间才可用），并清掉两类内容类浮层的排他选中——两者都由本域单向驱动，
/// 宿主只交出读取闭包与执行回调。
///
/// ## 依赖方向（单向）
///
/// 本域 → [PlayerSessionModel] 与 [AnnotationTimeline]（值类型）；其余跨域事实
/// （装载门、录制接管、校准会话、相机授权门、投屏准备门、引擎时长、画布与
/// 选中）全部经构造注入的显式闭包取得。本域不 import 播放页、不 import 中枢、
/// 不读构建上下文、不注容器，可在无 ProviderScope 下直测。反向依赖不存在。
library;

import '../annotation/annotation_timeline.dart';
import '../player_session/player_session.dart';

/// 编辑器入口编排域（会话域：无 widget）。
class EditorEntry {
  EditorEntry({
    required this._session,
    required this._readSession,
    required this._blocksWrite,
    required this._takenOver,
    required this._avSyncActive,
    required this._requestCameraPermission,
    required this._prepareCast,
    required this._readTimeline,
    required this._readVideoDuration,
    required this._resetTimeline,
    required this._clearExclusiveSelections,
    required this._isMounted,
  });

  /// 模式取值 owner（唯一写缝）。
  final PlayerSessionModel _session;

  /// 模式取值读面（owner 的当前值）。
  final PlayerSession Function() _readSession;

  /// 装载未完成门：会写盘入口此刻是否被挡下（挡下时宿主已弹提示）。
  final bool Function() _blocksWrite;

  /// 录制接管期事实（取自「录制期播放接管」域）。
  final bool Function() _takenOver;

  /// 音画同步校准会话是否进行中（对比类进入与之互斥）。
  final bool Function() _avSyncActive;

  /// 进入对比态前的相机授权门（编排在相机与练习面域）。
  final Future<bool> Function() _requestCameraPermission;

  /// 进入投屏态前的**投屏准备**门（准备面板 + 起投的编排在播放页）：
  /// 返回 true = 已经投上了（或本就在投），可以提交进入投屏-控制层。
  final Future<bool> Function() _prepareCast;

  /// 当前标注时间线（画布兜底读它的有效时长）。
  final AnnotationTimeline Function() _readTimeline;

  /// 引擎当前时长（时间线零时长时的兜底来源）。
  final Duration? Function() _readVideoDuration;

  /// 以给定时长重建整片时间线（标注编辑模块的复位写缝）。
  final void Function(Duration duration) _resetTimeline;

  /// 清掉两类内容类浮层的排他选中（浮层装配域的交出写缝）。
  final void Function() _clearExclusiveSelections;

  /// 页面仍在树上。
  final bool Function() _isMounted;

  /// 宿主自身发起一次进入请求（单击画面）：门禁不过即静默拦截、待办不落。
  void requestEntry() {
    if (!_isMounted() || _readSession().controlOpen) return;
    if (_blocksWrite()) return;
    if (_takenOver()) return;
    _session.requestEntry(_entryTargetFor(_readSession().mode));
  }

  /// 待办编排与唯一提交：门禁通过后补齐画布准备，经唯一提交入口提交；不成立
  /// 则取消待办（模式值一位不动）。
  Future<void> orchestratePendingEntry() async {
    if (!_isMounted()) return;
    if (_readSession().pendingEntry == null) return;
    final target = _readSession().pendingEntry?.target;
    // 与音画同步校准会话互斥与录制期互斥：
    // 命中即取消待办、失败零副作用。
    if ((_avSyncActive() && _conflictsWithAvSync(target)) ||
        (_takenOver() && _conflictsWithRecording(target))) {
      _session.cancelPendingEntry();
      return;
    }
    // 相机授权门：目标取值的进入前置（声明表 cameraPermission）——拒绝不进入、
    // 零副作用。已在对比态内的展开跃迁不重问。
    if (_needsCameraGate(target)) {
      final granted = await _requestCameraPermission();
      if (!_isMounted()) return;
      if (_readSession().pendingEntry == null) return;
      if (!granted) {
        _session.cancelPendingEntry();
        return;
      }
    }
    // 投屏准备门：目标取值的进入前置（声明表 castPreparation）——准备面板
    // 与起投的编排在宿主；取消或起投失败不进入、零副作用。已在投屏内的
    // 展开跃迁（投屏-观看态 → 投屏-控制层）由宿主直接放行、不重跑准备。
    if (_needsCastPrep(target)) {
      final ready = await _prepareCast();
      if (!_isMounted()) return;
      if (_readSession().pendingEntry == null) return;
      if (!ready) {
        _session.cancelPendingEntry();
        return;
      }
    }
    if (!_isMounted()) return;
    if (_readSession().pendingEntry == null) return;
    _prepareCanvas();
    _session.commit();
  }

  /// 收起控制层：经模式值回观看态（对比-控制层则回对比-播放态）；未展开或
  /// 页面已卸载为幂等 no-op。
  void collapse() {
    if (!_isMounted() || !_readSession().controlOpen) return;
    _session.collapse();
  }

  /// 退出对比态回观看态；非对比态为幂等 no-op。
  void exitCompare() => _session.exitCompare();

  /// 退出取景调节态（退出三同路按所在路径分支）：
  /// 对比取景回对比-控制层；单画面取景回编辑态。
  void exitFraming() => _session.enter(
    _readSession().mode == PlayerSessionMode.compareFraming
        ? PlayerSessionMode.compareEditing
        : PlayerSessionMode.editing,
  );

  /// 进入编辑面前的画布准备：零时长时间线以引擎时长兜底重建，并清掉浮层的
  /// 排他选中（浮层选中态是播放态子状态，控制层展开时浮层不抢标注手势）。
  void _prepareCanvas() {
    final timeline = _readTimeline();
    final duration = _readVideoDuration();
    if (timeline.videoDuration <= Duration.zero && duration != null) {
      _resetTimeline(duration);
    }
    _clearExclusiveSelections();
  }

  /// 单击画面的进入目标（穷尽 switch：加取值即编译报错）。
  ///
  /// 投屏-观看态 → 投屏-控制层：点画面把控制层展开回来（投屏期手势语义
  /// 不变），**不重跑投屏准备**（已在投屏内）。投屏-控制层走不到这里
  /// （[requestEntry] 先按控制层已展开拦下），保底取自身 = 幂等。
  PlayerSessionMode _entryTargetFor(PlayerSessionMode mode) => switch (mode) {
    PlayerSessionMode.compareWatching => PlayerSessionMode.compareEditing,
    PlayerSessionMode.castWatching => PlayerSessionMode.castControl,
    PlayerSessionMode.watching ||
    PlayerSessionMode.editing ||
    PlayerSessionMode.beatCorrectionStandby ||
    PlayerSessionMode.segmentDensityStandby ||
    PlayerSessionMode.compareEditing ||
    PlayerSessionMode.compareFraming ||
    PlayerSessionMode.framing ||
    PlayerSessionMode.castControl => PlayerSessionMode.editing,
  };

  /// 相机授权前置取自 owner 的进入声明表（逐值一行，加取值只改表一处）。
  bool _needsCameraGate(PlayerSessionMode? target) =>
      target != null &&
      playerSessionEntryDeclarationTable[target]?.requirement ==
          PlayerSessionEntryRequirement.cameraPermission;

  /// 投屏准备前置同样取自进入声明表（与相机授权同一口径）。
  bool _needsCastPrep(PlayerSessionMode? target) =>
      target != null &&
      playerSessionEntryDeclarationTable[target]?.requirement ==
          PlayerSessionEntryRequirement.castPreparation;

  /// 音画同步校准会话与之互斥的进入目标（穷尽 switch；null = 无待办，不冲突）。
  ///
  /// 投屏与之互斥：校准在**本机内核**上量音画偏移，投屏把播放挪到电视上，
  /// 两者同时进行互相打脸——进入投屏时的静默拒绝即这一条。
  bool _conflictsWithAvSync(PlayerSessionMode? target) => switch (target) {
    PlayerSessionMode.compareWatching ||
    PlayerSessionMode.compareEditing ||
    PlayerSessionMode.castControl => true,
    PlayerSessionMode.watching ||
    PlayerSessionMode.editing ||
    PlayerSessionMode.beatCorrectionStandby ||
    PlayerSessionMode.segmentDensityStandby ||
    PlayerSessionMode.compareFraming ||
    PlayerSessionMode.framing ||
    PlayerSessionMode.castWatching ||
    null => false,
  };

  /// 录制接管期拒绝的进入目标（穷尽 switch；null = 无待办，不冲突）。
  ///
  /// 录制期进投屏同样拒绝：录制与投屏是两条互相冲突的播放接管。
  /// 投屏-观看态不在此列——它由收起而来、不经本编排，且录制期不会处在
  /// 投屏态内。
  bool _conflictsWithRecording(PlayerSessionMode? target) => switch (target) {
    PlayerSessionMode.compareEditing ||
    PlayerSessionMode.compareFraming ||
    PlayerSessionMode.framing ||
    PlayerSessionMode.castControl => true,
    PlayerSessionMode.watching ||
    PlayerSessionMode.editing ||
    PlayerSessionMode.beatCorrectionStandby ||
    PlayerSessionMode.segmentDensityStandby ||
    PlayerSessionMode.compareWatching ||
    PlayerSessionMode.castWatching ||
    null => false,
  };
}
