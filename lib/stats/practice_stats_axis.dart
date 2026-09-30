library;

import 'dart:math' as math;

import 'practice_stats_daily.dart';

/// 柱状图 y 轴刻度：由窗口内最大值与单位算出的整齐上界、步长与刻度值
/// 列表（纯件：y 轴刻度）。全部为无 IO 纯函数。

/// 按时间的候选步长（分钟），从小到大。
const List<int> _timeSteps = [1, 2, 5, 10, 15, 30, 60, 120, 180, 360];

/// 按次数的候选步长（场次），从小到大。
const List<int> _countSteps = [1, 2, 5, 10, 20, 50, 100];

/// 刻度档数上限（使刻度不超过 5 档）。
const int _maxIntervals = 5;

/// 一分钟对应的微秒数（时长口径的内部表示换算）。
const int _microsPerMinute = Duration.microsecondsPerMinute;

/// 一组 y 轴刻度：步长、整齐上界与自 0 起的刻度值列表。
///
/// [step] 对两个单位通用：按时间时是分钟，按次数时是场次（一个刻度档
/// 的量）。
class BarChartAxis {
  const BarChartAxis({
    required this.step,
    required this.upperBound,
    required this.ticks,
  });

  /// 一个刻度档的量（按时间 = 分钟，按次数 = 场次）。
  final int step;

  /// 柱高归一用的整齐上界（不小于窗口内最大值，单位同 [step]）。
  final int upperBound;

  /// 刻度值列表（自 0 到上界、按步长升序；柱顶与刻度线同尺）。
  final List<int> ticks;

  /// 上界换算回柱量的内部表示（时长 = 微秒，场次 = 场次数），供柱高
  /// 归一与网格线定位使用。
  int upperInValue(StatsMetric metric) => switch (metric) {
    StatsMetric.time => upperBound * _microsPerMinute,
    StatsMetric.count => upperBound,
  };
}

/// 由窗口内逐日柱与单位算 y 轴刻度（时长按分钟取档，向上取整保证上界
/// 盖住真实柱值；场次直接取档）。见 [barChartAxis]。
BarChartAxis barChartAxisForBars(
  List<DailyPracticeBar> bars,
  StatsMetric metric,
) {
  final maxValue = bars.fold<int>(
    0,
    (max, bar) => switch (metric) {
      // 时长口径以整分钟向上取参与取档，避免上界小于柱值。
      StatsMetric.time => math.max(
        max,
        (bar.total.inMicroseconds + _microsPerMinute - 1) ~/ _microsPerMinute,
      ),
      StatsMetric.count => math.max(max, bar.sessions),
    },
  );
  return barChartAxis(maxValue: maxValue, metric: metric);
}

/// 由窗口内最大值（按时间 = 分钟，按次数 = 场次）与单位算 y 轴刻度：
/// 步长取候选中最小、且最大值落在其不超过 5 档的刻度上者；上界 = 盖住
/// 最大值的最小整档。
///
/// 全零窗口（无任何练习）退化为最小步长的单档：仍画一条基线上方的
/// 网格线，图面不空成没有坐标。
BarChartAxis barChartAxis({
  required int maxValue,
  required StatsMetric metric,
}) {
  final steps = metric == StatsMetric.time ? _timeSteps : _countSteps;
  final step = steps.firstWhere(
    (candidate) => maxValue <= 0 || (maxValue / candidate).ceil() <= _maxIntervals,
    orElse: () => steps.last,
  );
  final upper = maxValue <= 0 ? step : (maxValue / step).ceil() * step;
  return BarChartAxis(step: step, upperBound: upper, ticks: _ticks(step, upper));
}

/// 自 0 到上界、按步长升序的刻度值。
List<int> _ticks(int step, int upper) => [
  for (var tick = 0; tick <= upper; tick += step) tick,
];
