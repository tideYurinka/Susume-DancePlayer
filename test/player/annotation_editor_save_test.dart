import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（提交点钩子断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  group('提交点触发保存', () {
    test('单发编辑提交后段级 diff 入队（分段线落 annotations 段）', () {
      editor().submit(AddSegmentLine(at: ten));

      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.segmentLines.single.position, ten);
      expect(sink.saved.single.corrections, isNull);
      expect(sink.saved.single.session, isNull);
    });

    test('no-op 编辑不入队', () {
      editor().submit(AddSegmentLine(at: ten));
      sink.saved.clear();

      editor().submit(AddSegmentLine(at: ten));
      expect(sink.saved, isEmpty);
    });

    test('段级 diff：纯熟练度编辑只带 session 段', () {
      editor().submit(AddSegmentLine(at: ten));
      sink.saved.clear();

      editor().submit(SetSegmentMastery(order: 0, mastery: LearningMastery.mastered));
      final diff = sink.saved.single;
      expect(diff.session?.mastery, {0: LearningMastery.mastered});
      expect(diff.annotations, isNull);
      expect(diff.corrections, isNull);
    });

    test('flag 切换随分段线落 annotations 段', () {
      editor().submit(AddSegmentLine(at: ten));
      sink.saved.clear();

      editor().submit(ToggleSegmentFlag(index: 0));
      expect(sink.saved.single.annotations?.segmentLines.single.flagged, isTrue);
    });

    test('自动分段：重写后的熟练度落 session 段、重点落 annotations 段', () {
      editor().submit(AddSegmentLine(at: ten));
      editor().submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 1));
      sink.saved.clear();

      // 旧分区 [0,10)/[10,60) → 新分区 [0,20)/[20,60)：旧段 1 与新段 0、
      // 新段 1 都相交 → 它的熟练度与重点两个新段都继承。
      editor().submit(
        AutoSegment(start: Duration.zero, end: total, cuts: const [twenty]),
      );

      final diff = sink.saved.single;
      expect(diff.session?.mastery, {
        0: LearningMastery.mastered,
        1: LearningMastery.mastered,
      });
      expect(diff.annotations?.emphasizedSegments, {0, 1});
    });
  });

  // 拖动会话「中间态不入队、收口一次」已收成跨族参数表：
  // annotation_editor_drag_session_parity_test.dart。

  group('撤销/重做各算一次编辑', () {
    test('undo 入队回退后状态', () {
      editor().submit(AddSegmentLine(at: ten));
      editor().submit(AddSegmentLine(at: twenty));
      sink.saved.clear();

      editor().undo();
      expect(sink.saved.length, 1);
      expect(
        sink.saved.single.annotations?.segmentLines.map((l) => l.position),
        [ten],
      );
    });

    test('redo 入队重放后状态', () {
      editor().submit(AddSegmentLine(at: ten));
      editor().submit(AddSegmentLine(at: twenty));
      editor().undo();
      sink.saved.clear();

      editor().redo();
      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.segmentLines.length, 2);
    });

    test('无历史 undo / 无可重做 redo 不入队', () {
      editor().undo();
      editor().redo();
      expect(sink.saved, isEmpty);
    });
  });

  test('未接编排器（默认 null sink）全程零行为不抛', () {
    final bare = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(bare.dispose);
    final editor = bare.read(annotationEditorProvider);
    editor.submit(AddSegmentLine(at: ten));
    editor.undo();
    expect(bare.read(annotationTimelineProvider).segmentLines, isEmpty);
  });
}
