import 'dart:async';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/dance/dance_library_writes.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_video_document_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 舞库管理写直测：改名写两条（公开标记文件署名真值先、索引署名
/// 缓存后），经原子读改写执行——同文档其它字段不动、真值写成功即改名成立。
/// 次序不靠插桩调用日志断言（不断言调用次序），而是
/// 由两个失败方向的结果钉住：真值没写成 ⇒ 索引缓存一动不动；索引写失败 ⇒
/// 真值已经在盘上。两向合起来即「真值先、缓存后」。
void main() {
  test('改名写两条：署名真值与索引署名缓存都落到新值', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1')]),
    );
    final writes = _writes(indexStore: indexStorage, storage: documents);

    final renamed = await writes.rename(
      entry: _entry('v1'),
      input: const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
    );

    expect(renamed, isTrue);
    expect(
      MarkersDocument.fromJson(documents.markersSnapshot).signature,
      const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
    );
    expect(
      indexStorage.current.entries.single.signatureCache,
      const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
    );
  });

  test('改名经原子读改写：同文档其它字段原样保留', () async {
    final documents = InMemoryVideoDocumentStorage(
      markers: MarkersDocument(
        mirrored: true,
        rangeStartMs: 1000,
        rangeEndMs: 9000,
        segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
      ).toJson(),
    );
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1')]),
    );
    final writes = _writes(indexStore: indexStorage, storage: documents);

    await writes.rename(
      entry: _entry('v1'),
      input: const SongSignature(song: '新名'),
    );

    final markers = MarkersDocument.fromJson(documents.markersSnapshot);
    expect(markers.signature, const SongSignature(song: '新名'));
    expect(markers.mirrored, isTrue);
    expect(markers.rangeStartMs, 1000);
    expect(markers.rangeEndMs, 9000);
    expect(markers.segmentLines, const [
      SegmentLine(position: Duration(seconds: 5)),
    ]);
  });

  test('markers 未创建：首建初值带索引署名缓存与镜像过渡值，再写新署名', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          _entry(
            'v1',
            mirrored: true,
            localMirrorEnabled: false,
            signatureCache: const SongSignature(song: '旧名'),
          ),
        ],
      ),
    );
    final writes = _writes(indexStore: indexStorage, storage: documents);

    await writes.rename(
      entry: indexStorage.current.entries.single,
      input: const SongSignature(song: '新名'),
    );

    final markers = MarkersDocument.fromJson(documents.markersSnapshot);
    expect(markers.signature, const SongSignature(song: '新名'));
    expect(markers.mirrored, isTrue, reason: '首建不得把镜像过渡值冲成缺省');
    expect(markers.localMirrorEnabled, isFalse);
  });

  test('版本舞者与版本注记可选：留空存空串；歌曲名空回退文件名', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1')]),
    );
    final writes = _writes(indexStore: indexStorage, storage: documents);

    await writes.rename(
      entry: _entry('v1'),
      input: const SongSignature(song: '   '),
    );

    expect(
      MarkersDocument.fromJson(documents.markersSnapshot).signature,
      const SongSignature(song: 'v1.mp4'),
    );
    expect(
      indexStorage.current.entries.single.signatureCache,
      const SongSignature(song: 'v1.mp4'),
    );
  });

  test('署名真值写失败：改名不成立、零副作用，索引缓存一动不动（真值先）', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          _entry('v1', signatureCache: const SongSignature(song: '旧名')),
        ],
      ),
    );
    final writes = _writes(
      indexStore: indexStorage,
      storage: FailingVideoDocumentStorage(documents, failMarkers: true),
    );

    final renamed = await writes.rename(
      entry: indexStorage.current.entries.single,
      input: const SongSignature(song: '新名'),
    );

    expect(renamed, isFalse);
    expect(indexStorage.updateCount, 0, reason: '真值没写成，缓存不该动');
    expect(
      indexStorage.current.entries.single.signatureCache,
      const SongSignature(song: '旧名'),
    );
    expect(documents.markersSnapshot, isEmpty);
  });

  test('索引写失败：真值已落盘即改名成立（缓存后于真值），索引保持原样、无半写状态', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          _entry('v1', signatureCache: const SongSignature(song: '旧名')),
        ],
      ),
    );
    final writes = _writes(
      indexStore: _FailingIndexStorage(indexStorage),
      storage: documents,
    );

    final renamed = await writes.rename(
      entry: indexStorage.current.entries.single,
      input: const SongSignature(song: '新名'),
    );

    expect(renamed, isTrue, reason: '署名真值写成功即视为改名成立');
    expect(
      MarkersDocument.fromJson(documents.markersSnapshot).signature,
      const SongSignature(song: '新名'),
    );
    expect(
      indexStorage.current.entries.single.signatureCache,
      const SongSignature(song: '旧名'),
      reason: '索引写失败不留半写状态（原样保留，下次打开以真值回写）',
    );
  });

  test('改名成功：索引署名缓存写成功后补一次 onRenamed（推送同步接线点）', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1')]),
    );
    var calls = 0;
    final writes = _writes(
      indexStore: indexStorage,
      storage: documents,
      onRenamed: () async {
        calls++;
      },
    );

    final renamed = await writes.rename(
      entry: _entry('v1'),
      input: const SongSignature(song: '新名'),
    );

    expect(renamed, isTrue);
    expect(calls, 1);
  });

  test('改名不成立（署名真值写失败）：onRenamed 不被调用', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [_entry('v1')]),
    );
    var calls = 0;
    final writes = _writes(
      indexStore: indexStorage,
      storage: FailingVideoDocumentStorage(documents, failMarkers: true),
      onRenamed: () async {
        calls++;
      },
    );

    final renamed = await writes.rename(
      entry: _entry('v1'),
      input: const SongSignature(song: '新名'),
    );

    expect(renamed, isFalse);
    expect(calls, 0);
  });

  test('索引署名缓存写失败：改名仍成立，但不补同步（缓存没变，读了也是旧名）', () async {
    final documents = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          _entry('v1', signatureCache: const SongSignature(song: '旧名')),
        ],
      ),
    );
    var calls = 0;
    final writes = _writes(
      indexStore: _FailingIndexStorage(indexStorage),
      storage: documents,
      onRenamed: () async {
        calls++;
      },
    );

    final renamed = await writes.rename(
      entry: indexStorage.current.entries.single,
      input: const SongSignature(song: '新名'),
    );

    expect(renamed, isTrue, reason: '署名真值已落盘即改名成立');
    expect(calls, 0);
    expect(
      indexStorage.current.entries.single.signatureCache,
      const SongSignature(song: '旧名'),
    );
  });

  group('封面位置（公开标记文件 meta 段）', () {
    test('写入：位置落进 meta 段，读面可读', () async {
      final documents = InMemoryVideoDocumentStorage();
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      expect(
        await writes.setCoverPosition(videoId: 'v1', positionMs: 42000),
        42000,
      );

      final markers = MarkersDocument.fromJson(documents.markersSnapshot);
      expect(markers.coverPositionMs, 42000);
      expect(documents.markersSnapshot['meta'], containsPair(
        'coverPositionMs',
        42000,
      ));
    });

    test('写入不丢同文档其它字段：署名 / 首尾 / 分段线 / meta 未知键原样保留', () async {
      final documents = InMemoryVideoDocumentStorage(
        markers: const {
          'version': 8,
          'meta': {
            'mirrored': true,
            'signature': {'dancer': '如', 'song': '真值名', 'remark': ''},
            'metaFuture': 'keep-me',
          },
          'annotations': {
            'range': {'startMs': 10000, 'endMs': 120000},
            'segmentLines': [
              {'timeMs': 60000, 'flag': true},
            ],
            'halfBeatLines': [],
            'emphasizedSegments': [],
            'localMirrorFragments': [],
          },
        },
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      await writes.setCoverPosition(videoId: 'v1', positionMs: 30000);

      final markers = MarkersDocument.fromJson(documents.markersSnapshot);
      expect(markers.coverPositionMs, 30000);
      expect(markers.signature, const SongSignature(dancer: '如', song: '真值名'));
      expect(markers.mirrored, isTrue);
      expect(markers.rangeStartMs, 10000);
      expect(markers.rangeEndMs, 120000);
      expect(markers.segmentLines, const [
        SegmentLine(position: Duration(seconds: 60), flagged: true),
      ]);
      expect(documents.markersSnapshot['meta'], containsPair(
        'metaFuture',
        'keep-me',
      ));
    });

    test('恢复为默认：传 null 清除字段（回到跟随首线），同文档其它字段不动', () async {
      final documents = InMemoryVideoDocumentStorage(
        markers: const MarkersDocument(
          signature: SongSignature(song: '歌'),
          coverPositionMs: 42000,
          rangeStartMs: 10000,
          rangeEndMs: 120000,
        ).toJson(),
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      // 返回清除后生效的位置 = 跟随首线的有效区间起点。
      expect(
        await writes.setCoverPosition(videoId: 'v1', positionMs: null),
        10000,
      );

      final markers = MarkersDocument.fromJson(documents.markersSnapshot);
      expect(markers.coverPositionMs, isNull);
      expect(
        (documents.markersSnapshot['meta'] as Map).containsKey(
          'coverPositionMs',
        ),
        isFalse,
      );
      expect(markers.signature, const SongSignature(song: '歌'));
      expect(markers.rangeStartMs, 10000);
    });

    test('markers 写失败：返回 null、文档原样（零副作用）', () async {
      final documents = InMemoryVideoDocumentStorage(
        markers: const MarkersDocument(coverPositionMs: 42000).toJson(),
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: FailingVideoDocumentStorage(documents, failMarkers: true),
      );

      expect(
        await writes.setCoverPosition(videoId: 'v1', positionMs: 99000),
        isNull,
      );
      expect(
        MarkersDocument.fromJson(documents.markersSnapshot).coverPositionMs,
        42000,
      );
    });

    test('无有效区间：清除返回第 0 帧（缺省语义不产出负数/空值）', () async {
      final documents = InMemoryVideoDocumentStorage();
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      expect(
        await writes.setCoverPosition(videoId: 'v1', positionMs: null),
        0,
      );
    });
  });

  group('逐段改档与一键完全掌握', () {    test('逐段改档：落盘值按段序对齐，同文档其它字段原样保留', () async {
      final documents = InMemoryVideoDocumentStorage(
        local: {
          'version': 3,
          'session': {
            'mastery': {'0': 'familiar'},
            'activatedSegments': [1],
            'futureSessionKey': 'keep',
          },
          'prefs': {'layoutLocked': true, 'futurePrefsKey': 7},
        },
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      final written = await writes.setSegmentsMastery(
        videoId: 'v1',
        values: const DanceMasteryValues(
          orders: [0, 1],
          mastery: {
            0: LearningMastery.mastered,
            1: LearningMastery.keepingUp,
          },
        ),
      );

      expect(written, isTrue);
      final local = LocalDocument.fromJson(documents.localSnapshot);
      expect(local.mastery, const {
        0: LearningMastery.mastered,
        1: LearningMastery.keepingUp,
      });
      expect(local.activatedSegments, const [1]);
      expect(
        documents.localSnapshot['session'],
        containsPair('futureSessionKey', 'keep'),
      );
      expect(
        (documents.localSnapshot['prefs'] as Map)['futurePrefsKey'],
        7,
        reason: '原子读改写不丢同文档其它段与未知扩展键',
      );
      expect(local.layoutLocked, isTrue);
    });

    test('改到「未练」：显式未练不入 Map（稀疏存储，段序键被清出）', () async {
      final documents = InMemoryVideoDocumentStorage(
        local: const LocalDocument(
          mastery: {
            0: LearningMastery.familiar,
            1: LearningMastery.mastered,
          },
        ).toJson(),
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      await writes.setSegmentsMastery(
        videoId: 'v1',
        values: const DanceMasteryValues(
          orders: [0],
          mastery: {0: LearningMastery.unlearned},
        ),
      );

      expect(LocalDocument.fromJson(documents.localSnapshot).mastery, const {
        1: LearningMastery.mastered,
      });
    });

    test('一键完全掌握：全部给定段写最高档', () async {
      final documents = InMemoryVideoDocumentStorage();
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      await writes.setSegmentsMastery(
        videoId: 'v1',
        values: const DanceMasteryValues(orders: [0, 1, 2]).allMastered,
      );

      expect(LocalDocument.fromJson(documents.localSnapshot).mastery, const {
        0: LearningMastery.mastered,
        1: LearningMastery.mastered,
        2: LearningMastery.mastered,
      });
    });

    test('撤销：回写快照回到点击前的值（原为未练的段清出 Map）', () async {
      final documents = InMemoryVideoDocumentStorage(
        local: const LocalDocument(
          mastery: {0: LearningMastery.familiar},
        ).toJson(),
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: documents,
      );

      await writes.setSegmentsMastery(
        videoId: 'v1',
        values: const DanceMasteryValues(orders: [0, 1]).allMastered,
      );
      expect(LocalDocument.fromJson(documents.localSnapshot).mastery, const {
        0: LearningMastery.mastered,
        1: LearningMastery.mastered,
      });

      // 页面内快照 = 点击前的稀疏熟练度表（段 1 未练 → 缺席）。
      await writes.setSegmentsMastery(
        videoId: 'v1',
        values: const DanceMasteryValues(
          orders: [0, 1],
          mastery: {0: LearningMastery.familiar},
        ),
      );

      expect(LocalDocument.fromJson(documents.localSnapshot).mastery, const {
        0: LearningMastery.familiar,
      });
    });

    test('local 写失败：返回 false、文件原样（零副作用）', () async {
      final documents = InMemoryVideoDocumentStorage(
        local: const LocalDocument(
          mastery: {0: LearningMastery.familiar},
        ).toJson(),
      );
      final writes = _writes(
        indexStore: InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [_entry('v1')]),
        ),
        storage: FailingVideoDocumentStorage(documents, failLocal: true),
      );

      final written = await writes.setSegmentsMastery(
        videoId: 'v1',
        values: const DanceMasteryValues(
          orders: [0],
          mastery: {0: LearningMastery.mastered},
        ),
      );

      expect(written, isFalse);
      expect(LocalDocument.fromJson(documents.localSnapshot).mastery, const {
        0: LearningMastery.familiar,
      });
    });
  });
}

DanceLibraryWrites _writes({
  required VideoIndexStorage indexStore,
  required VideoDocumentStorage storage,
  Future<void> Function()? onRenamed,
}) => DanceLibraryWrites(
  indexStore: indexStore,
  storageFor: (_) => storage,
  onRenamed: onRenamed,
);

VideoIndexEntry _entry(
  String videoId, {
  bool mirrored = false,
  bool localMirrorEnabled = true,
  SongSignature? signatureCache,
}) =>
    VideoIndexEntry(
      videoId: videoId,
      displayName: '$videoId.mp4',
      filePath: '/videos/$videoId.mp4',
      sizeBytes: 1,
      fastKey: 'k-$videoId',
      mirrored: mirrored,
      localMirrorEnabled: localMirrorEnabled,
      lastOpenedAt: DateTime(2026, 9, 1),
      signatureCache: signatureCache,
    );

/// 索引写失败：真值已落盘、缓存保持原样断言用。
class _FailingIndexStorage implements VideoIndexStorage {
  _FailingIndexStorage(this._inner);

  final InMemoryVideoIndexStorage _inner;

  @override
  Future<VideoIndex> load() => _inner.load();

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async =>
      throw StateError('索引不可写');
}
