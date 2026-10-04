import 'dart:io';

import 'package:dance_learning_app/annotation/dancer_roster.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 持久化 seam 直测：markers 顶层 `roster` 段的段声明 + 编解码 + 往返。
/// 覆盖：全字段往返逐位一致、缺段空兜底、段内/元素级未知键
/// 透传、空名册不写段键、`withRoster` 只触碰名册段、真实文件 + 内存
/// fake 双跑（重开还原）。
void main() {
  const roster = [
    DancerRosterEntry(name: '果', color: 0xFFE53935),
    DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
  ];

  group('markers 顶层 roster 段（内存模型）', () {
    test('名册全字段往返逐位一致', () {
      const doc = MarkersDocument(roster: roster);
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.roster, roster);
      expect(restored.roster.first.name, '果');
      expect(restored.roster.first.color, 0xFFE53935);
    });

    test('缺 roster 段的旧文件按空读取、不崩', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': false},
      });
      expect(doc.roster, isEmpty);
    });

    test('空名册不写段键', () {
      const doc = MarkersDocument();
      expect(doc.toJson().containsKey('roster'), isFalse);
    });

    test('段内与元素级未知键透传保留，且不覆盖已登记字段', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'roster': {
          'dancers': [
            {'name': '果', 'color': 4278190325, 'entryReserved': 7},
          ],
          'sectionReserved': {'future': 1},
        },
      });
      expect(doc.roster, const [
        DancerRosterEntry(name: '果', color: 4278190325),
      ]);
      final json = doc.toJson();
      expect(json['roster']['sectionReserved'], {'future': 1});
      expect(json['roster']['dancers'].single['entryReserved'], 7);
      expect(json['roster']['dancers'].single['name'], '果');
    });

    test('损坏条目按缺省兜底不崩溃，合法项保留', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'roster': {
          'dancers': [
            'bad',
            42,
            {'name': '果'},
            {'color': 0xFF1E88E5},
            {'name': '鸟', 'color': 0xFF1E88E5},
          ],
        },
      });
      expect(doc.roster, const [
        DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
      ]);
    });

    test('withRoster 整表补写只触碰名册段，notes / beat / corrections 原样', () {
      const note = NoteSticker(startMs: 8000, endMs: 16000, text: '这里注意手');
      final base = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': true},
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'generatedAt': '2026-01-01T00:00:00.000Z',
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
        'corrections': {
          'shift': 0.25,
          'anchors': [4],
        },
      }).withNotes(const [note]);
      final next = base.withRoster(roster);
      expect(next.roster, roster);
      expect(next.notes, const [note]);
      expect(next.beat, base.beat);
      expect(next.mirrored, isTrue);
      expect(next.rangeStartMs, base.rangeStartMs);
    });

    test('名册参与相等判定（净变化判定不漏）', () {
      expect(
        const MarkersDocument(roster: roster),
        isNot(const MarkersDocument()),
      );
      expect(
        const MarkersDocument(roster: roster),
        const MarkersDocument(roster: roster),
      );
    });
  });

  group('markers/协调器：roster 段持久化（真实文件 + 内存 fake 双跑）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('roster_markers');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    VideoDocumentStorage makeReal(Directory dir) => AtomicVideoDocumentStorage(
      markersFile: File(p.join(dir.path, 'markers_abc.json')),
      localFile: File(p.join(dir.path, 'local_abc.json')),
    );

    final fakeStorage = InMemoryVideoDocumentStorage();

    for (final (label, make) in [
      ('真实文件', makeReal),
      // 内存 fake 两个协调器须共享同一存储才能模拟「重开同一文件」。
      ('内存 fake', (Directory _) => fakeStorage),
    ]) {
      test('$label：整表补写落盘，重开按名册还原一致', () async {
        final coordinator = VideoDocumentCoordinator(make(tempDir));
        await coordinator.patchMarkers((doc) => doc.withRoster(roster));
        // 重开：新协调器从同一文件读回。
        final reopened = VideoDocumentCoordinator(make(tempDir));
        final restored = await reopened.readMarkers();
        expect(restored.roster, roster);
      });
    }
  });
}
