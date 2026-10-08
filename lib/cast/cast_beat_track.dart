/// 拍声轨合成（纯件，零 Flutter、零 IO）：把一份**拍声排程**烘成一条 16 位
/// PCM WAV，交给 ffmpeg 与源片音轨 `amix`。
///
/// ## 为什么在 Dart 侧合成
///
/// 拍点来自节拍网格（任意时刻，不是均匀 BPM），而段资产是几条几十毫秒的
/// 采样。要在 ffmpeg 里表达它，只有两条路：给每一拍挂一路 `adelay` 输入
/// （几百路输入，命令与滤镜图都爆掉），或者先把它们按采样位摆好。后者是一段
/// 纯算术：合成结果可直测到**第几帧是哪一段的哪个样本**——「拍声与画面同拍」
/// 因此不是听感描述，是可以钉住的采样位。
///
/// ## 口径
///
/// - 采样率取 [kCastBeatTrackSampleRate]，与随包的三段拍声资产同率（不为了
///   合成再做一次重采样）；资产若是别的采样率（或单声道）在这里归一。
/// - 音量**烘进样本**（[CastBeatClick.volume] 与手机本地播放同一份响度口径），
///   所以命令里不再叠 `volume` 滤镜，改音量就是换缓存键。
/// - 长度 = 素材时长；超出时长的拍点被丢掉（轨不会因此变长）。
/// - 资产读不到或不是 16 位 PCM = 报错：宁可这次渲染失败，也不悄悄投一条
///   没拍声的轨出去。
library;

import 'dart:typed_data';

import 'cast_render_request.dart';

/// 合成轨的采样率：与随包拍声段资产一致（22050 Hz）。
const int kCastBeatTrackSampleRate = 22050;

/// 合成轨的声道数（单声道资产铺到左右两声道）。
const int kCastBeatTrackChannels = 2;

/// 把 [clicks] 合成为一条 WAV（[assets] 是资产路径 → WAV 字节）。
Uint8List buildCastBeatTrackWav({
  required List<CastBeatClick> clicks,
  required Map<String, Uint8List> assets,
  required Duration duration,
}) {
  final frames =
      (duration.inMicroseconds * kCastBeatTrackSampleRate) ~/
      Duration.microsecondsPerSecond;
  final mix = Int16List(frames * kCastBeatTrackChannels);
  final parsed = <String, _PcmWav>{};

  for (final click in clicks) {
    final frame =
        (click.time.inMicroseconds * kCastBeatTrackSampleRate) ~/
        Duration.microsecondsPerSecond;
    if (frame >= frames) continue; // 超出素材时长：丢掉，不拉长轨
    final samples = parsed.putIfAbsent(click.asset, () {
      final bytes = assets[click.asset];
      if (bytes == null) {
        throw ArgumentError.value(click.asset, 'assets', '拍声资产读不到');
      }
      return _PcmWav.parse(bytes);
    });
    _mixInto(
      mix: mix,
      frames: frames,
      startFrame: frame,
      source: samples,
      volume: click.volume,
    );
  }

  return _encodeWav(mix, frames: frames);
}

/// 把一条资产按 [volume] 叠进 [mix] 的第 [startFrame] 帧起。
void _mixInto({
  required Int16List mix,
  required int frames,
  required int startFrame,
  required _PcmWav source,
  required double volume,
}) {
  final ratio = source.sampleRate / kCastBeatTrackSampleRate;
  final sourceFrames = source.frameCount;
  final targetFrames = ratio == 0 ? 0 : (sourceFrames / ratio).ceil();
  for (var i = 0; i < targetFrames; i++) {
    final frame = startFrame + i;
    if (frame < 0 || frame >= frames) break;
    for (var channel = 0; channel < kCastBeatTrackChannels; channel++) {
      final value = source.sampleAt(frameIndex: i * ratio, channel: channel);
      if (value == 0) continue;
      final index = frame * kCastBeatTrackChannels + channel;
      final sum = mix[index] + (value * volume).round();
      mix[index] = sum > 32767
          ? 32767
          : sum < -32768
          ? -32768
          : sum;
    }
  }
}

/// 一条解析好的 16 位 PCM WAV（样本按帧交错）。
class _PcmWav {
  const _PcmWav({
    required this.sampleRate,
    required this.channels,
    required this.samples,
  });

  final int sampleRate;
  final int channels;

  /// 交错样本（帧 0 的各声道在前）。
  final Int16List samples;

  int get frameCount => samples.length ~/ channels;

  /// 第 [frameIndex] 帧的 [channel] 声道；越界给 0。帧号是**小数**——源采样率
  /// 与合成轨不同率时按线性插值取。
  int sampleAt({required double frameIndex, required int channel}) {
    if (frameIndex < 0 || frameIndex >= frameCount) return 0;
    final low = frameIndex.floor();
    final high = low + 1;
    final fraction = frameIndex - low;
    final sourceChannel = channel < channels ? channel : 0; // 单声道铺满
    final a = samples[low * channels + sourceChannel];
    if (fraction == 0 || high >= frameCount) return a;
    final b = samples[high * channels + sourceChannel];
    return (a + (b - a) * fraction).round();
  }

  /// 解析一条 WAV：只认 16 位 PCM（随包拍声与测试资产都是这一档）。
  static _PcmWav parse(Uint8List bytes) {
    if (bytes.length < 44 ||
        _tag(bytes, 0) != 'RIFF' ||
        _tag(bytes, 8) != 'WAVE') {
      throw const FormatException('拍声资产不是 WAV');
    }
    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes);
    int? sampleRate;
    int? channels;
    Int16List? samples;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final tag = _tag(bytes, offset);
      final size = view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (tag == 'fmt ') {
        final format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        sampleRate = view.getUint32(body + 4, Endian.little);
        final bits = view.getUint16(body + 14, Endian.little);
        if (format != 1 || bits != 16) {
          throw const FormatException('拍声资产不是 16 位 PCM');
        }
      } else if (tag == 'data') {
        final length = size > bytes.length - body ? bytes.length - body : size;
        samples = Int16List(length ~/ 2);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = view.getInt16(body + i * 2, Endian.little);
        }
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    final rate = sampleRate;
    final channelCount = channels;
    final decoded = samples;
    if (rate == null ||
        channelCount == null ||
        channelCount <= 0 ||
        decoded == null) {
      throw const FormatException('拍声资产缺少 fmt / data 段');
    }
    return _PcmWav(sampleRate: rate, channels: channelCount, samples: decoded);
  }

  static String _tag(Uint8List bytes, int offset) =>
      String.fromCharCodes(bytes.sublist(offset, offset + 4));
}

/// 16 位 PCM WAV 编码（44 字节规范头 + 交错样本）。
Uint8List _encodeWav(Int16List samples, {required int frames}) {
  final dataBytes = frames * kCastBeatTrackChannels * 2;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.view(bytes.buffer);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, kCastBeatTrackChannels, Endian.little);
  view.setUint32(24, kCastBeatTrackSampleRate, Endian.little);
  view.setUint32(
    28,
    kCastBeatTrackSampleRate * kCastBeatTrackChannels * 2,
    Endian.little,
  );
  view.setUint16(32, kCastBeatTrackChannels * 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes;
}
