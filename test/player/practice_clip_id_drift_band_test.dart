import 'dart:ui' as ui;

import 'package:dance_learning_app/annotation/annotation_timeline.dart'
    show AnnotationTimeline;
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationTimelineProvider, practiceClipsProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/device_viewport.dart';

/// 轨道带部件测试：片段截取拖动起手的作用对象
/// 不因表变化而漂移——起手之后另一条片段被外部写（素材连带删除）移出轨道，
/// 拖动收口仍作用于起手的那条片段。
void main() {
  const total = Duration(minutes: 3);

  const clipA = PracticeClip(
    id: 'cA',
    materialId: 'mA',
    materialSourceStartMs: 100000,
    inMs: 0,
    outMs: 10000,
    materialDurationMs: 30000,
  );
  const clipB = PracticeClip(
    id: 'cB',
    materialId: 'mB',
    materialSourceStartMs: 120000,
    inMs: 0,
    outMs: 10000,
    materialDurationMs: 30000,
  );

  late FakePlaybackEngine engine;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
  });

  testWidgets('拖动起手后另一条片段被外部删除：收口仍作用于起手的那条', (tester) async {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 8 * 3.5,
    );
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatTrackStateProvider.overrideWithBuild(
            (ref, _) => uniformReadyBeatState(seconds: 180),
          ),
          annotationTimelineProvider.overrideWithBuild(
            (ref, _) => AnnotationTimeline.wholeVideo(total),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: buildTrackBandSession(engine: engine),
                rowTable: TrackRowTable.compare,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackBand)),
      listen: false,
    );
    container.read(practiceClipsProvider.notifier).restore(const [
      clipA,
      clipB,
    ]);
    await tester.pumpAndSettle();

    final blockB = tester.getRect(find.byKey(const Key('practice_clip_cB')));
    expect(blockB.left, greaterThan(0), reason: 'B 在轨道上有实体块');

    // 在 B 的尾端点带起手截取拖动。
    final gesture = await tester.startGesture(
      Offset(blockB.right - 7, blockB.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // 起手之后外部写：素材连带删除把 A 移出轨道，B 的下标从 1 漂到 0。
    container.read(practiceClipsProvider.notifier).removeByMaterial('mA');
    await tester.pumpAndSettle();

    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    final table = container.read(practiceClipsProvider);
    expect(table.map((clip) => clip.id), ['cB'], reason: '外部删除不被拖动改写');
    expect(table.single.inMs, clipB.inMs, reason: '另一端不动');
    expect(
      table.single.outMs,
      greaterThan(clipB.outMs),
      reason: '截取收口仍作用于起手的那条片段',
    );
  });
}
