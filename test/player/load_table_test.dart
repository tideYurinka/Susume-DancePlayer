import 'package:dance_learning_app/persistence/load_table.dart';
import 'package:dance_learning_app/player/open_session.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationTimelineProvider,
        layoutLockedProvider,
        learningMasteryProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show delayedLoopProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/open_restore.dart'
    show videoOpenRestorerProvider;
import 'package:dance_learning_app/player/preview_snap.dart'
    show previewSnapEnabledProvider;
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider, videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 装载表直测：断言表对外声明的
/// 次序、来源与默认值，以及「缺段 / 空文档」时各取值道确实回落成表里声明的
/// 默认——不断言表的内部结构、不断言各模块怎么解析字段。
void main() {
  group('装载表：次序即声明次序', () {
    test('行序 = 恢复次序（编辑器公开标记 → 编辑器本地私密 → 偏好 → 名册 → 署名 → 镜像 → 续播）', () {
      expect(
        LoadTable.standard.rows.map((row) => row.id).toList(),
        [
          LoadRowId.editorPublicMarkers,
          LoadRowId.editorLocalPrivate,
          LoadRowId.preferences,
          LoadRowId.roster,
          LoadRowId.signature,
          LoadRowId.mirror,
          LoadRowId.resume,
        ],
      );
    });

    test('行标识的声明次序与表行序一致（声明即事实）', () {
      expect(
        LoadTable.standard.rows.map((row) => row.id).toList(),
        LoadRowId.values,
        reason: '枚举声明次序即表的行序：署名行因此排在镜像行之前（首次导入先命名、后镜像）',
      );
    });

    test('顺序依赖由声明次序承载：时间线先于熟练度/激活段过滤，也先于续播 seek', () {
      int positionOf(LoadRowId id) => LoadTable.standard.rows.indexWhere(
            (row) => row.id == id,
          );
      expect(
        positionOf(LoadRowId.editorPublicMarkers),
        lessThan(positionOf(LoadRowId.editorLocalPrivate)),
      );
      expect(
        positionOf(LoadRowId.editorPublicMarkers),
        lessThan(positionOf(LoadRowId.resume)),
      );
    });

    test('列：文档来源与段逐行声明', () {
      LoadRow rowOf(LoadRowId id) => LoadTable.standard.rowFor(id);
      expect(rowOf(LoadRowId.editorPublicMarkers).source, LoadSource.publicMarkers);
      expect(rowOf(LoadRowId.editorLocalPrivate).source, LoadSource.localPrivate);
      expect(rowOf(LoadRowId.preferences).source, LoadSource.localPrivate);
      expect(rowOf(LoadRowId.roster).source, LoadSource.publicMarkers);
      expect(rowOf(LoadRowId.mirror).source, LoadSource.indexEntry);
      expect(rowOf(LoadRowId.signature).source, LoadSource.indexEntry);
      expect(rowOf(LoadRowId.resume).source, LoadSource.indexEntry);

      for (final row in LoadTable.standard.rows) {
        expect(row.segment, isNotEmpty, reason: '${row.id} 缺段声明');
      }
      expect(rowOf(LoadRowId.editorPublicMarkers).segment, contains('时间线'));
      expect(rowOf(LoadRowId.editorLocalPrivate).segment, contains('熟练度'));
      expect(rowOf(LoadRowId.preferences).segment, contains('吸附'));
      expect(rowOf(LoadRowId.resume).segment, contains('续播'));
      // 取景挪行、换字段：源侧取景选区留在公开标记文件装载行
      // （声明次序即恢复次序——公开标记行先于偏好行执行）。
      expect(
        LoadTable.standard.rows.indexOf(rowOf(LoadRowId.editorPublicMarkers)),
        lessThan(LoadTable.standard.rows.indexOf(rowOf(LoadRowId.preferences))),
      );
      expect(rowOf(LoadRowId.editorPublicMarkers).segment, contains('取景选区'));
      expect(rowOf(LoadRowId.preferences).segment, isNot(contains('取景')));
    });
  });

  group('装载表：默认值一处声明', () {
    test('偏好行声明吸附开 / 前导 4 拍 / 不锁（其余字段默认归本行的模块）', () {
      final defaults = LoadDefaults.preferences;
      expect(defaults.previewSnapEnabled, isTrue);
      expect(defaults.delayedLoopBeats, 4);
      expect(defaults.layoutLocked, isFalse);
      // 打开恢复的复位函数与拍数回落读的就是这一份。
      expect(LoadTable.standard.rowFor(LoadRowId.preferences).defaults, defaults);
      expect(loadPreferenceDefaults, defaults);
    });

    test('文档行不声明字段默认（空文档回落为各自的空态）', () {
      for (final id in [
        LoadRowId.editorPublicMarkers,
        LoadRowId.editorLocalPrivate,
        LoadRowId.roster,
        LoadRowId.mirror,
        LoadRowId.signature,
        LoadRowId.resume,
      ]) {
        expect(LoadTable.standard.rowFor(id).defaults, isNull, reason: '$id');
      }
    });
  });

  group('装载表：缺段与空文档时的回落', () {
    test('markers / local 全空：取值道落成表里声明的默认值', () async {
      final probe = await _open(markers: const {}, local: const {});
      final defaults = LoadDefaults.preferences;
      expect(probe.container.read(previewSnapEnabledProvider), defaults.previewSnapEnabled);
      expect(probe.container.read(delayedLoopProvider).beats, defaults.delayedLoopBeats);
      expect(probe.container.read(layoutLockedProvider), defaults.layoutLocked);

      // 文档行：空文档回落为空态（无分段线、无熟练度、无激活、无备注）。
      expect(probe.container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(probe.container.read(learningMasteryProvider), isEmpty);
      expect(probe.container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(probe.container.read(noteStickersProvider), isEmpty);
      expect(probe.container.read(localMirrorFragmentsProvider), isEmpty);
    });

    test('文档在但段缺：在读的段照常恢复，缺的段各自回落', () async {
      // local 只有 session 段（无 prefs 段）；markers 只有 annotations
      // 段（无 notes 段）。
      final probe = await _open(
        markers: const {
          'version': 8,
          'meta': {'mirrored': false},
          'annotations': {
            'range': {'startMs': 0, 'endMs': 180000},
            'segmentLines': [
              {'timeMs': 60000, 'flag': true},
            ],
            'emphasizedSegments': [1],
          },
        },
        local: const {
          'version': 3,
          'session': {
            'mastery': {'1': 'practicing'},
            'activatedSegments': [1],
          },
        },
      );

      // 在读的段恢复。
      expect(probe.container.read(annotationTimelineProvider).segmentLines.length, 1);
      expect(
        probe.container.read(learningMasteryProvider),
        {1: LearningMastery.learning},
      );
      expect(probe.container.read(selectedLearningSegmentsProvider), {1});

      // 缺的段回落：备注 / 局部镜像片段为空，偏好三值落表默认。
      expect(probe.container.read(noteStickersProvider), isEmpty);
      expect(probe.container.read(localMirrorFragmentsProvider), isEmpty);
      final defaults = LoadDefaults.preferences;
      expect(probe.container.read(previewSnapEnabledProvider), defaults.previewSnapEnabled);
      expect(probe.container.read(delayedLoopProvider).beats, defaults.delayedLoopBeats);
      expect(probe.container.read(layoutLockedProvider), defaults.layoutLocked);
    });
  });
}

/// 最小探针：建立会话后走一次打开恢复，等价播放页接线。
Future<_Probe> _open({
  required Map<String, dynamic> markers,
  required Map<String, dynamic> local,
}) async {
  final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
  final docStorage = InMemoryVideoDocumentStorage(
    markers: markers,
    local: local,
  );
  final indexStorage = InMemoryVideoIndexStorage();
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      videoIndexStoreProvider.overrideWithValue(indexStorage),
      contentHasherProvider.overrideWithValue(const FixedHasher('hash-1')),
      videoDocumentStorageFactoryProvider.overrideWithValue(
        (_) => docStorage,
      ),
      beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
    ],
  );
  // 容器内无 widget 监听，保持恢复目标 provider 存活（等价播放页接线）。
  container.listen(previewSnapEnabledProvider, (_, _) {});
  container.listen(delayedLoopProvider, (_, _) {});
  container.listen(layoutLockedProvider, (_, _) {});
  container.listen(annotationTimelineProvider, (_, _) {});
  container.listen(learningMasteryProvider, (_, _) {});
  container.listen(selectedLearningSegmentsProvider, (_, _) {});
  container.listen(noteStickersProvider, (_, _) {});
  container.listen(localMirrorFragmentsProvider, (_, _) {});
  addTearDown(container.dispose);

  final session = OpenSession(
    filePath: '/videos/a.mp4',
    indexStore: indexStorage,
    hasher: const FixedHasher('hash-1'),
    coordinatorFor: (videoId) =>
        container.read(videoDocumentCoordinatorProvider(videoId)),
  );
  await session.establish();
  await container.read(videoOpenRestorerProvider).resolve(
        session: session,
        videoDuration: engine.duration!,
      );
  return _Probe(container);
}

class _Probe {
  _Probe(this.container);

  final ProviderContainer container;
}
