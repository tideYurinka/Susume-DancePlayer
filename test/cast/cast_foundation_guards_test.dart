import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 投屏地基的声明面护栏：**新增的三个普通权限要写进清单并写明各自用途**，
/// 假接收端要**独立于本域的实现**（它是我们自己的对照，不是第二个客户端）。
///
/// 这三条都是「仓库里的声明事实」；包在系统里实际拿到什么权限、真电视认不认
/// 我们的 SOAP，归真机验收（步骤见 `lib/cast/docs/real-device-acceptance.md`）。
void main() {
  test('清单里有投屏的三个普通权限，且各有一条写明用途的注释', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    const permissions = {
      'android.permission.ACCESS_NETWORK_STATE': '网络状态',
      'android.permission.ACCESS_WIFI_STATE': 'WiFi 状态',
      'android.permission.CHANGE_WIFI_MULTICAST_STATE': '组播',
    };

    for (final entry in permissions.entries) {
      final declaration = '<uses-permission android:name="${entry.key}" />';
      final index = manifest.indexOf(declaration);
      expect(
        index,
        isNonNegative,
        reason: '投屏要的${entry.value}权限没在清单里：${entry.key}',
      );
      expect(
        manifest.substring(0, index).lastIndexOf('<!--'),
        greaterThan(
          manifest.substring(0, index).lastIndexOf('<uses-permission'),
        ),
        reason: '${entry.key} 上面要紧挨一条写明用途的注释',
      );
      expect(
        manifest.substring(0, index).contains('运行时弹窗'),
        isTrue,
        reason: '三个都是普通权限，注释里要写明没有运行时弹窗',
      );
    }
  });

  test('假接收端不 import 本域：它是独立对照，不是第二个客户端', () {
    final imports = dartImportsOf('tool/cast_fake_receiver.dart');

    expect(imports, isNotEmpty, reason: '扫描不到 import，护栏自身已失效');
    expect(
      imports.where(
        (import) => import.startsWith('package:dance_learning_app/cast/'),
      ),
      isEmpty,
      reason: '假接收端一旦复用本域的报文装配，端到端就不再是独立对照',
    );
  });
}
