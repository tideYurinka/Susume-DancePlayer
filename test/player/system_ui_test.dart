import 'package:dance_learning_app/player/system_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 断言方向请求只允许竖屏：含 `portraitUp`，其余方向一律不许。
void expectOnlyPortrait(List<String> calls) {
  final orientationsCall = calls.firstWhere(
    (call) => call.startsWith('SystemChrome.setPreferredOrientations'),
  );
  expect(
    orientationsCall,
    contains(DeviceOrientation.portraitUp.toString()),
    reason: '竖屏锁应请求 portraitUp',
  );
  for (final orientation in DeviceOrientation.values) {
    if (orientation == DeviceOrientation.portraitUp) continue;
    expect(
      orientationsCall.contains(orientation.toString()),
      isFalse,
      reason: '竖屏锁不应允许 ${orientation.name}',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 拦截 SystemChrome 平台通道，返回调用记录（'method:arguments'）。
  Future<List<String>> captureSystemChromeCalls(
    Future<void> Function() action,
  ) async {
    final calls = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add('${call.method}:${call.arguments}');
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await action();
    return calls;
  }

  test('enterPlayerMode：沉浸模式 + 允许全方向（随设备自动旋转）', () async {
    final calls = await captureSystemChromeCalls(
      () => const SystemChromeSystemUiController().enterPlayerMode(),
    );

    expect(
      calls,
      contains(
        'SystemChrome.setEnabledSystemUIMode:SystemUiMode.immersiveSticky',
      ),
    );
    final orientationsCall = calls.firstWhere(
      (call) => call.startsWith('SystemChrome.setPreferredOrientations'),
    );
    for (final orientation in DeviceOrientation.values) {
      expect(
        orientationsCall,
        contains(orientation.toString()),
        reason: '播放界面不应锁定方向：应允许 ${orientation.name}',
      );
    }
  });

  test('lockPortrait：只请求竖屏，不改变系统 UI 模式（全局竖屏锁）', () async {
    final calls = await captureSystemChromeCalls(
      () => const SystemChromeSystemUiController().lockPortrait(),
    );

    expectOnlyPortrait(calls);
    expect(
      calls.any(
        (call) => call.startsWith('SystemChrome.setEnabledSystemUIMode'),
      ),
      isFalse,
      reason: '锁竖屏不改变系统 UI：启动瞬间与非播放器页面不得进入沉浸模式',
    );
  });

  test('restoreDefaultUi：恢复系统 UI（edgeToEdge）并落回竖屏锁', () async {
    final calls = await captureSystemChromeCalls(
      () => const SystemChromeSystemUiController().restoreDefaultUi(),
    );

    expect(
      calls,
      contains('SystemChrome.setEnabledSystemUIMode:SystemUiMode.edgeToEdge'),
    );
    // 退出播放器落回全局竖屏锁。
    expectOnlyPortrait(calls);
  });

  test('lockLandscape：保持沉浸并只允许横屏', () async {
    final calls = await captureSystemChromeCalls(
      () => const SystemChromeSystemUiController().lockLandscape(),
    );

    expect(
      calls,
      contains(
        'SystemChrome.setEnabledSystemUIMode:SystemUiMode.immersiveSticky',
      ),
    );
    final orientationsCall = calls.firstWhere(
      (call) => call.startsWith('SystemChrome.setPreferredOrientations'),
    );
    expect(
      orientationsCall,
      contains(DeviceOrientation.landscapeLeft.toString()),
    );
    expect(
      orientationsCall,
      contains(DeviceOrientation.landscapeRight.toString()),
    );
    expect(
      orientationsCall.contains(DeviceOrientation.portraitUp.toString()),
      isFalse,
      reason: '锁定横屏后不应允许竖屏',
    );
  });
}
