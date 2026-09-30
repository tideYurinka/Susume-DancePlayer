import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// 素材清单：第五份接入文档段化通用机制的文档
/// ——单段、写入者 = 录制会话；条目带 videoId 与源区间。
/// 直测：字段单一声明、逐层陌生键保底、版本政策（地板 = 本版）、条目真存在。
void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('material_manifest_test');
    file = File('${tempDir.path}/manifest.json');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  MaterialRecord record({String id = 'm1', String videoId = 'vid1'}) =>
      MaterialRecord(
        id: id,
        videoId: videoId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        durationMs: 12345,
        sourceStartMs: 6789,
        fileName: 'rec_1.mp4',
        sizeBytes: 42,
      );

  Map<String, dynamic> readJson() => jsonDecode(file.readAsStringSync())
      as Map<String, dynamic>;

  group('素材清单文档（段化机制第五份接入）', () {
    test('单段编解码 round trip：version + materials 段 + 条目字段', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());

      final json = readJson();
      expect(json['version'], 3);
      final entry = (json['materials'] as List).single
          as Map<String, dynamic>;
      expect(entry['id'], 'm1');
      expect(entry['videoId'], 'vid1');
      expect(entry['createdAtMs'], 1700000000000);
      expect(entry['durationMs'], 12345);
      expect(entry['sourceStartMs'], 6789);
      expect(entry['fileName'], 'rec_1.mp4');
      expect(entry['sizeBytes'], 42);

      final doc = await MaterialManifestStore(MaterialManifestFileStore(file)).read();
      expect(doc.materials, [record()]);
    });

    test('版本政策：换代前 v1 低于地板 → 空态；更高版本/版本头读不出 → 只读照读且不写回', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());

      final previous = readJson()..['version'] = 1;
      file.writeAsStringSync(jsonEncode(previous));
      expect(
        await MaterialManifestStore(MaterialManifestFileStore(file)).read(),
        MaterialManifestDocument.empty,
      );

      final wrong = readJson()..['version'] = 4;
      file.writeAsStringSync(jsonEncode(wrong));
      final higher = MaterialManifestStore(MaterialManifestFileStore(file));
      expect((await higher.read()).materials, [record()]);
      await higher.append(record(id: 'm2'));
      expect(readJson(), wrong, reason: '只读文件不写回');

      final missing = readJson()..remove('version');
      file.writeAsStringSync(jsonEncode(missing));
      final noVersion = MaterialManifestStore(MaterialManifestFileStore(file));
      expect((await noVersion.read()).materials, [record()]);
      await noVersion.remove('m1');
      expect(readJson(), missing, reason: '只读文件不写回');
    });

    test('逐层陌生键保底：文档级/条目级未知键原样带回、写回原样', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());

      final mutated = readJson();
      mutated['futureDocKey'] = 'keep-doc';
      ((mutated['materials'] as List).single as Map<String, dynamic>)
          ['futureEntryKey'] = 'keep-entry';
      file.writeAsStringSync(jsonEncode(mutated));

      final reopened = MaterialManifestStore(MaterialManifestFileStore(file));
      expect((await reopened.read()).materials, [record()]);
      await reopened.append(record(id: 'm2'));

      final written = readJson();
      expect(written['futureDocKey'], 'keep-doc');
      expect(
        (written['materials'] as List).first,
        containsPair('futureEntryKey', 'keep-entry'),
      );
    });

    test('v2 → v3 迁移：旧段形状 `materials.entries` 上提为 `materials` 列表', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());
      final v2 = {
        'version': 2,
        'futureDocKey': 'keep-doc',
        'materials': {
          'crFixtureSection': 'drop-me',
          'entries': readJson()['materials'],
        },
      };
      file.writeAsStringSync(jsonEncode(v2));

      final reopened = MaterialManifestStore(MaterialManifestFileStore(file));
      expect((await reopened.read()).materials, [record()]);

      await reopened.append(record(id: 'm2'));
      final written = readJson();
      expect(written['version'], 3);
      expect(
        (written['materials'] as List).map((e) => (e as Map)['id']),
        ['m1', 'm2'],
      );
      expect(written['futureDocKey'], 'keep-doc');
    });

    test('损坏条目丢弃：必填字段缺失的条目不入库、合法条目保留', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());
      final mutated = readJson();
      final entries = mutated['materials'] as List;
      entries.add({
        'videoId': 'vid1',
        'fileName': 'broken.mp4',
      }); // 缺 id。
      file.writeAsStringSync(jsonEncode(mutated));

      final doc = await MaterialManifestStore(MaterialManifestFileStore(file)).read();
      expect(doc.materials, [record()]);
    });

    test('关掉重开素材还在：append 后新实例读取同一文件仍有条目', () async {
      final first = MaterialManifestStore(MaterialManifestFileStore(file));
      await first.append(record());
      await first.append(record(id: 'm2'));

      final reopened = MaterialManifestStore(MaterialManifestFileStore(file));
      final doc = await reopened.read();
      expect(
        doc.materials.map((m) => m.id),
        unorderedEquals(['m1', 'm2']),
      );
    });

    test('删除素材条目：remove 只删指定 id、其余条目保留并落盘', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());
      await store.append(record(id: 'm2'));

      final after = await store.remove('m1');
      expect(after.materials.map((m) => m.id), ['m2']);
      final reopened = await MaterialManifestStore(
        MaterialManifestFileStore(file),
      ).read();
      expect(reopened.materials, after.materials, reason: '删除落盘：重开仍在');

      // 删除不存在的 id：清单原样。
      final unchanged = await store.remove('nope');
      expect(unchanged.materials.map((m) => m.id), ['m2']);
    });

    test('删除一支舞的素材条目：removeByVideo 只删该舞条目、其余保留并落盘', () async {
      final store = MaterialManifestStore(MaterialManifestFileStore(file));
      await store.append(record());
      await store.append(record(id: 'm2'));
      await store.append(record(id: 'm3', videoId: 'vid2'));

      final after = await store.removeByVideo('vid1');
      expect(after.materials.map((m) => m.id), ['m3']);
      final reopened = await MaterialManifestStore(
        MaterialManifestFileStore(file),
      ).read();
      expect(reopened.materials, after.materials, reason: '删除落盘：重开仍在');

      // 未命中 videoId：清单原样。
      final unchanged = await store.removeByVideo('nope');
      expect(unchanged.materials.map((m) => m.id), ['m3']);
    });
  });
}
