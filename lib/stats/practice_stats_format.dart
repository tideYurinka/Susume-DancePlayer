import '../core/clock_text.dart';
import '../core/local_day.dart';

/// 时长展示串（统计与舞详情共用）：满一小时 `时:分:秒`（分秒两位补零），
/// 不足一小时省略时位、只显 `分:秒`（分不补零）。
String statsDurationText(Duration duration) {
  final hours = duration.inHours;
  return hours > 0 ? '$hours:${clockMmSs(duration)}' : clockMss(duration);
}

/// 日期标签（首页卡片与舞详情共用）：今天/昨天用相对标签替代具体日期；
/// 同年更早日期 `M月d日`；跨年补年份 `yyyy年M月d日`。
String dayLabel(DateTime day, {required DateTime now}) {
  final today = localDay(now);
  final target = localDay(day);
  if (target == today) return '今天';
  if (target == today.subtract(const Duration(days: 1))) return '昨天';
  if (target.year == now.year) return '${target.month}月${target.day}日';
  return '${target.year}年${target.month}月${target.day}日';
}
