import 'package:flutter_test/flutter_test.dart';

/// 顶栏标题自动滚动是匀速循环动画：控制层在场且标题溢出时
/// `pumpAndSettle` 永不收敛。此助手按固定步长泵帧，等待弹层/过渡动画
/// 完成，而不等待循环滚动停歇。
Future<void> pumpPastMarquee(
  WidgetTester tester, {
  int steps = 12,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(step);
  }
}
