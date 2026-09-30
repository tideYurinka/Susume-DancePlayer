import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/beat_grid.dart';
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../core/playback/playback_engine.dart';

/// 延迟播放阶段。
enum DelayedPlayPhase {
  /// 无延迟播放。
  idle,

  /// 预备播放中：已倒回起点前 N 拍连续播，尚未越过起点。
  preparing,

  /// 已越过起点：延迟锚生效（数拍以起点为第 1 个八拍），直到被打断撤销。
  active,
}

/// 延迟播放状态机。
///
/// **触发**（[trigger]）：解析起点 = 当前相位（[phaseOf]，含「八拍锚点」重定相）
/// 下最近的八拍点 → 算预备序列 = 自起点向前 N 个真实拍点（[prepBeatsOf]，在
/// 有效区间头截断）→ `seek(预备起点)` → `play()`。画面、音乐、拍声照常
/// 推进，暂停中触发也一样看得见听得到。
///
/// **越过起点**：订阅引擎位置流，位置越过起点即转 [DelayedPlayPhase.active]
/// 并交出**延迟锚**（[delayAnchor] = 起点）。
///
/// **打断**（[interrupt]）= 清延迟锚 + 回 idle；不 seek、不改播放
/// 态（那个操作本身的效果照常）。重复触发 = 重设（清旧锚、按新位置重算）。
///
/// **注入**：相位来源 [phaseOf]（占位/异常网格返回 null——不产生八拍点）、
/// 预备拍数 [prepBeatsOf]（设备级设置）、有效区间 [validRangeOf]、
/// 兜底网格 [gridOf]（仅兜底分支使用）。
///
/// **兜底分支**（占位/异常网格，保留的退化路径）：墙钟等一个八拍标称
/// （≈4s）后从当前位置起播，编号为触发锚的 1…8；无延迟锚。待内测用户无
/// 反馈后删除。
///
/// 本控制器不持有引擎所有权；[dispose] 只取消订阅与定时器。
class DelayedPlayController extends ChangeNotifier {
  DelayedPlayController(
    this._engine, {
    required this.phaseOf,
    required this.prepBeatsOf,
    required this.validRangeOf,
    required this.gridOf,
    this.mediaPositionOf,
    this.isTakenOverOf,
  }) {
    _playingSub = _engine.isPlayingStream.listen((playing) {
      if (!playing) interrupt();
    });
  }

  final PlaybackEngine _engine;

  /// 相位来源：当前相位（网格 + 八拍锚点）。null = 占位/异常网格（不产生
  /// 八拍点）→ 该次触发走兜底分支。
  final BeatPhase? Function() phaseOf;

  /// 预备拍数 N（设备级 `prepBeats.delayedPlay`）。
  final int Function() prepBeatsOf;

  /// 有效区间（数拍与拍点的有效范围）；null = 区间未就绪 → 兜底。
  final ({Duration start, Duration end})? Function() validRangeOf;

  /// 兜底分支的网格来源（八拍标称等待时长与兜底编号换算）。主路径不消费。
  final BeatGrid Function() gridOf;

  /// 触发时的媒介位置来源（数拍派生位置）；缺省回退引擎当前位置。
  final Duration? Function()? mediaPositionOf;

  /// 录制期播放接管事实来源：接管期不生效（缺省不接管）。
  final bool Function()? isTakenOverOf;

  DelayedPlayPhase _phase = DelayedPlayPhase.idle;

  /// 当前阶段（宿主与测试据此读延迟播放是否在途）。
  DelayedPlayPhase get phase => _phase;

  /// 延迟起点（八拍点）；null = 无延迟锚（idle 或兜底路径）。
  Duration? _start;

  /// 延迟锚（会话值，不落盘）：预备期即生效——预备区浮层的 `0|x` 与越点后
  /// 的 `1|1` 由同一锚经既有数拍编号派生（锚点链优先级：录制锚 → 延迟锚 →
  /// 激活锚 → 分段线 → 首线）。null = 无锚。
  Duration? get delayAnchor => _start;

  StreamSubscription<Duration>? _positionSub;

  /// 引擎转停沿订阅：用户暂停、播到尾、退后台的停沿即撤锚并作废在途预备
  /// （起播沿不打断——触发即起播）。
  StreamSubscription<bool>? _playingSub;

  // ── 兜底分支（占位/异常网格）的墙钟倒计时 ──
  Timer? _countdown;

  bool _disposed = false;

  /// 触发延迟播放：倒回起点前 N 拍连续播到起点。
  ///
  /// [mediaPosition] = 宿主当帧的**数拍派生位置**（`beatCountPositionProvider`
  /// ——与数拍数字、节拍动画同一份媒介位置；省略时现读引擎位置）。
  ///
  /// 已是 preparing/active 时重复触发 = 重设（清旧锚、按新位置重算）。
  Future<void> trigger({Duration? mediaPosition}) async {
    if (_disposed) return;
    // 重复触发 = 重设：清旧锚、旧前导、旧订阅，按新位置重算（idle 时无
    // 在途痕迹，不空发收前导）。
    if (_phase != DelayedPlayPhase.idle) await _teardown();
    final position = mediaPosition ?? _engine.position;
    // 相位当次取定一次：起点解析与预备序列同源（不容两次读取漂移）。
    final phase = phaseOf();
    if (phase == null) {
      _startFallback();
      return;
    }
    final start = _resolveStart(position, phase);
    if (start == null) {
      _startFallback();
      return;
    }
    final grid = phase.grid;
    final startIndex = grid.beatIndexAt(start);
    final prep = <Duration>[];
    for (var i = startIndex - 1; i >= 0 && prep.length < prepBeatsOf(); i--) {
      final time = grid.beatTime(i);
      final range = validRangeOf();
      if (range == null || time < range.start) break; // 有效区间头截断。
      prep.insert(0, time);
    }
    _start = start;
    _phase = DelayedPlayPhase.preparing;
    // 触发即倒回预备起点连续播：seek → play。
    await _engine.seek(prep.isEmpty ? start : prep.first);
    if (_disposed) return;
    unawaited(_engine.play());
    _positionSub = _engine.positionStream.listen(_onPosition);
    notifyListeners();
  }

  /// 起点解析（唯一出处）：当前相位（含八拍锚点重定相）下最近的八拍点；
  /// 相位不可用（占位/异常网格）或起点越出有效区间 → null（该次走兜底）。
  Duration? _resolveStart(Duration position, BeatPhase phase) {
    final start = phase.nearest(position);
    if (start == null) return null;
    final range = validRangeOf();
    if (range == null || start < range.start || start > range.end) return null;
    return start;
  }

  /// 位置推进：越过起点即转 active（延迟锚已就位），收前导交回正式节拍器。
  void _onPosition(Duration position) {
    if (_disposed || _phase != DelayedPlayPhase.preparing) return;
    final start = _start;
    if (start == null || position < start) return;
    _positionSub?.cancel();
    _positionSub = null;
    _phase = DelayedPlayPhase.active;
    notifyListeners();
  }

  /// 中断延迟播放（打断表逐行成立，宿主接线）：收前导 + 清延迟锚 + 回
  /// idle；不 seek、不改播放态。idle 时 no-op。
  void interrupt() {
    if (_disposed || _phase == DelayedPlayPhase.idle) return;
    _cancelCountdown();
    _positionSub?.cancel();
    _positionSub = null;
    _start = null;
    _phase = DelayedPlayPhase.idle;
    notifyListeners();
  }

  // ── 兜底分支（占位/异常网格）：保留的旧墙钟路径 ──

  void _startFallback() {
    final grid = gridOf();
    _phase = DelayedPlayPhase.preparing;
    _countdown = Timer(grid.eightBeatNominal, _startFallbackPlayback);
    notifyListeners();
  }

  Future<void> _startFallbackPlayback() async {
    _cancelCountdown();
    if (_disposed) return; // 倒计时期间已离开播放器：不再播放、不通知。
    _phase = DelayedPlayPhase.idle;
    notifyListeners();
    await _engine.play();
  }

  void _cancelCountdown() {
    _countdown?.cancel();
    _countdown = null;
  }

  /// 清掉一次在途延迟的全部痕迹（重复触发重设与 dispose 共用）。
  Future<void> _teardown() async {
    _cancelCountdown();
    _positionSub?.cancel();
    _positionSub = null;
    _start = null;
  }

  /// 触发一次延迟播放（宿主手势/控制层按钮入口）：录制期播放接管时不生效，
  /// 媒介位置按注入来源现读（缺省回退引擎当前位置）。
  Future<void> triggerNow() {
    if (isTakenOverOf?.call() ?? false) return Future<void>.value();
    return trigger(mediaPosition: mediaPositionOf?.call());
  }

  void Function(Duration? anchor)? _writeAnchor;
  void Function(bool preparing)? _writePreparing;

  /// 延迟锚 / 预备相位值道同步（宿主注入 provider 写缝）：控制器每次通知把
  /// 当前锚与「是否预备中」推给值道，宿主不再自行 addListener。
  void attachChannels({
    required void Function(Duration? anchor) writeAnchor,
    required void Function(bool preparing) writePreparing,
  }) {
    if (_channelsAttached) return;
    _channelsAttached = true;
    _writeAnchor = writeAnchor;
    _writePreparing = writePreparing;
    addListener(_pushChannels);
    _pushChannels();
  }

  bool _channelsAttached = false;

  void _pushChannels() {
    _writeAnchor?.call(delayAnchor);
    _writePreparing?.call(_phase == DelayedPlayPhase.preparing);
  }

  @override
  void dispose() {
    _disposed = true;
    removeListener(_pushChannels);
    _cancelCountdown();
    _positionSub?.cancel();
    _positionSub = null;
    _playingSub?.cancel();
    _playingSub = null;
    super.dispose();
  }
}

/// 延迟预备期事实道：延迟播放控制器「相位 = preparing」
/// 的现值 + 边沿，宿主在控制器每次通知时写入；练习记账事实流消费——预备
/// 期播放**不计**，越过起点（相位翻 active/idle）即照常按观看态计入。
final delayedPlayPreparingProvider =
    NotifierProvider<_DelayedPlayPreparingModel, bool>(
      _DelayedPlayPreparingModel.new,
    );

class _DelayedPlayPreparingModel extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool preparing) {
    if (state != preparing) state = preparing;
  }
}
