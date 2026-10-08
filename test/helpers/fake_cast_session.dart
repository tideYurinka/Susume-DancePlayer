import 'dart:async';

import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_session.dart';

/// 脚本化的假会话建立口：按脚本给出会话、按脚本拒绝连接、可挂起；并记录
/// 每条遥控的调用与参数——投屏准备面板、投屏态、倍速切换与失败面全部经它
/// 测，不碰真网络。照 `fake_update_gateway.dart` 的既有范式。
class FakeCastSessionFactory implements CastSessionFactory {
  /// 建立的会话，按顺序（每次 connect 新建一条）。
  final List<FakeCastSession> sessions = [];

  /// [connect] 的调用次数与最后一次接的接收端。
  int connectCalls = 0;
  CastReceiver? lastReceiver;

  /// 非 null 时 [connect] 抛出它（连不上用例）。
  Object? connectError;

  /// 非 null 时 [connect] 挂在它上面（连接在飞用例放行用）。
  Completer<void>? connectGate;

  /// 非 null 时新会话的字段按它布景。
  void Function(FakeCastSession session)? configure;

  @override
  Future<CastSession> connect(CastReceiver receiver) async {
    connectCalls++;
    lastReceiver = receiver;
    final gate = connectGate;
    if (gate != null) await gate.future;
    final error = connectError;
    if (error != null) throw error;
    final session = FakeCastSession(receiver);
    configure?.call(session);
    sessions.add(session);
    return session;
  }
}

/// 脚本化的假投屏会话：记录每一条遥控的顺序与参数，可注入失败（拒播 /
/// 掉线），支持的动作、音量、位置与播放状态都可脚本化。
class FakeCastSession implements CastSession {
  FakeCastSession(this.receiver);

  @override
  final CastReceiver receiver;

  /// 被调用过的动作名，按顺序（`push` / `play` / `pause` / `stop` / `seek`
  /// / `setVolume` / `volume` / `position` / `playbackState` /
  /// `supportedTransportActions` / `disconnect`）。
  final List<String> calls = [];

  Uri? pushedUri;

  /// 每一次跳转与设音量给的参数。
  final List<Duration> seeks = [];
  final List<double> volumes = [];

  /// 非 null 时所有**遥控动作**抛出它（拒播或掉线用例）。
  Object? actionError;

  /// 非 null 时只有 [push] 抛出它（推片被拒用例）。
  Object? pushError;

  /// [supportedTransportActions] 的返回值。
  CastTransportActions reportedActions = const CastTransportActions.none();

  /// 非 null 时 [supportedTransportActions] 抛出它（探测失败用例，真实实现
  /// 会静默降级成空集）。
  Object? actionsError;

  Duration reportedPosition = Duration.zero;
  CastPlaybackState reportedState = CastPlaybackState.playing;
  double reportedVolume = 0.5;

  /// 非 null 时读音量抛出它（设备不报音量用例）。
  Object? volumeError;

  int disconnectCalls = 0;
  bool get disconnected => disconnectCalls > 0;

  /// 非 null 时 [disconnect] 抛出它（收尾失败用例：停服不该被它挡住）。
  Object? disconnectError;

  /// 非 null 时 [disconnect] 挂在它上面（「停服不等收尾回应」用例放行用）。
  Completer<void>? disconnectGate;

  void _check(String name, {Object? failure}) {
    calls.add(name);
    final error = failure ?? actionError;
    if (error != null) throw error;
  }

  @override
  Future<void> push(Uri source) async {
    _check('push', failure: pushError);
    pushedUri = source;
  }

  @override
  Future<void> play() async => _check('play');

  @override
  Future<void> pause() async => _check('pause');

  @override
  Future<void> stop() async => _check('stop');

  @override
  Future<void> seek(Duration position) async {
    _check('seek');
    seeks.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _check('setVolume');
    volumes.add(volume);
  }

  @override
  Future<double> volume() async {
    _check('volume');
    final error = volumeError;
    if (error != null) throw error;
    return reportedVolume;
  }

  @override
  Future<Duration> position() async {
    _check('position');
    return reportedPosition;
  }

  @override
  Future<CastPlaybackState> playbackState() async {
    _check('playbackState');
    return reportedState;
  }

  @override
  Future<CastTransportActions> supportedTransportActions() async {
    calls.add('supportedTransportActions');
    final error = actionsError;
    if (error != null) throw error;
    return reportedActions;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    final gate = disconnectGate;
    if (gate != null) await gate.future;
    final error = disconnectError;
    if (error != null) throw error;
  }
}
