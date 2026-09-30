import 'package:dance_learning_app/core/document_codec.dart';
import 'package:dance_learning_app/core/document_version_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试专用最小 schema：一个文档（两个段）+ 若干字段。
/// 含可空字段（显式未设哨兵）、列表、嵌套元素、未知键（逐层）。
enum _MetaField { title, note }

enum _ItemsField { entries }

enum _ItemField { positionMs, tag }

enum _DocSection { meta, items, probe }

class TestMeta {
  const TestMeta({this.title = '', this.note, this.extra = const {}});
  final String title;
  final String? note;
  final Map<String, Object?> extra;
}

class TestItem {
  const TestItem({this.positionMs = 0, this.tag, this.extra = const {}});
  final int positionMs;
  final String? tag;
  final Map<String, Object?> extra;
}

class TestItems {
  const TestItems({this.entries = const [], this.extra = const {}});
  final List<TestItem> entries;
  final Map<String, Object?> extra;
}

class TestDoc {
  const TestDoc({this.meta = const TestMeta(), this.items = const TestItems(), this.probe, this.extra = const {}});
  final TestMeta meta;
  final TestItems items;

  /// 可缺席段（如 markers 的 `beat`：未分析时无该段）的段值；null = 缺席。
  final TestMeta? probe;
  final Map<String, Object?> extra;
}

class TestListDoc {
  const TestListDoc({this.entries = const [], this.extra = const {}});
  final List<TestItem> entries;
  final Map<String, Object?> extra;
}

const _itemCodec = RecordCodec<TestItem, _ItemField>(
  ids: _ItemField.values,
  decl: _itemDecl,
  build: _buildItem,
  extraOf: _extraOfItem,
  withExtra: _withExtraItem,
);

FieldDecl<TestItem> _itemDecl(_ItemField id) => switch (id) {
  _ItemField.positionMs => FieldDecl(
    key: 'positionMs',
    read: (json) => (json['positionMs'] as num?)?.toInt() ?? 0,
    write: (item) => item.positionMs,
    equal: (a, b) => a.positionMs == b.positionMs,
  ),
  _ItemField.tag => FieldDecl(
    key: 'tag',
    read: (json) => json['tag'] as String?,
    write: (item) => item.tag,
    equal: (a, b) => a.tag == b.tag,
  ),
};

TestItem _buildItem(Map<_ItemField, Object?> values) => TestItem(
  positionMs: values[_ItemField.positionMs] as int,
  tag: values[_ItemField.tag] as String?,
);

Map<String, Object?> _extraOfItem(TestItem item) => item.extra;

TestItem _withExtraItem(TestItem item, Map<String, Object?> extra) =>
    TestItem(positionMs: item.positionMs, tag: item.tag, extra: extra);

const _metaCodec = RecordCodec<TestMeta, _MetaField>(
  ids: _MetaField.values,
  decl: _metaDecl,
  build: _buildMeta,
  extraOf: _extraOfMeta,
  withExtra: _withExtraMeta,
);

FieldDecl<TestMeta> _metaDecl(_MetaField id) => switch (id) {
  _MetaField.title => FieldDecl(
    key: 'title',
    shareable: true,
    read: (json) => json['title'] as String? ?? '',
    write: (meta) => meta.title,
    equal: (a, b) => a.title == b.title,
  ),
  _MetaField.note => FieldDecl(
    key: 'note',
    read: (json) => json['note'] as String?,
    // 未设置（null）不写键。
    write: (meta) => meta.note ?? omitField,
    equal: (a, b) => a.note == b.note,
  ),
};

TestMeta _buildMeta(Map<_MetaField, Object?> values) => TestMeta(
  title: values[_MetaField.title] as String,
  note: values[_MetaField.note] as String?,
);

Map<String, Object?> _extraOfMeta(TestMeta meta) => meta.extra;

TestMeta _withExtraMeta(TestMeta meta, Map<String, Object?> extra) =>
    TestMeta(title: meta.title, note: meta.note, extra: extra);

const _itemsCodec = RecordCodec<TestItems, _ItemsField>(
  ids: _ItemsField.values,
  decl: _itemsDecl,
  build: _buildItems,
  extraOf: _extraOfItems,
  withExtra: _withExtraItems,
);

FieldDecl<TestItems> _itemsDecl(_ItemsField id) => switch (id) {
  _ItemsField.entries => FieldDecl(
    key: 'entries',
    read: (json) => [
      for (final e in (json['entries'] as List? ?? const <Object?>[]))
        if (e is Map<String, Object?>) _itemCodec.decode(e),
    ],
    write: (items) => [for (final e in items.entries) _itemCodec.encode(e)],
    equal: (a, b) =>
        a.entries.length == b.entries.length &&
        List.generate(a.entries.length, (i) => _itemCodec.equals(a.entries[i], b.entries[i]))
            .every((ok) => ok),
  ),
};

TestItems _buildItems(Map<_ItemsField, Object?> values) =>
    TestItems(entries: values[_ItemsField.entries] as List<TestItem>);

Map<String, Object?> _extraOfItems(TestItems items) => items.extra;

TestItems _withExtraItems(TestItems items, Map<String, Object?> extra) =>
    TestItems(entries: items.entries, extra: extra);

/// 分段形状测试政策的版本链：地板 1 + 一级迁移（v1 → v2，形状不变）。
final DocumentVersionPolicy _docPolicy = DocumentVersionPolicy(
  floor: 1,
  steps: [MigrationStep(1, (json) => Map<String, Object?>.of(json))],
);

final _docCodec = DocumentCodec<TestDoc, _DocSection>(
  policy: _docPolicy,
  ids: _DocSection.values,
  decl: _docSectionDecl,
  empty: TestDoc.new,
  build: _buildDoc,
  extraOf: _docExtraOf,
  withExtra: _docWithExtra,
);

SectionDecl<TestDoc> _docSectionDecl(_DocSection id) => switch (id) {
  _DocSection.meta => SectionDecl(key: 'meta', codec: _metaCodec, sectionOf: (doc) => doc.meta),
  _DocSection.items => SectionDecl(key: 'items', codec: _itemsCodec, sectionOf: (doc) => doc.items),
  _DocSection.probe => SectionDecl(
    key: 'probe',
    codec: _metaCodec,
    absentOf: (doc) => doc.probe == null,
    sectionOf: (doc) => doc.probe,
  ),
};

TestDoc _buildDoc(Map<_DocSection, Object?> sections) => TestDoc(
  meta: sections[_DocSection.meta] as TestMeta,
  items: sections[_DocSection.items] as TestItems,
  probe: sections[_DocSection.probe] as TestMeta?,
);

Map<String, Object?> _docExtraOf(TestDoc doc) => doc.extra;

TestDoc _docWithExtra(TestDoc doc, Map<String, Object?> extra) =>
    TestDoc(meta: doc.meta, items: doc.items, probe: doc.probe, extra: extra);

void main() {
  group('document_codec 往返', () {
    test('全字段往返：可空省略字段、列表、嵌套元素', () {
      const doc = TestDoc(
        meta: TestMeta(title: 'song', note: 'note-a'),
        items: TestItems(entries: [
          TestItem(positionMs: 1200, tag: 'intro'),
          TestItem(positionMs: 3400, tag: null),
        ]),
        extra: {'topFuture': {'nested': [1, 2]}},
      );

      final json = _docCodec.encode(doc);
      final restored = _docCodec.decode(json);

      expect(_docCodec.equals(restored, doc), isTrue);
      expect(restored.meta.title, 'song');
      expect(restored.meta.note, 'note-a');
      expect(restored.items.entries.length, 2);
      expect(restored.items.entries[0].positionMs, 1200);
      expect(restored.items.entries[0].tag, 'intro');
      expect(restored.items.entries[1].tag, isNull);
      expect(restored.extra, {'topFuture': {'nested': [1, 2]}});
    });

    test('未设置（null）不写键，设值写键', () {
      final unsetJson = _metaCodec.encode(const TestMeta(title: 'a'));
      expect(unsetJson.containsKey('note'), isFalse);

      final setJson = _metaCodec.encode(
        const TestMeta(title: 'a', note: 'note-a'),
      );
      expect(setJson['note'], 'note-a');

      expect(_metaCodec.decode(unsetJson).note, isNull);
      expect(_metaCodec.decode(setJson).note, 'note-a');
    });
  });

  group('document_codec 逐层陌生键保底', () {
    test('文档层、段层、元素层的未知键都原样带回、写回原样', () {
      final json = <String, Object?>{
        'version': 2,
        'meta': <String, Object?>{
          'title': 'x',
          'metaFuture': 'keep-me',
        },
        'items': <String, Object?>{
          'entries': [
            <String, Object?>{'positionMs': 5, 'tag': 'a', 'itemFuture': [1, {'k': 'v'}]},
          ],
          'itemsFuture': 7,
        },
        'docFuture': true,
      };

      final restored = _docCodec.decode(json);

      expect(restored.extra, {'docFuture': true});
      expect(restored.meta.extra, {'metaFuture': 'keep-me'});
      expect(restored.items.extra, {'itemsFuture': 7});
      expect(restored.items.entries.single.extra, {'itemFuture': [1, {'k': 'v'}]});

      final written = _docCodec.encode(restored);
      expect(written, json);
    });

    test('保底区不覆盖已登记字段：写盘时保底区先展开、已登记字段后写', () {
      // 元素层：extra 里塞入与已登记字段同名的键，注册值必须胜出。
      final itemJson = _itemCodec.encode(
        const TestItem(positionMs: 100, extra: {'positionMs': 999, 'tag': 'hijack'}),
      );
      expect(itemJson['positionMs'], 100);
      expect(itemJson['tag'], isNull);

      // 段层同理。
      final metaJson = _metaCodec.encode(
        const TestMeta(title: 'real', extra: {'title': 'hijack'}),
      );
      expect(metaJson['title'], 'real');

      // 文档层：extra 塞 version 与段键，注册值必须胜出。
      final docJson = _docCodec.encode(
        const TestDoc(extra: {'version': 99, 'meta': 'hijack'}),
      );
      expect(docJson['version'], 2);
      expect(docJson['meta'], isA<Map<String, Object?>>());
    });
  });

  group('document_codec 可缺席段', () {
    test('段值缺席：写侧省略段键；读侧段键缺失得到 null 段值', () {
      final json = _docCodec.encode(const TestDoc());
      expect(json.containsKey('probe'), isFalse);
      // 恒在段不受影响。
      expect(json.containsKey('meta'), isTrue);
      expect(json.containsKey('items'), isTrue);

      final restored = _docCodec.decode(<String, Object?>{'version': 2});
      expect(restored.probe, isNull);

      final present = _docCodec.decode(<String, Object?>{
        'version': 2,
        'probe': {'title': 'p'},
      });
      expect(present.probe?.title, 'p');
    });

    test('缺席段的相等与哈希：双双缺席相等；缺席 vs 在席不等', () {
      const a = TestDoc();
      const b = TestDoc();
      expect(_docCodec.equals(a, b), isTrue);
      expect(_docCodec.hash(a), _docCodec.hash(b));

      const c = TestDoc(probe: TestMeta(title: 'p'));
      expect(_docCodec.equals(a, c), isFalse);
      expect(_docCodec.equals(c, c), isTrue);
    });
  });

  group('document_codec 版本政策', () {
    test('低于地板 → 空态（唯一合法的读空）', () {
      final below = _docCodec.decode(<String, Object?>{
        'version': 0,
        'meta': {'title': 'stale'},
      });
      expect(below.meta.title, '');
      expect(below.items.entries, isEmpty);
      expect(below.extra, isEmpty);
    });

    test('链上中间版本 → 逐级升位后正常读、可写', () {
      const onDisk = <String, Object?>{
        'version': 1,
        'meta': {'title': 'old'},
        'docFuture': {'keep': 1},
      };
      final doc = _docCodec.decode(onDisk);
      expect(doc.meta.title, 'old');
      expect(doc.extra, {'docFuture': {'keep': 1}});
      expect(_docPolicy.isWritable(onDisk), isTrue);
      expect(_docCodec.encode(doc)['version'], 2);
    });

    test('version 相符 → 正常读、可写', () {
      const onDisk = <String, Object?>{
        'version': 2,
        'meta': {'title': 'fresh'},
      };
      final ok = _docCodec.decode(onDisk);
      expect(ok.meta.title, 'fresh');
      expect(_docPolicy.isWritable(onDisk), isTrue);
    });

    test('更高版本 → 认识多少读多少 + 只读（不读空、不改写）', () {
      const onDisk = <String, Object?>{
        'version': 3,
        'meta': {'title': 'from-the-future'},
        'items': {
          'entries': [
            {'positionMs': 7, 'tag': 'a'},
          ],
        },
        'futureSection': {'x': 1},
      };
      final doc = _docCodec.decode(onDisk);
      expect(doc.meta.title, 'from-the-future');
      expect(doc.items.entries.single.positionMs, 7);
      expect(doc.extra, {'futureSection': {'x': 1}});
      expect(_docPolicy.isWritable(onDisk), isFalse);
    });

    test('版本头读不出（缺失/非整数）→ 认识多少读多少 + 只读', () {
      for (final onDisk in const <Map<String, Object?>>[
        {'meta': {'title': 'stale'}},
        {'version': '2', 'meta': {'title': 'stale'}},
      ]) {
        final doc = _docCodec.decode(onDisk);
        expect(doc.meta.title, 'stale', reason: '$onDisk');
        expect(_docPolicy.isWritable(onDisk), isFalse, reason: '$onDisk');
      }
    });
  });

  group('document_codec 可分享投影', () {
    test('默认不进包：只有显式标记的字段流出，未登记键一律剔除', () {
      final json = <String, Object?>{
        'version': 2,
        'meta': <String, Object?>{
          'title': 'x',
          'note': 'private',
          'metaFuture': 'keep-me',
        },
        'items': <String, Object?>{
          'entries': [
            <String, Object?>{'positionMs': 5, 'tag': 'a'},
          ],
        },
        'docFuture': true,
      };

      // `title` 已标记 shareable；`note`、整个 `items` 段与逐层未登记键
      // 都默认不进包。
      expect(_docCodec.projectJson(json), {
        'version': 2,
        'meta': {'title': 'x'},
      });
    });

    test('字段级投影：非可分享字段与未登记键剔除', () {
      expect(
        _metaCodec.projectJson({
          'title': 'x',
          'note': 'private',
          'metaFuture': 1,
        }),
        {'title': 'x'},
      );
    });
  });

  group('document_codec 相等语义', () {
    test('保底区不参与比较：仅 extra 不同 → 相等且哈希一致', () {
      const a = TestDoc(
        meta: TestMeta(title: 't'),
        extra: {'docFuture': 1},
      );
      const b = TestDoc(
        meta: TestMeta(title: 't', extra: {'metaFuture': 2}),
      );
      expect(_docCodec.equals(a, b), isTrue);
      expect(_docCodec.hash(a), _docCodec.hash(b));

      const c = TestItem(positionMs: 1, extra: {'x': 1});
      const d = TestItem(positionMs: 1, extra: {'y': 2});
      expect(_itemCodec.equals(c, d), isTrue);
      expect(_itemCodec.hash(c), _itemCodec.hash(d));
    });

    test('本版本字段变化才判不等（含可空字段的设值 vs 未设置）', () {
      const a = TestMeta(title: 't');
      const b = TestMeta(title: 't', note: 'note-a');
      expect(_metaCodec.equals(a, b), isFalse);

      const c = TestDoc(meta: TestMeta(title: 't'));
      const d = TestDoc(meta: TestMeta(title: 'u'));
      expect(_docCodec.equals(c, d), isFalse);

      const e = TestItems(entries: [TestItem(positionMs: 1)]);
      const f = TestItems(entries: [TestItem(positionMs: 2)]);
      expect(_itemsCodec.equals(e, f), isFalse);
    });

    test('深相等与深哈希一致：数值 1 与 1.0 相等且同哈希', () {
      expect(jsonDeepEquals([1, {'k': 2}], [1.0, {'k': 2.0}]), isTrue);
      expect(
        jsonDeepHash([1, {'k': 2}]),
        jsonDeepHash([1.0, {'k': 2.0}]),
      );
    });
  });

  group('list_document_codec 单列表文档（视频索引/练习统计同款）', () {
    /// 列表形状测试政策的版本链：地板 2 + 一级迁移（v2 → v3，形状不变）。
    final listPolicy = DocumentVersionPolicy(
      floor: 2,
      steps: [MigrationStep(2, (json) => Map<String, Object?>.of(json))],
    );
    final codec = ListDocumentCodec<TestListDoc, TestItem, _ItemField>(
      policy: listPolicy,
      listKey: 'entries',
      elementCodec: _itemCodec,
      empty: () => const TestListDoc(),
      build: (elements) => TestListDoc(entries: elements),
      listOf: (doc) => doc.entries,
      extraOf: (doc) => doc.extra,
      withExtra: (doc, extra) => TestListDoc(entries: doc.entries, extra: extra),
    );

    test('往返：写出去再读回来逐位相等', () {
      const doc = TestListDoc(entries: [
        TestItem(positionMs: 100, tag: 'a'),
        TestItem(positionMs: 200),
      ]);
      final json = codec.encode(doc);
      expect(json['version'], 3);
      expect((json['entries'] as List).length, 2);
      final restored = codec.decode(json);
      expect(restored.entries.length, 2);
      expect(restored.entries[0].positionMs, 100);
      expect(restored.entries[0].tag, 'a');
      expect(restored.entries[1].tag, isNull);
    });

    test('中间版本可升位：链上 v2 文件升到本版后读、可写、版本写回为链尾', () {
      const onDisk = <String, Object?>{
        'version': 2,
        'entries': [
          {'positionMs': 5, 'tag': 'mid'},
        ],
        'docFuture': 1,
      };
      final doc = codec.decode(onDisk);
      expect(doc.entries.single.positionMs, 5);
      expect(doc.entries.single.tag, 'mid');
      expect(doc.extra, {'docFuture': 1});
      expect(listPolicy.isWritable(onDisk), isTrue);
      expect(codec.encode(doc)['version'], 3);
    });

    test('高于本版只读：认识多少读多少、不读空、不可写', () {
      const onDisk = <String, Object?>{
        'version': 4,
        'entries': [
          {'positionMs': 9, 'tag': 'future'},
        ],
        'futureDoc': {'x': 1},
      };
      final doc = codec.decode(onDisk);
      expect(doc.entries.single.positionMs, 9);
      expect(doc.extra, {'futureDoc': {'x': 1}});
      expect(listPolicy.isWritable(onDisk), isFalse);
    });

    test('低于地板 → 空态；列表非 List → 空态；版本头读不出 → 只读照读', () {
      final json = codec.encode(
        const TestListDoc(entries: [TestItem(positionMs: 1)]),
      );
      expect(codec.decode({...json, 'version': 1}).entries, isEmpty);
      expect(
        codec.decode({...json, 'entries': 'not-a-list'}).entries,
        isEmpty,
      );
      expect(codec.decode(json).entries, hasLength(1));
      final noVersion = {...json}..remove('version');
      expect(codec.decode(noVersion).entries, hasLength(1));
      expect(listPolicy.isWritable(noVersion), isFalse);
    });

    test('逐层保底：文档级与元素级未知键都原样带回、写回原样', () {
      final json = codec.encode(
        const TestListDoc(
          entries: [TestItem(positionMs: 1, extra: {'itemFuture': 'k'})],
          extra: {'docFuture': {'n': 1}},
        ),
      );
      final restored = codec.decode(json);
      expect(restored.extra['docFuture'], {'n': 1});
      expect(restored.entries.single.extra['itemFuture'], 'k');
      final rewritten = codec.encode(restored);
      expect(rewritten['docFuture'], {'n': 1});
      expect(
        (rewritten['entries'] as List).single['itemFuture'],
        'k',
      );
    });

    test('相等语义：元素逐个比较、保底区不参与；哈希与相等一致', () {
      const a = TestListDoc(
        entries: [TestItem(positionMs: 1)],
        extra: {'docFuture': 1},
      );
      const b = TestListDoc(
        entries: [TestItem(positionMs: 1, extra: {'itemFuture': 2})],
      );
      expect(codec.equals(a, b), isTrue);
      expect(codec.hash(a), codec.hash(b));

      const c = TestListDoc(entries: [TestItem(positionMs: 1)]);
      const d = TestListDoc(entries: [TestItem(positionMs: 2)]);
      expect(codec.equals(c, d), isFalse);
      const e = TestListDoc(
        entries: [TestItem(positionMs: 1), TestItem(positionMs: 1)],
      );
      expect(codec.equals(c, e), isFalse, reason: '长度不等先判不等');
    });
  });
}
