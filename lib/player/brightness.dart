import 'package:screen_brightness/screen_brightness.dart';

/// 屏幕亮度控制接缝（可注入，widget 测试断言用）。
///
/// 播放器左半屏上下滑调亮度：手势层只依赖本接口，
/// 真实实现走 [screen_brightness] 的**应用级**亮度
/// （[ScreenBrightness.setApplicationScreenBrightness]：不永久改动系统
/// 设置，Android 无权限要求）；测试注入 fake 记录调用。
abstract interface class ScreenBrightnessController {
  /// 当前应用亮度（0..1）；读取失败抛错由调用方兜底。
  Future<double> get brightness;

  /// 设置应用亮度（0..1；越界钳制）。
  Future<void> setBrightness(double value);
}

/// 真实实现：[screen_brightness] 插件。
class SystemScreenBrightnessController implements ScreenBrightnessController {
  const SystemScreenBrightnessController();

  static final ScreenBrightness _plugin = ScreenBrightness();

  @override
  Future<double> get brightness => _plugin.application;

  @override
  Future<void> setBrightness(double value) {
    return _plugin.setApplicationScreenBrightness(value.clamp(0.0, 1.0));
  }
}
