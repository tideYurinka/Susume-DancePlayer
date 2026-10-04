/// 节拍呈现：这一簇唯一的对外
/// 对象——接口只有 `attach` / `detach` / `onFrame(节拍上下文, 媒介位置)`
/// 三个方法与一个当前拍读出。位置与上下文同走 `onFrame` 一条入口，求值经
/// core 纯层 [evaluateCurrentBeat]（屏幕与声音同读的一次求值），发布值是
/// 自足的值：数拍 + 动画状态（八拍窗口相位、强拍边界、用户半拍线投影）。
/// 屏幕消费方只读本值，不读网格 / 相位 / 半拍线 / 位置 / 锚。
///
/// 发声排程在本对象内：当下 =
/// 最近一次报位 + 单调钟外推（任何报位直接覆盖，含向后；暂停冻结）；热
/// 路径只保留一个「已交给原生到哪个媒介时刻」的水位、整拍与半拍各一条只
/// 进不退的拍光标，以及一个左闭右开前瞻窗（拍点窗见 [_BeatScanWindow]）；
/// 位置跳变（前跳越过已排区、后跳越过前瞻窗）由对象自判——清原生未消费
/// 并把水位与拍光标一并归位。校准会话与正式数拍走**同一条求值**
/// （`lib/beat/CONTEXT.md`「节拍呈现」）：换的只是间隔（档间隔的
/// 均匀网格）与「现在」的锚（会话进入时刻、速率 1）——数拍锚点链、重音与
/// 小节口径与正式播放同一套，会话拍点即档间隔的整倍数。
///
/// 本外推是全仓**唯一**的「现在」：它同时回答
/// 「排哪一拍」与「告诉原生锚在哪」——下推原生的是
/// `(媒介时刻, 倍速, 播放态)` 配对（`MediaClockSync`），配对的另一半
/// （原生自己的帧位）由原生现取；「只进不退」由水位与拍光标承担，渲染器
/// 不做任何时间估计。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import '../annotation/annotation_timeline.dart' show AnnotationTimeline;
import '../core/playback/av_sync_math.dart' show avSyncTickTriggerShiftMedia;
import '../core/playback/playback_engine.dart' show PlaybackEngine;
import '../core/beat_grid.dart'
    show BeatGrid, BeatGridReads, UniformBeatGrid, kBeatsPerEightCount;
import '../core/current_beat.dart'
    show CurrentBeat, evaluateBeatCountAnchor, evaluateCurrentBeat;
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../core/playback/media_clock.dart' show MediaClockSync;
import 'beat_animation.dart'
    show BeatPresentationValue, deriveBeatPhase, projectUserHalfBeatLines;
import 'beat_audio_log.dart' show beatAudioLog;
import 'beat_schedule.dart'
    show
        BeatAudioRendererLifecycle,
        BeatScheduleCommand,
        BeatScheduleConsumer,
        BeatStreamControl,
        kMetronomeLookaheadWindow;
import 'calibration_session_grid.dart'
    show CalibrationSessionBpmTier, CalibrationSessionGrid;
import 'metronome_source_registry.dart'
    show
        MetronomeSegmentSlot,
        MetronomeSourceEntry,
        metronomeSegmentIdOf,
        metronomeSourceEntryOfId,
        selectMetronomeSlot,
        selectMetronomeSpeedGroupIndex;
import 'segment_jump.dart' show segmentLinePositions;

/// 周期 tick 的周期（30ms 沿用既有取值）。
const Duration kBeatPresentationTopUpPeriod = Duration(milliseconds: 30);

/// 周期时机开流失败后的重试冷却（毫秒；应活边沿不受冷却约束）。
const int kStreamRetryCooldownMs = 1000;

/// 同一个应活轮次内重建原生流对象的次数上限（超限先在同流上重试，等下一
/// 个应活边沿开新的一轮）。
const int kTransportResetLimitPerRound = 3;

/// 拍光标空位哨兵（拍点媒介时刻恒 ≥ 0）。
const int _noBeatEmitted = -1;

/// 节拍上下文：宿主一处构造的不可变值，每帧传入。
/// 上下文是产品状态的唯一入口——任一字段变化即下一次 [BeatPresentation.onFrame]
/// 生效，不需要通知、不需要信号。
class BeatPresentationContext {
  const BeatPresentationContext({
    required this.grid,
    required this.phase,
    required this.segmentLines,
    required this.firstLine,
    this.recordingAnchor,
    this.delayAnchor,
    this.activeAnchor,
    required this.source,
    required this.slotVolumeOf,
    required this.halfBeatLines,
    required this.halfBeatEnabled,
    required this.avSyncDelayMs,
    required this.rate,
    required this.playing,
    required this.soundEnabled,
    required this.gridError,
    required this.sessionActive,
    this.sessionBeatInterval,
  });

  /// 节拍网格（所有消费方读同一网格）。
  final BeatGrid grid;

  /// 八拍相位（网格 + 八拍锚点集合，单一相位源）。
  final BeatPhase phase;

  /// 数拍锚素材：录制锚 / 延迟锚 / 激活段段首 / 分段线 / 首线。
  final Duration? recordingAnchor;
  final Duration? delayAnchor;
  final Duration? activeAnchor;
  final List<Duration> segmentLines;
  final Duration firstLine;

  /// 生效音源（设置槽 + 会话回落的派生值）。
  final MetronomeSourceEntry source;

  /// 按槽音量口径（歌曲响度基准 × 增益，半拍槽含拉平）。
  final double Function(MetronomeSegmentSlot slot) slotVolumeOf;

  /// 用户半拍线与半拍声开关。
  final List<Duration> halfBeatLines;
  final bool halfBeatEnabled;

  /// 音画同步 Δ（毫秒；会话活跃取会话试听值，由宿主解析）。
  final int avSyncDelayMs;

  /// 播放速率（引擎真实倍速）。
  final double rate;

  /// 播放态（引擎播放 ∧ 应用前台）。
  final bool playing;

  /// 声音反馈开关。
  final bool soundEnabled;

  /// 网格异常标志（秒制兜底）：发布空值、发声静默（既有口径）。
  final bool gridError;

  /// 校准会话：活跃 + 会话档等拍间隔（null = 无会话档间隔）。
  final bool sessionActive;
  final Duration? sessionBeatInterval;
}

/// 节拍上下文素材：宿主按
/// provider 接线读齐的**原始事实**——网格、相位、时间线、锚点、音源与会话
/// 模式。解析规则（分段线/半拍线投影、会话试听 Δ、生效音源项、会话档间隔、
/// 网格异常谓词）不归宿主，收在 [assembleBeatPresentationContext]。
///
/// 引擎活输入（真实倍速、播放态）**不入本值**：它每帧现读（见
/// [BeatPresentationDriver.readTransport]），缓存会把倍速冻结在素材重算的
/// 那一刻。
///
/// 依赖方向单向：节拍呈现域 → 网格/相位/时间线/音源纯件；反向不成立。
class BeatPresentationFacts {
  const BeatPresentationFacts({
    required this.grid,
    required this.phase,
    required this.timeline,
    required this.recordingAnchor,
    required this.delayAnchor,
    required this.activeLoopStart,
    required this.sourceId,
    required this.slotVolumeOf,
    required this.halfBeatEnabled,
    required this.soundEnabled,
    required this.avSyncDelayMs,
    required this.sessionActive,
    required this.sessionTier,
    required this.sessionTrialMs,
  });

  /// 节拍网格（含节拍对齐/倍频派生）。
  final BeatGrid grid;

  /// 八拍相位（网格 + 锚点集合）。
  final BeatPhase phase;

  /// 有效标注时间线（分段线与半拍线的来源）。
  final AnnotationTimeline timeline;

  /// 数拍锚素材：录制锚 / 延迟锚 / 激活段段首。
  final Duration? recordingAnchor;
  final Duration? delayAnchor;
  final Duration? activeLoopStart;

  /// 生效音源 id（设置槽 + 会话回落的派生值）。
  final String sourceId;

  /// 按槽音量口径（歌曲响度基准 × 增益，半拍槽含拉平）。
  final double Function(MetronomeSegmentSlot slot) slotVolumeOf;

  /// 用户半拍声开关（半拍线本体在时间线里）。
  final bool halfBeatEnabled;

  /// 声音反馈开关。
  final bool soundEnabled;

  /// 音画同步设置 Δ（毫秒；会话活跃时被会话试听值取代）。
  final int avSyncDelayMs;

  /// 校准会话事实：活跃 / 档位 / 试听 Δ。
  final bool sessionActive;
  final CalibrationSessionBpmTier sessionTier;
  final int sessionTrialMs;
}

/// 上下文装配：素材 + 引擎事实（倍速、播放态）→ 每帧上下文。
/// 宿主不再持有本装配的任一规则；新增一个上下文字段只改本处与
/// [BeatPresentationContext] 声明。
BeatPresentationContext assembleBeatPresentationContext(
  BeatPresentationFacts facts, {
  required double rate,
  required bool playing,
}) {
  return BeatPresentationContext(
    grid: facts.grid,
    phase: facts.phase,
    recordingAnchor: facts.recordingAnchor,
    delayAnchor: facts.delayAnchor,
    activeAnchor: facts.activeLoopStart,
    segmentLines: segmentLinePositions(facts.timeline),
    firstLine: facts.timeline.rangeStart,
    source: metronomeSourceEntryOfId(facts.sourceId),
    slotVolumeOf: facts.slotVolumeOf,
    halfBeatLines: [
      for (final line in facts.timeline.halfBeatLines) line.position,
    ],
    halfBeatEnabled: facts.halfBeatEnabled,
    // Δ 的会话试听解析在此落定（会话活跃取试听值）。
    avSyncDelayMs: facts.sessionActive
        ? facts.sessionTrialMs
        : facts.avSyncDelayMs,
    rate: rate,
    playing: playing,
    soundEnabled: facts.soundEnabled,
    // 异常网格（秒制兜底）由网格谓词一处回答。
    gridError: facts.grid.isSecondsFallback,
    sessionActive: facts.sessionActive,
    sessionBeatInterval: CalibrationSessionGrid.beatIntervalOf(
      facts.sessionTier,
      facts.grid.hasRealBeats ? facts.grid : null,
    ),
  );
}

/// 一次发布求值（纯函数）：`(节拍上下文, 媒介位置) → 发布值`。无锚可数
/// （位置早于首线或超出网格末拍）或网格异常（秒制兜底不画假拍序，既有
/// 口径）时返回 null——浮层不显示。
BeatPresentationValue? evaluatePresentationValue({
  required BeatPresentationContext context,
  required Duration position,
}) {
  if (context.gridError) return null;
  final beat = evaluateCurrentBeat(
    grid: context.grid,
    phase: context.phase,
    recordingAnchor: context.recordingAnchor,
    delayAnchor: context.delayAnchor,
    activeAnchor: context.activeAnchor,
    segmentLines: context.segmentLines,
    firstLine: context.firstLine,
    position: position,
    halfBeatLines: context.halfBeatLines,
    halfBeatEnabled: context.halfBeatEnabled,
  );
  if (beat == null) return null;
  final animation = deriveBeatPhase(
    grid: context.grid,
    position: position,
    phase: context.phase,
  );
  final windowFirst = animation.windowFirstBeatIndex;
  final last = context.grid.lastBeatIndex;

  // 窗口内部边界（第 i 格左边界 = 全局拍 windowFirst + i）是否画强拍竖线：
  // 越界边界无拍可派生、不画（有界网格 beatTime 越界抛错）。
  bool isStrongBoundary(int offset) {
    final boundary = windowFirst + offset;
    if (boundary < 0) return false;
    if (last != null && boundary > last) return false;
    return context.phase.isStrongBeat(boundary);
  }

  final strongOffsets = <int>[
    for (var i = 1; i < kBeatsPerEightCount; i++)
      if (isStrongBoundary(i)) i,
  ];
  final projections = projectUserHalfBeatLines(
    grid: context.grid,
    windowFirstBeatIndex: windowFirst,
    halfBeatLines: context.halfBeatLines,
  );
  return BeatPresentationValue(
    beat: beat,
    animation: animation,
    strongBoundaryOffsets: strongOffsets,
    halfBeatProjections: projections,
  );
}

/// 排程不变量断言：产出的**指令时刻**（拍点 − Δ 平移，原生实际消费的
/// 时刻）不早于当时的估计位置——这正是跳过守卫维持的同一条不变量，此处
/// 是它的兜底断言（负 Δ 下拍点媒体时刻可以早于位置，指令时刻不早，不
/// 误报）。相邻产出间隔与网格相邻拍点间隔的关系由产出行内携带的「媒体
/// 时刻 + 当时位置」直接可读（真机按 ±1ms 判读；间隔一律按媒体时刻，
/// 不含 Δ·rate 位移）。
String? scheduleInvariantWarning({required int commandMs, required int estMs}) {
  if (commandMs < estMs) {
    return '排程报警 ${commandMs}ms：产出早于当时位置 ${estMs}ms';
  }
  return null;
}

/// 节拍呈现对象：
///
/// ```
/// attach()                         // 开流、按注册表装配段表
/// detach()                         // 收流、清未消费
/// onFrame(节拍上下文, 媒介位置)     // 位置事件与周期 tick 同走这一条
/// ValueListenable<发布值?> 当前拍   // 屏幕订阅的同一个值
/// ```
///
/// 发声排程走同一条 `onFrame`：外推当下 → 位置跳变自判 → 左闭右
/// 开前瞻窗逐拍交原生。执行器 seam 可空（null = 不触流）；seam 工厂在每
/// 次推进时现读（音源切换致渲染器重建后新实例即被拾取，推进不断声）。
/// attach/detach 幂等：重复 attach 不重复开流，未 attach 时 detach 是
/// no-op，detach 后 `onFrame` 不再发布。
class BeatPresentation {
  BeatPresentation({
    BeatStreamControl Function()? streamControl,
    BeatScheduleConsumer Function()? consumer,
    BeatAudioRendererLifecycle Function()? timebase,
    this.onSessionBeat,
    this.topUpPeriod = Duration.zero,
  }) : _streamControlOf = streamControl,
       _consumerOf = consumer,
       _timebaseOf = timebase;

  final BeatStreamControl Function()? _streamControlOf;
  final BeatScheduleConsumer Function()? _consumerOf;

  /// 渲染器时基 seam（哑转发：呈现唯一外推的媒介时刻配对下推原生 + 会话
  /// 边沿）。null = 本装配不含时基（纯装配缝用例）。
  final BeatAudioRendererLifecycle Function()? _timebaseOf;

  /// 会话拍视觉出口：每产出一条会话拍指令点火一次（气泡脉冲与发声同一
  /// 拍点时刻表、同一拍序）。
  final void Function()? onSessionBeat;

  /// 周期 tick 间隔（[kBeatPresentationTopUpPeriod]；`Duration.zero` =
  /// 不起表，装配缝用例手动驱动 tick）。
  final Duration topUpPeriod;

  final ValueNotifier<BeatPresentationValue?> _currentBeat =
      ValueNotifier<BeatPresentationValue?>(null);

  /// 当前拍读出（屏幕订阅的同一个值；null = 无可数拍 / 网格异常 / 未 attach）。
  ValueListenable<BeatPresentationValue?> get currentBeat => _currentBeat;

  bool _attached = false;

  // ---- 记账一：时钟（最近一次报位 + 报位时的单调钟读数，外推用）----

  bool _hasClock = false;
  Duration _clockPosition = Duration.zero;
  int _clockMonotonicMs = 0;
  bool _clockPlaying = false;

  // ---- 记账二：水位与拍光标（水位 = 已交给原生到哪个媒介时刻；毫秒；
  // null = 未立。两条拍光标 = 已产出的最大拍点媒介时刻，整拍与半拍各一条，
  // 只进不退）----

  int? _watermarkMs;
  int _wholeBeatCursorMs = _noBeatEmitted;
  int _halfBeatCursorMs = _noBeatEmitted;

  // ---- 记账三/四：网格身份与音源身份（换代自判用）----

  BeatGrid? _builtGrid;
  String? _builtSourceId;

  // ---- 校准会话锚（会话域水位的原点；单调毫秒）----

  bool _sessionArmed = false;
  int? _sessionEntryMs;

  // ---- 记账五：流记账（应活态 / 已开 / 在案失败 / 在途开流）----

  bool? _shouldLive;
  bool _streamOpen = false;
  _OpenFailure? _openFailure;
  Future<void>? _streamStart;

  // ---- 驱动：最近一帧的上下文与位置（周期 tick 重放）+ 推进串行链 ----

  BeatPresentationContext? _lastContext;
  Timer? _topUpTimer;
  Future<void> _chain = Future.value();

  /// 当前推进链排空（装配缝用例等产出落定用；不触内部状态）。
  Future<void> get settled => _chain;

  /// 最近一次接线的 seam 实例（音源切换致渲染器重建后随推进换新；detach
  /// 用最近实例收口，宿主销毁后不再触碰工厂闭包）。已收尾（含容器销毁）
  /// 后不再新接线：取控制流返回空，调用方据此丢弃本次推进；保留的最近
  /// 实例只供收尾与单调钟兜底。
  BeatScheduleConsumer? _lastConsumer;
  BeatStreamControl? _lastControl;

  BeatStreamControl? _captureControl() {
    if (!_attached) return null;
    return _lastControl = _streamControlOf?.call();
  }

  /// 不连续（flush / 位置跳变 / 进出场 / 换代 / 停流）：水位与两条拍光标
  /// 一并归位——已交给原生的指令作废，恢复后自当下重排。
  void _resetCursors() {
    _watermarkMs = null;
    _wholeBeatCursorMs = _noBeatEmitted;
    _halfBeatCursorMs = _noBeatEmitted;
  }

  /// 开流、接线执行器 seam、起周期 tick 表。重复 attach 幂等（不重复开流）。
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    if (topUpPeriod > Duration.zero) {
      _topUpTimer = Timer.periodic(topUpPeriod, (_) {
        // 周期 tick 同走 onFrame：重放最近报位（发布值照常更新）。
        if (_lastContext != null) onFrame(_lastContext!, _clockPosition);
      });
    }
    final control = _captureControl();
    if (control != null) {
      await _coalesceOpen(control);
    }
  }

  /// 收流、清未消费。未 attach 时 no-op；detach 后 onFrame 不再发布。
  /// 收口用**最近一次接线**的 seam 实例（工厂闭包在宿主销毁后不可再触碰）。
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    _topUpTimer?.cancel();
    _topUpTimer = null;
    final consumer = _lastConsumer;
    final control = _lastControl;
    if (consumer != null) {
      await consumer.flush();
    } else {
      // 从未推进过（attach 后直接 detach）：接线一次以收口；宿主已销毁
      // 时工厂不可触碰，异常即无事可做。
      try {
        await _consumerOf?.call().flush();
      } on Object catch (_) {}
    }
    control?.stopStream();
    _streamOpen = false;
    _shouldLive = null;
    _resetCursors();
    _openFailure = null;
    _builtGrid = null;
    _builtSourceId = null;
    _sessionArmed = false;
    _sessionEntryMs = null;
    _hasClock = false;
    _lastContext = null;
  }

  /// 位置事件与周期 tick 的唯一入口：按该位置求值并发布（值不变不重发），
  /// 并推进发声排程。
  void onFrame(BeatPresentationContext context, Duration position) {
    if (!_attached) return;
    final value = evaluatePresentationValue(
      context: context,
      position: position,
    );
    if (value != _currentBeat.value) _currentBeat.value = value;
    // 任何报位直接覆盖时钟（含向后；周期 tick 重放同一位置，位置值相同
    // 不重立锚，外推进度得以保留）。播放态边沿重立锚——暂停冻结期间锚
    // 墙钟老化，恢复即以当下为新锚（不把暂停时长外推进位置）。
    if (!_hasClock ||
        position != _clockPosition ||
        context.playing != _clockPlaying) {
      _clockPosition = position;
      _clockMonotonicMs = _monotonicMs();
      _clockPlaying = context.playing;
      _hasClock = true;
    }
    _lastContext = context;
    _enqueueAdvance();
  }

  void _enqueueAdvance() {
    final context = _lastContext!;
    _chain = _chain.then(
      (_) => _advance(context),
      onError: (Object error, StackTrace stack) {
        beatAudioLog('推进失败（$error）：下一帧再试');
      },
    );
  }

  int _monotonicMs() =>
      (_lastControl ?? _streamControlOf?.call())?.monotonicMs() ?? 0;

  /// 时基下推（配对）：媒介时刻取自本对象的唯一外推
  /// （调用方已算好的 [mediaMs]，同一次推进只算一遍），倍速与播放态随同一
  /// 份上下文同源；配对的另一半 = 原生自己的帧位，由原生在收到下推时现取。
  /// 校准会话期间不下推媒体轴（会话锚由渲染器经会话边沿自理；渲染器侧
  /// 的会话拒收是同一纪律的第二道闸）。
  void _pushMediaNow(BeatPresentationContext context, int nowMs, int mediaMs) {
    if (!_attached) return;
    if (context.sessionActive) return;
    _timebaseOf?.call().onMediaNow(
      MediaClockSync(
        mediaTimeMs: mediaMs,
        rate: context.rate,
        playing: context.playing,
      ),
    );
  }

  /// 当下：锚点报位 + 单调差 × 速率的外推（全仓唯一一条「现在」算式，
  /// 见 [_extrapolateMs]）。会话轴不另写式子——它换的是锚，见该函数。
  int _estimateMs(BeatPresentationContext context, int nowMs) {
    if (context.sessionActive) {
      // 会话域：同一条外测算式换锚——锚 = 会话进入时刻、位置 0、速率 1
      // （会话时钟走墙钟，媒体倍速不进会话域）。
      return _extrapolateMs(
        posMs: 0,
        atMs: _sessionEntryMs!,
        rate: 1,
        nowMs: nowMs,
      );
    }
    // 媒介域：锚 = 最近一次报位；暂停冻结 = 速率 0（锚不老化）。
    return _extrapolateMs(
      posMs: _clockPosition.inMilliseconds,
      atMs: _clockMonotonicMs,
      rate: context.playing ? context.rate : 0,
      nowMs: nowMs,
    );
  }

  /// 「现在」的唯一算式：锚点报位 + 单调钟差 ×
  /// 速率，负值钳 0。媒体轴与会话轴共用；两轴的差别只是锚的取值——
  /// 「校准会话换的是间隔与时钟位置」在代码里就是换这组锚。
  int _extrapolateMs({
    required int posMs,
    required int atMs,
    required double rate,
    required int nowMs,
  }) {
    final estimate = posMs + ((nowMs - atMs) * rate).round();
    return estimate < 0 ? 0 : estimate;
  }

  Future<void> _advance(BeatPresentationContext context) async {
    final control = _captureControl();
    if (control == null) return;
    final consumer = _lastConsumer = _consumerOf?.call();
    if (consumer == null) return;
    final nowMs = control.monotonicMs();

    // 会话边沿：进入 = 时基切会话锚 + flush + 水位归会话域零；退出 =
    // 时基清会话锚 + flush + 水位作废（回媒介域后自跳变判定归位）。
    if (context.sessionActive != _sessionArmed) {
      _sessionArmed = context.sessionActive;
      await _timebaseOf?.call().onCalibrationSession(context.sessionActive);
      await consumer.flush();
      _sessionEntryMs = context.sessionActive ? nowMs : null;
      _resetCursors();
      _pushMediaNow(context, nowMs, _estimateMs(context, nowMs));
    }

    // 流生命周期收口先于一切产出判定（应活 = 会话常开或播放×开声）：
    // 应活即开流/自愈，不应活停流；边沿/自愈/关门在途时等收口落定、本拍
    // 不产（先开流再入队：无流的指令会被原生丢弃）。
    final shouldLive =
        context.sessionActive || (context.playing && context.soundEnabled);
    final wasLive = _shouldLive;
    _shouldLive = shouldLive;
    if (!shouldLive) {
      // 不应活（含应活边沿转停与首拍即不应活）：时基照实下推（播放态 =
      // 假），flush + 停流，错过的拍不补发；水位作废（恢复后自当下重排）。
      _pushMediaNow(context, nowMs, _estimateMs(context, nowMs));
      if (wasLive == true || _streamOpen) await _closeStream(consumer, control);
      return;
    }
    if (wasLive != true) {
      // 应活边沿（起手/恢复/开声/会话进）：attach 已开流的不重复开，其余
      // 开流；水位归位到当下。
      if (!_streamOpen) {
        await _coalesceOpen(control);
        if (!_streamOpen) return;
      }
      _resetCursors();
      _pushMediaNow(context, nowMs, _estimateMs(context, nowMs));
    } else if (_needsOpen(control)) {
      // 周期时机自愈：失效探测 / 在案失败 → 冷却后重开（重建流对象按预算）。
      if (!_cooldownElapsed(control)) return;
      await _coalesceOpen(control);
      if (!_streamOpen) return;
      _resetCursors();
      _pushMediaNow(context, nowMs, _estimateMs(context, nowMs));
    }

    final estMs = _estimateMs(context, nowMs);
    _pushMediaNow(context, nowMs, estMs);

    // 发声闸门（唯一一处）：播放中 ∧ 开声 ∧ 非异常 ∧ 音源可用；校准会话
    // 是唯一例外（不受开声开关与播放态约束，见应活判定）。闸门只关发声
    // 不关求值（发布值已出）；关期水位不动，恢复后首个推进按跳变判定归位。
    final gateOpen =
        context.playing &&
        context.soundEnabled &&
        !context.gridError &&
        context.source.available;

    // 校准会话：同一条热路径的退化情形（会话等拍网格 + 墙钟位置 + 锚 0 +
    // 无半拍）。
    if (context.sessionActive) {
      final toMs = estMs + kMetronomeLookaheadWindow.inMilliseconds;
      await _advanceSession(context, consumer, estMs, toMs);
      _watermarkMs = toMs;
      return;
    }

    // 网格 / 音源换代：清掉旧上下文的未消费拍声，水位归位到当下。
    final gridChanged =
        _builtGrid != null && !identical(context.grid, _builtGrid);
    final sourceChanged = context.source.id != _builtSourceId;
    if (gridChanged || sourceChanged) {
      beatAudioLog('硬切 ${gridChanged ? '网格换代' : '音源换代'}');
      await consumer.flush();
      _resetCursors();
      _pushMediaNow(context, nowMs, _estimateMs(context, nowMs));
    }
    _builtGrid = context.grid;
    _builtSourceId = context.source.id;

    // 位置跳变自判（判据只用当下与水位）：向前越过已排区、向后越过前瞻
    // 窗，都清原生未消费并把水位归位——seek、段循环与整片循环回跳、以及
    // 携带回跳前位置的陈旧报位都走这一条，宿主不声明。
    final watermark = _watermarkMs;
    if (watermark != null &&
        (estMs > watermark ||
            estMs + kMetronomeLookaheadWindow.inMilliseconds < watermark)) {
      await consumer.flush();
      _resetCursors();
      _pushMediaNow(context, nowMs, _estimateMs(context, nowMs));
    }
    // 闸门在换代与跳变自判之后：清账动作不因静默而跳过（旧音源的已排
    // 拍声仍须清掉），只挡新产出。
    if (!gateOpen) return;

    final fromMs = _watermarkMs == null
        ? estMs
        : (estMs > _watermarkMs! ? estMs : _watermarkMs!);
    final toMs = estMs + kMetronomeLookaheadWindow.inMilliseconds;
    await _advanceMedia(context, consumer, estMs, fromMs, toMs);
    _watermarkMs = toMs;
  }

  /// 播放轴产出：指令时刻落在 `[fromMs, toMs)` 的逐拍指令（拍点窗见
  /// [_BeatScanWindow]）。整拍与半拍各有一条只进不退的拍光标：同一拍点产出
  /// 一次后不再产出，落在窗左端的那拍排一次、落在右端的留给下一轮 ⇒ 一拍一
  /// 声在结构上成立；指令时刻早于当下的拍跳过（不响过去、不补发）。选段/半
  /// 拍经 core 同一次求值（[evaluateCurrentBeat]：前导区 0｜x、半拍只在正式
  /// 区、锚逐拍现算）。
  Future<void> _advanceMedia(
    BeatPresentationContext context,
    BeatScheduleConsumer consumer,
    int estMs,
    int fromMs,
    int toMs,
  ) async {
    // Δ 的唯一换算：具名算式带倍速因子，媒体轴与
    // 会话轴共用（会话轴的因子取 1，见 [_advanceSession]）。
    final shiftMs = avSyncTickTriggerShiftMedia(
      delayMs: context.avSyncDelayMs,
      rate: context.rate,
    ).inMilliseconds;
    final groupIndex = selectMetronomeSpeedGroupIndex(
      context.source.speedGroups,
      context.grid.nominalBeat.inMilliseconds,
    );
    final window = _BeatScanWindow(
      commandFromMs: fromMs,
      commandToMs: toMs,
      shiftMs: shiftMs,
    );
    final beats = context.grid.beatsInWindow(
      Duration(milliseconds: window.fromMs),
      Duration(milliseconds: window.toMs),
    );
    CurrentBeat? evalAt(Duration position) => evaluateCurrentBeat(
      grid: context.grid,
      phase: context.phase,
      recordingAnchor: context.recordingAnchor,
      delayAnchor: context.delayAnchor,
      activeAnchor: context.activeAnchor,
      segmentLines: context.segmentLines,
      firstLine: context.firstLine,
      position: position,
      halfBeatLines: context.halfBeatLines,
      halfBeatEnabled: context.halfBeatEnabled,
    );
    // 整拍：拍点在窗内且未产出过即排（拍号按该拍位置现算，与屏幕同一次求值）。
    for (final beatTime in beats) {
      final beatMs = beatTime.inMilliseconds;
      if (!window.covers(beatMs) || window.isPast(beatMs, estMs)) continue;
      if (beatMs <= _wholeBeatCursorMs) continue;
      final beat = evalAt(beatTime);
      if (beat == null) continue;
      final slot = selectMetronomeSlot(
        eightCount: beat.eightCount,
        beatCount: beat.beatCount,
        mode: context.source.mode,
      );
      _wholeBeatCursorMs = beatMs;
      await _emit(
        context,
        consumer,
        commandMs: window.commandOf(beatMs),
        mediaMs: beatMs,
        estMs: estMs,
        eightCount: beat.eightCount,
        beatCount: beat.beatCount,
        anchorMs: evaluateBeatCountAnchor(
          grid: context.grid,
          phase: context.phase,
          recordingAnchor: context.recordingAnchor,
          delayAnchor: context.delayAnchor,
          activeAnchor: context.activeAnchor,
          segmentLines: context.segmentLines,
          firstLine: context.firstLine,
          position: beatTime,
        )?.inMilliseconds,
        slot: slot,
        groupIndex: groupIndex,
      );
    }
    // 半拍：用户半拍线落在窗内且未产出过才排，按线所在拍现算（求值只在前导
    // 区外、开关开且非与整拍同毫秒时给出该线——前导区不出半拍由同一条派生
    // 推出）。
    for (final half in context.halfBeatLines) {
      final halfMs = half.inMilliseconds;
      if (!window.covers(halfMs) || window.isPast(halfMs, estMs)) continue;
      if (halfMs <= _halfBeatCursorMs) continue;
      final beat = evalAt(half);
      if (beat == null || !beat.halfBeatLines.contains(half)) continue;
      _halfBeatCursorMs = halfMs;
      await _emit(
        context,
        consumer,
        commandMs: window.commandOf(halfMs),
        mediaMs: halfMs,
        estMs: estMs,
        eightCount: beat.eightCount,
        beatCount: beat.beatCount,
        anchorMs: evaluateBeatCountAnchor(
          grid: context.grid,
          phase: context.phase,
          recordingAnchor: context.recordingAnchor,
          delayAnchor: context.delayAnchor,
          activeAnchor: context.activeAnchor,
          segmentLines: context.segmentLines,
          firstLine: context.firstLine,
          position: half,
        )?.inMilliseconds,
        slot: MetronomeSegmentSlot.half,
        groupIndex: groupIndex,
      );
    }
  }

  /// 会话轴产出：与正式数拍**同一条求值**（`lib/beat/CONTEXT.md`「节拍呈现」）——
  /// 会话域网格 = 档间隔的均匀网格（占位实现同款：时间轴 0 对齐、每小节
  /// 首拍强拍、无界），会话拍点经 [evaluateCurrentBeat] 与锚点链求值，
  /// 八拍号、拍号、锚与选段同正式播放一套口径。档位变更自下一拍生效
  /// （已排拍按旧档消费，未排拍按新档整倍数取点）。Δ 换算用同一条
  /// 具名算式，倍速因子取 1（会话时钟走墙钟）。
  Future<void> _advanceSession(
    BeatPresentationContext context,
    BeatScheduleConsumer consumer,
    int estMs,
    int toMs,
  ) async {
    final interval = context.sessionBeatInterval;
    if (interval == null || interval <= Duration.zero) return;
    final intervalMs = interval.inMilliseconds;
    final grid = UniformBeatGrid(bpm: 60000 / intervalMs);
    final phase = BeatPhase(grid: grid);
    final shiftMs = avSyncTickTriggerShiftMedia(
      delayMs: context.avSyncDelayMs,
      rate: 1,
    ).inMilliseconds;
    final watermark = _watermarkMs ?? estMs;
    final fromMs = watermark > estMs ? watermark : estMs;
    final groupIndex = selectMetronomeSpeedGroupIndex(
      context.source.speedGroups,
      intervalMs,
    );
    final window = _BeatScanWindow(
      commandFromMs: fromMs,
      commandToMs: toMs,
      shiftMs: shiftMs,
    );
    for (final beatTime in grid.beatsInWindow(
      Duration(milliseconds: window.fromMs),
      Duration(milliseconds: window.toMs),
    )) {
      if (!_attached) return;
      final beatMs = beatTime.inMilliseconds;
      if (!window.covers(beatMs) || window.isPast(beatMs, estMs)) continue;
      if (beatMs <= _wholeBeatCursorMs) continue;
      // 会话拍号与锚走正式数拍的同一套求值（无界网格恒可数）。
      final beat = evaluateCurrentBeat(
        grid: grid,
        phase: phase,
        recordingAnchor: null,
        delayAnchor: null,
        activeAnchor: null,
        segmentLines: const [],
        firstLine: Duration.zero,
        position: beatTime,
        halfBeatLines: const [],
        halfBeatEnabled: false,
      );
      if (beat == null) continue;
      _wholeBeatCursorMs = beatMs;
      onSessionBeat?.call();
      await _emit(
        context,
        consumer,
        commandMs: window.commandOf(beatMs),
        mediaMs: beatMs,
        estMs: estMs,
        eightCount: beat.eightCount,
        beatCount: beat.beatCount,
        anchorMs: evaluateBeatCountAnchor(
          grid: grid,
          phase: phase,
          recordingAnchor: null,
          delayAnchor: null,
          activeAnchor: null,
          segmentLines: const [],
          firstLine: Duration.zero,
          position: beatTime,
        )?.inMilliseconds,
        slot: selectMetronomeSlot(
          eightCount: beat.eightCount,
          beatCount: beat.beatCount,
          mode: context.source.mode,
        ),
        groupIndex: groupIndex,
      );
    }
  }

  /// 产出唯一出口：闸门已在推进入口一处收口（会话例外），此处只写消费
  /// seam + 产出日志。产出行携带观测四元组（媒体时刻、号、该拍求值用的
  /// 锚、当时位置），全部按**已算出的值**拼（不为
  /// 拼一行日志重算呈现值）；并跑排程不变量断言（指令时刻早于当
  /// 时位置即报警行，正常播放全程无报警）。
  Future<void> _emit(
    BeatPresentationContext context,
    BeatScheduleConsumer consumer, {
    required int commandMs,
    required int mediaMs,
    required int estMs,
    required int eightCount,
    required int beatCount,
    required int? anchorMs,
    required MetronomeSegmentSlot slot,
    required int groupIndex,
  }) async {
    final accepted = await consumer.schedule(
      BeatScheduleCommand(
        beatMediaTime: Duration(milliseconds: commandMs),
        segmentId: metronomeSegmentIdOf(context.source, groupIndex, slot),
        volume: context.slotVolumeOf(slot),
      ),
    );
    final invariant = scheduleInvariantWarning(
      commandMs: commandMs,
      estMs: estMs,
    );
    if (invariant != null) beatAudioLog(invariant);
    beatAudioLog(
      '产出 ${mediaMs}ms 号$eightCount｜$beatCount'
      '${anchorMs == null ? '' : ' 锚${anchorMs}ms'} 位置${estMs}ms '
      '$slot 组$groupIndex',
    );
    if (!accepted) {
      beatAudioLog('入队失败 ${commandMs}ms：原生未接受，按流记账触发自愈重试');
      _openFailure ??= _OpenFailure(cause: '入队失败', atMs: _monotonicMs());
    }
  }

  // ---- 流生命周期与自愈（应活即开流、不应活停流、失效探测后重开并按
  // 水位重排）----

  bool _needsOpen(BeatStreamControl control) {
    if (!_streamOpen || _openFailure != null) return true;
    try {
      return control.streamLost();
    } on Object {
      return true;
    }
  }

  bool _cooldownElapsed(BeatStreamControl control) {
    final failure = _openFailure;
    if (failure == null) return true;
    return control.monotonicMs() - failure.atMs >= kStreamRetryCooldownMs;
  }

  Future<void> _closeStream(
    BeatScheduleConsumer consumer,
    BeatStreamControl control,
  ) async {
    _streamOpen = false;
    _openFailure = null;
    _resetCursors();
    try {
      await consumer.flush();
      control.stopStream();
    } on Object catch (error) {
      beatAudioLog('停流失败（$error）：下一轮再试');
    }
  }

  Future<void> _coalesceOpen(BeatStreamControl control) {
    final pending = _streamStart;
    if (pending != null) return pending;
    final future = _openStreamAttempt(control);
    _streamStart = future;
    return future.whenComplete(() {
      if (identical(_streamStart, future)) _streamStart = null;
    });
  }

  Future<void> _openStreamAttempt(BeatStreamControl control) async {
    try {
      bool lost;
      try {
        lost = control.streamLost();
      } on Object catch (error) {
        beatAudioLog('流状态探测失败（$error）：按流已失效处理，重建原生输出流');
        lost = true;
      }
      if (lost) beatAudioLog('流已被系统错误关闭（应活）：探测到即重开');
      final failure = _openFailure;
      if (failure != null && failure.resets < kTransportResetLimitPerRound) {
        try {
          await control.rebuildTransport();
          _openFailure = _OpenFailure(
            cause: failure.cause,
            atMs: failure.atMs,
            resets: failure.resets + 1,
          );
          beatAudioLog('重建原生输出流后重试（此前失败：${failure.cause}）');
        } on Object catch (error) {
          beatAudioLog('重建原生输出流失败（$error）：下一轮再试');
        }
      }
      await control.openStream();
      _streamOpen = true;
      final recovered = _openFailure?.cause;
      _openFailure = null;
      if (recovered != null) beatAudioLog('开流恢复（此前失败：$recovered）');
    } on Object catch (error) {
      final previous = _openFailure;
      _openFailure = previous == null
          ? _OpenFailure(cause: '$error', atMs: control.monotonicMs())
          : _OpenFailure(
              cause: '$error',
              atMs: control.monotonicMs(),
              resets: previous.resets,
            );
      beatAudioLog('开流失败（$error）：不闩锁，周期时机冷却重试');
    }
  }
}

/// 一次开流失败的记录：原因、时刻（同一单调时基，供冷却判定）与本轮已
/// 重建原生流的次数。成功开流即置 null。
class _OpenFailure {
  const _OpenFailure({
    required this.cause,
    required this.atMs,
    this.resets = 0,
  });

  final String cause;
  final int atMs;
  final int resets;
}

/// 节拍呈现驱动：把「素材变化 → 重驱」「位置
/// 报位 → 重驱」「播放态/前后台边沿 → 重驱」收成节拍呈现域自己的编排。
/// 宿主只做 provider 接线，并上报两条会话事实（位置原始报位、应用前后台）。
///
/// 依赖一律显式（读取闭包），不收容器句柄、不读构建上下文、不 import 中枢：
///
/// - [readFacts]：provider 接线的素材读面（[BeatPresentationFacts]）；
/// - [readTransport]：引擎活输入（真实倍速、播放态），每帧现读不缓存；
/// - [readPosition]：播放位置的原始报位（null = 位置未就绪，本次不驱动）。
///
/// 播放态 = 引擎播放 ∧ 应用前台（[setAppPaused] 的上报值）。重驱经微任务
/// 错开 provider 通知窗口（同帧二重建守卫）。驱动不触碰呈现对象的
/// attach/detach 生命周期——那是宿主自己的收尾。
class BeatPresentationDriver {
  BeatPresentationDriver({
    required this.presentation,
    required this.readFacts,
    required this.readTransport,
    required this.readPosition,
  });

  /// 被驱动的节拍呈现对象（宿主已 attach）。
  final BeatPresentation presentation;

  /// 素材读面（provider 接线的原始事实）。
  final BeatPresentationFacts Function() readFacts;

  /// 引擎活输入：真实倍速 + 引擎播放态。
  final ({double rate, bool playing}) Function() readTransport;

  /// 播放位置的原始报位；null = 位置未就绪。
  final Duration? Function() readPosition;

  bool _appPaused = false;
  bool _disposed = false;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  /// 应用前后台事实：退后台 = 引擎播放态不再算数（节拍声应活门控的一路）；
  /// 回前台即按引擎真实播放态恢复。
  void setAppPaused(bool paused) {
    _appPaused = paused;
    resync();
  }

  /// 引擎两条流接线：位置报位与播放态边沿各重驱一次（宿主不再转发这两条
  /// 引擎事件）。重复调用幂等；[dispose] 收流。
  void attach(PlaybackEngine engine) {
    _positionSub ??= engine.positionStream.listen((_) => resync());
    _playingSub ??= engine.isPlayingStream.listen((_) => resync());
  }

  /// 任一素材事实、位置报位或播放态边沿变化：按现读素材与位置重驱一次
  /// `onFrame`（发布值 + 发声排程同一条入口）。已收尾即丢弃（含在途微任务）。
  void resync() {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (_disposed) return;
      final position = readPosition();
      if (position == null) return;
      final transport = readTransport();
      presentation.onFrame(
        assembleBeatPresentationContext(
          readFacts(),
          rate: transport.rate,
          playing: !_appPaused && transport.playing,
        ),
        position,
      );
    });
  }

  /// 收尾：先收引擎流，其后不再驱动（宿主 dispose 时调用；不触碰呈现对象）。
  void dispose() {
    _disposed = true;
    _positionSub?.cancel();
    _positionSub = null;
    _playingSub?.cancel();
    _playingSub = null;
  }
}

/// 拍声扫描窗（Δ×倍速换算的唯一消费口径，「口径各归一处」）：把
/// 指令时刻窗 `[commandFromMs, commandToMs)` 映射为拍点窗。正 Δ 把指令时刻
/// 提前到拍点之前，拍点窗随之整体前移同样多——Δ ≥ 窗宽时窗口不动则无拍可
/// 排；Δ ≤ 0 时指令时刻晚于拍点，按拍点扫码已经足够，不前移（负 Δ 的指令
/// 提前量因此可以大于窗宽）。
class _BeatScanWindow {
  _BeatScanWindow({
    required int commandFromMs,
    required int commandToMs,
    required this.shiftMs,
  }) : fromMs = commandFromMs + (shiftMs > 0 ? shiftMs : 0),
       toMs = commandToMs + (shiftMs > 0 ? shiftMs : 0);

  /// 拍点窗（左闭右开；beatsInWindow 闭窗含端点，右端由 [covers] 裁）。
  final int fromMs;
  final int toMs;

  /// 指令时刻 = 拍点 − [shiftMs]（Δ×倍速的具名换算在调用侧完成）。
  final int shiftMs;

  bool covers(int beatMs) => beatMs >= fromMs && beatMs < toMs;

  int commandOf(int beatMs) => beatMs - shiftMs;

  /// 指令时刻早于当下：不响过去、不补发。
  bool isPast(int beatMs, int estMs) => commandOf(beatMs) < estMs;
}
