import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:flutter_test/flutter_test.dart';

/// **能力三态 → 渲染分辨率档**的纯件直测：不启动 widget、不跑进程。
///
/// 三态是接缝的返回值（`encoder_realtime_capability.dart`），这里钉住它对
/// **渲染参数与缓存键**的含义：保证 1× = 向系统问的那一档（1080p/30）——答案
/// 只保证到那一档，画面上限因此收在 1080 行上（4K 源也不放行）；不保证与
/// **问不到**都降到 720p——兜底取「按不可保证处理」，宁可降分辨率，也不给
/// 用户一个未知时长的进度条（ADR-0004 的回填）。
void main() {
  group('能力三态 → 分辨率档', () {
    test('保证 1× 实时 ⇒ 保证档（问的那一档，画面上限收在 1080 行）', () {
      expect(
        castRenderResolutionFor(CastEncoderRealtime.guaranteed),
        CastRenderResolution.p1080,
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
        {CastRenderResolution.p1080, CastRenderResolution.p720},
        reason: '三态收敛到两个分辨率档：只有「保证」那一条不降级',
      );
    });
  });

  group('问系统的那一档：尺寸与帧率由 Dart 侧给出', () {
    test('保证档问的是 1080p / 30fps（原生不再硬编这三个数）', () {
      expect(kCastGuaranteeQueryTarget.width, 1920);
      expect(kCastGuaranteeQueryTarget.height, 1080);
      expect(kCastGuaranteeQueryTarget.fps, 30);
    });

    test('保证档的缩放上限就是问的那一档高度（两处不许各写一个数）', () {
      expect(
        CastRenderResolution.p1080.scaleNode,
        contains('min(${kCastGuaranteeQueryTarget.height},ih)'),
      );
    });
  });

  group('分辨率档：记号与渲染参数', () {
    test('两档记号互异（记号进缓存键）', () {
      final tokens = CastRenderResolution.values.map((r) => r.token).toSet();

      expect(tokens.length, CastRenderResolution.values.length);
    });

    test('保证档：8M、高度封在 1080 行（只降不升）、宽度按源比例（方像素）', () {
      expect(CastRenderResolution.p1080.bitrate, '8M');
      expect(
        CastRenderResolution.p1080.scaleNode,
        "scale=-2:'min(1080,ih)',setsar=1",
      );
      expect(
        CastRenderResolution.p1080.scaleNode,
        contains('setsar=1'),
        reason: 'scale 会改 SAR：方像素得我们钉住',
      );
    });

    test('720p 档：4M、高度封在 720 行（只降不升）、宽度按源比例（方像素）', () {
      expect(CastRenderResolution.p720.bitrate, '4M');
      expect(
        CastRenderResolution.p720.scaleNode,
        "scale=-2:'min(720,ih)',setsar=1",
      );
      // 旧断言写死 `scale=-2:720`——那对**裁切后不足 720 行**的选区是**放大**
      // （API<29 是常态降级路径），与「不足以 1× 实时就宁可降分辨率」相反。
      // 现在高度取 min(720, ih)：高过 720 才降、不足就原样留着。
      expect(
        CastRenderResolution.p720.scaleNode,
        isNot(contains('scale=-2:720')),
        reason: '写死 720 会把小选区放大',
      );
      expect(
        CastRenderResolution.p720.scaleNode,
        contains('setsar=1'),
        reason: 'scale 会改 SAR：方像素得我们钉住',
      );
    });
  });

  group('保证档：答案只保证到问的那一档，4K 源不放行', () {
    /// 缩放节点里高度那一段表达式：`scale=-2:'<表达式>',setsar=1`。
    String heightExpression() {
      final match = RegExp(
        r"scale=-2:'([^']+)'",
      ).firstMatch(CastRenderResolution.p1080.scaleNode);
      expect(match, isNotNull, reason: '高度得是带引号的表达式，逗号才不会被当成链分隔');
      return match!.group(1)!;
    }

    /// 按生产那条表达式的语义算输出高度：`min(1080, ih)`——`ih` 是**取景之后**
    /// 那块画面的高度，也就是送进缩放节点的源高度。
    int scaledHeightFor(int sourceHeight) =>
        sourceHeight < 1080 ? sourceHeight : 1080;

    test('高度表达式读的是源高度（ih），不是写死的 1080', () {
      expect(heightExpression(), contains('ih'));
      expect(heightExpression(), contains('min(1080'));
    });

    test('4K 源（2160 行）收在 1080 行：一条 1080p30 的答案不放行更大的画面', () {
      expect(scaledHeightFor(2160), 1080);
    });

    test('1080 行及以下：原样留着，不放大', () {
      expect(scaledHeightFor(1080), 1080);
      expect(scaledHeightFor(720), 720);
      expect(scaledHeightFor(480), 480);
    });
  });

  group('720p 档：高度只降不升（选区比 720 小 → 不放大）', () {
    /// 缩放节点里高度那一段表达式：`scale=-2:'<表达式>',setsar=1`。
    String heightExpression() {
      final match = RegExp(
        r"scale=-2:'([^']+)'",
      ).firstMatch(CastRenderResolution.p720.scaleNode);
      expect(match, isNotNull, reason: '高度得是带引号的表达式，逗号才不会被当成链分隔');
      return match!.group(1)!;
    }

    /// 按生产那条表达式的语义算输出高度：`min(720, ih)`——`ih` 是**取景之后**
    /// 那块画面的高度，也就是送进缩放节点的源高度。
    int scaledHeightFor(int sourceHeight) =>
        sourceHeight < 720 ? sourceHeight : 720;

    test('高度表达式读的是源高度（ih），不是写死的 720', () {
      expect(heightExpression(), contains('ih'));
      expect(heightExpression(), contains('min(720'));
    });

    test('选区比 720 小（例如裁出来只有 300 行）：原样留着，不放大', () {
      expect(scaledHeightFor(300), 300);
      expect(scaledHeightFor(719), 719);
    });

    test('选区正好 720 行：一位不动', () {
      expect(scaledHeightFor(720), 720);
    });

    test('源画面高过 720（1080 / 1920）：压到 720', () {
      expect(scaledHeightFor(1080), 720);
      expect(scaledHeightFor(1920), 720);
    });

    test('表达式里没有把高度写死成 720 的写法', () {
      expect(heightExpression(), isNot('720'));
    });
  });
}
