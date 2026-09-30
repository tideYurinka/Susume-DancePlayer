import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_recorder.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_practice_facts.dart';
import '../helpers/in_memory_practice_stats_storage.dart';

/// 统计排除语境 · 记录器层：录制准备期的
/// 前导回退与片段回看的循环播放经事实翻转不计入练舞统计；事实回「计」且
/// 引擎在播即从当下重开区间（口径与存储形状不变）。
///
/// seam = 注入事实流（[FakePracticeFactsSource]）+ 注入假时钟（与既有记录
/// 器测试同款）；断言只看 store 的记录结果。
void main() {
  const sig = SongSignature(song: 'My Love');

  late FakePlaybackEngine engine;
  late FakePracticeFactsSource facts;
  late InMemoryPracticeStatsStorage storage;
  late PracticeStatsStore store;
  late PracticeStatsRecorder recorder;

  DateTime now = DateTime.parse('2026-09-05T20:00:00');
  void advance(Duration d) => now = now.add(d);

  setUp(() {
    engine = FakePlaybackEngine();
    facts = FakePracticeFactsSource(engine);
    storage = InMemoryPracticeStatsStorage();
    store = PracticeStatsStore(storage);
    recorder = PracticeStatsRecorder(
      facts: facts.stream,
      store: store,
      clock: () => now,
    );
    recorder.updateVideo(
      videoId: 'hash1',
      signature: sig,
      fallbackName: '123.mp4',
    );
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

  test('排除类播放不计入（前导回退 / 回看循环全程在排除内）', () async {
    facts.set(recordingPreparing: true);
    await play();
    advance(const Duration(minutes: 3));
    await pause();
    facts.set(recordingPreparing: false);
    await pumpEdges();

    expect(storage.savedJson, isNull);
    expect(await store.records(), isEmpty);
  });

  test('排除外的普通播放照常计入：排除只掐掉区间内的播放时间', () async {
    await play();
    advance(const Duration(minutes: 2));
    facts.set(clipReviewInFlight: true);
    await pumpEdges(); // 前导回退 / 回看循环开始
    advance(const Duration(minutes: 3));
    facts.set(clipReviewInFlight: false);
    await pumpEdges(); // 回到真实跟跳
    await pumpEdges();
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 3 * 60);
  });

  test('排除期间暂停、结束后播放：恢复后照常计入', () async {
    await play();
    advance(const Duration(minutes: 1));
    facts.set(recordingPreparing: true);
    await pumpEdges();
    advance(const Duration(minutes: 2));
    await pause(); // 排除期间暂停：不入账
    facts.set(recordingPreparing: false);
    await pumpEdges();
    await play();
    advance(const Duration(minutes: 4));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 5 * 60);
  });
}
