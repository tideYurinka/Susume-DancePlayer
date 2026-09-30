import 'dart:async';

import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_recorder.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_practice_facts.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/uniform_test_grid.dart';

/// 记录器接线四拍桶（见词条「四拍桶」）：既有事实流判定 + 位置流分摊。
/// 断言只看两个 store 的外部结果（会话总时长与桶分片）。
void main() {
  final sig = const SongSignature(song: 'My Love');

  late FakePlaybackEngine engine;
  late FakePracticeFactsSource facts;
  late InMemoryPracticeStatsStorage statsStorage;
  late InMemoryFourBeatBucketStorage bucketStorage;
  late PracticeStatsStore store;
  late FourBeatBucketStore buckets;
  late StreamController<Duration> positions;
  late PracticeStatsRecorder recorder;

  final grid = UniformTestGrid();
  var gridReady = true;
  var densityValue = 1.0;

  DateTime now = DateTime.parse('2026-09-05T20:00:00');

  setUp(() {
    engine = FakePlaybackEngine();
    facts = FakePracticeFactsSource(engine);
    statsStorage = InMemoryPracticeStatsStorage();
    store = PracticeStatsStore(statsStorage);
    bucketStorage = InMemoryFourBeatBucketStorage();
    buckets = FourBeatBucketStore(bucketStorage);
    positions = StreamController<Duration>.broadcast();
    gridReady = true;
    now = DateTime.parse('2026-09-05T20:00:00');
    recorder = PracticeStatsRecorder(
      facts: facts.stream,
      store: store,
      clock: () => now,
      positions: positions.stream,
      buckets: buckets,
      grid: () => gridReady ? grid : null,
      density: () => densityValue,
    );
    recorder.updateVideo(videoId: 'hash1', signature: sig, fallbackName: 'x');
  });

  tearDown(() => positions.close());

  Future<void> settle() async {
    for (var i = 0; i < 4; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> play() async {
    await engine.play();
    await settle();
  }

  Future<void> pause() async {
    await engine.pause();
    await settle();
  }

  Future<void> emitPosition(
    Duration mediaPosition, {
    Duration wallStep = const Duration(milliseconds: 100),
  }) async {
    now = now.add(wallStep);
    positions.add(mediaPosition);
    await settle();
  }

  /// 以 [step] 步长把媒介位置从 [from] 推进到 [to]（含端点）。
  Future<void> playTo(
    Duration to, {
    Duration from = const Duration(milliseconds: 100),
    Duration step = const Duration(milliseconds: 100),
  }) async {
    var position = from;
    while (position <= to) {
      await emitPosition(position);
      position += step;
    }
  }

  Future<FourBeatBucketShard> reloadShard() =>
      FourBeatBucketStore(bucketStorage).shard('hash1');

  test('网格就绪时播放产生桶数据并落盘，重开后保持', () async {
    await play();
    await playTo(
      const Duration(seconds: 2),
      step: const Duration(milliseconds: 100),
    );
    await pause();
    await recorder.settleAndFlush();

    // 重开（新 store 读同一存储）后分片仍在。
    final shard = await reloadShard();
    expect(shard.signature, sig);
    final day = shard.days['2026-09-05']!;
    expect(
      day.buckets[const FourBeatBucketKey(1, 0)]!.wallSeconds,
      closeTo(1.8, 1e-6),
    );
    expect(day.buckets[const FourBeatBucketKey(1, 0)]!.sweeps, 1);
    expect(
      day.buckets[const FourBeatBucketKey(1, 1)]!.wallSeconds,
      closeTo(0.1, 1e-6),
    );
  });

  test('暂停与翻看的时间不入桶', () async {
    await play();
    await playTo(const Duration(seconds: 1));
    await pause();
    now = now.add(const Duration(minutes: 5)); // 暂停/翻看 5 分钟
    await play();
    await playTo(
      const Duration(seconds: 2),
      from: const Duration(milliseconds: 1100),
    );
    await pause();
    await recorder.settleAndFlush();

    final shard = await reloadShard();
    final day = shard.days['2026-09-05']!;
    // 两段连续播放各只记采样步长（首采样立基准），5 分钟暂停不计。
    expect(
      day.buckets[const FourBeatBucketKey(1, 0)]!.wallSeconds,
      closeTo(1.7, 1e-6),
    );
    expect(day.buckets[const FourBeatBucketKey(1, 0)]!.sweeps, 1);
  });

  test('网格未就绪不产桶、只记总时长；中途就绪后从当下产桶', () async {
    gridReady = false;
    await play();
    await playTo(const Duration(seconds: 1));
    expect((await buckets.shard('hash1')).days, isEmpty);

    gridReady = true;
    await playTo(
      const Duration(seconds: 2),
      from: const Duration(milliseconds: 1100),
    );
    await pause();
    await recorder.settleAndFlush();

    final shard = await reloadShard();
    expect(
      shard
          .days['2026-09-05']!
          .buckets[const FourBeatBucketKey(1, 0)]!
          .wallSeconds,
      closeTo(0.8, 1e-6),
    );
    // 会话总时长照涨（含无网格的 1 秒）。
    final sessions = await store.records();
    expect(sessions.single.wallSeconds, closeTo(2.0, 1e-6));
  });

  test('跳变处断开：不跨越中间桶、不给中间桶补账', () async {
    await play();
    await playTo(
      const Duration(milliseconds: 500),
      step: const Duration(milliseconds: 100),
    );
    // 拖动到桶 2（跳变），再继续推进。
    await emitPosition(const Duration(seconds: 5));
    await playTo(
      const Duration(seconds: 6),
      from: const Duration(milliseconds: 5100),
    );
    await pause();
    await recorder.settleAndFlush();

    final shard = await reloadShard();
    final day = shard.days['2026-09-05']!;
    expect(
      day.buckets.containsKey(const FourBeatBucketKey(1, 1)),
      isFalse,
    ); // 中间桶没被补账
    expect(day.buckets[const FourBeatBucketKey(1, 0)]!.sweeps, 0); // 没越过桶 0 右边界
    expect(
      day.buckets[const FourBeatBucketKey(1, 0)]!.wallSeconds,
      closeTo(0.4, 1e-6),
    );
    expect(
      day.buckets[const FourBeatBucketKey(1, 2)]!.wallSeconds,
      greaterThan(0),
    );
  });

  test('播放头未推进的时段只进会话总时长、不进桶', () async {
    await play();
    await emitPosition(const Duration(milliseconds: 100));
    await emitPosition(const Duration(milliseconds: 200));
    // 引擎在播但播放头停住 3 秒（位置事件缺口）。
    await emitPosition(
      const Duration(milliseconds: 200),
      wallStep: const Duration(seconds: 3),
    );
    await pause();
    await recorder.settleAndFlush();

    final shard = await reloadShard();
    expect(
      shard
          .days['2026-09-05']!
          .buckets[const FourBeatBucketKey(1, 0)]!
          .wallSeconds,
      closeTo(0.1, 1e-6),
    );
    final sessions = await store.records();
    expect(sessions.single.wallSeconds, closeTo(3.2, 1e-6));
  });

  test('未关联视频时不产桶', () async {
    recorder.updateVideo(videoId: null, signature: null, fallbackName: 'x');
    await play();
    await playTo(const Duration(seconds: 2));
    await pause();
    await recorder.settleAndFlush();

    expect((await buckets.shard('hash1')).days, isEmpty);
  });

  test('记账倍频进桶键身份：×2 档落「2:序号」键，原样落裸整数键', () async {
    densityValue = 2;
    await play();
    await playTo(const Duration(seconds: 2));
    await pause();
    await recorder.settleAndFlush();

    final day = (await reloadShard()).days['2026-09-05']!;
    expect(day.buckets.keys.where((k) => k.isBare), isEmpty);
    expect(day.buckets[const FourBeatBucketKey(2, 0)]!.sweeps, 1);
    // 与原样档同一播放序列：总秒数不变（1.8 + 0.1），只是键带上 ×2 身份。
    expect(
      day.buckets.values.fold<double>(0, (s, v) => s + v.wallSeconds),
      closeTo(1.9, 1e-6),
    );
  });
}
