import 'package:dance_learning_app/core/app_identity.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_test/flutter_test.dart';

/// App 身份：显示名与构建标识按**安装身份**取值（ADR-0003）。构建期注入的
/// flavor 在宿主测试里改不动，所以显示名那一处抽成纯函数直测；[appDisplayName]
/// 只断言它取的就是本机身份那一份。
void main() {
  test('正式版与测试版的显示名', () {
    expect(displayNameFor(InstallIdentity.official), 'Susume');
    expect(displayNameFor(InstallIdentity.test), 'Susume 测试版');
  });

  test('appDisplayName 取本机身份那一份，短名不带身份标记', () {
    expect(appDisplayName, displayNameFor(buildInstallIdentity));
    expect(appShortName, 'Susume', reason: '首页顶栏只有一行宽度，不承担身份标记');
  });

  test('构建标识未注入时是空串：正式版不进关于页那一行', () {
    expect(appBuildId, '');
  });

  test('宿主测试跑在 default-flavor 上：身份是正式版', () {
    // `pubspec.yaml` 的 `default-flavor: prod` 由 flutter 工具变成
    // FLUTTER_APP_FLAVOR 这个 dart-define，`appFlavor` 因此有值——这条断言把
    // 「不带 --flavor 的命令落在正式版」钉在 Dart 侧。带 `--flavor beta` 跑测试
    // 时它会如实报错：那一跑之下，本仓按正式版写下的其它期望也不再成立。
    expect(appFlavor, 'prod');
    expect(buildInstallIdentity, InstallIdentity.official);
  });
}
