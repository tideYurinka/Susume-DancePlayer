import 'package:dance_learning_app/core/local_day.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('localDay：取日期零点、丢弃时刻', () {
    expect(localDay(DateTime(2026, 9, 15, 23, 59, 59)), DateTime(2026, 9, 15));
    expect(localDay(DateTime(2026, 9, 15)), DateTime(2026, 9, 15));
  });

  test('localDayKey：yyyy-MM-dd，月日两位补零', () {
    expect(localDayKey(DateTime(2026, 1, 5, 12)), '2026-01-05');
    expect(localDayKey(DateTime(2026, 9, 15)), '2026-09-15');
    expect(localDayKey(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
