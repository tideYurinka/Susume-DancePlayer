/// 播放手势仲裁域。
///
/// 播放页那段「一次手势会话怎么判、判完交给谁」的仲裁收在本域：
///
/// - **轴锁**：单/双指横向拖动与纵向音量亮度分支由 [PlayerGestureInterpreter]
///   按累计位移锁定轴向，灵敏度按**起始**手指数换算；
/// - **突发指针锁定**：以「首指按下 → 全部抬起」为一个 burst 跟踪原始指针
///   （不经 gesture arena）——scale 识别器抬指后的 onEnd+onStart 重启被识别为
///   同一 burst：不重取基准、不降档、三指跳转守卫不提前清；
/// - **取消区语义**：进度拖动期间手指焦点进入**画面矩形左上角的四分之一圆
///   扇形**（圆心与半径经输入值对象的现读闭包取得）即「待取消」，
///   松手回退到定格快照；进出逐帧跟踪；
/// - **三指跳转**：并入 scale 流程，横向累计位移首次过阈一次性跳转（左首右尾，
///   取最近分段线，无分段线回退首/尾边界）；
/// - **长按二倍速**：单指长按阈值到进入临时倍率、松开恢复（取景调节态停用）；
/// - **取景手势分支**：取景调节态内整场手势交给取景域会话（进入/调节/结束），
///   本条守卫排在「同一 burst 识别器重启保持原会话」的早退之前。
///
/// ## 接口
///
/// 入口是**一个**显式的输入值对象 [GestureArbitrationInput]（层域入口形状，
/// 沿画面层 `PictureLayerInput` 样板）：这一层要的目标域句柄、
/// 读取闭包与回调都在它的字段清单里，加一项输入只改值对象与装配点。播放页
/// 只做接线：把域实例的识别器与回调交给画面层手势件（[doubleTapRecognizer] /
/// [longPressRecognizer] / [onScaleStart] / [onScaleUpdate] / [onScaleEnd] /
/// [onPointerDown] / [onPointerUp] / [onPointerCancel]），把系统级指针取消接给
/// [onSystemPointerCancel]，浮层专属的起手/逐帧/收尾时机经输入钩子转发。
///
/// ## 依赖方向（单向）
///
/// 本域 → 取景域（[FramingSessionHost]）、亮度音量域（[LevelControl]）、
/// 拖动会话（[EngineSeek]）、录制期播放接管域（[RecordingPlaybackTakeover]）、
/// 编辑器入口域（[EditorEntry]）；五个目标域均不反向依赖本域。其余跨域事实
/// （视口尺寸、时间线、倍速瞬态、浮层钩子、单击/双击语义）全部经输入值对象的
/// 显式闭包取得——本域不 import 播放页、不 import 中枢、
/// 不读构建上下文、不注容器，可在无 ProviderScope 下直测。
library;

import 'dart:async';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/gestures.dart'
    show
        LongPressEndDetails,
        LongPressGestureRecognizer,
        LongPressStartDetails,
        PointerCancelEvent,
        PointerDownEvent,
        PointerUpEvent,
        ScaleEndDetails,
        ScaleStartDetails,
        ScaleUpdateDetails;

import '../annotation/annotation_timeline.dart';
import '../cast/cast_session.dart' show CastRemoteItem;
import 'editor_skeleton.dart' show focalInCancelZone;
import 'advanced_gestures.dart' show PlayerDoubleTapGestureRecognizer;
import 'editor_entry.dart';
import 'engine_seek.dart';
import 'framing_session.dart';
import 'gesture_feedback.dart' show GestureFeedbackController, LevelAdjustKind;
import 'gestures.dart'
    show
        PlayerGestureActionType,
        PlayerGestureAxis,
        PlayerGestureInterpreter,
        SystemGestureYieldInsets,
        kLongPressDoubleSpeedTimeout,
        kThreeFingerJumpThresholdPx,
        seekDeltaFor,
        yieldedAxes;
import 'level_control.dart';
import 'notice.dart' show NoticeId;
import 'presentation_session.dart';
import 'recording_playback_takeover.dart';
import 'segment_jump.dart';

/// 手势仲裁输入：本层挂载所需的全部外部事实（见库头契约）。
///
/// 五个目标域句柄 + 反馈相位控制器 + 宿主事实闭包（视口、时间线、倍速瞬态、
/// 单击/双击语义、浮层时机钩子）一次给全。形状即「这一层需要什么」的可读清单。
class GestureArbitrationInput {
  const GestureArbitrationInput({
    required this.engineSeek,
    required this.level,
    required this.framing,
    required this.editorEntry,
    required this.takeover,
    required this.feedback,
    required this.isFramingActive,
    required this.isControlOpen,
    required this.isMounted,
    required this.viewportSize,
    required this.pictureRect,
    required this.yieldSystemInsets,
    required this.readTimeline,
    required this.beginTransientRate,
    required this.endTransientRate,
    required this.onDoubleTap,
    required this.onTwoFingerDoubleTap,
    required this.castRemoteItemShown,
    required this.writeThreeFingerDirection,
    required this.showNotice,
    required this.presentation,
  });

  /// 拖动会话与引擎（进度拖动、三指跳转落点、播放态读面）。
  final EngineSeek engineSeek;

  /// 亮度音量域（纵向滑分支写回）。
  final LevelControl level;

  /// 取景域会话（取景手势分支）。
  final FramingSessionHost framing;

  /// 编辑器入口域（单击画面唤出控制层）。
  final EditorEntry editorEntry;

  /// 录制期播放接管域（接管期拒绝播放类手势）。
  final RecordingPlaybackTakeover takeover;

  /// 手势反馈相位控制器（scrubbing/levelAdjust 与取消区待取消态）。
  final GestureFeedbackController feedback;

  /// 取景调节态谓词（模式值 = 第三值 `compareFraming`）。
  final bool Function() isFramingActive;

  /// 控制层是否展开（单击唤出与浮层捏合的前置）。
  final bool Function() isControlOpen;

  /// 三指跳转方向注入点写入：跳转触发的那一处把
  /// 方向写进注入点，提示内容声明经它读取。
  final void Function(ThreeFingerSwipeDirection direction)
  writeThreeFingerDirection;

  /// 短暂提示触发面：只报身份，不持控制器。
  final void Function(NoticeId id) showNotice;

  /// 宿主是否仍在树上。
  final bool Function() isMounted;

  /// 手势作用区尺寸（音量/亮度归一化与横向起点分侧用）。
  final Size Function() viewportSize;

  /// 画面矩形**现读**闭包：组合根解一次的矩形（未经取景变换、屏幕坐标），
  /// 取消区判定按它的左上角与 [cancelZoneRadius] 半径走——域内不重写
  /// contain 算术。现读：拖动中途旋转屏幕 / 切换控制层开合时按同一条规则
  /// 重算。
  final Rect Function() pictureRect;

  /// 系统手势内缩现读闭包：组合根解一次上报值、经几何纯件算出让路区，
  /// 转屏与窗口变化后按新值重算；null = 宿主未给出让路区，一律不让路。
  final SystemGestureYieldInsets? Function() yieldSystemInsets;

  /// 有效标注时间线（三指跳转的分段线与首尾边界）。
  final AnnotationTimeline Function() readTimeline;

  /// 进入临时倍率（长按 2× 阈值到）。
  final Future<void> Function() beginTransientRate;

  /// 结束临时倍率（松开/指针取消/离页收尾，幂等）。
  final Future<void> Function() endTransientRate;

  /// 单指双击（页面接管：录制接管与播放态取反；取景守卫与浮层命中在
  /// [_handleDoubleTap] 内先行裁决）。
  final Future<void> Function() onDoubleTap;

  /// 双指双击（页面接管：延迟播放触发）。
  final void Function() onTwoFingerDoubleTap;

  /// 投屏态下某一枚遥控项显不显示（票 #38；唯一判据 = `CastRemoteControls`，
  /// 见 `lib/cast/cast_session.dart` 的 [CastRemoteItem]）。**非投屏态恒 true**
  /// ——本域不因投屏判据改动非投屏行为。判据说「不显示」的那一项：手势整段
  /// 吞掉（不写本机、不发遥控、不画反馈），与界面上那枚控件离场同一口径。
  final bool Function(CastRemoteItem item) castRemoteItemShown;

  /// 演出层会话：浮层选中/混区/全局缩放状态机与提示钩子都自持在它里面，
  /// 本域单向调用（演出层不反向 import 本域）。
  final PresentationSession presentation;
}

/// 播放手势仲裁域（层域：手势件骨架留在画面层，本域持有仲裁）。
class GestureArbitration {
  GestureArbitration({required this.input}) {
    _doubleTapRecognizer = PlayerDoubleTapGestureRecognizer()
      ..onDoubleTap = _handleDoubleTap
      ..onTwoFingerDoubleTap = input.onTwoFingerDoubleTap
      ..onSingleTap = _handleSingleTap;
    _longPressRecognizer =
        LongPressGestureRecognizer(duration: kLongPressDoubleSpeedTimeout)
          ..onLongPressStart = _handleLongPressStart
          ..onLongPressEnd = _handleLongPressEnd;
  }

  /// 本层挂载所需的全部外部事实（见 [GestureArbitrationInput]）。
  final GestureArbitrationInput input;

  EngineSeek get _engineSeek => input.engineSeek;
  LevelControl get _level => input.level;
  FramingSessionHost get _framing => input.framing;
  EditorEntry get _editorEntry => input.editorEntry;
  RecordingPlaybackTakeover get _takeover => input.takeover;
  GestureFeedbackController get _feedback => input.feedback;

  /// 双击类识别器（单指双击暂停/播放、双指双击延迟播放、孤立单击唤出）。
  late final PlayerDoubleTapGestureRecognizer _doubleTapRecognizer;

  /// 全屏单指长按 2× 识别器。
  late final LongPressGestureRecognizer _longPressRecognizer;

  /// 基础手势解释器（一次手势会话一个，跨 start/update/end 保持）。
  final PlayerGestureInterpreter _interpreter = PlayerGestureInterpreter();

  /// 本次 burst 内在按的原始指针集合（首指按下 → 全部抬起）。
  final Set<int> _burstPointers = <int>{};

  /// 本次 burst 首指按下位置（浮层命中判定：单击/双击仲裁不携带位置）。
  Offset? _firstDownPosition;

  /// 本 burst 内是否已开过 scale 手势会话：首个 onStart 为会话起点，同 burst
  /// 内识别器重启产生的后续 onStart 一律忽略（取景分支例外，见 [onScaleStart]）。
  bool _burstScaleStarted = false;

  /// 本次手势起始手指数（灵敏度换算用；与解释器轴向分支同源）。
  int _pointerCount = 1;

  /// 本次会话被禁的轴（系统手势让路）：起手判定在会话开始时
  /// 按本 burst 首指按下位置定一次，整场不变。
  Set<PlayerGestureAxis> _yieldedAxes = const {};

  /// 本 burst 是否被系统取消：画面层收到
  /// 指针取消或页面层兜底回调均幂等置位；收尾按取消语义走，与会话开始时
  /// 复位。
  bool _systemCancelled = false;

  /// 手势作用区高度（音量/亮度归一化用）。
  double _areaHeight = 1.0;

  /// 三指滑动累计横向位移与是否已跳转。
  double _threeFingerAccDx = 0;
  bool _threeFingerJumped = false;

  /// 双击类识别器（画面层手势件接线用）。
  PlayerDoubleTapGestureRecognizer get doubleTapRecognizer =>
      _doubleTapRecognizer;

  /// 长按 2× 识别器（画面层手势件接线用）。
  LongPressGestureRecognizer get longPressRecognizer => _longPressRecognizer;

  // ---- scale 流程 ----

  /// 本 burst 的被禁轴集合：判定点是首指按下位置，起手点缺失
  /// 或宿主未给出让路区时不让路。
  Set<PlayerGestureAxis> _burstYieldedAxes() {
    final insets = input.yieldSystemInsets();
    if (insets == null) return const {};
    return yieldedAxes(
      downPosition: _firstDownPosition,
      screen: input.viewportSize(),
      insets: insets,
    );
  }

  /// 手势开始：取景分支优先（绝对值型，识别器重启须重取基准），其余按
  /// burst 首次开会话处理。
  void onScaleStart(ScaleStartDetails details) {
    if (input.isFramingActive()) {
      // 平移让路判定：起手为单指且本 burst 首指按下点落在让路区 → 本次
      // 会话的建框帧不写取景取值（多指起手同样不写值）。
      final panYielded =
          details.pointerCount == 1 && _burstYieldedAxes().isNotEmpty;
      _framing.begin(
        focal: details.focalPoint,
        pointerCount: details.pointerCount,
        panYielded: panYielded,
      );
      _burstScaleStarted = true;
      return;
    }
    if (_burstScaleStarted) return; // 同 burst 内识别器重启：保持原会话。
    _burstScaleStarted = true;
    input.presentation.onGestureSessionStarted(details);
    _pointerCount = details.pointerCount;
    final size = input.viewportSize();
    _areaHeight = size.height;
    // 起手让路判定：判定点是本 burst 首指按下位置，起手点
    // 缺失或宿主未给出让路区时不让路。
    final yielded = _burstYieldedAxes();
    _yieldedAxes = yielded;
    _interpreter.start(
      pointerCount: details.pointerCount,
      startX: details.focalPoint.dx,
      screenWidth: size.width,
      yieldedAxes: yielded,
    );
    _threeFingerAccDx = 0;
    _threeFingerJumped = false;
    // 本次手势起始手指数入反馈控制器（进度拖动灵敏度读面；只记录，不改
    // 任何手势行为）。
    _feedback.noteStartPointerCount(details.pointerCount);
    // 防御性复位：上一手势被系统取消而未走收尾时，先按取消语义结束滞留
    // 的反馈会话，再复位取消标记。
    _endActiveFeedbackSessions();
    _systemCancelled = false;
  }

  /// 手势更新：取景 → 浮层捏合 → 三指跳转 → 浮层平移 → 取消区 → 动作分支。
  Future<void> onScaleUpdate(ScaleUpdateDetails details) async {
    if (_framing.adjust(
      focal: details.focalPoint,
      pointerCount: details.pointerCount,
    )) {
      return;
    }
    if (input.presentation.tryConsumeOverlayPinchFrame(details)) return;
    if (_pointerCount >= 3) {
      // 三指：只一次性跳转，不逐帧 seek、不调音量/亮度；录制期不生效；
      // 水平被禁（左右让路区起手）时三指帧整段吞掉，不回落其它分支。
      if (_takeover.active) return;
      if (_yieldedAxes.contains(PlayerGestureAxis.horizontal)) return;
      _threeFingerAccDx += details.focalPointDelta.dx;
      if (!_threeFingerJumped &&
          _threeFingerAccDx.abs() >= kThreeFingerJumpThresholdPx) {
        _threeFingerJumped = true;
        _jumpThreeFinger(
          _threeFingerAccDx < 0
              ? ThreeFingerSwipeDirection.left
              : ThreeFingerSwipeDirection.right,
        );
      }
      return;
    }
    if (input.presentation.tryConsumeOverlayPanFrame(details)) return;
    _trackCancelZone(details.focalPoint);
    final action = _interpreter.update(
      dx: details.focalPointDelta.dx,
      dy: details.focalPointDelta.dy,
    );
    if (action == null) return;
    switch (action.type) {
      case PlayerGestureActionType.seek:
        // 投屏态内「进度」这一枚由接收端能力判据决定（票 #38）：判据说
        // 不显示就不动本机、不发遥控、不画拖动指示——按下去没反应的控制
        // 不留（非投屏态恒 true，行为逐位不变）。
        if (!input.castRemoteItemShown(CastRemoteItem.progress)) return;
        // 录制期不生效：scrub 起手会暂停引擎，而录制期源侧须恒 1.0× 在播。
        if (_takeover.active) return;
        if (!_feedback.isScrubbing) {
          // 会话内部固定次序：在播先 await pause → 基准 = 定格点快照 →
          // 指示位 = 基准；false = 时长未知（会话未激活则丢弃本帧）。
          await _engineSeek.beginScrub();
          _trackCancelZone(details.focalPoint);
        }
        if (!_engineSeek.scrubbing) return;
        final step = seekDeltaFor(action.deltaPx, _pointerCount);
        if (step == Duration.zero) return; // 纯纵向朝角区位移：不重复入队。
        _engineSeek.moveScrubBy(step);
      case PlayerGestureActionType.volume:
        // 投屏态内「音量」这一枚同上：接收端没有音量端点 / 探测失败 = 不
        // 显示（不出现滑条、不写接收端、也不动本机音量）。
        if (!input.castRemoteItemShown(CastRemoteItem.volume)) return;
        _feedback.showLevelAdjust(
          kind: LevelAdjustKind.volume,
          value: _level.adjustVolume(
            deltaPx: action.deltaPx,
            areaHeight: _areaHeight,
          ),
        );
      case PlayerGestureActionType.brightness:
        _feedback.showLevelAdjust(
          kind: LevelAdjustKind.brightness,
          value: _level.adjustBrightness(
            deltaPx: action.deltaPx,
            areaHeight: _areaHeight,
          ),
        );
    }
  }

  /// 手势结束：burst 未结束时是识别器重启的 onEnd，保持会话；全部抬起才收尾。
  Future<void> onScaleEnd(ScaleEndDetails details) async {
    if (_burstPointers.isNotEmpty) return;
    await _finishSession();
  }

  // ---- 原始指针 burst ----

  /// 画面层指针按下：跟踪 burst 首指并转发浮层簿记。
  void onPointerDown(PointerDownEvent event) {
    if (_burstPointers.isEmpty) _firstDownPosition = event.position;
    _burstPointers.add(event.pointer);
    input.presentation.onRawPointerDown(event);
  }

  /// 画面层指针抬起/取消：移出 burst，全部离开才收尾。
  void onPointerUp(PointerUpEvent event) => _pointerGone(event.pointer);

  /// 画面层指针被取消：认定本 burst 被系统取消，随后的收尾按取消语义走；
  /// 与页面层兜底回调的先后顺序无关（两者均幂等置位）。
  void onPointerCancel(PointerCancelEvent event) {
    _systemCancelled = true;
    _pointerGone(event.pointer);
  }

  void _pointerGone(int pointer) {
    if (_burstPointers.remove(pointer) && _burstPointers.isEmpty) {
      unawaited(_finishSession());
    }
    // 浮层混区簿记与 burst 同步摘除（指针未在跟踪集合内也要摘）。
    input.presentation.onRawPointerUp(pointer);
  }

  /// 系统级指针取消（顶层 Listener 兜底，本 Flutter 的 GestureDetector 无
  /// onScaleCancel 钩子）：同样置位取消标记并结束滞留会话（与画面层指针
  /// 取消的先后顺序无关，幂等）。
  void onSystemPointerCancel() {
    _systemCancelled = true;
    _endActiveFeedbackSessions();
    _level.endGestureSession(cancel: true);
    // 滞留 burst 簿记一并清理：兜底是唯一取消信号时，指针集合与会话状态
    // 不留到下一个手势（首指位置、解释器、识别器重启守卫均随收尾复位）。
    for (final pointer in _burstPointers.toList()) {
      _pointerGone(pointer);
    }
    unawaited(input.endTransientRate());
  }

  // ---- tap / 长按 ----

  /// 孤立单指单击：取景态交给取景域；否则先问浮层仲裁，再唤出编辑器入口。
  void _handleSingleTap() {
    if (!input.isMounted() || input.isControlOpen()) return;
    if (input.isFramingActive()) {
      _framing.handleTap(_firstDownPosition);
      return;
    }
    if (input.presentation.onOverlayTap(_firstDownPosition)) return;
    _editorEntry.requestEntry();
  }

  /// 孤立单指双击：取景调节态停用；落选中态浮层上的双击不进播放语义
  /// （选中态浮层只有选中与几何手势语义），其余交给页面（接管分支 + 播放
  /// 态取反）。**投屏态内「播放暂停」判据说这一项不显示时整段吞掉**（票
  /// #38）：与底排那枚播放键离场同一口径。
  void _handleDoubleTap() {
    if (input.isFramingActive()) return;
    if (!input.castRemoteItemShown(CastRemoteItem.playPause)) return;
    if (input.presentation.consumesOverlayDoubleTap(_firstDownPosition)) return;
    unawaited(input.onDoubleTap());
  }

  /// 长按阈值到：取景调节态停用；其余尝试进入临时 2×（在播才生效）。
  Future<void> _handleLongPressStart(LongPressStartDetails _) {
    if (input.isFramingActive()) return Future<void>.value();
    return input.beginTransientRate();
  }

  /// 长按松开：结束临时 2×、恢复手势前倍速。
  Future<void> _handleLongPressEnd(LongPressEndDetails _) =>
      input.endTransientRate();

  // ---- 收尾 ----

  /// 三指跳转：跳转到滑动方向时间轴上最近的一条**标记过**的分段线；
  /// 该方向无标记线时左滑回视频首、右滑回视频尾；只跳转，不新建/移动/删除标记。
  void _jumpThreeFinger(ThreeFingerSwipeDirection direction) {
    // 三指跳转也是「进度」这一枚遥控项（票 #38）：投屏态内接收端不支持
    // 跳转时整段不生效，也不写方向、不弹提示。
    if (!input.castRemoteItemShown(CastRemoteItem.progress)) return;
    final timeline = input.readTimeline();
    final target = threeFingerJumpTarget(
      direction: direction,
      currentPosition: _engineSeek.engine.position,
      segmentLines: flaggedSegmentLinePositions(timeline),
      videoStart: timeline.rangeStart,
      videoEnd: timeline.rangeEnd,
    );
    _engineSeek.seek(target);
    input.writeThreeFingerDirection(direction);
    input.showNotice(NoticeId.threeFingerToast);
  }

  /// 真正结束手势会话（burst 全部抬起 / 末指 onScaleEnd）：幂等。
  Future<void> _finishSession() async {
    if (!_burstScaleStarted) return;
    _burstScaleStarted = false;
    _framing.end();
    input.presentation.onGestureSessionEnded();
    _interpreter.end();
    // 单一收尾判定：被系统取消或进度拖动已进入待取消，都按取消语义收尾。
    final cancel = _systemCancelled || _feedback.cancelArmed;
    await _engineSeek.endScrub(cancel: cancel);
    _level.endGestureSession(cancel: cancel);
    _feedback.endLevelAdjust();
  }

  /// 收尾进行中的反馈会话：scrubbing 按取消标记恢复手势前播放态，
  /// levelAdjust 结束相位。
  void _endActiveFeedbackSessions() {
    if (_feedback.isScrubbing) {
      unawaited(
        _engineSeek.endScrub(cancel: _systemCancelled || _feedback.cancelArmed),
      );
    } else if (_feedback.isLevelAdjusting) {
      _feedback.endLevelAdjust();
    }
  }

  /// 进度拖动期间逐帧跟踪手指焦点进出取消区（进 → 浮层转警示「松开取消」，
  /// 出 → 恢复原样）；仅 scrubbing 相位有意义。判定＝画面矩形左上角四分之
  /// 一圆扇形，规则收在纯件 [focalInCancelZone]。
  void _trackCancelZone(Offset focal) {
    if (!_feedback.isScrubbing) return;
    _feedback.setCancelArmed(
      focalInCancelZone(pictureRect: input.pictureRect(), focal: focal),
    );
  }

  /// 宿主销毁时调用：取消待定 tap 判定窗口并释放两个识别器。
  void dispose() {
    _doubleTapRecognizer.dispose();
    _longPressRecognizer.dispose();
  }
}
