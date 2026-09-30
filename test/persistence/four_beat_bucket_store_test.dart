import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:dance_learning_app/stats/four_beat_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';

/// 每舞桶分片文档与 store（见词条「四拍桶」；字段声明机制）：
/// 字段声明往返、版本门严格、逐层陌生键保底、容错读兜底、改名
/// write-through、删除清理。
void main() {
  final sig = const SongSignature(dancer: '如', song: 'My Love', remark: '9人版');
  final other = const SongSignature(song: 'Solo');

  DateTime day(int d) => DateTime(2026, 9, d);

  FourBeatBucketCredit credit(
    int bucket, {
    double wallSeconds = 0,
    int sweeps = 0,
    int dayOfMonth = 5,
    double density = 1,
  }) => FourBeatBucketCredit(
    day: day(dayOfMonth),
    bucket: bucket,
    wallSeconds: wallSeconds,
    sweeps: sweeps,
    density: density,
  );

  FourBeatBucketDay buckets(
    Map<FourBeatBucketKey, FourBeatBucketValue> value,
  ) => FourBeatBucketDay(buckets: value);

  group('分片文档 JSON 映射', () {
    test('JSON 形状：版本 + 署名段 + 账本段逐日逐桶', () {
      final shard = FourBeatBucketShard(
        signature: sig,
        days: {
          '2026-09-05': buckets({
            const FourBeatBucketKey(1, 3): const FourBeatBucketValue(
              wallSeconds: 12.5,
              sweeps: 2,
            ),
          }),
        },
      );
      final json = shard.toJson();
      expect(json['version'], 1);
      expect(json['signature'], {
        'dancer': '如',
        'song': 'My Love',
        'remark': '9人版',
      });
      expect(json['ledger'], {
        'days': {
          '2026-09-05': {
            '3': {'wallSeconds': 12.5, 'sweeps': 2},
          },
        },
      });
    });

    test('往返保留署名、逐日逐桶与版本头', () {
      final shard = FourBeatBucketShard(
        signature: sig,
        days: {
          '2026-09-05': buckets({
            const FourBeatBucketKey(1, 3): const FourBeatBucketValue(
              wallSeconds: 12.5,
              sweeps: 2,
            ),
          }),
          '2026-09-06': buckets({
            const FourBeatBucketKey(1, 0): const FourBeatBucketValue(
              wallSeconds: 4.0,
              sweeps: 1,
            ),
          }),
        },
      );
      final restored = FourBeatBucketShard.fromJson(shard.toJson());
      expect(restored.signature, sig);
      expect(
        restored
            .days['2026-09-05']!
            .buckets[const FourBeatBucketKey(1, 3)]!
            .wallSeconds,
        12.5,
      );
      expect(
        restored
            .days['2026-09-05']!
            .buckets[const FourBeatBucketKey(1, 3)]!
            .sweeps,
        2,
      );
      expect(
        restored
            .days['2026-09-06']!
            .buckets[const FourBeatBucketKey(1, 0)]!
            .wallSeconds,
        4.0,
      );
    });

    test('逐层陌生键保底：文档/段/元素与非桶序号键原样带回', () {
      final restored = FourBeatBucketShard.fromJson({
        'version': 1,
        'futureTop': 7,
        'signature': {'song': 'My Love', 'futureSig': true},
        'ledger': {
          'futureLedger': 'x',
          'days': {
            '2026-09-05': {
              'futureDay': 'y',
              '3': {'wallSeconds': 1.0, 'sweeps': 1, 'futureBucket': 'z'},
            },
          },
        },
      });
      expect(restored.extra, {'futureTop': 7});
      expect(restored.signatureExtra, {'futureSig': true});
      expect(restored.daysExtra, {'futureLedger': 'x'});
      final dayValue = restored.days['2026-09-05']!;
      expect(dayValue.extra, {'futureDay': 'y'});
      expect(dayValue.buckets[const FourBeatBucketKey(1, 3)]!.extra, {
        'futureBucket': 'z',
      });
      // 写回原样（保底区先展开、已登记字段后写）。
      final json = restored.toJson();
      expect(json['futureTop'], 7);
      expect((json['signature'] as Map)['futureSig'], isTrue);
      expect(
        ((json['ledger'] as Map)['days'] as Map)['2026-09-05'],
        containsPair('futureDay', 'y'),
      );
    });

    test('版本政策：低于地板为空态；版本头读不出与更高版本都读得出、只读', () {
      expect(FourBeatBucketShard.fromJson(const {}).days, isEmpty);
      expect(FourBeatBucketShard.fromJson(const {'version': '1'}).days, isEmpty);
      expect(
        FourBeatBucketShard.fromJson(const {'version': 0}).days,
        isEmpty,
        reason: '地板 1 之下是唯一合法的读空',
      );

      const higher = <String, dynamic>{
        'version': 2,
        'ledger': {
          'days': {
            '2026-09-05': {
              '3': {'wallSeconds': 1.0},
            },
          },
        },
      };
      expect(FourBeatBucketShard.fromJson(higher).days, isNotEmpty);
      expect(FourBeatBucketShard.versionPolicy.isWritable(higher), isFalse);
    });

    test('版本 1 的损坏内容按项跳过、不崩', () {
      final restored = FourBeatBucketShard.fromJson({
        'version': 1,
        'signature': {'song': 'My Love'},
        'ledger': {
          'days': {
            '2026-09-05': {
              '3': 'not-an-object',
              'x': {'wallSeconds': 1.0},
              '4': {'wallSeconds': 2.0, 'sweeps': 1},
            },
            'bad-day': 'not-an-object',
          },
        },
      });
      expect(restored.signature.song, 'My Love');
      final dayValue = restored.days['2026-09-05']!;
      expect(dayValue.buckets, hasLength(1));
      expect(dayValue.buckets[const FourBeatBucketKey(1, 4)]!.sweeps, 1);
      // 非桶序号/非对象的条目收进保底区，不冒充桶值。
      expect(dayValue.extra.keys, containsAll(['3', 'x']));
      // 日值非对象 = 损坏条目，按项跳过、不崩。
      expect(restored.days.containsKey('bad-day'), isFalse);
    });
  });

  group('store 累加与落盘', () {
    test('同桶多次记账累加墙钟与扫过', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(3, wallSeconds: 1.5, sweeps: 1)],
      );
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(3, wallSeconds: 2.5, sweeps: 1)],
      );
      await store.settle();

      final shard = await FourBeatBucketStore(storage).shard('hash1');
      expect(shard.signature, sig);
      expect(
        shard
            .days['2026-09-05']!
            .buckets[const FourBeatBucketKey(1, 3)]!
            .wallSeconds,
        closeTo(4.0, 1e-9),
      );
      expect(
        shard
            .days['2026-09-05']!
            .buckets[const FourBeatBucketKey(1, 3)]!
            .sweeps,
        2,
      );
    });

    test('分片按舞隔离：写一支舞不触碰另一支', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(1, wallSeconds: 1)],
      );
      await store.recordCredits(
        videoId: 'hash2',
        signature: other,
        credits: [credit(2, wallSeconds: 2)],
      );
      await store.settle();

      final reloaded = FourBeatBucketStore(storage);
      expect((await reloaded.shard('hash1')).days['2026-09-05']!.buckets.keys, [
        const FourBeatBucketKey(1, 1),
      ]);
      expect((await reloaded.shard('hash2')).days['2026-09-05']!.buckets.keys, [
        const FourBeatBucketKey(1, 2),
      ]);
      expect((await reloaded.shard('hash3')).days, isEmpty);
    });

    test('跨零点两天的桶分别承载', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [
          credit(0, wallSeconds: 1.0, dayOfMonth: 5),
          credit(0, wallSeconds: 1.0, dayOfMonth: 6),
        ],
      );
      await store.settle();
      final shard = await FourBeatBucketStore(storage).shard('hash1');
      expect(
        shard
            .days['2026-09-05']!
            .buckets[const FourBeatBucketKey(1, 0)]!
            .wallSeconds,
        1.0,
      );
      expect(
        shard
            .days['2026-09-06']!
            .buckets[const FourBeatBucketKey(1, 0)]!
            .wallSeconds,
        1.0,
      );
    });

    test('磁盘缺失/损坏按空态处理', () async {
      final storage = InMemoryFourBeatBucketStorage()
        ..setRaw('hash1', {'version': 1, 'ledger': 'not-a-map'});
      expect((await FourBeatBucketStore(storage).shard('hash1')).days, isEmpty);
    });

    test('不可写分片：读得出、写回被跳过（只读）', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final onDisk = <String, dynamic>{
        'version': 2,
        'ledger': {
          'days': {
            '2026-09-05': {
              '3': {'wallSeconds': 1.0},
            },
          },
        },
        'futureTop': 1,
      };
      storage.setRaw('hash1', onDisk);
      final store = FourBeatBucketStore(storage);

      expect((await store.shard('hash1')).days, isNotEmpty);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(0, wallSeconds: 2.0)],
      );
      await store.settle();

      expect(storage.saveCount, 0, reason: '只读分片不写回');
      expect(storage.savedJsonFor('hash1'), onDisk, reason: '盘上原文一字未动');
    });
  });

  group('桶键的倍频身份', () {
    test('倍频档桶键落盘为「倍频值:桶序号」，原样档保持裸整数', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [
          credit(3, wallSeconds: 1.0, sweeps: 1),
          credit(5, wallSeconds: 2.0, sweeps: 1, density: 2),
          credit(0, wallSeconds: 3.0, density: 0.25),
        ],
      );
      await store.settle();
      final day =
          (storage.savedJsonFor('hash1')!['ledger'] as Map)['days'] as Map;
      expect(
        (day['2026-09-05'] as Map).keys,
        containsAll(['3', '2:5', '0.25:0']),
      );
    });

    test('带倍频身份的键读回进桶、非桶键仍进陌生键保底', () {
      final restored = FourBeatBucketShard.fromJson({
        'version': 1,
        'ledger': {
          'days': {
            '2026-09-05': {
              '2:5': {'wallSeconds': 2.0, 'sweeps': 1},
              '0.5:3': {'wallSeconds': 4.0},
              'junk-key': {'wallSeconds': 9.0},
              '7': {'wallSeconds': 1.0, 'sweeps': 2},
            },
          },
        },
      });
      final day = restored.days['2026-09-05']!;
      expect(day.buckets[const FourBeatBucketKey(2, 5)]!.wallSeconds, 2.0);
      expect(day.buckets[const FourBeatBucketKey(0.5, 3)]!.wallSeconds, 4.0);
      expect(day.buckets[const FourBeatBucketKey(1, 7)]!.sweeps, 2);
      expect(day.extra.keys, ['junk-key']);
    });

    test('混格分片解码-编码往返：键逐字保留', () {
      const raw = {
        'version': 1,
        'signature': {'song': 'My Love'},
        'ledger': {
          'days': {
            '2026-09-05': {
              '3': {'wallSeconds': 1.0, 'sweeps': 1},
              '2:5': {'wallSeconds': 2.0, 'sweeps': 1},
              '0.25:0': {'wallSeconds': 3.0, 'sweeps': 0},
            },
          },
        },
      };
      final json = FourBeatBucketShard.fromJson(raw).toJson();
      expect(json['ledger'], raw['ledger']);
    });

    test('改倍频不写桶盘：无新桶账时 settle/flush 不落盘', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(1, wallSeconds: 1)],
      );
      await store.settle();
      expect(storage.saveCount, 1);
      // 模拟「只改了倍频、没有新练习」：无脏分片，磁盘逐字节不变。
      await store.settle();
      await store.settle();
      expect(storage.saveCount, 1);
    });
  });

  group('读取时投影不认段内档', () {
    // 500ms/拍、64 拍、首拍即强拍（复用既有 fixture）；分片带三种倍频
    // 身份的桶键。投影按文档**整曲档**建当前桶格——markers 段内档作为
    // 真实变化的输入传入，逐位一致即负断言承重。
    final beatDoc = uniformDownbeatGridDoc(seconds: 32);
    FourBeatBucketShard shard() => FourBeatBucketShard(
      signature: sig,
      days: {
        '2026-09-05': buckets({
          const FourBeatBucketKey(1, 3): const FourBeatBucketValue(
            wallSeconds: 1.0,
            sweeps: 1,
          ),
          const FourBeatBucketKey(2, 10): const FourBeatBucketValue(
            wallSeconds: 4.0,
            sweeps: 2,
          ),
          const FourBeatBucketKey(0.25, 0): const FourBeatBucketValue(
            wallSeconds: 8.0,
          ),
        }),
      },
    );

    test('文档带段内档与不带：投影逐位一致，桶键与桶明细一个字节不改', () {
      final plainMarkers = projectShardToCurrentGrid(
        shard(),
        marker_doc.MarkersDocument(beat: beatDoc),
      );
      final withSegments = projectShardToCurrentGrid(
        shard(),
        marker_doc.MarkersDocument(
          beat: beatDoc,
          segmentDensities: const {0: 2.0, 1: 0.5},
        ),
      );
      expect(withSegments, plainMarkers);
      // 投影口径字面不变（桶 3 = 裸键 1s + ×¼ 记录分摊 2s，秒守恒）。
      expect(plainMarkers['2026-09-05']![3], (wallSeconds: 3.0, sweeps: 1));
      expect(withSegments['2026-09-05']![3], (wallSeconds: 3.0, sweeps: 1));
    });

    test('段内档改动前后：分片落盘内容不受读取时投影影响（磁盘一个字节不动）', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [
          credit(3, wallSeconds: 1.0, sweeps: 1),
          credit(5, wallSeconds: 2.0, sweeps: 1, density: 2),
        ],
      );
      await store.settle();
      final bytesBefore = storage.savedJsonFor('hash1');

      final shard = await store.shard('hash1');
      projectShardToCurrentGrid(
        shard,
        marker_doc.MarkersDocument(
          beat: beatDoc,
          segmentDensities: const {0: 2.0},
        ),
      );
      await store.settle();
      await store.settle();

      expect(storage.saveCount, 1);
      expect(storage.savedJsonFor('hash1'), bytesBefore);
    });
  });

  group('改名 write-through', () {
    test('已有分片改名后署名改写并落盘', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(1, wallSeconds: 1)],
      );
      await store.settle();
      await store.migrateSignature('hash1', other);

      final shard = await FourBeatBucketStore(storage).shard('hash1');
      expect(shard.signature, other);
      expect(
        shard
            .days['2026-09-05']!
            .buckets[const FourBeatBucketKey(1, 1)]!
            .wallSeconds,
        1.0,
      );
    });

    test('无桶数据的舞改名不建文件', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.migrateSignature('hash1', sig);
      expect(storage.savedJsonFor('hash1'), isNull);
    });
  });

  group('删除清理', () {
    test('删除该舞分片后读回空态，其它舞保留', () async {
      final storage = InMemoryFourBeatBucketStorage();
      final store = FourBeatBucketStore(storage);
      await store.recordCredits(
        videoId: 'hash1',
        signature: sig,
        credits: [credit(1, wallSeconds: 1)],
      );
      await store.recordCredits(
        videoId: 'hash2',
        signature: other,
        credits: [credit(2, wallSeconds: 2)],
      );
      await store.settle();
      await store.deleteShard('hash1');

      final reloaded = FourBeatBucketStore(storage);
      expect((await reloaded.shard('hash1')).days, isEmpty);
      expect((await reloaded.shard('hash2')).days, isNotEmpty);
    });

    test('删除未落盘的舞不抛错', () async {
      final store = FourBeatBucketStore(InMemoryFourBeatBucketStorage());
      await store.deleteShard('missing');
    });
  });

  group('并发首读（时序暴露）', () {
    test('同一舞分片首读在飞时并发记账与改名：不空指针、既存账与本次账都保留', () async {
      final existing = FourBeatBucketShard(
        signature: sig,
        days: {
          '2026-09-05': buckets({
            const FourBeatBucketKey(1, 1): const FourBeatBucketValue(
              wallSeconds: 2,
              sweeps: 1,
            ),
          }),
        },
      );
      final storage = _SlowLoadStorage()..setRaw('hash1', existing.toJson());
      final store = FourBeatBucketStore(storage);

      // 首次导入命名（改名写-through）与播放位置采样同刻：两者都要先读同一
      // 份分片，慢读窗口内不得让后到者读到空账面。
      await Future.wait([
        store.recordCredits(
          videoId: 'hash1',
          signature: sig,
          credits: [credit(3, wallSeconds: 1)],
        ),
        store.migrateSignature('hash1', other),
      ]);

      final shard = await store.shard('hash1');
      expect(
        shard.days['2026-09-05']!.buckets.keys,
        containsAll([
          const FourBeatBucketKey(1, 1),
          const FourBeatBucketKey(1, 3),
        ]),
        reason: '既存账不被空态覆盖、本次账照常并入',
      );
    });
  });
}

/// loadOrNull 慢读（真实文件 IO 的读窗口）：并发首读因此可复现。
class _SlowLoadStorage extends InMemoryFourBeatBucketStorage {
  @override
  Future<Map<String, dynamic>?> loadOrNull(String videoId) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return super.loadOrNull(videoId);
  }
}
