import 'dart:async';

import 'package:dance_learning_app/cast/cast_receiver.dart';

/// 脚本化的假发现：逐次给出接收端名单（或"取不到"/挂起），并记录被调用了
/// 几次、每次给的等待时长——注入后即可脚本化「搜到几台 / 一台都没有 / 发现
/// 出错」三态。照 `fake_update_gateway.dart` 的既有范式。
class FakeCastReceiverDiscovery implements CastReceiverDiscovery {
  FakeCastReceiverDiscovery({this.script = const []});

  /// [discover] 的逐次脚本（用尽后返回空表）。
  final List<List<CastReceiver>> script;
  int _index = 0;

  /// [discover] 的调用次数与最后一次的等待时长：断言「重扫就是再调一次」。
  int discoverCalls = 0;
  Duration? lastTimeout;

  /// 非 null 时 [discover] 抛出它（替身注入失败）。
  Object? error;

  /// 非 null 时 [discover] 挂起等它完成（检查在飞的发现再按一次的用例）。
  Completer<void>? gate;

  @override
  Future<List<CastReceiver>> discover({
    Duration timeout = kCastDiscoveryTimeout,
  }) async {
    discoverCalls++;
    lastTimeout = timeout;
    final pending = gate;
    if (pending != null) await pending.future;
    final failure = error;
    if (failure != null) throw failure;
    if (_index < script.length) return script[_index++];
    return const [];
  }
}
