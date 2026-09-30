import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/drill_task_bar.dart'
    show kDrillTaskBarAdvanceHold, kDrillTaskBarTopInset;
import 'package:dance_learning_app/help/guide_anchor.dart';
import 'package:dance_learning_app/help/guide_host.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationTimelineProvider, localMirrorFragmentsProvider;
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

/// 菜单类三条就地讲解（去掉备注贴纸那一条；「局部镜像」是两步单元）
/// 在引导宿主接缝上的
/// 行为：首次触达 → 出现且**高亮落在刚落成的实物上**（镜像轨上那块 / 被标记
/// 的那条分段线 / 新落的那根半拍线，按会话里记下的新产物序号取向）；取不到
/// 序号 → 锚点缺席，放行不弹；关掉（单步）或走完两步即置位，此后不再出现。
void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(GuideHost)),
        listen: false,
      );

  // 气泡一句话取装载结果（单一来源），测试不另抄一份文案。
  String messageOf(_MenuBadgeCase c) => guideStepMessage(
    helpGuideSteps.firstWhere((s) => s.unitId == c.unitId).id,
  );

  // 编辑态上手与首尾线（轨道带在真机上随学习段挂载即触达，注册表序都在
  // 这四条之前）先于这四条出现：本套件按「已看过」装配，免得它们顶掉被测
  // 角标。
  InMemoryPrivateJsonStorage storage() => InMemoryPrivateJsonStorage(
    initial: const {
      'onboarding': {'editorIntro': true, 'practiceRange': true},
    },
  );

  // 单步矩阵显式钉住：本套件只按单步形态断言（「单步只有 ✕」/「关掉即置
  // 位」），将来某条单元变多步时必须在这里显式改判据，而不是静默漏测。
  test('单步角标矩阵：局部镜像是两步，其余三条单步', () {
    expect(
      {for (final c in _cases()) c.unitId: guideStepsOfUnit(c.unitId).length},
      {
        badgeLocalMirrorUnitId: 2,
        badgeSegmentFlagUnitId: 1,
        badgeHalfBeatUnitId: 1,
      },
    );
  });

  // 仍是**单步**角标的用例；两步的「局部镜像」另有专门用例。
  final singleStepCases = [
    for (final c in _cases())
      if (guideStepsOfUnit(c.unitId).length == 1) c,
  ];

  // 首次触达并在两种物理视口下各断言一次：气泡一句话 + 高亮真的落在实物
  // 控件上（横竖屏共用同一行表，方向差异只改带的落位）。
  for (final view in const [Size(800, 1400), Size(1400, 800)]) {
    for (final c in singleStepCases) {
      testWidgets(
        '${c.unitId}：首次触达 → 出现且指向实物（${view.width.toInt()}×${view.height.toInt()}）',
        (tester) async {
          await _pumpBand(tester, storage: storage(), view: view, c: c);

          await _touch(tester, c);
          expect(find.text(messageOf(c)), findsOneWidget);
          // 单步角标：一句话 + 关闭钮，无步数指示、无跳过。
          expect(find.byKey(const Key('guide_skip')), findsNothing);
          expectGuidePointsAt(tester, find.byKey(Key(c.artifactKey)));
        },
      );
    }
  }

  for (final c in singleStepCases) {
    testWidgets('${c.unitId}：关掉即置位；已置位再触达不再出现', (tester) async {
      final s = storage();
      await _pumpBand(tester, storage: s, c: c);

      await _touch(tester, c);
      await tester.tap(find.byKey(const Key('guide_close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(
        (s.snapshot['onboarding'] as Map)[onboardingFlagFields[c.unitId]],
        isTrue,
      );

      // 重启后实物仍在场：已置位 → 再触达也不出现。
      await _pumpBand(tester, storage: s, c: c);
      await _touch(tester, c);
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
    });
  }

  for (final c in _cases()) {
    testWidgets('${c.unitId}：取不到新产物序号 → 锚点缺席放行，不弹不挡界面', (tester) async {
      final s = storage();
      await _pumpBand(tester, storage: s, c: c);

      // 只触达、不记序号（等价于「入口不可用 / 没落成」：没有产物可指）。
      containerOf(tester)
          .read(guideSessionProvider.notifier)
          .trigger(c.unitId);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
      expect(
        (s.snapshot['onboarding'] as Map)[onboardingFlagFields[c.unitId]],
        isNull,
        reason: '不出现也不消耗',
      );
    });
  }

  testWidgets('未触达：不主动弹出（角标只在功能第一次真正被使用时出现）', (tester) async {
    await _pumpBand(tester, storage: storage(), c: _cases().first);

    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
  });

  testWidgets('演练优先：演练进行期间四条也不插话，收场后立刻出现', (tester) async {
    final c = _cases().first;
    await _pumpBand(tester, storage: storage(), c: c);
    final container = containerOf(tester);

    container.read(guideSessionProvider.notifier).setDrillRunning(true);
    await _touch(tester, c);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);

    container.read(guideSessionProvider.notifier).setDrillRunning(false);
    await tester.pumpAndSettle();
    expect(find.text(messageOf(c)), findsOneWidget);
  });

  // ---- 局部镜像两步：第一步锚刚落的那块；第二步
  // 锚那枚「局部镜像」开关。开关住在播放页控制层，本装配面（只有轨道带）里
  // 不在场，故第二步在这里不出场、也不被消耗；「两步各自框准」的走查由
  // `control_layer_test` 的播放页接缝断言。
  testWidgets(
    '局部镜像：第一步框住刚落的那块（1/2）；推进后第二步锚点不在本装配面 → 不出场、不消耗',
    (tester) async {
      final c = _caseOfUnit(badgeLocalMirrorUnitId);
      final s = storage();
      await _pumpBand(tester, storage: s, c: c);

      await _touch(tester, c);
      expect(
        find.text(guideStepMessage('badge_local_mirror_step')),
        findsOneWidget,
      );
      expect(find.text('1/2'), findsOneWidget);
      expectGuidePointsAt(tester, find.byKey(Key(c.artifactKey)));

      await tester.tap(find.byKey(const Key('guide_next')));
      await tester.pumpAndSettle();

      // 第二步的锚点（`tool_local_mirror`）不在场：锚点缺席即放行，浮层撤下、
      // 整单元不置位。
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
      expect(
        (s.snapshot['onboarding'] as Map)[onboardingFlagFields[c.unitId]],
        isNull,
        reason: '第二步没演过，整单元不置位',
      );
    },
  );

  testWidgets('局部镜像：两步同属一个单元——「跳过」即整单元置位，此后不再出现', (tester) async {
    final c = _caseOfUnit(badgeLocalMirrorUnitId);
    final s = storage();
    await _pumpBand(tester, storage: s, c: c);
    await _touch(tester, c);
    await tester.tap(find.byKey(const Key('guide_skip')));
    await tester.pumpAndSettle();
    expect(
      (s.snapshot['onboarding'] as Map)[onboardingFlagFields[c.unitId]],
      isTrue,
    );

    await _pumpBand(tester, storage: s, c: c);
    await _touch(tester, c);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
  });

  // ---- 三指跳转单元：与「标记分段线」
  // 各是一条独立单元，触发时点相同；两步同锚刚标记的那条线，第二步是动手
  // 演练（判据闩由测试直接记入，播放页记入点在 player_page_test 断言）。
  _MenuBadgeCase threeFingerCase() => _MenuBadgeCase(
        unitId: badgeThreeFingerJumpUnitId,
        anchorBase: segmentLineAnchorKeyBase,
        index: 1,
        artifactKey: 'segment_line_1',
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 5)),
            SegmentLine(position: Duration(seconds: 10), flagged: true),
            SegmentLine(position: Duration(seconds: 15), flagged: true),
          ],
        ),
      );

  testWidgets('三指跳转：标记做成 → 单元触发，第一步讲解框住刚标记的线（1/2）', (tester) async {
    final c = threeFingerCase();
    await _pumpBand(tester, storage: storage(), c: c);

    await _touch(tester, c);
    expect(find.text(guideStepMessage('badge_segment_flag_step')), findsOneWidget);
    expectGuidePointsAt(tester, find.byKey(Key(c.artifactKey)));
    expect(find.text('1/2'), findsOneWidget);
  });

  testWidgets('三指跳转：推进到第二步那一帧请求进观看态恰一次；锚点撤下演出驻留；'
      '做到打勾停约 0.4 秒推进并置位', (tester) async {
    final s = storage();
    final c = threeFingerCase();
    await _pumpBand(tester, storage: s, c: c);
    final container = containerOf(tester);
    final enterWatching = container.read(guideEnterWatchingRequestProvider);
    var requests = 0;
    void collapse() => requests++;
    enterWatching.attach(collapse);
    addTearDown(() => enterWatching.detach(collapse));

    await _touch(tester, c);
    await tester.tap(find.byKey(const Key('guide_next')));
    await tester.pump();
    await tester.pump();

    expect(requests, 1, reason: '推进到第二步的一帧请求一次，不重复');
    expect(find.text(guideStepMessage('badge_three_finger_jump_step')), findsOneWidget);
    expect(find.byKey(const Key('drill_anchor_highlight')), findsOneWidget);
    // 驻留锚点步（三指跳转 ②）：锚点还在屏上时条子也仍停靠安全区顶——矩形
    // 只用于画高亮框，不用于贴条。
    expect(
      tester.getRect(find.byKey(const Key('drill_task_bar'))).top,
      closeTo(kDrillTaskBarTopInset, 0.5),
      reason: '三指跳转 ② 继续停靠安全区顶',
    );
    expect(find.byKey(const Key('drill_task_arrow')), findsNothing);

    // 锚点从上报板撤下（控制层收起带走轨道带的同款事实）：本步演出驻留。
    container.read(guideAnchorRectsProvider.notifier).remove(c.artifactKey);
    await tester.pump();
    expect(find.byKey(const Key('drill_anchor_highlight')), findsOneWidget);
    expect(find.text(guideStepMessage('badge_three_finger_jump_step')), findsOneWidget);

    // 做到（判据闩置位）→ 当场填勾 → 停约 0.4 秒推进 → 整单元置位。
    container
        .read(guideSessionProvider.notifier)
        .latch(HandsOnCriterion.threeFingerJumpPerformed);
    await tester.pump();
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    await tester.pump(kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text(guideStepMessage('badge_three_finger_jump_step')), findsNothing);
    expect(
      (s.snapshot['onboarding'] as Map)[onboardingFlagFields[c.unitId]],
      isTrue,
    );
  });

  testWidgets('三指跳转：判据未走完时下次标记另一条线，第二步还在且锚换成刚标记的那条', (tester) async {
    final c = threeFingerCase();
    await _pumpBand(tester, storage: storage(), c: c);
    final container = containerOf(tester);

    await _touch(tester, c);
    expectGuidePointsAt(tester, find.byKey(Key('segment_line_1')));

    await tester.tap(find.byKey(const Key('guide_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_anchor_highlight')), findsOneWidget);

    // 「下次标记另一条线」：新产物序号接管（同单元后落成的实物接管锚点）。
    container.read(guideSessionProvider.notifier).recordArtifact(c.unitId, 2);
    await tester.pumpAndSettle();
    // 第二步还在场，锚点实物换成了刚标记的那条（segment_line_2 在屏）。
    expect(find.text(guideStepMessage('badge_three_finger_jump_step')), findsOneWidget);
    expect(find.byKey(const Key('drill_anchor_highlight')), findsOneWidget);
    expect(find.byKey(const Key('segment_line_2')), findsOneWidget);
  });

  testWidgets('三指跳转：「跳过」→ 整单元置位，此后再触达也不再出现', (tester) async {
    final s = storage();
    final c = threeFingerCase();
    await _pumpBand(tester, storage: s, c: c);
    await _touch(tester, c);
    await tester.tap(find.byKey(const Key('guide_skip')));
    await tester.pumpAndSettle();
    expect(
      (s.snapshot['onboarding'] as Map)[onboardingFlagFields[c.unitId]],
      isTrue,
    );

    await _pumpBand(tester, storage: s, c: c);
    await _touch(tester, c);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
  });

  test('三指跳转：引导重置把判据闩一并清（重置后须再做到才可能推进）', () async {
    final container = ProviderContainer(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(
          InMemoryPrivateJsonStorage(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(guideSessionProvider.notifier)
        .latch(HandsOnCriterion.threeFingerJumpPerformed);
    expect(
      container.read(guideSessionProvider).criterionLatches.contains(
        HandsOnCriterion.threeFingerJumpPerformed,
      ),
      isTrue,
    );

    await container
        .read(guideResetProvider)
        .resetUnit(badgeThreeFingerJumpUnitId);
    expect(
      container.read(guideSessionProvider).criterionLatches.contains(
        HandsOnCriterion.threeFingerJumpPerformed,
      ),
      isFalse,
    );
  });

  test('锚点 key 拼法：注册表基键 + 新产物序号 == 实物的既有定位 key', () {
    for (final c in _cases()) {
      final step = helpGuideSteps.firstWhere((s) => s.unitId == c.unitId);
      expect(step.anchorKey, c.anchorBase, reason: c.unitId);
      expect(
        guideArtifactAnchorKey(c.anchorBase, c.index),
        c.artifactKey,
        reason: c.unitId,
      );
      expect(
        guideAnchorKeyOfStep(step, {c.unitId: c.index}),
        c.artifactKey,
        reason: c.unitId,
      );
      // 序号取不到 → 退回基键（基键不承载实物，等同锚点缺席）。
      expect(guideAnchorKeyOfStep(step, const {}), c.anchorBase);
    }
  });
}

/// 一条菜单类角标用例：单元、锚点基键、新产物序号（刻意取非 0 的三个以证明
/// 角标指向的是**刚落成的那一条**，不是第一条）、被指向的实物控件，以及为让
/// 该实物在场而种下的轨上内容。
class _MenuBadgeCase {
  const _MenuBadgeCase({
    required this.unitId,
    required this.anchorBase,
    required this.index,
    required this.artifactKey,
    required this.timeline,
    this.mirrors = const [],
  });

  final String unitId;
  final String anchorBase;
  final int index;
  final String artifactKey;
  final AnnotationTimeline timeline;
  final List<LocalMirrorFragment> mirrors;
}

AnnotationTimeline _plainTimeline() =>
    AnnotationTimeline.normalized(videoDuration: const Duration(seconds: 30));

List<_MenuBadgeCase> _cases() => [
  _MenuBadgeCase(
    unitId: badgeLocalMirrorUnitId,
    anchorBase: mirrorFragmentAnchorKeyBase,
    index: 1,
    artifactKey: 'mirror_fragment_1',
    timeline: _plainTimeline(),
    mirrors: const [
      LocalMirrorFragment(startMs: 2000, endMs: 3000),
      LocalMirrorFragment(startMs: 12000, endMs: 13000),
    ],
  ),
  _MenuBadgeCase(
    unitId: badgeSegmentFlagUnitId,
    anchorBase: segmentLineAnchorKeyBase,
    index: 1,
    artifactKey: 'segment_line_1',
    timeline: AnnotationTimeline.normalized(
      videoDuration: const Duration(seconds: 30),
      segmentLines: const [
        SegmentLine(position: Duration(seconds: 5)),
        SegmentLine(position: Duration(seconds: 10), flagged: true),
        SegmentLine(position: Duration(seconds: 15)),
      ],
    ),
  ),
  _MenuBadgeCase(
    unitId: badgeHalfBeatUnitId,
    anchorBase: halfBeatLineAnchorKeyBase,
    index: 1,
    artifactKey: 'half_beat_line_1',
    timeline: AnnotationTimeline.normalized(
      videoDuration: const Duration(seconds: 30),
      halfBeatLines: const [
        HalfBeatLine(position: Duration(seconds: 5)),
        HalfBeatLine(position: Duration(seconds: 10)),
      ],
    ),
  ),
];

/// 按单元 id 取用例（不依赖 [_cases] 的书写次序：加用例、调次序都不会让
/// 「测的是哪一条」跟着变）。
_MenuBadgeCase _caseOfUnit(String unitId) =>
    _cases().firstWhere((c) => c.unitId == unitId);

/// 记一次「功能第一次真正被使用」：触达 + 新产物序号（control_layer 的
/// 「添加」菜单条目动作在提交生效后走的就是这两步）。
Future<void> _touch(WidgetTester tester, _MenuBadgeCase c) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GuideHost)),
    listen: false,
  );
  container
      .read(guideSessionProvider.notifier)
      .recordArtifact(c.unitId, c.index);
  container.read(guideSessionProvider.notifier).trigger(c.unitId);
  await tester.pumpAndSettle();
}

/// 真机轨道带装配：轨道上种下该用例的实物，引导宿主包住整页。
Future<void> _pumpBand(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
  required _MenuBadgeCase c,
  Size view = const Size(800, 1400),
}) async {
  // 合成档视口（入参 view，默认 800×1400dp；dpr 1.0），非设备档。
  tester.view.physicalSize = view;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(storage),
        annotationTimelineProvider.overrideWithBuild((ref, _) => c.timeline),
        if (c.mirrors.isNotEmpty)
          localMirrorFragmentsProvider.overrideWithBuild((ref, _) => c.mirrors),
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
