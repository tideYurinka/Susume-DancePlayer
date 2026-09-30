import 'dart:async';

import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/drill_task_bar.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/help/player_drill.dart';
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/guide_copy_fixture.dart';

/// 手势演练层测试：演练进度随既有手势域读面推进（单指 / 双指 / 末步三个点击类子勾各
/// 一条，共三步）；末步不再要求单击；条子与编辑态上手共用停靠式待办条（勾
/// 选框、进度点、「跳过」，条身不吃触摸）。跳过不置位、三步走完置位。既有
/// 读面以测试内 provider 与手势反馈控制器直供，不依赖播放页装配。
void main() {
  /// 可写测试 provider：模拟既有域读面的变化。末步没有「控制层开合」这一项
  /// ——单击不再被要求，也没有任何读面能喂出这一勾。
  final transientRateActive = NotifierProvider<_TestValue<bool>, bool>(
    () => _TestValue(false),
  );
  final delayedPlayPreparing = NotifierProvider<_TestValue<bool>, bool>(
    () => _TestValue(false),
  );

  late InMemoryPrivateJsonStorage storage;
  late GestureFeedbackController feedback;
  late StreamController<void> playingFlips;
  var backgroundTaps = 0;

  Future<ProviderContainer> pumpDrill(WidgetTester tester) async {
    final input = PlayerDrillInput(
      scrub: DrillScrubFace(
        changes: feedback,
        isScrubbing: () => feedback.isScrubbing,
        startPointerCount: () => feedback.startPointerCount,
      ),
      playingFlips: playingFlips.stream,
      transientRateActive: transientRateActive,
      delayedPlayPreparing: delayedPlayPreparing,
    );
    late final ProviderContainer container;
    container = ProviderContainer(
      overrides: [
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // 条子底下的画面：条身覆盖区域里的手势应当落到它身上。
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => backgroundTaps++,
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
                PlayerDrill(input: input),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// 顺序走完前两步滑动手势（单指 → 双指），停在末步。
  Future<void> scrubToLastStep(WidgetTester tester) async {
    feedback.noteStartPointerCount(1);
    feedback.beginScrubbing();
    await pumpPastHold(tester);
    feedback.endScrubbing();
    feedback.noteStartPointerCount(2);
    feedback.beginScrubbing();
    await pumpPastHold(tester);
    feedback.endScrubbing();
  }

  setUp(() {
    storage = InMemoryPrivateJsonStorage();
    feedback = GestureFeedbackController();
    playingFlips = StreamController<void>.broadcast();
    backgroundTaps = 0;
  });

  tearDown(() => playingFlips.close());

  testWidgets('未看过：条子与编辑态那条同形同停靠位，含勾选框 / 进度点 / 跳过，并上报「演练进行中」', (tester) async {
    final container = await pumpDrill(tester);

    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_icon')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_checkbox')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_dots')), findsOneWidget);
    expect(find.textContaining(guideStepMessage(helpDrillSteps.first.id)), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byKey(const Key('drill_task_skip')), findsOneWidget);
    expect(
      container.read(guideSessionProvider).drillRunning,
      isTrue,
      reason: '演练进行期间宿主不出任何引导步（演练优先）',
    );

    // 停靠基准与编辑态那条同源：安全区顶 8、左右各 16（注）。
    final screenWidth = tester.view.physicalSize.width /
        tester.view.devicePixelRatio;
    final bar = tester.getRect(find.byKey(const Key('drill_task_bar')));
    expect(bar.top, closeTo(8, 0.5));
    expect(bar.left, closeTo(16, 0.5));
    expect(bar.right, closeTo(screenWidth - 16, 0.5));
  });

  testWidgets('已看过（状态位置位）：演练不再出现，也不上报「进行中」', (tester) async {
    storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'playerDrill': true},
      },
    );
    final container = await pumpDrill(tester);

    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(container.read(guideSessionProvider).drillRunning, isFalse);
  });

  testWidgets('单指滑：做到当场填勾、停约 0.4 秒再进第 2 步', (tester) async {
    await pumpDrill(tester);

    feedback.noteStartPointerCount(1);
    feedback.beginScrubbing();
    await tester.pump();

    expect(find.text('1/3'), findsOneWidget, reason: '停留期间仍停在本步');
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
      reason: '做到当场把待做勾选框填上',
    );

    await tester.pump(
      kDrillTaskBarAdvanceHold - const Duration(milliseconds: 50),
    );
    expect(find.text('1/3'), findsOneWidget, reason: '未满停留时长不推进');

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('双指滑：进度拖动且起始手指数 ≥ 2 → 打勾推进', (tester) async {
    await pumpDrill(tester);

    // 先做完单指步（顺序演练），再做双指。
    feedback.noteStartPointerCount(1);
    feedback.beginScrubbing();
    await pumpPastHold(tester);
    feedback.endScrubbing();

    feedback.noteStartPointerCount(2);
    feedback.beginScrubbing();
    await pumpPastHold(tester);

    expect(find.text('3/3'), findsOneWidget);
  });

  testWidgets('末步三个子勾各一条：双击 / 双指双击 / 长按，做对一个亮一个', (tester) async {
    final container = await pumpDrill(tester);
    await scrubToLastStep(tester);
    expect(find.text('3/3'), findsOneWidget);

    IconData chipIcon(String id) => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(Key('drill_task_sub_$id')),
            matching: find.byType(Icon),
          ),
        )
        .icon!;

    // 双击暂停/播放：播放态翻转一次。
    playingFlips.add(null);
    await tester.pump();
    await tester.pump();
    expect(chipIcon('drill_double_tap'), Icons.check_circle);

    // 双指双击延迟播放：延迟播放会话开始。
    container.read(delayedPlayPreparing.notifier).state = true;
    await tester.pump();
    await tester.pump();
    expect(chipIcon('drill_two_finger_double_tap'), Icons.check_circle);

    // 长按临时 2 倍速：临时倍速会话开始。
    container.read(transientRateActive.notifier).state = true;
    await tester.pump();
    await tester.pump();
    expect(chipIcon('drill_long_press'), Icons.check_circle);
  });

  testWidgets('末步只做齐两个子勾不收场：待做勾不填、不置位', (tester) async {
    final container = await pumpDrill(tester);
    await scrubToLastStep(tester);
    expect(find.text('3/3'), findsOneWidget);

    playingFlips.add(null);
    await tester.pump();
    await tester.pump();
    container.read(delayedPlayPreparing.notifier).state = true;
    await tester.pump();
    await tester.pump();

    // 三个子勾只做了两个：末步仍停着等最后一个，待做勾还没填。
    await pumpPastHold(tester);
    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box_outline_blank,
    );
    expect(container.read(guideSessionProvider).drillRunning, isTrue);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['playerDrill'] ?? false,
      isFalse,
      reason: '三个子勾做齐才收场（全部做到才置位）',
    );
  });

  testWidgets('三步走完置位：单指滑 / 双指滑 / 末步三个子勾做齐 → 停留 → 置位不再出现', (tester) async {
    final container = await pumpDrill(tester);

    await scrubToLastStep(tester);
    expect(find.text('3/3'), findsOneWidget);

    // 三个点击类动作：双击 → 双指双击 → 长按。全程没有、也无法再做「单击
    // 唤出控制层」（输入值对象里已没有这一项读面）。
    playingFlips.add(null);
    await tester.pump();
    container.read(delayedPlayPreparing.notifier).state = true;
    await tester.pump();
    container.read(transientRateActive.notifier).state = true;
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
      reason: '三个子勾齐了，末步的待做勾也被填上',
    );

    await pumpPastHold(tester);

    // 演练收场：不再出现，状态位置位，「进行中」撤回。
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(container.read(guideSessionProvider).drillRunning, isFalse);
    expect(storage.snapshot['onboarding']['playerDrill'], isTrue);
  });

  test('待办条「做到即停」的时长是独立字面量：0.4 秒', () {
    expect(kDrillTaskBarAdvanceHold, const Duration(milliseconds: 400));
  });

  testWidgets('步数与子勾数：3 步、末步 3 个点击类子勾（不再有单击），无三指滑步', (tester) async {
    // 步 id 与子勾 id 是注册表结构：钉住它们属结构回归，改动即真契约变更。
    expect(helpDrillSteps.length, 3);
    expect(
      helpDrillSteps.map((s) => s.id).toList(),
      ['drill_single_finger', 'drill_two_finger', 'drill_taps'],
    );
    expect(
      helpDrillSteps.last.subChecks.map((s) => s.id).toList(),
      ['drill_double_tap', 'drill_two_finger_double_tap', 'drill_long_press'],
    );
    expect(
      [
        for (final s in helpDrillSteps.last.subChecks)
          guideSubCheckLabel(helpDrillSteps.last.id, s.id),
      ],
      everyElement(isNotEmpty),
      reason: '末步每个子勾片都有随包文案',
    );
    expect(
      helpDrillSteps
          .expand((step) => step.subChecks)
          .map((sub) => sub.id)
          .where((id) => id.contains('single_tap')),
      isEmpty,
      reason: '不再要求、也不再记「单击唤出控制层」这一勾',
    );
  });

  testWidgets('手机宽度下三步条子都不溢出（真机 361 逻辑宽）', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    await pumpDrill(tester);

    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    void expectFits(int stepIndex) {
      expect(tester.takeException(), isNull, reason: '第 ${stepIndex + 1} 步');
      final bar = tester.getRect(find.byKey(const Key('drill_task_bar')));
      expect(bar.left, greaterThanOrEqualTo(0));
      expect(bar.right, lessThanOrEqualTo(screenWidth));
    }

    expectFits(0);

    // 第 1 步（单指滑）→ 第 2 步（双指滑）→ 第 3 步（末步）。
    feedback.noteStartPointerCount(1);
    feedback.beginScrubbing();
    await pumpPastHold(tester);
    expectFits(1);
    feedback.endScrubbing();
    feedback.noteStartPointerCount(2);
    feedback.beginScrubbing();
    await pumpPastHold(tester);

    // 第 3 步带三个子勾片。
    expect(find.text('3/3'), findsOneWidget);
    for (final sub in helpDrillSteps.last.subChecks) {
      expect(find.byKey(Key('drill_task_sub_${sub.id}')), findsOneWidget);
      expect(
        find.text(guideSubCheckLabel(helpDrillSteps.last.id, sub.id)),
        findsOneWidget,
      );
    }
    expectFits(2);
  });

  testWidgets('条身除「跳过」外不吃触摸：条子覆盖区域里的手势照常落到画面上', (tester) async {
    await pumpDrill(tester);

    await tester.tapAt(
      tester.getCenter(find.textContaining(guideStepMessage(helpDrillSteps.first.id))),
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('drill_task_dot_0'))),
    );
    await tester.pump();

    expect(backgroundTaps, 2, reason: '条身数处点击都穿透到其下的画面');
  });

  testWidgets('离开播放页（挂载销毁）：撤回「进行中」，不压住别处的引导步', (tester) async {
    final container = await pumpDrill(tester);
    expect(container.read(guideSessionProvider).drillRunning, isTrue);

    // 页面销毁（pop / 换页）即演练不再在屏；不撤回会永久压住宿主。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(container.read(guideSessionProvider).drillRunning, isFalse);
  });

  testWidgets('跳过：条子消失但不置位，下次从头做，「进行中」撤回', (tester) async {
    final container = await pumpDrill(tester);

    await tester.tap(find.byKey(const Key('drill_task_skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(
      container.read(guideSessionProvider).drillRunning,
      isFalse,
      reason: '跳过演练不等于放弃后续教学（编辑态上手照常出现）',
    );
    expect(
      (storage.snapshot['onboarding'] as Map?)?['playerDrill'] ?? false,
      isFalse,
    );
  });

  testWidgets('中途退出不置位：下次进播放页从头做', (tester) async {
    await pumpDrill(tester);
    feedback.noteStartPointerCount(1);
    feedback.beginScrubbing();
    await pumpPastHold(tester);

    // 换页销毁后重新挂载：仍从未置位的第一条步开始。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final container = await pumpDrill(tester);

    expect(find.text('1/3'), findsOneWidget);
    expect(container.read(guideSessionProvider).drillRunning, isTrue);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['playerDrill'] ?? false,
      isFalse,
    );
  });
}

/// 越过停留：勾已填上约 0.4 秒后推进到下一步。
Future<void> pumpPastHold(WidgetTester tester) async {
  await tester.pump(
    kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50),
  );
  await tester.pump();
}

/// 可写测试值：模拟既有域读面的取值与变化。
class _TestValue<T> extends Notifier<T> {
  _TestValue(this._initial);

  final T _initial;

  @override
  T build() => _initial;

  // 测试驱动：直接赋 state。
}
