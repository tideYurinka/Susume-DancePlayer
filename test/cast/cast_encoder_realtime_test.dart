import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// **能力三态 → 渲染分辨率档**的纯件直测：不启动 widget、不跑进程。
///
/// 三态是接缝的返回值（`encoder_realtime_capability.dart`），这里钉住它对
/// **渲染参数与缓存键**的含义：保证 1× = 按源分辨率；不保证与**问不到**都
/// 降到 720p——兜底取「按不可保证处理」，宁可降分辨率，也不给用户一个
/// 未知时长的进度条（ADR-0004 的回填）。
void main() {
  group('能力三态 → 分辨率档', () {
    test('保证 1× 实时 ⇒ 按源分辨率渲', () {
      expect(
        castRenderResolutionFor(CastEncoderRealtime.guaranteed),
        CastRenderResolution.source,
      );
    });

    test('不保证 1× 实时 ⇒ 降到 720p', () {
      expect(
        castRenderResolutionFor(CastEncoderRealtime.notGuaranteed),
        CastRenderResolution.p720,
      );
    });

    test('问不到 ⇒ 按不可保证处理：降到 720p', () {
      expect(
        castRenderResolutionFor(CastEncoderRealtime.unknown),
        CastRenderResolution.p720,
      );
    });

    test('三态穷尽且互异（新增一态必须在这里有落点）', () {
      final answers = {
        for (final capability in CastEncoderRealtime.values)
          castRenderResolutionFor(capability),
      };
      expect(CastEncoderRealtime.values.length, 3);
      expect(
        answers,
        {CastRenderResolution.source, CastRenderResolution.p720},
        reason: '三态收敛到两个分辨率档：只有「保证」那一条不降级',
      );
    });
  });

  group('分辨率档：记号与渲染参数', () {
    test('两档记号互异（记号进缓存键）', () {
      final tokens = CastRenderResolution.values.map((r) => r.token).toSet();

      expect(tokens.length, CastRenderResolution.values.length);
    });

    test('源档：8M、不进任何缩放节点（按源分辨率渲）', () {
      expect(CastRenderResolution.source.bitrate, '8M');
      expect(CastRenderResolution.source.scaleNode, isNull);
    });

    test('720p 档：4M、高 720 行、宽度按源比例（方像素，不拉伸）', () {
      expect(CastRenderResolution.p720.bitrate, '4M');
      expect(CastRenderResolution.p720.scaleNode, 'scale=-2:720,setsar=1');
    });
  });
}
