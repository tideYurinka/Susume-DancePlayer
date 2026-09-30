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
        annotationSaveSinkProvider;
import 'package:dance_learning_app/player/note_editor.dart'
    show noteFragmentHighlightProvider;
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

/// 「左下跳转」的定位高亮 widget 缝直测：高亮
/// 供打在对应备注片段上；片段被点按 / 拖动起手即清（用户已到位）。
void main() {
  const total = Duration(minutes: 1);

  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  /// 泵出一个带两条备注片段的 TrackBand，返回容器。
  Future<ProviderContainer> pumpBandWithNotes(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) =>
              uniformReadyBeatState(seconds: total.inMilliseconds / 1000),
        ),
      ],
    );
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
            notes: const [
              NoteSticker(startMs: 10000, endMs: 18000),
              NoteSticker(startMs: 30000, endMs: 36000),
            ],
          ),
        );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('默认无高亮；打高亮后对应片段出现高亮标识、另一片段没有',
      (tester) async {
    final container = await pumpBandWithNotes(tester);
    expect(find.byKey(const Key('note_fragment_highlight')), findsNothing);
    container
        .read(noteFragmentHighlightProvider.notifier)
        .highlight(30000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note_fragment_highlight')), findsOneWidget);
    container.dispose();
  });

  testWidgets('高亮只认起点匹配的备注；备注消失即无高亮', (tester) async {
    final container = await pumpBandWithNotes(tester);
    container
        .read(noteFragmentHighlightProvider.notifier)
        .highlight(99999);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note_fragment_highlight')), findsNothing);
    container.dispose();
  });

  testWidgets('点按备注片段后高亮清除（用户已到位）', (tester) async {
    final container = await pumpBandWithNotes(tester);
    container
        .read(noteFragmentHighlightProvider.notifier)
        .highlight(10000);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note_fragment_highlight')), findsOneWidget);
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(
      rect.left + rect.width * 14000 / total.inMilliseconds,
      rect.center.dy,
    ));
    await tester.pumpAndSettle();
    expect(
      container.read(noteFragmentHighlightProvider),
      isNull,
      reason: '片段交互即清除高亮',
    );
    container.dispose();
  });
}
