import 'dart:io';

import 'package:dance_learning_app/persistence/index_file_provider.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';

/// 按视频文档单一基目录：生产代码里
/// `markers_<hash>.json` / `local_<hash>.json` 只剩一处路径来源——应用
/// 文档目录（与 `index.json` 同级）。恢复装载读方与偏好写方对同一
/// videoId 指向同一实例（同一条写链），落盘文件就在索引同级目录。
void main() {
  const videoId = 'hash-abc123';

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('single_base_dir');
    container = ProviderContainer(
      overrides: [
        importIndexFileProvider.overrideWithValue(
          Future.value(File(p.join(tempDir.path, 'index.json'))),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await tempDir.delete(recursive: true);
  });

  test('偏好写入落在应用文档目录（与 index.json 同级），恢复装载读方读到同一份', () async {
    await container
        .read(videoDocumentCoordinatorProvider(videoId))
        .patchLocal((doc) => doc.withLayoutLocked(true));

    final localFile = File(p.join(tempDir.path, 'local_$videoId.json'));
    expect(localFile.existsSync(), isTrue);

    final viaFactory = container.read(videoDocumentStorageFactoryProvider)(
      videoId,
    );
    final json = await viaFactory.loadLocal();
    expect(json['prefs']['layoutLocked'], true);
  });

  test('文档目录无文件按空态读取（旧支持目录同名文件不做迁移、整体丢弃）', () async {
    final viaFactory = container.read(videoDocumentStorageFactoryProvider)(
      videoId,
    );
    final doc = await container
        .read(videoDocumentCoordinatorProvider(videoId))
        .readLocal();
    expect(doc.layoutLocked, isFalse);
    expect(await viaFactory.loadLocal(), isEmpty);
  });
}
