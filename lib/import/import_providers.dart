import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_importer.dart';
import '../persistence/index_file_provider.dart';
import '../persistence/video_index.dart';
import 'video_picker.dart';
import '../core/video_identity.dart';

/// 应用私有导入目录：文档目录下的 `videos/`（生产实现）。
///
/// 测试用 `overrideWith` 覆盖为临时目录，见
/// `test/import/import_flow_test.dart`。
final importVideosDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(base.path, 'videos'));
  await directory.create(recursive: true);
  return directory;
});

/// 系统文件选择器（测试注入 fake）。
final videoPickerProvider = Provider<VideoPicker>((ref) => SystemVideoPicker());

/// 视频索引读写（index.json）。
///
/// 以接口类型暴露：player 域镜像询问/历史应用与导入管道共用；
/// 测试用内存实现覆盖（`overrideWithValue`），避免真实文件 IO 在
/// fake async 时钟下不可完成（见 `test/helpers/in_memory_video_index_storage.dart`）。
final videoIndexStoreProvider = Provider<VideoIndexStorage>((ref) {
  return VideoIndexStore(ref.watch(importIndexFileProvider));
});

/// 内容哈希计算：生产为后台 isolate 的 xxHash64；测试注入
/// 固定值/门控桩（`test/helpers/gated_hasher.dart` 先例）。
final contentHasherProvider = Provider<ContentHasher>(
  (ref) => const XxHash64ContentHasher(),
);

/// 导入管道（选择 → 复制 → 清缓存 → 后台哈希 + 视频索引）。
final videoImporterProvider = Provider<VideoImporter>((ref) {
  return VideoImporter(
    ref.watch(videoPickerProvider),
    () => ref.read(importVideosDirectoryProvider.future),
    indexStore: ref.watch(videoIndexStoreProvider),
    hasher: ref.watch(contentHasherProvider),
  );
});
