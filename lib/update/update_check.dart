/// 本机构建号与版本判定：更新状态机
/// （`lib/update/update_state.dart`）读它判「有没有新版」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_manifest.dart';

/// 本机构建号：`PackageInfo.buildNumber` 解析，读不出 / 非数字 → null。
final localBuildNumberProvider = FutureProvider<int?>((ref) async {
  try {
    return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
  } catch (_) {
    return null;
  }
});

/// 有没有新版本：远端构建号更大才算有。取不到清单或本机构建号未知一律返回
/// 假——那两种情形由状态机另判成「检查失败」，不在这里下结论。
bool hasUpdate({
  required UpdateManifest? manifest,
  required int? localBuildNumber,
}) {
  if (manifest == null || localBuildNumber == null) return false;
  return manifest.buildNumber > localBuildNumber;
}
