import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'help_platform_actions.dart';
import 'help_snack_bar.dart';
import 'platform_help_actions.dart' show helpImageSaverProvider;

/// 图片保存的三档提示语（**唯一来源**）：成功、相册权限被拒、其它失败。与
/// 链接复制那套同一口径——都是 [SnackBar] 一句话。
const String helpImageSavedMessage = '已保存到相册';
const String helpImageSavePermissionDeniedMessage = '需要相册权限才能保存';
const String helpImageSaveFailedMessage = '保存失败';

/// 保存一张正文里的图到系统相册：字节由**渲染件从它自己的资产包读出**后交给
/// 端口（假资产包因此在测试里仍在环上），文件名取资产的文件名。长按缩略图与
/// 长按全屏大图两处都走这一条链路，行为一致。
Future<void> saveHelpImage(
  WidgetRef ref,
  BuildContext context, {
  required AssetBundle bundle,
  required String assetKey,
}) async {
  final bytes = await _readBytes(bundle, assetKey);
  if (bytes == null) {
    if (context.mounted) showHelpSnackBar(context, helpImageSaveFailedMessage);
    return;
  }
  try {
    await ref
        .read(helpImageSaverProvider)
        .save(bytes, helpImageFileName(assetKey));
    if (context.mounted) showHelpSnackBar(context, helpImageSavedMessage);
  } on HelpImageSavePermissionDenied {
    if (context.mounted) {
      showHelpSnackBar(context, helpImageSavePermissionDeniedMessage);
    }
  } catch (_) {
    if (context.mounted) showHelpSnackBar(context, helpImageSaveFailedMessage);
  }
}

/// 资产 key 的文件名部分（`…/shot.png` → `shot.png`）：存下后的文件名与它
/// 一致，重名由系统相册自己加序号。
String helpImageFileName(String assetKey) => assetKey.split('/').last;

/// 从资产包读出这张图的字节；读不到（资产缺失、读取失败）返回 null，调用方
/// 按「保存失败」提示。
Future<Uint8List?> _readBytes(AssetBundle bundle, String assetKey) async {
  try {
    final data = await bundle.load(assetKey);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null;
  }
}
