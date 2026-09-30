import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_document_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// 真实文件与内存 fake 双跑同一用例体。
  VideoDocumentStorage makeReal(Directory dir) => AtomicVideoDocumentStorage(
        markersFile: File(p.join(dir.path, 'markers_abc.json')),
        localFile: File(p.join(dir.path, 'local_abc.json')),
      );

  for (final (label, make) in [
    ('真实文件', makeReal),
    ('内存 fake', (Directory dir) => InMemoryVideoDocumentStorage()),
  ]) {
    group(label, () {
      test('缺失文件读空态，不崩溃', () async {
        final coordinator = VideoDocumentCoordinator(make(tempDir));
        expect(await coordinator.readMarkers(), const MarkersDocument.empty());
        expect(await coordinator.readLocal(), const LocalDocument.empty());
      });

      test('损坏文件读空态，不崩溃', () async {
        final storage = make(tempDir);
        if (storage is AtomicVideoDocumentStorage) {
          await File(p.join(tempDir.path, 'markers_abc.json'))
              .writeAsString('{not json');
          await File(p.join(tempDir.path, 'local_abc.json'))
              .writeAsString('[1, 2]');
        } else {
          await (storage as InMemoryVideoDocumentStorage)
              .saveMarkers(const {'broken': true});
        }
        final coordinator = VideoDocumentCoordinator(storage);
        expect(await coordinator.readMarkers(), const MarkersDocument.empty());
      });

      test('patch markers 落盘并可读回', () async {
        final coordinator = VideoDocumentCoordinator(make(tempDir));
        await coordinator.patchMarkers(
          (doc) => doc.withSegmentLines(const [
            SegmentLine(position: Duration(milliseconds: 4200), flagged: true),
          ]),
        );
        final doc = await coordinator.readMarkers();
        expect(doc.segmentLines, [
          const SegmentLine(
            position: Duration(milliseconds: 4200),
            flagged: true,
          ),
        ]);
      });

      test('并发 patch 不同字段互不覆盖（串行链无 lost-update）', () async {
        final coordinator = VideoDocumentCoordinator(make(tempDir));
        await Future.wait([
          coordinator.patchMarkers(
            (doc) => doc.withMirrored(true),
          ),
          coordinator.patchMarkers(
            (doc) => doc.withSignature(
              const SongSignature(song: 'My Love'),
            ),
          ),
          coordinator.patchLocal(
            (doc) => doc.withMastery(0, LearningMastery.mastered),
          ),
          coordinator.patchLocal(
            (doc) => doc.withLayoutLocked(true),
          ),
        ]);
        expect((await coordinator.readMarkers()).mirrored, true);
        expect(
          (await coordinator.readMarkers()).signature?.song,
          'My Love',
        );
        expect(
          (await coordinator.readLocal()).mastery,
          {0: LearningMastery.mastered},
        );
        expect((await coordinator.readLocal()).layoutLocked, true);
      });

      test('两个写者共用一个文件：交错写不丢字段（每次写入都是原子读改写）', () async {
        final storage = make(tempDir);
        // 打开会话与舞库管理写各持一个协调器（两个写者），但共用同一份文件
        // 存取实例——序列化必须落在存取上，否则后写的一方把另一方的字段
        // 退回上一版。
        final sessionWriter = VideoDocumentCoordinator(storage);
        final libraryWriter = VideoDocumentCoordinator(storage);
        await Future.wait([
          sessionWriter.patchMarkers((doc) => doc.withMirrored(true)),
          libraryWriter.patchMarkers(
            (doc) => doc.withSignature(const SongSignature(song: 'My Love')),
          ),
        ]);

        final doc = await sessionWriter.readMarkers();
        expect(doc.mirrored, isTrue, reason: '另一写者的字段不得被退回上一版');
        expect(doc.signature?.song, 'My Love');
      });

      test('两个写者交错写 local：mastery 与布局锁两字段都存活', () async {
        final storage = make(tempDir);
        final sessionWriter = VideoDocumentCoordinator(storage);
        final settingsWriter = VideoDocumentCoordinator(storage);
        await Future.wait([
          sessionWriter.patchLocal(
            (doc) => doc.withMastery(0, LearningMastery.mastered),
          ),
          settingsWriter.patchLocal((doc) => doc.withLayoutLocked(true)),
        ]);

        final doc = await sessionWriter.readLocal();
        expect(doc.mastery, {0: LearningMastery.mastered});
        expect(doc.layoutLocked, isTrue);
      });

      test('串行链内后一次 patch 读到前一次结果', () async {
        final coordinator = VideoDocumentCoordinator(make(tempDir));
        await coordinator.patchMarkers(
          (doc) => doc.withRange(startMs: 100, endMs: 900),
        );
        await coordinator.patchMarkers(
          (doc) {
            expect(doc.rangeStartMs, 100);
            return doc.withRange(startMs: 200, endMs: 900);
          },
        );
        expect((await coordinator.readMarkers()).rangeStartMs, 200);
      });

      test('delete：两份文档一并删除、读回空态；重复删除不抛错', () async {
        final storage = make(tempDir);
        await storage.saveMarkers(const {'version': 1});
        await storage.saveLocal(const {'version': 1});

        await storage.delete();

        expect(await storage.loadMarkers(), isEmpty);
        expect(await storage.loadLocal(), isEmpty);
        expect(await storage.loadMarkersOrNull(), isNull);
        if (storage is AtomicVideoDocumentStorage) {
          expect(
            File(p.join(tempDir.path, 'markers_abc.json')).existsSync(),
            isFalse,
          );
          expect(
            File(p.join(tempDir.path, 'local_abc.json')).existsSync(),
            isFalse,
          );
        }
        await storage.delete(); // 已删：不抛错。
      });

      test('文件里未知扩展字段在 patch 后保留', () async {
        final storage = make(tempDir);
        final coordinator = VideoDocumentCoordinator(storage);
        await coordinator.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        if (storage is AtomicVideoDocumentStorage) {
          final file = File(p.join(tempDir.path, 'markers_abc.json'));
          final json =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          json['p1Reserved'] = {'future': true};
          await file.writeAsString(jsonEncode(json));
        } else {
          final json = (storage as InMemoryVideoDocumentStorage)
              .markersSnapshot
            ..['p1Reserved'] = {'future': true};
          await storage.saveMarkers(json);
        }

        await coordinator.patchMarkers(
          (doc) => doc.withEmphasizedSegments([0]),
        );
        final json = await _readRawMarkers(storage, tempDir);
        expect(json['p1Reserved'], {'future': true});
        expect(json['meta']['mirrored'], true);
        expect(json['annotations']['emphasizedSegments'], [0]);
      });

      test('低于地板（markers v6）按空态读、只读不写回（地板下唯一合法读空）', () async {
        final storage = make(tempDir);
        const belowFloor = <String, dynamic>{'version': 6, 'mirrored': true};
        await storage.saveMarkers(Map<String, dynamic>.of(belowFloor));
        final coordinator = VideoDocumentCoordinator(storage);
        expect(await coordinator.readMarkers(), const MarkersDocument.empty());
        await coordinator.patchMarkers(
          (doc) => doc.withRange(startMs: 0, endMs: 10),
        );
        expect(await _readRawMarkers(storage, tempDir), belowFloor);
      });

      test('更高版本按认识多少读多少打开、本机不写回', () async {
        final storage = make(tempDir);
        const forward = <String, dynamic>{
          'version': 99,
          'meta': {'mirrored': true},
          'metaReserved': {'newer': true},
        };
        await storage.saveMarkers(Map<String, dynamic>.of(forward));
        final coordinator = VideoDocumentCoordinator(storage);
        // 认识的段与字段照读。
        expect((await coordinator.readMarkers()).mirrored, isTrue);
        // patch 不产生写盘：文件保持高版本原样（含陌生键）。
        await coordinator.patchMarkers(
          (doc) => doc.withRange(startMs: 0, endMs: 10),
        );
        expect(await _readRawMarkers(storage, tempDir), forward);
      });

      test('patch 无变化时不重写文件', () async {
        final storage = make(tempDir);
        final coordinator = VideoDocumentCoordinator(storage);
        await coordinator.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        final before = await _readRawMarkers(storage, tempDir);
        await coordinator.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        expect(await _readRawMarkers(storage, tempDir), before);
      });

      test('readMarkersOrNull：缺失 null，落盘后读回文档', () async {
        final coordinator = VideoDocumentCoordinator(make(tempDir));
        expect(await coordinator.readMarkersOrNull(), isNull);
        await coordinator.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        expect(
          (await coordinator.readMarkersOrNull())?.mirrored,
          isTrue,
        );
      });

      test('readMarkersOrNull：损坏文件返回 null（首建判定依据）', () async {
        final storage = make(tempDir);
        if (storage is AtomicVideoDocumentStorage) {
          await File(p.join(tempDir.path, 'markers_abc.json'))
              .writeAsString('{not json');
        } else {
          (storage as InMemoryVideoDocumentStorage).corruptMarkers();
        }
        final coordinator = VideoDocumentCoordinator(storage);
        expect(await coordinator.readMarkersOrNull(), isNull);
      });

      test('markers 与 local 各自单一实例：两文件内容互不串', () async {
        final storage = make(tempDir);
        final coordinator = VideoDocumentCoordinator(storage);
        await coordinator.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        await coordinator.patchLocal(
          (doc) => doc.withLayoutLocked(true),
        );
        final markersJson = await _readRawMarkers(storage, tempDir);
        final localCoordinator = VideoDocumentCoordinator(storage);
        expect((await localCoordinator.readMarkers()).mirrored, true);
        expect((await localCoordinator.readLocal()).layoutLocked, true);
        expect(markersJson.containsKey('layoutLocked'), isFalse);
      });
    });
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
