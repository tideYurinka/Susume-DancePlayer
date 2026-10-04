import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/persistence/document_read_outcome.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_video_document_storage.dart';

/// 一等读结局：
/// - 三态：文件不在（可写）/ 听懂了（可写）/ 只读（原因具名）；
/// - 只读三种原因各自的结局类型与原因可观察，读出后盘上字节不变；
/// - 只读结局没有写回成员（类型上不可达覆盖没读懂的文件）；
/// - 空态只剩两个来源；「版本头不是整数」不再产生可写空态；
/// - 写回二态（已提交 / 被拒），拒写盘上不改。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('document_read_outcome');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  VideoDocumentStorage makeReal() => AtomicVideoDocumentStorage(
    markersFile: File(p.join(tempDir.path, 'markers_abc.json')),
    localFile: File(p.join(tempDir.path, 'local_abc.json')),
  );

  /// 真实文件读原始字节（「盘上一字未动」的证据）。
  Future<String> rawMarkersText(VideoDocumentStorage storage) async {
    if (storage is AtomicVideoDocumentStorage) {
      return File(p.join(tempDir.path, 'markers_abc.json')).readAsString();
    }
    return jsonEncode(
      (storage as InMemoryVideoDocumentStorage).markersSnapshot,
    );
  }

  /// local 文件读原始字节（同上）。
  Future<String> rawLocalText(VideoDocumentStorage storage) async {
    if (storage is AtomicVideoDocumentStorage) {
      return File(p.join(tempDir.path, 'local_abc.json')).readAsString();
    }
    return jsonEncode((storage as InMemoryVideoDocumentStorage).localSnapshot);
  }

  for (final (label, make) in [
    ('真实文件', makeReal),
    ('内存 fake', () => InMemoryVideoDocumentStorage()),
  ]) {
    group(label, () {
      group('一等读结局三态', () {
        test('文件不在 → 可写、可创建（空文档 + 提交成功）', () async {
          final storage = make();
          final coordinator = VideoDocumentCoordinator(storage);
          final outcome = await coordinator.readMarkersOutcome();
          expect(outcome, isA<DocumentAbsent<MarkersDocument>>());
          expect(outcome.document, const MarkersDocument.empty());
          final writable =
              outcome as WritableDocumentReadOutcome<MarkersDocument>;
          final result = await writable.write(
            (context) => context.document.withMirrored(true),
          );
          expect(result, isA<DocumentWriteCommitted<MarkersDocument>>());
          expect((await coordinator.readMarkers()).mirrored, isTrue);
        });

        test('听懂了（在链上）→ 可写、整份替换、逐层陌生键保底随行', () async {
          final storage = make();
          await storage.saveMarkers(const {
            'version': 8,
            'meta': {
              'mirrored': true,
              'metaReserved': {'newer': true},
            },
            'docReserved': 7,
          });
          final coordinator = VideoDocumentCoordinator(storage);
          final outcome = await coordinator.readMarkersOutcome();
          expect(outcome, isA<DocumentUnderstood<MarkersDocument>>());
          expect(outcome.document.mirrored, isTrue);
          final writable =
              outcome as WritableDocumentReadOutcome<MarkersDocument>;
          final result = await writable.write(
            (context) => context.document.withSegmentLines(const []),
          );
          expect(result, isA<DocumentWriteCommitted<MarkersDocument>>());
          final raw =
              jsonDecode(await rawMarkersText(storage)) as Map<String, dynamic>;
          expect(raw['version'], 8, reason: '无变化跳写：盘上原文一字未动');
          expect(raw['docReserved'], 7);
          expect((raw['meta'] as Map)['metaReserved'], {'newer': true});
        });
      });

      group('只读三原因：结局类型与原因可观察、盘上字节不变', () {
        test('高于本版 → aboveCurrent；认识多少读多少；不写回', () async {
          final storage = make();
          const forward = {
            'version': 99,
            'meta': {'mirrored': true},
            'docReserved': 1,
          };
          await storage.saveMarkers(Map<String, dynamic>.of(forward));
          final before = await rawMarkersText(storage);
          final outcome = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
          expect(
            (outcome as DocumentReadOnly<MarkersDocument>).reason,
            DocumentReadOnlyReason.aboveCurrent,
          );
          expect(outcome.document.mirrored, isTrue, reason: '认出多少读多少');
          expect(await rawMarkersText(storage), before);
        });

        test('低于地板 → belowFloor；空态；不写回', () async {
          final storage = make();
          const legacy = {
            'version': 6,
            'meta': {'mirrored': true},
          };
          await storage.saveMarkers(Map<String, dynamic>.of(legacy));
          final before = await rawMarkersText(storage);
          final outcome = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
          expect(
            (outcome as DocumentReadOnly<MarkersDocument>).reason,
            DocumentReadOnlyReason.belowFloor,
          );
          expect(outcome.document, const MarkersDocument.empty());
          expect(await rawMarkersText(storage), before);
        });

        test('版本头读不出 → unreadableVersionHeader；照读；不写回', () async {
          final storage = make();
          const headless = {
            'version': '8',
            'meta': {'mirrored': true},
            'docReserved': 2,
          };
          await storage.saveMarkers(Map<String, dynamic>.of(headless));
          final before = await rawMarkersText(storage);
          final outcome = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
          expect(
            (outcome as DocumentReadOnly<MarkersDocument>).reason,
            DocumentReadOnlyReason.unreadableVersionHeader,
          );
          expect(outcome.document.mirrored, isTrue, reason: '认出多少读多少');
          expect(await rawMarkersText(storage), before);
        });

        test('只读结局不是可写结局：类型上没有写回入口', () async {
          final storage = make();
          await storage.saveMarkers(const {'version': 99});
          final outcome = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(
            outcome,
            isNot(isA<WritableDocumentReadOutcome<MarkersDocument>>()),
          );
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
        });
      });

      group('空态只剩两个来源；版本头不是整数不再产生可写空态', () {
        test('文件不在与本体解析不出对象都按空态 + 可写创建', () async {
          final empty = VideoDocumentCoordinator(make());
          final absent = await empty.readMarkersOutcome();
          expect(absent, isA<DocumentAbsent<MarkersDocument>>());
          expect(absent.document, const MarkersDocument.empty());

          // 本体解析不出对象（顶层非对象 / 损坏）：文件层与「文件不在」
          // 同源（都是 null），同按空态 + 可写创建。
          final storage = make();
          if (storage is AtomicVideoDocumentStorage) {
            await File(p.join(tempDir.path, 'markers_abc.json'))
                .writeAsString('[1, 2]');
          } else {
            await (storage as InMemoryVideoDocumentStorage).saveMarkers(const {
              'broken': true,
            });
            storage.corruptMarkers();
          }
          final corrupt = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(corrupt, isA<DocumentAbsent<MarkersDocument>>());
          expect(corrupt.document, const MarkersDocument.empty());
        });

        test('版本头不是整数 → 只读、照读（不是可写空态）', () async {
          final storage = make();
          await storage.saveMarkers(const {
            'version': '8',
            'meta': {'mirrored': true},
          });
          final outcome = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
          expect(outcome.document, isNot(const MarkersDocument.empty()));
          expect(
            outcome,
            isNot(isA<WritableDocumentReadOutcome<MarkersDocument>>()),
          );
        });

        test('存在但内容为空对象 → 版本头缺失、只读（不折叠成可写空态）', () async {
          final storage = make();
          await storage.saveMarkers(const <String, dynamic>{});
          final outcome = await VideoDocumentCoordinator(storage)
              .readMarkersOutcome();
          expect(outcome, isA<DocumentReadOnly<MarkersDocument>>());
          expect(
            (outcome as DocumentReadOnly<MarkersDocument>).reason,
            DocumentReadOnlyReason.unreadableVersionHeader,
          );
          expect(
            outcome,
            isNot(isA<WritableDocumentReadOutcome<MarkersDocument>>()),
          );
        });
      });

      group('写回二态', () {
        test('读与写之间盘上换成只读文件 → 被拒且盘上不改', () async {
          final storage = make();
          await storage.saveMarkers(const MarkersDocument().toJson());
          final coordinator = VideoDocumentCoordinator(storage);
          final outcome = await coordinator.readMarkersOutcome();
          expect(outcome, isA<DocumentUnderstood<MarkersDocument>>());

          // 读之后、写之前换成更高版本（唯一写回入口仍试图写）。
          const forward = {
            'version': 99,
            'meta': {'mirrored': true},
          };
          await storage.saveMarkers(Map<String, dynamic>.of(forward));
          final before = await rawMarkersText(storage);

          final writable =
              outcome as WritableDocumentReadOutcome<MarkersDocument>;
          final result = await writable.write(
            (context) => context.document.withRange(startMs: 1, endMs: 2),
          );
          expect(result, isA<DocumentWriteRejected<MarkersDocument>>());
          expect(
            (result as DocumentWriteRejected<MarkersDocument>).reason,
            DocumentReadOnlyReason.aboveCurrent,
          );
          expect(await rawMarkersText(storage), before);
        });
      });

      // local 侧与 markers 同款接缝（同一份政策形状、同一结局类型）：
      // 三原因 + 字节不变 + 写回被拒各一条，避免只有 markers 被覆盖。
      group('local 读结局', () {
        test('高于本版 → aboveCurrent；不写回', () async {
          final storage = make();
          await storage.saveLocal(const {
            'version': 99,
            'prefs': {'layoutLocked': true},
          });
          final before = await rawLocalText(storage);
          final outcome = await VideoDocumentCoordinator(storage)
              .readLocalOutcome();
          expect(outcome, isA<DocumentReadOnly<LocalDocument>>());
          expect(
            (outcome as DocumentReadOnly<LocalDocument>).reason,
            DocumentReadOnlyReason.aboveCurrent,
          );
          expect(outcome.document.layoutLocked, isTrue);
          expect(await rawLocalText(storage), before);
        });

        test('低于地板 → belowFloor 空态；版本头读不出 → 照读只读', () async {
          final storage = make();
          await storage.saveLocal(const {
            'version': 2,
            'prefs': {'layoutLocked': true},
          });
          final below = await VideoDocumentCoordinator(storage)
              .readLocalOutcome();
          expect(below, isA<DocumentReadOnly<LocalDocument>>());
          expect(
            (below as DocumentReadOnly<LocalDocument>).reason,
            DocumentReadOnlyReason.belowFloor,
          );
          expect(below.document, const LocalDocument.empty());

          final headless = make();
          await headless.saveLocal(const {
            'prefs': {'layoutLocked': true},
          });
          final outcome = await VideoDocumentCoordinator(headless)
              .readLocalOutcome();
          expect(outcome, isA<DocumentReadOnly<LocalDocument>>());
          expect(
            (outcome as DocumentReadOnly<LocalDocument>).reason,
            DocumentReadOnlyReason.unreadableVersionHeader,
          );
          expect(outcome.document.layoutLocked, isTrue);
        });

        test('可写读写回提交；读与写之间换成只读文件 → 被拒且盘上不改', () async {
          final storage = make();
          await storage.saveLocal(const LocalDocument().toJson());
          final coordinator = VideoDocumentCoordinator(storage);
          final outcome = await coordinator.readLocalOutcome();
          expect(outcome, isA<DocumentUnderstood<LocalDocument>>());

          await storage.saveLocal(const {'version': 99});
          final before = await rawLocalText(storage);
          final writable =
              outcome as WritableDocumentReadOutcome<LocalDocument>;
          final result = await writable.write(
            (context) => context.document.withLayoutLocked(true),
          );
          expect(result, isA<DocumentWriteRejected<LocalDocument>>());
          expect(
            (result as DocumentWriteRejected<LocalDocument>).reason,
            DocumentReadOnlyReason.aboveCurrent,
          );
          expect(await rawLocalText(storage), before);
        });
      });
    });
  }
}
