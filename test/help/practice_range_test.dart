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
import 'package:dance_learning_app/help/guide_state.dart'
    show guideResetProvider, guideSessionProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationTimelineProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_band_session.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/guide_units_harness.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/pump_settle.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/guide_copy_fixture.dart';

/// 首尾线：首次进编辑态且轨道上已有学习段时，
/// 排在编辑态上手之后同屏圈出头线与尾线，气泡只指头线；轮到该步时把轨道
/// 铺开成整片（本会话一次），一句话讲含义、不要求操作；无学习段不出现、
/// 不被消耗。
void main() {
  testWidgets('真轨道装配：编辑态上手走完后首尾线接上，两枚锚点各圈一圈；关掉即置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final session = trackBandSession();
    await _pumpTrackBandHost(tester, storage: storage, session: session);

    // 编辑态上手第 ① 步先出（触达由轨道带接线；注册表序里它在前）：首尾线
    // 不抢。全片视野下第一段已宽于 44，判据①即过。
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    await _advanceToLineHandle(tester);
    await _leaveLineHandle(tester);

    // 首尾线立刻接上：一句话气泡，两枚锚点矩形都在场、两圈都画，气泡指头线。
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsOneWidget);
    expectGuidePointsAt(
      tester,
      find.byKey(const Key('practice_range_head_line')),
    );
    expect(
      guideRects(tester)[practiceRangeTailAnchorKey],
      isNotNull,
      reason: '尾线锚点矩形在场：两圈同屏才画得出来',
    );
    // 两枚锚点各画一圈白色描边（位置 = 板报锚点矩形外扩 guideHoleInflate）。
    final strokeRects = <Rect>[];
    expect(
      find.byKey(const Key('guide_highlight')),
      paints..everything((method, arguments) {
        if (method != #drawRect) return true;
        final paint = arguments[1];
        if (paint is Paint &&
            paint.style == PaintingStyle.stroke &&
            paint.color == Colors.white) {
          strokeRects.add(arguments[0] as Rect);
        }
        return true;
      }),
    );
    final anchorRects = guideRects(tester);
    for (final key in const [
      practiceRangeHeadAnchorKey,
      practiceRangeTailAnchorKey,
    ]) {
      expect(
        strokeRects,
        contains(anchorRects[key]!.inflate(guideHoleInflate)),
        reason: '$key 应各被圈一圈（锚点 $anchorRects / 描边 $strokeRects）',
      );
    }
    expect(
      (storage.snapshot['onboarding'] as Map)['practiceRange'],
      isNull,
      reason: '单元未收场不置位',
    );

    // 关掉 = 收场：置位、不再出现。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['practiceRange'], isTrue);
  });

  testWidgets('放大态进入该步：两条线都落在放大窗口之外，铺开后窗口回全片、两条都可圈', (tester) async {
    // 60s 的舞：自动设好的练习范围 = 全片（0–60s）。走完编辑态上手前两步、
    // 第 ③ 步还挂着时，用户自己把视野放大到中段——那一刻 0s 的头线与 60s 的
    // 尾线都落在窗口之外，这一步讲的东西根本不在屏上。
    final storage = InMemoryPrivateJsonStorage();
    final session = trackBandSession(duration: const Duration(seconds: 60));
    await _pumpTrackBandHost(
      tester,
      storage: storage,
      session: session,
      duration: const Duration(seconds: 60),
    );
    await tester.pumpAndSettle();
    await _advanceToLineHandle(tester);
    session.updateWindow(
      const TimelineWindow(
        total: Duration(seconds: 60),
        start: Duration(seconds: 5),
        end: Duration(seconds: 15),
      ),
    );
    await tester.pumpAndSettle();
    expect(guideRects(tester)[practiceRangeHeadAnchorKey], isNull);

    // 收掉编辑态上手第 ③ 步：轮到首尾线那一步，铺开不依赖锚点已上报——
    // 窗口回全片正是触发条件生效的那一刻，两枚锚点随之都在场、两圈框都画、
    // 气泡指头线。
    await _leaveLineHandle(tester);
    expect(session.window, isNull, reason: '轮到该步时窗口复位为全片');
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsOneWidget);
    expect(guideRects(tester)[practiceRangeHeadAnchorKey], isNotNull);
    expect(guideRects(tester)[practiceRangeTailAnchorKey], isNotNull);
    expectGuidePointsAt(
      tester,
      find.byKey(const Key('practice_range_head_line')),
    );
  });

  testWidgets('铺开只做一次：此后自己放大平移、收起再展开控制层都不再被拉回', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final session = trackBandSession();
    await _pumpTrackBandHost(tester, storage: storage, session: session);
    await _advanceToPracticeRange(tester);

    expect(session.window, isNull, reason: '轮到该步时先铺开成整片');
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsOneWidget);

    // 收场（✕）：本单元的铺开已经花掉。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect((storage.snapshot['onboarding'] as Map)['practiceRange'], isTrue);

    // 此后用户自己放大到中段：视野不再被拉回。
    const zoomed = TimelineWindow(
      total: Duration(seconds: 30),
      start: Duration(seconds: 9),
      end: Duration(seconds: 11),
    );
    session.updateWindow(zoomed);
    await tester.pumpAndSettle();
    expect(
      session.window!.start,
      const Duration(seconds: 9),
      reason: '自己缩放的视野保留',
    );

    // 平移同样保留。
    session.updateWindow(zoomed.pannedBy(const Duration(seconds: 5)));
    await tester.pumpAndSettle();
    expect(
      session.window!.start,
      const Duration(seconds: 14),
      reason: '自己平移的视野保留',
    );

    // 收起再展开控制层（本带连同它的 widget 状态重建）：视野不被拉回——本
    // 单元在本会话里已经收场，铺开照常只做一次。
    await _remountTrackBand(tester);
    expect(
      session.window!.start,
      const Duration(seconds: 14),
      reason: '收起再展开控制层后视野不被拉回',
    );
    expect(find.byKey(const Key('guide_bubble')), findsNothing);

    // 重置该单元：本会话进度（含「已铺开过」这一份）一并清掉，该单元重新被
    // 触达时铺开照常再做一次。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(GuideHost)),
      listen: false,
    );
    await container.read(guideResetProvider).resetUnit(practiceRangeUnitId);
    await tester.pumpAndSettle();
    session.updateWindow(
      const TimelineWindow(
        total: Duration(seconds: 30),
        start: Duration(seconds: 9),
        end: Duration(seconds: 11),
      ),
    );
    await tester.pumpAndSettle();
    container.read(guideSessionProvider.notifier).trigger(practiceRangeUnitId);
    await tester.pumpAndSettle();
    expect(session.window, isNull, reason: '重置后该单元重新触达，铺开照常再做一次');
    expect(find.text('这两条线圈出练习范围：圈外的部分不参与分段和循环'), findsOneWidget);
  });

  test('铺开的时机：排在首尾线前面的编辑态上手全走完（或整单元收场）才轮到它', () {
    final editorIntroStepIds = [
      for (final step in helpGuideSteps)
        if (step.unitId == editorIntroUnitId) step.id,
    ];
    expect(
      guideUnitStepsDone(editorIntroUnitId, editorIntroStepIds.toSet()),
      isTrue,
    );
    expect(
      guideUnitStepsDone(
        editorIntroUnitId,
        editorIntroStepIds.take(editorIntroStepIds.length - 1).toSet(),
      ),
      isFalse,
    );
    expect(guideUnitStepsDone(editorIntroUnitId, const {}), isFalse);
  });

  testWidgets('关掉后新手引导页对应行变已完成（带「重置」）', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'practiceRange': true},
      },
    );
    await pumpGuideUnitsHarness(tester, storage: storage);
    await openGuideUnitsPage(tester);

    final row = find.byKey(const Key('guide_unit_$practiceRangeUnitId'));
    expect(
      find.descendant(of: row, matching: find.text('已完成')),
      findsOneWidget,
    );
    expect(find.byKey(Key('guide_reset_$practiceRangeUnitId')), findsOneWidget);
  });

  testWidgets('该步还没收场时收起再展开控制层：视野不再被拉回（本会话只铺开一次）', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final session = trackBandSession();
    await _pumpTrackBandHost(tester, storage: storage, session: session);
    await _advanceToPracticeRange(tester);
    expect(session.window, isNull);

    // 还在这一步（没关掉）时把视野收小、再收起展开控制层：本带连同它的
    // widget 状态重建，但「本会话已铺开过」这一份进度在会话面里，视野不被
    // 拉回。
    session.updateWindow(
      const TimelineWindow(
        total: Duration(seconds: 30),
        start: Duration(seconds: 9),
        end: Duration(seconds: 11),
      ),
    );
    await tester.pumpAndSettle();
    await _remountTrackBand(tester);
    await tester.pumpAndSettle();
    expect(
      session.window!.start,
      const Duration(seconds: 9),
      reason: '本会话只铺开一次：重建后不再拉回',
    );
  });

  testWidgets('轨道上没有学习段：首尾线不出现、也不被消耗，窗口一位不变', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final session = trackBandSession();
    const zoomed = TimelineWindow(
      total: Duration(seconds: 30),
      start: Duration(seconds: 9),
      end: Duration(seconds: 11),
    );
    session.updateWindow(zoomed);
    await _pumpTrackBandHost(
      tester,
      storage: storage,
      session: session,
      withSegmentLine: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect(find.byKey(const Key('drill_task_bar')), findsNothing);
    expect(
      session.window!.start,
      const Duration(seconds: 9),
      reason: '无学习段不动窗口',
    );
    expect(storage.snapshot['onboarding'], isNull);
  });

  test('次序：首尾线排在编辑态上手全部步之后（注册表序即推进序）', () {
    final editorIntroIndexes = [
      for (var i = 0; i < helpGuideSteps.length; i++)
        if (helpGuideSteps[i].unitId == editorIntroUnitId) i,
    ];
    final practiceRangeIndex = helpGuideSteps.indexWhere(
      (s) => s.unitId == practiceRangeUnitId,
    );
    expect(practiceRangeIndex, greaterThan(editorIntroIndexes.last));
  });

  test('文案只讲含义：不含「拖/拉/点/按/滑」等操作动词', () {
    final step = helpGuideSteps.firstWhere(
      (s) => s.unitId == practiceRangeUnitId,
    );
    expect(step.form, GuideUnitForm.inplaceTour);
    for (final verb in ['拖', '拉', '点', '按', '滑']) {
      expect(
        guideStepMessage(step.id).contains(verb),
        isFalse,
        reason: '文案含「$verb」',
      );
    }
  });
}

/// 真轨道装配用的会话域（假引擎），测试可在挂载前先设好窗口。
TrackBandSession trackBandSession({
  Duration duration = const Duration(seconds: 30),
}) => buildTrackBandSession(engine: FakePlaybackEngine(duration: duration));

/// 从编辑态上手第 ① 步走到第 ③ 步（就地讲解「线上的小把手」）：第 ① 步的
/// 判据当场成立、停约 0.4 秒推进到第 ② 步；点第一段循环 → 第 ③ 步。
Future<void> _advanceToLineHandle(WidgetTester tester) async {
  await tester.pump(
    kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50),
  );
  await tester.pumpAndSettle();
  expect(find.textContaining(editorIntroLoopSentence), findsOneWidget);
  await tester.tap(find.byKey(const Key('learning_segment_0')));
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(
    kDrillTaskBarAdvanceHold + const Duration(milliseconds: 50),
  );
  await tester.pumpAndSettle();
  expect(find.text('线上的小把手可以拖着挪'), findsOneWidget);
}

/// 收掉编辑态上手第 ③ 步（「下一步」，3/3 的最后一步即整单元收场）。
Future<void> _leaveLineHandle(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('guide_next')));
  await tester.pumpAndSettle();
}

/// 从编辑态上手一路走到首尾线步。
Future<void> _advanceToPracticeRange(WidgetTester tester) async {
  await _advanceToLineHandle(tester);
  await _leaveLineHandle(tester);
}

/// 装配里的 Riverpod 容器。
ProviderContainer guideContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(GuideHost)),
      listen: false,
    );

/// 锚点矩形板现值（哪个锚点在屏上报了矩形）。
Map<String, Rect> guideRects(WidgetTester tester) =>
    guideContainer(tester).read(guideAnchorRectsProvider);

/// 真机轨道带装配：一条分段线落在 10s（派生两段学习段），引导宿主包住整页。
Future<void> _pumpTrackBandHost(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
  required TrackBandSession session,
  bool withSegmentLine = true,
  Duration duration = const Duration(seconds: 30),
  Size view = const Size(800, 1400),
}) async {
  // 合成档视口（入参 view，默认 800×1400dp；dpr 1.0），非设备档。
  tester.view.physicalSize = view;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final engine = FakePlaybackEngine(duration: duration);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(storage),
        annotationTimelineProvider.overrideWithBuild(
          (ref, _) => AnnotationTimeline.normalized(
            videoDuration: duration,
            segmentLines: withSegmentLine
                ? const [SegmentLine(position: Duration(seconds: 10))]
                : const [],
          ),
        ),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) =>
              uniformReadyBeatState(seconds: duration.inSeconds.toDouble()),
        ),
      ],
      child: _TrackBandHarness(session: session),
    ),
  );
  await pumpSettle(tester);
  // riverpod 的会话 provider 状态随测试进程存活、跨用例不随 ProviderScope
  // 重建：每次装配清掉本单元的本会话进度，用例各自从零起算。
  final container = guideContainer(tester);
  container.read(guideSessionProvider.notifier).clearUnit(practiceRangeUnitId);
  if (withSegmentLine) {
    // 清进度把本带挂载时触达面刚记下的那次触达一并清掉了：装配前提既在，
    // 补回这一次。
    container.read(guideSessionProvider.notifier).trigger(practiceRangeUnitId);
  }
}

/// 收起再展开控制层 = 本带连同它的会话状态从树上撤下又装回：宿主与容器原样
/// 留着，只有本带那一支进出（会话进度因此在，本带的 widget 状态因此不在）。
Future<void> _remountTrackBand(WidgetTester tester) async {
  final harness = tester.state<_TrackBandHarnessState>(
    find.byType(_TrackBandHarness),
  );
  harness.setMounted(false);
  await tester.pumpAndSettle();
  harness.setMounted(true);
  await pumpSettle(tester);
}

/// 轨道带宿主（本带进出用）：引导宿主与容器留在树上，本带按 [mounted] 进出。
class _TrackBandHarness extends StatefulWidget {
  const _TrackBandHarness({required this.session});

  final TrackBandSession session;

  @override
  State<_TrackBandHarness> createState() => _TrackBandHarnessState();
}

class _TrackBandHarnessState extends State<_TrackBandHarness> {
  bool _mounted = true;

  void setMounted(bool mounted) => setState(() => _mounted = mounted);

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (_, child) => GuideHost(child: child!),
    home: Scaffold(
      body: _mounted
          ? TrackBand(
              input: TrackBandInput(
                session: widget.session,
                rowTable: TrackRowTable.normal,
              ),
            )
          : const SizedBox.shrink(),
    ),
  );
}
