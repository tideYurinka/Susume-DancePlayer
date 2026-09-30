import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        layoutLockedProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';

class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「长按片段锁定 / 解锁」widget 缝直测：长按
/// 备注轨片段经共用件解析命中（与单击同一条路径）即取反该备注的内容锁
/// ——经标注编辑模块提交（入撤销史、豁免锁定分段）；再长按解锁；长按
/// 轨道空白无动作。
void main() {
  const total = Duration(minutes: 1);

  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  /// 泵出一个带就绪节拍网格 + 备注片段的 TrackBand。
  Future<ProviderContainer> pumpBandWithNotes({
    required WidgetTester tester,
    required List<NoteSticker> notes,
    bool layoutLocked = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) => uniformReadyBeatState(seconds: total.inMilliseconds / 1000),
        ),
      ],
    );
    if (layoutLocked) {
      container.read(layoutLockedProvider.notifier).replace(true);
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: buildTrackBandSession(
                  engine: engine,
                  container: container,
                ),
                rowTable: TrackRowTable.normal,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            timeline: AnnotationTimeline.wholeVideo(total),
            notes: notes,
          ),
        );
    await tester.pumpAndSettle();
    return container;
  }

  double xOf(Rect rect, int ms) =>
      rect.left + rect.width * ms / total.inMilliseconds;

  testWidgets('长按备注片段锁定该备注', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.longPressAt(Offset(xOf(rect, 14000), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteStickersProvider).single.locked, isTrue);
    container.dispose();
  });

  testWidgets('已锁定片段再长按解锁', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(startMs: 10000, endMs: 18000, locked: true),
      ],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.longPressAt(Offset(xOf(rect, 14000), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteStickersProvider).single.locked, isFalse);
    container.dispose();
  });

  testWidgets('长按轨道空白无动作', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.longPressAt(Offset(xOf(rect, 40000), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteStickersProvider).single.locked, isFalse);
    container.dispose();
  });

  testWidgets('锁定开关入撤销史：锁定后撤销恢复未锁', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.longPressAt(Offset(xOf(rect, 14000), rect.center.dy));
    await tester.pumpAndSettle();
    container.read(annotationEditorProvider).undo();
    await tester.pumpAndSettle();
    expect(container.read(noteStickersProvider).single.locked, isFalse);
    container.dispose();
  });

  testWidgets('锁定分段开启时长按照常切换（豁免锁定分段门禁）', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
      layoutLocked: true,
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.longPressAt(Offset(xOf(rect, 14000), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteStickersProvider).single.locked, isTrue);
    container.dispose();
  });
}
