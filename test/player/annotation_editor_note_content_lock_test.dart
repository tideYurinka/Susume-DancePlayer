import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录 diff 的假保存编排（备注臂断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final diffs = <AnnotationSectionDiff>[];

  @override
  void save(AnnotationSectionDiff diff) => diffs.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「内容锁字段与模块门禁」模块写缝直测：内容锁只护
/// 几何——整体移 / 端点拖 / 贴纸几何在目标备注已锁时被模块拒绝并弹对应
/// 提示（同族「备注已锁定」提示，不动「已锁定分段」提示）；文本 / 样式 /
/// 锁定开关豁免；与全局「锁定分段」并存、两套门禁各自独立生效；锁定
/// 开关入史、随备注臂保存。
void main() {
  const total = Duration(minutes: 1);

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

  List<NoteSticker> notes() => container.read(noteStickersProvider);

  int historyLength() => container.read(annotationEditHistoryProvider).length;

  int layoutPromptSeq() =>
      container.read(noticeTriggerProvider(NoticeId.layoutLock));

  int contentPromptSeq() =>
      container.read(noticeTriggerProvider(NoticeId.noteContentLock));

  void restore({List<NoteSticker> notes = const []}) {
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        notes: notes,
      ),
    );
  }

  group('几何类命令在备注已锁时被拒', () {
    test('整体移：EditLocked、时间窗不动、不入史、内容锁提示触发一次', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 20000)),
      );
      expect(outcome, isA<EditLocked>());
      expect(notes(), const [
        NoteSticker(startMs: 10000, endMs: 18000, locked: true),
      ]);
      expect(historyLength(), 0);
      expect(contentPromptSeq(), 1);
      expect(layoutPromptSeq(), 0);
    });

    test('端点拖：EditLocked、时间窗不动', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      final outcome = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(milliseconds: 24000),
        ),
      );
      expect(outcome, isA<EditLocked>());
      expect(notes(), const [
        NoteSticker(startMs: 10000, endMs: 18000, locked: true),
      ]);
      expect(contentPromptSeq(), 1);
    });

    test('贴纸几何：EditLocked、几何不动', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      final outcome = editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.8, centerY: 0.6, scale: 2.5),
        ),
      );
      expect(outcome, isA<EditLocked>());
      expect(notes().single.geometry, const NoteGeometry());
      expect(contentPromptSeq(), 1);
    });

    test('拖动会话逐帧：已锁备注 moveTo 返回空、状态不动', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      final session = editor().beginNoteMoveDrag(0);
      expect(session.moveTo(const Duration(milliseconds: 20000)), isNull);
      expect(contentPromptSeq(), 1);
      session.end();
      expect(historyLength(), 0);
      expect(notes().single.startMs, 10000);
    });

    test('字段级：只锁目标备注，未锁备注几何照常', () {
      restore(
        notes: const [
          NoteSticker(startMs: 10000, endMs: 18000, locked: true),
          NoteSticker(startMs: 30000, endMs: 38000),
        ],
      );
      final outcome = editor().submit(
        const MoveNote(index: 1, to: Duration(milliseconds: 40000)),
      );
      expect(outcome.applied, isTrue);
      expect(notes()[1].startMs, 40000);
      expect(contentPromptSeq(), 0);
    });
  });

  group('豁免：文本 / 样式 / 锁定开关不受内容锁影响', () {
    test('已锁备注的文本照常编辑（入史一步）', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      final outcome = editor().submit(SetNoteText(index: 0, text: '这里注意手'));
      expect(outcome.applied, isTrue);
      expect(notes().single.text, '这里注意手');
      expect(notes().single.locked, isTrue);
      expect(historyLength(), 1);
      expect(contentPromptSeq(), 0);
    });

    test('锁定开关解锁后几何命令照常生效', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      expect(editor().submit(ToggleNoteLock(index: 0)).applied, isTrue);
      expect(notes().single.locked, isFalse);
      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 20000)),
      );
      expect(outcome.applied, isTrue);
      expect(notes().single.startMs, 20000);
      expect(contentPromptSeq(), 0);
      expect(historyLength(), 2);
    });

    test('锁定开关本身也受锁后不被内容锁挡：锁定未锁备注照常', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      expect(editor().submit(ToggleNoteLock(index: 0)).applied, isTrue);
      expect(notes().single.locked, isTrue);
    });

    test('锁定开关一次提交一个撤销步，撤销恢复原锁定态', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      editor().submit(ToggleNoteLock(index: 0));
      expect(historyLength(), 1);
      editor().undo();
      expect(notes().single.locked, isFalse);
    });
  });

  group('与全局「锁定分段」并存', () {
    test('锁定分段开启不挡备注几何（锁只护分段结构，不再弹布局提示）', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      container.read(layoutLockedProvider.notifier).toggle();
      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 20000)),
      );
      expect(outcome.applied, isTrue);
      expect(layoutPromptSeq(), 0);
      expect(contentPromptSeq(), 0);
    });

    test('锁定分段开启时已锁备注的锁定开关仍豁免', () {
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
      );
      container.read(layoutLockedProvider.notifier).toggle();
      expect(editor().submit(ToggleNoteLock(index: 0)).applied, isTrue);
      expect(notes().single.locked, isFalse);
      expect(layoutPromptSeq(), 0);
      expect(contentPromptSeq(), 0);
    });
  });

  test('锁定态随备注臂入队保存（重开后状态一致）', () {
    restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
    editor().submit(ToggleNoteLock(index: 0));
    final diff = sink.diffs.last;
    expect(diff.notes, isNotNull);
    expect(diff.notes!.single.locked, isTrue);
  });
}
