/// 帮助域平台动作的实现件与注入点：`lib/help/` 里唯一引
/// `url_launcher` 与 `gal` 的一处；渲染件只认 `help_platform_actions.dart`
/// 里的端口接口，测试一律用替身覆写这里的 Provider，不碰真浏览器与真相册。
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:url_launcher/url_launcher.dart';

import 'help_platform_actions.dart';

/// 走 url_launcher 交系统浏览器打开外部网址（二次确认）。地址解析不了或交不
/// 出去时返回 false，不抛——调用方按「打不开」
/// 走复制与提示。
class PlatformHelpExternalLinkOpener implements HelpExternalLinkOpener {
  @override
  Future<bool> open(String href) async {
    final Uri uri;
    try {
      uri = Uri.parse(href);
    } on FormatException {
      return false;
    }
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// 走 gal 把图片字节存进系统相册。权限流程在这里：先查访问权，没有就申请，
/// 申请后仍没有则按**权限被拒**失败；gal 报的其它错误（空间不足、格式不支持、
/// 意外）归**其它失败**。平台没有 gal 实现时抛 MissingPluginException，
/// 同样落进其它失败——不为它单独写代码。
///
/// 相册里的文件名与资产文件名一致：gal 自己按字节探测图片格式补扩展名，故
/// 交给它的 [name] 去掉扩展名（`shot.png` → `shot`，存下仍是 `shot.png` 且
/// 类型正确）。
class PlatformHelpImageSaver implements HelpImageSaver {
  @override
  Future<void> save(Uint8List bytes, String name) async {
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const HelpImageSavePermissionDenied();
      }
      await Gal.putImageBytes(bytes, name: _withoutExtension(name));
    } on HelpImageSaveException {
      rethrow;
    } on GalException catch (e) {
      if (e.type == GalExceptionType.accessDenied) {
        throw const HelpImageSavePermissionDenied();
      }
      throw const HelpImageSaveFailed();
    } catch (_) {
      throw const HelpImageSaveFailed();
    }
  }
}

/// 资产文件名去掉扩展名：gal 的 `name` 入参不接受扩展名，它按字节探测格式
/// 自己补。
///
/// 这处截法属**文件名的世界**（`name` 是相册里那个文件的名字，不是拿给用户
/// 看的名字），规则与「文件名回落名」纯件（`persistence/song_signature.dart`
/// 的 `songFallbackName`）是两条、有意各留一份：两者只在点在末尾这类资产名
/// 里不出现的输入上分岔（`dance.` → 这里 `dance`、那里 `dance.`），且为一次
/// 字符串截断不值得新开 `lib/help → lib/persistence` 这条跨上下文依赖。
/// `test/architecture/naming_fallback_test.dart` 把本处登记为文件世界的豁免。
String _withoutExtension(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

/// 外部网址打开件的注入点：真实实现走 url_launcher；测试 override 注入替身。
final helpExternalLinkOpenerProvider = Provider<HelpExternalLinkOpener>(
  (ref) => PlatformHelpExternalLinkOpener(),
);

/// 图片保存件的注入点：真实实现走 gal；测试 override 注入替身。非 Android
/// 平台不为保存单独写代码——平台实现件在没实现的平台上抛
/// [HelpImageSaveFailed]，调用方走同一句「保存失败」。
final helpImageSaverProvider = Provider<HelpImageSaver>(
  (ref) => PlatformHelpImageSaver(),
);
