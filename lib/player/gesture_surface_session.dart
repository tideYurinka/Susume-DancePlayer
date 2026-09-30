/// 输入会话簿记壳：band/blank 两面共用的 raw 指针簿记、
/// burst/tap 仲裁、单指轴锁与事件转发，收进一个实例——两面 State 只剩
/// 装配 + 内容层，不各持一份逐字段同构的簿记副本（`_downPoints` /
/// `PointerBurstTracker` / `BlankTapArbiter` / `_accDx/_accDy` /
/// `_maxDisplacement` / `_sawPointerCancel`…）。
///
/// 面差异只经注入表达（边界：吸附/窗口跟随/拖线命中/
/// scrub 生命周期等一概留在宿主内容层）：
/// - [GestureSurfaceSession.isEditContent]：band 内容命中检查（按下点落在
///   编辑内容上则本 burst 不进入空白 tap 判定——**单指空闲单击与双指双击
///   同一判据**）；blank 传 null。
/// - [GestureSurfaceSession.pinchSession]：跨面双指**转发面**原样
///   注入，raw 四回调按 [pinchSurface] 选择转发方法；[suppressedByMixedPinch]
///   即其 `burstEverMixed` 闩锁（混区起手抑制）。持有者是谁与本模块无关
///   （跨面会话自身或吸收它的轨道带会话域都实现该面）。
/// - `onSingleTap/onDoubleTap/onTwoFingerDoubleTap`：tap 序列仲裁输出
///   （约 300ms 判定窗口仲裁在 [BlankTapArbiter] 内，降为内部 seam）。
/// - `onMultiFingerWhileScrub`：锁定 scrub 中加指/被混区抑制/指针取消时的
///   宿主通知。blank 注入（scrub.end()——加指冻结按松手恢复，轴锁同时
///   复位、回落 arming 待重锁）；band 传 null（冻结不结束本地处理：轴锁
///   保留、抬回单指即恢复 scrub 帧）。该注入的有无同时决定帧分发语义：
///   null（band 形态）= 起手即 ≥2 指的会话整场按 pinch 帧转发；非 null
///   （blank 形态）= pinch 帧仅在当前 ≥2 指时转发、余指路径回归 arming。
/// - `onScrubFrame / onPinchFrame`：内容层逐帧事件（模块只判定「哪类帧」，
///   「对帧做什么」留在宿主——开放/封闭判据）。
/// - `onSurfaceScaleStart / onSurfaceScaleEnd`：会话边界的内容钩子
///   （捏合基准快照、贴边平移收口、防御性 scrub 收尾等）。
/// - `onIdleTapContent`：空闲单击微任务复核前的内容消费机会（band 学习段
///   点选命中；返回 true 表示已消费、不进入 tap 仲裁）。blank 传 null。
/// - `isHostAlive`：微任务复核的宿主存活守卫。
///
/// 不变量（时序与两面 handler 一致）：一个 burst = 首指 down →
/// 全部 up/cancel，cancel 的 burst 不判 tap；铁律闩锁（会话内曾达到的
/// 最大焦点位移，回到原位不清零）；证据存档（burst 结束证据保留到下一
/// burst 首指，供迟到的 scale 会话复核）；混区起手 → suppressed；
/// pointerDown 先于该指针的 Move/Up/Cancel；
/// scaleUpdate 未 start 时内部忽略（识别器重启空转）。
///
/// 行为注记（沿既有先例）：pointerCancel 统一置位取消旗标，使
/// 「先取消后有 scale 会话结束」的序列会取消待定 tap 序列而非进入判定。
/// 该序列在 scale 识别器下不可达（指针取消后识别器不产生会话结束回调），
/// 外部可观察行为不变；旗标语义 = 取消不是单击。
///
/// 内容命中证据 `_burstSawContent` **同等地喂给单指与双指两条路径**
/// （见 [scaleEnd] 的微任务复核）：内容上的单击与内容上的双指双击一样，
/// 都不是空白手势。真机上手指滚过平台 slop（约 8dp）后子级点按识别器自我
/// 出局、带级却仍按常量 `kTouchSlop`（18dp）判成「空闲单击」，一次误触就把
/// 控制层收了起来——同一个量（手指容差）在两处取了两个值，证据同喂即消除
/// 这条分叉。
library;

import 'dart:async';

import 'package:flutter/gestures.dart'
    show
        kTouchSlop,
        PointerCancelEvent,
        PointerDownEvent,
        PointerMoveEvent,
        PointerUpEvent,
        ScaleEndDetails,
        ScaleStartDetails,
        ScaleUpdateDetails;
import 'package:flutter/widgets.dart' show Offset, VoidCallback;

import 'advanced_gestures.dart'
    show BlankTapArbiter, PointerBurstEnd, PointerBurstTracker;
import 'two_finger_session.dart' show CrossSurfacePinchForwarder;

/// 轴锁策略：现两面同值 [strictHorizontal]（水平累计明显占优才
/// 锁轴）；majoritySlop 预留——第二策略出现再升级为接口。
enum AxisPolicy { strictHorizontal }

/// 输入会话相位（只读查询）：
/// - [idle]：无活动 scale 会话；
/// - [tracking]：会话中、轴未锁（arming）；
/// - [horizontalLocked]：轴已锁（scrub 帧转发中）；
/// - [multiFinger]：会话中当前 ≥2 指；
/// - [suppressed]：本 burst 曾进入跨面混区会话（单指语义全抑制）。
enum GestureSurfacePhase {
  idle,
  tracking,
  horizontalLocked,
  multiFinger,
  suppressed,
}

/// [CrossSurfacePinchForwarder] 的原始指针转发来源面（混区聚合需要区分
/// 标注来源面）：band 转发 `trackBandPointerX`，blank 转发 `blankPointerX`。
enum PinchForwardSurface { trackBand, blank }

/// band/blank 共用的输入会话簿记壳（plain class + State 装配，
/// 沿 CrossSurfacePinchSession/SerialSeekQueue 先例：不进 Riverpod）。
class GestureSurfaceSession {
  GestureSurfaceSession({
    required this.axis,
    this.isEditContent,
    this.pinchSession,
    this.pinchSurface = PinchForwardSurface.blank,
    this.onSingleTap,
    this.onDoubleTap,
    this.onTwoFingerDoubleTap,
    this.onMultiFingerWhileScrub,
    this.onSurfaceScaleStart,
    this.onScrubFrame,
    this.onPinchFrame,
    this.onSurfaceScaleEnd,
    this.onIdleTapContent,
    bool Function()? isHostAlive,
  }) : _isHostAlive = isHostAlive ?? (() => true);

  /// 轴锁策略（现恒 [AxisPolicy.strictHorizontal]）。
  final AxisPolicy axis;

  /// 按下点内容命中检查（band：练习片段块/段体/线/预览条等，见宿主
  /// `_isEditContentAt`；null = 无编辑内容面）。命中的 burst **单指空闲
  /// 单击与双指双击都不进空白 tap 判定**（单指空闲单击与双指双击同一判据）。
  final bool Function(Offset global)? isEditContent;

  /// 跨面双指转发面；null = 无跨面会话（独立使用，行为不变）。
  final CrossSurfacePinchForwarder? pinchSession;

  /// 原始指针向 [pinchSession] 的转发来源面。
  final PinchForwardSurface pinchSurface;

  // 按 [pinchSurface] 一次性选定的原始指针转发（首次访问时绑定；
  // pinchSession 为 null 时为空转发）。避免逐事件重复 switch。
  late final void Function(int, Offset)? _pinchDown = _pick(
    pinchSession?.trackBandPointerDown,
    pinchSession?.blankPointerDown,
  );

  late final void Function(int, Offset)? _pinchMove = _pick(
    pinchSession?.trackBandPointerMove,
    pinchSession?.blankPointerMove,
  );

  late final void Function(int)? _pinchUp = _pick(
    pinchSession?.trackBandPointerUp,
    pinchSession?.blankPointerUp,
  );

  late final void Function(int)? _pinchCancel = _pick(
    pinchSession?.trackBandPointerCancel,
    pinchSession?.blankPointerCancel,
  );

  T _pick<T>(T trackBand, T blank) =>
      pinchSurface == PinchForwardSurface.trackBand ? trackBand : blank;

  final VoidCallback? onSingleTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTwoFingerDoubleTap;

  /// 锁定 scrub 中加指 / 被混区抑制 / 指针取消：宿主收尾 scrub（blank）；
  /// null（band 形态）= 冻结不结束本地处理（轴锁保留、模块继续转发 scrub
  /// 帧，由宿主内容层按 pointerCount 自冻结）。
  final VoidCallback? onMultiFingerWhileScrub;

  /// scale 会话开始的内容钩子（模块簿记复位之后调用：宿主做捏合基准
  /// 快照、清除选中、防御性 scrub 收尾等）。
  final void Function(ScaleStartDetails d)? onSurfaceScaleStart;

  /// 轴锁定的 scrub 内容帧（含锁定事件本身——前段位移立即生效）。
  final void Function(ScaleUpdateDetails d)? onScrubFrame;

  /// pinch 内容帧（分发语义见 [onMultiFingerWhileScrub] 说明）。
  final void Function(ScaleUpdateDetails d)? onPinchFrame;

  /// scale 会话结束的内容钩子（微任务仲裁之前调用：窗口基准清空、贴边
  /// 平移收口、scrub 松手收尾等）。
  final void Function(ScaleEndDetails d)? onSurfaceScaleEnd;

  /// 空闲单指单击的内容消费机会（band 学习段点选）；返回 true = 已消费、
  /// 不进入 tap 仲裁。
  final bool Function()? onIdleTapContent;

  final bool Function() _isHostAlive;

  // ---- 簿记（两面同构字段收拢于此） ----

  /// 带内按下指针的全局位置（pinch 锚点取按下瞬间双指中点；up/cancel 清理；
  /// 会话结束不清——识别器空转会话不丢按下点）。
  final Map<int, Offset> _downPoints = <int, Offset>{};

  /// 原始指针 burst 跟踪（双指双击判定路径 + 证据存档）。
  final PointerBurstTracker _burstTracker = PointerBurstTracker();

  /// tap 序列仲裁器（约 300ms 判定窗口；内部 seam）。
  late final BlankTapArbiter _tapArbiter = BlankTapArbiter(
    onSingleTap: onSingleTap,
    onDoubleTap: onDoubleTap,
    onTwoFingerDoubleTap: onTwoFingerDoubleTap,
  );

  /// 会话中是否有指针被系统取消：取消不是单击。
  bool _sawPointerCancel = false;

  /// 本 burst 是否有指针落在编辑内容上（内容命中检查）。
  bool _burstSawContent = false;

  /// 当前 scale 会话起始手指数与焦点（结束时上报仲裁器）。
  int _sessionPointerCount = 1;
  Offset _sessionStartFocal = Offset.zero;

  /// 单指轴锁定标记（strictHorizontal：水平累计明显占优）。
  bool _axisLocked = false;
  double _accDx = 0;
  double _accDy = 0;

  /// 会话内焦点离起点的最大位移（铁律闩锁）。
  double _maxDisplacement = 0;

  /// 当前 scale 会话中的手指数（phase 查询用）。
  int _framePointerCount = 0;

  /// 是否已有 scale 会话（scaleUpdate 未 start 内部忽略）。
  bool _scaleSessionActive = false;

  /// blank 形态（scrub 生命周期归宿主）。
  bool get _hostOwnsScrub => onMultiFingerWhileScrub != null;

  /// 本 burst 曾进入跨面双指会话（混区起手）。
  bool get _mixedPinchBurst =>
      pinchSession?.burstEverMixed ?? false;

  /// 混区抑制闩锁只读查询。
  bool get suppressedByMixedPinch => _mixedPinchBurst;

  /// 当前会话相位（只读）。
  GestureSurfacePhase get phase {
    if (_mixedPinchBurst) return GestureSurfacePhase.suppressed;
    if (_scaleSessionActive && _framePointerCount >= 2) {
      return GestureSurfacePhase.multiFinger;
    }
    if (_axisLocked) return GestureSurfacePhase.horizontalLocked;
    if (_scaleSessionActive) return GestureSurfacePhase.tracking;
    return GestureSurfacePhase.idle;
  }

  /// 单指轴锁定会话（拖动目标自管显示值与窗口）。
  bool get axisLockedSession => _axisLocked;

  /// 起手即 ≥2 指的 scale 会话（捏合自管窗口）。
  bool get multiFingerSession =>
      _scaleSessionActive && _sessionPointerCount >= 2;

  /// 播放 tick 是否让位于手势会话——拖动目标即显示值（单指轴锁定）或捏合
  /// 会话在场（起手即 ≥2 指）：两者都自己写预览线显示值，tick 不覆盖它
  /// （窗口跟随的让位另按 [multiFingerSession] 等更窄的判据，见宿主）。
  bool get tickYieldsToGesture => axisLockedSession || multiFingerSession;

  /// 带内按下指针位置快照（宿主捏合锚点换算用：按下瞬间双指中点——
  /// scale 识别器位移过阈才回调、焦点已偏离真实中点）。
  List<Offset> get pointerDownPositions =>
      List<Offset>.unmodifiable(_downPoints.values);

  // ---- raw 指针流（Listener 四回调各一行转发） ----

  void pointerDown(PointerDownEvent e) {
    if (_downPoints.isEmpty) {
      // 新 burst 起：复位取消标记与内容命中证据。
      _sawPointerCancel = false;
      _burstSawContent = false;
    }
    _downPoints[e.pointer] = e.position;
    // 内容命中检查：按下点落在编辑内容上则本 burst 不进入空白 tap
    // 判定（编辑优先）。
    final hit = isEditContent;
    if (hit != null && hit(e.position)) {
      _burstSawContent = true;
    }
    _burstTracker.pointerDown(e.pointer, e.position);
    _pinchDown?.call(e.pointer, e.position);
  }

  void pointerMove(PointerMoveEvent e) {
    _burstTracker.pointerMove(e.pointer, e.position);
    _pinchMove?.call(e.pointer, e.position);
  }

  void pointerUp(PointerUpEvent e) {
    _downPoints.remove(e.pointer);
    _pinchUp?.call(e.pointer);
    final burst = _burstTracker.pointerUp(e.pointer);
    if (burst != null) _onBurstEnd(burst);
  }

  void pointerCancel(PointerCancelEvent e) {
    _sawPointerCancel = true;
    _downPoints.remove(e.pointer);
    _pinchCancel?.call(e.pointer);
    _burstTracker.pointerCancel(e.pointer);
    // blank 形态：指针被系统取消 → scrub 随之中止并恢复手势前播放态
    // （宿主经回调收尾；未在 scrub 中时为无害 no-op）。band 形态无此语义。
    if (_hostOwnsScrub) {
      _axisLocked = false;
      onMultiFingerWhileScrub!.call();
    }
    if (_downPoints.isEmpty) _tapArbiter.cancel();
  }

  /// burst 结束（全部指针抬起）上报仲裁器：双指 = tap 序列判定；三指及
  /// 以上 / 有位移 / 取消 / 内容命中 = 取消待定序列（位移仲裁：静止两击 =
  /// 双击、位移 = 缩放/平移）。单指 burst 不在此上报（由 scale 会话路径
  /// 上报——scale 在双指按下/抬起时会重启会话、结束事件不可靠）。
  void _onBurstEnd(PointerBurstEnd burst) {
    if (burst.pointerCount < 2) return;
    if (burst.cancelled) {
      _tapArbiter.cancel(); // 取消的 burst 不是 tap。
      return;
    }
    if (_burstSawContent) {
      // 内容上的双指双击不是空白手势：不进入空白 tap 判定并取消待定序列。
      _tapArbiter.cancel();
      return;
    }
    _tapArbiter.handleSessionEnd(
      pointerCount: burst.pointerCount,
      position: burst.position,
      idleTap: !burst.moved,
      pointersStillDown: false,
    );
  }

  // ---- arena（scale）流 ----

  void scaleStart(ScaleStartDetails d) {
    // 会话簿记先复位（含 total 未知的空轨：收起单击判定仍需干净起点）。
    _axisLocked = false;
    _accDx = 0;
    _accDy = 0;
    _maxDisplacement = 0;
    _framePointerCount = d.pointerCount;
    _sessionPointerCount = d.pointerCount;
    _sessionStartFocal = d.localFocalPoint;
    _scaleSessionActive = true;
    // 内容钩子：捏合基准快照 / 清除选中 / 防御性 scrub 收尾等。
    onSurfaceScaleStart?.call(d);
  }

  void scaleUpdate(ScaleUpdateDetails d) {
    if (!_scaleSessionActive) return; // 识别器重启空转：内部忽略。
    _framePointerCount = d.pointerCount;
    // 铁律闩锁：记录会话内曾达到的最大焦点位移（回到原位不清零）。
    final displacement = (d.localFocalPoint - _sessionStartFocal).distance;
    if (displacement > _maxDisplacement) {
      _maxDisplacement = displacement;
    }
    final suppressed = _mixedPinchBurst;
    if (!_hostOwnsScrub && suppressed) {
      // band 形态：混区 burst 内不累计、不锁定、不转发（整场是缩放+平移
      // 会话，窗口由跨面会话驱动）。
      return;
    }
    _accDx += d.focalPointDelta.dx;
    _accDy += d.focalPointDelta.dy;
    if (d.pointerCount >= 2) {
      if (_hostOwnsScrub) {
        // blank 形态：加指冻结 scrub 并收尾会话（按松手语义恢复手势前播放
        // 态——回调转宿主），轴锁复位；pinch 帧照常转发（宿主自判基准）。
        if (_axisLocked) {
          _axisLocked = false;
          onMultiFingerWhileScrub!.call();
        }
        onPinchFrame?.call(d);
      } else {
        // band 形态：轴锁保留（冻结不结束本地处理，宿主按 pointerCount
        // 自冻结）；起手为单指的会话在 ≥2 帧仍可锁轴（宿主冻结，抬回单指
        // 即恢复）——起手即 ≥2 指的捏合会话不锁轴、整场按 pinch 转发。
        if (_axisLocked) {
          onScrubFrame?.call(d);
        } else if (_sessionPointerCount < 2) {
          if (_accDx.abs() > _accDy.abs()) {
            _axisLocked = true;
            onScrubFrame?.call(d);
          }
        } else {
          onPinchFrame?.call(d);
        }
      }
      return;
    }
    if (suppressed) {
      // blank 形态被混区抑制：锁定中的 scrub 立即收尾（回调转宿主）、轴锁
      // 复位；不转发内容帧。
      if (_hostOwnsScrub && _axisLocked) {
        _axisLocked = false;
        onMultiFingerWhileScrub!.call();
      }
      return;
    }
    if (_axisLocked) {
      onScrubFrame?.call(d);
      return;
    }
    if (!_hostOwnsScrub && _sessionPointerCount >= 2) {
      // band 形态：起手即 ≥2 指的捏合会话整场按 pinch 转发（抬到剩一指
      // 挂起等手势结束，宿主自判 pointerCount）。
      onPinchFrame?.call(d);
      return;
    }
    // strictHorizontal 轴锁定：累计位移水平明显占优才锁（锁定事件本身
    // 立即转发 scrub 帧——前段位移含 slop 前后整段，起手死区修复）。
    if (_accDx.abs() > _accDy.abs()) {
      _axisLocked = true;
      onScrubFrame?.call(d);
    }
  }

  void scaleEnd(ScaleEndDetails d) {
    final pointerCount = _sessionPointerCount;
    final startFocal = _sessionStartFocal;
    // 空闲 = 会话内任一时刻焦点位移都在触摸 slop 内（铁律闩锁），
    // 且携带存档的 burst 级证据（判定见 PointerBurstTracker.isIdleTap：
    // 本 burst 曾含 ≥2 指或有过位移时，识别器重启的少指会话不判空闲单击，
    // 证据经存档保留至下一 burst 开始，微任务复核时仍可读）。
    final wasIdleTap = _burstTracker.isIdleTap(_maxDisplacement, kTouchSlop);
    // 会话状态复位（下一会话干净起点）。
    _axisLocked = false;
    _scaleSessionActive = false;
    _framePointerCount = 0;
    // 内容钩子先于微任务仲裁（窗口基准清空、贴边平移收口、scrub 松手
    // 收尾等——次序与两面 handler 一致）。
    onSurfaceScaleEnd?.call(d);
    if (pointerCount >= 2) return; // 双指路径归 burst 跟踪（见 _onBurstEnd）。
    final sawCancel = _sawPointerCancel;
    final mixedBurst = _mixedPinchBurst;
    // 内容命中证据快照（微任务复核前 burst 可能已被下一 burst 复位）。
    final sawContent = _burstSawContent;
    // 微任务复核沿用单击判定：加指产生的空转会话（其余指针仍按下）不算
    // tap；宿主销毁后不再仲裁。
    scheduleMicrotask(() {
      if (!_isHostAlive()) return;
      if (sawCancel || mixedBurst) {
        // 系统取消的会话不是单击：不进入 tap 判定并取消待定序列。
        _tapArbiter.cancel();
        return;
      }
      final consume = onIdleTapContent;
      if (wasIdleTap &&
          _downPoints.isEmpty &&
          consume != null &&
          consume()) {
        return;
      }
      if (sawContent) {
        // 内容上的空闲单击同样不是空白手势：按下点落在编辑内容上
        // 时**单指路径**也不进空白 tap 判定（收面板 / 延迟播放都不在内容上
        // 生效），与双指路径同一条规则、同一份 [isEditContent] 判定。
        // 真机上手指滚过平台 slop（约 8dp）后子级点按识别器自我出局，带级
        // 却仍按常量 18dp 判成「空闲单击」⇒ 块体上的一次误触把控制层收了
        // 起来：证据同喂两条路径即无此分叉。
        //
        // 次序是有意的：内容消费钩子 [onIdleTapContent] 必须**先**问——
        // 学习段体本身也是内容（同一次按下 [isEditContent] 即为真），若先
        // 取消就再也轮不到消费，学习段点选会一并失效。
        _tapArbiter.cancel();
        return;
      }
      _tapArbiter.handleSessionEnd(
        pointerCount: pointerCount,
        position: startFocal,
        idleTap: wasIdleTap,
        pointersStillDown: _downPoints.isNotEmpty,
      );
    });
  }

  /// 行级点按层空白命中的落穿入口：行级 tap 识别器赢得 arena 后，
  /// 把本次**空白**单击交回带级空白 tap 仲裁（同一个 [_tapArbiter] 实例、
  /// 同一份约 300ms 判定窗口）——行级层不复刻第二份双击/收起判定。指针被
  /// 系统取消或有指针仍在按下时不是单击。
  void forwardRowBlankTap(Offset position) {
    if (_sawPointerCancel || _downPoints.isNotEmpty) return;
    _tapArbiter.handleSessionEnd(
      pointerCount: 1,
      position: position,
      idleTap: true,
      pointersStillDown: false,
    );
  }

  /// 宿主销毁时调用：取消待定 tap 判定窗口。
  void dispose() => _tapArbiter.dispose();
}
