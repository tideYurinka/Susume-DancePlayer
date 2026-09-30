import 'dart:typed_data';

import 'package:dance_learning_app/player/beat_audio_native.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';

/// 假原生 sink（seam 注入，「消费 seam 时序」）：
/// 记录 sync/enqueue/flush/start/stop 与段加载，取时函数可推进；开流可置为
/// 先失败后成功（生命周期自愈用例）、可模拟原生「流已被错误关闭」状态。
///
/// 渲染器直测（`native_scheduled_audio_test.dart`）与页面部件测试
/// （`player_page_test.dart` 退后台停流）共用，避免两处各写一份假 sink。
class FakeBeatAudioSink implements BeatAudioSink {
  FakeBeatAudioSink({this.failStart = false});

  /// 段槽容量（默认 = 注册表派生的原生容量；模拟原生按 id 校验装载槽位）。
  int segmentCapacity = kMetronomeNativeSegmentCapacity;

  /// 开流是否失败（用例中途可改：先抛后成的自愈路径）。
  bool failStart;

  /// 原生「流已被错误关闭」状态（错误回调置位、**不关流**；成功开流清除）。
  bool lostByError = false;

  /// 重建原生输出流次数（路由切换恢复：旧流对象失效后必须换新对象）。
  int recoverCount = 0;

  /// 状态查询本身抛异常（真机实测：设备切换后连 streamLost 都报错——恢复
  /// 不能被探测异常挡死）。
  bool throwOnStreamLost = false;

  /// 原生是否接受入队（默认接受；置 false 模拟原生丢弃/拒绝）。
  bool acceptEnqueue = true;

  final List<({double mediaTimeMs, double rate, bool playing})> syncs = [];
  final List<({double beatMediaTimeMs, int segmentId, double volume})>
  enqueues = [];
  final List<({int segmentId, int sampleRate, int markerMs, int frames})>
  loads = [];

  /// 开流/停流/flush 的**调用序列**（退后台「flush + 停流 + 播放态下推」
  /// 类判据断言顺序用）。
  final List<String> calls = [];
  int flushCount = 0;

  /// 成功开流次数。
  int startCount = 0;

  /// 开流尝试次数（含失败）：断言「失败后仍会重试」。
  int startAttempts = 0;
  int stopCount = 0;
  bool disposed = false;

  int _monotonicMs = 0;

  void advanceMonotonicMs(int deltaMs) => _monotonicMs += deltaMs;

  @override
  void sync({
    required double mediaTimeMs,
    required double rate,
    required bool playing,
  }) {
    syncs.add(
      (mediaTimeMs: mediaTimeMs, rate: rate, playing: playing),
    );
  }

  @override
  bool enqueue({
    required double beatMediaTimeMs,
    required int segmentId,
    required double volume,
  }) {
    enqueues.add(
      (beatMediaTimeMs: beatMediaTimeMs, segmentId: segmentId, volume: volume),
    );
    return acceptEnqueue;
  }

  @override
  void flush() {
    flushCount++;
    calls.add('flush');
  }

  @override
  void start() {
    startAttempts++;
    if (failStart) throw StateError('stream unavailable');
    startCount++;
    lostByError = false; // 成功开流 = 流重建，错误关闭状态清除
    calls.add('start');
  }

  @override
  void stop() {
    stopCount++;
    calls.add('stop');
  }

  @override
  void recoverTransport() {
    recoverCount++;
    calls.add('recoverTransport');
    // 换新流对象 = 旧对象上的失效状态不再有意义（原生 recover_transport
    // 同样清 streamLost），且状态查询恢复可用。
    lostByError = false;
    throwOnStreamLost = false;
  }

  @override
  bool streamLost() {
    if (throwOnStreamLost) throw StateError('beat_audio 原生调用失败（code=1）');
    return lostByError;
  }

  @override
  void loadSegment({
    required int segmentId,
    required Float32List pcm,
    required int sampleRate,
    required int markerMs,
  }) {
    if (segmentId < 0 || segmentId >= segmentCapacity) {
      throw StateError('段 id 越界（segmentId=$segmentId 容量=$segmentCapacity）');
    }
    loads.add(
      (
        segmentId: segmentId,
        sampleRate: sampleRate,
        markerMs: markerMs,
        frames: pcm.length,
      ),
    );
  }

  @override
  void dispose() => disposed = true;

  @override
  int monotonicMs() => _monotonicMs;
}

/// 合成 16-bit PCM WAV 字节（多声道逐帧交织）。
Uint8List pcm16Wav({
  required int sampleRate,
  required int channels,
  required List<double> frames,
}) {
  final dataBytes = frames.length * channels * 2;
  final bytes = ByteData(44 + dataBytes);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little); // PCM
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, dataBytes, Endian.little);
  var at = 44;
  for (final frame in frames) {
    for (var ch = 0; ch < channels; ch++) {
      bytes.setInt16(at, (frame * 32767).round(), Endian.little);
      at += 2;
    }
  }
  return bytes.buffer.asUint8List();
}

/// 合成段资产装载器（不触 rootBundle/真实文件系统）：返回极短的可解码 WAV。
Future<ByteData> syntheticSegmentLoader(String asset) async {
  return ByteData.sublistView(
    pcm16Wav(sampleRate: 22050, channels: 1, frames: const [0.0, 0.5, -0.5]),
  );
}
