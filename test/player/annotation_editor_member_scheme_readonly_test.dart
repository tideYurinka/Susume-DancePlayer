import 'package:dance_learning_app/annotation/learning_segment_attributes.dart'
    show LearningMastery;
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/annotation/note_sticker.dart'
    show NoteGeometry, NoteSticker;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        AnnotationGestureTarget,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationMemberSchemeReadonlyProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        noteStickersProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录 diff 的假保存编排（编辑器 → sink 链路断言用）。
class RecordingSink implements AnnotationSaveSink {
  final diffs = <AnnotationSectionDiff>[];

  @override
  void save(AnnotationSectionDiff diff) => diffs.add(diff);

  @override
  Future<void> flush() async {}
}

/// 门禁第三原因「组员方案只读」的模块直测：
/// ProviderContainer 直测模块 interface，仿 annotation_editor_compare_readonly_test
/// 模板（同一份逐 verb 声明，不建第二张平行动词表）。
///
/// 验收：装载组员方案时一切几何与文本改动（含熟练度/重点/flag/备注文本/
/// 备注锁开关）被拒且**静默**（不弹任何提示）、不入史、不入盘；点选照常，
/// 而写我落盘状态的激活学习段被拒、不落盘的临时衔接段照常可用；未装载
/// 组员方案时逐 verb 行为不变。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late RecordingSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSink();
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
  dynamic timeline() => container.read(annotationTimelineProvider);

  void loadMemberScheme() => container
      .read(annotationMemberSchemeReadonlyProvider.notifier)
      .setLoaded(true);

  void seedLines() {
    editor().submit(AddSegmentLine(at: ten));
    editor().submit(AddSegmentLine(at: twenty));
    editor().submit(AddHalfBeatLine(at: const Duration(seconds: 5)));
    sink.diffs.clear();
  }

  void seedNote() {
    editor().restoreDocument(
      const AnnotationRestoreDocument(
        notes: [NoteSticker(startMs: 1000, endMs: 9000, text: '手')],
      ),
    );
  }

  group('装载组员方案时几何与文本 verb 全部被拒（静默、不入史、不入盘）', () {
    for (final (name, command) in <(String, AnnotationEdit)>[
      ('加分段线', AddSegmentLine(at: Duration(seconds: 15))),
      ('移分段线', MoveSegmentLine(index: 0, to: Duration(seconds: 15))),
      ('删分段线', RemoveSegmentLine(index: 0)),
      ('加半拍线', AddHalfBeatLine(at: Duration(seconds: 15))),
      ('移半拍线', MoveHalfBeatLine(index: 0, to: Duration(seconds: 15))),
      ('删半拍线', RemoveHalfBeatLine(index: 0)),
      ('首尾边界调整', SetVideoRange(start: Duration(seconds: 5))),
      (
        '自动分段',
        AutoSegment(
          start: Duration.zero,
          end: total,
          cuts: const [Duration(seconds: 15)],
        ),
      ),
      ('清空分段', ClearSegmentLines()),
      (
        '节拍对齐应用',
        ApplyBeatShift(
          delta: const Duration(milliseconds: 100),
          shiftSeconds: 0.1,
        ),
      ),
      ('落八拍锚点', AddEightBeatAnchor(at: Duration(seconds: 15))),
      ('删八拍锚点', RemoveEightBeatAnchor(at: Duration(seconds: 15))),
      ('清空八拍锚点', ClearEightBeatAnchors()),
      ('插备注片段', InsertNote(at: Duration(seconds: 30))),
      ('移备注片段', MoveNote(index: 0, to: Duration(seconds: 30))),
      (
        '备注端点拖',
        DragNoteEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(seconds: 30),
        ),
      ),
      (
        '备注贴纸几何',
        SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.6, centerY: 0.4, scale: 1.2),
        ),
      ),
      ('删备注片段', RemoveNote(index: 0)),
      ('加局部镜像片段', AddLocalMirrorFragment(at: Duration(seconds: 30))),
      ('删局部镜像片段', RemoveLocalMirrorFragment(index: 0)),
      ('移局部镜像片段', MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 30))),
      (
        '局部镜像端点拖',
        DragLocalMirrorFragmentEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(seconds: 30),
        ),
      ),
    ]) {
      test('组员方案只读下 $name 被拒，不弹提示、不入史、不入盘', () {
        seedLines();
        seedNote();
        loadMemberScheme();
        final historyBefore = container
            .read(annotationEditHistoryProvider)
            .length;
        final lockPromptBefore = container.read(
          noticeTriggerProvider(NoticeId.layoutLock),
        );
        final contentLockPromptBefore = container.read(
          noticeTriggerProvider(NoticeId.noteContentLock),
        );

        final outcome = editor().submit(command);

        expect(outcome, isA<EditLocked>(), reason: name);
        expect(outcome.applied, isFalse, reason: name);
        expect(outcome.geometryChanged, isFalse, reason: name);
        expect(
          container.read(annotationEditHistoryProvider).length,
          historyBefore,
          reason: name,
        );
        expect(sink.diffs, isEmpty, reason: name);
        // 静默：与对比态只读同款，不弹「已锁定分段」也不弹「备注已锁定」。
        expect(
          container.read(noticeTriggerProvider(NoticeId.layoutLock)),
          lockPromptBefore,
          reason: name,
        );
        expect(
          container.read(noticeTriggerProvider(NoticeId.noteContentLock)),
          contentLockPromptBefore,
          reason: name,
        );
      });
    }

    test('文本与 flag/熟练度/重点/备注锁开关同样被拒（组员方案一个字不能改）', () {
      seedLines();
      seedNote();
      loadMemberScheme();
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;

      expect(
        editor().submit(
          SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
        ),
        isA<EditLocked>(),
      );
      expect(
        editor().submit(ToggleSegmentEmphasis(order: 0)),
        isA<EditLocked>(),
      );
      expect(editor().submit(ToggleSegmentFlag(index: 0)), isA<EditLocked>());
      expect(
        editor().submit(SetNoteText(index: 0, text: '改字')),
        isA<EditLocked>(),
      );
      expect(editor().submit(ToggleNoteLock(index: 0)), isA<EditLocked>());

      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore,
      );
      expect(sink.diffs, isEmpty);
      expect(container.read(noteStickersProvider)[0].text, '手');
      expect(container.read(noteStickersProvider)[0].locked, isFalse);
    });

    test('拒绝无副作用：线位置保持、状态未动', () {
      seedLines();
      loadMemberScheme();
      editor().submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
      );
      expect(timeline().segmentLines.map((l) => l.position), [ten, twenty]);
    });

    test('无第二张平行动词表：用户锁与组员方案只读同时成立时用户锁先拒并弹提示', () {
      seedLines();
      container.read(layoutLockedProvider.notifier).toggle();
      loadMemberScheme();
      final promptBefore = container.read(
        noticeTriggerProvider(NoticeId.layoutLock),
      );
      final outcome = editor().submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
      );
      expect(outcome, isA<EditLocked>());
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        promptBefore + 1,
      );
    });
  });

  group('装载组员方案时点选照常、持久化激活被拒、临时衔接段可用', () {
    test('激活学习段被拒（我的落盘状态不被这次查看改动）', () {
      seedLines();
      loadMemberScheme();
      domain().toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      domain().selectOnly(0);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      // 被拒即静默：不写盘、不弹提示。
      expect(sink.diffs, isEmpty);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('点选照常', () {
      seedLines();
      loadMemberScheme();
      domain().select(SegmentLineSelection(0));
      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>(),
      );
    });

    test('不落盘的临时衔接段照常可用', () {
      seedLines();
      loadMemberScheme();
      editor().toggleTransitionSegment(0);
      expect(container.read(transitionSegmentProvider), isNotNull);
    });
  });

  group('未装载组员方案行为逐位不变（回归护栏）', () {
    test('同一几何 verb 照常生效', () {
      seedLines();
      expect(
        editor().submit(
          MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
        ),
        isA<EditApplied>(),
      );
      expect(sink.diffs, isNotEmpty);
    });

    test('手势起手判定：几何族目标被拒、点选目标不拒', () {
      loadMemberScheme();
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.segmentLineMove),
        isTrue,
      );
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.segmentLineTap),
        isFalse,
      );
      expect(
        editor().gestureStartRejected(AnnotationGestureTarget.learningTrackTap),
        isFalse,
      );
    });
  });
}
