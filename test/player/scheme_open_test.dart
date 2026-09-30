import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/member_scheme_store.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show
        videoDocumentCoordinatorProvider,
        videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_edit.dart'
    show AddSegmentLine, EditLocked;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        annotationEditorProvider,
        annotationMemberSchemeReadonlyProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider,
        practiceClipActivationProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/open_restore.dart'
    show VideoOpenRestorer, videoOpenRestorerProvider;
import 'package:dance_learning_app/player/open_session.dart';
import 'package:dance_learning_app/beat/loudness_probe.dart'
    show SongLoudnessProbe;
import 'package:dance_learning_app/player/song_loudness.dart'
    show songLoudnessProbeProvider;
import 'package:dance_learning_app/player/scheme_open.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_member_scheme_storage.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

const String kVideoId = 'hash-1';
const String kFilePath = '/videos/a.mp4';
const Duration kDuration = Duration(minutes: 3);
final DateTime kImportedAt = DateTime(2026, 9, 15);

/// 组员方案携带的公开标注文档：首尾即整片、1 条分段线、段 1 重点、带节拍
/// （带 beat 才不触发后台分析写盘，恢复语义用例由此保持落盘面干净）。
Map<String, dynamic> memberMarkersJson() => {
  'version': 8,
  'meta': {'mirrored': false},
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
  'annotations': {
    'range': {'startMs': 0, 'endMs': 180000},
    'segmentLines': [
      {'timeMs': 60000, 'flag': false},
    ],
    'emphasizedSegments': [1],
  },
};

/// 我的公开标注文档：1 条分段线（有内容的形状；30s 线以区别于组员方案的 60s）。
Map<String, dynamic> myMarkersJson() => {
  'version': 8,
  'meta': {'mirrored': false},
  'annotations': {
    'range': {'startMs': 0, 'endMs': 180000},
    'segmentLines': [
      {'timeMs': 30000, 'flag': false},
    ],
    'emphasizedSegments': <int>[],
  },
};

/// 我的本地文档：段 1 熟练度与激活（装载组员方案时两者都不得进播放器，
/// 落盘值原样不动）。
Map<String, dynamic> myLocalJson() => {
  'version': 3,
  'session': {
    'mastery': {'1': 'practicing'},
    'activatedSegments': [1],
  },
  'prefs': {'previewSnapEnabled': false, 'delayedLoopBeats': 4},
};

/// 组员方案条目落盘 JSON（store 编解码器私有，测试直写归一形状）。
Map<String, dynamic> schemeDocJson(List<MemberSchemeRecord> records) => {
  'version': 1,
  'schemes': {
    'entries': [
      for (final r in records)
        {
          'schemeId': r.schemeId,
          'memberName': r.memberName,
          'schemeName': r.schemeName,
          if (r.mastery != null)
            'mastery': {
              for (final e in r.mastery!.entries) '${e.key}': e.value,
            },
          'importedAtMs': r.importedAt.millisecondsSinceEpoch,
          'markers': r.markers,
        },
    ],
  },
};

/// 「只有自动写盘内容」的 markers：仅 meta + beat，无任何标注面。
Map<String, dynamic> autoOnlyMarkersJson() => {
  'version': 8,
  'meta': {'mirrored': false},
  'beat': {
    'model': 'madmom_downbeat_rnn_full.onnx',
    'fps': 100,
    'generatedAt': '2026-09-01T00:00:00.000Z',
    'beats': [
      {'t': 0.5, 'down': true},
    ],
  },
};

MemberSchemeRecord memberRecord({
  String schemeId = 's1',
  Map<int, int>? mastery = const {0: 4, 1: 2},
  Map<String, dynamic>? markers,
}) =>
    MemberSchemeRecord(
      schemeId: schemeId,
      memberName: '果',
      schemeName: '队长的版本',
      mastery: mastery,
      importedAt: kImportedAt,
      markers: markers ?? memberMarkersJson(),
    );

class _FixedLoudnessProbe implements SongLoudnessProbe {
  const _FixedLoudnessProbe();

  @override
  Future<double> pcmRms(String videoPath) async => 0.1;
}

class Probe {
  Probe({
    required this.container,
    required this.docStorage,
    required this.memberStorage,
  });

  final ProviderContainer container;
  final InMemoryVideoDocumentStorage docStorage;
  final InMemoryMemberSchemeStorage memberStorage;

  VideoOpenRestorer get restorer => container.read(videoOpenRestorerProvider);

  /// 装配并建立打开会话 + 走打开恢复（播放页的等价接线）。[open] = 这次
  /// 打开带的方案参数，缺省 = 不带参数（首页卡片与「打开续播」的形态）。
  Future<void> open({SchemeOpen open = const AutoSchemeOpen()}) async {
    final session = OpenSession(
      filePath: kFilePath,
      indexStore: container.read(videoIndexStoreProvider),
      hasher: const FixedHasher(kVideoId),
      coordinatorFor: (videoId) =>
          container.read(videoDocumentCoordinatorProvider(videoId)),
    );
    await session.establish();
    await restorer.resolve(
      session: session,
      videoDuration: kDuration,
      scheme: open,
    );
  }
}

Probe makeProbe({
  Map<String, dynamic> markers = const {},
  Map<String, dynamic> local = const {},
  List<MemberSchemeRecord> schemes = const [],
}) {
  final docStorage = InMemoryVideoDocumentStorage(
    markers: markers,
    local: local,
  );
  final memberStorage = InMemoryMemberSchemeStorage(
    schemes.isEmpty ? null : schemeDocJson(schemes),
  );
  final engine = FakePlaybackEngine(duration: kDuration);
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      videoIndexStoreProvider.overrideWithValue(
        InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [
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
          ]),
        ),
      ),
      contentHasherProvider.overrideWithValue(const FixedHasher(kVideoId)),
      videoDocumentStorageFactoryProvider.overrideWithValue(
        (String videoId) => docStorage,
      ),
      memberSchemeStoreProvider.overrideWith(
        (ref, videoId) => MemberSchemeStore(memberStorage),
      ),
      beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
      // 响度补测注入定值桩（带 beat 的打开会触发后台补测，宿主测试不碰
      // 原生 ffmpeg）。
      songLoudnessProbeProvider.overrideWithValue(_FixedLoudnessProbe()),
    ],
  );
  // 容器内无 widget 监听，保持恢复目标 provider 存活（Riverpod 3 默认无
  // 监听即销毁）。
  container.listen(annotationTimelineProvider, (_, _) {});
  container.listen(learningMasteryProvider, (_, _) {});
  container.listen(learningEmphasisProvider, (_, _) {});
  container.listen(selectedLearningSegmentsProvider, (_, _) {});
  addTearDown(container.dispose);
  return Probe(
    container: container,
    docStorage: docStorage,
    memberStorage: memberStorage,
  );
}

/// 我的落盘激活（退出后须与查看前逐位相同的那个值）。
Object? persistedActivation(InMemoryVideoDocumentStorage storage) =>
    (storage.localSnapshot['session'] as Map<String, dynamic>?)?[
        'activatedSegments'];

void main() {
  group('打开参数 resolveOpenedMemberScheme（纯函数）', () {
    List<MemberSchemeRecord> schemes() => [
      memberRecord(schemeId: 's1'),
      memberRecord(schemeId: 's2'),
    ];

    test('不带参数：恒用我的，我的方案为空也不让位给组员方案', () {
      expect(
        resolveOpenedMemberScheme(
          open: const AutoSchemeOpen(),
          schemes: schemes(),
        ),
        isNull,
      );
    });

    test('不带参数：没有组员方案 → 我的', () {
      expect(
        resolveOpenedMemberScheme(
          open: const AutoSchemeOpen(),
          schemes: const [],
        ),
        isNull,
      );
    });

    test('显式「我的标注」用我的；显式组员方案取那一条；被删标识回落我的', () {
      expect(
        resolveOpenedMemberScheme(
          open: const MySchemeOpen(),
          schemes: schemes(),
        ),
        isNull,
        reason: '「我的标注」那一行是我的方案唯一出口',
      );

      expect(
        resolveOpenedMemberScheme(
          open: const MemberSchemeOpen('s2'),
          schemes: schemes(),
        )?.schemeId,
        's2',
      );

      expect(
        resolveOpenedMemberScheme(
          open: const MemberSchemeOpen('gone'),
          schemes: schemes(),
        ),
        isNull,
      );
    });
  });

  group('以某一份方案打开时的恢复', () {
    test('不带参数且我无内容：仍用我的——不借组员方案的标注、可写就位、激活照常', () async {
      final probe = makeProbe(
        schemes: [memberRecord()],
        local: myLocalJson(),
      );
      await probe.open();

      // 打开的是我的空方案：没有组员方案那条 60s 的分段线。
      final timeline = probe.container.read(annotationTimelineProvider);
      expect(timeline.segmentLines, isEmpty);
      // 只读不就位；我的落盘激活不被触碰（退出后逐位相同）。
      expect(
        probe.container.read(annotationMemberSchemeReadonlyProvider),
        isFalse,
      );
      expect(persistedActivation(probe.docStorage), [1]);
    });

    test('不带参数且我的方案有内容：用我的——标注与激活照常恢复、只读不就位', () async {
      final probe = makeProbe(
        markers: myMarkersJson(),
        local: myLocalJson(),
        schemes: [memberRecord()],
      );
      await probe.open();

      final timeline = probe.container.read(annotationTimelineProvider);
      expect(timeline.segmentLines.single.position, const Duration(seconds: 30));
      expect(probe.container.read(learningMasteryProvider), {
        1: LearningMastery.learning,
      });
      expect(probe.container.read(selectedLearningSegmentsProvider), {1});
      expect(
        probe.container.read(annotationMemberSchemeReadonlyProvider),
        isFalse,
      );
      expect(persistedActivation(probe.docStorage), [1]);
    });

    test('显式「我的标注」：我的方案空也走我的——只读不就位、不借组员方案的标注', () async {
      final probe = makeProbe(
        local: myLocalJson(),
        schemes: [memberRecord()],
      );
      await probe.open(open: const MySchemeOpen());

      expect(
        probe.container.read(annotationMemberSchemeReadonlyProvider),
        isFalse,
      );
      // 打开的是我的空方案，不是组员方案那条 60s 的分段线。
      expect(
        probe.container.read(annotationTimelineProvider).segmentLines,
        isEmpty,
      );
      expect(persistedActivation(probe.docStorage), [1]);
    });

    test('显式点某个组员方案：用那一条（同标识替换后仍取最新一份）', () async {
      final probe = makeProbe(
        local: myLocalJson(),
        schemes: [
          memberRecord(schemeId: 's1'),
          memberRecord(schemeId: 's2', mastery: const {0: 0}),
        ],
      );
      await probe.open(open: const MemberSchemeOpen('s2'));

      expect(probe.container.read(learningMasteryProvider), {
        0: LearningMastery.unlearned,
      });
      expect(
        probe.container.read(annotationMemberSchemeReadonlyProvider),
        isTrue,
      );
      expect(probe.container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(persistedActivation(probe.docStorage), [1]);
    });

    test('显式标识已不存在（那条方案被删）：回落我的', () async {
      final probe = makeProbe(
        markers: myMarkersJson(),
        local: myLocalJson(),
        schemes: [memberRecord()],
      );
      await probe.open(open: const MemberSchemeOpen('gone'));

      expect(
        probe.container.read(annotationTimelineProvider).segmentLines.single.position,
        const Duration(seconds: 30),
      );
      expect(
        probe.container.read(annotationMemberSchemeReadonlyProvider),
        isFalse,
      );
    });

    test('熟练度快照未随包：按未练显示，不残留上一支舞的档位', () async {
      final probe = makeProbe(
        markers: myMarkersJson(),
        local: myLocalJson(),
        schemes: [memberRecord(mastery: null)],
      );
      // 先以我的方案打开一次（熟练度面进入 learning）。
      await probe.open(open: const MySchemeOpen());
      expect(probe.container.read(learningMasteryProvider), {
        1: LearningMastery.learning,
      });

      await probe.open(open: const MemberSchemeOpen('s1'));
      expect(probe.container.read(learningMasteryProvider), isEmpty);
      expect(
        probe.container.read(annotationMemberSchemeReadonlyProvider),
        isTrue,
      );
    });

    test('装载组员方案时编辑被门禁拒绝、持久化激活被拒、临时衔接段可用', () async {
      final probe = makeProbe(
        schemes: [memberRecord()],
        local: myLocalJson(),
      );
      await probe.open(open: const MemberSchemeOpen('s1'));
      final sessionBefore = probe.docStorage.localSnapshot['session'];

      expect(
        probe.container.read(annotationEditorProvider).submit(
              const AddSegmentLine(at: Duration(seconds: 90)),
            ),
        isA<EditLocked>(),
      );
      // 持久化激活被拒：内存不激活、盘上原样。
      probe.container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      expect(probe.container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(persistedActivation(probe.docStorage), [1]);
      // 不落盘的临时衔接段照常可用（照着队友的分段跟练的路径）。
      probe.container.read(annotationEditorProvider).toggleTransitionSegment(0);
      expect(probe.container.read(transitionSegmentProvider), isNotNull);
      // 练习片段回看照常，但这次查看不动我的 session 段——在屏的是发送方
      // 那份熟练度快照，写进去会把我的档位与激活覆盖成队友的。
      final clip = PracticeClip(
        id: 'c1',
        materialId: 'm1',
        materialSourceStartMs: 0,
        inMs: 0,
        outMs: 1000,
      );
      probe.container.read(practiceClipActivationProvider.notifier).toggle(clip);
      expect(
        probe.container.read(practiceClipActivationProvider)?.clipId,
        'c1',
        reason: '回看本身照常',
      );
      // 保存编排是合并窗口 + 异步落盘：强制收口后再看盘（守卫缺位时这一步
      // 会把发送方的熟练度写进我的文件）。
      await probe.container.read(annotationSaveSinkProvider)!.flush();
      expect(probe.docStorage.localSnapshot['session'], sessionBefore);
    });
  });
}
