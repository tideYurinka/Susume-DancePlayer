import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/import/video_importer.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/import/video_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_video_picker.dart';
import '../helpers/gated_hasher.dart';

/// 模拟真实选择器缓存语义的假选择器：clearCache 会删除已选源文件
/// （file_picker 的临时缓存物化副本）。用于回归「按新视频导入」分支
/// 必须在复制完成后才清缓存，否则源文件被删、复制失败。
class DeletingVideoPicker implements VideoPicker {
  DeletingVideoPicker(this.picked);

  final PickedVideo picked;

  int clearCacheCalls = 0;

  @override
  Future<PickedVideo?> pickVideo() async => picked;

  @override
  Future<void> clearCache() async {
    clearCacheCalls++;
    final file = File(picked.sourceUri.toFilePath());
    if (await file.exists()) {
      await file.delete();
    }
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('importer_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  VideoImporter importer({
    required VideoPicker picker,
    Directory? destination,
    VideoIndexStore? indexStore,
    ContentHasher? hasher,
    DateTime Function()? now,
  }) {
    return VideoImporter(
      picker,
      () async => destination ?? Directory(p.join(tempDir.path, 'videos')),
      indexStore:
          indexStore ??
          VideoIndexStore(File(p.join(tempDir.path, 'index.json'))),
      hasher: hasher ?? const XxHash64ContentHasher(),
      now: now ?? () => DateTime(2026, 9, 1, 12),
    );
  }

  Future<File> writeSource(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  /// 轮询索引直到满足 [done]，用于等待后台哈希/索引任务落盘。
  Future<VideoIndex> waitForIndex(
    VideoIndexStore store,
    bool Function(VideoIndex index) done, {
    int tries = 200,
  }) async {
    for (var i = 0; i < tries; i++) {
      final index = await store.load();
      if (done(index)) return index;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return store.load();
  }

  group('copyToPrivateDir（复制到私有目录）', () {
    test('复制字节到目标目录、返回目标信息、并清理选择器缓存', () async {
      final src = await writeSource('dance.mp4', [1, 2, 3, 4, 5]);
      final picker = FakeVideoPicker(null);

      final imported = await importer(picker: picker).copyToPrivateDir(
        PickedVideo(name: 'dance.mp4', sourceUri: src.uri, sizeBytes: 5),
      );

      expect(imported.name, 'dance.mp4');
      expect(imported.sizeBytes, 5);
      expect(imported.uri.scheme, 'file');
      final target = File(imported.uri.toFilePath());
      expect(target.existsSync(), isTrue);
      expect(await target.readAsBytes(), [1, 2, 3, 4, 5]);
      expect(picker.clearCacheCalled, isTrue);
    });

    test('目标目录不存在时自动创建', () async {
      final src = await writeSource('a.mp4', [9]);
      final destination = Directory(p.join(tempDir.path, 'nested', 'videos'));

      final imported = await importer(
        picker: FakeVideoPicker(null),
        destination: destination,
      ).copyToPrivateDir(PickedVideo(name: 'a.mp4', sourceUri: src.uri));

      expect(File(imported.uri.toFilePath()).existsSync(), isTrue);
    });

    test('同名文件冲突时生成带序号的新文件名，不覆盖旧文件', () async {
      final src = await writeSource('a.mp4', [1]);
      final picker = FakeVideoPicker(null);
      final im = importer(picker: picker);

      final first = await im.copyToPrivateDir(
        PickedVideo(name: 'a.mp4', sourceUri: src.uri),
      );
      final second = await im.copyToPrivateDir(
        PickedVideo(name: 'a.mp4', sourceUri: src.uri),
      );

      expect(second.uri.toFilePath(), isNot(first.uri.toFilePath()));
      expect(p.basename(second.uri.toFilePath()), 'a (1).mp4');
      expect(
        await File(first.uri.toFilePath()).readAsBytes(),
        await File(second.uri.toFilePath()).readAsBytes(),
      );
    });

    test('非 file:// 源抛出明确错误', () async {
      final picker = FakeVideoPicker(null);
      final im = importer(picker: picker);

      expect(
        () => im.copyToPrivateDir(
          PickedVideo(
            name: 'a.mp4',
            sourceUri: Uri.parse('content://media/external/video/a.mp4'),
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('import（选择 → 复制 → 清理缓存）', () {
    test('用户取消（选择器返回 null）返回 null 且不清理缓存', () async {
      final picker = FakeVideoPicker(null);

      final result = await importer(picker: picker).import();

      expect(result, isNull);
      expect(picker.pickCalls, 1);
      expect(picker.clearCacheCalled, isFalse);
    });

    test('选择视频后复制到私有目录、清理缓存、返回导入结果', () async {
      final src = await writeSource('b.mp4', [7, 8]);
      final picker = FakeVideoPicker(
        PickedVideo(name: 'b.mp4', sourceUri: src.uri, sizeBytes: 2),
      );

      final imported = await importer(picker: picker).import();

      expect(imported, isNotNull);
      expect(imported!.name, 'b.mp4');
      expect(File(imported.uri.toFilePath()).existsSync(), isTrue);
      expect(await File(imported.uri.toFilePath()).readAsBytes(), [7, 8]);
      expect(picker.clearCacheCalled, isTrue);
    });
  });

  group('open / 视频标识与索引', () {
    test('导入立即返回（不等待 xxHash64），索引随后后台写入且字段完整', () async {
      final src = await writeSource('dance.mp4', [1, 2, 3, 4, 5]);
      final gate = Completer<String>();
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));
      final picker = FakeVideoPicker(
        PickedVideo(name: 'dance.mp4', sourceUri: src.uri, sizeBytes: 5),
      );
      final im = importer(
        picker: picker,
        indexStore: s,
        hasher: GatedHasher(gate),
      );

      final imported = await im.import();

      expect(imported, isNotNull);
      expect(imported!.name, 'dance.mp4');
      expect(File(imported.uri.toFilePath()).existsSync(), isTrue);
      expect(gate.isCompleted, isFalse, reason: '导入返回时 xxHash64 不应已完成（后台计算）');
      expect(picker.clearCacheCalled, isTrue, reason: '复制完成即清理选择器缓存，不等待哈希');

      gate.complete('stubbed-hash');
      final index = await waitForIndex(s, (i) => i.entries.isNotEmpty);
      final e = index.entries.single;
      expect(e.videoId, 'stubbed-hash');
      expect(e.displayName, 'dance.mp4');
      expect(e.filePath, imported.uri.toFilePath());
      expect(e.sizeBytes, 5);
      expect(e.fastKey, '5:dance.mp4');
      expect(e.mirrored, isFalse);
      expect(e.lastOpenedAt, DateTime(2026, 9, 1, 12));
    });

    test('再次打开同一视频：快速键命中立即返回既有副本，后台校验一致仅刷新时间', () async {
      final src = await writeSource('dance.mp4', [1, 2, 3]);
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));

      // 首次导入（真实哈希）→ 等索引落盘。
      final firstIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'dance.mp4', sourceUri: src.uri, sizeBytes: 3),
        ),
        indexStore: s,
      );
      await firstIm.import();
      final afterFirst = await waitForIndex(s, (i) => i.entries.isNotEmpty);
      final firstEntry = afterFirst.entries.single;

      // 再次打开同一文件：快速键命中，门控哈希证明不等待校验。
      final gate = Completer<String>();
      final secondIm = importer(
        picker: FakeVideoPicker(null),
        indexStore: s,
        hasher: GatedHasher(gate),
        now: () => DateTime(2026, 9, 2, 12),
      );
      final second = await secondIm.open(
        PickedVideo(name: 'dance.mp4', sourceUri: src.uri, sizeBytes: 3),
      );

      expect(
        second.uri.toFilePath(),
        firstEntry.filePath,
        reason: '快速键命中：立即播放既有私有副本，不重新复制',
      );
      expect(gate.isCompleted, isFalse, reason: '快速键命中不等待哈希校验');

      gate.complete(firstEntry.videoId);
      final afterVerify = await waitForIndex(
        s,
        (i) => i.entries.single.lastOpenedAt == DateTime(2026, 9, 2, 12),
      );
      expect(afterVerify.entries.length, 1, reason: '哈希一致：不新增条目');
      expect(afterVerify.entries.single.videoId, firstEntry.videoId);
    });

    test('同名同大小不同内容：按新视频导入、旧条目保留（去冲突命名）', () async {
      final src1 = await writeSource('dance.mp4', [1, 2, 3]);
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));

      final firstIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'dance.mp4', sourceUri: src1.uri, sizeBytes: 3),
        ),
        indexStore: s,
      );
      await firstIm.import();
      final afterFirst = await waitForIndex(s, (i) => i.entries.isNotEmpty);
      final oldEntry = afterFirst.entries.single;

      // 同名同大小（3 字节）但内容不同：快速键命中 → 先播放旧副本，
      // 后台哈希不一致 → 按新视频导入。
      final src2 = await writeSource('dance_new.mp4', [9, 9, 9]);
      final secondIm = importer(
        picker: FakeVideoPicker(null),
        indexStore: s,
        now: () => DateTime(2026, 9, 3, 12),
      );
      final second = await secondIm.open(
        PickedVideo(name: 'dance.mp4', sourceUri: src2.uri, sizeBytes: 3),
      );
      expect(
        second.uri.toFilePath(),
        oldEntry.filePath,
        reason: '快速键命中：本会话先播放既有副本',
      );

      final index = await waitForIndex(s, (i) => i.entries.length == 2);
      final byVideoId = {for (final e in index.entries) e.videoId: e};

      expect(byVideoId[oldEntry.videoId], isNotNull, reason: '旧条目保留');
      final expectedNewHash = await const XxHash64ContentHasher().hashFile(
        src2,
      );
      final newEntry = byVideoId[expectedNewHash];
      expect(newEntry, isNotNull, reason: '新内容按新视频导入');
      expect(newEntry!.displayName, 'dance.mp4');
      expect(
        p.basename(newEntry.filePath),
        'dance (1).mp4',
        reason: '私有目录同名去冲突命名',
      );
      expect(newEntry.sizeBytes, 3);
      expect(newEntry.lastOpenedAt, DateTime(2026, 9, 3, 12));
    });

    test('同名同大小不同内容 + 真实缓存语义：清缓存不删待复制源文件，新视频仍导入', () async {
      final src1 = await writeSource('dance.mp4', [1, 2, 3]);
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));
      final firstIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'dance.mp4', sourceUri: src1.uri, sizeBytes: 3),
        ),
        indexStore: s,
      );
      await firstIm.import();
      final afterFirst = await waitForIndex(s, (i) => i.entries.isNotEmpty);
      final oldEntry = afterFirst.entries.single;

      // 真实选择器的 clearCache 会删除缓存里的源文件；「按新视频导入」
      // 分支必须先复制后清缓存，否则源文件被删、复制失败。
      final src2 = await writeSource('dance_new.mp4', [9, 9, 9]);
      final picker = DeletingVideoPicker(
        PickedVideo(name: 'dance.mp4', sourceUri: src2.uri, sizeBytes: 3),
      );
      final secondIm = importer(
        picker: picker,
        indexStore: s,
        now: () => DateTime(2026, 9, 5, 12),
      );
      final second = await secondIm.open(
        PickedVideo(name: 'dance.mp4', sourceUri: src2.uri, sizeBytes: 3),
      );
      expect(second.uri.toFilePath(), oldEntry.filePath);

      final index = await waitForIndex(s, (i) => i.entries.length == 2);
      expect(index.findById(oldEntry.videoId), isNotNull, reason: '旧条目保留');
      expect(picker.clearCacheCalls, greaterThanOrEqualTo(1));
      final newEntry = index.entries.firstWhere(
        (e) => e.videoId != oldEntry.videoId,
      );
      expect(
        p.basename(newEntry.filePath),
        'dance (1).mp4',
        reason: '复制成功（清缓存发生在复制之后）并去冲突命名',
      );
      expect(newEntry.lastOpenedAt, DateTime(2026, 9, 5, 12));
    });

    test('快速键命中哈希一致：保留既有镜像状态（镜像按 video_id 存取）', () async {
      final src = await writeSource('dance.mp4', [1, 2, 3]);
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));

      // 首次导入后手动把条目镜像状态置为 true（接线前用 store 直接写）。
      final firstIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'dance.mp4', sourceUri: src.uri, sizeBytes: 3),
        ),
        indexStore: s,
      );
      await firstIm.import();
      final afterFirst = await waitForIndex(s, (i) => i.entries.isNotEmpty);
      final videoId = afterFirst.entries.single.videoId;
      // 模拟接线后的镜像开启：直接以镜像条目替换整份索引
      //（upsert 的合并语义是保留既有镜像偏好，不适合用来“设置”）。
      await s.update(
        (index) => VideoIndex(
          entries: [index.entries.single.copyWith(mirrored: true)],
        ),
      );

      // 再次打开同一视频：快速键命中 → 后台校验一致 → 仅刷新时间。
      final secondIm = importer(
        picker: FakeVideoPicker(null),
        indexStore: s,
        now: () => DateTime(2026, 9, 6, 12),
      );
      final second = await secondIm.open(
        PickedVideo(name: 'dance.mp4', sourceUri: src.uri, sizeBytes: 3),
      );
      expect(second.uri.toFilePath(), afterFirst.entries.single.filePath);

      final afterVerify = await waitForIndex(
        s,
        (i) => i.entries.single.lastOpenedAt == DateTime(2026, 9, 6, 12),
      );
      expect(afterVerify.entries.length, 1);
      expect(afterVerify.entries.single.videoId, videoId);
      expect(
        afterVerify.entries.single.mirrored,
        isTrue,
        reason: 'refresh 不得重置镜像状态',
      );
    });

    test('同内容不同文件名合并：保留既有镜像状态', () async {
      final srcA = await writeSource('a.mp4', [1, 2, 3]);
      final srcB = await writeSource('b.mp4', [1, 2, 3]); // 同内容不同名
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));

      final firstIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'a.mp4', sourceUri: srcA.uri, sizeBytes: 3),
        ),
        indexStore: s,
      );
      await firstIm.import();
      final afterFirst = await waitForIndex(s, (i) => i.entries.isNotEmpty);
      // 模拟接线后的镜像开启：直接以镜像条目替换整份索引
      //（upsert 的合并语义是保留既有镜像偏好，不适合用来“设置”）。
      await s.update(
        (index) => VideoIndex(
          entries: [index.entries.single.copyWith(mirrored: true)],
        ),
      );

      final secondIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'b.mp4', sourceUri: srcB.uri, sizeBytes: 3),
        ),
        indexStore: s,
        now: () => DateTime(2026, 9, 7, 12),
      );
      await secondIm.import(); // 快速键不同 → 首次导入路径 → upsert 合并

      final index = await waitForIndex(
        s,
        (i) => i.entries.isNotEmpty && i.entries.single.displayName == 'b.mp4',
      );
      expect(index.entries.length, 1);
      expect(index.entries.single.videoId, afterFirst.entries.single.videoId);
      expect(
        index.entries.single.mirrored,
        isTrue,
        reason: 'upsert 合并不得重置镜像状态',
      );
      expect(index.entries.single.lastOpenedAt, DateTime(2026, 9, 7, 12));
    });

    test('同内容不同文件名：走首次导入路径，同 videoId 条目合并不重复', () async {
      final srcA = await writeSource('a.mp4', [1, 2, 3]);
      final srcB = await writeSource('b.mp4', [1, 2, 3]); // 同内容不同名
      final s = VideoIndexStore(File(p.join(tempDir.path, 'index.json')));

      final firstIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'a.mp4', sourceUri: srcA.uri, sizeBytes: 3),
        ),
        indexStore: s,
      );
      await firstIm.import();
      final afterFirst = await waitForIndex(s, (i) => i.entries.isNotEmpty);

      final secondIm = importer(
        picker: FakeVideoPicker(
          PickedVideo(name: 'b.mp4', sourceUri: srcB.uri, sizeBytes: 3),
        ),
        indexStore: s,
        now: () => DateTime(2026, 9, 4, 12),
      );
      await secondIm.import(); // 快速键不同 → 首次导入路径

      final index = await waitForIndex(
        s,
        (i) => i.entries.isNotEmpty && i.entries.single.displayName == 'b.mp4',
      );
      expect(index.entries.length, 1, reason: '同 videoId 条目合并');
      expect(index.entries.single.videoId, afterFirst.entries.single.videoId);
      expect(p.basename(index.entries.single.filePath), 'b.mp4');
      expect(index.entries.single.lastOpenedAt, DateTime(2026, 9, 4, 12));
    });

    test('open 非 file:// 源抛出明确错误', () async {
      final im = importer(picker: FakeVideoPicker(null));
      expect(
        () => im.open(
          PickedVideo(
            name: 'a.mp4',
            sourceUri: Uri.parse('content://media/external/video/a.mp4'),
          ),
        ),
        throwsStateError,
      );
    });
  });
}
