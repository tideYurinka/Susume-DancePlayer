import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/document_version_registry.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/memory_manifest_storage.dart';

/// 跨发布版本夹具的参数化契约测试（缝 3）。
///
/// 只读 `test/fixtures/cross_release/<发布版>/<文档>.json`（旧包真实写出的
/// 文件）与 `documentVersionPolicies` 登记表，只经**公开读面**观察：每份
/// 夹具读出的用户内容逐项在场、写回后版本为当前版本、逐层陌生键逐层往返。
/// 夹具键名按各发布 tag 的真实 schema 手钉，不由本测试构造。
const String _fixturesRoot = 'test/fixtures/cross_release';

/// store 的唯一公开写入口是串行「读 → 改 → 写」：删一个**不存在**的 id
/// 等于不改内容地触发一次整份写回，正好观察写回后的版本与逐层保底区。
const String _absentEntryId = '__cross_release_absent__';

/// 一份夹具文档的契约：公开读面、公开写回面、用户内容断言、逐层陌生键
/// 断言、迁移按设计丢弃的路径（`<层>.<键>`）。
class _DocContract {
  const _DocContract({
    required this.read,
    required this.writeBack,
    required this.expectUserContent,
    required this.expectUnknownLevels,
    this.dropped = const {},
    this.reshaped,
  });

  final Future<Object?> Function(Map<String, Object?> raw) read;
  final Future<Map<String, Object?>> Function(Map<String, Object?> raw)
  writeBack;
  final void Function(Object? doc) expectUserContent;
  final void Function(Map<String, Object?> encoded) expectUnknownLevels;
  final Set<String> dropped;

  /// 迁移级的形状对照：旧夹具 → 本版写回形状（不传即形状不变）。
  final Map<String, Object?> Function(Map<String, Object?> raw)? reshaped;
}

Future<Object?> _readThroughSchemes(Map<String, Object?> raw) =>
    MemberSchemeStore(
      InMemoryMemberSchemeStorage(Map<String, dynamic>.from(raw)),
    ).read();

Future<Map<String, Object?>> _writeBackThroughSchemes(
  Map<String, Object?> raw,
) async {
  final storage = InMemoryMemberSchemeStorage(Map<String, dynamic>.from(raw));
  await MemberSchemeStore(storage).remove(_absentEntryId);
  return storage.json;
}

Future<Object?> _readThroughMaterials(Map<String, Object?> raw) async {
  final storage = MemoryManifestStorage();
  await storage.save(Map<String, dynamic>.from(raw));
  return MaterialManifestStore(storage).read();
}

Future<Map<String, Object?>> _writeBackThroughMaterials(
  Map<String, Object?> raw,
) async {
  final storage = MemoryManifestStorage();
  await storage.save(Map<String, dynamic>.from(raw));
  await MaterialManifestStore(storage).remove(_absentEntryId);
  return storage.load();
}

final Map<String, _DocContract> _contracts = {
  'markers': _DocContract(
    read: (raw) async => MarkersDocument.fromJson(raw),
    writeBack: (raw) async => MarkersDocument.fromJson(raw).toJson(),
    expectUserContent: (doc) {
      final d = doc as MarkersDocument;
      expect(d.signature?.dancer, '如');
      expect(d.signature?.song, 'My Love');
      expect(d.rangeEndMs, 258182);
      expect(d.segmentLines, hasLength(2));
      expect(d.segmentLines.first.flagged, isTrue);
      expect(d.beat?.beats, hasLength(2));
      expect(d.notes.single.text, '@果 注意手位');
      expect(d.roster.single.name, '果');
    },
    expectUnknownLevels: (encoded) {
      expect((encoded['meta']! as Map)['crFixtureSection'], 'cr-section');
      expect(
        ((encoded['annotations']! as Map)['segmentLines']! as List).first,
        containsPair('crFixtureElement', 'cr-element'),
      );
    },
  ),
  'local': _DocContract(
    read: (raw) async => LocalDocument.fromJson(raw),
    writeBack: (raw) async => LocalDocument.fromJson(raw).toJson(),
    dropped: const {'prefs.framingSource', 'prefs.framingPractice'},
    expectUserContent: (doc) {
      final d = doc as LocalDocument;
      expect(d.mastery[0], LearningMastery.learning);
      expect(d.mastery[1], LearningMastery.mastered);
      expect(d.activatedSegments, [0, 1]);
      expect(d.speedRate, 1.25);
      expect(d.practiceClips.single.id, 'clip-1');
    },
    expectUnknownLevels: (encoded) {
      expect((encoded['session']! as Map)['crFixtureSection'], 'cr-section');
      expect(
        (encoded['prefs']! as Map)['overlay'],
        containsPair('crFixtureNested', 'cr-nested'),
      );
    },
  ),
  'videoIndex': _DocContract(
    read: (raw) async => VideoIndex.fromJson(raw),
    writeBack: (raw) async => VideoIndex.fromJson(raw).toJson(),
    expectUserContent: (doc) {
      final d = doc as VideoIndex;
      expect(d.entries.single.videoId, 'hash-love');
      expect(d.entries.single.displayName, 'My Love 练习室');
      expect(d.entries.single.signatureCache?.song, 'My Love');
    },
    expectUnknownLevels: (encoded) {
      expect(
        (encoded['entries']! as List).first,
        containsPair('crFixtureElement', 'cr-element'),
      );
    },
  ),
  'practiceStats': _DocContract(
    read: (raw) async => PracticeStatsDocument.fromJson(raw),
    writeBack: (raw) async => PracticeStatsDocument.fromJson(raw).toJson(),
    expectUserContent: (doc) {
      final d = doc as PracticeStatsDocument;
      expect(d.sessions.single.videoId, 'hash-love');
      expect(d.sessions.single.signature.song, 'My Love');
      expect(d.sessions.single.wallSeconds, 372.4);
    },
    expectUnknownLevels: (encoded) {
      expect(
        (encoded['sessions']! as List).first,
        containsPair('crFixtureElement', 'cr-element'),
      );
    },
  ),
  'practicePlan': _DocContract(
    read: (raw) async => PracticePlanDocument.fromJson(raw),
    writeBack: (raw) async => PracticePlanDocument.fromJson(raw).toJson(),
    expectUserContent: (doc) {
      final d = doc as PracticePlanDocument;
      expect(d.entries.single.videoId, 'hash-love');
      expect(d.entries.single.ddl?.occasion, '演出');
      expect(d.entries.single.ddl?.checklist.single.text, '带水');
      expect(d.events.single.id, 'e1');
    },
    expectUnknownLevels: (encoded) {
      final entry = (encoded['entries']! as List).first as Map;
      expect(entry['crFixtureElement'], 'cr-element');
      expect(entry['ddl'], containsPair('crFixtureNested', 'cr-nested'));
      expect(
        ((entry['ddl']! as Map)['checklist']! as List).first,
        containsPair('crFixtureItem', 'cr-item'),
      );
    },
  ),
  'fourBeatBucket': _DocContract(
    read: (raw) async => FourBeatBucketShard.fromJson(raw),
    writeBack: (raw) async => FourBeatBucketShard.fromJson(raw).toJson(),
    expectUserContent: (doc) {
      final d = doc as FourBeatBucketShard;
      expect(d.signature.song, 'My Love');
      expect(d.days.keys, contains('2026-09-05'));
    },
    expectUnknownLevels: (encoded) {
      expect((encoded['signature']! as Map)['crFixtureSection'], 'cr-section');
      final ledger = encoded['ledger']! as Map;
      expect(ledger['crFixtureNested'], 'cr-nested');
      expect(
        ((ledger['days']! as Map)['2026-09-05']! as Map)['crFixtureElement'],
        'cr-element',
      );
    },
  ),
  'memberSchemes': _DocContract(
    read: _readThroughSchemes,
    writeBack: _writeBackThroughSchemes,
    reshaped: (raw) => {
      ...raw,
      'schemes': (raw['schemes']! as Map)['entries'],
    },
    expectUserContent: (doc) {
      final d = doc as MemberSchemesDocument;
      expect(d.schemes.single.schemeId, 's1');
      expect(d.schemes.single.memberName, '小如');
    },
    expectUnknownLevels: (encoded) {
      expect(
        (encoded['schemes']! as List).first,
        containsPair('crFixtureElement', 'cr-element'),
      );
    },
  ),
  'materialManifest': _DocContract(
    read: _readThroughMaterials,
    writeBack: _writeBackThroughMaterials,
    reshaped: (raw) => {
      ...raw,
      'materials': (raw['materials']! as Map)['entries'],
    },
    expectUserContent: (doc) {
      final d = doc as MaterialManifestDocument;
      expect(d.materials.single.id, 'm1');
      expect(d.materials.single.fileName, 'rec_1.mp4');
    },
    expectUnknownLevels: (encoded) {
      expect(
        (encoded['materials']! as List).first,
        containsPair('crFixtureElement', 'cr-element'),
      );
    },
  ),
};

/// `expected` 的每一项都必须在 `actual` 里逐层在场（保底随行的可观察形式）。
void _expectContains(
  Object? actual,
  Object? expected, {
  required String path,
  required Set<String> dropped,
}) {
  if (dropped.contains(path)) return;
  if (expected is Map) {
    expect(actual, isA<Map>(), reason: '路径 $path');
    final map = actual as Map;
    for (final entry in expected.entries) {
      final child = path.isEmpty ? '${entry.key}' : '$path.${entry.key}';
      if (dropped.contains(child)) continue;
      expect(map.containsKey(entry.key), isTrue, reason: '缺键 $child');
      _expectContains(
        map[entry.key],
        entry.value,
        path: child,
        dropped: dropped,
      );
    }
    return;
  }
  if (expected is List) {
    expect(actual, isA<List>(), reason: '路径 $path');
    final list = actual as List;
    expect(list, hasLength(expected.length), reason: '$path 长度');
    for (var i = 0; i < expected.length; i++) {
      _expectContains(list[i], expected[i], path: '$path.$i', dropped: dropped);
    }
    return;
  }
  expect(actual, expected, reason: '路径 $path');
}

List<String> _fixtureReleases() {
  final names =
      Directory(_fixturesRoot)
          .listSync()
          .whereType<Directory>()
          .map((dir) => dir.path.split(Platform.pathSeparator).last)
          .toList()
        ..sort();
  return names;
}

Set<String> _fixtureDocKeys(String release) =>
    Directory('$_fixturesRoot/$release')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.json'))
        .map((name) => name.substring(0, name.length - '.json'.length))
        .toSet();

Map<String, Object?> _readFixture(String release, String docKey) =>
    jsonDecode(File('$_fixturesRoot/$release/$docKey.json').readAsStringSync())
        as Map<String, Object?>;

void main() {
  final releases = _fixtureReleases();

  test('夹具网格覆盖八份文档 × 全部发布版，地板 v0.1.0 文档键与登记表一致', () {
    expect(releases, isNotEmpty);
    expect(releases.first, 'v0.1.0');
    final floorDocKeys = _fixtureDocKeys('v0.1.0');
    expect(floorDocKeys, documentVersionPolicies.keys.toSet());
    for (final release in releases) {
      expect(_fixtureDocKeys(release), floorDocKeys, reason: '$release 的文档格不齐');
    }
  });

  for (final docKey in documentVersionPolicies.keys) {
    final contract = _contracts[docKey]!;
    final policy = documentVersionPolicies[docKey]!;
    for (final release in releases) {
      test('$release $docKey：读出的用户内容在场、写回版本 ${policy.currentVersion}、'
          '逐层陌生键往返', () async {
        final raw = _readFixture(release, docKey);

        contract.expectUserContent(await contract.read(raw));

        final encoded = await contract.writeBack(raw);
        expect(
          encoded['version'],
          policy.currentVersion,
          reason: '写回后版本必须是本版链尾',
        );

        final expectedContent = (contract.reshaped?.call(raw) ?? {...raw})
          ..remove('version');
        _expectContains(
          encoded,
          expectedContent,
          path: '',
          dropped: contract.dropped,
        );
        expect(encoded['crFixtureDoc'], 'cr-doc', reason: '文档级陌生键');
        contract.expectUnknownLevels(encoded);
      });
    }
  }

  test('schema provenance：公开标记不掺 tag 之后才有的键、本地文档带 tag v3 的取景两键', () {
    for (final release in releases) {
      final meta = _readFixture(release, 'markers')['meta']! as Map;
      expect(
        meta.containsKey('framingBand'),
        isFalse,
        reason: '$release 的公开标记掺入了 tag 之后才进 meta 的 framingBand（按当前 schema 猜）',
      );
      expect(
        meta.containsKey('framingSelection'),
        isFalse,
        reason: '$release 的公开标记掺入了 v9 才进 meta 的 framingSelection（按当前 schema 猜）',
      );
      final prefs = _readFixture(release, 'local')['prefs']! as Map;
      expect(
        prefs.containsKey('framingSource'),
        isTrue,
        reason: '$release 的本地文档缺 tag v3 的 framingSource',
      );
      expect(
        prefs.containsKey('framingPractice'),
        isTrue,
        reason: '$release 的本地文档缺 tag v3 的 framingPractice',
      );
    }
  });

  test('升链文档：v0.1.0 夹具写回为本版，且迁移按设计丢弃旧取景两键', () async {
    final localRaw = _readFixture('v0.1.0', 'local');
    final localEncoded = await _contracts['local']!.writeBack(localRaw);
    expect(localEncoded['version'], LocalDocument.versionPolicy.currentVersion);
    final prefs = localEncoded['prefs']! as Map;
    expect(prefs.containsKey('framingSource'), isFalse);
    expect(prefs.containsKey('framingPractice'), isFalse);

    final markersRaw = _readFixture('v0.1.0', 'markers');
    final markersEncoded = await _contracts['markers']!.writeBack(markersRaw);
    expect(markersRaw['version'], 7);
    expect(
      markersEncoded['version'],
      MarkersDocument.versionPolicy.currentVersion,
    );
  });

  test('四份「地板 = 本版」的夹具：写回后版本不变', () async {
    for (final docKey in const [
      'videoIndex',
      'practiceStats',
      'practicePlan',
      'fourBeatBucket',
    ]) {
      for (final release in releases) {
        final raw = _readFixture(release, docKey);
        final encoded = await _contracts[docKey]!.writeBack(raw);
        expect(
          encoded['version'],
          raw['version'],
          reason: '$release $docKey 写回后版本不变',
        );
      }
    }
  });
}
