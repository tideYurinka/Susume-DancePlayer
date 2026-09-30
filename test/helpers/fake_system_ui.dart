import 'package:dance_learning_app/player/system_ui.dart';

/// 记录调用的假系统 UI 控制器（沉浸模式/方向断言用）。
class FakeSystemUi implements SystemUiController {
  int enterCount = 0;
  int restoreCount = 0;
  int lockLandscapeCount = 0;
  int lockPortraitCount = 0;

  @override
  Future<void> enterPlayerMode() async => enterCount++;

  @override
  Future<void> lockLandscape() async => lockLandscapeCount++;

  @override
  Future<void> lockPortrait() async => lockPortraitCount++;

  @override
  Future<void> restoreDefaultUi() async => restoreCount++;
}
