/// 串行 seek 队列（latest-wins）：一次只在途一个 seek。
///
/// 真机诊断：快速连续 seek 的突发会被 mpv 丢弃（只生效首条，进度几乎不动），
/// 故拖动/回退等高频 seek 走本队列串行化——在途 seek 未完成时新目标只更新
/// 待发值，完成后只发最新目标；手势结束自然收敛到最终目标。player_page
/// （播放手势 scrubbing）与轨道带预览条拖动共用同一套串行化语义。
///
///  **按帧节流**（[minInterval]）：拖动期间引擎 seek 按帧间隔发出
/// （默认 16ms ≈ 60fps 一帧），间隔内的过密中间目标直接丢弃（latest-wins
/// 折叠，只发最新）；首个 seek 立即发出，松手后最终目标必达（收敛语义
/// 不变）。时钟与延时可注入（测试确定性断言节流时序）。
library;

import 'dart:async';

/// 拖动 seek 的默认节流间隔（约一帧 @60fps；轨道带预览条拖动使用）。
const Duration kScrubSeekMinInterval = Duration(milliseconds: 16);

/// 串行 latest-wins seek 队列：把 [enqueue] 的目标经 [_seek] 一次一个地发往
/// 引擎；在途期间到达的新目标折叠为待发值（只发最新）。
class SerialSeekQueue {
  SerialSeekQueue(
    this._seek, {
    this.minInterval = Duration.zero,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future.delayed;

  /// 实际 seek 动作（通常 = 引擎 seek；测试可注入可控 fake 断言串行性）。
  final Future<void> Function(Duration target) _seek;

  /// 相邻两次实际 seek 的最小间隔（节流窗口）；[Duration.zero] = 不节流
  /// （player_page 播放手势等既有消费方行为保持不变）。
  final Duration minInterval;

  /// 时钟（节流间隔测量用；默认墙钟，测试可注入假时钟）。
  final DateTime Function() _clock;

  /// 延时原语（节流等待用；默认 [Future.delayed]，测试可注入受控 future）。
  final Future<void> Function(Duration delay) _delay;

  /// 待发目标（latest-wins：在途期间只保留最新一个）。
  Duration? _pending;

  /// 是否已有排空循环在途（一次只在途一个 seek）。
  bool _inFlight = false;

  /// 上次实际 seek 的**完成**时刻（null = 尚未发过）。节流自上一条完成起
  /// 计——引擎 seek 本身的耗时天然计入间隔（慢引擎不会背靠背连发，快引擎
  /// 由墙钟间隔兜底），与文档「相邻两次实际 seek 的最小间隔」一致。
  DateTime? _lastDispatchAt;

  /// [enqueueAndWait] 的排空等待者（[_drain] 循环退出时统一完成）。
  final List<Completer<void>> _waiters = <Completer<void>>[];

  /// 入队 [target] 并返回它（调用侧可与指示 UI 同源消费入队值，无需关心
  /// 串行化中间态）。返回类型保留调用侧「钳制后实际入队值」用法。
  Duration enqueue(Duration target) {
    _pending = target;
    if (!_inFlight) {
      _inFlight = true;
      unawaited(_drain());
    }
    return target;
  }

  /// 入队 [target] 并等待队列排空（该目标或其后到达的更晚目标已实际发往
  /// 引擎）后完成——「恢复 seek 落定后再续播」类顺序语义用（拖线
  /// 实时预览收尾）。纯等待语义：不改变 latest-wins 折叠与节流行为。
  Future<void> enqueueAndWait(Duration target) {
    enqueue(target);
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final last = _lastDispatchAt;
        if (last != null && minInterval > Duration.zero) {
          final remaining = minInterval - _clock().difference(last);
          if (remaining > Duration.zero) {
            // 节流窗口内：等待（等待期间新目标继续折叠为最新）。
            await _delay(remaining);
          }
        }
        final next = _pending!;
        _pending = null;
        await _seek(next);
        _lastDispatchAt = _clock();
      }
    } finally {
      _inFlight = false;
      if (_waiters.isNotEmpty) {
        final waiters = List.of(_waiters);
        _waiters.clear();
        for (final waiter in waiters) {
          waiter.complete();
        }
      }
    }
  }
}
