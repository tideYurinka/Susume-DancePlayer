import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine.dart';
import 'package:flutter/widgets.dart';

import 'video_surface.dart';

/// 测试用 FakeEngine：实现 [PlaybackEngine]，不依赖真实解码。
///
/// 时间推进基于 Dart 定时器：播放期间每 100ms 推进 `100ms × rate`，
/// 在 flutter_test / fake_async 的 fake 时钟下由 `tester.pump` /
/// `fakeAsync.elapse` 驱动。
///
/// 除接口成员外，额外暴露 `source` / `position` / `isDisposed` 供测试断言，
/// `seekCalls`（按序记录 seek 目标）与 `callLog`（按序记录 play/pause/seek
/// 调用，scrub 暂停/恢复顺序断言用）。
/// [videoAspectRatio] 可构造时指定，供播放器 contain 布局测试用。
class FakePlaybackEngine implements PlaybackEngine {
  FakePlaybackEngine({Duration? duration, this.videoAspectRatio, this.videoFps})
    : _duration = duration ?? const Duration(minutes: 3);

  /// 推进节拍：每拍推进 100ms × rate。
  static const Duration tick = Duration(milliseconds: 100);

  final Duration _duration;

  /// 视频画面宽高比（测试可指定；null 表示未知，渲染层回退为填满）。
  /// 非 final：竖屏骨架用例模拟「首帧就绪后宽高比落定」。
  @override
  double? videoAspectRatio;

  /// 视频帧率（测试可指定 demux-fps 用例；null = 未知 → UI 回落 30fps）。
  @override
  final double? videoFps;

  Duration _position = Duration.zero;
  double _rate = 1.0;
  bool _playing = false;
  bool _disposed = false;
  Uri? _source;
  Timer? _ticker;

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completedController =
      StreamController<void>.broadcast();
  final StreamController<bool> _playingController =
      StreamController<bool>.broadcast();

  /// 唯一的播放态写入点：赋值同时发出 isPlaying 边沿（记录器消费）。
  void _setPlaying(bool playing) {
    if (_playing == playing) return;
    _playing = playing;
    _playingController.add(playing);
  }

  /// 测试直呼：模拟播放到尾（不经定时器推进）——转暂停、发 completed 与
  /// isPlaying=false 边沿（与 [_onTick] 到尾分支同语义）。未在播时 no-op。
  void simulateCompleted() {
    if (!_playing) return;
    _setPlaying(false);
    _ticker?.cancel();
    _ticker = null;
    _completedController.add(null);
  }

  /// 最近一次 [open] 的 source（测试断言用）。
  Uri? get source => _source;

  /// 每次 [seek] 收到的目标位置（按调用顺序，测试断言钳制用）。
  final List<Duration> seekCalls = [];

  /// 引擎方法调用序列（play/pause/seek，测试断言 scrub 暂停/恢复顺序用：
  /// 轴锁定后先 pause 再 seek、松手后 play 从落点继续）。
  final List<String> callLog = [];

  /// seek 在途时长（默认零 = 立即落定）。起播守卫类用例（被取消的
  /// 激活不得在 seek 落定后起播）用它把「seek 未落定」的窗口拉长到可断言；
  /// 与相机替身的 `startRecordingLatency` 同款手法。零值时不留任何 await，
  /// 既有用例时序不变。
  Duration seekLatency = Duration.zero;

  /// 当前播放位置（同步读取，测试断言用）。
  @override
  Duration get position => _position;

  /// 是否已 [dispose]（测试断言用）。
  bool get isDisposed => _disposed;

  @override
  double get rate => _rate;

  @override
  bool get isPlaying => _playing;

  @override
  Duration? get duration => _duration;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<void> get completedStream => _completedController.stream;

  @override
  Stream<bool> get isPlayingStream => _playingController.stream;

  @override
  Future<void> open(Uri source, {bool play = false}) async {
    // 取消在途 ticker：打开新源时旧播放节拍不得继续推进/发 completed。
    _ticker?.cancel();
    _ticker = null;
    _setPlaying(false);
    _source = source;
    _position = Duration.zero;
    _positionController.add(_position);
    if (play) {
      await this.play();
    }
  }

  @override
  Future<void> play() async {
    _assertUsable();
    callLog.add('play');
    if (_playing) return;
    if (_position >= _duration) {
      // 播放到尾后再次 play：从头开始（与主流播放器一致）。
      _position = Duration.zero;
      _positionController.add(_position);
    }
    _setPlaying(true);
    _ticker ??= Timer.periodic(tick, _onTick);
  }

  @override
  Future<void> pause() async {
    callLog.add('pause');
    _setPlaying(false);
    _ticker?.cancel();
    _ticker = null;
  }

  void _onTick(Timer timer) {
    _position += tick * _rate;
    if (_position >= _duration) {
      _position = _duration;
      _setPlaying(false);
      timer.cancel();
      _ticker = null;
      _completedController.add(null);
    }
    _positionController.add(_position);
  }

  @override
  Future<void> seek(Duration position) async {
    callLog.add('seek');
    seekCalls.add(position);
    if (seekLatency > Duration.zero) {
      // 在途窗口（默认零值不 await，既有用例时序不变）：落位与位置事件都
      // 延后到窗口结束，模拟真机 seek 未落定。
      await Future<void>.delayed(seekLatency);
    }
    _position = _clamp(position);
    _positionController.add(_position);
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
  }

  /// 每次 [setAvSyncDelayMs] 收到的延迟值（按调用顺序，引擎 seam
  /// 断言用；callLog 同步记录 `avSync:<ms>`）。
  final List<int> avSyncDelayCalls = [];

  @override
  Future<void> setAvSyncDelayMs(int delayMs) async {
    avSyncDelayCalls.add(delayMs);
    callLog.add('avSync:$delayMs');
  }

  @override
  Widget buildVideoSurface() =>
      VideoSurfacePlaceholder(videoAspectRatio: videoAspectRatio);

  @override
  Future<void> dispose() async {
    if (_disposed) return; // 幂等
    _disposed = true;
    _setPlaying(false);
    _ticker?.cancel();
    _ticker = null;
    await _positionController.close();
    await _completedController.close();
    await _playingController.close();
  }

  Duration _clamp(Duration position) {
    if (position < Duration.zero) return Duration.zero;
    if (position > _duration) return _duration;
    return position;
  }

  void _assertUsable() {
    if (_disposed) {
      throw StateError('FakePlaybackEngine 已 dispose，不可再操作。');
    }
  }
}
