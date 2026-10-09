import 'package:dance_learning_app/cast/cast_coordinates.dart';
import 'package:dance_learning_app/cast/cast_range_gate.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// **投屏坐标换算**直测（纯件）：源坐标 ↔ 副本坐标双向换算、学习段钳制、副本
/// 原点（范围生效时副本 0 是首线）与时长钳制。不构造容器、不构造会话与通道、
/// 不碰网络——一份「各档渲染请求 + 本次学习段」加几个位置就够。
///
/// 期望值都是按口径手算出来的整数（0.5× 档源 30 秒 = 副本 60 秒、0.75× 档源
/// 30 秒 = 副本 40 秒），不是把实现的算法重写一遍。
void main() {
  const videoDuration = Duration(seconds: 60);

  /// 一份渲染请求（素材 60 秒）。
  CastRenderRequest requestOf(
    CastSpeedTier tier, {
    CastRange? range,
    CastRenderChoices choices = const CastRenderChoices.all(),
  }) => CastRenderRequest(
    videoPath: '/videos/这支舞.mp4',
    videoId: 'vid-a',
    duration: videoDuration,
    choices: choices,
    speedTier: tier,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
    range: range,
  );

  CastCoordinates coordinatesOf(
    List<CastSpeedTier> tiers, {
    CastRange? range,
    CastRenderChoices choices = const CastRenderChoices.all(),
    ({Duration start, Duration end})? practiceSpan,
  }) => CastCoordinates(
    requests: {
      for (final tier in tiers)
        tier: requestOf(tier, range: range, choices: choices),
    },
    practiceSpan: practiceSpan,
  );

  group('范围不生效（副本原点仍是源片 0）', () {
    test('源坐标 → 副本坐标：三档各自按倍率缩放', () {
      final coordinates = coordinatesOf(CastSpeedTier.values);

      expect(
        coordinates.copyPositionOf(const Duration(seconds: 30), CastSpeedTier.half),
        const Duration(seconds: 60),
        reason: '0.5× 档：30 ÷ 0.5',
      );
      expect(
        coordinates.copyPositionOf(
          const Duration(seconds: 30),
          CastSpeedTier.threeQuarter,
        ),
        const Duration(seconds: 40),
        reason: '0.75× 档：30 ÷ 0.75',
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 30), CastSpeedTier.full),
        const Duration(seconds: 30),
        reason: '1× 档原样',
      );
    });

    test('副本坐标 → 源坐标：三档各自按倍率换回', () {
      final coordinates = coordinatesOf(CastSpeedTier.values);

      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 60), CastSpeedTier.half),
        const Duration(seconds: 30),
        reason: '0.5× 档：60 × 0.5',
      );
      expect(
        coordinates.sourcePositionOf(
          const Duration(seconds: 40),
          CastSpeedTier.threeQuarter,
        ),
        const Duration(seconds: 30),
        reason: '0.75× 档：40 × 0.75',
      );
      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 30), CastSpeedTier.full),
        const Duration(seconds: 30),
      );
    });

    test('副本原点是源片 0；副本时长按倍率换算（60 秒素材）', () {
      final coordinates = coordinatesOf(CastSpeedTier.values);

      for (final tier in CastSpeedTier.values) {
        expect(coordinates.sourceStartOf(tier), Duration.zero);
      }
      expect(coordinates.copyDurationOf(CastSpeedTier.half), const Duration(seconds: 120));
      expect(
        coordinates.copyDurationOf(CastSpeedTier.threeQuarter),
        const Duration(seconds: 80),
      );
      expect(coordinates.copyDurationOf(CastSpeedTier.full), const Duration(seconds: 60));
    });

    test('越界一律钳进 [0, 目标时长]：过冲收到尾、负读数收到零', () {
      final coordinates = coordinatesOf(CastSpeedTier.values);

      expect(
        coordinates.copyPositionOf(const Duration(seconds: 90), CastSpeedTier.half),
        const Duration(seconds: 120),
        reason: '源 90 秒在 0.5× 档是 180 秒，这一档只有 120 秒',
      );
      expect(
        coordinates.copyPositionOf(
          const Duration(seconds: 100),
          CastSpeedTier.threeQuarter,
        ),
        const Duration(seconds: 80),
        reason: '源 100 秒在 0.75× 档是 133.3 秒，这一档只有 80 秒',
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: -5), CastSpeedTier.half),
        Duration.zero,
        reason: '坏读数不造出负位置',
      );
      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 200), CastSpeedTier.half),
        const Duration(seconds: 60),
        reason: '副本 200 秒是源 100 秒，整片只有 60 秒',
      );
    });
  });

  group('范围生效时副本的时间轴原点挪到首线', () {
    // 素材 60 秒、首线 10 秒、尾线 40 秒：副本覆盖源 10–40 秒（30 秒那一段）。
    const range = CastRange(
      start: Duration(seconds: 10),
      end: Duration(seconds: 40),
    );

    test('副本原点是首线；副本时长按那一段换算', () {
      final coordinates = coordinatesOf(CastSpeedTier.values, range: range);

      for (final tier in CastSpeedTier.values) {
        expect(
          coordinates.sourceStartOf(tier),
          const Duration(seconds: 10),
          reason: '${tier.token}× 档的重编码副本从首线起',
        );
      }
      expect(coordinates.copyDurationOf(CastSpeedTier.full), const Duration(seconds: 30));
      expect(
        coordinates.copyDurationOf(CastSpeedTier.threeQuarter),
        const Duration(seconds: 40),
        reason: '30 ÷ 0.75',
      );
      expect(
        coordinates.copyDurationOf(CastSpeedTier.half),
        const Duration(seconds: 60),
        reason: '30 ÷ 0.5',
      );
    });

    test('源坐标 → 副本坐标：先减首线、再按倍率缩放、最后钳进那一段', () {
      final coordinates = coordinatesOf(CastSpeedTier.values, range: range);

      expect(
        coordinates.copyPositionOf(const Duration(seconds: 10), CastSpeedTier.full),
        Duration.zero,
        reason: '首线那一刻 = 副本 0',
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 20), CastSpeedTier.full),
        const Duration(seconds: 10),
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 15), CastSpeedTier.half),
        const Duration(seconds: 10),
        reason: '0.5× 档：(15 − 10) ÷ 0.5',
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 5), CastSpeedTier.full),
        Duration.zero,
        reason: '首线之前钳到副本头，不推给接收端一个负数',
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 50), CastSpeedTier.full),
        const Duration(seconds: 30),
        reason: '源 50 秒是副本 40 秒，这一段只有 30 秒',
      );
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 100), CastSpeedTier.half),
        const Duration(seconds: 60),
        reason: '(100 − 10) ÷ 0.5 = 180，这一段 0.5× 档只有 60 秒',
      );
    });

    test('副本坐标 → 源坐标：先按倍率换回、再加回首线，尾线之后收到尾线', () {
      final coordinates = coordinatesOf(CastSpeedTier.values, range: range);

      expect(
        coordinates.sourcePositionOf(Duration.zero, CastSpeedTier.full),
        const Duration(seconds: 10),
        reason: '副本 0 = 首线',
      );
      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 20), CastSpeedTier.half),
        const Duration(seconds: 20),
        reason: '首线 10 + 20×0.5',
      );
      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 200), CastSpeedTier.full),
        const Duration(seconds: 40),
        reason: '过冲收到尾线（那一段的尽头），不越过尾线',
      );
    });

    test('复制档即便带着范围也不收：副本原点仍是源片 0', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.full],
        range: range,
        choices: const CastRenderChoices(picture: false, sound: true),
      );

      expect(coordinates.sourceStartOf(CastSpeedTier.full), Duration.zero);
      expect(coordinates.copyDurationOf(CastSpeedTier.full), videoDuration);
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 20), CastSpeedTier.full),
        const Duration(seconds: 20),
        reason: '1× 复制档推的是整片，坐标也照整片',
      );
      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 20), CastSpeedTier.full),
        const Duration(seconds: 20),
      );
    });
  });

  group('换档续播：经源坐标、两端原点的差异都被吸收', () {
    const range = CastRange(
      start: Duration(seconds: 10),
      end: Duration(seconds: 40),
    );

    test('没有学习段：只按两档倍率换算', () {
      final coordinates = coordinatesOf([CastSpeedTier.half, CastSpeedTier.full]);

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 20),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 40),
        reason: '源 20 秒 → 20 ÷ 0.5',
      );
    });

    test('没有学习段、两档原点不同：先回源坐标再加新原点', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.half, CastSpeedTier.full],
        range: range,
      );

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 20),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 40),
        reason: '1× 副本 20 秒 = 源 30 秒 → (30 − 10) ÷ 0.5',
      );
    });

    test('段内：位置原样落进目标档', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.half, CastSpeedTier.full],
        practiceSpan: (
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 6),
        ),
      );

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 5),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 10),
        reason: '源 5 秒在段内 → 5 ÷ 0.5',
      );
    });

    test('段后：收到段尾（续播不落在段外）', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.half, CastSpeedTier.full],
        practiceSpan: (
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 6),
        ),
      );

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 30),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 12),
        reason: '源 30 秒收到段尾 6 秒 → 6 ÷ 0.5',
      );
    });

    test('段前：抬到段头', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.half, CastSpeedTier.full],
        practiceSpan: (
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 6),
        ),
      );

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 1),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 8),
        reason: '源 1 秒抬到段头 4 秒 → 4 ÷ 0.5',
      );
    });

    test('学习段钳制在源坐标上做：范围生效时也收到段尾', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.half, CastSpeedTier.full],
        range: range,
        practiceSpan: (
          start: const Duration(seconds: 12),
          end: const Duration(seconds: 15),
        ),
      );

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 20),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 10),
        reason: '1× 副本 20 秒 = 源 30 秒，收到段尾 15 秒 → (15 − 10) ÷ 0.5',
      );
    });

    test('只勾声音类：1× 复制档与 0.5× 重编码档原点不同，换档也不偏', () {
      final coordinates = coordinatesOf(
        [CastSpeedTier.half, CastSpeedTier.full],
        range: range,
        choices: const CastRenderChoices(picture: false, sound: true),
      );

      expect(
        coordinates.resumePositionOf(
          position: const Duration(seconds: 30),
          from: CastSpeedTier.full,
          to: CastSpeedTier.half,
        ),
        const Duration(seconds: 40),
        reason: '1× 复制档副本 30 秒 = 源 30 秒（不收范围）→ (30 − 10) ÷ 0.5',
      );
    });
  });

  group('没有这一档的请求', () {
    test('原点按源片 0、副本时长不钳（位置照算）', () {
      const coordinates = CastCoordinates();

      expect(coordinates.sourceStartOf(CastSpeedTier.half), Duration.zero);
      expect(coordinates.copyDurationOf(CastSpeedTier.half), isNull);
      expect(
        coordinates.copyPositionOf(const Duration(seconds: 90), CastSpeedTier.half),
        const Duration(seconds: 180),
        reason: '没有这一档的请求就没有它的副本时长，不钳',
      );
      expect(
        coordinates.sourcePositionOf(const Duration(seconds: 180), CastSpeedTier.half),
        const Duration(seconds: 90),
      );
    });
  });
}
