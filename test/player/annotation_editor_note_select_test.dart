import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        noteStickersProvider,
        selectedNoteFragmentIndexProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（净变化断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 备注片段选中模块 seam 直测：单击 = 选中写入标注选中单选槽
///（与局部镜像片段 / 分段线互斥免费）；不改几何、不产生编辑/撤销步；
/// 派生 selected 索引对现势备注数做有效性校验；恢复装载（重开播放页）
/// 不残留。
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

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);
  AnnotationSelection? selection() =>
      container.read(annotationSelectionProvider);
  int? selectedNoteIndex() =>
      container.read(selectedNoteFragmentIndexProvider);
  int historyLength() => container.read(annotationEditHistoryProvider).length;

  void seedNotes() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: 60));
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        notes: const [
          NoteSticker(startMs: 10000, endMs: 18000, text: '甲'),
          NoteSticker(startMs: 30000, endMs: 36000, text: '乙'),
        ],
      ),
    );
  }

  test('tapNoteFragment = 只选中（不改几何、不入史）', () {
    seedNotes();
    final before = container.read(noteStickersProvider);
    domain().select(NoteFragmentSelection(1));
    expect(selection(), isA<NoteFragmentSelection>());
    expect(selectedNoteIndex(), 1);
    expect(container.read(noteStickersProvider), before,
        reason: '选中不改几何');
    expect(historyLength(), 0, reason: '选中不产生编辑/撤销步');
  });

  test('选中异类（分段线）后备注派生 selected 为 null（共用单选槽）', () {
    seedNotes();
    domain().select(NoteFragmentSelection(0));
    expect(selectedNoteIndex(), 0);
    editor().submit(AddSegmentLine(at: const Duration(seconds: 4)));
    domain().select(SegmentLineSelection(0));
    expect(selectedNoteIndex(), isNull);
    expect(selection(), isA<SegmentLineSelection>());
  });

  test('重开播放页（全复位）后选中不残留', () {
    seedNotes();
    domain().select(NoteFragmentSelection(0));
    expect(selectedNoteIndex(), 0);
    editor().resetForVideo(total);
    expect(selectedNoteIndex(), isNull);
  });

  test('删除备注后选中整清：不落到下一条上', () {
    seedNotes();
    domain().select(NoteFragmentSelection(0));
    expect(selectedNoteIndex(), 0);

    editor().submit(RemoveNote(index: 0));

    // 删完还剩一条（原索引 1）：选中必须是 null——只按索引越界判定的话，
    // 索引 0 会"顺手"指到那一条上，选中框 / 内容浮条 / 端点柄跟着搬家。
    expect(container.read(noteStickersProvider), hasLength(1));
    expect(selection(), isNull);
    expect(selectedNoteIndex(), isNull);
  });
}
