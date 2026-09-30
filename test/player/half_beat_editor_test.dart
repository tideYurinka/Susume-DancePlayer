import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        selectedHalfBeatLineIndexProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
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
  // 占位均匀网格（120bpm）提交时照常吸附半拍格点（等距取
  // 靠后）——10s → 10.25s、15s → 15.25s、20s → 20.25s。
  const tenLanded = Duration(seconds: 10, milliseconds: 250);
  const fifteenLanded = Duration(seconds: 15, milliseconds: 250);
  const twentyLanded = Duration(seconds: 20, milliseconds: 250);

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

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);
  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

  group('半拍线编辑命令', () {
    test('插入半拍线：入时间线、diff 的 annotations 段携带半拍线落 markers', () {
      editor().submit(AddHalfBeatLine(at: ten));

      // 提交时模块内吸附半拍格点（占位均匀网格照常）。
      expect(timeline().halfBeatLines, [
        const HalfBeatLine(position: tenLanded),
      ]);
      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.halfBeatLines.single.position, tenLanded);
      expect(sink.saved.single.corrections, isNull);
      expect(sink.saved.single.session, isNull);
    });

    test('半拍线插入不清激活学习段（非分段几何）', () {
      editor().submit(AddSegmentLine(at: ten));
      domain().toggleLearningSegment(0);
      sink.saved.clear();

      editor().submit(AddHalfBeatLine(at: twenty));
      expect(container.read(selectedLearningSegmentsProvider), {0});
    });

    test('半拍线拖动：会话中间态不入队、收口一次落终态', () {
      editor().submit(AddHalfBeatLine(at: ten));
      sink.saved.clear();

      final session = editor().beginHalfBeatDrag(0);
      session.moveTo(const Duration(seconds: 15));
      expect(sink.saved, isEmpty);
      session.end();

      expect(sink.saved.length, 1);
      expect(
        sink.saved.single.annotations?.halfBeatLines.single.position,
        // 原始指针位置经模块内吸附半拍格点后落库。
        fifteenLanded,
      );
    });

    test('撤销/重做覆盖半拍线编辑', () {
      editor().submit(AddHalfBeatLine(at: ten));
      expect(timeline().halfBeatLines, hasLength(1));

      editor().undo();
      expect(timeline().halfBeatLines, isEmpty);

      editor().redo();
      expect(timeline().halfBeatLines, [
        const HalfBeatLine(position: tenLanded),
      ]);
    });

    test('半拍线索引越界拖动抛 RangeError', () {
      expect(() => editor().beginHalfBeatDrag(0), throwsRangeError);
    });
  });

  group('半拍线删除', () {
    test('删除半拍线：出时间线、diff 的 annotations 段携带半拍线落 markers', () {
      editor().submit(AddHalfBeatLine(at: ten));
      editor().submit(AddHalfBeatLine(at: twenty));
      sink.saved.clear();

      editor().submit(const RemoveHalfBeatLine(index: 0));

      expect(timeline().halfBeatLines, [
        const HalfBeatLine(position: twentyLanded),
      ]);
      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.halfBeatLines.single.position, twentyLanded);
      expect(sink.saved.single.corrections, isNull);
      expect(sink.saved.single.session, isNull);
    });

    test('删除 = 一次标注编辑：撤销恢复、重做再删', () {
      editor().submit(AddHalfBeatLine(at: ten));
      editor().submit(const RemoveHalfBeatLine(index: 0));
      expect(timeline().halfBeatLines, isEmpty);

      editor().undo();
      expect(timeline().halfBeatLines, [
        const HalfBeatLine(position: tenLanded),
      ]);

      editor().redo();
      expect(timeline().halfBeatLines, isEmpty);
    });

    test('删后清选中（半拍线单选槽）', () {
      editor().submit(AddHalfBeatLine(at: ten));
      domain().toggle(HalfBeatLineSelection(0));
      expect(
        container.read(selectedHalfBeatLineIndexProvider),
        isNotNull,
      );

      editor().submit(const RemoveHalfBeatLine(index: 0));
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });

    test('删除不清激活学习段（非分段几何）', () {
      editor().submit(AddSegmentLine(at: ten));
      editor().submit(AddHalfBeatLine(at: twenty));
      domain().toggleLearningSegment(0);

      editor().submit(const RemoveHalfBeatLine(index: 0));
      expect(container.read(selectedLearningSegmentsProvider), {0});
    });

    test('索引越界抛 RangeError', () {
      expect(
        () => editor().submit(const RemoveHalfBeatLine(index: 0)),
        throwsRangeError,
      );
    });
  });
}
