import 'dart:async';

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
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
import 'package:dance_learning_app/help/player_drill.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationTimelineProvider;
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/pump_settle.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/guide_copy_fixture.dart';

/// 编辑态上手「动手两步 + 讲解一步」在引导宿主
/// 接缝上的行为：①放大判据（第一段段体在屏、渲染宽 ≥44 逻辑像素，放大
/// 别处不算）②激活判据（第一段被激活过一次）③就地讲解锚第一条分段线的
/// 小把手；三步次序、做到当场填勾并停约 0.4 秒再推进、跳过即整单元置位、
/// 锚点不在当前表面即退场且不被消耗、收场后首尾线立刻接上、动手期间不出
/// 别的引导步。
void main() {
  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(GuideHost)),
        listen: false,
      );

  testWidgets('三步次序与两个动手判据：放大第一段才进第 2 步、激活第一段才进第 3 步，走完置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final segmentWidth = ValueNotifier<double>(20);
    addTearDown(segmentWidth.dispose);
    var segmentTaps = 0;
    await _pumpAnchorHost(
      tester,
      storage: storage,
      segmentWidth: segmentWidth,
      onSegmentTap: () => segmentTaps++,
    );
    final container = containerOf(tester);
    container
        .read(guideSessionProvider.notifier)
        .trigger(practiceRangeUnitId);

    // 第 1 步：停靠式待办条（无遮罩气泡、无「下一步」——推进只看判据）。
    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text(guideStepMessage('editor_intro_zoom')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_checkbox')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_skip')), findsOneWidget);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(find.byKey(const Key('guide_next')), findsNothing);
    // 高亮框跟着第一段段体：不压暗、不挖洞、不拦触摸；白色描边（与就地
    // 讲解的高亮框同色——主题主色画在视频画面上看不清）。
    expect(find.byKey(const Key('drill_anchor_highlight')), findsOneWidget);
    expect(
      find.byKey(const Key('drill_anchor_highlight')),
      paints..rect(color: Colors.white, style: PaintingStyle.stroke),
      reason: '跟随高亮框描白色边',
    );
    // 锚点在屏：条子贴在自己那圈高亮框旁，不再停靠安全区顶。贴框基准是
    // **画出来的高亮框矩形**（段体 20 逻辑像素宽时短边扩到 24 下限那一份）。
    expectDrillBarAnchoredTo(
      tester,
      guideHoleRect(
        tester.getRect(find.byKey(const Key('learning_segment_0'))),
      ),
    );
    // 箭头指得准那一段：段体只有 20 宽、框被扩到 24，箭头仍对准段体中心。
    expect(
      tester.getCenter(find.byKey(const Key('drill_task_arrow'))).dx,
      closeTo(
        tester.getCenter(find.byKey(const Key('learning_segment_0'))).dx,
        1,
      ),
    );
    // 段体初始渲染宽 20 < 44：不推进。
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);

    // 只放大别处不算：别的锚点变宽，第 1 步仍在。
    container
        .read(guideAnchorRectsProvider.notifier)
        .report(segmentLineAnchorKeyBase, const Rect.fromLTWH(0, 0, 300, 48));
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);

    // 第一段段体渲染宽到 44 逻辑像素（双指捏合或拉缩放滑条都体现为段体矩形
    // 变宽，判据同一）：做到当场填勾，仍停在第 1 步（停留期间中间态）。
    segmentWidth.value = 44;
    await _pumpToCheck(tester);
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
      reason: '做到即当场把勾选框填上勾',
    );
    expect(find.text('1/3'), findsOneWidget, reason: '停留期间还没进下一步');
    expect(
      find.byKey(const Key('drill_anchor_highlight')),
      findsOneWidget,
      reason: '高亮框随锚点放大仍在场，不掉',
    );
    expect((storage.snapshot['onboarding'] as Map?)?['editorIntro'], isNull);

    // 约 0.4 秒后推进到第 2 步；单元未走完不置位。
    await _pumpPastHold(tester);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.textContaining(editorIntroLoopSentence), findsOneWidget);
    expect((storage.snapshot['onboarding'] as Map?)?['editorIntro'], isNull);

    // 第 2 步判据 = 第一段被激活过一次：harness 里点段体只计数（激活事实由
    // 播放域记入），未记入前不推进。
    await tester.tap(find.byKey(const Key('learning_segment_0')));
    await tester.pumpAndSettle();
    expect(segmentTaps, 1, reason: '气泡讲的「点这一段」必须真的点得动');
    expect(find.text('2/3'), findsOneWidget);

    container
        .read(guideSessionProvider.notifier)
        .latch(HandsOnCriterion.editorIntroActivate);
    await _pumpToCheck(tester);
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
    );
    await _pumpPastHold(tester);

    // 第 3 步：就地讲解，锚在第一条分段线的小把手上。
    expect(find.byKey(const Key('guide_bubble')), findsOneWidget);
    expect(find.text('线上的小把手可以拖着挪'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
    expectGuidePointsAt(tester, find.byKey(const Key('segment_line_0_handle')));
    expect(
      find.byKey(const Key('guide_highlight')),
      paints
        ..rect(color: Colors.black54)
        ..rect()
        ..rect(color: Colors.white, style: PaintingStyle.stroke),
      reason: '就地讲解的高亮框也是白色描边——两种高亮框同一色',
    );

    // 走完第 3 步：整单元置位，此后不再出现；首尾线那一步立刻接上（气泡
    // 即首尾线步，编辑态上手的提示条与文案一起消失）。
    await tester.tap(find.byKey(const Key('guide_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.byKey(const Key('drill_anchor_highlight')), findsNothing);
    expect(find.text('线上的小把手可以拖着挪'), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['editorIntro'], isTrue);
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsOneWidget);
    expectGuidePointsAt(
      tester,
      find.byKey(const Key('practice_range_head_line')),
    );
  });

  testWidgets('两指张开放大：框与条子同帧重排，段体 20 逐步喂到 300 两条关系仍成立、条宽不近满宽', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final segmentWidth = ValueNotifier<double>(20);
    addTearDown(segmentWidth.dispose);
    await _pumpAnchorHost(
      tester,
      storage: storage,
      segmentWidth: segmentWidth,
    );
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;

    for (final width in const [20.0, 44.0, 150.0, 300.0]) {
      segmentWidth.value = width;
      // 段体变宽 → 锚点帧尾重报 → 宿主下一帧按新矩形重排（同帧关系）。
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      final segment = tester.getRect(
        find.byKey(const Key('learning_segment_0')),
      );
      expect(segment.width, closeTo(width, 0.5));
      // 贴框基准是画出来的框：20 宽时段体短边扩到 24 下限，箭头仍指得准。
      expectDrillBarAnchoredTo(tester, guideHoleRect(segment));

      final bar = tester.getRect(find.byKey(const Key('drill_task_bar')));
      expect(bar.width, closeTo(320, 1), reason: '条宽上限 320、不近满宽');
      expect(bar.right - bar.left, lessThan(screenWidth - 2 * 16));
      // 一句话在这个条宽下排成两行，仍整句完整在屏内。
      final message = tester.getRect(
        find.text(guideStepMessage('editor_intro_zoom')),
      );
      expect(
        message.height,
        greaterThan(24),
        reason: '本断言覆盖「一句话排成两行」的情形',
      );
      expect(message.left, greaterThanOrEqualTo(0));
      expect(message.right, lessThanOrEqualTo(screenWidth));
      expect(message.top, greaterThanOrEqualTo(0));
      expect(message.bottom, lessThanOrEqualTo(screenHeight));
    }
  });

  testWidgets('跳过 = 整单元置位；收场后首尾线那一步立刻接上', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await _pumpAnchorHost(tester, storage: storage);
    final container = containerOf(tester);
    container
        .read(guideSessionProvider.notifier)
        .trigger(practiceRangeUnitId);
    await tester.pumpAndSettle();

    // 动手第 1 步在屏时跳过：整单元一次置位。
    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('drill_task_skip')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['editorIntro'], isTrue);
    // 收场（含跳过）后首尾线立刻接上：高亮落在区间头线。
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsOneWidget);
    expectGuidePointsAt(
      tester,
      find.byKey(const Key('practice_range_head_line')),
    );

    // 重启（同一状态位）不再出现。
    await _pumpAnchorHost(tester, storage: storage, segmentWidth: null);
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
  });

  testWidgets('锚点不在当前表面（收起控制层）：两步退场、不被消耗，重新展开从没做完的那一步接着', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final segmentWidth = ValueNotifier<double>(20);
    addTearDown(segmentWidth.dispose);
    final controlsOpen = ValueNotifier<bool>(true);
    addTearDown(controlsOpen.dispose);
    await _pumpAnchorHost(
      tester,
      storage: storage,
      segmentWidth: segmentWidth,
      controlsOpen: controlsOpen,
    );

    expect(find.text('1/3'), findsOneWidget);
    // 做完第 1 步，停在未做完的第 2 步。
    segmentWidth.value = 44;
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    expect(find.text('2/3'), findsOneWidget);

    // 收起控制层：锚点从屏上撤下 → 两步立刻退场、也不被消耗。
    controlsOpen.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.byKey(const Key('drill_anchor_highlight')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map?)?['editorIntro'], isNull);

    // 重新展开：从没做完的第 2 步接着，已做过的第 1 步不重来。
    controlsOpen.value = true;
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    expect(find.textContaining(editorIntroLoopSentence), findsOneWidget);
    expect(find.text(guideStepMessage('editor_intro_zoom')), findsNothing);
  });

  testWidgets('轨道上还没有学习段：不出现、也不消耗状态位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await _pumpAnchorHost(tester, storage: storage, segmentsPresent: false);

    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.byKey(const Key('drill_anchor_highlight')), findsNothing);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(storage.snapshot['onboarding'], isNull);
  });

  testWidgets('引导重置：判据进度一并清掉，动手两步从第 1 步重头', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final segmentWidth = ValueNotifier<double>(20);
    addTearDown(segmentWidth.dispose);
    await _pumpAnchorHost(tester, storage: storage, segmentWidth: segmentWidth);
    final container = containerOf(tester);

    // 走到第 3 步（判据①②都已满足）。
    segmentWidth.value = 44;
    container
        .read(guideSessionProvider.notifier)
        .latch(HandsOnCriterion.editorIntroActivate);
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    expect(find.text('3/3'), findsOneWidget);

    // 重置：状态位之外，本会话的判据进度与触达一并清掉——须再次走到触发点
    // 才可能再出现。
    await container.read(guideResetProvider).resetUnit(editorIntroUnitId);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);

    // 重新触达（模拟再次进编辑态）：从第 1 步重头。
    container
        .read(guideSessionProvider.notifier)
        .trigger(editorIntroUnitId);
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text(guideStepMessage('editor_intro_zoom')), findsOneWidget);
    // 激活闩已清：不重新做到判据②就推不进第 3 步。判据①过 → 第 2 步。
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('3/3'), findsNothing);
  });

  testWidgets('动手步进行期间不出别的引导步；手势演练进行期间连编辑态上手也不出，收场后立刻恢复', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final segmentWidth = ValueNotifier<double>(20);
    addTearDown(segmentWidth.dispose);
    await _pumpAnchorHost(tester, storage: storage, segmentWidth: segmentWidth);
    final container = containerOf(tester);

    // 动手步进行中：触达一枚既有角标，不插话（注册表序里编辑态上手在前）。
    // 一枚锚点在本 harness 已在场的单步角标（分段单元是两步、其锚点
    // 不在此 harness 上，改由「标记分段线」当这条「分段落场后立刻接上」的
    // 样本）。
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);

    // 手势演练进行中：屏幕归演练，编辑态上手也不出。
    container.read(guideSessionProvider.notifier).setDrillRunning(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);

    // 演练收场：动手步立刻回来。
    container.read(guideSessionProvider.notifier).setDrillRunning(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);

    // 编辑态上手整单元收场后：被触达的角标立刻出现。
    segmentWidth.value = 44;
    container
        .read(guideSessionProvider.notifier)
        .latch(HandsOnCriterion.editorIntroActivate);
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    expect(find.text('3/3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('guide_skip')));
    await tester.pumpAndSettle();
    // 编辑态上手整单元收场后：被触达的角标立刻出现。
    expect(find.text('标记是给这一段做个记号，回头一眼找到这一处'), findsOneWidget);
  });

  testWidgets('真轨道装配：点第一段激活即进第 3 步，点别的段不算', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await _pumpTrackBandHost(tester, storage: storage);

    // 默认全片视野下第一段段体已宽于 44：第 1 步判据即过，填勾后停约 0.4 秒
    // 推进到第 2 步。
    await _pumpPastHold(tester);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.textContaining(editorIntroLoopSentence), findsOneWidget);

    // 点别的段（第 2 段）不算。
    await tester.tap(find.byKey(const Key('learning_segment_1')));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);

    // 点第一段段体把它循环起来：第 3 步立刻接上，锚第一条分段线的小把手。
    await tester.tap(find.byKey(const Key('learning_segment_0')));
    await _pumpToCheck(tester);
    await _pumpPastHold(tester);
    expect(find.byKey(const Key('guide_bubble')), findsOneWidget);
    expect(find.text('线上的小把手可以拖着挪'), findsOneWidget);
    expectGuidePointsAt(tester, find.byKey(const Key('segment_line_0_handle')));
  });

  testWidgets('真演练层收场即解禁：跳过演练后编辑态上手动手步立刻出现', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    final feedback = GestureFeedbackController();
    final playingFlips = StreamController<void>.broadcast();
    addTearDown(playingFlips.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          home: GuideHost(
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  GuideBadgeTrigger(
                    unitId: editorIntroUnitId,
                    child: GuideAnchor(
                      anchorKey: learningSegment0AnchorKey,
                      child: Container(
                        key: const Key('learning_segment_0'),
                        width: 20,
                        height: 40,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  PlayerDrill(
                    input: PlayerDrillInput(
                      scrub: DrillScrubFace(
                        changes: feedback,
                        isScrubbing: () => feedback.isScrubbing,
                        startPointerCount: () => feedback.startPointerCount,
                      ),
                      playingFlips: playingFlips.stream,
                      transientRateActive: _drillTransientRate,
                      delayedPlayPreparing: _drillDelayedPlay,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 演练在屏（它与编辑态上手共用同一条待办条）：编辑态上手被压住——
    // 条子上是演练第 1 步，而不是编辑态上手第 1 步。
    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(find.textContaining(guideStepMessage(helpDrillSteps.first.id)), findsOneWidget);
    // （演练与编辑态上手都是三步，「N/M」不再可判别，按文案区分。）
    expect(find.text(guideStepMessage(helpGuideSteps.first.id)), findsNothing);

    // 跳过演练：动手步立刻出现（同一条待办条换成编辑态上手第 1 步）。
    await tester.tap(find.byKey(const Key('drill_task_skip')));
    await tester.pumpAndSettle();

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text(guideStepMessage('editor_intro_zoom')), findsOneWidget);
    expect(
      find.textContaining(guideStepMessage(helpDrillSteps.first.id)),
      findsNothing,
      reason: '演练收场后不再占着条子',
    );
  });
}

/// 判据成立后跑出勾选态（停留期间的中间态）：零时长多帧，不越过停留时长。
Future<void> _pumpToCheck(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// 越过停留：勾已填上约 0.4 秒后推进到下一步。
Future<void> _pumpPastHold(WidgetTester tester) async {
  await tester.pump(
    kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50),
  );
  await tester.pumpAndSettle();
}

/// 演练读面的可写测试替身（本文件只驱动演练收场，不驱动手势）。
final _drillTransientRate = NotifierProvider<_TestValue<bool>, bool>(
  () => _TestValue(false),
);
final _drillDelayedPlay = NotifierProvider<_TestValue<bool>, bool>(
  () => _TestValue(false),
);

class _TestValue<T> extends Notifier<T> {
  _TestValue(this._initial);

  final T _initial;

  @override
  T build() => _initial;
}

/// 引导宿主接缝的最小装配：编辑态上手的三枚锚点 + 第一段段体的触达面（复用
/// 播放域的 [GuideBadgeTrigger] 范式）。段体宽度经 [segmentWidth] 可写，模拟
/// 双指捏合 / 缩放滑条把第一段放大；[controlsOpen] 可写，模拟收起 / 展开控制
/// 层带走整条轨道带（锚点卸载）；另有首尾线头线锚点与一枚单步角标作对照。
Future<void> _pumpAnchorHost(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
  ValueNotifier<double>? segmentWidth,
  ValueNotifier<bool>? controlsOpen,
  bool segmentsPresent = true,
  VoidCallback? onSegmentTap,
}) async {
  tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final width = segmentWidth ?? ValueNotifier<double>(20);
  if (segmentWidth == null) addTearDown(width.dispose);

  Widget editorIntroAnchors() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GuideBadgeTrigger(
        unitId: editorIntroUnitId,
        child: GuideAnchor(
          anchorKey: learningSegment0AnchorKey,
          child: ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, segmentWidth, _) => GestureDetector(
              onTap: onSegmentTap,
              child: Container(
                key: const Key('learning_segment_0'),
                width: segmentWidth,
                height: 40,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
      GuideAnchor(
        anchorKey: segmentLine0HandleAnchorKey,
        child: Container(
          key: const Key('segment_line_0_handle'),
          width: 24,
          height: 4,
          color: Colors.white,
        ),
      ),
      GuideAnchor(
        anchorKey: practiceRangeHeadAnchorKey,
        child: Container(
          key: const Key('practice_range_head_line'),
          width: 4,
          height: 40,
          color: Colors.orange,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        home: GuideHost(
          child: Scaffold(
            body: Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (controlsOpen == null)
                    if (segmentsPresent)
                      editorIntroAnchors()
                    else
                      const SizedBox.shrink()
                  else
                    ValueListenableBuilder<bool>(
                      valueListenable: controlsOpen,
                      builder: (_, open, _) => open && segmentsPresent
                          ? editorIntroAnchors()
                          : const SizedBox.shrink(),
                    ),
                  GuideAnchor(
                    anchorKey: segmentLineAnchorKeyBase,
                    child: IconButton(
                      key: const Key('segment_line'),
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

/// 真机轨道带装配：一条分段线落在 10s（派生两段学习段），引导宿主包住整页。
Future<void> _pumpTrackBandHost(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
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
        annotationTimelineProvider.overrideWithBuild(
          (ref, _) => AnnotationTimeline.normalized(
            videoDuration: const Duration(seconds: 30),
            segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
          ),
        ),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) => uniformReadyBeatState(seconds: 30),
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
}
