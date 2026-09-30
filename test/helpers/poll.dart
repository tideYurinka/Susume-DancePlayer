import 'package:flutter_test/flutter_test.dart';

/// 轮询等待 [condition] 满足（真实事件循环内调用，如 `tester.runAsync`）。
///
/// 每个轮询周期先检查条件，再执行 [onTick]（可选，widget 测试中用于
/// `tester.pump` 推进 fake 定时器/渲染帧），然后等待 [interval]。
/// 超时抛 [fail]（附 [reason]）。
Future<void> pollUntil(
  bool Function() condition, {
  Duration interval = const Duration(milliseconds: 10),
  int maxTries = 300,
  void Function()? onTick,
  String? reason,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    onTick?.call();
    await Future<void>.delayed(interval);
  }
  fail('条件未在预期时间内满足${reason == null ? '' : '：$reason'}');
}
