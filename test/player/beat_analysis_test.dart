import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart'
    show LearningMastery;
import 'package:dance_learning_app/beat/beat_pipeline.dart'
    show BeatAnalysisCancelled, BeatAnalysisPipeline, BeatAnalysisRequest;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackPhase,
        BeatTrackState,
        beatGridProvider,
        beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveSeed;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc
    show BeatGrid, BeatPoint;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider, videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider, beatAnalysisRunnerProvider;
import 'package:dance_learning_app/player/beat_prompt_panel.dart'
    show beatPromptEnabledProvider;
import 'package:dance_learning_app/player/metronome_sound.dart'
    show metronomeSoundEnabledProvider;
import 'package:dance_learning_app/player/open_restore.dart'
    show VideoOpenRestorer, videoOpenRestorerProvider;
import 'package:dance_learning_app/player/open_session.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show VideoSettingsPersistence;
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show
        DelayedLoopBeats,
        delayedLoopProvider,
        delayedLoopWaitProvider,
        prepBeatsProvider;
import 'package:dance_learning_app/player/song_loudness.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/poll.dart';

/// 响度测量桩：记录探测并拒绝测量（不触达 ffmpeg）。
class _NoopLoudnessProbe implements SongLoudnessProbe {
  final List<String> probed = [];

  @override
  Future<double> pcmRms(String videoPath) async {
    probed.add(videoPath);
    throw StateError('no probe in this test');
  }
}

/// 定值响度测量桩。
class _FixedLoudnessProbe implements SongLoudnessProbe {
  _FixedLoudnessProbe(this.rms);

  final double rms;
  final List<String> probed = [];

  @override
  Future<double> pcmRms(String videoPath) async {
    probed.add(videoPath);
    return rms;
  }
}

/// 固定值哈希（内容哈希校验桩，open_restore_test 先例）。
class FixedHasher implements ContentHasher {
  const FixedHasher(this.value);

  final String value;

  @override
  Future<String> hashFile(File file) async => value;
}

const String kVideoId = 'hash-1';
const String kFilePath = '/videos/a.mp4';
const Duration kDuration = Duration(minutes: 3);

/// markers.beat 段（已有节拍的打开恢复场景）。
Map<String, dynamic> beatJson() => {
  'model': 'madmom_downbeat_rnn_full.onnx',
  'fps': 100,
  'generatedAt': '2026-09-01T00:00:00.000Z',
  'beats': [
    {'t': 0.5, 'down': true},
    {'t': 1.0, 'down': false},
    {'t': 1.5, 'down': false},
    {'t': 2.0, 'down': false},
  ],
};

class BeatProbe {
  BeatProbe({
    required this.container,
    required this.pipeline,
    required this.docStorage,
  });

  final ProviderContainer container;
  final FakeBeatPipeline pipeline;
  final InMemoryVideoDocumentStorage docStorage;

  VideoOpenRestorer get restorer => container.read(videoOpenRestorerProvider);

  BeatTrackState get trackState => container.read(beatTrackStateProvider);

  /// 偏好恢复会话（自动置开的「记忆已读到」经真实恢复缝
  /// 落定——打开时读 local 文档并按身份落「已读到」标记）。
  VideoSettingsPersistence? settings;

  /// 最近一次落盘写入完成（记忆置开写盘的断言同步点）。
  Future<void> flushSettings() async => settings?.flush;

  OpenSession? _lastSession;

  /// 竞态用例补跑偏好恢复（模拟「记忆恢复晚于分析落定」）。
  Future<void> restoreSettings() async {
    await settings!.openFor(_lastSession!);
  }

  /// 装配并建立打开会话（宿主装配点）+ 走打开恢复。[withSettings] =
  /// 是否在恢复前走偏好恢复（竞态用例置 false：分析先落定、记忆后读）。
  Future<void> open({bool withSettings = true}) async {
    final session = OpenSession(
      filePath: kFilePath,
      indexStore: container.read(videoIndexStoreProvider),
      hasher: container.read(contentHasherProvider),
      coordinatorFor: (videoId) =>
          container.read(videoDocumentCoordinatorProvider(videoId)),
    );
    await session.establish();
    _lastSession = session;
    // 换会话前等旧会话在途落盘完成（手交棒同步点）：旧会话的写是
    // 即发即忘，不等会让新会话读到未落定的旧值。
    await settings?.flush;
    settings?.dispose();
    settings = VideoSettingsPersistence(container);
    if (withSettings) {
      await settings!.openFor(session);
    }
    await restorer.resolve(session: session, videoDuration: kDuration);
  }

  /// 等待在途分析收尾（fake 管线微任务完成 + 写回/置态）。
  Future<void> settle() async {
    await pipeline.settled;
    await pollUntil(
      () => trackState.phase != BeatTrackPhase.placeholder,
      reason: '分析未收尾',
    );
  }
}

BeatProbe makeProbe({
  Map<String, dynamic> markers = const {},
  Map<String, dynamic> local = const {},
  FakeBeatPipeline? pipeline,
  SongLoudnessProbe? loudnessProbe,
  InMemoryPrivateJsonStorage? privateStorage,
}) {
  final docStorage = InMemoryVideoDocumentStorage(
    markers: markers,
    local: local,
  );
  final indexStorage = InMemoryVideoIndexStorage(
    initial: VideoIndex(
      entries: [
        VideoIndexEntry(
          videoId: kVideoId,
          displayName: 'a.mp4',
          filePath: kFilePath,
          sizeBytes: 1,
          fastKey: '1:a.mp4',
          mirrored: false,
          mirrorAsked: true,
          lastOpenedAt: DateTime(2026, 9, 1),
        ),
      ],
    ),
  );
  final fakePipeline = pipeline ?? FakeBeatPipeline();
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(
        FakePlaybackEngine(duration: kDuration),
      ),
      videoIndexStoreProvider.overrideWithValue(indexStorage),
      contentHasherProvider.overrideWithValue(const FixedHasher(kVideoId)),
      videoDocumentStorageFactoryProvider.overrideWithValue((videoId) {
        return docStorage;
      }),
      beatAnalysisPipelineProvider.overrideWithValue(fakePipeline),
      // 响度测量桩：默认拒绝探测，保持既有用例确定性。
      songLoudnessProbeProvider.overrideWithValue(
        loudnessProbe ?? _NoopLoudnessProbe(),
      ),
      privateJsonStorageProvider.overrideWithValue(
        privateStorage ?? InMemoryPrivateJsonStorage(),
      ),
    ],
  );
  container.listen(beatTrackStateProvider, (_, _) {});
  container.listen(beatGridProvider, (_, _) {});
  container.listen(delayedLoopProvider, (_, _) {});
  // 会话响度基准保活（unawaited 补测异步写回，容器需持监听）。
  container.listen(songLoudnessBaselineProvider, (_, _) {});
  addTearDown(container.dispose);
  return BeatProbe(
    container: container,
    pipeline: fakePipeline,
    docStorage: docStorage,
  );
}

void main() {
  test('打开无网格视频：后台分析一次，完成写 markers.beat（含溯源）并切真实网格', () async {
    final probe = makeProbe();
    await probe.open();
    expect(probe.pipeline.calls, 1);
    expect(probe.pipeline.paths, [kFilePath]);
    expect(probe.trackState.phase, BeatTrackPhase.placeholder);
    await probe.settle();

    // 轨/吸附切真实网格：三态就绪 + beatGridProvider 为文档网格。
    expect(probe.trackState.phase, BeatTrackPhase.ready);
    final grid = probe.container.read(beatGridProvider);
    expect(grid.beatTime(0), const Duration(milliseconds: 500));
    expect(grid.isDownbeat(0), isTrue);

    // markers.beat 原子写回：溯源字段（model/fps/generatedAt）+ 拍点。
    final beat = marker_doc.BeatGrid.fromJson(
      probe.docStorage.markersSnapshot['beat'] as Map<String, dynamic>,
    );
    expect(beat.model, 'assets/models/madmom_downbeat_rnn_full.onnx');
    expect(beat.fps, 100);
    expect(beat.generatedAt.isAfter(DateTime(2026, 1, 1)), isTrue);
    expect(beat.beats.length, 4);
    expect(beat.beats.first.down, isTrue);
  });

  test('已有 beat：打开直接消费，零重复分析', () async {
    final probe = makeProbe(markers: {'version': 8, 'beat': beatJson()});
    await probe.open();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(probe.pipeline.calls, 0);
    expect(probe.trackState.phase, BeatTrackPhase.ready);
    final grid = probe.container.read(beatGridProvider);
    expect(grid.beatTime(3), const Duration(seconds: 2));
    // 打开恢复本身不写盘（beat 原样保留）。
    expect(probe.docStorage.markersSnapshot['beat'], beatJson());
  });

  test('v6 旧文件读入即空态：打开走「无 beat」路径、触发一次后台分析（版本门）', () async {
    final probe = makeProbe(markers: {'version': 6, 'beat': beatJson()});
    await probe.open();
    expect(probe.pipeline.calls, 1, reason: '旧版本文件整份丢弃 ⇒ 无 beat ⇒ 后台分析一次');
    await probe.settle();
    expect(probe.trackState.phase, BeatTrackPhase.ready);
  });

  test('分析完成自动分段一次：首尾 = 网格首末拍、一次可撤销编辑', () async {
    final probe = makeProbe();
    await probe.open();
    await probe.settle();

    final timeline = probe.container.read(annotationTimelineProvider);
    expect(
      timeline.rangeStart,
      const Duration(milliseconds: 500),
      reason: '自动首尾：首 = 网格首拍',
    );
    expect(
      timeline.rangeEnd,
      const Duration(seconds: 2),
      reason: '自动首尾：尾 = 网格末拍',
    );
    // 4 拍不足 32 拍：无切点（整段一段收在尾线）。
    expect(timeline.segmentLines, isEmpty);

    // 整动作一次入史：一步撤销回到整片范围。
    expect(probe.container.read(annotationEditHistoryProvider).canUndo, isTrue);
    probe.container.read(annotationEditorProvider).undo();
    final restored = probe.container.read(annotationTimelineProvider);
    expect(restored.rangeStart, Duration.zero);
    expect(restored.rangeEnd, kDuration);
  });

  test('分析完成自动分段：既有逐段熟练度/重点按时间重叠重写，不重置为缺省', () async {
    // 64 拍 @500ms（= 32s 网格）：4 个八拍/段 ⇒ 16.5s 一条切割线。
    final probe = makeProbe(
      pipeline: FakeBeatPipeline(
        result: [
          for (var i = 0; i < 64; i++)
            marker_doc.BeatPoint(t: 0.5 * (i + 1), down: i % 4 == 0),
        ],
      ),
      markers: const {
        'version': 8,
        'annotations': {
          'range': {'startMs': 0, 'endMs': 180000},
          'segmentLines': [
            {'timeMs': 8000},
            {'timeMs': 20000},
          ],
          'emphasizedSegments': [0, 2],
        },
      },
      local: const {
        'version': 3,
        'session': {
          'mastery': {'0': 'learning', '1': 'mastered', '2': 'familiar'},
        },
      },
    );
    await probe.open();
    await probe.settle();

    // 分析完成 → 自动分段把旧三段 [0,8)/[8,20)/[20,180) 换成新两段
    // [0.5,16.5)/[16.5,32)：新段熟练度取相交旧段最高档、重点取并集，
    // 既有逐段数据不因这一次自动分段丢失。
    final timeline = probe.container.read(annotationTimelineProvider);
    expect(timeline.rangeStart, const Duration(milliseconds: 500));
    expect(timeline.rangeEnd, const Duration(seconds: 32));
    expect(
      timeline.segmentLines.single.position,
      const Duration(milliseconds: 16500),
    );
    expect(probe.container.read(learningMasteryProvider), {
      0: LearningMastery.mastered,
      1: LearningMastery.mastered,
    });
    expect(probe.container.read(learningEmphasisProvider), {0, 1});

    // Seam C：两条写缝各落各段——熟练度写本地私密文档 session、
    // 重点写公开标记文档 annotations。
    await probe.container.read(annotationSaveSinkProvider)!.flush();
    expect((probe.docStorage.localSnapshot['session'] as Map)['mastery'], {
      '0': 'mastered',
      '1': 'mastered',
    });
    expect(
      (probe.docStorage.markersSnapshot['annotations']
          as Map)['emphasizedSegments'],
      [0, 1],
    );
  });

  test('已有 beat 打开恢复：不重放自动分段', () async {
    final probe = makeProbe(markers: {'version': 8, 'beat': beatJson()});
    await probe.open();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(
      probe.container.read(annotationEditHistoryProvider).canUndo,
      isFalse,
      reason: '打开恢复不重放自动分段，撤销史为空',
    );
    expect(
      probe.container.read(annotationTimelineProvider).rangeStart,
      Duration.zero,
    );
  });

  test('分析失败：异常态（吸附停用、延迟循环秒制兜底），markers 不写，下次打开重试', () async {
    final probe = makeProbe(pipeline: FakeBeatPipeline(error: '无有效音轨'));
    await probe.open();
    // 打开恢复把延迟循环复位 4 档（设置复位先于 local 恢复）；重选 8 档
    // 以断言异常态秒制兜底的档位换算。
    probe.container.read(prepBeatsProvider.notifier).setLoopLead(8);
    await probe.settle();

    // 异常态：无网格语义（首尾/半拍吸附自由）、延迟循环 8 档 = 8 秒。
    expect(probe.trackState.phase, BeatTrackPhase.error);
    expect(
      probe.container.read(delayedLoopWaitProvider),
      const Duration(seconds: 8),
    );
    // 秒制兜底仅是派生换算：用户延迟循环档位原值不动（8 档）。
    expect(probe.container.read(delayedLoopProvider), DelayedLoopBeats.eight);
    // 兜底秒值不落盘：markers 与 local 均无 beat 相关写入。
    expect(probe.docStorage.markersSnapshot.containsKey('beat'), isFalse);
    expect(probe.docStorage.localSnapshot.containsKey('beat'), isFalse);

    // 异常态本会话保持：等待后不自动重试（calls 仍 1）。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(probe.pipeline.calls, 1);

    // 下次打开自动重试（markers 仍无 beat）。
    await probe.open();
    expect(probe.pipeline.calls, 2);
  });

  test('分析中离开页面（取消）：不写半截、不置异常；下次打开自动重试', () async {
    final probe = makeProbe(
      pipeline: FakeBeatPipeline(hangUntilCancelled: true),
    );
    await probe.open();
    await pollUntil(() => probe.pipeline.calls == 1, reason: '分析未启动');

    // 离开页面语义：取消在途分析。
    probe.container.read(beatAnalysisRunnerProvider).cancel();
    await probe.pipeline.settled;

    expect(probe.docStorage.markersSnapshot.containsKey('beat'), isFalse);
    expect(probe.trackState.phase, BeatTrackPhase.placeholder);

    // 下次打开重试（fake 换成功路径）。
    probe.pipeline.hangUntilCancelled = false;
    await probe.open();
    await probe.settle();
    expect(probe.pipeline.calls, 2);
    expect(probe.trackState.phase, BeatTrackPhase.ready);
    expect(probe.docStorage.markersSnapshot.containsKey('beat'), isTrue);
  });

  test('打开新视频取消上一在途分析：一次只分析一个、不排队', () async {
    final probe = makeProbe(
      pipeline: FakeBeatPipeline(hangUntilCancelled: true),
    );
    await probe.open();
    await pollUntil(() => probe.pipeline.calls == 1, reason: '分析未启动');

    // 同一运行器再次启动（新视频打开路径）：旧代际作废。
    await probe.open();
    await pollUntil(() => probe.pipeline.calls == 2, reason: '新分析未启动');
    probe.pipeline.hangUntilCancelled = false;
    await probe.settle();

    expect(probe.trackState.phase, BeatTrackPhase.ready);
    expect(probe.docStorage.markersSnapshot.containsKey('beat'), isTrue);
  });

  test('节拍写回是 markers 首建时机：出生即带 index 署名/镜像初值', () async {
    const signature = SongSignature(song: 'My Love');
    final docStorage = InMemoryVideoDocumentStorage();
    final indexStorage = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          VideoIndexEntry(
            videoId: kVideoId,
            displayName: 'a.mp4',
            filePath: kFilePath,
            sizeBytes: 1,
            fastKey: '1:a.mp4',
            mirrored: true,
            mirrorAsked: true,
            lastOpenedAt: DateTime(2026, 9, 1),
            signatureCache: signature,
          ),
        ],
      ),
    );
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: kDuration),
        ),
        videoIndexStoreProvider.overrideWithValue(indexStorage),
        contentHasherProvider.overrideWithValue(const FixedHasher(kVideoId)),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (_) => docStorage,
        ),
        beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
      ],
    );
    container.listen(beatTrackStateProvider, (_, _) {});
    container.listen(beatGridProvider, (_, _) {});
    addTearDown(container.dispose);

    final session = OpenSession(
      filePath: kFilePath,
      indexStore: container.read(videoIndexStoreProvider),
      hasher: container.read(contentHasherProvider),
      coordinatorFor: (videoId) =>
          container.read(videoDocumentCoordinatorProvider(videoId)),
    );
    await session.establish();
    await container
        .read(videoOpenRestorerProvider)
        .resolve(session: session, videoDuration: kDuration);
    await pollUntil(
      () =>
          container.read(beatTrackStateProvider).phase == BeatTrackPhase.ready,
      reason: '分析未收尾',
    );

    final markers = docStorage.markersSnapshot;
    expect(markers['beat'], isNotNull);
    expect(markers['meta']['signature'], signature.toJson());
    expect(markers['meta']['mirrored'], isTrue);
  });

  group('歌曲响度基准', () {
    test('已有 beat 打开：缓存命中即用，不再探测补测', () async {
      final storage = InMemoryPrivateJsonStorage();
      await SongLoudnessBaselineStore(storage).save(kVideoId, 0.8);
      final probe = _FixedLoudnessProbe(0.25);
      final p = makeProbe(
        markers: {'version': 8, 'beat': beatJson()},
        loudnessProbe: probe,
        privateStorage: storage,
      );

      await p.open();
      await Future<void>.delayed(Duration.zero);

      expect(p.container.read(songLoudnessBaselineProvider), 0.8);
      expect(probe.probed, isEmpty);
    });

    test('已有 beat 打开：无缓存后台补测一次并按视频落盘', () async {
      final storage = InMemoryPrivateJsonStorage();
      final probe = _FixedLoudnessProbe(0.25);
      final p = makeProbe(
        markers: {'version': 8, 'beat': beatJson()},
        loudnessProbe: probe,
        privateStorage: storage,
      );

      await p.open();
      final expected = loudnessBaselineFromRms(0.25);
      await pollUntil(
        () => p.container.read(songLoudnessBaselineProvider) == expected,
        reason: '后台补测未收尾',
      );
      expect(probe.probed, [kFilePath]);
      expect(await SongLoudnessBaselineStore(storage).load(kVideoId), expected);
    });

    test('后台分析完成顺带测量：RMS 经基准映射按视频落盘，无独立补测', () async {
      final storage = InMemoryPrivateJsonStorage();
      final probe = _FixedLoudnessProbe(999);
      final pipeline = FakeBeatPipeline(pcmRmsValue: 0.25);
      final p = makeProbe(
        pipeline: pipeline,
        loudnessProbe: probe,
        privateStorage: storage,
      );

      await p.open();
      await p.settle();

      final expected = loudnessBaselineFromRms(0.25);
      expect(p.container.read(songLoudnessBaselineProvider), expected);
      expect(await SongLoudnessBaselineStore(storage).load(kVideoId), expected);
      expect(probe.probed, isEmpty); // 分析顺带测量，未另起补测。
    });

    test('取消竞态：checkCancelled 后才触发的顺带测量不写会话基准', () async {
      final storage = InMemoryPrivateJsonStorage();
      final container = ProviderContainer(
        overrides: [
          privateJsonStorageProvider.overrideWithValue(storage),
          beatAnalysisPipelineProvider.overrideWithValue(
            _LateCancelLoudnessPipeline(),
          ),
        ],
      );
      container.listen(songLoudnessBaselineProvider, (_, _) {});
      addTearDown(container.dispose);
      final runner = container.read(beatAnalysisRunnerProvider);

      final inFlight = runner.start(
        videoPath: kFilePath,
        coordinator: VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
        seed: () async =>
            const AnnotationSaveSeed(signature: null, mirrored: false),
        videoId: kVideoId,
      );
      runner.cancel(); // 回调触发前取消（代际号已自增）。
      await inFlight;

      expect(
        container.read(songLoudnessBaselineProvider),
        kDefaultSongLoudnessBaseline,
      );
    });
  });

  group('自动置开一次（识别成功与就绪打开两条路径共用一条判据）', () {
    test('默认态：两个总开关都是关（未做任何操作）', () {
      final probe = makeProbe();
      expect(probe.container.read(beatPromptEnabledProvider), isFalse);
      expect(probe.container.read(metronomeSoundEnabledProvider), isFalse);
    });

    test('新分析成功落定：两开关各自动置开一次且写进记忆；重开同一支舞仍是开', () async {
      final probe = makeProbe();
      await probe.open();
      await probe.settle();

      expect(probe.trackState.phase, BeatTrackPhase.ready);
      expect(probe.container.read(beatPromptEnabledProvider), isTrue);
      expect(probe.container.read(metronomeSoundEnabledProvider), isTrue);
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'sound': true,
      }, reason: '这次置开被写进这支舞的记忆');

      // 重开同一支舞（已有 beat，恢复路径）：生效值按记忆仍是开。
      await probe.open();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(probe.container.read(beatPromptEnabledProvider), isTrue);
      expect(probe.container.read(metronomeSoundEnabledProvider), isTrue);
    });

    test('打开已有节拍数据、无记忆记录的舞：网格就绪即两开关各置开一次并写进记忆', () async {
      final probe = makeProbe(markers: {'version': 8, 'beat': beatJson()});
      await probe.open();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(probe.pipeline.calls, 0, reason: '恢复路径不发生识别');
      expect(probe.trackState.phase, BeatTrackPhase.ready);
      expect(probe.container.read(beatPromptEnabledProvider), isTrue);
      expect(probe.container.read(metronomeSoundEnabledProvider), isTrue);
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'sound': true,
      });
    });

    test('打开有记忆记录的舞（记录是关）：不自动置开，生效值按记忆', () async {
      final probe = makeProbe(
        markers: {'version': 8, 'beat': beatJson()},
        local: const {
          'version': 3,
          'prefs': {
            'beatPrompt': {'animation': false, 'sound': false},
          },
        },
      );
      await probe.open();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(probe.container.read(beatPromptEnabledProvider), isFalse);
      expect(probe.container.read(metronomeSoundEnabledProvider), isFalse);
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': false,
        'sound': false,
      }, reason: '盘上记忆未被翻成开');
    });

    test('记忆恢复晚于分析落定的竞态：分析先成功、记忆随后读到「关」，最终生效关且盘上没被翻成开', () async {
      final probe = makeProbe(
        local: const {
          'version': 3,
          'prefs': {
            'beatPrompt': {'animation': false, 'sound': false},
          },
        },
      );
      // 竞态序：分析先落定（此刻记忆还没读到）。
      await probe.open(withSettings: false);
      await probe.settle();
      expect(probe.container.read(beatPromptEnabledProvider), isFalse);
      expect(probe.container.read(metronomeSoundEnabledProvider), isFalse);

      // 记忆随后读到「关」：最终生效值是关。
      await probe.restoreSettings();
      expect(probe.container.read(beatPromptEnabledProvider), isFalse);
      expect(probe.container.read(metronomeSoundEnabledProvider), isFalse);
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': false,
        'sound': false,
      }, reason: '磁盘上没有被翻成开');
    });

    test('手动扳动任何开关即写记忆；此后这支舞不再被自动置开', () async {
      final probe = makeProbe();
      await probe.open();
      await probe.settle();

      // 用户手动关掉两个开关：立刻写记忆。
      probe.container.read(beatPromptEnabledProvider.notifier).set(false);
      probe.container.read(metronomeSoundEnabledProvider.notifier).set(false);
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': false,
        'sound': false,
      });

      // 重开同一支舞（恢复路径）：保持关。
      await probe.open();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(probe.container.read(beatPromptEnabledProvider), isFalse);
      expect(probe.container.read(metronomeSoundEnabledProvider), isFalse);
    });

    test('关掉两个开关后重做一次识别（节拍数据被清掉重跑）：只被再置开一次，之后仍听用户的', () async {
      final probe = makeProbe(
        local: const {
          'version': 3,
          'prefs': {
            'beatPrompt': {'animation': false, 'sound': false},
          },
        },
      );
      await probe.open();
      await probe.settle();

      // 新分析成功 = 「再置开一次」（本轮会话用户没动过这份旧记录）。
      expect(probe.container.read(beatPromptEnabledProvider), isTrue);
      expect(probe.container.read(metronomeSoundEnabledProvider), isTrue);
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'sound': true,
      });

      // 用户再关掉：之后听用户的。
      probe.container.read(beatPromptEnabledProvider.notifier).set(false);
      probe.container.read(metronomeSoundEnabledProvider.notifier).set(false);
      await probe.open();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(probe.container.read(beatPromptEnabledProvider), isFalse);
      expect(probe.container.read(metronomeSoundEnabledProvider), isFalse);
    });

    test('识别期间（占位态）手动扳动的表态不被落定翻动：手动开的仍有效、没开的保持关', () async {
      final probe = makeProbe();
      await probe.open();
      expect(probe.trackState.phase, BeatTrackPhase.placeholder);

      // 占位态可显可响：用户手动开节拍动画（不开声音）。
      probe.container.read(beatPromptEnabledProvider.notifier).set(true);
      await probe.settle();

      expect(
        probe.container.read(beatPromptEnabledProvider),
        isTrue,
        reason: '用户手动开的仍然有效',
      );
      expect(
        probe.container.read(metronomeSoundEnabledProvider),
        isFalse,
        reason: '落定不越过用户本轮的表态另开未开的开关',
      );
      await probe.flushSettings();
      expect(probe.docStorage.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
      });
    });

    test('分析失败与中断：不产生开关写入、也不产生记忆写入', () async {
      final failed = makeProbe(pipeline: FakeBeatPipeline(error: '无有效音轨'));
      await failed.open();
      await failed.settle();
      expect(failed.container.read(beatPromptEnabledProvider), isFalse);
      expect(failed.container.read(metronomeSoundEnabledProvider), isFalse);
      expect(
        (failed.docStorage.localSnapshot['prefs'] as Map?)?.containsKey(
          'beatPrompt',
        ),
        isNot(isTrue),
        reason: '失败路径零记忆写入',
      );

      final cancelled = makeProbe(
        pipeline: FakeBeatPipeline(hangUntilCancelled: true),
      );
      await cancelled.open();
      await pollUntil(() => cancelled.pipeline.calls == 1, reason: '分析未启动');
      cancelled.container.read(beatAnalysisRunnerProvider).cancel();
      await cancelled.pipeline.settled;
      expect(cancelled.container.read(beatPromptEnabledProvider), isFalse);
      expect(cancelled.container.read(metronomeSoundEnabledProvider), isFalse);
      expect(
        (cancelled.docStorage.localSnapshot['prefs'] as Map?)?.containsKey(
          'beatPrompt',
        ),
        isNot(isTrue),
        reason: '中断路径零记忆写入',
      );
    });
  });
}

/// 竞态窗口桩：忽略取消，调用 onPcmRms 后抛取消异常。
class _LateCancelLoudnessPipeline implements BeatAnalysisPipeline {
  @override
  Future<List<marker_doc.BeatPoint>> analyze(
    BeatAnalysisRequest request,
  ) async {
    // 让出执行：宿主在回调触发前完成取消（竞态窗口）。
    await Future<void>.delayed(Duration.zero);
    request.onPcmRms?.call(0.25);
    throw const BeatAnalysisCancelled();
  }
}
