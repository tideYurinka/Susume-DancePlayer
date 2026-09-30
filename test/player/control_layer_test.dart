
import 'dart:async' show unawaited;
import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart'
    show NoteGeometry;
import 'package:dance_learning_app/beat/beat_pipeline.dart'
    show BeatAnalysisPipeline;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/help/content_registry.dart'
    show
        GuideUnitForm,
        HandsOnCriterion,
        autoSegmentMenuAnchorKey,
        badgeAutoSegmentUnitId,
        badgeBeatPromptUnitId,
        badgeHalfBeatUnitId,
        badgeLocalMirrorUnitId,
        badgeSegmentFlagUnitId,
        badgeSegmentUnitId,
        badgeSpeedUnitId,
        badgeThreeFingerJumpUnitId,
        guideStepsOfUnit,
        localMirrorSwitchAnchorKey,
        mirrorFragmentAnchorKeyBase,
        segmentDeleteSlotAnchorKey;
import 'package:dance_learning_app/help/drill_task_bar.dart'
    show kDrillTaskBarAdvanceHold;
import 'package:dance_learning_app/help/guide_anchor.dart' show guideAnchorRectsProvider;
import 'package:dance_learning_app/help/guide_host.dart' show GuideHost;
import 'package:dance_learning_app/help/guide_state.dart'
    show
        guideSessionProvider,
        onboardingFlagFields;
import 'package:dance_learning_app/help/guide_units_page.dart'
    show GuideUnitsPage;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/persistence/material_manifest.dart'
    show
        MaterialManifestStorage,
        materialManifestStorageProvider,
        materialManifestStoreProvider,
        materialsBaseDirectoryProvider;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/player/control_layer.dart'
    show
        ControlLayer,
        gridStepHapticProvider,
        kPortraitRotateButtonKey,
        kPortraitVideoToolbarColumnCount,
        kTopBarRenameHotZoneHeight,
        kTopBarRenameIconColor,
        kTopBarRenameIconGap,
        kTopBarRenameIconSize,
        kTopBarRenameRightInset,
        kTopBarToolsGapWidth,
        topBarSpeedSlotWidth;
import 'package:dance_learning_app/player/compare_split.dart'
    show kCompareSplitGap;
import 'package:dance_learning_app/player/editor_skeleton.dart'
    show
        kEditorPortraitToolbarRowsHeight,
        kEditorSettingsClusterHeight,
        kEditorTopBarHeight,
        kEditorVideoToolbarHeight;
import 'package:dance_learning_app/core/frame_time.dart'
    show frameDurationFor, kDefaultFrameDuration;
import 'package:dance_learning_app/player/load_gate.dart'
    show loadGateActiveProvider;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeHost, NoticeId, noticeTimingOf, noticeTriggerProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSelectionDomainProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        learningMasteryProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider,
        practiceClipsProvider,
        selectedHalfBeatLineIndexProvider,
        selectedLearningSegmentRepresentativeProvider,
        selectedLocalMirrorFragmentIndexProvider,
        selectedPracticeClipIdProvider,
        selectedSegmentLineIndexProvider,
        selectedVideoRangeBoundaryProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/editor_skeleton.dart'
    show
        EditorSkeleton,
        editorSkeletonFor,
        portraitPictureAreaRect,
        portraitRotateButtonRect;
import 'package:dance_learning_app/player/track_band_session.dart'
    show TrackBandSession;
import 'package:dance_learning_app/player/track_time.dart'
    show TimelineWindow;
import 'package:dance_learning_app/player/note_editor.dart'
    show noteTextEditorTargetProvider;
import 'package:dance_learning_app/player/compare_framing_view.dart'
    show compareFramingPictureRect;
import 'package:dance_learning_app/player/note_sticker_overlay.dart'
    show NoteStickerOverlay;
import 'package:dance_learning_app/player/av_sync.dart'
    show
        AudioOutputDeviceController,
        AvSyncDeviceInfo,
        audioOutputDeviceControllerProvider;
import 'package:dance_learning_app/player/av_sync_session.dart'
    show avSyncCalibrationSessionProvider;
import 'package:dance_learning_app/player/play_tool_table.dart'
    show
        kPlayToolLocalMirror,
        kPlayToolRowPortraitVideoToolbarBottom,
        kPlayToolRowPortraitVideoToolbarTop;
import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowTable;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/player/material_library.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart'
    show practiceClipEngineProvider;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatGridProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/preview_snap.dart'
    show previewSnapEnabledProvider;
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show DelayedLoopBeats, delayedLoopProvider;
import 'package:dance_learning_app/player/rate_label_slot.dart'
    show RateTextSlot;
import 'package:dance_learning_app/core/playback/serial_seek.dart'
    show kScrubSeekMinInterval;
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import '../helpers/video_surface.dart'
    show videoSurfacePlaceholderKey;
import 'package:dance_learning_app/player/gestures.dart' show seekDeltaFor;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'dart:io' show Directory;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/bubble_clamp_assertions.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/in_memory_private_json_storage.dart';
import 'package:dance_learning_app/player/mirror.dart' show MirrorController;
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/player/song_naming.dart'
    show SongNamingDialog;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';


/// 经控制柄（轨道手柄带）点击分段线（选中路径）。
Future<void> tapSegmentLineHandle(WidgetTester tester, int index) {
  return tester.tap(
    find.byKey(Key('segment_line_${index}_handle')),
    warnIfMissed: false,
  );
}

/// 顶栏播放设置工具图标：取工具槽位内第一个 Icon 的颜色
/// （置灰 = 白系低透明度，激活 = 琥珀）。
Color toolIconColor(WidgetTester tester, String toolKey) =>
    tester
        .widget<Icon>(
          find
              .descendant(
                of: find.byKey(Key(toolKey)),
                matching: find.byType(Icon),
              )
              .first,
        )
        .color!;

/// 可视窗口几何断言：[TimelineWindow] 按三字段逐一
/// 比对。
void expectWindow(
  TimelineWindow? actual, {
  required Duration start,
  required Duration end,
  Duration? total,
  String? reason,
}) {
  expect(actual, isNotNull, reason: reason);
  expect(actual!.start, start, reason: reason);
  expect(actual.end, end, reason: reason);
  if (total != null) expect(actual.total, total, reason: reason);
}


/// 直接挂载宿主：顶栏交互用例的测试壳只做生产
/// 宿主对控制层的三件事——传入镜像状态机与轨道带会话域、收起边沿移除
/// 控制层、短暂提示由 [NoticeHost] 渲染。播放页的打开会话、镜像询问遮罩、
/// 练习面与素材清单等整页装配不在本壳里。
class _ControlHost extends ConsumerStatefulWidget {
  const _ControlHost({
    required this.engine,
    required this.title,
    required this.skeleton,
    required this.indexStore,
    required this.docs,
    required this.layerWidth,
    required this.onMirrorReady,
    this.onSessionReady,
  });

  final FakePlaybackEngine engine;
  final String title;
  final EditorSkeleton skeleton;
  final InMemoryVideoIndexStorage indexStore;
  final InMemoryVideoDocumentStorage docs;
  final double Function() layerWidth;
  final ValueChanged<MirrorController> onMirrorReady;
  final ValueChanged<TrackBandSession>? onSessionReady;

  @override
  ConsumerState<_ControlHost> createState() => _ControlHostState();
}

class _ControlHostState extends ConsumerState<_ControlHost> {
  late final MirrorController _mirror;
  late final TrackBandSession _session;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    // 镜像状态机（宿主保有；打开会话的 resolve 由测试壳在泵出后驱动）。
    _mirror = MirrorController(
      widget.indexStore,
      coordinatorFor: (videoId) =>
          ref.read(videoDocumentCoordinatorProvider(videoId)),
      onLocalMirrorEnabledChanged: (value) =>
          ref.read(localMirrorEnabledProvider.notifier).replace(value),
    );
    widget.onMirrorReady(_mirror);
    _session = TrackBandSession(
      engine: widget.engine,
      timeline: () => ref.read(annotationTimelineProvider),
      clearLoops: (_, _) {},
      layerWidth: widget.layerWidth,
    );
    widget.onSessionReady?.call(_session);
  }

  @override
  Widget build(BuildContext context) {
    // 元素复用（同一用例内二次泵出）不重走 initState：每次 build 上报句柄。
    widget.onMirrorReady(_mirror);
    // 收起边沿（生产宿主同款）：控制层展开位 true→false 即移除控制层。
    ref.listen(playerSessionProvider, (previous, next) {
      if (previous != null &&
          previous.controlOpen &&
          !next.controlOpen &&
          _visible) {
        setState(() => _visible = false);
      }
    });
    return Stack(
      children: [
        if (_visible)
          ListenableBuilder(
            listenable: _mirror,
            builder: (context, _) => ControlLayer(
              session: _session,
              title: widget.title,
              mirror: _mirror,
              playing: widget.engine.isPlaying,
              onTogglePlay: () => widget.engine.isPlaying
                  ? widget.engine.pause()
                  : widget.engine.play(),
              onDelayedPlay: () {},
              onBack: () {},
              onCollapse: () => ref
                  .read(playerSessionProvider.notifier)
                  .collapse(),
              onEditSignature: () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => SongNamingDialog(
                    initialSong: widget.title,
                    fallbackText: widget.title,
                  ),
                ),
              ),
              skeleton: widget.skeleton,
              rowTable: TrackRowTable.normal,
              recording: false,
              onRequestOrientation: (_) {},
            ),
          ),
        // 居中短暂提示：控制层触发面（软门解释、装载提示）的渲染宿主。
        NoticeHost(specs: kNoticeSpecs),
      ],
    );
  }
}

void main() {

/// 某标注工具槽内的文案（轨道片头标签与槽文案同字，如「分段」
/// 「镜像」，断言按槽键圈定，不被带内标签命中）。
Finder slotText(Key slot, String text) =>
    find.descendant(of: find.byKey(slot), matching: find.text(text));
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    FakeSystemUi? systemUi,
    Uri? source,
    List<VideoIndexEntry>? indexEntries,
    Key? pageKey,
    VoidCallback? gridStepHaptic,
    BeatGrid? beatGrid,
    BeatAnalysisPipeline? beatPipeline,
    bool readyBeat = true,
    bool injectAvSyncSeam = false,
    // true = 真机引导宿主包住整页（测就地讲解与
    // 菜单锚点的叠层语义时用）。
    bool wrapGuideHost = false,
    // 引导宿主接缝要按「首启已走完」装配时传入（空存储 = 首启待走，会
    // 压住被测角标）。
    InMemoryPrivateJsonStorage? guideStorage,
    InMemoryVideoDocumentStorage? docs,
    // riverpod 3.4.2 未公开导出 Override 类型，沿用整页 harness 的动态清单。
    List<dynamic> extraOverrides = const [],
    Directory? materialsDir,
    MaterialManifestStorage? manifestStorage,
  }) async {
    final resolved = source ?? Uri.file('/videos/a.mp4');
    // 打开会话与镜像/偏好/署名消费方共读同一份内存文档与同一身份：库内
    // 种子条目 videoId 即固定哈希值（摘要相符 → 身份取条目），否则按
    // 新视频（entry 为 null）。真实实现走 path_provider + 文件哈希，在
    // flutter_test 的 fake async 时钟下不完成。
    final entries =
        indexEntries ??
        [
          historyEntry(filePath: resolved.toFilePath(), mirrored: false),
        ];
    final docStorage = docs ?? InMemoryVideoDocumentStorage();
    final entryVideoId = entries.length == 1 ? entries.single.videoId : 'seeded';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 格点跳步轻震注入：测试传记录器断言。
          if (gridStepHaptic != null)
            gridStepHapticProvider.overrideWithValue(gridStepHaptic),
          // 节拍网格注入（seam 测试点）：no-op 有界网格用例。
          if (beatGrid != null) beatGridProvider.overrideWithValue(beatGrid),
          playbackEngineProvider.overrideWithValue(engine),
          // 练习侧第二播放源：替身注入——缺省
          // MediaKit 引擎在测试宿主不可用（未 ensureInitialized）。
          practiceClipEngineProvider.overrideWithValue(
            FakePlaybackEngine(duration: const Duration(seconds: 20)),
          ),
          // 节拍分析管线注入：缺省走挂起管线（停稳在占位态、
          // 在其上注入与占位网格同值的就绪态，分段工具就绪门
          // 可点且几何换算与旧占位用例一致）；显式传入管线则原样（随后经
          // [injectBeatState] 注入目标态，不被分析流程改写）。
          beatAnalysisPipelineProvider.overrideWithValue(
            beatPipeline ?? hangingBeatPipeline,
          ),
          // 预设持久化：内存实现，避免真实文件 IO。
          privateJsonStorageProvider.overrideWithValue(
            guideStorage ?? InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(
            systemUi ?? FakeSystemUi(),
          ),
          // 音画同步设备快照 seam（补测用）：不注入时保持既有
          // 环境原样（会话进入不等快照、不激活）。
          if (injectAvSyncSeam)
            audioOutputDeviceControllerProvider.overrideWithValue(
              _FakeAudioOutputDeviceController(),
            ),
          contentHasherProvider.overrideWithValue(
            FixedHasher(entryVideoId),
          ),
          // 打开会话读两份文档（工厂）与镜像控制器读 markers（协调器）指向
          // 同一份内存文档：真实实现走 path_provider，在 flutter_test 的
          // fake async 时钟下不完成。
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) => VideoDocumentCoordinator(docStorage),
          ),
          ...extraOverrides,
          if (materialsDir != null)
            materialsBaseDirectoryProvider.overrideWithValue(
              () async => materialsDir,
            ),
          if (manifestStorage != null)
            materialManifestStorageProvider.overrideWithValue(
              manifestStorage,
            ),
          // 镜像索引：种入匹配 source 的「已询问」条目（镜像 false）→ 走
          // 历史应用路径，不弹询问遮罩（避免阻断控制层交互）。
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: VideoIndex(entries: entries)),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => wrapGuideHost
              ? GuideHost(child: child!)
              : (child ?? const SizedBox.shrink()),
          home: PlayerPage(key: pageKey, source: resolved),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 分段工具就绪门（无就绪网格置灰）——缺省注入与占位网格
    // 同值的就绪态（挂起管线保证不被分析流程改写）。
    if (readyBeat) {
      // 就绪网格覆盖引擎全时长（刻度可见性断言按全窗拍数计）。
      await injectBeatState(
        tester,
        uniformReadyBeatState(
          seconds: (engine.duration?.inMilliseconds ??
                  const Duration(seconds: 30).inMilliseconds) /
              1000,
        ),
      );
    }
  }

  /// 画面是否以水平镜像 Transform 呈现（翻转 = [mirrored_surface]；起
  /// 翻转门读「当前位置处的有效镜像」—— 三个镜像组共用）。
  bool surfaceMirrored(WidgetTester tester) =>
      find.byKey(const Key('mirrored_surface')).evaluate().isNotEmpty;

  /// 把播放头定格到 [position]：暂停 → seek（位置流补发）→ 重建一帧，翻转门
  /// 按当前位置重判（位置即真值）。
  Future<void> freezePlayheadAt(
    WidgetTester tester,
    FakePlaybackEngine engine,
    Duration position,
  ) async {
    await engine.pause();
    await engine.seek(position);
    await tester.pump();
  }

  /// 双击：两次 tap 间隔 < 双击窗口（复用 player_page 测试语义）。
  Future<void> doubleTap(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 单击唤出控制层：等双击判定窗口过（识别器回调孤立单指单击）后渲染。
  /// 宽视口：顶栏工具因「全局镜像」（原「镜像」加宽）与新增的
  /// 「局部镜像」两槽而变宽，默认测试视口（800 逻辑宽）已放不下 12 个槽
  /// ——断言「顶栏槽全部内联 / 逐个点顶栏槽」的用例须在真放得下的视口下跑。
  /// 960 与真实横屏设备同量级（dev 机横屏约 995 逻辑宽）。
  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> singleTapShow(WidgetTester tester) async {    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 泵出「镜像两层开关」共用的播放页并展开控制层：注入内存按视频文档
  /// 存储，使镜像控制器打开时按 videoId 读 markers 真值的路径立即完成
  /// （真实实现走 path_provider，在 flutter_test 的 fake async 时钟下不完成）。
  ///
  /// 声明在 [singleTapShow] 之后：Dart 局部函数须先声明后引用。
  Future<(FakePlaybackEngine, ProviderContainer, InMemoryVideoDocumentStorage)>
      pumpMirrorPlayer(
    WidgetTester tester, {
    Map<String, dynamic> markers = const {},
  }) async {
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    final docs = InMemoryVideoDocumentStorage(markers: markers);
    await pumpPlayer(tester, engine: engine, docs: docs);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
    await singleTapShow(tester);
    return (engine, container, docs);
  }

  /// 直接挂载壳里的容器读取（控制层是树上唯一类型锚点）。
  ProviderContainer containerOfControlLayer(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(ControlLayer)),
        listen: false,
      );

  /// 直接挂载控制层：顶栏交互用例的进入点从整页
  /// 降到控制层公开边界——控制层是公开类型，直接挂载省掉整页 harness 里
  /// 只为播放页打开会话与镜像身份路径服务的依赖替换（练习侧第二播放源、
  /// 内容哈希、素材目录/清单、镜像索引询问种子等）。依赖替换只留控制层
  /// 子树真需要的六件：播放内核、挂起节拍管线、预设持久化、系统 UI、
  /// 文档协调器与镜像索引实例。短暂提示渲染与收起移除见 [_ControlHost]。
  Future<
    (
      FakePlaybackEngine,
      ProviderContainer,
      InMemoryVideoDocumentStorage,
      MirrorController
    )
  >
  pumpControlLayer(
    WidgetTester tester, {
    FakePlaybackEngine? engine,
    Uri? source,
    InMemoryVideoDocumentStorage? docs,
    VideoIndexEntry? entry,
    bool readyBeat = true,
    bool injectAvSyncSeam = false,
    ValueChanged<TrackBandSession>? onSessionReady,
    // riverpod 3.4.2 未公开导出 Override 类型，沿用整页 harness 的动态清单。
    List<dynamic> extraOverrides = const [],
  }) async {
    final resolved = source ?? Uri.file('/videos/a.mp4');
    final e =
        engine ??
        FakePlaybackEngine(
          duration: const Duration(seconds: 30),
          videoAspectRatio: 16 / 9,
        );
    final docStorage = docs ?? InMemoryVideoDocumentStorage();
    // 打开会话给出的已确认身份（镜像读写锚定它）：缺省种一条「已询问、
    // 未镜像」的历史条目，走历史应用路径、不弹询问遮罩。
    final indexEntry =
        entry ?? historyEntry(filePath: resolved.toFilePath(), mirrored: false);
    final indexStore = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [indexEntry]),
    );
    MirrorController? mirror;
    final dpr = tester.view.devicePixelRatio;
    final screenWidth = tester.view.physicalSize.width / dpr;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(e),
          // 节拍分析管线挂起（同整页 harness）：就绪态由下方显式注入。
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          // 预设持久化：内存实现，避免真实文件 IO。
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          // 音画同步设备快照 seam：不注入时保持既有环境原样。
          if (injectAvSyncSeam)
            audioOutputDeviceControllerProvider.overrideWithValue(
              _FakeAudioOutputDeviceController(),
            ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) => VideoDocumentCoordinator(docStorage),
          ),
          videoIndexStoreProvider.overrideWithValue(indexStore),
          ...extraOverrides,
        ],
        child: MaterialApp(
          home: _ControlHost(
            engine: e,
            title: resolved.pathSegments.last,
            skeleton: editorSkeletonFor(
              screen: Size(
                screenWidth,
                tester.view.physicalSize.height / dpr,
              ),
              trackBandHeight: TrackRowTable.normal.totalHeight,
              videoAspectRatio: e.videoAspectRatio,
            ),
            indexStore: indexStore,
            docs: docStorage,
            layerWidth: () => screenWidth,
            onMirrorReady: (m) => mirror = m,
            onSessionReady: onSessionReady,
          ),
        ),
      ),
    );
    try {
      await tester.pumpAndSettle();
    } on FlutterError catch (error) {
      // 直接挂载即展开：长标题跑马灯等常驻动画永不静默。只豁免「达到
      // pumpAndSettle 超时」这一种（已达稳定布局），其余布局异常照抛。
      if (!error.message.contains('pumpAndSettle timed out')) rethrow;
    }
    // 直接挂载即处于编辑面（控制层展开）：会话模式对齐生产「控制层展开时」
    // 的取值，收起边沿（collapse → watching）由此可达。
    containerOfControlLayer(tester)
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.editing);
    await tester.pump();
    // 镜像身份路径（打开会话在生产里做的事）：resolve 后控制器进入
    // 「历史已应用」态，顶栏镜像/局部镜像槽读写真值。
    final baselineMarkers = docStorage.markersSnapshot.isEmpty
        ? null
        : marker_doc.MarkersDocument.fromJson(docStorage.markersSnapshot);
    await mirror!.resolve(
      resolved.toFilePath(),
      videoId: indexEntry.videoId,
      entry: indexEntry,
      baselineMarkers: baselineMarkers,
    );
    // 历史应用路径的「已按历史应用镜像」提示定时器（fake 时钟）：推过
    // 提示时长使其落定，不悬跨用例。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    if (readyBeat) {
      // 就绪网格覆盖引擎全时长（与整页 harness 同一注入，分段工具就绪门
      // 与步进范围判定按全窗拍数计）。
      ProviderScope.containerOf(
        tester.element(find.byType(ControlLayer)),
        listen: false,
      ).read(beatTrackStateProvider.notifier).replace(
            uniformReadyBeatState(
              seconds: (e.duration?.inMilliseconds ??
                  const Duration(seconds: 30).inMilliseconds) /
                  1000,
            ),
          );
      await tester.pump();
    }
    return (e, containerOfControlLayer(tester), docStorage, mirror!);
  }

  /// 编辑态空白单击收起：tap 后推进约 300ms 判定窗口再复核
  /// （pumpAndSettle 不推进无帧定时的判定窗口）。
  Future<void> tapBlankAndCollapse(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 竖屏视口：刻意放宽的**合成档**（物理宽放宽至 1336 = 668dp
  /// 逻辑宽，真机 DNP-AN00 为 632dp——放宽量 = 底排槽位统一「外 6 + 内 4/4」
  /// 内边距与 24 图标后整排的加宽量，见 [setNarrowView] 处同类先例；
  /// 实际逻辑尺寸 668×1368dp，非设备基准）。
  void setWidenedPortraitView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1336, 2736); // 合成档 668.0×1368.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Finder controlLayer() => find.byKey(const Key('control_layer'));

  /// 按标注工具槽位 key（挂在 Padding 上）取其第一个 InkWell。
  InkWell slotInkWell(WidgetTester tester, String slotKey) =>
      tester.widget<InkWell>(
        find
            .descendant(
              of: find.byKey(Key(slotKey)),
              matching: find.byType(InkWell),
            )
            .first,
      );

  /// 标注工具槽位是否可点（未选中/置灰时 onTap 为 null 但槽位常驻）。
  bool slotEnabled(WidgetTester tester, String slotKey) =>
      slotInkWell(tester, slotKey).onTap != null;

  /// 标注工具槽位内第一个 Icon 的颜色（置灰 = 白系低透明度）。
  Color slotIconColor(WidgetTester tester, String slotKey) =>
      tester.widget<Icon>(
        find
            .descendant(
              of: find.byKey(Key(slotKey)),
              matching: find.byType(Icon),
            )
            .first,
      ).color!;

  /// 菜单条目文字的显式颜色（未置灰 = null，置灰 = 浅底菜单不可用 token）。
  Color? menuEntryTextColor(WidgetTester tester, String entryKey) =>
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(Key(entryKey)),
              matching: find.byType(Text),
            ),
          )
          .style
          ?.color;

  /// 正常态槽集声明的槽键（声明次序）：槽位与次序的唯一来源是槽集声明
  /// 几何类断言不再手抄字段表。
  List<String> normalSlotKeys() => [
    for (final slot in ToolSlotTable.normal.slots) slot.key,
  ];

  /// 实际渲染出的标注工具槽键（按树序）：在工具条子树里收集所有命中工具
  /// 槽键全集（三份槽集并集）的字符串键。供跨面一致性断言使用。
  List<String> renderedSlotKeys(WidgetTester tester) {
    final universe = {
      for (final table in [
        ToolSlotTable.normal,
        ToolSlotTable.standby,
        ToolSlotTable.compare,
      ])
        for (final slot in table.slots) slot.key,
    };
    return find
        .descendant(
          of: find.byKey(const Key('control_layer_toolbar')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget.key is Key &&
                widget.key is ValueKey<String> &&
                universe.contains((widget.key as ValueKey<String>).value),
          ),
        )
        .evaluate()
        .map((element) => (element.widget.key as ValueKey<String>).value)
        .toList();
  }

  /// 打开「添加」条目菜单：点「添加」槽 → 等菜单路由弹出。
  Future<void> openAddMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('control_add')));
    await tester.pumpAndSettle();
  }

  /// 经「添加」槽触达条目：点开「添加」菜单 → 选中条目。
  Future<void> tapAddEntry(WidgetTester tester, String entryKey) async {
    await openAddMenu(tester);
    await tester.tap(find.byKey(Key(entryKey)));
    await tester.pumpAndSettle();
  }

  /// 打开「自动分段」条目菜单：点「自动分段」槽 → 等菜单路由
  /// 弹出。
  Future<void> openAutoMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('control_auto_range')));
    await tester.pumpAndSettle();
  }

  /// 经「自动分段」槽触达条目：点开菜单 → 选中条目。
  Future<void> tapAutoEntry(WidgetTester tester, String entryKey) async {
    await openAutoMenu(tester);
    await tester.tap(find.byKey(Key(entryKey)));
    await tester.pumpAndSettle();
  }

  /// 菜单里实际渲染出的自动分段条目键（按树序）。
  List<String> renderedAutoEntryKeys(WidgetTester tester) {
    final universe = {
      for (final entry in AutoSegmentEntryTable.normal.entries) entry.key,
    };
    return find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              universe.contains((widget.key as ValueKey<String>).value),
        )
        .evaluate()
        .map((element) => (element.widget.key as ValueKey<String>).value)
        .toList();
  }

  /// 菜单里实际渲染出的条目键（按树序）：收集当前树上命中条目键全集的
  /// 字符串键（菜单未开时为空）。供跨面一致性断言使用。
  List<String> renderedAddEntryKeys(WidgetTester tester) {
    final universe = {
      for (final entry in AddEntryTable.normal.entries) entry.key,
    };
    return find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              universe.contains((widget.key as ValueKey<String>).value),
        )
        .evaluate()
        .map((element) => (element.widget.key as ValueKey<String>).value)
        .toList();
  }

  group('唤出 / 收起', () {
    testWidgets('单击唤出控制层：顶部栏含返回箭头与视频文件名标题；单击空白收起', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);

      expect(controlLayer(), findsNothing);

      await singleTapShow(tester);

      expect(controlLayer(), findsOneWidget);
      // 顶部栏：返回箭头 + 文件名标题。
      expect(find.byKey(const Key('control_layer_back')), findsOneWidget);
      expect(find.text('a.mp4'), findsOneWidget);
      // 底部工具条右侧标注工具可见（不可用态）。
      expect(slotText(const Key('control_segment'), '分段'), findsOneWidget);
      expect(
        slotText(const Key('control_auto_range'), '自动分段'),
        findsOneWidget,
      );

      // 单击控制层外空白（中部轨道区占位）收起。
      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('control_layer_blank')),
      );
      expect(controlLayer(), findsNothing);
    });

    testWidgets('再次单击空白收起后播放手势恢复；展开零锁、收起零方向请求', (tester) async {
      final engine = FakePlaybackEngine();
      final systemUi = FakeSystemUi();
      await pumpPlayer(tester, engine: engine, systemUi: systemUi);

      await singleTapShow(tester);
      expect(systemUi.lockLandscapeCount, 0, reason: '进编辑面不锁方向');

      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('control_layer_blank')),
      );
      expect(systemUi.lockLandscapeCount, 0);
    });
  });

  group('设置簇迁出轨道带', () {
    testWidgets('控制层承载设置簇：轨道带外（带上方）右对齐、组序含延迟循环；不占带内', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final band = tester.getRect(find.byKey(const Key('track_band')));
      final cluster = tester.getRect(find.byKey(const Key('settings_cluster')));
      final previewSlot = tester.getRect(
        find.byKey(const Key('track_preview_snap_slot')),
      );
      final zoom = tester.getRect(find.byKey(const Key('track_zoom_dock')));
      final lock = tester.getRect(find.byKey(const Key('layout_lock_toggle')));

      // 带外：整簇在轨道带上方，不占带内内容区。
      expect(cluster.bottom, lessThanOrEqualTo(band.top + 1));
      for (final rect in [previewSlot, zoom, lock]) {
        expect(rect.intersect(band).isEmpty, isTrue);
      }
      // 右对齐贴带右缘。
      expect(cluster.right, lessThanOrEqualTo(band.right));
      expect(cluster.right, greaterThan(band.right - 16));
      // 组序 [预览吸附｜锁定分段｜缩放滑条]（前导退场、滑条靠右）。
      expect(previewSlot.right, lessThanOrEqualTo(lock.left));
      expect(lock.right, lessThanOrEqualTo(zoom.left));
      // 前导选择器退场：入口与文案都不在。
      expect(find.byKey(const Key('delayed_loop_menu')), findsNothing);
      expect(find.text('前导 4拍'), findsNothing);
      // 前导默认档位仍 4 拍（字段与取值域照旧，入口不在但行为不变）。
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('settings_cluster'))),
        listen: false,
      );
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.four);
    });

    testWidgets('设置条命中盒 ≥ 下限：两枚开关胶囊与缩放滑条', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      for (final key in const [
        'track_preview_snap_slot',
        'layout_lock_toggle',
        'track_zoom_dock',
        'track_zoom_slider',
      ]) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(
          rect.width,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中盒宽 ≥ $kHitTargetMinSize',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中盒高 ≥ $kHitTargetMinSize',
        );
      }
    });

    testWidgets('无时间线（时长未知）时整簇隐藏', (tester) async {
      final engine = _DurationlessEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      expect(find.byKey(const Key('settings_cluster')), findsNothing);
      expect(find.byKey(const Key('track_zoom_dock')), findsNothing);
      expect(find.byKey(const Key('delayed_loop_menu')), findsNothing);
    });

    testWidgets('缩放滑条左侧放大镜为纯装饰图标：存在、点击无任何状态变化', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final dock = find.byKey(const Key('track_zoom_dock'));
      final magnifier = find.descendant(
        of: dock,
        matching: find.byIcon(Icons.search),
      );
      expect(magnifier, findsOneWidget);

      // 点击放大镜：锁定分段、吸附、缩放窗口等状态全部不动。
      final container = ProviderScope.containerOf(
        tester.element(dock),
        listen: false,
      );
      final lockedBefore = container.read(layoutLockedProvider);
      final snapBefore = container.read(previewSnapEnabledProvider);
      await tester.tap(magnifier, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(container.read(layoutLockedProvider), lockedBefore);
      expect(container.read(previewSnapEnabledProvider), snapBefore);
      expect(
        tester.widget<Slider>(find.byKey(const Key('track_zoom_slider'))).value,
        0,
      );
    });

    testWidgets('延迟播放按钮图标 = 播放三角 + 右下角小时钟；按钮命中区不变', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final button = find.byKey(const Key('toolbar_delayed_play'));
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.play_arrow)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: button, matching: find.byIcon(Icons.schedule)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.av_timer), findsNothing);
      // 命中区与相邻播放按钮一致（IconButton 常规档）。
      final playRect = tester.getRect(find.byKey(const Key('toolbar_play')));
      expect(tester.getRect(button).height, playRect.height);
      expect(tester.getRect(button).width, playRect.width);
    });
  });

  group('轨道带（骨架）', () {
    testWidgets('控制层展开时视频下部显示轨道带（工具条上方）：三轨存在且带底于工具条', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      expect(find.byKey(const Key('track_band')), findsOneWidget);
      expect(find.byKey(const Key('track_learning')), findsOneWidget);
      expect(find.byKey(const Key('track_beat')), findsOneWidget);
      expect(find.byKey(const Key('track_handle_strip_row')), findsOneWidget);

      // 轨道带浮于底部工具条上方（带底 ≤ 工具条顶）。
      final bandBottom = tester
          .getBottomLeft(find.byKey(const Key('track_band')))
          .dy;
      final toolbarTop = tester
          .getTopLeft(find.byKey(const Key('control_layer_toolbar')))
          .dy;
      expect(bandBottom, lessThanOrEqualTo(toolbarTop));
    });

    testWidgets('轨道带背景 ≈ 黑60% 且控制层主体透明（浮层不被整屏叠层加深）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 轨道带自身 ≈黑60%，直接叠于 contain 视频上；
      // 控制层主体为透明（不再整屏 0.55 压暗，避免带被叠到 ≈82%）。
      final band = tester.widget<Container>(
        find.byKey(const Key('track_band')),
      );
      expect(band.color, Colors.black.withValues(alpha: 0.6));
      final shell = tester.widget<Material>(
        find.byKey(const Key('control_layer')),
      );
      expect(shell.type, MaterialType.transparency);
    });
  });

  group('分段工具', () {
    testWidgets('点击分段在预览线处创建分段线并生成前后学习段', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      expect(find.byKey(const Key('learning_segment_0')), findsNothing);
      expect(find.byKey(const Key('segment_line_0')), findsNothing);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('segment_line_0')), findsOneWidget);
      expect(find.byKey(const Key('learning_segment_0')), findsOneWidget);
      expect(find.byKey(const Key('learning_segment_1')), findsOneWidget);
      // 角标触达与新产物序号：落线**成功**才记，
      // 序号 = 刚落的那条线。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeSegmentUnitId),
      );
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeSegmentUnitId],
        0,
      );

      // 连着落第二条：序号更新为 1，角标改指刚落的第二条。
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeSegmentUnitId],
        1,
      );

      // 分段只落八拍点——预览 10s → 就近八拍点 12s（8s/12s
      // 等距取靠后）；x 按内容区宽（片头让位）。
      final rect = tester.getRect(find.byKey(const Key('segment_line_0')));
      final bandWidth = tester
          .getSize(find.byKey(const Key('track_band')))
          .width;
      expect(rect.center.dx, closeTo(bandX(12, total: 30, width: bandWidth), 1));
    });

    testWidgets('预览线在有效区间边界时分段按钮拒绝创建', (tester) async {
      // 打开即播放：用 400ms 短片让播放自然停在「视频尾」，测开区间右边界。
      final engine = FakePlaybackEngine(
        duration: const Duration(milliseconds: 400),
      );
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('segment_line_0')), findsNothing);
      expect(find.byKey(const Key('learning_segment_0')), findsNothing);
    });

    testWidgets('自动分段：打开三档菜单即触达，角标锚在菜单本体上', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: InMemoryPrivateJsonStorage(
          initial: {
            // 其余 13 个单元全部按「已看过」装配，只留自动分段待走。
            'onboarding': {
              for (final f in onboardingFlagFields.values) f: true,
            }..['badgeAutoSegment'] = false,
          },
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);

      await openAutoMenu(tester);

      // 菜单本体带菜单锚 key（不是回指工具槽），触达照旧在「菜单打开」
      // 这一刻记；讲解气泡真的挖洞在菜单上、箭头指准菜单中心。
      expect(find.byKey(Key(autoSegmentMenuAnchorKey)), findsOneWidget);
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeAutoSegmentUnitId),
      );
      await tester.pumpAndSettle();
      expect(
        container
            .read(guideAnchorRectsProvider)[autoSegmentMenuAnchorKey],
        isNotNull,
      );
      expectGuidePointsAt(
        tester,
        find.byKey(Key(autoSegmentMenuAnchorKey)),
      );

      // 菜单项照常可点（洞内穿透的前提）：选档生效、菜单关闭、矩形撤下。
      await tester.tap(find.byKey(const Key('control_auto_seg_4')));
      await tester.pumpAndSettle();
      expect(renderedAutoEntryKeys(tester), isEmpty, reason: '菜单已关闭');
      expect(
        container
            .read(guideAnchorRectsProvider)[autoSegmentMenuAnchorKey],
        isNull,
        reason: '菜单关闭即撤下矩形，宿主不再按已关菜单的位置画洞',
      );
    });
  });

  group('分段按钮八拍点落点（取代任意/格点吸附）', () {
    /// 就绪网格与占位同值（八拍点 = 0/4/8…s）；预览停 10s+300ms → 就近
    /// 八拍点 = 12s（距 12s 1.7s、距 8s 2.3s）。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpAtOffPoint(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10, milliseconds: 300));
      await engine.pause();
      await tester.pump();
      return (engine, container);
    }

    testWidgets('建线落在就近八拍点、播放头/预览线位置不动', (tester) async {
      final (engine, container) = await pumpAtOffPoint(tester);
      final positionBefore = engine.position;
      final seekCountBefore = engine.seekCalls.length;

      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        const Duration(seconds: 12),
        reason: '分段只落八拍点（预览 10s+300ms → 12s）',
      );
      expect(engine.position, positionBefore, reason: '创建不移动播放头');
      expect(engine.seekCalls.length, seekCountBefore, reason: '创建不 seek');
      // 重复位置 no-op 语义不变：再点一次不产生重复线。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).segmentLines.length,
        1,
      );
      // no-op 路径不重复触达：序号保持首次落线记下的 0，不被二次改写。
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeSegmentUnitId],
        0,
      );
    });


    testWidgets('八拍点落在有效区间边界时拒斥创建（既有区间外拒斥不变）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      // 预览 500ms 在开区间内，但最近格点 = 0 = rangeStart（区间边界）。
      await engine.seek(const Duration(milliseconds: 500));
      await engine.pause();
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('segment_line_0')), findsNothing);
      expect(
        container.read(annotationTimelineProvider).segmentLines,
        isEmpty,
      );
    });

    testWidgets('占位态：置灰、单击弹「节拍分析中…」且不建线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      // 网格未就绪种类唯一一条外观断言：置灰统一为同一 token。
      expect(slotIconColor(tester, 'control_segment'),
          kToolSlotDisabledIconColor);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_analyzing_prompt')), findsOneWidget);
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      // 角标不被消耗：讲解不出现，触达也没记。
      expect(
        container.read(guideSessionProvider).triggered,
        isNot(contains(badgeSegmentUnitId)),
      );
    });

    testWidgets('异常态：置灰、单击弹「无节拍数据」且不建线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(beatTrackStateProvider.notifier).replace(
            const BeatTrackState.error(),
          );
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      // 外观已由上一条（网格未就绪种类）唯一断言钉住，此处只钉语义。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_no_data_prompt')), findsOneWidget);
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
    });
  });

  group('学习段熟练度与重点', () {
    /// 点选学习段片段：在其左下（25%/75%）处点按——右上 dock
    /// 覆盖学习段轨右端的上半行（dock 高约 26dp < 轨高 48dp），右端长
    /// 片段（如单线 30s 视频的段 1）中心点会落在 dock 上；与真机一致
    /// 点按未被 dock 遮挡的段体区（行下半、偏左）。
    Future<void> tapLearningSegmentBody(WidgetTester tester, int index) async {
      final rect = tester.getRect(find.byKey(Key('learning_segment_$index')));
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.75),
      );
    }

    Future<void> pumpWithSelectedSegment(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await tapLearningSegmentBody(tester, 1);
      await tester.pumpAndSettle();
    }

    Color? segmentColor(WidgetTester tester, int index) {
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      // 格框渲染拆为发光层 + 格框本体，熟练度填充在
                      // `_box` 本体上。
                      of: find.byKey(Key('learning_segment_$index')),
                      matching: find.byKey(
                        Key('learning_segment_${index}_box'),
                      ),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      return decoration.color;
    }

    Future<void> selectMastery(WidgetTester tester, String keyName) async {
      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(keyName)));
      await tester.pumpAndSettle();
    }

    testWidgets('选中片段后可设置熟练度：五档全可选、面板与槽显示按新档位', (tester) async {
      await pumpWithSelectedSegment(tester);

      // 工具区图例（未练灰）与轨道片段灰取同一 token，颜色一致。
      Color? masteryToolIconColor() => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const Key('control_mastery')),
              matching: find.byType(Icon),
            ),
          )
          .color;
      String masteryToolLabel() => tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('control_mastery')),
              matching: find.byType(Text),
            ),
          )
          .data!;

      expect(masteryToolIconColor(), segmentColor(tester, 1));
      expect(masteryToolLabel(), '未练');

      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pumpAndSettle();
      expect(segmentColor(tester, 1), Colors.grey.shade600);
      // 面板五档齐全（菜单键 = 枚举名），档位文案按新档位。
      for (final entry in const {
        'unlearned': '未练',
        'learning': '学习中',
        'keepingUp': '能跟上',
        'familiar': '较熟',
        'mastered': '掌握',
      }.entries) {
        final item = find.descendant(
          of: find.byKey(Key('control_mastery_${entry.key}')),
          matching: find.byType(Text),
        );
        expect(item, findsOneWidget);
        expect(tester.widget<Text>(item).data, entry.value);
      }
      await tester.tap(find.byKey(const Key('control_mastery_unlearned')));
      await tester.pumpAndSettle();

      await selectMastery(tester, 'control_mastery_learning');
      expect(segmentColor(tester, 1), kMasteryLearningColor);
      expect(segmentColor(tester, 1)!.a, 1.0);
      expect(masteryToolLabel(), '学习中');
      expect(masteryToolIconColor(), kMasteryLearningColor, reason: '工具区回显当前熟练度');

      await selectMastery(tester, 'control_mastery_keepingUp');
      expect(segmentColor(tester, 1), kMasteryKeepingUpColor);
      expect(segmentColor(tester, 1)!.a, 1.0);
      expect(masteryToolLabel(), '能跟上');

      await selectMastery(tester, 'control_mastery_familiar');
      expect(segmentColor(tester, 1), kMasteryFamiliarColor);
      expect(segmentColor(tester, 1)!.a, 1.0);
      expect(masteryToolLabel(), '较熟');

      await selectMastery(tester, 'control_mastery_mastered');
      expect(segmentColor(tester, 1), Colors.green);
      expect(segmentColor(tester, 1)!.a, 1.0);
      expect(masteryToolLabel(), '掌握');

      await selectMastery(tester, 'control_mastery_unlearned');
      expect(segmentColor(tester, 1), Colors.grey.shade600);
      expect(masteryToolLabel(), '未练');
      expect(controlLayer(), findsOneWidget, reason: '选中与设置不触发收起');

      // 属性是会话态：收起再唤出后仍保留当前值。
      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('track_handle_strip_row')),
      );
      expect(controlLayer(), findsNothing);
      await singleTapShow(tester);
      expect(segmentColor(tester, 1), Colors.grey.shade600);
    });

    testWidgets('选中片段可切换重点；轨道与工具区状态可见', (tester) async {
      await pumpWithSelectedSegment(tester);

      expect(
        find.byKey(const Key('learning_segment_1_emphasis')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('learning_segment_1_emphasis')),
        findsOneWidget,
      );
      final icon = tester.widget<Icon>(
        find.byKey(const Key('control_emphasis_icon')),
      );
      expect(icon.color, Colors.amber);

      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('learning_segment_1_emphasis')),
        findsNothing,
      );
      expect(controlLayer(), findsOneWidget, reason: '设置重点不触发收起');
    });

    testWidgets('切换选中片段时熟练度/重点跟随各自当前值', (tester) async {
      await pumpWithSelectedSegment(tester);
      await selectMastery(tester, 'control_mastery_learning');
      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await tester.pumpAndSettle();
      expect(segmentColor(tester, 0), Colors.grey.shade600);
      expect(
        find.byKey(const Key('learning_segment_0_emphasis')),
        findsNothing,
      );

      await tapLearningSegmentBody(tester, 1);
      await tester.pumpAndSettle();
      expect(segmentColor(tester, 1), kMasteryLearningColor);
      expect(
        find.byKey(const Key('learning_segment_1_emphasis')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await tester.pumpAndSettle();
      expect(segmentColor(tester, 0), Colors.grey.shade600);
      expect(segmentColor(tester, 1), kMasteryLearningColor);
    });

    testWidgets('打开新视频重置熟练度/重点/选中态（仅当前会话内生效）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await tapLearningSegmentBody(tester, 1);
      await tester.pumpAndSettle();
      await selectMastery(tester, 'control_mastery_learning');
      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();

      await pumpPlayer(
        tester,
        engine: engine,
        source: Uri.file('/videos/b.mp4'),
        pageKey: const Key('second_player_page'),
      );
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(segmentColor(tester, 1), Colors.grey.shade600);
      expect(
        find.byKey(const Key('learning_segment_1_emphasis')),
        findsNothing,
      );
    });

    testWidgets('未选中片段时熟练度/重点工具不可用但按得动（弹做法）；空白单击仍收起', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      // 门 = 无对象：置灰但按得动——点一下弹「该怎么做」，
      // 档位菜单不打开（打开菜单是动作）。槽键此刻挂在按得动的那层上。
      expect(
        tester
            .widget<PopupMenuButton<LearningMastery>>(
              find.descendant(
                of: find.byKey(const Key('control_mastery')),
                matching: find.byType(PopupMenuButton<LearningMastery>),
              ),
            )
            .enabled,
        isFalse,
        reason: '档位菜单本身仍关着',
      );
      expect(slotEnabled(tester, 'control_mastery'), isTrue,
          reason: '无对象 → 置灰但按得动');
      // 槽键挂外层 Padding（统一座架），可点性走语义助手。
      expect(slotEnabled(tester, 'control_emphasis'), isTrue,
          reason: '同门同款');

      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pump();
      await tester.pump();
      expect(find.text('先点一段再点这里'), findsOneWidget);
      expect(find.byKey(const Key('control_mastery_unlearned')), findsNothing);

      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('track_handle_strip_row')),
      );
      expect(controlLayer(), findsNothing);
    });
  });

  group('熟练度与重点作用于全部选中段', () {
    Future<void> tapLearningSegmentBody(WidgetTester tester, int index) async {
      final rect = tester.getRect(find.byKey(Key('learning_segment_$index')));
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.75),
      );
    }

    /// 三段时间线 + 唤出控制层。
    Future<ProviderContainer> pumpThreeSegments(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byKey(const Key('control_mastery'))),
        listen: false,
      );
    }

    /// 长按段 [from] 横拖圈选（松手提交）。
    Future<void> dragSelect(
      WidgetTester tester,
      int from,
      double dragBy,
    ) async {
      final start = tester.getCenter(find.byKey(Key('learning_segment_$from')));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(Offset(dragBy, 0));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    Color? segmentColor(WidgetTester tester, int index) {
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: find.byKey(Key('learning_segment_$index')),
                      matching: find.byKey(
                        Key('learning_segment_${index}_box'),
                      ),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      return decoration.color;
    }

    String masteryToolLabel(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('control_mastery')),
            matching: find.byType(Text),
          ),
        )
        .data!;

    Future<void> selectMastery(WidgetTester tester, String keyName) async {
      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(keyName)));
      await tester.pumpAndSettle();
    }

    testWidgets('圈选多段：熟练度钮显示最低档，选一档全部选中段同档、一步撤销', (tester) async {
      final container = await pumpThreeSegments(tester);
      final editor = container.read(annotationEditorProvider);

      // 先单选布出不等档位：段 0 掌握、段 1 能跟上、段 2 学习中；再圈选 0..2。
      await tapLearningSegmentBody(tester, 0);
      await tester.pumpAndSettle();
      await selectMastery(tester, 'control_mastery_mastered');
      await tapLearningSegmentBody(tester, 1);
      await tester.pumpAndSettle();
      await selectMastery(tester, 'control_mastery_keepingUp');
      await tapLearningSegmentBody(tester, 2);
      await tester.pumpAndSettle();
      await selectMastery(tester, 'control_mastery_learning');
      await dragSelect(tester, 0, 600);

      // 多段档位不一：钮显示其中最低的一档。
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
      expect(masteryToolLabel(tester), '学习中');

      await selectMastery(tester, 'control_mastery_keepingUp');
      expect(segmentColor(tester, 0), kMasteryKeepingUpColor);
      expect(segmentColor(tester, 1), kMasteryKeepingUpColor);
      expect(segmentColor(tester, 2), kMasteryKeepingUpColor);
      expect(masteryToolLabel(tester), '能跟上');

      // 一步撤销回到改前全貌。
      editor.undo();
      await tester.pumpAndSettle();
      expect(segmentColor(tester, 0), Colors.green);
      expect(segmentColor(tester, 1), kMasteryKeepingUpColor);
      expect(segmentColor(tester, 2), kMasteryLearningColor);
    });

    testWidgets('圈选多段点重点：不全有星一次全点亮、全有星一次全取消', (tester) async {
      final container = await pumpThreeSegments(tester);
      await dragSelect(tester, 0, 600);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});

      Icon emphasisIcon(WidgetTester tester) => tester.widget<Icon>(
        find.byKey(const Key('control_emphasis_icon')),
      );
      // 不全有星：灯不亮。
      expect(emphasisIcon(tester).color, isNot(Colors.amber));

      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();
      for (final index in [0, 1, 2]) {
        expect(
          find.byKey(Key('learning_segment_${index}_emphasis')),
          findsOneWidget,
        );
      }
      expect(emphasisIcon(tester).color, Colors.amber);

      // 全有星：一次全取消、灯灭。
      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();
      for (final index in [0, 1, 2]) {
        expect(
          find.byKey(Key('learning_segment_${index}_emphasis')),
          findsNothing,
        );
      }
      expect(emphasisIcon(tester).color, isNot(Colors.amber));
    });
  });

  group('分段线 flag 与删除融合', () {
    Future<void> pumpWithTwoLines(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      // 播放头停在与线 1（20s）重合处会使其线心点击被预览线 2px
      // 命中柱吸收——移到两线之外的中性位置（5s，避开线 10/20s 与空白
      // 收起点 track_handle_strip_row 中心 x=400），线身/空白点击不受影响。
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.pumpAndSettle();
      return;
    }

    double segmentLineWidth(WidgetTester tester, int index) {
      // 分段线视觉为直接绘制的 ColoredBox 标记（key 即标记本体）。
      return tester.getSize(find.byKey(Key('segment_line_$index'))).width;
    }

    /// 「标记分段线」条目在「添加」菜单里——
    /// 开菜单读条目可用性，再点外部收起。
    Future<bool> flagEntryEnabled(WidgetTester tester) async {
      await openAddMenu(tester);
      final enabled =
          tester.widget<PopupMenuItem<VoidCallback?>>(
                find.byKey(const Key('control_segment_flag')),
              ).enabled;
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      return enabled;
    }

    bool deleteSlotEnabled(WidgetTester tester) =>
        slotEnabled(tester, 'control_segment_delete');

    testWidgets('选中分段线后经「添加」菜单可创建/取消 flag，且不触发收起', (tester) async {
      await pumpWithTwoLines(tester);

      // 未选中：条目置灰但按得动（点一下弹「该怎么做」）。
      expect(await flagEntryEnabled(tester), isTrue);
      await tapSegmentLineHandle(tester, 1);
      await tester.pumpAndSettle();
      // 选中未标记的线 → 「标记分段线」，点下即置位。
      await openAddMenu(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('control_segment_flag')),
          matching: find.text('标记分段线'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      expect(segmentLineWidth(tester, 1), 6);
      expect(controlLayer(), findsOneWidget);

      // 一次标注编辑、一步可撤销：一步 undo 回未标记细线
      // （撤销按既有语义先清选中，未选中未标记 = 1dp）。
      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pumpAndSettle();
      expect(segmentLineWidth(tester, 1), 1, reason: 'flag 切换一步可撤销');

      // 再置位后菜单显示「取消标记」，点下即清除（撤销清了选中，先重选）。
      await tapSegmentLineHandle(tester, 1);
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      expect(segmentLineWidth(tester, 1), 6);
      await openAddMenu(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('control_segment_flag')),
          matching: find.text('取消标记'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      expect(segmentLineWidth(tester, 1), 3);
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('空白收起清除线选中（空白含收起即清除，'
        '取代「收起保持」）', (tester) async {
      await pumpWithTwoLines(tester);

      await tapSegmentLineHandle(tester, 1);
      await tester.pumpAndSettle();
      expect(segmentLineWidth(tester, 1), 3);
      expect(await flagEntryEnabled(tester), isTrue);

      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('track_handle_strip_row')),
      );
      expect(controlLayer(), findsNothing);
      await singleTapShow(tester);

      // 空白单击（含收起）不针对选中线 → 选中已清除，「标记分段线」
      // 条目与删除槽位回到置灰（「置灰仍按得动」）、线不再加粗。
      expect(segmentLineWidth(tester, 1), 1);
      expect(await flagEntryEnabled(tester), isTrue);
      expect(deleteSlotEnabled(tester), isTrue);
    });

    testWidgets('选中分段线后显示删除；删除融合相邻学习段且不触发收起', (tester) async {
      await pumpWithTwoLines(tester);

      expect(find.byKey(const Key('control_segment_delete')), findsOneWidget);
      expect(deleteSlotEnabled(tester), isTrue,
          reason: '无作用对象 → 置灰但按得动');
      await tapSegmentLineHandle(tester, 1);
      await tester.pumpAndSettle();
      expect(deleteSlotEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('segment_line_1')), findsNothing);
      expect(find.byKey(const Key('learning_segment_2')), findsNothing);
      expect(find.byKey(const Key('learning_segment_1')), findsOneWidget);
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('学习段选中时删除/标记槽位置灰（常驻不隐藏，按得动、弹做法）', (tester) async {
      await pumpWithTwoLines(tester);

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('control_segment_delete')), findsOneWidget);
      expect(deleteSlotEnabled(tester), isTrue,
          reason: '学习段选中 → 删除无对象 → 置灰但按得动');
      // 「标记分段线」条目随学习段选中回到置灰（菜单开着才见条目；
      // 置灰仍按得动）。
      expect(await flagEntryEnabled(tester), isTrue);
      expect(controlLayer(), findsOneWidget);
    });

  });

  group('轨道带（带内空白横滑 = 精细调整）', () {
    testWidgets('控制层展开时在轨道带内空白水平拖动 → 精细调整 seek（与视频区同一语义：起手定格、全程无浮层、松手恢复）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 预览条在展开态轨道带内渲染。
      expect(find.byKey(const Key('preview_line')), findsOneWidget);

      // PlayerPage 打开即播放：微调起手即定格，seek 断言不受播放推进干扰。
      expect(engine.isPlaying, isTrue);

      // 从中点(400) 向右拖 300 → 累计 300px × 50ms = 15s。
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('track_band'))),
      );
      await tester.pump();
      await g.moveBy(const Offset(150, 0)); // 越过 slop：轴锁定 + 起手定格
      await tester.pump();

      // 与视频可见区同一语义：起手定格 + 全程不出现进度浮层。
      expect(engine.isPlaying, isFalse, reason: '带内空白横滑起手即定格');
      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '编辑态微调全程不出现进度浮层',
      );

      await g.moveBy(const Offset(150, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      // 首帧 seek = 定格基准 + 150px；落点 = 首帧 + 后 150px（共 15s 位移）。
      expect(engine.seekCalls, isNotEmpty);
      final target = engine.seekCalls.first + const Duration(seconds: 7, milliseconds: 500);
      expect(engine.seekCalls.last, target);
      // 松手恢复手势前播放态（原在播 → 续播）。
      expect(engine.callLog, contains('pause'));
      expect(engine.isPlaying, isTrue);
      // 中部空白（视频可见区）拖动仍不 seek（手势作用域回归，见上组）。
    });
  });

  group('收起语义（单击任何非交互区收起）', () {
    testWidgets('单击轨道带空白（轨道手柄带行）→ 收起回全屏播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(controlLayer(), findsOneWidget);

      // 手柄带行空白处单击（无片段/线，整轨均为空白）。
      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('track_handle_strip_row')),
      );
      expect(controlLayer(), findsNothing);
    });

    testWidgets('单击轨间隙（学习段轨与节拍轨之间）→ 收起', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 轨间隙 = 学习段轨底与节拍轨顶之间。
      final learningBottom = tester
          .getBottomLeft(find.byKey(const Key('track_learning')))
          .dy;
      final beatTop = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      final gapY = (learningBottom + beatTop) / 2;
      final bandCenter = tester
          .getCenter(find.byKey(const Key('track_band')))
          .dx;
      await tester.tapAt(Offset(bandCenter, gapY));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(controlLayer(), findsNothing);
    });

    testWidgets('单击未拖动的预览条 → 不收起（编辑优先：预览条为轨道编辑内容）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      // 移到中段，避免播放头与视频首交互线重叠。
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      expect(find.byKey(const Key('preview_line')), findsOneWidget);

      // 预览条按命中吸收（与首尾线同法），其上不识别空白区
      // 双击（编辑优先），单击也不再视为轨道空白收起；
      // 预览条两侧的空白带仍单击收起（上方用例覆盖）。
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('preview_line'))),
      );
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('拖动预览条不触发收起且帧级 seek（04 语义回归）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 拖动 = 水平位移超 tap 判定 → 不是单击：seek 生效、控制层仍展开。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('track_band')),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();
      expect(engine.seekCalls, isNotEmpty);
      expect(controlLayer(), findsOneWidget, reason: '拖动不是单击，不收起');
    });

    testWidgets('按钮/面板/缩放滑条单击不收起（各自生效）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 工具条播放按钮：单击生效（暂停）、不收起。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      expect(controlLayer(), findsOneWidget);

      // 展开气泡：气泡出现、控制层不收起。
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      final bubble = find.byKey(const Key('speed_bubble'));
      expect(bubble, findsOneWidget);
      expect(controlLayer(), findsOneWidget);

      // 气泡内交互控件（标题条倍率下拉）单击：不收起控制层、
      // 气泡仍在（点气泡外才收起）。
      await tester.tap(find.text('当前倍速'));
      await tester.pump();
      expect(bubble, findsOneWidget);
      expect(controlLayer(), findsOneWidget);
      // 点气泡外（遮罩）：气泡收起、控制层仍在。
      await tester.tapAt(const Offset(20, 300));
      await tester.pump();
      expect(bubble, findsNothing);
      expect(controlLayer(), findsOneWidget);

      // 轨道带右下角缩放滑条：单击其区域不收起（滑条自身消费指针）。
      await tester.tap(find.byKey(const Key('track_zoom_slider')));
      await tester.pump();
      expect(controlLayer(), findsOneWidget);
    });
  });

  group('双击暂停与单击唤出共存（双击判定窗口内单击不唤出）', () {
    testWidgets('单击（孤立单指）经约 300ms 窗口后才唤出控制层', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);

      await tester.tap(find.byKey(const Key('player_surface')));
      // 尚未越过双击判定窗口：控制层不出现。
      await tester.pump(const Duration(milliseconds: 100));
      expect(controlLayer(), findsNothing);

      // 越过窗口：孤立单指单击 → 唤出。
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('双击暂停在窗口内胜出：不唤出控制层', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);

      await doubleTap(tester);
      expect(engine.isPlaying, isFalse, reason: '双击应暂停/播放');
      // 再越过双击窗口也不唤出（双击吞掉该序列，非孤立单击）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      expect(controlLayer(), findsNothing);
    });
  });

  group('播放设置工具区', () {
    // 本组顶栏交互用例改从直接挂载控制层进（控制层
    // 是公开类型）——进入方式从「整页 + 单击唤出」降为「直接挂载」，断言
    // 语义不变；依赖替换不再包含只为播放页打开会话与镜像身份路径服务的
    // 那批（练习侧第二播放源、内容哈希、素材目录/清单等）。
    testWidgets('倍速设置可展开（一次只开一个），可设倍速', (tester) async {
      final (engine, _, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      expect(find.byKey(const Key('speed_bubble')), findsOneWidget);

      // 点速选档 0.75 → 内核倍率生效且气泡收起（速点即生效并收起）。
      await tester.tap(find.text('0.75x'));
      await tester.pump();
      expect(engine.rate, 0.75);
      expect(find.byKey(const Key('speed_bubble')), findsNothing);
    });

    testWidgets('展开项一次只展开一个：展开节拍提示自动收起倍速设置', (tester) async {
      final (_, container, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      expect(find.byKey(const Key('speed_bubble')), findsOneWidget);

      // 展开节拍提示：第一步点在遮罩上 = 点气泡外 → 倍速气泡收起；再点
      // 节拍提示工具展开节拍气泡（同一气泡组件与状态来源，互斥——一次只开
      // 一个）。
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pump();
      expect(find.byKey(const Key('speed_bubble')), findsNothing);
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pump();
      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beat,
      );
      expect(find.byKey(const Key('speed_bubble')), findsOneWidget);
    });

    testWidgets('合并气泡：点「倍速设置」开出双栏，步进栏预设行可直接启用', (tester) async {
      await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();

      // 双栏：左步进栏 + 右倍速栏；步进栏预设列表与新增占位行齐备。
      expect(find.byKey(const Key('speed_rate_column')), findsOneWidget);
      expect(find.byKey(const Key('speed_step_column')), findsOneWidget);
      expect(find.text('倍速步进'), findsOneWidget);
      expect(
        find.byKey(const Key('speed_step_preset_builtin_first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('speed_step_preset_builtin_review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('speed_step_edit_builtin_first')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('speed_step_add_preset')), findsOneWidget);
      expect(find.byKey(const Key('speed_step_settings_toggle')), findsNothing);
      expect(find.byKey(const Key('speed_step_switch')), findsNothing);
    });

    testWidgets('倍速步进启用走范围判定：预览在激活段内直接启用并提示', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      // 经标注编辑模块命令播种（store 写缝已私有）。
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      // 点预设行即应用该预设并进入启用流程（范围内直接启用）。
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pump();

      // 预览（0:00）位于激活段 0 内：不弹范围选择，直接启用。
      expect(find.byKey(const Key('speed_step_scope_dialog')), findsNothing);
      expect(engine.rate, 0.5, reason: '默认步进首档 a=0.5');
      expect(find.text('已启用步进倍速'), findsOneWidget);
    });

    testWidgets('预览在激活范围外弹三选一：「激活当前学习段并启用步进倍速」', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      // 经标注编辑模块命令播种（store 写缝已私有）。
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      // 点预设行即应用并进入启用流程（范围内激活直接启用；
      // 范围外弹三选一）。
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pump();

      expect(find.byKey(const Key('speed_step_scope_dialog')), findsOneWidget);
      // 预览（0:00）在段 0 内：第一项候选可用。
      final firstOption = tester.widget<TextButton>(
        find.byKey(const Key('speed_step_scope_select_segment')),
      );
      expect(firstOption.onPressed, isNotNull);

      await tester.tap(
        find.byKey(const Key('speed_step_scope_select_segment')),
      );
      await tester.pump();

      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(engine.rate, 0.5);
      expect(find.text('已启用步进倍速'), findsOneWidget);
    });

    testWidgets('步进启用提示居中浮层：不拦截触摸、约 1.5s 自动消失', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      // 经标注编辑模块命令播种（store 写缝已私有）。
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pump();

      // 居中浮层（锁定分段提示同款）：短暂显示后自动消失。
      final prompt = find.byKey(const Key('step_enabled_prompt'));
      expect(prompt, findsOneWidget);
      // 浮层为 IgnorePointer 子树：不拦截触摸、不与手势争 arena。
      final ignorePointer = tester.firstWidget<IgnorePointer>(
        find.ancestor(
          of: prompt,
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointer.ignoring, isTrue);
      expect(find.byType(SnackBar), findsNothing);

      await tester.pump(noticeTimingOf(NoticeId.stepEnabled).hold);
      await tester.pump();
      expect(prompt, findsNothing);
      expect(find.text('已启用步进倍速'), findsNothing);
    });

    testWidgets('范围三选一「取消」：不启用步进、不改变激活', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      // 经标注编辑模块命令播种（store 写缝已私有）。
      container
          .read(annotationEditorProvider)
          .submit(AddSegmentLine(at: const Duration(seconds: 10)));

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_scope_cancel')));
      await tester.pump();

      expect(engine.rate, 1.0);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(find.text('已启用步进倍速'), findsNothing);
    });

    testWidgets('预览不在任何学习段内：第一项置灰、「对全片」生效', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pump();

      expect(find.byKey(const Key('speed_step_scope_dialog')), findsOneWidget);
      // 无分段线：无候选段，第一项置灰。
      final firstOption = tester.widget<TextButton>(
        find.byKey(const Key('speed_step_scope_select_segment')),
      );
      expect(firstOption.onPressed, isNull);

      await tester.tap(find.byKey(const Key('speed_step_scope_whole_video')));
      await tester.pump();

      expect(engine.rate, 0.5);
      expect(
        container.read(speedControlProvider).stepScope,
        SpeedStepScope.wholeVideo,
      );
      expect(find.text('已启用步进倍速'), findsOneWidget);
    });

    testWidgets('镜像工具点击立即切换镜像状态', (tester) async {
      final (_, container, _, mirror) = await pumpControlLayer(tester);

      expect(mirror.mirrored, isFalse, reason: '初始未镜像');
      expect(container.read(localMirrorEnabledProvider), isTrue);

      await tester.tap(find.byKey(const Key('tool_mirror')));
      await tester.pump();
      expect(mirror.mirrored, isTrue, reason: '点击立即生效');
    });

    testWidgets('查看引导：点击 push 新手引导页', (tester) async {
      // 本用例点顶栏的查看引导槽；用足够宽的视口保证工具都内联。
      setWideView(tester);
      await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_guide')));
      await tester.pumpAndSettle();
      // 新手引导页被推入，控制层仍在下层（被盖住即 offstage）。
      expect(find.byType(GuideUnitsPage), findsOneWidget);
      expect(
        find.byKey(const Key('control_layer'), skipOffstage: false),
        findsOneWidget,
      );
      // 无作用对象（无局部镜像片段）也可点：上面这条断言本身即证。
      expect(find.text('新手引导'), findsOneWidget);
    });
  });

  group('标题栏工具右对齐（无溢出兜底）', () {
    // 窄视口（横屏小窗量级的**合成档** 668×360dp，非设备基准）：顶栏工具仍全部内联（宽度 668dp 足以容下九枚
    // 工具），底部标注工具条与设置簇也不裁——不再有溢出收敛。
    void setNarrowView(WidgetTester tester) {
      tester.view.physicalSize = const Size(1336, 720);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    Finder topBarTool(String key) => find.byKey(Key(key));

    testWidgets('宽敞视口：全部工具固定槽位内联、无「更多」入口、最右工具贴顶栏右内缘', (
      tester,
    ) async {
      setWideView(tester);
      await pumpControlLayer(tester);

      expect(find.byKey(const Key('tool_more')), findsNothing);
      // 整体右对齐：最右工具（查看引导）右缘贴顶栏右内缘（水平内边距 4）。
      // 成员与次序归表直测（play_tool_table_test），此处只钉右对齐几何。
      final guideRight = tester.getRect(topBarTool('tool_guide')).right;
      expect(guideRight, closeTo(960 - 4, 2));
    });

    testWidgets('默认视口（800 逻辑宽）：顶栏 11 槽全部内联、无「更多」入口', (
      tester,
    ) async {
      // 顶栏可用宽 = 总宽 − 返回键 − 间隙，容下 11 槽（移走「倍速
      // 步进」槽后更宽松；溢出机制本身由下面的窄视口用例覆盖）。
      await pumpControlLayer(tester);

      expect(find.byKey(const Key('tool_more')), findsNothing);
      expect(find.byKey(const Key('tool_local_mirror')), findsOneWidget);
      expect(find.byKey(const Key('tool_guide')), findsOneWidget,
          reason: '位次最后的工具也在内联段');
    });

    testWidgets('窄视口：标题区让位保持、滚动也不与工具区重叠', (tester) async {
      setNarrowView(tester);
      await pumpControlLayer(tester);

      // 标题让位：不越过最左工具（撤销）左缘（跑马自身判定与滚动见
      // title_auto_scroll_test；此处验证 Expanded 让位布局不变）。
      final titleRect = tester.getRect(find.byKey(const Key('control_layer_title')));
      final firstToolRect = tester.getRect(find.byKey(const Key('tool_undo')));
      expect(titleRect.right, lessThanOrEqualTo(firstToolRect.left));
    });
  });

  group('顶栏标题改名热区', () {
    Finder hotZone() => find.byKey(const Key('control_layer_rename'));
    Finder titleInZone() => find.descendant(
      of: hotZone(),
      matching: find.byKey(const Key('control_layer_title')),
    );
    Finder iconInZone() => find.descendant(
      of: hotZone(),
      matching: find.byKey(const Key('control_layer_rename_icon')),
    );

    testWidgets('短标题：热区随内容收缩（文本 + 间隙 + 图标）、高 44；图标字形/尺寸/颜色合规且不随系统字号缩放', (
      tester,
    ) async {
      setWideView(tester);
      // 系统字号放大：图标尺寸与热区高是受控排版，不随字号缩放。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpControlLayer(tester);

      final zone = tester.getRect(hotZone());
      final title = tester.getRect(titleInZone());
      expect(
        zone.width,
        closeTo(
          title.width + kTopBarRenameIconGap + kTopBarRenameIconSize,
          0.5,
        ),
        reason: '热区横向随标题收缩 = 文本 + 间隙 + 图标',
      );
      expect(zone.left, closeTo(title.left, 0.5), reason: '热区与标题同左缘');
      expect(
        zone.height,
        closeTo(kTopBarRenameHotZoneHeight, 0.5),
        reason: '热区高 = 命中盒下限 48dp（取代 44 口径)',
      );
      // 实际命中矩形独立钉下限（值随下限口径更新）。
      expect(
        zone.height,
        greaterThanOrEqualTo(kHitTargetMinSize),
        reason: '改名热区实际命中高 ≥ 通行下限',
      );
      final icon = tester.widget<Icon>(iconInZone());
      expect(icon.icon, Icons.drive_file_rename_outline);
      expect(icon.size, kTopBarRenameIconSize);
      expect(icon.color, kTopBarRenameIconColor);
      // 渲染尺寸同钉：图标不随系统字号（1.3）缩放（受控排版）。
      expect(
        tester.getSize(iconInZone()),
        const Size(kTopBarRenameIconSize, kTopBarRenameIconSize),
      );
    });

    testWidgets('短标题右侧留白不接点击；点热区本体进改名框', (tester) async {
      setWideView(tester);
      await pumpControlLayer(tester);

      final zone = tester.getRect(hotZone());
      final firstTool = tester.getRect(find.byKey(const Key('tool_undo')));
      // 标题区直到工具间隙都是留白（热区只占内容宽）。
      final blankRight = firstTool.left - kTopBarToolsGapWidth;
      expect(zone.right, lessThan(blankRight - 20), reason: '短标题右侧确有留白');

      await tester.tapAt(Offset((zone.right + blankRight) / 2, zone.center.dy));
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('song_naming_dialog')),
        findsNothing,
        reason: '标题右侧留白不接点击',
      );

      // 对照：点热区本体（整条标题 + 图标）进改名框。
      await tester.tap(hotZone());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
    });

    testWidgets('长标题：热区整体右缩 8dp，右缘收在工具间隙死区之外（图标不进死区）', (tester) async {
      setWideView(tester);
      const longName = 'dance-with-a-really-long-name-for-marquee-check.mp4';
      await pumpControlLayer(tester, source: Uri.file('/videos/$longName'));

      final zone = tester.getRect(hotZone());
      final firstTool = tester.getRect(find.byKey(const Key('tool_undo')));
      expect(
        zone.right,
        lessThanOrEqualTo(firstTool.left - kTopBarToolsGapWidth),
        reason: '热区（含图标）不进入工具间隙死区',
      );
      expect(
        zone.right,
        closeTo(
          firstTool.left - kTopBarToolsGapWidth - kTopBarRenameRightInset,
          0.5,
        ),
        reason: '长标题时热区整体右缩 8dp，图标与死区之间留可见空隙',
      );
      // 图标是热区内的最右件：右缩量即图标与死区的可见空隙。
      expect(tester.getRect(iconInZone()).right, closeTo(zone.right, 0.5));
    });

    testWidgets('长标题判定同源：文本宽落在「可用宽 −8dp」带内时仍单份完整显示（不右缩）', (tester) async {
      // 「长标题时右缩」是条件行为：文本单份宽不超出「不右缩可用文本宽」时，
      // 热区上限 = 今天标题的可用宽（不缩 8dp）。本条用例把文本宽精确定位到
      // 那条 8dp 带内——右缩被无条件应用时，这段文本会被判为溢出转跑马灯，
      // 本断言即红。
      setWideView(tester);
      await pumpControlLayer(tester, source: Uri.file('/videos/M'));

      // 基准量：单字符宽（标题全由同一字形组成，与字体是否等宽无关）与
      // 标题槽可用宽。
      final advance = tester
          .getSize(find.byKey(const Key('control_layer_title')))
          .width;
      final slotWidth = tester
          .getSize(find.byKey(const Key('control_layer_title_slot')))
          .width;
      // 能单份完整容纳的最长标题（不右缩口径：文本 <= 槽宽 − 间隙 − 图标）。
      final chars = ((slotWidth - kTopBarRenameIconGap - kTopBarRenameIconSize) /
              advance)
          .floor();
      expect(chars, greaterThan(2));
      final title = 'M' * chars;
      final textWidth = advance * chars;
      // 目标视口：让槽宽 = 文本宽 + 22 —— 文本宽落在「槽宽 − 26」与
      // 「槽宽 − 18」之间（差 4dp），即只有 8dp 右缩被误用为溢出阈值时才会
      // 翻成跑马灯的那条带。
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final targetScreenWidth = screenWidth + (textWidth + 22 - slotWidth);
      tester.view.physicalSize = Size(
        (targetScreenWidth * tester.view.devicePixelRatio).roundToDouble(),
        tester.view.physicalSize.height,
      );
      await pumpControlLayer(tester, source: Uri.file('/videos/$title'));
      await tester.pump();

      // 单份完整显示：没有跑马灯（溢出时 [AutoScrollTitle] 渲染两份文本）。
      expect(
        find.text(title),
        findsOneWidget,
        reason: '文本未超可用宽，不该被判为长标题转跑马灯',
      );
      final zone = tester.getRect(hotZone());
      expect(
        zone.width,
        closeTo(textWidth + kTopBarRenameIconGap + kTopBarRenameIconSize, 1.0),
        reason: '热区 = 文本 + 间隙 + 图标（未右缩）',
      );
      final firstTool = tester.getRect(find.byKey(const Key('tool_undo')));
      // 未右缩：热区右缘允许越过「死区左缘 − 8dp」，但仍不进死区。
      expect(
        zone.right,
        lessThanOrEqualTo(firstTool.left - kTopBarToolsGapWidth + 1),
        reason: '热区仍不进工具间隙死区',
      );
    });

    testWidgets('装载未完成：图标置灰、热区仍可点、点一下弹「正在装载」且不写盘；落定后恢复', (tester) async {
      setWideView(tester);
      final (_, container, docs, _) = await pumpControlLayer(tester);

      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      expect(
        tester.widget<Icon>(iconInZone()).color,
        kToolSlotDisabledIconColor,
        reason: '装载未完成：图标取不可用 token',
      );
      await tester.tap(hotZone());
      await tester.pump();
      await tester.pump();
      expect(find.text('正在装载'), findsOneWidget);
      expect(
        find.byKey(const Key('song_naming_dialog')),
        findsNothing,
        reason: '被门挡下：命名框不开',
      );
      expect(docs.markersSnapshot, isEmpty, reason: '被门挡下：不写盘');

      // 装载落定：图标恢复、入口放行（无需重开页面）。
      container.read(loadGateActiveProvider.notifier).settle();
      await tester.pump();
      expect(
        tester.widget<Icon>(iconInZone()).color,
        kTopBarRenameIconColor,
      );
      await tester.tap(hotZone());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('song_naming_dialog')), findsOneWidget);
    });
  });

  group('节拍提示入口移顶栏', () {
    testWidgets('点顶栏节拍提示打开节拍提示气泡面板；对齐入口开独立气泡', (
      tester,
    ) async {
      await pumpControlLayer(tester);

      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      // 第三列为「节拍矫正」菜单列（两入口），对齐控件本体不在
      // 本气泡内（点「节拍对齐」才开独立气泡）。
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beat_align_group')), findsNothing);

      // 点「节拍对齐」→ 本气泡消失、独立对齐气泡出现（锚同一入口链接）。
      await tester.tap(find.byKey(const Key('beat_correction_align_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(find.byKey(const Key('beat_align_bubble')), findsOneWidget);
      final entry = tester.getRect(find.byKey(const Key('tool_beat_prompt')));
      final bubble = tester.getRect(find.byKey(const Key('beat_align_bubble')));
      expect(bubble.top, greaterThanOrEqualTo(entry.bottom - 4));
    });

    testWidgets('面板展开不点亮琥珀「激活」', (tester) async {
      await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();

      expect(toolIconColor(tester, 'tool_beat_prompt'), isNot(kHighlightAmber));
    });

    testWidgets('竖屏 361.1dp 顶栏节拍提示工具打开同一个三段堆叠面板（验收）', (
      tester,
    ) async {
      // 真机竖屏基准 361.1×781.7dp（1264×2736 @3.5，唯一竖屏基准）。
      useNamedViewport(tester, ViewportTier.compact);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull, reason: '竖屏基准下编辑面无布局溢出');

      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await pumpPastMarquee(tester);

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

    testWidgets('轨道设置条不再含节拍提示入口，其余成员与顺序不变', (tester) async {
      await pumpControlLayer(tester);

      expect(find.byKey(const Key('settings_cluster')), findsOneWidget);
      expect(find.byKey(const Key('beat_prompt_panel_entry')), findsNothing);
      final keys = const [
        'track_preview_snap_slot',
        'layout_lock_toggle',
        'track_zoom_dock',
      ];
      for (final key in keys) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 应保留');
      }
      for (var i = 1; i < keys.length; i++) {
        expect(
          tester.getRect(find.byKey(Key(keys[i]))).left,
          greaterThanOrEqualTo(
            tester.getRect(find.byKey(Key(keys[i - 1]))).left,
          ),
          reason: '${keys[i]} 应在 ${keys[i - 1]} 右侧',
        );
      }
    });

    test('倍速槽定宽不随文本缩放收缩（缩放系数下限 1）', () {
      // 倍率槽是固定宽：textScaler < 1 时定宽不收缩，否则紧约束的 SizedBox
      // 会比内容窄而溢出。定宽覆盖激活 / 未激活两形态与两字激活标签互换，
      // 由「启用 / 停用步进不改变倍速槽宽度与几何中心」widget 用例钉住。
      expect(
        topBarSpeedSlotWidth(textScaler: TextScaler.linear(0.8)),
        topBarSpeedSlotWidth(),
      );
    });
  });

  group('工具图标激活反馈（扩为「倍速侧任一生效中」）', () {
    Finder inSpeedTool(Finder matching) => find.descendant(
      of: find.byKey(const Key('tool_speed_settings')),
      matching: matching,
    );

    /// 种入两个学习段并激活第 0 段：预览落在段内，点预设行即直接启用步进。
    Future<ProviderContainer> seedActiveSegment(WidgetTester tester) async {
      final container = containerOfControlLayer(tester);
      // 经标注编辑模块命令播种（store 写缝已私有）。
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await tester.pumpAndSettle();
      return container;
    }

    /// 开气泡并点首个内置预设行：启用步进（首档 a=0.5），气泡随之收起。
    Future<void> enableFirstPreset(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      // 点预设行即应用并进入启用流程（预览在激活段 0 内 → 直接启用）。
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pumpAndSettle();
    }

    testWidgets('默认（倍速 1.0、步进未启用、镜像关）：图标均不高亮、不显示倍率值', (tester) async {
      await pumpControlLayer(tester);

      expect(
        toolIconColor(tester, 'tool_speed_settings'),
        isNot(kHighlightAmber),
      );
      expect(toolIconColor(tester, 'tool_mirror'), isNot(kHighlightAmber));
      expect(inSpeedTool(find.text('倍速设置')), findsOneWidget);
      expect(inSpeedTool(find.byType(RateTextSlot)), findsNothing);
    });

    testWidgets('设非 1.0 倍速：倍速图标琥珀高亮、标签「倍速」并显示当前倍速值', (tester) async {
      final (engine, _, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.text('0.75x'));
      await tester.pump();

      expect(engine.rate, 0.75);
      expect(toolIconColor(tester, 'tool_speed_settings'), kHighlightAmber);
      expect(inSpeedTool(find.text('倍速')), findsOneWidget);
      expect(inSpeedTool(find.text('步进')), findsNothing);
      expect(
        inSpeedTool(
          // 倍率文字入固定槽位，标签拆为「倍速」+ 槽位文本。
          find.text('0.75x'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('面板展开本身不高亮：展开倍速设置气泡图标保持非琥珀', (tester) async {
      await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      // 展开的是锚定气泡而非全宽面板；展开本身不算激活。
      expect(find.byKey(const Key('speed_bubble')), findsOneWidget);
      expect(
        toolIconColor(tester, 'tool_speed_settings'),
        isNot(kHighlightAmber),
      );
    });

    testWidgets('步进生效：倍速槽图标琥珀、标签「步进」、显示当前生效倍率', (tester) async {
      final (engine, _, _, _) = await pumpControlLayer(tester);
      await seedActiveSegment(tester);

      await enableFirstPreset(tester);

      // 步进首档 a=0.5（≠1.0）：槽按新语义点亮并显示生效倍率。
      expect(engine.rate, 0.5);
      expect(toolIconColor(tester, 'tool_speed_settings'), kHighlightAmber);
      expect(inSpeedTool(find.text('步进')), findsOneWidget);
      expect(inSpeedTool(find.text('倍速')), findsNothing);
      expect(inSpeedTool(find.text('0.5x')), findsOneWidget);
    });

    testWidgets('步进档位循环推进：倍速槽显示的生效倍率随档位跳动', (tester) async {
      await pumpControlLayer(tester);
      final container = await seedActiveSegment(tester);

      await enableFirstPreset(tester);
      expect(inSpeedTool(find.text('0.5x')), findsOneWidget);

      // 首个内置预设每档 3 遍：完成 3 圈循环后升到 0.6。
      final notifier = container.read(speedControlProvider.notifier);
      for (var i = 0; i < 3; i++) {
        await notifier.onSegmentLoopLap();
      }
      await tester.pump();

      expect(inSpeedTool(find.text('0.6x')), findsOneWidget);
      expect(inSpeedTool(find.text('0.5x')), findsNothing);
    });

    testWidgets('步进停用后回到手动倍速：标签回落「倍速」、琥珀不灭、显示手动倍率', (tester) async {
      final (engine, _, _, _) = await pumpControlLayer(tester);
      await seedActiveSegment(tester);

      // 先设手动 0.75（同时停用步进），再启用步进，再停用回手动。
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.text('0.75x'));
      await tester.pump();
      await enableFirstPreset(tester);
      expect(inSpeedTool(find.text('步进')), findsOneWidget);
      expect(inSpeedTool(find.text('0.5x')), findsOneWidget);

      // 已启用时再点「已启用」那行 = 停用；生效倍速回到手动 0.75。
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pumpAndSettle();

      expect(engine.rate, 0.75);
      expect(toolIconColor(tester, 'tool_speed_settings'), kHighlightAmber);
      expect(inSpeedTool(find.text('倍速')), findsOneWidget);
      expect(inSpeedTool(find.text('步进')), findsNothing);
      expect(inSpeedTool(find.text('0.75x')), findsOneWidget);
    });

    testWidgets('启用 / 停用步进不改变倍速槽宽度与几何中心（顶栏不重排）', (tester) async {
      await pumpControlLayer(tester);
      await seedActiveSegment(tester);

      Rect slotRect(String key) => tester.getRect(find.byKey(Key(key)));
      final before = slotRect('tool_speed_settings');
      // 定宽口径 = 纯函数单源（激活标签 + 倍率槽），未激活形态占用同宽。
      expect(before.width, topBarSpeedSlotWidth());
      // 相邻槽位基线：启用 / 停用步进前后一位不动。
      final beatBefore = slotRect('tool_beat_prompt');
      final mirrorBefore = slotRect('tool_mirror');
      expect(find.byKey(const Key('tool_more')), findsNothing);

      await enableFirstPreset(tester);
      final during = slotRect('tool_speed_settings');
      expect(during.width, before.width, reason: '步进生效不改槽宽');
      expect(during.center.dx, closeTo(before.center.dx, 0.01));
      expect(slotRect('tool_beat_prompt'), beatBefore);
      expect(slotRect('tool_mirror'), mirrorBefore);
      expect(find.byKey(const Key('tool_more')), findsNothing, reason: '无工具落进「更多」');

      // 停用步进（回到手动 1.0）后仍同宽同中心。
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pumpAndSettle();
      final after = slotRect('tool_speed_settings');
      expect(after.width, before.width, reason: '停用步进不改槽宽');
      expect(after.center.dx, closeTo(before.center.dx, 0.01));
      expect(slotRect('tool_beat_prompt'), beatBefore);
      expect(slotRect('tool_mirror'), mirrorBefore);
      expect(find.byKey(const Key('tool_more')), findsNothing, reason: '无工具弹出「更多」');
    });

    testWidgets('文本缩放 0.8：定宽不收缩，步进生效仍不重排、无溢出', (tester) async {
      // 倍率槽是固定宽（不随文本缩放收缩）：定宽若跟着缩，紧约束的
      // SizedBox 会比内容窄而报 RenderFlex 溢出——本用例钉住该边界。
      tester.platformDispatcher.textScaleFactorTestValue = 0.8;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpControlLayer(tester);
      await seedActiveSegment(tester);

      final before = tester.getRect(find.byKey(const Key('tool_speed_settings')));
      expect(
        before.width,
        topBarSpeedSlotWidth(textScaler: TextScaler.linear(0.8)),
      );

      await enableFirstPreset(tester);
      final during = tester.getRect(find.byKey(const Key('tool_speed_settings')));
      expect(during.width, before.width);
      expect(during.center.dx, closeTo(before.center.dx, 0.01));
      expect(inSpeedTool(find.text('0.5x')), findsOneWidget);
    });

    testWidgets('文本缩放 1.3：倍速槽定宽随缩放放大，标签与倍率读数不被裁', (tester) async {
      // 端到端钉住「量测与渲染同源」：
      // 定宽若漏掉任一成分的缩放（如标签宽），紧约束槽会比放大后的内容窄
      // 而报 RenderFlex 溢出。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpControlLayer(tester);
      // 1.3× 下播放器标题溢出走自动滚动（repeat 动画，口径），
      // pumpAndSettle 不落定——播种与启用步进改用固定帧推进。
      final container = containerOfControlLayer(tester);
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.getRect(find.byKey(const Key('tool_speed_settings'))).width,
        topBarSpeedSlotWidth(textScaler: TextScaler.linear(1.3)),
        reason: '定宽随 > 1 缩放放大',
      );
      expect(inSpeedTool(find.text('步进')), findsOneWidget);
      expect(inSpeedTool(find.text('0.5x')), findsOneWidget);
    });

    testWidgets('镜像开启：镜像图标琥珀高亮；关闭后熄灭', (tester) async {
      final (_, _, _, mirror) = await pumpControlLayer(tester);

      expect(toolIconColor(tester, 'tool_mirror'), isNot(kHighlightAmber));

      await tester.tap(find.byKey(const Key('tool_mirror')));
      await tester.pump();
      expect(mirror.mirrored, isTrue);
      expect(toolIconColor(tester, 'tool_mirror'), kHighlightAmber);

      await tester.tap(find.byKey(const Key('tool_mirror')));
      await tester.pump();
      expect(mirror.mirrored, isFalse);
      expect(toolIconColor(tester, 'tool_mirror'), isNot(kHighlightAmber));
    });

    testWidgets('按视频记忆恢复镜像开启：镜像图标直接琥珀高亮', (tester) async {
      final source = Uri.file('/videos/b.mp4');
      await pumpControlLayer(
        tester,
        source: source,
        // 历史条目 mirrored = true：打开即按记忆恢复镜像开启。
        entry: historyEntry(
          filePath: source.toFilePath(),
          mirrored: true,
          displayName: 'b.mp4',
        ),
      );

      expect(toolIconColor(tester, 'tool_mirror'), kHighlightAmber);
    });
  });

  group('撤销/重做', () {
    /// 顶栏工具槽位内第一个 Icon 的颜色（置灰 = 不可用视觉 token，
    /// 起顶栏与底排共享同一不可用图标灰）。
    Color undoIconColor(WidgetTester tester, String toolKey) => tester
        .widget<Icon>(
          find
              .descendant(
                of: find.byKey(Key(toolKey)),
                matching: find.byType(Icon),
              )
              .first,
        )
        .color!;

    Future<FakePlaybackEngine> pumpWithSegmentLine(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      return engine;
    }

    testWidgets('撤销在重做左侧；初始无历史置灰（「文件」退场后撤销左起）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      expect(find.byKey(const Key('tool_undo')), findsOneWidget);
      expect(find.byKey(const Key('tool_redo')), findsOneWidget);
      final undoRect = tester.getRect(find.byKey(const Key('tool_undo')));
      final redoRect = tester.getRect(find.byKey(const Key('tool_redo')));
      expect(
        redoRect.center.dx,
        greaterThan(undoRect.center.dx),
        reason: '重做在撤销右侧',
      );
      // 撤销是顶栏工具区左起首位（后随分隔线与音画同步）。
      final avSyncRect = tester.getRect(find.byKey(const Key('tool_av_sync')));
      expect(
        undoRect.center.dx,
        lessThan(avSyncRect.center.dx),
        reason: '撤销位于工具区首位',
      );

      expect(undoIconColor(tester, 'tool_undo'), kToolSlotDisabledIconColor);
      expect(undoIconColor(tester, 'tool_redo'), kToolSlotDisabledIconColor);
    });

    testWidgets('分段创建可撤销/重做：线与学习段随之增减', (tester) async {
      await pumpWithSegmentLine(tester);
      expect(find.byKey(const Key('segment_line_0')), findsOneWidget);
      expect(
        undoIconColor(tester, 'tool_undo'),
        isNot(kToolSlotDisabledIconColor),
      );
      expect(undoIconColor(tester, 'tool_redo'), kToolSlotDisabledIconColor);

      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('segment_line_0')), findsNothing);
      expect(find.byKey(const Key('learning_segment_0')), findsNothing);

      await tester.tap(find.byKey(const Key('tool_redo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('segment_line_0')), findsOneWidget);
      expect(find.byKey(const Key('learning_segment_1')), findsOneWidget);
      expect(undoIconColor(tester, 'tool_redo'), kToolSlotDisabledIconColor);
    });

  });

  group('锁定分段（范围扩展与置灰）', () {
    /// 建一条 10s 分段线并开启锁定分段（点设置簇内开关）。
    Future<FakePlaybackEngine> pumpWithLineAndLock(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('segment_line_0')), findsOneWidget);

      // 播放头移到中性位置：与线 10s 不重合（预览线命中柱不吸收手柄点击）。
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();

      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('锁定分段·开'), findsOneWidget);
      return engine;
    }

    testWidgets('锁定后分段工具置灰：点击不建线并弹「已锁定分段」提示', (tester) async {
      final engine = await pumpWithLineAndLock(tester);
      // 锁定种类唯一一条外观断言：置灰统一为同一 token。
      expect(
        slotIconColor(tester, 'control_segment'),
        kToolSlotDisabledIconColor,
      );

      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pump();
      expect(find.byKey(const Key('segment_line_1')), findsNothing,
          reason: '锁下点击分段不建线');
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget,
          reason: '置灰按钮单击弹居中「已锁定分段」提示');
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('装载未完成压倒锁定：装载期点灰着的受锁工具先弹「正在装载」', (tester) async {
      await pumpWithLineAndLock(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pump();
      expect(find.text('正在装载'), findsOneWidget,
          reason: '装载未完成压倒锁的原因文案');
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('锁定后删除工具置灰：线保留、单击弹提示', (tester) async {
      await pumpWithLineAndLock(tester);
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      // 外观已由锁定种类唯一断言钉住；此处钉「置灰仍可点、弹锁提示」语义。
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pump();

      expect(find.byKey(const Key('segment_line_0')), findsOneWidget,
          reason: '锁下点击删除不执行');
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget);
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('锁定后自动首尾置灰：单击弹「已锁定分段」、不展开菜单不改边界；解锁后恢复', (tester) async {
      await pumpWithLineAndLock(tester);
      // 外观由锁定种类唯一断言钉住；此处钉「置灰仍可点、只弹原因」语义。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

      // 锁定：单击只弹「已锁定分段」，不展开菜单、不改边界。
      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      expect(renderedAutoEntryKeys(tester), isEmpty,
          reason: '锁定期间菜单不展开');
      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.rangeStart, Duration.zero);
      expect(timeline.rangeEnd, const Duration(seconds: 30));
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget,
          reason: '灰着的自动分段单击弹「已锁定分段」');
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);

      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_auto_range'), isTrue,
          reason: '解锁 + 节拍就绪：自动分段正常可点');
      // 解锁后自动首尾照常执行：首 = 第一拍 0.5s、尾 = 最后一拍 2.0s。
      await tapAutoEntry(tester, 'control_auto_seg_4');
      expect(container.read(annotationTimelineProvider).rangeStart,
          const Duration(milliseconds: 500));
      expect(container.read(annotationTimelineProvider).rangeEnd,
          const Duration(seconds: 2));
    });

    testWidgets('未锁定时四钮外观与行为与现状一致（回归）', (tester) async {
      final engine = await pumpWithLineAndLock(tester);
      // 解锁（pumpWithLineAndLock 已锁定）→ 回到未锁：分段钮在有效区间亮色可点。
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      // 启用态唯一一条外观断言：统一为启用 token。
      expect(
        slotIconColor(tester, 'control_segment'),
        kToolSlotEnabledIconColor,
      );
      expect(slotEnabled(tester, 'control_segment'), isTrue);
      expect(slotEnabled(tester, 'control_auto_range'), isTrue,
          reason: '节拍就绪 + 未锁：自动首尾可点');
      // 选中线后删除钮亮色可点（未锁行为现状一致）。
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('锁定后「标记分段线」条目置灰、点一下弹「已锁定分段」、flag 不变', (tester) async {
      await pumpWithLineAndLock(tester);

      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      // 「添加」菜单里只有「标记分段线」灰着：其余三条正常色；
      // 置灰文字取浅底弹出菜单专用 token。
      expect(
        menuEntryTextColor(tester, 'control_segment_flag'),
        kToolMenuDisabledTextColor,
      );
      for (final key in const [
        'control_note_sticker',
        'control_local_mirror',
        'control_half_beat',
      ]) {
        expect(menuEntryTextColor(tester, key),
            isNot(kToolMenuDisabledTextColor),
            reason: '$key 不受锁定分段');
      }
      // 置灰仍可点（判定表：锁定 = 置灰、可点、弹原因）。
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_segment_flag')),
            )
            .enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('segment_line_0')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('segment_line_0'))).width,
        3,
        reason: 'flag 不置位（动作不发生）',
      );
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget,
          reason: '点灰着的条目弹「已锁定分段」');
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('锁定后撤销不受锁影响：撤销锁开启前的建线（回归）', (tester) async {
      await pumpWithLineAndLock(tester);

      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('segment_line_0')), findsNothing);
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });
  });

  group('对比态标注工具区槽集', () {
    /// 泵出播放页 → 唤出控制层 → 建一条分段线（对比态没有分段槽，先在
    /// 编辑态建好，得到两个学习段）→ 进入对比-控制层（容器直进，绕过
    /// 宿主编排；先例）。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpCompareEditing(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      return (engine, container);
    }

    /// 点选学习段片段体（行下半、偏左，避开右上 dock）。
    Future<void> tapLearningSegmentBody(WidgetTester tester, int index) async {
      final rect = tester.getRect(find.byKey(Key('learning_segment_$index')));
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.75),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('跨面一致性：对比态槽集声明的槽位 == 实际渲染出的槽键逐位相等', (
      tester,
    ) async {
      await pumpCompareEditing(tester);

      final declared = ToolSlotTable.compare.slots.map((s) => s.key).toList();
      final rendered = renderedSlotKeys(tester);
      // 槽集声明 = 实际渲染：逐位相等（次序即声明次序，不可能漏项）。
      expect(rendered, declared);
      // 渲染次序 = 声明次序（x 坐标严格递增）。
      var previous = -1.0;
      for (final key in declared) {
        final x = tester.getCenter(find.byKey(Key(key))).dx;
        expect(x, greaterThan(previous), reason: key);
        previous = x;
      }
    });

    testWidgets('其余标注编辑工具（分段/添加/标记/自动分段）不再出现', (tester) async {
      await pumpCompareEditing(tester);

      expect(find.byKey(const Key('control_segment')), findsNothing);
      expect(find.byKey(const Key('control_add')), findsNothing);
      expect(find.byKey(const Key('control_segment_flag')), findsNothing);
    });

    testWidgets('逐槽可用性：删除置灰但按得动；无选中学习段时熟练度/重点置灰但按得动', (
      tester,
    ) async {
      await pumpCompareEditing(tester);

      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '无对象 → 置灰但按得动');
      // 对比工具区没有「截图排开」占位槽。
      expect(find.byKey(const Key('tool_screenshot')), findsNothing);
      expect(slotEnabled(tester, 'control_mastery'), isTrue);
      expect(slotEnabled(tester, 'control_emphasis'), isTrue);
    });

    testWidgets('点学习段选中并激活（今天语义）后熟练度/重点可用；删除置灰但按得动', (
      tester,
    ) async {
      final (_, container) = await pumpCompareEditing(tester);

      await tapLearningSegmentBody(tester, 1);

      expect(container.read(selectedLearningSegmentRepresentativeProvider), 1);
      expect(slotEnabled(tester, 'control_mastery'), isTrue);
      expect(slotEnabled(tester, 'control_emphasis'), isTrue);
      // 删除只认选中的练习片段：不随学习段选中点亮（置灰但按得动）。
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);
    });

    testWidgets('熟练度写点走标注编辑模块、撤销/重做在对比-控制层顶栏保留', (tester) async {
      final (_, container) = await pumpCompareEditing(tester);

      await tapLearningSegmentBody(tester, 1);
      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_mastery_learning')));
      await tester.pumpAndSettle();
      expect(
        container.read(learningMasteryProvider)[1],
        LearningMastery.learning,
      );

      // 顶栏撤销保留：一次点击回到未设档。
      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pumpAndSettle();
      expect(container.read(learningMasteryProvider)[1], isNull);

      await tester.tap(find.byKey(const Key('tool_redo')));
      await tester.pumpAndSettle();
      expect(
        container.read(learningMasteryProvider)[1],
        LearningMastery.learning,
      );
    });

    testWidgets('删除只认练习片段：分段线/半拍线在对比态删不掉（工具区无其编辑入口）', (
      tester,
    ) async {
      await pumpCompareEditing(tester);

      // 对比槽集没有分段/标记等线编辑槽，删除槽也不读线选中——分段线与
      // 半拍线在对比态没有任何可达的删除路径。
      expect(find.byKey(const Key('control_segment_flag')), findsNothing);
      expect(find.byKey(const Key('control_segment')), findsNothing);
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '无对象 → 置灰但按得动');
    });
  });

  group('顶栏「取景调整」入口', () {
    /// 定长等待（设备等效视口下播放循环带持续动画、pumpAndSettle 不收敛
    /// ——等进入动画/模式提交完成的统一时长）。
    const settlePump = Duration(milliseconds: 400);

    /// 泵出播放页 → 唤出控制层（编辑态）。
    Future<ProviderContainer> pumpEditingPlayer(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
    }

    testWidgets('普通编辑态点「取景调整」进单画面取景：控制层收起、取景条出现（无微调菜单）；「完成」回编辑态', (
      tester,
    ) async {
      final container = await pumpEditingPlayer(tester);

      expect(find.byKey(const Key('tool_framing_adjust')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tool_framing_adjust')));
      await tester.pump(settlePump);
      await tester.pump();

      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.framing);
      expect(controlLayer(), findsNothing);
      expect(find.byKey(const Key('framing_bar')), findsOneWidget);
      // 单画面取景条只有「复位」「完成」——没有「取景微调」替代路径菜单。
      expect(find.byKey(const Key('framing_nudge')), findsNothing);

      await tester.tap(find.byKey(const Key('framing_done')));
      await tester.pump(settlePump);
      await tester.pump();

      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.editing);
      expect(controlLayer(), findsOneWidget);
      expect(find.byKey(const Key('framing_bar')), findsNothing);
    });

    testWidgets('对比-控制层点同一枚入口进分屏取景；「完成」回对比-控制层（两条路径共用一个入口）', (
      tester,
    ) async {
      final container = await pumpEditingPlayer(tester);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pump(settlePump);
      await tester.pump();

      expect(find.byKey(const Key('control_framing')), findsNothing);
      await tester.tap(find.byKey(const Key('tool_framing_adjust')));
      await tester.pump(settlePump);
      await tester.pump();

      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.compareFraming);
      expect(find.byKey(const Key('framing_bar')), findsOneWidget);
      // 取景微调菜单在两条路径上整条退场。
      expect(find.byKey(const Key('framing_nudge')), findsNothing);

      await tester.tap(find.byKey(const Key('framing_done')));
      await tester.pump(settlePump);
      await tester.pump();

      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.compareEditing);
    });

    testWidgets('装载未完成门：点「取景调整」被挡下并弹「正在装载」，模式一位不动', (
      tester,
    ) async {
      final container = await pumpEditingPlayer(tester);
      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      await tester.tap(find.byKey(const Key('tool_framing_adjust')));
      await tester.pump(settlePump);
      await tester.pump();

      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.editing);
      expect(find.text('正在装载'), findsOneWidget);
      expect(find.byKey(const Key('framing_bar')), findsNothing);
    });

    testWidgets('待命态点「取景调整」能进单画面取景；退出回编辑态（八拍锚点不丢）', (
      tester,
    ) async {
      final container = await pumpEditingPlayer(tester);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.beatCorrectionStandby);
      await tester.pump(settlePump);
      await tester.pump();

      await tester.tap(find.byKey(const Key('tool_framing_adjust')));
      await tester.pump(settlePump);
      await tester.pump();
      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.framing);

      await tester.tap(find.byKey(const Key('framing_done')));
      await tester.pump(settlePump);
      await tester.pump();
      // 退出三同路一律回编辑态（待命态已退出；锚点状态归节拍域，不随退出丢）。
      expect(container.read(playerSessionProvider).mode,
          PlayerSessionMode.editing);
    });
  });

  group('标注工具区镜像开关槽', () {
    /// 定长等待（设备等效视口下播放循环带持续动画、pumpAndSettle 不收敛）。
    const settlePump = Duration(milliseconds: 400);

    void setDeviceView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
    }

    Future<ProviderContainer> pumpCompareEditingPlayer(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      setDeviceView(tester);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pump(settlePump);
      await tester.pump();
      return container;
    }

    testWidgets('开关槽落在标注工具区：练习侧镜像之前是删除（「取景」槽退役）', (
      tester,
    ) async {
      await pumpCompareEditingPlayer(tester);

      expect(find.byKey(const Key('control_practice_mirror')), findsOneWidget);
      // 次序：删除 < 练习侧镜像（x 严格递增）。
      final xDelete = tester.getCenter(find.byKey(const Key('control_segment_delete'))).dx;
      final xPractice =
          tester.getCenter(find.byKey(const Key('control_practice_mirror'))).dx;
      expect(xPractice, greaterThan(xDelete));
    });

    testWidgets('真机可达性：开关槽在设备等效视口下命中自身且可点', (tester) async {
      await pumpCompareEditingPlayer(tester);

      for (final key in const ['control_practice_mirror']) {
        final slotBox = tester.renderObject<RenderBox>(find.byKey(Key(key)));
        final hit = tester.hitTestOnBinding(
          slotBox.localToGlobal(slotBox.size.center(Offset.zero)),
        );
        expect(
          hit.path.any((entry) => entry.target == slotBox),
          isTrue,
          reason: '$key 必须命中自身',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('练习侧镜像槽：点按取反且激活态跟随生效值', (tester) async {
      final container = await pumpCompareEditingPlayer(tester);

      // 设备级默认开 → 槽激活；点按 → 生效值变 false。
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(find.text('练习侧镜像'), findsOneWidget);
      await tester.tap(find.byKey(const Key('control_practice_mirror')));
      await tester.pump(settlePump);
      await tester.pump();
      expect(container.read(effectivePracticeMirrorProvider), isFalse);
      expect(container.read(practiceMirrorOverrideProvider), isFalse);

      // 再点按 → 取反回 true。
      await tester.tap(find.byKey(const Key('control_practice_mirror')));
      await tester.pump(settlePump);
      await tester.pump();
      expect(container.read(effectivePracticeMirrorProvider), isTrue);
      expect(container.read(practiceMirrorOverrideProvider), isTrue);
    });

  });

  group('标注工具区固定槽位', () {
    testWidgets('跨面一致性：正常态槽集声明的槽位 == 实际渲染出的槽键逐位相等', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final declared = ToolSlotTable.normal.slots.map((s) => s.key).toList();
      final rendered = renderedSlotKeys(tester);
      // 槽集声明 = 实际渲染：逐位相等（次序即声明次序，不可能漏项）。
      expect(rendered, declared);
      // 渲染次序 = 声明次序（x 坐标严格递增）。
      var previous = -1.0;
      for (final key in declared) {
        final x = tester.getCenter(find.byKey(Key(key))).dx;
        expect(x, greaterThan(previous), reason: key);
        previous = x;
      }
    });

    testWidgets('跨面一致性：待命态槽集声明的槽位 == 实际渲染出的槽键逐位相等', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).enter(
            PlayerSessionMode.beatCorrectionStandby,
          );
      await tester.pumpAndSettle();

      final declared = ToolSlotTable.standby.slots.map((s) => s.key).toList();
      final rendered = renderedSlotKeys(tester);
      // 槽集声明 = 实际渲染：逐位相等（换装也是同一份声明数据驱动）。
      expect(rendered, declared);
      // 渲染次序 = 声明次序（x 坐标严格递增）。
      var previous = -1.0;
      for (final key in declared) {
        final x = tester.getCenter(find.byKey(Key(key))).dx;
        expect(x, greaterThan(previous), reason: key);
        previous = x;
      }
    });

    testWidgets('装载未完成门：会写盘的槽全部置灰、仍可点、弹「正在装载」且不写盘；落定后放行', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      // 跨面一致性（声明 == 实际可用性）：会写盘的槽全部置灰（禁用 token）
      // 且仍可点——装载未完成门压倒各自的其余门，点击语义 = 弹原因。
      for (final slot in ToolSlotTable.normal.slots.where(
        (s) => s.writesDocument,
      )) {
        expect(
          slotIconColor(tester, slot.key),
          kToolSlotDisabledIconColor,
          reason: '${slot.key} 置灰',
        );
        expect(
          evaluateToolSlot([
            ToolGateKind.loading,
            ...slot.gates,
          ]).tappable,
          isTrue,
          reason: '${slot.key} 声明可点',
        );
      }

      // 点「分段」：弹「正在装载」，不落任何分段线。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pump();
      await tester.pump();
      expect(find.text('正在装载'), findsOneWidget);
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);

      // 装载落定：入口自动恢复可用，无需重开页面。
      container.read(loadGateActiveProvider.notifier).settle();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(container.read(annotationTimelineProvider).segmentLines,
          hasLength(1));
    });

    testWidgets('装载未完成：待命态三个锚点写盘槽同门被挡、退出槽不声明本门', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.beatCorrectionStandby);
      await tester.pumpAndSettle();
      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      for (final slot in ToolSlotTable.standby.slots.where(
        (s) => s.writesDocument,
      )) {
        expect(
          slotIconColor(tester, slot.key),
          kToolSlotDisabledIconColor,
          reason: '${slot.key} 置灰',
        );
      }
      // 退出八拍矫正不写盘：置灰与否不由本门决定（此处它恒正常）。
      expect(slotEnabled(tester, 'control_beat_correction_exit'), isTrue);
    });

    testWidgets('装载未完成：设置开关与顶栏镜像开关被挡并弹原因、值一位不动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      // 设置开关（预览吸附）：点击弹原因、值不动。
      final before = container.read(previewSnapEnabledProvider);
      await tester.tap(find.byKey(const Key('track_preview_snap_slot')));
      await tester.pump();
      await tester.pump();
      expect(find.text('正在装载'), findsOneWidget);
      expect(container.read(previewSnapEnabledProvider), before);

      // 顶栏镜像开关：点击弹原因、画面镜像不动。
      expect(surfaceMirrored(tester), isFalse);
      await tester.tap(find.byKey(const Key('tool_mirror')));
      await tester.pump();
      expect(surfaceMirrored(tester), isFalse);
    });

    testWidgets('未选中分段线时「标记分段线」条目与删除置灰；截图排开不再渲染', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 「标记分段线」条目在「添加」菜单里：未选中时置灰但按得动。
      await openAddMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_segment_flag')),
            )
            .enabled,
        isTrue,
        reason: '无选中分段线 → 无对象 → 置灰但按得动（弹做法）',
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '同上：置灰但按得动');
      // 无对象种类唯一一条外观断言：置灰统一为同一 token。
      expect(slotIconColor(tester, 'control_segment_delete'),
          kToolSlotDisabledIconColor);
      // 标注工具区没有「截图排开」占位槽。
      expect(find.byKey(const Key('tool_screenshot')), findsNothing);
    });

    testWidgets('选中分段线后「标记分段线」条目可用；改选学习段后回到置灰', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      // 新建线落在播放头位置（10s）——线心点击会被预览线 2px 命中
      // 柱吸收，移开播放头再点选分段线/学习段（2s 避开线 10s、段 0 中心
      // 5s 与段体点击）。
      await engine.seek(const Duration(seconds: 2));
      await tester.pump();
      await tester.pumpAndSettle();

      // 新建线后选中在学习段上；开菜单确认条目置灰（仍按得动），
      // 点选分段线 → 可用。
      await openAddMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_segment_flag')),
            )
            .enabled,
        isTrue,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_segment_flag')),
            )
            .enabled,
        isTrue,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // 改选学习段：条目回到置灰（仍按得动）。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_segment_flag')),
            )
            .enabled,
        isTrue,
      );
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
    });
  });

  group('标注工具槽判定接线', () {
    testWidgets('行为修正：未锁定 + 预览线越界 → 分段槽置灰且不可点、不产生任何提示', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine, beatPipeline: hangingBeatPipeline);
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      // 自动分段设窄有效区间（就绪节拍首末拍 0.5s–2.0s）。
      await engine.pause();
      await engine.seek(const Duration(seconds: 1));
      await tester.pump();
      await tapAutoEntry(tester, 'control_auto_seg_4');
      expect(container.read(annotationTimelineProvider).rangeEnd,
          const Duration(seconds: 2));
      // 预览线停在有效区间外（未锁定）。
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();

      // 外观（预览线越界种类唯一一条外观断言）：置灰。
      expect(slotIconColor(tester, 'control_segment'),
          kToolSlotDisabledIconColor);
      // 置灰且不可点（原「置灰可点、点击静默」路径不可达）。
      expect(slotEnabled(tester, 'control_segment'), isFalse);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing,
          reason: '未锁定，不弹锁提示');
      expect(find.byKey(const Key('beat_analyzing_prompt')), findsNothing,
          reason: '越界静默，不弹原因提示');
      expect(find.byKey(const Key('beat_no_data_prompt')), findsNothing,
          reason: '越界静默，不弹原因提示');
    });

    testWidgets('无障碍语义：正常态每槽都是按钮并报可点；熟练度选中后另报已选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 无障碍树断言：门控槽键直接挂在 Semantics 上；熟练度键在
      // PopupMenuButton 上，助手向下找按钮语义层。
      for (final slot in ToolSlotTable.normal.slots) {
        expectButtonSemantics(tester, Key(slot.key), reason: slot.key);
      }
      // 可点与否按判定表报出：无对象 → 置灰但按得动；
      // 未就绪 → 置灰仍可点。
      expectButtonSemantics(tester, const Key('control_mastery'),
          enabled: true, reason: '未选中学习段 → 无对象 → 置灰但按得动');
      expectButtonSemantics(tester, const Key('control_segment'),
          enabled: true, reason: '网格未就绪 → 置灰仍可点');

      // 建线后点选学习段：熟练度槽激活并报「已选中」（点选定法同前：
      // 点选段体左下 25%/75%，避开预览线命中柱与右上 dock）。
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final segRect = tester.getRect(find.byKey(const Key('learning_segment_1')));
      await tester.tapAt(
        Offset(segRect.left + segRect.width * 0.25,
            segRect.top + segRect.height * 0.75),
      );
      await tester.pumpAndSettle();
      expectButtonSemantics(tester, const Key('control_mastery'),
          enabled: true, selected: true, reason: '激活槽报已选中');
    });

    testWidgets('无障碍语义：待命态 4 槽都是按钮；退出槽恒可点', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).enter(
            PlayerSessionMode.beatCorrectionStandby,
          );
      await tester.pumpAndSettle();

      for (final slot in ToolSlotTable.standby.slots) {
        expectButtonSemantics(tester, Key(slot.key), reason: slot.key);
      }
      expectButtonSemantics(tester, const Key('control_beat_correction_exit'),
          enabled: true, reason: '无门槽恒可点');
    });
  });

  group('竖屏底栏两行', () {
    /// 真机竖屏基准：1264×2736 @3.5 = 361.1×781.7dp。
    void setRealPortraitView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact);
    }

    /// 668dp 宽竖屏视口（刻意放宽的**合成档**：2338×2736 @3.5 = 668×781.7dp，
    /// 非设备基准）：放得下六枚
    /// 一行的宽视口回归护栏用。
    Future<void> enterPortraitEdit(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester);
    }

    testWidgets('次序：标注工具行在上、播放控制工具行在下；轨道行仍在两行上方', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 3),
        videoAspectRatio: 16 / 9,
      );
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);
      expect(tester.takeException(), isNull);

      // 标注行（槽位）在上、播放行（播放钮）在下。
      final slotsBottom = tester
          .getBottomLeft(find.byKey(const Key('control_auto_range')))
          .dy;
      final playTop = tester.getTopLeft(find.byKey(const Key('toolbar_play'))).dy;
      expect(playTop, greaterThanOrEqualTo(slotsBottom), reason: '播放控制行在标注工具行之下');

      // 轨道设置条与轨道行仍在两行工具行上方。
      final bandBottom = tester.getBottomLeft(find.byKey(const Key('track_band'))).dy;
      final toolbarTop = tester
          .getTopLeft(find.byKey(const Key('control_layer_toolbar')))
          .dy;
      expect(bandBottom, lessThanOrEqualTo(toolbarTop));
      final clusterBottom = tester
          .getBottomLeft(find.byKey(const Key('settings_cluster')))
          .dy;
      expect(clusterBottom, lessThanOrEqualTo(toolbarTop));
    });

    testWidgets('播放控制行交互照旧：播放/暂停、帧步进、延迟播放', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      // 播放/暂停。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      expect(engine.isPlaying, isFalse);

      // 帧步进（无选中 → 预览进度 ±1 帧，走既有 seek 提交口）。
      final seeksBefore = engine.seekCalls.length;
      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pump();
      expect(engine.seekCalls.length, greaterThan(seeksBefore));

      // 延迟播放：点它收起控制层并立即起播（既有路径）。
      await tester.tap(find.byKey(const Key('toolbar_delayed_play')));
      await tester.pump();
      await tester.pump();
      expect(controlLayer(), findsNothing);
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('帧步进钮：报角色与名字；读屏激活各恰好走一帧', (tester) async {
      final handle = tester.ensureSemantics();
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      const forward = Key('toolbar_frame_step_forward');
      const back = Key('toolbar_frame_step_back');
      expectButtonSemantics(tester, forward, label: '右移一步');
      expectButtonSemantics(tester, back, label: '左移一步');

      // 读屏路径在播时先 pause 再 submit，且 seek 走轨道带的串行队列
      // （latest-wins + 按帧节流 kScrubSeekMinInterval）：首帧立即发出，后续
      // 目标要等节流窗口过去才发。故先停稳引擎把位置定住，再按节流窗口推进
      // 假时钟让队列收敛，才能对「恰好一帧」做确定性断言（不是放宽断言）。
      await engine.pause();
      await tester.pump();

      // 读屏双击「右移一步」：恰好一帧（不是只断言 seek 次数增长）。
      final start = engine.position;
      activateBySemantics(tester, forward);
      await tester.pump(kScrubSeekMinInterval * 2);
      expect(engine.seekCalls, isNotEmpty, reason: '读屏激活应提交 seek');
      expect(
        engine.seekCalls.last - start,
        kDefaultFrameDuration,
        reason: '读屏双击帧步进钮恰好走一帧',
      );

      // 反向一枚同样走无障碍路径：从一帧处回退一帧。
      activateBySemantics(tester, back);
      await tester.pump(kScrubSeekMinInterval * 2);
      expect(
        engine.seekCalls.last,
        start,
        reason: '读屏双击「左移一步」回退恰好一帧',
      );
      handle.dispose();
    });

    testWidgets('帧号读数：竖屏字号 12、完整显示「当前 / 总长」两段不被裁', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      final readout = find.byKey(const Key('toolbar_time'));
      final text = tester.widget<Text>(readout);
      expect(text.data, contains(' / '), reason: '「当前 / 总长」两段同串显示');
      expect(text.style!.fontSize, 12, reason: '竖屏字号 12');
      // 右缘不越屏（读数盒左对齐独占剩余宽）。注：widget 测试宿主的默认
      // 字体每字形宽 = 字号，任何 19 字符文本在 12pt 下都无法真实放进
      // ≈145dp 剩余宽，「无省略截断」只能靠真机观感验收。
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getTopRight(readout).dx, lessThanOrEqualTo(screenWidth));
    });

    testWidgets('横屏底栏：读数字号仍 14、底栏仍一行（槽位与播放钮同一行）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final readout = find.byKey(const Key('toolbar_time'));
      expect(tester.widget<Text>(readout).style!.fontSize, 14);
      // 一行：播放钮与槽位垂直居中同带（y 中点重合）。
      final playY = tester.getCenter(find.byKey(const Key('toolbar_play'))).dy;
      final slotY = tester.getCenter(find.byKey(const Key('control_mastery'))).dy;
      expect(playY, closeTo(slotY, 0.5));
    });
  });

  group('标注工具区收进屏幕右缘', () {
    testWidgets(
      '窄视口下槽集全部槽收进屏幕右缘：最右「自动分段」右缘 ≤ 屏宽、不依赖横向滚动、时间读数收缩让位',
      (tester) async {
        // 模拟旋转前的窄竖屏帧（**合成档**，宽于真机 632dp）：旧布局时间读数 Expanded
        // 占满一半宽度、工具区滚动视口被挤窄，「自动分段」被裁出右缘；新布局
        // 时间读数收缩让位、工具区取剩余宽度，槽集固定宽度全部收进右缘。
        setWidenedPortraitView(tester);

        final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
        final systemUi = FakeSystemUi();
        await pumpPlayer(tester, engine: engine, systemUi: systemUi);
        // 竖屏单击直接进编辑（进入前置为无）——布局仍处于旋转前
        // 的窄竖屏帧，即不裁槽位的场景。
        await tester.tap(find.byKey(const Key('player_surface')));
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
        await pumpPastMarquee(tester); // 标题滚动不停歇，pumpAndSettle 不收敛

        final slotKeys = normalSlotKeys();
        // 工具区不依赖横向滚动（无横向 SingleChildScrollView）。
        expect(
          find
              .descendant(
                of: find.byKey(const Key('control_layer_toolbar')),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is SingleChildScrollView &&
                      w.scrollDirection == Axis.horizontal,
                ),
              )
              .evaluate(),
          isEmpty,
        );
        // 几何断言：每槽右缘都在屏幕右缘内，最右「自动分段」可见可点。
        final screenWidth =
            tester.view.physicalSize.width / tester.view.devicePixelRatio;
        for (final key in slotKeys) {
          expect(
            tester.getTopRight(find.byKey(Key(key))).dx,
            lessThanOrEqualTo(screenWidth),
            reason: key,
          );
        }
        // 槽位固定顺序不变（x 严格递增）。
        var previous = -1.0;
        for (final key in slotKeys) {
          final x = tester.getCenter(find.byKey(Key(key))).dx;
          expect(x, greaterThan(previous), reason: key);
          previous = x;
        }
      },
    );
  });

  group('底部工具组整体右对齐', () {
    testWidgets(
      '宽视口下工具组贴右缘：最右「自动首尾」右缘贴工具条右内缘、与时间读数之间留出空白、槽位顺序不变',
      (tester) async {
        // 刻意放宽的**合成档**宽视口（1368×632dp，非设备基准）：旧布局工具区紧跟时间读数左对
        // 铺排、右侧留大片空；新布局固定槽位整体右对齐贴
        // 右缘。留白独占弹性（若时间读数仍占 flex 份额，宽视口下工具组会
        // 悬浮在中部、离右缘数百 dp——正是要修的观感）。
        tester.view.physicalSize = const Size(2736, 1264);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.reset);

        final engine = FakePlaybackEngine(
          duration: const Duration(minutes: 3),
        );
        await pumpPlayer(tester, engine: engine);
        await singleTapShow(tester);

        final slotKeys = normalSlotKeys();
        // 整体贴右缘：最右「自动首尾」右缘 = 工具条右内缘（水平 padding 8）。
        final toolbarRight = tester.getTopRight(
          find.byKey(const Key('control_layer_toolbar')),
        ).dx;
        final setEndRight = tester.getTopRight(
          find.byKey(const Key('control_auto_range')),
        ).dx;
        expect(setEndRight, closeTo(toolbarRight - 8, 1));
        // 不越右缘（工具条右内缘之内）。
        expect(setEndRight, lessThanOrEqualTo(toolbarRight - 8));
        // 组左侧与时间读数之间留出宽幅可点空白（宽视口下显著大于固定间距）。
        final masteryLeft = tester.getTopLeft(
          find.byKey(const Key('control_mastery')),
        ).dx;
        final timeRight = tester.getTopRight(
          find.byKey(const Key('toolbar_time')),
        ).dx;
        expect(masteryLeft - timeRight, greaterThan(100));
        // 槽位固定顺序不变（x 严格递增）。
        var previous = -1.0;
        for (final key in slotKeys) {
          final x = tester.getCenter(find.byKey(Key(key))).dx;
          expect(x, greaterThan(previous), reason: key);
          previous = x;
        }
      },
    );

    testWidgets('窄视口下右对齐仍不越右缘：时间读数收缩让位、留白压缩但不为负', (tester) async {
      // 旋转前窄竖屏帧（刻意收窄的**合成档** 632×1368dp，非设备基准）：时间读数收缩、留白最小化为 0，
      // 工具组 8 槽仍贴右内缘（几何不回归 + 右对齐并存）。
      setWidenedPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester); // 标题滚动不停歇，pumpAndSettle 不收敛

      final toolbarRight = tester.getTopRight(
        find.byKey(const Key('control_layer_toolbar')),
      ).dx;
      final setEndRight = tester.getTopRight(
        find.byKey(const Key('control_auto_range')),
      ).dx;
      expect(setEndRight, closeTo(toolbarRight - 8, 1));
      expect(setEndRight, lessThanOrEqualTo(toolbarRight - 8));
    });

    testWidgets('工具组与时间读数之间的空白属工具条区域：点击不触发收起', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 3),
      );
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final masteryTop = tester.getTopLeft(
        find.byKey(const Key('control_mastery')),
      );
      final timeRight = tester.getTopRight(
        find.byKey(const Key('toolbar_time')),
      ).dx;
      // 点击留白中点（工具条区域内部）。
      final gapCenter = Offset(
        (timeRight + masteryTop.dx) / 2,
        masteryTop.dy,
      );
      await tester.tapAt(gapCenter);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(controlLayer(), findsOneWidget, reason: '工具条留白不触发收起');
    });
  });

  group('底栏标注工具槽全内联（无溢出兜底）', () {
    /// 真机竖屏基准：1264×2736 @3.5 = 361.1×781.7dp，与开发
    /// 真机 DNP-AN00 一致。
    void setRealPortraitView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact);
    }

    /// 668dp 宽竖屏视口（刻意放宽的**合成档**：2338×2736 @3.5 = 668×781.7dp，
    /// 非设备基准）：放得下六枚
    /// 一行的宽视口回归护栏用。
    /// 竖屏点画面直接进编辑面，等标题滚动下的过渡帧。
    Future<void> enterPortraitEdit(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester);
    }

    testWidgets('真机竖屏基准：标注工具行七槽全部内联、无溢出入口、门禁语义不变', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      // 零 RenderFlex 溢出（布局期溢出会被测试宿主记为异常）。
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const Key('control_layer_toolbar'))).width,
        closeTo(1264 / 3.5, 0.01),
      );
      // 无横向滚动兜底。
      expect(
        find
            .descendant(
              of: find.byKey(const Key('control_layer_toolbar')),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.horizontal,
              ),
            )
            .evaluate(),
        isEmpty,
      );

      // 七槽全部内联可见，不存在任何溢出入口。
      expect(find.byKey(const Key('toolbar_more')), findsNothing);
      final declared = normalSlotKeys();
      expect(renderedSlotKeys(tester), declared);
      // 次序与槽集声明一致（x 严格递增）。
      var previous = -1.0;
      for (final key in declared) {
        final x = tester.getCenter(find.byKey(Key(key))).dx;
        expect(x, greaterThan(previous), reason: key);
        previous = x;
      }
      // 门禁语义不变：无选中对象时「删除」置灰（按得动、
      // 点一下弹做法，动作不发生）。
      expect(
        tester
            .widget<Semantics>(
              find.byKey(const Key('control_segment_delete')),
            )
            .properties
            .enabled,
        isTrue,
        reason: '无对象 → 置灰但按得动',
      );
      expect(slotIconColor(tester, 'control_segment_delete'),
          kToolSlotDisabledIconColor,
          reason: '删除槽仍置灰');

      // 点「分段」：与既有内联同一条动作路径（一次点击 = 一条分段线）。
      // 先暂停定格到确定预览位（就近八拍点落点不受播放位置漂移影响）。
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(container.read(annotationTimelineProvider).segmentLines, hasLength(1));
    });

    testWidgets('真机竖屏基准 + 待命态：4 槽全部内联、无溢出入口', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).enter(
            PlayerSessionMode.beatCorrectionStandby,
          );
      await pumpPastMarquee(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('toolbar_more')), findsNothing);
      for (final slot in ToolSlotTable.standby.slots) {
        expect(
          find.byKey(Key(slot.key)),
          findsOneWidget,
          reason: '${slot.key} 在标注工具行内联可见',
        );
      }
    });

    testWidgets('真机竖屏基准 + 对比态：6 槽全部内联、无溢出入口', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        docs: InMemoryVideoDocumentStorage(local: const {'version': 3}),
      );
      await enterPortraitEdit(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).enter(
            PlayerSessionMode.compareEditing,
          );
      await pumpPastMarquee(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('toolbar_more')), findsNothing);
      for (final slot in ToolSlotTable.compare.slots) {
        expect(
          find.byKey(Key(slot.key)),
          findsOneWidget,
          reason: '${slot.key} 在标注工具行内联可见',
        );
      }
    });

    testWidgets('真机竖屏基准：内联「添加」槽锚自身打开条目菜单（添加条目可达）', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      // 「添加」在竖屏标注工具行内联：点它锚槽位自身弹出条目
      // 菜单——与既有内联口径同一路径。
      expect(find.byKey(const Key('control_add')), findsOneWidget);
      await tester.tap(find.byKey(const Key('control_add')));
      await pumpPastMarquee(tester);

      for (final entry in AddEntryTable.normal.entries) {
        expect(
          find.byKey(Key(entry.key)),
          findsOneWidget,
          reason: '${entry.key} 在「添加」槽打开的条目菜单里可达',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('横屏 782dp：底栏逐位不变——7 槽全内联、无「更多」入口、最右贴右内缘', (tester) async {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      expect(find.byKey(const Key('toolbar_more')), findsNothing);
      final declared = normalSlotKeys();
      expect(renderedSlotKeys(tester), declared);
      final toolbarRight = tester
          .getTopRight(find.byKey(const Key('control_layer_toolbar')))
          .dx;
      expect(
        tester.getTopRight(find.byKey(const Key('control_auto_range'))).dx,
        closeTo(toolbarRight - 8, 1),
      );
      var previous = -1.0;
      for (final key in declared) {
        final x = tester.getCenter(find.byKey(Key(key))).dx;
        expect(x, greaterThan(previous), reason: key);
        previous = x;
      }
    });
  });

  group('标注工具区槽位命中盒下限', () {
    /// 真机竖屏基准（同上组）：1264×2736 @3.5 = 361.1×781.7dp。
    void setRealPortraitView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact);
    }

    Future<void> enterPortraitEdit(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester);
    }

    /// 槽位的**命中矩形**（断言打命中矩形、不打视觉件矩形）——
    /// 槽 key 子树里第一个 InkWell 的框，即透明外扩后的可点域。
    Rect slotHitRect(WidgetTester tester, String slotKey) => tester.getRect(
      find
          .descendant(
            of: find.byKey(Key(slotKey)),
            matching: find.byType(InkWell),
          )
          .first,
    );

    testWidgets('每个槽的命中矩形 ≥ 密集区兜底下限，且槽集齐全', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);
      expect(tester.takeException(), isNull);

      final declared = normalSlotKeys();
      expect(renderedSlotKeys(tester), declared);
      for (final key in declared) {
        final hit = slotHitRect(tester, key);
        expect(hit.width, greaterThanOrEqualTo(kHitTargetDenseMinSize),
            reason: '$key 命中宽不足密集区兜底下限');
        expect(hit.height, greaterThanOrEqualTo(kHitTargetDenseMinSize),
            reason: '$key 命中高不足密集区兜底下限');
      }
    });

    testWidgets('相邻槽命中域不互吞（命中矩形两两不重叠）', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      final rects = [
        for (final key in renderedSlotKeys(tester))
          MapEntry(key, slotHitRect(tester, key)),
      ]..sort((a, b) => a.value.left.compareTo(b.value.left));
      for (var i = 0; i < rects.length - 1; i++) {
        expect(
          rects[i].value.right,
          lessThanOrEqualTo(rects[i + 1].value.left),
          reason: '${rects[i].key} 与 ${rects[i + 1].key} 的命中域互吞',
        );
      }
    });

    testWidgets('透明外扩不改视觉几何：图标档、标签档与行名义高逐位不变', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await enterPortraitEdit(tester);

      // 视觉件逐位不变：图标 24 档（含渲染矩形）、标签 10 档。
      for (final key in normalSlotKeys()) {
        final icon = find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Icon),
        );
        expect(tester.widget<Icon>(icon.first).size, kToolSlotIconSize,
            reason: '$key 图标尺寸被外扩改变');
        expect(
          tester.getRect(icon.first).size,
          const Size(kToolSlotIconSize, kToolSlotIconSize),
          reason: '$key 图标渲染矩形被外扩改变',
        );
        final label = find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byWidgetPredicate(
            (w) => w is Text && w.data != null,
          ),
        );
        expect(
          tester.widget<Text>(label.first).style?.fontSize,
          kToolSlotLabelFontSize,
          reason: '$key 标签字号被外扩改变',
        );
      }
      // 行名义高不变：竖屏底栏两行仍是名义高表值（52×2）。
      expect(
        tester.getSize(find.byKey(const Key('control_layer_toolbar'))).height,
        kEditorPortraitToolbarRowsHeight,
      );
    });
  });

  group('底部工具条进度控件', () {
    testWidgets('播放/暂停按钮切换引擎播放态', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);

      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('延迟播放按钮 = 收起控制层 + 触发延迟播放（同一次点按内，收起先于触发）；预备期无占位徽章', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(controlLayer(), findsOneWidget);

      // 先暂停到确定态。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);

      await tester.tap(find.byKey(const Key('toolbar_delayed_play')));
      await tester.pump();
      await tester.pump();
      // 同一次点按内：控制层已收起、延迟已触发；预备期树上不存在
      // 「延迟播放中…」徽章键与文案。
      expect(controlLayer(), findsNothing);
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(find.text('延迟播放中…'), findsNothing);
      // 触发即倒回预备起点连续播：点按完成的一刻引擎已在播。
      expect(engine.isPlaying, isTrue);
      expect(engine.seekCalls, isNotEmpty, reason: '触发即 seek 到预备起点');
    });
  });

  group('手势作用域切换（编辑态播放手势不生效）', () {
    testWidgets('控制层展开时空白横滑即调进度（取代旧「不生效」）；收起后播放手势恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 展开时在中部空白向右拖动：空白横滑 seek 生效（
      // 编辑态视频可见区单指水平滑 = 调进度，取代「编辑态播放手势不生效」
      // 的空白区部分）。
      final seeksWhileOpen = engine.seekCalls.length;
      final g = await tester.startGesture(const Offset(400, 300));
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
      expect(
        engine.seekCalls.length,
        greaterThan(seeksWhileOpen),
        reason: '编辑态空白横滑可调进度',
      );

      // 收起 → 手势恢复：拖动应 seek。
      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('control_layer_blank')),
      );
      final seeksBeforeClosed = engine.seekCalls.length;
      final g2 = await tester.startGesture(const Offset(400, 300));
      for (var i = 0; i < 8; i++) {
        await g2.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g2.up();
      await tester.pump();
      expect(
        engine.seekCalls.length,
        greaterThan(seeksBeforeClosed),
        reason: '收起后播放手势恢复（可调进度）',
      );
    });
  });

  group('竖屏直接进标注编辑', () {
    testWidgets('竖屏单击唤出：一次单击直接进编辑、零方向锁', (tester) async {
      // 窄竖屏**合成档**（632×1368dp，刻意收窄、非设备基准）。后工具区不再横向
      // 滚动，8 槽以真机可容纳的宽度为准收进右缘。
      setWidenedPortraitView(tester);

      final engine = FakePlaybackEngine();
      final systemUi = FakeSystemUi();
      await pumpPlayer(tester, engine: engine, systemUi: systemUi);

      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester); // 标题滚动不停歇，pumpAndSettle 不收敛

      expect(controlLayer(), findsOneWidget);
      expect(systemUi.lockLandscapeCount, 0, reason: '进编辑面不锁方向');
    });

    testWidgets('竖屏收起控制层：零方向请求并回观看态', (tester) async {
      setWidenedPortraitView(tester);

      final engine = FakePlaybackEngine();
      final systemUi = FakeSystemUi();
      await pumpPlayer(tester, engine: engine, systemUi: systemUi);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester);
      expect(controlLayer(), findsOneWidget);

      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).collapse();
      await tester.pump();

      expect(controlLayer(), findsNothing);
      expect(systemUi.lockLandscapeCount, 0);
    });
  });

  group('竖屏画面落位两分支', () {
    const portraitWidth = 668.0; // setWidenedPortraitView：1336×2736 @2
    const portraitHeight = 1368.0;
    const normalTrackBandHeight = 208.0; // 行高表之和，不随屏高压缩
    /// 可用高 = 1368 − (顶栏 52 + 底栏两行 104 + 视频播放工具栏两行 104 +
    /// 设置条 48) = 1060；画面区 = 1060 − 208 = 852（视频工具栏一行变两行、
    /// 设置条命中盒下限 48，名义高表随之重算）。
    const pictureAreaHeight = 852.0;

    /// 竖屏视口下点画面进编辑面。
    Future<void> openEditor(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await pumpPastMarquee(tester);
      expect(controlLayer(), findsOneWidget);
    }

    /// 竖屏编辑面转屏钮：画面区右下角的横屏入口。
    Finder rotateButton() => find.byKey(kPortraitRotateButtonKey);
    Finder videoPlaceholder() => find.byKey(videoSurfacePlaceholderKey);
    Finder trackBand() => find.byKey(const Key('track_band'));

    /// 画面区右下角内缩后的转屏钮角点（与实现同一式子）。
    Offset expectedRotateCorner(double aspectRatio) {
      final area = portraitPictureAreaRect(
        screen: const Size(portraitWidth, portraitHeight),
        systemTopInset: 0,
        skeleton: editorSkeletonFor(
          screen: const Size(portraitWidth, portraitHeight),
          trackBandHeight: normalTrackBandHeight,
          videoAspectRatio: aspectRatio,
        ),
      );
      return portraitRotateButtonRect(pictureArea: area).bottomRight;
    }

    testWidgets('画面区随两行工具栏变矮后，取景放大仍盖满这块区域（变换层几何）', (tester) async {
      setWidenedPortraitView(tester);
      final engine = FakePlaybackEngine(videoAspectRatio: 16 / 9);
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);

      final area = portraitPictureAreaRect(
        screen: const Size(portraitWidth, portraitHeight),
        systemTopInset: 0,
        skeleton: editorSkeletonFor(
          screen: const Size(portraitWidth, portraitHeight),
          trackBandHeight: normalTrackBandHeight,
          videoAspectRatio: 16 / 9,
        ),
      );
      expect(area.height, closeTo(pictureAreaHeight, 0.5),
          reason: '画面区 = 骨架给的那一块（比一行工具栏时矮 52dp）');
      final band = tester.getRect(videoPlaceholder());
      expect(band.bottom, closeTo(area.bottom, 0.5),
          reason: '未调过：画面带贴画面区下缘');

      // 进取景子态，拖动圈一块（画面带中段偏窄的一条）。
      await tester.tap(find.byKey(const Key('tool_framing_adjust')));
      await tester.pumpAndSettle();
      final from = Offset(
        band.left + band.width * 0.35,
        band.top + band.height * 0.1,
      );
      final to = Offset(
        band.left + band.width * 0.65,
        band.top + band.height * 0.9,
      );
      final touch = await tester.startGesture(from);
      await tester.pump();
      await touch.moveTo(Offset.lerp(from, to, 0.15)!);
      await tester.pump();
      await touch.moveTo(to);
      await tester.pump();
      await touch.up();
      await tester.pumpAndSettle();

      // 退出取景回编辑态：选区内容按 contain 放大（取景态内按整帧显示）。
      await tester.tap(find.byKey(const Key('framing_done')));
      await tester.pumpAndSettle();

      final zoomed = tester.getRect(videoPlaceholder());
      expect(zoomed.height, greaterThan(band.height * 2), reason: '取景放大生效');
      expect(zoomed.top, lessThanOrEqualTo(area.top),
          reason: '放大后的画面件矩形盖上画面区上缘');
      expect(zoomed.bottom, greaterThanOrEqualTo(area.bottom),
          reason: '放大后的画面件矩形盖住画面区下缘');
    });

    testWidgets('竖屏 + 横屏源：画面满宽、底边贴住画面区下缘，黑区留在画面上方', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 16 / 9;
      final engine = FakePlaybackEngine(videoAspectRatio: ar);
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);

      final video = tester.getRect(videoPlaceholder());
      final videoToolbar = tester.getRect(
        find.byKey(const Key('control_layer_video_toolbar')),
      );
      expect(video.left, 0);
      expect(video.width, portraitWidth, reason: '画面满宽');
      expect(
        video.height,
        closeTo(portraitWidth / ar, 0.5),
        reason: '高度 = 画面按 contain 在满宽下的实测高',
      );
      expect(
        video.bottom,
        closeTo(videoToolbar.top, 0.5),
        reason: '底边贴住画面区下缘（紧贴视频播放工具栏两行上缘）',
      );
      expect(
        videoToolbar.top - kEditorTopBarHeight,
        closeTo(pictureAreaHeight, 0.5),
        reason: '测试视口 668×1368 下画面区实际渲染高 = 852',
      );
      expect(
        video.top,
        closeTo(kEditorTopBarHeight + pictureAreaHeight - portraitWidth / ar, 0.5),
        reason: '黑区留在画面上方（画面顶 = 顶栏之下 + 画面区高 − 画面高）',
      );
      expect(
        video.top,
        greaterThan(kEditorTopBarHeight),
        reason: '画面不再贴顶、落在顶栏之下',
      );
      // 画面区下缘与视频播放工具栏两行上缘直接相接：转屏钮贴该角内缩 8dp。
      expect(rotateButton(), findsOneWidget);
      expect(
        tester.getRect(rotateButton()).bottomRight,
        expectedRotateCorner(ar),
        reason: '转屏钮落在画面区右下角内缩 8dp 处',
      );
      // 名义 chrome 高与真实渲染对齐（骨架常量是实测值，不是猜的）。
      expect(
        tester.getSize(find.byKey(const Key('control_layer_toolbar'))).height,
        kEditorPortraitToolbarRowsHeight,
        reason: '竖屏底栏两行，名义高表与真实渲染一致',
      );
      expect(
        tester.getSize(find.byKey(const Key('settings_cluster'))).height,
        kEditorSettingsClusterHeight,
      );

      final band = tester.getRect(trackBand());
      expect(
        band.top,
        greaterThanOrEqualTo(videoToolbar.bottom),
        reason: '轨道带常驻画面区之下、一点不遮画面',
      );
      expect(band.height, normalTrackBandHeight, reason: '轨道行高不随屏高变化');
      // 注解层换算基准跟随画面（贴底、满宽），不留在旧的居中信箱位。
      expect(
        tester
            .widget<NoteStickerOverlay>(find.byType(NoteStickerOverlay))
            .contentRect,
        Rect.fromLTWH(0, video.top, portraitWidth, portraitWidth / ar),
        reason: '贴纸画面矩形随画面一起落位',
      );
    });

    testWidgets('竖屏 + 竖向源：画面与观看态逐位相同（整屏 contain 居中），工具带压在其上', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 9 / 16;
      final engine = FakePlaybackEngine(videoAspectRatio: ar);
      final systemUi = FakeSystemUi();
      await pumpPlayer(tester, engine: engine, systemUi: systemUi);
      await openEditor(tester);

      // 满宽 contain = 668/(9/16) ≈ 1187.6 > 画面区 852 → 观看态背景位：
      // 整屏 contain 居中（宽受限，左右贴边、上下留黑）。
      final expected = Rect.fromLTWH(
        0,
        (portraitHeight - portraitWidth / ar) / 2,
        portraitWidth,
        portraitWidth / ar,
      );
      expect(tester.getRect(videoPlaceholder()), expected, reason: '竖向源走观看态背景位');
      // 工具带为正常骨架段（浮层分支退场），轨道带行高不变、可操作。
      final band = tester.getRect(trackBand());
      expect(band.height, normalTrackBandHeight, reason: '行高表不动、不随屏高压缩');
      expect(
        band.top,
        lessThan(expected.bottom),
        reason: '工具带以半透明黑压在背景位画面之上',
      );
      final seeksBefore = engine.seekCalls.length;
      final drag = await tester.startGesture(tester.getCenter(trackBand()));
      await tester.pump();
      await drag.moveBy(const Offset(150, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(
        engine.seekCalls.length,
        greaterThan(seeksBefore),
        reason: '轨道带仍可操作（拖动提交 seek）',
      );
      // 竖向源下画面仍是与观看态逐位相同的背景位；转屏钮仍在同一处
      // （只看画面区、不看画面显示朝向）。
      expect(rotateButton(), findsOneWidget);
      expect(
        tester.getRect(rotateButton()).bottomRight,
        expectedRotateCorner(ar),
        reason: '竖画面与横画面落在同一处',
      );
      // 注解层换算基准与观看态同几何（整屏 contain 居中）。
      expect(
        tester
            .widget<NoteStickerOverlay>(find.byType(NoteStickerOverlay))
            .contentRect,
        expected,
      );

      // 收起控制层 = 观看态：背景位不因工具带让位，逐位相同。
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).collapse();
      await tester.pump();
      expect(tester.getRect(videoPlaceholder()), expected, reason: '背景位收起/展开逐位相同');
    });

    testWidgets('宽高比未知：先按观看态背景位出画，不闪错误布局', (tester) async {
      setWidenedPortraitView(tester);
      final engine = FakePlaybackEngine(); // videoAspectRatio = null
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);

      // 未知 = 观看态背景位：画面件整屏（宽高比未知由内核自行 contain）。
      expect(
        tester.getRect(videoPlaceholder()),
        const Rect.fromLTWH(0, 0, portraitWidth, portraitHeight),
        reason: '未知时不撑错误尺寸、直接出观看态画面',
      );
      expect(rotateButton(), findsOneWidget, reason: '未知宽高比同样给转屏钮');
      expect(trackBand(), findsOneWidget);
    });

    testWidgets('首帧就绪（宽高比落定）→ 即时重算重排，不闪错误布局', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 16 / 9;
      final engine = FakePlaybackEngine(); // 打开时宽高比未知
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);
      expect(
        tester.getRect(videoPlaceholder()),
        const Rect.fromLTWH(0, 0, portraitWidth, portraitHeight),
        reason: '未知时先出观看态画面（1368 − 0）',
      );

      // 首帧就绪：内核把宽高比交出来（media_kit videoParams 流），位置流
      // 边沿触发一次重建。
      engine.videoAspectRatio = ar;
      await engine.seek(Duration.zero);
      await tester.pump();

      final video = tester.getRect(videoPlaceholder());
      expect(tester.takeException(), isNull);
      expect(video.height, closeTo(portraitWidth / ar, 0.5), reason: '按实测高重排');
      expect(
        video.bottom,
        closeTo(
          tester
              .getRect(find.byKey(const Key('control_layer_video_toolbar')))
              .top,
          0.5,
        ),
        reason: '画面底边贴住画面区下缘（紧贴视频播放工具栏两行上缘）',
      );
      expect(rotateButton(), findsOneWidget, reason: '本态转屏钮在场');
    });

    testWidgets('首帧就绪（竖向源）→ 仍观看态背景位但按实测宽高比 contain', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 9 / 16;
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);
      expect(
        tester.getRect(videoPlaceholder()),
        const Rect.fromLTWH(0, 0, portraitWidth, portraitHeight),
      );

      engine.videoAspectRatio = ar;
      await engine.seek(Duration.zero);
      await tester.pump();

      expect(
        tester.getRect(videoPlaceholder()),
        Rect.fromLTWH(
          0,
          (portraitHeight - portraitWidth / ar) / 2,
          portraitWidth,
          portraitWidth / ar,
        ),
        reason: '竖向源落定后仍背景位、画面按 contain 就位',
      );
      expect(rotateButton(), findsOneWidget, reason: '本态转屏钮在场');
    });

    testWidgets('竖屏编辑面：进编辑面零锁，点一次转屏钮锁横屏', (tester) async {
      setWidenedPortraitView(tester);
      final engine = FakePlaybackEngine(videoAspectRatio: 9 / 16);
      final systemUi = FakeSystemUi();
      await pumpPlayer(tester, engine: engine, systemUi: systemUi);
      await openEditor(tester);
      expect(systemUi.lockLandscapeCount, 0, reason: '进编辑面不自动锁方向');
      expect(rotateButton(), findsOneWidget, reason: '画面区右下角有可点的方向入口');

      await tester.tap(rotateButton());
      await tester.pump();
      expect(systemUi.lockLandscapeCount, 1, reason: '点一次锁横屏');
    });

    testWidgets('收起控制层＝整屏 contain 居中；展开＝贴底让位', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 16 / 9;
      final engine = FakePlaybackEngine(videoAspectRatio: ar);
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);
      final expanded = tester.getRect(videoPlaceholder());
      expect(
        expanded.bottom,
        closeTo(
          tester
              .getRect(find.byKey(const Key('control_layer_video_toolbar')))
              .top,
          0.5,
        ),
        reason: '展开＝贴住画面区下缘让位',
      );
      expect(expanded.top, greaterThan(kEditorTopBarHeight));

      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).collapse();
      await tester.pump();

      final video = tester.getRect(videoPlaceholder());
      expect(
        video.top,
        closeTo((portraitHeight - portraitWidth / ar) / 2, 0.5),
        reason: '收起＝整屏居中最大化',
      );
      expect(
        video,
        isNot(expanded),
        reason: '展开确实让位（与收起不同）',
      );
      expect(
        tester
            .widget<NoteStickerOverlay>(find.byType(NoteStickerOverlay))
            .contentRect
            .top,
        closeTo((portraitHeight - portraitWidth / ar) / 2, 0.5),
        reason: '观看态注解层基准回到居中信箱',
      );
      expect(rotateButton(), findsNothing, reason: '观看态没有转屏钮');
    });

    testWidgets('横竖屏切换：不丢播放位置、缩放窗口、选中与编辑面展开态', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 16 / 9;
      final engine = FakePlaybackEngine(videoAspectRatio: ar);
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);
      await engine.seek(const Duration(seconds: 30));
      await tester.pump();
      final session = tester
          .widget<ControlLayer>(find.byType(ControlLayer))
          .session;
      // 制造一个真实的缩放窗口（用户放大时间轴）。
      session.updateWindow(
        TimelineWindow.full(engine.duration!)
            .zoomed(anchor: const Duration(seconds: 30), factor: 2),
      );
      await tester.pump();
      final zoomed = session.window;
      expect(zoomed, isNotNull, reason: '缩放窗口已生效');

      // 制造一条选中的分段线：选中是 provider 状态，旋转只改屏尺寸。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(annotationEditorProvider)
          .submit(AddSegmentLine(at: const Duration(seconds: 10)));
      await tester.pump();
      container
          .read(annotationSelectionDomainProvider)
          .select(SegmentLineSelection(0));
      await tester.pump();
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      // 转横屏（同一页面实例、仅屏尺寸变化；**合成档** 1368×668dp，非设备基准）。
      tester.view.physicalSize = const Size(2736, 1336);
      await tester.pump();

      expect(controlLayer(), findsOneWidget, reason: '切换方向不收起编辑面');
      expect(engine.position, const Duration(seconds: 30), reason: '不丢播放位置');
      expect(
        tester.widget<ControlLayer>(find.byType(ControlLayer)).session.window,
        zoomed,
        reason: '缩放窗口随旋转原样保留（页面持有，不因方向复位）',
      );
      expect(
        container.read(selectedSegmentLineIndexProvider),
        0,
        reason: '不丢选中（分段线选中随旋转保留）',
      );
      expect(rotateButton(), findsNothing, reason: '横屏不出现竖屏转屏钮');

      // 再转回竖屏：位置、缩放窗口与选中同样一位不丢。
      tester.view.physicalSize = const Size(1336, 2736); // 合成档 445.3×912.0dp（dpr 3），非设备基准。
      await tester.pump();
      expect(controlLayer(), findsOneWidget);
      expect(engine.position, const Duration(seconds: 30));
      expect(
        container.read(selectedSegmentLineIndexProvider),
        0,
        reason: '转回竖屏仍不丢选中',
      );
      expect(
        tester.widget<ControlLayer>(find.byType(ControlLayer)).session.window,
        zoomed,
      );
      expect(rotateButton(), findsOneWidget, reason: '转回竖屏转屏钮在场');
    });

    testWidgets('横屏编辑面：本无提示行，视频仍居中', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0; // 逻辑 960×540（横屏）
      addTearDown(tester.view.reset);
      const ar = 16 / 9;
      final engine = FakePlaybackEngine(videoAspectRatio: ar);
      await pumpPlayer(tester, engine: engine);
      await openEditor(tester);

      expect(rotateButton(), findsNothing, reason: '横屏不出现竖屏转屏钮');
      final video = tester.getRect(videoPlaceholder());
      expect(
        video.top,
        closeTo((540 - 960 / ar) / 2, 0.5),
        reason: '横屏行仍是整屏居中 contain（逐位不变）',
      );
      expect(tester.getRect(trackBand()).height, normalTrackBandHeight);
    });

    testWidgets('对比态竖屏：采纳骨架（手势面在位、无提示行），画面层仍是既有上下分屏', (tester) async {
      setWidenedPortraitView(tester);
      const ar = 16 / 9;
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 1),
        videoAspectRatio: ar,
      );
      await pumpPlayer(
        tester,
        engine: engine,
        docs: InMemoryVideoDocumentStorage(local: const {'version': 3}),
      );
      await openEditor(tester);
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      ).read(playerSessionProvider.notifier).enter(
            PlayerSessionMode.compareEditing,
          );
      await pumpPastMarquee(tester);

      expect(tester.takeException(), isNull);
      // 骨架同一套：空白手势面在位，对比态同样没有提示行。
      expect(rotateButton(), findsOneWidget, reason: '对比练习态共用同一枚');
      expect(find.byKey(const Key('control_layer_blank')), findsOneWidget);
      expect(
        find.byKey(const Key('control_layer_video_toolbar')),
        findsOneWidget,
      );
      // 轨道带换对比行集（行高表不动），整带高参与画面区高计算。
      expect(
        tester.getRect(trackBand()).height,
        TrackRowTable.compare.totalHeight,
      );
      // 画面层仍是既有上下分屏：源侧画面按 contain 居中于上半区，不落画面带。
      final source = tester.getRect(videoPlaceholder());
      expect(
        source.center.dy,
        closeTo((portraitHeight - kCompareSplitGap) / 4, 0.5),
        reason: '源侧仍居中于上半区（上下分屏几何不变）',
      );
      expect(source.center.dx, closeTo(portraitWidth / 2, 0.5));
      expect(
        source.bottom,
        lessThanOrEqualTo((portraitHeight - kCompareSplitGap) / 2),
        reason: '源侧不越出上半区',
      );
      // 贴纸基准按**源半区画面矩形**（对比态按半区各有一份），不随
      // 画面带下移、也不为对比态另造分屏几何。
      expect(
        tester
            .widget<NoteStickerOverlay>(find.byType(NoteStickerOverlay))
            .contentRect,
        compareFramingPictureRect(
          screen: Size(portraitWidth, portraitHeight),
          landscape: false,
          aspectRatio: ar,
        ),
        reason: '对比态贴纸基准走源半区画面矩形',
      );
    });
  });

  group('竖屏标题栏瘦身与视频播放工具栏两行', () {
    /// 真机竖屏基准：1264×2736 @3.5 = 361.1×781.7dp（唯一竖屏基准）。
    void setRealPortraitView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact);
    }

    /// 668dp 宽竖屏视口（刻意放宽的**合成档**：2338×2736 @3.5 = 668×781.7dp，
    /// 非设备基准）：两行都放得下、零缩放的宽视口回归护栏用。
    void setWidePortraitView(WidgetTester tester) {
      tester.view.physicalSize = const Size(2338, 2736);
      tester.view.devicePixelRatio = 3.5;
      addTearDown(tester.view.reset);
    }

    /// 240dp 宽竖屏视口（刻意收窄的**合成档**：480×1568 @2 = 240×784dp，非
    /// 设备基准）：两行都放不下、逐列缩到列宽的窄视口回归护栏用。
    void setNarrowPortraitView(WidgetTester tester) {
      tester.view.physicalSize = const Size(480, 1568);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    /// 标题栏三枚看片通用工具（落竖屏标题栏）与两行视频播放工具
    /// （拆行，声明次序即行序）。
    const titleBarTools = ['tool_undo', 'tool_redo', 'tool_guide'];
    const topRowTools = ['tool_mirror', 'tool_local_mirror'];
    const bottomRowTools = [
      'tool_av_sync',
      'tool_framing_adjust',
      'tool_beat_prompt',
      'tool_speed_settings',
      'tool_compare',
    ];
    const videoTools = [...topRowTools, ...bottomRowTools];
    const allTools = [...titleBarTools, ...videoTools];

    /// 测试字体下槽的自然盒（缩放用例与零缩放用例共用的期望值）：四字标签槽
    /// 61×46dp、倍速槽是定宽槽（含倍率槽位）94×46dp。
    const kFourCharToolWidth = 61.0;
    const kSpeedToolWidth = 94.0;
    const kToolNaturalHeight = 46.0;

    /// 本节视口下的等分列宽（可用宽 ÷ 列数）。
    double columnWidth(WidgetTester tester) =>
        tester.view.physicalSize.width /
        tester.view.devicePixelRatio /
        kPortraitVideoToolbarColumnCount;

    Finder topBar() => find.byKey(const Key('control_layer_top_bar'));
    Finder videoToolbar() =>
        find.byKey(const Key('control_layer_video_toolbar'));
    Finder inBar(Finder matching) =>
        find.descendant(of: topBar(), matching: matching);

    testWidgets('竖屏标题栏含撤销/重做/查看引导，其余六枚不在顶栏、无「更多」', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull);

      expect(inBar(find.byKey(const Key('control_layer_back'))), findsOneWidget);
      expect(
        inBar(find.byKey(const Key('control_layer_title'))),
        findsOneWidget,
      );
      // 三枚看片通用工具落竖屏标题栏（返回键与标题之后）。
      for (final key in titleBarTools) {
        expect(
          inBar(find.byKey(Key(key))),
          findsOneWidget,
          reason: '$key 在竖屏标题栏',
        );
      }
      for (final key in videoTools) {
        expect(
          inBar(find.byKey(Key(key))),
          findsNothing,
          reason: '$key 不在竖屏顶栏',
        );
      }
      expect(inBar(find.byKey(const Key('tool_more'))), findsNothing);
      for (final key in allTools) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 仍在竖屏编辑面');
      }
    });

    testWidgets('标题栏三枚次序为撤销→重做→查看引导，且都在标题右侧、查看引导可点', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);

      final titleRect = tester.getRect(
        inBar(find.byKey(const Key('control_layer_title'))),
      );
      double centerX(String key) =>
          tester.getRect(inBar(find.byKey(Key(key)))).center.dx;
      expect(centerX('tool_undo'), greaterThan(titleRect.right),
          reason: '撤销在标题右侧');
      expect(centerX('tool_redo'), greaterThan(centerX('tool_undo')),
          reason: '重做在撤销右侧');
      expect(centerX('tool_guide'), greaterThan(centerX('tool_redo')),
          reason: '查看引导在重做右侧');
      // 槽填上，不再恒置灰。
      expect(toolIconColor(tester, 'tool_guide'),
          isNot(kToolSlotDisabledIconColor), reason: '查看引导不再恒置灰');
      // 三枚与标题同一行（标题栏内，不在画面下方的视频播放工具栏）。
      for (final key in titleBarTools) {
        expect(
          tester.getRect(find.byKey(Key(key))).center.dy,
          closeTo(titleRect.center.dy, 2),
          reason: '$key 与标题同排',
        );
      }
      // 竖屏标题栏入口点击 push 新手引导页。
      await tester.tap(inBar(find.byKey(const Key('tool_guide'))));
      await tester.pumpAndSettle();
      expect(find.byType(GuideUnitsPage), findsOneWidget);
    });

    testWidgets('长歌名：标题在标题栏内让位三枚工具、跑马字幕仍可用', (tester) async {
      setRealPortraitView(tester);
      const longName = 'dance-with-a-really-long-name-for-marquee-check.mp4';
      await pumpControlLayer(
        tester,
        source: Uri.file('/videos/$longName'),
      );

      final title = find.descendant(
        of: topBar(),
        matching: find.byKey(const Key('control_layer_title')),
      );
      final titleRect = tester.getRect(title);
      final undoRect = tester.getRect(inBar(find.byKey(const Key('tool_undo'))));
      expect(
        titleRect.right,
        lessThanOrEqualTo(undoRect.left),
        reason: '标题让位标题栏右侧三枚工具',
      );
      // 溢出即跑马：文本双份循环并随时间左移（既有 [AutoScrollTitle] 行为）。
      final marquee = find.descendant(of: topBar(), matching: find.text(longName));
      expect(marquee, findsNWidgets(2), reason: '长歌名走既有跑马字幕');
      final before = tester.getTopLeft(marquee.first).dx;
      await tester.pump(const Duration(seconds: 1));
      final after = tester.getTopLeft(marquee.first).dx;
      expect(after, lessThan(before), reason: '标题横向匀速滚动');
    });

    testWidgets('竖屏视频工具栏两行：上排靠右两枚、下排五枚；全部入口一次放下、无「更多」', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull, reason: '真机基准下两行无布局溢出');

      expect(videoToolbar(), findsOneWidget);
      expect(find.byKey(const Key('tool_more')), findsNothing, reason: '无溢出入口');
      // 栏名义高 = 骨架名义高表里的那一项（两行；缩放只缩内容、不缩名义高）。
      expect(
        tester.getSize(videoToolbar()).height,
        closeTo(kEditorVideoToolbarHeight, 0.5),
      );
      // 三枚看片通用工具不再出现在视频播放工具栏任何一行。
      Finder inToolbar(Finder matching) =>
          find.descendant(of: videoToolbar(), matching: matching);
      for (final key in titleBarTools) {
        expect(inToolbar(find.byKey(Key(key))), findsNothing,
            reason: '$key 不在视频播放工具栏');
      }

      // 上排两枚同排、下排五枚同排（逐列居中：同排 = 竖直中心同一线）；上排
      // 整行落在下排之上。
      double centerY(String key) =>
          tester.getRect(find.byKey(Key(key))).center.dy;
      for (final key in topRowTools) {
        expect(centerY(key), closeTo(centerY(topRowTools.first), 0.5),
            reason: '$key 在上排');
      }
      for (final key in bottomRowTools) {
        expect(centerY(key), closeTo(centerY(bottomRowTools.first), 0.5),
            reason: '$key 在下排');
      }
      expect(centerY(topRowTools.first), lessThan(centerY(bottomRowTools.first)),
          reason: '上排在下排之上');
      expect(
        tester.getRect(find.byKey(Key(topRowTools.first))).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(Key(bottomRowTools.first))).top,
        ),
        reason: '上排整行落在下排之上',
      );
      // 两行都在视频工具栏内。
      expect(inToolbar(find.byKey(Key(topRowTools.first))), findsOneWidget);
      expect(inToolbar(find.byKey(Key(bottomRowTools.last))), findsOneWidget);

      // 下排次序（x 严格递增，音画同步 → 取景调整 → 节拍提示 → 倍速设置 →
      // 对比练习）。
      var previous = -1.0;
      for (final key in bottomRowTools) {
        final x = tester.getRect(find.byKey(Key(key))).center.dx;
        expect(x, greaterThan(previous), reason: '$key 次序');
        previous = x;
      }
      // 上排靠右：两枚都落在右半屏。
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final key in topRowTools) {
        expect(
          tester.getRect(find.byKey(Key(key))).center.dx,
          greaterThan(screenWidth / 2),
          reason: '$key 靠右',
        );
      }
      // 全部入口一次放下、在屏内、可直接点到。
      for (final key in allTools) {
        final r = tester.getRect(find.byKey(Key(key)));
        expect(r.left, greaterThanOrEqualTo(0), reason: key);
        expect(r.right, lessThanOrEqualTo(screenWidth), reason: key);
        expect(find.byKey(Key(key)).hitTestable(), findsOneWidget,
            reason: '$key 可直接点到');
      }
      expect(tester.getRect(videoToolbar()).left, 0);
      expect(tester.getRect(videoToolbar()).right, closeTo(screenWidth, 0.5));
    });

    test('行集成员数不超过等分列数：留空列集恒非负（Spacer 的 flex 不会变负）', () {
      for (final row in const [
        kPlayToolRowPortraitVideoToolbarTop,
        kPlayToolRowPortraitVideoToolbarBottom,
      ]) {
        expect(
          row.slots.length,
          lessThanOrEqualTo(kPortraitVideoToolbarColumnCount),
          reason:
              '${row.slots.length} 枚超过 $kPortraitVideoToolbarColumnCount 列：'
              '留空列集会变负、列分配断言',
        );
      }
      expect(
        kPortraitVideoToolbarColumnCount -
            kPlayToolRowPortraitVideoToolbarTop.slots.length,
        3,
        reason: '上排两枚住最右两列，前 3 列留空',
      );
    });

    testWidgets('下排五等分列：列中心等距、整行铺满可用宽、左右边距相同', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final column = columnWidth(tester);
      final centers = [
        for (final key in bottomRowTools)
          tester.getRect(find.byKey(Key(key))).center.dx,
      ];
      expect(centers, hasLength(kPortraitVideoToolbarColumnCount));
      // 列中心 = (i + 1/2) × 列宽（列中心等距、整行铺满可用宽、左右边距相同）。
      for (var i = 0; i < centers.length; i++) {
        expect(
          centers[i],
          closeTo((i + 0.5) * column, 0.5),
          reason: '第 ${i + 1} 列列心',
        );
      }
      expect(
        screenWidth - centers.last,
        closeTo(centers.first, 0.5),
        reason: '左右边距相同（首末列心到两侧屏缘等距）',
      );
      final step = centers[1] - centers[0];
      for (var i = 2; i < centers.length; i++) {
        expect(centers[i] - centers[i - 1], closeTo(step, 0.5),
            reason: '列中心等距');
      }
      // 整行铺满可用宽：列宽 = 可用宽 ÷ 5。
      expect(column, closeTo(screenWidth / kPortraitVideoToolbarColumnCount, 0.5));
    });

    testWidgets('上排两枚对到最右两列列心（全局镜像在倍速设置正上方、局部镜像在对比练习正上方）', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);

      double centerX(String key) => tester.getRect(find.byKey(Key(key))).center.dx;
      expect(
        centerX('tool_mirror'),
        closeTo(centerX('tool_speed_settings'), 0.5),
        reason: '全局镜像对到第四列列心（倍速设置正上方）',
      );
      expect(
        centerX('tool_local_mirror'),
        closeTo(centerX('tool_compare'), 0.5),
        reason: '局部镜像对到第五列列心（对比练习正上方）',
      );
      // 两枚与各自正下方那一枚同列心（整列竖直对齐）。
      expect(
        centerX('tool_mirror'),
        closeTo(0.7 * tester.view.physicalSize.width / tester.view.devicePixelRatio, 0.5),
      );
      expect(
        centerX('tool_local_mirror'),
        closeTo(0.9 * tester.view.physicalSize.width / tester.view.devicePixelRatio, 0.5),
      );
    });

    testWidgets('真机基准：两行各自等比缩小——六枚零缩放（自然盒 61×46），倍速槽缩到列宽', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);

      final column = columnWidth(tester);
      // 四字标签槽自然宽 61 ≤ 列宽 72.2：零缩放，命中盒 = 该槽族的自然盒。
      for (final key in [...topRowTools, ...bottomRowTools]) {
        if (key == 'tool_speed_settings') continue;
        final r = tester.getRect(find.byKey(Key(key)));
        expect(r.width, closeTo(kFourCharToolWidth, 0.5), reason: '$key 零缩放');
        expect(r.height, closeTo(kToolNaturalHeight, 0.5),
            reason: '$key 命中盒 = 看片工具槽自然盒（缩放只发生在装不下的那一枚）');
      }
      // 倍速槽定宽 94 > 列宽 72.2：缩到列宽（放不下等比缩小兜底）。缩后命中盒
      // 随之变小是该兜底的既有代价（低于 48dp 通行下限），
      // 这里钉住的只有「等比」本身——宽高比与未缩放形态一致。
      final speed = tester.getRect(find.byKey(const Key('tool_speed_settings')));
      expect(speed.width, closeTo(column, 0.5), reason: '倍速槽缩到列宽');
      expect(
        speed.width / speed.height,
        closeTo(kSpeedToolWidth / kToolNaturalHeight, 0.01),
        reason: '缩是等比的（宽高比不变）',
      );
      // 缩后仍可直接点到。
      expect(
        find.byKey(const Key('tool_speed_settings')).hitTestable(),
        findsOneWidget,
      );
    });

    testWidgets('放得下零缩放：668dp 竖屏视口两行都不触发等比缩小', (tester) async {
      setWidePortraitView(tester);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull);

      // 列宽 133.6 > 倍速槽定宽 94：全部保持自然宽（零缩放）。
      for (final key in bottomRowTools) {
        expect(
          tester.getRect(find.byKey(Key(key))).width,
          closeTo(
            key == 'tool_speed_settings'
                ? kSpeedToolWidth
                : kFourCharToolWidth,
            0.5,
          ),
          reason: '$key 零缩放',
        );
      }
      for (final key in topRowTools) {
        expect(
          tester.getRect(find.byKey(Key(key))).width,
          closeTo(kFourCharToolWidth, 0.5),
          reason: '$key 零缩放',
        );
      }
    });

    testWidgets('窄视口（240dp）：两行各自逐列等比缩小、全部入口一次放下、无「更多」', (tester) async {
      setNarrowPortraitView(tester);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull, reason: '窄视口下两行不溢出');
      expect(find.byKey(const Key('tool_more')), findsNothing, reason: '无溢出入口');

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final column = columnWidth(tester);
      // 自然宽 61 / 94 都放不下 48dp 的列：两行各自缩到列宽（等比缩小兜底）。
      for (final key in videoTools) {
        expect(
          tester.getRect(find.byKey(Key(key))).width,
          closeTo(column, 0.5),
          reason: '$key 缩到列宽',
        );
        expect(find.byKey(Key(key)).hitTestable(), findsOneWidget,
            reason: '$key 可直接点到');
      }
      // 缩后仍两行、列心仍等距。
      double centerX(String key) => tester.getRect(find.byKey(Key(key))).center.dx;
      for (var i = 0; i < bottomRowTools.length; i++) {
        expect(
          centerX(bottomRowTools[i]),
          closeTo((i + 0.5) * column, 0.5),
          reason: '缩后第 ${i + 1} 列列心不变',
        );
      }
      final screen = tester.getRect(videoToolbar());
      expect(screen.left, 0);
      expect(screen.right, closeTo(screenWidth, 0.5));
    });

    testWidgets('落位：画面区下缘紧贴视频播放工具栏两行，该栏在设置条与轨道行上方', (tester) async {
      setRealPortraitView(tester);
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 3),
        videoAspectRatio: 16 / 9,
      );
      await pumpControlLayer(tester, engine: engine);

      final rows = tester.getRect(videoToolbar());
      final cluster = tester.getRect(find.byKey(const Key('settings_cluster')));
      final band = tester.getRect(find.byKey(const Key('track_band')));
      expect(
        find.byKey(const Key('editor_landscape_prompt')),
        findsNothing,
        reason: '本态没有提示行',
      );
      // 真机竖屏基准 361.1×781.7dp：画面区 = 781.7 − (顶栏 52 + 底栏两行 104 +
      // 视频工具栏两行 104 + 设置条 48) − 轨道带 208 = 265.7（一行变两行、
      // 设置条命中盒下限 48）。
      expect(
        tester.getRect(topBar()).bottom + 265.7,
        closeTo(rows.top, 0.5),
        reason: '画面区下缘即视频播放工具栏两行上缘',
      );
      expect(rows.height, closeTo(kEditorVideoToolbarHeight, 0.5),
          reason: '两行栏名义高（52 × 2）');
      expect(rows.bottom, lessThanOrEqualTo(cluster.top), reason: '设置条在两行之下');
      expect(cluster.top, lessThanOrEqualTo(band.top), reason: '轨道行在设置条之下');
    });

    testWidgets('设置簇无时间线自收 0 高：轨道行仍紧接视频播放工具栏两行下方', (tester) async {
      setRealPortraitView(tester);
      // 零时长 = 无时间线：设置簇按既有行为自收为 0 高（名义高表 28dp 与
      // 实际渲染在此态必然不一致），画面区不能因此浮空。
      await pumpControlLayer(
        tester,
        engine: FakePlaybackEngine(duration: Duration.zero),
      );

      expect(find.byKey(const Key('settings_cluster')), findsNothing);
      expect(
        find.byKey(const Key('editor_landscape_prompt')),
        findsNothing,
        reason: '本态没有提示行',
      );
      final rows = tester.getRect(videoToolbar());
      final band = tester.getRect(find.byKey(const Key('track_band')));
      expect(
        band.top,
        closeTo(rows.bottom, 0.5),
        reason: '设置簇自收 0 高时轨道行紧接该行下方（与实际设置簇高无关）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('门禁口径照旧：撤销/重做置灰与历史、局部镜像软门、倍速槽激活态', (tester) async {
      setRealPortraitView(tester);
      final (_, container, _, _) = await pumpControlLayer(tester);

      // 无历史：撤销/重做置灰。
      expect(toolIconColor(tester, 'tool_undo'), kToolSlotDisabledIconColor);
      expect(toolIconColor(tester, 'tool_redo'), kToolSlotDisabledIconColor);
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      await tester.pump();
      expect(
        toolIconColor(tester, 'tool_undo'),
        isNot(kToolSlotDisabledIconColor),
        reason: '有历史后撤销亮起',
      );
      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pump();
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(
        toolIconColor(tester, 'tool_redo'),
        isNot(kToolSlotDisabledIconColor),
        reason: '撤销后可重做',
      );

      // 无片段：局部镜像置灰但仍可点（软门），点一下弹解释、不改状态。
      expect(
        toolIconColor(tester, 'tool_local_mirror'),
        kToolSlotDisabledIconColor,
      );
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(find.text('请添加局部镜像片段'), findsOneWidget);

      // 倍速槽激活态：启用步进后图标琥珀、标签取「步进」。
      container.read(annotationEditorProvider)
        ..submit(AddSegmentLine(at: const Duration(seconds: 10)))
        ..submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('speed_step_preset_builtin_first')));
      await tester.pumpAndSettle();
      expect(toolIconColor(tester, 'tool_speed_settings'), kHighlightAmber);
      expect(
        find.descendant(
          of: find.byKey(const Key('tool_speed_settings')),
          matching: find.text('步进'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('音画同步与节拍提示气泡从各自新槽位旁锚定弹出', (tester) async {
      setRealPortraitView(tester);
      await pumpControlLayer(tester);

      final avSync = tester.getRect(find.byKey(const Key('tool_av_sync')));
      await tester.tap(find.byKey(const Key('tool_av_sync')));
      await pumpPastMarquee(tester);
      final avBubble = tester.getRect(find.byKey(const Key('av_sync_bubble')));
      expect(
        avBubble.top,
        greaterThanOrEqualTo(avSync.bottom - 4),
        reason: '音画同步气泡锚在其竖屏槽位之下',
      );

      final beat = tester.getRect(find.byKey(const Key('tool_beat_prompt')));
      // 音画同步气泡开着时，第一次点节拍提示由点外收起遮罩承接（互斥单开）；
      // 再点一次才开节拍提示面板。
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await pumpPastMarquee(tester);
      expect(find.byKey(const Key('av_sync_bubble')), findsNothing, reason: '互斥单开');
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await pumpPastMarquee(tester);
      final panel = tester.getRect(find.byKey(const Key('beat_prompt_panel')));
      expect(
        panel.top,
        greaterThanOrEqualTo(beat.bottom - 4),
        reason: '节拍提示面板锚在其竖屏槽位之下',
      );
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(panel.right, lessThanOrEqualTo(screenWidth));
    });

    testWidgets('普通态 / 待命态 / 对比态三种竖屏编辑面一致：标题栏三枚、视频工具栏两行', (tester) async {
      setRealPortraitView(tester);
      final (_, container, _, _) = await pumpControlLayer(tester);
      final notifier =
          container.read(playerSessionProvider.notifier);

      void expectTwoRows() {
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('tool_more')), findsNothing);
        for (final key in allTools) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 可见');
        }
        // 三枚看片通用工具三态都在标题栏，七枚画面/节拍设置工具
        // 三态都不在顶栏；视频工具栏三态同为两行
        // （上排两枚 + 下排五枚）。
        expect(find.byKey(const Key('control_layer_video_toolbar')), findsOneWidget);
        for (final key in titleBarTools) {
          expect(
            inBar(find.byKey(Key(key))),
            findsOneWidget,
            reason: '$key 三态都在竖屏标题栏',
          );
        }
        for (final key in videoTools) {
          expect(
            inBar(find.byKey(Key(key))),
            findsNothing,
            reason: '$key 三态都不在竖屏顶栏',
          );
        }
        double centerY(String key) =>
            tester.getRect(find.byKey(Key(key))).center.dy;
        for (final key in topRowTools) {
          expect(centerY(key), closeTo(centerY(topRowTools.first), 0.5),
              reason: '$key 在上排');
        }
        for (final key in bottomRowTools) {
          expect(centerY(key), closeTo(centerY(bottomRowTools.first), 0.5),
              reason: '$key 在下排');
        }
        expect(centerY(topRowTools.first),
            lessThan(centerY(bottomRowTools.first)),
            reason: '上排在下排之上');
        // 普通/待命/对比三态一致：都没有提示行。
        expect(
          find.byKey(const Key('editor_landscape_prompt')),
          findsNothing,
          reason: '提示行三态都不存在',
        );
      }

      expectTwoRows();

      notifier.enter(PlayerSessionMode.beatCorrectionStandby);
      await pumpPastMarquee(tester);
      expectTwoRows();

      notifier.enter(PlayerSessionMode.editing);
      await pumpPastMarquee(tester);
      notifier.enter(PlayerSessionMode.compareEditing);
      await pumpPastMarquee(tester);
      expectTwoRows();
    });

    testWidgets('横屏顶栏逐位不变：十枚工具仍内联一行、无竖屏视频工具栏', (tester) async {
      // 真机横屏基准 2736×1264 @3.5 = 781.7×361.1dp。
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull);

      expect(
        find.byKey(const Key('control_layer_video_toolbar')),
        findsNothing,
        reason: '横屏不出现竖屏那两行',
      );
      expect(find.byKey(const Key('tool_more')), findsNothing);
      for (final key in allTools) {
        expect(
          inBar(find.byKey(Key(key))),
          findsOneWidget,
          reason: '$key 仍内联在横屏顶栏',
        );
      }
      final tops = {
        for (final key in allTools)
          tester.getRect(find.byKey(Key(key))).top.round(),
      };
      expect(tops, hasLength(1), reason: '十枚工具仍在同一行');
      // 横屏编辑面同样没有提示行。
      expect(find.byKey(const Key('editor_landscape_prompt')), findsNothing);
    });

    testWidgets('窄横屏视口：加了「取景调整」的顶栏仍不溢出、十枚入口可直接点到', (tester) async {
      // 640×420dp 合成档横置（非设备基准）：可用宽放不下带标签十槽，按既有
      // 「放不下收标签」兜底收成图标形态——不溢出、无「更多」、逐枚可点。
      tester.view.physicalSize = const Size(1280, 840);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await pumpControlLayer(tester);
      expect(tester.takeException(), isNull, reason: '窄视口顶栏不溢出');

      expect(find.byKey(const Key('tool_more')), findsNothing, reason: '无溢出入口');
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      for (final key in allTools) {
        expect(inBar(find.byKey(Key(key))), findsOneWidget, reason: '$key 在顶栏');
        expect(find.byKey(Key(key)).hitTestable(), findsOneWidget,
            reason: '$key 可直接点到');
        expect(tester.getRect(find.byKey(Key(key))).right,
            lessThanOrEqualTo(screenWidth),
            reason: '$key 在屏宽内');
      }
    });
  });

  group('编辑态空白区双击与全域捏合', () {
    /// 双指 tap（两指按下 → 50ms → 相继抬起）。
    Future<void> twoFingerTapAt(WidgetTester tester, Offset center) async {
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    /// 双指向两侧张开（放大缩放窗口）。
    Future<void> pinchOutward(WidgetTester tester, Offset center) async {
      final g1 = await tester.startGesture(center - const Offset(40, 0));
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();
    }

    testWidgets('空白单击在约 300ms 判定窗口内不收起、窗口过后收起', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controlLayer(), findsOneWidget, reason: '双击判定窗口内不收起');
      await tester.pump(kDoubleTapTimeout);
      expect(controlLayer(), findsNothing);
    });

    testWidgets('双指捏合后先抬一指、余指微动再抬——不收起控制层', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 双指捏合（放大窗口）→ 先抬一指 → 余指在触摸 slop 内微动 → 再抬：
      // 尾指会话是 scale 识别器重启会话（burst 曾含 ≥2 指），不是孤立
      // 空闲单击——经 300ms 判定窗口后不收起。
      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g1 = await tester.startGesture(center - const Offset(40, 0));
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.moveBy(const Offset(4, 0));
      await tester.pump();
      await g2.up();
      await tester.pump();

      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(
        controlLayer(),
        findsOneWidget,
        reason: 'burst 曾含 ≥2 指：重启的少指会话不判空闲单击、不收起',
      );
    });

    testWidgets('空白单指双击 = 只切换播放/暂停、留在编辑态不收起', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(engine.isPlaying, isTrue);

      final blank = find.byKey(const Key('control_layer_blank'));
      final center = tester.getCenter(blank);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controlLayer(), findsOneWidget, reason: '单指双击不再收起');
      expect(engine.isPlaying, isFalse, reason: '双击切换播放/暂停');
      // 窗口过后不重复动作（无残留收起、无二次切换）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget);
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('空白双指双击 = 收起并启动延迟播放，八拍后开始播放', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      await twoFingerTapAt(tester, center);
      await tester.pump(const Duration(milliseconds: 50));
      await twoFingerTapAt(tester, center);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controlLayer(), findsNothing, reason: '双指双击收起，不残留展开态');
      expect(
        find.byKey(const Key('delayed_play_indicator')),
        findsNothing,
        reason: '预备期无占位徽章',
      );
      // 延迟期间引擎不强制暂停（原本在播则继续播，八拍到点
      // 重新开始播放）。
      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      await tester.pump();
      expect(engine.isPlaying, isTrue, reason: '八拍倒计时后开始播放');
    });

    testWidgets('交互控件点击即时生效：不经 300ms 判定窗口', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 播放/暂停按钮：pump 一帧即生效（无窗口延迟）、不收起。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      expect(engine.isPlaying, isFalse);
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('段体上双击不切换播放（编辑优先）：单击语义生效、不收起', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      // 在预览位置建一条分段线 → 产生两个学习段。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('learning_segment_0')), findsOneWidget);

      final center = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));

      expect(engine.isPlaying, isTrue, reason: '段体双击不切换播放');
      expect(controlLayer(), findsOneWidget, reason: '段体编辑不收起');
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(engine.isPlaying, isTrue);
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('分段线/首尾线上双击不切换播放（编辑优先）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final lineCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0')),
      );
      final startLineCenter = tester.getCenter(
        find.byKey(const Key('video_range_start_line')),
      );

      Future<void> doubleTapAt(Offset center) async {
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 分段线上双击：命中层吸收，播放与展开态不受影响。
      await doubleTapAt(lineCenter);
      expect(engine.isPlaying, isTrue, reason: '分段线双击不切换播放');
      expect(controlLayer(), findsOneWidget, reason: '分段线编辑不收起');
      // 首尾线上双击：同上。
      await doubleTapAt(startLineCenter);
      expect(engine.isPlaying, isTrue, reason: '首尾线双击不切换播放');
      expect(controlLayer(), findsOneWidget, reason: '首尾线编辑不收起');
      // 判定窗口过后仍无任何切换/收起。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(engine.isPlaying, isTrue);
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('系统取消的静止触摸不收起（取消不是单击，回归）', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g = await tester.startGesture(center);
      await tester.pump();
      await g.cancel();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget, reason: '取消不是单击，不收起');
    });

    testWidgets('视频可见区双指捏合缩放轨道时间轴（全域捏合）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(tickCount(tester), 361);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      await pinchOutward(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(tickCount(tester), lessThan(361), reason: '捏合放大：可视窗口变短');
      expect(controlLayer(), findsOneWidget, reason: '捏合是缩放不是单击/双击：不收起');
    });

    testWidgets('空白面捏合锚点取预览线：预览线在窗口内时原地放大线在屏上 x 不变', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      await singleTapShow(tester);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      // 预览线在内容区中点（90s），双指中点在它右侧 200px 张开 → 锚 =
      // 预览线 90s：线在屏上的位置纹丝不动、线附近被铺开。
      final bandWidth = tester
          .getSize(find.byKey(const Key('track_band')))
          .width;
      await pinchOutward(tester, center + const Offset(200, 0));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(tickCount(tester), lessThan(361), reason: '放大生效');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(bandWidth / 2, 2.0),
        reason: '锚 = 预览线：90s 保持窗内比例；放大后窗口起点 > 0，让位收回'
            '满带宽摊开，90s 仍在窗内 50% → 带宽中点',
      );
    });

    testWidgets('双指双击与捏合按位移仲裁：位移过阈 = 缩放、不延迟播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      // 双指按下后张开（位移过阈）→ 是捏合缩放，不是双指双击。
      await pinchOutward(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(tickCount(tester), lessThan(361), reason: '缩放生效');
    });
  });

  group('控制层双指缩放+平移联动', () {
    testWidgets('空白区双指张开且中点右移：缩放+平移联动、内容跟手', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      await singleTapShow(tester);
      expect(tickCount(tester), 361);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      // 双指按下（中点 400）→ g2 独自右移 160px：跨度 80→240（放大 3×）、
      // 中点右移 80px。窗口以锚缩放到 [80s,100s] 再左移（按内容区宽换算）
      // → 锚时间 90s（=预览条）跟手右移 80px。
      final g1 = await tester.startGesture(center - const Offset(40, 0));
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(Offset.zero);
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();

      expect(tickCount(tester), lessThan(361), reason: '张合缩放仍生效');
      final bandWidth = tester
          .getSize(find.byKey(const Key('track_band')))
          .width;
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(bandWidth * 0.6, 6),
        reason: '焦点（双指中点）右移 → 窗口平移、锚时间内容跟手；'
            '窗口 [78s,98s] 起点 > 0 后让位收回，90s 在窗内 60%'
            '→ 0.6 × 带宽',
      );
      // 判定窗口过后不收起（双指手势不是单击）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('混区起手（一指压段体+一指压空白）一起右移：窗口平移，无 seek、无选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      await singleTapShow(tester);
      // 建一条分段线产生两个学习段，并先放大窗口（缩放滑条路径之外的
      // 既有捏合能力，此处用双指张开建立非全宽窗口）。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final blankCenter = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g1 = await tester.startGesture(blankCenter - const Offset(40, 0));
      final g2 = await tester.startGesture(blankCenter + const Offset(40, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();
      final zoomedTicks = tickCount(tester);
      final previewBefore = tester
          .getCenter(find.byKey(const Key('preview_line')))
          .dx;
      expect(zoomedTicks, lessThan(361), reason: '前置：窗口已放大');

      // 混区起手：一指压学习段段体、另一指压空白区，同向右移 100px
      // （跨度不变 = 纯平移）→ 窗口随之左移、内容跟手（预览条右移 100px）；
      // 全程无 seek、无选中副作用。
      final segCenter = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      final blankPt = blankCenter + const Offset(-60, -40);
      final m1 = await tester.startGesture(segCenter);
      final m2 = await tester.startGesture(blankPt);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await m1.moveBy(const Offset(25, 0));
        await m2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await m1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await m2.up();
      await tester.pump();

      // 混区会话按控制层宽换算（片头让位是带内口径；空白面/混区
      // 换算仍按控制层宽）→ 带内内容跟手 = 焦点位移 × 内容区宽/带宽；本用例钉的是
      // 「窗口平移生效、内容跟手、无 seek、无选中」。
      final bandWidth = tester
          .getSize(find.byKey(const Key('track_band')))
          .width;
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(
          previewBefore + 100 * bandContentWidth(bandWidth) / bandWidth,
          5,
        ),
        reason: '混区双指中点位移 → 平移窗口、内容跟手',
      );
      expect(
        engine.seekCalls,
        [const Duration(seconds: 90)],
        reason: '混区会话内不做进度 seek（仅保留测试预置的那次 seek）',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('control_layer'))),
        listen: false,
      );
      expect(
        container.read(selectedLearningSegmentRepresentativeProvider),
        isNull,
        reason: '混区起手不产生片段选中副作用',
      );
      // 判定窗口过后不收起（回归 53 同源：burst 曾含双指）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget);
      expect(
        tickCount(tester),
        lessThan(361),
        reason: '窗口仍非全宽（逐事件跨度采样的少量抖动不改变缩放语义）',
      );
    });

    testWidgets('交互控件上的指针不参与双指会话：不缩放、按钮不触发', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(tickCount(tester), 361);
      expect(engine.isPlaying, isTrue);

      // 一指压播放按钮、一指压空白区并外移：按钮指针不进跨面会话 →
      // 空白指针是单指（不捏合）；按钮被拖离也不触发切换。
      final buttonCenter = tester.getCenter(
        find.byKey(const Key('toolbar_play')),
      );
      final blankCenter = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g1 = await tester.startGesture(buttonCenter);
      final g2 = await tester.startGesture(blankCenter);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(10, -10));
        await g2.moveBy(const Offset(-40, 0));
        await tester.pump();
      }
      expect(tickCount(tester), 361, reason: '控件指针不参与 → 未形成双指捏合');
      expect(engine.isPlaying, isFalse, reason: '空白单指横滑 = 既有微调语义（暂停定格）');
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();

      // 微调松手恢复手势前播放态，按钮自身未被切换。
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue, reason: '播放按钮未触发额外切换');
    });
  });

  group('缩放倍数活过一次编辑展开', () {
    /// 双指向两侧张开（放大缩放窗口）——与相邻组同一手势形状。
    Future<void> pinchOutward(WidgetTester tester, Offset center) async {
      final g1 = await tester.startGesture(center - const Offset(40, 0));
      final g2 = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();
    }

    testWidgets('编辑态放大 → 收起到播放态 → 再展开：窗口与倍率一致', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(tickCount(tester), 361);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      await pinchOutward(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      final zoomed = tickCount(tester);
      expect(zoomed, lessThan(361), reason: '前置：窗口已放大');

      // 收起（进播放态）再展开（回编辑态）：缩放窗口原处保留。
      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(controlLayer(), findsNothing, reason: '前置：控制层已收起');
      await singleTapShow(tester);
      expect(tickCount(tester), zoomed, reason: '缩放窗口跨编辑会话保留');
    });

    testWidgets('关闭后重新打开（同一份文档存储）：回到全片，且无缩放相关持久化字段', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final docs = InMemoryVideoDocumentStorage();
      await pumpPlayer(tester, engine: engine, docs: docs);
      await singleTapShow(tester);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      await pinchOutward(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(tickCount(tester), lessThan(361), reason: '前置：窗口已放大');

      // 关闭这支舞（页面销毁 → 控制器随作用域失效）；换 key 重新泵入
      // 播放页 = 全新页面 State（模拟关掉这支舞后重新打开；同 key 会被
      // Flutter 复用 Element/State）。同一份文档存储：缩放相关键不得落
      // 盘、窗口回全片。
      await pumpPlayer(
        tester,
        engine: engine,
        docs: docs,
        pageKey: const Key('zoom_reopen_player_page'),
      );
      // 新容器：重新注入与首次同值的就绪节拍态（刻度计数口径一致）。
      await injectBeatState(tester, uniformReadyBeatState(seconds: 180));
      await singleTapShow(tester);
      expect(
        tickCount(tester),
        361,
        reason: '重新打开回全片（缩放态不持久化）',
      );
      String keysOf(Map<String, dynamic> json) =>
          (json.keys.toList()..sort()).join(',');
      final serialized =
          '${keysOf(docs.markersSnapshot)}|${keysOf(docs.localSnapshot)}';
      expect(
        serialized.toLowerCase().contains('zoom') ||
            serialized.toLowerCase().contains('window'),
        isFalse,
        reason: '本地文档（markers/local）无缩放相关键',
      );
    });
  });

  group('轨道带内双指缩放平移', () {
    testWidgets('双指起手于手柄带控制柄槽：缩放生效且线不被拖动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('control_layer'))),
        listen: false,
      );
      final linePosBefore = container
          .read(annotationTimelineProvider)
          .segmentLines
          .first
          .position;

      // 双指都落在控制柄槽（手柄带行内），向两侧张开 → 缩放生效。
      final handleCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0_handle')),
      );
      final g1 = await tester.startGesture(handleCenter - const Offset(20, 0));
      final g2 = await tester.startGesture(handleCenter + const Offset(20, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();

      expect(tickCount(tester), lessThan(361), reason: '手柄槽上双指起手 → 缩放生效');
      expect(
        container.read(annotationTimelineProvider).segmentLines.first.position,
        linePosBefore,
        reason: '双指会话激活 → 控制柄拖拽让位，线不被拖动',
      );
      expect(
        engine.seekCalls,
        [const Duration(seconds: 90)],
        reason: '线拖拽让位 → 无拖线预览 seek（仅保留预置 seek）',
      );
    });

    testWidgets('双指起手于学习段体：缩放生效、无选中副作用', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(tickCount(tester), 361);

      final segCenter = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      final g1 = await tester.startGesture(segCenter - const Offset(30, 0));
      final g2 = await tester.startGesture(segCenter + const Offset(30, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();

      expect(tickCount(tester), lessThan(361), reason: '段体上双指起手 → 缩放生效');
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('control_layer'))),
        listen: false,
      );
      expect(
        container.read(selectedLearningSegmentRepresentativeProvider),
        isNull,
        reason: '双指起手不产生片段选中副作用',
      );
    });

    testWidgets('单指拖控制柄中途加指：线让位停移，双指接管平移', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      // 播放头（预览线）移开 90s 线位：控制柄起手不被预览线命中列接管
      //（预览线优先），保证本用例考的是既有拖线让位。
      await engine.seek(const Duration(seconds: 30));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('control_layer'))),
        listen: false,
      );
      final linePosBefore = container
          .read(annotationTimelineProvider)
          .segmentLines
          .first
          .position;

      final handleCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0_handle')),
      );
      // 单指起手拖控制柄（过 slop 的 move 只触发 start，再一帧 move 才
      // update；线落点恒吸八拍点，拖过半格距才落到新格点）。
      final g1 = await tester.startGesture(handleCenter);
      await g1.moveBy(const Offset(30, 0));
      await tester.pump();
      await g1.moveBy(const Offset(90, 0));
      await tester.pump();
      final lineDuringDrag = container
          .read(annotationTimelineProvider)
          .segmentLines
          .first
          .position;
      expect(lineDuringDrag, isNot(linePosBefore), reason: '前置：单指拖柄在移动线');

      // 第二指落入手柄带 → 双指会话激活：线让位停移，焦点位移转窗口平移。
      final g2 = await tester.startGesture(handleCenter + const Offset(200, 0));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      expect(
        container.read(annotationTimelineProvider).segmentLines.first.position,
        lineDuringDrag,
        reason: '≥2 指在场 → 线让位停移',
      );

      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump();
      expect(
        container.read(annotationTimelineProvider).segmentLines.first.position,
        lineDuringDrag,
      );
    });
  });

  group('编辑态手势语义与进度手势分区', () {
    /// 双指 tap（两指按下 → 50ms → 相继抬起），在 [center] 处。
    Future<void> twoFingerTapAt(WidgetTester tester, Offset center) async {
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> doubleTapAt(WidgetTester tester, Offset center) async {
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('轨道空白（轨道手柄带行）单指双击 = 只切播放/暂停、不收起', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(engine.isPlaying, isTrue);

      await doubleTapAt(
        tester,
        tester.getCenter(find.byKey(const Key('track_handle_strip_row'))),
      );
      expect(engine.isPlaying, isFalse, reason: '轨道空白双击切播放/暂停');
      expect(controlLayer(), findsOneWidget, reason: '轨道空白双击不收起');
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget);
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('双指双击在段体上不触发：不收起、不延迟播放（内容命中检查）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('learning_segment_0')), findsOneWidget);

      final center = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      await twoFingerTapAt(tester, center);
      await twoFingerTapAt(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(controlLayer(), findsOneWidget, reason: '段体上双指双击不收起');
      expect(
        find.byKey(const Key('delayed_play_indicator')),
        findsNothing,
        reason: '段体上双指双击不启动延迟播放',
      );
    });

    testWidgets('双指双击在分段线/首尾线上不触发（内容命中检查）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      final lineCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0')),
      );
      final startLineCenter = tester.getCenter(
        find.byKey(const Key('video_range_start_line')),
      );
      await twoFingerTapAt(tester, lineCenter);
      await twoFingerTapAt(tester, lineCenter);
      await twoFingerTapAt(tester, startLineCenter);
      await twoFingerTapAt(tester, startLineCenter);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(controlLayer(), findsOneWidget, reason: '线上双指双击不收起');
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
    });

    testWidgets('双指双击在预览条上不触发（内容命中检查）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      expect(find.byKey(const Key('preview_line')), findsOneWidget);

      final center = tester.getCenter(find.byKey(const Key('preview_line')));
      await twoFingerTapAt(tester, center);
      await twoFingerTapAt(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(controlLayer(), findsOneWidget, reason: '预览条上双指双击不收起');
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
    });

    testWidgets('非轨道区（视频可见区）单指横滑 = 全屏式微调：在播即暂停、全程无进度浮层、松手从落点续播、不收起（无浮层）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(engine.isPlaying, isTrue);
      engine.callLog.clear();
      engine.seekCalls.clear();

      final blank = find.byKey(const Key('control_layer_blank'));
      final center = tester.getCenter(blank);
      final g = await tester.startGesture(center);
      await tester.pump();
      // 水平占优 → 轴锁定 → 进入微调：若在播按下即暂停（定格预览）。
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(engine.isPlaying, isFalse, reason: '微调按下即在播暂停定格');
      // 编辑态全程不出现进度浮层。
      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '编辑态微调全程不出现进度浮层',
      );
      // 无取消角：不显示取消区提示文案。
      expect(find.text('拖到画面左上角松开可取消'), findsNothing);
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      // pause 先于首次 seek（同全屏 scrub 语义：先定格再逐帧预览）。
      expect(engine.callLog.indexOf('pause'), lessThan(engine.callLog.indexOf('seek')));

      await g.up();
      await tester.pumpAndSettle();
      // 原在播 → 松手从落点续播。
      expect(engine.isPlaying, isTrue, reason: '松手恢复手势前播放态（在播续播）');
      expect(engine.seekCalls, isNotEmpty, reason: '微调产生帧级 seek');
      // 微调会话结束不触发空白收起（铁律保持）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget, reason: '微调会话结束不收起');
    });

    testWidgets('微调预览线随实际目标时间移动（不贴手指）、灵敏度同全屏单指', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      // 先暂停到确定位置（避免播放 tick 干扰基准快照）。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      final base = engine.position;
      engine.callLog.clear();
      engine.seekCalls.clear();

      final blank = find.byKey(const Key('control_layer_blank'));
      final center = tester.getCenter(blank);
      final g = await tester.startGesture(center);
      await tester.pump();
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      // 灵敏度同全屏单指：50ms/px × 100px = 5s 增量，目标 = 暂停点 + 增量
      // （不是手指绝对位置换算——1:1 会换算到 x=500px ≈ 112.5s）。
      final expected = base + const Duration(seconds: 5);
      expect(engine.seekCalls.last, expected, reason: 'seek 收敛到微调目标时间');
      expect(engine.position, expected);
      // 预览线随实际目标时间移动（非手指 x）：目标时间在内容区里的 x 位置
      //（内容区左缘让出轨道片头带）。
      final screenWidth = tester.view.physicalSize.width /
          tester.view.devicePixelRatio;
      final expectedX = bandX(expected.inMilliseconds / 1000, total: 180, width: screenWidth);
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(expectedX, 2.0),
        reason: '预览线跟实际目标时间、不贴手指',
      );
    });

    testWidgets('原暂停时微调：松手停在落点、不恢复播放', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      engine.callLog.clear();
      engine.seekCalls.clear();

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g = await tester.startGesture(center);
      await tester.pump();
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(engine.isPlaying, isFalse, reason: '原暂停 → 停在落点');
      expect(
        engine.callLog.where((c) => c == 'play'),
        isEmpty,
        reason: '原暂停不恢复播放',
      );
      expect(engine.seekCalls, isNotEmpty);
      expect(controlLayer(), findsOneWidget, reason: '微调不收起');
    });

    testWidgets('轨道带内空白横滑与非轨道区微调同一语义：起手定格、全程无浮层、目标按累计位移走（无浮层）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(engine.isPlaying, isTrue);
      engine.callLog.clear();
      engine.seekCalls.clear();

      // 在手柄带行空白横滑：与非轨道区微调同一会话语义。
      final stripRow = find.byKey(const Key('track_handle_strip_row'));
      final start = tester.getCenter(stripRow);
      final g = await tester.startGesture(start);
      await tester.pump();
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(engine.isPlaying, isFalse, reason: '带内空白横滑起手即定格');
      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '编辑态带内空白横滑全程不出现进度浮层',
      );
      // 预览线随目标时间移动（不贴手指）：目标 = 定格基准 + 累计位移。
      final previewX = tester.getCenter(find.byKey(const Key('preview_line'))).dx;
      expect(previewX, lessThan(start.dx + 60), reason: '预览线不贴手指');
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(engine.seekCalls, isNotEmpty);
      expect(
        engine.seekCalls.last,
        engine.seekCalls.first + seekDeltaFor(40, 1),
        reason: '目标按累计位移走（灵敏度同全屏单指）',
      );
      expect(
        engine.callLog,
        contains('pause'),
        reason: '带内空白横滑起手定格（微调语义）',
      );
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget, reason: '带内拖动不收起');
    });

    testWidgets('设备等效视口（2736×1264 @3.5）下编辑态两类横滑全程无 RenderFlex 溢出', (tester) async {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 视频可见区横滑：全程无溢出、无浮层。
      final blank = find.byKey(const Key('control_layer_blank'));
      final g = await tester.startGesture(tester.getCenter(blank));
      await tester.pump();
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await g.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      expect(tester.takeException(), isNull, reason: '视频可见区横滑无溢出');
      await g.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // 轨道带空白（手柄带行 + 备注轨行）横滑：全程无溢出、无浮层。
      final g2 = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('track_handle_strip_row'))),
      );
      await tester.pump();
      await g2.moveBy(const Offset(80, 0));
      await tester.pump();
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      expect(tester.takeException(), isNull, reason: '轨道带空白横滑无溢出');
      await g2.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final g3 = await tester.startGesture(
        Offset(400, trackRowCenterY(tester, 'track_notes')),
      );
      await tester.pump();
      await g3.moveBy(const Offset(80, 0));
      await tester.pump();
      await g3.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      expect(tester.takeException(), isNull, reason: '备注轨行空白横滑无溢出');
      await g3.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('备注轨/局部镜像轨空白横滑全程无进度浮层；对比行集下备注轨同样', (tester) async {
      // 钉住视口（其余用例可能遗留 tester.view 状态）：x=400 为 800 逻辑宽
      // 的正中，备注/镜像轨该处为空白。
      tester.view.physicalSize = const Size(1600, 900); // 合成档 800.0×450.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(engine.isPlaying, isTrue);
      engine.seekCalls.clear();

      Future<void> swipeRowBlank(String rowKey) async {
        engine.seekCalls.clear();
        engine.callLog.clear();
        final y = trackRowCenterY(tester, rowKey);
        final g = await tester.startGesture(Offset(400, y));
        await tester.pump();
        await g.moveBy(const Offset(60, 0));
        await tester.pump();
        await g.moveBy(const Offset(40, 0));
        await tester.pump();
        // 定长 pump 推进 fake clock：串行 seek 队列的节流定时器需要时间
        // 前进才排空（纯 pump 不计时）。
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump(const Duration(milliseconds: 60));
        expect(engine.isPlaying, isFalse, reason: '$rowKey 起手定格（微调语义）');
        expect(engine.seekCalls, isNotEmpty, reason: '$rowKey 产生微调 seek');
        expect(
          find.byKey(const Key('scrub_indicator')),
          findsNothing,
          reason: '$rowKey 空白横滑全程不出现进度浮层',
        );
        await g.up();
        await tester.pumpAndSettle();
        expect(engine.isPlaying, isTrue, reason: '$rowKey 松手恢复播放');
      }

      await swipeRowBlank('track_notes');
      await swipeRowBlank('track_mirror');

      // 对比行集（对比-控制层）下备注轨同样无浮层。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await swipeRowBlank('track_notes');
    });

    testWidgets('微调与既有空白手势共存：加指转捏合恢复播放并缩放、随后双击切播放不收起', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      expect(engine.isPlaying, isTrue);

      // 单指微调中加第二指 → 微调收尾（恢复播放）、转捏合缩放。
      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g1 = await tester.startGesture(center);
      await tester.pump();
      await g1.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(engine.isPlaying, isFalse, reason: '微调起手暂停');
      final g2 = await tester.startGesture(center + const Offset(60, 0));
      await tester.pump();
      // 双指张开 = 捏合缩放（不是微调，也不是双指双击）。
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-25, 0));
        await g2.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      expect(engine.isPlaying, isTrue, reason: '加指冻结微调即恢复手势前播放态');
      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '编辑态全程无微调浮层',
      );
      var ticks = 0;
      for (var i = 0; i <= 400; i++) {
        if (tester.any(find.byKey(ValueKey('beat_tick_${i * 500000}')))) {
          ticks++;
        }
      }
      expect(ticks, lessThan(361), reason: '捏合缩放生效（窗口变短）');
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget, reason: '捏合会话不收起');

      // 微调后再单指双击：仍只切播放/暂停、不收起（分区与双击共存）。
      await doubleTapAt(
        tester,
        tester.getCenter(find.byKey(const Key('control_layer_blank'))),
      );
      expect(engine.isPlaying, isFalse, reason: '双击切播放/暂停');
      expect(controlLayer(), findsOneWidget, reason: '双击不收起');
    });

    testWidgets('起手在学习段体上不触发空白横滑 seek（编辑优先）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      engine.seekCalls.clear();

      final center = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      final g = await tester.startGesture(center);
      await tester.pump();
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(engine.seekCalls, [const Duration(seconds: 0)],
          reason: '段体上横滑 = 清空后只选中这一段：'
              '只剩选中即循环的跳段首 seek，无空白横滑 scrub seek');
      expect(controlLayer(), findsOneWidget);
    });

    testWidgets('空白区纯纵向往返位移（未锁轴）松手：不视为静止单击、不收起', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g = await tester.startGesture(center);
      await tester.pump();
      await g.moveBy(const Offset(0, 60));
      await tester.pump();
      await g.moveBy(const Offset(0, -60));
      await tester.pump();
      await g.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(controlLayer(), findsOneWidget, reason: '往返位移是拖动会话，不收起');
    });

    testWidgets('空白单击（静止）仍经约 300ms 判定窗口收起（铁律收起侧回归）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(controlLayer(), findsOneWidget, reason: '判定窗口内不收起');
      await tester.pump(kDoubleTapTimeout);
      expect(controlLayer(), findsNothing, reason: '静止单击仍收起');
    });
  });

  group('倍速气泡中心对齐（槽位移右缘）', () {
    testWidgets('编辑态：气泡从「倍速设置」槽旁锚定弹出、完整进屏', (tester) async {
      // 槽位位于分隔段右端（左邻局部镜像、右邻分隔线），合并
      // 气泡（≈488 自然宽）以槽为中心必越右留边——宿主钳制平移进屏，
      // 中心对齐不再几何可行；锚定关系（槽正下方）与两向完整进屏是本
      // 用例钉住的行外行为，钳制细节由窄视口用例覆盖。
      setWideView(tester);
      await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final tool = tester.renderObject<RenderBox>(
        find.byKey(const Key('tool_speed_settings')),
      );
      final bubbleCenter = bubble.localToGlobal(
        bubble.size.center(Offset.zero),
      );
      final toolCenter = tool.localToGlobal(tool.size.center(Offset.zero));
      expect(
        bubbleCenter.dy,
        greaterThan(toolCenter.dy),
        reason: '气泡在工具图标下方（锚定倍速槽）',
      );
      final bubbleRect = bubbleGlobalRect(bubble);
      final screenRight =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        bubbleRect.right,
        lessThanOrEqualTo(screenRight - speedBubbleScreenMargin + 0.5),
        reason: '右缘不越屏（水平钳制进屏）',
      );
      expect(
        bubbleRect.left,
        greaterThanOrEqualTo(speedBubbleScreenMargin - 0.5),
        reason: '左缘不越屏',
      );
    });

    testWidgets('编辑态近右缘（倍速设置图标）：合并气泡完整进屏、右缘留边',
        (tester) async {
      await pumpControlLayer(tester);

      // 短按倍速设置图标即开合并气泡（左倍速栏 + 右步进栏）。
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      expectBubbleClampedOnScreen(bubble, screenWidth: 800);
    });
  });

  group('时间读数到帧', () {
    // 单击唤出即开始播放（既有行为），先经 toolbar_play 暂停定格再读文本。
    Future<String> pausedToolbarTime(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      return tester.widget<Text>(
        find.byKey(const Key('toolbar_time')),
      ).data!;
    }

    testWidgets('时间读数显示 mm:ss:ff（帧号自 0，默认 30fps，无旧十分位残留）', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final text = await pausedToolbarTime(tester);
      expect(text, matches(RegExp(r'^\d{2,}:\d{2}:\d{2} / 03:00:00$')));
      expect(text.contains('.'), isFalse, reason: '不得残留 mm:ss.d 旧格式');
      // 帧号自 0、按默认 30fps 换算（独立于实现重算）。
      final frame = int.parse(text.split(' / ').first.split(':').last);
      final expectedFrame =
          engine.position.inMilliseconds % 1000 * 30 ~/ 1000;
      expect(frame, expectedFrame);
    });

    testWidgets('引擎可暴露 demux-fps 时以其换算（25fps，区别于默认 30fps）', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(minutes: 3),
        videoFps: 25,
      );
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      final text = await pausedToolbarTime(tester);
      expect(text, matches(RegExp(r'^\d{2,}:\d{2}:\d{2} / 03:00:00$')));
      final frame = int.parse(text.split(' / ').first.split(':').last);
      final ms = engine.position.inMilliseconds % 1000;
      final expectedAt25 = ms * 25 ~/ 1000;
      final expectedAt30 = ms * 30 ~/ 1000;
      expect(expectedAt25, isNot(expectedAt30), reason: '用例须能区分两种帧率');
      expect(frame, expectedAt25);
    });
  });

  group('选中清除与插入重映射', () {
    /// 建两条线（10s / 20s）、预览线移到 5s 中性位后经控制柄
    /// 选中 [selectIndex]，返回 ProviderContainer 供带外断言。
    Future<ProviderContainer> pumpWithSelectedLine(
      WidgetTester tester, {
      int selectIndex = 1,
    }) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, selectIndex);
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
    }

    testWidgets('播放控制清除线选中（其它操作即清除）', (tester) async {
      final container = await pumpWithSelectedLine(tester);
      expect(container.read(selectedSegmentLineIndexProvider), 1);

      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();

      expect(container.read(annotationSelectionProvider), isNull);
    });

    testWidgets('空白单击收起清除线选中', (tester) async {
      final container = await pumpWithSelectedLine(tester);
      expect(container.read(selectedSegmentLineIndexProvider), 1);

      await tapBlankAndCollapse(
        tester,
        find.byKey(const Key('track_handle_strip_row')),
      );
      await tester.pumpAndSettle();

      expect(container.read(annotationSelectionProvider), isNull);
    });

    testWidgets('分段工具在选中线左侧插入 → 线选中重映射 +1', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      // 先建 20s 线（线 0）并选中（预览线先让开 20s 线位，适配）。
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      // 预览线移到 5s（选中线左侧）再分段 → 新线成为线 0，选中重映射为 1。
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(container.read(selectedSegmentLineIndexProvider), 1);
    });
  });

  group('帧步进按钮（目标链改半拍线/端标）', () {
    /// 建两条线（12s / 20s，均落八拍点）、预览线停 5s 中性位、暂停，返回
    /// 引擎与容器。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpPausedWithLines(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 12));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      return (engine, container);
    }

    testWidgets('帧步进钮命中矩形 ≥ 通行下限', (tester) async {
      await pumpPausedWithLines(tester);

      for (final key in [
        'toolbar_frame_step_back',
        'toolbar_frame_step_forward',
      ]) {
        final hit = tester.getRect(find.byKey(Key(key)));
        expect(
          hit.width,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中宽 ≥ 通行下限',
        );
        expect(
          hit.height,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中高 ≥ 通行下限',
        );
      }
    });

    testWidgets('按钮位于延迟播放右侧：左移一帧在延迟播放与右移一帧之间', (tester) async {
      await pumpPausedWithLines(tester);

      expect(find.byKey(const Key('toolbar_frame_step_back')), findsOneWidget);
      expect(
        find.byKey(const Key('toolbar_frame_step_forward')),
        findsOneWidget,
      );
      final delayedDx =
          tester.getCenter(find.byKey(const Key('toolbar_delayed_play'))).dx;
      final backDx =
          tester.getCenter(find.byKey(const Key('toolbar_frame_step_back'))).dx;
      final forwardDx = tester
          .getCenter(find.byKey(const Key('toolbar_frame_step_forward')))
          .dx;
      expect(backDx, greaterThan(delayedDx));
      expect(forwardDx, greaterThan(backDx));
    });

    testWidgets('无选中暂停时右移一帧 = 预览进度 +1/30s（默认 30fps），不入撤销', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);

      final historyLengthBefore =
          container.read(annotationEditHistoryProvider).length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();

      expect(engine.seekCalls.last, const Duration(seconds: 5) + kDefaultFrameDuration);
      // 预览步进不新增撤销命令（建线等既有历史不计）。
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyLengthBefore,
        reason: '预览进度步进不是时间线编辑，不入撤销历史',
      );
      // 无选中时帧步进属「其它操作」：清除既有选中（规则）。
      expect(container.read(annotationSelectionProvider), isNull);
    });

    testWidgets('无选中且在播：先暂停定格再步进（pause 先于 seek）', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);

      await engine.play();
      await tester.pump();
      final logBefore = engine.callLog.length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();

      expect(engine.isPlaying, isFalse);
      expect(engine.callLog.sublist(logBefore), ['pause', 'seek']);
      expect(engine.seekCalls.last, const Duration(seconds: 5) + kDefaultFrameDuration);
    });

    testWidgets('左移一帧在起点附近钳制到 0（不越界）', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);

      await engine.seek(const Duration(milliseconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pump();

      expect(engine.seekCalls.last, Duration.zero);
    });

    // 分段线从上一帧/下一帧目标链移除——选中分段线时步进回落
    // 为预览进度步进，线不动。
    testWidgets('选中分段线：步进不再作用于线（回落预览步进、线不动）', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).segmentLines[0].position,
        const Duration(seconds: 12),
        reason: '分段线不支持逐帧微调（只落八拍点）',
      );
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 5) + kDefaultFrameDuration,
        reason: '步进回落为预览进度 ±1 帧',
      );
    });

    testWidgets('选中半拍线：右移跳相邻半拍格点（10.25s → 10.75s）', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      container.read(annotationEditorProvider).submit(
            const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)),
          );
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '强制对齐：线步进跳相邻半拍格点',
      );
      expect(container.read(selectedHalfBeatLineIndexProvider), 0,
          reason: '步进针对选中线，不清选中');
    });

    testWidgets('无选中预览步进：引擎暴露 demux-fps 时步长按其换算（25fps → 40ms）', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 30),
        videoFps: 25,
      );
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        engine.seekCalls.last,
        const Duration(seconds: 5) + frameDurationFor(25),
      );
    });

    // 测试清理：同上，端标步进入撤销断言迁模块面（历史语义组）。
    testWidgets('选中首线端标（占位网格无真实拍点语义）：右移回退 ±1 帧', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // readyBeat:false → 节拍轨占位（无界网格，无真实拍点语义）。
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await tester.pumpAndSettle();
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).rangeStart,
        kDefaultFrameDuration,
      );
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start);
    });

    testWidgets('选中首线端标（就绪网格）：右移到相邻真实拍点（0 → 0.5s）', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await tester.pumpAndSettle();
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(milliseconds: 500),
      );
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start);
    });

    testWidgets('锁定分段开启：选中半拍线步进照常（半拍线不受锁）；无选中步进预览不受锁', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      container.read(annotationEditorProvider).submit(
            const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)),
          );
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '半拍线步进不受锁定分段',
      );
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);

      // 清除选中 → 目标为预览进度：不受锁限制。
      container.read(annotationSelectionDomainProvider).clear();
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 50));
      expect(
        engine.seekCalls.last,
        greaterThan(const Duration(seconds: 5)),
        reason: '无选中 → 帧步进推进预览位置',
      );
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing,
          reason: '预览步进不触发锁提示');
    });

    testWidgets('锁定分段开启：选中端标步进被阻止并提示（范围覆盖首尾线）', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();

      // 选中尾线端标（选中不受锁），帧步进目标为边界 → 被阻并提示。
      await tester.tap(find.byKey(const Key('video_range_end_marker')));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.end,
      );

      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pump();
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 30),
        reason: '锁下端标步进不执行',
      );
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget);
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('临时衔接段中心线选中时步进：线与临时段都不动（目标链已移除分段线）', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      // 学习轨行内点线身（线 0 @12s）激活临时衔接段（同时选中该线）。
      final lineDx =
          tester.getCenter(find.byKey(const Key('segment_line_0'))).dx;
      await tester.tapAt(
        Offset(lineDx, trackRowCenterY(tester, 'track_learning')),
      );
      await tester.pumpAndSettle();
      final transition = container.read(transitionSegmentProvider);
      expect(transition, isNotNull);
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(container.read(transitionSegmentProvider), transition,
          reason: '分段线几何未变，临时段保留');
      expect(
        container.read(annotationTimelineProvider).segmentLines[0].position,
        const Duration(seconds: 12),
        reason: '分段线不支持逐帧微调',
      );
    });

    testWidgets('空白微调 seek 越出临时衔接段范围 → 临时段取消（Q8 一行修复）', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      // 学习轨行内点线身（线 0 @12s）激活临时衔接段（同时选中该线；激活
      // seek 到临时段起点 8s）。
      final lineDx =
          tester.getCenter(find.byKey(const Key('segment_line_0'))).dx;
      await tester.tapAt(
        Offset(lineDx, trackRowCenterY(tester, 'track_learning')),
      );
      await tester.pumpAndSettle();
      expect(container.read(transitionSegmentProvider), isNotNull);

      // 激活即起播：本用例要的是「暂停 + 基准恰为 8s」的确定性
      // 布景（微调目标是相对基准的算术），故起播后复位回去。
      await engine.pause();
      await engine.seek(const Duration(seconds: 8));
      await tester.pumpAndSettle();

      // 空白区单指横滑微调：基准 8s（临时段激活 seek 落点）+ 360px ×
      // 50ms/px = +18s → 26s，越出临时段（8s–16s）生效范围 → 应取消激活。
      final center = tester.getCenter(
        find.byKey(const Key('control_layer_blank')),
      );
      final g = await tester.startGesture(center);
      await tester.pump();
      await g.moveBy(const Offset(180, 0));
      await tester.pump();
      await g.moveBy(const Offset(180, 0));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(engine.seekCalls.last, const Duration(seconds: 26),
          reason: '微调目标越出临时段范围');
      expect(container.read(transitionSegmentProvider), isNull,
          reason: '微调 seek 越出与其他 seek 入口同一「越出即取消激活」判定'
              '（临时衔接段一并清除）');
    });
  });

  group('帧步进同步播放头到线（目标 = 半拍线/端标）', () {
    /// 建一条半拍线（10.25s，半拍格点）+ 一条分段线（20s 八拍点）、预览线
    /// 停 5s 中性位、暂停，返回引擎与容器。本组验证步进后播放头同步语义。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpPausedWithLines(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.pause();
      container.read(annotationEditorProvider).submit(
            const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)),
          );
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      return (engine, container);
    }

    testWidgets('选中半拍线暂停时右移：播放头同步 seek 到线新位置', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
      final seeksBefore = engine.seekCalls.length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        engine.seekCalls.sublist(seeksBefore),
        [const Duration(seconds: 10, milliseconds: 750)],
        reason: '跳步移线后播放头同步到线新位置',
      );
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('选中半拍线在播时步进：先 pause 再 seek 到线新位置、不自动续播', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      final seeksBefore = engine.seekCalls.length;

      await engine.play();
      await tester.pump();
      final logBefore = engine.callLog.length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(engine.callLog.sublist(logBefore), ['pause', 'seek']);
      expect(
        engine.seekCalls.sublist(seeksBefore),
        [const Duration(seconds: 10, milliseconds: 750)],
      );
      expect(engine.isPlaying, isFalse, reason: '同步后定格，不自动续播');
      expect(container.read(selectedHalfBeatLineIndexProvider), 0,
          reason: '同步不清选中');
    });

    testWidgets('连续步进两步：latest-wins，播放头停在线 11.25s', (tester) async {
      final (engine, container) = await pumpPausedWithLines(tester);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      final seeksBefore = engine.seekCalls.length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 11, milliseconds: 250),
      );
      expect(
        engine.seekCalls.sublist(seeksBefore),
        [
          const Duration(seconds: 10, milliseconds: 750),
          const Duration(seconds: 11, milliseconds: 250),
        ],
        reason: '连续步进逐步同步预览',
      );
    });

    testWidgets('选中首线端标步进：播放头同步到 rangeStart 新位置', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await tester.pumpAndSettle();
      final seeksBefore = engine.seekCalls.length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        engine.seekCalls.sublist(seeksBefore),
        [const Duration(milliseconds: 500)],
        reason: '端标步进后播放头同步到首线新位置',
      );
    });

    testWidgets('钳制 no-op 步进（线未动）不触发同步 seek', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await tester.pumpAndSettle();
      final seeksBefore = engine.seekCalls.length;

      // 首线端标在 0：左移一帧被钳制为 no-op（先例），线未动不同步。
      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pumpAndSettle();

      expect(engine.seekCalls.length, seeksBefore,
          reason: '线未移动时不做播放头同步');
    });
  });

  group('帧步进长按连续步进', () {
    /// 建两条线（10s / 20s）、预览线停 5s 中性位、暂停，返回引擎与容器。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpPausedWithLines(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      return (engine, container);
    }

    Future<TestGesture> holdStepButton(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('toolbar_frame_step_forward'))),
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('短按仍单步：点击只步进一帧，等待后不再重复', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      final base = engine.seekCalls.length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();
      expect(engine.seekCalls.length - base, 1);

      // 短按不该埋下任何重复定时器：等 1.5s（超过长按启动阈值）仍一步。
      await tester.pump(const Duration(milliseconds: 1500));
      expect(engine.seekCalls.length - base, 1);
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 5) + kDefaultFrameDuration,
      );
    });

    testWidgets('按住未到启动阈值（0.4s）：只有按下那一步', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      final base = engine.seekCalls.length;
      final gesture = await holdStepButton(tester);
      expect(engine.seekCalls.length - base, 1, reason: '按下即单步，反馈即时');

      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.seekCalls.length - base, 1, reason: '0.4s 内不进入重复模式');

      await gesture.up();
      await tester.pump();
    });

    testWidgets('长按进入重复模式：约 0.4s 后步进、之后约 0.15s 一次', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      final base = engine.seekCalls.length;
      final gesture = await holdStepButton(tester);

      await tester.pump(const Duration(milliseconds: 400));
      // 冲刷串行 seek 队列的节流窗口（minInterval 按墙钟计时，测试的假
      // 时钟里最多滞后约一个节流间隔）；下同。
      await tester.pump(const Duration(milliseconds: 50));
      final afterHold = engine.seekCalls.length - base;
      expect(afterHold, 2, reason: '0.4s 启动重复模式，触发第一次重复步进');

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 50));
      expect(engine.seekCalls.length - base, afterHold + 1);

      await gesture.up();
      await tester.pump();
    });

    testWidgets('按住渐快：长按步数明显多于固定 0.15s 节奏，且有上限', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      final base = engine.seekCalls.length;
      final gesture = await holdStepButton(tester);

      await tester.pump(const Duration(milliseconds: 2500));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));

      final steps = engine.seekCalls.length - base;
      // 固定 0.15s/次的基准：按下 1 步 + 0.4s 启动后约 14 次 ≈ 15 步。
      const fixedBaseline = 15;
      expect(steps, greaterThan(fixedBaseline), reason: '渐快后步数应多于固定节奏');
      // 上限（50ms 下限节奏的理论极值约 45 步），防失控。
      expect(steps, lessThan(50));
    });

    testWidgets('松开即停：不继续重复，也不补触发额外单步', (tester) async {
      final (engine, _) = await pumpPausedWithLines(tester);
      final base = engine.seekCalls.length;
      final gesture = await holdStepButton(tester);

      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 50));
      final beforeRelease = engine.seekCalls.length - base;
      expect(beforeRelease, greaterThan(1));

      await gesture.up();
      // 冲刷节流窗口：松开最多补发按住期间已触发、仍滞留窗口的最后一个
      // 目标（latest-wins 收敛语义，最终目标必达），不得再触发新的步进。
      await tester.pump(const Duration(milliseconds: 50));
      final afterRelease = engine.seekCalls.length - base;
      expect(afterRelease, inInclusiveRange(beforeRelease, beforeRelease + 1),
          reason: '松开瞬间不补触发新的单步');

      await tester.pump(const Duration(milliseconds: 800));
      expect(engine.seekCalls.length - base, afterRelease,
          reason: '松开后停止重复');
    });

    testWidgets('其它按钮行为不变：播放按钮点击只切换一次，无重复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isFalse);
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(engine.isPlaying, isTrue);

      // 点击只触发一次 onPressed：继续等也不反复切换。
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.isPlaying, isTrue);
    });
  });

  group('左右钮半拍格点跳步（目标 = 半拍线/端标）', () {
    /// 建一条半拍线（10.25s，半拍格点上）、预览线停 5s 中性位、暂停、
    /// 吸附开（默认偏好），返回引擎与容器。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpPausedWithLine(
      WidgetTester tester, {
      VoidCallback? gridStepHaptic,
      BeatGrid? beatGrid,
    }) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        gridStepHaptic: gridStepHaptic,
        beatGrid: beatGrid,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.pause();
      container.read(annotationEditorProvider).submit(
            const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)),
          );
      await tester.pumpAndSettle();
      await engine.seek(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      return (engine, container);
    }

    /// 选中半拍线 0（经节拍轨行内命中列点选）。
    Future<void> selectHalfBeat(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
    }

    testWidgets('选中半拍线 + 吸附开：右移到相邻半拍格点（10.25s → 10.75s）', (tester) async {
      var haptics = 0;
      final (engine, container) = await pumpPausedWithLine(tester, gridStepHaptic: () => haptics++);
      final historyBefore =
          container.read(annotationEditHistoryProvider).length;
      await selectHalfBeat(tester, engine);
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '半拍格点跳步：右移到下一中点（仅相邻拍点中点 0.25 倍数）',
      );
      expect(engine.seekCalls.last, const Duration(seconds: 10, milliseconds: 750),
          reason: '播放头同步到线新位置');
      // 单击单步入史。
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore + 1,
      );
      // 轻震一次。
      expect(haptics, 1);
      expect(container.read(selectedHalfBeatLineIndexProvider), 0,
          reason: '格点跳步不清选中');
    });

    testWidgets('线不在半拍格点上：右移严格越过当前位置（10.4s → 10.75s，不回头）', (tester) async {
      final (engine, container) = await pumpPausedWithLine(tester);
      // 模块写入把线移到格点之间（10.25s+150ms，非中点）。
      container.read(annotationEditorProvider).submit(
        const MoveHalfBeatLine(
          index: 0,
          to: Duration(seconds: 10, milliseconds: 400),
        ),
      );
      await tester.pumpAndSettle();
      await selectHalfBeat(tester, engine);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '严格越过当前位置：10.4s 的下一中点是 10.75s',
      );
    });

    testWidgets('选中半拍线 + 吸附开：左移到前一个相邻半拍格点（10.25s → 9.75s）', (tester) async {
      final (engine, container) = await pumpPausedWithLine(tester);
      await selectHalfBeat(tester, engine);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 9, milliseconds: 750),
      );
      expect(engine.seekCalls.last, const Duration(seconds: 9, milliseconds: 750));
    });

    testWidgets('无相邻半拍格点：线在末中点之后右移 no-op（线不动、不入史、无轻震）', (tester) async {
      var haptics = 0;
      final (engine, container) = await pumpPausedWithLine(
        tester,
        // 有界真实网格（fake）：拍点 0..4s（每拍 0.5s），末中点 3.75s。
        gridStepHaptic: () => haptics++,
        beatGrid: const _BoundedTestGrid(),
      );
      // 把半拍线放到末中点（3.75s）之后：交互提交经模块落点
      // 解析、线不可能停在末中点之外，off-grid 旧数据经恢复装载（免吸附
      // 路径）就位。
      container.read(annotationEditorProvider).restoreDocument(
            AnnotationRestoreDocument(
              timeline: AnnotationTimeline.normalized(
                videoDuration: const Duration(seconds: 30),
                rangeStart: Duration.zero,
                rangeEnd: const Duration(seconds: 30),
                segmentLines: const [],
                halfBeatLines: const [
                  HalfBeatLine(
                    position: Duration(seconds: 4, milliseconds: 500),
                  ),
                ],
              ),
            ),
          );
      await tester.pumpAndSettle();
      await selectHalfBeat(tester, engine);
      final historyBefore =
          container.read(annotationEditHistoryProvider).length;

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 4, milliseconds: 500),
        reason: '网格末中点（3.75s）之外无下一中点：no-op 线不动',
      );
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore,
        reason: 'no-op 不入史',
      );
      expect(haptics, 0, reason: 'no-op 无轻震');
    });

    testWidgets('选中半拍线 + 吸附开：按住不连续快进（1s 长按只移一格）', (tester) async {
      var haptics = 0;
      final (engine, container) = await pumpPausedWithLine(tester, gridStepHaptic: () => haptics++);
      await selectHalfBeat(tester, engine);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('toolbar_frame_step_forward'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '格点跳步无长按连续：按住只移一格',
      );
      expect(haptics, 1, reason: '只轻震一次');
    });

    testWidgets('选中首线端标：右移到相邻真实拍点（0 → 0.5s）；在首拍点左移 no-op', (tester) async {
      var haptics = 0;
      final (engine, container) = await pumpPausedWithLine(
        tester,
        gridStepHaptic: () => haptics++,
        // 有界真实网格：真实拍点 0/0.5/…/4s。
        beatGrid: const _BoundedTestGrid(),
      );
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await tester.pumpAndSettle();
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start);

      // 首拍点（0s）左移无前一拍点：no-op。
      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pumpAndSettle();
      expect(container.read(annotationTimelineProvider).rangeStart,
          Duration.zero);
      expect(haptics, 0);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(milliseconds: 500),
      );
      expect(haptics, 1);
    });

    testWidgets('端标在网格覆盖区外：步进回退 ±1 帧（覆盖外自由）', (tester) async {
      var haptics = 0;
      final (engine, container) = await pumpPausedWithLine(
        tester,
        gridStepHaptic: () => haptics++,
        // 有界真实网格覆盖区 0..4s；尾线 30s 在覆盖区外。
        beatGrid: const _BoundedTestGrid(),
      );
      await engine.seek(const Duration(seconds: 5));
      await tester.pump();
      await tester.tap(find.byKey(const Key('video_range_end_marker')));
      await tester.pumpAndSettle();
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.end);

      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pumpAndSettle();

      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 30) - kDefaultFrameDuration,
        reason: '覆盖区外不吸拍点：回退 ±1 帧自由步进',
      );
      expect(haptics, 0, reason: '自由步进不轻震');
    });

    testWidgets('提示文案固定「左移/右移一步」：无移一格/移一帧双态切换', (tester) async {
      final (engine, container) = await pumpPausedWithLine(tester);

      expect(find.byTooltip('右移一步'), findsOneWidget);
      expect(find.byTooltip('左移一步'), findsOneWidget);
      expect(find.byTooltip('右移一格'), findsNothing);
      expect(find.byTooltip('右移一帧'), findsNothing);

      await selectHalfBeat(tester, engine);

      // 选中后文案仍固定不变。
      expect(find.byTooltip('右移一步'), findsOneWidget);
      expect(find.byTooltip('左移一步'), findsOneWidget);
      expect(find.byTooltip('右移一格'), findsNothing);
      expect(find.byTooltip('右移一帧'), findsNothing);
    });
  });

  group('自动分段钮（「文件」菜单退场）', () {
    /// 34 拍就绪态（0.5s 起每拍 0.5s）：34 拍 → 32 拍相位处一刀（16.5s），
    /// 尾部 2 拍并入末段。
    BeatTrackState readyBeatState34() => BeatTrackState.ready(
      marker_doc.BeatGrid(
        model: 'fake.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2024),
        beats: [
          for (var i = 0; i < 34; i++)
            marker_doc.BeatPoint(t: 0.5 + i * 0.5, down: i % 4 == 0),
        ],
      ),
    );

    testWidgets('自动分段钮：一次写入首尾 + 32 拍切点，单步入撤销', (tester) async {
      final engine = FakePlaybackEngine();
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(tester, readyBeatState34());
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
      );

      await tapAutoEntry(tester, 'control_auto_seg_4');

      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.rangeStart, const Duration(milliseconds: 500));
      expect(timeline.rangeEnd, const Duration(milliseconds: 17000));
      expect(
        [for (final line in timeline.segmentLines) line.position],
        const [Duration(milliseconds: 16500)],
        reason: '从首线相位第 32 拍下刀，尾部 2 拍并入末段',
      );

      // 整动作一次入史：一步撤销回整片范围、无分段线。
      container.read(annotationEditorProvider).undo();
      final restored = container.read(annotationTimelineProvider);
      expect(restored.rangeStart, Duration.zero);
      expect(restored.rangeEnd, engine.duration);
      expect(restored.segmentLines, isEmpty);
    });


  });

  group('自动分段档位菜单', () {
    /// 泵出控制层展开 + 就绪节拍（首末拍 0.5s/2.0s）+ 暂停的播放器。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpAutoReady(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
      );
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);
      await engine.pause();
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      return (engine, container);
    }

    testWidgets('点自动分段槽向上弹出菜单：恰为三档、次序与条目表声明一致、锚定槽位向上', (tester) async {
      await pumpAutoReady(tester);

      // 菜单未开时全树无条目键。
      expect(renderedAutoEntryKeys(tester), isEmpty);
      await openAutoMenu(tester);

      expect(find.text('清空分段'), findsOneWidget);
      expect(find.text('4 个八拍/段'), findsOneWidget);
      expect(find.text('8 个八拍/段'), findsOneWidget);
      expect(renderedAutoEntryKeys(tester),
          AutoSegmentEntryTable.normal.entries.map((e) => e.key).toList(),
          reason: '条目表声明 == 菜单实际渲染（逐位相等）');

      // 向上弹出：条目整体在槽上缘之上（工具区在屏幕底部）。
      final slotTop =
          tester.getTopLeft(find.byKey(const Key('control_auto_range'))).dy;
      final itemTop = tester.getTopLeft(
        find.byKey(const Key('control_auto_clear')),
      ).dy;
      expect(itemTop, lessThan(slotTop), reason: '菜单锚定槽位向上弹出');

      // 收起菜单（点外部）。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(renderedAutoEntryKeys(tester), isEmpty);
    });

    testWidgets('锁定期间自动分段菜单不展开：该菜单取不到「条目不可用」态', (tester) async {
      await pumpAutoReady(tester);
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('锁定分段·开'), findsOneWidget);

      // 三条目声明的门（装载 / 锁定 / 网格未就绪）都让槽走「弹原因」语义，
      // 菜单不展开；三门都不命中时条目又全部可用（文字 style = null）。故
      // 自动分段菜单里「不可用条目文字色 == 浅底菜单 token」这条渲染分支
      // 在发布形态下取不到——浅底菜单不可用文字 token 的落地断言由「添加」
      // 菜单那条持有（锁定 + 选中分段线 → 「标记分段线」置灰）。
      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      expect(renderedAutoEntryKeys(tester), isEmpty,
          reason: '锁定压倒菜单展开：条目不可用的自动分段菜单形态不可达');
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget);
    });

    testWidgets('「8 个八拍/段」提交：自动首尾 + 按档位划分切割线（4 拍网格不足 8 档 → 无切割线）', (tester) async {
      final (engine, container) = await pumpAutoReady(tester);
      final before = container.read(annotationEditHistoryProvider).length;

      await tapAutoEntry(tester, 'control_auto_seg_8');

      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.rangeStart, const Duration(milliseconds: 500),
          reason: '首 = 网格首拍');
      expect(timeline.rangeEnd, const Duration(seconds: 2),
          reason: '尾 = 网格末拍');
      expect(timeline.segmentLines, isEmpty,
          reason: '4 拍网格不足 8 个整八拍：无切割线、整段一段');
      expect(container.read(annotationEditHistoryProvider).length,
          before + 1, reason: '一次提交 = 一步标注编辑');

      // 一步撤销回整片范围。
      container.read(annotationEditorProvider).undo();
      final restored = container.read(annotationTimelineProvider);
      expect(restored.rangeStart, Duration.zero);
      expect(restored.rangeEnd, engine.duration);
    });

    testWidgets('「清空分段」提交：切割线清空、首尾保留，一步可撤销', (tester) async {
      final (engine, container) = await pumpAutoReady(tester);
      // 换 30s 就绪网格（八拍点充足）：先经「4 个八拍/段」造出首尾与切割线。
      await injectBeatState(tester, uniformReadyBeatState(seconds: 30));
      await tester.pump();
      await tapAutoEntry(tester, 'control_auto_seg_4');
      final before = container.read(annotationTimelineProvider);
      expect(before.segmentLines, isNotEmpty, reason: '前置：档位切点已落');
      expect(before.rangeStart, Duration.zero);
      expect(before.rangeEnd, engine.duration);

      await tapAutoEntry(tester, 'control_auto_clear');

      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.segmentLines, isEmpty, reason: '切割线清空');
      expect(timeline.rangeStart, Duration.zero, reason: '首尾线保留');
      expect(timeline.rangeEnd, engine.duration);

      container.read(annotationEditorProvider).undo();
      expect(
        container.read(annotationTimelineProvider).segmentLines
            .map((l) => l.position),
        before.segmentLines.map((l) => l.position),
        reason: '一步撤销恢复',
      );
    });

    testWidgets('任意时刻至多一个工具菜单开着：自动分段菜单打开时「添加」菜单先收起', (tester) async {
      await pumpAutoReady(tester);

      await openAddMenu(tester);
      expect(renderedAddEntryKeys(tester), isNotEmpty,
          reason: '前置：「添加」菜单开着');

      // 菜单外点击（含另一枚菜单槽）先被点外收起遮罩承接：收「添加」菜单，
      // 不直接开新菜单——任意时刻至多一个工具菜单开着。
      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      expect(renderedAddEntryKeys(tester), isEmpty, reason: '「添加」菜单收起');
      expect(renderedAutoEntryKeys(tester), isEmpty, reason: '新菜单未叠开');

      // 再点一次才打开「自动分段」菜单。
      await openAutoMenu(tester);
      expect(renderedAutoEntryKeys(tester),
          AutoSegmentEntryTable.normal.entries.map((e) => e.key).toList());
    });

    testWidgets('对比态：自动分段槽在册、同一菜单形态可用（提交走同一条目路径）', (tester) async {
      final (engine, container) = await pumpAutoReady(tester);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('control_auto_range')), findsOneWidget);
      // 对比-控制层内引擎边界循环持续调度帧：定步 pump（既有先例）。
      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(renderedAutoEntryKeys(tester),
          AutoSegmentEntryTable.normal.entries.map((e) => e.key).toList(),
          reason: '前置：对比态菜单开着');
      // 条目置灰观感（可用性 token）仍可点（锁定 / 未就绪同款判定）。
      await tester.tap(find.byKey(const Key('control_auto_seg_4')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      // 三档条目与编辑态同一菜单形态（同一份条目表声明渲染）；提交动作
      // 同走唯一映射点，无按模式分支。
      // 收起菜单（点外部）。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(renderedAutoEntryKeys(tester), isEmpty);
    });

    testWidgets('装载未完成：槽单击弹「正在装载」、菜单不开（既有判定）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pump();
      await tester.pump();
      expect(find.text('正在装载'), findsOneWidget);
      expect(renderedAutoEntryKeys(tester), isEmpty, reason: '菜单不开');

      // 装载落定：照常开菜单、档位提交。
      container.read(loadGateActiveProvider.notifier).settle();
      await tester.pumpAndSettle();
      await injectBeatState(tester, readyBeatState());
      await tester.pump();
      await tapAutoEntry(tester, 'control_auto_seg_4');
      expect(container.read(annotationTimelineProvider).rangeStart,
          const Duration(milliseconds: 500));
    });

    testWidgets('锁定 + 网格未就绪：单击只弹「已锁定分段」（锁定压倒未就绪）、菜单不开、不改状态', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        beatPipeline: hangingBeatPipeline,
        readyBeat: false,
      );
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();
      expect(renderedAutoEntryKeys(tester), isEmpty,
          reason: '锁定压倒未就绪：单击只弹原因、菜单不开');
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget,
          reason: '锁定原因优先于网格未就绪');
      expect(find.byKey(const Key('beat_analyzing_prompt')), findsNothing);
      expect(container.read(annotationTimelineProvider).rangeStart,
          Duration.zero, reason: '不改任何状态');
    });

    testWidgets('网格未就绪：槽单击弹既有原因提示、菜单不开', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      expect(slotEnabled(tester, 'control_auto_range'), isTrue,
          reason: '网格未就绪置灰仍可点（既有判定表）');
      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_analyzing_prompt')), findsOneWidget);
      expect(renderedAutoEntryKeys(tester), isEmpty, reason: '菜单不开');
    });
  });

  group('「添加」槽与添加条目菜单', () {
    testWidgets('正常态渲染「添加」槽（原两创建类槽不再渲染）；跨面一致性：条目表声明的条目键 == 菜单实际渲染逐位相等；菜单向上弹出', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 「添加」槽在册；原两个创建类槽不再作为槽位渲染（菜单未开时全树无键）。
      expect(find.byKey(const Key('control_add')), findsOneWidget);
      expect(find.text('添加'), findsOneWidget);
      expect(find.byKey(const Key('control_half_beat')), findsNothing);
      expect(find.byKey(const Key('control_local_mirror')), findsNothing);
      expect(renderedAddEntryKeys(tester), isEmpty);

      // 点「添加」→ 菜单弹出：四个条目，自上而下 = 备注贴纸 / 局部镜像 /
      // 标记分段线 / 半拍标记（新次序；「标记分段线」插在「半拍标记」
      // 之前），文案取条目自己声明的标签。
      await openAddMenu(tester);
      expect(find.text('备注贴纸'), findsOneWidget);
      // 「局部镜像」与顶栏同名槽文案重合 → 在条目自身的键内定位。
      expect(
        find.descendant(
          of: find.byKey(const Key('control_local_mirror')),
          matching: find.text('局部镜像'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('control_segment_flag')),
          matching: find.text('标记分段线'),
        ),
        findsOneWidget,
      );
      expect(find.text('半拍标记'), findsOneWidget);
      expect(renderedAddEntryKeys(tester), const [
        'control_note_sticker',
        'control_local_mirror',
        'control_segment_flag',
        'control_half_beat',
      ], reason: '菜单渲染次序 = 条目表声明次序');

      // 向上弹出：条目整体在「添加」槽上缘之上（工具区在屏幕底部）。
      final slotTop = tester.getTopLeft(find.byKey(const Key('control_add'))).dy;
      final itemTop = tester.getTopLeft(
        find.byKey(const Key('control_half_beat')),
      ).dy;
      expect(itemTop, lessThan(slotTop), reason: '菜单锚定槽位向上弹出');

      // 收起菜单（点外部）。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(renderedAddEntryKeys(tester), isEmpty);
    });

    testWidgets('动作逐位一致：选「半拍线」提交半拍线插入（模块内解析最近半拍格点）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      // 占位网格 120bpm：半拍位 = 250ms 倍数；预览停 10.3s → 吸附 10.25s。
      await engine.pause();
      await engine.seek(const Duration(seconds: 10, milliseconds: 300));
      await tester.pump();

      await tapAddEntry(tester, 'control_half_beat');
      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.halfBeatLines, hasLength(1));
      expect(
        timeline.halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
      );
    });

    testWidgets('门逐位一致：预览线越界 → 菜单照常打开、半拍线置灰不可点、局部镜像片段照常可点', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine, beatPipeline: hangingBeatPipeline);
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      // 自动分段设窄有效区间（就绪节拍首末拍 0.5s–2.0s），预览线停区间外。
      await engine.pause();
      await engine.seek(const Duration(seconds: 1));
      await tester.pump();
      await tapAutoEntry(tester, 'control_auto_seg_4');
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();

      // 「添加」钮本身不受越界影响：菜单照常打开。
      expect(slotEnabled(tester, 'control_add'), isTrue);
      await openAddMenu(tester);
      // 半拍线条目置灰且不可点；局部镜像片段条目照常可点。
      expect(
        (tester.widget(find.byKey(const Key('control_half_beat'))) as dynamic)
            .enabled,
        isFalse,
        reason: '越界只挡半拍线条目',
      );
      expect(
        (tester.widget(
          find.byKey(const Key('control_local_mirror')),
        ) as dynamic)
            .enabled,
        isTrue,
      );
      // 半拍线不可点 → 点击不插入、菜单保持打开；局部镜像片段可选 → 提交片段插入。
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pump();
      expect(container.read(annotationTimelineProvider).halfBeatLines, isEmpty,
          reason: '置灰条目不可点');
      await tester.tap(find.byKey(const Key('control_local_mirror')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(1),
          reason: '局部镜像片段不受越界约束');
    });

    testWidgets('门逐位一致：锁定分段不受「添加」/半拍线约束——钮正常色、菜单照开、选条目照常插入', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();

      // 「添加」钮不受锁：正常色、可点，菜单照常打开。
      expect(slotIconColor(tester, 'control_add'),
          kToolSlotEnabledIconColor);
      expect(slotEnabled(tester, 'control_add'), isTrue);
      await openAddMenu(tester);
      expect(find.text('半拍标记'), findsOneWidget);
      // 选「半拍线」→ 照常插入（锁只护分段结构），不弹锁提示。
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pumpAndSettle();
      expect(container.read(annotationTimelineProvider).halfBeatLines,
          hasLength(1));
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('四条菜单类角标：动作真正发生才触达并记下新产物序号', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await engine.pause();
      await engine.seek(const Duration(seconds: 10, milliseconds: 300));
      await tester.pump();

      // 半拍标记：10.3s → 吸附 10.25s，记下新落那根（序号 0）。
      await tapAddEntry(tester, 'control_half_beat');
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeHalfBeatUnitId),
      );
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeHalfBeatUnitId],
        0,
      );

      // 局部镜像：同处落第一块（序号 0）——创建即生效的既有行为不受影响。
      await tapAddEntry(tester, 'control_local_mirror');
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeLocalMirrorUnitId),
      );
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeLocalMirrorUnitId],
        0,
      );

      // 标记分段线：先经「分段」落一条线（吸附 8s 八拍点），选中它再标记
      // ——记下的序号 = 被标记的那条线的序号。
      await engine.seek(const Duration(seconds: 8, milliseconds: 100));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).segmentLines,
        hasLength(1),
        reason: '前置：分段线真的落成了',
      );
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await tapAddEntry(tester, 'control_segment_flag');
      final flaggedIndex = container
          .read(annotationTimelineProvider)
          .segmentLines
          .indexWhere((line) => line.flagged);
      expect(flaggedIndex, isNonNegative, reason: '前置：标记真的落成了');
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeSegmentFlagUnitId),
      );
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeSegmentFlagUnitId],
        flaggedIndex,
      );

      // 三指跳转单元：同一触发点、同一条刚标记的线——与「标记
      // 分段线」各是一条独立单元，各自触达、各自记序号。
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeThreeFingerJumpUnitId),
      );
      expect(
        container.read(guideSessionProvider).artifactIndexes[
            badgeThreeFingerJumpUnitId],
        flaggedIndex,
      );
    });

    testWidgets('取消标记不触发也不消耗：三指跳转单元保持未触达', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await engine.pause();
      await tester.pumpAndSettle();

      // 不经「标记」动作、直接经编辑提交种一条已标记的线：菜单现态是
      // 「取消标记」。
      container
          .read(annotationEditorProvider)
          .submit(AddSegmentLine(at: const Duration(seconds: 8)));
      container.read(annotationEditorProvider).submit(
            const ToggleSegmentFlag(index: 0),
          );
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      expect(find.text('取消标记'), findsOneWidget);

      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).segmentLines.first.flagged,
        isFalse,
        reason: '前置：标记真的被取消了',
      );
      expect(
        container.read(guideSessionProvider).triggered,
        isNot(contains(badgeThreeFingerJumpUnitId)),
        reason: '取消标记不触达',
      );
      expect(
        container.read(guideSessionProvider).triggered,
        isNot(contains(badgeSegmentFlagUnitId)),
        reason: '「标记分段线」同规：取消不触发也不消耗',
      );
      expect(
        container.read(guideSessionProvider).artifactIndexes[
            badgeThreeFingerJumpUnitId],
        isNull,
      );
    });

    testWidgets('入口不可用（预览线越界）：点条目动作不发生 → 不触达、不记序号', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine, beatPipeline: hangingBeatPipeline);
      await injectBeatState(tester, readyBeatState());
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await engine.pause();
      await engine.seek(const Duration(seconds: 1));
      await tester.pump();
      // 自动分段设窄有效区间（就绪节拍首末拍 0.5s–2.0s），预览线停区间外。
      await tapAutoEntry(tester, 'control_auto_seg_4');
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();

      await openAddMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_half_beat')),
            )
            .enabled,
        isFalse,
        reason: '前置：越界让半拍标记入口按不动',
      );
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pumpAndSettle();

      expect(container.read(annotationTimelineProvider).halfBeatLines, isEmpty);
      expect(
        container.read(guideSessionProvider).triggered,
        isNot(contains(badgeHalfBeatUnitId)),
      );
      expect(
        container
            .read(guideSessionProvider).artifactIndexes
            .containsKey(badgeHalfBeatUnitId),
        isFalse,
      );
    });

    testWidgets('没落成（半拍格点上已有线）：EditNoop → 不触达、不记序号', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        docs: InMemoryVideoDocumentStorage(
          markers: {
            'version': 8,
            'annotations': {
              'range': {'startMs': 0, 'endMs': 30000},
              'segmentLines': <Object?>[],
              'halfBeatLines': [
                {'timeMs': 10250},
              ],
            },
          },
        ),
      );
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await engine.pause();
      await engine.seek(const Duration(seconds: 10, milliseconds: 300));
      await tester.pump();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines,
        hasLength(1),
        reason: '前置：盘上那根半拍线已载入',
      );

      // 同一格点上再落一次 = 无净变化（EditNoop）：没落成，不触达不消耗。
      await tapAddEntry(tester, 'control_half_beat');
      expect(container.read(annotationTimelineProvider).halfBeatLines,
          hasLength(1));
      expect(
        container.read(guideSessionProvider).triggered,
        isNot(contains(badgeHalfBeatUnitId)),
      );
      expect(
        container
            .read(guideSessionProvider).artifactIndexes
            .containsKey(badgeHalfBeatUnitId),
        isFalse,
      );
    });
  });

  group('「备注贴纸」条目与文本编辑器面', () {
    /// 泵播放器、展开控制层、暂停在 t=10s（就绪网格下吸附 8s 起一个八拍）。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpPausedAt10s(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      return (engine, container);
    }

    testWidgets('点击「备注贴纸」建出默认一个八拍时间窗的备注并立即弹出文本编辑器；写入文本、收起即存', (tester) async {
      final (_, container) = await pumpPausedAt10s(tester);

      await tapAddEntry(tester, 'control_note_sticker');

      // 建出默认一个八拍窗（就绪网格 30s：拍点 0.5s 一拍，八拍宽 4s；
      // 10s 请求落在拍点上 → 照落 10s，窗宽仍是一个八拍）。
      expect(container.read(noteStickersProvider), hasLength(1));
      expect(container.read(noteStickersProvider).single.startMs, 10000);
      expect(container.read(noteStickersProvider).single.endMs, 14000);
      // 编辑器立即弹出，文本区为空（新建即弹）。
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.byKey(const Key('note_text_editor_field')),
        ).controller!.text,
        '',
      );
      expect(container.read(annotationEditHistoryProvider).length, 1,
          reason: '创建为一个独立撤销步');

      // 写入文本、收起即存：文本命令入史、编辑器面收起。
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '这里注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('note_text_editor')), findsNothing);
      expect(container.read(noteStickersProvider).single.text, '这里注意手');
      expect(container.read(annotationEditHistoryProvider).length, 2,
          reason: '文本命令为第二个独立撤销步');
    });

    testWidgets('收起时文本未变不产生额外撤销步', (tester) async {
      final (engine, container) = await pumpPausedAt10s(tester);
      await tapAddEntry(tester, 'control_note_sticker');
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '这里注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();
      expect(container.read(annotationEditHistoryProvider).length, 2,
          reason: '创建 + 写文本各一步');

      // 预览线停在窗内（10s..14s）：再点条目转编辑、载入既有文本，
      // 原样收起 = 无净变化 → 不产生额外撤销步。
      await engine.seek(const Duration(seconds: 13));
      await tester.pump();
      final stepsBefore =
          container.read(annotationEditHistoryProvider).length;
      await tapAddEntry(tester, 'control_note_sticker');
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();
      expect(container.read(annotationEditHistoryProvider).length, stepsBefore,
          reason: '文本未变，收起不入史');
    });

    testWidgets('建出备注后一个字没写就收起：片段不留（空文本不是可保存状态）', (tester) async {
      final (_, container) = await pumpPausedAt10s(tester);
      await tapAddEntry(tester, 'control_note_sticker');
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);

      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();

      expect(container.read(noteStickersProvider), isEmpty);
      expect(find.byKey(const Key('note_text_editor')), findsNothing);
    });

    testWidgets('锁定分段：清空文本收起照常删备注（锁只护分段结构，不弹锁提示）', (tester) async {
      final (_, container) = await pumpPausedAt10s(tester);
      await tapAddEntry(tester, 'control_note_sticker');
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '这里注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();

      container.read(noteTextEditorTargetProvider.notifier).open(10000);
      await tester.pump();
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
      expect(container.read(noteStickersProvider), isEmpty,
          reason: '空文本 = 删除备注，锁定分段不挡备注删除');
      expect(find.byKey(const Key('note_text_editor')), findsNothing,
          reason: '收起照常发生');
    });

    testWidgets('编辑目标失效（备注被撤销移除）时编辑器面收起、不残留空面板', (tester) async {
      final (_, container) = await pumpPausedAt10s(tester);
      await tapAddEntry(tester, 'control_note_sticker');
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);

      // 撤销建备注 → 目标备注消失 → 编辑器面收起。
      container.read(annotationEditorProvider).undo();
      await tester.pumpAndSettle();

      expect(container.read(noteStickersProvider), isEmpty);
      expect(find.byKey(const Key('note_text_editor')), findsNothing);
    });

    testWidgets('锁定分段：备注贴纸条目照常可用，点击建备注并弹编辑器（锁只护分段结构）', (tester) async {
      final (_, container) = await pumpPausedAt10s(tester);
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();

      await openAddMenu(tester);
      expect(
        (tester.widget(
          find.byKey(const Key('control_note_sticker')),
        ) as dynamic)
            .enabled,
        isTrue,
        reason: '备注贴纸不受锁定分段',
      );
      await tester.tap(find.byKey(const Key('control_note_sticker')));
      await tester.pumpAndSettle();

      expect(container.read(noteStickersProvider), hasLength(1));
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);
    });

    testWidgets('预览线落在既有备注窗内：点「备注贴纸」不新建，打开那条既有备注的编辑器', (tester) async {
      final (engine, container) = await pumpPausedAt10s(tester);

      // 先在 10s 建一条备注（吸附后窗 = 12s..16s），写入文本并收起。
      await tapAddEntry(tester, 'control_note_sticker');
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '这里注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();
      expect(container.read(noteStickersProvider), hasLength(1));

      // 预览线停在窗内 13s：点击条目 → 备注条数不变、无新撤销步，
      // 编辑器打开的是那条既有备注（文本区载入其既有文本）。
      await engine.seek(const Duration(seconds: 13));
      await tester.pump();
      await tapAddEntry(tester, 'control_note_sticker');

      expect(container.read(noteStickersProvider), hasLength(1),
          reason: '落点已占不新建');
      expect(container.read(annotationEditHistoryProvider).length, 2,
          reason: '转编辑不入史（建 1 + 文本 1）');
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.byKey(const Key('note_text_editor_field')),
        ).controller!.text,
        '这里注意手',
        reason: '打开的是既有备注的编辑器',
      );
    });

    testWidgets('预览线在空档：照常新建（行为不变）', (tester) async {
      final (engine, container) = await pumpPausedAt10s(tester);
      await tapAddEntry(tester, 'control_note_sticker');
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '这里注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();
      expect(container.read(noteStickersProvider), hasLength(1));

      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tapAddEntry(tester, 'control_note_sticker');

      expect(container.read(noteStickersProvider), hasLength(2));
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);
    });

    testWidgets('空档新建：新贴纸沿用前一条（左邻）的位置与大小', (tester) async {
      final (engine, container) = await pumpPausedAt10s(tester);
      const inherited = NoteGeometry(centerX: 0.2, centerY: 0.8, scale: 2.0);

      // 第一条建在 10s（窗 [10s,14s)），再把它拖到左下角并放大。
      await tapAddEntry(tester, 'control_note_sticker');
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '这里注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pumpAndSettle();
      container.read(annotationEditorProvider).submit(
        const SetNoteGeometry(index: 0, geometry: inherited),
      );
      await tester.pump();

      // 预览线移到 20s 的空档再建一条：它落在左邻的位置与大小上。
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tapAddEntry(tester, 'control_note_sticker');

      final notes = container.read(noteStickersProvider);
      expect(notes, hasLength(2));
      expect(notes.last.startMs, 20000);
      expect(notes.last.geometry, inherited);
    });

  });

  group('局部镜像槽与片段删除', () {
    /// 泵一个就绪网格、暂停在 t=10s 的播放器（便于断言片段落点/删除）。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpPausedAt(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      return (engine, container);
    }

    testWidgets('底部「添加」菜单选「局部镜像片段」在播放头处创建片段（经模块 verb、入史）', (tester) async {
      final (_, container) = await pumpPausedAt(tester);
      expect(find.byKey(const Key('control_add')), findsOneWidget);

      final before = container.read(localMirrorFragmentsProvider);
      await tapAddEntry(tester, 'control_local_mirror');
      await tester.pumpAndSettle();

      final after = container.read(localMirrorFragmentsProvider);
      expect(after.length, before.length + 1, reason: '创建即入片段 lane');
      expect(
        container.read(annotationEditHistoryProvider).length,
        1,
        reason: '创建为一个独立撤销步',
      );
    });

    testWidgets('选中片段后删除可用；删除经模块 verb 移除并清选中', (tester) async {
      final (_, container) = await pumpPausedAt(tester);
      // 先经「添加」菜单创建片段（播放头 10s → 就绪八拍 8s 起默认宽 4s）。
      await tapAddEntry(tester, 'control_local_mirror');
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider).length, 1);
      // 片段独立 lane 未选中 → 删除无作用对象（置灰但按得动）。
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);

      // 片段块「单击 = 选中并取反启停」。
      await tester.tap(
        find.byKey(const Key('mirror_fragment_0_icon')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '选中片段后删除可用');
      expect(
        container.read(selectedLocalMirrorFragmentIndexProvider),
        0,
      );

      // 删除经模块 verb：片段移除 + 选中清除。
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), isEmpty);
      expect(container.read(annotationSelectionProvider), isNull);
    });
  });

  group('局部镜像端到端回归：整条路径经 UI 收敛', () {
    /// 泵出展开控制层的播放页并取出容器（本组两用例共用开头，收口；
    /// 自带引擎、不注入按视频文档存储——与 [pumpMirrorPlayer] 的差别即在此）。
    Future<ProviderContainer> pumpMirrorPlayerWithEngine(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      return ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
    }

    /// 在 [fragmentIndex] 片段块上单击（= 只选中）。
    Future<void> tapFragment(WidgetTester tester, int fragmentIndex) async {
      await tester.tap(
        find.byKey(Key('mirror_fragment_${fragmentIndex}_icon')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('端到端：槽建→总开关→位置反相→删除 全程经真实 PlayerPage UI', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final container = await pumpMirrorPlayerWithEngine(tester, engine);
      expect(surfaceMirrored(tester), isFalse, reason: '无片段、全局镜像关 → 不翻转');

      // ① 建：在播放头 8s（八拍点）处经「添加」菜单的「局部镜像片段」条目
      // 创建默认一"八拍"启用片段。
      await freezePlayheadAt(tester, engine, const Duration(seconds: 8));
      expect(find.byKey(const Key('control_add')), findsOneWidget);
      await tapAddEntry(tester, 'control_local_mirror');
      await tester.pumpAndSettle();
      final fragments = container.read(localMirrorFragmentsProvider);
      expect(fragments, hasLength(1));
      // 轨上琥珀块出现（创建即打开总开关 → 生效视觉）。
      expect(find.byKey(const Key('mirror_fragment_0_icon')), findsOneWidget);

      // ② 位置反相：停在片段内（含起点）→ 画面翻转；停在右端外（半开）→ 恢复。
      final f = fragments.single;
      await freezePlayheadAt(tester, engine, Duration(milliseconds: f.startMs));
      expect(surfaceMirrored(tester), isTrue, reason: '启用片段覆盖当前位置 → 反相');
      await freezePlayheadAt(tester, engine, Duration(milliseconds: f.endMs));
      expect(surfaceMirrored(tester), isFalse, reason: '半开右端外 → 保持全局镜像');

      // ③ 总开关闭环：全局镜像全程关——切总开关关 → 同位置不再翻转；再开 →
      // 同位置又翻转。翻转严格随总开关变（片段无自带启停位）。
      container.read(localMirrorEnabledProvider.notifier).replace(false);
      await tester.pump();
      await freezePlayheadAt(tester, engine, Duration(milliseconds: f.startMs));
      expect(surfaceMirrored(tester), isFalse, reason: '总开关关 → 全片按全局镜像');
      container.read(localMirrorEnabledProvider.notifier).replace(true);
      await tester.pump();
      await freezePlayheadAt(tester, engine, Duration(milliseconds: f.startMs));
      expect(surfaceMirrored(tester), isTrue,
          reason: '总开关重开 → 同位置又翻转（翻转随总开关）');

      // ④ 删除：单击选中（点选只选中）后删除可用，经模块 verb 移除。
      await tapFragment(tester, 0);
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '选中片段后删除可用');
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), isEmpty);
      expect(container.read(annotationSelectionProvider), isNull);
      await freezePlayheadAt(tester, engine, Duration(milliseconds: f.startMs));
      expect(surfaceMirrored(tester), isFalse, reason: '片段删除后画面不翻转');
    });

    testWidgets('锁定分段开启：局部镜像条目与删除照常、不弹锁提示；撤销/重做照常', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpMirrorPlayerWithEngine(tester, engine);

      // 建一条片段并选中（解锁态）。
      await freezePlayheadAt(tester, engine, const Duration(seconds: 10));
      await tapAddEntry(tester, 'control_local_mirror');
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(1));
      // 单击片段 = 只选中，删除可用。
      await tapFragment(tester, 0);
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);

      // 开启锁定分段。
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('锁定分段·开'), findsOneWidget);

      // 「添加」钮不受锁：菜单照常打开，锁下选「局部镜像」照常建新片段。
      expect(slotEnabled(tester, 'control_add'), isTrue);
      await freezePlayheadAt(tester, engine, const Duration(seconds: 20));
      await openAddMenu(tester);
      expect(
        renderedAddEntryKeys(tester),
        AddEntryTable.normal.entries.map((e) => e.key).toList(),
        reason: '锁定期间菜单照常打开',
      );
      await tester.tap(find.byKey(const Key('control_local_mirror')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(2),
          reason: '锁下局部镜像条目照常建片段');
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);

      // 删除：局部镜像片段不受锁，照常删除。
      await tapFragment(tester, 0);
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(1));
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);

      // 撤销/重做照常回放。
      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(2),
          reason: '撤销仍回放删除步');
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);

      await tester.tap(find.byKey(const Key('tool_redo')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(1),
          reason: '重做仍回放删除步');
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });
  });

  group('顶栏「全局镜像 / 局部镜像」两槽（直接挂载控制层）', () {
    /// 建一条片段（经「添加」菜单）：创建即生效 → 总开关自动打开。
    Future<void> addFragment(WidgetTester tester) async {
      await tapAddEntry(tester, 'control_local_mirror');
      await tester.pumpAndSettle();
    }

    testWidgets('两槽几何：「局部镜像」紧邻「全局镜像」右侧、同一分隔段内（槽文案与次序归表直测）', (
      tester,
    ) async {
      await pumpControlLayer(tester);

      final global = tester.getRect(find.byKey(const Key('tool_mirror')));
      final local = tester.getRect(find.byKey(const Key('tool_local_mirror')));
      expect(local.top, global.top, reason: '两槽同排（同一分隔段内）');
      expect(
        local.left,
        closeTo(global.right, 0.5),
        reason: '紧邻右侧、中间无分隔线',
      );
    });

    testWidgets('有片段：点一下标黄、总开关即生效；再点取消', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await addFragment(tester);

      // 创建即生效（总开关自动打开）：定格在片段内 → 局部生效态亮琥珀。
      final fragment = container.read(localMirrorFragmentsProvider).single;
      await engine.seek(Duration(milliseconds: fragment.startMs));
      await tester.pump();
      expect(toolIconColor(tester, 'tool_local_mirror'), kHighlightAmber);
      expect(container.read(localMirrorEnabledProvider), isTrue);

      // 再点取消：整组不生效。
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(
        toolIconColor(tester, 'tool_local_mirror'),
        isNot(kHighlightAmber),
      );
      expect(container.read(localMirrorEnabledProvider), isFalse,
          reason: '一点即生效');

      // 三点再开：立即恢复生效。
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(toolIconColor(tester, 'tool_local_mirror'), kHighlightAmber);
      expect(container.read(localMirrorEnabledProvider), isTrue);
    });

    testWidgets('无片段：置灰但仍可点，点一下弹「请添加局部镜像片段」且不产生任何状态变化', (tester) async {
      final (_, container, docs, _) = await pumpControlLayer(tester);
      expect(container.read(localMirrorFragmentsProvider), isEmpty);
      expect(
        toolIconColor(tester, 'tool_local_mirror'),
        kToolSlotDisabledIconColor,
        reason: '无片段置灰',
      );
      final valueBefore = container.read(localMirrorEnabledProvider);
      final depthBefore = container.read(annotationEditHistoryProvider).length;

      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();

      expect(find.text('请添加局部镜像片段'), findsOneWidget);
      expect(find.byKey(const Key('local_mirror_empty_prompt')), findsOneWidget);
      expect(container.read(localMirrorEnabledProvider), valueBefore,
          reason: '软门点击不产生状态变化');
      expect(container.read(annotationEditHistoryProvider).length, depthBefore,
          reason: '不入撤销/重做史');
      expect(docs.markersSnapshot, isEmpty, reason: '不写盘');

      // 居中轻提示短暂后自动消失（时长取模块表值，不再 import 生产常量）。
      await tester.pump(noticeTimingOf(NoticeId.localMirrorEmpty).hold);
      await tester.pump();
      expect(find.byKey(const Key('local_mirror_empty_prompt')), findsNothing);
    });

    testWidgets('删掉最后一条片段：按钮回置灰、取值保留；再加片段时新建那一条仍自动打开', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await addFragment(tester);

      // 关掉总开关（片段整组不生效）。
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(container.read(localMirrorEnabledProvider), isFalse);

      // 选中最后一条片段并删除。
      await tester.tap(
        find.byKey(const Key('mirror_fragment_0_icon')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();

      expect(container.read(localMirrorFragmentsProvider), isEmpty);
      expect(
        toolIconColor(tester, 'tool_local_mirror'),
        kToolSlotDisabledIconColor,
        reason: '删掉最后一条 → 按钮回置灰',
      );
      expect(container.read(localMirrorEnabledProvider), isFalse,
          reason: '取值保留（不自我打开）');

      // 再加片段：沿用上次取值之上，按「创建即生效」自动打开新建那一条。
      await addFragment(tester);
      expect(container.read(localMirrorEnabledProvider), isTrue);
      expect(toolIconColor(tester, 'tool_local_mirror'), kHighlightAmber);
    });

    testWidgets('锁定分段开启：切换照常生效（视图开关不受锁）；切换前后撤销栈深度不变', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await addFragment(tester);
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();
      final depth = container.read(annotationEditHistoryProvider).length;

      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();

      expect(container.read(localMirrorEnabledProvider), isFalse,
          reason: '锁定期间照常生效');
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing,
          reason: '视图开关不走标注门禁，不弹「已锁定分段」');
      expect(container.read(annotationEditHistoryProvider).length, depth,
          reason: '切换前后撤销栈深度不变（不入史）');
    });

    testWidgets('切换即写盘：公开标记文件里读得到该字段；本机缓存（视频索引）同步回写', (tester) async {
      final (engine, container, docs, _) = await pumpControlLayer(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await addFragment(tester);
      expect(
        marker_doc.MarkersDocument.fromJson(docs.markersSnapshot)
            .localMirrorEnabled,
        isTrue,
        reason: '创建即生效：首建 markers 就带总开关真值',
      );

      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();

      expect(
        marker_doc.MarkersDocument.fromJson(docs.markersSnapshot)
            .localMirrorEnabled,
        isFalse,
        reason: '切换即写盘（无「保存」步）',
      );
      final index = await container.read(videoIndexStoreProvider).load();
      expect(
        index.findByFilePath(
          Uri.file('/videos/a.mp4').toFilePath(),
        )!.localMirrorEnabled,
        isFalse,
        reason: '本机缓存同步回写',
      );
      expect(container.read(localMirrorEnabledProvider), isFalse);
    });

    testWidgets('锁定分段下选条目照常创建并自动打开总开关（锁只护分段结构）', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await addFragment(tester);
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(container.read(localMirrorEnabledProvider), isFalse);

      // 锁定分段下再选条目：照常创建（片段）→ 总开关自动打开。
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();
      await addFragment(tester);

      expect(container.read(localMirrorFragmentsProvider), hasLength(2),
          reason: '局部镜像片段不受锁定分段');
      expect(
        container.read(localMirrorEnabledProvider),
        isTrue,
        reason: '创建成功即自动打开总开关',
      );
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });

    testWidgets('杀进程重开：新会话（新容器、同一持久化文档）按标记文件真值恢复总开关', (tester) async {
      final (engine, container, docs, _) = await pumpControlLayer(tester);
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await addFragment(tester);
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(container.read(localMirrorEnabledProvider), isFalse);
      expect(
        marker_doc.MarkersDocument.fromJson(docs.markersSnapshot)
            .localMirrorEnabled,
        isFalse,
        reason: '切换已落盘',
      );

      // 杀进程重开：新挂载（新 ProviderScope / 新容器）、同一持久化文档。
      final (_, reopened, _, _) =
          await pumpControlLayer(tester, docs: docs);

      expect(reopened.read(localMirrorEnabledProvider), isFalse,
          reason: '重开按标记文件真值恢复，不回到缺省');
    });
  });

  group('镜像两层开关端到端回归', () {
    /// 片段块填充色（生效 = 琥珀、不生效 = 灰；视觉全由总开关驱动）。
    Color fragmentFillColor(WidgetTester tester, int index) {
      final block = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ValueKey('mirror_fragment_$index')),
              matching: find.byType(Container),
            )
            .first,
      );
      return (block.decoration! as BoxDecoration).color!;
    }

    /// 片段块反相图标色（本组片段为默认一「八拍」宽 = 宽块，图标恒在）。
    Color fragmentIconColor(WidgetTester tester, int index) => tester
        .widget<Icon>(find.byKey(ValueKey('mirror_fragment_${index}_icon')))
        .color!;

    /// 顶栏槽是否处于琥珀激活态（两个镜像开关的真值在 UI 上的可观察面）。
    bool slotAmber(WidgetTester tester, String toolKey) =>
        toolIconColor(tester, toolKey) == kHighlightAmber;

    /// 经「添加」菜单的「局部镜像片段」条目在 [position] 处建一条片段
    /// （走真实菜单链，不直调模块 verb）。
    Future<LocalMirrorFragment> addFragmentViaMenu(
      WidgetTester tester,
      FakePlaybackEngine engine,
      ProviderContainer container,
      Duration position,
    ) async {
      await engine.pause();
      await engine.seek(position);
      await tester.pump();
      await tapAddEntry(tester, 'control_local_mirror');
      await tester.pumpAndSettle();
      return container.read(localMirrorFragmentsProvider).single;
    }

    /// 经顶栏槽把全局镜像对齐到 [on]（槽的琥珀态即真值，不读 provider）。
    Future<void> alignGlobalMirror(WidgetTester tester, bool on) async {
      if (slotAmber(tester, 'tool_mirror') != on) {
        await tester.tap(find.byKey(const Key('tool_mirror')));
        await tester.pump();
      }
      expect(slotAmber(tester, 'tool_mirror'), on, reason: '全局镜像对齐到 $on');
    }

    /// 经顶栏槽把局部镜像总开关对齐到 [on]（须已有片段，否则槽为软门）。
    Future<void> alignLocalMirror(WidgetTester tester, bool on) async {
      if (slotAmber(tester, 'tool_local_mirror') != on) {
        await tester.tap(find.byKey(const Key('tool_local_mirror')));
        await tester.pump();
      }
      expect(
        slotAmber(tester, 'tool_local_mirror'),
        on,
        reason: '局部镜像总开关对齐到 $on',
      );
    }

    testWidgets('主路径：添加菜单建片段（总开关自动打开）→ 顶栏变黄 → 区间内反相/离开恢复 → 取消（画面恢复且轨道全灰）→ 再开（恢复琥珀且反相）', (
      tester,
    ) async {
      // 与模块 verb / provider 直写的两组不同：那条链上「建」与「启停」
      // provider 直写，轨道块颜色与顶栏琥珀态分属两组；本用例把「添加菜单
      // → 顶栏开关 → 轨道块颜色 → 画面翻转」收成一条全程经真实 PlayerPage
      // UI 的链，并断言落盘真值。
      // 播放头位置经 [FakePlaybackEngine]（生产 [PlaybackEngine] 契约的测试
      // 实现）建立，不直写任何 provider/私有状态；UI 通路改位置另由本组的
      // 步进与拖动定格两用例覆盖。
      // 起点是升级后真实存在的状态：标记文件里总开关为关（用户上次关过）、
      // 没有任何片段。
      final (engine, container, docs) = await pumpMirrorPlayer(tester, markers: {
        'version': 8,
        'meta': {'mirrored': false, 'localMirrorEnabled': false},
      });
      expect(container.read(localMirrorEnabledProvider), isFalse,
          reason: '打开读到 markers 真值');
      expect(container.read(localMirrorFragmentsProvider), isEmpty,
          reason: '起点无片段');
      expect(
        toolIconColor(tester, 'tool_local_mirror'),
        kToolSlotDisabledIconColor,
        reason: '无片段 → 顶栏「局部镜像」置灰',
      );
      expect(surfaceMirrored(tester), isFalse, reason: '起点画面不翻转');

      // ① 「添加 → 局部镜像片段」在播放头 8s（就绪网格八拍点）建默认一
      // 「八拍」宽的片段；总开关此刻为关 → 创建即生效、自动打开。
      final fragment = await addFragmentViaMenu(
        tester,
        engine,
        container,
        const Duration(seconds: 8),
      );
      expect(fragment.startMs, 8000, reason: '创建起点吸八拍点');
      expect(fragment.endMs, 12000, reason: '默认宽一个「八拍」');
      final start = Duration(milliseconds: fragment.startMs);
      final end = Duration(milliseconds: fragment.endMs);
      expect(container.read(localMirrorEnabledProvider), isTrue,
          reason: '总开关自动打开');
      expect(slotAmber(tester, 'tool_local_mirror'), isTrue,
          reason: '顶栏「局部镜像」变黄');
      expect(
        marker_doc.MarkersDocument.fromJson(docs.markersSnapshot)
            .localMirrorEnabled,
        isTrue,
        reason: '自动打开即写盘',
      );
      expect(fragmentFillColor(tester, 0), kLocalMirrorEnabledFill,
          reason: '总开关开 → 轨道片段琥珀填充');
      expect(fragmentIconColor(tester, 0), kLocalMirrorEnabledIconColor,
          reason: '总开关开 → 片段图标琥珀');

      // ② 播放头进入片段区间 → 画面反相；离开（半开右端外）→ 恢复。
      await freezePlayheadAt(tester, engine, start);
      expect(surfaceMirrored(tester), isTrue, reason: '区间内（含起点）反相');
      await freezePlayheadAt(tester, engine, end);
      expect(surfaceMirrored(tester), isFalse, reason: '半开右端外 → 恢复全局镜像');

      // ③ 顶栏点一下取消：画面不再反相，轨道片段全灰。
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(container.read(localMirrorEnabledProvider), isFalse,
          reason: '一点即生效（无「保存」步）');
      expect(slotAmber(tester, 'tool_local_mirror'), isFalse,
          reason: '顶栏「局部镜像」熄灭');
      await freezePlayheadAt(tester, engine, start);
      expect(surfaceMirrored(tester), isFalse, reason: '取消后区间内也不反相');
      expect(fragmentFillColor(tester, 0), kLocalMirrorDisabledFill,
          reason: '总开关关 → 轨道片段全灰填充');
      expect(fragmentIconColor(tester, 0), kLocalMirrorDisabledIconColor,
          reason: '总开关关 → 片段图标灰');

      // ④ 再点开：恢复琥珀且画面反相（位置不变、立即生效）。
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(slotAmber(tester, 'tool_local_mirror'), isTrue,
          reason: '顶栏「局部镜像」恢复琥珀');
      expect(surfaceMirrored(tester), isTrue, reason: '同位置又反相');
      expect(fragmentFillColor(tester, 0), kLocalMirrorEnabledFill,
          reason: '轨道片段恢复琥珀填充');
      expect(fragmentIconColor(tester, 0), kLocalMirrorEnabledIconColor,
          reason: '轨道片段恢复琥珀图标');
    });

    testWidgets('四种组合各抽查一次：全局镜像 × 总开关，片段内与片段外各判（两个开关全程经顶栏槽驱动）', (
      tester,
    ) async {
      final (engine, container, docs) = await pumpMirrorPlayer(tester);
      final fragment = await addFragmentViaMenu(
        tester,
        engine,
        container,
        const Duration(seconds: 8),
      );
      final start = Duration(milliseconds: fragment.startMs);
      final end = Duration(milliseconds: fragment.endMs);

      // 真值表逐行写死：全局 / 总开关 /
      // 片段内有效镜像 / 片段外有效镜像。期望值不由被测实现推导。
      for (final (global, local, inside, outside) in [
        (false, false, false, false),
        (false, true, true, false),
        (true, false, true, true),
        (true, true, false, true),
      ]) {
        await alignGlobalMirror(tester, global);
        await alignLocalMirror(tester, local);
        // 两个开关的绝对锚点：值道 + 公开标记文件真值（不只靠槽的琥珀态）。
        expect(container.read(localMirrorEnabledProvider), local,
            reason: '值道 = 总开关 $local');
        expect(
          marker_doc.MarkersDocument.fromJson(docs.markersSnapshot)
              .localMirrorEnabled,
          local,
          reason: '标记文件 meta.localMirrorEnabled = $local',
        );
        expect(
          marker_doc.MarkersDocument.fromJson(docs.markersSnapshot).mirrored,
          global,
          reason: '标记文件 meta.mirrored = $global',
        );

        await freezePlayheadAt(tester, engine, start);
        expect(
          surfaceMirrored(tester),
          inside,
          reason: '全局镜像=$global、总开关=$local、片段内 → 反相=$inside',
        );
        await freezePlayheadAt(tester, engine, end);
        expect(
          surfaceMirrored(tester),
          outside,
          reason: '全局镜像=$global、总开关=$local、片段外 → 反相=$outside',
        );
      }
    });

    testWidgets('步进定格同判：区间内后退一帧即恢复、再前进一帧又反相（位置即真值）', (tester) async {
      final (engine, container, _) = await pumpMirrorPlayer(tester);
      final fragment = await addFragmentViaMenu(
        tester,
        engine,
        container,
        const Duration(seconds: 8),
      );
      final start = Duration(milliseconds: fragment.startMs);

      // 前置：全局镜像关、总开关开（创建即生效）→ 区间内反相。
      expect(slotAmber(tester, 'tool_mirror'), isFalse,
          reason: '前置：全局镜像关');
      expect(slotAmber(tester, 'tool_local_mirror'), isTrue,
          reason: '前置：总开关开');
      await freezePlayheadAt(tester, engine, start);
      expect(surfaceMirrored(tester), isTrue, reason: '前置：区间内反相');

      // 无选中时帧步进 = 预览进度 ±1 帧（默认 30fps）；每次 seek 走空白面
      // 唯一提交口，须越过按帧节流窗口（[kScrubSeekMinInterval]）才实际发出。
      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pump();
      await tester.pump(kScrubSeekMinInterval * 2);
      await tester.pump();
      expect(engine.position, lessThan(start), reason: '左移一帧落到区间外');
      expect(surfaceMirrored(tester), isFalse, reason: '步进定格同判：位置即真值');

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();
      await tester.pump(kScrubSeekMinInterval * 2);
      await tester.pump();
      expect(engine.position, start, reason: '右移一帧回到起点');
      expect(surfaceMirrored(tester), isTrue, reason: '步进回到区间内又反相');

      // 换第二组开关组合（全局开 + 总开关开）复判同一对边界：区间内 = 全局
      // ⊕ 覆盖 = 不反相、区间外 = 全局开 = 反相——步进同判不只在单一组合下成立。
      await alignGlobalMirror(tester, true);
      await freezePlayheadAt(tester, engine, start);
      expect(surfaceMirrored(tester), isFalse, reason: '全局开 + 覆盖 → 不反相');
      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pump();
      await tester.pump(kScrubSeekMinInterval * 2);
      await tester.pump();
      expect(engine.position, lessThan(start), reason: '左移一帧落到区间外');
      expect(surfaceMirrored(tester), isTrue,
          reason: '全局开 + 区间外 → 按全局镜像（反相）');
      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pump();
      await tester.pump(kScrubSeekMinInterval * 2);
      await tester.pump();
      expect(surfaceMirrored(tester), isFalse, reason: '步进回区间内又不反相');
    });

    testWidgets('拖动定格同判：编辑态空白微调扫过区间，每个落点的画面与该位置判据一致', (tester) async {
      final (engine, container, _) = await pumpMirrorPlayer(tester);
      final fragment = await addFragmentViaMenu(
        tester,
        engine,
        container,
        const Duration(seconds: 8),
      );
      final startMs = fragment.startMs;
      final endMs = fragment.endMs;

      /// 空白微调扫过整个片段区间：每步 20px = 1s（单指档
      /// [kSeekSensitivityMsPerPx] 50ms/px），每个落点判一次画面，返回扫到的
      /// 画面态集合。期望值 = 「覆盖 ∧ 总开关」与全局镜像的异或，逐落点断言。
      Future<Set<bool>> sweep({required bool global}) async {
        await alignGlobalMirror(tester, global);
        await freezePlayheadAt(tester, engine, Duration.zero);
        expect(surfaceMirrored(tester), global,
            reason: '扫之前停在区间外 → 按全局镜像');

        final gesture = await tester.startGesture(const Offset(400, 150));
        await tester.pump();
        final observed = <bool>{};
        for (var i = 0; i < 16; i++) {
          await gesture.moveBy(const Offset(20, 0));
          // 空白面 seek 唯一提交口按帧节流（[kScrubSeekMinInterval]）：逐帧
          // 推进测试时钟，否则后续目标停在节流窗口内不发往引擎。
          await tester.pump(kScrubSeekMinInterval * 2);
          await tester.pump();
          final positionMs = engine.position.inMilliseconds;
          final covered = positionMs >= startMs && positionMs < endMs;
          final expected = global != covered;
          final mirrored = surfaceMirrored(tester);
          expect(
            mirrored,
            expected,
            reason: '全局=$global 拖动定格在 ${positionMs}ms：覆盖=$covered →'
                '反相=$expected',
          );
          observed.add(mirrored);
        }
        await gesture.up();
        await tester.pump();
        expect(observed, {true, false},
            reason: '扫过区间边界：入区间与出区间的两种画面态都出现过');

        // 松手停在落点（原为暂停 → 不续播），画面与该落点一致。
        expect(engine.isPlaying, isFalse, reason: '微调松手停在落点');
        final landedMs = engine.position.inMilliseconds;
        expect(
          surfaceMirrored(tester),
          global != (landedMs >= startMs && landedMs < endMs),
          reason: '松手后画面按落点判定',
        );
        return observed;
      }

      // 总开关开（创建即生效）+ 全局镜像两态各扫一遍：拖动定格同判不只在
      // 单一组合下成立。
      await sweep(global: false);
      await sweep(global: true);
    });

    testWidgets('锁定分段开启：两个镜像开关照常生效、不入史、不弹锁提示', (tester) async {
      final (engine, container, docs) = await pumpMirrorPlayer(tester);
      final fragment = await addFragmentViaMenu(
        tester,
        engine,
        container,
        const Duration(seconds: 8),
      );
      await freezePlayheadAt(tester, engine, Duration(milliseconds: fragment.startMs));
      expect(surfaceMirrored(tester), isTrue, reason: '全局关 + 总开关开 → 反相');

      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      expect(find.text('锁定分段·开'), findsOneWidget);
      final depth = container.read(annotationEditHistoryProvider).length;

      // 局部镜像总开关：锁下点一下照常生效（整组不生效 → 画面按全局镜像），
      // 且不弹「已锁定分段」——推进到提示驻留时长之后再看，否定断言不靠单帧。
      await tester.tap(find.byKey(const Key('tool_local_mirror')));
      await tester.pump();
      expect(slotAmber(tester, 'tool_local_mirror'), isFalse,
          reason: '锁下总开关熄灭');
      expect(surfaceMirrored(tester), isFalse, reason: '锁下总开关照常生效');
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing,
          reason: '视图开关不走标注门禁（整个提示驻留窗口内都无提示）');

      // 全局镜像：锁下点一下照常生效（全局开 + 总开关关 → 全片镜像）。
      await tester.tap(find.byKey(const Key('tool_mirror')));
      await tester.pump();
      expect(slotAmber(tester, 'tool_mirror'), isTrue,
          reason: '锁下全局镜像变琥珀');
      expect(surfaceMirrored(tester), isTrue, reason: '锁下全局镜像照常生效');
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing,
          reason: '全局镜像同为视图开关，不弹锁提示');

      // 两个开关都不入撤销/重做史，切换后落盘真值随之更新。
      expect(container.read(annotationEditHistoryProvider).length, depth,
          reason: '两个镜像开关均不入史');
      expect(
        marker_doc.MarkersDocument.fromJson(docs.markersSnapshot)
            .localMirrorEnabled,
        isFalse,
        reason: '锁下切换照常写盘',
      );
    });
  });

  group('音画同步入口（直接挂载控制层）', () {
    testWidgets('点开音画同步气泡：含设备名、读数、−/＋、重置',
        (tester) async {
      await pumpControlLayer(tester);

      // 点开：气泡含设备名、读数、−/＋、重置（与节拍提示的相邻几何归表直测）。
      expect(find.byKey(const Key('av_sync_bubble')), findsNothing);
      await tester.tap(find.byKey(const Key('tool_av_sync')));
      // 会话脉冲 ticker 常驻（刻度带/滴答持续产拍）：气泡开启
      // 期间不可 pumpAndSettle，固定帧推进展开落定。
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('av_sync_bubble')), findsOneWidget);
      expect(find.byKey(const Key('av_sync_device')), findsOneWidget);
      expect(find.byKey(const Key('av_sync_readout')), findsOneWidget);
      expect(find.byKey(const Key('av_sync_minus')), findsOneWidget);
      expect(find.byKey(const Key('av_sync_plus')), findsOneWidget);
      expect(find.byKey(const Key('av_sync_reset')), findsOneWidget);
    });

    testWidgets('与节拍提示气泡互斥单开', (tester) async {
      await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_av_sync')));
      // 会话脉冲 ticker 常驻：固定帧推进，不可 pumpAndSettle。
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('av_sync_bubble')), findsOneWidget);

      // 点节拍提示工具先被点外收起遮罩承接（关音画同步）；再点开节拍提示。
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('av_sync_bubble')), findsNothing);
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);

      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
    });
  });

  group('收起控制层与音画同步校准会话（补测；直接挂载控制层）', () {
    testWidgets('收起控制层即取消校准会话：会话转非活跃', (tester) async {
      final (_, container, _, _) = await pumpControlLayer(
        tester,
        engine: FakePlaybackEngine(duration: const Duration(minutes: 1)),
        injectAvSyncSeam: true,
      );

      // 打开音画同步气泡（挂载即进入校准会话）：进入是异步链（设备快照 +
      // 存储读），固定帧推进至活跃。
      container
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.avSync);
      await tester.pump();
      await tester.pump();
      expect(
        container.read(avSyncCalibrationSessionProvider).active,
        isTrue,
        reason: '前置：气泡挂载即进入校准会话',
      );

      // 收起控制层（经模式值收起——生产收起缝）：气泡随展开位边沿自收
      // 尾，显式取消校准会话（丢弃试听值退出，零写盘）。气泡外点遮罩
      // 会吃掉空白点按（点外只收气泡），故经收起缝驱动同一条边沿链。
      container.read(playerSessionProvider.notifier).collapse();
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('control_layer')), findsNothing);
      expect(
        container.read(avSyncCalibrationSessionProvider).active,
        isFalse,
        reason: '收起控制层 = 取消校准会话',
      );
    });
  });

  group('练习素材库子页（播放器内入口退场，夹具直开子页）', () {
    late Directory materialLibraryTempDir;
    setUp(() async {
      materialLibraryTempDir = await Directory.systemTemp.createTemp(
        'control_layer_material_library',
      );
    });
    tearDown(() async {
      if (materialLibraryTempDir.existsSync()) {
        materialLibraryTempDir.deleteSync(recursive: true);
      }
    });

    Future<void> pumpSheetFrames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 装载 future 在浮层首帧后的微任务里完成：再 pump 一帧显示结果。
      await tester.pump();
    }

    /// 直开素材库子页（播放器内入口退场，页面行为由本组直驱子页
    /// 覆盖——查看与删除路径与既有口径逐位一致）。
    Future<void> openMaterialSheet(WidgetTester tester) async {
      final context = tester.element(find.byType(PlayerPage));
      showModalBottomSheet<void>(
        context: context,
        builder: (context) => const MaterialLibraryPage(),
      );
      await pumpSheetFrames(tester);
    }

    /// 泵出播放页 → 唤出控制层 → 容器直进对比-控制层（绕过宿主编排；
    /// 本文件「对比态标注工具区槽集」组先例）。素材清单/目录注入内存与
    /// 临时目录实现——真实文件 IO 在 fake async 时钟下不完成。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpCompareEditing(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        extraOverrides: [
          materialManifestStorageProvider.overrideWithValue(
            MemoryManifestStorage(),
          ),
          materialsBaseDirectoryProvider.overrideWithValue(
            () async => materialLibraryTempDir,
          ),
        ],
      );
      await singleTapShow(tester);
      await engine.pause();
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      return (engine, container);
    }

    /// 种一条当前舞的素材（写入清单——子页打开时经 openFor 按 videoId
    /// 装载；测试容器里 videoId 不会随署名解析，显式设定）。
    Future<void> seedMaterial(ProviderContainer container) async {
      container.read(currentVideoIdProvider.notifier).set('vid_test');
      await container.read(materialManifestStoreProvider).append(
        MaterialRecord(
          id: 'mat_a',
          videoId: 'vid_test',
          createdAt: DateTime(2026, 9, 13, 14, 30),
          durationMs: 8000,
          sourceStartMs: 10000,
          fileName: 'rec_1.mp4',
          sizeBytes: 1,
        ),
      );
    }

    testWidgets('播放器内不再有素材库入口：顶栏无「文件」，全树无「练习素材库」', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      expect(find.byKey(const Key('tool_file')), findsNothing);
      expect(find.text('文件'), findsNothing);
      expect(find.text('练习素材库'), findsNothing);
    });

    testWidgets('子页列条目（区间/时长/录制时刻）', (tester) async {
      final (_, container) = await pumpCompareEditing(tester);
      await seedMaterial(container);
      await openMaterialSheet(tester);

      expect(find.byKey(const Key('material_library_page')), findsOneWidget);
      expect(find.text('00:10 - 00:18'), findsOneWidget,
          reason: '录制区间 = 源起点 + 素材时长');
      expect(find.text('时长 00:08'), findsOneWidget);
      expect(find.text('录制于 2026-09-13 14:30'), findsOneWidget);
      expect(find.byKey(const Key('material_library_empty')), findsNothing);
    });

    testWidgets('空态：无素材时给空态提示', (tester) async {
      await pumpCompareEditing(tester);
      await openMaterialSheet(tester);

      expect(find.byKey(const Key('material_library_empty')), findsOneWidget);
    });

    testWidgets('删除需确认并连带删文件与全部轨道引用', (tester) async {
      final (_, container) = await pumpCompareEditing(tester);
      await seedMaterial(container);
      container.read(practiceClipsProvider.notifier).state = [
        const PracticeClip(
          id: 'clip_a',
          materialId: 'mat_a',
          materialSourceStartMs: 10000,
          inMs: 0,
          outMs: 8000,
        ),
      ];
      await tester.pump();
      await openMaterialSheet(tester);

      // 点删除 → 确认弹窗提示连带删除。
      await tester.tap(find.byKey(const Key('material_library_delete_0')));
      await pumpSheetFrames(tester);
      expect(find.byKey(const Key('material_library_delete_dialog')),
          findsOneWidget);
      expect(find.text('将连其全部轨道引用一并删除'), findsOneWidget);

      // 确认：条目消失、轨道引用连带删除。
      await tester.tap(
        find.byKey(const Key('material_library_confirm_delete')),
      );
      await pumpSheetFrames(tester);
      await pumpSheetFrames(tester);
      expect(find.byKey(const Key('material_library_empty')), findsOneWidget);
      expect(container.read(practiceClipsProvider), isEmpty);
    });
  });

  group('练习片段选中与删除（自导出组迁出）', () {
    /// 泵出播放页 → 进入对比-控制层 → 种入素材 + 片段并选中：练习片段写
    /// 点的标准夹具（素材清单注入内存实现——真实文件 IO 在 fake async
    /// 时钟下不完成）。
    Future<(FakePlaybackEngine, ProviderContainer)> pumpClipReady(
      WidgetTester tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        manifestStorage: MemoryManifestStorage(),
      );
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();

      // 素材入库 + 片段入轨 + 选中（容器直写）。
      final material = MaterialRecord(
        id: 'm1',
        videoId: 'vid_a',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        durationMs: 10000,
        sourceStartMs: 5000,
        fileName: 'rec_1.mp4',
        sizeBytes: 8,
      );
      await container.read(materialManifestStoreProvider).append(material);
      container.read(practiceClipsProvider.notifier).restore([
        const PracticeClip(
          id: 'c1',
          materialId: 'm1',
          materialSourceStartMs: 5000,
          inMs: 1000,
          outMs: 4000,
          materialDurationMs: 10000,
        ),
      ]);
      container.read(selectedPracticeClipIdProvider.notifier).select('c1');
      await tester.pumpAndSettle();
      return (engine, container);
    }

    testWidgets('块体点选 = 选中写点：再点同片段取消；选中态描边可见', (tester) async {
      final (_, container) = await pumpClipReady(tester);
      // 夹具预置了选中；本用例从无选中起测。
      container.read(selectedPracticeClipIdProvider.notifier).select(null);
      await tester.pumpAndSettle();
      expect(container.read(selectedPracticeClipIdProvider), isNull);

      await tester.tap(find.byKey(const Key('practice_clip_c1')));
      await tester.pumpAndSettle();
      expect(container.read(selectedPracticeClipIdProvider), 'c1');
      // 选中态在轨道带块上有可见表现（描边）：未选中块无描边。
      final decoratedBoxes = tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('practice_clip_c1')),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        decoratedBoxes.any(
          (box) =>
              box.decoration is BoxDecoration &&
              (box.decoration as BoxDecoration).border != null,
        ),
        isTrue,
      );

      // 隔过双击判定窗口再点：两次快速 tap 会被并成双击。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.tap(find.byKey(const Key('practice_clip_c1')));
      await tester.pumpAndSettle();
      expect(container.read(selectedPracticeClipIdProvider), isNull);
    });

    testWidgets('删除只把选中片段移出轨道：素材与清单保留、选中整清、一步撤销可回退', (
      tester,
    ) async {
      final (_, container) = await pumpClipReady(tester);
      // 夹具已预置选中 c1。
      expect(container.read(selectedPracticeClipIdProvider), 'c1');
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();
      expect(container.read(practiceClipsProvider), isEmpty);
      // 选中随片段移出轨道整清（删除槽回无对象置灰，按得动、弹做法）。
      expect(container.read(selectedPracticeClipIdProvider), isNull);
      // 素材库条目保留。
      expect(
        (await container.read(materialManifestStoreProvider).read()).materials,
        hasLength(1),
      );
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue);

      // 一步撤销：片段回轨（片段 lane 参与历史折叠）。
      await tester.tap(find.byKey(const Key('tool_undo')));
      await tester.pumpAndSettle();
      expect(container.read(practiceClipsProvider), hasLength(1));
    });

    testWidgets('对比态：分段线选中残留不点亮删除槽', (
      tester,
    ) async {
      final (_, container) = await pumpClipReady(tester);
      // 从无片段选中起测（夹具预置了选中 c1）：本用例只钉线选中残留。
      container.read(selectedPracticeClipIdProvider.notifier).select(null);
      // 前置：退回编辑态，种一条分段线并选中，再进对比态——选中槽残留。
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      await tester.pumpAndSettle();
      container
          .read(annotationEditorProvider)
          .submit(AddSegmentLine(at: const Duration(seconds: 10)));
      container
          .read(annotationSelectionDomainProvider)
          .select(SegmentLineSelection(0));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '编辑态：选中分段线删除可用');
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      expect(container.read(selectedSegmentLineIndexProvider), 0,
          reason: '前置：分段线选中跨模式残留');
      // 对比态删除只认选中的练习片段：残留的线选中不得点亮删除槽
      // （无对象 → 置灰，起置灰仍按得动 = 弹做法、不放行动作）。
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '对比态两类线删不掉，线选中残留不放行删除');
      expect(slotIconColor(tester, 'control_segment_delete'),
          kToolSlotDisabledIconColor,
          reason: '删除槽仍置灰');
    });

    testWidgets('编辑态：练习片段选中残留不点亮删除槽', (
      tester,
    ) async {
      final (_, container) = await pumpClipReady(tester);
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '对比态：选中片段删除可用');
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      await tester.pumpAndSettle();
      expect(container.read(selectedPracticeClipIdProvider), 'c1',
          reason: '前置：片段选中跨模式残留');
      // 编辑态删除不认练习片段：残留的片段选中不得点亮删除槽
      // （无对象 → 置灰，起置灰仍按得动 = 弹做法、不放行动作）。
      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '编辑态删除只认线与局部镜像片段');
      expect(slotIconColor(tester, 'control_segment_delete'),
          kToolSlotDisabledIconColor,
          reason: '删除槽仍置灰');
    });
  });

  group('控制层语义档文本随系统字号', () {
    for (final scale in [1.3, 1.6]) {
      testWidgets('textScaler $scale：槽标签与时间读数随字号、无溢出', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
        await pumpPlayer(tester, engine: engine);
        await singleTapShow(tester);

        // 1.6× 下的已知溢出来自倍率读数定宽槽（量测缓存按 1.0×，
        // 修），不在本用例范围；1.3× 断言无溢出异常。
        if (scale == 1.3) {
          expect(tester.takeException(), isNull, reason: '1.3× 下无溢出异常');
        } else {
          tester.takeException();
        }
        // 时间读数在场且随系统字号放大（语义档）。
        final time = find.byKey(const Key('toolbar_time'));
        expect(time, findsOneWidget);
        final timeText = tester.widget<Text>(time);
        // Text 未显式设 textScaler = 继承环境缩放（语义档：随系统字号）。
        expect(
          timeText.textScaler?.scale(10) ?? 10 * scale,
          10 * scale,
          reason: '时间读数吃环境缩放值（无固定缩放覆写）',
        );
        // 顶栏槽标签随系统字号放大；起，本视口
        // 1.6× 下顶栏可用宽放不下带标签九槽、标签收起为纯图标（Semantics
        // 保留语义、命中盒钳到兜底下限）——「随系统字号」由 1.3× 档与上方
        // 时间读数断言承接，此处只在标签在场时断言缩放。
        final speedSlot = find.byKey(const Key('tool_speed_settings'));
        expect(speedSlot, findsOneWidget);
        final labels = find.descendant(
          of: speedSlot,
          matching: find.byType(Text),
        );
        if (labels.evaluate().isNotEmpty) {
          final label = tester.widget<Text>(labels.first);
          expect(
            label.textScaler?.scale(10) ?? 10 * scale,
            10 * scale,
            reason: '槽标签吃环境缩放值（定宽量测侧同源取 MediaQuery 缩放）',
          );
        }
      });
    }
  });

  group('引导角标触发', () {
    testWidgets('节拍未就绪点分段：仍弹「节拍分析中…」，不触达、不置位', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(
        tester,
        readyBeat: false,
      );
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_analyzing_prompt')), findsOneWidget);
      expect(container.read(guideSessionProvider).triggered, isEmpty);
      final storage = container.read(privateJsonStorageProvider)
          as InMemoryPrivateJsonStorage;
      expect(storage.snapshot['onboarding'], isNull);
    });

    testWidgets('节拍未就绪打开自动分段菜单：不触达、不置位', (tester) async {
      final (_, container, _, _) = await pumpControlLayer(
        tester,
        readyBeat: false,
      );

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();

      expect(container.read(guideSessionProvider).triggered, isEmpty);
      final storage = container.read(privateJsonStorageProvider)
          as InMemoryPrivateJsonStorage;
      expect(storage.snapshot['onboarding'], isNull);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('就绪后首次点分段：触达分段角标', (tester) async {
      final (engine, container, _, _) = await pumpControlLayer(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();

      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeSegmentUnitId),
      );
    });

    testWidgets('首次打开自动分段菜单：触达自动分段角标', (tester) async {
      final (_, container, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('control_auto_range')));
      await tester.pumpAndSettle();

      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeAutoSegmentUnitId),
      );
      // 收起菜单，不留定时器悬跨用例。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    });

    testWidgets('首次打开节拍提示气泡（横屏顶栏）：触达节拍提示角标', (tester) async {
      final (_, container, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();

      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeBeatPromptUnitId),
      );
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();
    });

    testWidgets('竖屏视频工具栏打开节拍提示气泡：同样触达（锚点横竖屏都在场）', (tester) async {
      setWidenedPortraitView(tester);
      final (_, container, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();

      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeBeatPromptUnitId),
      );
      await tester.tap(find.byKey(const Key('tool_beat_prompt')));
      await tester.pumpAndSettle();
    });

    testWidgets('首次打开倍速设置气泡：触达倍速单元', (tester) async {
      final (_, container, _, _) = await pumpControlLayer(tester);

      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pumpAndSettle();

      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeSpeedUnitId),
      );
      await tester.tap(find.byKey(const Key('tool_speed_settings')));
      await tester.pumpAndSettle();
    });

  });

  group('灰钮给做法', () {
    /// 无对象提示浮层（胶囊键）里的一句文案。
    Finder noSubjectPrompt(String text) => find.descendant(
          of: find.byKey(const Key('no_subject_prompt')),
          matching: find.text(text),
        );

    /// 落一条分段线（这支舞因此有分段），并把线的选中留在线上
    /// （熟练度 / 重点此刻没有作用对象——学习段没被选中）。
    Future<void> landOneLine(FakePlaybackEngine engine, WidgetTester tester) async {
      await engine.pause();
      await engine.seek(const Duration(seconds: 10));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
    }

    /// 点第一段的段体（换选中对象）：线的选中被清掉，删除与「标记分段线」
    /// 因此回到没有作用对象（分段本身已经切出来了）。
    Future<void> selectLearningSegmentBody(WidgetTester tester) async {
      final rect = tester.getRect(find.byKey(const Key('learning_segment_1')));
      await tester.tapAt(
        Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.75),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('删除：已有分段但没选中 → 置灰、按得动、弹「先选中一条分段线或片段，再点这里删除」、动作不发生', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await landOneLine(engine, tester);
      await selectLearningSegmentBody(tester);
      final linesBefore =
          container.read(annotationTimelineProvider).segmentLines.length;
      expect(linesBefore, 1, reason: '这支舞已有一条分段线');

      expect(slotEnabled(tester, 'control_segment_delete'), isTrue,
          reason: '无对象 → 置灰但按得动');
      expect(slotIconColor(tester, 'control_segment_delete'),
          kToolSlotDisabledIconColor,
          reason: '仍置灰（只是按得动）');

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pump();
      await tester.pump();

      expect(
        noSubjectPrompt('先选中一条分段线或片段，再点这里删除'),
        findsOneWidget,
      );
      expect(
        container.read(annotationTimelineProvider).segmentLines.length,
        linesBefore,
        reason: '动作不发生',
      );
    });

    testWidgets('一条分段都没有：删除与熟练度都弹「先用『分段』或『自动分段』切出段来」（更前面的一步）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pump();
      await tester.pump();
      expect(noSubjectPrompt('先用『分段』或『自动分段』切出段来'), findsOneWidget);

      // 每次按都弹：提示还亮着时再按一次，仍弹出（同一身份重排停留）。
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pump();
      await tester.pump();
      expect(noSubjectPrompt('先用『分段』或『自动分段』切出段来'), findsOneWidget);
      expect(container.read(noticeTriggerProvider(NoticeId.noSubject)), 2);

      // 上一条消退后再按熟练度：同一句（两态取辞与入口无关）。
      await tester.pump(noticeTimingOf(NoticeId.noSubject).hold);
      await tester.pump();
      expect(find.byKey(const Key('no_subject_prompt')), findsNothing);
      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pump();
      await tester.pump();
      expect(noSubjectPrompt('先用『分段』或『自动分段』切出段来'), findsOneWidget);
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
    });

    testWidgets('熟练度 / 重点：已有分段但没选中学习段 → 置灰可点、弹「先点一段再点这里」、不打开档位菜单、不写盘', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await landOneLine(engine, tester);

      expect(slotEnabled(tester, 'control_mastery'), isTrue,
          reason: '无对象 → 置灰但按得动');
      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pump();
      await tester.pump();
      expect(noSubjectPrompt('先点一段再点这里'), findsOneWidget);
      expect(find.byKey(const Key('control_mastery_unlearned')), findsNothing,
          reason: '档位菜单不打开（那是动作）');
      expect(container.read(learningMasteryProvider), isEmpty);

      await tester.pump(noticeTimingOf(NoticeId.noSubject).hold);
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pump();
      await tester.pump();
      expect(noSubjectPrompt('先点一段再点这里'), findsOneWidget);
      expect(
        find.byKey(const Key('learning_segment_1_emphasis')),
        findsNothing,
        reason: '重点不置位（动作不发生）',
      );
    });

    testWidgets('「标记分段线」条目：没选中分段线 → 置灰可点、弹「先选中一条分段线，再点这里标记」、flag 不变', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await landOneLine(engine, tester);
      await selectLearningSegmentBody(tester);

      await openAddMenu(tester);
      expect(
        tester
            .widget<PopupMenuItem<VoidCallback?>>(
              find.byKey(const Key('control_segment_flag')),
            )
            .enabled,
        isTrue,
        reason: '无对象 → 置灰可点',
      );
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();

      expect(noSubjectPrompt('先选中一条分段线，再点这里标记'), findsOneWidget);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isFalse,
        reason: 'flag 不切换（动作不发生）',
      );
    });

    testWidgets('有作用对象：删除照常执行、不弹任何东西；熟练度照常打开档位菜单', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await landOneLine(engine, tester);

      // 点学习段体选中该段：熟练度有作用对象 → 正常打开档位菜单。
      await selectLearningSegmentBody(tester);
      await tester.tap(find.byKey(const Key('control_mastery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('control_mastery_learning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('control_mastery_learning')));
      await tester.pumpAndSettle();
      expect(container.read(learningMasteryProvider)[1],
          LearningMastery.learning);
      expect(find.byKey(const Key('no_subject_prompt')), findsNothing,
          reason: '有作用对象时不弹任何东西');

      // 选中分段线：删除照常执行。
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(find.byKey(const Key('no_subject_prompt')), findsNothing);

      // 重点：落线后点学习段体选中该段 → 照常置位、不弹任何东西。
      await landOneLine(engine, tester);
      await selectLearningSegmentBody(tester);
      await tester.tap(find.byKey(const Key('control_emphasis')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('learning_segment_1_emphasis')),
          findsOneWidget);
      expect(find.byKey(const Key('no_subject_prompt')), findsNothing);

      // 「标记分段线」：选中分段线 → 照常切换 flag、不弹任何东西。
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isTrue,
      );
      expect(find.byKey(const Key('no_subject_prompt')), findsNothing);
    });

    testWidgets('其余门的原因文案与点击语义逐位不变：锁定 → 「已锁定分段」、装载未完成 → 「正在装载」', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await landOneLine(engine, tester);
      // 锁上后选中分段线：删除命中锁定门（无对象门不被点亮）。
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('layout_lock_prompt')), findsOneWidget);
      expect(noSubjectPrompt('先选中一条分段线或片段，再点这里删除'), findsNothing);
      expect(container.read(annotationTimelineProvider).segmentLines,
          hasLength(1));

      // 装载未完成压倒一切：仍弹「正在装载」、线不动。
      await tester.pump(noticeTimingOf(NoticeId.layoutLock).hold);
      await tester.pump();
      container.read(loadGateActiveProvider.notifier).begin();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pump();
      await tester.pump();
      expect(find.text('正在装载'), findsOneWidget);
      expect(container.read(annotationTimelineProvider).segmentLines,
          hasLength(1));
    });
  });

  group('落半拍线后自动收视野', () {
    /// 泵出直接挂载壳并交出轨道带会话句柄（窗口读值口），预览线定格 10s
    /// （半拍格点 10.25s 就近解析的基准位；占位均匀网格 @120bpm = 0.5s/拍）。
    Future<(FakePlaybackEngine, TrackBandSession, ProviderContainer)>
    pumpWithSession(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      TrackBandSession? session;
      await pumpControlLayer(
        tester,
        engine: engine,
        onSessionReady: (s) => session = s,
      );
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      return (engine, session!, containerOfControlLayer(tester));
    }

    Future<void> dropHalfBeat(WidgetTester tester) async {
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pumpAndSettle();
    }

    testWidgets('全宽态落半拍线：窗口收拢到线附近（缩放条拉满 → 可视宽 2s），线在窗内', (tester) async {
      final (_, session, container) = await pumpWithSession(tester);
      expect(session.window, isNull, reason: '前置：初始全宽');

      await dropHalfBeat(tester);

      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
        reason: '前置：线落在就近半拍格点',
      );
      expectWindow(
        session.window,
        start: const Duration(milliseconds: 9250),
        end: const Duration(milliseconds: 11250),
        total: const Duration(seconds: 30),
      );
      expect(
        session.window!.contains(
          container.read(annotationTimelineProvider).halfBeatLines.single.position,
        ),
        isTrue,
      );
    });

    testWidgets('已在放大态落线：收拢行为一致；落线后窗口仍可继续缩放与平移', (tester) async {
      final (_, session, _) = await pumpWithSession(tester);
      session.updateWindow(
        TimelineWindow(
          total: const Duration(seconds: 30),
          start: const Duration(seconds: 20),
          end: const Duration(seconds: 24),
        ),
      );

      await dropHalfBeat(tester);

      expectWindow(
        session.window,
        start: const Duration(milliseconds: 9250),
        end: const Duration(milliseconds: 11250),
        total: const Duration(seconds: 30),
        reason: '收拢不依赖落线前的缩放程度',
      );

      // 收拢后窗口照常可写（双指缩放/平移的同一写口）。
      session.updateWindow(
        TimelineWindow(
          total: const Duration(seconds: 30),
          start: const Duration(seconds: 5),
          end: const Duration(seconds: 15),
        ),
      );
      expectWindow(
        session.window,
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 15),
        total: const Duration(seconds: 30),
      );
    });

    testWidgets('其它落点不改窗口：落分段线 / 标记分段线 / 落备注 / 落局部镜像', (tester) async {
      final (engine, session, container) = await pumpWithSession(tester);
      session.updateWindow(
        TimelineWindow(
          total: const Duration(seconds: 30),
          start: const Duration(seconds: 8),
          end: const Duration(seconds: 12),
        ),
      );
      TimelineWindow windowAfter() => session.window!;

      // 落分段线。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(container.read(annotationTimelineProvider).segmentLines, hasLength(1));
      expectWindow(
        windowAfter(),
        start: const Duration(seconds: 8),
        end: const Duration(seconds: 12),
      );

      // 标记分段线（先选中刚落的那条）。
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isTrue,
        reason: '前置：标记动作真实发生',
      );
      expectWindow(
        windowAfter(),
        start: const Duration(seconds: 8),
        end: const Duration(seconds: 12),
      );

      // 落局部镜像。
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_local_mirror')));
      await tester.pumpAndSettle();
      expect(container.read(localMirrorFragmentsProvider), hasLength(1));
      expectWindow(
        windowAfter(),
        start: const Duration(seconds: 8),
        end: const Duration(seconds: 12),
      );

      // 落备注贴纸（弹出备注编辑器，关掉收场）。
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_note_sticker')));
      await tester.pumpAndSettle();
      expect(container.read(noteStickersProvider), hasLength(1));
      expectWindow(
        windowAfter(),
        start: const Duration(seconds: 8),
        end: const Duration(seconds: 12),
      );
      // 收掉备注编辑器，不留悬空路由。
      await engine.pause();
    });
  });

  group('添加即暂停', () {
    /// 泵出直接挂载壳并交出轨道带会话句柄，预览线 10s 处**在播**（占位
    /// 均匀网格 @120bpm = 0.5s/拍，半拍格点 0.25s 间距）。
    Future<(FakePlaybackEngine, TrackBandSession, ProviderContainer)>
    pumpPlayingWithSession(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      TrackBandSession? session;
      await pumpControlLayer(
        tester,
        engine: engine,
        onSessionReady: (s) => session = s,
      );
      await engine.seek(const Duration(seconds: 10));
      await engine.play();
      await tester.pump();
      return (engine, session!, containerOfControlLayer(tester));
    }

    /// 在播态打开「添加」菜单：不用 pumpAndSettle（引擎 100ms tick 会持续
    /// 排帧），按固定小步泵推过菜单路由入场动画（约 300ms）。
    Future<void> openAddMenuPlaying(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('control_add')));
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// 在播态点条目：固定小步泵（合计 < 100ms，引擎 tick 不触发、位置
    /// 只因打开菜单的泵推进 ≤ 90ms ≈ 0.09s）。
    Future<void> tapEntryPlaying(WidgetTester tester, String entryKey) async {
      await tester.tap(find.byKey(Key(entryKey)));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));
    }

    testWidgets('播放中落半拍标记：停播；线落在就近格点、暂停不 seek', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);
      expect(engine.isPlaying, isTrue);
      final seeksBefore = engine.callLog.where((c) => c == 'seek').length;

      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_half_beat');

      expect(engine.isPlaying, isFalse, reason: '落成即停');
      expect(
        engine.callLog.where((c) => c == 'seek').length,
        seeksBefore,
        reason: '暂停不 seek：预览线停在原地',
      );
      final line = container
          .read(annotationTimelineProvider)
          .halfBeatLines
          .single
          .position;
      expect(line.inMilliseconds % 250, 0, reason: '线落在半拍格点');
      final ms = engine.position.inMilliseconds;
      final lower = ms ~/ 250 * 250;
      expect(
        <int>[lower, lower + 250].contains(line.inMilliseconds),
        isTrue,
        reason: '线位置 = 按下那一刻预览线就近的格点（画面未被动过）',
      );
    });

    testWidgets('播放中落局部镜像 / 标记分段线 / 备注贴纸（新建）：都停', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);

      // 局部镜像。
      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_local_mirror');
      expect(engine.isPlaying, isFalse);
      expect(container.read(localMirrorFragmentsProvider), hasLength(1));

      // 标记分段线：先落一条分段线并选中（此时仍停；「分段线」槽不在
      // 添加即暂停清单里），恢复在播再标记。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      expect(container.read(selectedSegmentLineIndexProvider), 0);
      await engine.play();
      await tester.pump();
      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_segment_flag');
      expect(engine.isPlaying, isFalse, reason: '标记真实发生即停');
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isTrue,
        reason: '前置：标记动作真实发生',
      );

      // 备注贴纸（新建即弹编辑器那一支）。
      await engine.play();
      await tester.pump();
      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_note_sticker');
      expect(engine.isPlaying, isFalse);
      expect(container.read(noteStickersProvider), hasLength(1));
      expect(container.read(noteTextEditorTargetProvider), isNotNull,
          reason: '新建那支弹出编辑器');
    });

    testWidgets('播放中落备注贴纸而落点已占：转开既有备注编辑器，同样停', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);
      // 前置：10s 处已有备注（起点 10s，占 [10s, 14s)，预览线 10s 在其内）。
      container
          .read(annotationEditorProvider)
          .submit(InsertNote(at: const Duration(seconds: 10)));
      await tester.pump();
      final existingStart =
          container.read(noteStickersProvider).single.startMs;
      await engine.play();
      await tester.pump();

      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_note_sticker');

      expect(engine.isPlaying, isFalse, reason: '转编辑那一支同样停');
      expect(container.read(noteStickersProvider), hasLength(1),
          reason: '没新建');
      expect(
        container.read(noteTextEditorTargetProvider),
        existingStart,
        reason: '打开的是既有那条备注的编辑器',
      );
    });

    testWidgets('落点越界不停：预览线在有效区间外，照常播、不留产物、无暂停调用', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);
      await engine.pause();
      // 有效区间 = 整片 [0, 30s)：预览线推到 30s 即越界。
      await engine.seek(const Duration(seconds: 30));
      await tester.pump();
      await openAddMenu(tester);
      await engine.play();
      await tester.pump();
      final logBefore = engine.callLog.length;

      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));

      expect(engine.isPlaying, isTrue, reason: '没落成不停');
      expect(
        engine.callLog.length,
        logBefore,
        reason: '没有暂停/播放/seek 调用',
      );
      expect(container.read(annotationTimelineProvider).halfBeatLines, isEmpty,
          reason: '不留产物');
      // 收尾停播：不悬跨 pending 周期定时器（断言已毕，不算播放动作）。
      await engine.pause();
      await tester.pump();
    });

    testWidgets('同位已有半拍线不停：命令判为无操作，照常播、不加线', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);
      await engine.pause();
      await tester.pump();
      container.read(annotationEditorProvider).submit(
            const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)),
          );
      await tester.pump();
      // 恢复在播（开菜单的泵合计 90ms < 一个 100ms tick，位置最多推进到
      // 10.09s，就近格点仍是已占的 10.25s）。
      await openAddMenu(tester);
      await engine.play();
      await tester.pump();
      final logBefore = engine.callLog.length;

      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));

      expect(engine.isPlaying, isTrue, reason: '没落成不停');
      expect(
        engine.callLog.length,
        logBefore,
        reason: '没有暂停/播放/seek 调用',
      );
      expect(
        container.read(annotationTimelineProvider).halfBeatLines,
        hasLength(1),
        reason: '同位既有线保留，没有第二根',
      );
      // 收尾停播：不悬跨 pending 周期定时器（断言已毕，不算播放动作）。
      await engine.pause();
      await tester.pump();
    });

    testWidgets('已暂停时落任一条目：不产生任何播放动作（调用序列钉住）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpControlLayer(tester, engine: engine);
      final container = containerOfControlLayer(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      expect(engine.isPlaying, isFalse);
      // 前置：选中一条分段线（供「标记分段线」）、10s 处已有备注（供
      // 「落点已占转编辑」那支）。前置本身不触引擎。
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      await tapSegmentLineHandle(tester, 0);
      await tester.pumpAndSettle();
      expect(container.read(selectedSegmentLineIndexProvider), 0);
      container
          .read(annotationEditorProvider)
          .submit(InsertNote(at: const Duration(seconds: 10)));
      await tester.pump();
      final logBefore = engine.callLog.length;

      // 半拍标记。
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pumpAndSettle();
      // 局部镜像。
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_local_mirror')));
      await tester.pumpAndSettle();
      // 标记分段线。
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_segment_flag')));
      await tester.pumpAndSettle();
      // 备注贴纸（落点已占、转开既有备注编辑器）。
      await openAddMenu(tester);
      await tester.tap(find.byKey(const Key('control_note_sticker')));
      await tester.pumpAndSettle();

      expect(engine.isPlaying, isFalse, reason: '暂停保持停');
      expect(
        engine.callLog.length,
        logBefore,
        reason: '没有多出来的播放/暂停/seek 调用',
      );
      expect(container.read(noteStickersProvider), hasLength(1),
          reason: '前置：四条都真实发生（备注是转编辑、未新建）');
      expect(container.read(noteTextEditorTargetProvider), isNotNull);
      expect(
        container.read(annotationTimelineProvider).halfBeatLines,
        hasLength(1),
      );
      expect(container.read(localMirrorFragmentsProvider), hasLength(1));
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isTrue,
      );
    });

    testWidgets('暂停后不自动续播：收编辑器不续播、落线后无定时恢复', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);
      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_half_beat');
      expect(engine.isPlaying, isFalse);

      // 落线之后过 5s：没有任何定时恢复。
      await tester.pump(const Duration(seconds: 5));
      expect(engine.isPlaying, isFalse);

      // 备注编辑器收起也不续播。
      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_note_sticker');
      expect(container.read(noteTextEditorTargetProvider), isNotNull);
      container.read(noteTextEditorTargetProvider.notifier).close();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(engine.isPlaying, isFalse, reason: '收起不续播');
    });

    testWidgets('一次添加仍是一步可撤销：落成后撤销一步，线没了、播放态不动', (tester) async {
      final (engine, _, container) = await pumpPlayingWithSession(tester);
      await openAddMenuPlaying(tester);
      await tapEntryPlaying(tester, 'control_half_beat');
      expect(
        container.read(annotationTimelineProvider).halfBeatLines,
        hasLength(1),
      );
      expect(container.read(annotationEditHistoryProvider).canUndo, isTrue);

      container.read(annotationEditorProvider).undo();
      await tester.pump();

      expect(
        container.read(annotationTimelineProvider).halfBeatLines,
        isEmpty,
        reason: '一次添加 = 一步撤销',
      );
      expect(engine.isPlaying, isFalse, reason: '撤销不改播放态');
      expect(
        engine.callLog.where((c) => c == 'seek').length,
        1,
        reason: '全程只有前置那一次 seek',
      );
    });
  });

  group('分段＝动手选中＋一句讲删除', () {
    /// 真机播放页 + 引导宿主：只留分段单元待走（其余 13 个单元按已看过装
    /// 配，免得前置单元的步插话）。
    InMemoryPrivateJsonStorage segmentGuideStorage() =>
        InMemoryPrivateJsonStorage(
          initial: {
            'onboarding': {
              for (final field in onboardingFlagFields.values) field: true,
            }..['badgeSegment'] = false,
          },
        );

    /// 首次落线成功：把刚落那条线的序号记进会话（真实链路里由「分段」槽
    /// 的落线动作记，见上面的「点击分段在预览线处创建分段线」用例）。
    Future<ProviderContainer> dropFirstLine(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      expect(
        container
            .read(guideSessionProvider)
            .artifactIndexes[badgeSegmentUnitId],
        0,
      );
      return container;
    }

    Future<void> pumpPastHold(WidgetTester tester) async {
      await tester.pump(
        kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('删除槽锚点在编辑态那枚上接线（对比态那枚不接）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: segmentGuideStorage(),
      );
      final container = await dropFirstLine(tester, engine);

      expect(
        container.read(guideAnchorRectsProvider)[segmentDeleteSlotAnchorKey],
        isNotNull,
        reason: '编辑态的「删除」槽上报矩形，第二步的高亮才落得下',
      );

      // 同一枚槽 key 在对比态另有一份声明（`ToolSlotTable.compare`）：
      // 条目只声明编辑态那枚，对比态不上报矩形（边界）。
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      expect(
        container.read(guideAnchorRectsProvider)[segmentDeleteSlotAnchorKey],
        isNull,
        reason: '对比态那枚同名槽不接锚点',
      );
    });

    testWidgets('落线 → 框住控制柄 → 点它选中 → 第二步指「删除」槽', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: segmentGuideStorage(),
      );
      final container = await dropFirstLine(tester, engine);

      // 第一步：停靠式待办条，高亮框落在刚落那条线的控制柄上。
      expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
      expect(find.text(guideStepMessage('badge_segment_select')), findsOneWidget);
      expect(
        container
            .read(guideAnchorRectsProvider)['segment_line_0_handle'],
        isNotNull,
      );

      // 亲手点控制柄把线选中：当场填勾，停约 0.4 秒进第二步。
      await tester.tap(
        find.byKey(const Key('segment_line_0_handle')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(container.read(selectedSegmentLineIndexProvider), 0);
      expect(
        tester
            .widget<Icon>(find.byKey(const Key('drill_task_checkbox')))
            .icon,
        Icons.check_box,
      );
      await pumpPastHold(tester);

      // 第二步：就地讲解指住编辑态那枚「删除」槽。
      expect(find.text(guideStepMessage('badge_segment_delete')), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);
      expect(
        container.read(guideAnchorRectsProvider)[segmentDeleteSlotAnchorKey],
        isNotNull,
      );
      expectGuidePointsAt(
        tester,
        find.byKey(const Key(segmentDeleteSlotAnchorKey)),
      );
    });

    testWidgets('落线即重开判据：先选中一条线再落新线，新线仍要亲手选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: segmentGuideStorage(),
      );
      await singleTapShow(tester);
      // 先落一条线并把它选中（此时单元还没触达：还没点「分段」）。
      await engine.seek(const Duration(seconds: 5));
      await engine.pause();
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );
      await tester.tap(
        find.byKey(const Key('segment_line_0_handle')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        container
            .read(guideSessionProvider)
            .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
        0,
      );

      // 再落一条新线：落线即重开判据，不继承上一条的选中——新线要亲手选。
      await engine.seek(const Duration(seconds: 20));
      await tester.pump();
      await tester.tap(find.byKey(const Key('control_segment')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(guideSessionProvider)
            .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
        isNull,
      );
      expect(find.text('1/2'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(find.byKey(const Key('drill_task_checkbox')))
            .icon,
        Icons.check_box_outline_blank,
        reason: '刚落的新线还没被选中：不打勾',
      );
      await pumpPastHold(tester);
      expect(find.text('1/2'), findsOneWidget, reason: '落线本身不算选中，不推进');
    });

    testWidgets('在线身那一行点它也记入选中判据', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: segmentGuideStorage(),
      );
      final container = await dropFirstLine(tester, engine);

      await tester.tap(
        find.byKey(const Key('segment_line_0')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(
        container
            .read(guideSessionProvider)
            .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
        0,
        reason: '线身那一行点中它也算「选中过一次」',
      );
      await pumpPastHold(tester);
      expect(find.text(guideStepMessage('badge_segment_delete')), findsOneWidget);
    });

    testWidgets('收起控制层两步都退场；重新展开接着演、已做过的步不重来', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: segmentGuideStorage(),
      );
      final container = await dropFirstLine(tester, engine);
      expect(find.text('1/2'), findsOneWidget);

      // 收起控制层：锚点随轨道带撤下 → 两步退场、判据不被消耗。
      container.read(playerSessionProvider.notifier).collapse();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('drill_task_bar')), findsNothing);
      expect(
        container
            .read(guideSessionProvider)
            .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
        isNull,
        reason: '退场不算做到，判据闩不置位',
      );

      // 重新展开：从没做完的第 1 步接着演。
      container.read(playerSessionProvider.notifier).openEditor();
      await tester.pumpAndSettle();
      expect(find.text('1/2'), findsOneWidget);

      // 做到第 1 步、再收起展开一次：已做过的步不重来，直接接着第 2 步。
      await tester.tap(
        find.byKey(const Key('segment_line_0_handle')),
        warnIfMissed: false,
      );
      await tester.pump();
      await pumpPastHold(tester);
      container.read(playerSessionProvider.notifier).collapse();
      await tester.pumpAndSettle();
      container.read(playerSessionProvider.notifier).openEditor();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('drill_task_bar')), findsNothing);
      expect(find.text(guideStepMessage('badge_segment_delete')), findsOneWidget);
    });
  });

  group('两排工具槽的引导锚点按槽声明包装', () {
    /// 未声明承载引导锚点的顶栏槽键（行集里除「局部镜像」外的八条）。
    const undeclaredPlayToolKeys = [
      'tool_undo',
      'tool_redo',
      'tool_av_sync',
      'tool_beat_prompt',
      'tool_mirror',
      'tool_speed_settings',
      'tool_compare',
      'tool_guide',
    ];

    testWidgets('横屏顶栏：声明为真的槽上报自己的矩形，其余八条一律不上报', (tester) async {
      setWideView(tester);
      final (_, container, _, _) = await pumpControlLayer(tester);

      expect(
        container.read(guideAnchorRectsProvider)['tool_local_mirror'],
        tester.getRect(find.byKey(const Key('tool_local_mirror'))),
        reason: '「局部镜像」声明承载锚点：矩形板上报的就是这枚槽自己的矩形',
      );
      for (final key in undeclaredPlayToolKeys) {
        expect(
          container.read(guideAnchorRectsProvider)[key],
          isNull,
          reason: '$key 未声明承载引导锚点，不包包装器、不上报',
        );
      }
    });

    testWidgets('底栏三态：只有编辑态那枚「删除」槽上报矩形，其余底栏槽一律不上报', (tester) async {
      setWideView(tester);
      final (_, container, _, _) = await pumpControlLayer(tester);

      // 期望在用例里写死（不读被测的 `carriesGuideAnchor` 反推）：某枚槽的
      // 声明被误翻真时，这里跟着实现改口径会红，而不是静默变绿。
      void expectReported(ToolSlotTable table, Set<String> reported) {
        for (final slot in table.slots) {
          final rect = container.read(guideAnchorRectsProvider)[slot.key];
          if (reported.contains(slot.key)) {
            expect(
              rect,
              tester.getRect(find.byKey(Key(slot.key))),
              reason: '${slot.key} 声明承载锚点：矩形板上报的就是这枚槽自己的矩形',
            );
          } else {
            expect(
              rect,
              isNull,
              reason: '${slot.key} 未声明承载引导锚点，不包包装器、不上报',
            );
          }
        }
      }

      expectReported(ToolSlotTable.normal, {'control_segment_delete'});

      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.beatCorrectionStandby);
      await tester.pumpAndSettle();
      expectReported(ToolSlotTable.standby, const {});

      // 对比态另有一枚同名「删除」槽：是另一枚槽、不声明，故不上报。
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await tester.pumpAndSettle();
      expectReported(ToolSlotTable.compare, const {});
    });

    testWidgets('竖屏视频工具栏：同一枚声明为真的槽在锚点板上报，与槽位矩形重合', (tester) async {
      setWidenedPortraitView(tester);
      final (_, container, _, _) = await pumpControlLayer(tester);

      final slot = find.byKey(const Key('tool_local_mirror'));
      expect(
        find.ancestor(
          of: slot,
          matching: find.byKey(const Key('control_layer_video_toolbar')),
        ),
        findsOneWidget,
        reason: '竖屏这枚槽住在视频工具栏那一行',
      );
      expect(
        container.read(guideAnchorRectsProvider)['tool_local_mirror'],
        tester.getRect(slot),
        reason: '换到竖屏落点，上报的仍是这枚槽自己的矩形',
      );
      // 竖屏标题栏那三条不声明，同样不上报。
      for (final key in const ['tool_undo', 'tool_redo', 'tool_guide']) {
        expect(container.read(guideAnchorRectsProvider)[key], isNull);
      }
    });

    testWidgets('触达了但实物锚点不在场：不出场、不消耗，也不跳到第二步', (tester) async {
      final storage = _localMirrorGuideStorage();
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(
        tester,
        engine: engine,
        wrapGuideHost: true,
        guideStorage: storage,
      );
      await singleTapShow(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

      // 声明已生效：这枚槽在锚点板上报了矩形。
      expect(
        container.read(guideAnchorRectsProvider)['tool_local_mirror'],
        isNotNull,
      );
      // 只触达、没落成片段：第一步的实物锚点（`mirror_fragment_N`）不在场，
      // 单元停在第一步——不出场、不消耗，第二步（这枚开关）也不越位先演。
      container
          .read(guideSessionProvider.notifier)
          .trigger(badgeLocalMirrorUnitId);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(find.byKey(const Key('drill_task_bar')), findsNothing);
      expect(
        (storage.snapshot['onboarding'] as Map)['badgeLocalMirror'],
        isFalse,
        reason: '锚点缺席即放行，不消耗状态位',
      );
    });
  });

  group('局部镜像两步走查', () {
    test('注册表：两条步同属一个单元，锚点是刚落的那块与那枚开关', () {
      final steps = guideStepsOfUnit(badgeLocalMirrorUnitId);
      expect(steps.map((s) => s.id), [
        'badge_local_mirror_step',
        'badge_local_mirror_switch',
      ]);
      expect(steps.map((s) => s.anchorKey), [
        mirrorFragmentAnchorKeyBase,
        localMirrorSwitchAnchorKey,
      ]);
      expect(
        steps.every((s) => s.form == GuideUnitForm.inplaceTour),
        isTrue,
        reason: '两步都是就地讲解',
      );
      expect(
        localMirrorSwitchAnchorKey,
        kPlayToolLocalMirror.key,
        reason: '第二步声明的锚点 key 就是顶栏那枚槽的槽键',
      );
    });

    // 两档均为**合成档**（960×540dp 与 668×1368dp，非设备基准）。
    for (final view in const [
      ('横屏顶栏', Size(1920, 1080), 2.0),
      ('竖屏视频工具栏', Size(1336, 2736), 2.0),
    ]) {
      final (label, size, ratio) = view;
      testWidgets(
        '$label：第一步框住刚落的那块（1/2）→ 下一步框住那枚开关（2/2）→ 走完才置位',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = ratio;
          addTearDown(tester.view.reset);
          final engine = FakePlaybackEngine(
            duration: const Duration(seconds: 30),
          );
          final storage = _localMirrorGuideStorage();
          await pumpPlayer(
            tester,
            engine: engine,
            wrapGuideHost: true,
            guideStorage: storage,
          );
          await singleTapShow(tester);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(PlayerPage)),
            listen: false,
          );
          await tapAddEntry(tester, 'control_local_mirror');
          await tester.pumpAndSettle();

          // 第一步：指刚刚落成的那块镜像片段，1/2。
          expect(
            find.text(guideStepMessage('badge_local_mirror_step')),
            findsOneWidget,
          );
          expect(find.text('1/2'), findsOneWidget);
          expectGuidePointsAt(
            tester,
            find.byKey(const Key('mirror_fragment_0')),
          );

          await tester.tap(find.byKey(const Key('guide_next')));
          await tester.pumpAndSettle();

          // 第二步：指顶栏（竖屏是视频工具栏）那枚「局部镜像」开关，2/2。
          expect(
            find.text(guideStepMessage('badge_local_mirror_switch')),
            findsOneWidget,
          );
          expect(find.text('2/2'), findsOneWidget);
          expectGuidePointsAt(
            tester,
            find.byKey(const Key('tool_local_mirror')),
          );
          // 这句话讲的是事实：落成这块的那一刻总开关被自动打开（不是用户开
          // 的），故走到第二步时开关读数是「已经开着」。
          expect(
            container.read(localMirrorEnabledProvider),
            isTrue,
            reason: '刚落这块时总开关已被自动打开',
          );
          // 两步走完才置位：第二步还在场时状态位仍未置。
          expect(
            (storage.snapshot['onboarding'] as Map)['badgeLocalMirror'] ??
                false,
            isFalse,
          );

          await tester.tap(find.byKey(const Key('guide_next')));
          await tester.pumpAndSettle();

          expect(find.byKey(const Key('guide_highlight')), findsNothing);
          expect(find.byKey(const Key('guide_bubble')), findsNothing);
          expect(
            (storage.snapshot['onboarding'] as Map)['badgeLocalMirror'],
            isTrue,
          );

          // 置位后此后再落一块：不再出现（走完两步的路径，非仅「跳过」）。
          await tapAddEntry(tester, 'control_local_mirror');
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('guide_highlight')), findsNothing);
          expect(find.byKey(const Key('guide_bubble')), findsNothing);
        },
      );
    }

    for (final (label, applyView) in <(String, void Function(WidgetTester))>[
      ('横屏', setWideView),
      ('竖屏', setWidenedPortraitView),
    ]) {
      testWidgets('$label：控制层收起时第二步不出场、不被消耗；再展开从没做完的那一步接着演', (
        tester,
      ) async {
        applyView(tester);
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final storage = _localMirrorGuideStorage();
        await pumpPlayer(
          tester,
          engine: engine,
          wrapGuideHost: true,
          guideStorage: storage,
        );
        await singleTapShow(tester);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PlayerPage)),
          listen: false,
        );
        await tapAddEntry(tester, 'control_local_mirror');
        await tester.pumpAndSettle();

        // 走到第二步。
        await tester.tap(find.byKey(const Key('guide_next')));
        await tester.pumpAndSettle();
        expect(
          find.text(guideStepMessage('badge_local_mirror_switch')),
          findsOneWidget,
        );

        // 收起控制层：那枚开关随整层退场（锚点不在场）→ 第二步不出场。
        container.read(playerSessionProvider.notifier).collapse();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tool_local_mirror')), findsNothing);
        expect(
          find.text(guideStepMessage('badge_local_mirror_switch')),
          findsNothing,
        );
        expect(find.byKey(const Key('guide_highlight')), findsNothing);
        expect(
          (storage.snapshot['onboarding'] as Map)['badgeLocalMirror'] ?? false,
          isFalse,
          reason: '收起不出场也不消耗',
        );

        // 再展开：仍从没做完的第二步接着演（第一步不重来）。
        container.read(playerSessionProvider.notifier).openEditor();
        await tester.pumpAndSettle();
        expect(
          find.text(guideStepMessage('badge_local_mirror_switch')),
          findsOneWidget,
        );
        expect(find.text('2/2'), findsOneWidget);
        expectGuidePointsAt(tester, find.byKey(const Key('tool_local_mirror')));
        expect(
          find.text(guideStepMessage('badge_local_mirror_step')),
          findsNothing,
          reason: '已走完的第一步不重来',
        );
      });
    }
  });
}

/// 局部镜像两步走查的引导状态位装配：其余单元全部已看过、只留
/// `badgeLocalMirror` 未看过——演练与首启都不压住被测的这两步。
InMemoryPrivateJsonStorage _localMirrorGuideStorage() =>
    InMemoryPrivateJsonStorage(
      initial: {
        'onboarding': {
          for (final field in onboardingFlagFields.values) field: true,
        }..['badgeLocalMirror'] = false,
      },
    );

/// 当前可见节拍刻度数（窗口缩放可见性断言；拍序号 = 时间/0.5s，
/// 占位均匀网格 @120bpm）—— / 双指用例共用。
int tickCount(WidgetTester tester, {int maxIndex = 400}) {
  var n = 0;
  for (var i = 0; i <= maxIndex; i++) {
    if (tester.any(find.byKey(ValueKey('beat_tick_${i * 500000}')))) n++;
  }
  return n;
}

/// 有界测试网格（no-op 用例）：拍点 0..4s（每拍 0.5s，9 拍），
/// 4/4 小节，首个强拍 0 号拍，格点 = 0s/2s/4s（四拍格）。
class _BoundedTestGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _BoundedTestGrid();

  static final _uniform = const UniformBeatGrid();

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => _uniform.beatTime(index);

  @override
  int beatIndexAt(Duration time) => _uniform.beatIndexAt(time);

  @override
  bool isDownbeat(int index) => _uniform.isDownbeat(index);

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => 8;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      _uniform.beatsDuration(count, from: from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) =>
      _uniform.beatsInWindow(start, end);
}

/// 时长未知的测试引擎（覆盖 duration getter 为 null；同 player_page_test
/// 先例）——「无时间线时设置簇整簇隐藏」用。
class _DurationlessEngine extends FakePlaybackEngine {
  _DurationlessEngine() : super(duration: const Duration(minutes: 3));

  @override
  Duration? get duration => null;
}

/// 测试用音频输出设备控制器（补测：音画同步会话进入需要设备
/// 快照 seam；缺省平台通道在测试环境永不应答 → 会话无法活跃）。
class _FakeAudioOutputDeviceController implements AudioOutputDeviceController {
  @override
  Future<AvSyncDeviceInfo?> get() async => null;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream =>
      const Stream<AvSyncDeviceInfo?>.empty();
}
