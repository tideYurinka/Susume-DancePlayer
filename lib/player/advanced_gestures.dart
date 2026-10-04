/// 高级播放手势识别器。
///
/// 双指双击用自定义 [OneSequenceGestureRecognizer] +
/// [RawGestureDetector] 接入：`requireGestureRecognizer` 不存在、pan 与
/// scale 互斥，多指模式只能自行聚合。
///
/// Flutter 3.47 的 [ScaleGestureRecognizer] 只在位移超过 slop 时胜出
/// （不在第二指落下时立即胜出），因此本识别器与
/// `GestureDetector.onScale*`（单/双/三指拖动）在同一 arena 内可共存：
///
/// - [PlayerDoubleTapGestureRecognizer]：单指双击（暂停/播放）与双指双击
///   （延迟播放）互斥识别，**替代**自带 [DoubleTapGestureRecognizer]——
///   自带实现会把双指并击误判为两次单击（多指需自行聚合），导致双指
///   双击手势中途触发一次暂停/播放；本识别器按两次 tap
///   的手指数一致性区分，混合手指数（先单后双等）一律不识别。
///
/// 三指滑动跳转不设独立识别器：并入外层 scale 流程按 pointerCount==3
/// 分支处理（见 `player_page.dart`）——自定义识别器与 scale 争 gesture
/// arena 在真机不可靠（曾致三指被误判为调进度）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/gestures.dart';

/// 双指双击回调（延迟播放触发）。
typedef TwoFingerDoubleTapCallback = void Function();

/// 单击回调（单指单击、双击判定窗口内未再接第二次 tap 才触发）。
///
/// 控制层唤出：单击延迟到 [kDoubleTapTimeout]（≈300ms）
/// 判定窗口结束才回调——双击判定窗口内的第一次 tap 若随后组成双击则不触发
/// （双击胜出），只有孤立的单指单击才触发。纯视觉回调，由
/// [PlayerDoubleTapGestureRecognizer] 内部判定，不与自带 TapGestureRecognizer
/// 争 arena（真机手势可靠性原则：优先平台标准识别器、避免额外识别器争斗）。
typedef PlayerSingleTapCallback = void Function();

/// 播放器双击识别器：单指双击、双指双击互斥识别，并兼任**单击（控制层唤出）**
/// 的判定。
///
/// 状态机：
///
/// - 每次「tap」= 1 或 2 根手指按下后全部抬起，期间任一手指位移超过
///   [kDoubleTapTouchSlop] 即作废；
/// - 第一次 tap 完成后**hold** 其指针的 arena（跨指针抬起后的 sweep），
///   等待 [kDoubleTapTimeout] 内的第二次 tap；
/// - 第二次 tap 与第一次**手指数一致**、按下位置在 [kDoubleTapSlop] 内、
///   且间隔 ≥ [kDoubleTapMinTime]（防触点抖动）→ 识别：按手指数回调
///   [onDoubleTap]（单指）或 [onTwoFingerDoubleTap]（双指）；
/// - 第一次 tap 为单指、且在 [kDoubleTapTimeout] 内没有第二次 tap（孤立
///   单指单击）→ [kDoubleTapTimeout] 到点回调 [onSingleTap]（控制层唤出）；
///   第一次 tap 为双指 → 双指单击不回调（控制层唤出限单指）；
/// - 手指数不一致 / 超时（双指） / 位移超限 / cancel → 复位（不识别）。
class PlayerDoubleTapGestureRecognizer extends OneSequenceGestureRecognizer {
  PlayerDoubleTapGestureRecognizer({
    this.onDoubleTap,
    this.onTwoFingerDoubleTap,
    this.onSingleTap,
  });

  /// 单指双击（替代 `GestureDetector.onDoubleTap`：暂停/播放）。
  GestureDoubleTapCallback? onDoubleTap;

  /// 双指双击（延迟播放）。
  TwoFingerDoubleTapCallback? onTwoFingerDoubleTap;

  /// 单指单击（控制层唤出）：延迟至双击判定窗口后触发，见
  /// [PlayerSingleTapCallback]。
  PlayerSingleTapCallback? onSingleTap;

  /// 第一次 tap 的记录（手指数 + 第一指按下位置）。
  _TapRecord? _firstTap;

  /// 第一次 tap 涉及的全部指针（用于复位时按指针逐个让出 arena）。
  final Set<int> _firstTapPointers = <int>{};

  /// 正在跟踪的指针（OneSequenceGestureRecognizer 的 `_trackedPointers` 为
  /// 私有，子类自行镜像一份，用于按指针逐个让出 arena）。
  final Set<int> _tracked = <int>{};

  /// 当前 tap 的手指数（null = 无进行中的 tap）。
  int? _tapFingerCount;

  /// 当前 tap 第一指按下位置（两次 tap 位置容差校验）。
  Offset? _tapStart;

  /// 当前 tap 各指针的按下位置（位移超限校验）。
  final Map<int, Offset> _downPositions = <int, Offset>{};

  /// 第一次 tap 完成 → 等待第二次 tap 的窗口定时器。
  Timer? _betweenTapsTimer;

  /// 第一次 tap 完成 → 最短间隔（防触点抖动）倒计时。
  Timer? _minTimeTimer;
  bool _minTimeElapsed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer, event.transform);
    _tracked.add(event.pointer);
    if (_tapFingerCount == null) {
      // 新 tap 的第一指：与第一次 tap 的位置/最短间隔校验。
      final first = _firstTap;
      if (first != null &&
          (!_minTimeElapsed ||
              (event.position - first.position).distance > kDoubleTapSlop)) {
        // 不是第二次 tap（过远或过快）：放弃当前序列，本次按下作新序列第一 tap。
        _abandonFirstTap();
      }
      _tapFingerCount = 1;
      _tapStart = event.position;
    } else {
      _tapFingerCount = _tapFingerCount! + 1;
    }
    _downPositions[event.pointer] = event.position;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      final down = _downPositions[event.pointer];
      if (_tapFingerCount != null &&
          down != null &&
          (event.position - down).distance > kDoubleTapTouchSlop) {
        _reset(); // 位移超限：不是 tap。
      }
    } else if (event is PointerUpEvent) {
      if (_tapFingerCount != null) {
        // 手指抬起后该指针的 arena 会被 sweep；hold 住以跨 tap 等待第二次 tap
        //（与自带 DoubleTapGestureRecognizer 的 `gestureArena.hold` 同理）。
        GestureBinding.instance.gestureArena.hold(event.pointer);
        _downPositions.remove(event.pointer);
        if (_downPositions.isEmpty) {
          _completeTap();
        }
        _tracked.remove(event.pointer);
      }
    } else if (event is PointerCancelEvent) {
      _tracked.remove(event.pointer);
      _reset();
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  void _completeTap() {
    final count = _tapFingerCount!;
    final position = _tapStart!;
    _tapFingerCount = null;
    _tapStart = null;

    if (count > 2) {
      _reset(); // 超过双指：不识别。
      return;
    }
    if (_firstTap == null) {
      // 第一次 tap：记录并等待第二次。
      _firstTap = _TapRecord(fingerCount: count, position: position);
      _firstTapPointers
        ..clear()
        ..addAll(_tracked);
      _betweenTapsTimer = Timer(kDoubleTapTimeout, _onFirstTapTimeout);
      _minTimeTimer = Timer(kDoubleTapMinTime, () => _minTimeElapsed = true);
      return;
    }
    // 第二次 tap：手指数一致才识别（单指双击 → 暂停/播放；双指双击 → 延迟播放）。
    if (_firstTap!.fingerCount != count) {
      _reset();
      return;
    }
    _finishDoubleTap();
  }

  /// 双击判定窗口到点仍无第二次 tap：结束本次序列。首 tap 为**单指**时视为
  /// 孤立单击 → 回调 [onSingleTap]（控制层唤出，双击窗口语义）；双指
  /// 首 tap → 双指单击，不唤出控制层。任何情况下都让出 arena 并清空状态。
  void _onFirstTapTimeout() {
    _stopTimers();
    final first = _firstTap;
    _forfeit(_tracked);
    _clearState();
    if (first != null && first.fingerCount == 1) {
      onSingleTap?.call();
    }
  }

  void _finishDoubleTap() {
    _stopTimers();
    final first = _firstTap!;
    _clearState();
    // 让出所有指针的 arena 并胜出（第一次 tap 的 arena 此前被 hold）。
    resolve(GestureDisposition.accepted);
    if (first.fingerCount == 1) {
      onDoubleTap?.call();
    } else {
      onTwoFingerDoubleTap?.call();
    }
  }

  /// 放弃第一次 tap 的等待（第二次 tap 过远/过快）：逐个让出第一次 tap
  /// 指针的 arena，保持对当前指针的跟踪。
  void _abandonFirstTap() {
    _stopTimers();
    _forfeit(_firstTapPointers);
    _clearState();
  }

  /// 完全复位：让出全部 arena 并清理状态。
  void _reset() {
    _stopTimers();
    _forfeit(_tracked);
    _clearState();
  }

  /// 逐个让出 [pointers] 的 arena（resolvePointer rejected + release）。
  ///
  /// 内部先拷贝：resolvePointer 会触发 [rejectGesture] → 嵌套 [_reset]，
  /// 期间集合可能被清空，迭代必须基于快照。
  void _forfeit(Set<int> pointers) {
    for (final pointer in pointers.toList()) {
      resolvePointer(pointer, GestureDisposition.rejected);
      GestureBinding.instance.gestureArena.release(pointer);
    }
  }

  void _stopTimers() {
    _betweenTapsTimer?.cancel();
    _betweenTapsTimer = null;
    _minTimeTimer?.cancel();
    _minTimeTimer = null;
    _minTimeElapsed = false;
  }

  void _clearState() {
    _firstTap = null;
    _firstTapPointers.clear();
    _tapFingerCount = null;
    _tapStart = null;
    _downPositions.clear();
  }

  @override
  void rejectGesture(int pointer) {
    // 输掉 arena（如拖动被 scale 接管）：让出该指针的条目、停止跟踪并复位。
    resolvePointer(pointer, GestureDisposition.rejected);
    stopTrackingPointer(pointer);
    _tracked.remove(pointer);
    _reset();
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  void dispose() {
    _stopTimers();
    _forfeit(_tracked);
    _clearState();
    super.dispose();
  }

  @override
  String get debugDescription => 'player double tap';
}

class _TapRecord {
  const _TapRecord({required this.fingerCount, required this.position});

  /// 手指数（1 = 单指 tap，2 = 双指 tap）。
  final int fingerCount;

  /// 第一指按下位置（两次 tap 的位置容差校验基准）。
  final Offset position;
}

/// 编辑态空白区双击仲裁器：**不参与 gesture arena** 的 tap 序列
/// 判定，供已由单一 ScaleGestureRecognizer 独占 arena 的区域（轨道带、
/// 控制层视频可见区）复用全屏唤出层的双击共存语义——
///
/// - 孤立单指单击 → [kDoubleTapTimeout]（≈300ms）判定窗口到点回调
///   [onSingleTap]（收起）；
/// - 窗口内的第二次同手指数 tap（位置在 [kDoubleTapSlop] 内）→ 按手指数
///   回调 [onDoubleTap]（调用侧语义：编辑态只切播放/暂停）或
///   [onTwoFingerDoubleTap]（收起+延迟播放）；
/// - 非空闲会话（拖动/捏合，位移过阈）取消待定序列——静止两击 = 双击、
///   位移 = 缩放/拖动的仲裁与本区 scale 识别器的自然让位一致；
///
/// 触发时机约定：双击回调在**第二次 tap 完成（末指抬起）**时触发——与
/// [PlayerDoubleTapGestureRecognizer] 一致；「第二击按下
/// 即触发、不等判定窗口」的实质是「不等 300ms 判定窗口」，下压即判需在
/// 第二击手指数齐前预判手指数（单指双击会误吞双指双击的第二击首指），
/// 本仲裁器不做。
///
/// 位移阈值沿两路来源的自然约定（同一仲裁器内并存）：单指路径的空闲
/// 判定用调用侧 scale 会话的累计焦点位移（触摸 slop [kTouchSlop]）；双指
/// burst 路径用逐指位移（[kDoubleTapTouchSlop]，与全屏识别器的 tap 位移
/// 上限一致）。
///
/// 之所以不直接复用 [PlayerDoubleTapGestureRecognizer]：后者作为 arena
/// 成员会让同区的 scale 识别器无法在按下即胜出（双击识别器直到位移过阈
/// 才让出 arena），拖动/捏合的前 ~100px 会丢给识别器竞争——空白区捏合/
/// 拖动语义必须与既有完全一致（「缩放范围/钳制/滑条规则不变」），
/// 故在 scale 会话边界之上以纯状态机实现同一判定。
class BlankTapArbiter {
  BlankTapArbiter({
    this.onSingleTap,
    this.onDoubleTap,
    this.onTwoFingerDoubleTap,
  });

  /// 孤立单指单击（约 300ms 窗口后）：收起。
  final VoidCallback? onSingleTap;

  /// 单指双击（语义由调用侧定义；编辑态 = 只切播放/暂停不收起）。
  final VoidCallback? onDoubleTap;

  /// 双指双击：收起 + 延迟播放。
  final VoidCallback? onTwoFingerDoubleTap;

  /// 第一次 tap 的判定窗口定时器。
  Timer? _windowTimer;

  /// 待定 tap 的手指数与位置。
  int? _pendingFingerCount;
  Offset _pendingPosition = Offset.zero;

  /// 取消待定序列（不触发任何回调）。
  void cancel() {
    _windowTimer?.cancel();
    _windowTimer = null;
    _pendingFingerCount = null;
  }

  void dispose() => cancel();

  /// scale 会话结束时上报：[pointerCount] = 会话起始手指数、[position] =
  /// 会话起始焦点、[idleTap] = 全程无拖动/捏合（位移在触摸 slop 内）、
  /// [pointersStillDown] = 会话结束后是否仍有指针按下（false = 真抬起）。
  ///
  /// scale 识别器在加指时可能先跑一个空转的单指会话（其余指针仍按下），
  /// [pointersStillDown] 复核将其排除，不计为 tap。
  void handleSessionEnd({
    required int pointerCount,
    required Offset position,
    required bool idleTap,
    required bool pointersStillDown,
  }) {
    if (pointersStillDown) {
      // 加指产生的空转会话（其余指针仍按下）：不是 tap，也不取消待定
      // 序列——它只是 scale 识别器重启会话的噪声。
      return;
    }
    if (!idleTap || pointerCount < 1 || pointerCount > 2) {
      // 非空闲会话（拖动/捏合/超双指）取消待定序列（与全屏识别器的
      // 「第二指过远/位移超限 → 放弃当前序列」同义）。
      cancel();
      return;
    }
    final pending = _pendingFingerCount;
    if (pending != null) {
      final isSecondTap =
          pending == pointerCount &&
          (position - _pendingPosition).distance <= kDoubleTapSlop;
      cancel();
      if (isSecondTap) {
        if (pointerCount == 1) {
          onDoubleTap?.call();
        } else {
          onTwoFingerDoubleTap?.call();
        }
      }
      return;
    }
    // 第一次 tap：记录并等待判定窗口。
    _pendingFingerCount = pointerCount;
    _pendingPosition = position;
    _windowTimer = Timer(kDoubleTapTimeout, () {
      _windowTimer = null;
      final wasSingle = _pendingFingerCount == 1;
      _pendingFingerCount = null;
      if (wasSingle) onSingleTap?.call();
    });
  }
}

/// 一次指针 burst（自第一指按下至全部抬起）的结束记录。
class PointerBurstEnd {
  const PointerBurstEnd({
    required this.pointerCount,
    required this.position,
    required this.moved,
    required this.cancelled,
  });

  /// burst 内的最大同时按下手指数。
  final int pointerCount;

  /// 各次按下位置的平均值（双指 = 双指中点）。
  final Offset position;

  /// burst 内是否有任一指位移超过触摸 slop（拖动/捏合）。
  final bool moved;

  /// burst 是否被系统取消（任一指针 PointerCancel；edge 手势抢占、来电等）。
  /// 取消的 burst 不是 tap 也不是合法手势——调用侧只应据此取消待定序列。
  final bool cancelled;
}

/// 指针 burst 跟踪器：在原始 [Listener] 层聚合「一次按下到全部
/// 抬起」的手指数、中点与位移。
///
/// 为何需要它：scale 识别器在双指按下/抬起时会重启会话，且重启后的会话
/// 在测试与部分真机序列中不产生可靠的会话结束事件——双指双击（静止的
/// 两击）的判定改由本跟踪器承担，单指单击仍走 scale 会话路径（见
/// [BlankTapArbiter.handleSessionEnd] 的调用侧分工）。
class PointerBurstTracker {
  final Map<int, Offset> _downPositions = <int, Offset>{};
  final List<Offset> _burstPositions = <Offset>[];
  int _maxPointers = 0;
  bool _moved = false;
  bool _cancelled = false;

  /// 最近一次 burst 的证据存档：burst 结束时写入，下一 burst
  /// 开始时清除——供晚于 burst 结束的识别器会话结束回调读取。
  int _lastBurstMaxPointers = 0;
  bool _lastBurstMoved = false;

  /// 指针按下。返回非 null 表示上一个 burst 恰在此次按下前结束。
  PointerBurstEnd? pointerDown(int pointer, Offset position) {
    final ended = _downPositions.isEmpty && _maxPointers > 0 ? _end() : null;
    if (ended != null || (_downPositions.isEmpty && _maxPointers == 0)) {
      // 新 burst 开始：清除上一 burst 的存档证据。
      _lastBurstMaxPointers = 0;
      _lastBurstMoved = false;
    }
    _downPositions[pointer] = position;
    _burstPositions.add(position);
    if (_downPositions.length > _maxPointers) {
      _maxPointers = _downPositions.length;
    }
    return ended;
  }

  /// 指针移动（位移过触摸 slop → 标记 moved = 拖动/捏合，非 tap）。
  void pointerMove(int pointer, Offset position) {
    final down = _downPositions[pointer];
    if (down != null && (position - down).distance > kDoubleTapTouchSlop) {
      _moved = true;
    }
  }

  /// 指针被系统取消：标记本 burst 已取消（不是 tap，也不是合法手势）。
  void pointerCancel(int pointer) {
    _downPositions.remove(pointer);
    _cancelled = true;
  }

  /// 何时算「捏合」：burst 曾达到的最大同时按下手指数阈值。
  static const int kMinPinchPointers = 2;

  /// 最近一次 burst 的证据：burst 存续时读实时值，结束后读
  /// [_end] 写入的存档，直到下一 burst 的首指按下才清除。
  ///
  /// 为何需要它：scale 识别器在抬指/加指后会重启会话，会话级位移证据
  /// （调用侧的 maxDisplacement）随重启被复位；且识别器的会话结束回调
  /// （含调用侧的微任务复核）可能晚于原始指针层的 burst 结束——若证据
  /// 随 burst 结束即清零，重启的少指尾会话就查不到上下文。存档保留使
  /// 调用侧在任意时序下都能读到：曾含 ≥2 指（捏合后分次松手）或有过
  /// 位移的 burst，其尾部少指会话不判空闲单击、不触发 300ms 收起。
  ({int maxPointers, bool moved}) get latestBurstEvidence => _maxPointers > 0
      ? (maxPointers: _maxPointers, moved: _moved)
      : (maxPointers: _lastBurstMaxPointers, moved: _lastBurstMoved);

  /// 会话结束的空闲单击判定：会话级位移在触摸 slop 内，且本
  /// （或上一存档的）burst 未曾达到捏合指数、也未曾位移。空白与轨道带
  /// 两条路径共用，避免判定条件变更时两处散改。
  bool isIdleTap(double sessionMaxDisplacement, double slop) {
    final evidence = latestBurstEvidence;
    return sessionMaxDisplacement < slop &&
        evidence.maxPointers < kMinPinchPointers &&
        !evidence.moved;
  }

  /// 指针抬起/取消。返回非 null 表示全部指针已抬起（burst 结束）。
  PointerBurstEnd? pointerUp(int pointer) {
    _downPositions.remove(pointer);
    if (_downPositions.isNotEmpty) return null;
    return _end();
  }

  PointerBurstEnd? _end() {
    if (_maxPointers == 0) return null;
    final end = PointerBurstEnd(
      pointerCount: _maxPointers,
      position: _burstPositions.isEmpty
          ? Offset.zero
          : _burstPositions.reduce((a, b) => a + b) /
                _burstPositions.length.toDouble(),
      moved: _moved,
      cancelled: _cancelled,
    );
    // 证据存档——识别器会话结束回调可能晚于 burst 结束，尾部
    // 少指会话的空闲判定仍需读取（下一 burst 开始时清除，见 pointerDown）。
    _lastBurstMaxPointers = _maxPointers;
    _lastBurstMoved = _moved;
    _maxPointers = 0;
    _moved = false;
    _cancelled = false;
    _burstPositions.clear();
    return end;
  }
}
