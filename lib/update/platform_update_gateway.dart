/// 更新网关的网络与安装实现：`lib/update/`
/// 里唯一的网络调用点——读版本清单与下载安装包都只在这里落网；安装侧经
/// MethodChannel 交给原生。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_gateway.dart';
import 'update_manifest.dart';

/// 版本清单固定地址：HTTPS + 本项目自定义域。
final Uri updateManifestUrl = Uri.parse('https://dl.yurinka.top/latest.json');

/// 清单请求的 URI：除一个时间戳查询参数外零参数，规避任何中间缓存。
Uri updateManifestRequestUri(DateTime now) => updateManifestUrl.replace(
  queryParameters: {'t': '${now.millisecondsSinceEpoch}'},
);

/// 下载包的固定文件名：应用私有文件目录（Android `getFilesDir()`）里的唯一
/// 落点，逐次覆盖。
const String updateApkFileName = 'susume-update.apk';

/// 真实实现：一次 GET，无请求体、无自定义请求头、无任何用户标识；下载同样
/// 零请求体、零用户标识，写进应用私有目录。
///
/// [resolveBaseDirectory] 是落点解析口子（沿平台分享通道的注入手法）：缺省
/// 取 `path_provider` 的应用私有文件目录（Android 即 `files/`，FileProvider
/// 的 `files-path` 已覆盖），测试传临时目录直测下载与取消。
class PlatformUpdateGateway implements UpdateGateway {
  PlatformUpdateGateway({Future<Directory> Function()? resolveBaseDirectory})
    : resolveBaseDirectory =
          resolveBaseDirectory ?? getApplicationSupportDirectory;

  static const _timeout = Duration(seconds: 10);

  /// 安装请求通道（Android 侧 `InstallRequestPlugin`）：查询按应用授权、
  /// 前往设置页、拉起系统安装器。
  static const _installChannel = MethodChannel('susume/install_request');

  final Future<Directory> Function() resolveBaseDirectory;

  /// 在飞下载用的客户端（取消即强关它）与在飞下载本身（取消要等它把半成品
  /// 删掉才算数）。
  HttpClient? _downloadClient;
  Future<String>? _downloadInFlight;

  /// 取消标记：客户端被强关后下载流以异常结束，靠它把那次异常归为「用户
  /// 取消」而不是「下载失败」。
  bool _downloadCancelled = false;

  @override
  Future<UpdateManifest?> fetchManifest() async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(updateManifestRequestUri(DateTime.now()))
          .timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      return UpdateManifest.parse(body);
    } catch (_) {
      // 无网 / 超时 / DNS 失败 / 连接被拒：与"远端没有更新"同一态。
      return null;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> downloadApk({
    required String url,
    required void Function(int received, int total) onProgress,
  }) {
    final inFlight = _download(url, onProgress);
    _downloadInFlight = inFlight;
    return inFlight.whenComplete(() {
      if (identical(_downloadInFlight, inFlight)) _downloadInFlight = null;
    });
  }

  Future<String> _download(
    String url,
    void Function(int received, int total) onProgress,
  ) async {
    _downloadCancelled = false;
    final target = File(
      p.join((await resolveBaseDirectory()).path, updateApkFileName),
    );
    // 开始新下载前清掉上一个包。
    if (await target.exists()) await target.delete();

    final client = HttpClient();
    _downloadClient = client;
    IOSink? sink;
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw const UpdateDownloadException();
      }
      final total = response.contentLength > 0 ? response.contentLength : 0;
      sink = target.openWrite();
      var received = 0;
      await for (final chunk in response.timeout(_timeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // 取消发生在客户端建立之前时（关不掉连接、流不会出错）也按取消收场。
      if (_downloadCancelled) throw const UpdateDownloadCancelled();
      return target.path;
    } catch (_) {
      // 失败与取消都不留半成品；取消的异常按取消上抛。
      await _discard(sink, target);
      if (_downloadCancelled) throw const UpdateDownloadCancelled();
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(_downloadClient, client)) _downloadClient = null;
    }
  }

  @override
  Future<void> cancelDownload() async {
    _downloadCancelled = true;
    _downloadClient?.close(force: true);
    try {
      await _downloadInFlight;
    } catch (_) {
      // 取消自身的异常：半成品已由下载侧删掉，不冒泡。
    }
  }

  @override
  Future<bool> canRequestInstall() async =>
      await _installChannel.invokeMethod<bool>('canRequestInstall') ?? false;

  @override
  Future<void> openInstallSettings() async {
    await _installChannel.invokeMethod<void>('openInstallSettings');
  }

  @override
  Future<void> requestInstall(String filePath) async {
    await _installChannel.invokeMethod<void>('requestInstall', filePath);
  }

  /// 收尾：关掉写句柄（可能已随取消失效，忽略）并删掉包/半成品。
  Future<void> _discard(IOSink? sink, File target) async {
    try {
      await sink?.close();
    } catch (_) {
      // 句柄已随取消失效。
    }
    if (await target.exists()) await target.delete();
  }
}
