import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditorProvider,
        annotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 对比-控制层标注工具区三 verb 的标注编辑模块直测：熟练度、重点、
/// 删除各自一次提交 = 一次标注编辑（单步可撤销、写点经唯一写路径）。纯
/// 容器直测，不启动 widget 环境。
void main() {
  group('对比态工具三 verb（模块直测）', () {
    late ProviderContainer container;
    late AnnotationEditor editor;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(
            FakePlaybackEngine(duration: const Duration(minutes: 1)),
          ),
        ],
      );
      editor = container.read(annotationEditorProvider);
      // 一条分段线 → 两个学习段（删除 verb 的作用对象与段序归属前提）。
      editor.submit(AddSegmentLine(at: const Duration(seconds: 30)));
    });

    tearDown(() => container.dispose());

    test('熟练度 verb：一次提交设档、单步撤销还原', () {
      final outcome = editor.submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.learning),
      );
      expect(outcome, isA<EditApplied>());
      expect(container.read(learningMasteryProvider), const {
        0: LearningMastery.learning,
      });

      editor.undo();
      expect(container.read(learningMasteryProvider), isEmpty);
    });

    test('重点 verb：一次提交切换星标、单步撤销还原', () {
      final outcome = editor.submit(ToggleSegmentEmphasis(order: 1));
      expect(outcome, isA<EditApplied>());
      expect(container.read(learningEmphasisProvider), const {1});

      editor.undo();
      expect(container.read(learningEmphasisProvider), isEmpty);
    });

    test('删除 verb：一次提交删线、单步撤销恢复线与段属性', () {
      editor.submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.mastered),
      );
      final outcome = editor.submit(RemoveSegmentLine(index: 0));
      expect(outcome, isA<EditApplied>());
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);

      editor.undo();
      expect(container.read(annotationTimelineProvider).segmentLines.length, 1);
      expect(container.read(learningMasteryProvider), const {
        1: LearningMastery.mastered,
      });
    });
  });
}
