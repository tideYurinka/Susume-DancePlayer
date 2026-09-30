import 'package:dance_learning_app/annotation/annotation_timeline.dart'
    show AnnotationTimeline;
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
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/notice.dart' show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
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

/// 门禁第二原因「对比态只读」的模块直测：
/// ProviderContainer 直测模块 interface，仿 annotation_editor_lock_gate_test
/// 模板。
///
/// 验收：对比态下逐 verb（分段线 / 半拍线 / 首尾 / 备注片段 / 局部镜像
/// 片段 / 八拍锚点，含自动分段/清空/节拍对齐等几何族）被拒且**静默**（不
/// 弹任何提示）、不入史、不入盘；豁免 verb（熟练度/重点/flag/备注文本/
/// 备注锁开关）照常；非对比态逐 verb 行为不变。无第二张平行动词表——
/// 受拦 verb 集与用户锁逐 verb 声明同源（同一份门禁原因声明）。
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
  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

  void enterCompare({PlayerSessionMode mode = PlayerSessionMode.compareEditing}) =>
      container.read(playerSessionProvider.notifier).enter(mode);

  void seedLines() {
    editor().submit(AddSegmentLine(at: ten));
    editor().submit(AddSegmentLine(at: twenty));
    editor().submit(AddHalfBeatLine(at: const Duration(seconds: 5)));
    sink.diffs.clear();
  }

  void seedNote() {
    editor().restoreDocument(
      const AnnotationRestoreDocument(notes: [
        NoteSticker(startMs: 1000, endMs: 9000, text: '手'),
      ]),
    );
  }

  group('对比态下几何 verb 全部被拒（静默、不入史、不入盘）', () {
    for (final (name, command) in <(String, AnnotationEdit)>[
      ('加分段线', AddSegmentLine(at: Duration(seconds: 15))),
      ('移分段线', MoveSegmentLine(index: 0, to: Duration(seconds: 15))),
      ('删分段线', RemoveSegmentLine(index: 0)),
      ('加半拍线', AddHalfBeatLine(at: Duration(seconds: 15))),
      ('移半拍线', MoveHalfBeatLine(index: 0, to: Duration(seconds: 15))),
      ('删半拍线', RemoveHalfBeatLine(index: 0)),
      ('首尾边界调整', SetVideoRange(start: Duration(seconds: 5))),
      ('自动分段', AutoSegment(
          start: Duration.zero,
          end: total,
          cuts: const [Duration(seconds: 15)],
        )),
      ('清空分段', ClearSegmentLines()),
      ('节拍对齐应用', ApplyBeatShift(
          delta: const Duration(milliseconds: 100),
          shiftSeconds: 0.1,
        )),
      ('落八拍锚点', AddEightBeatAnchor(at: Duration(seconds: 15))),
      ('删八拍锚点', RemoveEightBeatAnchor(at: Duration(seconds: 15))),
      ('清空八拍锚点', ClearEightBeatAnchors()),
      ('插备注片段', InsertNote(at: Duration(seconds: 30))),
      ('移备注片段', MoveNote(index: 0, to: Duration(seconds: 30))),
      ('备注端点拖', DragNoteEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(seconds: 30),
        )),
      ('备注贴纸几何', SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.6, centerY: 0.4, scale: 1.2),
        )),
      ('删备注片段', RemoveNote(index: 0)),
      ('加局部镜像片段', AddLocalMirrorFragment(at: Duration(seconds: 30))),
      ('删局部镜像片段', RemoveLocalMirrorFragment(index: 0)),
      ('移局部镜像片段', MoveLocalMirrorFragment(
          index: 0,
          to: Duration(seconds: 30),
        )),
      ('局部镜像端点拖', DragLocalMirrorFragmentEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(seconds: 30),
        )),
    ]) {
      test('对比-控制层：$name 被拒，不弹提示、不入史、不入盘', () {
        seedLines();
        seedNote();
        enterCompare();
        final historyBefore = container
            .read(annotationEditHistoryProvider)
            .length;
        final lockPromptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
        final contentLockPromptBefore = container
            .read(noticeTriggerProvider(NoticeId.noteContentLock));

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
        // 静默：对比态不是「锁」，不弹「已锁定分段」也不弹「备注已锁定」。
        expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), lockPromptBefore,
            reason: name);
        expect(
          container.read(noticeTriggerProvider(NoticeId.noteContentLock)),
          contentLockPromptBefore,
          reason: name,
        );
      });
    }

    test('对比-播放态同样只读（带级：模式 ∈ 对比态即只读）', () {
      seedLines();
      enterCompare(mode: PlayerSessionMode.compareWatching);
      final outcome = editor().submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
      );
      expect(outcome, isA<EditLocked>());
      expect(sink.diffs, isEmpty);
    });

    test('拒绝后状态未动：线位置保持，历史一位不动', () {
      seedLines();
      enterCompare();
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;
      editor().submit(MoveSegmentLine(index: 0, to: const Duration(seconds: 15)));
      expect(timeline().segmentLines.map((l) => l.position), [ten, twenty]);
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore,
      );
    });

    test('无第二张平行动词表：同一 verb 用户锁与对比只读共用一份声明', () {
      // 锁定分段 + 对比态同时成立时，用户锁先拒且弹「已锁定分段」提示
      // （门禁次序：用户锁 → 内容锁 → 对比只读）。
      seedLines();
      container.read(layoutLockedProvider.notifier).toggle();
      enterCompare();
      final promptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      final outcome = editor().submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
      );
      expect(outcome, isA<EditLocked>());
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore + 1);
    });
  });

  group('对比态豁免 verb 照常（只读只拦几何，不拦属性与写字）', () {
    test('熟练度 / 重点 / flag 在对比态照常生效并入史', () {
      seedLines();
      enterCompare();
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;

      expect(
        editor().submit(
          SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
        ),
        isA<EditApplied>(),
      );
      expect(
        editor().submit(ToggleSegmentEmphasis(order: 0)),
        isA<EditApplied>(),
      );
      expect(
        editor().submit(ToggleSegmentFlag(index: 0)),
        isA<EditApplied>(),
      );
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore + 3,
      );
      expect(sink.diffs, isNotEmpty);
    });

    test('备注文本与备注锁开关在对比态照常（不改备注文本编辑链路）', () {
      seedNote();
      enterCompare();
      expect(
        editor().submit(SetNoteText(index: 0, text: '改字')),
        isA<EditApplied>(),
      );
      expect(
        editor().submit(ToggleNoteLock(index: 0)),
        isA<EditApplied>(),
      );
      expect(container.read(noteStickersProvider)[0].text, '改字');
      expect(container.read(noteStickersProvider)[0].locked, isTrue);
    });
  });

  group('非对比态行为逐位不变（回归护栏）', () {
    test('观看态/编辑态下同一几何 verb 照常生效', () {
      seedLines();
      expect(
        editor().submit(MoveSegmentLine(index: 0, to: const Duration(seconds: 15))),
        isA<EditApplied>(),
      );
      expect(timeline().segmentLines.first.position,
          const Duration(seconds: 15));
      expect(sink.diffs, isNotEmpty);
    });
  });
}
