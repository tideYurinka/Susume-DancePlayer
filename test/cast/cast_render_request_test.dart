import 'dart:typed_data';

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
    CastRenderResolution resolution = CastRenderResolution.p1080,
    CastRenderSettings settings = const CastRenderSettings(),
    String annotationFingerprint = 'fp-1',
    List<CastBeatClick> beatClicks = const [],
    List<CastSticker> stickers = const [],
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
    stickers: stickers,
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
      final guarantee = request(
        resolution: CastRenderResolution.p1080,
      ).cacheKey;
      final p720 = request(resolution: CastRenderResolution.p720).cacheKey;

      expect(p720, isNot(guarantee));
      expect(
        guarantee.token,
        contains('#${CastRenderResolution.p1080.token}#'),
      );
      expect(p720.token, contains('#${CastRenderResolution.p720.token}#'));
      // 除了分辨率档，两次请求逐字同源：差异只可能来自这一维。
      expect(
        request(resolution: CastRenderResolution.p1080).cacheKey,
        guarantee,
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

    test('判等与键摘要同源：每一格变了，两者一起变（不会一边变一边不变）', () {
      const base = CastRenderSettings();
      const variants = <CastRenderSettings>[
        CastRenderSettings(globalMirrored: true),
        CastRenderSettings(localMirrorEnabled: false),
        CastRenderSettings(beatCountVisible: true),
        CastRenderSettings(beatAnimationStyle: 'pendulum'),
        CastRenderSettings(beatOverlay: 'bov:1'),
        CastRenderSettings(stickerOverlay: 'st:0.2x0.1'),
        CastRenderSettings(framing: '0.1,0.1,0.8,0.8'),
        CastRenderSettings(halfBeatSoundEnabled: true),
        CastRenderSettings(metronomeVolumePercent: 80),
        CastRenderSettings(songLoudnessBaseline: 0.42),
        CastRenderSettings(metronomeSourceId: 'vocal'),
      ];

      for (final variant in variants) {
        expect(variant, isNot(base), reason: '这一格变化必须判不等');
        expect(
          variant == base,
          variant.token == base.token,
          reason: '判等与进键的记号是同一份口径：一个变了另一个没变就是漏同步',
        );
        expect(variant.token, isNot(base.token), reason: '这一格变化必须换键');
      }
      expect(
        const CastRenderSettings() == const CastRenderSettings(),
        isTrue,
        reason: '同值同记号',
      );
      expect(
        const CastRenderSettings().token,
        const CastRenderSettings().token,
      );
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
    test('默认保证档：没问过系统时不在请求上无谓降级', () {
      expect(request().resolution, CastRenderResolution.p1080);
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

  group('这一次装哪几条贴纸输入（#21 整改）', () {
    CastSticker sheet() => CastSticker(
      imageBytesOf: () async => Uint8List.fromList(const [0x89, 0x50, 0x4e, 0x47]),
      startMs: 200,
      endMs: 900,
      centerX: 0.3,
      centerY: 0.2,
      widthFraction: 0.25,
      heightFraction: 0.1,
    );

    test('唯一一处回答：贴纸是画面内容类，勾了画面类且有贴纸才逐条装', () {
      expect(
        castStagedStickerSlots(
          request(
            choices: const CastRenderChoices(picture: false, sound: true),
            stickers: [sheet()],
          ),
        ),
        isEmpty,
        reason: '不勾画面类就一条都不装',
      );
      expect(
        castStagedStickerSlots(
          request(choices: const CastRenderChoices(picture: true, sound: false)),
        ),
        isEmpty,
        reason: '没有贴纸就没有这一路输入',
      );
      expect(
        castStagedStickerSlots(
          request(
            choices: const CastRenderChoices(picture: true, sound: false),
            stickers: [sheet(), sheet()],
          ),
        ),
        [0, 1],
        reason: '装了就是逐条装，返回的是请求里的下标（不是「前 n 条」）',
      );
    });
  });
}
