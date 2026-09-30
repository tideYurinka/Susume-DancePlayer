import 'package:dance_learning_app/stats/selection_haptic.dart';

/// 记录调用的假选择模式震动控制器（热力图长按进模式断言用）。
class FakeSelectionHapticController implements SelectionHapticController {
  /// [selectionImpact] 的调用次数。
  int impactCalls = 0;

  @override
  Future<void> selectionImpact() async {
    impactCalls++;
  }
}
