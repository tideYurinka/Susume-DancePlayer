import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/beat/beat_pipeline.dart'
    show BeatAnalysisPipeline;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;
import 'package:dance_learning_app/core/playback/playback_loop_providers.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/core/video_identity.dart' show ContentHasher;
import 'package:dance_learning_app/help/content_registry.dart'
    show HandsOnCriterion;
import 'package:dance_learning_app/help/guide_state.dart'
    show guideEnterWatchingRequestProvider, guideSessionProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider, videoDocumentStorageProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        activeLoopRangeProvider,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationTimelineProvider,
        practiceClipsProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/av_sync.dart'
    show avSyncDelaysAutoRestoreProvider, avSyncProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/beat_schedule.dart';
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/load_gate.dart'
    show loadGateActiveProvider;
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show DelayedLoopBeats, delayedLoopProvider, prepBeatsProvider;
import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/metronome_sound.dart';
import 'package:dance_learning_app/player/beat_prompt_panel.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTimingOf;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/player/beat_prompt_memory.dart';
import 'package:dance_learning_app/player/gestures.dart';
import 'package:dance_learning_app/player/metronome_overlay.dart';
import 'package:dance_learning_app/player/overlay.dart';
import 'package:dance_learning_app/player/native_scheduled_audio.dart';
import 'package:dance_learning_app/player/beat_presentation_providers.dart'
    show beatCountPositionProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/editor_skeleton.dart'
    show videoPictureRect;
import 'package:dance_learning_app/player/picture_layer.dart';
import 'package:dance_learning_app/core/frame_time.dart';
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/track_time.dart';

import '../helpers/video_surface.dart';

import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/bubble_clamp_assertions.dart';
import '../helpers/fake_beat_audio_sink.dart';
import '../helpers/fake_beat_schedule_consumer.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';

/// 浮层位载荷的测试构造（默认写竖屏·普通格；调用方可指定格）。
OverlayPlacements overlayPlacements({
  OverlayPlacementCell cell = OverlayPlacementCell.portraitNormal,
  Offset offset = Offset.zero,
  double rectWidthFactor = 1.0,
  double pendulumScale = 1.0,
}) => OverlayPlacements(
  offsets: {cell: offset},
  rectWidthFactor: rectWidthFactor,
  pendulumScale: pendulumScale,
);

void main() {
  /// 单击唤出控制层：等自定义双击识别器判定孤立单击后渲染。
  Future<void> singleTapShow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 经标注编辑模块提交一次首/尾设置（旧「设首/尾」按钮入口
  /// 移除后的等价测试编排，走同一模块管线）。
  Future<void> submitRange(
    WidgetTester tester, {
    Duration? start,
    Duration? end,
  }) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
    container
        .read(annotationEditorProvider)
        .submit(SetVideoRange(start: start, end: end));
    await tester.pump();
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    FakeSystemUi? systemUi,
    FakeScreenBrightnessController? brightness,
    FakeSystemMediaVolumeController? volume,
    Uri? source,
    Key? pageKey,
    BeatAnalysisPipeline? beatPipeline,
    BeatScheduleConsumer? beatScheduleConsumer,
    // 渲染器生命周期 seam 注入（退后台 flush + 停流 + 播放态下推）。
    // 缺省走真实渲染器（哑 sink，无声）。
    BeatAudioRenderer? beatAudioRenderer,
    // 空态 seam：false → 位置流不产值（播放位置未就绪）。
    bool positionReady = true,
    // 注入可读 local 文档（真机等价）——打开恢复路径真的跑过。
    // null = 不注入（哈希读不到文件，恢复路径不执行，既有布景不变）。
    Map<String, dynamic>? localDoc,
    // 注入内容摘要（门存续用例用挂起摘要保持「装载未完成」）
    // 与按视频文档存储（摘要完成后接上恢复链）。
    ContentHasher? hasher,
    InMemoryVideoDocumentStorage? docs,
    // false → 只挂树不 pumpAndSettle（观察打开**在途**的帧）。
    bool settle = true,
    // 注入内存私密 JSON 存储（隔离步进预设读盘，不触真实路径）。
    bool inMemoryPrivateJson = false,
    // 画面层接线断言用：种入「已询问」索引条目的镜像真值。
    bool mirrored = false,
  }) async {
    final resolvedSource = source ?? Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          if (hasher != null) contentHasherProvider.overrideWithValue(hasher),
          if (docs != null)
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => docs,
            ),
          // 固定哈希 + 内存文档存储，让「内容一致 → 读 local →
          // 恢复写回」整条链在测试里真实执行。
          if (localDoc != null) ...[
            contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(local: localDoc),
            ),
          ],
          // 节拍分析管线注入：缺省走真实管线（既有行为不变）；
          // 注入 fake 管线（成功/失败/挂起）驱动打开恢复流程到达目标节拍
          // 轨三态，自动首尾可用性按同一生产路径派生。
          if (beatPipeline != null)
            beatAnalysisPipelineProvider.overrideWithValue(beatPipeline),
          // 排程消费 seam 注入：fake 断言指令内容与时刻。
          if (beatScheduleConsumer != null)
            beatScheduleConsumerProvider.overrideWithValue(
              beatScheduleConsumer,
            ),
          // 渲染器生命周期 seam 注入：fake 断言退后台下推序列。
          if (beatAudioRenderer != null)
            beatAudioRendererProvider.overrideWithValue(beatAudioRenderer),
          // 位置未就绪 seam：空位置流，AsyncValue.value == null。
          if (!positionReady)
            playbackPositionProvider.overrideWith(
              (ref) => const Stream<Duration>.empty(),
            ),
          systemUiControllerProvider.overrideWithValue(
            systemUi ?? FakeSystemUi(),
          ),
          screenBrightnessControllerProvider.overrideWithValue(
            brightness ?? FakeScreenBrightnessController(),
          ),
          // 系统媒体音量 seam：注入 fake 断言手势写系统流。
          systemMediaVolumeControllerProvider.overrideWithValue(
            volume ?? FakeSystemMediaVolumeController(),
          ),
          // 内存索引（镜像接线后 PlayerPage 需要读索引）：种入
          // 与 source 匹配的「已询问」条目（镜像默认 false；画面层接线断言
          // 用 `mirrored: true` 种真值）→ 走「按历史应用」路径，顶部短暂
          // 提示不拦截任何交互，不干扰本文件的手势断言。
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(
                    filePath: resolvedSource.toFilePath(),
                    mirrored: mirrored,
                    // 与固定哈希一致，恢复路径的内容校验才放行。
                    videoId: localDoc != null ? 'vid-a' : 'seeded',
                  ),
                ],
              ),
            ),
          ),
          if (inMemoryPrivateJson)
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
        ],
        child: MaterialApp(
          home: PlayerPage(key: pageKey, source: resolvedSource),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
    // 节拍动画总开关默认关——本文件用例针对数拍浮层机制本身，
    // 先把总开关置开（空态一用例随后显式关闭，仍覆盖「关 → 不挂载」）。
    if (settle) {
      turnBeatAnimationOn(tester);
      await tester.pump();
    }
  }

  /// 双击手势：两次 tap 间隔 < kDoubleTapTimeout（300ms）。
  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(finder);
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 从 [start] 起按 [deltas] 步进拖动（每步 moveBy + pump）。
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

  /// 双指拖动：两指同步按 [deltas] 步进。
  Future<void> stepDragTwoFingers(
    WidgetTester tester,
    Offset start1,
    Offset start2,
    List<Offset> deltas,
  ) async {
    final g1 = await tester.startGesture(start1);
    final g2 = await tester.startGesture(start2);
    for (final delta in deltas) {
      await g1.moveBy(delta);
      await g2.moveBy(delta);
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pumpAndSettle();
  }

  /// 从 [start] 右滑 [frames] 帧（每帧 [delta]，不抬起），返回进行中的
  /// 手势以便中间断言后手动 up。
  Future<TestGesture> dragFrames(
    WidgetTester tester,
    Offset start,
    int frames, {
    Offset delta = const Offset(20, 0),
  }) async {
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < frames; i++) {
      await gesture.moveBy(delta);
      await tester.pump();
    }
    return gesture;
  }

  /// 共用编排：打开编辑器并播种分段线（停在控制层展开态）。
  Future<ProviderContainer> openEditorWithSegmentLines(
    WidgetTester tester,
    FakePlaybackEngine engine,
    List<Duration> positions, {
    BeatScheduleConsumer? beatScheduleConsumer,
    BeatAudioRenderer? beatAudioRenderer,
    bool positionReady = true,
    Map<String, dynamic>? localDoc,
  }) async {
    await pumpPlayer(
      tester,
      engine: engine,
      beatScheduleConsumer: beatScheduleConsumer,
      beatAudioRenderer: beatAudioRenderer,
      positionReady: positionReady,
      localDoc: localDoc,
    );
    await singleTapShow(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
    // 既有用例验证「不延迟」的立即循环路径（默认 4 拍延迟后，
    // 到段尾先静帧等待；延迟路径由本组专测覆盖）。
    container.read(prepBeatsProvider.notifier).setLoopLead(0);
    // 经标注编辑模块命令播种分段线（store 写缝已私有）。
    final editor = container.read(annotationEditorProvider);
    for (final position in positions) {
      editor.submit(AddSegmentLine(at: position));
    }
    await tester.pumpAndSettle();
    return container;
  }

  group('进入播放器', () {
    testWidgets('打开即播放：open(source, play: true)，进入沉浸/全方向模式', (tester) async {
      final engine = FakePlaybackEngine();
      final systemUi = FakeSystemUi();
      final source = Uri.file('/videos/a.mp4');

      await pumpPlayer(
        tester,
        engine: engine,
        systemUi: systemUi,
        source: source,
      );

      expect(engine.source, source);
      expect(engine.isPlaying, isTrue);
      expect(systemUi.enterCount, 1);
      // 播放中不显示中央播放提示。
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });

    testWidgets('打开失败时展示错误提示且不进入播放态', (tester) async {
      final engine = _ThrowingOpenEngine();

      await pumpPlayer(tester, engine: engine);

      expect(find.text('视频打开失败'), findsOneWidget);
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('打开在途的帧不显示中央播放指示（引擎此刻还没有可报的播放态）', (tester) async {
      final engine = _SlowOpenEngine();

      await pumpPlayer(tester, engine: engine, settle: false);
      await tester.pump();

      // 打开在途：引擎 isPlaying=false，但这不是「暂停」——指示不得提前挂出
      // （把可见条件改成直读引擎后，这一帧最容易回归）。
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsNothing);

      engine.completeOpen();
      await tester.pumpAndSettle();

      expect(engine.isPlaying, isTrue);
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });
  });

  group('装载未完成门', () {
    /// 挂起公开标记文件读：把打开会话钉在「装载未完成」。打开路径按路径命中
    /// 条目即取身份、不读视频内容，故可挂起的环节是建立序列的文档读，不是摘要。
    Future<_GatedMarkersStorage> pumpLoadingPage(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
      FakeScreenBrightnessController? brightness,
      FakeSystemMediaVolumeController? volume,
    }) async {
      // 实体文件：门的存续只在真有文件可装载时成立（无文件即刻落定）。
      final dir = Directory.systemTemp.createTempSync('load_gate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/a.mp4')..writeAsBytesSync(const [0]);
      final docs = _GatedMarkersStorage();
      await pumpPlayer(
        tester,
        engine: engine,
        source: Uri.file(file.path),
        hasher: const FixedHasher('seeded'),
        docs: docs,
        beatPipeline: hangingBeatPipeline,
        brightness: brightness,
        volume: volume,
      );
      return docs;
    }

    testWidgets('装载未完成：点进编辑器被挡并弹「正在装载」；播放/拖动/亮度音量不受影响；落定后放行', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final brightness = FakeScreenBrightnessController(initialBrightness: 0.5);
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      final docs = await pumpLoadingPage(
        tester,
        engine: engine,
        brightness: brightness,
        volume: volume,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(container.read(loadGateActiveProvider), isTrue);

      // 单击画面（进编辑器入口）被同一道门挡下：控制层不展开、弹原因。
      await singleTapShow(tester);
      expect(find.byKey(const Key('control_layer')), findsNothing);
      expect(find.text('正在装载'), findsOneWidget);

      // 播放 / 暂停不受门影响（双击）。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue);

      // 拖动（单指左滑调进度）不受门影响。
      await tester.pump(const Duration(seconds: 30));
      final before = engine.position;
      await stepDrag(
        tester,
        const Offset(600, 400),
        List.filled(10, const Offset(-20, 0)),
      );
      expect(engine.position, isNot(before));

      // 亮度（左半屏竖直滑）与音量（右半屏竖直滑）手势不受门影响。
      await stepDrag(
        tester,
        const Offset(200, 400),
        List.filled(10, const Offset(0, -20)),
      );
      expect(brightness.setCalls, isNotEmpty);
      await stepDrag(
        tester,
        const Offset(600, 300),
        List.filled(10, const Offset(0, -20)),
      );
      expect(volume.setCalls, isNotEmpty);

      // 装载落定（建立序列走完）→ 入口自动恢复可用，无需重开页面。
      // 身份由 pumpPlayer 种入的索引条目按路径承载（镜像走历史应用，不弹
      // 询问遮罩）；身份值本身不参与门断言。
      docs.release();
      await tester.pumpAndSettle();
      expect(container.read(loadGateActiveProvider), isFalse);
      await singleTapShow(tester);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });
  });

  group('播放/暂停', () {
    testWidgets('双击画面播放/暂停切换，中央提示随之显隐', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);

      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);

      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue);
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });

    testWidgets('播放到尾（completed 事件）进入暂停态', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
      await pumpPlayer(tester, engine: engine);

      await tester.pump(const Duration(seconds: 2));

      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('画面播放开关：语义激活真的切换引擎播放态', (tester) async {
      const switchKey = Key('picture_play_switch');
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      expect(engine.isPlaying, isTrue);

      expectButtonSemantics(tester, switchKey, label: '暂停画面', enabled: true);
      semanticsOfKey(tester, switchKey).properties.onTap!();
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse, reason: '语义激活走与双击同一条写入口');
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
      expectButtonSemantics(tester, switchKey, label: '播放画面', enabled: true);
    });
  });

  group('基础手势', () {
    testWidgets('单指左滑调进度：position 减小（低灵敏度）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位，避免钳制
      final before = engine.position;

      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(10, const Offset(-20, 0)),
      );

      expect(engine.position, lessThan(before));
    });

    testWidgets('单指右滑调进度：position 增大', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      final before = engine.position; // 0

      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(10, const Offset(20, 0)),
      );

      expect(engine.position, greaterThan(before));
    });

    testWidgets('拖动调进度：seek 目标 = 手势起点 + 累计增量（真机回归：逐帧小增量 seek 被 mpv 丢弃）', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      // 暂停以冻结 position（避免播放漂移干扰精确断言）。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      final base = engine.position;

      // 单指右滑 200px（20px × 10 帧，50ms/px）→ 累计应 +10s。
      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(10, const Offset(20, 0)),
      );

      expect(engine.seekCalls, isNotEmpty);
      // 识别器 slop 会吃掉首帧位移（真机同样损失起始 ~18px），故不精确断言
      // 10s；断言累计到位（≥8s，旧实现目标只在 base±300ms 抖动）。
      final last = engine.seekCalls.last;
      expect(
        last,
        greaterThanOrEqualTo(base + const Duration(seconds: 8)),
        reason: 'seek 目标应为手势起点+累计增量（非逐帧小增量，防真机 seek 丢失）',
      );
      // 目标单调不减：旧实现从过期 position 出发，目标来回横跳不单调。
      for (var i = 1; i < engine.seekCalls.length; i++) {
        final gap = engine.seekCalls[i] - engine.seekCalls[i - 1];
        expect(
          gap.inMilliseconds,
          greaterThanOrEqualTo(0),
          reason: '向右拖动 seek 目标应单调不减',
        );
      }
    });

    testWidgets('视频开头单指左滑：seek 目标被钳制不低于 0', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      // position 从 0 开始，左滑的 seek 目标恒为负 → widget 钳制到 0。
      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(10, const Offset(-20, 0)),
      );

      expect(engine.seekCalls, isNotEmpty);
      expect(engine.seekCalls.every((t) => t >= Duration.zero), isTrue);
    });

    testWidgets('双指左滑灵敏度更高：位移约 3× 单指', (tester) async {
      final singleEngine = FakePlaybackEngine(
        duration: const Duration(minutes: 3),
      );
      await pumpPlayer(tester, engine: singleEngine);
      await tester.pump(const Duration(seconds: 30));
      final singleBefore = singleEngine.position;
      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(10, const Offset(-20, 0)),
      );
      final singleDeltaMs =
          (singleBefore - singleEngine.position).inMilliseconds;

      final dualEngine = FakePlaybackEngine(
        duration: const Duration(minutes: 3),
      );
      // 第二次 pump 需强制重建 PlayerPage（同形 widget 树默认复用 State，
      // 否则新引擎不会被读取）。
      await pumpPlayer(tester, engine: dualEngine, pageKey: UniqueKey());
      await tester.pump(const Duration(seconds: 30));
      final dualBefore = dualEngine.position;
      await stepDragTwoFingers(
        tester,
        const Offset(360, 300),
        const Offset(440, 300),
        List.filled(10, const Offset(-20, 0)),
      );
      final dualDeltaMs = (dualBefore - dualEngine.position).inMilliseconds;

      expect(dualDeltaMs, greaterThan(singleDeltaMs));
      expect(
        dualDeltaMs,
        closeTo(
          singleDeltaMs * kSeekDoubleFingerMultiplier,
          singleDeltaMs * kSeekDoubleFingerMultiplier * 0.4,
        ),
      );
    });

    testWidgets('双指横滑中途抬一指、单指续滑：不降档不重开基准（burst 锁定）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      // 暂停并定位到 30s（固定 seek 基准），清空记录。
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      final g1 = await tester.startGesture(const Offset(360, 300));
      final g2 = await tester.startGesture(const Offset(440, 300));
      // 双指右滑：每帧两指各 +20px（焦点每 move +10px，共 6 个 update）
      // → 累计 60px × 50ms × 3 = +9s（轴锁定 slop 由首两步跨过）。
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(20, 0));
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      final afterDual = engine.seekCalls.last;
      // 串行 seek 为 latest-wins，中间目标可能被合并，但末目标 = 基准 +
      // 累计增量：双指段末目标必为 36s（40px×150ms/px；首步 slop 内不产出）。
      expect(afterDual, const Duration(seconds: 36));

      // 中途抬一指，余下单指续滑 3 帧（同 60px）：仍按双指灵敏度（+3s/
      // 20px，不降档为 +1s/20px）且不重取基准（目标自 36s 续加 → 末值 45s）。
      await g1.up();
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g2.up();
      await tester.pumpAndSettle();

      expect(engine.seekCalls.last, const Duration(seconds: 45));
      expect(engine.position, const Duration(seconds: 45));
      // 续滑段（> 36s 的目标）每步增量仍为 3s（无双指→单指降档），
      // 且自 36s 连续续加（无基准重取断层：降档会产出 +1s 步进、重取
      // 基准则首个续滑目标 ≤ 37s 且总末值 < 45s）。
      final tail = engine.seekCalls
          .where((t) => t > const Duration(seconds: 36))
          .toList();
      var previous = const Duration(seconds: 36);
      for (final target in tail) {
        expect(target - previous, const Duration(seconds: 3));
        previous = target;
      }
      expect(previous, const Duration(seconds: 45));
    });

    testWidgets('右半屏上滑调大系统媒体音量、下滑调小（与侧键同源）', (tester) async {
      final engine = FakePlaybackEngine();
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await pumpPlayer(tester, engine: engine, volume: volume);

      await stepDrag(
        tester,
        const Offset(600, 400),
        List.filled(10, const Offset(0, -20)),
      );
      final afterUp = volume.currentVolume;
      expect(afterUp, greaterThan(0.5));
      expect(volume.setCalls, isNotEmpty);

      await stepDrag(
        tester,
        const Offset(600, 400),
        List.filled(10, const Offset(0, 20)),
      );
      expect(volume.currentVolume, lessThan(afterUp));
      expect(volume.currentVolume, greaterThan(0.0));
      // 调音量全程引擎无 pause/play/seek。
      expect(engine.callLog, ['play']);
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('左半屏上滑调大亮度、下滑调小', (tester) async {
      final engine = FakePlaybackEngine();
      final brightness = FakeScreenBrightnessController(initialBrightness: 0.5);
      await pumpPlayer(tester, engine: engine, brightness: brightness);

      await stepDrag(
        tester,
        const Offset(200, 400),
        List.filled(10, const Offset(0, -20)),
      );
      final afterUp = brightness.initialBrightness;
      expect(afterUp, greaterThan(0.5));
      expect(brightness.setCalls, isNotEmpty);

      await stepDrag(
        tester,
        const Offset(200, 400),
        List.filled(10, const Offset(0, 20)),
      );
      expect(brightness.initialBrightness, lessThan(afterUp));
      expect(brightness.initialBrightness, greaterThan(0.0));
    });

    testWidgets('右半屏水平滑调进度、不误触系统媒体音量（轴向锁定）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await pumpPlayer(tester, engine: engine, volume: volume);
      await tester.pump(const Duration(seconds: 30));
      final before = engine.position;

      await stepDrag(
        tester,
        const Offset(600, 300),
        List.filled(10, const Offset(-20, 0)),
      );

      expect(engine.position, lessThan(before));
      expect(volume.setCalls, isEmpty);
      expect(volume.currentVolume, 0.5);
    });

    testWidgets('双指垂直滑不触发动作（未绑定）', (tester) async {
      final engine = FakePlaybackEngine();
      final brightness = FakeScreenBrightnessController(initialBrightness: 0.5);
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await pumpPlayer(
        tester,
        engine: engine,
        brightness: brightness,
        volume: volume,
      );

      await stepDragTwoFingers(
        tester,
        const Offset(300, 200),
        const Offset(500, 200),
        List.filled(10, const Offset(0, -20)),
      );

      expect(volume.setCalls, isEmpty);
      expect(volume.currentVolume, 0.5);
      expect(brightness.setCalls, isEmpty);
    });
  });

  group('进度拖动定格预览', () {
    testWidgets('轴锁定前（未越阈值）不暂停、不 seek（既有行为不变）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      expect(engine.isPlaying, isTrue);
      final callsBefore = engine.callLog.length;

      // 累计位移 < kAxisLockSlop（18px）：解释器不产出 seek 动作。
      final gesture = await dragFrames(
        tester,
        const Offset(400, 300),
        2,
        delta: const Offset(8, 0),
      );
      await gesture.up();
      await tester.pump();

      expect(engine.seekCalls, isEmpty);
      expect(engine.callLog.length, callsBefore, reason: '轴锁定前不暂停、不 seek');
      expect(engine.isPlaying, isTrue, reason: '轴锁定前不暂停');
    });

    testWidgets('在播右滑：轴锁定后先 pause 再逐帧 seek，position 收敛到最新目标', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位
      final base = engine.position;
      expect(engine.isPlaying, isTrue);

      final gesture = await dragFrames(tester, const Offset(400, 300), 10);
      // 排空串行 seek 队列（latest-wins 收敛）。
      await tester.pump();
      await tester.pump();

      // 轴锁定后、首次 seek 前已 pause；拖动中保持暂停（画面定格预览）。
      expect(engine.isPlaying, isFalse);
      final pauseIdx = engine.callLog.indexOf('pause');
      final firstSeek = engine.callLog.indexOf('seek');
      expect(pauseIdx, greaterThanOrEqualTo(0), reason: '原在播应先 pause');
      expect(firstSeek, greaterThan(pauseIdx), reason: 'pause 须先于首次 seek');
      expect(
        engine.callLog.sublist(pauseIdx + 1).contains('play'),
        isFalse,
        reason: '拖动中不恢复播放',
      );

      // 逐帧 seek 收敛：position == 最后（钳制后的）目标。
      expect(engine.seekCalls, isNotEmpty);
      expect(engine.position, engine.seekCalls.last);
      expect(engine.position, greaterThan(base), reason: '右滑进度前进');

      // scrubbing 预览期间：暂停态但无中央大图标。
      expect(find.byKey(const Key('play_indicator')), findsNothing);

      // 松手：原先在播 → play 从落点继续。
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(engine.callLog.last, 'play');
      expect(engine.isPlaying, isTrue);
      expect(
        engine.position,
        engine.seekCalls.last,
        reason: '从落点继续（未推进时钟前 position 不变）',
      );

      // 双击回归：scrub 结束后暂停/播放切换正常，图标按真实状态。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('原已暂停拖动：不额外 pause/play，松手保持暂停；图标如实显示', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      // 先双击暂停（原已暂停场景）。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
      final pauseCountBefore = engine.callLog.where((c) => c == 'pause').length;

      final gesture = await dragFrames(tester, const Offset(400, 300), 8);
      await tester.pump();
      await tester.pump();

      // 拖动中：保持暂停；未再发 pause/play（仅 seek）。
      expect(engine.isPlaying, isFalse);
      expect(
        engine.callLog.where((c) => c == 'pause').length,
        pauseCountBefore,
        reason: '原已暂停则 scrub 不再 pause',
      );
      expect(
        engine.callLog.where((c) => c == 'play').length,
        1,
        reason: 'scrub 期间与结束都不 play（只有 open 那次 play）',
      );
      expect(engine.seekCalls, isNotEmpty);
      expect(engine.position, engine.seekCalls.last);
      // scrubbing 期间：暂停态大图标被抑制。
      expect(find.byKey(const Key('play_indicator')), findsNothing);

      await gesture.up();
      await tester.pump();
      await tester.pump();

      // 松手：原已暂停 → 保持暂停；图标按真实状态如实显示。
      expect(engine.isPlaying, isFalse);
      expect(engine.callLog.last, isNot('play'));
      expect(engine.position, engine.seekCalls.last);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('scrub 被系统指针取消（PointerCancel）时恢复手势前播放态', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位
      expect(engine.isPlaying, isTrue);

      // 轴锁定 → scrubbing（引擎已暂停定格）。
      final gesture = await dragFrames(tester, const Offset(400, 300), 10);
      await tester.pump();
      expect(engine.isPlaying, isFalse);
      expect(engine.callLog.contains('pause'), isTrue);

      // 系统取消指针（GestureDetector 无 onScaleCancel，靠顶层 Listener
      // 收尾）：应恢复手势前播放态（原先在播 → play 继续）。
      await gesture.cancel();
      await tester.pump();
      await tester.pump();

      expect(engine.isPlaying, isTrue, reason: '指针取消不得让引擎停留在 scrub 暂停态');
      expect(engine.callLog.last, 'play');
      // 相位已回 idle：暂停态大图标按真实状态（播放中 → 不显示）。
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });

    testWidgets('越界拖动 seek 目标钳制（首/尾），position 收敛到钳制值', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 10));
      await pumpPlayer(tester, engine: engine);
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);

      // 尾部钳制：右滑远超时长 → 目标收敛到 duration。
      // 单指 50ms/px：300px→15s > 10s；slop 损失 ~40px 后仍远超时长。
      final gesture = await dragFrames(
        tester,
        const Offset(200, 300),
        10,
        delta: const Offset(30, 0),
      );
      await tester.pump();
      await tester.pump();
      expect(engine.seekCalls, isNotEmpty);
      expect(engine.seekCalls.last, const Duration(seconds: 10));
      expect(engine.position, const Duration(seconds: 10));
      await gesture.up();
      await tester.pump();

      // 首部钳制：从结尾左滑远超 → 目标收敛到 0。
      final gesture2 = await dragFrames(
        tester,
        const Offset(600, 300),
        10,
        delta: const Offset(-30, 0),
      );
      await tester.pump();
      await tester.pump();
      expect(engine.seekCalls.last, Duration.zero);
      expect(engine.position, Duration.zero);
      await gesture2.up();
      await tester.pump();
      expect(engine.position, Duration.zero);
      expect(engine.isPlaying, isFalse);
    });
  });

  group('scrub 指示浮层（迷你进度条与时间文本）', () {
    /// 把引擎停在「暂停且 position=0」的确定性状态（指示文本断言按 0 位
    /// 起步；pause 停 ticker、seek 归零，不依赖拖动前播放推进的节拍）。
    Future<void> parkPausedAtZero(FakePlaybackEngine engine) async {
      await engine.pause();
      await engine.seek(Duration.zero);
    }

    /// 断言游标（填充）占条比例 ≈ [ratio]：按轨道实测宽度换算
    /// （不依赖测试屏幕尺寸与常量值）。
    void expectFillRatio(WidgetTester tester, double ratio) {
      final bar = tester.getSize(find.byKey(const Key('scrub_indicator_bar')));
      final fill = tester.getSize(
        find.byKey(const Key('scrub_indicator_fill')),
      );
      expect(
        fill.width / bar.width,
        closeTo(ratio, 0.005),
        reason: '游标占条比例 = 钳制后目标 / 总长',
      );
    }

    testWidgets('scrubbing 出现迷你条与「目标/总长」文本；多帧拖动后按钳制后目标更新；松手即消失', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await parkPausedAtZero(engine);
      await tester.pump();

      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '未进入 scrubbing 不显示指示浮层',
      );

      final gesture = await dragFrames(tester, const Offset(400, 300), 10);
      await tester.pump();
      await tester.pump();

      // 出现；文本与游标 = 钳制后目标 / 总长（mm:ss:ff，帧号格式）。期望值以
      // 引擎观测为准（seekCalls.last 即引擎收到的钳制后目标——串行队列
      // 排空后与指示目标一致），不写死像素→秒换算（scale 识别器验收会
      // 吸收首帧位移，帧数与秒数非 1:1，不属本测试契约）。
      final totalMs = const Duration(minutes: 3).inMilliseconds;
      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      final targetAfterFirstSegment = engine.seekCalls.last;
      expect(targetAfterFirstSegment, greaterThan(Duration.zero));
      expect(
        find.text('${formatFrameTime(targetAfterFirstSegment)} / 03:00:00'),
        findsOneWidget,
      );
      expectFillRatio(tester, targetAfterFirstSegment.inMilliseconds / totalMs);

      // 继续拖动 10 帧：文本与游标随新目标更新（非停滞在首帧目标）。
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await tester.pump();
      await tester.pump();
      final targetAfterSecondSegment = engine.seekCalls.last;
      expect(
        targetAfterSecondSegment,
        greaterThan(targetAfterFirstSegment),
        reason: '拖动若干帧后指示目标随拖动更新',
      );
      expect(
        find.text('${formatFrameTime(targetAfterSecondSegment)} / 03:00:00'),
        findsOneWidget,
      );
      expectFillRatio(
        tester,
        targetAfterSecondSegment.inMilliseconds / totalMs,
      );

      // 松手（原已暂停）：指示消失，保持暂停，大图标按真实状态显示。
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('越界拖动：指示目标与文本随钳制收敛（尾钳时长 / 首钳 0）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 10));
      await pumpPlayer(tester, engine: engine);
      await parkPausedAtZero(engine);
      await tester.pump();

      // 尾钳制：右滑 10×30px → 裸目标 ≈13.5s > 10s → 显示 10s（== 总长）。
      final gesture = await dragFrames(
        tester,
        const Offset(200, 300),
        10,
        delta: const Offset(30, 0),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('00:10:00 / 00:10:00'), findsOneWidget);
      expectFillRatio(tester, 1.0);
      await gesture.up();
      await tester.pump();
      await tester.pump();

      // 首钳制：已停在 10s 处左滑 10×30px → 裸目标 < 0 → 显示 0。
      final gesture2 = await dragFrames(
        tester,
        const Offset(600, 300),
        10,
        delta: const Offset(-30, 0),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('00:00:00 / 00:10:00'), findsOneWidget);
      expectFillRatio(tester, 0.0);
      await gesture2.up();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
    });

    testWidgets('时长未知（duration null）：只显示目标时间，无比例条与总长，不崩溃', (tester) async {
      final engine = _DurationlessEngine();
      await pumpPlayer(tester, engine: engine);
      await engine.pause();
      await engine.seek(Duration.zero);
      await tester.pump();

      final gesture = await dragFrames(tester, const Offset(400, 300), 10);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      expect(
        find.text(formatFrameTime(engine.seekCalls.last)),
        findsOneWidget,
        reason: '只显示目标时间（期望值同 test 1：以引擎观测为准）',
      );
      expect(find.textContaining(' / '), findsNothing, reason: '不显示总长');
      expect(
        find.byKey(const Key('scrub_indicator_bar')),
        findsNothing,
        reason: '时长未知无总长可比，不显示比例条',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
    });

    testWidgets('浮层 IgnorePointer：指示可见期间继续拖动 seek 持续生效，松手恢复播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位，避免钳制
      expect(engine.isPlaying, isTrue);

      final gesture = await dragFrames(tester, const Offset(400, 300), 5);
      await tester.pump();
      await tester.pump();

      // 指示已出现（轴锁定 + 首个 seek 后）；在播先暂停定格预览。
      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      expect(engine.isPlaying, isFalse);
      final targetAtIndicator = engine.seekCalls.last;
      final seekCountAtIndicator = engine.seekCalls.length;

      // 指示可见期间继续拖动 10 帧：seek 逐帧持续生效（浮层不拦截），
      // 目标逐帧推进并收敛到最新值（latest-wins）。
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await tester.pump();
      await tester.pump();
      expect(
        engine.seekCalls.length,
        greaterThan(seekCountAtIndicator),
        reason: '拖动全程不被浮层拦截，seek 持续生效',
      );
      final convergedTarget = engine.seekCalls.last;
      expect(
        convergedTarget,
        greaterThan(targetAtIndicator),
        reason: '指示可见期间目标随拖动逐帧推进',
      );
      expect(engine.position, convergedTarget, reason: '串行 seek 收敛到最新（钳制后）目标');
      expect(
        find.text('${formatFrameTime(convergedTarget)} / 03:00:00'),
        findsOneWidget,
      );

      // 松手：原先在播 → play 从落点继续；指示消失。
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(engine.callLog.last, 'play');
      expect(engine.isPlaying, isTrue);
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
    });

    testWidgets('轴锁定前不显示指示（相位与 09 一致）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await parkPausedAtZero(engine);
      await tester.pump();

      // 累计位移 16px < kAxisLockSlop（18px）：不进入 scrubbing。
      final gesture = await dragFrames(
        tester,
        const Offset(400, 300),
        2,
        delta: const Offset(8, 0),
      );
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
    });
  });

  group('音量/亮度横向滑条', () {
    /// 滑条填充比例：填充宽 / 底轨宽（0..1）。
    double fillRatio(WidgetTester tester) {
      final track = tester.getSize(find.byKey(const Key('level_track')));
      final fill = tester.getSize(find.byKey(const Key('level_fill')));
      return fill.width / track.width;
    }

    testWidgets('右半屏垂直滑：轴锁定后出现音量滑条（喇叭图标），填充随系统媒体音量更新，'
        '调节期间不暂停/无进度反馈，松手立即消失', (tester) async {
      final engine = FakePlaybackEngine();
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.3);
      await pumpPlayer(tester, engine: engine, volume: volume);
      expect(engine.isPlaying, isTrue);
      expect(engine.callLog, ['play'], reason: 'open(play: true) 仅一次 play');

      final gesture = await tester.startGesture(const Offset(600, 400));

      // 轴锁定前（累计位移 < kAxisLockSlop）：无滑条、音量不变、引擎无调用。
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump();
      expect(
        find.byKey(const Key('level_adjust_slider')),
        findsNothing,
        reason: '轴锁定前不显示音量/亮度滑条',
      );
      expect(volume.setCalls, isEmpty);
      expect(engine.callLog, ['play']);

      // 越过轴向锁定阈值（连续上滑）：出现音量滑条，填充随当前值更新。
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      final slider = find.byKey(const Key('level_adjust_slider'));
      expect(slider, findsOneWidget, reason: '轴锁定后出现横向滑条');
      expect(
        find.descendant(of: slider, matching: find.byIcon(Icons.volume_up)),
        findsOneWidget,
        reason: '右半屏垂直滑 → 音量（喇叭）图标',
      );
      expect(volume.currentVolume, greaterThan(0.3), reason: '上滑调大音量');
      expect(
        fillRatio(tester),
        closeTo(volume.currentVolume, 0.02),
        reason: '填充长度 == 系统媒体音量当前比例（0..1），从左到右实时更新',
      );
      // 手势期间的值可播报：滑条本身无语义，旁边挂一个
      // liveRegion 报出对象与百分比。
      expectSemanticsLabel(
        tester,
        const Key('level_adjust_announce'),
        label: '音量 ${(volume.currentVolume * 100).round()}%',
        liveRegion: true,
        reason: '音量变化要能被读屏播报出具体值',
      );

      // 继续上滑（滑条可见、IgnorePointer 不拦截触摸）：音量与填充继续增长。
      final v1 = volume.currentVolume;
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
      }
      expect(
        volume.currentVolume,
        greaterThan(v1),
        reason: '滑条显示期间拖动持续生效（浮层不拦截触摸）',
      );
      expect(fillRatio(tester), closeTo(volume.currentVolume, 0.02));
      expectSemanticsLabel(
        tester,
        const Key('level_adjust_announce'),
        label: '音量 ${(volume.currentVolume * 100).round()}%',
        liveRegion: true,
        reason: '值变化后播报区域跟着更新',
      );
      expect(engine.seekCalls, isEmpty, reason: '垂直手势不产生进度反馈');

      // 调节期间：引擎无 pause/play（不暂停播放）、无 seek（无进度反馈）、
      // 无暂停态中央大图标。
      expect(engine.isPlaying, isTrue, reason: '调音量期间不暂停播放');
      expect(engine.callLog, ['play'], reason: '调音量期间引擎无 pause/play 调用');
      expect(engine.seekCalls, isEmpty, reason: '垂直手势不产生进度反馈');
      expect(find.byKey(const Key('play_indicator')), findsNothing);

      // 松手：滑条立即消失（无延迟淡出——不额外推进时钟）。
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('level_adjust_slider')),
        findsNothing,
        reason: '松手即消失',
      );
      expect(engine.isPlaying, isTrue, reason: '松手后播放不受影响');
      expect(engine.callLog, ['play']);
    });

    testWidgets('暂停中垂直调音量：保持暂停、无额外 pause/play；调节期间中央大图标被抑制，'
        '松手后按真实状态如实显示', (tester) async {
      final engine = FakePlaybackEngine();
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.3);
      await pumpPlayer(tester, engine: engine, volume: volume);
      // 先双击暂停（原已暂停场景）。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
      final callLogBefore = List.of(engine.callLog);

      final gesture = await tester.startGesture(const Offset(600, 400));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
      }

      // 调节期间：引擎无新 pause/play（不恢复播放）；暂停态大图标被抑制
      // （不与滑条重叠）；滑条填充随当前值。
      expect(engine.isPlaying, isFalse, reason: '调音量不改变播放态');
      expect(engine.callLog, callLogBefore, reason: '调音量期间引擎无 pause/play 调用');
      expect(find.byKey(const Key('level_adjust_slider')), findsOneWidget);
      expect(
        find.byKey(const Key('play_indicator')),
        findsNothing,
        reason: '反馈相位激活期间中央大图标不显示（避免遮挡滑条）',
      );
      expect(fillRatio(tester), closeTo(volume.currentVolume, 0.02));
      expect(volume.currentVolume, greaterThan(0.3));

      // 松手：滑条消失，暂停态大图标按真实状态（仍暂停）如实显示。
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('level_adjust_slider')), findsNothing);
      expect(engine.isPlaying, isFalse);
      expect(
        find.byKey(const Key('play_indicator')),
        findsOneWidget,
        reason: '结束后按真实状态如实显示',
      );
    });

    testWidgets('左半屏垂直滑：轴锁定后出现亮度滑条（太阳图标），填充随当前亮度更新', (tester) async {
      final engine = FakePlaybackEngine();
      final brightness = FakeScreenBrightnessController(initialBrightness: 0.4);
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await pumpPlayer(
        tester,
        engine: engine,
        brightness: brightness,
        volume: volume,
      );
      expect(brightness.setCalls, isEmpty);

      final gesture = await tester.startGesture(const Offset(200, 400));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump();
      }

      expect(brightness.setCalls, isNotEmpty);
      final current = brightness.initialBrightness; // setBrightness 已回写
      expect(current, greaterThan(0.4), reason: '上滑调大亮度');
      final slider = find.byKey(const Key('level_adjust_slider'));
      expect(slider, findsOneWidget);
      expect(
        find.descendant(of: slider, matching: find.byIcon(Icons.wb_sunny)),
        findsOneWidget,
        reason: '左半屏垂直滑 → 亮度（太阳）图标',
      );
      expect(
        fillRatio(tester),
        closeTo(current, 0.02),
        reason: '填充长度 == 当前亮度（0..1）',
      );
      expect(volume.currentVolume, 0.5, reason: '亮度手势不动系统媒体音量');
      expect(engine.isPlaying, isTrue, reason: '调亮度期间不暂停播放');
      expect(engine.callLog, ['play'], reason: '调亮度期间引擎无 pause/play');
      expect(engine.seekCalls, isEmpty);
      expectSemanticsLabel(
        tester,
        const Key('level_adjust_announce'),
        label: '亮度 ${(current * 100).round()}%',
        liveRegion: true,
        reason: '亮度变化同样要能播报出具体值，且与音量区分对象',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('level_adjust_slider')),
        findsNothing,
        reason: '松手即消失',
      );
    });

    testWidgets('水平（进度）拖动不出现音量/亮度滑条：scrubbing 与 levelAdjust 互斥', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await pumpPlayer(tester, engine: engine, volume: volume);
      await tester.pump(const Duration(seconds: 30)); // 离开 0 位
      final volumeBefore = volume.currentVolume;

      final gesture = await tester.startGesture(const Offset(600, 300));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      expect(engine.seekCalls, isNotEmpty, reason: '水平拖动调进度');
      expect(
        find.byKey(const Key('level_adjust_slider')),
        findsNothing,
        reason: '水平（进度）手势不出现音量/亮度滑条（反馈互斥）',
      );
      expect(volume.currentVolume, volumeBefore, reason: '水平拖动不调系统媒体音量');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue, reason: '松手恢复手势前播放态');
    });
  });

  group('画面层接线（整页只剩「该层被摆进树」）', () {
    testWidgets('层被摆进树，且吃到的宽高比与骨架来自引擎与页面', (tester) async {
      final engine = FakePlaybackEngine(videoAspectRatio: 9 / 16);
      await pumpPlayer(tester, engine: engine);

      final layer = find.byType(PictureLayer);
      expect(layer, findsOneWidget);
      final watching = tester.widget<PictureLayer>(layer).input;
      expect(watching.video.aspectRatio, 9 / 16, reason: '宽高比来自引擎');
      expect(watching.frame.skeleton, isNull, reason: '观看态不落骨架');
      expect(watching.frame.compareActive, isFalse);
      expect(find.byKey(videoSurfacePlaceholderKey), findsOneWidget);

      // 展开控制层 → 页面把竖屏编辑骨架交给画面层。
      await singleTapShow(tester);
      final editing = tester
          .widget<PictureLayer>(find.byType(PictureLayer))
          .input;
      expect(editing.frame.skeleton, isNotNull, reason: '编辑态骨架来自页面');
    });

    testWidgets('层吃到的画面方向来自源视频面装配点（镜像历史 → 镜像方向）', (tester) async {
      final engine = FakePlaybackEngine(videoAspectRatio: 9 / 16);
      // 固定哈希与索引条目 videoId 相符 → 走「按历史应用」，镜像真值真的落到
      // 装配点；画面层吃到的是装配点给出的方向，不是自己算的方向。
      await pumpPlayer(
        tester,
        engine: engine,
        mirrored: true,
        hasher: const FixedHasher('seeded'),
        docs: InMemoryVideoDocumentStorage(),
      );

      final input = tester
          .widget<PictureLayer>(find.byType(PictureLayer))
          .input;
      expect(input.face.source, FaceDirection.mirrored);
      expect(find.byKey(const Key('mirrored_surface')), findsOneWidget);
    });
  });

  group('视频首/尾设置与播放联动（自动首尾）', () {
    testWidgets('自动首尾一次写入节拍轨首末拍，轨道首尾线即时移动（末拍不归格点）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_auto_seg_4')));
      await tester.pumpAndSettle();

      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      // 内容区左缘让出轨道片头带——期望位置问模块同一口径。
      final axis = bandGeometryOf(
        total: const Duration(minutes: 3),
        width: width,
      ).axis;
      // 首 = 第一拍 0.5s、尾 = 最后一拍 2.0s；末拍 2.0s 不在格点（0.5s 起
      // 每四拍）也不被挪动——音乐边界优先于网格。
      expect(
        tester.getCenter(find.byKey(const Key('video_range_start_line'))).dx,
        closeTo(axis.timeToX(const Duration(milliseconds: 500)), 2),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_end_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 2)), 2),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(milliseconds: 500),
      );
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 2),
      );

      // 重新点击可再触发（重复提交同一动作不报错、幂等落位）。
      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_auto_seg_4')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(milliseconds: 500),
      );
    });

    testWidgets('设为视频首/尾写入当前播放位置，轨道首尾线即时移动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('toolbar_play'))); // 暂停。
      await tester.pumpAndSettle();

      await submitRange(tester, start: const Duration(seconds: 20));
      await engine.seek(const Duration(seconds: 40));
      await tester.pump();
      await submitRange(tester, end: const Duration(seconds: 40));

      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      final axis = bandGeometryOf(
        total: const Duration(minutes: 3),
        width: width,
      ).axis;
      expect(
        tester.getCenter(find.byKey(const Key('video_range_start_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 20)), 2),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_end_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 40)), 2),
      );
    });

    testWidgets('播放到自定义视频尾停止并弹提示，延迟八拍后从视频首循环', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();

      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await submitRange(tester, start: const Duration(seconds: 20));
      await submitRange(tester, end: const Duration(seconds: 40));

      // 收起控制层后播放：从尾点按下播放会先回视频首。
      // 空白单击经约 300ms 双击判定窗口后收起。
      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pump();
      expect(engine.position, const Duration(seconds: 20));

      await tester.pump(const Duration(seconds: 20));
      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 40));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      expect(engine.isPlaying, isTrue);
      expect(
        engine.position,
        greaterThanOrEqualTo(const Duration(seconds: 20)),
      );
      expect(engine.position, lessThan(const Duration(seconds: 21)));
    });

    testWidgets('进度拖出区间暂停查看；出界按播放原地播放不拉回', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('toolbar_play'))); // 暂停打开自动播放。
      await tester.pumpAndSettle();

      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await submitRange(tester, start: const Duration(seconds: 20));
      await submitRange(tester, end: const Duration(seconds: 40));

      // 带内空白横滑改走精细调整；拖出区间的绝对跟手语义经预览
      // 线命中列接管路径（手柄带）——预览线先 seek 到起手 x=130 处的时间
      //（内容区宽换算，落在区间内），再从其命中列起手。
      const startX = 130.0;
      final startAxis = bandGeometryOf(
        total: const Duration(minutes: 3),
        width: tester.getSize(find.byKey(const Key('track_band'))).width,
      ).axis;
      await engine.seek(startAxis.xToTime(startX));
      await tester.pumpAndSettle();
      final y = tester
          .getCenter(find.byKey(const Key('track_handle_strip_row')))
          .dy;
      final gesture = await tester.startGesture(Offset(startX, y));
      for (var i = 0; i < 9; i++) {
        await gesture.moveBy(const Offset(30, 0)); // 最终 ≈90s，区间外。
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(engine.position, greaterThan(const Duration(seconds: 40)));

      await gesture.up();
      await tester.pumpAndSettle();

      // 越界播放：区间外按播放从原地播放，不再被拉回 rangeStart，
      // 也不触发尾线循环提示。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      expect(engine.isPlaying, isTrue);
      expect(engine.position, greaterThan(const Duration(seconds: 40)));
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      await tester.tap(find.byKey(const Key('toolbar_play'))); // 暂停收尾。
      await tester.pumpAndSettle();
    });

    testWidgets('播放头在区间外按播放：从原地播放，不被拉回 rangeStart', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('toolbar_play'))); // 暂停打开自动播放。
      await tester.pumpAndSettle();
      await submitRange(tester, start: const Duration(seconds: 20));
      await submitRange(tester, end: const Duration(seconds: 40));

      // 头线左侧（10s）起播：原地播放，不被拉回 20s。
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      expect(engine.isPlaying, isTrue);
      expect(engine.position, lessThan(const Duration(seconds: 12)));
      await tester.tap(find.byKey(const Key('toolbar_play'))); // 暂停。
      await tester.pumpAndSettle();

      // 越尾线加固：无放行标记时在尾线右侧（50s）起播 → 按到尾
      // 语义钳回尾线（40s）并弹循环提示（自动越线不再直通片尾）。
      await engine.seek(const Duration(seconds: 50));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 40));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);
    });

    testWidgets('全屏进度手势拖出区间后松手原地续播', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();

      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await submitRange(tester, start: const Duration(seconds: 20));
      await submitRange(tester, end: const Duration(seconds: 40));
      // 空白单击经约 300ms 双击判定窗口后收起。
      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();

      // 从视频首播放后用全屏单指手势右拖约 +25s：落点越过尾(40s)。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pump();
      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(25, const Offset(20, 0)),
      );
      await tester.pumpAndSettle();

      // 越界播放：松手从落点原地续播，出界不再守卫拦截。
      expect(engine.position, greaterThan(const Duration(seconds: 40)));
      expect(engine.isPlaying, isTrue);
    });
  });

  group('首尾线拖动宿主接线', () {
    /// 轨道带时间轴（按当前带宽换算，经共享测试入口）。
    TimelineAxis bandAxis(WidgetTester tester, Duration total) =>
        bandGeometryOf(
          total: total,
          width: tester.getSize(find.byKey(const Key('track_band'))).width,
        ).axis;

    testWidgets('拖动首线经宿主写入时间线：边界变更且首 ≤ 尾钳制', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 先经「设为视频尾」把尾收到 40s，给钳制断言布局（拖动越过尾线）。
      await engine.seek(const Duration(seconds: 40));
      await tester.pump();
      await submitRange(tester, end: const Duration(seconds: 40));

      final axis = bandAxis(tester, total);
      final line = find.byKey(const Key('video_range_start_line'));
      // 整片视图首线贴屏边：从轨道手柄带手柄（外扩补偿后仍在带内）按下拖。
      final press = tester.getCenter(
        find.byKey(const Key('video_range_start_marker')),
      );
      final target = axis.timeToX(const Duration(seconds: 100));
      final gesture = await tester.startGesture(press);
      await tester.pump();
      final delta = (target - press.dx) / 2;
      await gesture.moveBy(Offset(delta, 0));
      await tester.pump();
      await gesture.moveBy(Offset(delta, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // 越过尾线 → 沿用「设为视频首」钳制语义（AnnotationTimeline.normalized
      // 归一化保证首 ≤ 尾）：首 = 尾 = 拖动目标 100s。
      expect(
        tester.getCenter(line).dx,
        closeTo(axis.timeToX(const Duration(seconds: 100)), 2),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_end_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 100)), 2),
      );
    });

    testWidgets('拖动尾线经宿主写入时间线：边界变更且尾 ≥ 首钳制', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 先经「设为视频首」把首批到 30s。
      await engine.seek(const Duration(seconds: 30));
      await tester.pump();
      await submitRange(tester, start: const Duration(seconds: 30));
      final axis = bandAxis(tester, total);
      final line = find.byKey(const Key('video_range_end_line'));
      final press = tester.getCenter(
        find.byKey(const Key('video_range_end_marker')),
      );
      final target = axis.timeToX(const Duration(seconds: 10));
      final gesture = await tester.startGesture(press);
      await tester.pump();
      final delta = (target - press.dx) / 2;
      await gesture.moveBy(Offset(delta, 0));
      await tester.pump();
      await gesture.moveBy(Offset(delta, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // 拖到首线左侧 → 沿用「设为视频尾」钳制语义（首 ≤ 尾归一化）：
      // 尾被抬到首 = 30s，首不动。
      expect(
        tester.getCenter(line).dx,
        closeTo(axis.timeToX(const Duration(seconds: 30)), 2),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_start_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 30)), 2),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_start_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 30)), 2),
      );
    });

    testWidgets('拖动首线：预览 seek 不改变播放位置，不收起控制层', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      // 预览线离开首线命中列（否则列内起手转预览线拖动）。
      await engine.seek(const Duration(seconds: 90));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();
      // 拖线起手前播放位置（自动播放中，非 0）：松手恢复目标 = 该定格点。
      final before = engine.position;

      final press = tester.getCenter(
        find.byKey(const Key('video_range_start_marker')),
      );
      final gesture = await tester.startGesture(press);
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      // 拖动永不收起：过双击判定窗口后控制层仍在。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();

      // 拖线实时预览 seek 存在，松手回到起手定格点续播——拖线本身
      // 不改变播放位置。
      expect(engine.seekCalls, isNotEmpty, reason: '拖线实时预览 seek');
      expect(engine.seekCalls.last, before, reason: '松手回预览线位置');
      // 续播从定格点继续（后续 pump 会推进位置，只断言不回退）。
      expect(engine.position, greaterThanOrEqualTo(before));
      expect(engine.isPlaying, isTrue, reason: '原在播松手从定格点续播');
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      await engine.pause(); // 清 ticker：测试收尾不留周期定时器。
    });
  });

  group('循环提示弹窗（FakeEngine 完成事件驱动）', () {
    testWidgets('播放到尾：左下角弹循环提示并显示「不循环」', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 3));
      await pumpPlayer(tester, engine: engine);

      // 播放到尾（completed 事件）→ 左下角出现循环提示。
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);
      expect(find.text('即将自动循环播放'), findsOneWidget);
      expect(find.text('不循环'), findsOneWidget);

      // 落位基准 = 画面矩形左下角（默认 800×600 逻辑视口；宽高比未知 →
      // 画面矩形 = 整屏），再按系统手势让路区（底 44 下限）把底边推出带外。
      final picture = videoPictureRect(
        screen: const Size(800, 600),
        systemTopInset: 0,
        videoAspectRatio: null,
      );
      final card = tester.getRect(find.byKey(const Key('loop_prompt')));
      expect(card.left, picture.left + 24);
      expect(card.bottom, 600 - kGestureYieldBottomMinPx);

      // 播放停在结尾，等待自动循环。
      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 3));
      // 播完即进入暂停态：中央播放指示按引擎真实状态显出来
      // （「播完」路径不再靠手动同步）。
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('延迟一个八拍后自动从头循环播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 3));
      await pumpPlayer(tester, engine: engine);

      await tester.pump(const Duration(seconds: 4)); // 播放到尾
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);
      expect(engine.isPlaying, isFalse);

      // 一个八拍（默认 120 BPM → 4s）后自动循环：从头重新播放、提示消失。
      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      expect(engine.isPlaying, isTrue);
      expect(engine.position, greaterThan(Duration.zero));
      expect(engine.position, lessThan(const Duration(seconds: 3)));
      // 自动循环起播同样随引擎边沿收口（「全片循环」路径）。
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });

    testWidgets('点击「不循环」停留于结尾，本次播放不再自动循环', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 3));
      await pumpPlayer(tester, engine: engine);

      await tester.pump(const Duration(seconds: 4)); // 播放到尾
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      await tester.tap(find.byKey(const Key('loop_dismiss_button')));
      await tester.pump();
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 3)); // 停留于结尾

      // 再过一个八拍：不自动循环。
      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 3));

      // 手动重新播放到尾：不再提示、不再自动循环。
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      await tester.pump();
      expect(engine.isPlaying, isTrue);
      await tester.pump(const Duration(seconds: 4)); // 再次到尾
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      await tester.pump(const Duration(seconds: 8));
      expect(engine.isPlaying, isFalse);
      expect(engine.position, const Duration(seconds: 3));
    });
  });

  group('离开播放器', () {
    testWidgets('返回后停止播放并恢复系统 UI', (tester) async {
      final engine = FakePlaybackEngine();
      final systemUi = FakeSystemUi();
      final navigatorKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            systemUiControllerProvider.overrideWithValue(systemUi),
            screenBrightnessControllerProvider.overrideWithValue(
              FakeScreenBrightnessController(),
            ),
            // 镜像接线后 PlayerPage 需读索引：内存索引种入匹配条目
            // （镜像 false、已询问 → 走历史应用路径，不弹询问）。
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(filePath: '/videos/a.mp4', mirrored: false),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          PlayerPage(source: Uri.file('/videos/a.mp4')),
                    ),
                  ),
                  child: const Text('打开播放器'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开播放器'));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue);
      expect(systemUi.enterCount, 1);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(engine.isPlaying, isFalse);
      expect(systemUi.restoreCount, 1);
    });
  });

  group('学习段激活与循环联动', () {
    testWidgets('点击学习段跳段首，播放到段尾帧级 seek 回段头', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      expect(engine.seekCalls, contains(const Duration(seconds: 10)));
      expect(
        engine.position,
        allOf(
          greaterThanOrEqualTo(const Duration(seconds: 10)),
          lessThan(const Duration(seconds: 11)),
        ),
      );

      await tester.pump(const Duration(seconds: 11));
      expect(
        engine.position,
        allOf(
          greaterThanOrEqualTo(const Duration(seconds: 10)),
          lessThan(const Duration(seconds: 12)),
        ),
      );
      expect(engine.seekCalls.last, const Duration(seconds: 10));
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
    });

    testWidgets('点学习段即起播：暂停态点段跳到段首并当场开始播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      // 布景：暂停态停在段首之前（旧口径下点段只 seek 不 play——暂停态
      // 引擎不因那次 seek 推进，画面与数拍都看不出任何变化）。
      await engine.pause();
      await engine.seek(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pump();
      await tester.pump();

      // 判据①：引擎处于播放态、位置在段首、循环范围 = 该段。
      expect(engine.isPlaying, isTrue, reason: '点学习段当场开始播放');
      expect(engine.seekCalls, contains(const Duration(seconds: 10)));
      expect(
        engine.position,
        allOf(
          greaterThanOrEqualTo(const Duration(seconds: 10)),
          lessThan(const Duration(seconds: 12)),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      final range = container.read(activeLoopRangeProvider)!;
      expect(range.start, const Duration(seconds: 10));
      expect(range.end, const Duration(seconds: 20));
      await engine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('激活起播被取消：在途 seek 落定后不得再翻回播放态', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await engine.pause();
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);

      // 拉长 seek 在途窗口：点段激活后又立刻点一次取消，取消发生在「跳段首」
      // 落定之前——在途的那次起播必须作废（结构保证，不靠时序纪律）。
      engine.seekLatency = const Duration(milliseconds: 500);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pump(); // 接线与入队跑起来（seek 已发往引擎、尚未落定）
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);
      expect(engine.seekCalls, contains(const Duration(seconds: 10)));
      expect(engine.isPlaying, isFalse, reason: 'seek 未落定，起播还没发生');

      await tester.pump(const Duration(milliseconds: 100)); // seek 仍在途
      await tester.tap(find.byKey(const Key('learning_segment_1'))); // 取消激活
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // 越过在途窗口
      await tester.pumpAndSettle();

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(engine.isPlaying, isFalse, reason: '被取消的激活不得在 seek 落定后起播');
    });

    testWidgets('local 文档可读（打开恢复已跑）时点学习段仍跳段首并段尾回卷', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(
        tester,
        engine,
        [const Duration(seconds: 10), const Duration(seconds: 20)],
        // 真机等价布景：local 文档可读 → 恢复路径真实执行（片段列表恢复、
        // 无激活片段——恢复写回为空）。缺陷布景下片段侧恢复静默标志被
        // 污染为真，点学习段的跳段首 seek 被会话级 OR 抑制。
        localDoc: {
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
        },
      );
      // 恢复路径确实跑过：片段列表已从盘上写回。
      expect(container.read(practiceClipsProvider), isNotEmpty);

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      expect(engine.seekCalls, contains(const Duration(seconds: 10)));

      // 段尾回卷照常：播放越过 20s 后 seek 回段首 10s。
      await tester.pump(const Duration(seconds: 11));
      expect(engine.seekCalls.last, const Duration(seconds: 10));
    });

    testWidgets('多段选中按合并范围连续循环（经直接布置的选中集合）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await tester.pumpAndSettle();
      // 点选只产生单元素集合；多段选中由长按圈选产生，此处直接布置。
      container.read(selectedLearningSegmentsProvider.notifier).state = const {
        0,
        1,
      };
      await tester.pumpAndSettle();
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1});
      expect(engine.seekCalls.last, Duration.zero);

      // 订阅循环遍数事件源（消费同一接缝）。
      final loopCounts = <int>[];
      final loopSubscription = container
          .read(learningSegmentLoopCountStreamProvider)
          .listen(loopCounts.add);
      addTearDown(loopSubscription.cancel);
      await tester.pump(const Duration(seconds: 21));
      expect(engine.seekCalls.last, Duration.zero);
      expect(engine.position, lessThan(const Duration(seconds: 2)));
      expect(loopCounts, const [1]);
    });

    testWidgets('步进倍率随激活段循环推进（每循环一圈 +1 遍，满 c 遍升档）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 2), // 段 0 = [0, 2s)，一圈 2s
      ]);

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await tester.pumpAndSettle();

      // 预览（段首）在激活段内 → 直接启用（模型级；UI 弹窗路径见控制层测试）。
      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      expect(engine.rate, 0.5);

      // FakeEngine tick = 100ms × rate：0.5 倍速下一圈 2s 需 4s 真实时间，
      // 3 圈 = 12s；推进 13s 越过第 3 圈（默认 c=3 → 升到第二档 0.6）。
      await tester.pump(const Duration(seconds: 13));
      expect(engine.rate, 0.6);
      expect(container.read(speedControlProvider).stepCycle, 3);
    });

    testWidgets('进度拖出激活范围取消激活并停用区间循环', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // 起播常态：激活即起播后位置流常开——越界清除正是在这个
      // 常态下判定的（循环层拉回 vs「清循环先于入队」的竞态在此被钉住）。
      expect(engine.isPlaying, isTrue);

      // 局部镜像轨叠最顶，整带矩形中心已落入学习段内容行（会被
      // 段体横滑识别吞掉）；横滑 scrub 改在空白行（节拍轨行）起手。
      final beatY = tester.getCenter(find.byKey(const Key('track_beat'))).dy;
      await stepDrag(
        tester,
        Offset(tester.getCenter(find.byKey(const Key('track_band'))).dx, beatY),
        List.filled(15, const Offset(20, 0)),
      );
      await tester.pump();

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(engine.position, greaterThan(const Duration(seconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.position, greaterThan(const Duration(seconds: 20)));
      expect(engine.seekCalls.last, isNot(const Duration(seconds: 10)));
      expect(engine.isPlaying, isTrue, reason: '越界撤激活不停画面');
    });

    testWidgets('循环前导：到段尾 seek 段首−4拍连续播放，倒数数字随浮层联动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      // 默认设置即 4 拍（BPM 120 → 前导 2s）；helper 关闭了前导，这里显式
      // 恢复默认验证前导路径。
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.none);
      container.read(prepBeatsProvider.notifier).setLoopLead(4);

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      expect(engine.seekCalls.last, const Duration(seconds: 10));
      // 收起控制层：数拍浮层在播放态显示。
      await singleTapShow(tester);

      // 播放到段尾（20s）：seek 到段首−4拍（8s）连续播放，画面不停住。
      await tester.pump(const Duration(seconds: 10));
      expect(engine.seekCalls.last, const Duration(seconds: 8));
      expect(engine.isPlaying, isTrue);

      // 前导区（8s–10s）：浮层显示倒数单数。
      expect(find.byKey(const Key('beat_count_leading')), findsOneWidget);
      expect(find.byKey(const Key('beat_count_practice')), findsNothing);

      // 进入段首（10s）：练习区正式数拍（两数）。
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byKey(const Key('beat_count_leading')), findsNothing);
    });

    testWidgets('浮层无「采样待补」提示行', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
      ]);
      await singleTapShow(tester);

      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byKey(const Key('beat_sound_sample_pending')), findsNothing);
      expect(find.textContaining('采样待补'), findsNothing);
    });

    testWidgets('退后台补齐 flush + 停流 + 播放态下推', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // 注入**真实渲染器 + 假原生 sink**：页面这一路要断言的正是渲染器真实
      // 实现里的 flush/停流（假渲染器只能证明「页面转发了调用」，证明不了
      // 停流真的发生）。
      final sink = FakeBeatAudioSink();
      final container = await openEditorWithSegmentLines(
        tester,
        engine,
        [const Duration(seconds: 10), const Duration(seconds: 20)],
        beatAudioRenderer: BeatAudioRenderer(
          sink: sink,
          loadAsset: syntheticSegmentLoader,
        ),
      );
      container.read(metronomeSoundEnabledProvider.notifier).set(true);
      await engine.play();
      await tester.pump(const Duration(seconds: 1));
      await tester.idle();
      expect(sink.startCount, greaterThan(0), reason: '播放中且开声 → 流已开');
      final flushesBefore = sink.flushCount;
      final startsBefore = sink.startCount;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // 停流由深模块的下一个推进拍收口（生命周期在模块
      // 内部，周期 top-up 30ms）——推过一个 top-up 周期。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.idle();

      // 退后台 = flush（未到点指令不补发）+ 停流 + 播放态下推（渲染器停沿），
      // 口径与暂停一致：三者齐备、顺序为「先 flush 后停流」（停流经模块
      // 收口，晚至一个 top-up 周期）。
      expect(sink.flushCount, greaterThan(flushesBefore), reason: '退后台 flush');
      expect(sink.calls, containsAllInOrder(['flush', 'stop']));
      expect(sink.stopCount, greaterThan(0), reason: '退后台停流（不空耗）');
      expect(sink.startCount, startsBefore, reason: '停流后不再开流');

      // 回前台按真实播放态重放：引擎仍可能在播，不重放会停在「流已停」。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      // 重开流由深模块的下一个推进拍收口——推过一个 top-up 周期。
      await tester.pump(const Duration(milliseconds: 50));
      await tester.idle();

      expect(sink.startCount, greaterThan(startsBefore), reason: '回前台重开流');
    });

    testWidgets('节拍呈现发声接线薄冒烟：位置产指令、跳变自判 flush、前导照常产出', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // 发声纪律已在对象装配缝直测（beat_presentation_test 等）；页面只留
      // 薄冒烟：位置流喂 onFrame、执行器 seam 出指令的接线正确性。
      final consumer = FakeBeatScheduleConsumer();
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ], beatScheduleConsumer: consumer);
      container.read(metronomeSoundEnabledProvider.notifier).set(true);
      await tester.pumpAndSettle();

      // position 驱动：位置推进产出排程指令（位置是唯一真相）。
      await tester.pump(const Duration(seconds: 1));
      await tester.idle();
      expect(consumer.commands, isNotEmpty, reason: 'position 驱动节拍呈现产指令');

      // 跳变自判：seek 前跳越过已排区 → 对象清原生未消费（宿主不声明）。
      final flushesBefore = consumer.flushCount;
      await engine.seek(const Duration(seconds: 15));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.idle();
      expect(consumer.flushCount, greaterThan(flushesBefore));

      // 前导：回跳到段首前的位置在锚点之前 → 前导拍照常产出。
      container.read(prepBeatsProvider.notifier).setLoopLead(4);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10)); // 播到段尾进入前导。
      await tester.idle();
      expect(engine.seekCalls.last, const Duration(seconds: 8));
      expect(consumer.commands, isNotEmpty, reason: '前导期拍声持续产出');
    });

    testWidgets('节拍素材 provider 变化经聚合订阅重驱：改动即收口发声', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final consumer = FakeBeatScheduleConsumer();
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ], beatScheduleConsumer: consumer);
      container.read(metronomeSoundEnabledProvider.notifier).set(true);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.idle();
      expect(consumer.commands, isNotEmpty, reason: '位置流驱动节拍呈现产指令');

      // 素材 provider 变化（开声转关）经 [beatPresentationFactsProvider] 的
      // 聚合订阅驱动重驱：应活转停即 flush + 停流。聚合订阅若断线，这里不会
      // 有任何收口动作（下一条位置报位才可能被读到）。
      final flushesBefore = consumer.flushCount;
      container.read(metronomeSoundEnabledProvider.notifier).set(false);
      await tester.pump();
      await tester.idle();
      expect(
        consumer.flushCount,
        greaterThan(flushesBefore),
        reason: '素材 provider 变化经聚合订阅重驱',
      );
    });

    testWidgets('lap 回跳后拍声与前导照常（位置跳变由节拍呈现自判）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final consumer = FakeBeatScheduleConsumer();
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ], beatScheduleConsumer: consumer);
      container.read(metronomeSoundEnabledProvider.notifier).set(true);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // helper 关闭了前导，这里显式启用 4 拍（BPM 120 → 前导 2s）。
      container.read(prepBeatsProvider.notifier).setLoopLead(4);

      await tester.pump(const Duration(seconds: 10)); // 到段尾：lap 回跳进前导。
      await tester.idle();
      expect(engine.seekCalls.last, const Duration(seconds: 8));
      final loop = container.read(playbackLoopLayerProvider);
      expect(loop.delayedLoopActive, isTrue);

      // 回跳 seek 补发的位置事件落前导起点：前导激活不被回声取消，
      // 保持到越过段首（进入 [10s, 20s)）才收。
      await tester.pump(const Duration(milliseconds: 500));
      expect(loop.delayedLoopActive, isTrue, reason: '回跳后激活不被 seek 回声取消');
      await tester.pump(const Duration(seconds: 2));
      expect(loop.delayedLoopActive, isFalse, reason: '进入段首前导收');
    });

    testWidgets('循环前导打断：前导期间拖出激活范围取消前导、不停住画面', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // helper 关闭了前导，这里显式启用默认 4 拍。
      container.read(prepBeatsProvider.notifier).setLoopLead(4);
      // 到段尾进入前导。
      await tester.pump(const Duration(seconds: 10));
      expect(engine.seekCalls.last, const Duration(seconds: 8));
      expect(engine.isPlaying, isTrue);

      // 前导期间拖出激活范围：激活清除 → 循环停用 → 前导取消，画面继续播。
      // 整带矩形中心已落入学习段内容行（段体横滑吞掉 scrub），
      // 横滑 scrub 改在空白行（节拍轨行）起手。
      final beatY = tester.getCenter(find.byKey(const Key('track_beat'))).dy;
      await stepDrag(
        tester,
        Offset(tester.getCenter(find.byKey(const Key('track_band'))).dx, beatY),
        List.filled(15, const Offset(20, 0)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(engine.isPlaying, isTrue, reason: '前导是播放态，打断不停住画面');
      // 取消后不再自动回段首。
      await tester.pump(const Duration(seconds: 3));
      expect(engine.seekCalls.last, isNot(const Duration(seconds: 10)));
    });

    testWidgets('全屏进度手势拖出激活范围同样取消激活', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // 空白单击经约 300ms 双击判定窗口后收起。
      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();

      await stepDrag(
        tester,
        const Offset(400, 300),
        List.filled(15, const Offset(20, 0)),
      );

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(engine.position, greaterThan(const Duration(seconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.position, greaterThan(const Duration(seconds: 20)));
    });

    testWidgets('激活段循环优先于视频尾循环提示', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 15),
      ]);
      // 右上 dock 覆盖学习段轨右端上半行，改点段体左下未遮挡区。
      final seg1 = tester.getRect(find.byKey(const Key('learning_segment_1')));
      await tester.tapAt(
        Offset(seg1.left + seg1.width * 0.25, seg1.top + seg1.height * 0.75),
      );
      await tester.pumpAndSettle();

      await tester.pump(const Duration(milliseconds: 15100));

      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      expect(engine.position, lessThan(const Duration(seconds: 16)));
      expect(engine.seekCalls.last, const Duration(seconds: 15));
    });

    testWidgets('浮层数拍内容随节拍显示/动画开关显隐；声音与开关互不绑定', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // 收起控制层：数拍浮层在播放态显示。
      await singleTapShow(tester);

      // 激活段内：总开关默认开，数拍数字与动画可见。
      await tester.pump(const Duration(seconds: 12));
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byType(MetronomeBeatAnimation), findsOneWidget);

      // 总开关关：数字与动画整体隐藏；声音开关不受影响。
      container.read(beatPromptEnabledProvider.notifier).set(false);
      await tester.pump();
      expect(find.byKey(const Key('beat_count_practice')), findsNothing);
      expect(find.byType(MetronomeBeatAnimation), findsNothing);

      expect(container.read(metronomeSoundEnabledProvider), isFalse);
      container.read(metronomeSoundEnabledProvider.notifier).set(true);
      // 总开关重新打开：数字与动画一起回来。
      container.read(beatPromptEnabledProvider.notifier).set(true);
      await tester.pump();
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byType(MetronomeBeatAnimation), findsOneWidget);
      expect(container.read(metronomeSoundEnabledProvider), isTrue);
    });

    testWidgets('数拍浮层与节拍动画跟八拍锚点更新（播放/暂停/步进同判）', (tester) async {
      // 观看态（播放态浮层）：注入就绪真实网格 + 八拍锚点 28（14s，半八拍
      // 落点），位置 14s → 段首（首线 0s）起按八拍点顺数 = 第 5 个八拍
      // （显示 ²1）；无锚点时 = 4｜5。播放、暂停、步进定格三种情形同判。
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(
        tester,
        uniformDownbeatBeatState(seconds: 30, anchors: const [28]),
      );

      String eightText() =>
          tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data!;
      String beatText() =>
          tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data!;
      String? groupText() {
        final finder = find.byKey(const Key('beat_count_group'));
        if (finder.evaluate().isEmpty) return null;
        return tester.widget<Text>(finder).data;
      }

      // 播放推进到 14s = 拍 28（八拍锚点所在强拍）。
      await tester.pump(const Duration(seconds: 14));
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(eightText(), '1', reason: '第 5 个八拍 → 四八拍循环回 1');
      expect(groupText(), '2', reason: '组上标 2（相对八拍 5 > 4）');
      expect(beatText(), '1', reason: '八拍点处拍号回 1（旧口径 4｜5）');

      // 暂停定格：同判（相位只由位置派生，无独立时钟状态）。
      engine.pause();
      await tester.pump();
      expect(eightText(), '1');
      expect(beatText(), '1');

      // 步进（seek + 定格）到半八拍区间内的下一拍：号不变、拍号顺数。
      await engine.seek(const Duration(milliseconds: 14500));
      await tester.pump();
      expect(eightText(), '1');
      expect(beatText(), '2');

      // 节拍动画同相位源：14.5s = 锚点（拍 28）后的第 1 拍 → 八拍窗口首拍 =
      // 拍 28、游标在栏内偏移 1 格（1/8；旧口径窗口 24 起会落在 5/8）。
      double cursorFraction() {
        final bar = tester.getRect(find.byKey(const Key('beat_anim_bar')));
        final cursor = tester.getRect(
          find.byKey(const Key('beat_anim_cursor')),
        );
        return (cursor.center.dx - bar.left) / bar.width;
      }

      expect(cursorFraction(), closeTo(0.125, 0.02), reason: '窗口首拍 = 锚点拍 28');

      // 换回无锚点网格：同位置显示今日口径（4｜5），游标也回到窗口 [24,32)
      // 的中段（证明浮层确实读相位源，动画与数字同判）。
      await injectBeatState(tester, uniformDownbeatBeatState(seconds: 30));
      await engine.seek(const Duration(seconds: 14));
      await tester.pump();
      expect(eightText(), '4');
      expect(groupText(), isNull, reason: '相对八拍 4 不加组上标');
      expect(beatText(), '5');
      expect(cursorFraction(), closeTo(0.5, 0.02), reason: '无锚点窗口偏移 4');
    });

    testWidgets('前导胶囊＝不延迟：段循环到段尾立即回段首（无前导 seek）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      // 前导是否生效 = 胶囊拍数（不延迟 = 0 = 关），无面板独立开关。
      container.read(prepBeatsProvider.notifier).setLoopLead(0);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();

      // 播放到段尾（20s）：立即回段首（10s），不 seek 前导起点（8s）。
      await tester.pump(const Duration(seconds: 10));
      expect(engine.seekCalls.last, const Duration(seconds: 10));
    });
  });

  group('长按拖动圈选与循环联动', () {
    Future<ProviderContainer> pumpPausedEditor(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await engine.pause();
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      return container;
    }

    testWidgets('拖动期间不 seek 不起播；松手提交跳选中首段段首并起播', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpPausedEditor(tester, engine);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await tester.pump(const Duration(milliseconds: 700)); // 长按成立
      await tester.pumpAndSettle();
      expect(engine.seekCalls, isEmpty, reason: '长按成立只就位范围，不 seek');
      expect(engine.isPlaying, isFalse, reason: '拖动期间不起播');

      await gesture.moveBy(const Offset(400, 0)); // 拖进段 2
      await tester.pumpAndSettle();
      expect(engine.seekCalls, isEmpty, reason: '横拖逐帧不 seek');
      expect(engine.isPlaying, isFalse);
      // 拖动只就位循环范围：选中首段段首 → 末段段尾。
      final draggingRange = container.read(activeLoopRangeProvider)!;
      expect(draggingRange.start, const Duration(seconds: 10));
      expect(draggingRange.end, const Duration(seconds: 30));

      await gesture.up(); // 松手提交
      await tester.pumpAndSettle();
      expect(
        engine.seekCalls,
        contains(const Duration(seconds: 10)),
        reason: '跳选中首段段首',
      );
      expect(engine.isPlaying, isTrue, reason: '松手起播');
      await engine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('在播中取消：回滚按下前选中与循环，不打断播放、不新增 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      // 按下前布景：选中段 0、循环在播（点段跳段首起播）。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue);
      final seekCountBeforeDrag = engine.seekCalls.length;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_2'))),
      );
      await tester.pump(const Duration(milliseconds: 700)); // 长按成立
      await tester.pumpAndSettle();
      await gesture.moveBy(const Offset(-400, 0)); // 拖向段 1
      await tester.pumpAndSettle();
      await gesture.cancel(); // 系统打断
      await tester.pumpAndSettle();

      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(
        engine.seekCalls.length,
        seekCountBeforeDrag,
        reason: '取消回滚静默写：不跳段首',
      );
      expect(engine.isPlaying, isTrue, reason: '回滚不打断播放');
      await engine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('手势取消：回到按下前（无选中），不 seek 不起播', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPausedEditor(tester, engine);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(const Offset(400, 0));
      await tester.pumpAndSettle();
      await gesture.cancel();
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(engine.seekCalls, isEmpty);
      expect(engine.isPlaying, isFalse);
    });
  });

  group('三指滑动跳转接线（真实分段线 + 首/尾边界回退）', () {
    /// 三指同步步进拖动（每步 moveBy + pump）。
    Future<void> stepDragThreeFingers(
      WidgetTester tester,
      Offset start,
      List<Offset> deltas,
    ) async {
      final g1 = await tester.startGesture(start);
      final g2 = await tester.startGesture(start + const Offset(0, 30));
      final g3 = await tester.startGesture(start + const Offset(0, 60));
      for (final delta in deltas) {
        await g1.moveBy(delta);
        await g2.moveBy(delta);
        await g3.moveBy(delta);
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pumpAndSettle();
    }

    /// 打开播放器并种入分段线时间线：首边界 5s、尾边界 2:50、
    /// 分段线 10s（未标记）/20s（标记）/40s（标记）。
    /// 进度停在 [currentPosition]（暂停态），
    /// seek 记录清空只看三指跳转产生的 seek。返回 ProviderContainer。
    Future<ProviderContainer> openWithTimeline(
      WidgetTester tester,
      FakePlaybackEngine engine, {
      required Duration currentPosition,
      FakeScreenBrightnessController? brightness,
      FakeSystemMediaVolumeController? volume,
    }) async {
      await pumpPlayer(
        tester,
        engine: engine,
        brightness: brightness,
        volume: volume,
      );
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(currentPosition);
      await tester.pumpAndSettle();
      engine.seekCalls.clear();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      // 经标注编辑模块命令播种区间与分段线。
      final editor = container.read(annotationEditorProvider);
      editor.submit(
        SetVideoRange(
          start: const Duration(seconds: 5),
          end: const Duration(minutes: 2, seconds: 50),
        ),
      );
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 40)));
      // 20s/40s 标记（选中索引后提交切换标记的标注编辑），10s 保持未标记。
      editor.submit(const ToggleSegmentFlag(index: 1));
      editor.submit(const ToggleSegmentFlag(index: 2));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('左滑跳到当前进度左侧最近的标记分段线', (tester) async {
      final engine = FakePlaybackEngine();
      await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 30),
      );

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(-20, 0)),
      );

      expect(engine.seekCalls.last, const Duration(seconds: 20));
    });

    testWidgets('右滑跳到当前进度右侧最近的标记分段线', (tester) async {
      final engine = FakePlaybackEngine();
      await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 30),
      );

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(20, 0)),
      );

      expect(engine.seekCalls.last, const Duration(seconds: 40));
    });

    testWidgets('左侧无标记线：左滑回退到首边界（视频首设置生效）', (tester) async {
      final engine = FakePlaybackEngine();
      await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 8),
      );

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(-20, 0)),
      );

      // 首边界 rangeStart=5s，而非视频原始起点 0。
      expect(engine.seekCalls.last, const Duration(seconds: 5));
    });

    testWidgets('右侧无标记线：右滑回退到尾边界（视频尾设置生效）', (tester) async {
      final engine = FakePlaybackEngine();
      await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 50),
      );

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(20, 0)),
      );

      // 尾边界 rangeEnd=2:50，而非视频原始时长 3:00。
      expect(engine.seekCalls.last, const Duration(minutes: 2, seconds: 50));
    });

    testWidgets('未标记分段线不是跳转目标：左滑跳过它回退首边界', (tester) async {
      final engine = FakePlaybackEngine();
      await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 15),
      );

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(-20, 0)),
      );

      // 左侧最近的 10s 未标记 → 对跳转隐形，方向上无标记线 → 回退首边界 5s。
      expect(engine.seekCalls.last, const Duration(seconds: 5));
    });

    testWidgets('单指横滑中途加指：不重开会话、灵敏度仍按起始单指（burst 锁定）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      final g1 = await tester.startGesture(const Offset(400, 300));
      // 单指右滑 3 帧 ×20px：scale 识别器 pan slop（36px）吞掉首帧，
      // 后 2 帧 ×20px ×50ms = +2s → 末目标 32s。
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(engine.seekCalls.last, const Duration(seconds: 32));

      // 中途加指（落在当前焦点处，避免加指帧的焦点半跳污染期望值）：
      // 会话不重开——灵敏度仍按 burst 起始单指计，基准不重取。
      final g2 = await tester.startGesture(const Offset(460, 300));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(20, 0));
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      // 双指段 6 个 update ×10px（焦点=中点，每指 move 各 +10px）×50ms
      // = +3s → 末目标 35s（若重开为双指会话则按 3× 灵敏度到 41s）。
      expect(engine.seekCalls.last, const Duration(seconds: 35));
      expect(engine.position, const Duration(seconds: 35));
    });

    testWidgets('三指触发跳转后先抬一指、余指继续移动：无新增 seek/音量/亮度动作（burst 锁定）', (
      tester,
    ) async {
      final engine = FakePlaybackEngine();
      final brightness = FakeScreenBrightnessController(initialBrightness: 0.5);
      final volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 30),
        brightness: brightness,
        volume: volume,
      );

      final start = const Offset(400, 200);
      final g1 = await tester.startGesture(start);
      final g2 = await tester.startGesture(start + const Offset(0, 30));
      final g3 = await tester.startGesture(start + const Offset(0, 60));
      // 三指左滑 60px ≥ 40px 阈值 → 一次性跳转到标记线 20s。
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(-20, 0));
        await g2.moveBy(const Offset(-20, 0));
        await g3.moveBy(const Offset(-20, 0));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(engine.seekCalls, hasLength(1));
      expect(engine.seekCalls.single, const Duration(seconds: 20));

      // 先抬一指（不同时松手），余下两指继续大幅横移 + 纵移。
      await g1.up();
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g2.moveBy(const Offset(-30, 15));
        await g3.moveBy(const Offset(-30, 15));
        await tester.pump();
      }
      // 全部抬起前：无新增 seek、无音量/亮度调整。
      expect(engine.seekCalls, hasLength(1), reason: 'burst 未结束不得再产生 seek');
      expect(volume.currentVolume, 0.5, reason: 'burst 未结束不得调音量');
      expect(brightness.setCalls, isEmpty, reason: 'burst 未结束不得调亮度');

      await g2.up();
      await g3.up();
      await tester.pumpAndSettle();
      expect(engine.seekCalls, hasLength(1));
      expect(engine.position, const Duration(seconds: 20));
    });

    testWidgets('三指跳转发生即记入引导判据闩', (tester) async {
      final engine = FakePlaybackEngine();
      final container = await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 30),
      );
      expect(
        container
            .read(guideSessionProvider)
            .criterionLatches
            .contains(HandsOnCriterion.threeFingerJumpPerformed),
        isFalse,
      );

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(-20, 0)),
      );

      expect(engine.seekCalls, hasLength(1), reason: '前置：三指跳转真的发生了');
      expect(
        container
            .read(guideSessionProvider)
            .criterionLatches
            .contains(HandsOnCriterion.threeFingerJumpPerformed),
        isTrue,
      );
    });

    testWidgets('组合根把收起动作挂进「进观看态」注入点：请求即收起控制层；观看态下幂等', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

      // 观看态（控制层未展开）请求：什么都不做。
      expect(container.read(playerSessionProvider).controlOpen, isFalse);
      container.read(guideEnterWatchingRequestProvider).request();
      await tester.pumpAndSettle();
      expect(container.read(playerSessionProvider).controlOpen, isFalse);

      // 编辑态（控制层展开）请求：收起控制层回观看态。
      await singleTapShow(tester);
      expect(container.read(playerSessionProvider).controlOpen, isTrue);
      container.read(guideEnterWatchingRequestProvider).request();
      await tester.pumpAndSettle();
      expect(container.read(playerSessionProvider).controlOpen, isFalse);
    });

    testWidgets('三指跳转只 seek：分段线不被新建/移动/删除', (tester) async {
      final engine = FakePlaybackEngine();
      final container = await openWithTimeline(
        tester,
        engine,
        currentPosition: const Duration(seconds: 30),
      );
      final before = container.read(annotationTimelineProvider);

      await stepDragThreeFingers(
        tester,
        const Offset(400, 200),
        List.filled(3, const Offset(-20, 0)),
      );

      expect(engine.seekCalls, hasLength(1));
      expect(container.read(annotationTimelineProvider), before);
    });
  });

  group('观看态气泡水平钳制（取代中心差断言）', () {
    testWidgets('胶囊贴右缘：气泡完整进屏、右缘留边、滑条可达', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);

      await tester.tap(find.byKey(const Key('speed_entry_button')));
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final capsule = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_entry_button')),
      );
      // 窄屏几何断言：胶囊右锚 → 居中必溢出 → 钳制后完整进屏。
      expectBubbleClampedOnScreen(bubble, screenWidth: 800);
      expect(
        bubbleGlobalRect(bubble).center.dy,
        lessThan(capsule.localToGlobal(capsule.size.center(Offset.zero)).dy),
        reason: '气泡在胶囊上方',
      );

      // 最右列竖滑条可达（钳制不裁掉最右内容）。
      expectHitReachable(
        tester.renderObject<RenderBox>(
          find.byKey(const Key('speed_rate_slider')),
        ),
      );
    });

    testWidgets('窄屏（竖屏 360 逻辑宽）真实流程：胶囊贴右缘气泡完整进屏、倍速栏可达', (tester) async {
      // 竖屏可用宽不足以并排 → 上下堆叠，气泡宽回到 300 上限，
      // 水平钳制后完整进屏（左右留边）。
      tester.view.physicalSize = const Size(
        720,
        1440,
      ); // 合成档 360.0×720.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);

      await tester.tap(find.byKey(const Key('speed_entry_button')));
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      expectBubbleClampedOnScreen(bubble, screenWidth: 360);
      final rate = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_column')),
      );
      final step = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_step_column')),
      );
      expect(
        step.localToGlobal(Offset.zero).dy,
        greaterThanOrEqualTo(
          rate.localToGlobal(Offset.zero).dy + rate.size.height - 0.5,
        ),
        reason: '竖屏上下堆叠：步进栏在倍速栏下方',
      );
      expectHitReachable(
        tester.renderObject<RenderBox>(
          find.byKey(const Key('speed_rate_slider')),
        ),
      );
    });

    testWidgets('观看态胶囊开出的即同一双栏气泡，可直接点预设行启用步进（范围外先三选一）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine, inMemoryPrivateJson: true);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

      // 观看态（控制层收起）胶囊点开双栏气泡：步进栏在、可点预设行。
      await tester.tap(find.byKey(const Key('speed_entry_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_rate_column')), findsOneWidget);
      expect(find.byKey(const Key('speed_step_column')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('speed_step_preset_builtin_first')),
      );
      await tester.pumpAndSettle();
      // 无分段线：范围外 → 应用级三选一弹窗（不需控制层展开）。
      expect(find.byKey(const Key('speed_step_scope_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('speed_step_scope_whole_video')));
      await tester.pumpAndSettle();

      expect(container.read(speedControlProvider).stepEnabled, isTrue);
      expect(engine.rate, 0.5, reason: '按预设首档起跑');
      expect(
        find.byKey(const Key('speed_bubble')),
        findsNothing,
        reason: '确认后收起气泡',
      );
      expect(
        find.byKey(const Key('control_layer_back')),
        findsNothing,
        reason: '全程控制层收起',
      );
    });

    testWidgets('观看态胶囊指示保持：图标 + 生效倍率 + 步进生效时「步进」徽章', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      Finder inPill(Finder matching) => find.descendant(
        of: find.byKey(const Key('speed_entry_button')),
        matching: matching,
      );

      expect(inPill(find.byIcon(Icons.speed)), findsOneWidget);
      expect(inPill(find.text('1x')), findsOneWidget);
      expect(inPill(find.text('步进')), findsNothing);

      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      await tester.pump();

      expect(inPill(find.byIcon(Icons.speed)), findsOneWidget);
      expect(inPill(find.text('0.5x')), findsOneWidget);
      expect(inPill(find.text('步进')), findsOneWidget);
    });
  });

  group('临时衔接段（FakeEngine）', () {
    /// 打开编辑态并种入 5/15/25s 三条分段线，返回 provider 容器。
    Future<ProviderContainer> openEditorWithLines(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      // 经标注编辑模块命令播种分段线。
      final editor = container.read(annotationEditorProvider);
      for (final position in const [
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 25),
      ]) {
        editor.submit(AddSegmentLine(at: position));
      }
      await tester.pumpAndSettle();
      return container;
    }

    /// 触发区点击线 1（15s，学习轨行纵带；x = 时间满宽换算）。
    Future<void> tapLine1LearningRow(WidgetTester tester) async {
      final rect = tester.getRect(find.byKey(const Key('track_band')));
      await tester.tapAt(
        Offset(
          rect.left + rect.width * 15 / 30,
          trackRowCenterY(tester, 'track_learning'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('点临时衔接段即起播：暂停态点段跳到段首并当场开始播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithLines(tester, engine);

      // 布景：暂停态停在临时段之前。
      await engine.pause();
      await engine.seek(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);

      await tapLine1LearningRow(tester);

      // 判据①：播放态 + 位置在段首 + 循环范围 = 该段。
      expect(engine.isPlaying, isTrue, reason: '点临时衔接段当场开始播放');
      final transition = container.read(transitionSegmentProvider)!;
      expect(engine.seekCalls, contains(transition.start));
      expect(engine.position, greaterThanOrEqualTo(transition.start));
      final range = container.read(activeLoopRangeProvider)!;
      expect(range.start, transition.start);
      expect(range.end, transition.end);
      await engine.pause();
      await tester.pumpAndSettle();
    });

    testWidgets('激活跳段首并起播并段内循环：enableLoop(前1八拍,后1八拍)+队首 seek+提示', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithLines(tester, engine);

      // 反转旧口径：旧实现在暂停态点段**只 seek 不 play**——
      // 引擎不因那次 seek 推进，观感等于点了没反应。故本用例先把引擎停住
      // 再点段，播放态断言才有判别力。
      await engine.pause();
      await engine.seek(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('transition_prompt')), findsNothing);
      await tapLine1LearningRow(tester);

      final transition = container.read(transitionSegmentProvider)!;
      expect(transition.start, const Duration(seconds: 12));
      expect(transition.end, const Duration(seconds: 19));
      // 激活即起播：暂停态点段当场开始播放。
      expect(engine.isPlaying, isTrue, reason: '激活即起播（旧「只 seek 不 play」口径反转）');
      // 跳到临时段首（复用真实段激活的 enableLoop + 队首 seek 接线）。
      // pumpAndSettle 期间提示浮层淡出的帧会推进 FakeEngine 播放，位置
      // 断言按「已入段、仍在段内」而非贴段首（seekCalls 证明起跳点）。
      expect(engine.seekCalls, contains(const Duration(seconds: 12)));
      expect(
        engine.position,
        allOf(
          greaterThanOrEqualTo(const Duration(seconds: 12)),
          lessThan(const Duration(seconds: 19)),
        ),
      );
      // 短提示浮层出现。
      expect(find.byKey(const Key('transition_prompt')), findsOneWidget);

      // 段内循环：播过 19s 被拉回前导起点 12s−4拍（10s，默认 4 拍前导），
      // 前导播完回到段内。
      await tester.pump(const Duration(seconds: 12));
      expect(
        engine.position,
        allOf(
          greaterThanOrEqualTo(const Duration(seconds: 10)),
          lessThan(const Duration(seconds: 19)),
        ),
        reason: '区间循环层把越出 19s 的进度拉回前导起点 10s',
      );
      expect(engine.seekCalls.last, const Duration(seconds: 10));
    });
  });

  group('全屏单指长按 2×', () {
    /// 在 [at] 按下并按住超过长按阈值（0.45s），返回进行中的手势以便中间
    /// 断言后手动 up/继续移动。
    Future<TestGesture> pressAndHold(WidgetTester tester, Offset at) async {
      final gesture = await tester.startGesture(at);
      await tester.pump(
        kLongPressDoubleSpeedTimeout + const Duration(milliseconds: 30),
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('在播长按满阈值 → 临时 2× + 「2 倍速」提示，松开恢复原值', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      expect(engine.isPlaying, isTrue);
      final center = tester.getCenter(find.byKey(const Key('player_surface')));

      final gesture = await pressAndHold(tester, center);
      // 生效：内核切 2.0 + 提示常显。
      expect(engine.rate, kLongPressDoubleSpeedRate);
      expect(find.byKey(const Key('double_speed_badge')), findsOneWidget);

      // 松开：恢复手势前倍速、提示消失。
      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.0);
      expect(find.byKey(const Key('double_speed_badge')), findsNothing);
      // 长按不属 tap → 不会误唤起控制层。
      expect(find.byKey(const Key('control_layer')), findsNothing);
    });

    testWidgets('恢复的是手势前手动倍速（非固定 1.0）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await engine.setRate(1.5); // 手势前手动 1.5
      await tester.pump();
      final center = tester.getCenter(find.byKey(const Key('player_surface')));

      final gesture = await pressAndHold(tester, center);
      expect(engine.rate, kLongPressDoubleSpeedRate);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.5);
    });

    testWidgets('生效期间移动手指不中断 2×、不触发 seek', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      final center = tester.getCenter(find.byKey(const Key('player_surface')));

      final gesture = await pressAndHold(tester, center);
      expect(engine.rate, kLongPressDoubleSpeedRate);

      // 阈值后大幅横向移动：本会话已被 2× 锁定 → 不 seek（scale 不再胜出）。
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      expect(engine.rate, kLongPressDoubleSpeedRate, reason: '移动不取消 2×');
      expect(engine.seekCalls, isEmpty, reason: '移动不触发 seek');
      expect(find.byKey(const Key('double_speed_badge')), findsOneWidget);
      // 全站黑底胶囊默认档尺寸不变。
      final speedBadge = tester.getSize(
        find.byKey(const Key('double_speed_badge')),
      );
      expect(speedBadge.width, closeTo(89, 0.05));
      expect(speedBadge.height, closeTo(40, 0.05));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.0);
    });

    testWidgets('暂停时长按满阈值不触发（无提示、倍速不变、松开无动作）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await engine.pause(); // 非播放态
      await tester.pump();
      final center = tester.getCenter(find.byKey(const Key('player_surface')));

      final gesture = await pressAndHold(tester, center);
      expect(find.byKey(const Key('double_speed_badge')), findsNothing);
      expect(engine.rate, 1.0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.0);
      expect(find.byKey(const Key('double_speed_badge')), findsNothing);
    });

    testWidgets('控制层（编辑态展开）内长按不触发 2×', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester); // 打开控制层
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      final center = tester.getCenter(find.byKey(const Key('player_surface')));

      final gesture = await pressAndHold(tester, center);
      expect(engine.rate, 1.0, reason: '控制层展开不识别长按 2×');
      expect(find.byKey(const Key('double_speed_badge')), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.0);
    });

    testWidgets('全屏态可交互控件（倍速入口胶囊）上长按不触发 2×', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      final pill = find.byKey(const Key('speed_entry_button'));
      expect(pill, findsOneWidget);
      final center = tester.getCenter(pill);

      final gesture = await pressAndHold(tester, center);
      expect(engine.rate, 1.0, reason: '落在交互控件上不触发 2×');
      expect(find.byKey(const Key('double_speed_badge')), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(engine.rate, 1.0);
    });

    testWidgets('双击暂停/播放不受长按识别器影响（回归）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      final surface = find.byKey(const Key('player_surface'));
      await doubleTap(tester, surface);
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse, reason: '双击暂停仍生效');

      await doubleTap(tester, surface);
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue, reason: '双击恢复播放仍生效');
    });
  });

  group('自动首尾工具与换视频复位', () {
    testWidgets('就绪态点击：一次写入节拍轨首末拍、单步入撤销、撤销还原整片区间', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_auto_seg_4')));
      await tester.pump();

      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(milliseconds: 500),
        reason: '首 = 第一拍 0.5s',
      );
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 2),
        reason: '尾 = 最后一拍 2.0s',
      );
      expect(container.read(annotationEditHistoryProvider).canUndo, isTrue);

      // 单步入撤销：一步还原整片区间（首尾同一提交）。
      container.read(annotationEditorProvider).undo();
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        Duration.zero,
      );
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        engine.duration,
      );
    });

    testWidgets('占位态置灰：点击不执行、弹「节拍分析中…」', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pump();
      expect(find.byKey(const Key('beat_analyzing_prompt')), findsOneWidget);
      expect(find.text('节拍分析中…'), findsOneWidget);
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        Duration.zero,
        reason: '置灰点击不执行',
      );
      await tester.pump(noticeTimingOf(NoticeId.beatAnalyzing).hold);
      await tester.pump();
      expect(find.byKey(const Key('beat_analyzing_prompt')), findsNothing);
    });

    testWidgets('异常态置灰：点击不执行、弹「无节拍数据」', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(tester, const BeatTrackState.error());
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pump();
      expect(find.byKey(const Key('beat_no_data_prompt')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_no_data_prompt')),
          matching: find.text('无节拍数据'),
        ),
        findsOneWidget,
        reason: '节拍轨异常态自带「无节拍数据」文案，此处限定提示浮层',
      );
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        engine.duration,
        reason: '置灰点击不执行',
      );
      await tester.pump(noticeTimingOf(NoticeId.beatNoData).hold);
      await tester.pump();
      expect(find.byKey(const Key('beat_no_data_prompt')), findsNothing);
    });

    testWidgets('初始化兜底复位：时长未就绪进编辑态前 resetForVideo 整片重建 + 清历史', (tester) async {
      // 引擎时长未就绪（timeline 停在零时长）时先产生一条可撤销编辑；
      // 唤出控制层的兜底复位应一次完成——整片时间线、历史清空。
      final engine = _LateDurationEngine();
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );
      // 零时长时间线上区间编辑为 no-op，用属性编辑制造一条可撤销历史。
      container
          .read(annotationEditorProvider)
          .submit(
            const SetSegmentMastery(
              order: 0,
              mastery: LearningMastery.mastered,
            ),
          );
      expect(container.read(annotationEditHistoryProvider).canUndo, isTrue);

      engine.durationReady = true;
      await singleTapShow(tester);
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).videoDuration,
        const Duration(minutes: 3),
        reason: '兜底复位以引擎时长重建整片时间线',
      );
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        Duration.zero,
      );
      expect(container.read(annotationEditHistoryProvider).canUndo, isFalse);
    });
  });

  group('数拍浮层宿主接线', () {
    // 自定义位置单击：浮层默认位在左上角，singleTapShow 只点画面中心。
    Future<void> tapAt(WidgetTester tester, Offset location) async {
      final gesture = await tester.startGesture(location);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
    }

    // 本组测试默认视口 800×600（横屏，视口高 600 → 默认位 y = 72）。
    const overlayPoint = Offset(80, 120);
    const outsidePoint = Offset(600, 400);

    /// 本组默认视口下浮层位所在格（姿态 = 视口宽高口径）。
    const overlayCell = OverlayPlacementCell.landscapeNormal;

    /// 本组默认视口（800×600）下未自定义位的默认偏移（贴左、视口高 12%）。
    const overlayDefaultTopLeft = Offset(
      0,
      600 * kDefaultOverlayOffsetHeightFactor,
    );

    // 浮层只在内容可见时存在——可见内容的编排 = 激活学习段 +
    // 收起控制层 + 播放位置就绪。
    Future<ProviderContainer> pumpVisibleOverlay(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // 收起控制层：数拍浮层在播放态完整交互。
      await singleTapShow(tester);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('内容可见：点选浮层进选中态、不唤出控制层', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpVisibleOverlay(tester, engine);

      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      await tapAt(tester, overlayPoint);

      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('control_layer')), findsNothing);
    });

    testWidgets('内容可见：选中态点浮层外退出选中态且不唤出控制层', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpVisibleOverlay(tester, engine);

      await tapAt(tester, overlayPoint);
      await tapAt(tester, outsidePoint);

      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(find.byKey(const Key('control_layer')), findsNothing);
    });

    testWidgets('未选中点浮层外仍唤出控制层（宿主原语义不变）', (tester) async {
      await pumpPlayer(tester, engine: FakePlaybackEngine());

      await tapAt(tester, outsidePoint);

      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('✕ 关闭浮层 = 总开关关 + 退出选中 + 中央提示自动消退', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);

      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('metronome_overlay_close')));
      await tester.pump();

      // 总开关同步为关 + 退出选中态 + 浮层消失。
      expect(container.read(beatPromptEnabledProvider), isFalse);
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(find.byType(MetronomeOverlay), findsNothing);

      // 中央纯文字提示出现（IgnorePointer 同构短暂提示），停留后自动消退。
      expect(
        find.byKey(const Key('beat_overlay_close_prompt')),
        findsOneWidget,
      );
      expect(find.text('节拍提示已关闭 · 编辑态顶栏可重新打开'), findsOneWidget);
      await tester.pump(noticeTimingOf(NoticeId.beatOverlayClose).hold);
      expect(find.byKey(const Key('beat_overlay_close_prompt')), findsNothing);

      // 面板再开（开关开）→ 浮层恢复。
      container.read(beatPromptEnabledProvider.notifier).set(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(container.read(beatPromptEnabledProvider), isTrue);
      expect(find.byType(MetronomeOverlay), findsOneWidget);
    });

    testWidgets('✕ 关闭浮层写进这支舞的记忆：'
        '浮层消失，记忆记录落 animation=false', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);

      // 先扳开总开关（一次用户表态，记忆记录成立且 animation=true）。
      container.read(beatPromptEnabledProvider.notifier).set(true);
      expect(container.read(beatPromptMemoryProvider)?.animation, isTrue);

      await tapAt(tester, overlayPoint);
      await tester.tap(find.byKey(const Key('metronome_overlay_close')));
      await tester.pump();

      // ✕ = 把总开关关掉，同样记进这支舞：记忆字段翻回 false。
      expect(find.byType(MetronomeOverlay), findsNothing);
      expect(container.read(beatPromptEnabledProvider), isFalse);
      expect(container.read(beatPromptMemoryProvider)?.animation, isFalse);
    });

    testWidgets('选中态「跳转节拍提示面板」角工具打开节拍提示面板', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpVisibleOverlay(tester, engine);

      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('metronome_overlay_beat_panel')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      // 观看态同一角标打开的是**同一个气泡**、第三列一致——
      // 「节拍矫正」菜单列（标题 + 两入口）在本气泡内，对齐控件本体不在。
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(find.text('节拍矫正'), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beat_align_group')), findsNothing);
    });

    testWidgets('竖屏 361.1dp 角工具打开同一个三段堆叠面板', (tester) async {
      // 真机竖屏基准 361.1×781.7dp（1264×2736 @3.5，唯一竖屏基准）。
      useNamedViewport(tester, ViewportTier.compact);

      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      // 进编辑面（竖屏点画面直接进，无方向前置）。
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester);
      // 播种两条分段线：不走 openEditorWithSegmentLines（其 pumpAndSettle
      // 在竖屏标题跑马灯下不收敛）。
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      await pumpPastMarquee(tester);
      // 激活第一段，再收起控制层 → 观看态浮层完整交互。
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await pumpPastMarquee(tester);
      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump(const Duration(seconds: 12));
      await pumpPastMarquee(tester);
      expect(tester.takeException(), isNull, reason: '竖屏基准下无布局溢出');

      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('metronome_overlay_beat_panel')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      // 同一面板、三段上下堆叠（x 对齐、y 递增），面板完整在屏内。
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      final anim = tester.getTopLeft(find.byKey(const Key('beat_anim_column')));
      final sound = tester.getTopLeft(
        find.byKey(const Key('beat_sound_column')),
      );
      final correction = tester.getTopLeft(
        find.byKey(const Key('beat_correction_column')),
      );
      expect(anim.dy, lessThan(sound.dy));
      expect(sound.dy, lessThan(correction.dy));
      expect(anim.dx, closeTo(sound.dx, 0.5));
      expect(sound.dx, closeTo(correction.dx, 0.5));
      expect(
        tester.getRect(find.byKey(const Key('beat_prompt_panel'))).right,
        lessThanOrEqualTo(1264 / 3.5),
      );
    });

    // 循环无关的可见浮层编排：激活段后再点一次取消激活（toggle 语义），
    // 消除区间循环对 seek/位置的干扰；浮层经「最近分段线」锚点仍可见
    // （放宽）。
    Future<ProviderContainer> pumpVisibleOverlayLoopFree(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      await singleTapShow(tester);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('选中态：浮层外起手两指外张仍缩放该浮层并钳上限 2.5', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );

      // 两指起手在浮层命中矩形之外（屏幕中部偏右），多帧外张到钳上限。
      final g1 = await tester.startGesture(const Offset(560, 300));
      final g2 = await tester.startGesture(const Offset(600, 300));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await g1.moveBy(const Offset(-50, 0));
        await g2.moveBy(const Offset(50, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      final placement = container.read(overlayPlacementProvider);
      expect(placement, isNotNull);
      expect(placement!.rectWidthFactor, 2.5);
    });

    testWidgets('选中态：两指横滑被浮层缩放会话收编，不触发视频 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      await tapAt(tester, overlayPoint);
      engine.seekCalls.clear();

      // 两指横滑（未选中态下该手势 = 双指高灵敏度 seek）。
      final g1 = await tester.startGesture(const Offset(360, 300));
      final g2 = await tester.startGesture(const Offset(440, 300));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(20, 0));
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      expect(engine.seekCalls, isEmpty);
      expect(engine.position, const Duration(seconds: 30));
    });

    testWidgets('选中态：一指浮层上一指出框的混区两指仍继续缩放（不进混区锁）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      await tapAt(tester, overlayPoint);

      // 一指落浮层上（默认位区域）、一指落在浮层外（混区起手），多帧外张。
      final g1 = await tester.startGesture(const Offset(80, 120));
      final g2 = await tester.startGesture(const Offset(200, 48));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await g1.moveBy(const Offset(-30, 0));
        await g2.moveBy(const Offset(160, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      // 混区起手不再闩锁抑制选中态缩放：系数仍被外张放大。
      final placement = container.read(overlayPlacementProvider);
      expect(placement, isNotNull);
      expect(placement!.rectWidthFactor, greaterThan(1.0));
    });

    testWidgets('未选中态（浮层可见）：双指横滑仍触发视频 seek（行为不变）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      final g1 = await tester.startGesture(const Offset(360, 300));
      final g2 = await tester.startGesture(const Offset(440, 300));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await g1.moveBy(const Offset(20, 0));
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      // 双指横滑仍走视频 seek（基准 30s 起向前进），未被浮层收编。
      expect(engine.seekCalls, isNotEmpty);
      expect(engine.seekCalls.last, greaterThan(const Duration(seconds: 30)));
    });

    // —— 选中态单指主体拖动平移 + 右下锁定钮 ——

    /// 选中态下（默认解锁）从 [start] 单指主体拖动 [frames] 帧（每帧
    /// [delta]），返回终态前一次 pump 已完成；用于断言拖动平移。
    Future<void> overlayBodyDrag(
      WidgetTester tester,
      Offset start, {
      int frames = 8,
      Offset delta = const Offset(20, 14),
    }) async {
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < frames; i++) {
        await gesture.moveBy(delta);
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('选中态：单指主体拖动 = 平移浮层、不触发视频 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      // 进入选中态默认解锁。
      final before =
          container.read(overlayPlacementProvider)?.offsetFor(overlayCell) ??
          Offset.zero;
      expect(before, Offset.zero);

      await overlayBodyDrag(tester, const Offset(110, 140));

      // 浮层被单指拖动平移（不再需要右下把手）。
      final after = container
          .read(overlayPlacementProvider)!
          .offsetFor(overlayCell)!;
      expect(after.dx, greaterThan(before.dx));
      expect(after.dy, greaterThan(before.dy));
      // 主体单指拖动不落视频语义（无 seek）。
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('锁定后：单指主体拖动穿透给视频 seek、双指缩放无效', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();
      // 先有一份自定义位（本测试视口 800×600 = 横屏，写横屏·普通格）：
      // 锁定/解锁的质量对比有非空基准。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            overlayPlacements(cell: overlayCell, offset: overlayDefaultTopLeft),
          );
      await tester.pumpAndSettle();

      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      // 点右下锁定钮 → 锁定。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);
      final beforePlacement = container.read(overlayPlacementProvider)!;

      // 锁定后单指主体拖动：浮层不动（位置不变）、手势穿透给视频 → seek。
      await overlayBodyDrag(tester, const Offset(110, 140));
      expect(
        container.read(overlayPlacementProvider),
        beforePlacement,
        reason: '锁定后单指主体拖动不应平移浮层',
      );
      expect(engine.seekCalls, isNotEmpty, reason: '锁定后单指应穿透给视频 seek');

      // 锁定后双指缩放无效：内合/外张都不改变缩放系数。
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();
      final g1 = await tester.startGesture(const Offset(140, 60));
      final g2 = await tester.startGesture(const Offset(180, 60));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await g1.moveBy(const Offset(-40, 0));
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      final after = container.read(overlayPlacementProvider)!;
      expect(after.rectWidthFactor, beforePlacement.rectWidthFactor);
      expect(after.pendulumScale, beforePlacement.pendulumScale);
    });

    testWidgets('锁定后角工具仍可操作：✕ 关闭浮层正常', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);

      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // 锁定态下角工具（✕ 关闭）仍可操作：关闭 = 退出选中态 + 总开关关。
      await tester.tap(find.byKey(const Key('metronome_overlay_close')));
      await tester.pump();
      expect(container.read(beatPromptEnabledProvider), isFalse);
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(find.byType(MetronomeOverlay), findsNothing);
    });

    testWidgets('锁定可再点解锁：恢复单指主体拖动平移', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      await tapAt(tester, overlayPoint);
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // 再点锁定钮解锁。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock_open), findsOneWidget);

      // 解锁恢复单指主体拖动平移。
      final before =
          container.read(overlayPlacementProvider)?.offsetFor(overlayCell) ??
          Offset.zero;
      await overlayBodyDrag(tester, const Offset(110, 140));
      final after = container
          .read(overlayPlacementProvider)!
          .offsetFor(overlayCell)!;
      expect(after.dx, greaterThan(before.dx));
      expect(after.dy, greaterThan(before.dy));
    });

    testWidgets('锁定后角工具仍可操作：重置位置回默认位', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      await tapAt(tester, overlayPoint);
      // 先（解锁态）单指主体拖动离开默认位。
      await overlayBodyDrag(tester, const Offset(110, 140));
      final dragged = container
          .read(overlayPlacementProvider)!
          .offsetFor(overlayCell);
      expect(dragged, isNotNull);
      expect(dragged, isNot(overlayDefaultTopLeft));
      // 锁定。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // 锁定态点右上重置角工具 → 位置回默认位（清自定义位；恢复仍可达）。
      await tester.tap(find.byKey(const Key('metronome_overlay_reset')));
      await tester.pump();
      // 清除即回落「无自定义位」（provider null = 文件无浮层位字段）。
      expect(
        container.read(overlayPlacementProvider)?.offsetFor(overlayCell),
        isNull,
      );
      expect(
        tester.getTopLeft(find.byType(MetronomeOverlay)),
        overlayDefaultTopLeft,
      );
    });

    testWidgets('锁定后节拍提示入口角工具仍可打开气泡', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpVisibleOverlay(tester, engine);
      await tapAt(tester, overlayPoint);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // 锁定态左下节拍提示入口角工具仍可操作 → 打开气泡。
      await tester.tap(
        find.byKey(const Key('metronome_overlay_beat_panel')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
    });

    testWidgets('解锁恢复双指缩放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpVisibleOverlayLoopFree(tester, engine);
      await engine.pause();
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();
      // 先有一份自定义位：缩放系数基准非空（本测试视口 800×600 = 横屏）。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            overlayPlacements(cell: overlayCell, offset: overlayDefaultTopLeft),
          );
      await tester.pumpAndSettle();

      await tapAt(tester, overlayPoint);
      // 锁定再解锁。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock_open), findsOneWidget);

      // 解锁后两指外张缩放该浮层 → 宽系数放大（锁定时缩放被禁）。
      final base = container.read(overlayPlacementProvider)!.rectWidthFactor;
      final g1 = await tester.startGesture(const Offset(140, 60));
      final g2 = await tester.startGesture(const Offset(180, 60));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await g1.moveBy(const Offset(-40, 0));
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      final after = container.read(overlayPlacementProvider)!;
      expect(after.rectWidthFactor, greaterThan(base));
    });
  });

  group('浮层存在性 = 内容可见性 + 控制层展开只读', () {
    Future<void> tapAt(WidgetTester tester, Offset location) async {
      final gesture = await tester.startGesture(location);
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
    }

    Future<ProviderContainer> pumpVisibleOverlay(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      await singleTapShow(tester);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      return container;
    }

    void expectNoGhost() {
      expect(find.byType(MetronomeOverlay), findsNothing);
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
    }

    testWidgets('空态一（节拍动画总开关关）：浮层不挂载、点按不命中、不可进选中态', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);

      container.read(beatPromptEnabledProvider.notifier).set(false);
      await tester.pump();
      expectNoGhost();

      // 空白处单击走宿主原语义（唤出控制层），不点出幽灵选中框。
      await tapAt(tester, const Offset(80, 120));
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('空态二（无激活段但有分段线）：浮层照常挂载并按段首数', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // 播放态、显示开、位置就绪，未激活任何学习段/临时衔接段；
      // 存在可锚点（分段线）→ 浮层显示。
      await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      // 收起控制层（openEditor 编排停在控制层展开态）。
      await singleTapShow(tester);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      expect(find.byType(MetronomeOverlay), findsOneWidget);
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
    });

    testWidgets('空态二（无可锚点）：位置早于首线 → 浮层不挂载', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      // 首线（rangeStart）推到 5s：当前位置（0s 附近）早于首线 → 无可锚点。
      await submitRange(tester, start: const Duration(seconds: 5));
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      expect(container.read(activeLoopRangeProvider), isNull);
      expectNoGhost();
      // 幽灵浮层防护在该分支同样生效：点按不命中、不进选中态，
      // 空白单击走宿主原语义（唤出控制层）。
      await tapAt(tester, const Offset(80, 120));
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('空态三（异常态）：浮层不挂载、点按不命中；恢复后回保存位置', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      // 记录就绪态原样（恢复可见时回到同一网格，与播放位置保持一致）。
      final readyState = container.read(beatTrackStateProvider);

      // 先单指拖动主体挪位（选中态单指拖动即平移；验证恢复可见后
      // 回到保存位置而非默认位）。
      await tapAt(tester, const Offset(80, 120));
      final gesture = await tester.startGesture(const Offset(80, 120));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(15, 12));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 异常态：浮层整体消失（含选中态）。
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      // 发布值经「异常 → onFrame 重发布 → 发布空值」一条链传播（比直读
      // 网格晚一拍），等它落定再断言浮层消失。
      await tester.pumpAndSettle();
      expectNoGhost();

      // 恢复可见（回到就绪态）：浮层回保存位置——挪位后的区域内点选命中
      // （默认位纵向 72 + 8 帧 × 12 = 168 起）。
      container.read(beatTrackStateProvider.notifier).replace(readyState);
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      await tapAt(tester, const Offset(180, 200));
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
    });

    testWidgets('空态四（位置未就绪）：浮层不挂载', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // 位置流不产任何值 = 位置未就绪（其余三条件全部满足）。
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
      ], positionReady: false);
      expect(container.read(playbackPositionProvider).value, isNull);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      expectNoGhost();
    });

    testWidgets('控制层展开/收起往返：展开只读常显（无选中框、不可点选），收起恢复交互', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpVisibleOverlay(tester, engine);

      // 先进选中态，再经浮层外单击唤出控制层（先退出选中态）。
      await tapAt(tester, const Offset(80, 120));
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      await tapAt(tester, const Offset(600, 400));
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      // 展开态：浮层内容仍绘制（只读），无选中框与角工具。
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(
        find.byKey(const Key('metronome_overlay_beat_panel')),
        findsNothing,
      );

      // 展开态点浮层区域：只读、不可进选中态。该点落在控制层画面区，
      // 单击同时收起控制层（画面区单击 = 收起）。
      await tapAt(tester, const Offset(80, 120));
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('control_layer')), findsNothing);

      // 收起控制层后恢复完整交互（已收起，直接点浮层区域）。
      await tapAt(tester, const Offset(80, 120));
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
    });
  });

  group('数拍浮层四格切格与重置', () {
    // 竖屏 600×1000 / 横屏 1000×600（转屏 = 视口宽高互换）。
    void setPortraitView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        1200,
        2000,
      ); // 合成档 600.0×1000.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    void setLandscapeView(WidgetTester tester) {
      tester.view.physicalSize = const Size(
        2000,
        1200,
      ); // 合成档 1000.0×600.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    Future<ProviderContainer> pumpVisibleOverlay(
      WidgetTester tester,
      FakePlaybackEngine engine, {
      Map<String, dynamic>? localDoc,
    }) async {
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ], localDoc: localDoc);
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();
      // 收起控制层（编辑面在场时点空白区收起；否则点画面唤出再收起）。
      if (find.byKey(const Key('control_layer_blank')).evaluate().isNotEmpty) {
        await tester.tap(find.byKey(const Key('control_layer_blank')));
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      } else {
        await singleTapShow(tester);
      }
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      return container;
    }

    Offset overlayTopLeft(WidgetTester tester) =>
        tester.getTopLeft(find.byType(MetronomeOverlay));

    /// 写一份四格容器到会话态（绕过 UI 的布景入口）。
    void seedPlacements(
      ProviderContainer container,
      Map<OverlayPlacementCell, Offset> offsets,
    ) => container
        .read(overlayPlacementProvider.notifier)
        .set(OverlayPlacements(offsets: offsets));

    // 默认位 = 贴左、纵向视口高 12%（竖屏高 1000 / 横屏高 600）。
    const portraitDefaultTopLeft = Offset(
      0,
      1000 * kDefaultOverlayOffsetHeightFactor,
    );
    const landscapeDefaultTopLeft = Offset(
      0,
      600 * kDefaultOverlayOffsetHeightFactor,
    );

    testWidgets('转屏切格：各自复原、跨格不串值、钳制不回写', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      seedPlacements(container, const {
        OverlayPlacementCell.portraitNormal: Offset(40, 80),
        OverlayPlacementCell.landscapeNormal: Offset(100, 120),
      });
      await tester.pumpAndSettle();

      // 竖屏：取竖屏·普通格。
      expect(overlayTopLeft(tester), const Offset(40, 80));

      // 转横屏（视口宽高互换）：取横屏·普通格。
      setLandscapeView(tester);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(100, 120));

      // 转回竖屏：原值原样恢复；容器里两格一字未改。
      setPortraitView(tester);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(40, 80));
      final placements = container.read(overlayPlacementProvider)!;
      expect(
        placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(40, 80),
      );
      expect(
        placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        const Offset(100, 120),
      );
    });

    testWidgets('存值越界：显示被钳在屏内、容器值不变、转回原姿态原样恢复', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      // 存值 (600,400)：竖屏 600×1000 里 dx 越界（maxDx 280），横屏
      // 1000×600 里合法——钳制只进生效面。
      seedPlacements(container, const {
        OverlayPlacementCell.portraitNormal: Offset(600, 400),
        OverlayPlacementCell.landscapeNormal: Offset(600, 400),
      });
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(280, 400));

      // 转横屏：同值在横屏里合法，原样落地。
      setLandscapeView(tester);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(600, 400));

      // 转回竖屏：存值一字未改，原样钳回屏内。
      setPortraitView(tester);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(280, 400));
      final placements = container.read(overlayPlacementProvider)!;
      expect(
        placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(600, 400),
      );
      expect(
        placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        const Offset(600, 400),
      );
    });

    testWidgets('切格后命中区与显示位置同源：刚转完屏一次点中浮层', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      seedPlacements(container, const {
        OverlayPlacementCell.portraitNormal: Offset(40, 80),
        OverlayPlacementCell.landscapeNormal: Offset(100, 120),
      });
      await tester.pumpAndSettle();
      setLandscapeView(tester);
      await tester.pumpAndSettle();

      // 显示位 = 横屏·普通格；一次点中即进选中态（命中区与显示同源）。
      final gesture = await tester.startGesture(const Offset(200, 180));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('metronome_overlay_selected'))),
        const Offset(100, 120),
      );
    });

    testWidgets('选中态与右下锁定钮跨切格保持', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      seedPlacements(container, const {
        OverlayPlacementCell.portraitNormal: Offset(40, 80),
        OverlayPlacementCell.landscapeNormal: Offset(100, 120),
      });
      await tester.pumpAndSettle();

      // 选中并锁定。
      final select = await tester.startGesture(const Offset(120, 140));
      await select.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // 转屏切格：选中框与锁定态都保持。
      setLandscapeView(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const Key('metronome_overlay_selected'))),
        const Offset(100, 120),
      );
    });

    testWidgets('开关对比切格：观看取普通格、对比取对比格，来回各自复原', (tester) async {
      setLandscapeView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      seedPlacements(container, const {
        OverlayPlacementCell.landscapeNormal: Offset(10, 20),
        OverlayPlacementCell.landscapeCompare: Offset(300, 200),
      });
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(10, 20));

      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(300, 200));

      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.watching);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(10, 20));
    });

    testWidgets('展开或收起控制层不改变浮层位置（只有对比会话进出切格）', (tester) async {
      setLandscapeView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(tester, engine);
      seedPlacements(container, const {
        OverlayPlacementCell.landscapeNormal: Offset(10, 20),
        OverlayPlacementCell.landscapeCompare: Offset(300, 200),
      });
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(10, 20));

      // 展开控制层（编辑态仍为普通格）。
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      expect(overlayTopLeft(tester), const Offset(10, 20));

      // 收起控制层。
      container.read(playerSessionProvider.notifier).collapse();
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(10, 20));
    });

    testWidgets('转屏与开关对比本身不产生任何落盘写入（钳制不回写）', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(
        tester,
        engine,
        localDoc: {
          'version': 3,
          'prefs': {
            'overlay': {'dx': 40.0, 'dy': 80.0},
          },
        },
      );
      // 旧文件（只有 dx/dy）= 竖屏·普通已自定义，恢复读取不改取值。
      expect(overlayTopLeft(tester), const Offset(40, 80));
      final storage = container.read(
        videoDocumentStorageProvider('vid-a'),
      ) as InMemoryVideoDocumentStorage;
      final before = storage.localSnapshot['prefs']['overlay'];
      // 节拍提示记忆随舞起，装景用的总开关置开
      // 是一次记忆变更、经「变更即存」把 prefs 整段 patch 成绝对终值：dx/dy
      // 原样保留、缺席系数按默认补齐。转屏与进/出对比此后不再产生任何写入
      // （钳制不回写）。
      expect(before, {
        'dx': 40.0,
        'dy': 80.0,
        'rectWidthFactor': 1.0,
        'pendulumScale': 1.0,
      });

      // 转横屏 → 横屏·普通格未自定义（默认位）；再进/出对比态。
      setLandscapeView(tester);
      await tester.pumpAndSettle();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.watching);
      await tester.pumpAndSettle();
      // 越过去抖窗口与写链。
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(storage.localSnapshot['prefs']['overlay'], before);
    });

    testWidgets('无自定义位的新文件：转屏与开关对比不写出 overlay 段', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(
        tester,
        engine,
        localDoc: {'version': 3, 'prefs': <String, dynamic>{}},
      );
      // 文件无浮层位字段 → 四格全未自定义 → 默认位（贴左、视口高 12%）。
      expect(overlayTopLeft(tester), portraitDefaultTopLeft);
      final storage = container.read(
        videoDocumentStorageProvider('vid-a'),
      ) as InMemoryVideoDocumentStorage;
      expect(
        (storage.localSnapshot['prefs'] as Map).containsKey('overlay'),
        isFalse,
      );

      setLandscapeView(tester);
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), landscapeDefaultTopLeft);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.watching);
      await tester.pumpAndSettle();
      // 越过去抖窗口与写链。
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // 切格/转屏不写出任何 overlay 键（未自定义与「无字段」同值）。
      expect(
        (storage.localSnapshot['prefs'] as Map).containsKey('overlay'),
        isFalse,
      );
    });

    testWidgets('设备转横屏后浮层落在横屏·普通格', (tester) async {
      setPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final systemUi = FakeSystemUi();
      await pumpPlayer(tester, engine: engine, systemUi: systemUi);
      await singleTapShow(tester);
      await pumpPastMarquee(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      seedPlacements(container, const {
        OverlayPlacementCell.portraitNormal: Offset(40, 80),
        OverlayPlacementCell.landscapeNormal: Offset(100, 120),
        OverlayPlacementCell.landscapeCompare: Offset(300, 200),
      });
      await pumpPastMarquee(tester);

      // 设备转到横屏：浮层落横屏·普通格（不是对比格）。
      setLandscapeView(tester);
      await pumpPastMarquee(tester);
      expect(overlayTopLeft(tester), const Offset(100, 120));
    });

    testWidgets('重置只清当前格 + 两系数回 1.0：另三格不动、文件里当前格两键消失', (tester) async {
      setLandscapeView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(
        tester,
        engine,
        localDoc: {'version': 3, 'prefs': <String, dynamic>{}},
      );
      // 四格各有自定义位 + 两个系数都非默认（当前格 = 横屏·普通）。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {
                OverlayPlacementCell.portraitNormal: Offset(10, 20),
                OverlayPlacementCell.landscapeNormal: Offset(40, 80),
                OverlayPlacementCell.portraitCompare: Offset(50, 60),
                OverlayPlacementCell.landscapeCompare: Offset(70, 90),
              },
              rectWidthFactor: 2.0,
              pendulumScale: 0.75,
            ),
          );
      await tester.pumpAndSettle();
      expect(overlayTopLeft(tester), const Offset(40, 80));

      // 选中浮层（点其当前显示位内部）。
      final select = await tester.startGesture(const Offset(120, 140));
      await select.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );

      final storage = container.read(
        videoDocumentStorageProvider('vid-a'),
      ) as InMemoryVideoDocumentStorage;
      // 先让布景那次写入收口。
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect((storage.localSnapshot['prefs'] as Map)['overlay'], {
        'dx': 10.0,
        'dy': 20.0,
        'landscapeDx': 40.0,
        'landscapeDy': 80.0,
        'compareDx': 50.0,
        'compareDy': 60.0,
        'landscapeCompareDx': 70.0,
        'landscapeCompareDy': 90.0,
        'rectWidthFactor': 2.0,
        'pendulumScale': 0.75,
      });

      // 右上角重置钮：只清当前格。
      await tester.tap(find.byKey(const Key('metronome_overlay_reset')));
      await tester.pump();

      // 会话态：当前格回未自定义、生效位回默认位；另三格与两系数口径。
      final placements = container.read(overlayPlacementProvider)!;
      expect(
        placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        isNull,
      );
      expect(
        placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(10, 20),
      );
      expect(
        placements.offsetFor(OverlayPlacementCell.portraitCompare),
        const Offset(50, 60),
      );
      expect(
        placements.offsetFor(OverlayPlacementCell.landscapeCompare),
        const Offset(70, 90),
      );
      expect(placements.rectWidthFactor, 1.0);
      expect(placements.pendulumScale, 1.0);
      expect(overlayTopLeft(tester), landscapeDefaultTopLeft);

      // 去抖窗口内尚未落盘（与既有落盘路径同一去抖）。
      expect(
        (storage.localSnapshot['prefs'] as Map)['overlay'],
        containsPair('landscapeDx', 40.0),
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final overlay = (storage.localSnapshot['prefs'] as Map)['overlay'] as Map;
      // 当前格两个键都消失；另三格两键一字不动；两系数回 1.0。
      expect(overlay.containsKey('landscapeDx'), isFalse);
      expect(overlay.containsKey('landscapeDy'), isFalse);
      expect(overlay['dx'], 10.0);
      expect(overlay['dy'], 20.0);
      expect(overlay['compareDx'], 50.0);
      expect(overlay['compareDy'], 60.0);
      expect(overlay['landscapeCompareDx'], 70.0);
      expect(overlay['landscapeCompareDy'], 90.0);
      expect(overlay['rectWidthFactor'], 1.0);
      expect(overlay['pendulumScale'], 1.0);
    });

    testWidgets('重置清掉唯一自定义格：文件里 overlay 段整体消失、旧键不残留', (tester) async {
      setLandscapeView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpVisibleOverlay(
        tester,
        engine,
        localDoc: {
          'version': 3,
          'prefs': {
            'overlay': {'landscapeDx': 40.0, 'landscapeDy': 80.0},
          },
        },
      );
      expect(overlayTopLeft(tester), const Offset(40, 80));

      // 选中并重置当前（也是唯一）自定义格。
      final select = await tester.startGesture(const Offset(120, 140));
      await select.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      await tester.tap(find.byKey(const Key('metronome_overlay_reset')));
      await tester.pump();

      final storage = container.read(
        videoDocumentStorageProvider('vid-a'),
      ) as InMemoryVideoDocumentStorage;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // 唯一自定义格被清 = 四格全未自定义：overlay 段整体消失（承诺性形状），
      // 该格两个旧键不得残留。
      expect(
        (storage.localSnapshot['prefs'] as Map).containsKey('overlay'),
        isFalse,
        reason: '唯一自定义格被清后 overlay 段整体消失，旧键不得残留',
      );
      expect(overlayTopLeft(tester), landscapeDefaultTopLeft);
    });
  });

  group('无激活段锚点链（无激活学习段也显示数拍）', () {
    /// 打开播放页：两条分段线（10s/20s）、无激活段、有界就绪均匀真实网格
    /// （末拍 24s、拍距 0.5s，与占位网格同几何）、控制层已收起。
    Future<ProviderContainer> pumpNoActivation(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      final container = await openEditorWithSegmentLines(tester, engine, [
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      // 注入有界就绪网格（末拍 24s < 视频尾 30s）：验证超出网格末拍不显示。
      await injectBeatState(tester, uniformReadyBeatState(seconds: 24));
      await singleTapShow(tester);
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('位置在第二段内：数字与动画同显，从 20s 段首 1｜1 顺数', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpNoActivation(tester, engine);

      // 位置 21s：锚点 = 20s 分段线，拍差 2 → 1｜3。
      await engine.seek(const Duration(seconds: 21));
      await tester.pumpAndSettle();

      expect(find.byType(MetronomeOverlay), findsOneWidget);
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byType(MetronomeBeatAnimation), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '3',
      );
    });

    testWidgets('拖到不同段：数字从各自段首重数（锚对齐八拍大线）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpNoActivation(tester, engine);

      // 位置 12s：分段线 10s 不落八拍大线（网格八拍大线 0/4/8/12/16s——10s
      // 是四拍中线、占位期插入的分段线不吸附）→ **锚归到其后最近的大线
      // 12s**（接线：锚点对齐网格八拍大线）→ 恰在大线上恒 1｜1。
      await engine.seek(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '1',
      );

      // 位置 11s（10s 分段线之后、对齐后的大线 12s 之前）：锚在其后 → 按
      // 「第 0 个八拍顺数」呈现（距锚 2 拍 → 0|7），与矩形动画当前格同号。
      await engine.seek(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_count_leading')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '0',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '7',
      );

      // 位置 5s（早于全部分段线）：锚点 = 首线（0s，本身即八拍点 → 恒等）
      // → 1｜1 起顺数，12s… 5s = 拍 10，8s（拍 8）处号进位 → 2｜3。
      await engine.seek(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '2',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '3',
      );
    });

    testWidgets('位置恰在分段线上 → 该线为新段段首，从 1｜1 重数', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpNoActivation(tester, engine);

      await engine.seek(const Duration(seconds: 20));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '1',
      );
    });

    testWidgets('位置超出网格末拍 → 浮层不挂载；回到范围内恢复且回保存位置', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpNoActivation(tester, engine);

      // 恢复可见后回到 per-video 保存位置/尺寸：改一次 placement（本测试
      // 默认视口 800×600 = 横屏，写入横屏·普通格）。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            overlayPlacements(
              cell: OverlayPlacementCell.landscapeNormal,
              offset: const Offset(40, 60),
              rectWidthFactor: 2,
            ),
          );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byType(MetronomeOverlay)),
        const Offset(40, 60),
      );

      // 末拍 24s 之后（26s > 末拍，仍在视频时长内）→ 不挂载。
      await engine.seek(const Duration(seconds: 26));
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeOverlay), findsNothing);

      // 回到范围内：浮层恢复，且回到保存位置。
      await engine.seek(const Duration(seconds: 22));
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(MetronomeOverlay)),
        const Offset(40, 60),
      );
    });
  });

  group('临时段激活即显（FakeEngine）', () {
    /// 打开编辑态并种入 5/15/25s 三条分段线，返回 provider 容器。
    Future<ProviderContainer> openEditorWithLines(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      final editor = container.read(annotationEditorProvider);
      for (final position in const [
        Duration(seconds: 5),
        Duration(seconds: 15),
        Duration(seconds: 25),
      ]) {
        editor.submit(AddSegmentLine(at: position));
      }
      await tester.pumpAndSettle();
      return container;
    }

    /// 触发区点击线 1（15s，学习轨行纵带；x = 时间满宽换算）。
    Future<void> tapLine1LearningRow(WidgetTester tester) async {
      final rect = tester.getRect(find.byKey(const Key('track_band')));
      await tester.tapAt(
        Offset(
          rect.left + rect.width * 15 / 30,
          trackRowCenterY(tester, 'track_learning'),
        ),
      );
      await tester.pump();
    }

    void expectCount1Of1(WidgetTester tester) {
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byKey(const Key('beat_count_leading')), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '1',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '1',
      );
    }

    testWidgets('激活临时段即 1｜1、不闪 0|8；起播后复位暂停也不冻结', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithLines(tester, engine);

      // 停在临时段段首之前（桥接窗口：旧位置 < 新段首）。
      await engine.pause();
      // 位置先停在 8s（早于 15s 线的临时段段首）。
      await engine.seek(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      await tapLine1LearningRow(tester);
      final segmentStart = container.read(transitionSegmentProvider)!.start;
      expect(segmentStart, greaterThan(const Duration(seconds: 8)));

      // 激活即起播：本用例布景要的是「无新位置事件」的暂停态，
      // 故起播落定后复位到暂停（起播本身由专测覆盖）。顺序：
      // 先让 seek 落定 + 起播跑完，再暂停，否则复位会被在途的起播盖掉。
      await tester.pumpAndSettle();
      await engine.pause();
      await tester.pumpAndSettle();

      // 收起控制层：数拍浮层在播放态显示。
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      // 激活瞬间即 1｜1（seek 落定后的真实位置），不闪 0|8 前导。
      expectCount1Of1(tester);
      // 暂停态无新位置事件也保持 1｜1（不冻结在旧值）。
      await tester.pump(const Duration(seconds: 1));
      expectCount1Of1(tester);
    });

    testWidgets('播放中激活临时段：数字立即 1｜1，不闪 0|8', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await openEditorWithLines(tester, engine);

      // 播放中位置早于临时段段首（约 0.2s 处）。
      await engine.seek(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      await tapLine1LearningRow(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      expectCount1Of1(tester);
    });

    testWidgets('桥接清除后段内连续顺数（跨触发线不重数）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await openEditorWithLines(tester, engine);

      await engine.pause();
      await engine.seek(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      await tapLine1LearningRow(tester);
      await singleTapShow(tester);
      await tester.pumpAndSettle();
      expectCount1Of1(tester);

      // 段内推进到触发线（15s）之后：跨线连续顺数、不重数（16s = 段首 +8
      // 拍 → 2｜1 前一拍 15.5s = 1｜8，这里取 17s = 10 拍差 → 2｜3）。
      await engine.seek(const Duration(seconds: 17));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_eight'))).data,
        '2',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('beat_count_beat'))).data,
        '3',
      );
    });
  });

  test('数拍派生位置不随音画同步 Δ 平移（±1000ms 两端与中间值同刻）', () async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        avSyncDelaysAutoRestoreProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);
    await engine.open(Uri.file('/videos/a.mp4'));
    await engine.pause();
    container.listen(playbackPositionProvider, (_, _) {});
    container.listen(avSyncProvider, (_, _) {});
    await engine.seek(const Duration(seconds: 8));
    await pumpEventQueue();

    final base = container.read(beatCountPositionProvider);
    expect(base, const Duration(seconds: 8));

    Duration countAt(int delayMs) {
      container.read(avSyncProvider.notifier).adopt(delayMs);
      return container.read(beatCountPositionProvider)!;
    }

    // 任何 Δ（含两端）下派生位置与节拍轨刻度（原始位置流）同刻。
    expect(countAt(1000), base);
    expect(countAt(-1000), base);
    expect(countAt(370), base);
    expect(countAt(0), base);
  });

  test('FakeEngine 暂停态 seek 后仍补发位置事件（语义基准）', () async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    await engine.open(Uri.file('/videos/a.mp4'));
    final events = <Duration>[];
    final sub = engine.positionStream.listen(events.add);
    await engine.pause();
    await engine.seek(const Duration(seconds: 7));
    await Future<void>.delayed(Duration.zero);
    expect(events, contains(const Duration(seconds: 7)));
    await sub.cancel();
  });
}

/// 打开即抛错的测试引擎（覆盖 FakePlaybackEngine 的 open 行为）。
class _ThrowingOpenEngine extends FakePlaybackEngine {
  @override
  Future<void> open(Uri source, {bool play = false}) async {
    throw StateError('模拟打开失败');
  }
}

/// 打开可延迟落定的引擎：打开在途时可观察「中央播放指示是否
/// 提前挂出」——那一帧引擎 isPlaying=false，但语义是「还没打开」。
class _SlowOpenEngine extends FakePlaybackEngine {
  final Completer<void> _openGate = Completer<void>();

  @override
  Future<void> open(Uri source, {bool play = false}) async {
    await _openGate.future;
    await super.open(source, play: play);
  }

  void completeOpen() => _openGate.complete();
}

/// 时长可延迟就绪的测试引擎：[durationReady] 置真前引擎
/// 观测不到时长（模拟打开初期 metadata 未到），置真后返回真实时长。
class _LateDurationEngine extends FakePlaybackEngine {
  _LateDurationEngine() : super(duration: const Duration(minutes: 3));

  bool durationReady = false;

  @override
  Duration? get duration => durationReady ? super.duration : null;
}

/// 时长未知的测试引擎（覆盖 duration getter 为 null——时长未解析/打开失败
/// 场景；内部钳制仍用父类 3 分钟假时长，拖动 seek 不越界）。
class _DurationlessEngine extends FakePlaybackEngine {
  _DurationlessEngine() : super(duration: const Duration(minutes: 3));

  @override
  Duration? get duration => null;
}

/// 挂起公开标记文件读：建立序列在文档读上不落定，把打开会话钉在「装载未完成」
/// ——门的存续窗口在测试里可控；[release] 即装载落定。
///
/// 打开一支舞命中条目后不读视频内容，故可挂起的环节从「摘要」换成「文档读」
/// （挂起摘要已不再能拖住装载）。
class _GatedMarkersStorage extends InMemoryVideoDocumentStorage {
  final Completer<void> _gate = Completer<void>();
  bool _passed = false;

  Future<void> _awaitGate() async {
    if (_passed) return;
    await _gate.future;
    _passed = true;
  }

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() async {
    await _awaitGate();
    return super.loadMarkersOrNull();
  }

  @override
  Future<Map<String, dynamic>> loadMarkers() async {
    await _awaitGate();
    return super.loadMarkers();
  }

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}
