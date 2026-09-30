import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/load_gate.dart'
    show loadGateActiveProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        annotationEditorProvider,
        practiceClipsProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/compare_recording.dart'
    show
        kCompareRecordButtonBottomInset,
        kCompareRecordButtonIdleCoreDiameter,
        kCompareRecordButtonOuterDiameter,
        kCompareRecordButtonRecordingColor,
        kCompareRecordButtonRecordingCoreRadius,
        kCompareRecordButtonRecordingCoreSize,
        kCompareRecordButtonRingThickness;
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/device_viewport.dart';

void main() {
  group('对比-录制会话与素材入库', () {
    late FakePlaybackEngine engine;
    late FakeSystemUi systemUi;
    late FakeCameraCaptureService camera;
    late MemoryManifestStorage manifestStorage;
    late File materialOutputFile;

    void setWideView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    /// 设备等效视口（开发真机横屏 2736×1264、dpr 3.5 ⇒ 781.7×361.1dp）：
    /// 「可达性 ≠ 存在性」的验收纪律——界面类判据必须在真机等效视口下断言
    /// 能点到，只 find.byKey 存在不算过。
    void setDeviceView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
    }

    Future<void> pumpPlayer(
      WidgetTester tester, {
      Map<String, dynamic> devicePrivate = const {},
    }) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(initial: devicePrivate),
            ),
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            // 按视频文档走内存实现：真实文件 IO 在 fake async 时钟下不可
            // 完成（录制准备拍数读点的取值路径整体留在 fake 区内）。
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => materialOutputFile,
            ),
            systemUiControllerProvider.overrideWithValue(systemUi),
            contentHasherProvider.overrideWithValue(
              const FixedHasher('seeded'),
            ),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: source.toFilePath(),
                      mirrored: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(home: PlayerPage(source: source)),
        ),
      );
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

    Future<void> pressRecord(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('compare_record_button')));
      // 一泵落按下编排（含异步取值），二泵触发到达期的准备定时器。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// 双击画面（两次 tap 间隔 < 双击窗口 300ms；复用 control_layer_test 语义）：
    /// 播放/暂停切换。
    Future<void> doubleTap(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
    }

    /// 建 3 个学习段并激活第 [order] 段（默认第 2 段：10s–20s）。
    void givenActiveSegment(WidgetTester tester, int order) {
      final editor = containerOf(tester).read(annotationEditorProvider);
      // 插线受「网格未就绪」门：先置就绪网格。
      containerOf(tester).read(beatTrackStateProvider.notifier).replace(
            BeatTrackState.ready(
              BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 6),
                shift: 0,
                // 均匀 0.5s 拍点、强拍相位自 2.0s：八拍点含 10s 与 20s，
                // 分段线落点恰吸附到 10s/20s（八拍 = 4s）。
                beats: [
                  for (var i = 0; i < 60; i++)
                    BeatPoint(t: 0.5 + i * 0.5, down: (0.5 + i * 0.5) % 4 == 2),
                ],
              ),
            ),
          );
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      containerOf(tester)
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(order);
    }

    Future<MaterialManifestDocument> readManifest() =>
        MaterialManifestStore(manifestStorage).read();

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      systemUi = FakeSystemUi();
      camera = FakeCameraCaptureService();
      manifestStorage = MemoryManifestStorage();
      materialOutputFile = File('/tmp/unused.mp4');
    });

    testWidgets('对比-播放态常驻录制钮（待录态）；非对比态不出现', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      setWideView(tester);
      await pumpPlayer(tester);
      expect(find.byKey(const Key('compare_record_button')), findsNothing);

      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('compare_record_button')), findsOneWidget);
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsNothing,
      );
      // 待录态名字报「开始录制」。
      expectButtonSemantics(
        tester,
        const Key('compare_record_button'),
        label: '开始录制',
      );
      semanticsHandle.dispose();
    });

    testWidgets('装载未完成门：起录被同一道门挡下并弹原因，不落素材与片段', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      givenActiveSegment(tester, 1);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      // 布景自身的定位 seek（激活学习段跳段首）不计入本用例的 seek 序列。
      engine.seekCalls.clear();

      containerOf(tester).read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      await pressRecord(tester);

      // 弹原因、不起录、不进前导、不落素材（装载期唯一写盘保护）。
      expect(find.text('正在装载'), findsOneWidget);
      expect(camera.startRecordingCalls, isEmpty);
      expect(engine.seekCalls, isEmpty);
      expect((await readManifest()).materials, isEmpty);
    });

    testWidgets('按下 = 暂停 → 前导回退 8 拍起播 → 位置越过段首起录；不再补 seek、按钮只留红点', (
      tester,
    ) async {
      setWideView(tester);
      await pumpPlayer(tester);
      givenActiveSegment(tester, 1);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      // 布景自身的定位 seek（激活学习段跳段首）不计入本用例的 seek 序列。
      engine.seekCalls.clear();

      await pressRecord(tester);
      // 非待录态名字改报「停止录制」。
      expectButtonSemantics(
        tester,
        const Key('compare_record_button'),
        label: '停止录制',
      );
      // 前导回退：8 拍 × 500ms（占位网格）= 4s，从段首 10s 退到 6s 连续播放。
      expect(engine.callLog, contains('pause'));
      expect(engine.seekCalls.last, const Duration(seconds: 6));
      expect(engine.isPlaying, isTrue);

      await tester.pump(const Duration(seconds: 4));
      // 到起点起录：强制 1.0×、分辨率默认 1080p、方向锁定横屏。
      expect(camera.startRecordingCalls, hasLength(1));
      expect(
        camera.startRecordingCalls.single.resolution,
        RecordingResolution.fhd1080p,
      );
      expect(
        camera.startRecordingCalls.single.orientation,
        RecordingOrientation.landscape,
      );
      expect(engine.rate, 1.0);
      expect(find.byKey(const Key('compare_recording_indicator')), findsOneWidget);
      // 起录时机：起播那一次定位（段首前 8 拍 = 6s）之后不再有
      // 任何 seek——旧实现在到点补一次帧级 seek 硬拉回起点，那就是源侧可见
      // 的顿挫。
      expect(
        engine.seekCalls,
        [const Duration(seconds: 6)],
        reason: '起播那次定位之后不得再出现 seek',
      );
      // 录制钮不显示已录时长：控制器秒表与素材时长不同源。
      expect(
        find.byKey(const Key('compare_recording_elapsed')),
        findsNothing,
      );
      expect(find.textContaining(':'), findsNothing);
    });

    testWidgets('激活段段尾自动停并入库：素材文件与清单条目真存在、停后暂停在停止点、激活段保持', (
      tester,
    ) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_1.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      givenActiveSegment(tester, 1);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      // 起录重配耗时（先红后绿配方：不设耗时的用例会把起录演成微任务，
      // 实测前言也就永远等于计划余量——这条链路的偏差就测不出来）。
      camera.startRecordingLatency = const Duration(milliseconds: 200);

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4)); // 前导。
      await tester.pump(const Duration(seconds: 10)); // 录制至段尾。
      await tester.pumpAndSettle();

      // 段尾自动停：按钮回待录态、暂停在停止点、激活段保持激活。
      expect(camera.stopRecordingCount, 1);
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsNothing,
      );
      expect(engine.isPlaying, isFalse);
      // 段 2 = 10s–18s（20s 落点吸附到八拍点 18s）。
      expect(engine.position.inMilliseconds, inInclusiveRange(17500, 18500));
      expect(
        containerOf(tester).read(selectedLearningSegmentsProvider),
        isNotEmpty,
      );

      // 素材文件与清单条目真的存在。
      expect(materialOutputFile.existsSync(), isTrue);
      final doc = await readManifest();
      expect(doc.materials, hasLength(1));
      expect(doc.materials.single.videoId, isNotEmpty);
      expect(doc.materials.single.sourceStartMs, 10000);
      expect(doc.materials.single.durationMs, 10000);

      // 在轨片段：入点 = **实测**前言长度、出点 = 素材全长，故片段
      // 范围正好从起录点（10s）开始——前言留在素材文件里但不进片段定义。
      // 武装点 9.4s 起武装、重配 200ms 后编码器才在写（源位置 9.6s），故实测
      // 前言 = 400ms（不是计划余量 600ms）。
      final clips = containerOf(tester).read(practiceClipsProvider);
      expect(clips, hasLength(1));
      expect(clips.single.inMs, 400);
      expect(clips.single.outMs, 10000);
      expect(clips.single.materialDurationMs, 10000);
      expect(clips.single.sourceStartMs, 10000);
      expect(clips.single.sourceEndMs, 10000 + 10000 - 400);
    });

    testWidgets('无激活段：按下位置起、手动停；素材按按下位置入库', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_2.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await engine.seek(const Duration(seconds: 12));
      engine.seekCalls.clear(); // 布景定位不计入本用例的 seek 序列。
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4)); // 前导回 8s、播回 12s。

      expect(camera.startRecordingCalls, hasLength(1));
      // 起播定位在按下位置前 8 拍（12s − 4s = 8s）；越过 12s 时不再 seek。
      expect(engine.seekCalls, [const Duration(seconds: 8)]);

      await pressRecord(tester); // 手动停。
      await tester.pumpAndSettle();

      expect(camera.stopRecordingCount, 1);
      final doc = await readManifest();
      expect(doc.materials.single.sourceStartMs, 12000);
    });

    testWidgets('宿主接线：就绪网格下无激活段起录点吸附到相位最近八拍点', (
      tester,
    ) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_snap.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      // 就绪网格（与 givenActiveSegment 同一套夹具）：八拍点 = 2、10、18…s。
      containerOf(tester).read(beatTrackStateProvider.notifier).replace(
            BeatTrackState.ready(
              BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 6),
                shift: 0,
                beats: [
                  for (var i = 0; i < 60; i++)
                    BeatPoint(t: 0.5 + i * 0.5, down: (0.5 + i * 0.5) % 4 == 2),
                ],
              ),
            ),
          );
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 按下 12.3s（非八拍点）：吸附到 10s，前导 8 拍 → 6s 起播。
      await engine.seek(const Duration(milliseconds: 12300));
      engine.seekCalls.clear();
      camera.startRecordingLatency = const Duration(milliseconds: 200);
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 5));

      expect(camera.startRecordingCalls, hasLength(1));
      expect(engine.seekCalls, [const Duration(seconds: 6)]);

      await pressRecord(tester); // 手动停。
      await tester.pumpAndSettle();

      // 素材来源起点 = 新起录点（吸附后的八拍点）。
      expect((await readManifest()).materials.single.sourceStartMs, 10000);
    });

    testWidgets('暂停态起录：准备期与录制期中央不出现播放指示，停录后按真实状态显示', (
      tester,
    ) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 替身必须发真事件——中央指示由引擎播放态边沿单向驱动，替身
      // 沉默则本用例的显隐断言等于没测（边沿在下面逐条断言）。
      final playingEdges = <bool>[];
      final edges = engine.isPlayingStream.listen(playingEdges.add);
      addTearDown(edges.cancel);

      // 真机日常路径：按下录制前视频本来是暂停的（双击暂停）。
      await engine.seek(const Duration(seconds: 12));
      await tester.pump();
      await doubleTap(tester);
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);

      await pressRecord(tester);
      await tester.pump();
      // 准备期：起录前 pause（原已暂停 → 无新边沿）→ 前导回退 8 拍起播。
      expect(engine.isPlaying, isTrue);
      expect(
        find.byKey(const Key('play_indicator')),
        findsNothing,
        reason: '准备期引擎在播 ⇒ 中央指示不得挂着（缓存副本过期的旧病）',
      );

      await tester.pump(const Duration(seconds: 4)); // 前导播回按下位置。
      await tester.pump(const Duration(milliseconds: 100));
      expect(camera.startRecordingCalls, hasLength(1));
      expect(engine.isPlaying, isTrue);
      expect(
        find.byKey(const Key('play_indicator')),
        findsNothing,
        reason: '录制期引擎在播 ⇒ 中央指示不得挂着',
      );

      await pressRecord(tester); // 手动停录。
      await tester.pumpAndSettle();
      expect(camera.stopRecordingCount, 1);
      expect(engine.isPlaying, isFalse);
      expect(
        find.byKey(const Key('play_indicator')),
        findsOneWidget,
        reason: '停录后按真实状态如实显示（引擎已暂停）',
      );

      // 反方向（真机现象的另一半）：停录后双击想继续播——不再「图标凭空
      // 弹出而视频没动」，而是按引擎真实状态走播放分支并如实隐藏指示。
      await doubleTap(tester);
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue, reason: '暂停态下双击 = 起播');
      expect(
        find.byKey(const Key('play_indicator')),
        findsNothing,
        reason: '起播后指示随之隐藏（与引擎同源）',
      );
      expect(
        playingEdges,
        containsAllInOrder([false, true, false, true]),
        reason: '双击暂停 / 前导起播 / 停录暂停 / 停录后双击起播各发过一次真实边沿',
      );
    });

    testWidgets('无激活段播到有效区间尾自动停', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_3.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await engine.seek(const Duration(seconds: 27));
      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4)); // 前导。
      expect(camera.startRecordingCalls, hasLength(1));

      await tester.pump(const Duration(seconds: 3)); // 到 30s 区间尾。
      await tester.pumpAndSettle();

      expect(camera.stopRecordingCount, 1);
      expect(await readManifest().then((d) => d.materials), hasLength(1));
    });

    testWidgets('录制中倍速写穿临时失效、停后恢复；异常网格秒制兜底仍可录', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_4.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await containerOf(
        tester,
      ).read(speedControlProvider.notifier).setRate(1.5);
      givenActiveSegment(tester, 1);
      // 节拍网格异常：录制准备走秒制兜底（建段后就绪网格被异常覆盖）。
      containerOf(tester).read(beatTrackStateProvider.notifier).replace(
            const BeatTrackState.error(),
          );
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 4)); // 秒制兜底 ≈4s。
      expect(camera.startRecordingCalls, hasLength(1));
      expect(engine.rate, 1.0);

      // 倍速设置临时失效。
      await containerOf(
        tester,
      ).read(speedControlProvider.notifier).setRate(2.0);
      expect(engine.rate, 1.0);

      await pressRecord(tester);
      await tester.pumpAndSettle();

      expect(engine.rate, 1.5); // 停后恢复。
      expect(await readManifest().then((d) => d.materials), hasLength(1));
    });

    testWidgets('录制中不进入对比-控制层（画面单击无效、待办不落）', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester); // 按下即起录（位置 0 无前导）。
      await tester.pump(const Duration(seconds: 1));
      expect(camera.startRecordingCalls, hasLength(1));

      await singleTapShow(tester);
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
      expect(
        containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNull,
      );

      await pressRecord(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('录制钮底部居中、外环 72、内芯随相位换形，且外观不随系统字号缩放', (
      tester,
    ) async {
      setWideView(tester);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_hit.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      final hit = tester.getRect(find.byKey(const Key('compare_record_hit')));
      expect(hit.width, greaterThanOrEqualTo(72), reason: '命中宽 ≥ 72 下限');
      expect(hit.height, greaterThanOrEqualTo(72), reason: '命中高 ≥ 72 下限');
      expect(
        hit.size,
        const Size(
          kCompareRecordButtonOuterDiameter,
          kCompareRecordButtonOuterDiameter,
        ),
        reason: '命中盒 = 快门外径（72 的环本身就大过通行下限，不再靠透明外扩）',
      );
      expect(hit.center.dx, closeTo(view.width / 2, 1.0), reason: '底部居中');
      expect(
        hit.bottom,
        closeTo(view.height - kCompareRecordButtonBottomInset, 1.0),
        reason: '底边留 24（本用例无系统手势内缩）',
      );

      // 外环：白环、外径 72、环厚 4（1× 字号基线）。
      final ringFinder = find.byKey(const Key('compare_record_button'));
      final ring = tester.getRect(ringFinder);
      expect(
        ring.size,
        const Size(
          kCompareRecordButtonOuterDiameter,
          kCompareRecordButtonOuterDiameter,
        ),
        reason: '外环外径 72',
      );
      expect(ring.center, hit.center, reason: '外环在命中盒内居中');
      final ringDecoration =
          tester.widget<Container>(ringFinder).decoration! as BoxDecoration;
      expect(ringDecoration.shape, BoxShape.circle, reason: '外环是圆环');
      final ringBorder = ringDecoration.border! as Border;
      expect(
        ringBorder.top.width,
        kCompareRecordButtonRingThickness,
        reason: '环厚 4',
      );
      expect(ringBorder.top.color, Colors.white, reason: '白环');

      // 待录内芯：白实心圆 56。
      final idleCoreFinder = find.descendant(
        of: ringFinder,
        matching: find.byType(Container),
      );
      expect(
        tester.getSize(idleCoreFinder),
        const Size(
          kCompareRecordButtonIdleCoreDiameter,
          kCompareRecordButtonIdleCoreDiameter,
        ),
        reason: '待录内芯直径 56',
      );
      final idleCoreDecoration =
          tester.widget<Container>(idleCoreFinder).decoration! as BoxDecoration;
      expect(idleCoreDecoration.shape, BoxShape.circle, reason: '待录内芯是实心圆');
      expect(idleCoreDecoration.color, Colors.white);

      // 外观不随系统字号缩放：整枚钮无文字、尺寸写死，放大到 2× 后逐位不变。
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      await tester.pump();
      expect(
        tester.getSize(ringFinder),
        const Size(
          kCompareRecordButtonOuterDiameter,
          kCompareRecordButtonOuterDiameter,
        ),
        reason: '2× 字号下外环仍 72',
      );
      expect(
        tester.getSize(idleCoreFinder),
        const Size(
          kCompareRecordButtonIdleCoreDiameter,
          kCompareRecordButtonIdleCoreDiameter,
        ),
        reason: '2× 字号下待录内芯仍 56',
      );
      expect(hit.center.dx, closeTo(view.width / 2, 1.0), reason: '2× 字号下仍居中');

      // 无死区：命中盒四角在环体外、盒内，点它照样起录。
      await tester.tapAt(hit.bottomLeft + const Offset(2, -2));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        camera.startRecordingCalls,
        hasLength(1),
        reason: '命中盒角落起录——环体之外的盒内区域不是死区',
      );

      // 录制中内芯：红圆角方块 32（圆角 8），替掉原先的小红点。
      final indicatorFinder = find.byKey(
        const Key('compare_recording_indicator'),
      );
      expect(indicatorFinder, findsOneWidget);
      expect(
        tester.getSize(indicatorFinder),
        const Size(
          kCompareRecordButtonRecordingCoreSize,
          kCompareRecordButtonRecordingCoreSize,
        ),
        reason: '录制中内芯 32 方块',
      );
      final indicatorDecoration =
          tester.widget<Container>(indicatorFinder).decoration! as BoxDecoration;
      expect(indicatorDecoration.shape, BoxShape.rectangle);
      expect(
        indicatorDecoration.borderRadius,
        BorderRadius.circular(kCompareRecordButtonRecordingCoreRadius),
      );
      expect(indicatorDecoration.color, kCompareRecordButtonRecordingColor);

      await pressRecord(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('录制中退后台自动停并入库', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_5.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(camera.startRecordingCalls, hasLength(1));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(camera.stopRecordingCount, 1);
      expect(await readManifest().then((d) => d.materials), hasLength(1));
    });

    testWidgets('录制中退出对比态自动停并入库', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_6.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(camera.startRecordingCalls, hasLength(1));

      containerOf(tester).read(playerSessionProvider.notifier).exitCompare();
      await tester.pumpAndSettle();

      expect(modeOf(tester), PlayerSessionMode.watching);
      expect(camera.stopRecordingCount, 1);
      expect(await readManifest().then((d) => d.materials), hasLength(1));
    });

    testWidgets('关掉重开素材还在库里', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_7.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      await pressRecord(tester);
      await tester.pumpAndSettle();
      expect(await readManifest().then((d) => d.materials), hasLength(1));

      // 关掉重开：同一份清单存储上新实例读取，条目仍在。
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpPlayer(tester);
      expect(await readManifest().then((d) => d.materials), hasLength(1));
    });

    testWidgets('设备级分辨率档 720p：起录按档位出参', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_8.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(
        tester,
        devicePrivate: {'recordingResolution': '720p'},
      );
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(
        camera.startRecordingCalls.single.resolution,
        RecordingResolution.hd720p,
      );
      await pressRecord(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('取景调节态不画录制钮：底部居中让给取景条', (tester) async {
      setWideView(tester);
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareFraming);
      await tester.pumpAndSettle();

      // 取景调节态：录制钮完全不画（命中盒与本体都没有），底部居中归取景条。
      expect(find.byKey(const Key('compare_record_hit')), findsNothing);
      expect(find.byKey(const Key('compare_record_button')), findsNothing);
      expect(find.byKey(const Key('framing_bar')), findsOneWidget);
      expect(camera.startRecordingCalls, isEmpty);
      expect(
        containerOf(tester).read(playerSessionProvider).mode,
        PlayerSessionMode.compareFraming,
      );
    });

    testWidgets('录制中「取景」入口无效（旁路待办一律取消）', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_9.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await pressRecord(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(camera.startRecordingCalls, hasLength(1));

      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.compareFraming);
      await tester.pump();
      // 宿主编排取消录制中的取景待办：模式一位不动、待办清空。
      await tester.pumpAndSettle();
      expect(
        containerOf(tester).read(playerSessionProvider).mode,
        PlayerSessionMode.compareWatching,
      );
      expect(
        containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNull,
      );

      await pressRecord(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('武装窗口内点录制钮 = 取消：停录并丢弃已武装的那段，不落素材', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_a.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      givenActiveSegment(tester, 1);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      // 起录重配耗时（先红后绿配方：替身不能把起录演成微任务）。
      camera.startRecordingLatency = const Duration(milliseconds: 100);

      await pressRecord(tester);
      // 3.6s：位置 9.6s——武装点 9.4s 已过、编码器已在写，起录点 10s 未到。
      await tester.pump(const Duration(milliseconds: 3600));
      expect(camera.startRecordingCalls, hasLength(1));
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsOneWidget,
        reason: '准备/武装态与录制中一样是红点（去掉秒数后只剩红点）',
      );

      await pressRecord(tester); // 武装窗口内点击 = 取消（回退不录）。
      await tester.pumpAndSettle();

      expect(camera.stopRecordingCount, 1);
      expect(engine.isPlaying, isFalse);
      expect(await readManifest().then((d) => d.materials), isEmpty);
      expect(containerOf(tester).read(practiceClipsProvider), isEmpty);

      // 取消后越过原起录点（10s）也不再起录。
      await tester.pump(const Duration(seconds: 1));
      expect(camera.startRecordingCalls, hasLength(1));
      expect(await readManifest().then((d) => d.materials), isEmpty);
    });

    testWidgets('无激活段在区间尾附近按下录制：被拒、给短暂提示、轨道上无零长片段', (tester) async {
      // 设备等效视口（走的是真机上那一下点按，不是宽视口的
      // 内联布景）：录制钮必须**命中自身**、点下去真的有反应。
      setDeviceView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_rej.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      // 按下位置 29.7s：距有效区间尾（视频尾线 30s）只剩 300ms < 一拍。
      await engine.seek(const Duration(seconds: 29, milliseconds: 700));
      engine.seekCalls.clear();
      final recordBox = tester.renderObject<RenderBox>(
        find.byKey(const Key('compare_record_button')),
      );
      final hit = tester.hitTestOnBinding(
        recordBox.localToGlobal(recordBox.size.center(Offset.zero)),
      );
      expect(
        hit.path.any((entry) => entry.target == recordBox),
        isTrue,
        reason: '录制钮必须命中自身（只 find.byKey 存在不算过）',
      );
      await pressRecord(tester);

      // 短暂提示：居中轻提示出现，按钮仍待录态。
      expect(
        find.byKey(const Key('compare_record_rejected_prompt')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsNothing,
      );
      expect(find.textContaining('无法起录'), findsOneWidget);
      // 拒录不起前导：不动引擎位置、不武装编码器。
      expect(engine.seekCalls, isEmpty);
      expect(camera.startRecordingCalls, isEmpty);

      // 事件过去之后也不落素材、不落片段（旧实现会落一条近 0 长的）。
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(camera.stopRecordingCount, 0);
      expect(await readManifest().then((d) => d.materials), isEmpty);
      expect(containerOf(tester).read(practiceClipsProvider), isEmpty);
      expect(materialOutputFile.existsSync(), isFalse);
    });

    testWidgets('节拍前导：准备期起提示声前导、越起录点收起（秒制兜底无声）', (tester) async {
      setWideView(tester);
      materialOutputFile = File(
        '${Directory.systemTemp.createTempSync('cmp_rec').path}/rec_b.mp4',
      );
      addTearDown(() => materialOutputFile.parent.delete(recursive: true));
      await pumpPlayer(tester);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();

      await engine.seek(const Duration(seconds: 12));
      await pressRecord(tester);
      await tester.pump(const Duration(milliseconds: 250)); // 前导中段。
      expect(camera.startRecordingCalls, isEmpty); // 尚未到起点。

      await tester.pump(const Duration(seconds: 4));
      expect(camera.startRecordingCalls, hasLength(1));
      await pressRecord(tester);
      await tester.pumpAndSettle();
    });
  });
}
