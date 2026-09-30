import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'metronome_source_registry.dart';

/// 原生渲染 sink seam：[BeatAudioRenderer]（排程消费生产实现）的
/// 底座。测试注入 fake 断言 sync/enqueue/flush/start/stop 与段加载；生产
/// 实现 [NativeBeatAudioSink] 经 dart:ffi 调 AAudio 渲染器
/// （`android/app/src/main/cpp/audio_native.cpp`，同款接入）。
abstract interface class BeatAudioSink {
  /// 下推同步对（媒介时钟锚）：原生锚换算只用媒介时刻 + 倍速 + 播放态。
  void sync({
    required double mediaTimeMs,
    required double rate,
    required bool playing,
  });

  /// 排程一条指令（拍点媒介时间 + 哑段 id + 音量）。返回原生是否接受
  /// 入队（返回值被检查，false = 原生未入队，调用侧记一行诊断并
  /// 按流记账触发自愈）。
  bool enqueue({
    required double beatMediaTimeMs,
    required int segmentId,
    required double volume,
  });

  /// 丢弃全部未消费事件（暂停/seek/关声：错过的拍不补发）。
  void flush();

  /// 开流（段就绪后调用，以便按实际流采样率重采样）。
  void start();

  /// 停流（暂停/关声/退页：流对象保留复用，回调停止即不空耗）。
  void stop();

  /// 重建原生输出流（**路由切换/流失效后的最后一个恢复手段**）：停流、
  /// 关掉当前流对象、清空事件环与播放头，下一次 [start] 在**全新流对象**
  /// 上开流；段资产与句柄保留，不必重新装载。
  ///
  /// 为什么需要它（真机取证）：输出设备切换（蓝牙断开）时 AAudio
  /// 用错误回调报告 `AAUDIO_ERROR_DISCONNECTED`；此后旧流对象可能既跑不起
  /// 来（`requestStart` 返回 `AAUDIO_ERROR_INVALID_STATE`）又不自行重建，
  /// 应活时表现为**永久静默**。
  void recoverTransport();

  /// 原生流是否**已被系统错误关闭**（拔耳机/路由切换/设备异常：原生错误
  /// 回调置此状态，**不自己关流**——跨线程 close 被 AAudio 拒；成功开流即
  /// 清除）。Dart 在**应活**时探测到即重开（生命周期自愈）——无新边沿时
  /// 不至于永久静默。
  ///
  /// 原生返回 1（已被错误关闭）/ 0（正常）/ -1（句柄无效上抛）。探测本身也
  /// 可能抛（流句柄已不可信）：调用方按「流已失效」处理。
  bool streamLost();

  /// 加载段资产（解码后的源 PCM + 源采样率 + 段内拍点标记毫秒）；[segmentId]
  /// 越界（< 0 或 ≥ [kMetronomeNativeSegmentCapacity]）原生拒绝并上抛。
  void loadSegment({
    required int segmentId,
    required Float32List pcm,
    required int sampleRate,
    required int markerMs,
  });

  /// 释放原生渲染器（流关闭 + 句柄销毁；此后不得再调用）。
  void dispose();

  /// 单调墙钟（毫秒，CLOCK_MONOTONIC）：冷却计时与配对转发共用同一时基。
  int monotonicMs();
}

/// dart:ffi 绑定（libaudio_native.so）。加载失败（非 Android 平台/宿主
/// 单测）[instance] 为 null，调用方回退哑 sink（不发声，播放链路不受阻）。
class BeatAudioNative {
  BeatAudioNative._(this._create, this._loadSegment, this._sync, this._enqueue,
      this._flush, this._start, this._stop, this._streamLost, this._destroy,
      this._monotonicMs, this._recoverTransport);

  final Pointer<Void> Function(int) _create;
  final int Function(Pointer<Void>, int, Pointer<Float>, int, int, int)
      _loadSegment;
  final int Function(Pointer<Void>, double, double, int) _sync;
  final int Function(Pointer<Void>, double, int, double) _enqueue;
  final int Function(Pointer<Void>) _flush;
  final int Function(Pointer<Void>) _start;
  final int Function(Pointer<Void>) _stop;
  final int Function(Pointer<Void>) _streamLost;
  final void Function(Pointer<Void>) _destroy;
  final int Function() _monotonicMs;
  final int Function(Pointer<Void>) _recoverTransport;

  static BeatAudioNative? _instance;

  static BeatAudioNative? get instance => _instance ??= _tryLoad();

  static BeatAudioNative? _tryLoad() {
    try {
      final lib = DynamicLibrary.open('libaudio_native.so');
      final Pointer<Void> Function(int) create = lib.lookupFunction<
          Pointer<Void> Function(Int32),
          Pointer<Void> Function(int)>('beat_audio_create');
      return BeatAudioNative._(
        create,
        lib.lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Float>, Int32, Int32,
                Int32),
            int Function(Pointer<Void>, int, Pointer<Float>, int, int,
                int)>('beat_audio_load_segment'),
        lib.lookupFunction<
            Int32 Function(Pointer<Void>, Double, Double, Int32),
            int Function(Pointer<Void>, double, double, int)>(
            'beat_audio_sync'),
        lib.lookupFunction<
            Int32 Function(Pointer<Void>, Double, Int32, Float),
            int Function(Pointer<Void>, double, int, double)>(
            'beat_audio_enqueue'),
        lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('beat_audio_flush'),
        lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('beat_audio_start'),
        lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('beat_audio_stop'),
        lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('beat_audio_stream_lost'),
        lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('beat_audio_destroy'),
        lib.lookupFunction<Int64 Function(), int Function()>(
            'beat_audio_monotonic_ms'),
        lib.lookupFunction<Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)>('beat_audio_recover_transport'),
      );
    } on Object {
      return null;
    }
  }

  static void _check(int code) {
    if (code != 0) throw StateError('beat_audio 原生调用失败（code=$code）');
  }

  /// 打开原生渲染器；任一步失败上抛（调用方回退哑 sink）。段槽容量由注册
  /// 表派生（[kMetronomeNativeSegmentCapacity]）随创建下传，原生按容量校验。
  static BeatAudioSink open() {
    final native = instance;
    if (native == null) {
      throw StateError('libaudio_native.so 不可用（非 Android 宿主）');
    }
    final handle = native._create(kMetronomeNativeSegmentCapacity);
    if (handle == nullptr) throw StateError('beat_audio_create 失败');
    return _NativeSink(native, handle);
  }
}

class _NativeSink implements BeatAudioSink {
  _NativeSink(this._native, this._handle);

  final BeatAudioNative _native;
  Pointer<Void> _handle;
  bool _disposed = false;

  @override
  void sync({
    required double mediaTimeMs,
    required double rate,
    required bool playing,
  }) {
    if (_disposed) return;
    BeatAudioNative._check(_native._sync(
      _handle,
      mediaTimeMs,
      rate,
      playing ? 1 : 0,
    ));
  }

  @override
  bool enqueue({
    required double beatMediaTimeMs,
    required int segmentId,
    required double volume,
  }) {
    if (_disposed) return false;
    // 返回值被检查。0 = 已入队；1 = 无锚/暂停/段未就绪/环满、
    // -1 = 参数错——两者都不是「已接受」，由调用侧记诊断并按
    // 流记账触发自愈（丢弃是否属纪律常态由日志分辨）。
    return _native._enqueue(_handle, beatMediaTimeMs, segmentId, volume) == 0;
  }

  @override
  void flush() {
    if (_disposed) return;
    BeatAudioNative._check(_native._flush(_handle));
  }

  @override
  void start() {
    if (_disposed) return;
    BeatAudioNative._check(_native._start(_handle));
  }

  @override
  void stop() {
    if (_disposed) return;
    BeatAudioNative._check(_native._stop(_handle));
  }

  @override
  void recoverTransport() {
    if (_disposed) return;
    final code = _native._recoverTransport(_handle);
    BeatAudioNative._check(code);
  }

  @override
  bool streamLost() {
    if (_disposed) return false;
    // 原生契约：1 = 已被错误关闭、0 = 正常、-1 = 句柄无效——错误码走同一
    // `_check` 纪律上抛（与 loadSegment/flush/start/stop 一致），不把哨兵
    // 值当成「已丢失」真值。
    final code = _native._streamLost(_handle);
    BeatAudioNative._check(code);
    return code == 1;
  }

  @override
  void loadSegment({
    required int segmentId,
    required Float32List pcm,
    required int sampleRate,
    required int markerMs,
  }) {
    if (_disposed) return;
    final Pointer<Float> buffer = malloc<Float>(pcm.length);
    try {
      buffer.asTypedList(pcm.length).setAll(0, pcm);
      BeatAudioNative._check(_native._loadSegment(
        _handle,
        segmentId,
        buffer,
        pcm.length,
        sampleRate,
        markerMs,
      ));
    } finally {
      malloc.free(buffer);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _native._destroy(_handle);
    _handle = nullptr;
  }

  @override
  int monotonicMs() => _native._monotonicMs();
}

/// WAV 解码结果：单声道样本 + 源采样率。
class WavMono {
  const WavMono({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

/// 解码 PCM WAV（16-bit 整型或 32-bit 浮点；多声道混为单声道）为单声道
/// 浮点样本。非法/不支持的格式上抛（调用方决定兜底）。
WavMono decodeWavMono(Uint8List bytes) {
  if (bytes.length < 12 ||
      bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46 ||
      bytes[8] != 0x57 ||
      bytes[9] != 0x41 ||
      bytes[10] != 0x56 ||
      bytes[11] != 0x45) {
    throw ArgumentError('非 RIFF/WAVE 数据');
  }
  final data = ByteData.sublistView(bytes);
  int audioFormat = 0;
  int channels = 0;
  int sampleRate = 0;
  int bitsPerSample = 0;
  Uint8List? payload;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      audioFormat = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      final end = (body + size) <= bytes.length ? body + size : bytes.length;
      // 保持视图（非拷贝）：payload.offsetInBytes 即块体在 bytes 内偏移。
      payload = Uint8List.sublistView(bytes, body, end);
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }

  if (payload == null || channels <= 0 || sampleRate <= 0) {
    throw ArgumentError('WAV 缺少 fmt/data 块');
  }
  final frames = payload.length ~/ (bitsPerSample ~/ 8 * channels);
  final samples = Float32List(frames);
  final frameBytes = bitsPerSample ~/ 8 * channels;
  for (var frame = 0; frame < frames; frame++) {
    var sum = 0.0;
    for (var ch = 0; ch < channels; ch++) {
      final at = frame * frameBytes + ch * (bitsPerSample ~/ 8);
      switch ((audioFormat, bitsPerSample)) {
        case (1, 16):
          sum += data.getInt16(payload.offsetInBytes + at, Endian.little) / 32768.0;
        case (3, 32):
          sum += data.getFloat32(payload.offsetInBytes + at, Endian.little);
        default:
          throw ArgumentError(
              '不支持的 WAV 编码（format=$audioFormat bits=$bitsPerSample）');
      }
    }
    samples[frame] = sum / channels;
  }
  return WavMono(samples: samples, sampleRate: sampleRate);
}
