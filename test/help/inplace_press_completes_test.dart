import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_anchor.dart' show GuideAnchor;
import 'package:dance_learning_app/help/guide_host.dart' show GuideHost;
import 'package:dance_learning_app/help/guide_state.dart'
    show
        OnboardingStore,
        guideSessionProvider,
        onboardingFlagFields,
        onboardingStorageProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/guide_copy_fixture.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 就地讲解「框内按下即做到」：高亮框内任一指针
/// 按下即算这一步做到——单步 / 末步整单元置位，多步推进下一步；判定取
/// 按下，拖动起手也算；穿透语义不变，同一下照常落到被指的控件上。
void main() {
  InMemoryPrivateJsonStorage storageOf() => InMemoryPrivateJsonStorage(
    initial: const {
      'onboarding': {'firstRun': true},
    },
  );

  Future<ProviderContainer> pumpFixture(
    WidgetTester tester, {
    required InMemoryPrivateJsonStorage storage,
    required List<Widget> anchors,
  }) async {
    tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(body: Stack(children: anchors)),
        ),
      ),
    );
    return container;
  }

  /// 单步单元「标记分段线」的锚点控件（带可点的内芯，验穿透）。
  Widget segmentFlagAnchor({VoidCallback? onTap}) => Positioned(
    left: 40,
    top: 40,
    child: GuideAnchor(
      anchorKey: segmentLineAnchorKeyBase,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: const Key('flagged_line'),
          width: 120,
          height: 120,
          color: Colors.blue,
        ),
      ),
    ),
  );

  /// 多步单元「节拍提示」三栏的锚点控件（按步序纵向排开，一行一栏）。
  List<Widget> beatPromptAnchors() {
    final columns = [
      (beatAnimationColumnAnchorKey, 'beat_animation'),
      (beatSoundColumnAnchorKey, 'beat_sound'),
      (beatCorrectColumnAnchorKey, 'beat_correct'),
    ];
    return [
      for (final (index, (key, name)) in columns.indexed)
        Positioned(
          left: 40,
          top: 40 + 160.0 * index,
          child: GuideAnchor(
            anchorKey: key,
            child: SizedBox(key: Key(name), width: 200, height: 120),
          ),
        ),
    ];
  }

  void expectSettled(InMemoryPrivateJsonStorage storage, String unitId) {
    expect(
      (storage.snapshot['onboarding'] as Map)[onboardingFlagFields[unitId]],
      isTrue,
      reason: '$unitId 框内按下即整单元置位（落盘）',
    );
  }

  testWidgets('单步：框内按下即置位，此后不再出现', (tester) async {
    final storage = storageOf();
    final container = await pumpFixture(
      tester,
      storage: storage,
      anchors: [segmentFlagAnchor()],
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_highlight')), findsOneWidget);

    await tester.tap(find.byKey(const Key('flagged_line')));
    await tester.pumpAndSettle();
    expectSettled(storage, badgeSegmentFlagUnitId);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
  });

  testWidgets('穿透不变：框内按下照常交给被指的控件', (tester) async {
    var taps = 0;
    final storage = storageOf();
    final container = await pumpFixture(
      tester,
      storage: storage,
      anchors: [segmentFlagAnchor(onTap: () => taps++)],
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('flagged_line')));
    await tester.pumpAndSettle();
    expect(taps, 1, reason: '按下穿透语义逐点不变：动作照常发生');
  });

  testWidgets('多步逐步推进：按当前栏只算这一栏，末栏按下即整单元置位', (tester) async {
    final storage = storageOf();
    final container = await pumpFixture(
      tester,
      storage: storage,
      anchors: beatPromptAnchors(),
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeBeatPromptUnitId);
    await tester.pumpAndSettle();
    expect(
      find.text(guideStepMessage('badge_beat_prompt_animation')),
      findsOneWidget,
    );

    // 按第一栏：只这一栏算过，推进第二栏，单元未置位。
    await tester.tap(find.byKey(const Key('beat_animation')));
    await tester.pumpAndSettle();
    expect(
      find.text(guideStepMessage('badge_beat_prompt_sound')),
      findsOneWidget,
    );
    expect((storage.snapshot['onboarding'] as Map)['badgeBeatPrompt'], isNull);

    // 按第二栏 → 第三栏。
    await tester.tap(find.byKey(const Key('beat_sound')));
    await tester.pumpAndSettle();
    expect(
      find.text(guideStepMessage('badge_beat_prompt_correct')),
      findsOneWidget,
    );

    // 末栏按下：整单元置位。
    await tester.tap(find.byKey(const Key('beat_correct')));
    await tester.pumpAndSettle();
    expectSettled(storage, badgeBeatPromptUnitId);
  });

  testWidgets('拖动起手也算：按下即算做到，不要求一次完整点按', (tester) async {
    final storage = storageOf();
    final container = await pumpFixture(
      tester,
      storage: storage,
      anchors: [segmentFlagAnchor()],
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byKey(const Key('flagged_line')));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pumpAndSettle();
    expectSettled(storage, badgeSegmentFlagUnitId);
    await gesture.up();
  });

  testWidgets('洞外按下不算：单步不推进也不置位', (tester) async {
    final storage = storageOf();
    final container = await pumpFixture(
      tester,
      storage: storage,
      anchors: [
        segmentFlagAnchor(),
        Positioned(
          left: 40,
          top: 600,
          child: SizedBox(key: const Key('dim_area'), width: 200, height: 200),
        ),
      ],
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byKey(const Key('dim_area')));
    final gesture = await tester.startGesture(center);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      (storage.snapshot['onboarding'] as Map)['badgeSegmentFlag'],
      isNull,
      reason: '洞外按下与点击同样无效果：不推进、不置位',
    );
    expect(find.byKey(const Key('guide_highlight')), findsOneWidget);
  });

  testWidgets('未按下：锚点撤下不消耗，单元不置位', (tester) async {
    final storage = storageOf();
    final container = await pumpFixture(
      tester,
      storage: storage,
      anchors: [segmentFlagAnchor()],
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_highlight')), findsOneWidget);

    // 锚点控件撤下（不按下）：不置位，也不该被误判成做到。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect((storage.snapshot['onboarding'] as Map)['badgeSegmentFlag'], isNull);
  });
}
