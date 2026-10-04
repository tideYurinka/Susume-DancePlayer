import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart'
    show LearningMastery;
import 'package:dance_learning_app/annotation/segment_line.dart'
    show SegmentLine;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationTimelineProvider,
        learningEmphasisProvider;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/track_band.dart'
    show TrackBand, TrackBandInput, beatAnalyzingFlowProvider;
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/pump_settle.dart';
import '../helpers/track_band_session_harness.dart';

/// 学习段快慢标记：红边框 = 变快（×2）、
/// 蓝边框 = 变慢（×½），画在青色选中框之内；段首小字表达精确档位。
///
/// 显示时机只有两处——段内倍频待命态与「节拍倍频」气泡打开；关气泡即收。
/// 标记不覆盖熟练度填充、重点星与段内八拍数（keyed decoration 读面断言，
/// 先例 test/player/track_band_test.dart；本仓不做 golden）。
void main() {
  testWidgets('待命态：设档段带红/蓝标记与段首小字，未设档段无标记', (tester) async {
    final container = await pumpBand(
      tester,
      lines: const [Duration(seconds: 10), Duration(seconds: 20)],
      densities: const {0: 2.0, 1: 0.5},
    );
    enterStandby(container);
    await pumpSettle(tester);

    // 段 0 = ×2 → 红框 + 「×2」；段 1 = ×½ → 蓝框 + 「×½」；段 2 未设档无标记。
    expect(
      find.byKey(const Key('learning_segment_0_density_mark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('learning_segment_1_density_mark')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('learning_segment_2_density_mark')),
      findsNothing,
    );
    expect(find.text('×2'), findsOneWidget);
    expect(find.text('×½'), findsOneWidget);

    final redBorder = _markBorder(tester, 0);
    expect(redBorder.top.color, kSegmentDensityFasterColor);
    final blueBorder = _markBorder(tester, 1);
    expect(blueBorder.top.color, kSegmentDensitySlowerColor);
  });

  testWidgets('标记只在待命态与节拍倍频气泡打开时出现；关气泡即收', (tester) async {
    final container = await pumpBand(
      tester,
      lines: const [Duration(seconds: 10)],
      densities: const {0: 2.0},
    );
    // 编辑面（两处之外）：不画。
    await pumpSettle(tester);
    expect(
      find.byKey(const Key('learning_segment_0_density_mark')),
      findsNothing,
    );

    // 节拍倍频气泡打开：画。
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.beatDensity);
    await pumpSettle(tester);
    expect(
      find.byKey(const Key('learning_segment_0_density_mark')),
      findsOneWidget,
    );

    // 关气泡即收。
    container.read(speedBubbleSessionProvider.notifier).close();
    await pumpSettle(tester);
    expect(
      find.byKey(const Key('learning_segment_0_density_mark')),
      findsNothing,
    );

    // 退出待命态即收。
    enterStandby(container);
    await pumpSettle(tester);
    expect(
      find.byKey(const Key('learning_segment_0_density_mark')),
      findsOneWidget,
    );
    container
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.editing);
    await pumpSettle(tester);
    expect(
      find.byKey(const Key('learning_segment_0_density_mark')),
      findsNothing,
    );
  });

  testWidgets('标记画在青色选中框之内：两层并存且不同宽同位', (tester) async {
    final container = await pumpBand(
      tester,
      lines: const [Duration(seconds: 10)],
      densities: const {0: 2.0},
    );
    enterStandby(container);
    await pumpSettle(tester);
    // 点第一段段体 → 选中（青色选中框）。
    final rect = tester.getRect(find.byKey(const Key('learning_segment_0')));
    await tester.tapAt(
      Offset(rect.left + rect.width * 0.25, rect.top + rect.height * 0.75),
    );
    await pumpSettle(tester);

    // 选中框仍在（青色加粗整框），标记层也在。
    expect(_boxDecoration(tester, 0).border, _cyanBorder());
    final markRect = tester.getRect(
      find.byKey(const Key('learning_segment_0_density_mark')),
    );
    final boxRect = tester.getRect(
      find.byKey(const Key('learning_segment_0_box')),
    );
    expect(
      markRect.left > boxRect.left &&
          markRect.right < boxRect.right &&
          markRect.top > boxRect.top &&
          markRect.bottom < boxRect.bottom,
      isTrue,
      reason: '标记在选中框之内、不与其同宽同位',
    );
  });

  testWidgets('标记不覆盖熟练度填充、重点星与段内八拍数', (tester) async {
    // 线 t=8/16：段首段尾皆八拍整点，八拍数淡字可见（先例几何）。
    await pumpBand(
      tester,
      lines: const [Duration(seconds: 8), Duration(seconds: 16)],
      densities: const {0: 2.0},
      emphasized: const {0},
      standby: true,
    );

    // 填充仍是熟练度色（未练灰），星与八拍数两 key 都还在。
    final box = _boxDecoration(tester, 0);
    expect(box.color, learningMasteryColor(LearningMastery.unlearned));
    expect(
      find.byKey(const Key('learning_segment_0_emphasis')),
      findsOneWidget,
    );
    // 八拍数（段内淡字）仍在段上（缩字层级随段宽，不限定变体）。
    expect(
      find.descendant(
        of: find.byKey(const Key('learning_segment_0')),
        matching: find.byWidgetPredicate(
          (w) => w.key.toString().contains('eight_count'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('段窄到放不下：不画段首小字，框仍然完整', (tester) async {
    // 1 小时视频满窗 800px → 1s 段约 0.22px，放不下任何小字。
    await pumpBand(
      tester,
      total: const Duration(hours: 1),
      lines: const [Duration(seconds: 600), Duration(seconds: 601)],
      densities: const {1: 2.0},
      standby: true,
    );
    expect(
      find.byKey(const Key('learning_segment_1_density_mark')),
      findsOneWidget,
      reason: '框完整',
    );
    expect(
      find.byKey(const Key('learning_segment_1_density_label')),
      findsNothing,
      reason: '小字不画',
    );
  });
}

Border _markBorder(WidgetTester tester, int index) {
  final decoration =
      tester
              .widget<DecoratedBox>(
                find.byKey(Key('learning_segment_${index}_density_mark')),
              )
              .decoration
          as BoxDecoration;
  return decoration.border! as Border;
}

/// 青色选中框的描边（生产 token 同值断言，同款读面）。
Border _cyanBorder() =>
    Border.all(color: kCyanAccentColor, width: kSegmentSelectedBorderWidth);

BoxDecoration _boxDecoration(WidgetTester tester, int index) {
  return tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.byKey(Key('learning_segment_$index')),
              matching: find.byKey(Key('learning_segment_${index}_box')),
            ),
          )
          .decoration
      as BoxDecoration;
}

void enterStandby(ProviderContainer container) {
  container
      .read(playerSessionProvider.notifier)
      .enter(PlayerSessionMode.segmentDensityStandby);
}

/// 学习段熟练度「未练」色断言已内联（learningMasteryColor token）。

Future<ProviderContainer> pumpBand(
  WidgetTester tester, {
  required List<Duration> lines,
  required Map<int, double> densities,
  Duration total = const Duration(seconds: 60),
  Set<int> emphasized = const {},
  bool standby = false,
}) async {
  final engine = FakePlaybackEngine(duration: total);
  final timeline = AnnotationTimeline.normalized(
    videoDuration: total,
    segmentLines: [for (final at in lines) SegmentLine(position: at)],
  );
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      beatAnalyzingFlowProvider.overrideWithValue(true),
      beatTrackStateProvider.overrideWithBuild(
        (ref, _) => uniformReadyBeatState(seconds: total.inMilliseconds / 1000),
      ),
      annotationTimelineProvider.overrideWithBuild((ref, _) => timeline),
      learningEmphasisProvider.overrideWithBuild((ref, _) => emphasized),
    ],
  );
  addTearDown(container.dispose);
  // 逐段档经恢复装载注入（非史非存，用例同款接缝）。
  container
      .read(annotationEditorProvider)
      .restoreDocument(AnnotationRestoreDocument(segmentDensities: densities));
  if (standby) enterStandby(container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: TrackBand(
            input: TrackBandInput(
              session: buildTrackBandSession(
                engine: engine,
                timeline: timeline,
                container: container,
              ),
              rowTable: TrackRowTable.normal,
            ),
          ),
        ),
      ),
    ),
  );
  await pumpSettle(tester);
  return container;
}
