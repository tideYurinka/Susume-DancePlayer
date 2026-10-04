import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/open_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

const String kVideoId = 'hash-1';
const String kFilePath = '/videos/a.mp4';

VideoIndexEntry entryFor({String videoId = kVideoId}) => VideoIndexEntry(
  videoId: videoId,
  displayName: 'a.mp4',
  filePath: kFilePath,
  sizeBytes: 1,
  fastKey: '1:a.mp4',
  mirrored: false,
  mirrorAsked: true,
  lastOpenedAt: DateTime(2026, 9, 1),
  signatureCache: const SongSignature(song: 'a'),
);

Map<String, dynamic> markersJson() => {
  'version': 8,
  'annotations': {
    'range': {'startMs': 0, 'endMs': 180000},
    'segmentLines': [
      {'timeMs': 60000, 'flag': true},
    ],
    'emphasizedSegments': [1],
  },
};

Map<String, dynamic> localJson() => {
  'version': 3,
  'session': {
    'mastery': {'1': 'practicing'},
    'activatedSegments': [1],
  },
};

/// 索引不可读（读盘抛错）的存储：按「未命中」语义处理。
class ThrowingIndexStorage implements VideoIndexStorage {
  @override
  Future<VideoIndex> load() async => throw StateError('index unreadable');

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async => throw StateError('index unreadable');
}

OpenSession sessionFor({
  required VideoIndexStorage indexStore,
  required ContentHasher hasher,
  required VideoDocumentCoordinator Function(String videoId) coordinatorFor,
}) => OpenSession(
  filePath: kFilePath,
  indexStore: indexStore,
  hasher: hasher,
  coordinatorFor: coordinatorFor,
);

void main() {
  test('建立序列·条目命中且摘要相符：身份取条目、读该身份两份文档为基线', () async {
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [entryFor()]),
    );
    final storage = InMemoryVideoDocumentStorage(
      markers: markersJson(),
      local: localJson(),
    );
    final requested = <String>[];
    final session = sessionFor(
      indexStore: index,
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (videoId) {
        requested.add(videoId);
        return VideoDocumentCoordinator(storage);
      },
    );

    await session.establish();

    expect(session.established, isTrue);
    expect(session.identity, OpenIdentityKind.matched);
    expect(session.videoId, kVideoId);
    expect(session.entry, isNotNull);
    expect(requested, [kVideoId], reason: '文档按确定的身份寻址');
    expect(
      session.markers.segmentLines.single.position,
      const Duration(seconds: 60),
      reason: '基线快照 = 身份对应的公开标记文件',
    );
    expect(session.local.mastery, {1: LearningMastery.learning});
    expect(
      session.markersOnDisk,
      session.markers,
      reason: '在盘与否一并留下：镜像真值只认打开时已在盘的文档',
    );
  });

  test('建立序列·条目命中但摘要不符：身份取摘要、按新视频、旧条目保留', () async {
    final oldEntry = entryFor(videoId: 'hash-old');
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [oldEntry]),
    );
    final requested = <String>[];
    final session = sessionFor(
      indexStore: index,
      hasher: const FixedHasher('hash-new'),
      coordinatorFor: (videoId) {
        requested.add(videoId);
        return VideoDocumentCoordinator(InMemoryVideoDocumentStorage());
      },
    );

    await session.establish();

    expect(session.established, isTrue);
    expect(session.identity, OpenIdentityKind.contentChanged);
    expect(session.videoId, 'hash-new');
    expect(session.entry, isNull, reason: '不套用旧条目（登记的行为修正）');
    expect(requested, ['hash-new'], reason: '按新视频读新身份的两份文档');
    expect(index.current.findById('hash-old'), isNotNull, reason: '旧条目保留');
    expect(session.markers, const MarkersDocument.empty());
    expect(
      session.markersOnDisk,
      isNull,
      reason: '打开时不存在 → 不是镜像真值（首次导入的命名框首建不在此列）',
    );
  });

  test('建立序列·公开标记文件损坏不可读：在盘判据按无真值（null）', () async {
    final storage = InMemoryVideoDocumentStorage(
      markers: markersJson(),
      markersPresent: true,
    )..corruptMarkers();
    final session = sessionFor(
      indexStore: InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor()]),
      ),
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (_) => VideoDocumentCoordinator(storage),
    );

    await session.establish();

    expect(session.markers, const MarkersDocument.empty(), reason: '基线按空态');
    expect(session.markersOnDisk, isNull, reason: '损坏按无真值，走 index 路径');
  });

  test('建立序列·无条目：身份取摘要，按新视频语义且可落盘', () async {
    final storage = InMemoryVideoDocumentStorage();
    final requested = <String>[];
    final session = sessionFor(
      indexStore: InMemoryVideoIndexStorage(initial: VideoIndex.empty),
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (videoId) {
        requested.add(videoId);
        return VideoDocumentCoordinator(storage);
      },
    );

    await session.establish();

    expect(session.identity, OpenIdentityKind.newVideo);
    expect(session.videoId, kVideoId, reason: '身份取摘要（内容寻址）');
    expect(session.entry, isNull);
    expect(requested, [kVideoId]);

    // 可落盘：会话协调器写入即落到摘要寻址的文档——后台任务算出的身份与
    // 解析算出的必然相同，故此刻的写入与哈希落盘后的打开同址。
    await session.coordinator!.patchMarkers(
      (current) => current.withSegmentLines(const [
        SegmentLine(position: Duration(seconds: 30)),
      ]),
    );
    expect(
      storage.markersSnapshot['annotations']['segmentLines'],
      hasLength(1),
      reason: '无索引条目时仍可落盘',
    );
  });

  test('建立序列·索引不可读：按无条目语义（身份取摘要）', () async {
    final session = sessionFor(
      indexStore: ThrowingIndexStorage(),
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );

    await session.establish();

    expect(session.identity, OpenIdentityKind.newVideo);
    expect(session.videoId, kVideoId);
    expect(session.entry, isNull);
  });

  test('建立序列·摘要计算失败：不识别身份、不建写链（行为不变）', () async {
    final session = sessionFor(
      indexStore: InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor()]),
      ),
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );
    final failed = OpenSession(
      filePath: kFilePath,
      indexStore: InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor()]),
      ),
      hasher: const _ThrowingHasher(),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );

    await failed.establish();

    expect(failed.established, isTrue);
    expect(failed.videoId, isNull);
    expect(failed.identity, isNull);
    expect(failed.coordinator, isNull, reason: '无身份 → 无落盘目标');

    // 同一接缝的正常支不受影响。
    await session.establish();
    expect(session.videoId, kVideoId);
  });

  group('建立序列·含旧取景键的 v3 文件打开即复位', () {
    Future<(OpenSession, InMemoryVideoDocumentStorage)> establishWith({
      Map<String, dynamic> local = const {},
      Map<String, dynamic> markers = const {},
    }) async {
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor()]),
      );
      final storage = InMemoryVideoDocumentStorage(
        markers: Map<String, dynamic>.of(markers),
        local: local,
      );
      final session = sessionFor(
        indexStore: index,
        hasher: const FixedHasher(kVideoId),
        coordinatorFor: (videoId) => VideoDocumentCoordinator(storage),
      );
      await session.establish();
      return (session, storage);
    }

    test('v3 旧两键：取景不换算、不提升；打开不写公开标记文件', () async {
      final (session, storage) = await establishWith(
        local: {
          'version': 3,
          'prefs': {
            'framingSource': {'scale': 2.5, 'offsetX': 0.1, 'offsetY': -0.05},
            'framingPractice': {'scale': 1.5, 'offsetX': 0.2, 'offsetY': 0.3},
          },
        },
      );

      expect(session.markers.framingSelection, isNull, reason: '旧值不换算：按未调过打开');
      expect(storage.markersSnapshot, isEmpty, reason: 'meta 段不出现取景选区');
    });

    test('打开不迁移落盘：盘上 local 仍是 v3、旧键原样（迁移只在下一次写入生效）', () async {
      final (_, storage) = await establishWith(
        local: {
          'version': 3,
          'prefs': {
            'framingSource': {'scale': 2.5, 'offsetX': 0.0, 'offsetY': 0.0},
            'framingPractice': {'scale': 1.5, 'offsetX': 0.0, 'offsetY': 0.0},
          },
        },
      );

      expect(storage.localSnapshot['version'], 3);
      final prefs = storage.localSnapshot['prefs'] as Map;
      expect(prefs.containsKey('framingSource'), isTrue);
      expect(prefs.containsKey('framingPractice'), isTrue);
      expect(storage.markersSnapshot, isEmpty);
    });

    test('标记文件已有取景选区时按现值读入，不被旧本地键改写', () async {
      final (session, storage) = await establishWith(
        local: {
          'version': 3,
          'prefs': {
            'framingSource': {'scale': 2.5, 'offsetX': 0.0, 'offsetY': 0.0},
          },
        },
        markers: {
          'version': 9,
          'meta': {
            'framingSelection': {
              'left': 0.1,
              'top': 0.2,
              'right': 0.5,
              'bottom': 0.9,
            },
          },
        },
      );

      expect(
        session.markers.framingSelection,
        const FramingSelection(left: 0.1, top: 0.2, right: 0.5, bottom: 0.9),
      );
      expect((storage.markersSnapshot['meta'] as Map)['framingSelection'], {
        'left': 0.1,
        'top': 0.2,
        'right': 0.5,
        'bottom': 0.9,
      });
    });

    test('含旧取景字段的 v8 文件：打开即未调过、迁移只丢旧字段', () async {
      final (session, storage) = await establishWith(
        markers: {
          'version': 8,
          'meta': {
            'framingBand': {'top': 0.1, 'bottom': 0.5, 'centerX': 0.3},
          },
        },
      );

      expect(session.markers.framingSelection, isNull);
      expect(storage.markersSnapshot['version'], 8, reason: '打开不写回');
      expect((storage.markersSnapshot['meta'] as Map)['framingBand'], {
        'top': 0.1,
        'bottom': 0.5,
        'centerX': 0.3,
      }, reason: '打开动作不写盘，迁移只在下一次写回生效');
    });

    test('无旧键：打开照常、不写盘', () async {
      final (session, storage) = await establishWith(local: localJson());
      expect(session.established, isTrue);
      expect(session.markers.framingSelection, isNull);
      expect(storage.markersSnapshot, isEmpty);
    });
  });
}

class _ThrowingHasher implements ContentHasher {
  const _ThrowingHasher();

  @override
  Future<String> hashFile(File file) async => throw StateError('hash failed');
}
