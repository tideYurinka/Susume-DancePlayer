import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 滑动选择模式进入反馈接缝（可注入）：进模式时经原生
/// 震动通道发一次短震（Android `Vibrator` / `VibratorManager`，不依赖
/// 系统「触摸反馈」开关）。接口 + 真实实现 + provider 注入，手法沿
/// `lib/player/system_volume.dart`、`lib/share_channel/`；测试注入 fake
/// （`test/helpers/fake_selection_haptic.dart`）。
abstract interface class SelectionHapticController {
  /// 一次真机可感知的短震；通道缺失或非 Android 宿主时静默无操作。
  Future<void> selectionImpact();
}

/// 真实实现：平台通道 `dance_learning_app/native_haptic`（Android 侧
/// `NativeHapticPlugin.kt`）。
class PlatformSelectionHapticController implements SelectionHapticController {
  static const _channel = MethodChannel('dance_learning_app/native_haptic');

  @override
  Future<void> selectionImpact() async {
    try {
      await _channel.invokeMethod<void>('impact');
    } on PlatformException {
      // 通道不在或调用失败：静默无操作，不向页面冒泡。
    } on MissingPluginException {
      // 非 Android 宿主 / 测试环境无原生实现：静默无操作。
    }
  }
}

/// 滑动选择模式震动注入点：真实实现走 MethodChannel；测试 override 注入
/// fake。
final selectionHapticProvider = Provider<SelectionHapticController>(
  (ref) => PlatformSelectionHapticController(),
);
