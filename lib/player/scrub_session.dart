/// ScrubSession：player↔blank 共用的 scrub 生命周期状态机。
///
/// 把两处同构的「暂停-基准-累计-恢复、取消回退」收进一件：水平拖动定格
/// 预览（player 全屏手势）与空白面微调三件套共用同一实现——引擎只经注入
/// 闭包触碰（plain class + 注入闭包，沿 [SeekSubmitter]/
/// CrossSurfacePinchSession 先例；逐帧态不跨层共享）；
/// 模块不进 Riverpod、不持 Ref，可在无 ProviderScope 下直测。
///
/// 核心不变量：
///
/// - **pause 先于任何 seek**：在播起手先 `await pause` 定格，才有基准快照
///   与逐帧 seek（FakeEngine callLog 断言序，同款）；
/// - **基准 = 定格点快照**：非手指按下点——在播时从按下到轴锁定之间位置
///   仍随播放推进，回退到定格点才等于「这次拖动没发生过」；
/// - **begin/end 幂等**；end 在 !isActive 时 no-op；
/// - **cancel 回退单发**：经 [SeekSubmitter.submit] 的 latest-wins 串行队列
///   只发一次（在途 seek 未完成则回退目标成为最终待发值），不写 indicator
///   （player 面回退后守卫目标仍读指示位，见下）；
/// - **恢复守卫统一读注入守卫**：宿主闭包各自消费 effective 派生时间线
///   （player/blank 手势必发生于时间线初始化后，raw 与 effective 同值，
///   行为不变的收敛）；null = 不守卫；
/// - **取消区几何判定留在宿主**：宿主持有手指焦点坐标，本件只接收
///   cancel 布尔；cancelZoneEnabled=false 时 cancel 无害（blank 无取消角）。
///
/// 本件**不再回报「我暂停/续播了」**——那个回报的全部用途是让宿主
/// 同步它自己那份播放态 UI 副本，而播放态已收归引擎单一真源（指示与控制层
/// 播放键直读引擎 `PlaybackEngine.isPlaying`，重建由播放页的播放态边沿订阅
/// 触发）。相位仍经注入的 `feedback` 对外可见。
///
/// band 不用本件（band 越出有效区间暂停为 live-absolute 语义，留在带内）。
library;

import 'package:flutter/foundation.dart';

import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/core/playback/seek_submitter.dart';

/// scrub 会话（player 定格预览 / blank 微调共用）。
class ScrubSession {
  ScrubSession({
    required this.seek,
    required Future<void> Function() pause,
    required Future<void> Function() play,
    required this.isPlaying,
    required this.position,
    this.resumeRange,
    this.onCommit,
    this.feedback,
    this.indicator,
    this.cancelZoneEnabled = false,
    this.requireKnownDuration = true,
  }) : _pauseEngine = pause,
       _playEngine = play;

  /// 每帧落点走 [SeekSubmitter] 实例（内部 seam）：钳制、清循环
  /// 激活、串行入队、显示位/窗口跟随固定次序由它收口，本件不重复实现。
  final SeekSubmitter seek;

  final Future<void> Function() _pauseEngine;
  final Future<void> Function() _playEngine;

  /// 引擎当前播放态（begin 时捕获为 wasPlaying，end 时据此恢复）。
  final bool Function() isPlaying;

  /// 引擎当前位置（begin 在 pause 之后读取一次，作为基准快照）。
  final Duration Function() position;

  /// 恢复守卫：目标界内才续播（null = 不守卫）。宿主闭包读 effective 派生
  /// 时间线/时长。
  final bool Function(Duration target)? resumeRange;

  /// 会话收口落点回报：非取消收口时以最终落点（indicator 值或
  /// 基准）回调一次——宿主据此打「显式用户拖进度」放行标记；取消回退不
  /// 回报（落点未生效）。null = 不回报。
  final void Function(Duration target)? onCommit;

  /// 手势反馈相位（scrubbing 浮层）；null = 宿主自管相位。
  final GestureFeedbackController? feedback;

  /// 显示用指示浮层目标位（观看态 _scrubTarget）：begin 写基准、moveBy 写
  /// 入队值；end 守卫目标也读它（与入队 seek 同源，串行 seek 期间不滞后读
  /// 引擎 position）。null = 无显示浮层，目标由本件内部 [_target] 跟踪
  /// （编辑态微调不显示浮层）。
  final ValueNotifier<Duration>? indicator;

  /// 是否启用取消回退（player true、blank false——blank 无取消角）。
  final bool cancelZoneEnabled;

  /// begin 是否要求时长已知（false = 时长未知也照常起会话）。blank true
  /// （现状：时长未知静默不起会话）；player false（现状：时长未知时 scrub
  /// 照常工作，钳制交由 [SeekSubmitter] 的 ≥0 分支，见
  /// player_page_test 时长未知）。
  final bool requireKnownDuration;

  /// 会话激活标记（宿主收尾/防御复位只读）。
  bool get isActive => _active;
  bool _active = false;

  /// begin 时引擎是否在播（end 据此恢复）。
  bool _wasPlaying = false;

  /// 定格点基准快照与就绪标记（moveBy 在基准未定时丢弃本帧）。
  Duration _base = Duration.zero;
  bool _baseReady = false;

  /// 累计增量（每帧由宿主换算灵敏度后传入）。
  Duration _accumulated = Duration.zero;

  /// 会话内部目标跟踪（begin 写基准、moveBy 写入队值）：end 收口落点 = 指示
  /// 位（有显示时）或 [_target]（无显示时），二者与入队 seek 同源。
  Duration _target = Duration.zero;

  /// 开始会话（幂等）：active 置位 → feedback.beginScrubbing() → 在播先
  /// await pause（**pause 先于任何 seek**）→ 基准 = 定格点快照 →
  /// indicator = 基准。返回 false = 时长未知（同现状静默：不进相位、不
  /// 暂停、不 seek）；已激活时幂等返回 true。
  Future<bool> begin() async {
    if (_active) return true;
    final total = seek.total?.call();
    if (requireKnownDuration && (total == null || total <= Duration.zero)) {
      return false;
    }
    _active = true;
    _baseReady = false;
    _accumulated = Duration.zero;
    _wasPlaying = isPlaying();
    feedback?.beginScrubbing();
    if (_wasPlaying) {
      await _pauseEngine();
    }
    _base = position();
    _baseReady = true;
    _target = _base;
    indicator?.value = _base;
    return true;
  }

  /// 逐帧推进：目标 = 基准 + 累计、钳 [0, total]（钳制经 [seek.submit]），
  /// 经 seek.submit 落点并同步 indicator；begin 未完成（基准未定）时丢弃
  /// 本帧。delta 允许为 0（blank 零位移帧照常重提交，靠 submitter 节流折
  /// 叠；player 面零步长在宿主侧跳过）。
  void moveBy(Duration delta) {
    if (!_active || !_baseReady) return;
    _accumulated += delta;
    _target = seek.submit(_base + _accumulated);
    indicator?.value = _target;
  }

  /// 结束会话（幂等）：[cancel]=true 且 cancelZoneEnabled 时先单发基准回
  /// 退（latest-wins 收敛到快照点，不写 indicator），再按恢复守卫续播
  /// （wasPlaying && 界内才 play，界外为暂停查看态）；随后结束反馈相位。
  /// !isActive 时 no-op。
  Future<void> end({bool cancel = false}) async {
    if (!_active) return;
    _active = false;
    final wasPlaying = _wasPlaying;
    _wasPlaying = false;
    _baseReady = false;
    feedback?.setCancelArmed(false);
    if (cancel && cancelZoneEnabled) {
      seek.submit(_base); // 取消：回退只发一次（latest-wins 收敛到定格点）。
    }
    // 收口落点单源 [_target]（indicator 只是显示镜像，与本件同写同值）。
    final target = _target;
    if (!cancel) onCommit?.call(target);
    final guard = resumeRange;
    if (wasPlaying && (guard == null || guard(target))) {
      await _playEngine();
    }
    feedback?.endScrubbing();
  }
}
