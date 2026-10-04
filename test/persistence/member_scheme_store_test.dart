import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 组员方案存取：沿素材清单的 store 三件套先例——
/// 单段 `schemes_<hash>.json`、写入者 = 导入动作、字段单一声明、逐层
/// 陌生键保底、版本政策（地板 = 本版）、方案标识替换与新增两路各一条断言。
void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('member_scheme_store_test');
    file = File('${tempDir.path}/schemes_v1.json');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  MemberSchemeRecord record({
    String schemeId = 's1',
    String memberName = '小如',
    String schemeName = '真值名',
  }) => MemberSchemeRecord(
    schemeId: schemeId,
    memberName: memberName,
    schemeName: schemeName,
    mastery: const {0: 2, 1: 4},
    importedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    markers: const {
      'version': 3,
      'meta': {'signature': 'x'},
      'segmentLines': <Object?>[],
    },
  );

  Map<String, dynamic> readJson() =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  group('组员方案文档（段化机制接入）', () {
    test('单段编解码 round trip：version + schemes 段 + 条目字段全含', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());

      final json = readJson();
      expect(json['version'], 2);
      final entry = (json['schemes'] as List).single as Map<String, dynamic>;
      expect(entry['schemeId'], 's1');
      expect(entry['memberName'], '小如');
      expect(entry['schemeName'], '真值名');
      expect(entry['mastery'], {'0': 2, '1': 4});
      expect(entry['importedAtMs'], 1700000000000);
      expect(entry['markers'], containsPair('meta', {'signature': 'x'}));

      final reopened = await MemberSchemeStore(MemberSchemeFileStore(file))
          .read();
      expect(reopened.schemes, [record()]);
    });

    test('版本政策：更高版本/版本头读不出 → 只读照读且不写回', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());

      final wrong = readJson()..['version'] = 3;
      file.writeAsStringSync(jsonEncode(wrong));
      final higher = MemberSchemeStore(MemberSchemeFileStore(file));
      expect((await higher.read()).schemes, [record()]);
      await higher.upsert(record(schemeId: 's2'));
      expect(readJson(), wrong, reason: '只读文件不写回');

      final missing = readJson()..remove('version');
      file.writeAsStringSync(jsonEncode(missing));
      final noVersion = MemberSchemeStore(MemberSchemeFileStore(file));
      expect((await noVersion.read()).schemes, [record()]);
      await noVersion.remove('s1');
      expect(readJson(), missing, reason: '只读文件不写回');
    });

    test('逐层陌生键保底：文档级/条目级未知键原样带回、写回原样', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());

      final mutated = readJson();
      mutated['futureDocKey'] = 'keep-doc';
      ((mutated['schemes'] as List).single
              as Map<String, dynamic>)['futureEntryKey'] =
          'keep-entry';
      file.writeAsStringSync(jsonEncode(mutated));

      final reopened = MemberSchemeStore(MemberSchemeFileStore(file));
      expect((await reopened.read()).schemes, [record()]);
      await reopened.upsert(record(schemeId: 's2'));

      final written = readJson();
      expect(written['futureDocKey'], 'keep-doc');
      expect(
        (written['schemes'] as List).first,
        containsPair('futureEntryKey', 'keep-entry'),
      );
    });

    test('v1 → v2 迁移：旧段形状 `schemes.entries` 上提为 `schemes` 列表', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());
      final v1 = {
        'version': 1,
        'futureDocKey': 'keep-doc',
        'schemes': {
          'crFixtureSection': 'drop-me',
          'entries': readJson()['schemes'],
        },
      };
      file.writeAsStringSync(jsonEncode(v1));

      final reopened = MemberSchemeStore(MemberSchemeFileStore(file));
      expect((await reopened.read()).schemes, [record()]);

      await reopened.upsert(record(schemeId: 's2'));
      final written = readJson();
      expect(written['version'], 2);
      expect((written['schemes'] as List).map((e) => (e as Map)['schemeId']), [
        's1',
        's2',
      ]);
      expect(written['futureDocKey'], 'keep-doc');
    });

    test('损坏条目丢弃：缺 schemeId 的条目不入库、合法条目保留', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());
      final mutated = readJson();
      (mutated['schemes'] as List).add({'memberName': '坏条目'});
      file.writeAsStringSync(jsonEncode(mutated));

      final doc = await MemberSchemeStore(MemberSchemeFileStore(file)).read();
      expect(doc.schemes.map((s) => s.schemeId), ['s1']);
    });

    test('同方案标识再导入 = 替换那一条，不堆两条', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());
      await store.upsert(
        MemberSchemeRecord(
          schemeId: 's1',
          memberName: '小如改',
          importedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
          markers: const {'version': 4},
        ),
      );

      final doc = await store.read();
      expect(doc.schemes.length, 1);
      expect(doc.schemes.single.memberName, '小如改');
      expect(doc.schemes.single.markers, {'version': 4});
      final reopened = await MemberSchemeStore(MemberSchemeFileStore(file))
          .read();
      expect(reopened.schemes, doc.schemes, reason: '替换落盘');
    });

    test('异方案标识导入 = 新增一条，两者并存', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());
      await store.upsert(record(schemeId: 's2', memberName: '小海'));

      final doc = await store.read();
      expect(doc.schemes.map((s) => s.schemeId), ['s1', 's2']);
    });

    test('删除一条组员方案：remove 只删指定标识、其余保留并落盘', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());
      await store.upsert(record(schemeId: 's2'));

      final after = await store.remove('s1');
      expect(after.schemes.map((s) => s.schemeId), ['s2']);
      final reopened = await MemberSchemeStore(MemberSchemeFileStore(file))
          .read();
      expect(reopened.schemes, after.schemes);
    });

    test('按舞清除 = 整份文件删除：clear 后读回空态、文件不存在', () async {
      final store = MemberSchemeStore(MemberSchemeFileStore(file));
      await store.upsert(record());
      await store.clear();

      expect(file.existsSync(), isFalse);
      expect(
        await MemberSchemeStore(MemberSchemeFileStore(file)).read(),
        MemberSchemesDocument.empty,
      );
    });
  });
}
