import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设备时钟读面：把「现在」收成一个可覆写的注入点。
///
/// 生产缺省即系统时钟，每次读取都取当刻（provider 值本身是函数，长驻进程
/// 跨零点也不会读到旧时刻）；测试在 [ProviderScope] 覆写成固定的虚拟时刻，
/// 使「今天」参与判定的界面与纯件——月视图所示月、时间轴今天线、日程剩余
/// 天数、复习提醒阈值、滚轮年列基准日——与真实日期无关，任一天运行结论一致。
final deviceClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
