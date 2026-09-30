import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_anchor.dart';
import 'package:dance_learning_app/help/guide_host.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/player/play_tool_table.dart';
import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/guide_assertions.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/guide_copy_fixture.dart';

/// 引导角标（14 单元口径）在引导宿主接缝上的行为：
/// 首次触达 → 出现一次；关掉即置位；未触达不出现；同屏只一条不叠加。
/// 「编辑态上手」是另一条多步 badge 单元，其顺序推进与步数/跳过
/// 见 `editor_intro_test.dart`；本套件只测**单步**角标，以及锚点尚未接线的
/// 单元不出场、也不被消耗。另载一条纯结构护栏：两排工具槽里声明
/// 承载引导锚点的槽，其槽键必须被注册表步锚中（顶栏与底栏同一口径）。
void main() {
  /// 锚点已接线且单步的角标单元 id（注册表即清单）。节拍提示 / 倍速的逐栏
  /// 锚点、音画同步、名册的锚点在各自气泡面板上，见下面的「不出场」组；
  /// 分段是动手一步 ＋ 讲解一步的两步单元，选中判据与「删除」槽
  /// 锚点各归 `segment_select_delete_test` / `control_layer_test`，
  /// 本套件只测单步角标，故不在内。
  const badgeUnitIds = {practiceRangeUnitId, badgeAutoSegmentUnitId};

  final badgeSteps = [
    for (final step in helpGuideSteps)
      if (badgeUnitIds.contains(step.unitId)) step,
  ];

  /// 锚点不在本套件的装配面上（节拍 / 倍速 / 音画同步的逐栏锚点在各自
  /// 气泡面板里；名册在备注编辑）——本 harness 不挂这些面板，触达后
  /// 锚点缺席，按无步放行、不消耗。分段两步的锚点在轨道带与控制层，
  /// 同样不在本 harness 上，但它的选中判据归 `segment_select_delete_test`，
  /// 这里不重复。
  const unwiredUnitIds = {
    badgeBeatPromptUnitId,
    badgeSpeedUnitId,
    badgeAvSyncUnitId,
    badgeRosterUnitId,
  };

  test('声明承载引导锚点的槽，其槽键都有注册表步锚在它上面（顶栏与底栏同一口径）', () {
    // 「声明为真」是渲染点包不包锚点包装器的唯一依据（顶栏
    // `PlayToolSlot.carriesGuideAnchor` / 底栏 `ToolSlot.carriesGuideAnchor`，
    // 锚点 key 即槽键），故这一条同时管两排：任何一枚声明为真的槽都必须有注册
    // 表步真的锚在它上面——只有声明、没有步锚上来是「忘了接」；没声明的槽由
    // 渲染点结构上不包包装器、不上报矩形，即「故意不接」。
    final declaredPlayToolKeys = {
      for (final row in [
        kPlayToolRowLandscapeTopBar,
        kPlayToolRowPortraitTitleBar,
        // 竖屏视频工具栏拆两行，两行都进本护栏。
        kPlayToolRowPortraitVideoToolbarTop,
        kPlayToolRowPortraitVideoToolbarBottom,
      ])
        for (final slot in row.slots)
          if (slot.carriesGuideAnchor) slot.key,
    };
    final declaredBottomSlotKeys = {
      for (final table in [
        ToolSlotTable.normal,
        ToolSlotTable.standby,
        ToolSlotTable.compare,
      ])
        for (final slot in table.slots)
          if (slot.carriesGuideAnchor) slot.key,
    };
    expect(declaredPlayToolKeys, isNotEmpty, reason: '顶栏那一排在册，护栏不是空真');
    expect(declaredBottomSlotKeys, isNotEmpty, reason: '底栏那一排在册，护栏不是空真');

    final anchoredStepKeys = helpGuideSteps.map((s) => s.anchorKey).toSet();
    for (final key in {...declaredPlayToolKeys, ...declaredBottomSlotKeys}) {
      expect(
        anchoredStepKeys.contains(key),
        isTrue,
        reason: '槽 $key 声明承载引导锚点，却没有注册表步锚在它上面',
      );
    }
  });

  testWidgets('两条单步角标各有注册表步、锚点 key 互不相同', (tester) async {
    expect(badgeSteps.length, badgeUnitIds.length);
    for (final unitId in badgeUnitIds) {
      expect(guideStepsOfUnit(unitId), hasLength(1));
    }
    expect(badgeSteps.map((s) => s.anchorKey).toSet().length, badgeSteps.length);
  });

  testWidgets('锚点尚未接线的步不出场、也不被消耗（锚点缺席即放行）', (tester) async {
    for (final unitId in unwiredUnitIds) {
      final storage = InMemoryPrivateJsonStorage(
        initial: const {
          'onboarding': {'firstRun': true, 'editorIntro': true},
        },
      );
      // 锚点不在场：真实链路里未接线的锚点没有任何控件上报矩形。
      await _pumpHost(tester, storage: storage, anchorsPresent: false);

      await _trigger(tester, unitId);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('guide_highlight')),
        findsNothing,
        reason: '$unitId 的锚点未接线，不出场',
      );
      expect(
        (storage.snapshot['onboarding'] as Map)[onboardingFlagFields[unitId]],
        isNull,
        reason: '$unitId 未出场也不被消耗',
      );
    }
  });

  for (final step in badgeSteps) {
    testWidgets('${step.id}：未触达不出现；触达即出现；关掉置位不再出现', (tester) async {
      // 首启两步是模态的、先于一切角标（注册表序）：本套件只测角标，
      // 首启按已走完装配。
      final storage = InMemoryPrivateJsonStorage(
        initial: const {
          'onboarding': {'firstRun': true},
        },
      );
      await _pumpHost(tester, storage: storage);

      // 未触达：不出现（不排队、不主动弹出）。
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
      expect(find.text(guideStepMessage(step.id)), findsNothing);

      // 首次触达：气泡出现，一句话 + 关闭钮；角标无跳过钮、无步数指示。
      await _trigger(tester, step.unitId);
      await tester.pumpAndSettle();

      expect(find.text(guideStepMessage(step.id)), findsOneWidget);
      expect(find.byKey(const Key('guide_close')), findsOneWidget);
      expect(find.byKey(const Key('guide_skip')), findsNothing);
      // 提示块真的指向声明的那枚锚点控件：贴住它、箭头对准它的中心。
      expectGuidePointsAt(tester, find.byKey(Key(step.anchorKey!)));

      // 关掉即置位：本会话与落盘都不再看；再触达也不出现。
      await tester.tap(find.byKey(const Key('guide_close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guide_highlight')), findsNothing);
      final flags = storage.snapshot['onboarding'] as Map;
      final field = onboardingFlagFields[step.unitId]!;
      expect(flags[field], isTrue);

      await _pumpHost(tester, storage: storage);
      // 已置位：再触达也不再出现。
      await _trigger(tester, step.unitId);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
    });
  }

  testWidgets('不排队不叠加：同屏只一条；显示中再触达不顶替；关掉才轮到已触达的下一条', (tester) async {
    // 两条各自已接线的单步角标，注册表序即竞争序（首尾线在前、自动分段在后）。
    final first = badgeSteps[0];
    final second = badgeSteps[1];
    final third = badgeSteps[0];
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    await _pumpHost(tester, storage: storage);

    await _trigger(tester, first.unitId);
    await _trigger(tester, second.unitId);
    await tester.pumpAndSettle();

    // 两条都已触达：仍只渲染一条（宿主结构保证），取注册表靠前的一条。
    expect(_bubbleTexts(tester), [guideStepMessage(first.id)]);

    // 显示中再触达别的角标：不顶替当前这条，也绝不同屏叠加。
    await _trigger(tester, third.unitId);
    await tester.pumpAndSettle();
    expect(_bubbleTexts(tester), [guideStepMessage(first.id)]);

    // 关掉当前条：才轮到已触达的下一条。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect(_bubbleTexts(tester), [guideStepMessage(second.id)]);
  });

  testWidgets('GuideBadgeTrigger：挂载即记触达，重复挂载幂等', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: Scaffold(
                body: GuideBadgeTrigger(
                  unitId: badgeAutoSegmentUnitId,
                  child: SizedBox(width: 10, height: 10),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      container.read(guideSessionProvider).triggered,
      [badgeAutoSegmentUnitId],
    );

    // 同一单元在两处各挂一枚触发器（同一功能有多个宿主位）：幂等。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    GuideBadgeTrigger(
                      unitId: badgeAutoSegmentUnitId,
                      child: SizedBox(width: 10, height: 10),
                    ),
                    GuideBadgeTrigger(
                      unitId: badgeAutoSegmentUnitId,
                      child: SizedBox(width: 10, height: 10),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(
      container.read(guideSessionProvider).triggered,
      [badgeAutoSegmentUnitId],
    );
  });

  testWidgets('角标优先于未置位的首启/演练步：不被前置单元压制（不排队）', (tester) async {
    final step = badgeSteps.first;
    // 首启未走完：真实链路里首启是模态的，但演练退出不置位同样
    // 会留在注册表序前部——角标不等待任何前置单元。
    final storage = InMemoryPrivateJsonStorage();
    await _pumpHost(tester, storage: storage);

    await _trigger(tester, step.unitId);
    await tester.pumpAndSettle();

    expect(find.text(guideStepMessage(step.id)), findsOneWidget);
  });

  testWidgets('分段 / 自动分段的锚点不再落在工具槽上', (tester) async {
    final autoStep = helpGuideSteps.firstWhere(
      (s) => s.unitId == badgeAutoSegmentUnitId,
    );
    // 分段（两步）：第 ① 步锚刚落那条线的**控制柄**（与线身同基键 +
    // `_handle` 尾缀），第 ② 步锚编辑态那枚「删除」槽（唯一一处锚工具
    // 槽的角标）；线身那条（本用例样本）与「标记分段线」共用基键。
    final segmentUnitSteps = [
      for (final s in helpGuideSteps)
        if (s.unitId == badgeSegmentUnitId) s,
    ];
    expect(segmentUnitSteps.map((s) => s.anchorKey), [
      segmentLineAnchorKeyBase,
      segmentDeleteSlotAnchorKey,
    ]);
    // 自动分段：锚在刚弹出的三档菜单本体上，不回指工具槽。
    expect(autoStep.anchorKey, autoSegmentMenuAnchorKey);

    // 两态各有一枚「删除」槽，槽键同名而引导锚点只在编辑态那一枚上声明：
    // 分段第 ② 步的锚点常量必须与编辑态那枚的槽键逐位一致（对比态那枚
    // 不承载锚点，故不接）。
    ToolSlot editDelete() => ToolSlotTable.normal.slots.firstWhere(
      (slot) => slot.id == ToolSlotId.delete,
    );
    ToolSlot compareDelete() => ToolSlotTable.compare.slots.firstWhere(
      (slot) => slot.id == ToolSlotId.delete,
    );
    expect(editDelete().key, segmentDeleteSlotAnchorKey);
    expect(
      editDelete().carriesGuideAnchor,
      isTrue,
      reason: '编辑态那枚「删除」槽承载分段第 ② 步的锚点',
    );
    expect(compareDelete().key, segmentDeleteSlotAnchorKey);
    expect(
      compareDelete().carriesGuideAnchor,
      isFalse,
      reason: '对比态另有一枚同名槽：不接锚点（边界）',
    );
  });

  testWidgets('GuideBadgeTrigger enabled=false：功能不可用不触达、不置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(
              home: Scaffold(
                body: GuideBadgeTrigger(
                  unitId: badgeAutoSegmentUnitId,
                  enabled: false,
                  child: SizedBox(width: 10, height: 10),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    expect(container.read(guideSessionProvider).triggered, isEmpty);
  });

  testWidgets('演练优先：演练进行期间角标也不插话，收场后立刻出现', (tester) async {
    final step = badgeSteps.first;
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    await _pumpHost(tester, storage: storage);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GuideHost)),
      listen: false,
    );

    container.read(guideSessionProvider.notifier).setDrillRunning(true);
    await _trigger(tester, step.unitId);
    await tester.pumpAndSettle();
    expect(find.text(guideStepMessage(step.id)), findsNothing, reason: '演练期间屏幕归演练');

    container.read(guideSessionProvider.notifier).setDrillRunning(false);
    await tester.pumpAndSettle();
    expect(find.text(guideStepMessage(step.id)), findsOneWidget);
  });

  testWidgets('触达了但锚点不在场：不出现（角标只指向在场控件）', (tester) async {
    final step = badgeSteps.first;
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    await _pumpHost(tester, storage: storage, anchorsPresent: false);

    await _trigger(tester, step.unitId);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(find.text(guideStepMessage(step.id)), findsNothing);
    // 未消费：锚点出现后仍会显示。
  });
}

/// 气泡里正在显示的一句话（应恰一条）。
List<String> _bubbleTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('guide_bubble')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .where((text) => text.isNotEmpty)
    .toList();

Future<void> _trigger(WidgetTester tester, String unitId) async {
  ProviderScope.containerOf(
    tester.element(find.byType(GuideHost)),
    listen: false,
  ).read(guideSessionProvider.notifier).trigger(unitId);
}

/// 角标宿主接缝的最小装配：五个角标锚点 + 触发面 + 状态位落盘全走真实现。
Future<void> _pumpHost(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
  bool anchorsPresent = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        home: GuideHost(
          child: Scaffold(
            body: Center(
              // 声明的锚点件全部在场。
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (anchorsPresent)
                    // 每个锚点 key 只摆一枚：同 key 两枚会在上报板上互顶矩形、
                    // 每帧改写，宿主永远等不到静帧。共键的两处——分段与「标记
                    // 分段线」共用同一线身基键，首启的「等会儿再下载」
                    // 与「我先自己用」两支指认共用同一枚「帮助」锚点键。
                    for (final step in {
                      for (final step in helpGuideSteps)
                        if (step.form == GuideUnitForm.inplaceTour)
                          step.anchorKey!: step,
                    }.values)
                      GuideAnchor(
                        anchorKey: step.anchorKey!,
                        child: IconButton(
                          key: Key(step.anchorKey!),
                          onPressed: () {},
                          icon: const Icon(Icons.content_cut),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
