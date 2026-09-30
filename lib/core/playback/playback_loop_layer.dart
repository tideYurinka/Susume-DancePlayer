import 'dart:async';

import 'playback_engine.dart';

/// AB/区间循环薄层。
///
/// ADR-0001：五款候选播放器均无区间循环原生支持，故在播放器之上自建薄层——
/// 监听 [PlaybackEngine.positionStream]，播放 position 到达 B 点时帧级
/// seek 回 A 点。本层不依赖具体内核，任何 [PlaybackEngine]
/// （含 FakeEngine）均可驱动。
///
/// 纯逻辑、可单测；激活段与循环触发 UI 在消费侧。
///
/// 「循环前导」：每圈到 B 后 seek 到
/// 「段首 − [updateDelayedLoopWait] 前导时长」处**连续播放**（不暂停），
/// 段首前 N 拍播动作前导；进入段首前导态结束，到段尾再 seek 回前导起点。
/// 前导期间手动 seek 出前导区/停用/换段取消剩余前导；与整片「循环提示」
/// 路径（LoopPrompt）完全隔离。
class PlaybackLoopLayer {
  PlaybackLoopLayer(this._engine) {
    _positionSubscription = _engine.positionStream.listen(_onPosition);
  }

  final PlaybackEngine _engine;

  StreamSubscription<Duration>? _positionSubscription;

  final StreamController<int> _loopCountController =
      StreamController<int>.broadcast();

  /// 每完成一圈循环发出的递增遍数事件（倍速步进消费）。
  Stream<int> get loopCountStream => _loopCountController.stream;

  final StreamController<bool> _delayedLoopController =
      StreamController<bool>.broadcast();

  /// 循环前导态事件源：true = 本圈到段尾、正在段首前播动作
  /// 前导；false = 已进入段首或前导被打断。UI 据此驱动前导节拍声等。
  Stream<bool> get delayedLoopActiveStream => _delayedLoopController.stream;

  /// 当前是否处于循环前导（段首前 N 拍动作前导播放）中。
  bool get delayedLoopActive => _delayedLoopActive;

  /// 当前循环遍数（从 0 起，每回到 A 点 +1）。
  int get loopCount => _loopCount;

  int _loopCount = 0;

  /// 每圈段首前的动作前导时长（会话设置换算而来）；零 = 不前导
  /// （到 B 立即回段首）。
  Duration _delayedLoopWait = Duration.zero;

  bool _delayedLoopActive = false;

  /// 回前导起点的帧级 seek 是否在途；真实内核 position 可能仍停留在 B 点
  /// 并继续发 tick，在途期间忽略后续 tick，避免一圈被 seek/计数多次。
  bool _loopSeekInFlight = false;

  /// 是否已观察到播放位置进入当前循环作用域 `[leadStart, b)`（含前导区）。
  ///
  /// 启用循环时进度可能仍在旧位置（≥ b），激活段的段首 seek 也在串行队列
  /// 中；必须等 seek 落到作用域内才开始计圈，避免“启用即假循环”。
  bool _enteredLoopRange = false;

  /// 区间 [a, b)；未启用时为 null。
  ({Duration a, Duration b})? _bounds;

  bool get enabled => _bounds != null;

  /// 前导起点：max(a − 前导时长, 0)（段首前余量不足时钳到视频 0 处）。
  Duration _leadStart(({Duration a, Duration b}) bounds) {
    final lead = bounds.a - _delayedLoopWait;
    return lead < Duration.zero ? Duration.zero : lead;
  }

  /// 更新每圈段首前的动作前导时长；零 = 不前导（现状立即回段首）。
  ///
  /// 前导在途中改为零：立即结束本圈前导态，按既有播放继续（下一圈到段尾
  /// 直接回段首）。
  void updateDelayedLoopWait(Duration wait) {
    _delayedLoopWait = wait;
    if (_delayedLoopActive && wait <= Duration.zero) {
      _setLeadActive(false);
    }
  }

  /// 启用 [a, b) 区间循环：position 到达 b 时 seek 回前导起点连续播放。
  ///
  /// [a] 必须小于 [b]；a >= b 视为未启用（不抛错，静默忽略）。
  /// 换段（重新启用）取消在途前导态。
  void enableLoop({required Duration a, required Duration b}) {
    _setLeadActive(false);
    final bounds = a < b ? (a: a, b: b) : null;
    _bounds = bounds;
    _loopCount = 0;
    _loopSeekInFlight = false;
    _lastObservedPosition = _engine.position;
    _enteredLoopRange =
        bounds != null &&
        _engine.position >= _leadStart(bounds) &&
        _engine.position < bounds.b;
  }

  /// 停用区间循环（激活清除/几何变化/手动 seek 出范围的打断路径均经此处
  /// 收口）；取消在途前导态。
  void disableLoop() {
    _setLeadActive(false);
    _bounds = null;
  }

  /// 最近一次观察到的播放位置（短段 tick 跨越判定用）。
  Duration? _lastObservedPosition;

  /// 「下一条越过 B 的 tick 视为已进入区间」允许的最大位置跳变：
  /// 仅覆盖单 tick 推进（100ms × ≤3 倍速），手动 seek 的大步长不算。
  static const Duration _maxTickJump = Duration(milliseconds: 300);

  /// 前导期内位置容差（帧级残余 tick，30fps 帧长约 33ms，取 50ms 覆盖）：
  /// 明显跳出 `[leadStart − 容差, b)` 才是手动 seek 打断前导。
  static const Duration _leadPointTolerance = Duration(milliseconds: 50);

  void _onPosition(Duration position) {
    final bounds = _bounds;
    if (bounds == null) return;
    final previous = _lastObservedPosition;
    _lastObservedPosition = position;
    if (_delayedLoopActive) {
      _onLeadPosition(bounds, position);
      return;
    }
    if (_loopSeekInFlight) return;
    if (!_enteredLoopRange) {
      if (position >= bounds.a && position < bounds.b) {
        _enteredLoopRange = true;
      } else if (_engine.isPlaying &&
          position >= bounds.b &&
          previous != null &&
          previous < bounds.b &&
          position - previous <= _maxTickJump) {
        // 短学习段死路径：tick 间隔 ≥ 段长时没有任何 tick 落在
        // [a,b) 内，「已进入区间」标记永不置真。下一条越过 B 的 tick
        // 视为已进入；跳变超过单 tick 推进的手动 seek 不算。
        _enteredLoopRange = true;
      }
      if (!_enteredLoopRange) return;
    }
    if (position >= bounds.b) {
      _triggerLoop(bounds);
    }
  }

  /// 前导期内位置处理：播过段首前导态结束；明显跳出前导区（早于前导起点
  /// 或越过段尾）是手动 seek 打断——取消前导态并按出范围重置「已进入」
  /// 标记（循环由宿主重新激活/位置回段内后再计），引擎保持播放不停住。
  void _onLeadPosition(({Duration a, Duration b}) bounds, Duration position) {
    if (position >= bounds.a && position < bounds.b) {
      _setLeadActive(false);
      return;
    }
    final leadStart = _leadStart(bounds);
    if (position < leadStart - _leadPointTolerance || position >= bounds.b) {
      _enteredLoopRange = false;
      _setLeadActive(false);
    }
  }

  /// 本圈到段尾：seek 回前导起点连续播放（前导时长为零直接回段首）。
  ///
  /// 前导态在 seek 落定后发布（宿主据此起节拍声等）；seek 在途期间残余
  /// 位置 tick 经 [_loopSeekInFlight] 屏蔽，一圈只计一次。
  void _triggerLoop(({Duration a, Duration b}) bounds) {
    _loopCount++;
    _loopCountController.add(_loopCount);
    _loopSeekInFlight = true;
    final target = _leadStart(bounds);
    unawaited(
      _engine.seek(target).whenComplete(() {
        _loopSeekInFlight = false;
        // seek 在途换段/停用（_bounds 变更）：不按陈旧区间进前导。
        if (!identical(_bounds, bounds)) return;
        _setLeadActive(_delayedLoopWait > Duration.zero);
      }),
    );
  }

  void _setLeadActive(bool active) {
    if (_delayedLoopActive == active) return;
    _delayedLoopActive = active;
    _delayedLoopController.add(active);
  }

  /// 释放本层资源（取消 position 订阅）；不释放底层引擎。
  Future<void> dispose() async {
    _setLeadActive(false);
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _loopCountController.close();
    await _delayedLoopController.close();
  }
}
