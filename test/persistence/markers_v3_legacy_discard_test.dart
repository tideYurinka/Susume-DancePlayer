import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 低于地板的旧标记文件验收：地板 7 之下的 v3／v4 文件读到
/// 空态（唯一合法的读空），且只读——随后一次编辑不改盘、原文一字不动。
/// 真实文件 + 内存 fake 双跑。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('markers_v3_discard');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  VideoDocumentStorage makeReal() => AtomicVideoDocumentStorage(
    markersFile: File(p.join(tempDir.path, 'markers_abc.json')),
    localFile: File(p.join(tempDir.path, 'local_abc.json')),
  );

  Future<Map<String, dynamic>> readRaw(VideoDocumentStorage storage) async {
    if (storage is AtomicVideoDocumentStorage) {
      return jsonDecode(
        await File(p.join(tempDir.path, 'markers_abc.json')).readAsString(),
      ) as Map<String, dynamic>;
    }
    return (storage as InMemoryVideoDocumentStorage).markersSnapshot;
  }

  /// v3 老文件：版本头 3 + meta/corrections/annotations/notes/roster
  /// 五段（notes 段含 `refs` 键——v4 起不再被解释）。
  const v3File = <String, dynamic>{
    'version': 3,
    'meta': {'mirrored': true, 'localMirrorEnabled': false},
    'corrections': {'shift': 0.25},
    'annotations': {
      'range': {'startMs': 1000, 'endMs': 200000},
      'segmentLines': [
        {'timeMs': 4200, 'flag': true},
      ],
      'halfBeatLines': [
        {'timeMs': 100},
      ],
      'emphasizedSegments': [0, 1],
      'localMirrorFragments': [
        {'startMs': 1000, 'endMs': 3000, 'enabled': true},
      ],
    },
    'notes': {
      'notes': [
        {
          'startMs': 1000,
          'endMs': 3000,
          'text': '@果果 注意',
          'refs': [
            {'name': '果果', 'start': 0, 'length': 2, 'occurrence': 0},
          ],
        },
      ],
    },
    'roster': {
      'roster': [
        {'name': '果果', 'color': 0xFFFFD54F},
      ],
    },
    'beat': {
      'model': 'm.onnx',
      'fps': 100,
      'generatedAt': '2026-09-10T00:00:00.000Z',
      'shift': 0.25,
      'anchors': [4, 12],
      'beats': [
        {'t': 0.5, 'down': true},
      ],
    },
  };

  /// v4 老文件：版本头 4 + 备注/名册段（notes 段含 `style` 键——v5 起
  /// 不再被解释）。
  const v4File = <String, dynamic>{
    'version': 4,
    'meta': {'mirrored': true},
    'annotations': {
      'range': {'startMs': 1000, 'endMs': 200000},
      'segmentLines': [
        {'timeMs': 4200, 'flag': true},
      ],
    },
    'notes': {
      'notes': [
        {
          'startMs': 1000,
          'endMs': 3000,
          'text': '@果果 注意',
          'style': {'color': 4278255360, 'outline': false},
        },
      ],
    },
    'roster': {
      'roster': [
        {'name': '果果', 'color': 0xFFFFD54F},
      ],
    },
  };

  const legacyFiles = {'v3': v3File, 'v4': v4File};

  for (final (label, make) in [
    ('真实文件', makeReal),
    ('内存 fake', () => InMemoryVideoDocumentStorage()),
  ]) {
    group(label, () {
      for (final entry in legacyFiles.entries) {
        test('${entry.key} 低于地板：读到空态、只读——编辑不改盘', () async {
          final storage = make();
          await storage.saveMarkers(Map<String, dynamic>.of(entry.value));

          // 打开：读到空态——分段线/半拍线/重点段/锚点/节拍对齐/片段/
          // 备注/名册全无。
          final coordinator = VideoDocumentCoordinator(storage);
          final opened = await coordinator.readMarkers();
          expect(opened, const MarkersDocument.empty());
          expect(opened.segmentLines, isEmpty);
          expect(opened.halfBeatLines, isEmpty);
          expect(opened.localMirrorFragments, isEmpty);
          expect(opened.notes, isEmpty);
          expect(opened.roster, isEmpty);
          expect(opened.beat, isNull);
          expect(
            MarkersDocument.versionPolicy.isWritable(entry.value),
            isFalse,
          );

          // 随后一次编辑：不改盘、原文一字不动。
          await coordinator.patchMarkers(
            (doc) => doc.withSegmentLines(const [
              SegmentLine(position: Duration(milliseconds: 5000)),
            ]),
          );
          expect(await readRaw(storage), entry.value, reason: '盘上原文一字未动');
        });
      }
    });
  }
}
