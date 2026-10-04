import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_recorder.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/song_signature.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:dance_learning_app/stats/practice_stats_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_practice_facts.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 练舞统计记账域的会话直测：不 pump widget、不注容器。
///
/// seam = 会话交出的行为（启动清上下文、跟随署名域、收尾落盘、摘订阅）
/// 与记录器落盘结果；署名域用真实的 [SongSignatureController]（方向
/// 统计域 → 署名域），不注入容器。
void main() {
  final path = '/videos/a.mp4';
  final sig = const SongSignature(song: 'My Love');
  const fallbackName = 'a.mp4';

  late FakePlaybackEngine engine;
  late FakePracticeFactsSource facts;
  late InMemoryPracticeStatsStorage storage;
  late PracticeStatsStore store;
  late InMemoryFourBeatBucketStorage bucketStorage;
  late FourBeatBucketStore bucketStore;
  late SongSignatureController identity;
  late PracticeStatsRecorder recorder;
  late PracticeStatsSession session;

  DateTime now = DateTime.parse('2026-09-05T20:00:00');
  void advance(Duration d) => now = now.add(d);

  final notifiedIds = <String?>[];

  setUp(() {
    engine = FakePlaybackEngine();
    facts = FakePracticeFactsSource(engine);
    storage = InMemoryPracticeStatsStorage();
    store = PracticeStatsStore(storage);
    bucketStorage = InMemoryFourBeatBucketStorage();
    bucketStore = FourBeatBucketStore(bucketStorage);
    identity = SongSignatureController(InMemoryVideoIndexStorage());
    recorder = PracticeStatsRecorder(
      facts: facts.stream,
      store: store,
      clock: () => now,
    );
    session = PracticeStatsSession(
      recorder: recorder,
      signatureController: identity,
      fallbackName: () => fallbackName,
      statsStore: store,
      bucketStore: bucketStore,
      onVideoIdChanged: notifiedIds.add,
    );
    notifiedIds.clear();
    now = DateTime.parse('2026-09-05T20:00:00');
  });

  tearDown(() async {
    session.dispose();
    await recorder.dispose();
  });

  Future<void> pumpEdges() => Future<void>.delayed(Duration.zero);

  Future<void> play() async {
    await engine.play();
    await pumpEdges();
  }

  Future<void> pause() async {
    await engine.pause();
    await pumpEdges();
  }

  /// 署名域解析：视频标识与（可选）署名快照一次给全。
  Future<void> openAs({required String videoId, SongSignature? signature}) {
    return identity.startForFile(
      path,
      videoId: videoId,
      entry: historyEntry(
        filePath: path,
        mirrored: false,
        videoId: videoId,
      ).copyWith(signatureCache: signature),
    );
  }

  test('start 清空记录器上下文：解析窗口内的播放不记到上一个视频名下', () async {
    recorder.updateVideo(
      videoId: 'old',
      signature: const SongSignature(song: '旧舞'),
      fallbackName: 'old.mp4',
    );

    session.start();
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    expect(await store.records(), isEmpty);
  });

  test('署名域通知即同步视频标识与署名：交出 videoId、续播按新署名入账', () async {
    session.start();
    expect(notifiedIds, isEmpty, reason: '启动本身不改变「当前视频」的读取面');

    await openAs(videoId: 'vid-a', signature: sig);

    expect(notifiedIds, ['vid-a']);
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.signature, sig);
  });

  test('未署名视频按回退文件名计入（与顶栏回退一致）', () async {
    session.start();
    await openAs(videoId: 'vid-a');
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    expect(
      (await store.records()).single.signature,
      const SongSignature(song: fallbackName),
    );
  });

  test('sync：标识未解析时也把 null 交给读取面并清记录器上下文', () async {
    session.start();
    await openAs(videoId: 'vid-a', signature: sig);
    notifiedIds.clear();

    // 重开为无身份视频：署名域不发通知，靠显式 sync 落定。
    await identity.startForFile(path, videoId: null);
    session.syncVideoContext();

    expect(notifiedIds, [null]);
    await play();
    advance(const Duration(minutes: 1));
    await pause();
    expect(await store.records(), isEmpty);
  });

  test('settle 结算开放缓冲并落盘（退出播放器/切后台）', () async {
    session.start();
    await openAs(videoId: 'vid-a', signature: sig);
    await play();
    advance(const Duration(minutes: 2));

    await session.settle();

    expect(storage.savedJson, isNotNull);
    expect(storage.savedJson!['sessions'] as List, hasLength(1));
  });

  test('dispose 摘除署名域订阅：此后署名变化不再同步进记录器', () async {
    session.start();
    await openAs(videoId: 'vid-a', signature: sig);
    await play();
    advance(const Duration(minutes: 1));
    await pause();
    notifiedIds.clear();

    session.dispose();
    await identity.applySignature(
      const SongSignature(song: 'New'),
      fallbackSong: 'x',
    );

    expect(notifiedIds, isEmpty);
    await play();
    advance(const Duration(minutes: 1));
    await pause();
    expect((await store.records()).single.signature, sig);
  });

  test('重复 start 只订阅一次；记录器为 null 仍交出当前视频标识', () async {
    final bare = PracticeStatsSession(
      recorder: null,
      signatureController: identity,
      fallbackName: () => fallbackName,
      statsStore: store,
      bucketStore: bucketStore,
      onVideoIdChanged: notifiedIds.add,
    );
    bare.start();
    bare.start();
    await openAs(videoId: 'vid-a');
    await bare.settle(); // 无记录器时零操作

    expect(notifiedIds, ['vid-a']);
    bare.dispose();
  });

  test('署名域提交通知：统计记录与四拍桶分片的署名快照都迁移到新署名', () async {
    session.start();
    await openAs(videoId: 'vid-a', signature: sig);
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    bucketStorage.setRaw(
      'vid-a',
      FourBeatBucketShard(
        signature: sig,
        days: {
          '2026-09-05': FourBeatBucketDay(
            buckets: {
              const FourBeatBucketKey(1, 0): const FourBeatBucketValue(
                wallSeconds: 10,
                sweeps: 1,
              ),
            },
          ),
        },
      ).toJson(),
    );

    const migrated = SongSignature(dancer: '如', song: 'My Love', remark: '9人版');
    // 命名/改名提交走署名域；统计域订阅该提交信号做写-through。
    await identity.applySignature(migrated, fallbackSong: 'a.mp4');
    await pumpEdges();
    await pumpEdges();

    expect(
      PracticeStatsDocument.fromJson(storage.savedJson!)
          .sessions
          .single
          .signature,
      migrated,
    );
    expect(
      FourBeatBucketShard.fromJson(bucketStorage.savedJsonFor('vid-a')!)
          .signature,
      migrated,
    );
  });

  test('署名域提交通知：videoId 未解析时跳过两个落点', () async {
    session.start();
    await identity.applySignature(
      const SongSignature(song: 'My Love'),
      fallbackSong: 'a.mp4',
    );
    await pumpEdges();

    expect(storage.savedJson, isNull);
    expect(bucketStorage.saveCount, 0);
  });

  test('dispose 摘除提交通知订阅：此后署名提交不再迁移署名快照', () async {
    session.start();
    await openAs(videoId: 'vid-a', signature: sig);
    await play();
    advance(const Duration(minutes: 1));
    await pause();
    session.dispose();

    await identity.applySignature(
      const SongSignature(song: 'My Love'),
      fallbackSong: 'a.mp4',
    );
    await pumpEdges();

    expect(
      PracticeStatsDocument.fromJson(storage.savedJson!)
          .sessions
          .single
          .signature,
      sig,
    );
  });
}
