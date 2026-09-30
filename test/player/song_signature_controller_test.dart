import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/stats/song_signature.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

void main() {
  const filePath = '/priv/videos/dance.mp4';

  /// 同名同大小不同内容时打开会话给出的新身份（内容摘要）；旧条目仍在索引里。
  const changedId = 'hash-2';

  VideoIndexEntry entry({
    SongSignature? signatureCache,
    bool mirrored = false,
  }) {
    return VideoIndexEntry(
      videoId: 'hash-1',
      displayName: 'dance.mp4',
      filePath: filePath,
      sizeBytes: 3,
      fastKey: fastKeyFor(name: 'dance.mp4', sizeBytes: 3),
      mirrored: mirrored,
      mirrorAsked: true,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
      signatureCache: signatureCache,
    );
  }

  /// 构造（索引 + 协调器 + 控制器）并注入会话给出的已确认身份、完成打开解析。
  Future<
    (
      InMemoryVideoIndexStorage,
      InMemoryVideoDocumentStorage,
      SongSignatureController,
    )
  >
  make({
    VideoIndex initial = VideoIndex.empty,
    Map<String, dynamic> markers = const {},
    bool markersPresent = false,
  }) async {
    final index = InMemoryVideoIndexStorage(initial: initial);
    final docs = InMemoryVideoDocumentStorage(
      markers: markers,
      markersPresent: markersPresent,
    );
    final coordinator = VideoDocumentCoordinator(docs);
    final controller = SongSignatureController(
      index,
      coordinatorFor: (_) => coordinator,
    );
    final entry = initial.findByFilePath(filePath);
    await controller.startForFile(
      filePath,
      videoId: entry?.videoId,
      entry: entry,
    );
    return (index, docs, controller);
  }

  group('打开解析署名现值', () {
    test('无 markers：署名取 index 署名缓存', () async {
      const cached = SongSignature(song: 'My Love');
      final (index, docs, controller) = await make(
        initial: VideoIndex(entries: [entry(signatureCache: cached)]),
      );
      expect(controller.signature, cached);
      expect(docs.markersSnapshot.containsKey('version'), isFalse);
      expect(index.current.entries.single.signatureCache, cached);
    });

    test('无 markers 且无缓存：未署名（null，标题回退文件名）', () async {
      final (_, _, controller) = await make(
        initial: VideoIndex(entries: [entry()]),
      );
      expect(controller.signature, isNull);
    });

    test('markers 存在：以 markers 署名为准并回写 index 缓存', () async {
      const markersSignature = SongSignature(
        dancer: '如',
        song: 'My Love',
        remark: '9人版',
      );
      final (index, _, controller) = await make(
        initial: VideoIndex(entries: [entry()]),
        markers: MarkersDocument(
          signature: markersSignature,
          mirrored: true,
        ).toJson(),
        markersPresent: true,
      );
      expect(controller.signature, markersSignature);
      expect(index.current.entries.single.signatureCache, markersSignature);
    });

    test('markers 缺失而索引条目未落盘：保持未署名不崩溃', () async {
      final (_, _, controller) = await make();
      expect(controller.signature, isNull);
    });
  });

  group('命名/改名双写', () {
    test('改名双写 index + markers', () async {
      final (index, docs, controller) = await make(
        initial: VideoIndex(entries: [entry()]),
      );
      await controller.applySignature(
        const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
        fallbackSong: 'dance.mp4',
      );
      expect(controller.signature!.song, 'My Love');
      expect(index.current.entries.single.signatureCache!.song, 'My Love');
      expect(
        MarkersDocument.fromJson(docs.markersSnapshot).signature,
        const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
      );
    });

    test('markers 不存在：首建即带完整署名与镜像初值', () async {
      final (_, docs, controller) = await make(
        initial: VideoIndex(entries: [entry(mirrored: true)]),
      );
      await controller.applySignature(
        const SongSignature(song: 'My Love'),
        fallbackSong: 'dance.mp4',
      );
      final markers = MarkersDocument.fromJson(docs.markersSnapshot);
      expect(markers.signature, const SongSignature(song: 'My Love'));
      expect(markers.mirrored, isTrue);
      expect(MarkersDocument.fromJson(docs.markersSnapshot).mirrored, isTrue);
    });

    test('markers 已存在且带标注：改名只动署名，不覆盖其它字段', () async {
      final existing = MarkersDocument(
        mirrored: true,
        signature: const SongSignature(song: '旧名'),
        rangeStartMs: 100,
        rangeEndMs: 900,
        segmentLines: const [],
      );
      final (_, docs, controller) = await make(
        initial: VideoIndex(entries: [entry()]),
        markers: existing.toJson(),
        markersPresent: true,
      );
      await controller.applySignature(
        const SongSignature(song: '新名'),
        fallbackSong: 'dance.mp4',
      );
      final markers = MarkersDocument.fromJson(docs.markersSnapshot);
      expect(markers.signature, const SongSignature(song: '新名'));
      expect(markers.mirrored, isTrue);
      expect(markers.rangeStartMs, 100);
      expect(markers.rangeEndMs, 900);
    });

    test('提交前净化：歌曲名空回退文件名、控制字符剥离', () async {
      final (index, docs, controller) = await make(
        initial: VideoIndex(entries: [entry()]),
      );
      final result = await controller.applySignature(
        const SongSignature(dancer: ' 如\n', song: ' ', remark: '9人版\x7f'),
        fallbackSong: 'dance.mp4',
      );
      expect(
        result,
        const SongSignature(dancer: '如', song: 'dance.mp4', remark: '9人版'),
      );
      expect(index.current.entries.single.signatureCache, result);
      expect(MarkersDocument.fromJson(docs.markersSnapshot).signature, result);
    });

    test('重名允许：不同条目写同名署名互不干扰', () async {
      final other = VideoIndexEntry(
        videoId: 'hash-2',
        displayName: 'copy.mp4',
        filePath: '/priv/videos/copy.mp4',
        sizeBytes: 3,
        fastKey: fastKeyFor(name: 'copy.mp4', sizeBytes: 3),
        mirrored: false,
        mirrorAsked: true,
        lastOpenedAt: DateTime(2026, 9, 2),
      );
      final (index, _, controller) = await make(
        initial: VideoIndex(entries: [entry(), other]),
      );
      await controller.applySignature(
        const SongSignature(song: 'My Love'),
        fallbackSong: 'dance.mp4',
      );
      final entries = index.current.entries;
      expect(entries[0].signatureCache, const SongSignature(song: 'My Love'));
      expect(entries[1].signatureCache, isNull);
    });

    test('会话给出身份而索引条目未落盘（哈希后台计算中）：条目落盘后双写', () async {
      final index = InMemoryVideoIndexStorage();
      final docs = InMemoryVideoDocumentStorage();
      final coordinator = VideoDocumentCoordinator(docs);
      final controller = SongSignatureController(
        index,
        coordinatorFor: (_) => coordinator,
      );
      // 打开会话按内容摘要给出身份（索引条目尚未落盘），不再轮询等待。
      await controller.startForFile(filePath, videoId: 'hash-1');
      // 打开解析期间后台哈希落盘（同一内容 → 条目 videoId 与身份一致）。
      await index.update((i) => i.upsert(entry()));
      await controller.applySignature(
        const SongSignature(song: 'My Love'),
        fallbackSong: 'dance.mp4',
      );
      expect(index.current.entries.single.signatureCache!.song, 'My Love');
      expect(
        MarkersDocument.fromJson(docs.markersSnapshot).signature!.song,
        'My Love',
      );
    });

    test('未接协调器：只写 index，不写 markers', () async {
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry()]),
      );
      final controller = SongSignatureController(index);
      await controller.startForFile(
        filePath,
        videoId: 'hash-1',
        entry: entry(),
      );
      await controller.applySignature(
        const SongSignature(song: 'My Love'),
        fallbackSong: 'dance.mp4',
      );
      expect(index.current.entries.single.signatureCache!.song, 'My Love');
    });

    test('哈希不符（同名同大小不同内容）：不套用旧条目署名，写入新身份文档', () async {
      const oldSignature = SongSignature(song: '旧名');
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry(signatureCache: oldSignature)]),
      );
      final changedDocs = InMemoryVideoDocumentStorage();
      final controller = SongSignatureController(
        index,
        coordinatorFor: (id) => VideoDocumentCoordinator(
          id == changedId ? changedDocs : InMemoryVideoDocumentStorage(),
        ),
      );

      // 打开会话：条目命中但摘要不符 → 身份取摘要、entry 为 null、旧条目保留。
      await controller.startForFile(filePath, videoId: changedId);

      expect(controller.signature, isNull, reason: '不套用旧条目的署名缓存');
      expect(
        index.current.entries.single.signatureCache,
        oldSignature,
        reason: '旧条目保留、不被写',
      );

      await controller.applySignature(
        const SongSignature(song: '新名'),
        fallbackSong: 'dance.mp4',
      );

      expect(
        MarkersDocument.fromJson(changedDocs.markersSnapshot).signature,
        const SongSignature(song: '新名'),
        reason: '改名写到会话给出的新身份文档',
      );
      expect(
        index.current.entries.single.signatureCache,
        oldSignature,
        reason: '摘要不符时旧条目不被写',
      );
    });
  });
}
