import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/import/video_recovery.dart';
import 'package:dance_learning_app/import/video_picker.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_video_picker.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/recording_hasher.dart';

/// 找回动作直测：入参 = 条目 + 用户选中的文件；流程 = 算选中文件的
/// **视频标识** → 与条目身份比对。相符即把副本放回条目记录的原路径，
/// 不符 / 取消 / 失败三种结局如实返回、状态不变。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('recovery_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// 条目记录的原路径（父目录 `videos/` 起初不存在 = 副本丢失）。
  String originalPathFor(String videoId) =>
      p.join(tempDir.path, 'videos', '$videoId.mp4');

  Future<File> writeSelected(String name, List<int> bytes) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  VideoIndexEntry entry({
    required String filePath,
    String videoId = 'v1',
    String displayName = 'old-name.mp4',
    int sizeBytes = 3,
    DateTime? lastOpenedAt,
    bool mirrored = true,
    bool mirrorAsked = true,
    SongSignature? signatureCache,
    int lastPositionMs = 12000,
  }) => VideoIndexEntry(
    videoId: videoId,
    displayName: displayName,
    filePath: filePath,
    sizeBytes: sizeBytes,
    fastKey: fastKeyFor(name: displayName, sizeBytes: sizeBytes),
    mirrored: mirrored,
    mirrorAsked: mirrorAsked,
    lastOpenedAt: lastOpenedAt ?? DateTime(2026, 9, 1),
    signatureCache: signatureCache,
    lastPositionMs: lastPositionMs,
  );

  VideoRecovery recovery({
    required VideoPicker picker,
    required VideoIndexStorage indexStore,
    required ContentHasher hasher,
  }) => VideoRecovery(picker, indexStore: indexStore, hasher: hasher);

  group('相符：副本放回条目记录的原路径', () {
    test('父目录按需创建；身份、大小、路径与其余键都不动，只刷新显示名与快速键', () async {
      final selected = await writeSelected('new-name.mp4', [1, 2, 3]);
      final originalPath = originalPathFor('v1');
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            entry(
              filePath: originalPath,
              signatureCache: const SongSignature(song: '起风了'),
            ),
          ],
        ),
      );
      final hasher = RecordingHasher('v1');
      final picker = FakeVideoPicker(
        PickedVideo(
          name: 'new-name.mp4',
          sourceUri: selected.uri,
          sizeBytes: 3,
        ),
      );

      final outcome = await recovery(
        picker: picker,
        indexStore: storage,
        hasher: hasher,
      ).recover(storage.current.entries.single);

      expect(outcome, isA<VideoCopyRestored>());
      final restored = (outcome as VideoCopyRestored).entry;

      // 副本回到条目记录的原路径（不是选中文件所在的目录）。
      expect(originalPath, p.join(tempDir.path, 'videos', 'v1.mp4'));
      final copy = File(originalPath);
      expect(copy.existsSync(), isTrue, reason: '父目录按需创建后副本落回原路径');
      expect(await copy.readAsBytes(), [1, 2, 3]);

      // 身份、大小、路径、镜像组态、署名缓存、续播位置与最近打开时间都不动。
      final inIndex = storage.current.entries.single;
      expect(inIndex.videoId, 'v1');
      expect(inIndex.filePath, originalPath);
      expect(inIndex.sizeBytes, 3);
      expect(inIndex.mirrored, isTrue);
      expect(inIndex.mirrorAsked, isTrue);
      expect(inIndex.signatureCache, const SongSignature(song: '起风了'));
      expect(inIndex.lastPositionMs, 12000);
      expect(inIndex.lastOpenedAt, DateTime(2026, 9, 1));

      // 只刷新显示名与快速键（原文件名可能已改）。
      expect(inIndex.displayName, 'new-name.mp4');
      expect(inIndex.fastKey, fastKeyFor(name: 'new-name.mp4', sizeBytes: 3));
      expect(restored.displayName, 'new-name.mp4');

      // 核对算的是选中文件的标识，且复制完成后清选择器缓存。
      expect(hasher.hashedPaths, [selected.path]);
      expect(picker.clearCacheCalled, isTrue);
    });

    test('原路径已有别的字节：直接覆盖（那个位置本就是自持副本的位置）', () async {
      final selected = await writeSelected('v1.mp4', [7, 7, 7]);
      final originalPath = originalPathFor('v1');
      File(originalPath)
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 1, 1]);
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(filePath: originalPath)]),
      );

      final outcome =
          await recovery(
            picker: FakeVideoPicker(
              PickedVideo(
                name: 'v1.mp4',
                sourceUri: selected.uri,
                sizeBytes: 3,
              ),
            ),
            indexStore: storage,
            hasher: RecordingHasher('v1'),
          ).restoreFrom(
            storage.current.entries.single,
            PickedVideo(name: 'v1.mp4', sourceUri: selected.uri, sizeBytes: 3),
          );

      expect(outcome, isA<VideoCopyRestored>());
      expect(await File(originalPath).readAsBytes(), [7, 7, 7]);
    });
  });

  group('不符：明确返回「不是这支」', () {
    test('指纹不符：不复制、不落索引、不清缓存，选中文件原样带出', () async {
      final selected = await writeSelected('other.mp4', [9, 9, 9]);
      final originalPath = originalPathFor('v1');
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(filePath: originalPath)]),
      );
      final picker = FakeVideoPicker(
        PickedVideo(name: 'other.mp4', sourceUri: selected.uri, sizeBytes: 3),
      );

      final outcome = await recovery(
        picker: picker,
        indexStore: storage,
        hasher: RecordingHasher('not-this-dance'),
      ).recover(storage.current.entries.single);

      expect(outcome, isA<VideoIsNotThisDance>());
      final notThis = outcome as VideoIsNotThisDance;
      expect(notThis.picked.name, 'other.mp4');
      expect(notThis.picked.sourceUri, selected.uri);
      expect(
        notThis.videoId,
        'not-this-dance',
        reason: '核对算出的标识原样带出（另建一支直接用它，不再读第二遍）',
      );
      expect(File(originalPath).existsSync(), isFalse, reason: '不符不复制');
      expect(storage.updateCount, 0, reason: '不符不落索引');
      expect(picker.clearCacheCalled, isFalse, reason: '选中文件还要用来另建一支，不清选择器缓存');
      expect(storage.current.entries.single.displayName, 'old-name.mp4');
    });
  });

  group('取消：选择器返回 null', () {
    test('取消：零副作用（不复制、不落索引、不清缓存）', () async {
      final originalPath = originalPathFor('v1');
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(filePath: originalPath)]),
      );

      final outcome = await recovery(
        picker: FakeVideoPicker(null),
        indexStore: storage,
        hasher: RecordingHasher('v1'),
      ).recover(storage.current.entries.single);

      expect(outcome, isA<VideoRecoveryCancelled>());
      expect(File(originalPath).existsSync(), isFalse);
      expect(storage.updateCount, 0);
      expect(storage.current.entries.single.displayName, 'old-name.mp4');
    });
  });

  group('失败：如实返回、状态不变', () {
    test('核对（算标识）失败：failed 带出原错，索引与盘上状态不变', () async {
      final selected = await writeSelected('v1.mp4', [1, 2, 3]);
      final originalPath = originalPathFor('v1');
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(filePath: originalPath)]),
      );
      final picker = FakeVideoPicker(
        PickedVideo(name: 'v1.mp4', sourceUri: selected.uri, sizeBytes: 3),
      );

      final outcome = await recovery(
        picker: picker,
        indexStore: storage,
        hasher: _ThrowingHasher(),
      ).recover(storage.current.entries.single);

      expect(outcome, isA<VideoRecoveryFailed>());
      expect(
        (outcome as VideoRecoveryFailed).error,
        isA<FileSystemException>(),
        reason: '原错如实带出（不为界面另造一句）',
      );
      expect(storage.updateCount, 0);
      expect(File(originalPath).existsSync(), isFalse);
      expect(picker.clearCacheCalled, isFalse);
    });

    test('复制失败（源文件不在）：failed，索引不变、原路径不留残缺副本', () async {
      final missing = File(p.join(tempDir.path, 'gone.mp4'));
      final originalPath = originalPathFor('v1');
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(filePath: originalPath)]),
      );
      final picker = FakeVideoPicker(
        PickedVideo(name: 'v1.mp4', sourceUri: missing.uri, sizeBytes: 3),
      );

      final outcome = await recovery(
        picker: picker,
        indexStore: storage,
        hasher: RecordingHasher('v1'),
      ).recover(storage.current.entries.single);

      expect(outcome, isA<VideoRecoveryFailed>());
      expect(
        (outcome as VideoRecoveryFailed).error,
        isA<FileSystemException>(),
      );
      expect(File(originalPath).existsSync(), isFalse);
      expect(storage.updateCount, 0, reason: '复制失败不写显示名/快速键');
      expect(storage.current.entries.single.displayName, 'old-name.mp4');
      expect(picker.clearCacheCalled, isFalse);
    });

    test('非 file:// 源：failed 而非静默（与导入源的边界同一条）', () async {
      final originalPath = originalPathFor('v1');
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(filePath: originalPath)]),
      );

      final outcome =
          await recovery(
            picker: FakeVideoPicker(null),
            indexStore: storage,
            hasher: RecordingHasher('v1'),
          ).restoreFrom(
            storage.current.entries.single,
            PickedVideo(
              name: 'v1.mp4',
              sourceUri: Uri.parse('content://media/external/video/v1.mp4'),
            ),
          );

      expect(outcome, isA<VideoRecoveryFailed>());
      expect((outcome as VideoRecoveryFailed).error, isA<StateError>());
      expect(storage.updateCount, 0);
    });
  });
}

/// 算标识即失败的假哈希（界面上「找回失败」那一声的来源）。
class _ThrowingHasher implements ContentHasher {
  @override
  Future<String> hashFile(File file) async =>
      throw const FileSystemException('读取失败');
}
