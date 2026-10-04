import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_anchor.dart'
    show guideAnchorRectsProvider;
import 'package:dance_learning_app/help/guide_host.dart' show GuideHost;
import 'package:dance_learning_app/help/guide_state.dart'
    show
        OnboardingStore,
        guideSessionProvider,
        onboardingFlagFields,
        onboardingStorageProvider;
import 'package:dance_learning_app/player/av_sync.dart'
    show
        AvSyncDeviceInfo,
        AudioOutputDeviceController,
        avSyncDelaysAutoRestoreProvider,
        audioOutputDeviceControllerProvider;
import 'package:dance_learning_app/player/beat_prompt_panel.dart'
    show beatPromptEnabledProvider;
import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/speed_step_preset_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/guide_copy_fixture.dart';

/// 测试用音频输出设备控制器（恒「其它设备」、事件流静默）。
class _SilentDeviceController implements AudioOutputDeviceController {
  @override
  Future<AvSyncDeviceInfo?> get() async => null;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream =>
      const Stream<AvSyncDeviceInfo?>.empty();
}

/// 三个播放设置面板的逐栏走查：节拍提示 3 步、
/// 倍速 1 步、音画同步 1 步——气泡首次打开时就地开始，逐步锚在各栏上；
/// 讲解期间气泡内容照常可读可点；走完 / 跳过 / 关气泡都收场并置位，只此
/// 一次。文案不含方位词、节拍三步不提三种状态。
void main() {
  InMemoryPrivateJsonStorage storageOf() => InMemoryPrivateJsonStorage(
    initial: const {
      'onboarding': {'firstRun': true},
    },
  );

  /// 气泡宿主壳：入口钮（CompositedTransformTarget）+ 共享
  /// [SpeedBubbleHost]，外层套生产同路径的 [GuideHost]
  /// （MaterialApp.builder）。入口离左右缘足够远，锚定居中不触发水平钳制。
  final LayerLink link = LayerLink();

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required SpeedBubbleMode mode,
    required InMemoryPrivateJsonStorage storage,
    bool narrowScreen = false,
  }) async {
    if (narrowScreen) {
      tester.view.physicalSize = const Size(400, 1600); // 合成档 400×1600dp，非设备档。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        privateJsonStorageProvider.overrideWithValue(storage),
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
        metronomeSettingsAutoRestoreProvider.overrideWithValue(false),
        speedStepPresetStorageProvider.overrideWithValue(
          SpeedStepPresetStore(storage),
        ),
        avSyncDelaysAutoRestoreProvider.overrideWithValue(false),
        audioOutputDeviceControllerProvider.overrideWithValue(
          _SilentDeviceController(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 200, top: 40),
                    child: CompositedTransformTarget(
                      link: link,
                      child: IconButton(
                        key: const Key('bubble_entry'),
                        onPressed: () => container
                            .read(speedBubbleSessionProvider.notifier)
                            .open(mode),
                        icon: const Icon(Icons.music_note),
                      ),
                    ),
                  ),
                ),
                SpeedBubbleHost(
                  linkFor: (_) => link,
                  targetAnchor: Alignment.bottomCenter,
                  followerAnchor: Alignment.topCenter,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return container;
  }

  void expectSettled(InMemoryPrivateJsonStorage storage, String unitId) {
    expect(
      (storage.snapshot['onboarding'] as Map)[onboardingFlagFields[unitId]],
      isTrue,
      reason: '$unitId 收场即置位（落盘）',
    );
  }

  group('注册表：步数与锚点次序', () {
    test('节拍提示 3 步：动画栏 → 声音栏 → 矫正栏', () {
      final steps = guideStepsOfUnit(badgeBeatPromptUnitId);
      expect(steps.length, 3);
      expect(steps.map((s) => s.anchorKey).toList(), [
        beatAnimationColumnAnchorKey,
        beatSoundColumnAnchorKey,
        beatCorrectColumnAnchorKey,
      ]);
    });

    test('倍速 1 步：只讲步进栏', () {
      final steps = guideStepsOfUnit(badgeSpeedUnitId);
      expect(steps.length, 1);
      expect(steps.single.anchorKey, speedStepColumnAnchorKey);
    });

    test('倍速单元说明非空', () {
      expect(guideUnitDescription(badgeSpeedUnitId), isNotEmpty);
    });

    test('音画同步 1 步：＋/－ 那一行（独立单元）', () {
      final steps = guideStepsOfUnit(badgeAvSyncUnitId);
      expect(steps.length, 1);
      expect(steps.map((s) => s.anchorKey).toList(), [
        avSyncDelayColumnAnchorKey,
      ]);
    });

    test('三处走查文案不含方位词（横竖屏重排不需要分支）', () {
      final messages = [
        for (final unitId in [
          badgeBeatPromptUnitId,
          badgeSpeedUnitId,
          badgeAvSyncUnitId,
        ])
          for (final step in guideStepsOfUnit(unitId))
            guideStepMessage(step.id),
      ];
      expect(messages.length, 5);
      // 只禁「指栏位所在位置」的方位词（左栏/下栏这一类）；「对上声音」
      // 这类动词补语不算。
      final directionPattern = RegExp(
        '左[栏侧边]|右[栏侧边]|上[方下面栏]|下[方面栏]|顶[部栏]|底[部栏]|旁边',
      );
      for (final message in messages) {
        expect(
          directionPattern.firstMatch(message),
          isNull,
          reason: '「$message」出现方位词，横竖屏会对不上',
        );
      }
    });

    test('节拍提示三步通篇不提三种状态', () {
      final beatMessages = [
        for (final step in guideStepsOfUnit(badgeBeatPromptUnitId))
          guideStepMessage(step.id),
      ];
      final statePattern = RegExp('未分析|分析中|已就绪');
      for (final message in beatMessages) {
        expect(statePattern.firstMatch(message), isNull);
      }
    });
  });

  group('节拍提示：3 步逐栏走查', () {
    testWidgets('首次打开：1/3 落动画栏 → 下一步落声音栏 → 矫正栏 → 走完置位', (tester) async {
      final storage = storageOf();
      final container = await pumpHost(
        tester,
        mode: SpeedBubbleMode.beat,
        storage: storage,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();

      final steps = guideStepsOfUnit(badgeBeatPromptUnitId);
      expect(find.text(guideStepMessage(steps[0].id)), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
      expectGuidePointsAt(tester, find.byKey(const Key('beat_anim_column')));

      await tester.tap(find.byKey(const Key('guide_next')));
      await tester.pumpAndSettle();
      expect(find.text(guideStepMessage(steps[1].id)), findsOneWidget);
      expectGuidePointsAt(tester, find.byKey(const Key('beat_sound_column')));
      // 讲解期间气泡本体与被讲的下一栏照原样在场可读（洞挖在该组上，
      // 压暗的只是别处）。
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      expect(find.text('声音反馈'), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide_next')));
      await tester.pumpAndSettle();
      expect(find.text(guideStepMessage(steps[2].id)), findsOneWidget);
      expectGuidePointsAt(
        tester,
        find.byKey(const Key('beat_correction_column')),
      );

      await tester.tap(find.byKey(const Key('guide_next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expectSettled(storage, badgeBeatPromptUnitId);

      // 只此一次：再开气泡不再出现。
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeBeatPromptUnitId),
      );
    });

    testWidgets('讲解期间气泡里的开关照常可用；关掉气泡即收场并置位', (tester) async {
      final storage = storageOf();
      final container = await pumpHost(
        tester,
        mode: SpeedBubbleMode.beat,
        storage: storage,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();

      // 高亮的那一栏里的总开关照常生效（洞内穿透）。
      final promptWasOn = container.read(beatPromptEnabledProvider);
      await tester.tap(find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pump();
      expect(container.read(beatPromptEnabledProvider), !promptWasOn);

      // 走查没走完就把气泡关掉：同样收场并置位，引导层消失。
      container.read(speedBubbleSessionProvider.notifier).close();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expectSettled(storage, badgeBeatPromptUnitId);
    });

    testWidgets('跳过即整单元置位；竖屏堆叠下锚点同样逐栏正确', (tester) async {
      final storage = storageOf();
      await pumpHost(
        tester,
        mode: SpeedBubbleMode.beat,
        storage: storage,
        narrowScreen: true,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();

      final steps = guideStepsOfUnit(badgeBeatPromptUnitId);
      expect(find.text(guideStepMessage(steps[0].id)), findsOneWidget);
      expectGuidePointsAt(tester, find.byKey(const Key('beat_anim_column')));

      await tester.tap(find.byKey(const Key('guide_skip')));
      await tester.pumpAndSettle();
      expectSettled(storage, badgeBeatPromptUnitId);
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
    });
  });

  group('倍速：1 步逐栏走查', () {
    testWidgets('首次打开：只一步、高亮落步进栏、不画步数；走完置位且只此一次', (tester) async {
      final storage = storageOf();
      final container = await pumpHost(
        tester,
        mode: SpeedBubbleMode.speed,
        storage: storage,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();

      final step = guideStepsOfUnit(badgeSpeedUnitId).single;
      expect(find.text(guideStepMessage(step.id)), findsOneWidget);
      expect(find.text('1/1'), findsNothing, reason: '单元只剩一步，不画步数指示');
      // 单步就地讲解只有 ✕（既有的单步形态），没有「下一步 / 跳过」。
      expect(find.byKey(const Key('guide_next')), findsNothing);
      expect(find.byKey(const Key('guide_skip')), findsNothing);
      expect(find.byKey(const Key('guide_close')), findsOneWidget);
      expectGuidePointsAt(tester, find.byKey(const Key('speed_step_column')));

      await tester.tap(find.byKey(const Key('guide_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expectSettled(storage, badgeSpeedUnitId);
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeSpeedUnitId),
      );

      // 只此一次：再开气泡不再出现。
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
    });

    testWidgets('走查没走完就把气泡关掉：同样收场并置位', (tester) async {
      final storage = storageOf();
      final container = await pumpHost(
        tester,
        mode: SpeedBubbleMode.speed,
        storage: storage,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsOneWidget);

      container.read(speedBubbleSessionProvider.notifier).close();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expectSettled(storage, badgeSpeedUnitId);
    });

    testWidgets('竖屏堆叠下同一份文案与锚点照常正确', (tester) async {
      final storage = storageOf();
      await pumpHost(
        tester,
        mode: SpeedBubbleMode.speed,
        storage: storage,
        narrowScreen: true,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      await tester.pumpAndSettle();

      final step = guideStepsOfUnit(badgeSpeedUnitId).single;
      expect(find.text(guideStepMessage(step.id)), findsOneWidget);
      expectGuidePointsAt(tester, find.byKey(const Key('speed_step_column')));

      await tester.tap(find.byKey(const Key('guide_close')));
      await tester.pumpAndSettle();
      expectSettled(storage, badgeSpeedUnitId);
    });
  });

  group('音画同步：1 步逐栏走查（第 9 个功能提示单元）', () {
    testWidgets('首次打开：单步落 ＋/－ 那一行；按框里的 ＋ 即置位', (tester) async {
      final storage = storageOf();
      final container = await pumpHost(
        tester,
        mode: SpeedBubbleMode.avSync,
        storage: storage,
      );
      await tester.tap(find.byKey(const Key('bubble_entry')));
      // 校准会话持续收脉冲（不可 pumpAndSettle）；判定链路是异步 Future
      // （状态位读）+ 锚点帧尾重查，固定推进若干帧到稳定。
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }

      final steps = guideStepsOfUnit(badgeAvSyncUnitId);
      expect(find.text(guideStepMessage(steps[0].id)), findsOneWidget);
      // 单步：不必多点一次「下一步」。
      expect(find.byKey(const Key('guide_next')), findsNothing);
      // 高亮框落在含 ＋/－ 的那一行上。
      expectGuidePointsAt(tester, find.byKey(const Key('av_sync_readout_row')));
      final rowRect = tester.getRect(
        find.byKey(const Key('av_sync_readout_row')),
      );
      final reported = container.read(
        guideAnchorRectsProvider,
      )[avSyncDelayColumnAnchorKey];
      expect(reported, rowRect, reason: '锚点矩形即 ＋/－ 那一行');
      expect(
        reported,
        isNot(tester.getRect(find.byKey(const Key('av_sync_slider')))),
        reason: '锚点在那一行上，不在滑条上',
      );
      expect(
        rowRect.contains(
          tester.getCenter(find.byKey(const Key('av_sync_minus'))),
        ),
        isTrue,
        reason: '高亮框包住 －',
      );
      expect(
        rowRect.contains(
          tester.getCenter(find.byKey(const Key('av_sync_plus'))),
        ),
        isTrue,
        reason: '高亮框包住 ＋',
      );

      // 框里那枚 ＋ 照常生效（排布与可点性逐位不变），按下即算做到。
      await tester.tap(find.byKey(const Key('av_sync_plus')));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(find.text('+10 ms'), findsOneWidget, reason: '＋ 照常步进一档');
      expectSettled(storage, badgeAvSyncUnitId);
      expect(
        container.read(guideSessionProvider).triggered,
        contains(badgeAvSyncUnitId),
      );
      expect(find.byKey(const Key('guide_bubble')), findsNothing);

      // 只此一次：再开气泡不再出现。
      await tester.tap(find.byKey(const Key('bubble_entry')));
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
    });
  });
}
