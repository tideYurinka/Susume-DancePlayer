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
import 'package:path/path.dart' as p;

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

/// 真实副本文件：兜底定身份要按副本读大小与文件名，故补建条目场景用真文件
/// （摘要本身仍由桩给出）。
Future<File> writeTempVideo({int sizeBytes = 16}) async {
  final directory = await Directory.systemTemp.createTemp('open_session_test');
  addTearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  final file = File(p.join(directory.path, 'a.mp4'));
  await file.writeAsBytes(List<int>.filled(sizeBytes, 7));
  return file;
}

void main() {
  test('建立序列·条目命中：身份取条目、读该身份两份文档为基线，全程不读视频内容', () async {
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
      // 一调用就失败：打开路径触发任何内容摘要都判失败（不读整片的证伪手段）。
      hasher: const _ThrowingHasher(),
      coordinatorFor: (videoId) {
        requested.add(videoId);
        return VideoDocumentCoordinator(storage);
      },
    );

    await session.establish();

    expect(session.established, isTrue);
    expect(session.identity, OpenIdentityKind.entryHit);
    expect(session.videoId, kVideoId);
    expect(session.entry, isNotNull);
    expect(requested, [kVideoId], reason: '文档按条目身份寻址');
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
    expect(
      index.current.findByFilePath(kFilePath),
      entryFor(),
      reason: '命中条目的打开路径不写索引',
    );
  });

  test('建立序列·条目命中而内容已变：身份仍取条目（打开不再校验相符）', () async {
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [entryFor()]),
    );
    final session = sessionFor(
      indexStore: index,
      // 摘要会给出另一个身份：打开路径若还拿它校验，本条就会落空。
      hasher: const FixedHasher('hash-new'),
      coordinatorFor: (_) => VideoDocumentCoordinator(
        InMemoryVideoDocumentStorage(markers: markersJson()),
      ),
    );

    await session.establish();

    expect(session.identity, OpenIdentityKind.entryHit);
    expect(session.videoId, kVideoId, reason: '身份取条目，不算摘要、也不比对');
    expect(session.entry, isNotNull);
    expect(
      session.markers.segmentLines,
      hasLength(1),
      reason: '条目身份不变 → 这支舞的旧标注照常加载',
    );
    expect(index.current.findById('hash-new'), isNull, reason: '不按摘要建条目');
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

  test('建立序列·按路径无条目：兜底算一次摘要定身份，并按它补建条目', () async {
    final video = await writeTempVideo();
    final index = InMemoryVideoIndexStorage(initial: VideoIndex.empty);
    final storage = InMemoryVideoDocumentStorage();
    final requested = <String>[];
    final session = OpenSession(
      filePath: video.path,
      indexStore: index,
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (videoId) {
        requested.add(videoId);
        return VideoDocumentCoordinator(storage);
      },
      now: () => DateTime(2026, 9, 2),
    );

    await session.establish();

    expect(session.identity, OpenIdentityKind.fallbackHash);
    expect(session.videoId, kVideoId, reason: '身份取兜底算出的摘要（内容寻址）');
    expect(requested, [kVideoId]);
    final created = index.current.findByFilePath(video.path);
    expect(created, isNotNull, reason: '兜底定身份后补建条目：下次打开不再兜底');
    expect(created!.videoId, kVideoId);
    expect(created.displayName, 'a.mp4');
    expect(created.filePath, video.path);
    expect(created.sizeBytes, 16);
    expect(
      created.fastKey,
      fastKeyFor(name: 'a.mp4', sizeBytes: 16),
      reason: '快速键按副本现算，导入对账据此识别同一支舞',
    );
    expect(created.lastOpenedAt, DateTime(2026, 9, 2));
    expect(created.mirrorAsked, isFalse, reason: '补建条目不假装用户答过镜像');

    // 可落盘：会话协调器写入即落到摘要寻址的文档——兜底算出的身份与此后
    // 任何一次打开必然相同，故此刻的写入与条目落盘后的打开同址。
    await session.coordinator!.patchMarkers(
      (current) => current.withSegmentLines(const [
        SegmentLine(position: Duration(seconds: 30)),
      ]),
    );
    expect(
      storage.markersSnapshot['annotations']['segmentLines'],
      hasLength(1),
      reason: '兜底定身份后仍可落盘',
    );
  });

  test('建立序列·兜底补建后再打开同一支舞：按路径命中、不再兜底', () async {
    final video = await writeTempVideo();
    final index = InMemoryVideoIndexStorage(initial: VideoIndex.empty);
    final first = OpenSession(
      filePath: video.path,
      indexStore: index,
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );
    await first.establish();
    expect(first.identity, OpenIdentityKind.fallbackHash);

    // 同一支舞再打开：索引里已有条目 → 按路径命中；摘要一调用就失败也不影响。
    final again = OpenSession(
      filePath: video.path,
      indexStore: index,
      hasher: const _ThrowingHasher(),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );
    await again.establish();

    expect(again.identity, OpenIdentityKind.entryHit);
    expect(again.videoId, kVideoId);
    expect(again.entry, index.current.findByFilePath(video.path));
  });

  test('建立序列·索引不可读：按无条目语义兜底定身份，补建写失败不阻塞打开', () async {
    final session = sessionFor(
      indexStore: ThrowingIndexStorage(),
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );

    await session.establish();

    expect(session.established, isTrue);
    expect(session.identity, OpenIdentityKind.fallbackHash);
    expect(session.videoId, kVideoId);
  });

  test('建立序列·副本不在：兜底读不到内容 → 无身份空态、不补建条目', () async {
    final index = InMemoryVideoIndexStorage(initial: VideoIndex.empty);
    final session = OpenSession(
      filePath: '/videos/missing.mp4',
      indexStore: index,
      // 真读一遍副本：副本不在即抛错（与真实摘要计算的失败面同款）。
      hasher: const _FileReadingHasher(),
      coordinatorFor: (_) =>
          VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
    );

    await session.establish();

    expect(session.established, isTrue);
    expect(session.videoId, isNull);
    expect(session.identity, isNull);
    expect(session.coordinator, isNull, reason: '无身份 → 无落盘目标');
    expect(index.current.entries, isEmpty, reason: '兜底失败不补建条目');
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

/// 真读副本文件的摘要桩：副本不在时与真实摘要计算同款抛错（大小即伪摘要）。
class _FileReadingHasher implements ContentHasher {
  const _FileReadingHasher();

  @override
  Future<String> hashFile(File file) async {
    var total = 0;
    await for (final chunk in file.openRead()) {
      total += chunk.length;
    }
    return 'digest-$total';
  }
}
