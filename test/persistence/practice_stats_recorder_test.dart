import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_recorder.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_practice_facts.dart';
import '../helpers/in_memory_practice_stats_storage.dart';

/// 练习统计记录器（收口）。
///
/// seam = 注入事实流（[FakePracticeFactsSource]：引擎 isPlaying 边沿搬入，
/// 专属事实测试手动翻转）+ 注入假时钟；断言只看 store 的记录结果。
void main() {
  final sig = const SongSignature(song: 'My Love');
  final fallbackSig = const SongSignature(song: '123.mp4');

  late FakePlaybackEngine engine;
  late FakePracticeFactsSource facts;
  late InMemoryPracticeStatsStorage storage;
  late PracticeStatsStore store;
  late PracticeStatsRecorder recorder;

  // 假时钟：测试手动推进的本地墙钟。
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

  // FakePlaybackEngine 的播放节拍定时器无需真实推进：记录器只消费
  // isPlaying 边沿；这里让边沿事件在微任务队列中送达。
  Future<void> pumpEdges() => Future<void>.delayed(Duration.zero);

  Future<void> play() async {
    await engine.play();
    await pumpEdges();
  }

  Future<void> pause() async {
    await engine.pause();
    await pumpEdges();
  }

  test('播放累计墙钟时长、倍速不折算', () async {
    await engine.open(Uri.parse('file:///v.mp4'));
    await pumpEdges();
    await play();
    await engine.setRate(2.0);
    advance(const Duration(minutes: 6));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 6 * 60); // 墙钟 6 分钟，与倍速无关
    expect(records.single.start, DateTime.parse('2026-09-05T20:00:00'));
    expect(records.single.signature, sig);
  });

  test('暂停期间不计、5 分钟内续播并入同一会话', () async {
    await play();
    advance(const Duration(minutes: 3));
    await pause();
    advance(const Duration(minutes: 4));
    await play();
    advance(const Duration(minutes: 2));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 5 * 60);
  });

  test('暂停 ≥5 分钟后续播新开会话', () async {
    await play();
    advance(const Duration(minutes: 2));
    await pause();
    advance(const Duration(minutes: 6));
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    expect(await store.records(), hasLength(2));
  });

  test('全屏拖动（翻看）先暂停：拖动期间由播放态门覆盖，恢复续播照常计', () async {
    await play();
    advance(const Duration(minutes: 2));
    await pause(); // scrub 起手先暂停——翻看不再单独排除
    advance(const Duration(minutes: 3)); // 拖动期间引擎不在播
    await play(); // 松手恢复播放态
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 3 * 60); // 前后两段并入同一会话
  });

  test('事实翻转（回看在飞）即结算：不计期间的播放态边沿不入账', () async {
    await play();
    advance(const Duration(minutes: 1));
    facts.set(clipReviewInFlight: true);
    await pumpEdges(); // 翻转点结算当前区间
    advance(const Duration(minutes: 3)); // 回看期间引擎仍在播
    await pause(); // 不计期间的边沿不入账
    await play();
    advance(const Duration(minutes: 1));
    facts.set(clipReviewInFlight: false);
    await pumpEdges(); // 退出回看：在播即从当下重开
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 2 * 60); // 1 + 1，回看 3 分钟不入账
  });

  test('行为修正一：回看在飞中无需配平，事实回「计」即恢复入账', () async {
    await play();
    advance(const Duration(minutes: 1));
    facts.set(clipReviewInFlight: true);
    await pumpEdges();
    advance(const Duration(minutes: 2));
    // 「离开播放页」不再需要任何配平调用：记录器没有计数器可漂移。
    facts.set(clipReviewInFlight: false);
    await pumpEdges(); // 重开页、退出回看
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 2 * 60); // 1 + 1，不计段被掐掉
  });

  test('录制准备期不计入：相位翻回即从当下重开区间', () async {
    await play();
    advance(const Duration(minutes: 1));
    facts.set(recordingPreparing: true);
    await pumpEdges(); // 前导回退开始
    advance(const Duration(minutes: 1));
    await pause(); // 准备期引擎暂停：边沿不入账
    facts.set(recordingPreparing: false);
    await pumpEdges(); // 起录（真实跟跳）
    await play();
    advance(const Duration(minutes: 4));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 5 * 60); // 1 + 4，准备期 1 分钟不计
  });

  test('延迟预备播放期不计入：越过起点翻回即从当下重开区间', () async {
    await play();
    advance(const Duration(minutes: 1));
    facts.set(delayedPlayPreparing: true);
    await pumpEdges(); // 预备播放开始（引擎在播但不计）
    advance(const Duration(minutes: 1));
    facts.set(delayedPlayPreparing: false);
    await pumpEdges(); // 越过起点：延迟锚生效，照常计入
    advance(const Duration(minutes: 4));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 5 * 60); // 1 + 4，预备期 1 分钟不计
  });

  test('解析窗口（标识未定）不计：解析落定且在播从当下新开区间', () async {
    recorder.updateVideo(videoId: null, signature: null, fallbackName: 'x');
    await play();
    advance(const Duration(minutes: 1)); // 解析窗口内的播放不记到任何视频名下
    recorder.updateVideo(
      videoId: 'hash1',
      signature: sig,
      fallbackName: '123.mp4',
    );
    await pumpEdges(); // 标识落定：从当下新开区间
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 60);
  });

  test('到尾自动停止按暂停语义结算', () async {
    await play();
    advance(const Duration(minutes: 2));
    // FakePlaybackEngine 到尾自行转暂停并发出 isPlaying=false 边沿。
    engine.simulateCompleted();
    await pumpEdges();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 2 * 60);
  });

  test('跨零点播放拆成按日两条记录', () async {
    now = DateTime.parse('2026-09-05T23:58:00');
    await play();
    advance(const Duration(minutes: 7)); // 越过零点
    await pause();

    final records = await store.records();
    expect(records, hasLength(2));
    expect(records[0].start, DateTime.parse('2026-09-05T23:58:00'));
    expect(records[0].wallSeconds, 2 * 60);
    expect(records[1].start, DateTime.parse('2026-09-06T00:00:00'));
    expect(records[1].wallSeconds, 5 * 60);
  });

  test('未署名视频按回退文件名计入', () async {
    recorder.updateVideo(
      videoId: 'hash1',
      signature: null,
      fallbackName: '123.mp4',
    );
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    expect((await store.records()).single.signature, fallbackSig);
  });

  test('改名写-through：开放会话缓冲一并迁移，续播并入新署名', () async {
    await play();
    advance(const Duration(minutes: 2));
    await pause();
    await store.migrateSignature('hash1', const SongSignature(song: 'My Love'));
    advance(const Duration(minutes: 1));
    recorder.updateVideo(
      videoId: 'hash1',
      signature: const SongSignature(song: 'My Love'),
      fallbackName: '123.mp4',
    );
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    final records = await store.records();
    expect(records, hasLength(1));
    expect(records.single.signature, const SongSignature(song: 'My Love'));
    expect(records.single.wallSeconds, 3 * 60);
  });

  test('settleAndFlush（退出播放器/切后台）结算开放缓冲并落盘', () async {
    await play();
    advance(const Duration(minutes: 2));
    await recorder.settleAndFlush();

    expect(storage.savedJson, isNotNull);
    final sessions = storage.savedJson!['sessions'] as List;
    expect(sessions, hasLength(1));
  });

  test('未关联视频（videoId 未解析）时不记账', () async {
    recorder.updateVideo(videoId: null, signature: null, fallbackName: 'x');
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    expect(storage.savedJson, isNull);
    expect(await store.records(), isEmpty);
  });

  test('dispose 取消事实订阅', () async {
    await recorder.dispose();
    await play();
    advance(const Duration(minutes: 1));
    await pause();

    expect(await store.records(), isEmpty);
  });
}
