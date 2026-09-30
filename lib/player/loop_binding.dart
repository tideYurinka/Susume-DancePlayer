/// 学习段循环接线：激活范围变化到区间循环作用域
/// 的那段编排——循环层作用域起停、循环提示的区间语义、激活即起播的
/// seek-then-play 序号机、片段循环前导取值，以及循环层两条事件流（每圈跳回、
/// 循环前导激活）的收尾接线都自持在这里。
///
/// 契约：构造收显式依赖（引擎与 seek 域、循环层、循环提示、对比录制与练习
/// 片段前导取值闭包），不读容器、不读构建上下文；跨帧状态（激活起播序号）
/// 自持在本对象。宿主只把 provider 变化接到它的入口，不再自己编排。
///
/// 依赖方向（单向）：本域 → 引擎/seek 域、循环层（core）、循环提示、对比录制
/// 与延迟播放域；被依赖的模块都不 import 本域，本域也不 import
/// 播放页与中枢。
library;

import 'dart:async';

import '../annotation/annotation_timeline.dart' show AnnotationTimeline;
import '../annotation/segment_selection.dart' show LearningSegmentRange;
import '../core/playback/playback_loop_layer.dart' show PlaybackLoopLayer;
import 'delayed_play.dart' show DelayedPlayController;
import 'engine_seek.dart' show EngineSeek;
import 'loop_prompt.dart' show LoopPromptController;

/// 循环范围记录投影：本域收记录形、不依赖标注库的选中类型，消费方把
/// provider 值经本函数投影成同一形状（null 透传）。
({Duration start, Duration end})? loopRangeRecord(
  LearningSegmentRange? range,
) => range == null ? null : (start: range.start, end: range.end);

/// 学习段循环接线（会话域：无 widget）。
class LoopBinding {
  LoopBinding({
    required this.engineSeek,
    required this.loopLayer,
    required this.loopPrompt,
    required this.delayedPlay,
    required this.effectiveLoopWaitOf,
    required this.delayedLoopWaitOf,
    required this.isMounted,
    required this.onDelayedLoopActive,
  });

  /// 引擎与 seek/scrub 域（激活即起播的 seek-then-play）。
  final EngineSeek engineSeek;

  /// 播放循环层（区间作用域与前导时长的唯一写面）。
  final PlaybackLoopLayer loopLayer;

  /// 循环提示（区间语义接管尾点）。
  final LoopPromptController loopPrompt;

  /// 延迟播放（每圈跳回打断在途延迟起播）。
  final DelayedPlayController delayedPlay;

  /// 片段循环前导取值（对比录制域按在屏播放源给出：片段回放期间归零、
  /// 其余时间用现拍档）。
  final Duration Function(Duration setting) effectiveLoopWaitOf;

  /// 当前循环前导拍档（设备级设置读数）。
  final Duration Function() delayedLoopWaitOf;
  final bool Function() isMounted;
  final void Function() onDelayedLoopActive;

  StreamSubscription<int>? _loopCountSubscription;
  StreamSubscription<bool>? _delayedLoopStateSubscription;

  /// 激活起播序号：每次循环范围接线自增，在途 seek 落定后只在
  /// 序号仍是当前值时起播。latest-wins 由结构保证而不靠「别连着点」的时序
  /// 纪律：[EngineSeek.seekAndSettle] 的完成语义是「该目标或其后
  /// 更晚目标已发往引擎」，故被取代的旧 waiter 也会被唤醒，此时序号已变——
  /// 取消激活/拖出区间/改激活别的段之后，在途的那次起播不得再把画面翻回
  /// 播放态。
  int _activationEpoch = 0;
  bool _disposed = false;

  /// 循环层两条事件流接线：每圈跳回打断在途延迟起播；循环前导激活时重驱
  /// 节拍。重复调用幂等。
  void attach() {
    if (_disposed) return;
    _loopCountSubscription ??= loopLayer.loopCountStream.listen((_) {
      delayedPlay.interrupt();
    });
    _delayedLoopStateSubscription ??= loopLayer.delayedLoopActiveStream.listen((
      active,
    ) {
      if (active) onDelayedLoopActive();
    });
  }

  /// 片段循环不套循环前导：把对比录制域给出的有效前导写进循环层
  /// （片段回放期间归零、其余时间用现拍档）。
  void syncClipLoopWait() {
    loopLayer.updateDelayedLoopWait(effectiveLoopWaitOf(delayedLoopWaitOf()));
  }

  /// 激活范围变化同步到区间循环：合并范围起点 = 段首、终点 = 段尾。
  ///
  /// [activate] = true（点选激活/扩展/收缩）跳到新范围段首**落定之后**立即
  /// 起播；[activate] = false（打开恢复、录制回退待录态）只就位循环作用域——
  /// 不跳转、不自动播。范围为空时停用区间循环并按 [segmentLoopActive] 决定
  /// 循环提示的语义（[timeline] 为当时的生效时间线）。
  void syncLearningSegment(
    ({Duration start, Duration end})? range, {
    bool activate = true,
    required AnnotationTimeline timeline,
    required bool segmentLoopActive,
  }) {
    // 激活态一变即作废旧序号：在途的「seek 落定后起播」不得再翻播放态。
    final epoch = ++_activationEpoch;
    if (range == null) {
      loopLayer.disableLoop();
      loopPrompt.syncToTimeline(timeline, segmentLoopActive: segmentLoopActive);
      return;
    }
    loopPrompt.setSegmentLoopActive(true);
    loopLayer.enableLoop(a: range.start, b: range.end);
    if (activate) {
      unawaited(_seekThenPlay(range.start, epoch));
    }
  }

  /// 激活即起播：跳区间首的 seek 落定之后起播——顺序颠倒会在段首之外先播
  /// 几帧，且让「已进入区间」的判定拿到段外位置事件。
  Future<void> _seekThenPlay(Duration start, int epoch) async {
    await engineSeek.seekAndSettle(start);
    if (!isMounted() || epoch != _activationEpoch) return;
    await engineSeek.play();
  }

  void dispose() {
    _disposed = true;
    _loopCountSubscription?.cancel();
    _loopCountSubscription = null;
    _delayedLoopStateSubscription?.cancel();
    _delayedLoopStateSubscription = null;
  }
}
