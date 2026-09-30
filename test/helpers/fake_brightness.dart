import 'package:dance_learning_app/player/brightness.dart';

/// 记录调用的假屏幕亮度控制器（左半屏亮度手势断言用）。
class FakeScreenBrightnessController implements ScreenBrightnessController {
  FakeScreenBrightnessController({this.initialBrightness = 1.0});

  /// 当前亮度（0..1），初始可指定；[setBrightness] 会更新它。
  double initialBrightness;

  /// 每次 [setBrightness] 收到的值（按调用顺序）。
  final List<double> setCalls = [];

  @override
  Future<double> get brightness async => initialBrightness;

  @override
  Future<void> setBrightness(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    setCalls.add(clamped);
    initialBrightness = clamped;
  }
}
