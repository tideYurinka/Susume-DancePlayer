import 'package:dance_learning_app/cast/cast_range_gate.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// **投屏范围闸门**直测（纯件）：首线→尾线折成 `trim` / `atrim` 的中段节点、
/// 半开口径、整片不装节点、复制档明确不收范围，以及副本时长与时间轴原点的
/// 算术。不启动 widget、不跑进程（与 `cast_mirror_gate_test.dart` 同款）。
void main() {
  CastRenderRequest request({
    CastRange? range,
    CastRenderChoices choices = const CastRenderChoices.all(),
    CastSpeedTier speedTier = CastSpeedTier.full,
    Duration duration = const Duration(seconds: 30),
  }) => CastRenderRequest(
    videoPath: '/videos/a.mp4',
    videoId: 'vid-a',
    duration: duration,
    choices: choices,
    speedTier: speedTier,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
    range: range,
  );

  const range = CastRange(start: Duration(seconds: 2), end: Duration(seconds: 5));

  group('范围口径：源时间轴上的半开区间 [起, 止)', () {
    test('画面节点：trim 收口在起止上，紧接一句把时间基准挪到 0', () {
      expect(range.videoNodes, <String>[
        'trim=start=2:end=5',
        'setpts=PTS-STARTPTS',
      ]);
    });

    test('音轨节点：atrim 同款，紧接 asetpts 把时间基准挪到 0', () {
      expect(range.audioNodes, <String>[
        'atrim=start=2:end=5',
        'asetpts=PTS-STARTPTS',
      ]);
    });

    test('半开式的端点写法里没有 between（那会多收一帧）', () {
      for (final node in [...range.videoNodes, ...range.audioNodes]) {
        expect(node, isNot(contains('between')));
      }
    });

    test('整秒不写成小数、非整秒按既有的秒字面量写法', () {
      const fractional = CastRange(
        start: Duration(milliseconds: 2500),
        end: Duration(milliseconds: 10250),
      );

      expect(fractional.videoNodes.first, 'trim=start=2.5:end=10.25');
    });

    test('时长 = 止减起；空区间与倒置区间都给零（不造出负数时长）', () {
      expect(range.duration, const Duration(seconds: 3));
      expect(
        const CastRange(start: Duration(seconds: 5), end: Duration(seconds: 5))
            .duration,
        Duration.zero,
      );
      expect(
        const CastRange(start: Duration(seconds: 5), end: Duration(seconds: 3))
            .duration,
        Duration.zero,
      );
    });
  });

  group('整片 / 空区间 / 没带范围：一个节点都不装', () {
    test('未设首尾线（首线 0、尾线就是视频时长）= 不收', () {
      expect(
        castRangeActive(
          const CastRange(start: Duration.zero, end: Duration(seconds: 30)),
          const Duration(seconds: 30),
        ),
        isFalse,
        reason: '整片不装节点：链与不设范围逐字一致',
      );
      expect(
        castActiveRangeOf(
          request(
            range: const CastRange(
              start: Duration.zero,
              end: Duration(seconds: 30),
            ),
          ),
        ),
        isNull,
      );
    });

    test('没带范围（null）与空区间 / 倒置区间都不收', () {
      expect(
        castRangeActive(null, const Duration(seconds: 30)),
        isFalse,
      );
      for (final degenerate in const [
        CastRange(start: Duration(seconds: 5), end: Duration(seconds: 5)),
        CastRange(start: Duration(seconds: 5), end: Duration(seconds: 3)),
      ]) {
        expect(
          castRangeActive(degenerate, const Duration(seconds: 30)),
          isFalse,
          reason: '$degenerate 没有可收的一段',
        );
        expect(castActiveRangeOf(request(range: degenerate)), isNull);
      }
    });

    test('只设了尾线（首线仍是 0）：收，节点从 0 起', () {
      final tail = castActiveRangeOf(
        request(
          range: const CastRange(
            start: Duration.zero,
            end: Duration(seconds: 5),
          ),
        ),
      );

      expect(tail?.videoNodes, <String>[
        'trim=start=0:end=5',
        'setpts=PTS-STARTPTS',
      ]);
    });

    test('尾线短于整片之外的越界取值照收（由 trim 自己钳到素材末尾）', () {
      final over = castActiveRangeOf(
        request(
          range: const CastRange(
            start: Duration(seconds: 2),
            end: Duration(seconds: 99),
          ),
        ),
      );

      expect(over, isNotNull);
    });
  });

  group('复制档明确不接受范围（只勾声音类 + 1×）', () {
    test('复制档：范围不进链，也不进音轨（整片推、整片混）', () {
      final copy = request(
        range: range,
        choices: const CastRenderChoices(picture: false, sound: true),
      );

      expect(castActiveRangeOf(copy), isNull);
      expect(castCopySourceStartOf(copy), Duration.zero, reason: '副本原点仍在源片 0');
    });

    test('只勾声音类 + 非 1×：视频为重编码，范围照收（那一档切得动）', () {
      final slowed = request(
        range: range,
        choices: const CastRenderChoices(picture: false, sound: true),
        speedTier: CastSpeedTier.half,
      );

      expect(castActiveRangeOf(slowed), range);
      expect(castCopySourceStartOf(slowed), const Duration(seconds: 2));
    });

    test('勾了画面类：1× 档也收（视频重编码，切得动）', () {
      final picture = request(
        range: range,
        choices: const CastRenderChoices(picture: true, sound: false),
      );

      expect(castActiveRangeOf(picture), range);
    });
  });

  group('副本时长与时间轴原点', () {
    test('范围生效：源跨度 = 那一段，副本时长按倍速档换算', () {
      for (final (tier, expected) in [
        (CastSpeedTier.half, const Duration(seconds: 6)),
        (CastSpeedTier.threeQuarter, const Duration(seconds: 4)),
        (CastSpeedTier.full, const Duration(seconds: 3)),
      ]) {
        final each = request(range: range, speedTier: tier);

        expect(castCopySourceDurationOf(each), const Duration(seconds: 3));
        expect(
          castCopyDurationOf(each),
          expected,
          reason: '${tier.token} 档：3 秒那一段 ÷ ${tier.rate}',
        );
      }
    });

    test('范围不生效（整片 / 复制档）：源跨度与副本时长与今天逐位一致', () {
      const whole = CastRange(start: Duration.zero, end: Duration(seconds: 30));
      final full = request(range: whole);
      final slowed = request(range: whole, speedTier: CastSpeedTier.half);
      final copy = request(
        range: range,
        choices: const CastRenderChoices(picture: false, sound: true),
      );

      expect(castCopySourceDurationOf(full), const Duration(seconds: 30));
      expect(castCopyDurationOf(full), const Duration(seconds: 30));
      expect(castCopyDurationOf(slowed), const Duration(seconds: 60));
      expect(
        castCopySourceDurationOf(copy),
        const Duration(seconds: 30),
        reason: '复制档推的是整片，进度分母与坐标钳制都按整片',
      );
    });

    test('副本原点：范围生效 = 首线；整片与复制档 = 源片 0', () {
      expect(castCopySourceStartOf(request(range: range)), range.start);
      expect(
        castCopySourceStartOf(request(range: range, speedTier: CastSpeedTier.half)),
        range.start,
      );
      expect(castCopySourceStartOf(request()), Duration.zero);
    });
  });
}
