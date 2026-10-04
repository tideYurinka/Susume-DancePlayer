/// 更新状态机：启动静默检查与版本行发起的那一次检查是同一台机器，它的两个读
/// 面是**版本行**与**更新提示条**——检查只发一次请求、只下一份包，两处说的永
/// 远是同一件事。
///
/// 三件事分成各自的维：
/// - **检查结论**（[UpdateConclusion]）：有没有新版；
/// - **下载阶段**（[UpdateDownloadPhase]）：包在做什么；
/// - **在飞态**（[UpdateInFlight]）：检查中、交安装器这两件短命的事。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_check.dart';
import 'update_gateway.dart';
import 'update_manifest.dart';

/// 检查结论：这台状态机对「有没有新版」的结论。
///
/// 与 [UpdateDownloadPhase] 互相独立——结论说「有没有新版」，阶段说「包在做
/// 什么」。[UpdateConclusion.notChecked] 与 [UpdateConclusion.upToDate] 是
/// 两句不同的话，[UpdateConclusion.checkFailed] 也不假装成其中任何一句。
enum UpdateConclusion {
  /// 还没查过。
  notChecked,

  /// 查过，没有新版。
  upToDate,

  /// 查过，有新版；清单见 [UpdateState.manifest]。
  available,

  /// 检查失败：网络不通或清单读不到。
  checkFailed,
}

/// 下载阶段：包在做什么。不出现 / 可下载 / 下载中 / 下载失败 / 等用户放行
/// 「安装未知应用」。
enum UpdateDownloadPhase {
  /// 不出现：没有可下的包。
  none,
  available,
  downloading,
  failed,
  needsInstallPermission,
}

/// 在飞态：两件短命的事——正在检查、正在交系统安装器。
enum UpdateInFlight { none, checking, installing }

/// 版本行中间格读到的那一个值：**阶段优先、结论兜底**。
enum VersionRowStatus {
  notChecked,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  downloadFailed,
  needsInstallPermission,
  checkFailed,
}

/// 状态机读出的不可变状态：三个维 + 这一份包的读数。
class UpdateState {
  const UpdateState({
    this.conclusion = UpdateConclusion.notChecked,
    this.phase = UpdateDownloadPhase.none,
    this.inFlight = UpdateInFlight.none,
    this.manifest,
    this.received = 0,
    this.total = 0,
    this.filePath,
    this.dismissed = false,
  });

  /// 还没查过、也没有包在动。
  static const UpdateState idle = UpdateState();

  /// 有没有新版。
  final UpdateConclusion conclusion;

  /// 包在做什么。
  final UpdateDownloadPhase phase;

  /// 检查中 / 交安装器这两件短命的事。
  final UpdateInFlight inFlight;

  /// 远端发布的这一版；只有 [UpdateConclusion.available] 与一个非
  /// [UpdateDownloadPhase.none] 的阶段同时成立时才有值。
  final UpdateManifest? manifest;

  /// 下载中已收字节。
  final int received;

  /// 下载总字节；未知时为 0。
  final int total;

  /// 已下载安装包的落点；未下载完时 null。等用户放行授权后，从设置页返回要
  /// 接着装的就是这个文件。
  final String? filePath;

  /// 用户本次会话里按过提示条的 ✕：提示条不再出现，版本行照常读数。
  final bool dismissed;

  /// 下载进度（0–1）；总长未知时为 0。
  double get progress => total > 0 ? received / total : 0;

  /// 更新提示条出不出现：有新版（可下载 / 下载中 / 下载失败 / 等放行）且用户
  /// 没按过 ✕。「已是最新」与「检查失败」都不弹条。
  bool get promptVisible =>
      !dismissed && phase != UpdateDownloadPhase.none && manifest != null;

  /// 版本行中间格的取值：阶段优先、结论兜底。
  VersionRowStatus get versionRowStatus {
    if (inFlight == UpdateInFlight.checking) return VersionRowStatus.checking;
    switch (phase) {
      case UpdateDownloadPhase.downloading:
        return VersionRowStatus.downloading;
      case UpdateDownloadPhase.failed:
        return VersionRowStatus.downloadFailed;
      case UpdateDownloadPhase.needsInstallPermission:
        return VersionRowStatus.needsInstallPermission;
      case UpdateDownloadPhase.available:
        return VersionRowStatus.updateAvailable;
      case UpdateDownloadPhase.none:
        break;
    }
    return switch (conclusion) {
      UpdateConclusion.notChecked => VersionRowStatus.notChecked,
      UpdateConclusion.upToDate => VersionRowStatus.upToDate,
      UpdateConclusion.available => VersionRowStatus.updateAvailable,
      UpdateConclusion.checkFailed => VersionRowStatus.checkFailed,
    };
  }
}

/// 更新编排：检查、下载、取消、重试与交安装器都在这一台机器上；✕ 只关提示条，
/// 版本行照常读数。跑起来的时机由**根壳**给（启动静默检查一次），检查更新由
/// **版本行**发起——本状态机不因为被读到而自己联网。
class UpdateController extends Notifier<UpdateState> {
  /// 使在飞的下载与安装交发作废的世代号：✕ 或新一次下载都 ++，晚到的结果被
  /// 忽略。
  int _generation = 0;

  @override
  UpdateState build() => UpdateState.idle;

  /// 查一次。启动静默检查与手动检查走的是同一个它：结论写进同一台机器，因此
  /// 两个读面结论一致、同一时间只有一次请求在飞。
  Future<void> check() async {
    if (state.inFlight != UpdateInFlight.none ||
        state.phase == UpdateDownloadPhase.downloading) {
      return;
    }
    state = _copyWith(inFlight: UpdateInFlight.checking);
    // 清单读不到、本机构建号读不出、网关违约：一律「检查失败」，不假装
    // 「已是最新」。
    var conclusion = UpdateConclusion.checkFailed;
    UpdateManifest? manifest;
    try {
      final localBuildNumber = await ref.read(localBuildNumberProvider.future);
      final fetched = await ref.read(updateGatewayProvider).fetchManifest();
      if (fetched != null && localBuildNumber != null) {
        if (hasUpdate(manifest: fetched, localBuildNumber: localBuildNumber)) {
          conclusion = UpdateConclusion.available;
          manifest = fetched;
        } else {
          conclusion = UpdateConclusion.upToDate;
        }
      }
    } catch (_) {
      // 失败静默：应用行为与网络不存在时一致。
    }
    if (!ref.mounted) return;
    state = UpdateState(
      conclusion: conclusion,
      manifest: manifest,
      phase: conclusion == UpdateConclusion.available
          ? UpdateDownloadPhase.available
          : UpdateDownloadPhase.none,
      dismissed: state.dismissed,
    );
  }

  /// 取消在飞的那份包：作废晚到的续作，并请网关删掉半成品。版本行的「取消」
  /// 与提示条的 ✕ 共用这一下。
  void _cancelInFlightDownload() {
    _generation++;
    unawaited(ref.read(updateGatewayProvider).cancelDownload());
  }

  /// 按下「取消」（版本行）：中断在飞的那份包、丢掉半成品，回到可下载的位置。
  /// 取消的是这一次下载，不是「有没有新版」这件事——结论与提示条都不动。
  void cancelDownload() {
    if (state.phase != UpdateDownloadPhase.downloading) return;
    _cancelInFlightDownload();
    state = _copyWith(
      phase: UpdateDownloadPhase.available,
      received: 0,
      inFlight: UpdateInFlight.none,
    );
  }

  /// ✕：关掉提示条这一次（不写任何持久状态）；下载中则同时取消并丢掉半成品。
  /// 关掉的是提示条，不是「有没有新版」这件事——所以结论与读数原样留着，用户
  /// 之后从版本行再查一次也不会让它自己冒回来。
  void dismiss() {
    final wasDownloading = state.phase == UpdateDownloadPhase.downloading;
    if (wasDownloading) {
      _cancelInFlightDownload();
    } else {
      // 没有包要取消，同样作废在飞的续作。
      _generation++;
    }
    state = _copyWith(
      phase: wasDownloading ? UpdateDownloadPhase.available : state.phase,
      received: 0,
      inFlight: UpdateInFlight.none,
      dismissed: true,
    );
  }

  /// 按下「下载」/「重试」：开始（或重新开始）一次下载；重试不保留半成品
  /// （网关开始前清包）。下载完成后按授权继续走安装。
  Future<void> download() async {
    final manifest = state.manifest;
    if (manifest == null ||
        state.phase == UpdateDownloadPhase.downloading ||
        state.inFlight != UpdateInFlight.none) {
      return;
    }
    final generation = ++_generation;
    state = UpdateState(
      conclusion: state.conclusion,
      phase: UpdateDownloadPhase.downloading,
      manifest: manifest,
      total: manifest.size,
      dismissed: state.dismissed,
    );
    final String filePath;
    try {
      filePath = await ref
          .read(updateGatewayProvider)
          .downloadApk(
            url: manifest.apkUrl,
            onProgress: (received, total) {
              if (!ref.mounted || generation != _generation) return;
              state = _copyWith(
                phase: UpdateDownloadPhase.downloading,
                received: received,
                total: total > 0 ? total : manifest.size,
              );
            },
          );
    } catch (_) {
      if (!ref.mounted || generation != _generation) return;
      state = _copyWith(phase: UpdateDownloadPhase.failed, received: 0);
      return;
    }
    if (!ref.mounted || generation != _generation) return;
    await _continueToInstall(manifest, filePath, generation);
  }

  /// 按下「前往设置」：把用户送到「安装未知应用」设置页。不自动调用——自动
  /// 跳转会把用户困在设置页里反复弹回来。个别 OEM 没有这一页，拉不起来不出声，
  /// 用户可再按一次。
  Future<void> openInstallSettings() async {
    try {
      await ref.read(updateGatewayProvider).openInstallSettings();
    } catch (_) {
      // 留在原态等下再按，不把错误冒成未处理异常。
    }
  }

  /// 从「安装未知应用」设置页返回时重查一次授权：已放行就继续完成安装；没放
  /// 行则留在原处等用户再按。只在 needsInstallPermission 态触发——若在其它态
  /// 也自动重弹，用户放弃安装器返回就会陷入反复弹安装器的循环。
  Future<void> onAppResumed() async {
    if (state.phase != UpdateDownloadPhase.needsInstallPermission) return;
    final manifest = state.manifest;
    final filePath = state.filePath;
    if (manifest == null || filePath == null) return;
    final generation = _generation;
    if (!await _allowedToInstall()) return;
    if (!ref.mounted || generation != _generation) return;
    state = UpdateState(
      conclusion: UpdateConclusion.available,
      phase: UpdateDownloadPhase.available,
      manifest: manifest,
      dismissed: state.dismissed,
    );
    await _handToInstaller(filePath);
  }

  /// 下载完成后：授权为真直接交系统安装器；为假则改为「需要允许安装未知应
  /// 用」，不自动跳转。交出去之后回到可重下的位置——用户放弃安装器回来时提
  /// 示条还在。
  Future<void> _continueToInstall(
    UpdateManifest manifest,
    String filePath,
    int generation,
  ) async {
    final allowed = await _allowedToInstall();
    if (!ref.mounted || generation != _generation) return;
    if (!allowed) {
      state = UpdateState(
        conclusion: UpdateConclusion.available,
        phase: UpdateDownloadPhase.needsInstallPermission,
        manifest: manifest,
        filePath: filePath,
        dismissed: state.dismissed,
      );
      return;
    }
    state = UpdateState(
      conclusion: UpdateConclusion.available,
      phase: UpdateDownloadPhase.available,
      manifest: manifest,
      dismissed: state.dismissed,
    );
    await _handToInstaller(filePath);
  }

  /// 交系统安装器：拉起期间标成在飞（两个读面都不再发起第二次下载）；拉不起
  /// 来（用户连点、系统拒绝）不把下载件丢掉，用户可再按「下载」重来。
  Future<void> _handToInstaller(String filePath) async {
    state = _copyWith(inFlight: UpdateInFlight.installing);
    try {
      await ref.read(updateGatewayProvider).requestInstall(filePath);
    } catch (_) {
      // 拉不起来不是下载失败：不冒成未处理异常。
    }
    if (!ref.mounted) return;
    state = _copyWith(inFlight: UpdateInFlight.none);
  }

  /// 授权查询：查询本身失败（平台通道不在）按"未获授权"处理，把用户交给设置
  /// 页那一步——不把通道故障伪装成已授权。API < 26 的直通由原生侧返回真。
  Future<bool> _allowedToInstall() async {
    try {
      return await ref.read(updateGatewayProvider).canRequestInstall();
    } catch (_) {
      return false;
    }
  }

  /// 只换给出的那几维，其余原样带走（可空的清单与落点不从这条路上清）。
  UpdateState _copyWith({
    UpdateDownloadPhase? phase,
    UpdateInFlight? inFlight,
    int? received,
    int? total,
    bool? dismissed,
  }) => UpdateState(
    conclusion: state.conclusion,
    phase: phase ?? state.phase,
    inFlight: inFlight ?? state.inFlight,
    manifest: state.manifest,
    received: received ?? state.received,
    total: total ?? state.total,
    filePath: state.filePath,
    dismissed: dismissed ?? state.dismissed,
  );
}

/// 更新状态机注入点：两个读面（版本行与提示条）都读它。
final updateProvider = NotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);
