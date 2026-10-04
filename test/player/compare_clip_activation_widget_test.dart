import 'dart:io';
import 'dart:ui' as ui;

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        activeLoopRangeProvider,
        annotationEditorProvider,
        practiceClipActivationProvider,
        practiceClipsProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    as vdp
    show videoDocumentStorageProvider, videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';

/// 片段激活回看 · widget 层：点选练习片段即
/// 激活——两侧在该片段区间 AB 循环（源侧经单一循环范围 seam、练习侧
/// 第二播放源按截取范围回放）、回看期间摄像头停止 / 退出恢复、与学习
/// 段激活互斥（widget 层接线）。测试只断言用户可见外部行为。
void main() {
  final clip = PracticeClip(
    id: 'clip_m1',
    materialId: 'm1',
    materialSourceStartMs: 0,
    inMs: 10000,
    outMs: 20000,
  );
  final material = MaterialRecord(
    id: 'm1',
    videoId: 'vid-a',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    durationMs: 20000,
    sourceStartMs: 10000,
    fileName: 'rec_m1.mp4',
    sizeBytes: 1,
  );

  late FakePlaybackEngine engine;
  late FakePlaybackEngine practiceEngine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;
  late MemoryManifestStorage manifestStorage;

  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(
      1920,
      1080,
    ); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  /// 设备等效视口 + 真机手指容差（可达性 ≠ 存在性——宽视口
  /// 会把溢出路径整条遮掉；测试视图默认报空手势设置、回落到常量 18dp，
  /// 与真机约 8dp 不是一个数）。
  void setDeviceView(WidgetTester tester) {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 8 * 3.5,
    );
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    bool restoreClipActive = false,
    // 恢复片段列表但无激活片段（恢复写回为空的真机常态布景）。
    bool seedClipInDoc = false,
  }) async {
    final source = Uri.file('/videos/a.mp4');
    manifestStorage = MemoryManifestStorage();
    await MaterialManifestStore(manifestStorage).append(material);
    final docJson = restoreClipActive
        ? {
            'version': 3,
            'session': {
              'activatedSegments': <int>[],
              'activePracticeClipId': 'clip_m1',
            },
            'prefs': {
              'practiceClips': [
                {
                  'id': 'clip_m1',
                  'materialId': 'm1',
                  'materialSourceStartMs': 0,
                  'inMs': 10000,
                  'outMs': 20000,
                },
              ],
            },
          }
        : seedClipInDoc
        ? {
            'version': 3,
            'session': {
              'activatedSegments': <int>[],
              'activePracticeClipId': null,
            },
            'prefs': {
              'practiceClips': [
                {
                  'id': 'clip_m1',
                  'materialId': 'm1',
                  'materialSourceStartMs': 0,
                  'inMs': 10000,
                  'outMs': 20000,
                },
              ],
            },
          }
        : const <String, dynamic>{};
    // 打开会话与消费方指向同一份内存文档（工厂与按视频存取同实例），
    // 基线快照与后续写入才不漂移。
    final docStorage = InMemoryVideoDocumentStorage(local: docJson);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          practiceClipEngineProvider.overrideWithValue(practiceEngine),
          cameraCaptureProvider.overrideWithValue(camera),
          // 固定哈希（返回值 = videoId）让打开恢复的 local 读取与
          // 恢复写回在测试里真实执行（此前哈希读不到文件提前返回，恢复
          // 族断言从未走过真路径）。
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(systemUi),
          materialManifestStoreProvider.overrideWithValue(
            MaterialManifestStore(manifestStorage),
          ),
          materialsBaseDirectoryProvider.overrideWithValue(
            () async => Directory('/tmp/materials'),
          ),
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
          vdp
              .videoDocumentStorageProvider('vid-a')
              .overrideWithValue(docStorage),
          vdp.videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
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

  /// 进入对比-控制层（轨道带可见）：展示控制层 → 点对比练习 → 再点画面
  /// 展开控制层。
  Future<void> enterCompareEditing(WidgetTester tester) async {
    await singleTapShow(tester);
    await tester.tap(find.byKey(const Key('tool_compare')));
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.compareWatching);
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
  }

  /// 在轨放一个练习片段。
  void givenClipOnTrack(WidgetTester tester) {
    containerOf(tester).read(practiceClipsProvider.notifier).restore([clip]);
  }

  /// 收尾停播（fake 引擎的 tick 定时器不跨用例遗留）。
  Future<void> pauseEngines(WidgetTester tester) async {
    engine.pause();
    practiceEngine.pause();
    await tester.pumpAndSettle();
  }

  /// 步进横滑（scrub 拖动，同 player_page_test 手法）。
  Future<void> stepDrag(
    WidgetTester tester,
    Offset start,
    List<Offset> deltas,
  ) async {
    final gesture = await tester.startGesture(start);
    for (final delta in deltas) {
      await gesture.moveBy(delta);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
    practiceEngine = FakePlaybackEngine(duration: const Duration(seconds: 20));
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
  });

  testWidgets('点选片段即激活：两侧循环、摄像头停、练习侧回放片段画面', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompareEditing(tester);
    givenClipOnTrack(tester);
    await tester.pumpAndSettle();

    expect(camera.startCount, 1);
    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();

    // 激活就位：单一循环范围 = 片段源区间。
    final range = containerOf(tester).read(activeLoopRangeProvider);
    expect(range, isNotNull);
    expect(range!.start, const Duration(seconds: 10));
    expect(range.end, const Duration(seconds: 20));

    // 回看期间摄像头停止。
    expect(camera.stopCount, 1);

    // 练习侧回放片段画面：第二播放源打开素材文件、定位截取起点。
    expect(find.byKey(const Key('practice_clip_playback')), findsOneWidget);
    expect(practiceEngine.source.toString(), endsWith('vid-a/rec_m1.mp4'));
    expect(practiceEngine.seekCalls, contains(const Duration(seconds: 10)));

    // 退出激活（再点同片段）：回放退场 + 恢复实时预览。
    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('practice_clip_playback')), findsNothing);
    expect(camera.startCount, 2);
    await pauseEngines(tester);
  });

  testWidgets('设备等效视口下点块体首端 14dp 带：与正中同一激活结果（判据①）', (tester) async {
    setDeviceView(tester);
    // 一支 180 秒的舞里录 10 秒 = 块宽约 43dp（真机横屏的真实形状），而
    // 现有 6 条激活用例都在 960dp 宽的视口下点 160dp 块的正中——结构上
    // 抓不到「两端 14dp 是死区」这条缺陷。
    engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
    await pumpPlayer(tester);
    await enterCompareEditing(tester);
    givenClipOnTrack(tester);
    // 设备等效视口下页面标题溢出 → [AutoScrollTitle] 跑马灯 `repeat()`
    // 恒动，`pumpAndSettle` 不收敛（既有行为，与本用例无关）：本用例
    // 用定长 pump 推进。
    await tester.pump(const Duration(milliseconds: 50));

    final block = tester.getRect(
      find.byKey(const Key('practice_clip_clip_m1')),
    );
    // 块宽按内容区宽（带宽让出轨道片头带）。
    expect(block.width, closeTo(bandContentWidth(781.7) * 10000 / 180000, 1.5));
    expect(block.width - 2 * 14, lessThan(20), reason: '活区只有中间一小条');

    // 落点在左端 14dp 的截取端点带内（非中心）。
    await tester.tapAt(Offset(block.left + 7, block.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    // 与正中单击**同一激活结果**三支齐备：块缘描边、单一循环范围、
    // 练习侧切换（回放件就位 + 定位片段首 + 立即起播）。
    final range = containerOf(tester).read(activeLoopRangeProvider);
    expect(range, isNotNull);
    expect(range!.start, const Duration(seconds: 10));
    expect(range.end, const Duration(seconds: 20));
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byKey(const Key('practice_clip_clip_m1')),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect((decoration.border as Border?)?.top.color, Colors.white);
    expect(camera.stopCount, 1);
    expect(find.byKey(const Key('practice_clip_playback')), findsOneWidget);
    expect(practiceEngine.seekCalls, contains(const Duration(seconds: 10)));
    expect(engine.isPlaying, isTrue, reason: '点选激活即起播（跳区间首后立即播放）');

    engine.pause();
    practiceEngine.pause();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('点选练习片段即起播：暂停态点段 → 两侧当场回看、源侧在区间首', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompareEditing(tester);
    givenClipOnTrack(tester);
    await tester.pumpAndSettle();

    // 布景：两侧暂停在片段之前（旧口径下点选片段只 seek + enableLoop，
    // 源侧暂停时位置不推进 ⇒ 练习侧也不开始回看）。
    await pauseEngines(tester);
    await engine.seek(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(engine.isPlaying, isFalse);

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pump();
    await tester.pump();

    // 前置：引擎处于播放态、位置在片段首、循环范围 = 片段区间。
    expect(engine.isPlaying, isTrue, reason: '点选片段当场开始播放');
    expect(
      engine.position,
      allOf(
        greaterThanOrEqualTo(const Duration(seconds: 10)),
        lessThan(const Duration(seconds: 12)),
      ),
    );
    final range = containerOf(tester).read(activeLoopRangeProvider)!;
    expect(range.start, const Duration(seconds: 10));
    expect(range.end, const Duration(seconds: 20));

    // 练习侧当场回看（第二播放源进入播放态，不必再手动按播放）。
    await tester.pumpAndSettle();
    expect(practiceEngine.isPlaying, isTrue);
    await pauseEngines(tester);
  });

  testWidgets('与学习段激活互斥（widget 层）：激活学习段清除片段激活并恢复预览', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    // 对比态几何只读：分段线在进对比态前落线。
    await singleTapShow(tester);
    containerOf(tester)
        .read(annotationEditorProvider)
        .submit(const AddSegmentLine(at: Duration(seconds: 30)));
    await tester.tap(find.byKey(const Key('tool_compare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    givenClipOnTrack(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    expect(camera.stopCount, 1);

    // 点学习段轨的段（对比态语义：选中并激活）→ 片段激活被清除。
    await tester.tap(find.byKey(const Key('learning_segment_0')));
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(practiceClipActivationProvider), isNull);
    expect(find.byKey(const Key('practice_clip_playback')), findsNothing);
    expect(camera.startCount, 2);
    await pauseEngines(tester);
  });

  testWidgets('片段区间直循环（无循环前导）：到截取终点直接回截取起点', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompareEditing(tester);
    givenClipOnTrack(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();

    // 播放位置越过截取终点（20s）：循环层应直接 seek 回 10s（默认前导
    // 拍档非零时若套了前导，目标会落在 10s 之前的画面）。
    await engine.seek(const Duration(seconds: 20, milliseconds: 100));
    await tester.pumpAndSettle();

    expect(engine.seekCalls.last, const Duration(seconds: 10));
    await pauseEngines(tester);
  });

  testWidgets('重开恢复激活：激活还在、不自动跳转、不自动播放；进对比态不开摄像头', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester, restoreClipActive: true);
    await tester.pumpAndSettle();

    // 激活随 local session 段恢复就位；恢复不自动跳转（不 seek 片段首，
    // 源侧续播是页面既有行为、与恢复无关）。
    expect(
      containerOf(tester).read(practiceClipActivationProvider)?.clipId,
      'clip_m1',
    );
    expect(engine.seekCalls, isNot(contains(const Duration(seconds: 10))));

    // 进入对比态：回看接管练习侧——不开实时预览，片段画面就位。
    await singleTapShow(tester);
    await tester.tap(find.byKey(const Key('tool_compare')));
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.compareWatching);
    expect(camera.startCount, 0);
    expect(find.byKey(const Key('practice_clip_playback')), findsOneWidget);
    expect(find.byKey(const Key('fake_camera_preview')), findsNothing);
    await pauseEngines(tester);
  });

  testWidgets('进度拖出片段范围清激活（widget 层）：清除并恢复预览', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompareEditing(tester);
    givenClipOnTrack(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();
    expect(
      containerOf(tester).read(practiceClipActivationProvider)?.clipId,
      'clip_m1',
    );

    // 把播放位置先放到片段尾附近（引擎层 seek 不走清除判定），再从节拍
    // 轨行横滑 scrub 到片段范围外（> 20s）→ 激活清除、回放退场、预览恢复。
    await engine.seek(const Duration(seconds: 19));
    await tester.pumpAndSettle();
    final beatY = tester.getCenter(find.byKey(const Key('track_beat'))).dy;
    await stepDrag(
      tester,
      Offset(tester.getCenter(find.byKey(const Key('track_band'))).dx, beatY),
      List.filled(15, const Offset(20, 0)),
    );
    await tester.pumpAndSettle();

    expect(containerOf(tester).read(practiceClipActivationProvider), isNull);
    expect(find.byKey(const Key('practice_clip_playback')), findsNothing);
    expect(camera.startCount, 2);
    await pauseEngines(tester);
  });

  testWidgets('恢复跑过（无激活片段）后点选片段仍跳片段首：源间标志互不干扰', (tester) async {
    setWideView(tester);
    // 打开恢复真实执行：片段列表从盘上恢复，无激活片段（恢复写回为空）。
    await pumpPlayer(tester, seedClipInDoc: true);
    await enterCompareEditing(tester);
    expect(containerOf(tester).read(practiceClipsProvider), isNotEmpty);

    await tester.tap(find.byKey(const Key('practice_clip_clip_m1')));
    await tester.pumpAndSettle();

    // 片段激活的跳片段首 seek 保留。
    expect(practiceEngine.seekCalls, contains(const Duration(seconds: 10)));
    await pauseEngines(tester);
  });
}
