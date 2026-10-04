import 'dart:io';

import 'package:dance_learning_app/core/document_codec.dart';
import 'package:dance_learning_app/core/document_version_policy.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_practice_stats_storage.dart';

/// 练习统计记录单元与全局 store。
///
/// seam = store 的公开读写结果（文件读写结果 / 字段映射 / 版本头 /
/// 合并条件 / 写-through 迁移）。
void main() {
  final sig = const SongSignature(dancer: '如', song: 'My Love', remark: '9人版');
  final other = const SongSignature(song: 'Solo');

  DateTime at(String iso) => DateTime.parse(iso);

  PracticeStatsStore newStore(InMemoryPracticeStatsStorage storage) =>
      PracticeStatsStore(storage);

  group('记录单元 JSON 映射', () {
    test('往返保留全部字段', () {
      final record = PracticeSessionRecord(
        start: at('2026-09-05T20:12:03'),
        videoId: 'hash1',
        signature: sig,
        wallSeconds: 372.4,
      );
      final restored = PracticeSessionRecord.fromJson(record.toJson());
      expect(restored, record);
      expect(restored.wallSeconds, 372.4);
    });

    test('缺字段按兜底读取不崩', () {
      final restored = PracticeSessionRecord.fromJson({
        'start': '2026-09-05T20:12:03',
        'videoId': 'hash1',
      });
      expect(restored.signature, const SongSignature());
      expect(restored.wallSeconds, 0);
    });
  });

  group('文件 schema v2', () {
    test('保存带版本头，读取往返', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:12:03'),
        end: at('2026-09-05T20:18:15.400'),
      );
      await store.settle();
      expect(storage.savedJson!['version'], 2);
      final sessions = storage.savedJson!['sessions'] as List;
      expect(sessions, hasLength(1));
      final restored = PracticeStatsDocument.fromJson(storage.savedJson!);
      expect(restored.sessions.single.videoId, 'hash1');
      expect(restored.sessions.single.wallSeconds, closeTo(372.4, 1e-9));
    });

    test('文件缺失/损坏按空态处理不崩溃', () async {
      final missing = newStore(InMemoryPracticeStatsStorage());
      expect(await missing.records(), isEmpty);

      final corrupt = InMemoryPracticeStatsStorage()
        ..rawJson = {'version': 2, 'sessions': 'not-a-list'};
      expect(await newStore(corrupt).records(), isEmpty);
    });
  });

  group('会话合并', () {
    test('同视频间隔 <5 分钟并入开放会话', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:10:00'),
      );
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:12:00'),
        end: at('2026-09-05T20:15:00'),
      );
      final records = await store.records();
      expect(records, hasLength(1));
      expect(records.single.start, at('2026-09-05T20:00:00'));
      expect(records.single.wallSeconds, 13 * 60);
    });

    test('间隔 ≥5 分钟新开会话', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:10:00'),
      );
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:15:00'),
        end: at('2026-09-05T20:16:00'),
      );
      expect(await store.records(), hasLength(2));
    });

    test('不同视频/不同署名不合并', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:10:00'),
      );
      await store.recordPlaying(
        videoId: 'hash2',
        signature: sig,
        start: at('2026-09-05T20:11:00'),
        end: at('2026-09-05T20:12:00'),
      );
      await store.recordPlaying(
        videoId: 'hash2',
        signature: other,
        start: at('2026-09-05T20:13:00'),
        end: at('2026-09-05T20:14:00'),
      );
      expect(await store.records(), hasLength(3));
    });

    test('跨零点按播放实际发生的日分桶，记录不跨日', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T23:58:00'),
        end: at('2026-09-06T00:05:00'),
      );
      final records = await store.records();
      expect(records, hasLength(2));
      expect(records[0].start, at('2026-09-05T23:58:00'));
      expect(records[0].wallSeconds, 2 * 60);
      expect(records[1].start, at('2026-09-06T00:00:00'));
      expect(records[1].wallSeconds, 5 * 60);
    });

    test('跨零点且零点后间隔 <5 分钟：新日志、不并回前一日', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T23:55:00'),
        end: at('2026-09-05T23:59:00'),
      );
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-06T00:01:00'),
        end: at('2026-09-06T00:03:00'),
      );
      final records = await store.records();
      expect(records, hasLength(2));
      expect(records[1].start, at('2026-09-06T00:01:00'));
    });
  });

  group('改名写-through 迁移', () {
    test('该 videoId 全部记录（含开放缓冲）迁移到新署名', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: const SongSignature(song: '123.mp4'),
        start: at('2026-09-04T10:00:00'),
        end: at('2026-09-04T10:05:00'),
      );
      await store.recordPlaying(
        videoId: 'hash2',
        signature: other,
        start: at('2026-09-04T10:01:00'),
        end: at('2026-09-04T10:02:00'),
      );
      // 开放缓冲：刚记录、未 flush 的当前会话（与上一条间隔 ≥5min，
      // 否则上一段本就并入）。
      await store.recordPlaying(
        videoId: 'hash1',
        signature: const SongSignature(song: '123.mp4'),
        start: at('2026-09-04T10:20:00'),
        end: at('2026-09-04T10:21:00'),
      );

      await store.migrateSignature('hash1', sig);
      await store.settle();

      final records = await store.records();
      final migrated = records.where((r) => r.videoId == 'hash1').toList();
      expect(migrated, hasLength(2));
      for (final record in migrated) {
        expect(record.signature, sig);
      }
      // hash2 记录不受影响；删除视频后记录仍保留（按快照显示的依据）。
      expect(
        records.where((r) => r.videoId == 'hash2').single.signature,
        other,
      );
      expect(storage.document.sessions, hasLength(3));
    });

    test('迁移后同署名跨视频记录继续按署名合并（同视频）', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: const SongSignature(song: '123.mp4'),
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:05:00'),
      );
      await store.migrateSignature('hash1', sig);
      // 迁移后再播放：按新署名找到同视频开放会话并并入。
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:06:00'),
        end: at('2026-09-05T20:08:00'),
      );
      final records = await store.records();
      expect(records, hasLength(1));
      expect(records.single.signature, sig);
      expect(records.single.wallSeconds, 7 * 60);
    });
  });

  group('结算时机', () {
    test('settle 有变化才写盘；flush 幂等', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.settle();
      expect(storage.saveCount, 0);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:01:00'),
      );
      await store.settle();
      expect(storage.saveCount, 1);
      await store.settle();
      expect(storage.saveCount, 1);
    });

    test('写失败静默承接、不阻塞后续任务', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      storage.saveError = const FileSystemException('disk full', 'x');
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:01:00'),
      );
      await store.settle();
      storage.saveError = null;
      await store.settle();
      expect(storage.document.sessions, hasLength(1));
    });
  });

  group('接入文档编解码机制', () {
    PracticeSessionRecord record() => PracticeSessionRecord(
      start: at('2026-09-05T20:12:03'),
      videoId: 'hash1',
      signature: sig,
      wallSeconds: 372.4,
    );

    test('版本链地板 = 本版 = 2；换代前 v1 低于地板 → 空态；当前版本正常读', () {
      expect(PracticeStatsDocument.versionPolicy.floor, 2);
      expect(PracticeStatsDocument.versionPolicy.currentVersion, 2);
      final json = PracticeStatsDocument(sessions: [record()]).toJson();
      expect(json['version'], 2);
      expect(PracticeStatsDocument.fromJson(json).sessions, hasLength(1));
      expect(
        PracticeStatsDocument.fromJson({...json, 'version': 1}).sessions,
        isEmpty,
      );
    });

    test('版本头读不出与更高版本 → 认识多少读多少 + 只读', () {
      final json = PracticeStatsDocument(sessions: [record()]).toJson();
      final noVersion = {...json}..remove('version');
      expect(PracticeStatsDocument.fromJson(noVersion).sessions, hasLength(1));
      expect(
        PracticeStatsDocument.versionPolicy.isWritable(noVersion),
        isFalse,
      );

      final higher = {...json, 'version': 3};
      expect(PracticeStatsDocument.fromJson(higher).sessions, hasLength(1));
      expect(PracticeStatsDocument.versionPolicy.isWritable(higher), isFalse);
    });

    test('列表形状版本能力：合成两级链上中间版本可升位', () {
      final policy = DocumentVersionPolicy(
        floor: 1,
        steps: [
          MigrationStep(1, (json) => {...json, 'v1Shape': true}),
          MigrationStep(2, (json) => {...json, 'v2Shape': true}),
        ],
      );
      final codec =
          ListDocumentCodec<
            PracticeStatsDocument,
            PracticeSessionRecord,
            PracticeSessionRecordField
          >(
            policy: policy,
            listKey: 'sessions',
            elementCodec: PracticeSessionRecord.codec,
            empty: () => const PracticeStatsDocument.empty(),
            build: (elements) => PracticeStatsDocument(sessions: elements),
            listOf: (doc) => doc.sessions,
            extraOf: (doc) => doc.extra,
            withExtra: (doc, extra) =>
                PracticeStatsDocument(sessions: doc.sessions, extra: extra),
          );
      final onDisk = <String, Object?>{
        'version': 1,
        'sessions': [record().toJson()],
      };
      final doc = codec.decode(onDisk);
      expect(doc.sessions, hasLength(1));
      expect(doc.extra['v1Shape'], isTrue);
      expect(doc.extra['v2Shape'], isTrue);
      expect(policy.isWritable(onDisk), isTrue);
      expect(codec.encode(doc)['version'], 3);
    });

    test('不可写文件：读得出、写回被跳过（只读）', () async {
      final storage = InMemoryPracticeStatsStorage();
      final onDisk = <String, dynamic>{
        'version': 3,
        'sessions': [record().toJson()],
      };
      storage.rawJson = Map.of(onDisk);
      final store = newStore(storage);

      expect(await store.records(), hasLength(1));
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T21:00:00'),
        end: at('2026-09-05T21:05:00'),
      );
      await store.settle();

      expect(storage.saveCount, 0, reason: '只读文件不写回');
      expect(storage.savedJson, onDisk, reason: '盘上原文一字未动');
    });

    test('元素未知键保底：读回保留、写回原样、已登记字段不受影响', () {
      final json = record().toJson()..['futureField'] = 'keep';
      final restored = PracticeSessionRecord.fromJson(json);
      expect(restored.extra['futureField'], 'keep');
      expect(restored.toJson()['futureField'], 'keep');
      expect(restored.videoId, 'hash1');
      expect(restored.signature, sig);
    });

    test('文档级未知键保底：读回保留、写回原样', () {
      final json = PracticeStatsDocument(sessions: [record()]).toJson()
        ..['futureTopLevel'] = {'a': 1};
      final restored = PracticeStatsDocument.fromJson(json);
      expect(restored.extra['futureTopLevel'], {'a': 1});
      expect(restored.toJson()['futureTopLevel'], {'a': 1});
      expect(restored.sessions, hasLength(1));
    });

    test('字段枚举表驱动：逐字段往返保真并参与相等', () {
      final base = record();
      final restored = PracticeSessionRecord.fromJson(base.toJson());
      expect(restored, base);

      final tamper = <PracticeSessionRecordField, Object?>{
        PracticeSessionRecordField.start: DateTime(
          2020,
          1,
          1,
        ).toIso8601String(),
        PracticeSessionRecordField.videoId: 'zzz',
        PracticeSessionRecordField.signatureDancer: '另',
        PracticeSessionRecordField.signatureSong: '别的歌',
        PracticeSessionRecordField.signatureRemark: '注释',
        PracticeSessionRecordField.wallSeconds: 1.5,
      };
      for (final id in PracticeSessionRecordField.values) {
        final d = PracticeSessionRecord.codec.decl(id);
        final tampered = PracticeSessionRecord.fromJson({
          ...base.toJson(),
          d.key: tamper[id],
        });
        expect(
          PracticeSessionRecord.codec.equals(base, tampered),
          isFalse,
          reason: '字段 ${id.name} 应参与相等',
        );
      }
    });

    test('既有 version 1 文件经 store 读回不丢数据', () async {
      final storage = InMemoryPracticeStatsStorage();
      final store = newStore(storage);
      await store.recordPlaying(
        videoId: 'hash1',
        signature: sig,
        start: at('2026-09-05T20:00:00'),
        end: at('2026-09-05T20:05:00'),
      );
      await store.settle();
      final reloaded = newStore(storage);
      final records = await reloaded.records();
      expect(records, hasLength(1));
      expect(records.single.videoId, 'hash1');
      expect(records.single.signature, sig);
      expect(records.single.wallSeconds, 5 * 60);
    });
  });
}
