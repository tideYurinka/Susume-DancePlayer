/// 系统镜像跳转的真实实现：手写 MethodChannel `susume/system_mirror`
/// （Android 侧 `SystemMirrorSettingsPlugin`），**一页一条方法**——
/// `openCastSettings` 对应系统的「投屏 / 无线显示」设置
/// （`Settings.ACTION_CAST_SETTINGS`，public API since 21，minSdk 24 恒可
/// 用），`openDisplaySettings` 对应显示设置
/// （`Settings.ACTION_DISPLAY_SETTINGS`）。
///
/// **降级链在这里**（ADR-0004 的顺序，可直测）：先问系统投屏设置；它没接住
/// （回 false）或这一页报错，就退到显示设置；两级都不接返回 false。原生只
/// 回答"这一页打不打得开"，不替我们决定顺序，也不认识投屏会话。
///
/// 不引第三方包：这条路只要两条公开的 `Intent`，跳转后的行为不归我们管。
library;

import 'package:flutter/services.dart';

import 'system_mirror.dart';

/// 降级链的两级：**次序即降级次序**（系统「投屏 / 无线显示」设置 →
/// 显示设置）。原生侧逐名实现，本清单是"问到哪一页、按什么次序问"的唯一
/// 来源。
const List<String> kSystemMirrorSettingsPages = [
  'openCastSettings',
  'openDisplaySettings',
];

/// 系统镜像跳转的真实实现（手写平台通道，不引第三方包）。
class PlatformSystemMirrorLauncher implements SystemMirrorLauncher {
  static const _channel = MethodChannel('susume/system_mirror');

  @override
  Future<bool> open() async {
    for (final page in kSystemMirrorSettingsPages) {
      try {
        if (await _channel.invokeMethod<bool>(page) ?? false) return true;
      } on MissingPluginException {
        // 通道不在（非 Android 宿主 / 插件未注册）：两级都无从谈起，
        // 交给调用方给那句短暂提示，本口不抛。
        return false;
      } on PlatformException {
        // 这一页没接住：往下一级退（顺序不因一次失败被跳过）。
      }
    }
    return false;
  }
}
