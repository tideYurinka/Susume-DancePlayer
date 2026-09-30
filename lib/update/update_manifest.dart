/// 版本清单值类型：远端发布端写出的五个字段，
/// 一个都不多。解析把"任何字段缺失或类型不对"一律
/// 收敛为 null（即"无更新"），不抛异常——联网这件事永远不变成新的故障来源。
library;

import 'dart:convert';

class UpdateManifest {
  const UpdateManifest({
    required this.buildNumber,
    required this.versionName,
    required this.size,
    required this.apkUrl,
    required this.notes,
  });

  /// 判断有无新版本的唯一依据（与 [size] 无关）。
  final int buildNumber;

  /// 用户可见的版本名，形如 `0.1.0`。
  final String versionName;

  /// 安装包字节数。
  final int size;

  final String apkUrl;

  /// 更新说明，允许为空串。
  final String notes;

  /// 解析清单正文；任何不合法（不是 JSON / 字段缺失 / 类型不对）都返回
  /// null。
  static UpdateManifest? parse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;

    final buildNumber = decoded['build_number'];
    if (buildNumber is! int || buildNumber < 0) return null;

    final versionName = decoded['version_name'];
    if (versionName is! String || versionName.isEmpty) return null;

    final size = decoded['size'];
    if (size is! int || size <= 0) return null;

    final apkUrl = decoded['apk_url'];
    if (apkUrl is! String || apkUrl.isEmpty) return null;

    final notes = decoded['notes'];
    if (notes is! String) return null;

    return UpdateManifest(
      buildNumber: buildNumber,
      versionName: versionName,
      size: size,
      apkUrl: apkUrl,
      notes: notes,
    );
  }
}
