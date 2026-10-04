/// 舞库管理写（见词条「舞库」）：会话不在场时的写路径。
///
/// 管理写不建会话、不持基线，一律经按视频文档存取的原子读改写执行——
/// 「每次写入都是一次原子读改写」是防丢更新的结构事实，与打开会话同时
/// 存在也不互相覆盖。本文件零 Flutter、零 UI。
library;

import '../annotation/learning_segment_attributes.dart';
import '../persistence/video_index.dart';
import '../persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveSeed, firstBuildSeeded;
import '../persistence/document_read_outcome.dart';
import '../persistence/local_document.dart';
import '../persistence/marker_document.dart';
import '../persistence/song_signature.dart';
import '../persistence/video_document_store.dart';
import 'dance_library.dart';

/// 舞库自持的管理写路径：改名（公开标记文件署名真值 + 索引署名缓存）与
/// 逐段改档 / 一键完全掌握 / 撤销（本地文档 `session.mastery`）。
class DanceLibraryWrites {
  DanceLibraryWrites({
    required this.indexStore,
    required this.storageFor,
    this.onRenamed,
  });

  final VideoIndexStorage indexStore;
  final VideoDocumentStorage Function(String videoId) storageFor;

  /// 改名后的补动作（装配处接系统推送同步）：索引署名缓存写成功后回调
  /// 一次——读它做名字来源的消费方此刻已能读到新名。null = 未接；回调不
  /// 参与改名成立与否的判定，缓存写失败也不回调。
  final Future<void> Function()? onRenamed;

  /// 改名：公开标记文件 `meta` 段的署名真值（先）与视频索引的署名缓存
  /// （后），两条都写、收在这一处动作里。
  ///
  /// [input] 是编辑框的原始输入，按既有净化口径去空白/控制字符并把空歌名
  /// 回退到条目的显示名。返回 true = 署名真值已落盘（改名成立）。真值写
  /// 失败 → 索引缓存不动、返回 false（零副作用）；真值成功而索引写失败 →
  /// 改名仍成立（下次打开以真值回写缓存），索引保持原样、不留半写状态。
  /// 首建（markers 不存在/损坏）以索引署名缓存 + 镜像过渡值立底，不把用户
  /// 既有组态冲成缺省。
  Future<bool> rename({
    required VideoIndexEntry entry,
    required SongSignature input,
  }) async {
    final signature = sanitizeSignature(input, fallbackSong: entry.displayName);
    final storage = storageFor(entry.videoId);
    final coordinator = VideoDocumentCoordinator(storage);
    try {
      final outcome = await coordinator.readMarkersOutcome();
      if (outcome is! WritableDocumentReadOutcome<MarkersDocument>) {
        return false;
      }
      final result = await outcome.write((context) {
        final seeded = firstBuildSeeded(
          context.document,
          present: context.present,
          seed: AnnotationSaveSeed(
            signature: entry.signatureCache,
            mirrored: entry.mirrored,
            localMirrorEnabled: entry.localMirrorEnabled,
          ),
        );
        return seeded.withSignature(signature);
      });
      if (result is DocumentWriteRejected<MarkersDocument>) return false;
    } on Object {
      return false;
    }
    try {
      await indexStore.update(
        (index) => index.setSignatureCacheByFilePath(entry.filePath, signature),
      );
    } on Object {
      // 索引写失败：缓存保持原样（原子写，无半写状态）；署名真值已落盘，
      // 改名成立，下次打开以真值回写缓存。缓存没变则 [onRenamed] 不回调
      // （读它做名字来源的消费方此刻读到的还是旧名），下次写入或打开回写
      // 缓存后自然跟上。
      return true;
    }
    await onRenamed?.call();
    return true;
  }

  /// 写定封面位置：公开标记文件 `meta` 段的 `coverPositionMs`，经按视频文档
  /// 存取的原子读改写执行——与改名同族，不新增写入者、不新增段；同文档
  /// 其它字段与未知扩展键原样保留。
  ///
  /// [positionMs] 为 null = 清除该字段、恢复「跟随首线」。返回写后**生效**
  /// 的封面位置（毫秒）：写入时即写入值，清除时即缺省语义求出的首线位置
  /// （[coverPositionOf]，无有效区间为第 0 帧）——调用侧据此重新
  /// 生成封面，不必再读一次读面。返回 null = 写失败，文件按原子写保持原样
  /// （零副作用）。
  Future<int?> setCoverPosition({
    required String videoId,
    required int? positionMs,
  }) async {
    final coordinator = VideoDocumentCoordinator(storageFor(videoId));
    try {
      final outcome = await coordinator.readMarkersOutcome();
      if (outcome is! WritableDocumentReadOutcome<MarkersDocument>) return null;
      final result = await outcome.write(
        (context) => context.document.withCoverPosition(positionMs),
      );
      if (result is DocumentWriteRejected<MarkersDocument>) return null;
      return coverPositionOf(result.document).inMilliseconds;
    } on Object {
      return null;
    }
  }

  /// 逐段改档 / 一键完全掌握 / 撤销：把 [values] 各段的熟练度写进本地私密
  /// 文件 `session.mastery`，经按视频文档存取的原子读改写执行——同文档其它
  /// 段、`session`/`prefs` 其它字段与未知扩展键原样保留。
  ///
  /// 写出时按稀疏不变式归一：[DanceMasteryValues.mastery] 缺项即「未练」，
  /// 该段序键从 Map 移除（显式「未练」不入 Map），未列入段序表的段不动。
  /// 返回 true = 已落盘；写失败 → 文件按原子写保持原样、返回 false
  /// （零副作用）。
  Future<bool> setSegmentsMastery({
    required String videoId,
    required DanceMasteryValues values,
  }) async {
    final coordinator = VideoDocumentCoordinator(storageFor(videoId));
    try {
      final outcome = await coordinator.readLocalOutcome();
      if (outcome is! WritableDocumentReadOutcome<LocalDocument>) return false;
      final result = await outcome.write((context) {
        final next = Map<int, LearningMastery>.of(context.document.mastery);
        for (final order in values.orders) {
          final mastery = values.mastery[order] ?? LearningMastery.unlearned;
          if (mastery == LearningMastery.unlearned) {
            next.remove(order);
          } else {
            next[order] = mastery;
          }
        }
        return context.document.withMasteryMap(next);
      });
      if (result is DocumentWriteRejected<LocalDocument>) return false;
    } on Object {
      return false;
    }
    return true;
  }
}
