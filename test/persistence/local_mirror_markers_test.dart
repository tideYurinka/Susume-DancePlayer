import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 持久化 seam 直测：`annotations.localMirrorFragments` 字段往返、缺省空
/// 兜底、未知键 extra 透传（真实文件 + 内存 fake 双跑，仿
/// `video_document_coordinator_test.dart` 先例）。
void main() {
  group('MarkersDocument：localMirrorFragments typed 字段（内存模型）', () {
    test('typed 字段往返保真', () {
      const doc = MarkersDocument(
        localMirrorFragments: [
          LocalMirrorFragment(startMs: 1000, endMs: 3000),
          LocalMirrorFragment(startMs: 5000, endMs: 7000),
        ],
      );
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.localMirrorFragments, doc.localMirrorFragments);
      // typed 键读回时不回退进 extra。
      expect(restored.extra.containsKey('localMirrorFragments'), isFalse);
    });

    test('缺省（无该键）读为空列表', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': false},
      });
      expect(doc.localMirrorFragments, isEmpty);
      // 键入片段时参与相等/净变化判定。
      expect(
        doc,
        isNot(
          const MarkersDocument(
            localMirrorFragments: [
              LocalMirrorFragment(startMs: 1000, endMs: 3000),
            ],
          ),
        ),
      );
    });

    test('损坏条目按缺省兜底不崩溃，合法项保留', () {
      final doc = MarkersDocument.fromJson({
        'version': 8,
        'annotations': {
          'localMirrorFragments': [
            'bad',
            42,
            {'startMs': 1.5, 'endMs': 9},
            {'startMs': 1000, 'endMs': 3000, 'enabled': false},
          ],
        },
      });
      expect(doc.localMirrorFragments, const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
      ]);
    });

    test('withLocalMirrorFragments 补写不丢其它字段', () {
      const doc = MarkersDocument(mirrored: true, rangeStartMs: 100);
      final next = doc.withLocalMirrorFragments(const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
      ]);
      expect(next.mirrored, isTrue);
      expect(next.rangeStartMs, 100);
      expect(next.localMirrorFragments.length, 1);
    });

    test('写入恒为当前 schema 版本；typed 键不回退进 extra', () {
      const doc = MarkersDocument(
        localMirrorFragments: [LocalMirrorFragment(startMs: 1000, endMs: 3000)],
      );
      final json = doc.toJson();
      expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
      expect(json['annotations']['localMirrorFragments'], isNotNull);
    });

    test('unknown 键走既有 extra 透传，写回原样保留且 typed 键不重复进 extra', () {
      final json = <String, dynamic>{
        'version': 8,
        'meta': {'mirrored': true},
        'p1Reserved': {'future': true},
        'annotations': {
          'localMirrorFragments': [
            {'startMs': 1000, 'endMs': 3000, 'enabled': true},
          ],
        },
      };
      final doc = MarkersDocument.fromJson(json);
      expect(doc.localMirrorFragments, const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
      ]);
      expect(doc.extra['p1Reserved'], {'future': true});
      final written = doc.toJson();
      expect(written['p1Reserved'], {'future': true});
      expect(written['meta']['mirrored'], isTrue);
      // 遗留 enabled 键不被解释、走保底区写回原样（不再有登记字段）。
      expect(written['annotations']['localMirrorFragments'].single['enabled'],
          isTrue);
    });
  });

  group('MarkersDocument/协调器：typed 字段持久化（真实文件 + 内存 fake 双跑）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('local_mirror_markers');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    VideoDocumentStorage makeReal(Directory dir) => AtomicVideoDocumentStorage(
      markersFile: File(p.join(dir.path, 'markers_abc.json')),
      localFile: File(p.join(dir.path, 'local_abc.json')),
    );

    for (final (label, make) in [
      ('真实文件', makeReal),
      ('内存 fake', (Directory dir) => InMemoryVideoDocumentStorage()),
    ]) {
      group(label, () {
        test('写入 localMirrorFragments 后其它段与 extra 不丢、版本恒为当前 schema 版本', () async {
          final storage = make(tempDir);
          final coordinator = VideoDocumentCoordinator(storage);
          await coordinator.patchMarkers(
            (doc) => doc
                .withMirrored(true)
                .withSegmentLines(const [
                  SegmentLine(position: Duration(milliseconds: 4200)),
                ])
                .withLocalMirrorFragments(const [
                  LocalMirrorFragment(startMs: 1000, endMs: 3000),
                ]),
          );

          // 注入一个本版本不认识的保留键（模拟其它未来字段走 extra）。
          await _seedUnknownKey(storage, tempDir, 'p1Reserved', {
            'future': true,
          });

          // 再写一次 typed 字段，确认既有关键与 extra 都被保回。
          await coordinator.patchMarkers(
            (doc) => doc.withLocalMirrorFragments(const [
              LocalMirrorFragment(startMs: 1000, endMs: 3000),
            ]),
          );

          final json = await _readRawMarkers(storage, tempDir);
          expect(json['version'], MarkersDocument.versionPolicy.currentVersion);
          expect(json['meta']['mirrored'], true);
          expect(json['annotations']['segmentLines'], [
            {'timeMs': 4200, 'flag': false},
          ]);
          expect(json['annotations']['localMirrorFragments'], [
            {'startMs': 1000, 'endMs': 3000},
          ]);
          expect(json['p1Reserved'], {'future': true});

          final doc = await coordinator.readMarkers();
          expect(doc.localMirrorFragments, const [
            LocalMirrorFragment(startMs: 1000, endMs: 3000),
          ]);
          expect(doc.extra['p1Reserved'], {'future': true});
        });

        test('缺省（文件无 localMirrorFragments 键）读为空列表，typed 不落 extra', () async {
          final storage = make(tempDir);
          await storage.saveMarkers(const {
            'version': 8,
            'meta': {'mirrored': true},
          });
          final doc = await VideoDocumentCoordinator(storage).readMarkers();
          expect(doc.localMirrorFragments, isEmpty);
          expect(doc.mirrored, isTrue);
          expect(doc.extra.containsKey('localMirrorFragments'), isFalse);
        });
      });
    }
  });
}

Future<void> _seedUnknownKey(
  VideoDocumentStorage storage,
  Directory dir,
  String key,
  Object value,
) async {
  if (storage is AtomicVideoDocumentStorage) {
    final file = File(p.join(dir.path, 'markers_abc.json'));
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    json[key] = value;
    await file.writeAsString(jsonEncode(json));
  } else {
    final json = (storage as InMemoryVideoDocumentStorage).markersSnapshot;
    json[key] = value;
    await storage.saveMarkers(json);
  }
}

Future<Map<String, dynamic>> _readRawMarkers(
  VideoDocumentStorage storage,
  Directory dir,
) async {
  if (storage is AtomicVideoDocumentStorage) {
    return jsonDecode(
      await File(p.join(dir.path, 'markers_abc.json')).readAsString(),
    ) as Map<String, dynamic>;
  }
  return (storage as InMemoryVideoDocumentStorage).markersSnapshot;
}
