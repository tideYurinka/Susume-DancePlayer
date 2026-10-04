import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_loop_providers.dart';
import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider, videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        activeLoopRangeProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        learningEmphasisProvider,
        learningMasteryProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/open_session.dart';
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show DelayedLoopBeats, delayedLoopProvider;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show screenBrightnessControllerProvider;
import 'package:dance_learning_app/player/open_restore.dart'
    show OpenLoadHost, VideoOpenRestorer, videoOpenRestorerProvider;
import 'package:dance_learning_app/player/framing_session_state.dart'
    show framingStateProvider;
import 'package:dance_learning_app/player/preview_snap.dart'
    show previewSnapEnabledProvider;
import 'package:dance_learning_app/player/scheme_open.dart'
    show MemberSchemeOpen;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 抛错哈希（哈希计算失败的兜底路径用）。
class ThrowingHasher implements ContentHasher {
  const ThrowingHasher();

  @override
  Future<String> hashFile(File file) async => throw StateError('hash failed');
}

/// 带写盘计数的按视频文档存储（打开恢复不得触发多余写盘断言用）。
class CountingVideoDocumentStorage implements VideoDocumentStorage {
  CountingVideoDocumentStorage(this._inner);

  final InMemoryVideoDocumentStorage _inner;

  int markersWrites = 0;
  int localWrites = 0;

  Map<String, dynamic> get markersSnapshot => _inner.markersSnapshot;
  Map<String, dynamic> get localSnapshot => _inner.localSnapshot;

  @override
  Future<Map<String, dynamic>> loadMarkers() => _inner.loadMarkers();

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() =>
      _inner.loadMarkersOrNull();

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) async {
    markersWrites++;
    await _inner.saveMarkers(json);
  }

  @override
  Future<void> delete() => _inner.delete();

  @override
  Future<Map<String, dynamic>> loadLocal() => _inner.loadLocal();

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() => _inner.loadLocalOrNull();

  @override
  Future<void> saveLocal(Map<String, dynamic> json) async {
    localWrites++;
    await _inner.saveLocal(json);
  }

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    var wrote = false;
    await _inner.mutateMarkers((json, {required bool present}) async {
      final before = jsonEncode(json);
      await apply(json, present: present);
      wrote = jsonEncode(json) != before;
    });
    if (wrote) markersWrites++;
  }

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    var wrote = false;
    await _inner.mutateLocal((json, {required bool present}) async {
      final before = jsonEncode(json);
      await apply(json, present: present);
      wrote = jsonEncode(json) != before;
    });
    if (wrote) localWrites++;
  }
}

const String kVideoId = 'hash-1';
const String kFilePath = '/videos/a.mp4';
const Duration kDuration = Duration(minutes: 3);

VideoIndexEntry entryFor({
  String videoId = kVideoId,
  String filePath = kFilePath,
  SongSignature? signatureCache,
  bool mirrored = false,
  bool localMirrorEnabled = true,
}) {
  return VideoIndexEntry(
    videoId: videoId,
    displayName: filePath.split('/').last,
    filePath: filePath,
    sizeBytes: 1,
    fastKey: '1:a.mp4',
    mirrored: mirrored,
    mirrorAsked: true,
    localMirrorEnabled: localMirrorEnabled,
    lastOpenedAt: DateTime(2026, 9, 1),
    signatureCache: signatureCache,
  );
}

/// 命中场景的 markers 文档：首尾即整片、1 条带 flag 分段线、段 1 重点。
///
/// [withBeat] 为 true 时附带已有节拍段（无 beat 会触发后台分析并
/// 在完成时自动分段——恢复语义用例需带 beat 才不被自动分段改写）。
Map<String, dynamic> markersJson({
  List<Map<String, dynamic>> lines = const [
    {'timeMs': 60000, 'flag': true},
  ],
  List<int> emphasized = const [1],
  List<Map<String, dynamic>> localMirrorFragments = const [],
  bool? localMirrorEnabled,
  SongSignature? signature,
  bool mirrored = false,
  Map<String, dynamic>? metaFramingSelection,
  bool withBeat = false,
  List<int> anchors = const [],
  int rangeEndMs = 180000,
  List<Map<String, dynamic>> notes = const [],
}) => {
  'version': 9,
  'meta': {
    'mirrored': mirrored,
    'localMirrorEnabled': ?localMirrorEnabled,
    if (signature != null) 'signature': signature.toJson(),
    'framingSelection': ?metaFramingSelection,
  },
  if (withBeat)
    'beat': {
      'model': 'madmom_downbeat_rnn_full.onnx',
      'fps': 100,
      'generatedAt': '2026-09-01T00:00:00.000Z',
      'beats': [
        {'t': 0.5, 'down': true},
        {'t': 1.0, 'down': false},
        {'t': 1.5, 'down': false},
        {'t': 2.0, 'down': false},
      ],
    },
  // 写回时 corrections 段由编解码重新装配、shift 键恒在（端到端
  // 用例按落盘形断言段不被触碰，fixture 直接写成归一形）。
  if (withBeat && anchors.isNotEmpty)
    'corrections': {'shift': 0.0, 'anchors': anchors},
  if (notes.isNotEmpty) 'notes': {'notes': notes},
  'annotations': {
    'range': {'startMs': 0, 'endMs': rangeEndMs},
    'segmentLines': lines,
    'emphasizedSegments': emphasized,
    if (localMirrorFragments.isNotEmpty)
      'localMirrorFragments': localMirrorFragments,
  },
};

/// 命中场景的 local 文档：段 1 熟练度/激活（session）、吸附关、锁定分段
/// （prefs）；delayedLoopBeats 为历史残留键。
Map<String, dynamic> localJson({
  Map<String, String> mastery = const {'1': 'practicing'},
  List<int> activated = const [1],
}) => {
  'version': 3,
  'session': {'mastery': mastery, 'activatedSegments': activated},
  'prefs': {
    'previewSnapEnabled': false,
    'delayedLoopBeats': 8,
    'layoutLocked': true,
  },
};

class Probe {
  Probe({
    required this.container,
    required this.engine,
    required this.docStorage,
    required this.indexStorage,
    required this.hasher,
  });

  final ProviderContainer container;
  final FakePlaybackEngine engine;
  final CountingVideoDocumentStorage docStorage;
  final InMemoryVideoIndexStorage indexStorage;
  final ContentHasher hasher;

  VideoOpenRestorer get restorer => container.read(videoOpenRestorerProvider);

  /// 装配并建立打开会话（宿主装配点），返回会话本身。
  Future<OpenSession> establish({String filePath = kFilePath}) async {
    final session = OpenSession(
      filePath: filePath,
      indexStore: indexStorage,
      hasher: hasher,
      coordinatorFor: (videoId) =>
          container.read(videoDocumentCoordinatorProvider(videoId)),
    );
    await session.establish();
    return session;
  }

  /// 建立会话 + 走打开恢复（播放页 [_restoreForVideo] 的等价接线）。
  Future<void> open({
    String filePath = kFilePath,
    Duration videoDuration = kDuration,
  }) async {
    final session = await establish(filePath: filePath);
    await restorer.resolve(session: session, videoDuration: videoDuration);
  }
}

Probe makeProbe({
  VideoIndex? index,
  required ContentHasher hasher,
  Map<String, dynamic> markers = const {},
  Map<String, dynamic> local = const {},
  FakeBeatPipeline? pipeline,
  VideoDocumentStorage Function(String videoId)? storageFor,
  MemberSchemeStorage? memberSchemeStorage,
}) {
  final docStorage = CountingVideoDocumentStorage(
    InMemoryVideoDocumentStorage(markers: markers, local: local),
  );
  final documentStorage = storageFor ?? (String videoId) => docStorage;
  final indexStorage = InMemoryVideoIndexStorage(
    initial: index ?? VideoIndex(entries: [entryFor()]),
  );
  final engine = FakePlaybackEngine(duration: kDuration);
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      videoIndexStoreProvider.overrideWithValue(indexStorage),
      contentHasherProvider.overrideWithValue(hasher),
      videoDocumentStorageFactoryProvider.overrideWithValue(documentStorage),
      // 节拍分析注入 fake：本文件用例不消费节拍，避免真实管线启动。
      beatAnalysisPipelineProvider.overrideWithValue(
        pipeline ?? FakeBeatPipeline(),
      ),
      if (memberSchemeStorage != null)
        memberSchemeStorageProvider.overrideWith(
          (ref, videoId) => memberSchemeStorage,
        ),
    ],
  );
  // 容器内无 widget 监听，保持恢复目标 provider 存活（等价播放页的
  // listenManual 接线；Riverpod 3 默认无监听即销毁）。
  container.listen(annotationTimelineProvider, (_, _) {});
  container.listen(learningMasteryProvider, (_, _) {});
  container.listen(learningEmphasisProvider, (_, _) {});
  container.listen(selectedLearningSegmentsProvider, (_, _) {});
  container.listen(localMirrorFragmentsProvider, (_, _) {});
  container.listen(noteStickersProvider, (_, _) {});
  container.listen(activeLoopRangeProvider, (_, _) {});
  container.listen(previewSnapEnabledProvider, (_, _) {});
  container.listen(delayedLoopProvider, (_, _) {});
  container.listen(layoutLockedProvider, (_, _) {});
  container.listen(framingStateProvider, (_, _) {});
  addTearDown(container.dispose);
  return Probe(
    container: container,
    engine: engine,
    docStorage: docStorage,
    indexStorage: indexStorage,
    hasher: hasher,
  );
}

void main() {
  test('续播恢复越界：记录位置 > 自定义尾线 → 钳回尾线续播', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex(entries: [entryFor().copyWith(lastPositionMs: 150000)]),
      markers: markersJson(rangeEndMs: 120000),
    );
    await probe.open();

    // 钳回尾线（2 分钟），并按「位置超头部阈值」弹「从头播放？」小卡。
    expect(probe.engine.seekCalls, [const Duration(seconds: 120)]);
  });

  test('续播恢复在尾线内：不钳制、按记录位置续播', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex(entries: [entryFor().copyWith(lastPositionMs: 60000)]),
      markers: markersJson(rangeEndMs: 120000),
    );
    await probe.open();

    expect(probe.engine.seekCalls, [const Duration(seconds: 60)]);
  });

  test('哈希一致：markers + local 全量恢复，不 seek、循环作用域就位、保存接缝接通', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(),
      local: localJson(),
    );
    await probe.open();

    // 标注恢复：分段线（含 flag）/首尾/重点/熟练度。
    final timeline = probe.container.read(annotationTimelineProvider);
    expect(timeline.videoDuration, kDuration);
    expect(timeline.rangeStart, Duration.zero);
    expect(timeline.rangeEnd, kDuration);
    expect(timeline.segmentLines.length, 1);
    expect(timeline.segmentLines.first.position, const Duration(seconds: 60));
    expect(timeline.segmentLines.first.flagged, isTrue);
    expect(probe.container.read(learningEmphasisProvider), {1});
    expect(probe.container.read(learningMasteryProvider), {
      1: LearningMastery.learning,
    });

    // 激活恢复：集合就位、循环作用域就位，但不 seek、不自动播放。
    expect(probe.container.read(selectedLearningSegmentsProvider), {1});
    expect(probe.container.read(activeLoopRangeProvider), isNotNull);
    expect(probe.engine.seekCalls, isEmpty);
    expect(probe.engine.isPlaying, isFalse);
    expect(probe.engine.position, Duration.zero);

    // 设置恢复：预览吸附/锁定分段（吸附网格偏好已删除；循环前导为设备级，
    // 不再随舞恢复）。
    expect(probe.container.read(previewSnapEnabledProvider), isFalse);
    expect(probe.container.read(delayedLoopProvider), DelayedLoopBeats.four);
    expect(probe.container.read(layoutLockedProvider), isTrue);

    // 保存接缝接通；打开恢复本身不写盘。
    expect(probe.container.read(annotationSaveSinkProvider), isNotNull);
    expect(probe.docStorage.markersWrites, 0);
    expect(probe.docStorage.localWrites, 0);
  });

  test('段序越界属性丢弃不崩溃：熟练度/重点/激活只保留界内段序', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(emphasized: [0, 1, 9]),
      local: localJson(
        mastery: const {'0': 'unlearned', '1': 'practicing', '9': 'mastered'},
        activated: const [0, 1, 9],
      ),
    );
    await probe.open();

    expect(probe.container.read(learningEmphasisProvider), {0, 1});
    expect(probe.container.read(learningMasteryProvider), {
      0: LearningMastery.unlearned,
      1: LearningMastery.learning,
    });
    expect(probe.container.read(selectedLearningSegmentsProvider), {0, 1});
    expect(probe.engine.seekCalls, isEmpty);
  });

  test('打开恢复把 markers.localMirrorFragments 水合进会话 store', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(
        localMirrorFragments: const [
          {'startMs': 1000, 'endMs': 3000},
          {'startMs': 5000, 'endMs': 9000, 'enabled': false},
        ],
      ),
    );
    await probe.open();

    expect(probe.container.read(localMirrorFragmentsProvider), const [
      LocalMirrorFragment(startMs: 1000, endMs: 3000),
      LocalMirrorFragment(startMs: 5000, endMs: 9000),
    ]);
  });

  test('markers 无 localMirrorFragments 键 → 水合为空、不报错', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(localMirrorFragments: const []),
    );
    await probe.open();
    expect(probe.container.read(localMirrorFragmentsProvider), isEmpty);
  });

  test('打开恢复把 markers.notes 段水合进备注会话 store（全字段逐位一致）', () async {
    const noteJson = {
      'startMs': 8000,
      'endMs': 16000,
      'text': '这里注意手',
      'style': {'color': 4278255360, 'outline': false},
      'locked': true,
      'geometry': {'centerX': 0.4, 'centerY': 0.2, 'scale': 1.5},
      'refs': [],
    };
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(notes: const [noteJson]),
    );
    await probe.open();

    expect(probe.container.read(noteStickersProvider), const [
      NoteSticker(
        startMs: 8000,
        endMs: 16000,
        text: '这里注意手',
        locked: true,
        geometry: NoteGeometry(centerX: 0.4, centerY: 0.2, scale: 1.5),
      ),
    ]);
  });

  test('markers 缺 notes 段 → 备注贴纸为空、不崩', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(),
    );
    await probe.open();
    expect(probe.container.read(noteStickersProvider), isEmpty);
  });

  test('端到端：插入备注贴纸 → 落盘 → 重开 → 备注贴纸仍在且字段逐位一致；beat/corrections 不被触碰', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(withBeat: true, anchors: const [7]),
    );
    await probe.open();
    final beatBefore = probe.docStorage.markersSnapshot['beat'];
    final correctionsBefore = probe.docStorage.markersSnapshot['corrections'];

    // 首次会话内插入一条备注贴纸（网格未就绪：落点直通），经保存链落盘。
    final container = probe.container;
    final outcome = container
        .read(annotationEditorProvider)
        .submit(const InsertNote(at: Duration(milliseconds: 10300)));
    expect(outcome.applied, isTrue);
    final inserted = container.read(noteStickersProvider).single;
    await container.read(annotationSaveSinkProvider)!.flush();
    expect(probe.docStorage.markersWrites, 1);

    // 重开：同一存储、重新走打开恢复（恢复前清先清空备注贴纸 lane）。
    await probe.open();

    expect(container.read(noteStickersProvider), [
      inserted,
    ], reason: '重开后备注贴纸仍在且字段逐位一致（NoteSticker 相等覆盖全部字段）');
    // 备注贴纸编辑不触碰 beat / corrections 段（与并发写者不互相覆盖）。
    expect(probe.docStorage.markersSnapshot['beat'], beatBefore);
    expect(probe.docStorage.markersSnapshot['corrections'], correctionsBefore);
  });

  test('打开恢复不写总开关值道——唯一写者是镜像控制器（避免两处写的次序依赖）', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(localMirrorEnabled: false),
    );
    await probe.open();
    // 单写者：标记文件里的现值由 MirrorController.resolve 读出并
    // 写值道（三条读取路径见 mirror_test，页面级闭环见 control_layer_test
    // 「杀进程重开」用例）。打开恢复若也写，取值就成了「谁后跑谁赢」。
    expect(probe.container.read(localMirrorEnabledProvider), isTrue);
  });

  test('标注编辑的保存/撤销/重做不改变总开关取值', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex(entries: [entryFor(localMirrorEnabled: false)]),
      markers: markersJson(localMirrorEnabled: false),
      // 分析失败：异常态不触发自动分段，本用例只验证保存链。
      pipeline: FakeBeatPipeline(error: '无有效音轨'),
    );
    await probe.open();
    final editor = probe.container.read(annotationEditorProvider);

    // 一次编辑 → 撤销 → 重做：三个提交点都经保存链落盘 markers。
    expect(
      editor.submit(const AddSegmentLine(at: Duration(seconds: 30))).applied,
      isTrue,
    );
    editor.undo();
    editor.redo();
    // burst 合并窗口（300ms）到期落盘。
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final markers = marker_doc.MarkersDocument.fromJson(
      probe.docStorage.markersSnapshot,
    );
    expect(
      markers.localMirrorEnabled,
      isFalse,
      reason: '标注编辑的保存/撤销/重做不冲掉总开关现值',
    );
  });

  test('打开恢复的保存接缝首建初值带总开关过渡值（标注编辑不冲掉用户选择）', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex(entries: [entryFor(localMirrorEnabled: false)]),
      // 分析失败：异常态不触发自动分段，本用例只验证首建立底。
      pipeline: FakeBeatPipeline(error: '无有效音轨'),
    );
    await probe.open();

    final outcome = probe.container
        .read(annotationEditorProvider)
        .submit(const AddSegmentLine(at: Duration(seconds: 30)));
    expect(outcome.applied, isTrue);

    // burst 合并窗口（300ms）到期落盘。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final markers = probe.docStorage.markersSnapshot;
    expect(
      markers['meta']['localMirrorEnabled'],
      isFalse,
      reason: 'markers 首建以 index 过渡值立底，标注保存不把总开关冲成开',
    );
  });

  test('markers 缺 localMirrorEnabled 键 → 总开关兜底 true', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(),
    );
    await probe.open();
    expect(probe.container.read(localMirrorEnabledProvider), isTrue);
  });

  test('markers/local 缺失：空态可用、保存接缝接通、不回写 index', () async {
    final initial = VideoIndex(entries: [entryFor()]);
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: initial,
    );
    await probe.open();

    expect(probe.container.read(previewSnapEnabledProvider), isTrue);
    expect(probe.container.read(delayedLoopProvider), DelayedLoopBeats.four);
    expect(probe.container.read(layoutLockedProvider), isFalse);
    expect(probe.container.read(selectedLearningSegmentsProvider), isEmpty);
    expect(probe.container.read(annotationSaveSinkProvider), isNotNull);
    // markers 不存在：不以空态回写 index 缓存。
    expect(identical(probe.indexStorage.current, initial), isTrue);
  });

  test('markers 缺失而 local 有值：设置照常恢复，段序挂靠属性按空态', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      local: localJson(),
    );
    await probe.open();

    // 熟练度/激活按段序挂靠，几何真值在 markers：markers 缺失时无从
    // 挂靠，宁丢不挂错段；无几何依赖的设置照常恢复。
    expect(probe.container.read(learningMasteryProvider), isEmpty);
    expect(probe.container.read(selectedLearningSegmentsProvider), isEmpty);
    expect(probe.container.read(layoutLockedProvider), isTrue);
    // 循环前导不再来自 local 文档（设备级）。
    expect(probe.container.read(delayedLoopProvider), DelayedLoopBeats.four);
  });

  test('内容哈希不一致：按新视频处理（不载旧标注、旧条目/旧文件保留、身份取摘要）', () async {
    // 旧条目（hash-old）的文档与新内容（different-content）的文档分属两个文件。
    final oldStorage = CountingVideoDocumentStorage(
      InMemoryVideoDocumentStorage(markers: markersJson(), local: localJson()),
    );
    final newStorage = CountingVideoDocumentStorage(
      InMemoryVideoDocumentStorage(),
    );
    final probe = makeProbe(
      hasher: const FixedHasher('different-content'),
      index: VideoIndex(entries: [entryFor(videoId: 'hash-old')]),
      storageFor: (videoId) => videoId == 'hash-old' ? oldStorage : newStorage,
    );
    await probe.open();

    final timeline = probe.container.read(annotationTimelineProvider);
    expect(timeline.segmentLines, isEmpty);
    expect(probe.container.read(selectedLearningSegmentsProvider), isEmpty);
    expect(probe.container.read(layoutLockedProvider), isFalse);
    expect(
      probe.container.read(annotationSaveSinkProvider),
      isNotNull,
      reason: '按新视频语义仍可落盘（身份取摘要）',
    );
    // 旧条目保留、旧文件不被读也不被写。
    expect(probe.indexStorage.current.findById('hash-old'), isNotNull);
    expect(oldStorage.markersSnapshot, markersJson());
    expect(oldStorage.localSnapshot, localJson());
    expect(oldStorage.markersWrites, 0);
    expect(oldStorage.localWrites, 0);
    expect(newStorage.markersWrites, 0);
  });

  test('内容哈希计算失败：按新视频处理，不载旧标注', () async {
    final probe = makeProbe(
      hasher: const ThrowingHasher(),
      markers: markersJson(),
      local: localJson(),
    );
    await probe.open();

    expect(
      probe.container.read(annotationTimelineProvider).segmentLines,
      isEmpty,
    );
    expect(probe.container.read(annotationSaveSinkProvider), isNull);
  });

  test('索引无条目（条目尚未落盘）：空态但照常接通保存——身份取内容摘要', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex.empty,
    );
    await probe.open();

    expect(
      probe.container.read(annotationTimelineProvider).segmentLines,
      isEmpty,
    );
    expect(
      probe.container.read(annotationSaveSinkProvider),
      isNotNull,
      reason: '「无条目 ⇒ 不接保存编排」这条语义已删除',
    );
    expect(probe.docStorage.markersWrites, 0, reason: '恢复本身不写盘');
  });

  test('端到端：刚导入就打开（索引无条目）→ 标注落盘 → 重开后仍在', () async {
    final probeA = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex.empty,
      // 分析失败：异常态不触发自动分段，本用例只验证标注落盘。
      pipeline: FakeBeatPipeline(error: '无有效音轨'),
    );
    await probeA.open();

    // 刚导入就打开：无索引条目，身份取内容摘要，标注经会话协调器落盘。
    final outcome = probeA.container
        .read(annotationEditorProvider)
        .submit(const AddSegmentLine(at: Duration(seconds: 30)));
    expect(outcome.applied, isTrue);
    await probeA.container.read(annotationSaveSinkProvider)!.flush();
    expect(probeA.docStorage.markersWrites, 1);
    final persisted = probeA.docStorage.markersSnapshot;
    expect(persisted['annotations']['segmentLines'], hasLength(1));

    // 重开：同一内容身份寻址到同一份文档；索引仍无条目。
    final probeB = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex.empty,
      markers: persisted,
      pipeline: FakeBeatPipeline(error: '无有效音轨'),
    );
    await probeB.open();

    final timeline = probeB.container.read(annotationTimelineProvider);
    expect(timeline.segmentLines, hasLength(1));
    expect(
      timeline.segmentLines.single.position,
      const Duration(seconds: 30),
      reason: '无索引条目时打开的标注落盘后重开仍在',
    );
  });

  test('markers 存在：以其署名/镜像回写 index 缓存', () async {
    const signature = SongSignature(
      dancer: '阿如',
      song: 'My Love',
      remark: '9人版',
    );
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex(entries: [entryFor()]),
      markers: markersJson(signature: signature, mirrored: true),
    );
    await probe.open();

    final entry = probe.indexStorage.current.findById(kVideoId);
    expect(entry?.signatureCache, signature);
    expect(entry?.mirrored, isTrue);
    expect(entry?.mirrorAsked, isTrue);
  });

  test('index 缓存已与 markers 一致：不因恢复触发写盘', () async {
    const signature = SongSignature(song: 'My Love');
    final initial = VideoIndex(
      entries: [entryFor(signatureCache: signature, mirrored: true)],
    );
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: initial,
      markers: markersJson(signature: signature, mirrored: true),
    );
    await probe.open();

    expect(identical(probe.indexStorage.current, initial), isTrue);
  });

  test('index 回写在串行链内重读当前条目，不覆盖建立后到回写的并发字段', () async {
    const signature = SongSignature(song: 'My Love');
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(signature: signature, mirrored: true),
    );
    // 建立会话（读入条目快照）后、恢复回写前，同条目被并发写（镜像询问 /
    // 续播位置记录）；回写只改署名与镜像，不得把并发字段退回旧快照。
    final session = await probe.establish();
    await probe.indexStorage.update((index) {
      final entry = index.findById(kVideoId)!;
      return index.replaceEntry(
        entry.copyWith(
          mirrored: false,
          mirrorAsked: false,
          lastPositionMs: 99000,
        ),
      );
    });

    await probe.restorer.resolve(session: session, videoDuration: kDuration);

    final entry = probe.indexStorage.current.findById(kVideoId)!;
    expect(entry.signatureCache, signature, reason: 'markers 为真值：署名回写');
    expect(entry.mirrored, isTrue, reason: 'markers 为真值：镜像回写');
    expect(entry.lastPositionMs, 99000, reason: '回写不回退并发写入的续播位置');
    expect(entry.mirrorAsked, isFalse, reason: '回写不覆盖并发写入的询问标记');
  });

  test('恢复后编辑提交即时保存：markers 不存在时以 index 署名/镜像为初值首建', () async {
    const signature = SongSignature(song: 'My Love');
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      index: VideoIndex(entries: [entryFor(signatureCache: signature)]),
      // 分析失败：异常态不触发自动分段，本用例只验证首建立底。
      pipeline: FakeBeatPipeline(error: '无有效音轨'),
    );
    await probe.open();

    final outcome = probe.container
        .read(annotationEditorProvider)
        .submit(const AddSegmentLine(at: Duration(seconds: 30)));
    expect(outcome.applied, isTrue);

    // burst 合并窗口（300ms）到期落盘。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final markers = probe.docStorage.markersSnapshot;
    expect(
      markers['version'],
      marker_doc.MarkersDocument.versionPolicy.currentVersion,
    );
    expect(markers['meta']['signature'], signature.toJson());
    expect(markers['meta']['mirrored'], isFalse);
    expect((markers['annotations']['segmentLines'] as List).length, 1);
  });

  testWidgets('播放页打开命中条目：恢复标注与激活，不自动跳转 seek', (tester) async {
    final engine = FakePlaybackEngine(duration: kDuration);
    final docStorage = CountingVideoDocumentStorage(
      InMemoryVideoDocumentStorage(
        markers: markersJson(withBeat: true),
        local: localJson(),
      ),
    );
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [entryFor()]),
    );
    late final ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          contentHasherProvider.overrideWithValue(const FixedHasher(kVideoId)),
          videoDocumentStorageFactoryProvider.overrideWithValue((videoId) {
            return docStorage;
          }),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
        ],
        child: MaterialApp(home: PlayerPage(source: Uri.file(kFilePath))),
      ),
    );
    await tester.pumpAndSettle();

    // 恢复就位：标注与激活来自 markers/local。
    final element = tester.element(find.byType(PlayerPage));
    container = ProviderScope.containerOf(element);
    expect(container.read(annotationTimelineProvider).segmentLines.length, 1);
    expect(container.read(selectedLearningSegmentsProvider), {1});
    expect(container.read(activeLoopRangeProvider), isNotNull);
    // 恢复不自动跳转：除打开即播放外，无任何 seek，进度停在视频首。
    expect(engine.seekCalls, isEmpty);
    // 循环作用域就位：播放自然进入激活范围才循环（循环层已启用）。
    expect(container.read(playbackLoopLayerProvider).enabled, isTrue);
  });

  // ── 端到端收口：建 → 落盘 → 重开恢复 → 删除 单链直测 ──
  //
  // 与单段 seam 测试（纯函数、storage 往返、hydration）不同，本条
  // 把「经模块 verb 建片段 → 编排器落盘 markers → 杀进程重开经 open-restorer
  // 恢复进会话 store → 再删除落盘」串成一条可演示路径，证明整链无需 UI 也能
  // 端到端走通。容器 seam（无 widget 宿主）即真值源；每个 probe 各自持有内存
  // 文档存储，把上一会话落盘的 markers 快照作为「文件内容」喂给下一会话，以
  // 模拟进程重启后重读同一文件。
  test('端到端：建→落盘→杀进程重开恢复→删除 经 editor/编排器/open-restorer 单链', () async {
    // ── 会话一：打开命中（markers 已有首尾/分段线，非空态）→ 经模块 verb 建片段。
    final probeA = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(),
    );
    await probeA.open();
    final create = probeA.container
        .read(annotationEditorProvider)
        .submit(const AddLocalMirrorFragment(at: Duration(seconds: 10)));
    expect(create.applied, isTrue, reason: '建片段 verb 生效');
    expect(probeA.container.read(localMirrorFragmentsProvider), hasLength(1));
    // 调整：整体平移片段到另一段（轨上「调整」leg 的模块落点），随后一并落盘。
    final moved = probeA.container
        .read(annotationEditorProvider)
        .submit(
          const MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 30)),
        );
    expect(moved.applied, isTrue, reason: '整体移 verb 生效');
    final created = probeA.container.read(localMirrorFragmentsProvider).single;

    // ── 落盘：flush 编排器把片段写进 markers 文件。
    await probeA.container.read(annotationSaveSinkProvider)?.flush();
    final persistedSnapshot = probeA.docStorage.markersSnapshot;
    expect(
      marker_doc.MarkersDocument.fromJson(persistedSnapshot)
          .localMirrorFragments,
      [created],
      reason: '片段随编排器落盘到 markers typed 字段',
    );

    // ── 会话二（杀进程重开同文件内容）：open-restorer 恢复片段进会话 store。
    final probeB = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: persistedSnapshot,
    );
    await probeB.open();
    expect(probeB.container.read(localMirrorFragmentsProvider), [
      created,
    ], reason: '重开恢复：值 + 启停位 + 平移后几何逐位保真');

    // ── 会话三：删除片段 → 落盘 → 恢复侧不再带旧片段。
    final remove = probeB.container
        .read(annotationEditorProvider)
        .submit(const RemoveLocalMirrorFragment(index: 0));
    expect(remove.applied, isTrue, reason: '删除片段 verb 生效');
    await probeB.container.read(annotationSaveSinkProvider)?.flush();
    expect(
      marker_doc.MarkersDocument.fromJson(probeB.docStorage.markersSnapshot)
          .localMirrorFragments,
      isEmpty,
      reason: '删除落盘后 markers 不再含片段',
    );
  });

  test('换视频/新视频打开清零八拍矫正待命态，锚点数据不丢（退出路径）', () async {
    const String otherPath = '/videos/b.mp4';
    final probe = makeProbe(
      // 真正的「换视频」：索引里另有 b.mp4，本次打开的是它。
      index: VideoIndex(
        entries: [
          entryFor(),
          entryFor(filePath: otherPath),
        ],
      ),
      hasher: const FixedHasher(kVideoId),
      // b.mp4 的公开 markers beat 段带一个八拍锚点（拍序号 0 = 强拍）。
      markers: markersJson(withBeat: true, anchors: const [0]),
    );
    probe.container
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.beatCorrectionStandby);
    expect(
      probe.container.read(playerSessionProvider).isBeatCorrectionStandby,
      isTrue,
    );

    await probe.open(filePath: otherPath);

    expect(
      probe.container.read(playerSessionProvider).isBeatCorrectionStandby,
      isFalse,
      reason: '换视频/新视频打开不把上一首的待命态带过来',
    );
    expect(probe.container.read(beatTrackStateProvider).grid?.anchors, [
      0,
    ], reason: '锚点随公开 markers 的 beat 段恢复：待命态清零不等于数据丢');
  });

  group('启动序列折进打开恢复的 open 入口', () {
    test('open 驱动宿主各域会话：同一已确认身份、命名按新导入场景', () async {
      final probe = makeProbe(
        hasher: const FixedHasher(kVideoId),
        markers: markersJson(withBeat: true),
      );
      final host = _RecordingOpenLoadHost();

      await probe.restorer.open(
        source: Uri.file(kFilePath),
        videoDuration: kDuration,
        askNaming: true,
        host: host,
      );

      // 各宿主会话拿到的都是同一已确认身份。
      for (final session in [
        host.settingsSession,
        host.signatureSession,
        host.mirrorSession,
      ]) {
        expect(session, isNotNull, reason: '各域会话都被启动');
        expect(session!.videoId, kVideoId);
        expect(session.identified, isTrue);
      }
      expect(host.namingIsNewImport, isTrue, reason: '首次导入场景照实传给命名框');

      // 确有先后依赖的步骤对：统计先于署名、署名落定先于交给统计域、
      // 命名先于镜像（两个模态不叠置）。
      expect(
        host.indexOf('startStats'),
        lessThan(host.indexOf('startSignature')),
      );
      expect(
        host.indexOf('startSignature'),
        lessThan(host.indexOf('syncStatsVideoContext')),
      );
      expect(
        host.indexOf('promptNaming'),
        lessThan(host.indexOf('resolveMirror')),
      );
      // resolve 后台进行（不阻塞 open 返回）：排空它在途链再收尾容器。
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    test('open 建立的身份按内容摘要落定：非首次导入照常传给下游会话', () async {
      final probe = makeProbe(
        hasher: const FixedHasher(kVideoId),
        markers: markersJson(withBeat: true),
      );
      final host = _RecordingOpenLoadHost();

      await probe.restorer.open(
        source: Uri.file(kFilePath),
        videoDuration: kDuration,
        askNaming: false,
        host: host,
      );

      expect(host.namingIsNewImport, isFalse, reason: '非首次导入场景照实传给命名框');
      expect(host.signatureSession?.videoId, kVideoId);
      expect(host.signatureSession?.identified, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });

  test('取景随公开标记文件就位：打开这支舞即恢复那块选区，且零写盘', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(
        metaFramingSelection: {
          'left': 0.2,
          'top': 0.2,
          'right': 0.6,
          'bottom': 0.7,
        },
      ),
    );
    final before = probe.docStorage.markersSnapshot;
    await probe.open();

    expect(
      probe.container.read(framingStateProvider).source,
      const FramingSelection(left: 0.2, top: 0.2, right: 0.6, bottom: 0.7),
      reason: '取景随公开标记文件装载行就位',
    );
    expect(
      probe.docStorage.markersWrites,
      0,
      reason: '打开恢复的装载不产生落盘（与用户改动共用同一写入口）',
    );
    expect(probe.docStorage.markersSnapshot, before, reason: '盘上原文一字未动');
  });

  test('含旧取景字段的 v8 文件：打开为未调过，且打开动作不写公开标记文件', () async {
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: {
        'version': 8,
        'meta': {
          'framingBand': {'top': 0.2, 'bottom': 0.7, 'centerX': 0.45},
        },
      },
    );
    await probe.open();

    expect(
      probe.container.read(framingStateProvider).source,
      isNull,
      reason: '旧取景字段被迁移丢掉 = 复位',
    );
    expect(probe.docStorage.markersWrites, 0, reason: '打开动作不写公开标记文件');
    expect(
      probe.docStorage.markersSnapshot['version'],
      8,
      reason: '迁移只在下一次写回生效',
    );
    expect(
      (probe.docStorage.markersSnapshot['meta'] as Map)['framingBand'],
      isNotNull,
      reason: '打开不写盘，旧字段原文仍在',
    );
  });

  test('组员方案装载：方案里的取景生效', () async {
    final schemes = InMemoryMemberSchemeStorage();
    await MemberSchemeStore(schemes).upsert(
      MemberSchemeRecord(
        schemeId: 's1',
        memberName: '小如',
        schemeName: '真值名',
        importedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        markers: {
          'version': 9,
          'meta': {
            'framingSelection': {
              'left': 0.1,
              'top': 0.2,
              'right': 0.6,
              'bottom': 0.9,
            },
          },
        },
      ),
    );
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      markers: markersJson(
        metaFramingSelection: {
          'left': 0.3,
          'top': 0.3,
          'right': 0.8,
          'bottom': 0.8,
        },
      ),
      memberSchemeStorage: schemes,
    );
    final session = await probe.establish();
    await probe.restorer.resolve(
      session: session,
      videoDuration: kDuration,
      scheme: const MemberSchemeOpen('s1'),
    );

    expect(
      probe.container.read(framingStateProvider).source,
      const FramingSelection(left: 0.1, top: 0.2, right: 0.6, bottom: 0.9),
      reason: '方案里的构图生效，不用我自己的文件',
    );
  });

  test('容器销毁后恢复链不再读已销毁的 ref：在途成员方案读盘丢弃', () async {
    final gate = Completer<void>();
    final probe = makeProbe(
      hasher: const FixedHasher(kVideoId),
      memberSchemeStorage: _GatedMemberSchemeStorage(gate.future),
    );
    final session = await probe.establish();

    // 恢复链起跑即停在成员方案读盘上；此刻销毁容器（等价测试拆场：树与容器
    // 先于在途链退场），再放闸让读盘完成。
    final restore = probe.restorer.resolve(
      session: session,
      videoDuration: kDuration,
    );
    probe.container.dispose();
    gate.complete();

    await restore;
  });
}

/// 记录调用次序的打开装载宿主（接缝验证件）。
class _RecordingOpenLoadHost implements OpenLoadHost {
  final List<String> calls = <String>[];
  OpenSession? settingsSession;
  OpenSession? signatureSession;
  OpenSession? mirrorSession;
  bool? namingIsNewImport;

  int indexOf(String call) => calls.indexOf(call);

  @override
  bool isMounted() {
    calls.add('isMounted');
    return true;
  }

  @override
  Future<void> openSettings(OpenSession session) async {
    calls.add('openSettings');
    settingsSession = session;
  }

  @override
  void startStats() {
    calls.add('startStats');
  }

  @override
  Future<void> startSignature(OpenSession session) async {
    calls.add('startSignature');
    signatureSession = session;
  }

  @override
  void syncStatsVideoContext() {
    calls.add('syncStatsVideoContext');
  }

  @override
  Future<void> promptNaming({required bool isNewImport}) async {
    calls.add('promptNaming');
    namingIsNewImport = isNewImport;
  }

  @override
  Future<void> resolveMirror(OpenSession session) async {
    calls.add('resolveMirror');
    mirrorSession = session;
  }
}

/// 闸控成员方案存储：整份读挂在 [gate] 上，用来把恢复链停在读盘那一步。
class _GatedMemberSchemeStorage extends InMemoryMemberSchemeStorage {
  _GatedMemberSchemeStorage(this.gate);

  final Future<void> gate;

  @override
  Future<Map<String, dynamic>> load() async {
    await gate;
    return super.load();
  }
}
