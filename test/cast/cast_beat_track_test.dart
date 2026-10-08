import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_beat_track.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// 拍声轨合成直测（纯件）：**拍点落在正确的采样位**、音量按段口径缩放、
/// 资产自身的采样率与声道数被归一——「拍声与画面同拍」这条验收的算术面。
void main() {
  /// 造一段 16 位 PCM WAV（测试用资产；与随包的三段拍声同格式）。
  Uint8List wav({
    required List<int> samples,
    int sampleRate = 22050,
    int channels = 1,
  }) {
    final dataBytes = samples.length * 2;
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
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * channels * 2, Endian.little);
    view.setUint16(32, channels * 2, Endian.little);
    view.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    view.setUint32(40, dataBytes, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      view.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bytes;
  }

  /// 读合成结果里的第 [frame] 帧（左右两个声道）。
  (int, int) frameAt(Uint8List track, int frame) {
    final view = ByteData.view(track.buffer);
    final base = 44 + frame * kCastBeatTrackChannels * 2;
    return (
      view.getInt16(base, Endian.little),
      view.getInt16(base + 2, Endian.little),
    );
  }

  int framesOf(Uint8List track) =>
      (track.length - 44) ~/ (kCastBeatTrackChannels * 2);

  test('轨长 = 素材时长；没有拍声时是一条静音轨', () {
    final track = buildCastBeatTrackWav(
      clicks: const [],
      assets: const {},
      duration: const Duration(seconds: 2),
    );

    expect(kCastBeatTrackSampleRate, 22050, reason: '与随包三段拍声同采样率');
    expect(framesOf(track), 2 * kCastBeatTrackSampleRate);
    expect(frameAt(track, 0), (0, 0));
    expect(frameAt(track, kCastBeatTrackSampleRate), (0, 0));
  });

  test('拍点落在正确的采样位：500ms 的拍 = 第 11025 帧', () {
    final asset = wav(samples: const [1000, 2000, 3000]);
    final track = buildCastBeatTrackWav(
      clicks: const [
        CastBeatClick(
          time: Duration(milliseconds: 500),
          asset: 'assets/sounds/metronome_beat.wav',
          volume: 1,
        ),
      ],
      assets: {'assets/sounds/metronome_beat.wav': asset},
      duration: const Duration(seconds: 1),
    );

    const offset = 11025;
    expect(frameAt(track, offset - 1), (0, 0), reason: '拍点前一帧仍是静的');
    expect(frameAt(track, offset), (1000, 1000), reason: '单声道资产铺到左右两声道');
    expect(frameAt(track, offset + 1), (2000, 2000));
    expect(frameAt(track, offset + 2), (3000, 3000));
    expect(frameAt(track, offset + 3), (0, 0));
  });

  test('音量按样本缩放（手机本地播放的同一份响度口径）', () {
    final asset = wav(samples: const [1000, -1000]);
    final track = buildCastBeatTrackWav(
      clicks: const [
        CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 0.4),
      ],
      assets: {'a.wav': asset},
      duration: const Duration(seconds: 1),
    );

    expect(frameAt(track, 0), (400, 400));
    expect(frameAt(track, 1), (-400, -400));
  });

  test('资产采样率被归一：44100 的资产落在源时间轴的同一时刻', () {
    // 44100 Hz 的两个样本：第 0 帧 1000、第 2 帧（≈0.045ms）3000。
    final asset = wav(samples: const [1000, 0, 3000], sampleRate: 44100);
    final track = buildCastBeatTrackWav(
      clicks: const [
        CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 1),
      ],
      assets: {'a.wav': asset},
      duration: const Duration(seconds: 1),
    );

    // 44100 → 22050：输出第 0 帧 = 源第 0 帧，输出第 1 帧 = 源第 2 帧。
    expect(frameAt(track, 0), (1000, 1000));
    expect(frameAt(track, 1), (3000, 3000));
    expect(frameAt(track, 2), (0, 0));
  });

  test('低采样率资产按线性插值铺开（不是最近邻）', () {
    // 11025 Hz 是合成轨的一半：输出每两帧走一个源帧。
    final asset = wav(samples: const [0, 1000], sampleRate: 11025);
    final track = buildCastBeatTrackWav(
      clicks: const [
        CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 1),
      ],
      assets: {'a.wav': asset},
      duration: const Duration(seconds: 1),
    );

    expect(frameAt(track, 0), (0, 0));
    expect(frameAt(track, 1), (500, 500), reason: '源第 0.5 帧 = 两者的中点');
    expect(frameAt(track, 2), (1000, 1000));
  });

  test('叠加同一刻的多条拍声：样本相加后钳在 16 位范围', () {
    final asset = wav(samples: const [20000, 20000]);
    final track = buildCastBeatTrackWav(
      clicks: const [
        CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 1),
        CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 1),
        CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 1),
      ],
      assets: {'a.wav': asset},
      duration: const Duration(seconds: 1),
    );

    expect(frameAt(track, 0), (32767, 32767), reason: '60000 被钳到 32767，不绕回负数');
  });

  test('超出素材时长的拍点被丢：轨长不因它变长', () {
    final asset = wav(samples: const [1000]);
    final track = buildCastBeatTrackWav(
      clicks: const [
        CastBeatClick(time: Duration(seconds: 30), asset: 'a.wav', volume: 1),
      ],
      assets: {'a.wav': asset},
      duration: const Duration(seconds: 1),
    );

    expect(framesOf(track), kCastBeatTrackSampleRate);
    expect(frameAt(track, 100), (0, 0));
  });

  test('资产读不到或不是 16 位 PCM：报错，不悄悄出一条空轨', () {
    expect(
      () => buildCastBeatTrackWav(
        clicks: const [
          CastBeatClick(time: Duration.zero, asset: 'missing.wav', volume: 1),
        ],
        assets: const {},
        duration: const Duration(seconds: 1),
      ),
      throwsA(isA<ArgumentError>()),
    );

    final broken = Uint8List.fromList(List<int>.filled(44, 0));
    expect(
      () => buildCastBeatTrackWav(
        clicks: const [
          CastBeatClick(time: Duration.zero, asset: 'broken.wav', volume: 1),
        ],
        assets: {'broken.wav': broken},
        duration: const Duration(seconds: 1),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
