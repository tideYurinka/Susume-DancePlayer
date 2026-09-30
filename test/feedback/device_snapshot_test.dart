import 'package:dance_learning_app/feedback/device_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 诊断信息的应用版本：用户可见版本号只留版本名，但包内
/// `device.json` 里的应用版本必须仍带构建号——作者要能区分同一版本名的
/// 两次内测包。
void main() {
  void mockVersion({required String version, required String buildNumber}) {
    PackageInfo.setMockInitialValues(
      appName: 'Susume',
      packageName: 'top.yurinka.susume',
      version: version,
      buildNumber: buildNumber,
      buildSignature: '',
    );
  }

  test('诊断信息的应用版本仍是 版本名+构建号', () async {
    mockVersion(version: '0.1.0', buildNumber: '2');

    final snapshot = await loadDeviceSnapshot();

    expect(snapshot.appVersion, '0.1.0+2');
    expect(snapshot.toJson()['appVersion'], '0.1.0+2');
  });

  test('构建号为空时诊断版本只有版本名', () async {
    mockVersion(version: '0.1.0', buildNumber: '');

    final snapshot = await loadDeviceSnapshot();

    expect(snapshot.appVersion, '0.1.0');
  });
}
