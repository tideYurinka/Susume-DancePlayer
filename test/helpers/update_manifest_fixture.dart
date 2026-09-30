import 'dart:convert';

import 'package:dance_learning_app/update/update_manifest.dart';

/// 版本清单里包地址的形状：与 CI 写出的对象键同一
/// 形状，测试与源码护栏共取这一份。
const String updateManifestFixtureApkUrl =
    'https://dl.yurinka.top/releases/0.1.0/susume-0.1.0-arm64.apk';

/// 的样例五字段：边界用例在这份上改/删单个键。
Map<String, Object?> updateManifestJsonFields() => <String, Object?>{
  'build_number': 1,
  'version_name': '0.1.0',
  'size': 81234567,
  'apk_url': updateManifestFixtureApkUrl,
  'notes': '首次内测。',
};

/// 造一份清单 JSON：[fields] 就是要写进去的键值，缺哪个键就不写（边界用）。
/// 不传 = [updateManifestJsonFields]。
String updateManifestJson([Map<String, Object?>? fields]) =>
    jsonEncode(fields ?? updateManifestJsonFields());

/// 解析好的一份清单对象（widget 测试脚本化远端版本用）。
UpdateManifest updateManifestFixture({
  int buildNumber = 1,
  String versionName = '0.1.0',
  int size = 81234567,
  String notes = '首次内测。',
}) => UpdateManifest(
  buildNumber: buildNumber,
  versionName: versionName,
  size: size,
  apkUrl: updateManifestFixtureApkUrl,
  notes: notes,
);
