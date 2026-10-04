import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/practice_stats_recorder.dart';
import 'package:dance_learning_app/player/practice_accounting_providers.dart'
    show practiceStatsRecorderProvider, practiceAccountingFactsProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show practiceClipActivationProvider, practiceClipsProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/fixed_hasher.dart';

/// 统计挂接· widget 集成：进入对比态播放一段
/// → 统计有记录；录制准备的前导回退播放与片段回看的循环播放不计入。
/// 记录器注入假时钟（时长推进由测试手动控制），断言只看 store 记录。
void main() {
  final source = Uri.file('/videos/a.mp4');
  final material = MaterialRecord(
    id: 'm1',
    videoId: 'vid-a',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    durationMs: 20000,
    sourceStartMs: 10000,
    fileName: 'rec_m1.mp4',
    sizeBytes: 1,
  );
  final clip = PracticeClip(
    id: 'clip_m1',
    materialId: 'm1',
    materialSourceStartMs: 0,
    inMs: 10000,
    outMs: 20000,
  );

  late FakePlaybackEngine engine;
  late FakePlaybackEngine practiceEngine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;
  late InMemoryPracticeStatsStorage statsStorage;
  late PracticeStatsStore statsStore;
  late MemoryManifestStorage manifestStorage;

  // 假时钟：测试手动推进的本地墙钟（记录器注入）。
  DateTime statsNow = DateTime.parse('2026-09-05T20:00:00');
  void advanceStatsClock(Duration d) => statsNow = statsNow.add(d);

  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(
      1920,
      1080,
    ); // 合成档 960×540dp（dpr 2.0），非设备档。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  /// 生产事实组装（practiceAccountingFactsProvider）+ 记录器假时钟注入。
  /// 记录器在生产是常驻 provider（App 会话域），泄漏回归用例因此要在
  /// **同一容器跨页存活**的前提下先后泵「离开播放页 → 重开播放页」——
  /// 每次泵新建 ProviderScope 会把旧记录器一起销毁，恰好遮住这条缺陷。
  ProviderContainer? container;
  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    container ??= ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        practiceClipEngineProvider.overrideWithValue(practiceEngine),
        cameraCaptureProvider.overrideWithValue(camera),
        privateJsonStorageProvider.overrideWithValue(
          InMemoryPrivateJsonStorage(),
        ),
        materialManifestStoreProvider.overrideWithValue(
          MaterialManifestStore(manifestStorage),
        ),
        materialsBaseDirectoryProvider.overrideWithValue(
          () async => Directory('/tmp/materials'),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => InMemoryVideoDocumentStorage(),
        ),
        systemUiControllerProvider.overrideWithValue(systemUi),
        practiceStatsStoreProvider.overrideWithValue(statsStore),
        practiceStatsRecorderProvider.overrideWith((ref) {
          final recorder = PracticeStatsRecorder(
            facts: ref.watch(practiceAccountingFactsProvider),
            store: ref.watch(practiceStatsStoreProvider),
            clock: () => statsNow,
          );
          ref.onDispose(recorder.dispose);
          return recorder;
        }),
        contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(
            initial: VideoIndex(
              entries: [
                historyEntry(
                  filePath: source.toFilePath(),
                  mirrored: false,
                  videoId: 'vid-a',
                ),
              ],
            ),
          ),
        ),
      ],
    );
    // pumpApp 在一个用例里可能被多次调用（泄漏回归泵三页）；dispose 只做
    // 一次，其余 teardown 变空操作。
    addTearDown(() {
      final c = container;
      if (c == null) return;
      container = null;
      c.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container!,
        child: MaterialApp(home: home),
      ),
    );
  }

  Future<void> pumpPlayer(WidgetTester tester) async {
    manifestStorage = MemoryManifestStorage();
    await MaterialManifestStore(manifestStorage).append(material);
    await pumpApp(tester, PlayerPage(source: source));
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  PlayerSessionMode modeOf(WidgetTester tester) =>
      containerOf(tester).read(playerSessionProvider).mode;

  Future<void> singleTapShow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
  }

  Future<void> enterCompare(tester) async {
    await singleTapShow(tester);
    await tester.tap(find.byKey(const Key('tool_compare')));
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.compareWatching);
  }

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
    practiceEngine = FakePlaybackEngine(duration: const Duration(seconds: 20));
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
    statsStorage = InMemoryPracticeStatsStorage();
    statsStore = PracticeStatsStore(statsStorage);
    statsNow = DateTime.parse('2026-09-05T20:00:00');
    container = null;
  });

  testWidgets('进入对比态播放一段 → 统计有记录（墙钟不折算）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompare(tester);

    await engine.play();
    await tester.pump();
    advanceStatsClock(const Duration(minutes: 2));
    await engine.pause();
    await tester.pump();

    final records = await statsStore.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 2 * 60);
    expect(records.single.start, DateTime.parse('2026-09-05T20:00:00'));
  });

  testWidgets('录制准备的前导回退播放不计入：起录后的真实跟跳照常计', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompare(tester);

    // 定位到 30s 播放中按下录制：前导回退 ≈4s（无节拍网格按秒制兜底）。
    await engine.seek(const Duration(seconds: 30));
    await engine.play();
    await tester.pump();
    await tester.tap(find.byKey(const Key('compare_record_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    // 前导回退期间的播放不入账。
    advanceStatsClock(const Duration(minutes: 1));

    // 前导到点起录（前导定时器到点）→ 真实跟跳 30s 照常计入。
    await tester.pump(const Duration(seconds: 5));
    advanceStatsClock(const Duration(seconds: 30));
    await tester.tap(find.byKey(const Key('compare_record_button')));
    await tester.pump();
    await tester.pump();

    final records = await statsStore.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 30);
  });

  testWidgets('片段回看的循环播放不计入', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompare(tester);

    containerOf(tester).read(practiceClipsProvider.notifier).restore([clip]);
    // 片段在轨道带上，需先展开对比-控制层。
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    // 回看循环播放 2 分钟：源侧与练习侧的循环都不入账。
    await engine.play();
    await tester.pump();
    advanceStatsClock(const Duration(minutes: 2));
    await engine.pause();
    await practiceEngine.pause();
    await tester.pump();

    expect(await statsStore.records(), isEmpty);
  });

  testWidgets('泄漏回归：回看在飞时离开播放页，重开后退出回看重新入账', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompare(tester);

    containerOf(tester).read(practiceClipsProvider.notifier).restore([clip]);
    // 片段在轨道带上，需先展开对比-控制层再点选激活（回看在飞）。
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();

    // 回看在飞播放 1 分钟：不入账。
    await engine.play();
    await tester.pump();
    advanceStatsClock(const Duration(minutes: 1));
    expect(await statsStore.records(), isEmpty);

    // 回看在飞中离开播放页——旧实现这里之后所有播放静默不入账直到重启；
    // 修正后「计不计」随时反映当前事实，重开播放页、退出回看即恢复入账。
    await pumpApp(tester, const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpApp(tester, PlayerPage(source: source));
    await tester.pumpAndSettle();

    // 回看激活随打开恢复写回，重开后仍是回看在飞：照旧不入账。
    await engine.play();
    await tester.pump();
    advanceStatsClock(const Duration(minutes: 1));
    expect(await statsStore.records(), isEmpty);

    // 退出回看（画面常驻出口件与编辑态回看浮条共用的唯一退出写入口）：
    // 此后播放重新入账——旧实现走到这里仍是零入账。
    containerOf(tester)
        .read(practiceClipActivationProvider.notifier)
        .exitReview();
    await tester.pumpAndSettle();
    await engine.play();
    await tester.pump();
    advanceStatsClock(const Duration(minutes: 1));
    await engine.pause();
    await tester.pump();

    final records = await statsStore.records();
    expect(records, hasLength(1));
    expect(records.single.wallSeconds, 60);

    // 打开恢复的续播小卡自带 5 秒自动消失计时，收尾前放它走完。
    await tester.pump(const Duration(seconds: 5));
  });
}
