/// 更新网关接缝：把"远端发布的包"变成"本机
/// 可判定的结论"、再变成"应用私有目录里的一个文件"、最后变成"一次系统安装
/// 请求"。真实实现读网络、平台目录与安装请求通道，测试注入
/// `test/helpers/fake_update_gateway.dart` 脚本化替换——与平台分享通道同一
/// 注入手法。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_update_gateway.dart';
import 'update_manifest.dart';

abstract interface class UpdateGateway {
  /// 拉取一次远端版本清单。无网、超时、非 200、正文不可解析——一律返回
  /// null，不抛（失败静默）。
  Future<UpdateManifest?> fetchManifest();

  /// 把安装包下载进应用私有目录：开始前清掉上一个包，完成前不留半成品。
  /// 进度经 [onProgress] 报出（`received` 已收字节、`total` 总字节，总长
  /// 未知时为 0）。失败抛出；被 [cancelDownload] 取消时抛
  /// [UpdateDownloadCancelled]。成功返回安装包的落点路径——请求
  /// 安装装的就是这个文件。
  Future<String> downloadApk({
    required String url,
    required void Function(int received, int total) onProgress,
  });

  /// 取消在飞的下载并删掉半成品文件；无在飞下载时是空操作。返回时半成品
  /// 已不存在（「✕ = 取消」）。
  Future<void> cancelDownload();

  /// 是否已获「安装未知应用」授权：API 26+ 读按应用授权开关，API < 26
  /// 没有这一层、按系统既有行为直接请求安装，返回真。
  Future<bool> canRequestInstall();

  /// 把用户送到本应用的「安装未知应用」设置页；不自动调用。
  Future<void> openInstallSettings();

  /// 拉起系统安装器请求安装 [filePath]（应用私有目录里的安装包）。安装界面
  /// 认的是 APK 自述的应用名与版本号；覆盖安装会杀掉本应用进程，属正常行为。
  Future<void> requestInstall(String filePath);
}

/// 下载被 [UpdateGateway.cancelDownload] 取消：半成品已删除，调用方按
/// 「用户自己关掉的」处理，不报错。
class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();
}

/// 下载失败（非 200 / 连接中断）：提示条出「重试」，不静默。
class UpdateDownloadException implements Exception {
  const UpdateDownloadException();
}

/// 更新网关注入点：真实实现读网络；测试 override 注入 fake。
final updateGatewayProvider = Provider<UpdateGateway>(
  (ref) => PlatformUpdateGateway(),
);
