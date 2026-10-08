import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投屏渲染请求与**缓存键**直测（纯件）：勾选档、**分辨率档**、倍速档、设置
/// 快照与标注指纹各自进键，**任一分量变化即换一把键**——缓存的地基。
void main() {
  CastRenderRequest request({
    String videoId = 'vid-a',
    CastRenderChoices choices = const CastRenderChoices(
      picture: true,
      sound: true,
    ),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastRenderResolution resolution = CastRenderResolution.source,
    CastRenderSettings settings = const CastRenderSettings(),
    String annotationFingerprint = 'fp-1',
    List<CastBeatClick> beatClicks = const [],
  }) => CastRenderRequest(
    videoPath: '/videos/a.mp4',
    videoId: videoId,
    duration: const Duration(minutes: 3),
    choices: choices,
    speedTier: speedTier,
    resolution: resolution,
    settings: settings,
    annotationFingerprint: annotationFingerprint,
    beatClicks: beatClicks,
  );

  group('勾选档', () {
    test('默认全选；都不勾 = 不渲染', () {
      expect(const CastRenderChoices.all().picture, isTrue);
      expect(const CastRenderChoices.all().sound, isTrue);
      expect(const CastRenderChoices.all().renders, isTrue);
      expect(const CastRenderChoices.none().renders, isFalse);
      expect(
        const CastRenderChoices(picture: false, sound: true).renders,
        isTrue,
      );
      expect(
        const CastRenderChoices(picture: true, sound: false).renders,
        isTrue,
      );
    });

    test('四种组合各有互异的档位记号', () {
      final tokens = {
        for (final picture in [true, false])
          for (final sound in [true, false])
            CastRenderChoices(picture: picture, sound: sound).token,
      };
      expect(tokens.length, 4);
    });
  });

  group('缓存键', () {
    test('同一个请求给同一把键', () {
      expect(request().cacheKey, request().cacheKey);
      expect(request().cacheKey.hashCode, request().cacheKey.hashCode);
    });

    test('视频标识变化即换键', () {
      expect(
        request(videoId: 'vid-b').cacheKey,
        isNot(request(videoId: 'vid-a').cacheKey),
      );
    });

    test('勾选档变化即换键', () {
      expect(
        request(choices: const CastRenderChoices(picture: false, sound: true))
            .cacheKey,
        isNot(request().cacheKey),
      );
    });

    test('投屏倍速档变化即换键', () {
      expect(
        request(speedTier: CastSpeedTier.half).cacheKey,
        isNot(request(speedTier: CastSpeedTier.full).cacheKey),
      );
      expect(
        request(speedTier: CastSpeedTier.threeQuarter).cacheKey,
        isNot(request(speedTier: CastSpeedTier.half).cacheKey),
      );
    });

    test('标注内容指纹变化即换键', () {
      expect(
        request(annotationFingerprint: 'fp-2').cacheKey,
        isNot(request(annotationFingerprint: 'fp-1').cacheKey),
      );
    });

    test('分辨率档变化即换键：降级与不降级是两份缓存条目', () {
      final source = request(resolution: CastRenderResolution.source).cacheKey;
      final p720 = request(resolution: CastRenderResolution.p720).cacheKey;

      expect(p720, isNot(source));
      expect(source.token, contains('#${CastRenderResolution.source.token}#'));
      expect(p720.token, contains('#${CastRenderResolution.p720.token}#'));
      // 除了分辨率档，两次请求逐字同源：差异只可能来自这一维。
      expect(
        request(resolution: CastRenderResolution.source).cacheKey,
        source,
        reason: '同一维同值给同一把键',
      );
    });

    test('设置快照每一项变化即换键', () {
      final base = request().cacheKey;
      final variants = <String, CastRenderSettings>{
        '全局镜像': const CastRenderSettings(globalMirrored: true),
        '局部镜像总开关': const CastRenderSettings(localMirrorEnabled: false),
        '数拍显示': const CastRenderSettings(beatCountVisible: true),
        '节拍动画形态': const CastRenderSettings(beatAnimationStyle: 'pendulum'),
        '取景': const CastRenderSettings(framing: '0.1,0.1,0.8,0.8'),
        '半拍声': const CastRenderSettings(halfBeatSoundEnabled: true),
        '节拍音量': const CastRenderSettings(metronomeVolumePercent: 80),
        '响度基准': const CastRenderSettings(songLoudnessBaseline: 0.42),
        '音源': const CastRenderSettings(metronomeSourceId: 'vocal'),
      };
      for (final entry in variants.entries) {
        expect(
          request(settings: entry.value).cacheKey,
          isNot(base),
          reason: '${entry.key}变化没有换键：缓存会命中一份旧产物',
        );
      }
    });

    test('快照的默认值：与基准同一份取值', () {
      // 基准 = 默认快照（局部镜像总开关开、数拍不显示、未取景、1× 音量 50）。
      expect(const CastRenderSettings().localMirrorEnabled, isTrue);
      expect(const CastRenderSettings().beatCountVisible, isFalse);
      expect(const CastRenderSettings().framing, isEmpty);
      expect(const CastRenderSettings().metronomeVolumePercent, 50);
    });
  });

  group('倍速档', () {
    test('三档各自的倍率与记号互异', () {
      expect(CastSpeedTier.half.rate, 0.5);
      expect(CastSpeedTier.threeQuarter.rate, 0.75);
      expect(CastSpeedTier.full.rate, 1);
      final tokens = CastSpeedTier.values.map((t) => t.token).toSet();
      expect(tokens.length, CastSpeedTier.values.length);
    });
  });

  group('分辨率档', () {
    test('默认按源分辨率：没问过系统时不在请求上无谓降级', () {
      expect(request().resolution, CastRenderResolution.source);
    });

    test('降级那一档按高度 720 行现算宽度（记号进键）', () {
      expect(request(resolution: CastRenderResolution.p720).resolution.token,
          '720p');
    });
  });

  group('拍声排程', () {
    test('值对象：时刻 + 资产 + 音量', () {
      const click = CastBeatClick(
        time: Duration(milliseconds: 500),
        asset: 'assets/sounds/metronome_beat.wav',
        volume: 0.4,
      );
      expect(click.time, const Duration(milliseconds: 500));
      expect(click.asset, 'assets/sounds/metronome_beat.wav');
      expect(click.volume, 0.4);
    });
  });
}
