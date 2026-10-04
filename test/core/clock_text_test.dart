import 'package:dance_learning_app/core/clock_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clockMmSs：分秒两位补零，满小时回绕、不显小时', () {
    expect(clockMmSs(Duration.zero), '00:00');
    expect(clockMmSs(const Duration(seconds: 5)), '00:05');
    expect(clockMmSs(Duration(milliseconds: 59999)), '00:59');
    expect(clockMmSs(const Duration(minutes: 6, seconds: 12)), '06:12');
    expect(clockMmSs(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(
      clockMmSs(const Duration(hours: 1, minutes: 5, seconds: 3)),
      '05:03',
    );
  });

  test('clockMss：分钟不补零，小时折进分钟', () {
    expect(clockMss(Duration.zero), '0:00');
    expect(clockMss(const Duration(seconds: 5)), '0:05');
    expect(clockMss(const Duration(seconds: 83)), '1:23');
    expect(clockMss(const Duration(minutes: 12, seconds: 5)), '12:05');
    expect(clockMss(const Duration(hours: 1, minutes: 5, seconds: 3)), '65:03');
  });
}
