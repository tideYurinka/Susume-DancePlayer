/// EngineSeek：引擎与 seek/scrub 域。
///
/// 播放内核的持有与生命周期、seek 提交、拖动会话的起止都收在本域：
///
/// - **引擎生命周期**：`open`/`play`/`pause` 经本域调用引擎；`attach` 订阅
///   位置报位、播放态边沿与播放完成事件并转发给宿主回调，`detach` 取消三条
///   订阅（宿主收尾次序 = detach → pause，收尾期的播放态边沿不进入 UI 重建）；
/// - **seek 提交**：内部一只 [SeekSubmitter] 是各面唯一提交口（钳制 → 清循环
///   激活 → 串行入队 → 显示位/窗口跟随的固定次序由它收口）；
/// - **拖动会话**：内部一只 [ScrubSession] 承载定格预览 scrub 的
///   「暂停-基准-累计-恢复、取消回退」状态机，起止由本域编排；
/// - **接管事实**：接管期内拒绝 scrub——事实取自「录制期播放接管」域
///   （[RecordingPlaybackTakeover.active]），本域单向依赖它，其余播放面纪律
///   仍由接管域施加。
///
/// 引擎读取面经 [engine] 交出（画面构建、位置/时长/倍速/宽高比读数与兄弟域
/// 装配都消费同一只内核实例）；取消区几何、手势换算与相位显示留在宿主。
///
/// 依赖方向（单向）：本域 → 引擎接缝、[SeekSubmitter]、[ScrubSession]、
/// [RecordingPlaybackTakeover]、[GestureFeedbackController]；反向无——构造收
/// 显式闭包，不读构建上下文、不注容器，可在无 ProviderScope 下直测。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../annotation/annotation_timeline.dart';
import '../core/playback/playback_engine.dart';
import 'cast_mirror.dart';
import 'gesture_feedback.dart';
import 'recording_playback_takeover.dart';
import 'scrub_session.dart';
import '../core/playback/seek_submitter.dart';

/// 引擎与 seek/scrub 域（会话域：无 widget）。
class EngineSeek {
  EngineSeek({
    required this.engine,
    required RecordingPlaybackTakeover Function() takeoverOf,
    required AnnotationTimeline Function() timeline,
    required void Function(AnnotationTimeline timeline, Duration position)
    clearLoops,
    required void Function() interruptPendingDelayedPlay,
    required void Function(Duration target) onScrubCommitted,
    required this.feedback,
    required this.scrubTarget,
    required void Function(bool playing) onPlayingEdge,
    required void Function() onPosition,
    required Future<void> Function() onCompleted,
    required bool Function() isMounted,
    required CastMirror Function() castMirrorOf,
  }) : _resolveTakeover = takeoverOf,
       _positionTick = onPosition,
       _playingEdge = onPlayingEdge,
       _completed = onCompleted,
       _hostAlive = isMounted,
       _resolveCastMirror = castMirrorOf {
    _submitter = SeekSubmitter(
      engineSeek: (target) {
        // 任何 seek 都打断在途延迟起播：撤锚并
        // 作废在途预备，本次 seek 本身照常执行。
        interruptPendingDelayedPlay();
        return engine.seek(target);
      },
      total: () => engine.duration,
      timeline: timeline,
      clearLoops: clearLoops,
    );
    _scrubSession = ScrubSession(
      seek: _submitter,
      pause: engine.pause,
      play: engine.play,
      isPlaying: () => engine.isPlaying,
      position: () => engine.position,
      onCommit: onScrubCommitted,
      feedback: feedback,
      indicator: scrubTarget,
      cancelZoneEnabled: true,
      // 时长未知时 scrub 照常工作：不设时长门，钳制由提交口的 ≥0 分支兜底。
      requireKnownDuration: false,
    );
  }

  /// 播放内核（画面构建、位置/时长/倍速/宽高比读数与兄弟域装配的唯一来源）。
  final PlaybackEngine engine;

  /// 手势反馈相位控制器（scrubbing 相位由拖动会话驱动）。
  final GestureFeedbackController feedback;

  /// scrub 显示位（指示浮层目标值的唯一来源，与入队 seek 同源）。
  final ValueNotifier<Duration> scrubTarget;

  final RecordingPlaybackTakeover Function() _resolveTakeover;
  final void Function() _positionTick;
  final void Function(bool playing) _playingEdge;
  final Future<void> Function() _completed;
  final bool Function() _hostAlive;

  /// 投屏遥控镜像（见 [CastMirror]）：**投屏态内非空**，本机播放 / 暂停 /
  /// 跳转同时作用于接收端；未投屏给 [NoCastMirror]（空操作）。失败由镜像
  /// 口自己收口——本域不判投屏态、也不为它改变本机动作。
  final CastMirror Function() _resolveCastMirror;

  /// 当前镜像口。
  CastMirror get _castMirror => _resolveCastMirror();

  /// 镜像一次播放 / 暂停：**不 await**——遥控是旁路，本机播放不因一次网络
  /// 往返变慢；失败由镜像口自己收口（本口不抛）。
  void _mirrorPlay() => unawaited(_castMirror.play());

  void _mirrorPause() => unawaited(_castMirror.pause());

  void _mirrorSeek(Duration target) => unawaited(_castMirror.seek(target));

  late final SeekSubmitter _submitter;
  late final ScrubSession _scrubSession;

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<void>? _completedSubscription;

  /// 引擎三条流的订阅入口——位置报位、播放态边沿
  /// （[PlaybackEngine.isPlayingStream]）与播放完成事件
  /// （[PlaybackEngine.completedStream]）；重复调用幂等（已有订阅时不重建）。
  void attach() {
    _positionSubscription ??= engine.positionStream.listen(
      (_) => _positionTick(),
    );
    _playingSubscription ??= engine.isPlayingStream.listen(_playingEdge);
    _completedSubscription ??= engine.completedStream.listen((_) {
      unawaited(_completed());
    });
  }

  /// 取消三条引擎流订阅（宿主的收尾次序 = detach → pause，收尾期的播放态
  /// 边沿不进入 UI 重建），随后 [attach] 可再次接线。
  void detach() {
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _positionSubscription = null;
    _playingSubscription = null;
    _completedSubscription = null;
  }

  /// 打开 [source]；[play] 为 true 时打开即起播。
  Future<void> open(Uri source, {bool play = false}) =>
      engine.open(source, play: play);

  /// 播放（本机照常 + 投屏镜像；镜像口未接投屏时是空操作）。
  Future<void> play() {
    _mirrorPlay();
    return engine.play();
  }

  /// 暂停（本机照常 + 投屏镜像）。拖动会话内部用的是**内核**自己的
  /// pause/play（定格-恢复不走本入口），故拖动期间不会把电视也按停。
  Future<void> pause() {
    _mirrorPause();
    return engine.pause();
  }

  /// 录制期（含准备期）事实：取自接管域，供宿主拒绝播放类动作。
  bool get takenOver => _resolveTakeover().active;

  /// 拖动会话是否激活。
  bool get scrubbing => _scrubSession.isActive;

  /// seek 单发：钳制后入队，返回钳制后实际入队值；落点同时镜像给接收端
  /// （三指跳转、学习段跳段首一类单发 seek 因此也作用于电视）。
  Duration seek(Duration target) {
    final landed = _submitter.submit(target);
    _mirrorSeek(landed);
    return landed;
  }

  /// seek 单发并等队列排空（「seek 落定后再续播」类顺序语义）；落点同样
  /// 镜像给接收端。
  Future<void> seekAndSettle(Duration target) async {
    await _submitter.submitAndSettle(target);
    _mirrorSeek(target);
  }

  /// 起拖动会话（在播先暂停定格，基准 = 定格点快照；返回值 false = 时长未知
  /// 未起会话，调用方丢弃本帧）。
  Future<bool> beginScrub() => _scrubSession.begin();

  /// 逐帧推进拖动目标（基准 + 累计，钳制经 seek 提交口）。
  void moveScrubBy(Duration delta) => _scrubSession.moveBy(delta);

  /// 结束拖动会话：恢复手势前播放态、[cancel] 时回退到定格基准；宿主已收尾
  /// 或会话未激活时 no-op（幂等）。
  ///
  /// **拖动收口只镜像一次**：逐帧拖动的高频 seek 不发往接收端（那会变成
  /// 一串 SOAP），手指离手后按最终落点（显示位，`cancel` 时已回退到基准）
  /// 让电视跳一次。
  Future<void> endScrub({bool cancel = false}) async {
    if (!_hostAlive() || !_scrubSession.isActive) return;
    await _scrubSession.end(cancel: cancel);
    _mirrorSeek(scrubTarget.value);
  }
}
