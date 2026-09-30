import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/dance_ranking.dart';
import 'package:dance_learning_app/stats/practice_stats_daily.dart';
import 'package:flutter_test/flutter_test.dart';

/// 单舞排行纯件直测：排行按「窗口 × 单位」求值——窗口内时长按舞
/// 累加、场次按舞计数；窗口内当前单位为 0 的现存舞不出行；并列按 videoId
/// 升序。只断言输入输出，不触页面与 IO。
void main() {
  // 2026-09-13 是周日。
  final now = DateTime(2026, 9, 13, 21);

  test('按时间：窗口内时长按舞累加，降序', () {
    final rows = windowDanceRanking(
      [_dance('v1'), _dance('v2'), _dance('v3')],
      [
        _session(DateTime(2026, 9, 13, 10), 300, 'v1'),
        _session(DateTime(2026, 9, 12, 10), 120, 'v1'),
        _session(DateTime(2026, 9, 13, 11), 600, 'v2'),
      ],
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );

    expect([for (final row in rows) row.videoId], ['v2', 'v1']);
    expect(rows[0].total, const Duration(seconds: 600));
    expect(rows[1].total, const Duration(seconds: 420));
  });

  test('按次数：窗口内场次按舞计数，降序；并列按 videoId 升序', () {
    final rows = windowDanceRanking(
      [_dance('v2'), _dance('v1'), _dance('z'), _dance('a')],
      [
        _session(DateTime(2026, 9, 13, 10), 10, 'v1'),
        _session(DateTime(2026, 9, 13, 11), 10, 'v1'),
        _session(DateTime(2026, 9, 12, 10), 60, 'z'),
      ],
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.count,
    );

    // v1 两场在前；z 一场 60s；v2 窗口内没练过（0 场）不出行。
    expect([for (final row in rows) row.videoId], ['v1', 'z']);
    expect(rows[0].sessions, 2);
    expect(rows[0].total, const Duration(seconds: 20));
    expect(rows[1].sessions, 1);
  });

  test('窗口外不计：近 7 天窗口不统计 8 天前的记录', () {
    final rows = windowDanceRanking(
      [_dance('v1')],
      [
        _session(DateTime(2026, 9, 5, 10), 300, 'v1'),
        _session(DateTime(2026, 9, 7, 10), 100, 'v1'),
      ],
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );

    expect(rows.single.videoId, 'v1');
    expect(rows.single.total, const Duration(seconds: 100));
  });

  test('窗口换大，被小窗挤出的舞回到排行', () {
    final records = [_session(DateTime(2026, 6, 20, 10), 300, 'v1')];
    final in7 = windowDanceRanking(
      [_dance('v1')],
      records,
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );
    final in90 = windowDanceRanking(
      [_dance('v1')],
      records,
      now: now,
      window: PracticeStatsWindow.last90,
      metric: StatsMetric.time,
    );

    expect(in7, isEmpty);
    expect(in90.single.total, const Duration(seconds: 300));
  });

  test('0 秒记录不产生时长也不产生场次：该舞不出行', () {
    final rows = windowDanceRanking(
      [_dance('v1'), _dance('v2')],
      [_session(DateTime(2026, 9, 13, 10), 0, 'v1')],
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );
    expect(rows, isEmpty);
  });

  test('两种单位下第一名都持有列表最大值（进度条归一的基准）', () {
    final dances = [_dance('v1'), _dance('v2')];
    final records = [
      _session(DateTime(2026, 9, 13, 10), 300, 'v1'),
      _session(DateTime(2026, 9, 13, 11), 100, 'v2'),
    ];
    final byTime = windowDanceRanking(
      dances,
      records,
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );
    final byCount = windowDanceRanking(
      dances,
      records,
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.count,
    );
    expect(byTime.first.total, const Duration(seconds: 300));
    expect(byTime.first.total, greaterThanOrEqualTo(byTime.last.total));
    expect(byCount.first.sessions, greaterThanOrEqualTo(byCount.last.sessions));
  });

  test('行文案随单位：按时间显示时长，按次数显示整数次数', () {
    final rows = windowDanceRanking(
      [_dance('v1')],
      [_session(DateTime(2026, 9, 13, 10), 300, 'v1')],
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );
    expect(rows.single.valueTextFor(StatsMetric.time), '5:00');
    expect(rows.single.valueTextFor(StatsMetric.count), '1 次');
  });

  test('进度条归一基准 = 列表内最大值，随窗口 × 单位变化', () {
    final dances = [_dance('v1'), _dance('v2'), _dance('v3')];
    final records = [
      _session(DateTime(2026, 9, 13, 10), 300, 'v1'),
      _session(DateTime(2026, 9, 13, 11), 100, 'v2'),
      _session(DateTime(2026, 9, 5, 10), 900, 'v3'), // 近 7 天窗口外
    ];
    final in7Time = windowDanceRanking(
      dances,
      records,
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.time,
    );
    final in7Count = windowDanceRanking(
      dances,
      records,
      now: now,
      window: PracticeStatsWindow.last7,
      metric: StatsMetric.count,
    );
    final in90Time = windowDanceRanking(
      dances,
      records,
      now: now,
      window: PracticeStatsWindow.last90,
      metric: StatsMetric.time,
    );

    // 近 7 天按时间：最大值 = v1 的 300s；按场次：三家各一场，最大值 = 1。
    expect(
      rankingMaxValue(in7Time, StatsMetric.time),
      const Duration(seconds: 300).inMicroseconds,
    );
    expect(rankingMaxValue(in7Count, StatsMetric.count), 1);
    // 近 90 天按时间：最大值 = v3 的 900s。
    expect(
      rankingMaxValue(in90Time, StatsMetric.time),
      const Duration(seconds: 900).inMicroseconds,
    );
  });

  test('0 值舞与已删舞不进排行：不影响次序与最大值', () {
    final dances = [_dance('v1'), _dance('v2'), _dance('zero')];
    final records = [
      _session(DateTime(2026, 9, 13, 10), 300, 'v1'),
      _session(DateTime(2026, 9, 13, 11), 100, 'v2'),
      _session(DateTime(2026, 9, 13, 12), 0, 'zero'), // 0 秒：不出行
      _session(DateTime(2026, 9, 13, 13), 900, 'ghost'), // 已删舞：无条目
    ];
    for (final metric in StatsMetric.values) {
      final rows = windowDanceRanking(
        dances,
        records,
        now: now,
        window: PracticeStatsWindow.last7,
        metric: metric,
      );
      expect([for (final row in rows) row.videoId], ['v1', 'v2']);
      expect(
        rankingMaxValue(rows, metric),
        metric == StatsMetric.time
            ? const Duration(seconds: 300).inMicroseconds
            : 1,
      );
    }
  });

  test('空表没有归一基准：最大值为 0（页面不出进度条）', () {
    expect(rankingMaxValue(const [], StatsMetric.time), 0);
  });

  test('窗口内无任何练习：空表（页面据此显示空文案）', () {
    expect(
      windowDanceRanking(
        [_dance('v1')],
        const [],
        now: now,
        window: PracticeStatsWindow.last7,
        metric: StatsMetric.time,
      ),
      isEmpty,
    );
  });
}

PracticeSessionRecord _session(DateTime start, double seconds, String videoId) =>
    PracticeSessionRecord(
      start: start,
      videoId: videoId,
      signature: SongSignature(song: videoId),
      wallSeconds: seconds,
    );

/// 一支现存舞的快照（排行只列现存舞；时长与场次都来自窗口内记录）。
DanceSnapshot _dance(String videoId) => composeDanceSnapshot(
  entry: _entry(videoId),
  importOrder: 0,
  markers: const MarkersDocument(rangeStartMs: 0, rangeEndMs: 0),
  local: const LocalDocument.empty(),
  practice: const DancePracticeTotals(total: Duration.zero),
);

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
