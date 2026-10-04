/// SeekSubmitter：seek 的唯一提交口。
///
/// 一次调用把「进度目标」写齐三站：钳制 → 清循环激活（宿主绑 ref 的完整
/// helper，恒含临时衔接段）→ 串行入队 → 预览显示位。内部固定次序保证两条
/// 不变量成为结构性保证：
///
/// - **清循环先于入队**：目标越出生效循环范围时先取消激活（真实学习段 +
///   临时衔接段同一判定），避免区间循环层下一 tick 把进度拽回段首；
/// - **显示与 seek 同源**：displayHead 写入的是钳制后实际入队值，预览画面
///   与实际 seek 位置一致。
///
/// **不写窗口**：窗口跟随是编辑态会话域在
/// 位置 tick 上的唯一一处求值，提交口只写预览线显示值。
///
/// 内部持有一只 [SerialSeekQueue]（latest-wins + 按帧节流，实例与类保留为
/// 内部 seam，serial_seek_test 不废）；clock/delay 透传供测试注入假时钟。
/// 无抛错路径：任何目标提交都不抛出。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../annotation/annotation_timeline.dart';
import 'serial_seek.dart';

/// seek 尾段提交器：单发与逐帧同入口的 [submit] + 等队列排空的
/// [submitAndSettle]。由宿主 State 装配（plain class + 注入闭包，沿
/// SerialSeekQueue/CrossSurfacePinchSession 先例；逐帧态不跨层共享）。
class SeekSubmitter {
  SeekSubmitter({
    required Future<void> Function(Duration target) engineSeek,
    this.minInterval = Duration.zero,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? delay,
    this.total,
    required this.timeline,
    required this.clearLoops,
    this.displayHead,
  }) : _queue = SerialSeekQueue(
         engineSeek,
         minInterval: minInterval,
         clock: clock,
         delay: delay,
       );

  /// 相邻两次实际 seek 的最小间隔（节流窗口）：player 传 [Duration.zero]
  /// （不节流），blank/band 传 [kScrubSeekMinInterval]（约一帧）。
  final Duration minInterval;

  /// 引擎总时长（null = 时长未知：不钳上界）；≤0 同未知分支。
  final Duration? Function()? total;

  /// 统一读 effective 派生的时间线（供清循环判定消费）。
  final AnnotationTimeline Function() timeline;

  /// 宿主绑 ref 的完整清循环 helper（`clearLoopActivationsIfOutside`，
  /// 真实段 + 临时衔接段恒含）；本类是各面唯一调用位。
  final void Function(AnnotationTimeline timeline, Duration position)
  clearLoops;

  /// 预览显示位（blank/band 的拖动目标显示值）；null = 宿主自管（player
  /// 经返回值同源消费 _scrubTarget）。
  final ValueNotifier<Duration>? displayHead;

  /// 内部串行 seek 队列（latest-wins + 按帧节流；内部 seam）。
  final SerialSeekQueue _queue;

  /// 钳制 [target]：时长已知 → 钳到 `[0, total]`；未知/≤0 → 只钳 ≥0。
  Duration _clamp(Duration target) {
    if (target < Duration.zero) return Duration.zero;
    final total = this.total?.call();
    if (total == null || total <= Duration.zero) return target;
    if (target > total) return total;
    return target;
  }

  /// 单发 + 逐帧同入口：返回钳制后实际入队值。内部固定次序：钳制 →
  /// clearLoops(timeline(), t) → 入队 → displayHead?.value = 落点；
  /// 清循环先于入队；无抛错路径。
  ///
  /// [writeDisplay] = false：**只入队**，跳过显示位——拖线实时预览用
  /// （预览线显示值不随动）。
  Duration submit(Duration target, {bool writeDisplay = true}) {
    final clamped = _clamp(target);
    clearLoops(timeline(), clamped);
    final enqueued = _queue.enqueue(clamped);
    if (writeDisplay) _writeDisplay(enqueued);
    return enqueued;
  }

  /// 单发并等待队列排空（[SerialSeekQueue.enqueueAndWait] 语义）：该目标
  /// 或其后到达的更晚目标已实际发往引擎后完成——「seek 落定后再续播」类
  /// 顺序语义用（拖线预览收尾）。钳制与清循环次序同 [submit]；显示
  /// 位在队列排空后写入（当前消费方拖线恢复不传 displayHead，无时序差异）；
  /// [writeDisplay] 语义同 [submit]。
  Future<void> submitAndSettle(
    Duration target, {
    bool writeDisplay = true,
  }) async {
    final clamped = _clamp(target);
    clearLoops(timeline(), clamped);
    await _queue.enqueueAndWait(clamped);
    if (writeDisplay) _writeDisplay(clamped);
  }

  /// 写预览显示位。
  void _writeDisplay(Duration landed) {
    displayHead?.value = landed;
  }
}
