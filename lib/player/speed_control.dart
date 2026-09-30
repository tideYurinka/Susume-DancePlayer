import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/segment_selection.dart';
import '../core/playback/playback_engine.dart';
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../core/playback/playback_loop_providers.dart';
import 'annotation_editor.dart' show selectedLearningSegmentRangeProvider;

// formatRate 已归位纯函数域 speed_step.dart；此处 re-export 保持
// 既有消费方 import 不变。
import 'compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'speed_history_store.dart';
import 'speed_step.dart';

/// 倍速输入/滑条可调范围（初值）。
const double speedRateMin = 0.1;
const double speedRateMax = 2.0;

/// 常用倍速快捷档（0.25 为扒舞常用慢速；2.0 不经快捷，仅经
/// 自定义输入可达）。
const List<double> commonSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5];

/// 气泡自定义滑条上界（滑条 0.1–1.5；步长 0.05，
/// [speedRateMax] = 2.0）。
const double speedSliderMax = 1.5;

/// 气泡滑条步长（0.05 步——滑条为
/// 精调手段，分辨率与候选网格一致；lib 与测试共用同一常量推导分度）。
const double speedSliderStep = 0.05;

/// 倍速步进的作用范围。
///
/// - [activeSegment]：作用于当前激活学习段的合并范围（循环由区间循环薄层
///   驱动，每循环一圈推进一档）；
/// - [wholeVideo]：作用于首/尾划定的有效练习区间（循环由视频尾循环提示的
///   自动循环驱动，每次自动循环推进一档；无循环不推进）。
enum SpeedStepScope { activeSegment, wholeVideo }

/// 倍速控制状态（`player` 域）。
class SpeedControlState {
  const SpeedControlState({
    this.manualRate = 1.0,
    this.memoryRate,
    this.stepEnabled = false,
    this.stepParams = const SpeedStepParams(),
    this.stepScope = SpeedStepScope.activeSegment,
    this.stepCycle = 0,
    this.history = const [],
    this.transientActive = false,
  });

  /// 倍速设置（手动）倍率：经面板设置，钳制在 [speedRateMin, speedRateMax]、
  /// 保留两位小数。
  final double manualRate;

  /// 这支舞的**倍速记忆**（随舞，落本地文档 `prefs.speedRate`）：null = 这支舞
  /// 没有意见（按出厂原速 1.0× 打开）。只有用户改档写它，步进/瞬态不写。
  final double? memoryRate;

  /// 倍速步进是否启用（与倍速设置互斥，模型级）。
  final bool stepEnabled;

  /// 倍速步进参数（起步倍速/封顶倍速/每档遍数/递增量），恒合法（[SpeedStepParams.isValid]）。
  final SpeedStepParams stepParams;

  /// 步进作用范围：启用时按范围来源消费循环推进事件。
  final SpeedStepScope stepScope;

  /// 已完成的练习循环遍数（自启用起计；档位 = `rateForStepCycle(遍数)`）。
  final int stepCycle;

  /// 历史倍速：去重、最近使用在前（上限 [speedHistoryCap]）。
  final List<double> history;

  /// 观看面瞬态倍速（长按 2×）是否生效：「2 倍速」提示浮层据此
  /// 显隐（按住期常显、松开即卸载）。中途转暂停不变，直到 [SpeedControlModel.endTransientRate]。
  final bool transientActive;

  /// 当前生效倍率：步进启用时为当前遍数对应的步进档位，否则为 [manualRate]。
  /// 不反映观看面瞬态倍速（长按 2×，[SpeedControlModel.beginTransientRate]
  /// 只写引擎、不改模型状态）。
  double get effectiveRate =>
      stepEnabled ? rateForStepCycle(stepParams, stepCycle) : manualRate;

  /// 手动倍速是否处于「生效中」（非 1.0 且步进未启用）：
  /// [speedSideInEffect] 的手动分支。
  bool get manualSpeedInEffect => !stepEnabled && manualRate != 1.0;

  /// 倍速侧是否任一生效中：步进启用，或步进停用且手动倍速 ≠ 1.0。
  /// 顶栏「倍速设置」槽唯一的激活谓词；激活形态（图标琥珀、标签、倍率槽）
  /// 由该槽的渲染处给出。
  bool get speedSideInEffect => stepEnabled || manualSpeedInEffect;

  SpeedControlState copyWith({
    double? manualRate,
    double? memoryRate,
    bool clearMemory = false,
    bool? stepEnabled,
    SpeedStepParams? stepParams,
    SpeedStepScope? stepScope,
    int? stepCycle,
    List<double>? history,
    bool? transientActive,
  }) {
    return SpeedControlState(
      manualRate: manualRate ?? this.manualRate,
      memoryRate: clearMemory ? null : (memoryRate ?? this.memoryRate),
      stepEnabled: stepEnabled ?? this.stepEnabled,
      stepParams: stepParams ?? this.stepParams,
      stepScope: stepScope ?? this.stepScope,
      stepCycle: stepCycle ?? this.stepCycle,
      history: history ?? this.history,
      transientActive: transientActive ?? this.transientActive,
    );
  }
}

/// 倍速控制模型（`player` 域）。
///
/// 职责：
/// - 倍速设置：任意倍率经 [setRate] 驱动内核 [PlaybackEngine.setRate]；
///   历史去重、最近使用在前（上限 [speedHistoryCap]）；
/// - 倍速记忆随舞：[loadForOpen] 是装载入口——读回这支舞的记忆、
///   立即写穿引擎（无记忆即出厂原速 1.0×）、步进归未启用且遍数清零；用户改档
///   （[setRate]）同时写记忆与引擎，步进与瞬态不写记忆；
/// - 倍速步进：参数编辑，启用时内核切到起步倍速；
/// - 互斥（模型级）：设置倍速会停用步进；启用步进后倍速设置不再生效
///   （本模型只保证两者不会同时生效）。
///
/// 步进档位随「激活段循环」推进；纯函数档位数学见 `speed_step.dart`。
class SpeedControlModel extends Notifier<SpeedControlState> {
  @override
  SpeedControlState build() {
    // 激活段循环每完成一圈推进一档（循环遍数事件源）。
    final loopCountSubscription = ref
        .read(learningSegmentLoopCountStreamProvider)
        .listen((_) => unawaited(onSegmentLoopLap()));
    ref.onDispose(loopCountSubscription.cancel);
    // 步进作用于激活段时，激活被取消（进度拖出范围等）即停用步进——
    // 无循环不推进，也不滞留悬空范围。
    ref.listen<LearningSegmentRange?>(selectedLearningSegmentRangeProvider, (
      previous,
      next,
    ) {
      if (next == null &&
          state.stepEnabled &&
          state.stepScope == SpeedStepScope.activeSegment) {
        unawaited(setStepEnabled(false));
      }
    });
    // 倍速历史归设备级：启动恢复 + 记录即落盘；存储不可用
    // 时维持默认会话态，不抛错。
    restoreDone = ref.read(speedHistoryAutoRestoreProvider)
        ? _restoreHistory()
        : Future<void>.value();
    return const SpeedControlState();
  }

  /// 启动恢复是否完成（测试等价「重启后读态」的同步点）。
  late Future<void> restoreDone;

  /// 历史落盘写入串行链（测试等待落盘完成的同步点）。
  Future<void> _flushDone = Future<void>.value();

  /// 最近一次历史落盘写入完成（测试同步点）。
  Future<void> get flushDone => _flushDone;

  bool _historyMutated = false;

  Future<void> _restoreHistory() async {
    var disposed = false;
    ref.onDispose(() => disposed = true);
    try {
      final history = await ref.read(speedHistoryStorageProvider).load();
      // 恢复前用户已记录（启动恢复与首操作的竞态）：以用户态为准。
      if (disposed || _historyMutated || history.isEmpty) return;
      state = state.copyWith(history: history);
    } on Object {
      // 存储不可读：维持默认会话态。
    }
  }

  void _persistHistory() {
    _historyMutated = true;
    _flushDone = _flushDone.then((_) async {
      try {
        await ref.read(speedHistoryStorageProvider).save(state.history);
      } on Object {
        // 写失败不抛到 UI：历史留在会话内。
      }
    });
  }

  PlaybackEngine get _engine => ref.read(playbackEngineProvider);

  /// 开舞装载：随舞记忆的装载入口——读回记忆（[speedRate]，
  /// null = 这支舞没有意见）、立即把引擎倍速写成本舞倍率（无记忆即出厂
  /// 原速 1.0×）、步进归未启用且已完成遍数清零。换会话即清记忆槽：上一支
  /// 舞的记忆不留在下一支舞。
  ///
  /// 打开路径在开播前先以 null 调用一次（无 IO、无等待，引擎不带上一支舞的
  /// 速率起播），读回本地文档后再以记忆值精调——两次写穿是同一入口的先后
  /// 两次调用，不是穿插。录制期（含准备期）遵守录制强制的 1.0×：记忆照读
  /// 进模型，但不写穿引擎，停录后由录制会话恢复到这支舞的倍率。
  Future<void> loadForOpen(double? speedRate) async {
    assert(
      !state.transientActive,
      'loadForOpen: 瞬态倍速（长按 2×）生效期间不允许装载写穿引擎 rate',
    );
    final memory = speedRate == null ? null : _clampRate(speedRate);
    state = state.copyWith(
      manualRate: memory ?? 1.0,
      memoryRate: memory,
      clearMemory: memory == null,
      stepEnabled: false,
      stepCycle: 0,
    );
    if (_recordingLocksRate) return;
    await _engine.setRate(memory ?? 1.0);
  }

  /// 观看面瞬态倍速（长按 2×）：开始即快照引擎当前倍速并切到
  /// [rate]；[endTransientRate] 恢复到快照。瞬态期间其它写穿路径（手动
  /// [setRate] / [setStepEnabled] / 步进推进）若发生即为编程错误（debug
  /// assert）——引擎 rate 从此只有一个写者（本模型）。
  ///
  /// 仅当引擎**正在播放**才生效；暂停/未播为无副作用 no-op（沿用原
  /// `LongPressDoubleSpeedController.tryBegin` 语义，行为零变化）。begin
  /// 未 end 再 begin = debug assert。不写手动值/步进档位/历史——松开恢复的
  /// 正是进入瞬态那一刻的引擎倍速。
  Future<void> beginTransientRate(double rate) async {
    assert(
      !state.transientActive,
      'beginTransientRate: 上一瞬态倍速尚未结束（begin 未 end 再 begin）',
    );
    if (_recordingLocksRate) return;
    if (!_engine.isPlaying) return;
    _transientRestoreRate = _engine.rate;
    state = state.copyWith(transientActive: true);
    await _engine.setRate(_clampRate(rate));
  }

  /// 结束瞬态倍速（松开 / 指针取消 / 离开页收尾）：恢复到进入瞬态那一刻的
  /// 引擎倍速并退出生效态。未在瞬态时无副作用（幂等）。
  ///
  /// 录制期：**收尾同样上锁**——瞬态 2× 若在起录
  /// 前生效（多指同时操作可达），松手时把速率写回瞬态前基准会穿透录制强制的
  /// 1.0×（[beginTransientRate]/[setRate] 那几道写穿门都拦不住这条收尾路）。
  /// 停录后的「原倍速」由录制会话自己的快照恢复。
  Future<void> endTransientRate() async {
    if (!state.transientActive) return;
    state = state.copyWith(transientActive: false);
    if (_recordingLocksRate) return;
    await _engine.setRate(_transientRestoreRate);
  }

  /// 进入瞬态那一刻的引擎倍速（[endTransientRate] 要恢复的基准）。
  double _transientRestoreRate = 1.0;

  /// 对比-录制进行中：录制强制 1.0×，倍速设置与倍速步进临时
  /// 失效——一切写穿入口静默 no-op，停录后由录制会话恢复原倍速。
  bool get _recordingLocksRate =>
      ref.read(compareRecordingPhaseProvider) != CompareRecordingPhase.idle;

  /// 设置手动倍率（钳制范围、两位小数），并停用步进（互斥）。
  ///
  /// 不记历史：历史改「气泡打开快照 → 关闭时若
  /// 最终倍速相对快照变化才记一次」，由 UI 在关闭点调用 [recordHistory]。
  Future<void> setRate(double rate) async {
    assert(
      !state.transientActive,
      'setRate: 瞬态倍速（长按 2×）生效期间不允许手动写穿引擎 rate',
    );
    if (_recordingLocksRate) return; // 录制中强制 1.0×。
    final clamped = _clampRate(rate);
    state = state.copyWith(
      manualRate: clamped,
      memoryRate: clamped,
      stepEnabled: false,
    );
    await _engine.setRate(clamped);
  }

  /// 记一次历史倍速（「记历史」纯语义对 UI 暴露的唯一入口）：
  /// 钳制两位小数后登记，去重、最近在前、上限 [speedHistoryCap]。
  /// 同步完成（无内核调用）——气泡会话在 close/open 的下一行即读快照，
  /// 不允许 fire-and-forget 时序缝隙。
  void recordHistory(double rate) {
    final clamped = _clampRate(rate);
    if (state.history.isNotEmpty && state.history.first == clamped) return;
    state = state.copyWith(history: _recordHistory(state.history, clamped));
    _persistHistory();
  }

  /// 启用/停用倍速步进。启用时内核切到当前档位（新启用从首档 a 起步）并
  /// 记录作用范围 [scope]；停用后回到手动倍率。
  Future<void> setStepEnabled(
    bool enabled, {
    SpeedStepScope scope = SpeedStepScope.activeSegment,
  }) async {
    assert(
      !state.transientActive,
      'setStepEnabled: 瞬态倍速（长按 2×）生效期间不允许步进写穿引擎 rate',
    );
    if (_recordingLocksRate) {
      // 录制中强制 1.0×：不写穿引擎倍速。停用步进另当别论——它是纯状态
      // 收敛（删除正在生效的预设时不许留一条已不存在的参数继续「生效」），
      // 故照常落状态，停录后由录制会话恢复原倍速。
      if (enabled || !state.stepEnabled) return;
      state = state.copyWith(stepEnabled: false, stepCycle: 0);
      return;
    }
    if (enabled) {
      state = state.copyWith(stepEnabled: true, stepScope: scope, stepCycle: 0);
    } else {
      if (!state.stepEnabled) return;
      state = state.copyWith(stepEnabled: false, stepCycle: 0);
    }
    await _engine.setRate(state.effectiveRate);
  }

  /// 激活段循环每完成一圈（区间循环薄层事件）：步进作用于激活段时推进一档。
  Future<void> onSegmentLoopLap() => _advanceStep(SpeedStepScope.activeSegment);

  /// 全片自动循环每开始一圈（视频尾循环提示）：步进作用于全片时
  /// 推进一档（无循环不推进——「不循环」后本事件不再发生）。
  Future<void> onWholeVideoLoop() => _advanceStep(SpeedStepScope.wholeVideo);

  /// 推进一档：仅当步进启用且事件来源与作用范围一致时生效；档位经既有
  /// [rateForStepCycle]（每 c 遍升一档、至 b 回 a）。
  Future<void> _advanceStep(SpeedStepScope source) async {
    assert(
      !state.transientActive,
      '_advanceStep: 瞬态倍速（长按 2×）生效期间不允许步进推进写穿引擎 rate',
    );
    if (_recordingLocksRate) return; // 录制中强制 1.0×。
    if (!state.stepEnabled || state.stepScope != source) return;
    state = state.copyWith(stepCycle: state.stepCycle + 1);
    await _engine.setRate(state.effectiveRate);
  }

  /// 更新步进参数；非法参数忽略并保持原值。参数变化后从首档 a 重新起步。
  Future<void> updateStepParams(SpeedStepParams params) async {
    assert(
      !state.transientActive,
      'updateStepParams: 瞬态倍速（长按 2×）生效期间不允许步进参数写穿引擎 rate',
    );
    if (!params.isValid || params == state.stepParams) return;
    if (_recordingLocksRate) return; // 录制中强制 1.0×。
    state = state.copyWith(stepParams: params, stepCycle: 0);
    if (state.stepEnabled) {
      await _engine.setRate(state.effectiveRate);
    }
  }

  /// 历史登记：去重（同值移到最前）、最近使用在前、截断到 [speedHistoryCap]。
  List<double> _recordHistory(List<double> history, double rate) {
    final updated = <double>[rate, ...history.where((r) => r != rate)];
    return List.unmodifiable(
      updated.length > speedHistoryCap
          ? updated.sublist(0, speedHistoryCap)
          : updated,
    );
  }

  double _clampRate(double rate) {
    final rounded = roundRate(rate);
    return math.min(speedRateMax, math.max(speedRateMin, rounded));
  }
}

/// 倍速控制注入点；测试经 `playbackEngineProvider` 注入
/// FakeEngine 后直接驱动本模型。
final speedControlProvider =
    NotifierProvider<SpeedControlModel, SpeedControlState>(
      SpeedControlModel.new,
    );
