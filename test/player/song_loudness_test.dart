import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/song_loudness.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_private_json_storage.dart';

class _FixedProbe implements SongLoudnessProbe {
  _FixedProbe(this.rms);

  final double rms;
  final List<String> probed = [];

  @override
  Future<double> pcmRms(String videoPath) async {
    probed.add(videoPath);
    return rms;
  }
}

void main() {
  group('metronomeSliderGain（滑条增益纯函数）', () {
    test('50% → 1.0×基准；100% → 2.0×基准；线性', () {
      expect(metronomeSliderGain(50), 1.0);
      expect(metronomeSliderGain(100), 2.0);
      expect(metronomeSliderGain(0), 0.0);
      expect(metronomeSliderGain(75), 1.5);
    });

    test('越界滑条值钳制（防御非法输入）', () {
      expect(metronomeSliderGain(-10), 0.0);
      expect(metronomeSliderGain(200), 2.0);
    });
  });

  group('metronomeSampleVolume（实际发声响度纯函数）', () {
    test('50% = 歌曲响度基准；未测默认基准 1.0', () {
      expect(
        metronomeSampleVolume(volumePercent: 50, baseline: 0.8),
        0.8,
      );
      expect(
        metronomeSampleVolume(
          volumePercent: 50,
          baseline: kDefaultSongLoudnessBaseline,
        ),
        1.0,
      );
    });

    test('响度 = 基准 × 滑条/50，线性映射', () {
      expect(
        metronomeSampleVolume(volumePercent: 100, baseline: 0.5),
        1.0,
      );
      expect(
        metronomeSampleVolume(volumePercent: 25, baseline: 1.0),
        0.5,
      );
    });

    test('钳制 ≤ 1.0 防削波', () {
      expect(
        metronomeSampleVolume(volumePercent: 100, baseline: 2.0),
        1.0,
      );
    });

    test('半拍样本内部增益拉平（约 +6dB ≈ ×2），再统一钳制', () {
      final beat = metronomeSampleVolume(volumePercent: 50, baseline: 0.5);
      final half = metronomeSampleVolume(
        volumePercent: 50,
        baseline: 0.5,
        halfBeat: true,
      );
      expect(half, closeTo(beat * 2, 1e-9));
      // 钳制后半拍与普通拍同样不超过满刻度。
      expect(
        metronomeSampleVolume(volumePercent: 50, baseline: 1.0, halfBeat: true),
        1.0,
      );
    });
  });

  group('pcmRms / loudnessBaselineFromRms（测量 → 基准映射纯函数）', () {
    test('恒定幅值正弦段的 RMS ≈ 幅值 / √2', () {
      final pcm = List<double>.generate(44100, (i) => 0.5);
      expect(pcmRms(pcm), closeTo(0.5, 1e-9));
    });

    test('空/静音 PCM → RMS 0，映射兜底默认基准', () {
      expect(pcmRms(const []), 0.0);
      expect(loudnessBaselineFromRms(0), kDefaultSongLoudnessBaseline);
    });

    test('基准 = 目标响度 / 实测响度，带上下钳制', () {
      expect(loudnessBaselineFromRms(0.125), closeTo(1.0, 1e-9));
      // 响度很大的歌 → 基准 < 1；很小的歌 → 基准 > 1。
      expect(loudnessBaselineFromRms(0.5), lessThan(1.0));
      expect(loudnessBaselineFromRms(0.01), greaterThan(1.0));
      // 钳制边界。
      expect(loudnessBaselineFromRms(1e-4), kMaxSongLoudnessBaseline);
      expect(loudnessBaselineFromRms(1.0), kMinSongLoudnessBaseline);
    });
  });

  group('SongLoudnessBaselineStore（按视频私密缓存 seam）', () {
    test('load：缺失/损坏条目兜底 null', () async {
      final storage = InMemoryPrivateJsonStorage();
      final store = SongLoudnessBaselineStore(storage);
      expect(await store.load('video-a'), isNull);

      await storage.mutate((json, {required bool present}) => json['songLoudnessBaselines'] = {
            'video-a': 'broken',
          });
      expect(await store.load('video-a'), isNull);
    });

    test('save：按视频隔离落盘，保留同文件其它键', () async {
      final storage = InMemoryPrivateJsonStorage(
        initial: {
          'speedHistory': [1.5],
        },
      );
      final store = SongLoudnessBaselineStore(storage);

      await store.save('video-a', 0.8);
      await store.save('video-b', 1.4);

      expect(await store.load('video-a'), 0.8);
      expect(await store.load('video-b'), 1.4);
      expect(storage.snapshot['speedHistory'], [1.5]);
    });

    test('load：非有限/非正数兜底 null', () async {
      final storage = InMemoryPrivateJsonStorage();
      await storage.mutate((json, {required bool present}) => json['songLoudnessBaselines'] = {
            'video-a': 0,
            'video-b': -1.0,
          });
      final store = SongLoudnessBaselineStore(storage);
      expect(await store.load('video-a'), isNull);
      expect(await store.load('video-b'), isNull);
    });
  });

  group('SongLoudnessCoordinator（默认基准 → 补测更新）', () {
    test('ensureBaseline：无缓存 → 后台补测并更新会话基准 + 落盘', () async {
      final storage = InMemoryPrivateJsonStorage();
      final probe = _FixedProbe(0.25);
      final container = ProviderContainer(overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        songLoudnessProbeProvider.overrideWithValue(probe),
      ]);
      addTearDown(container.dispose);

      await container
          .read(songLoudnessCoordinatorProvider)
          .ensureBaseline(videoPath: '/tmp/a.mp4', videoId: 'video-a');

      expect(container.read(songLoudnessBaselineProvider),
          loudnessBaselineFromRms(0.25));
      expect(probe.probed, ['/tmp/a.mp4']);
      expect(
        await SongLoudnessBaselineStore(storage).load('video-a'),
        loudnessBaselineFromRms(0.25),
      );
    });

    test('ensureBaseline：有缓存 → 直接用缓存，不再测量', () async {
      final storage = InMemoryPrivateJsonStorage();
      await SongLoudnessBaselineStore(storage).save('video-a', 0.6);
      final probe = _FixedProbe(0.25);
      final container = ProviderContainer(overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        songLoudnessProbeProvider.overrideWithValue(probe),
      ]);
      addTearDown(container.dispose);

      await container
          .read(songLoudnessCoordinatorProvider)
          .ensureBaseline(videoPath: '/tmp/a.mp4', videoId: 'video-a');

      expect(container.read(songLoudnessBaselineProvider), 0.6);
      expect(probe.probed, isEmpty);
    });

    test('recordRms：节拍分析解码顺带测量入口，更新会话 + 落盘', () async {
      final storage = InMemoryPrivateJsonStorage();
      final container = ProviderContainer(overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      container
          .read(songLoudnessCoordinatorProvider)
          .recordRms('video-a', 0.125);
      expect(container.read(songLoudnessBaselineProvider),
          closeTo(1.0, 1e-9));
      await container
          .read(songLoudnessBaselineStorageProvider)
          .load('video-a');
      expect(
        await SongLoudnessBaselineStore(storage).load('video-a'),
        isNotNull,
      );
    });

    test('ensureBaseline：测量失败维持默认基准，不上抛', () async {
      final storage = InMemoryPrivateJsonStorage();
      final container = ProviderContainer(overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        songLoudnessProbeProvider.overrideWithValue(
          _ThrowingProbe(),
        ),
      ]);
      addTearDown(container.dispose);

      await container
          .read(songLoudnessCoordinatorProvider)
          .ensureBaseline(videoPath: '/tmp/a.mp4', videoId: 'video-a');

      expect(
        container.read(songLoudnessBaselineProvider),
        kDefaultSongLoudnessBaseline,
      );
    });
  });
}

class _ThrowingProbe implements SongLoudnessProbe {
  @override
  Future<double> pcmRms(String videoPath) async {
    throw StateError('decode failed');
  }
}
