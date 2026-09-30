import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/stored_zip.dart';
import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/import/video_importer.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/package/scheme_import.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fixed_hasher.dart';
import '../helpers/fake_video_picker.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 导入编排：真实 zip 往返 + 内存索引/方案/文档
/// 存取——断言分支树判定值与各分支的外部结果（写成我的标注 / 落组员方案 /
/// 建舞 / 明确拒绝）与包报错的用户话术。
/// 真实管道（复制/哈希/索引全真），仅选择器注入空实现；与编排共用同一
/// 份索引存取。
VideoImporter _realVideoImporter(
  VideoIndexStorage indexStore,
  Directory videosDir,
) => VideoImporter(
  FakeVideoPicker(null),
  () async => videosDir,
  indexStore: indexStore,
  hasher: const FixedHasher('hash-v1'),
);

VideoImporter _stubVideoImporter({VideoIndexStorage? indexStoreOverride}) =>
    VideoImporter(
      FakeVideoPicker(null),
      () async => throw StateError('该用例不应走建舞分支'),
      indexStore: indexStoreOverride ?? InMemoryVideoIndexStorage(),
      hasher: const FixedHasher('hash-v1'),
    );

const _sourceVideoEntry = SusumeMediaEntry(
  kind: SusumeMediaKind.sourceVideo,
  fileName: 'dance.mp4',
  sizeBytes: 3,
);

void main() {
  late Directory tempDir;
  late Directory videosDir;
  late Map<String, InMemoryMemberSchemeStorage> schemeStorages;
  late Map<String, InMemoryVideoDocumentStorage> documents;

  const manifest = SusumeManifest(
    videoId: 'hash-v1',
    schemeName: '测试歌',
    schemeId: 'scheme-1',
    memberName: '小如',
    mastery: {0: 2},
    media: [_sourceVideoEntry],
  );

  /// 不带源视频的包：分支树先决判据不成立，无论哪条分支都拒绝。
  const manifestNoVideo = SusumeManifest(
    videoId: 'hash-v1',
    schemeName: '测试歌',
    schemeId: 'scheme-1',
    memberName: '小如',
    mastery: {0: 2},
  );

  const markers = {'version': 3, 'segmentLines': <Object?>[]};

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scheme_import_test');
    videosDir = Directory(p.join(tempDir.path, 'videos'));
    schemeStorages = {};
    documents = {};
  });

  tearDown(() async => tempDir.delete(recursive: true));

  File videoSource() =>
      File(p.join(tempDir.path, 'dance.mp4'))..writeAsBytesSync([1, 2, 3]);

  Future<File> writePackage(SusumeManifest m) async {
    final file = File(p.join(tempDir.path, '测试歌.susume'));
    await writeSusumePackage(
      output: file,
      manifest: SusumeManifest(
        videoId: m.videoId,
        schemeName: m.schemeName,
        schemeId: m.schemeId,
        memberName: m.memberName,
        mastery: m.mastery,
        // 装配侧媒体条目必须带源文件：源视频条目一律指向同一份夹具视频。
        media: [
          for (final entry in m.media)
            SusumeMediaEntry(
              kind: entry.kind,
              fileName: entry.fileName,
              sizeBytes: entry.sizeBytes,
              file: entry.kind == SusumeMediaKind.sourceVideo
                  ? videoSource()
                  : null,
            ),
        ],
      ),
      markers: markers,
    );
    return file;
  }

  /// 版本不符的包：清单 version = 99（zip 层手写，包模块只写当前版本）。
  Future<File> writeFutureVersionPackage() async {
    final file = File(p.join(tempDir.path, 'future.susume'));
    await writeStoredZip(file, [
      (
        name: 'manifest.json',
        bytes: utf8.encode(jsonEncode({
          'version': 99,
          'videoId': 'hash-v1',
          'schemeName': '测试歌',
          'schemeId': 'scheme-1',
        })),
        file: null,
      ),
      (name: 'markers.json', bytes: utf8.encode(jsonEncode(markers)), file: null),
    ]);
    return file;
  }

  SchemeImporter importer({
    VideoIndexStorage? indexStore,
    VideoImporter? videoImporter,
    Future<bool> Function(String videoId, SongSignature signature)? titleWriter,
  }) {
    final store = indexStore ?? InMemoryVideoIndexStorage();
    return SchemeImporter(
      indexStore: store,
      videoImporter:
          videoImporter ?? _stubVideoImporter(indexStoreOverride: store),
      schemeStoreFor: (videoId) => MemberSchemeStore(
        schemeStorages.putIfAbsent(videoId, InMemoryMemberSchemeStorage.new),
      ),
      documentStorageFor: (videoId) =>
          documents.putIfAbsent(videoId, InMemoryVideoDocumentStorage.new),
      titleWriter: titleWriter,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  }

  PickedVideo pickedPackage(File file) => PickedVideo(
    name: '测试歌.susume',
    sourceUri: file.uri,
    sizeBytes: file.lengthSync(),
  );

  group('导入分支树的判定值（纯层）', () {
    test('已有舞问归属；无舞无熟练度直接建舞；无舞带熟练度问归属', () {
      expect(
        resolveImportBranch(danceExists: true, packageHasMastery: true),
        SchemeImportBranch.askOwnership,
      );
      expect(
        resolveImportBranch(danceExists: true, packageHasMastery: false),
        SchemeImportBranch.askOwnership,
      );
      expect(
        resolveImportBranch(danceExists: false, packageHasMastery: false),
        SchemeImportBranch.createAsMine,
      );
      expect(
        resolveImportBranch(danceExists: false, packageHasMastery: true),
        SchemeImportBranch.askCreateOwnership,
      );
    });
  });

  group('已有这支舞：写成我的标注', () {
    test('包里公开标注整份写进 markers，逐段熟练度与激活清空，其余私密字段原样', () async {
      final indexStore = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry('hash-v1')]),
      );
      final originalLocal =
          const LocalDocument(previewSnapEnabled: false, layoutLocked: true)
              .withMasteryMap(const {
                1: LearningMastery.keepingUp,
                2: LearningMastery.mastered,
              })
              .withActivatedSegments(const [1]);
      documents['hash-v1'] = InMemoryVideoDocumentStorage(
        local: originalLocal.toJson(),
      );
      final packageFile = await writePackage(manifest);

      final outcome = await importer(indexStore: indexStore).importScheme(
        picked: pickedPackage(packageFile),
        intent: const WriteAsMyMarkers(),
      );

      final imported = outcome as SchemeImported;
      expect(imported.landing, SchemeImportLanding.writtenAsMine);
      expect(imported.createdDance, isFalse);
      expect(imported.memberName, '小如');
      expect(imported.danceTitle, 'hash-v1.mp4');

      // 整份写入：markers 逐字段等于包里的公开标注。
      expect(documents['hash-v1']!.markersSnapshot, markers);

      // 本地文档：逐段熟练度与激活清空；编辑偏好、浮层几何等其余私密字段
      // 原样（整份文档等于「原文只清 session 两字段」）。
      expect(
        documents['hash-v1']!.localSnapshot,
        originalLocal
            .withMasteryMap(const {})
            .withActivatedSegments(const [])
            .toJson(),
      );

      // 不落组员方案。
      expect(schemeStorages, isEmpty);
    });
  });

  group('已有这支舞：留成组员方案', () {
    test('按方案标识落一条组员方案，值全含、不建新舞', () async {
      final indexStore = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry('hash-v1')]),
      );
      final packageFile = await writePackage(manifest);

      final outcome = await importer(indexStore: indexStore).importScheme(
        picked: pickedPackage(packageFile),
        intent: const LandAsMemberScheme('如改'),
      );

      final imported = outcome as SchemeImported;
      expect(imported.landing, SchemeImportLanding.keptAsMemberScheme);
      expect(imported.createdDance, isFalse);
      expect(imported.memberName, '如改');
      expect(imported.danceTitle, 'hash-v1.mp4');

      final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
      expect(doc.schemes.length, 1);
      expect(doc.schemes.single.schemeId, 'scheme-1');
      expect(doc.schemes.single.memberName, '如改');
      expect(doc.schemes.single.schemeName, '测试歌');
      expect(doc.schemes.single.mastery, {0: 2});
      expect(doc.schemes.single.markers, markers);
      expect(
        doc.schemes.single.importedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('同方案标识再导入替换旧条，异标识并存', () async {
      final indexStore = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry('hash-v1')]),
      );
      final schemeImporter = importer(indexStore: indexStore);
      final picked = pickedPackage(await writePackage(manifest));
      await schemeImporter.importScheme(
        picked: picked,
        intent: const LandAsMemberScheme('小如'),
      );
      await schemeImporter.importScheme(
        picked: picked,
        intent: const LandAsMemberScheme('小如二'),
      );

      final second = pickedPackage(
        await writePackage(
          const SusumeManifest(
            videoId: 'hash-v1',
            schemeName: '测试歌',
            schemeId: 'scheme-2',
            media: [_sourceVideoEntry],
          ),
        ),
      );
      await schemeImporter.importScheme(
        picked: second,
        intent: const LandAsMemberScheme('老师版'),
      );

      final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
      expect(doc.schemes.map((s) => s.schemeId), ['scheme-1', 'scheme-2']);
      expect(doc.schemes.first.memberName, '小如二');
    });
  });

  group('没有这支舞且包内带源视频', () {
    test('无熟练度：直接建舞写成我的——标注整份写入，不落组员方案', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final videoImporter = _realVideoImporter(indexStore, videosDir);
      final packageFile = await writePackage(
        const SusumeManifest(
          videoId: 'hash-v1',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          memberName: '小如',
          media: [_sourceVideoEntry],
        ),
      );

      final outcome =
          await importer(
            indexStore: indexStore,
            videoImporter: videoImporter,
          ).importScheme(
            picked: pickedPackage(packageFile),
            intent: const WriteAsMyMarkers(),
          );

      final imported = outcome as SchemeImported;
      expect(imported.landing, SchemeImportLanding.writtenAsMine);
      expect(imported.createdDance, isTrue);

      // 建舞：索引有该条目、私有目录有视频副本（既有管道的行为）。
      final index = await indexStore.load();
      expect(index.findById('hash-v1'), isNotNull);
      expect(File(index.findById('hash-v1')!.filePath).readAsBytesSync(), [
        1,
        2,
        3,
      ]);

      // 标注写成我的；熟练度本来就没带，也不落组员方案。
      expect(documents['hash-v1']!.markersSnapshot, markers);
      expect(schemeStorages, isEmpty);
    });

    test('带熟练度、建成我的标注方案：熟练度快照丢弃，标注整份写入', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final videoImporter = _realVideoImporter(indexStore, videosDir);
      final packageFile = await writePackage(manifest);

      final outcome =
          await importer(
            indexStore: indexStore,
            videoImporter: videoImporter,
          ).importScheme(
            picked: pickedPackage(packageFile),
            intent: const WriteAsMyMarkers(),
          );

      expect(
        (outcome as SchemeImported).landing,
        SchemeImportLanding.writtenAsMine,
      );
      expect(documents['hash-v1']!.markersSnapshot, markers);
      expect(schemeStorages, isEmpty, reason: '熟练度只随组员方案走：丢弃快照');
    });

    test('带熟练度、建成组员方案：建舞后挂带熟练度快照的组员方案', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final videoImporter = _realVideoImporter(indexStore, videosDir);
      final packageFile = await writePackage(manifest);

      final outcome =
          await importer(
            indexStore: indexStore,
            videoImporter: videoImporter,
          ).importScheme(
            picked: pickedPackage(packageFile),
            intent: const LandAsMemberScheme('小如'),
          );

      final imported = outcome as SchemeImported;
      expect(imported.landing, SchemeImportLanding.createdAsMemberScheme);
      expect(imported.createdDance, isTrue);
      expect(imported.memberName, '小如');

      final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
      expect(doc.schemes.single.schemeId, 'scheme-1');
      expect(doc.schemes.single.memberName, '小如');
      expect(doc.schemes.single.mastery, {0: 2});
    });

    test('走既有管道建舞（复制+哈希+索引），方案挂在新舞下', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final videoImporter = _realVideoImporter(indexStore, videosDir);
      final packageFile = await writePackage(manifest);

      final outcome =
          await importer(
            indexStore: indexStore,
            videoImporter: videoImporter,
          ).importScheme(
            picked: pickedPackage(packageFile),
            intent: const LandAsMemberScheme('小如'),
          );

      expect(outcome, isA<SchemeImported>());
      expect((outcome as SchemeImported).createdDance, isTrue);

      // 建舞：索引有该条目、私有目录有视频副本（既有管道的行为）。
      final index = await indexStore.load();
      expect(index.findById('hash-v1'), isNotNull);
      expect(File(index.findById('hash-v1')!.filePath).readAsBytesSync(), [
        1,
        2,
        3,
      ]);

      // 建舞后挂上组员方案。
      final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
      expect(doc.schemes.single.schemeId, 'scheme-1');
      expect(doc.schemes.single.memberName, '小如');
    });

    test('建舞的舞名以包清单的方案名立底，不回落源视频文件名', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final videoImporter = _realVideoImporter(indexStore, videosDir);
      final packageFile = await writePackage(
        const SusumeManifest(
          videoId: 'hash-v1',
          schemeName: '测试歌',
          schemeId: 'scheme-1',
          media: [
            SusumeMediaEntry(
              kind: SusumeMediaKind.sourceVideo,
              // 源视频文件名与歌名刻意不同：显示名不该被它带偏。
              fileName: 'VID_20260101.mp4',
              sizeBytes: 3,
            ),
          ],
        ),
      );
      final written = <String, SongSignature>{};

      final outcome =
          await importer(
            indexStore: indexStore,
            videoImporter: videoImporter,
            titleWriter: (videoId, signature) async {
              written[videoId] = signature;
              await indexStore.update(
                (index) => index.setSignatureCacheByFilePath(
                  index.findById(videoId)!.filePath,
                  signature,
                ),
              );
              return true;
            },
          ).importScheme(
            picked: pickedPackage(packageFile),
            intent: const LandAsMemberScheme('小如'),
          );

      expect(written['hash-v1']?.song, '测试歌');
      expect((outcome as SchemeImported).danceTitle, contains('测试歌'));
      expect((outcome).danceTitle, isNot(contains('VID_20260101')));
    });

    test('署名写入失败不阻断导入：舞名回落文件名，方案已挂上', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final videoImporter = _realVideoImporter(indexStore, videosDir);
      final packageFile = await writePackage(manifest);

      final outcome =
          await importer(
            indexStore: indexStore,
            videoImporter: videoImporter,
            titleWriter: (_, _) async => false,
          ).importScheme(
            picked: pickedPackage(packageFile),
            intent: const LandAsMemberScheme('小如'),
          );

      expect(outcome, isA<SchemeImported>());
      final doc = await MemberSchemeStore(schemeStorages['hash-v1']!).read();
      expect(doc.schemes.single.schemeId, 'scheme-1');
    });
  });

  group('包里没带源视频：三分支一律拒绝', () {
    test('本机也没有这支舞：明确拒绝，不建无归属的方案', () async {
      final indexStore = InMemoryVideoIndexStorage();
      final packageFile = await writePackage(manifestNoVideo);

      final outcome = await importer(indexStore: indexStore).importScheme(
        picked: pickedPackage(packageFile),
        intent: const LandAsMemberScheme('小如'),
      );

      expect(outcome, isA<SchemeImportRejected>());
      expect((outcome as SchemeImportRejected).message, contains('请先导入视频'));
      expect(schemeStorages, isEmpty, reason: '不建无归属的方案');
      expect((await indexStore.load()).entries, isEmpty);
    });

    test('本机已有这支舞：同样拒绝，不落任何数据', () async {
      final indexStore = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry('hash-v1')]),
      );
      documents['hash-v1'] = InMemoryVideoDocumentStorage();
      final packageFile = await writePackage(manifestNoVideo);

      final outcome = await importer(indexStore: indexStore).importScheme(
        picked: pickedPackage(packageFile),
        intent: const WriteAsMyMarkers(),
      );

      expect(outcome, isA<SchemeImportRejected>());
      expect((outcome as SchemeImportRejected).message, contains('请先导入视频'));
      expect(documents['hash-v1']!.markersSnapshot, isEmpty);
      expect(schemeStorages, isEmpty);
    });
  });

  group('包报错翻译成用户话术', () {
    test('版本不符 → 来自更新版本的提示', () async {
      final outcome = await importer().importScheme(
        picked: pickedPackage(await writeFutureVersionPackage()),
        intent: const LandAsMemberScheme(''),
      );

      expect(outcome, isA<SchemeImportFailed>());
      expect(
        (outcome as SchemeImportFailed).message,
        '这个文件来自更新版本的 Susume，请先升级',
      );
    });

    test('不是 zip → 损坏提示', () async {
      final notZip = File(p.join(tempDir.path, 'bad.susume'))
        ..writeAsBytesSync([0, 1, 2, 3]);

      final outcome = await importer().importScheme(
        picked: pickedPackage(notZip),
        intent: const LandAsMemberScheme(''),
      );

      expect(outcome, isA<SchemeImportFailed>());
      expect((outcome as SchemeImportFailed).message, '文件损坏或不是 Susume 包，无法导入');
    });
  });
}

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
