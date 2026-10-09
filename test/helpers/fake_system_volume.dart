import 'dart:async';

import 'package:dance_learning_app/player/system_volume.dart';

/// 记录调用的假系统媒体音量控制器（右半屏音量手势断言用）。
class FakeSystemMediaVolumeController implements SystemMediaVolumeController {
  FakeSystemMediaVolumeController({this.currentVolume = 0.5});

  /// 当前系统媒体音量（0..1），初始可指定；[setVolume] 会更新它。
  double currentVolume;

  /// 每次 [setVolume] 收到的值（按调用顺序，钳制前原值不记录——与真实
  /// 控制器一致：写入口即钳制语义）。
  final List<double> setCalls = [];

  /// 读当前音量（[volume]）被问过几次——断言「投屏态那个值来自哪一次探测、
  /// 有没有再多问一遍控制器」用。
  int readCalls = 0;

  final StreamController<double> _changes =
      StreamController<double>.broadcast();

  @override
  Future<double> get volume async {
    readCalls++;
    return currentVolume;
  }

  @override
  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    setCalls.add(clamped);
    currentVolume = clamped;
  }

  @override
  Stream<double> get volumeStream => _changes.stream;

  /// 测试直呼：模拟应用外音量变化（侧键等），经 [volumeStream] 广播并
  /// 更新现值（与真实系统行为一致：流事件即新现值）。
  void emitExternal(double value) {
    final clamped = value.clamp(0.0, 1.0);
    currentVolume = clamped;
    _changes.add(clamped);
  }
}
