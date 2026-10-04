import 'package:dance_learning_app/core/device_clock.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// 测试统一的虚拟今天：计划相关的「今天」全部取它——日期用例的数据与预
/// 期都由它派生，不读真实日期，故任一天跑出的结论一致。
///
/// 取值落在月上旬，使「本月 15 号」这类固定测试日仍是将来的待办目标；
/// 年份取 2026，与滚轮用例里写死的目标日同一年，年列不必跨档。
final DateTime testToday = DateTime(2026, 3, 10);

/// 把设备时钟读面覆写成 [testToday]（与 [localToday] 同源）。
List<Override> testClockOverrides() => [
  deviceClockProvider.overrideWithValue(() => testToday),
];
