/// 设备信息快照：应用版本（版本号 +
/// 构建号）、测试版构建标识、平台、机型、系统版本、Android SDK 版本六项。取数用
/// 既有的 `package_info_plus` 与 `device_info_plus`，不新增依赖。
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_identity.dart';

/// 设备与版本信息的六项值对象；[toJson] 是包内 `device.json` 的写向。
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.appVersion,
    required this.buildId,
    required this.platform,
    required this.model,
    required this.osVersion,
    required this.androidSdkVersion,
  });

  /// 应用版本号 + 构建号（形如 `0.1.0+1`；构建号为空时只有版本号）。**测试版**
  /// 的版本名自带 `-test` 后缀，因此这一串本身就读得出是哪一份身份。
  final String appVersion;

  /// **测试版**的构建标识（git 短哈希一类，见 `lib/core/app_identity.dart`）；
  /// **正式版**为空串。作者靠它与 [appVersion] 分辨同一版本名的两次测试包。
  final String buildId;

  /// 平台（Android 上为 `android`）。
  final String platform;

  final String? model;

  final String? osVersion;

  /// Android SDK 版本；非 Android 平台为 null。
  final int? androidSdkVersion;

  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'buildId': buildId,
    'platform': platform,
    'model': model,
    'osVersion': osVersion,
    'androidSdkVersion': androidSdkVersion,
  };
}

/// 采集设备信息六项。Android 取 SDK 版本与机型；其余平台没有 SDK 一项，
/// 平台与系统版本按运行环境给出。[buildId] 默认取构建期注入的那一个（见
/// `lib/core/app_identity.dart`），测试可覆写注入固定值。
Future<DeviceSnapshot> loadDeviceSnapshot({String buildId = appBuildId}) async {
  final package = await PackageInfo.fromPlatform();
  final appVersion = package.buildNumber.isEmpty
      ? package.version
      : '${package.version}+${package.buildNumber}';

  if (!Platform.isAndroid) {
    return DeviceSnapshot(
      appVersion: appVersion,
      buildId: buildId,
      platform: Platform.operatingSystem,
      model: null,
      osVersion: Platform.operatingSystemVersion,
      androidSdkVersion: null,
    );
  }

  final info = await DeviceInfoPlugin().androidInfo;
  return DeviceSnapshot(
    appVersion: appVersion,
    buildId: buildId,
    platform: 'android',
    model: info.model,
    osVersion: info.version.release,
    androidSdkVersion: info.version.sdkInt,
  );
}

/// 设备信息注入点：打包含它时读一次；测试覆写注入固定值，不必拉起平台通道。
final deviceSnapshotProvider = FutureProvider<DeviceSnapshot>(
  (ref) => loadDeviceSnapshot(),
);
