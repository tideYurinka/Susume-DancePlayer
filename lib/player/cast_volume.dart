/// 投屏期的音量接缝（票 #38）：音量手势的**写入路径按会话模式分派**——
/// 非投屏走既有的系统媒体音量接缝（`system_volume.dart`），投屏走**投屏
/// 会话**的 `setVolume` / `volume`（接收端上报值）。
///
/// 手势层只认 [SystemMediaVolumeController] 这一条接缝（见 `level_control.dart`
/// 的 `LevelControl`）：本文件的 [CastAwareSystemMediaVolumeController] 是它的
/// 一个实现——**不新起第二条写入支路**，投屏与否只在这里分流。真实接收端侧
/// 的读写由 [CastVolume] 的实现（`cast_run.dart` 的 `CastRunModel`）承担：它
/// 自己收口失败（掉线收口、问不到静默降级），本层不碰网络。
library;

import 'system_volume.dart';

/// 投屏会话的音量读写口（实现：`cast_run.dart` 的投屏运行域）。
///
/// - [setVolume]：把接收端音量设成 0..1；未投屏 = 空操作，失败由实现自己
///   收口（不抛——一次音量写不该把本机播放带停）。
/// - [reportedVolume]：读接收端此刻上报的音量；**问不到 / 没有音量端点 /
///   未投屏一律 null**（静默降级——不拿一次探测把投屏整条收掉）。
abstract interface class CastVolume {
  Future<void> setVolume(double volume);

  Future<double?> reportedVolume();
}

/// 按会话模式分派的音量控制器：投屏态读写**接收端**，其余读写**本机系统
/// 媒体音量**（行为逐位不变）。
///
/// - [volume]：投屏态取 [CastVolume.reportedVolume] 的上报值（这就是「显示值
///   由接收端上报驱动」）；接收端不报时抛错——调用方（`LevelControl`）保持
///   现值，不在界面上凭空显示一个 0。
/// - [setVolume]：投屏态写给接收端（本机系统媒体音量**一位不动**——投屏期
///   手机是遥控器，声音归电视）；非投屏走本机接缝。
/// - [volumeStream]：透传本机接缝，但**投屏期把本机事件滤掉**：侧键改的是
///   手机自己的音量，不该覆盖屏上那个「接收端音量」的读数。
class CastAwareSystemMediaVolumeController
    implements SystemMediaVolumeController {
  CastAwareSystemMediaVolumeController({
    required this.local,
    required this.isCasting,
    required this.cast,
  });

  /// 非投屏态读写的那条接缝（本机系统媒体音量）。
  final SystemMediaVolumeController local;

  /// 现在是不是投屏态（现读闭包——模式值可能在会话期内变化）。
  final bool Function() isCasting;

  /// 投屏态读写的那条口（投屏运行域）。
  final CastVolume cast;

  @override
  Future<double> get volume async {
    if (!isCasting()) return local.volume;
    final reported = await cast.reportedVolume();
    if (reported == null) {
      throw StateError('接收端没报当前音量');
    }
    return reported.clamp(0.0, 1.0);
  }

  @override
  Future<void> setVolume(double value) {
    if (!isCasting()) return local.setVolume(value);
    return cast.setVolume(value.clamp(0.0, 1.0));
  }

  @override
  Stream<double> get volumeStream =>
      local.volumeStream.where((_) => !isCasting());
}
