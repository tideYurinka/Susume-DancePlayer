/// 设备信息快照：应用版本（版本号 +
/// 构建号）、平台、机型、系统版本、Android SDK 版本五项。取数用既有的
/// `package_info_plus` 与 `device_info_plus`，不新增依赖。
library;

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 设备与版本信息的五项值对象；[toJson] 是包内 `device.json` 的写向。
class DeviceSnapshot {
  const DeviceSnapshot({
    required this.appVersion,
    required this.platform,
    required this.model,
    required this.osVersion,
    required this.androidSdkVersion,
  });

  /// 应用版本号 + 构建号（形如 `0.1.0+1`；构建号为空时只有版本号）。
  final String appVersion;

  /// 平台（Android 上为 `android`）。
  final String platform;

  final String? model;

  final String? osVersion;

  /// Android SDK 版本；非 Android 平台为 null。
  final int? androidSdkVersion;

  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'platform': platform,
    'model': model,
    'osVersion': osVersion,
    'androidSdkVersion': androidSdkVersion,
  };
}

/// 采集设备信息五项。Android 取 SDK 版本与机型；其余平台没有 SDK 一项，
/// 平台与系统版本按运行环境给出。
Future<DeviceSnapshot> loadDeviceSnapshot() async {
  final package = await PackageInfo.fromPlatform();
  final appVersion = package.buildNumber.isEmpty
      ? package.version
      : '${package.version}+${package.buildNumber}';

  if (!Platform.isAndroid) {
    return DeviceSnapshot(
      appVersion: appVersion,
      platform: Platform.operatingSystem,
      model: null,
      osVersion: Platform.operatingSystemVersion,
      androidSdkVersion: null,
    );
  }

  final info = await DeviceInfoPlugin().androidInfo;
  return DeviceSnapshot(
    appVersion: appVersion,
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
