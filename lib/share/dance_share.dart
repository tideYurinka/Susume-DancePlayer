import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../package/susume_package.dart';

/// 分享编排：详情页「分享」这一条链路的纯侧——
/// 三项勾选的取值、包体预检（估算 + 接近微信单文件上限提示）、装配落盘。
/// 建舞、写组员方案、复制媒体不在此列；递出经 [ShareChannel]。

/// 微信单文件上限（1 GB）的「接近」线：估算达到 900 MiB 即提示，**不
/// 阻止**用户。
const int kSusumeSizeWarnBytes = 900 * 1024 * 1024;

/// 包体估算：markers JSON 编码字节 + 各勾选媒体的字节数。清单本体与
/// zip 结构开销相对媒体可忽略，不逐项模拟中央目录——预检只要量级正确。
int estimateSusumeSizeBytes({
  required Map<String, Object?> markers,
  required List<SusumeMediaEntry> media,
}) =>
    utf8.encode(jsonEncode(markers)).length +
    media.fold(0, (sum, m) => sum + m.sizeBytes);

/// 估算是否已接近微信单文件上限（给出提示；不阻止递出）。
bool susumeSizeNearWechatLimit(int estimateBytes) =>
    estimateBytes >= kSusumeSizeWarnBytes;

/// 装配一支舞的分享包到 [outputDir]：包名 `<歌名>.susume`（未署名回落
/// 视频文件名，规则单处在 [susumePackageFileName]）。返回落盘文件。
Future<File> assembleDancePackage({
  required Directory outputDir,
  required SusumeManifest manifest,
  required Map<String, Object?> markers,
  required String videoFileName,
}) async {
  await outputDir.create(recursive: true);
  final output = File(p.join(
    outputDir.path,
    susumePackageFileName(
      songName: manifest.schemeName,
      videoFileName: videoFileName,
    ),
  ));
  await writeSusumePackage(
    output: output,
    manifest: manifest,
    markers: markers,
  );
  return output;
}

/// 分享产物目录：应用支持目录（Android 上即 `getFilesDir()`）下
/// `susume_share/`——必须落在出站 FileProvider 的 `<files-path path="."/>`
/// 覆盖范围内（递出原文件、零复制）；文档目录 `app_flutter/` 不在
/// `files-path` 内，会被 `getUriForFile` 拒绝。测试覆盖为临时目录。
final susumeShareDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationSupportDirectory();
  final directory = Directory(p.join(base.path, 'susume_share'));
  await directory.create(recursive: true);
  return directory;
});
