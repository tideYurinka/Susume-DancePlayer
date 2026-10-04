import 'package:dance_learning_app/stats/selection_haptic.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dance_learning_app/native_haptic');

  test('非 Android 宿主 / 通道缺失：静默无操作，不抛异常', () async {
    await PlatformSelectionHapticController().selectionImpact();
  });

  test('原生调用失败（PlatformException）：静默无操作，不向页面冒泡', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'no_vibrator');
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await PlatformSelectionHapticController().selectionImpact();
  });
}
