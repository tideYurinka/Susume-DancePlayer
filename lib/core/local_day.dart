/// 本地日与日键：全 App 一条口径。
///
/// 归日一律按设备本地时区取日期零点、丢弃时刻；日键是无时刻无时区的
/// `yyyy-MM-dd`，跨重启与跨时区读回同一日。统计聚合与计划日期共用它——
/// 聚合（会话）与明细（桶）必须归到同一天。
library;

/// 本地日归一：取日期零点、丢弃时刻。
DateTime localDay(DateTime time) => DateTime(time.year, time.month, time.day);

/// 本地日键（`yyyy-MM-dd`）：桶分片文档与图表测试键共用。
String localDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';
