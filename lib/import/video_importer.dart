import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/video_identity.dart';
import 'local_video_source.dart';
import 'picked_video.dart';
import '../persistence/video_index.dart';
import '../dance/video_copy_presence.dart';
import 'video_picker.dart';
import 'video_recovery.dart';

/// 已复制到应用私有目录、可直接播放的视频。
class ImportedVideo {
  const ImportedVideo({
    required this.name,
    required this.uri,
    required this.sizeBytes,
    this.isNewImport = false,
  });

  /// 显示名（含扩展名）。
  final String name;

  /// 私有目录内目标文件的 `file://` URI（播放器打开用）。
  final Uri uri;

  /// 目标文件大小（字节）。
  final int sizeBytes;

  /// 是否首次导入的新视频：进入播放器前弹命名框的依据——
  /// 既有条目（快速键命中/再次打开）与升级前的遗留旧视频不弹框。
  final bool isNewImport;

  /// 复制并覆盖个别字段（导入管道首建路径标记 [isNewImport] 用）。
  ImportedVideo copyWith({bool? isNewImport}) {
    return ImportedVideo(
      name: name,
      uri: uri,
      sizeBytes: sizeBytes,
      isNewImport: isNewImport ?? this.isNewImport,
    );
  }
}

/// 建舞分支的返回值：导入副本 + 视频标识（新舞身份）。
class ImportedDance {
  const ImportedDance({required this.video, required this.videoId});

  final ImportedVideo video;
  final String videoId;
}

/// 导入管道：选择 → 复制到应用私有目录 → 同步算 xxHash64 视频标识
/// （复制后的副本读一遍）→ 写视频索引（index.json）→ 清理选择器缓存。
///
/// 打开视频（[open]）时先用「大小 + 文件名」快速键先行匹配索引：
/// 命中且副本在场立即播放既有私有副本（不等待哈希），后台校验哈希一致则
/// 刷新最近打开时间，不一致（同名同大小不同内容）按新视频导入、旧条目
/// 保留；命中而副本不在（**副本丢失**）走**找回**——标识相符即把副本放回
/// 条目记录的原路径（帮助文档那句「重新导入同一支视频即可接回」由此成立），
/// 不符仍按新视频导入；未命中走首次导入路径——复制后同步算副本摘要并落
/// 条目，因此返回时条目已在清单里，随后任何一次打开都不再等后台哈希落盘。
class VideoImporter {
  VideoImporter(
    this._picker,
    this._resolveDestination, {
    required this.indexStore,
    required this.hasher,
    this.now = DateTime.now,
    this.copyPresence = const FileVideoCopyPresence(),
    this.recovery,
  });

  final VideoPicker _picker;
  final Future<Directory> Function() _resolveDestination;

  /// 视频索引读写（index.json；接口形态供测试注入内存实现）。
  final VideoIndexStorage indexStore;

  /// 视频标识计算（测试可注入门控/桩实现）。
  final ContentHasher hasher;

  /// 时钟（测试注入固定时间，保证最近打开时间可断言）。
  final DateTime Function() now;

  /// 副本存在性判定注入点（**副本丢失**事实的唯一来源）：快速键命中后
  /// 先问它副本在不在，再决定是直接用既有副本还是走找回。
  final VideoCopyPresence copyPresence;

  /// 找回动作（快速键命中而副本不在时走它）；null = 按本管道同一套件装配。
  /// 生产装配传入 [videoRecoveryProvider] 的同一实例，与找回面上的那条
  /// 找回是同一条动作。
  final VideoRecovery? recovery;

  late final VideoRecovery _recoveryAction =
      recovery ??
      VideoRecovery(_picker, indexStore: indexStore, hasher: hasher);

  /// 完整导入：选择视频 → 打开（快速键匹配或首次导入）。
  ///
  /// 用户取消（选择器返回 null）时返回 null，不做任何文件操作。
  Future<ImportedVideo?> import() async {
    final picked = await _picker.pickVideo();
    if (picked == null) return null;
    return open(picked);
  }

  /// 打开已选中的视频（快速键先行匹配）。
  ///
  /// 首次导入：复制 → **同步**算一遍副本摘要 → 落条目，返回时索引里
  /// 已有该条目（打开不再等后台哈希落盘；摘要仍在后台 isolate 计算，
  /// 只是这里等它算完）。快速键命中直接返回既有私有副本，
  /// 内容校验仍在后台对账；命中而副本不在则走找回（[VideoRecovery]）。
  Future<ImportedVideo> open(PickedVideo picked) async {
    final source = _sourceFileOf(picked);
    final sizeBytes = picked.sizeBytes ?? await source.length();
    final key = fastKeyFor(name: picked.name, sizeBytes: sizeBytes);

    // 快速键先行匹配：命中立即播放既有私有副本，后台校验对账。
    final index = await indexStore.load();
    final candidates = index.byFastKey(key);
    if (candidates.isNotEmpty) {
      final entry = candidates.first;
      // 命中而副本不在：今天那条路只刷新显示信息、路径仍指着不存在的
      // 文件；改走找回——标识相符即把副本放回条目记录的原路径。
      if (!copyPresence.exists(entry.filePath)) {
        return _openWithMissingCopy(entry, picked);
      }
      unawaited(_reconcileInBackground(picked, key));
      return ImportedVideo(
        name: entry.displayName,
        uri: File(entry.filePath).uri,
        sizeBytes: entry.sizeBytes,
      );
    }

    // 首次导入：复制到私有目录 → 同步算副本摘要 → 写条目再返回，
    // 返回即索引已落盘（不再有后台收尾那一段看不见的尾巴）。
    final dance = await _copyHashAndIndex(picked);
    return dance.video.copyWith(isNewImport: true);
  }

  /// 快速键命中而副本不在：走找回（与找回面同一条动作）。
  ///
  /// - 标识相符（重新导入的正是这支）：副本放回条目记录的原路径，打开的是
  ///   接回来的那支舞——既有条目，不弹命名框；
  /// - 标识不符（同名同大小不同内容）：按新视频导入、旧条目保留（与副本在
  ///   场时的对账口径同一条）；
  /// - 出错：如实向上抛（界面出声），条目的身份与路径不变。
  Future<ImportedVideo> _openWithMissingCopy(
    VideoIndexEntry entry,
    PickedVideo picked,
  ) async {
    final outcome = await _recoveryAction.restoreFrom(entry, picked);
    return switch (outcome) {
      VideoCopyRestored(entry: final restored) => ImportedVideo(
        name: restored.displayName,
        uri: File(restored.filePath).uri,
        sizeBytes: restored.sizeBytes,
      ),
      VideoIsNotThisDance(:final picked, :final videoId) =>
        (await _copyHashAndIndex(
          picked,
          knownVideoId: videoId,
        )).video.copyWith(isNewImport: true),
      VideoRecoveryFailed(:final error, :final stackTrace) =>
        Error.throwWithStackTrace(error, stackTrace),
      VideoRecoveryCancelled() => throw StateError('找回不会取消：这里已经拿着用户选中的文件'),
    };
  }

  /// 建舞分支：另建一支新舞——与首次导入同一条「复制进私有目录 → 算副本
  /// 摘要 → 落条目」路径，返回导入副本与视频标识（新舞的身份）；导入编排
  /// 要拿标识挂组员方案，因此摘要是同步等的。
  ///
  /// [knownVideoId] = 调用方已经算出的这支视频的**视频标识**（找回路径上
  /// 「不是这支」的结局就是它）：传入时不再读副本，总读取次数因此不增加；
  /// 缺省为 null = 没有已知标识，按副本算（既有调用点行为不变）。
  Future<ImportedDance> importDanceFile(
    PickedVideo picked, {
    String? knownVideoId,
  }) => _copyHashAndIndex(picked, knownVideoId: knownVideoId);

  /// 首次导入与建舞分支共用的落盘路径：复制 → 同步算副本摘要 → 落条目。
  ///
  /// 摘要读的是复制后的副本（源文件在清缓存后可能已不在）；
  /// [knownVideoId] 传入时不再读副本——身份在核对源文件时已经算出
  /// （找回路径上「同名同大小不同内容」那一条），总读取次数因此不增加。
  /// 任一步失败都向上抛，由调用方处置——不做静默兜底。
  Future<ImportedDance> _copyHashAndIndex(
    PickedVideo picked, {
    String? knownVideoId,
  }) async {
    final imported = await copyToPrivateDir(picked);
    final videoId =
        knownVideoId ?? await hasher.hashFile(File(imported.uri.toFilePath()));
    await indexStore.update(
      (index) => index.upsert(_entryFor(imported, videoId)),
    );
    return ImportedDance(video: imported, videoId: videoId);
  }

  /// 把 [picked] 复制到应用私有目录并清理选择器缓存。
  Future<ImportedVideo> copyToPrivateDir(PickedVideo picked) async {
    final source = _sourceFileOf(picked);
    final destination = await _resolveDestination();
    await destination.create(recursive: true);
    final target = await _uniqueTarget(destination, picked.name);

    await source.copy(target.path);
    // 复制完成后清理选择器缓存（Android SAF 的临时副本）。
    await _picker.clearCache();

    return ImportedVideo(
      name: picked.name,
      uri: target.uri,
      sizeBytes: await target.length(),
    );
  }

  /// 快速键命中后的后台校验与索引对账：
  ///
  /// 哈希一致 → 刷新该条目的显示信息与最近打开时间（不新增条目）；
  /// 不一致（同名同大小不同内容）→ 按新视频导入（复制 + 去冲突命名）、
  /// 旧条目保留。两者都保留既有条目的镜像状态（镜像按 video_id 存取）。
  Future<void> _reconcileInBackground(
    PickedVideo picked,
    String fastKey,
  ) async {
    try {
      final source = _sourceFileOf(picked);
      final videoId = await hasher.hashFile(source);

      // 判定与动作分两步：命中只做链内轻量 refresh；未命中先在事务外完成
      // 秒级复制，再以幂等 upsert 落索引——复制不再冻结索引写链。判定与
      // 落盘之间若该条目被并发写入，upsert 的同 id 合并兜底（不产生重复）。
      if ((await indexStore.load()).findById(videoId) != null) {
        await indexStore.update(
          (index) => index.refresh(
            videoId,
            displayName: picked.name,
            fastKey: fastKey,
            lastOpenedAt: now(),
          ),
        );
      } else {
        final imported = await copyToPrivateDir(picked);
        await indexStore.update(
          (index) => index.upsert(_entryFor(imported, videoId)),
        );
      }
      // 源缓存清理兜底：快速键命中且内容一致时由这里清理（不一致分支的
      // 复制内部已清理）。不能提前清理——真实 clearCache 会删掉选择器缓存
      // 里的源文件，而复制分支还需要它。
      await _picker.clearCache();
    } on Object catch (error) {
      // 后台校验失败不影响已开始的播放。
      debugPrint('视频标识后台校验失败：$error');
    }
  }

  /// 导入源必须物化成本地文件（判据与文案见 [localSourceFileOf]）。
  File _sourceFileOf(PickedVideo picked) =>
      localSourceFileOf(picked, what: '导入源');

  /// 由已导入的视频与它的视频标识构造索引条目（字段清单见
  /// [VideoIndexEntry.forVideoCopy]）。
  VideoIndexEntry _entryFor(ImportedVideo imported, String videoId) =>
      VideoIndexEntry.forVideoCopy(
        videoId: videoId,
        displayName: imported.name,
        filePath: imported.uri.toFilePath(),
        sizeBytes: imported.sizeBytes,
        lastOpenedAt: now(),
      );

  /// 目标文件名去冲突：同名时在扩展名前插入 ` (n)` 序号，不覆盖旧文件。
  Future<File> _uniqueTarget(Directory directory, String name) async {
    final base = p.basename(name);
    final extension = p.extension(base);
    final stem = extension.isEmpty
        ? base
        : base.substring(0, base.length - extension.length);

    var candidate = File(p.join(directory.path, base));
    var sequence = 1;
    while (await candidate.exists()) {
      candidate = File(p.join(directory.path, '$stem ($sequence)$extension'));
      sequence++;
    }
    return candidate;
  }
}
