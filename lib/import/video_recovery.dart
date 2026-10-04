/// 找回动作（import 域自持）：为**副本丢失**的舞重新指定它那支视频，
/// 并把副本放回条目记录的原路径。
///
/// 入参 = 条目 + 用户选中的文件；流程 = 算选中文件的**视频标识** → 与条目
/// 身份比对（词条见舞库）：
/// - 相符：把副本复制回条目记录的原路径（父目录按需创建、直接覆盖——那个
///   位置本就是自持副本的位置），并刷新显示名与快速键。身份（视频标识）、
///   大小、文档键、素材键都不动，因此标注、分段熟练度、练习素材、续播位置、
///   镜像与署名原地生效；封面也不用重取——指纹相符即内容相同，按身份命名的
///   封面缓存仍然正确。
/// - 不符：返回「不是这支」，由界面给「按新视频另建一支」（走既有导入管道）
///   或「取消」，不悄悄接上。
/// - 取消 / 任何一步失败：如实返回，状态不变（失败把错与栈带出，界面出声）。
library;

import 'dart:io';

import '../core/video_identity.dart';
import '../persistence/video_index.dart';
import 'local_video_source.dart';
import 'picked_video.dart';
import 'video_picker.dart';

/// 找回结局（四种，穷尽 switch 的论域）。
sealed class VideoRecoveryOutcome {
  const VideoRecoveryOutcome();
}

/// 相符：副本已回到条目记录的原路径；[entry] = 刷新显示名与快速键后的条目
/// （身份、大小、路径与其余键都没动）。
class VideoCopyRestored extends VideoRecoveryOutcome {
  const VideoCopyRestored(this.entry);

  final VideoIndexEntry entry;
}

/// 不符：选中文件的**视频标识**不是这支舞的。界面给「按新视频另建一支」
/// （复用既有导入管道，另建条目与副本，旧舞保持丢失）或「取消」。
/// [picked] 原样带出——另建一支要接着用它，因此这里不清选择器缓存。
class VideoIsNotThisDance extends VideoRecoveryOutcome {
  const VideoIsNotThisDance(this.picked, this.videoId);

  final PickedVideo picked;

  /// 核对时算出的**视频标识**（不是这支舞的）：另建一支直接拿它落条目，
  /// 同内容不必再读一遍（总读取次数不增加）。
  final String videoId;
}

/// 取消：用户在选择器里返回（未选任何文件），零副作用。
class VideoRecoveryCancelled extends VideoRecoveryOutcome {
  const VideoRecoveryCancelled();
}

/// 失败：核对或复制或刷新任一步出错；[error] 与 [stackTrace] 原样带出
/// （界面出声、需要时可按原栈重抛），条目的身份与路径不变。
class VideoRecoveryFailed extends VideoRecoveryOutcome {
  const VideoRecoveryFailed(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// 找回动作：选文件 → 核对**视频标识** → 相符则把副本放回原路径。
class VideoRecovery {
  VideoRecovery(this._picker, {required this.indexStore, required this.hasher});

  final VideoPicker _picker;

  /// 视频索引读写（接口形态供测试注入内存实现）。
  final VideoIndexStorage indexStore;

  /// 视频标识计算（核对用；测试可注入固定值/抛错桩）。
  final ContentHasher hasher;

  /// 「选择视频文件」这条出路：让用户挑一份文件再核对。
  Future<VideoRecoveryOutcome> recover(VideoIndexEntry entry) async {
    final PickedVideo? picked;
    try {
      picked = await _picker.pickVideo();
    } on Object catch (error, stackTrace) {
      return VideoRecoveryFailed(error, stackTrace);
    }
    if (picked == null) return const VideoRecoveryCancelled();
    return restoreFrom(entry, picked);
  }

  /// 核对用户选中的 [picked] 是不是 [entry] 那支；相符即放回原路径。
  ///
  /// 复制发生在比对之后、清缓存之前（清缓存会删掉选择器缓存里的源文件，
  /// 与导入管道同款次序）；显示名与快速键随选中的文件名刷新（原文件名可能
  /// 已改），大小按条目记录不动——标识相符即内容相同。
  Future<VideoRecoveryOutcome> restoreFrom(
    VideoIndexEntry entry,
    PickedVideo picked,
  ) async {
    try {
      final source = _localSourceOf(picked);
      final videoId = await hasher.hashFile(source);
      if (videoId != entry.videoId) return VideoIsNotThisDance(picked, videoId);

      final target = File(entry.filePath);
      await target.parent.create(recursive: true);
      await source.copy(target.path);
      await _picker.clearCache();

      final fastKey = fastKeyFor(name: picked.name, sizeBytes: entry.sizeBytes);
      await indexStore.update(
        (index) => index.refresh(
          entry.videoId,
          displayName: picked.name,
          fastKey: fastKey,
        ),
      );
      // 回读落定后的条目作答（身份与路径本来就不变）：条目在写链里被并发
      // 删掉时按本地刷新结果回答，不凭空失败。
      final refreshed =
          (await indexStore.load()).findById(entry.videoId) ??
          entry.copyWith(displayName: picked.name, fastKey: fastKey);
      return VideoCopyRestored(refreshed);
    } on Object catch (error, stackTrace) {
      return VideoRecoveryFailed(error, stackTrace);
    }
  }

  /// 找回源同样必须物化成本地文件（与导入源的边界同一条，见
  /// [localSourceFileOf]）。
  File _localSourceOf(PickedVideo picked) =>
      localSourceFileOf(picked, what: '找回源');
}
