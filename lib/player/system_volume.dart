import 'dart:async';

import 'package:flutter/services.dart';

/// 系统媒体音量控制接缝（可注入，widget 测试断言用）。
///
/// 播放器右半屏上下滑调**系统媒体音量**（与侧键同源，Android
/// `AudioManager STREAM_MUSIC`，节拍/前导声 USAGE_MEDIA 同流跟随）：
/// 手势层只依赖本接口，真实实现走平台通道；测试注入 fake 记录调用
/// （`test/helpers/fake_system_volume.dart`）。
abstract interface class SystemMediaVolumeController {
  /// 当前系统媒体音量（0..1 归一化，按平台当前值/最大值换算）；读取失败
  /// 抛错由调用方兜底。
  Future<double> get volume;

  /// 设置系统媒体音量（0..1，越界钳制后按平台最大刻度取整写入）。
  Future<void> setVolume(double value);

  /// 系统媒体音量变化流（含侧键等应用外来源）：每次变化发出归一化新值。
  /// 广播流，不缓存现值，消费方以边沿为准。
  Stream<double> get volumeStream;
}

/// 真实实现：平台通道 `dance_learning_app/system_media_volume`
/// （Android 原生 AudioManager STREAM_MUSIC；见
/// `android/.../SystemMediaVolumePlugin.kt`）。
class PlatformSystemMediaVolumeController
    implements SystemMediaVolumeController {
  static const MethodChannel _channel = MethodChannel(
    'dance_learning_app/system_media_volume',
  );
  static const EventChannel _eventChannel = EventChannel(
    'dance_learning_app/system_media_volume_events',
  );

  double _ratio(int volume, int max) => max <= 0 ? 0.0 : volume / max;

  @override
  Future<double> get volume async {
    final args = await _channel.invokeMapMethod<String, int>('get');
    if (args == null) throw StateError('系统媒体音量读取失败');
    return _ratio(
      args['volume'] ?? 0,
      args['max'] ?? 0,
    ).clamp(0.0, 1.0);
  }

  @override
  Future<void> setVolume(double value) {
    return _channel.invokeMethod<void>('set', {
      'volume': value.clamp(0.0, 1.0),
    });
  }

  @override
  Stream<double> get volumeStream {
    // 经自管广播流包装：平台通道未注册（非 Android/测试环境）时流激活的
    // MissingPluginException 在此静默承接（消费方零行为，播放不受阻），
    // 不向 widget 层冒泡。
    late final StreamController<double> controller;
    StreamSubscription<dynamic>? subscription;
    controller = StreamController<double>.broadcast(
      onListen: () {
        subscription = _eventChannel.receiveBroadcastStream().listen(
          (event) => controller.add(_decode(event)),
          onError: (Object _) {},
          cancelOnError: false,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  double _decode(Object? event) {
    final args = event as Map;
    return _ratio(
      (args['volume'] as num?)?.toInt() ?? 0,
      (args['max'] as num?)?.toInt() ?? 0,
    ).clamp(0.0, 1.0);
  }
}
