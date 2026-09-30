import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/dance/dance_practice_totals.dart';
import 'package:dance_learning_app/dance/segment_practice_aggregation.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    show BeatPoint;
import 'package:dance_learning_app/persistence/practice_stats.dart'
    show PracticeSessionRecord;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:dance_learning_app/stats/four_beat_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';

import '../helpers/document_grid_of.dart';
import '../helpers/uniform_test_grid.dart';

/// 桶 → 段展示分组聚合直测：段序对齐、桶按左边界归段、移动分段线
/// 只换分组、无桶为 0、缺数据时段标注、段界切在桶内时整桶归前一段。
void main() {
  // 500ms/拍 ⇒ 一个四拍桶 2s；桶键 n 的左边界 = n × 2s。
  final grid = UniformTestGrid(
    beatInterval: const Duration(milliseconds: 500),
    beatCount: 64,
  );

  test('桶按左边界归段：段序对齐，时长求和、次数取段内全部桶的最小值', () {
    final result = aggregateSegmentPractice(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {
          0: const SegmentBucketValue(wallSeconds: 1.5, sweeps: 3),
          1: const SegmentBucketValue(wallSeconds: 2.0, sweeps: 2),
          2: const SegmentBucketValue(wallSeconds: 1.0, sweeps: 5),
          3: const SegmentBucketValue(wallSeconds: 0.5, sweeps: 1),
        },
      }),
    );

    expect(result, hasLength(2));
    expect(result[0].practiceDuration, const Duration(milliseconds: 3500));
    expect(result[0].practiceCount, 2);
    expect(result[0].beatGridNotReady, isFalse);
    expect(result[1].practiceDuration, const Duration(milliseconds: 1500));
    expect(result[1].practiceCount, 1);
    expect(result[1].beatGridNotReady, isFalse);
  });

  test('段界切在桶内：整桶（时长与次数）归前一段', () {
    // 桶 1 占 [2s,4s)，分段线切在 3s（桶内）⇒ 桶 1 整桶归段 0。
    final result = aggregateSegmentPractice(
      segments: _segments([3, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {
          0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
          1: const SegmentBucketValue(wallSeconds: 2, sweeps: 1),
        },
      }),
    );

    expect(result[0].practiceDuration, const Duration(seconds: 3));
    expect(result[0].practiceCount, 1);
    expect(result[1].practiceDuration, Duration.zero);
    expect(result[1].practiceCount, 0);
  });

  test('未完整经过的段：段内缺席桶位按扫过 0 计，次数为 0', () {
    final result = aggregateSegmentPractice(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {
          // 段 0 两个桶位都扫过 3 次 ⇒ 完整经过 3 遍。
          0: const SegmentBucketValue(wallSeconds: 1, sweeps: 3),
          1: const SegmentBucketValue(wallSeconds: 1, sweeps: 3),
          // 段 1 只扫过桶 2；桶 3 缺席（= 0 次）⇒ 未完整经过。
          2: const SegmentBucketValue(wallSeconds: 1, sweeps: 3),
        },
      }),
    );

    expect(result[0].practiceCount, 3);
    expect(result[1].practiceDuration, const Duration(seconds: 1));
    expect(result[1].practiceCount, 0);
  });

  test('移动分段线只换分组：同一批桶重新分配，总量守恒', () {
    final buckets = _readFace({
      '2026-09-15': {
        for (var i = 0; i < 6; i++)
          i: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
      },
    });

    final before = aggregateSegmentPractice(
      segments: _segments([4, 20]),
      grid: grid,
      buckets: buckets,
    );
    final after = aggregateSegmentPractice(
      segments: _segments([8, 20]),
      grid: grid,
      buckets: buckets,
    );

    // 线在 4s：段 0 收左边界 0/2s 的桶，段 1 收 4/6/8/10s。
    expect(before[0].practiceDuration, const Duration(seconds: 2));
    expect(before[1].practiceDuration, const Duration(seconds: 4));
    // 线移到 8s：段 0 收 0/2/4/6s，段 1 收 8/10s。
    expect(after[0].practiceDuration, const Duration(seconds: 4));
    expect(after[1].practiceDuration, const Duration(seconds: 2));
  });

  test('跨本地日累计：同桶值求和后再归段', () {
    final result = aggregateSegmentPractice(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: _readFace({
        '2026-09-14': {
          0: const SegmentBucketValue(wallSeconds: 1, sweeps: 2),
          1: const SegmentBucketValue(wallSeconds: 1, sweeps: 2),
        },
        '2026-09-15': {
          0: const SegmentBucketValue(wallSeconds: 2, sweeps: 3),
          1: const SegmentBucketValue(wallSeconds: 1, sweeps: 4),
        },
      }),
    );

    // 桶 0 = 3s/5 次、桶 1 = 2s/6 次 ⇒ 段 0 时长 5s、次数取最小 5。
    expect(result[0].practiceDuration, const Duration(seconds: 5));
    expect(result[0].practiceCount, 5);
  });

  test('桶数据为空：各段为 0，网格就绪不标注缺数据', () {
    final result = aggregateSegmentPractice(
      segments: _segments([4, 8]),
      grid: grid,
      buckets: const {},
    );

    expect(result[0].practiceDuration, Duration.zero);
    expect(result[0].practiceCount, 0);
    expect(result[0].beatGridNotReady, isFalse);
    expect(result[1].practiceDuration, Duration.zero);
    expect(result[1].practiceCount, 0);
    expect(result[1].beatGridNotReady, isFalse);
  });

  test('节拍未就绪：数值为 0 且每段标注缺节拍数据', () {
    for (final grid in <BeatGrid?>[
      null,
      const UniformBeatGrid(), // 占位网格：hasRealBeats 为假
    ]) {
      final result = aggregateSegmentPractice(
        segments: _segments([4, 8]),
        grid: grid,
        buckets: _readFace({
          '2026-09-15': {
            0: const SegmentBucketValue(wallSeconds: 2, sweeps: 1),
          },
        }),
      );

      expect(result[0].practiceDuration, Duration.zero);
      expect(result[0].practiceCount, 0);
      expect(result[0].beatGridNotReady, isTrue);
      expect(result[1].beatGridNotReady, isTrue);
    }
  });

  test('桶位越界：左边界不在任何段内即丢弃', () {
    // 唯一段 [4s,8s)；桶 0/1（左边界 0/2s）在段首之前、桶 5（左边界 10s）
    // 在段尾之后 ⇒ 都无段可归，丢弃；只有桶 2/3（左边界 4/6s）计入。
    final result = aggregateSegmentPractice(
      segments: [
        LearningSegment(
          order: 0,
          start: Duration(seconds: 4),
          end: Duration(seconds: 8),
        ),
      ],
      grid: grid,
      buckets: _readFace({
        '2026-09-15': {
          0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
          1: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
          2: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
          3: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
          5: const SegmentBucketValue(wallSeconds: 9, sweeps: 9),
        },
      }),
    );

    expect(result.single.practiceDuration, const Duration(seconds: 2));
    expect(result.single.practiceCount, 1);
  });

  test('可聚合桶值：同桶累加与相等（存储值同形的漂移防护）', () {
    const a = SegmentBucketValue(wallSeconds: 1.5, sweeps: 2);
    const b = SegmentBucketValue(wallSeconds: 0.5, sweeps: 3);
    expect(a.plus(b), const SegmentBucketValue(wallSeconds: 2, sweeps: 5));
    expect(
      a.plus(b),
      isNot(const SegmentBucketValue(wallSeconds: 2, sweeps: 4)),
    );
  });

  test('无分段线：返回空列表', () {
    expect(
      aggregateSegmentPractice(
        segments: const [],
        grid: grid,
        buckets: _readFace({
          '2026-09-15': {
            0: const SegmentBucketValue(wallSeconds: 1, sweeps: 1),
          },
        }),
      ),
      isEmpty,
    );
  });

  group('统计面不回归：段内档', () {
    // 与上方用例同一支曲子（500ms/拍、64 拍、首拍即强拍）。生产聚合的
    // 网格 = 整曲构造（桶格恒取整曲档）；本组钉住其
    // 字面段级数字，并以「段内档混进聚合网格即偏移」的敏感性配对证明
    // 断言承重。
    final wholeSong = documentGridOf(uniformDownbeatGridDoc(seconds: 32));
    final segmentCarrying = documentGridOf(
      uniformDownbeatGridDoc(seconds: 32),
      segmentDensities: const {0: 2.0},
      segments: const [(startMs: 2000, endMs: 4000)],
    );
    final buckets = _readFace({
      '2026-09-15': {
        0: const SegmentBucketValue(wallSeconds: 1.5, sweeps: 3),
        1: const SegmentBucketValue(wallSeconds: 2.0, sweeps: 2),
        2: const SegmentBucketValue(wallSeconds: 1.0, sweeps: 5),
        3: const SegmentBucketValue(wallSeconds: 0.5, sweeps: 1),
      },
    });

    test('段内档改动前后：段练习时长与段练习次数逐位不变（整曲构造）', () {
      final result = aggregateSegmentPractice(
        segments: _segments([4, 8]),
        grid: wholeSong,
        buckets: buckets,
      );
      // 与既存口径字面一致（上方首条用例的数字）。
      expect(result[0].practiceDuration, const Duration(milliseconds: 3500));
      expect(result[0].practiceCount, 2);
      expect(result[1].practiceDuration, const Duration(milliseconds: 1500));
      expect(result[1].practiceCount, 1);
    });

    test('敏感性配对：段内档混进聚合网格则桶归段偏移——生产网格是整曲构造', () {
      final leaked = aggregateSegmentPractice(
        segments: _segments([4, 8]),
        grid: segmentCarrying,
        buckets: buckets,
      );
      // 段内 ×2 派生把桶位边界挪进段内（桶 1 左边界 2s → 3s），段级数字
      // 随之改变——若统计面开始消费段内档，上方的字面断言即红。
      expect(
        leaked[0].practiceDuration,
        isNot(const Duration(milliseconds: 3500)),
      );
    });

    test('总练习时长只来自会话记录，与任何倍频无关', () {
      // 结构性不回归：聚合函数签名只收会话记录，不存在段内档输入；
      // 字面值钉住口径。
      final records = [
        PracticeSessionRecord(
          start: DateTime.parse('2026-09-14T20:00:00'),
          videoId: 'hash1',
          signature: const SongSignature(song: '曲子'),
          wallSeconds: 100,
        ),
        PracticeSessionRecord(
          start: DateTime.parse('2026-09-15T21:00:00'),
          videoId: 'hash1',
          signature: const SongSignature(song: '曲子'),
          wallSeconds: 80,
        ),
      ];
      final totals = dancePracticeTotalsByVideo(records);
      expect(totals['hash1']!.total, const Duration(seconds: 180));
      expect(
        totals['hash1']!.lastPracticedAt,
        DateTime.parse('2026-09-15T21:01:20'),
      );
    });
  });

  /// 投影 × 聚合整链：档位切换不改段级数字。
  test('×2 档历史投影到原样档：段练习时长与次数同原生 ×2→×1 记录一致', () {
    // 与上方 grid 同一支曲子（500ms/拍、首拍即强拍）。
    final beats = [
      for (var i = 0; i < 64; i++) BeatPoint(t: 0.5 * i, down: i % 4 == 0),
    ];
    FourBeatBucketLines lines(double density) =>
        FourBeatBucketLines.of(beats: beats, shiftMs: 0, density: density);
    RecordedBucket rec(int index, double seconds, int sweeps) => RecordedBucket(
      key: FourBeatBucketKey(2, index),
      wallSeconds: seconds,
      sweeps: sweeps,
    );
    Map<String, Map<int, SegmentBucketValue>> projected(
      List<RecordedBucket> records,
    ) {
      final days = projectFourBeatBuckets(
        days: {'2026-09-15': records},
        recordGridOf: lines,
        currentGrid: lines(1),
      );
      return {
        for (final day in days.entries)
          day.key: {
            for (final entry in day.value.entries)
              entry.key: SegmentBucketValue(
                wallSeconds: entry.value.wallSeconds,
                sweeps: entry.value.sweeps,
              ),
          },
      };
    }

    // 同一段音乐 [0s,4s)：×2 档记在细桶 0..3，×1 档原生记在桶 0、1。
    final fromHalf = projected([
      rec(0, 1, 1),
      rec(1, 1, 1),
      rec(2, 2, 2),
      rec(3, 3, 2),
    ]);
    final native = {
      '2026-09-15': {
        0: const SegmentBucketValue(wallSeconds: 2, sweeps: 1),
        1: const SegmentBucketValue(wallSeconds: 5, sweeps: 2),
      },
    };
    final segments = _segments([4, 8]);
    final a = aggregateSegmentPractice(
      segments: segments,
      grid: grid,
      buckets: fromHalf,
    );
    final b = aggregateSegmentPractice(
      segments: segments,
      grid: grid,
      buckets: {'2026-09-15': native['2026-09-15']!},
    );
    expect(a[0].practiceDuration, b[0].practiceDuration);
    expect(a[0].practiceCount, b[0].practiceCount);
    expect(a[1].practiceDuration, b[1].practiceDuration);
    expect(a[1].practiceCount, b[1].practiceCount);
    expect(a[0].practiceDuration, const Duration(seconds: 7));
    expect(a[0].practiceCount, 1);
  });
}

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

/// 「本地日 → 桶 → 值」可聚合读面（恒等构造，仅为用例书写简短）。
Map<String, Map<int, SegmentBucketValue>> _readFace(
  Map<String, Map<int, SegmentBucketValue>> days,
) => days;
