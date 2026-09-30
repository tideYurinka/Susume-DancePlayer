/// 练舞统计聚合（舞库读面的第四处输入）。
///
/// 一次装入整库时只做这一次聚合；聚合表是**超集**（含已删视频的记录），
/// 列表口径由视频索引条目决定——已删视频没有条目可挂，历史统计自然
/// 不进列表。
library;

import '../persistence/practice_stats.dart';
import 'dance_library.dart';

/// 按 video_id 汇总练习时长与最近练习。
///
/// 最近练习取会话末刻（start + 墙钟秒）：磁盘上的会话只留 start 与累计
/// 墙钟秒，末刻是唯一可重建的「最近练习」估计（与练舞统计 store 跨重启
/// 合并时重建最近活动时刻的估计同源）；合并间隙不计入，故略偏早。
Map<String, DancePracticeTotals> dancePracticeTotalsByVideo(
  List<PracticeSessionRecord> records,
) {
  final totals = <String, DancePracticeTotals>{};
  for (final record in records) {
    final wall = record.wallDuration;
    final current = totals[record.videoId] ?? const DancePracticeTotals();
    final end = record.start.add(wall);
    final last = current.lastPracticedAt;
    totals[record.videoId] = DancePracticeTotals(
      total: current.total + wall,
      lastPracticedAt: last == null || end.isAfter(last) ? end : last,
    );
  }
  return Map.unmodifiable(totals);
}
