import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/video_identity.dart';
import 'picked_video.dart';
import '../persistence/video_index.dart';
import 'video_picker.dart';

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

/// 建舞分支的返回值：导入副本 + 内容哈希（新舞身份）。
class ImportedDance {
  const ImportedDance({required this.video, required this.videoId});

  final ImportedVideo video;
  final String videoId;
}

/// 导入管道：选择 → 复制到应用私有目录 → 清理选择器缓存；
/// 后台计算 xxHash64 视频标识并读写视频索引（index.json）。
///
/// 打开视频（[open]）时先用「大小 + 文件名」快速键先行匹配索引：
/// 命中立即播放既有私有副本（不等待哈希），后台校验哈希一致则刷新
/// 最近打开时间，不一致（同名同大小不同内容）按新视频导入、旧条目
/// 保留；未命中走首次导入路径（复制后立即返回，哈希后台计算）。
class VideoImporter {
  VideoImporter(
    this._picker,
    this._resolveDestination, {
    required this.indexStore,
    required this.hasher,
    this.now = DateTime.now,
  });

  final VideoPicker _picker;
  final Future<Directory> Function() _resolveDestination;

  /// 视频索引读写（index.json；接口形态供测试注入内存实现）。
  final VideoIndexStorage indexStore;

  /// 内容哈希计算（测试可注入门控/桩实现）。
  final ContentHasher hasher;

  /// 时钟（测试注入固定时间，保证最近打开时间可断言）。
  final DateTime Function() now;

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
  /// 返回后即可进入播放：首次导入复制完成即返回（哈希后台计算），
  /// 快速键命中直接返回既有私有副本（哈希校验后台进行）。
  Future<ImportedVideo> open(PickedVideo picked) async {
    final source = _sourceFileOf(picked);
    final sizeBytes = picked.sizeBytes ?? await source.length();
    final key = fastKeyFor(name: picked.name, sizeBytes: sizeBytes);

    // 快速键先行匹配：命中立即播放既有私有副本，后台校验对账。
    final index = await indexStore.load();
    final candidates = index.byFastKey(key);
    if (candidates.isNotEmpty) {
      final entry = candidates.first;
      unawaited(_reconcileInBackground(picked, key));
      return ImportedVideo(
        name: entry.displayName,
        uri: File(entry.filePath).uri,
        sizeBytes: entry.sizeBytes,
      );
    }

    // 首次导入：复制到私有目录并清理选择器缓存 → 立即返回，
    // 后台计算 xxHash64 并写入索引（不阻塞进入播放）。
    final imported = await copyToPrivateDir(picked);
    unawaited(_hashAndIndex(imported));
    return imported.copyWith(isNewImport: true);
  }

  /// 建舞分支：从分享包建一支新舞——既有管道的
  /// 复制进私有目录、算内容哈希、建索引三步全真，只是哈希同步等待：
  /// 导入编排要拿内容哈希挂组员方案，不能等后台收尾。返回导入副本与
  /// 内容哈希（新舞的身份）。
  Future<ImportedDance> importDanceFile(PickedVideo picked) async {
    final imported = await copyToPrivateDir(picked);
    final videoId = await hasher.hashFile(File(imported.uri.toFilePath()));
    await indexStore.update((index) => index.upsert(_entryFor(imported, videoId)));
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

  /// 首次导入的后台收尾：哈希私有副本并写入索引（新增/合并条目）。
  Future<void> _hashAndIndex(ImportedVideo imported) async {
    try {
      final videoId = await hasher.hashFile(File(imported.uri.toFilePath()));
      await indexStore.update(
        (index) => index.upsert(_entryFor(imported, videoId)),
      );
    } on Object catch (error) {
      // 后台收尾失败不影响已开始的播放；索引保持原状，下次打开重算。
      debugPrint('视频索引后台写入失败：$error');
    }
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

  /// 导入源必须物化成本地文件。
  ///
  /// 非 `file://` 源无可复制的文件：file_picker 会先把所选文件物化到缓存，
  /// 正常应为 file://。
  File _sourceFileOf(PickedVideo picked) {
    if (picked.sourceUri.scheme != 'file') {
      throw StateError(
        '暂不支持非本地文件的导入源（${picked.sourceUri.scheme}）；'
        'file_picker 会先把所选文件物化到缓存，正常应为 file://。',
      );
    }
    return File(picked.sourceUri.toFilePath());
  }

  /// 由已导入的视频与内容哈希构造索引条目。
  VideoIndexEntry _entryFor(ImportedVideo imported, String videoId) {
    return VideoIndexEntry(
      videoId: videoId,
      displayName: imported.name,
      filePath: imported.uri.toFilePath(),
      sizeBytes: imported.sizeBytes,
      fastKey: fastKeyFor(name: imported.name, sizeBytes: imported.sizeBytes),
      mirrored: false,
      lastOpenedAt: now(),
    );
  }

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
