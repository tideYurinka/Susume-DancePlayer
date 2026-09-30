import 'package:dance_learning_app/annotation/edit_history.dart';
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
        annotationTimelineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（收口 seam 两消费者对拍用）。
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
  EditHistory<AnnotationEditSnapshot> history() =>
      container.read(annotationEditHistoryProvider);

  group('单发路径 1:1 parity（历史 × 保存对拍）', () {
    test('净变化提交：历史 +1 ∧ 保存 +1，且撤销回放生效', () {
      editor().submit(AddSegmentLine(at: ten));

      expect(history().length, 1);
      expect(history().canUndo, isTrue);
      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.segmentLines.single.position, ten);
    });

    test('no-op 提交：历史 +0 ∧ 保存 +0', () {
      editor().submit(AddSegmentLine(at: ten));
      final lengthBefore = history().length;
      sink.saved.clear();

      editor().submit(AddSegmentLine(at: ten));

      expect(history().length, lengthBefore);
      expect(sink.saved, isEmpty);
    });
  });

  group('undo/redo 回放 1:1 parity（历史 × 保存对拍）', () {
    test('undo 净变化：历史栈相应变化（-1）∧ 保存 +1，回放经同一折叠入口', () {
      editor().submit(AddSegmentLine(at: ten));
      final lengthBefore = history().length;
      sink.saved.clear();

      editor().undo();

      expect(history().length, lengthBefore - 1);
      expect(history().canUndo, isFalse);
      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.segmentLines, isEmpty);
      expect(
        container.read(annotationTimelineProvider).segmentLines,
        isEmpty,
      );
    });

    test('redo 净变化：历史栈相应变化（+1）∧ 保存 +1', () {
      editor().submit(AddSegmentLine(at: ten));
      editor().undo();
      final lengthBefore = history().length;
      sink.saved.clear();

      editor().redo();

      expect(history().length, lengthBefore + 1);
      expect(history().canRedo, isFalse);
      expect(sink.saved.length, 1);
      expect(sink.saved.single.annotations?.segmentLines.single.position, ten);
    });

    test('no-op undo/redo（无历史/无可重做）：双 0', () {
      final lengthBefore = history().length;

      editor().undo();
      editor().redo();

      expect(history().length, lengthBefore);
      expect(history().canUndo, isFalse);
      expect(history().canRedo, isFalse);
      expect(sink.saved, isEmpty);
    });
  });

  // 拖动会话收口 1:1 parity（历史 × 保存）已收成跨族参数表：
  // annotation_editor_drag_session_parity_test.dart。

  group('单发路径失败原子性', () {
    test('非法索引提交抛 RangeError：状态/历史/保存干净，后续编辑正常', () {
      editor().submit(AddSegmentLine(at: ten));
      sink.saved.clear();
      final lengthBefore = history().length;
      final canUndoBefore = history().canUndo;
      final timelineBefore = container.read(annotationTimelineProvider);

      expect(
        () => editor().submit(const RemoveSegmentLine(index: 5)),
        throwsRangeError,
      );
      expect(container.read(annotationTimelineProvider), timelineBefore);
      expect(history().length, lengthBefore);
      expect(history().canUndo, canUndoBefore);
      expect(sink.saved, isEmpty);

      editor().submit(ToggleSegmentFlag(index: 0));
      expect(history().length, lengthBefore + 1);
      expect(sink.saved.length, 1);
    });

    test('区间外加线提交 EditNoop：状态/历史/保存干净', () {
      final lengthBefore = history().length;
      final timelineBefore = container.read(annotationTimelineProvider);

      final outcome = editor().submit(
        AddSegmentLine(at: total + const Duration(seconds: 1)),
      );
      expect(outcome, isA<EditNoop>());
      expect(container.read(annotationTimelineProvider), timelineBefore);
      expect(history().length, lengthBefore);
      expect(history().canUndo, isFalse);
      expect(sink.saved, isEmpty);
    });
  });
}
