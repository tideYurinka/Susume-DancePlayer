import 'package:dance_learning_app/stats/practice_stats_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 7, 21);
  final today = DateTime(2026, 9, 7, 10);
  final yesterday = DateTime(2026, 9, 6, 10);
  final earlier = DateTime(2026, 9, 4, 10);

  group('时长格式（时:分:秒 / 不足一小时 分:秒）', () {
    test('不足一小时省略时位', () {
      expect(statsDurationText(Duration(seconds: 372)), '6:12');
      expect(statsDurationText(Duration()), '0:00');
      expect(statsDurationText(const Duration(minutes: 59, seconds: 59)),
          '59:59');
    });

    test('满一小时出现时位，分秒补零', () {
      expect(statsDurationText(const Duration(hours: 1)), '1:00:00');
      expect(
        statsDurationText(
          const Duration(hours: 2, minutes: 3, seconds: 4),
        ),
        '2:03:04',
      );
    });
  });

  group('相对日期标签（今天/昨天替代近两日具体日期）', () {
    test('今天与昨天', () {
      expect(dayLabel(today, now: now), '今天');
      expect(dayLabel(yesterday, now: now), '昨天');
    });

    test('更早日期显示具体日期', () {
      expect(dayLabel(earlier, now: now), '9月4日');
    });

    test('跨年显示年份', () {
      expect(dayLabel(DateTime(2025, 12, 31), now: now), '2025年12月31日');
    });
  });
}
