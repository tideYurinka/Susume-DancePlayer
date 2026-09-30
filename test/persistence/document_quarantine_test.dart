import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/persistence/document_quarantine.dart';
import 'package:dance_learning_app/persistence/document_read_outcome.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_video_document_storage.dart';

/// 留档：
/// - 只读三种原因各产生一份留档，内容等于原文；
/// - 幂等（内容寻址）：同一份内容重复读出只留一份，内容不同各留一份；
/// - 不占写链：不引入「已留档」状态位（旁路文件被删后再读会重新留档）；
/// - 留档失败 = 整次写回失败：异常向上、盘上原文一字未动；
/// - 路径与文档同目录、名字含原因与内容哈希；不自动清理；
/// - 删除这支舞与恢复整机备份两条绕过版本政策的路径各有结论。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('document_quarantine');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  File markersFile() => File(p.join(tempDir.path, 'markers_abc.json'));
  File localFile() => File(p.join(tempDir.path, 'local_abc.json'));

  AtomicVideoDocumentStorage makeReal() => AtomicVideoDocumentStorage(
        markersFile: markersFile(),
        localFile: localFile(),
      );

  /// 盘上该文档的旁路留档文件（同目录、名字含 `quarantine-`）。
  List<File> sidecars() => tempDir
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).contains('.quarantine-'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  /// 留档的对外证据（真实文件读盘、内存 fake 读记录），真实与 fake 双跑。
  List<String> quarantinedContents(VideoDocumentStorage storage) {
    if (storage is AtomicVideoDocumentStorage) {
      return [for (final file in sidecars()) file.readAsStringSync()];
    }
    return (storage as InMemoryVideoDocumentStorage).quarantined.values.toList();
  }

  String sidecarNameOf(VideoDocumentStorage storage) {
    if (storage is AtomicVideoDocumentStorage) {
      return p.basename(sidecars().single.path);
    }
    return (storage as InMemoryVideoDocumentStorage).quarantined.keys.single;
  }

  /// 清掉已积累的留档（换文件时的旧内容留档不参与本轮断言）。
  void clearQuarantine(VideoDocumentStorage storage) {
    if (storage is AtomicVideoDocumentStorage) {
      for (final file in sidecars()) {
        file.deleteSync();
      }
    } else {
      (storage as InMemoryVideoDocumentStorage).quarantined.clear();
    }
  }

  for (final (label, make) in [
    ('真实文件', makeReal),
    ('内存 fake', () => InMemoryVideoDocumentStorage()),
  ]) {
    group(label, () {
      test('只读三种原因各产生一份留档，且留档内容等于原文', () async {
        final cases = <DocumentReadOnlyReason, String>{
          DocumentReadOnlyReason.aboveCurrent: '{"version":99,"meta":{"mirrored":true}}',
          DocumentReadOnlyReason.belowFloor: '{"version":6,"meta":{"mirrored":true}}',
          DocumentReadOnlyReason.unreadableVersionHeader: '{"meta":{"mirrored":true}}',
        };
        for (final entry in cases.entries) {
          final storage = make();
          await storage.saveMarkers(
            jsonDecode(entry.value) as Map<String, dynamic>,
          );
          clearQuarantine(storage);
          final outcome =
              await VideoDocumentCoordinator(storage).readMarkersOutcome();
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
          expect(
            (outcome as DocumentReadOnly<MarkersDocument>).reason,
            entry.key,
          );
          expect(
            quarantinedContents(storage),
            [entry.value],
            reason: '${entry.key} 应留档一份原文',
          );
        }
      });

      test('幂等（内容寻址）：同一内容重复读出只留一份，内容不同各留一份', () async {
        final storage = make();
        await storage.saveMarkers(const {
          'version': 99,
          'meta': {'mirrored': true},
        });
        final coordinator = VideoDocumentCoordinator(storage);
        await coordinator.readMarkersOutcome();
        await coordinator.readMarkersOutcome();
        await coordinator.readMarkers();
        expect(quarantinedContents(storage), hasLength(1));

        // 内容不同（同原因、不同原文）→ 各留一份。
        await storage.saveMarkers(const {
          'version': 98,
          'meta': {'mirrored': false},
        });
        await coordinator.readMarkersOutcome();
        expect(quarantinedContents(storage), hasLength(2));
      });

      test('不引入「已留档」状态位：旁路文件被删后再读会重新留档', () async {
        final storage = make();
        await storage.saveMarkers(const {'version': 99});
        final coordinator = VideoDocumentCoordinator(storage);
        await coordinator.readMarkersOutcome();
        expect(quarantinedContents(storage), hasLength(1));

        if (storage is AtomicVideoDocumentStorage) {
          await sidecars().single.delete();
        } else {
          (storage as InMemoryVideoDocumentStorage).quarantined.clear();
        }
        await coordinator.readMarkersOutcome();
        expect(
          quarantinedContents(storage),
          hasLength(1),
          reason: '幂等靠内容寻址，不靠「已留档」状态位',
        );
      });

      test('路径与文档同目录、名字含原因与内容哈希；可写读不留档', () async {
        final storage = make();
        await storage.saveMarkers(const MarkersDocument().toJson());
        await VideoDocumentCoordinator(storage).readMarkersOutcome();
        expect(quarantinedContents(storage), isEmpty, reason: '可写读不留档');

        await storage.saveMarkers(const {'version': 99});
        await VideoDocumentCoordinator(storage).readMarkersOutcome();
        final name = sidecarNameOf(storage);
        expect(name, contains('markers_abc'));
        expect(name, contains('.quarantine-'));
        expect(name, contains('aboveCurrent'));
        expect(
          RegExp(r'[0-9a-f]{16}').hasMatch(name),
          isTrue,
          reason: '名字含 16 位内容哈希：$name',
        );
      });

      test('local 侧同款：只读读出也留档', () async {
        final storage = make();
        await storage.saveLocal(const {
          'version': 99,
          'prefs': {'layoutLocked': true},
        });
        final outcome =
            await VideoDocumentCoordinator(storage).readLocalOutcome();
        expect(outcome, isA<DocumentReadOnly<dynamic>>());
        expect(
          (outcome as DocumentReadOnly<dynamic>).reason,
          DocumentReadOnlyReason.aboveCurrent,
        );
        expect(quarantinedContents(storage), hasLength(1));
        expect(sidecarNameOf(storage), contains('local_abc'));
      });
    });
  }

  group('原始文件缝的破坏性动词（真实文件）', () {
    test('留档失败 = 整次写回失败：异常向上、盘上原文一字未动', () async {
      final storage = makeReal();
      const original = {'version': 99, 'meta': {'mirrored': true}};
      await storage.saveMarkers(Map<String, dynamic>.of(original));
      final before = await markersFile().readAsString();
      // 用同名目录占住旁路文件路径，使留档写失败。
      final blocked = p.join(
        tempDir.path,
        DocumentQuarantine.sidecarName(
          markersFile().path,
          before,
          DocumentReadOnlyReason.aboveCurrent,
        ),
      );
      await Directory(blocked).create(recursive: true);

      await expectLater(
        storage.saveMarkers(const {'version': 8}),
        throwsA(isA<FileSystemException>()),
      );
      expect(await markersFile().readAsString(), before, reason: '原文一字未动');
      expect(
        tempDir.listSync().whereType<File>().map((file) => p.basename(file.path)),
        ['markers_abc.json'],
        reason: '留档失败不落任何文件（含不留临时残件）',
      );
    });

    test('恢复整机备份的全量替换：覆盖只读原文前先留档', () async {
      final storage = makeReal();
      const original = {'version': 99, 'meta': {'mirrored': true}};
      await storage.saveMarkers(Map<String, dynamic>.of(original));
      const fromBackup = {'version': 8, 'meta': {'signature': {'song': '海草舞'}}};

      await storage.saveMarkers(Map<String, dynamic>.of(fromBackup));

      expect(quarantinedContents(storage), [jsonEncode(original)]);
      expect(
        jsonDecode(await markersFile().readAsString()),
        fromBackup,
        reason: '覆盖照常发生（留档不阻断恢复，只保全原文）',
      );
    });

    test('原子读改写（mutate）也盖：改写只读原文前先留档', () async {
      final storage = makeReal();
      const original = {'version': 99, 'meta': {'mirrored': true}};
      await storage.saveMarkers(Map<String, dynamic>.of(original));

      await storage.mutateMarkers((json, {required bool present}) {
        json['docReserved'] = 1;
      });

      expect(quarantinedContents(storage), [jsonEncode(original)]);
    });

    test('删除路径的留档失败同样异常向上：一份文件都不删', () async {
      final storage = makeReal();
      const original = {'version': 99};
      await storage.saveMarkers(Map<String, dynamic>.of(original));
      final before = await markersFile().readAsString();
      final blocked = p.join(
        tempDir.path,
        DocumentQuarantine.sidecarName(
          markersFile().path,
          before,
          DocumentReadOnlyReason.aboveCurrent,
        ),
      );
      await Directory(blocked).create(recursive: true);

      await expectLater(
        storage.delete(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await markersFile().readAsString(), before, reason: '原文未删未动');
    });

    test('删除这支舞：删除只读原文前先留档，随后两份文档照常删除', () async {
      final storage = makeReal();
      const original = {'version': 99, 'meta': {'mirrored': true}};
      await storage.saveMarkers(Map<String, dynamic>.of(original));
      await storage.saveLocal(const {'version': 99});

      await storage.delete();

      expect(quarantinedContents(storage), hasLength(2), reason: '两份只读文档各留一份');
      expect(markersFile().existsSync(), isFalse);
      expect(localFile().existsSync(), isFalse);
    });

    test('删除可写文档不留档：内容读得懂就没有第二份原件的必要', () async {
      final storage = makeReal();
      await storage.saveMarkers(const MarkersDocument().toJson());
      await storage.saveLocal(const {'version': 3});

      await storage.delete();

      expect(quarantinedContents(storage), isEmpty);
    });

    test('不自动清理：留档旁路文件不被后续删除或覆盖清掉', () async {
      final storage = makeReal();
      await storage.saveMarkers(const {'version': 99});
      await VideoDocumentCoordinator(storage).readMarkersOutcome();
      final sidecar = sidecars().single;

      // 换一份可写文档并整份覆盖、再删除另一支文档：旁路文件仍在。
      await storage.saveMarkers(const MarkersDocument().toJson());
      await storage.delete();

      expect(sidecar.existsSync(), isTrue, reason: '留档不自动清理');
    });
  });
}
