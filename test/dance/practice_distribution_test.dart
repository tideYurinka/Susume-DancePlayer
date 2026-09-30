import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc show BeatGrid, BeatPoint;
import 'package:dance_learning_app/dance/practice_distribution.dart';
import 'package:dance_learning_app/dance/segment_practice_aggregation.dart'
    show SegmentBucketValue;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';
import '../helpers/uniform_test_grid.dart';

/// 练习分布曲线纯件直测：四拍桶采样点（绝对时间区间 + 桶中点）、
/// 范围筛选、时间刻度取样与 `m:ss` 文案。
void main() {
  // 500ms/拍 ⇒ 四拍桶宽 2s；桶 n 左边界 = n × 2s。
  final grid = UniformTestGrid(
    beatInterval: const Duration(milliseconds: 500),
    beatCount: 64,
  );
  final now = DateTime(2026, 9, 15, 12);

  test('桶序列：每个采样点是一个四拍桶，时长求和、次数直取', () {
    final distribution = _build(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {
          0: const SegmentBucketValue(wallSeconds: 1.5, sweeps: 3),
          1: const SegmentBucketValue(wallSeconds: 2.0, sweeps: 2),
          3: const SegmentBucketValue(wallSeconds: 0.5, sweeps: 1),
        },
      }),
      range: PracticeDistributionRange.cumulative,
      now: now,
    );

    // 64 拍、首强拍 0、桶宽 4 拍 ⇒ 16 个桶（左边界 0…30s）。
    expect(distribution.buckets, hasLength(16));
    expect(distribution.buckets[0].duration,
        const Duration(milliseconds: 1500));
    expect(distribution.buckets[0].count, 3);
    // 缺席桶位如实为 0。
    expect(distribution.buckets[2].duration, Duration.zero);
    expect(distribution.buckets[2].count, 0);
    expect(distribution.buckets[3].duration,
        const Duration(milliseconds: 500));
    expect(distribution.beatGridNotReady, isFalse);
  });

  test('桶区间左闭右开，末桶右界按末段线距外推', () {
    final distribution = _build(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1)},
      }),
      range: PracticeDistributionRange.cumulative,
      now: now,
    );

    // 桶 n：[2n s, 2(n+1) s)；末桶（15）右界 = 30s + (30 − 28)s = 32s。
    expect(distribution.buckets[0].start, Duration.zero);
    expect(distribution.buckets[0].end, const Duration(seconds: 2));
    expect(distribution.buckets[1].start, const Duration(seconds: 2));
    expect(distribution.buckets[15].start, const Duration(seconds: 30));
    expect(distribution.buckets[15].end, const Duration(seconds: 32));
  });

  test('桶中点：横坐标取该桶时间区间的中点', () {
    final distribution = _build(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1)},
      }),
      range: PracticeDistributionRange.cumulative,
      now: now,
    );

    expect(distribution.buckets[0].midpoint, const Duration(seconds: 1));
    expect(distribution.buckets[15].midpoint, const Duration(seconds: 31));
  });

  test('真实时间几何：相邻采样点屏距随桶时长变化，不是等距', () {
    // 桶 0 跨 2s（0–2s）、桶 1 跨 3s（2–5s）、桶 2 右界外推到 8s：
    // 相邻屏距随时间跨度 2.5 : 3 变化，不随桶数均分。
    final uneven = _UnevenTestGrid();
    final distribution = _build(
      segments: _segments([4, 8]),
      grid: uneven,
      buckets: _readFace({
        '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1)},
      }),
      range: PracticeDistributionRange.cumulative,
      now: now,
    );

    final xs = timeLerpX(
      [for (final bucket in distribution.buckets) bucket.midpoint],
      width: 300,
      pad: 18,
    );
    expect(xs, hasLength(3));
    expect(distribution.buckets[1].start, const Duration(seconds: 2));
    expect(distribution.buckets[1].end, const Duration(seconds: 5));
    expect(xs[1] - xs[0], closeTo((300 - 36) * 2.5 / 5.5, 0.001));
    expect(xs[2] - xs[1], closeTo((300 - 36) * 3 / 5.5, 0.001));
  });

  test('timeLerpX：单点居中、两端钳在绘图区内', () {
    expect(
      timeLerpX([const Duration(seconds: 3)], width: 300, pad: 18),
      [150],
    );
    final xs = timeLerpX(
      [Duration.zero, const Duration(seconds: 10)],
      width: 300,
      pad: 18,
    );
    expect(xs[0], 18);
    expect(xs[1], 282);
  });

  test('时间刻度取样：点数 1 / 2 / 3 / 7 时取首 / 约 1/3 / 约 2/3 / 末，去重升序', () {
    expect(timeTickIndices(0), isEmpty);
    expect(timeTickIndices(1), [0]);
    expect(timeTickIndices(2), [0, 1]);
    expect(timeTickIndices(3), [0, 1, 2]);
    expect(timeTickIndices(7), [0, 2, 4, 6]);
  });

  test('范围筛选：累计取全部日、近 7 天含今天向前 7 天、今日只取当天', () {
    final buckets = _readFace({
      // 第 8 天（近 7 天窗口外）。
      '2026-09-08': {
        0: const SegmentBucketValue(wallSeconds: 100, sweeps: 9),
        1: const SegmentBucketValue(wallSeconds: 0, sweeps: 9),
      },
      // 窗口首日（今天 − 6）。
      '2026-09-09': {
        0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
        1: const SegmentBucketValue(wallSeconds: 0, sweeps: 1),
      },
      '2026-09-14': {
        0: const SegmentBucketValue(wallSeconds: 2, sweeps: 2),
        1: const SegmentBucketValue(wallSeconds: 0, sweeps: 2),
      },
      '2026-09-15': {
        0: const SegmentBucketValue(wallSeconds: 4, sweeps: 4),
        1: const SegmentBucketValue(wallSeconds: 0, sweeps: 4),
      },
    });
    PracticeDistribution build(PracticeDistributionRange range) => _build(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: buckets,
      range: range,
      now: now,
    );

    expect(
      build(PracticeDistributionRange.cumulative).buckets[0].duration,
      const Duration(seconds: 107),
    );
    expect(
      build(PracticeDistributionRange.last7Days).buckets[0].duration,
      const Duration(seconds: 7),
    );
    expect(
      build(PracticeDistributionRange.today).buckets[0].duration,
      const Duration(seconds: 4),
    );
    expect(build(PracticeDistributionRange.today).buckets[0].count, 4);
  });

  test('范围边界：近 7 天窗口首日计入、前一日不计入', () {
    // 窗口 = 本地日 09-09…09-15（含今天）。
    expect(
      filterPracticeBuckets(
        _readFace({'2026-09-09': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1)}}),
        range: PracticeDistributionRange.last7Days,
        now: now,
      ),
      isNotEmpty,
    );
    expect(
      filterPracticeBuckets(
        _readFace({'2026-09-08': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1)}}),
        range: PracticeDistributionRange.last7Days,
        now: now,
      ),
      isEmpty,
    );
  });

  test('一次装配：曲线与逐段练习值同批返回、共用同一次范围筛选', () {
    final input = PracticeDistributionInput(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 3)},
        '2026-09-08': {0: const SegmentBucketValue(wallSeconds: 2, sweeps: 9)},
      }),
    );

    final cumulative = buildPracticeDistributionView(
      source: input,
      range: PracticeDistributionRange.cumulative,
      now: now,
    );
    expect(
      cumulative.distribution.buckets[0].duration,
      const Duration(seconds: 3),
    );
    expect(
      cumulative.segmentPractices[0].practiceDuration,
      const Duration(seconds: 3),
    );
    expect(cumulative.segmentPractices[0].beatGridNotReady, isFalse);

    // 近 7 天窗口筛掉 09-08 那笔：曲线与逐段值一起只取今日那笔。
    final windowed = buildPracticeDistributionView(
      source: input,
      range: PracticeDistributionRange.last7Days,
      now: now,
    );
    expect(
      windowed.distribution.buckets[0].duration,
      const Duration(seconds: 1),
    );
    expect(
      windowed.segmentPractices[0].practiceDuration,
      const Duration(seconds: 1),
    );
  });

  test('一次装配：网格未就绪时曲线缺数据，逐段值同标缺节拍', () {
    final view = buildPracticeDistributionView(
      source: PracticeDistributionInput(
        segments: _segments([4, 8]),
        buckets: _readFace({
          '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 3)},
        }),
      ),
      range: PracticeDistributionRange.cumulative,
      now: now,
    );

    expect(view.distribution.buckets, isEmpty);
    expect(view.distribution.beatGridNotReady, isTrue);
    expect(view.segmentPractices, hasLength(2));
    expect(view.segmentPractices[0].beatGridNotReady, isTrue);
  });

  test('曲线输入相等性：同内容相等；桶的本地日分布或值变即不等', () {
    PracticeDistributionInput input(
      Map<String, Map<int, SegmentBucketValue>> buckets,
    ) => PracticeDistributionInput(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: buckets,
    );

    const value = SegmentBucketValue(wallSeconds: 1, sweeps: 1);
    final today = input(_readFace({'2026-09-15': {0: value}}));
    expect(today, input(_readFace({'2026-09-15': {0: value}})));
    // 同累计、不同本地日：分布变化必须让读面变化可见（页面据此重算范围）。
    expect(today, isNot(input(_readFace({'2026-09-14': {0: value}}))));
    expect(
      today,
      isNot(
        input(
          _readFace({
            '2026-09-15': {
              0: const SegmentBucketValue(wallSeconds: 1, sweeps: 2),
            },
          }),
        ),
      ),
    );
  });

  test('网格读面失效键含逐段档集合：改段内档即失效', () {
    BeatGrid docGrid({Map<int, double> segmentDensities = const {}}) =>
        documentGridOf(
          marker_doc.BeatGrid(
            model: 'm.onnx',
            fps: 100,
            generatedAt: DateTime.utc(2026, 9, 17),
            beats: const [
              marker_doc.BeatPoint(t: 1, down: true),
              marker_doc.BeatPoint(t: 2, down: false),
              marker_doc.BeatPoint(t: 3, down: false),
              marker_doc.BeatPoint(t: 4, down: false),
            ],
          ),
          segmentDensities: segmentDensities,
        );
    PracticeDistributionInput input(BeatGrid g) => PracticeDistributionInput(
      segments: _segments([4, 8]),
      grid: g,
      buckets: _readFace({
        '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1)},
      }),
    );

    expect(input(docGrid()), input(docGrid()));
    // 改段内档（含清空、改档、增删段）：失效键变化，读面不复用旧网格。
    expect(input(docGrid(segmentDensities: {0: 2})), isNot(input(docGrid())));
    expect(
      input(docGrid(segmentDensities: {0: 2})),
      isNot(input(docGrid(segmentDensities: {0: 0.5}))),
    );
    expect(
      input(docGrid(segmentDensities: {0: 2, 1: 0.5})),
      isNot(input(docGrid(segmentDensities: {0: 2}))),
    );
    expect(input(docGrid(segmentDensities: {0: 2})), input(docGrid(segmentDensities: {0: 2})));
  });

  test('网格未就绪：数值为 0 并标注缺数据', () {
    for (final grid in <BeatGrid?>[null, const UniformBeatGrid()]) {
      final distribution = _build(
        segments: _segments([4, 8]),
        grid: grid,
        buckets: _readFace({
          '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 2, sweeps: 1)},
        }),
        range: PracticeDistributionRange.cumulative,
        now: now,
      );
      expect(distribution.buckets, isEmpty);
      expect(distribution.beatGridNotReady, isTrue);
    }
  });

  test('纵轴取值：时长取微秒数、次数取计数', () {
    final distribution = _build(
      segments: _segments([2, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {0: const SegmentBucketValue(wallSeconds: 2, sweeps: 7)},
      }),
      range: PracticeDistributionRange.cumulative,
      now: now,
    );
    final bucket = distribution.buckets[0];
    expect(
      bucket.valueFor(PracticeDistributionMetric.duration),
      const Duration(seconds: 2).inMicroseconds.toDouble(),
    );
    expect(bucket.valueFor(PracticeDistributionMetric.count), 7);
  });

  group('熟练度色带铺位', () {
    // 绘图区：宽 260、内缩 10，时间域 0–20s ⇒ 1s = 12px。
    const domainStart = Duration.zero;
    const domainEnd = Duration(seconds: 20);
    const width = 260.0;
    const pad = 10.0;

    List<MasteryBand> bands(
      List<LearningSegment> segments, {
      Map<int, LearningMastery>? masteries,
    }) => masteryBands(
      segments: segments,
      masteries:
          masteries ??
          const {
            0: LearningMastery.learning,
            1: LearningMastery.mastered,
            2: LearningMastery.unlearned,
          },
      domainStart: domainStart,
      domainEnd: domainEnd,
      width: width,
      pad: pad,
    );

    test('过渡带宽度：min(12dp, 邻段较窄段宽 × 0.3)；无邻段为 0', () {
      expect(bandTransitionWidth(200, 200), 12);
      expect(bandTransitionWidth(20, 200), 6);
      expect(bandTransitionWidth(20, 20), 6);
      expect(bandTransitionWidth(4, 4), closeTo(1.2, 1e-9));
    });

    test('段像素区间：按真实时间铺位，段界与时间横轴对得上', () {
      final result = bands([
        LearningSegment(order: 0, start: Duration.zero, end: Duration(seconds: 10)),
        LearningSegment(order: 1, start: Duration(seconds: 10), end: Duration(seconds: 20)),
      ]);
      expect(result[0].left, pad);
      expect(result[0].right, closeTo(10 * 12 + pad, 1e-9));
      expect(result[1].left, closeTo(10 * 12 + pad, 1e-9));
      expect(result[1].right, closeTo(width - pad, 1e-9));
      expect(result[0].mastery, LearningMastery.learning);
      expect(result[1].mastery, LearningMastery.mastered);
    });

    test('段跨首末：端点钳到绘图区内，不出现负宽', () {
      final result = bands([
        LearningSegment(
          order: 0,
          start: Duration(seconds: -5),
          end: Duration(seconds: 25),
        ),
      ]);
      expect(result, hasLength(1));
      expect(result[0].left, pad);
      expect(result[0].right, width - pad);
      expect(result[0].width, greaterThanOrEqualTo(0));
    });

    test('极窄段：区间不出现负宽，过渡带按段宽收窄且两半各归各段', () {
      final result = bands([
        LearningSegment(order: 0, start: Duration.zero, end: Duration(seconds: 1)),
        LearningSegment(
          order: 1,
          start: Duration(seconds: 1),
          end: Duration(seconds: 20),
        ),
      ]);
      final narrow = result[0];
      expect(narrow.width, greaterThanOrEqualTo(0));
      // 过渡带宽 = min(12, 12×0.3) = 3.6，以段界为中心各占一半。
      final tw = bandTransitionWidth(narrow.width, result[1].width);
      expect(tw, closeTo(3.6, 1e-9));
      expect(narrow.trailTransition, closeTo(tw, 1e-9));
      expect(result[1].leadTransition, closeTo(tw, 1e-9));
      // 各段固色区不为负：过渡带只吃本段宽的一半。
      expect(narrow.width - narrow.trailTransition / 2, greaterThanOrEqualTo(0));
    });

    test('段间空隙：两段不共界时过渡带为 0，空隙不填色', () {
      final result = bands([
        LearningSegment(order: 0, start: Duration.zero, end: Duration(seconds: 5)),
        LearningSegment(
          order: 1,
          start: Duration(seconds: 10),
          end: Duration(seconds: 15),
        ),
      ]);
      expect(result[0].trailTransition, 0);
      expect(result[1].leadTransition, 0);
      expect(result[0].right, closeTo(5 * 12 + pad, 1e-9));
      expect(result[1].left, closeTo(10 * 12 + pad, 1e-9));
    });

    test('无分段：返回空，图上不画任何色带', () {
      expect(bands(const []), isEmpty);
    });
  });

  group('时间 → 所属学习段', () {
    // 两段：[0,10s)、[10,20s)。
    final two = _segments([10, 20]);

    test('段内时刻归该段', () {
      expect(segmentIndexAtTime(two, const Duration(seconds: 3)), 0);
      expect(segmentIndexAtTime(two, const Duration(seconds: 15)), 1);
    });

    test('恰在段边界：左闭右开，界点归后一段', () {
      expect(segmentIndexAtTime(two, const Duration(seconds: 10)), 1);
      expect(segmentIndexAtTime(two, const Duration(seconds: 20)), isNull);
    });

    test('首线之前 / 尾线之后 / 段间空隙：无段可归，返回空', () {
      final gap = [
        LearningSegment(order: 0, start: Duration.zero, end: const Duration(seconds: 5)),
        LearningSegment(
          order: 1,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 15),
        ),
      ];
      expect(segmentIndexAtTime(two, const Duration(seconds: -1)), isNull);
      expect(segmentIndexAtTime(two, const Duration(seconds: 21)), isNull);
      expect(segmentIndexAtTime(gap, const Duration(seconds: 7)), isNull);
      expect(segmentIndexAtTime(const [], Duration.zero), isNull);
    });
  });

  group('段的横轴像素区间（选中边框 / 气泡锚点 / 色带共用）', () {
    // 绘图区：宽 260、内缩 10，时间域 0–20s ⇒ 1s = 12px。
    const domainStart = Duration.zero;
    const domainEnd = Duration(seconds: 20);
    const width = 260.0;
    const pad = 10.0;

    test('段界越出时间域：端点钳到绘图区，区间不为负', () {
      final range = segmentPixelRange(
        LearningSegment(
          order: 0,
          start: const Duration(seconds: -5),
          end: const Duration(seconds: 25),
        ),
        domainStart: domainStart,
        domainEnd: domainEnd,
        width: width,
        pad: pad,
      );
      expect(range.left, pad);
      expect(range.right, width - pad);
      expect(range.right - range.left, greaterThanOrEqualTo(0));
    });

    test('与色带铺位同一份几何：共界段的左右界逐值一致', () {
      final segments = _segments([10, 20]);
      final bands = masteryBands(
        segments: segments,
        masteries: const {0: LearningMastery.learning, 1: LearningMastery.mastered},
        domainStart: domainStart,
        domainEnd: domainEnd,
        width: width,
        pad: pad,
      );
      for (var i = 0; i < segments.length; i++) {
        final range = segmentPixelRange(
          segments[i],
          domainStart: domainStart,
          domainEnd: domainEnd,
          width: width,
          pad: pad,
        );
        expect(range.left, bands[i].left);
        expect(range.right, bands[i].right);
      }
    });
  });

  group('像素 → 时刻（手势逆映射）', () {
    const domainStart = Duration(seconds: 1);
    const domainEnd = Duration(seconds: 23);
    const width = 264.0;
    const pad = 18.0;

    test('绘图区端点对应域首末；中点对应域中值', () {
      expect(
        timeAtPixel(pad, domainStart: domainStart, domainEnd: domainEnd, width: width, pad: pad),
        domainStart,
      );
      expect(
        timeAtPixel(width - pad, domainStart: domainStart, domainEnd: domainEnd, width: width, pad: pad),
        domainEnd,
      );
      expect(
        timeAtPixel(width / 2, domainStart: domainStart, domainEnd: domainEnd, width: width, pad: pad),
        const Duration(seconds: 12),
      );
    });

    test('越出绘图区：钳到域端，不返回界外时刻', () {
      expect(
        timeAtPixel(0, domainStart: domainStart, domainEnd: domainEnd, width: width, pad: pad),
        domainStart,
      );
      expect(
        timeAtPixel(width, domainStart: domainStart, domainEnd: domainEnd, width: width, pad: pad),
        domainEnd,
      );
    });
  });
}

/// 直测薄适配：把输入字段装进 [PracticeDistributionInput]（生产由快照携带）。
PracticeDistribution _build({
  required List<LearningSegment> segments,
  required BeatGrid? grid,
  required Map<String, Map<int, SegmentBucketValue>> buckets,
  required PracticeDistributionRange range,
  required DateTime now,
}) => buildPracticeDistribution(
  source: PracticeDistributionInput(
    segments: segments,
    grid: grid,
    buckets: buckets,
  ),
  range: range,
  now: now,
);

/// 「本地日 → 桶 → 值」可聚合读面（恒等构造，仅为用例书写简短）。
Map<String, Map<int, SegmentBucketValue>> _readFace(
  Map<String, Map<int, SegmentBucketValue>> days,
) => days;

/// 由边界（首、分段线、尾）造段：段序即列表下标。
List<LearningSegment> _segments(List<int> boundariesSeconds) {
  final bounds = <Duration>[
    Duration.zero,
    for (final seconds in boundariesSeconds) Duration(seconds: seconds),
  ];
  return [
    for (var i = 0; i < bounds.length - 1; i++)
      LearningSegment(order: i, start: bounds[i], end: bounds[i + 1]),
  ];
}

/// 桶宽不均的测试网格：四拍线在 0s / 2s / 5s（末桶右界外推到 8s）。
class _UnevenTestGrid implements BeatGrid {
  final _beatMs = <int>[0, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000,
    6500, 8000];

  @override
  int get firstDownbeatIndex => 0;

  @override
  int get beatsPerBar => 4;

  @override
  BeatGridNature get nature => BeatGridNature.ready;

  @override
  int? get lastBeatIndex => _beatMs.length - 1;

  @override
  Duration beatTime(int index) => Duration(milliseconds: _beatMs[index]);

  @override
  int beatIndexAt(Duration time) {
    for (var i = _beatMs.length - 1; i >= 0; i--) {
      if (_beatMs[i] <= time.inMilliseconds) return i;
    }
    return -1;
  }

  @override
  bool isDownbeat(int index) => index % beatsPerBar == 0;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => [
    for (final ms in _beatMs)
      if (Duration(milliseconds: ms) >= start &&
          Duration(milliseconds: ms) <= end)
        Duration(milliseconds: ms),
  ];
}
