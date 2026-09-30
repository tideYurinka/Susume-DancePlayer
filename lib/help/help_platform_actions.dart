/// 帮助域的**平台动作端口**：正文里的外部网址要交系统浏览器打开、正文里的图
/// 要存进系统相册——都是平台能力，直接写进渲染件会让 widget 测试碰真浏览器
/// 与真相册。这里只放接口：widget 测试用替身覆写实现件里的 Provider，页面与
/// 渲染件不跟 url_launcher / gal 绑死；平台实现件与注入点同住
/// `platform_help_actions.dart`，是引插件依赖的唯一一处。
library;

import 'dart:typed_data';

/// 打开**外部网址**：返回是否真的交出去——`false` = 没交出去（设备上没有
/// 浏览器、系统拒绝等），调用方据此改走「复制地址 + 打不开，已复制地址」。
abstract interface class HelpExternalLinkOpener {
  Future<bool> open(String href);
}

/// 保存**图片**到系统相册的失败基类。失败分两类抛出——权限被拒与其它，供
/// 调用方把提示分成两档（「需要相册权限才能保存」与「保存失败」）。
sealed class HelpImageSaveException implements Exception {
  const HelpImageSaveException();
}

/// 相册访问权被拒（查了没有、申请了仍没有）。
class HelpImageSavePermissionDenied extends HelpImageSaveException {
  const HelpImageSavePermissionDenied();
}

/// 其它保存失败：空间不足、格式不支持、意外等。
class HelpImageSaveFailed extends HelpImageSaveException {
  const HelpImageSaveFailed();
}

/// 保存一张图到系统相册：字节由渲染件从它自己的资产包读出后交来，[name]
/// 是该资产的**文件名**（含扩展名，存下后的文件名与它一致）。权限流程由
/// 实现件负责——先查访问权、无则申请、仍无则抛
/// [HelpImageSavePermissionDenied]；其余失败抛 [HelpImageSaveFailed]。
abstract interface class HelpImageSaver {
  Future<void> save(Uint8List bytes, String name);
}
