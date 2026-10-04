import 'dart:io';

import 'package:dance_learning_app/update/platform_update_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 安装请求通道 Dart 侧直测：经 test messenger
/// 模拟原生侧——授权查询、前往设置、请求安装的转发形状；请求安装后不自动删
/// 掉安装包文件。原生设置页与系统安装器的真实行为留真机验收。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const installChannel = MethodChannel('susume/install_request');
  final installCalls = <MethodCall>[];
  var canInstall = true;

  setUp(() {
    installCalls.clear();
    canInstall = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(installChannel, (call) async {
          installCalls.add(call);
          if (call.method == 'canRequestInstall') return canInstall;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(installChannel, null);
  });

  test('授权查询、前往设置、请求安装的转发形状', () async {
    canInstall = false;
    final gateway = PlatformUpdateGateway();

    expect(await gateway.canRequestInstall(), isFalse);
    await gateway.openInstallSettings();
    await gateway.requestInstall('/data/user/0/top.yurinka.susume/files/x.apk');

    expect(installCalls.map((call) => call.method), [
      'canRequestInstall',
      'openInstallSettings',
      'requestInstall',
    ]);
    expect(
      installCalls.last.arguments,
      '/data/user/0/top.yurinka.susume/files/x.apk',
    );
  });

  test('授权为真时查询返回真', () async {
    final gateway = PlatformUpdateGateway();

    expect(await gateway.canRequestInstall(), isTrue);
  });

  test('请求安装后不自动删掉安装包文件（安装器可能仍在惰性读它）', () async {
    // 回归护栏：安装这条路今天只是转发，但将来谁给 requestInstall 加上"装完
    // 清理"会直接违反验收「安装成功不自动删掉安装包文件」，这条会红。
    final directory = await Directory.systemTemp.createTemp('install_channel');
    addTearDown(() => directory.delete(recursive: true));
    final apk = File('${directory.path}/susume-update.apk');
    await apk.writeAsBytes(List<int>.filled(16, 1));
    final gateway = PlatformUpdateGateway();

    await gateway.requestInstall(apk.path);

    expect(await apk.exists(), isTrue);
  });
}
