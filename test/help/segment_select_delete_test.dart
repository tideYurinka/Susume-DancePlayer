import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/drill_task_bar.dart'
    show kDrillTaskBarAdvanceHold;
import 'package:dance_learning_app/help/guide_anchor.dart';
import 'package:dance_learning_app/help/guide_host.dart';
import 'package:dance_learning_app/help/guide_layers.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationTimelineProvider, selectedSegmentLineIndexProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/pump_settle.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/guide_copy_fixture.dart';

/// 分段第 ① 步「亲手把刚落那条线选中一次」在引导
/// 宿主 + 真机轨道带接缝上的行为：高亮框框住刚落那条线的**控制柄**，点它、
/// 或在线身那一行点它，两条路径各算一次选中（落线本身不算、打勾之前不推进）；
/// 连着落两条时框改指第二条；重置清掉「这条线被选中过」这个判据闩。
///
/// 第二步（指「删除」工具槽）走真机播放页控制层那条接缝，见
/// `test/player/control_layer_test.dart` 的「分段＝动手选中＋一句讲删除」组。
void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(GuideHost)),
        listen: false,
      );

  final selectStep = helpGuideSteps.firstWhere(
    (s) => s.handsOnCriterion == HandsOnCriterion.badgeSegmentLineSelected,
  );
  final deleteStep = helpGuideSteps.firstWhere(
    (s) => s.anchorKey == segmentDeleteSlotAnchorKey,
  );

  /// 引导宿主接缝的装配：其余单元按「已看过」装配，只留分段待走；轨道上已
  /// 有分段线（编辑态上手与首尾线因此不插话）。
  Future<InMemoryPrivateJsonStorage> pumpBand(
    WidgetTester tester, {
    AnnotationTimeline? timeline,
  }) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: {
        'onboarding': {
          for (final field in onboardingFlagFields.values) field: true,
        }..['badgeSegment'] = false,
      },
    );
    tester.view.physicalSize = const Size(800, 1400); // 合成档 800×1400dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          privateJsonStorageProvider.overrideWithValue(storage),
          annotationTimelineProvider.overrideWithBuild(
            (ref, _) =>
                timeline ??
                AnnotationTimeline.normalized(
                  videoDuration: const Duration(seconds: 30),
                  segmentLines: const [
                    SegmentLine(position: Duration(seconds: 10)),
                  ],
                ),
          ),
        ],
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: buildTrackBandSession(engine: engine),
                rowTable: TrackRowTable.normal,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpSettle(tester);
    return storage;
  }

  /// 模拟「首次落线成功」：重开这一单元的判据 + 记下刚落那条线的序号 + 触达
  ///（与真机 `control_layer` 的「分段」槽落线动作同一套事实，逐位一致）。
  Future<void> dropLine(WidgetTester tester, int index) async {
    containerOf(tester)
      ..read(guideSessionProvider.notifier)
      .clearCriterion(HandsOnCriterion.badgeSegmentLineSelected)
      ..read(guideSessionProvider.notifier)
          .recordArtifact(badgeSegmentUnitId, index)
      ..read(guideSessionProvider.notifier).trigger(badgeSegmentUnitId);
    await tester.pumpAndSettle();
  }

  /// 越过「做到即停约 0.4 秒」的停留，进下一步。
  Future<void> pumpPastHold(WidgetTester tester) async {
    await tester.pump(
      kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50),
    );
    await tester.pumpAndSettle();
  }

  test('注册表两步：①动手选中控制柄、②就地讲解「删除」槽', () {
    expect(selectStep.form, GuideUnitForm.handsOnDrill);
    expect(
      guideAnchorKeyOfStep(selectStep, {badgeSegmentUnitId: 0}),
      'segment_line_0_handle',
      reason: '框住的是刚落那条线的控制柄（不是通高的线身、不是别的线）',
    );
    expect(deleteStep.form, GuideUnitForm.inplaceTour);
    expect(deleteStep.anchorKey, segmentDeleteSlotAnchorKey);
    expect(
      helpGuideSteps.where((s) => s.unitId == badgeSegmentUnitId).length,
      2,
    );
  });

  testWidgets('落线先给待办条：框住刚落那条线的控制柄，打勾之前不推进', (tester) async {
    await pumpBand(tester);
    await dropLine(tester, 0);

    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(find.text(guideStepMessage(selectStep.id)), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    // 高亮框套在控制柄上：不压暗、不挖洞（动手演练形态）。
    final rects = containerOf(tester).read(guideAnchorRectsProvider);
    expect(
      rects['segment_line_0_handle'],
      isNotNull,
      reason: '刚落那条线的控制柄在屏并上报矩形',
    );
    expect(
      find.byKey(const Key('guide_highlight')),
      findsNothing,
      reason: '动手步只有一圈描边，不压暗不挖洞',
    );

    // 锚点在屏：条子贴住控制柄那圈高亮框、不盖住它；被讲的那条线仍在屏上。
    final handle = tester.getRect(
      find.byKey(const Key('segment_line_0_handle')),
    );
    expectDrillBarAnchoredTo(tester, guideHoleRect(handle));
    expect(find.byKey(const Key('segment_line_0')), findsOneWidget);

    // 没点过控制柄：勾选框空着、停在第 1 步，等待时长过去也不推进。
    await tester.pump(kDrillTaskBarAdvanceHold + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text(guideStepMessage(selectStep.id)), findsOneWidget);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
  });

  testWidgets('路径一：点控制柄把线选中即打勾，停约 0.4 秒进第二步', (tester) async {
    await pumpBand(tester);
    await dropLine(tester, 0);

    await tester.tap(find.byKey(const Key('segment_line_0_handle')));
    await tester.pump();

    final container = containerOf(tester);
    expect(
      container.read(selectedSegmentLineIndexProvider),
      0,
      reason: '点小把手真的把线选中了',
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
      reason: '做到即当场填勾',
    );
    expect(find.text('1/2'), findsOneWidget, reason: '停留期间还没进下一步');

    await pumpPastHold(tester);
    // 走完第 1 步：整单元未收场（还有第 2 步），待办条让位给讲解层。
    expect(
      container.read(guideSessionProvider).stepsDone,
      contains(selectStep.id),
    );
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.text(guideStepMessage(selectStep.id)), findsNothing);
  });

  testWidgets('路径二：在线身那一行点它也算选中，同样打勾推进', (tester) async {
    await pumpBand(tester);
    await dropLine(tester, 0);

    // 线身视觉件自身 IgnorePointer（命中归线身那一行的点按层）：中心点仍
    // 落在点按层的触发窗内，warnIfMissed 关掉只压掉这条预期内的警告。
    await tester.tap(
      find.byKey(const Key('segment_line_0')),
      warnIfMissed: false,
    );
    await tester.pump();

    final container = containerOf(tester);
    expect(
      container.read(selectedSegmentLineIndexProvider),
      0,
      reason: '线身那一行点中它也算「选中过一次」',
    );
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
    );

    await pumpPastHold(tester);
    expect(
      container.read(guideSessionProvider).stepsDone,
      contains(selectStep.id),
    );
  });

  testWidgets('连着落两条：框改指第二条', (tester) async {
    await pumpBand(
      tester,
      timeline: AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 30),
        segmentLines: const [
          SegmentLine(position: Duration(seconds: 5)),
          SegmentLine(position: Duration(seconds: 10)),
        ],
      ),
    );
    await dropLine(tester, 0);
    expect(find.text(guideStepMessage(selectStep.id)), findsOneWidget);

    // 连着落第二条：序号更新为 1，框跟到第二条的控制柄。
    await dropLine(tester, 1);
    final container = containerOf(tester);
    expect(
      container.read(guideAnchorRectsProvider)['segment_line_1_handle'],
      isNotNull,
    );
    expect(
      find.byKey(const Key('segment_line_1_handle')),
      findsOneWidget,
      reason: '第二根控制柄在屏（框跟着它）',
    );

    // 点**第一条**的控制柄不算做到：判据是「刚落那条线」被选中过。
    await tester.tap(find.byKey(const Key('segment_line_0_handle')));
    await tester.pump();
    expect(container.read(selectedSegmentLineIndexProvider), 0);
    await tester.pump(kDrillTaskBarAdvanceHold + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget, reason: '选中别的线不推进');

    // 选中刚落那条（第二条）即打勾、走完第 1 步。
    await tester.tap(find.byKey(const Key('segment_line_1_handle')));
    await tester.pump();
    expect(container.read(selectedSegmentLineIndexProvider), 1);
    await pumpPastHold(tester);
    expect(
      container.read(guideSessionProvider).stepsDone,
      contains(selectStep.id),
    );
  });

  testWidgets('判据只认刚落那条线：落线即重开判据，新线仍要亲手选中', (tester) async {
    await pumpBand(
      tester,
      timeline: AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 30),
        segmentLines: const [
          SegmentLine(position: Duration(seconds: 5)),
          SegmentLine(position: Duration(seconds: 10)),
        ],
      ),
    );
    // 先选中一条线（此时单元还没触达）。
    await tester.tap(find.byKey(const Key('segment_line_0_handle')));
    await tester.pump();
    expect(
      containerOf(tester)
          .read(guideSessionProvider)
          .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
      0,
    );

    // 再落一条新线，序号与先前选中的那条相同——落线即重开判据，不继承旧选中。
    await dropLine(tester, 0);
    expect(find.text('1/2'), findsOneWidget);
    await tester.pump(kDrillTaskBarAdvanceHold + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget, reason: '落线本身不算选中，不推进');
  });

  testWidgets('重置清掉「这条线被选中过」这个判据闩，下次走到触发点会重演', (tester) async {
    final storage = await pumpBand(tester);
    await dropLine(tester, 0);

    // 走完第一步（判据已满足）。
    await tester.tap(find.byKey(const Key('segment_line_0_handle')));
    await pumpPastHold(tester);
    expect(
      containerOf(tester)
          .read(guideSessionProvider)
          .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
      0,
    );

    // 重置：状态位之外，本会话的选中闩与进度一并清掉，页面不退出。
    await containerOf(tester)
        .read(guideResetProvider)
        .resetUnit(badgeSegmentUnitId);
    await tester.pumpAndSettle();
    expect(
      (storage.snapshot['onboarding'] as Map)['badgeSegment'],
      isFalse,
      reason: '重置写回未完成',
    );
    expect(
      containerOf(tester)
          .read(guideSessionProvider)
          .criterionValues[HandsOnCriterion.badgeSegmentLineSelected],
      isNull,
      reason: '判据闩一并清掉',
    );

    // 重新走到触发点：从第一步重头演，判据闩已清——不点就不打勾、不推进。
    await dropLine(tester, 0);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text(guideStepMessage(selectStep.id)), findsOneWidget);
    await tester.pump(kDrillTaskBarAdvanceHold + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(
      containerOf(tester).read(guideSessionProvider).stepsDone,
      isNot(contains(selectStep.id)),
    );
  });
}
