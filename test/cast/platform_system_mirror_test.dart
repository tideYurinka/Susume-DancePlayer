import 'package:dance_learning_app/cast/platform_system_mirror.dart';
import 'package:dance_learning_app/cast/system_mirror.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_system_mirror_launcher.dart';

/// 系统镜像跳转的真实实现直测：经 test messenger 模拟原生侧，钉住**降级链**
/// ——先问系统「投屏 / 无线显示」设置，它接不住（回 false 或报错）才退到显示
/// 设置，两级都不接返回 false（调用方据此给一句短暂提示）。
///
/// 原生侧真的能不能打开这两页（`Settings.ACTION_CAST_SETTINGS` 在真机上的
/// 行为、无 Activity 接时抛不抛）留真机验收——与分享面板那条口径一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('susume/system_mirror');

  /// 原生侧逐页的回答：true = 接住、false = 没接住、PlatformException =
  /// 这一页报错；未列出的页按"没接住"。
  late Map<String, Object?> answers;
  late List<String> asked;

  void installMock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          asked.add(call.method);
          final answer = answers[call.method];
          if (answer is PlatformException) throw answer;
          return answer;
        });
  }

  setUp(() {
    answers = {};
    asked = [];
    installMock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('系统投屏设置接住 ⇒ 只问这一页，不再退到显示设置', () async {
    answers['openCastSettings'] = true;

    expect(await PlatformSystemMirrorLauncher().open(), isTrue);
    expect(asked, ['openCastSettings']);
  });

  test('系统投屏设置接不住 ⇒ 退到显示设置', () async {
    answers['openCastSettings'] = false;
    answers['openDisplaySettings'] = true;

    expect(await PlatformSystemMirrorLauncher().open(), isTrue);
    expect(asked, ['openCastSettings', 'openDisplaySettings']);
  });

  test('两级都不接 ⇒ false（调用方据此给一句短暂提示）', () async {
    answers['openCastSettings'] = false;
    answers['openDisplaySettings'] = false;

    expect(await PlatformSystemMirrorLauncher().open(), isFalse);
    expect(asked, ['openCastSettings', 'openDisplaySettings']);
  });

  test('这一页报错也照样往下一级退（顺序不因一次失败被跳过）', () async {
    answers['openCastSettings'] = PlatformException(code: 'no_activity');
    answers['openDisplaySettings'] = true;

    expect(await PlatformSystemMirrorLauncher().open(), isTrue);
    expect(asked, ['openCastSettings', 'openDisplaySettings']);
  });

  test('原生没返回布尔（null）：按没接住处理，不退化成"成功"', () async {
    answers['openCastSettings'] = null;
    answers['openDisplaySettings'] = true;

    expect(await PlatformSystemMirrorLauncher().open(), isTrue);
    expect(asked, ['openCastSettings', 'openDisplaySettings']);
  });

  test('通道不在（非 Android 宿主 / 插件未注册）⇒ false，不向上抛', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);

    expect(await PlatformSystemMirrorLauncher().open(), isFalse);
  });

  test('降级链的两级次序是唯一来源：清单即问询次序', () {
    expect(kSystemMirrorSettingsPages, [
      'openCastSettings',
      'openDisplaySettings',
    ]);
  });

  test('缺省装配走真实实现；测试可注入替身', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(systemMirrorLauncherProvider),
      isA<PlatformSystemMirrorLauncher>(),
    );

    final fake = FakeSystemMirrorLauncher(opened: false);
    final injected = ProviderContainer(
      overrides: [systemMirrorLauncherProvider.overrideWithValue(fake)],
    );
    addTearDown(injected.dispose);

    expect(await injected.read(systemMirrorLauncherProvider).open(), isFalse);
    expect(fake.openCalls, 1);
  });
}
