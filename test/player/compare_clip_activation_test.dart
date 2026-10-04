import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalSpan;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        activeLoopRangeProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        practiceClipActivationProvider,
        practiceClipsProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryAutoRestoreProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    as vdp
    show videoDocumentStorageProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 记录型保存 sink（激活写入点断言用，同 segment_selection_persistence）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 片段激活回看：接线层断言——激活互斥（激活
/// 源保持单值，纯件 [applyCompareActivation] 的既定形状）、单一循
/// 环范围派生、进度拖出范围清激活、`session` 段扩键落盘与恢复（不自动
/// 跳转、不自动播放）。
void main() {
  const clipIn = Duration(seconds: 10);
  const clipOut = Duration(seconds: 20);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
    sink = RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
    addTearDown(container.dispose);
  });

  PracticeClip clip({
    String id = 'clip_m1',
    int inMs = 10000,
    int outMs = 20000,
  }) => PracticeClip(
    id: id,
    materialId: 'm1',
    materialSourceStartMs: 0,
    inMs: inMs,
    outMs: outMs,
  );

  void givenClips([List<PracticeClip> clips = const []]) {
    container.read(practiceClipsProvider.notifier).restore(clips);
  }

  void givenThreeSegments() {
    final editor = container.read(annotationEditorProvider);
    for (final position in const [
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ]) {
      editor.submit(AddSegmentLine(at: position));
    }
    sink.saved.clear();
  }

  group('激活互斥（激活源保持单值）', () {
    test('激活片段清除学习段激活；再点同片段取消', () {
      givenThreeSegments();
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      givenClips([clip()]);

      container.read(practiceClipActivationProvider.notifier).toggle(clip());

      expect(container.read(practiceClipActivationProvider)?.clipId, 'clip_m1');
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(container.read(transitionSegmentProvider), isNull);

      // 单一循环范围 = 片段源区间。
      final range = container.read(activeLoopRangeProvider);
      expect(range, isNotNull);
      expect(range!.start, clipIn);
      expect(range.end, clipOut);

      // 再点同片段 → 取消激活。
      container.read(practiceClipActivationProvider.notifier).toggle(clip());
      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(activeLoopRangeProvider), isNull);
    });

    test('激活片段清除临时衔接段激活', () {
      givenThreeSegments();
      container.read(annotationEditorProvider).toggleTransitionSegment(1);
      expect(container.read(transitionSegmentProvider), isNotNull);
      givenClips([clip()]);

      container.read(practiceClipActivationProvider.notifier).toggle(clip());

      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(practiceClipActivationProvider)?.clipId, 'clip_m1');
    });

    test('激活学习段清除片段激活；循环范围回到学习段', () {
      givenThreeSegments();
      givenClips([clip()]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());

      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(activeLoopRangeProvider), isNotNull);
    });

    test('激活临时衔接段清除片段激活', () {
      givenThreeSegments();
      givenClips([clip()]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());

      container.read(annotationEditorProvider).toggleTransitionSegment(1);

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(transitionSegmentProvider), isNotNull);
    });

    test('片段被移出轨道：激活在同一次写里被清，循环范围为空', () {
      givenClips([clip(inMs: 10000, outMs: 20000)]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());
      // 片段被移出轨道：同一次写里清激活（写后
      // 不变量——表里没有的片段不能还在回看，悬空激活不可表达）。
      givenClips(const []);

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(container.read(activeLoopRangeProvider), isNull);
    });
  });

  group('进度拖出范围清激活（与学习段同规则：端点仍属范围）', () {
    test('拖出片段范围清除、端点保留', () {
      givenClips([clip()]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());

      // 拖出（< in）→ 清除。
      container
          .read(practiceClipActivationProvider.notifier)
          .clearIfOutside(const Duration(seconds: 5));
      expect(container.read(practiceClipActivationProvider), isNull);

      // 重新激活后在终点上 → 保留。
      container.read(practiceClipActivationProvider.notifier).toggle(clip());
      container
          .read(practiceClipActivationProvider.notifier)
          .clearIfOutside(clipOut);
      expect(container.read(practiceClipActivationProvider), isNotNull);
    });

    test('纯件同口径：clipActivationAfterSeek 端点内保留、越界为 null', () {
      const active = PracticeClipLoop(clipId: 'clip_m1');
      const range = IntervalSpan(startMs: 10000, endMs: 20000);
      expect(
        clipActivationAfterSeek(
          active: active,
          positionMs: 20000,
          clipRange: range,
        ),
        isNotNull,
      );
      expect(
        clipActivationAfterSeek(
          active: active,
          positionMs: 20001,
          clipRange: range,
        ),
        isNull,
      );
    });
  });

  group('session 段扩键落盘（与学习段激活同段同口径）', () {
    test('激活片段入队 session 段：activePracticeClipId 终值', () {
      givenClips([clip()]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());

      final session = sink.saved.last.session;
      expect(session?.activePracticeClipId, 'clip_m1');
      expect(session?.activatedSegments, isEmpty);
    });

    test('学习段激活写点携带片段清除终值（互不覆盖）', () {
      givenThreeSegments();
      givenClips([clip()]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());
      sink.saved.clear();

      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);

      final session = sink.saved.last.session;
      expect(session?.activatedSegments, const [0]);
      expect(session?.activePracticeClipId, isNull);
    });
  });

  group('跨会话恢复（不自动跳转、不自动播放）', () {
    test('恢复就位激活与循环作用域、标记恢复写（不 seek）', () {
      givenClips([clip()]);

      container
          .read(practiceClipActivationProvider.notifier)
          .restore('clip_m1', clips: [clip()]);

      expect(container.read(practiceClipActivationProvider)?.clipId, 'clip_m1');
      expect(container.read(activeLoopRangeProvider), isNotNull);
      expect(
        container
            .read(practiceClipActivationProvider.notifier)
            .lastWriteFromRestore,
        isTrue,
      );
      expect(sink.saved, isEmpty);
    });

    test('恢复写回为空（null 或 id 不在列表）不置恢复静默标志', () {
      // 无激活 id：什么都没写回，不得标记「来自恢复」。
      container
          .read(practiceClipActivationProvider.notifier)
          .restore(null, clips: []);
      expect(
        container
            .read(practiceClipActivationProvider.notifier)
            .lastWriteFromRestore,
        isFalse,
      );

      // id 不在片段列表（片段已删）：同样没写回激活。
      container
          .read(practiceClipActivationProvider.notifier)
          .restore('ghost', clips: [clip()]);
      expect(
        container
            .read(practiceClipActivationProvider.notifier)
            .lastWriteFromRestore,
        isFalse,
      );
    });

    test('恢复 id 不在片段列表：不激活', () {
      container
          .read(practiceClipActivationProvider.notifier)
          .restore('ghost', clips: [clip()]);
      expect(container.read(practiceClipActivationProvider), isNull);
    });

    test('换视频复位：非保存清、不入队', () {
      givenClips([clip()]);
      container.read(practiceClipActivationProvider.notifier).toggle(clip());
      sink.saved.clear();

      container.read(practiceClipActivationProvider.notifier).reset();

      expect(container.read(practiceClipActivationProvider), isNull);
      expect(sink.saved, isEmpty);
    });

    test('重开自动恢复：local session 段 activePracticeClipId 回会话态', () async {
      const pathA = '/videos/a.mp4';
      const idA = 'vid-a';
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      final storages = {
        idA: InMemoryVideoDocumentStorage(
          local: {
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
          },
        ),
      };
      final restoreContainer = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(
            FakePlaybackEngine(duration: const Duration(minutes: 1)),
          ),
          speedHistoryAutoRestoreProvider.overrideWithValue(false),
          videoIndexStoreProvider.overrideWithValue(index),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          for (final entry in storages.entries)
            vdp
                .videoDocumentStorageProvider(entry.key)
                .overrideWithValue(entry.value),
        ],
      );
      addTearDown(restoreContainer.dispose);

      final session = VideoSettingsPersistence(restoreContainer);
      await session.startForVideo(idA);

      expect(
        restoreContainer.read(practiceClipActivationProvider)?.clipId,
        'clip_m1',
      );
      expect(
        restoreContainer
            .read(practiceClipActivationProvider.notifier)
            .lastWriteFromRestore,
        isTrue,
      );
      expect(restoreContainer.read(activeLoopRangeProvider), isNotNull);
    });
  });
}
