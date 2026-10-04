import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/edit_history.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditSnapshot,
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        practiceClipsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 截取 / 删除 verb 与拖动会话按**片段 id** 寻址：
/// verb 找不到该 id = 静默 no-op（不执行、不入史、不落盘）；拖动起手记 id，
/// 起手之后外部写移动了下标仍作用于原片段。用户可见行为零变化。
void main() {
  const total = Duration(minutes: 1);

  // 三条互不重叠的片段（源时间轴升序）：
  // A：源 0–8s；B：源 10–20s；C：源 24–30s。
  const clipA = PracticeClip(
    id: 'cA',
    materialId: 'mA',
    materialSourceStartMs: 0,
    inMs: 0,
    outMs: 8000,
    materialDurationMs: 20000,
  );
  const clipB = PracticeClip(
    id: 'cB',
    materialId: 'mB',
    materialSourceStartMs: 10000,
    inMs: 0,
    outMs: 10000,
    materialDurationMs: 30000,
  );
  const clipC = PracticeClip(
    id: 'cC',
    materialId: 'mC',
    materialSourceStartMs: 24000,
    inMs: 0,
    outMs: 6000,
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
    // 就绪均匀网格：八拍点 = 0/4/8…s。
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: 60));
    container.read(practiceClipsProvider.notifier).restore(const [
      clipA,
      clipB,
      clipC,
    ]);
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);
  List<PracticeClip> table() => container.read(practiceClipsProvider);
  PracticeClip clipById(String id) =>
      table().firstWhere((clip) => clip.id == id);
  EditHistory<AnnotationEditSnapshot> history() =>
      container.read(annotationEditHistoryProvider);

  group('verb 按 id 寻址', () {
    test('截取：按 id 命中，直接提交改该片段、入史一次', () {
      final outcome = editor().submit(
        TrimPracticeClip(
          clipId: 'cB',
          edge: IntervalEdge.end,
          to: const Duration(seconds: 23),
        ),
      );
      expect(outcome.applied, isTrue);
      // 请求 23s → 就近八拍点 24s → 素材内 out = 14000（源 24000）。
      expect(clipById('cB').outMs, 14000);
      expect(clipById('cB').inMs, 0, reason: '另一端不动');
      expect(clipById('cC').outMs, 6000, reason: '其它片段不动');
      expect(history().length, 1);
      expect(sink.saved, isEmpty, reason: '片段落盘归随舞 prefs 编排，标注保存臂不携带片段段');
    });

    test('截取：未命中 id 静默 no-op——不执行、不入史、不落盘', () {
      final outcome = editor().submit(
        TrimPracticeClip(
          clipId: 'clip_missing',
          edge: IntervalEdge.end,
          to: const Duration(seconds: 24),
        ),
      );
      expect(outcome.applied, isFalse);
      expect(history().length, 0);
      expect(sink.saved, isEmpty);
      expect(table().length, 3);
    });

    test('删除：按 id 命中移出轨道、入史；未命中 id 静默 no-op', () {
      expect(editor().submit(RemovePracticeClip(clipId: 'cB')).applied, isTrue);
      expect(table().map((clip) => clip.id), ['cA', 'cC']);
      expect(history().length, 1);
      expect(sink.saved, isEmpty, reason: '片段落盘归随舞 prefs 编排，标注保存臂不携带片段段');

      final stale = editor().submit(RemovePracticeClip(clipId: 'cB'));
      expect(stale.applied, isFalse, reason: '同一 id 再删 = 已不存在 = no-op');
      expect(history().length, 1, reason: 'no-op 不入史');
      expect(sink.saved, isEmpty, reason: 'no-op 不落盘');
    });

    test('「起手后另一条片段被外部删除」仍作用于原片段：先红后绿的漂移用例', () {
      // 拖动起手作用在 B（下标 1）；起手之后外部写（素材连带删除）把 A
      // 移出轨道，B 的下标从 1 漂到 0——会话收口仍必须作用在 B 上。
      final session = editor().beginPracticeClipTrimDrag(1, IntervalEdge.end);
      container.read(practiceClipsProvider.notifier).removeByMaterial('mA');
      expect(table().map((clip) => clip.id), ['cB', 'cC']);

      expect(
        session.moveTo(const Duration(seconds: 23)),
        const Duration(seconds: 24),
        reason: '落点读回 = 被拖片段（B）写后的端点位置',
      );
      session.end();

      expect(clipById('cB').outMs, 14000, reason: '作用对象仍是起手的那条');
      expect(clipById('cC').outMs, 6000, reason: '下标漂移不得误伤别条');
      expect(history().length, 1);
      expect(sink.saved, isEmpty, reason: '片段落盘归随舞 prefs 编排，标注保存臂不携带片段段');
    });

    test('「起手后本条片段被外部删除」：会话逐帧静默，拖动不写任何片段', () {
      final session = editor().beginPracticeClipTrimDrag(1, IntervalEdge.end);
      container.read(practiceClipsProvider.notifier).removeByMaterial('mB');

      expect(session.moveTo(const Duration(seconds: 23)), isNull);
      session.end();

      expect(table().map((clip) => clip.id), ['cA', 'cC']);
      expect(table()[0].inMs, 0);
      expect(table()[0].outMs, 8000);
      expect(table()[1].inMs, 0);
      expect(table()[1].outMs, 6000, reason: '拖动不写任何片段');
      // 收口快照对把外部删除折进历史是既有事务口径，其作用域收口归
      // 撤销按 id 三方合并，此处不扩。
      expect(sink.saved, isEmpty);
    });
  });
}

class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}
