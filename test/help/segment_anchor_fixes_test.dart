import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_anchor.dart';
import 'package:dance_learning_app/help/guide_host.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationTimelineProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/pump_settle.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/guide_copy_fixture.dart';

/// 分段 / 自动分段的锚点落在「用户刚弄出来的那个东西」上：分段首次
/// **落线成功** → 触达 + 记新线序号，连着落两条时序号更新为
/// 第二条；取不到序号 → 不出场、不消耗；自动分段锚在刚弹出的三档菜单本体上
/// （不回指工具槽）。
///
/// 分段是两步（①动手选中刚落那条线的**控制柄**、②就地讲解「删除」
/// 槽）：本套件钉住两步各自的锚点拼法；两条选中路径与判据闩的行为见
/// `segment_select_delete_test.dart` 与 `control_layer_test.dart`。
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

  // 首尾线（轨道带一挂学习段即触达，注册表序在「分段」之前）按「已看过」
  // 装配，免得它顶掉被测的分段角标。
  InMemoryPrivateJsonStorage storage() => InMemoryPrivateJsonStorage(
    initial: const {
      'onboarding': {
        'firstRun': true,
        'editorIntro': true,
        'practiceRange': true,
      },
    },
  );

  AnnotationTimeline timelineWithLines() => AnnotationTimeline.normalized(
    videoDuration: const Duration(seconds: 30),
    segmentLines: const [
      SegmentLine(position: Duration(seconds: 5)),
      SegmentLine(position: Duration(seconds: 12)),
    ],
  );

  test('分段第 ① 步锚刚落那条线的控制柄：基键 + 序号 + `_handle` 尾缀', () {
    expect(selectStep.anchorKey, segmentLineAnchorKeyBase);
    expect(
      guideAnchorKeyOfStep(selectStep, {badgeSegmentUnitId: 1}),
      'segment_line_1_handle',
      reason: '连着落两条时指第二条的控制柄',
    );
  });

  test('分段第 ② 步锚编辑态那枚「删除」槽：不取新落线序号', () {
    expect(deleteStep.anchorKey, segmentDeleteSlotAnchorKey);
    expect(
      guideAnchorKeyOfStep(deleteStep, {badgeSegmentUnitId: 1}),
      segmentDeleteSlotAnchorKey,
      reason: '工具槽是固定锚点，不按序号拼',
    );
  });

  testWidgets('产物序号锚点：高亮落在刚落那条线的控制柄上', (tester) async {
    await _pumpBand(tester, storage: storage(), timeline: timelineWithLines());

    containerOf(tester)
      ..read(guideSessionProvider.notifier)
          .recordArtifact(badgeSegmentUnitId, 1)
      ..read(guideSessionProvider.notifier).trigger(badgeSegmentUnitId);
    await tester.pumpAndSettle();

    expect(find.text(guideStepMessage(selectStep.id)), findsOneWidget);
    expect(
      containerOf(tester)
          .read(guideAnchorRectsProvider)['segment_line_1_handle'],
      isNotNull,
    );
    expect(
      find.byKey(const Key('segment_line_1_handle')),
      findsOneWidget,
      reason: '高亮落在第二根控制柄上（不是别的线、不是通高的线身）',
    );
  });

  testWidgets('取不到新产物序号：不出场、不被消耗', (tester) async {
    final s = storage();
    await _pumpBand(tester, storage: s, timeline: timelineWithLines());

    // 等价「入口不可用 / 没落成」：只有触达、没有序号可指。
    containerOf(tester)
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentUnitId);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(
      (s.snapshot['onboarding']
          as Map)[onboardingFlagFields[badgeSegmentUnitId]],
      isNull,
      reason: '不出现也不消耗',
    );
  });

  test('自动分段锚在刚弹出的菜单上：注册表步声明菜单锚 key，不取序号', () {
    final step = helpGuideSteps.firstWhere(
      (s) => s.unitId == badgeAutoSegmentUnitId,
    );
    expect(step.anchorKey, autoSegmentMenuAnchorKey);
    // 菜单没有「新产物序号」：会话不记序号，锚 key 就是菜单本身。
    expect(guideAnchorKeyOfStep(step, const {}), autoSegmentMenuAnchorKey);
  });
}

/// 真机轨道带装配：轨道上种下被指的线，引导宿主包住整页（与「添加」菜单
/// 角标套件同一接缝）。
Future<void> _pumpBand(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
  required AnnotationTimeline timeline,
}) async {
  tester.view.physicalSize = const Size(800, 1400); // 合成档 800×1400dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(storage),
        annotationTimelineProvider.overrideWithBuild((ref, _) => timeline),
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
}
