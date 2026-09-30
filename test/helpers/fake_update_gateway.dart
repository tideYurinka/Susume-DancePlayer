import 'dart:async';

import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:dance_learning_app/update/update_manifest.dart';

/// 脚本化的假更新网关：逐次给出远端清单或
/// "取不到"，可注入失败与挂起，并记录被调用了几次——注入后即可脚本化
/// "有新版本 / 无新版 / 取不到清单"三态；下载侧脚本化"进度序列 / 在飞挂起 /
/// 失败"，并记录下载与取消各被调用了几次；安装侧脚本化"授权为真/为假"，
/// 并记录前往设置与请求安装各被调用的参数。照 `fake_share_channel.dart` 的
/// 既有范式。
class FakeUpdateGateway implements UpdateGateway {
  FakeUpdateGateway({this.manifestScript = const []});

  /// [fetchManifest] 的逐次脚本（用尽后返回 null）。
  final List<UpdateManifest?> manifestScript;
  int _index = 0;

  /// [fetchManifest] 的调用次数：断言"按下那一行会重查一次"。
  int fetchCalls = 0;

  /// 非 null 时 [fetchManifest] 抛出它（替身注入失败）。
  Object? fetchError;

  /// 非 null 时 [fetchManifest] 挂起等它完成（检查在飞时再按的用例）。
  Completer<void>? gate;

  /// [downloadApk] 一进来就逐段报出的进度（`(received, total)`）——报完才
  /// 等 [downloadGate]，测试因此看得见"下载中"的中间态。
  List<(int, int)> progressScript = const [];

  /// [downloadApk] 的调用次数与最后一次地址。
  int downloadCalls = 0;
  String? lastDownloadUrl;

  /// 非 null 时 [downloadApk] 挂在它上面（下载中态用例放行用）。
  Completer<void>? downloadGate;

  /// 非 null 时 [downloadApk] 报完进度后抛出它（下载失败用例）。
  Object? downloadError;

  /// [downloadApk] 成功后返回的落点：与真实实现同样是应用私有目录里的固定
  /// 文件，断言"请求安装装的就是刚下载的那个包"。
  String downloadedFilePath =
      '/data/user/0/top.yurinka.susume/files/susume-update.apk';

  /// [cancelDownload] 的调用次数。
  int cancelCalls = 0;

  /// [canRequestInstall] 的返回值（授权为假用例置 false）、调用次数，以及
  /// 非 null 时抛出的错误（通道故障用例）。
  bool canRequestInstallValue = true;
  int canRequestInstallCalls = 0;
  Object? canRequestInstallError;

  /// [openInstallSettings] 的调用次数。
  int openInstallSettingsCalls = 0;

  /// [requestInstall] 的调用次数与最后一次装的文件。
  int requestInstallCalls = 0;
  String? lastRequestInstallPath;

  /// 非 null 时 [requestInstall] 挂在它上面（交安装器在飞用例放行用）。
  Completer<void>? installGate;

  @override
  Future<UpdateManifest?> fetchManifest() async {
    fetchCalls++;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final error = fetchError;
    if (error != null) throw error;
    if (_index < manifestScript.length) return manifestScript[_index++];
    return null;
  }

  @override
  Future<String> downloadApk({
    required String url,
    required void Function(int received, int total) onProgress,
  }) async {
    downloadCalls++;
    lastDownloadUrl = url;
    for (final (received, total) in progressScript) {
      onProgress(received, total);
    }
    final gate = downloadGate;
    if (gate != null) await gate.future;
    final error = downloadError;
    if (error != null) throw error;
    return downloadedFilePath;
  }

  @override
  Future<void> cancelDownload() async {
    cancelCalls++;
    final gate = downloadGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<bool> canRequestInstall() async {
    canRequestInstallCalls++;
    final error = canRequestInstallError;
    if (error != null) throw error;
    return canRequestInstallValue;
  }

  @override
  Future<void> openInstallSettings() async {
    openInstallSettingsCalls++;
  }

  @override
  Future<void> requestInstall(String filePath) async {
    requestInstallCalls++;
    lastRequestInstallPath = filePath;
    final gate = installGate;
    if (gate != null) await gate.future;
  }
}
