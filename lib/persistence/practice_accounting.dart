/// 练习记账门：「这一刻算不算
/// 练习」的单一来源——播放语境枚举 + 逐值判定表 + 事实求值。
///
/// **三个概念面**：
/// ① 语境——[PracticeContext]，覆盖声明表的全部行；
/// ② 判定表——[practiceVerdictOf]，穷尽 switch 是唯一声明处，每行给出
///    [PracticeVerdict]（计/不计 + 依据）；
/// ③ 事实求值——[PracticeAccountingFacts] + [evaluatePracticeAccounting]，
///    由既有 owner 交出的四个事实推出这一刻的判定。
///
/// **判定表**（逐位固化今天的
/// 实际行为）：
///
/// | 语境 | 判定 | 依据 |
/// | --- | --- | --- |
/// | 在播：观看态 / 编辑态 / 八拍矫正待命态 / 对比-播放态 / 对比-控制层 / 取景调节态 / 三指跳转 / 学习段选中跳段与循环跳回 / 轨道带区间内拖动 / 片段端点截取拖动 / 音量亮度镜像与方向锁 / 录制中真实跟跳 | 计 | 引擎在播 |
/// | 练习片段回看在飞 | 不计 | 事实：激活非空 ∧ 片段可解析 |
/// | 录制准备期（前导回退） | 不计 | 事实：相位 = preparing |
/// | 延迟预备播放期 | 不计 | 事实：相位 = preparing |
/// | 音画同步校准会话 / 播到尾循环提示倒计时 / 备注编辑 / 帧步进 / 全屏拖动 scrub / 标注拖线预览 / 轨道带拖动越出有效区间 | 不计 | 引擎不在播（暂停或未起播） |
/// | 打开与换视频的解析窗口 | 不计 | 标识未定 |
/// | 练习侧第二引擎单独播放 | 不计 | 不在口径内（只订阅源引擎） |
///
/// **事实面最小**：只有三个语境需要专属事实——练习片段回看在飞（激活非空
/// ∧ 片段可解析，即今天的在飞语义）、录制准备期与延迟预备播放期（两者皆是
/// 相位 = preparing）；其余语境一律由「引擎在播」决定。解析窗口由
/// [PracticeAccountingFacts.videoIdentified]
/// 覆盖——它复用「videoId 解析出即已定」这一既有输入，不是新立的 owner；
/// 未定即窗口内。
///
/// **穷尽性护栏**：[PracticeContext] 加取值 ⇒ 本文件穷尽 switch 编译报错；
/// 声明表缺行 ⇒ 直测的结构断言（表行数 == 枚举取值数）失败。
///
/// 本模块零框架依赖（不引 Flutter、不引 Riverpod、不读任何 provider），
/// 取值只由入参决定，可在不启动 widget 环境的情况下直测。
library;

/// 播放语境：声明表的全部行（加一种语境 = 这里加一个取值 + 判定表加一行）。
enum PracticeContext {
  /// 观看态在播。
  watchPlaying,

  /// 编辑态在播。
  editPlaying,

  /// 八拍矫正待命态。
  eightBeatStandby,

  /// 对比-播放态。
  comparePlayback,

  /// 对比-控制层。
  compareControlLayer,

  /// 取景调节态。
  framingAdjust,

  /// 三指跳转。
  threeFingerJump,

  /// 学习段选中跳段。
  segmentSelectionJump,

  /// 学习段循环跳回。
  segmentLoopJumpBack,

  /// 轨道带区间内拖动（仍在播 ⇒ 照常计入）。
  trackBandInRangeDrag,

  /// 片段端点截取拖动。
  clipEndpointTrimDrag,

  /// 音量、亮度、镜像与方向锁调节。
  volumeBrightnessMirrorDirectionLock,

  /// 录制中真实跟跳。
  recordingLiveFollow,

  /// 练习片段回看在飞（激活非空 ∧ 片段可解析）。
  clipReviewInFlight,

  /// 录制准备期（前导回退，相位 = preparing）。
  recordingPreparing,

  /// 音画同步校准会话。
  avSyncCalibration,

  /// 延迟预备播放期（预备连续播，相位 = preparing）。
  delayedPlayPreparing,

  /// 播到尾循环提示倒计时。
  endLoopPromptCountdown,

  /// 备注编辑。
  noteEditing,

  /// 帧步进。
  frameStepping,

  /// 全屏拖动 scrub（在播时先暂停，引擎不在播）。
  fullscreenScrub,

  /// 标注拖线预览。
  annotationLineDragPreview,

  /// 轨道带拖动越出有效区间。
  trackBandDragOutOfRange,

  /// 打开与换视频的解析窗口。
  videoParsingWindow,

  /// 练习侧第二引擎（片段回放件）单独播放。
  secondEngineSoloPlayback,
}

/// 判定依据（每行带一句依据）。
enum PracticeBasis {
  /// 引擎在播。
  enginePlaying('引擎在播'),

  /// 事实：激活非空 ∧ 片段可解析。
  clipReviewInFlightFact('事实：激活非空 ∧ 片段可解析'),

  /// 事实：相位 = preparing（录制准备期与延迟预备播放期共用）。
  preparingPhaseFact('事实：相位 = preparing'),

  /// 引擎不在播（暂停或未起播）。
  engineNotPlaying('引擎不在播'),

  /// 标识未定（打开与换视频的解析窗口）。
  identityUnresolved('标识未定'),

  /// 不在口径内（只订阅源引擎）。
  outOfScope('不在口径内');

  const PracticeBasis(this.label);

  /// 这条依据的一句话表述。
  final String label;
}

/// 判定表对某一次询问给出的完整答案：计/不计 + 依据。
class PracticeVerdict {
  const PracticeVerdict._(this.counted, this.basis);

  static const countedIn = _countedIn;

  /// 这一瞬的播放算不算练习。
  final bool counted;

  final PracticeBasis basis;

  /// 这条依据的一句话表述。
  String get rationale => basis.label;

  @override
  bool operator ==(Object other) =>
      other is PracticeVerdict &&
      other.counted == counted &&
      other.basis == basis;

  @override
  int get hashCode => Object.hash(counted, basis);

  @override
  String toString() => '${counted ? '计' : '不计'}（${basis.label}）';
}

/// 判定行常量：声明表与事实求值共用同一组行，依据与判值只写一处。
const _countedIn = PracticeVerdict._(true, PracticeBasis.enginePlaying);
const _notCountedByClipReview = PracticeVerdict._(
  false,
  PracticeBasis.clipReviewInFlightFact,
);
const _notCountedByPreparing = PracticeVerdict._(
  false,
  PracticeBasis.preparingPhaseFact,
);
const _notCountedByNotPlaying = PracticeVerdict._(
  false,
  PracticeBasis.engineNotPlaying,
);
const _notCountedByIdentity = PracticeVerdict._(
  false,
  PracticeBasis.identityUnresolved,
);

/// 判定表：语境 → 判定（穷尽 switch 是唯一声明处；加枚举取值即编译报错）。
PracticeVerdict practiceVerdictOf(PracticeContext context) => switch (context) {
      // 计：引擎在播的各类语境。
      PracticeContext.watchPlaying ||
      PracticeContext.editPlaying ||
      PracticeContext.eightBeatStandby ||
      PracticeContext.comparePlayback ||
      PracticeContext.compareControlLayer ||
      PracticeContext.framingAdjust ||
      PracticeContext.threeFingerJump ||
      PracticeContext.segmentSelectionJump ||
      PracticeContext.segmentLoopJumpBack ||
      PracticeContext.trackBandInRangeDrag ||
      PracticeContext.clipEndpointTrimDrag ||
      PracticeContext.volumeBrightnessMirrorDirectionLock ||
      PracticeContext.recordingLiveFollow => _countedIn,

      // 不计：三个专属事实。
      PracticeContext.clipReviewInFlight => _notCountedByClipReview,
      PracticeContext.recordingPreparing => _notCountedByPreparing,
      PracticeContext.delayedPlayPreparing => _notCountedByPreparing,

      // 不计：引擎不在播（暂停或未起播）。
      PracticeContext.avSyncCalibration ||
      PracticeContext.endLoopPromptCountdown ||
      PracticeContext.noteEditing ||
      PracticeContext.frameStepping ||
      PracticeContext.fullscreenScrub ||
      PracticeContext.annotationLineDragPreview ||
      PracticeContext.trackBandDragOutOfRange => _notCountedByNotPlaying,

      // 不计：标识未定。
      PracticeContext.videoParsingWindow => _notCountedByIdentity,

      // 不计：不在口径内（只订阅源引擎）。
      PracticeContext.secondEngineSoloPlayback => const PracticeVerdict._(
          false,
          PracticeBasis.outOfScope,
        ),
    };

/// 事实面：判定值由既有 owner 交出的四个事实推出。
class PracticeAccountingFacts {
  const PracticeAccountingFacts({
    this.enginePlaying = false,
    this.clipReviewInFlight = false,
    this.recordingPreparing = false,
    this.delayedPlayPreparing = false,
    this.videoIdentified = true,
  });

  /// 引擎播放态（isPlaying）。
  final bool enginePlaying;

  /// 练习片段回看在飞：激活非空 ∧ 片段可解析（即今天的在飞语义；悬空
  /// 激活不构成此事实 ⇒ 保持「计入」的今天口径）。
  final bool clipReviewInFlight;

  /// 录制准备期：相位 = preparing（前导回退）。
  final bool recordingPreparing;

  /// 延迟预备播放期：相位 = preparing（预备连续播、尚未越过起点；
  /// ——预备期不计，越过起点后照常按观看态计入）。
  final bool delayedPlayPreparing;

  /// 视频标识已定（解析窗口内为 false）。
  final bool videoIdentified;
}

/// 事实求值：这一刻算不算练习。按序取第一个成立的事实——标识未定压过
/// 专属事实与在播（播放不得算到上一支舞头上），回看在飞与两支预备期
/// （相位 = preparing）压过在播，其余一律由「引擎在播」决定。
PracticeVerdict evaluatePracticeAccounting(PracticeAccountingFacts facts) {
  if (!facts.videoIdentified) return _notCountedByIdentity;
  if (facts.clipReviewInFlight) return _notCountedByClipReview;
  if (facts.recordingPreparing) return _notCountedByPreparing;
  if (facts.delayedPlayPreparing) return _notCountedByPreparing;
  if (facts.enginePlaying) return _countedIn;
  return _notCountedByNotPlaying;
}
