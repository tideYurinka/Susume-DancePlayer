import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'index_file_provider.dart' show importIndexFileProvider;
import 'video_document_store.dart';

/// 按视频文档文件工厂（收成单一基目录）：
/// 给定 videoId（内容哈希）产出该视频 `markers_<hash>.json` /
/// `local_<hash>.json` 的 [VideoDocumentStorage]。
///
/// 文件与 `index.json` 同级放在应用文档目录（位置自
/// `importIndexFileProvider` 派生，测试覆盖该 provider 即同时覆盖本工厂，
/// 无需触达 path_provider）；测试也可用 `overrideWithValue` 直接覆盖工厂
/// 为内存 fake 协调器工厂（见 `test/player/open_restore_test.dart`）。
///
/// 这是生产代码里唯一的按视频文档路径来源：恢复装载、保存编排、镜像与
/// 署名写、编辑偏好写四个消费方全部经本工厂取存储。工厂按 videoId 记忆
/// 已建实例，保证「一文件一实例、单条串行写链」跨消费方成立。
final videoDocumentStorageFactoryProvider =
    Provider<VideoDocumentStorage Function(String videoId)>((ref) {
  final indexFile = ref.watch(importIndexFileProvider);
  final instances = <String, VideoDocumentStorage>{};
  Future<File> documentFile(String name) async =>
      File(p.join((await indexFile).parent.path, name));
  return (videoId) => instances.putIfAbsent(
        videoId,
        () => AtomicVideoDocumentStorage(
          markersFile: documentFile('markers_$videoId.json'),
          localFile: documentFile('local_$videoId.json'),
        ),
      );
});

/// 按视频双文件存取注入点（family 参数 = videoId，内容哈希）：
/// 统一委托 [videoDocumentStorageFactoryProvider]，不另建路径构造。
final videoDocumentStorageProvider =
    Provider.family<VideoDocumentStorage, String>((ref, videoId) {
  return ref.watch(videoDocumentStorageFactoryProvider)(videoId);
});

/// 按视频文档协调器注入点（family 参数 = videoId）：全部 markers/local
/// 写入统一经此收敛，不另建写链。
final videoDocumentCoordinatorProvider =
    Provider.family<VideoDocumentCoordinator, String>((ref, videoId) {
  return VideoDocumentCoordinator(
    ref.watch(videoDocumentStorageProvider(videoId)),
  );
});
