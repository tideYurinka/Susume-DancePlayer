/// **系统镜像**入口接缝：把用户送到系统自带的「投屏 / 无线显示」设置。
///
/// 本项目**不做屏幕镜像**（本平台对第三方 App 封死了这条路，见 ADR-0004）；
/// 这一枚入口只负责把用户**送过去**——它是"我们这条路走不通"（手边只有
/// Chromecast、没有 DLNA 接收端、或者就要整屏）时的明示退路，不是本功能的
/// 一部分。断开投屏（免得电视上两份画面打架）归调用方：本接缝不认识投屏
/// 会话，只回答"这一页送没送出去"。
///
/// 接口 + 真实实现 + Provider 注入，注入手法沿仓内既有的平台 seam（相机采集
/// / 平台分享通道 / 更新网关）：真实实现走手写 MethodChannel
/// `susume/system_mirror`（`platform_system_mirror.dart`，Android 侧
/// `SystemMirrorSettingsPlugin`），测试注入脚本化替身
/// （`test/helpers/fake_system_mirror_launcher.dart`）。
///
/// **降级链归 Dart 这一侧**（ADR-0004：系统投屏设置 → 显示设置 → 一句短暂
/// 提示）：原生只老实回答"这一页打不打得开"，退到哪一级、以及两级都不行时
/// 给用户看什么字，都由本接缝与其调用方承担——那条链因此可以直测，不靠真机
/// 才能看见。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_system_mirror.dart';

/// 系统镜像跳转接缝。
abstract interface class SystemMirrorLauncher {
  /// 送用户去系统的「投屏 / 无线显示」设置。
  ///
  /// 返回 true = 已送出（某一级系统设置页接住了）；false = 两级都没接住，
  /// **不抛**（非 Android 宿主、通道不在、两级都无 Activity 接）——调用方
  /// 据此给一句**短暂提示**，而不是留一个按了没反应的入口。
  Future<bool> open();
}

/// 系统镜像跳转的注入点：真实实现走手写平台通道；测试 override 注入替身。
final systemMirrorLauncherProvider = Provider<SystemMirrorLauncher>(
  (ref) => PlatformSystemMirrorLauncher(),
);
