import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
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
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';

class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 镜像与备注四族的**抓取偏移边界来源**：整体移
/// 记「手指 − 片段起点」、端点拖记「手指 − 被拖端点」。用错边界会让片段在起手
/// 瞬间整段跳一个片段宽——下面每个用例的容差都窄于一个片段宽，因此换错来源
/// 必红。
void main() {
  const total = Duration(minutes: 1);
  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  Future<ProviderContainer> pumpBand({
    required WidgetTester tester,
    required List<LocalMirrorFragment> mirrors,
    required List<NoteSticker> notes,
  }) async {
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
            localMirrorFragments: mirrors,
            notes: notes,
          ),
        );
    await tester.pumpAndSettle();
    return container;
  }

  /// 在全局 [from] 处起手、向右水平拖动 [dx] 像素（分步越过拖动 slop）。
  Future<void> dragFromRight(
    WidgetTester tester,
    Offset from,
    double dx,
  ) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  double xOf(Rect rect, int ms) => bandXOf(
    Duration(milliseconds: ms),
    total: total,
    width: rect.width,
    bandLeft: rect.left,
  );
  double pxFor(Rect rect, int ms) => xOf(rect, ms) - xOf(rect, 0);

  // 拖动 slop（≈18px @ 60s/744px）折合约 1.5s；容差 2500ms 足以吸收它，却
  // 远小于一个 8000ms 片段宽——边界来源若被对调，落点偏差恰是一个片段宽。
  const toleranceMs = 2500;
  const deltaMs = 4000;

  testWidgets('镜像整体移边界来源 = 片段起点：首随手指移动，不跳到片段尾', (tester) async {
    final container = await pumpBand(
      tester: tester,
      mirrors: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      notes: const [],
    );
    final rect = tester.getRect(find.byKey(const Key('track_mirror')));
    // 起手在块体中部（14.5s，离两端命中带都远 → 整体移）。
    await dragFromRight(
      tester,
      Offset(xOf(rect, 14500), rect.center.dy),
      pxFor(rect, deltaMs),
    );
    final f = container.read(localMirrorFragmentsProvider).single;
    // 正确：首 ≈ 8000 + 移动量；错用片段尾作边界：首 ≈ 16000 + 移动量。
    expect(
      f.startMs,
      inInclusiveRange(
        8000 + deltaMs - toleranceMs,
        8000 + deltaMs + toleranceMs,
      ),
      reason: '整体移的抓取偏移锚在片段起点（错锚尾端会整段跳一个片段宽）',
    );
    expect(f.endMs - f.startMs, 8000, reason: '整体平移保持原宽');
    container.dispose();
  });

  testWidgets('镜像端点拖边界来源 = 被拖端点：拖尾端只动尾、不塌到起点', (tester) async {
    final container = await pumpBand(
      tester: tester,
      mirrors: const [LocalMirrorFragment(startMs: 8000, endMs: 16000)],
      notes: const [],
    );
    final rect = tester.getRect(find.byKey(const Key('track_mirror')));
    final endBand = tester
        .getRect(find.byKey(const Key('mirror_fragment_0_edge_end')))
        .center;
    await dragFromRight(
      tester,
      Offset(endBand.dx, rect.center.dy),
      pxFor(rect, deltaMs),
    );
    final f = container.read(localMirrorFragmentsProvider).single;
    expect(f.startMs, 8000, reason: '尾端拖只动尾端');
    // 正确：尾 ≈ 16000 + 移动量；错锚起点：尾 ≈ 8000 + 移动量（≈起点附近）。
    expect(
      f.endMs,
      inInclusiveRange(
        16000 + deltaMs - toleranceMs,
        16000 + deltaMs + toleranceMs,
      ),
      reason: '端点拖的抓取偏移锚在被拖端点（错锚另一端会塌向起点）',
    );
    container.dispose();
  });

  testWidgets('备注整体移边界来源 = 片段起点：首随手指移动，不跳到片段尾', (tester) async {
    final container = await pumpBand(
      tester: tester,
      mirrors: const [],
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await dragFromRight(
      tester,
      Offset(xOf(rect, 14000), rect.center.dy),
      pxFor(rect, deltaMs),
    );
    final note = container.read(noteStickersProvider).single;
    expect(
      note.startMs,
      inInclusiveRange(
        10000 + deltaMs - toleranceMs,
        10000 + deltaMs + toleranceMs,
      ),
      reason: '备注整体移的抓取偏移锚在片段起点（错锚尾端会整段跳一个片段宽）',
    );
    expect(note.endMs - note.startMs, 8000, reason: '整体平移保持原宽');
    container.dispose();
  });

  testWidgets('备注端点拖边界来源 = 被拖端点：拖尾端只动尾、不塌到起点', (tester) async {
    final container = await pumpBand(
      tester: tester,
      mirrors: const [],
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    final endBand = tester
        .getRect(find.byKey(const Key('note_fragment_0_edge_end')))
        .center;
    await dragFromRight(
      tester,
      Offset(endBand.dx, rect.center.dy),
      pxFor(rect, deltaMs),
    );
    final note = container.read(noteStickersProvider).single;
    expect(note.startMs, 10000, reason: '尾端拖只动尾端');
    expect(
      note.endMs,
      inInclusiveRange(
        18000 + deltaMs - toleranceMs,
        18000 + deltaMs + toleranceMs,
      ),
      reason: '端点拖的抓取偏移锚在被拖端点（错锚另一端会塌向起点）',
    );
    container.dispose();
  });
}
