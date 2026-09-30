import 'package:dance_learning_app/dance/dance_practice_totals.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

/// 练舞统计聚合直测：断言第四处输入（每支舞的累计时长与最近练习）。
void main() {
  group('练舞统计聚合', () {
    test('按 video_id 汇总累计墙钟时长；最近练习取会话末刻', () {
      final totals = dancePracticeTotalsByVideo([
        _record('v1', DateTime(2026, 9, 10, 20), wallSeconds: 600),
        _record('v2', DateTime(2026, 9, 11, 8), wallSeconds: 60),
        _record('v1', DateTime(2026, 9, 12, 9), wallSeconds: 120),
      ]);

      expect(totals['v1']!.total, const Duration(minutes: 12));
      expect(totals['v1']!.lastPracticedAt, DateTime(2026, 9, 12, 9, 2));
      expect(totals['v2']!.total, const Duration(minutes: 1));
      expect(totals['v2']!.lastPracticedAt, DateTime(2026, 9, 11, 8, 1));
    });

    test('无统计记录的舞不在聚合表里（缺统计按零时长、无最近练习兜底）', () {
      expect(dancePracticeTotalsByVideo(const []), isEmpty);
    });

    test('已删视频的记录留在聚合表（列表口径由索引条目决定）', () {
      final totals = dancePracticeTotalsByVideo([
        _record('deleted', DateTime(2026, 9, 10), wallSeconds: 30),
      ]);

      expect(totals, contains('deleted'));
    });
  });
}

PracticeSessionRecord _record(
  String videoId,
  DateTime start, {
  required double wallSeconds,
}) => PracticeSessionRecord(
  start: start,
  videoId: videoId,
  signature: const SongSignature(song: 's'),
  wallSeconds: wallSeconds,
);
