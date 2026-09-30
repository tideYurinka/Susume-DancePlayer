import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/notice.dart' show NoticeId, noticeTriggerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（备注臂入队断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「文本命令」模块写缝直测（起载荷 = 新文本本身——
/// 模块不解析点名、不读名册、不存引用）：文本命令写定新文本；入撤销史、
/// 豁免「锁定分段」门禁（只护几何，不挡写字）；`geometryChanged` 恒假
/// （不改学习段几何）。
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

  /// 造一条既有备注（非锁定，起点 10s 窗宽 4s）。
  void seedNote() {
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        notes: const [NoteSticker(startMs: 10000, endMs: 14000)],
      ),
    );
  }

  group('文本命令：写定文本、单步入史、豁免锁定分段门禁', () {
    test('提交生效：文本写定、geometryChanged 恒假、单步入史、notes 段入队', () {
      seedNote();

      final outcome = editor().submit(SetNoteText(index: 0, text: '这里注意手'));
      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse);
      expect(notes().single.text, '这里注意手');
      expect(container.read(annotationEditHistoryProvider).length, 1);
      expect(sink.saved.single.notes?.single.text, '这里注意手');
      expect(sink.saved.single.annotations, isNull);
    });

    test('锁定分段开启 → 文本命令豁免门禁：照常生效、不弹「已锁定分段」', () {
      seedNote();
      container.read(layoutLockedProvider.notifier).toggle();
      sink.saved.clear();

      final outcome = editor().submit(SetNoteText(index: 0, text: '锁定也能写字'));
      expect(outcome, isA<EditApplied>());
      expect(notes().single.text, '锁定也能写字');
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        0,
        reason: '豁免 verb 不触发锁定提示',
      );
    });

    test('同文本提交 = EditNoop：不入史、不入队', () {
      seedNote();
      editor().submit(SetNoteText(index: 0, text: '同样的话'));
      sink.saved.clear();

      final outcome = editor().submit(SetNoteText(index: 0, text: '同样的话'));
      expect(outcome.applied, isFalse);
      expect(container.read(annotationEditHistoryProvider).length, 1);
      expect(sink.saved, isEmpty);
    });

    test('undo 回退文本、redo 重放', () {
      seedNote();
      editor().submit(SetNoteText(index: 0, text: '改后'));
      editor().undo();
      expect(notes().single.text, '');
      editor().redo();
      expect(notes().single.text, '改后');
    });

    test('索引越界抛 RangeError（与其它按索引 verb 一致）', () {
      seedNote();
      expect(
        () => editor().submit(SetNoteText(index: 3, text: '越界')),
        throwsRangeError,
      );
    });
  });
}
