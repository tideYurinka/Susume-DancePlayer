/// RecordingPlaybackTakeover：录制期播放接管域。
///
/// 「录制期间播放行为被接管」这条纪律的宿主。六个面都收在这里：播放态同步、
/// 录制期拒绝 scrub、录制期循环停用、录制态标记、学段循环同步、scrub 会话
/// 收尾。引擎/seek 域与对比录制域各自保持原样，单向依赖本域。
///
/// 接口只有两组：
/// - 接管事实 [active]：此刻是否处于接管期（**含准备期**）——引擎/seek 面
///   据此拒绝 scrub、位置跳转、延迟播放等播放类动作；
/// - 相位与动作入口：进入/退出的三个播放面纪律按固定次序施加与复位
///   （[engage] / [disengage]），起录前的 scrub 会话收尾
///   （[endScrubBeforeStart]）与接管期内的播放动作消费（[handlePlaybackToggle]）。
///
/// 素材入库、相位换算、seek 提交、逐帧拖动预览不属于本域；本件不持
/// provider、不读构建上下文、不认识两个原域的类型，全部经注入闭包触碰
/// （沿 ScrubSession / SeekSubmitter 先例）。
///
/// 依赖方向：**单向**——两个原域 → 本域，本域 → 无（零 import，闭包注入）。
library;

/// 录制期播放接管（会话域：无 widget）。
///
/// 进入次序（[engage]）：录制态标记 → 播放态同步（撤在途延迟起播）→ 录制期
/// 循环停用（仅录制本体）。退出次序（[disengage]）：录制态标记复位 → 学段
/// 循环同步（作用域复位）。退出幂等：未处于接管期时为 no-op，故复位不会
/// 施加第二遍。
class RecordingPlaybackTakeover {
  RecordingPlaybackTakeover({
    required void Function() disableRecordingLoop,
    required void Function() restoreLearningSegmentLoop,
    required void Function(bool active) setRecordingMarker,
    required Future<void> Function() endScrubSession,
    required void Function() interruptPendingDelayedPlay,
    required Future<void> Function() stopRecordingSession,
  }) : _disableLoop = disableRecordingLoop,
       _restoreLoopScope = restoreLearningSegmentLoop,
       _markRecording = setRecordingMarker,
       _endScrub = endScrubSession,
       _interruptDelayed = interruptPendingDelayedPlay,
       _stopRecording = stopRecordingSession;

  /// 录制期循环停用（录制本体；录到区间/物理尾由录制会话自己判，循环前导与
  /// 回跳不得插手）。准备期不动作。
  final void Function() _disableLoop;

  /// 学段循环同步复位（退出接管时只就位作用域，不跳段首、不起播）。
  final void Function() _restoreLoopScope;

  /// 录制态标记（循环提示的尾点语义在接管期内整体停用）。
  final void Function(bool active) _markRecording;

  /// scrub 会话收尾（起录之前）。
  final Future<void> Function() _endScrub;

  /// 播放态同步：撤掉「到点自己动播放态」的在途挂账（延迟播放）。
  final void Function() _interruptDelayed;

  /// 播放态同步：接管期内的播放动作转成的停录请求。
  final Future<void> Function() _stopRecording;

  bool _active = false;

  /// 接管期事实（含准备期）：引擎/seek 面据此拒绝 scrub 与其它播放类动作。
  bool get active => _active;

  /// 进入接管期（录制相位 = 准备期或录制中）。
  ///
  /// [suppressLoop] 仅在录制本体（已越过起录点）为真：准备期只落标记与收
  /// 挂账、不碰循环。可重入（准备 → 录制的相位推进再次调用）：标记与挂账
  /// 无害重写，循环停用幂等。
  void engage({required bool suppressLoop}) {
    _active = true;
    _markRecording(true);
    _interruptDelayed();
    if (suppressLoop) _disableLoop();
  }

  /// 退出接管期：三项各自复位。幂等（未处于接管期时 no-op），故重复调用不会
  /// 施加第二遍学段循环同步。
  void disengage() {
    if (!_active) return;
    _active = false;
    _markRecording(false);
    _restoreLoopScope();
  }

  /// scrub 会话收尾（接管的第一面）：起录按下即收掉**在途的定格预览**——
  /// 收口在录制会话起步之前，否则 scrub 的收尾会在起录之后回写播放态与位置。
  Future<void> endScrubBeforeStart() => _endScrub();

  /// 播放态同步：接管期内到达的播放动作（双击画面）转成**停录**，与录制钮
  /// 同一个动作（准备期 = 取消并丢弃已武装的那段、录制中 = 停录入库）。
  /// 返回 true = 已由接管消费。
  Future<bool> handlePlaybackToggle() async {
    if (!_active) return false;
    await _stopRecording();
    return true;
  }
}
