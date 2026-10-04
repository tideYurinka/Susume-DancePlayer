import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/document_codec.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// 持久化 seam 直测：markers 顶层 `notes` 段的段声明 + 编解码 + 往返
/// （起 `notes` 段无 `style` 键）。
/// 覆盖：全字段往返、新写出的元素不含 `style` 键、缺段空兜底、段内/元素/
/// 文档级未知键透传、旧同版本 reader 回放安全、v3 / v4 低于地板按空态
/// 读出且只读、本版版本号不变、备注不触碰 `beat` / `corrections` 段。
void main() {
  const note = NoteSticker(
    startMs: 8000,
    endMs: 16000,
    text: '这里注意手',
    locked: true,
    geometry: NoteGeometry(centerX: 0.4, centerY: 0.2, scale: 1.5),
  );

  group('markers 顶层 notes 段', () {
    test('备注全字段往返逐位一致', () {
      const doc = MarkersDocument(notes: [note]);
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.notes, [note]);
      expect(restored.notes.first.startMs, 8000);
      expect(restored.notes.first.endMs, 16000);
      expect(restored.notes.first.text, '这里注意手');
      expect(restored.notes.first.locked, isTrue);
      expect(restored.notes.first.geometry.centerX, 0.4);
      expect(restored.notes.first.geometry.centerY, 0.2);
      expect(restored.notes.first.geometry.scale, 1.5);
      // 点名信息只在 text 里、样式是派生值没有字段：
      // 新写出的元素不含 `refs` / `style` 键。
      expect(note.toJson().containsKey('refs'), isFalse);
      expect(note.toJson().containsKey('style'), isFalse);
    });

    test('缺 notes 段的旧文件按空读取、不崩', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'meta': {'mirrored': false},
      });
      expect(doc.notes, isEmpty);
    });

    test('版本链本版（v9）', () {
      expect(MarkersDocument.versionPolicy.currentVersion, 9);
      const doc = MarkersDocument(notes: [note]);
      expect(doc.toJson()['version'], 9);
    });

    test('v4 文件整份按空态丢弃（不崩、不部分解析；升 v5 的安全网）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 4,
        'meta': {'mirrored': true},
        'notes': {
          'notes': [
            {
              'startMs': 8000,
              'endMs': 16000,
              'text': '@果果 注意',
              'style': {'color': 4278255360, 'outline': false},
            },
          ],
        },
        'roster': {'roster': []},
      });
      expect(doc, const MarkersDocument.empty());
      expect(doc.notes, isEmpty);
      expect(doc.mirrored, isFalse);
    });

    test('v3 老文件整份按空态丢弃（不崩、不部分解析）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 3,
        'meta': {'mirrored': true},
        'notes': {
          'notes': [
            {
              'startMs': 8000,
              'endMs': 16000,
              'text': '@果果 注意',
              'refs': [
                {'name': '果果', 'start': 0, 'length': 2, 'occurrence': 0},
              ],
            },
          ],
        },
        'roster': {'roster': []},
      });
      expect(doc, const MarkersDocument.empty());
      expect(doc.notes, isEmpty);
      expect(doc.mirrored, isFalse);
    });

    test('段内与元素级未知键透传保留，且不覆盖已登记字段', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'notes': {
          'notes': [
            {
              'startMs': 8000,
              'endMs': 16000,
              'text': '这里注意手',
              'style': {'color': 4278255360, 'outline': false},
              'locked': true,
              'geometry': {'centerX': 0.4, 'centerY': 0.2, 'scale': 1.5},
              'refs': [],
              'elementReserved': {'future': true},
            },
          ],
          'sectionReserved': {'future': 1},
        },
      });
      final json = doc.toJson();
      // 段内未知键原样写回。
      expect(json['notes']['sectionReserved'], {'future': 1});
      // 元素级未知键原样写回，且已登记字段不被覆盖。
      final element = json['notes']['notes'].single as Map<String, Object?>;
      expect(element['elementReserved'], {'future': true});
      expect(element['startMs'], 8000);
      expect(element['locked'], isTrue);
    });

    test('文档级未知键透传保留', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'docReserved': {'future': true},
      });
      expect(doc.extra['docReserved'], {'future': true});
      expect(doc.toJson()['docReserved'], {'future': true});
    });

    test('损坏条目按缺省兜底不崩溃，合法项保留', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'notes': {
          'notes': [
            'bad',
            42,
            {'endMs': 16000},
            {'startMs': 8000, 'endMs': 16000, 'text': 'ok'},
          ],
        },
      });
      expect(doc.notes.length, 1);
      expect(doc.notes.single.startMs, 8000);
      expect(doc.notes.single.text, 'ok');
      expect(doc.notes.single.locked, isFalse);
    });

    test('旧同版本 reader 回放后 notes 段仍在（顶层新增键安全路径）', () {
      // 模拟不认识 `notes` 键的旧同版本 reader：其已知键集 = version +
      // 既有四段；顶层未知键落文档级保底区、回写先展开（不会被后写的
      // 已登记键覆盖）。回放后 notes 键对 v3 新 reader 完整可读。
      final written = const MarkersDocument(notes: [note]).toJson();
      final replayedByLegacy = _legacyReaderRewrite(written);
      expect(replayedByLegacy.containsKey('notes'), isTrue);
      final reread = MarkersDocument.fromJson(replayedByLegacy);
      expect(reread.notes, [note]);
    });

    test('真实文件路径全字段往返逐位一致', () async {
      final dir = await Directory.systemTemp.createTemp('note_sticker_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/markers_abc.json');
      const doc = MarkersDocument(notes: [note]);
      await file.writeAsString(jsonEncode(doc.toJson()));
      final restored = MarkersDocument.fromJson(
        Map<String, Object?>.from(jsonDecode(await file.readAsString()) as Map),
      );
      expect(restored, doc);
      expect(restored.notes, const [note]);
    });

    test('withNotes 补写不触碰 beat / corrections 段', () {
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
      });
      final next = base.withNotes(const [note]);
      expect(next.notes, const [note]);
      // beat + corrections 装配的网格原样保留。
      expect(next.beat, base.beat);
      expect(next.beat?.shift, 0.25);
      expect(next.beat?.anchors, const [4]);
      expect(next.beat?.beats, base.beat?.beats);
      expect(next.mirrored, isTrue);
    });
  });
}

/// 旧同版本 reader 的最小模拟：与 markers 编解码同机制（`DocumentCodec`：
/// 顶层未知键收进文档级保底区、回写先展开保底区且永不覆盖已登记键），
/// 但已知键集只含 version 与既有四段——即 `notes` 段落码之前的 reader 形态。
/// 段值声明为可缺席（本测试只关心顶层键的保底路径）。
enum _LegacySection { meta, beat, corrections, annotations }

class _LegacyDoc {
  const _LegacyDoc({this.extra = const {}});
  final Map<String, Object?> extra;
}

final _legacyCodec = DocumentCodec<_LegacyDoc, _LegacySection>(
  policy: MarkersDocument.versionPolicy,
  ids: _LegacySection.values,
  decl: _legacyDecl,
  empty: _LegacyDoc.new,
  build: _buildLegacyDoc,
  extraOf: _legacyExtraOf,
  withExtra: _legacyWithExtra,
);

Map<String, Object?> _legacyExtraOf(_LegacyDoc doc) => doc.extra;

_LegacyDoc _legacyWithExtra(_LegacyDoc doc, Map<String, Object?> extra) =>
    _LegacyDoc(extra: extra);

SectionDecl<_LegacyDoc> _legacyDecl(_LegacySection id) => SectionDecl(
  key: switch (id) {
    _LegacySection.meta => 'meta',
    _LegacySection.beat => 'beat',
    _LegacySection.corrections => 'corrections',
    _LegacySection.annotations => 'annotations',
  },
  codec: const RecordCodec<Object?, Never>(
    ids: [],
    decl: _noFieldDecl,
    build: _buildNoFields,
    extraOf: _noExtraOf,
    withExtra: _noWithExtra,
  ),
  // 段值恒缺席：写侧省略段键（本测试不关心段内容，只关心顶层未知键）。
  absentOf: _alwaysAbsent,
  sectionOf: _noSection,
);

FieldDecl<Object?> _noFieldDecl(Never id) => throw StateError('无论域');

Object? _buildNoFields(Map<Never, Object?> values) => null;

Map<String, Object?> _noExtraOf(Object? value) => const {};

Object? _noWithExtra(Object? value, Map<String, Object?> extra) => value;

bool _alwaysAbsent(_LegacyDoc doc) => true;

Object? _noSection(_LegacyDoc doc) => null;

_LegacyDoc _buildLegacyDoc(Map<_LegacySection, Object?> sections) =>
    const _LegacyDoc();

Map<String, Object?> _legacyReaderRewrite(Map<String, Object?> json) =>
    _legacyCodec.encode(_legacyCodec.decode(json));
