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

/// 备注删除命令模块写缝直测：删除命令受锁定分段门禁（删属几何类）、
/// 单步为一个撤销步；
/// `geometryChanged` 恒假（不改学习段几何）。
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

  group('删除命令：备注消失、单步入史、受锁定分段门禁', () {
    test('提交生效：备注消失、geometryChanged 恒假、单步入史、notes 段入队', () {
      seedNote();

      final outcome = editor().submit(RemoveNote(index: 0));
      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse);
      expect(notes(), isEmpty);
      expect(container.read(annotationEditHistoryProvider).length, 1);
      expect(sink.saved.single.notes, isEmpty);
      expect(sink.saved.single.annotations, isNull);
    });

    test('锁定分段开启 → 删除照常（锁只护分段结构，不弹锁提示）', () {
      seedNote();
      container.read(layoutLockedProvider.notifier).toggle();

      final outcome = editor().submit(RemoveNote(index: 0));
      expect(outcome.applied, isTrue);
      expect(notes(), isEmpty);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('undo 恢复备注、redo 再删', () {
      seedNote();
      editor().submit(RemoveNote(index: 0));
      editor().undo();
      expect(notes().single.startMs, 10000);
      expect(notes().single.endMs, 14000);
      editor().redo();
      expect(notes(), isEmpty);
    });

    test('索引越界抛 RangeError（与其它按索引 verb 一致）', () {
      seedNote();
      expect(() => editor().submit(RemoveNote(index: 3)), throwsRangeError);
    });
  });

  group('样式命令退场', () {
    test('模块不再有样式提交入口：InsertNote 创建的备注只有几何与文本', () {
      editor().submit(const InsertNote(at: Duration(seconds: 10)));
      // 样式无字段可存：正文恒白、描边按底色派生都是渲染期派生值。
      expect(notes().single.text, '');
      expect(notes().single.locked, isFalse);
    });
  });
}
