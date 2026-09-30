import 'dart:io';

import 'package:dance_learning_app/core/cover_frame.dart'
    show kCoverPlaceholderAspectRatio;
import 'package:dance_learning_app/dance/cover_cache.dart';

/// 内存版封面缓存（widget 测试用）。
///
/// 与 `InMemoryVideoDocumentStorage` 同一先例：真实文件 IO 在 flutter_test
/// 的 fake async 时钟下不可完成，读面（卡片是否已有封面）因此需要内存
/// 替身。就绪状态、生成位置、封面比例、写入内容与删除都在内存里维护；
/// `fileFor` 只回答路径、不触磁盘。
class InMemoryCoverCache implements CoverCache {
  InMemoryCoverCache({
    Set<String> ready = const {},
    Map<String, double> aspectRatios = const {},
    Map<String, Duration> positions = const {},
  }) : _aspectRatios = {...aspectRatios},
       _positions = {...positions},
       _ready = {...ready};

  final Set<String> _ready;

  /// 各舞封面的生成位置（就绪时用于比对当前封面位置）。
  final Map<String, Duration> _positions;

  /// 各舞封面的宽高比；未指定按竖屏 3:4（与占位同款）。
  final Map<String, double> _aspectRatios;

  /// 当前被视作「已就绪」的舞。
  Set<String> get ready => Set.unmodifiable(_ready);

  @override
  Future<File> fileFor(String videoId) async =>
      File('/in-memory/cover_$videoId.jpg');

  @override
  Future<({File file, double aspectRatio})?> readyCover(
    String videoId,
    Duration position,
  ) async {
    if (!_ready.contains(videoId) || _positions[videoId] != position) {
      return null;
    }
    return (
      file: await fileFor(videoId),
      aspectRatio: _aspectRatios[videoId] ?? kCoverPlaceholderAspectRatio,
    );
  }

  @override
  Future<Map<String, double>> readyCovers(
    Map<String, Duration> positions,
  ) async => {
    for (final entry in positions.entries)
      if (_ready.contains(entry.key) && _positions[entry.key] == entry.value)
        entry.key: _aspectRatios[entry.key] ?? kCoverPlaceholderAspectRatio,
  };

  @override
  Future<File> tempFileFor(String videoId) async =>
      File('/in-memory/cover_$videoId.jpg.tmp');

  @override
  Future<bool> writeFrom(
    String videoId,
    File tempFile,
    Duration position,
  ) async {
    _ready.add(videoId);
    _positions[videoId] = position;
    return true;
  }

  @override
  Future<void> deleteFor(String videoId) async {
    _ready.remove(videoId);
    _positions.remove(videoId);
  }
}
