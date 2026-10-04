import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationSelectionDomainProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 记录型保存 sink（激活写入点断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 激活学习段落盘：激活集合经保存编排落 local `session` 段
/// 的 `activatedSegments` 字段——与熟练度同段、不同写入路径，各自读现
/// 值组完整段值、互不覆盖；用户路径（点选/步进激活/越出取消/临时段互
/// 斥清）入队，恢复装载与换视频复位路径不入队（恢复语义不变、不写错
/// 视频的文件）。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const thirty = Duration(seconds: 30);

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

  /// 建出 3 个学习段（两条分段线）并清空由此产生的保存记录。
  void givenThreeSegments() {
    editor().submit(AddSegmentLine(at: ten));
    editor().submit(AddSegmentLine(at: thirty));
    sink.saved.clear();
  }

  group('用户路径激活变更入队（session 段绝对终值）', () {
    test('点选激活段：diff 只带 session 段（熟练度现值 + 激活终值）', () {
      givenThreeSegments();

      domain().toggleLearningSegment(1);

      final session = sink.saved.single.session;
      expect(session?.activatedSegments, const [1]);
      expect(session?.mastery, isEmpty);
      expect(sink.saved.single.annotations, isNull);
      expect(sink.saved.single.corrections, isNull);
    });

    test('激活写入携带熟练度现值（同段不同写入路径互不覆盖）', () {
      givenThreeSegments();
      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );
      sink.saved.clear();

      domain().toggleLearningSegment(1);

      expect(sink.saved.single.session?.mastery, {0: LearningMastery.mastered});
    });

    test('熟练度编辑的 session diff 携带激活现值（反向不覆盖）', () {
      givenThreeSegments();
      domain().toggleLearningSegment(1);
      sink.saved.clear();

      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );

      expect(sink.saved.single.session?.activatedSegments, const [1]);
    });

    test('点选替换、再点取消：diff 携带每次终值', () {
      givenThreeSegments();

      domain().toggleLearningSegment(0);
      expect(sink.saved.last.session?.activatedSegments, const [0]);

      domain().toggleLearningSegment(1);
      expect(sink.saved.last.session?.activatedSegments, const [1]);

      domain().toggleLearningSegment(1);
      expect(sink.saved.last.session?.activatedSegments, isEmpty);
    });

    test('步进倍速「只激活该段」替换现有激活并入队', () {
      givenThreeSegments();
      domain().toggleLearningSegment(0);
      sink.saved.clear();

      domain().selectOnly(2);

      expect(sink.saved.single.session?.activatedSegments, const [2]);
    });

    test('seek 越出激活范围取消激活：清空值入队', () {
      givenThreeSegments();
      domain().toggleLearningSegment(0);
      sink.saved.clear();

      container
          .read(annotationSelectionDomainProvider)
          .clearLearningSegmentsIfOutside(thirty);

      expect(sink.saved.single.session?.activatedSegments, isEmpty);
    });

    test('无激活时越出判定与清空复位不入队（无变化不写盘）', () {
      givenThreeSegments();
      editor().clearForVideoRestore();
      expect(sink.saved, isEmpty);

      container
          .read(annotationSelectionDomainProvider)
          .clearLearningSegmentsIfOutside(thirty);
      expect(sink.saved, isEmpty);
    });
  });

  group('恢复与换视频路径不入队（恢复语义不变）', () {
    test('恢复装载不触发保存', () {
      givenThreeSegments();

      editor().restoreDocument(
        AnnotationRestoreDocument(activatedSegments: const {1}),
      );

      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(sink.saved, isEmpty);
    });

    test('恢复前清不触发保存', () {
      givenThreeSegments();
      domain().toggleLearningSegment(1);
      sink.saved.clear();

      editor().clearForVideoRestore();

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(sink.saved, isEmpty);
    });

    test('换视频兜底复位不触发保存', () {
      givenThreeSegments();
      domain().toggleLearningSegment(1);
      sink.saved.clear();

      editor().resetForVideo(total);

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(sink.saved, isEmpty);
    });
  });

  test('行为验收：激活 → flush（退出播放器）→ 重开读到激活仍在', () async {
    final inner = InMemoryVideoDocumentStorage();
    final orchestrator = AnnotationSaveOrchestrator(
      coordinator: VideoDocumentCoordinator(inner),
    );
    final behaviorContainer = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(orchestrator),
      ],
    );
    addTearDown(behaviorContainer.dispose);

    behaviorContainer
        .read(annotationEditorProvider)
        .submit(AddSegmentLine(at: ten));
    behaviorContainer
        .read(annotationSelectionDomainProvider)
        .toggleLearningSegment(0);

    // 退出播放器 = flush 强制落盘（burst 窗口未到期同样落定）。
    await orchestrator.flush();

    // 重开 = 从盘上 local 文件读回。
    final reopened = LocalDocument.fromJson(inner.localSnapshot);
    expect(reopened.activatedSegments, const [0]);
    expect(reopened.mastery, isEmpty);
  });
}
