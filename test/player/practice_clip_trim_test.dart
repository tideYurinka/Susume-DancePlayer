import 'package:dance_learning_app/annotation/annotation_timeline.dart'
    show AnnotationTimeline;
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/edit_history.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditSnapshot,
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        layoutLockedProvider,
        practiceClipsProvider;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（一次拖动 = 一次保存对拍用）。
class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

void main() {
  const total = Duration(minutes: 1);

  // 片段源区间 8s–20s：素材源起点 8000（非八拍点对齐的素材边界），截取
  // 范围素材内 0–12000，素材全长 20000（源 8000–28000）。
  const clip = PracticeClip(
    id: 'c1',
    materialId: 'm1',
    materialSourceStartMs: 8000,
    inMs: 0,
    outMs: 12000,
    materialDurationMs: 20000,
  );

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late _RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = _RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
    // 就绪均匀网格：八拍点 = 0/4/8…s（吸附纯件的接线口径）。
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: 60));
    container.read(practiceClipsProvider.notifier).restore(const [clip]);
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);
  PracticeClip clipAt(int index) =>
      container.read(practiceClipsProvider)[index];
  EditHistory<AnnotationEditSnapshot> history() =>
      container.read(annotationEditHistoryProvider);

  group('练习片段截取：模块侧 verb 与落点解析', () {
    test('尾端点拖：请求位置经相位吸就近八拍点，只改截取范围（素材内 out）', () {
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      // 请求 25s → 就近八拍点 24s → 素材内 out = 16000（源 24000）。
      expect(
        session.moveTo(const Duration(seconds: 25)),
        Duration(seconds: 24),
      );
      session.end();

      expect(clipAt(0).inMs, 0, reason: '另一端不动');
      expect(clipAt(0).outMs, 16000);
      expect(clipAt(0).materialSourceStartMs, 8000, reason: '素材引用不动');
    });

    test('首端点拖：吸附后只改素材内 in，out 不动', () {
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.start);
      // 请求 15s → 就近八拍点 16s → 素材内 in = 8000（源 16000）。
      expect(
        session.moveTo(const Duration(seconds: 15)),
        Duration(seconds: 16),
      );
      session.end();

      expect(clipAt(0).inMs, 8000);
      expect(clipAt(0).outMs, 12000, reason: '另一端不动');
    });

    test('钳在素材时长内：请求越素材尾被钳到素材全长', () {
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      // 请求 45s → 吸 44s → 偏移 36000 > 素材全长 20000 → 钳 20000。
      expect(
        session.moveTo(const Duration(seconds: 45)),
        Duration(seconds: 28),
      );
      session.end();

      expect(clipAt(0).outMs, 20000);
    });

    test('到头停住：越素材首被钳回素材内 0（不产生倒置、不出素材）', () {
      // 已截短首端的片段：素材内 4s–12s。
      container.read(practiceClipsProvider.notifier).restore(const [
        PracticeClip(
          id: 'c1',
          materialId: 'm1',
          materialSourceStartMs: 8000,
          inMs: 4000,
          outMs: 12000,
          materialDurationMs: 20000,
        ),
      ]);
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.start);
      // 请求 1s → 吸 0s → 偏移 -8000 → 钳 0（源起点停在素材首 8s）。
      expect(session.moveTo(const Duration(seconds: 1)), Duration(seconds: 8));
      session.end();

      expect(clipAt(0).inMs, 0);
      expect(clipAt(0).outMs, 12000);

      // 已在素材首时再往左拖：无净变化（到头停住）。
      final session2 = editor().beginPracticeClipTrimDrag(
        0,
        IntervalEdge.start,
      );
      expect(session2.moveTo(Duration.zero), isNull);
      session2.end();
      expect(container.read(annotationEditHistoryProvider).length, 1);
    });

    test('端点不倒置：拖过对端 = no-op（返回空、状态不变）', () {
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      // 请求 8s → 吸 8s → out = 0 = in → 倒置不成立。
      expect(session.moveTo(Duration.zero), isNull);
      session.end();

      expect(clipAt(0).outMs, 12000);
      expect(container.read(annotationEditHistoryProvider).length, 0);
    });

    test('异常网格（无八拍点）自由：请求位置原样落点', () {
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      expect(
        session.moveTo(const Duration(milliseconds: 25100)),
        const Duration(milliseconds: 25100),
      );
      session.end();

      expect(clipAt(0).outMs, 17100);
    });

    test('有效练习区间约束：吸附落点越有效区间尾被钳回区间内', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.normalized(
            videoDuration: total,
            rangeEnd: const Duration(seconds: 22),
          ),
        ),
      );
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      // 请求 25s → 吸 24s → 越有效区间尾 22s → 钳 22s（素材内 out 14000）。
      expect(
        session.moveTo(const Duration(seconds: 25)),
        Duration(seconds: 22),
      );
      session.end();

      expect(clipAt(0).outMs, 14000);

      // 对偶侧：有效区间首钳住首端点——区间首 16s 在素材内偏移 8000，
      // 请求 1s（吸 0s，越区间首）→ 钳回 16s（素材内 in 8000）。
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.normalized(
            videoDuration: total,
            rangeStart: const Duration(seconds: 16),
          ),
        ),
      );
      const wideClip = PracticeClip(
        id: 'c1',
        materialId: 'm1',
        materialSourceStartMs: 8000,
        inMs: 0,
        outMs: 20000,
        materialDurationMs: 20000,
      );
      container.read(practiceClipsProvider.notifier).restore(const [wideClip]);
      final session2 = editor().beginPracticeClipTrimDrag(
        0,
        IntervalEdge.start,
      );
      expect(
        session2.moveTo(const Duration(seconds: 1)),
        Duration(seconds: 16),
      );
      session2.end();

      expect(clipAt(0).inMs, 8000);
      expect(clipAt(0).outMs, 20000, reason: '另一端不动');
    });

    test('一次拖动 = 一步撤销；放宽回去仍可用；标注保存臂不入片段', () {
      final historyBefore = history().length;
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      session.moveTo(const Duration(seconds: 25));
      // 逐帧中间态不入史不入队。
      expect(history().length, historyBefore);
      session.end();
      session.end(); // 收口幂等。

      expect(history().length, historyBefore + 1);
      // 片段持久化归随舞 prefs 编排（provider 唯一写听者），标注保存臂
      // 不携带片段段。
      expect(sink.saved, isEmpty);
      expect(clipAt(0).outMs, 16000);

      // 一步撤销：截取范围放宽回原值；素材引用（id/源起点）不动。
      editor().undo();
      expect(clipAt(0), clip);
    });

    test('越界开始会话抛 RangeError', () {
      expect(
        () => editor().beginPracticeClipTrimDrag(1, IntervalEdge.end),
        throwsRangeError,
      );
      expect(
        () => editor().beginPracticeClipTrimDrag(-1, IntervalEdge.start),
        throwsRangeError,
      );
    });

    test('锁定分段不挡截取：逐帧照常写入、不弹提示', () {
      container.read(layoutLockedProvider.notifier).toggle();
      final promptBefore = container.read(
        noticeTriggerProvider(NoticeId.layoutLock),
      );
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      expect(session.moveTo(const Duration(seconds: 25)), isNotNull);
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        promptBefore,
      );
      session.end();
      expect(history().length, 1);
      expect(clipAt(0).outMs, isNot(12000), reason: '截取照常生效');
    });

    test('对比态只读不拦截取：对比-控制层内截取照常成立', () {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      final session = editor().beginPracticeClipTrimDrag(0, IntervalEdge.end);
      expect(
        session.moveTo(const Duration(seconds: 25)),
        Duration(seconds: 24),
      );
      session.end();
      expect(clipAt(0).outMs, 16000);
    });
  });
}
