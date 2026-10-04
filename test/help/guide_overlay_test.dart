import 'dart:async';

import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart'
    show
        badgeSegmentFlagUnitId,
        downloadVideoTutorialId,
        importVideoAnchorKey,
        segmentLineAnchorKeyBase;
import 'package:dance_learning_app/help/guide_anchor.dart'
    show GuideAnchor, guideAnchorRectsProvider;
import 'package:dance_learning_app/help/guide_host.dart' show GuideHost;
import 'package:dance_learning_app/help/guide_state.dart'
    show OnboardingStore, guideSessionProvider, onboardingStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/fake_share_channel.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

import 'package:dance_learning_app/dance/cover_frame_providers.dart'
    show coverCacheProvider, coverGenerationQueueProvider;
import 'package:dance_learning_app/dance/cover_generation_queue.dart'
    show CoverGenerationQueue;

void main() {
  testWidgets('未看过首启：先弹欢迎图文，指认收场前单元不置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await _pumpHome(tester, storage);

    // 首启第 1 段是模态欢迎图文：只有卡片自己的按钮。
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map?)?['firstRun'], isNull);
  });

  testWidgets('指认步：高亮区圈住导入钮 + 气泡一句话 + ✕，单步无步数指示', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = await _pumpHome(tester, storage);
    await _reachPointingStep(tester, container: container);

    // 引导真的指向「导入视频」钮：气泡紧贴该钮、箭头对准钮中心。
    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));

    // 单步讲解：一句话 + ✕，没有「下一步 / 跳过 / N/M」。
    expect(find.text(guideStepMessage('first_run_import')), findsOneWidget);
    expect(find.text('教程收起来了；以后想看就点这里'), findsNothing);
    expect(find.byKey(const Key('guide_close')), findsOneWidget);
    expect(find.byKey(const Key('guide_next')), findsNothing);
    expect(find.byKey(const Key('guide_skip')), findsNothing);
    expect(find.textContaining('/'), findsNothing);
    // ✕ 报出主动语态中文名。
    expectButtonSemantics(tester, const Key('guide_close'), label: '关闭引导');
  });

  testWidgets('高亮框里的控件保持可用：按它照样生效，框外的入口仍被吞掉', (tester) async {
    var insideTaps = 0;
    var outsideTaps = 0;
    final container = ProviderContainer(
      overrides: [
        onboardingStorageProvider.overrideWithValue(
          OnboardingStore(InMemoryPrivateJsonStorage()),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                // 首启「已经存好了」支指认锚的就是这个控件。
                Positioned(
                  left: 40,
                  top: 40,
                  child: GuideAnchor(
                    anchorKey: importVideoAnchorKey,
                    child: GestureDetector(
                      onTap: () => insideTaps++,
                      child: Container(
                        key: const Key('import_video_button'),
                        width: 120,
                        height: 120,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                // 框外的入口：压暗期间按不动。
                Positioned(
                  left: 40,
                  top: 600,
                  child: GestureDetector(
                    onTap: () => outsideTaps++,
                    child: Container(
                      key: const Key('outside_button'),
                      width: 120,
                      height: 120,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _resetFirstRunSession(container);
    await tester.pumpAndSettle();
    await _reachPointingStep(tester, container: container);
    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));

    // 框外被吞掉正是本测试要断言的行为：命中失败警告在此为预期，不打印。
    await tester.tap(
      find.byKey(const Key('outside_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(outsideTaps, 0, reason: '框外的入口照旧被压暗吞掉');

    // 框内按下即做到：同一下照常落到被指的控件上，且讲解收场。
    await tester.tap(find.byKey(const Key('import_video_button')));
    await tester.pumpAndSettle();
    expect(insideTaps, 1, reason: '高亮框里的控件保持可用：指了它就得按得动');
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
  });

  testWidgets('单步指认：点压暗处不推进也不收场，只有 ✕ 能收场', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = ProviderContainer(
      overrides: [
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 40,
                  top: 40,
                  child: GuideAnchor(
                    anchorKey: importVideoAnchorKey,
                    child: SizedBox(
                      key: const Key('import_video_button'),
                      width: 120,
                      height: 120,
                    ),
                  ),
                ),
                // 压暗处的一个无关控件：点它不触发它、也不推进讲解。
                Positioned(
                  left: 40,
                  top: 600,
                  child: GestureDetector(
                    onTap: () {},
                    child: SizedBox(
                      key: const Key('outside_button'),
                      width: 120,
                      height: 120,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _resetFirstRunSession(container);
    await tester.pumpAndSettle();
    await _reachPointingStep(tester, container: container);
    expect(find.text(guideStepMessage('first_run_import')), findsOneWidget);

    // 点压暗处：单步讲解不推进也不收场。
    await tester.tap(
      find.byKey(const Key('outside_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text(guideStepMessage('first_run_import')), findsOneWidget);
    expect((storage.snapshot['onboarding'] as Map?)?['firstRun'], isNull);

    // ✕ 收场即置位。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['firstRun'], isTrue);
  });

  testWidgets('单步讲解：只有 ✕，点压暗处不推进也不收场', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    final container = ProviderContainer(
      overrides: [
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                // 单步单元「标记分段线」锚的就是这个控件（分段单元是两步，
                // 不再是单步讲解用例的样本）。
                Positioned(
                  left: 40,
                  top: 40,
                  child: GuideAnchor(
                    anchorKey: segmentLineAnchorKeyBase,
                    child: SizedBox(
                      key: const Key('segment_line'),
                      width: 120,
                      height: 120,
                    ),
                  ),
                ),
                Positioned(
                  left: 40,
                  top: 600,
                  child: GestureDetector(
                    onTap: () {},
                    child: SizedBox(
                      key: const Key('outside_button'),
                      width: 120,
                      height: 120,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    container
        .read(guideSessionProvider.notifier)
        .trigger(badgeSegmentFlagUnitId);
    await tester.pumpAndSettle();
    expect(find.text('标记是给这一段做个记号，回头一眼找到这一处'), findsOneWidget);
    // 单步只有 ✕：无「下一步」、无「跳过」、无步数指示。
    expect(find.byKey(const Key('guide_close')), findsOneWidget);
    expect(find.byKey(const Key('guide_next')), findsNothing);
    expect(find.byKey(const Key('guide_skip')), findsNothing);
    expect(find.textContaining('/'), findsNothing);

    // 点压暗处：不推进也不收场；✕ 之外无处可点。
    await tester.tap(
      find.byKey(const Key('outside_button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('标记是给这一段做个记号，回头一眼找到这一处'), findsOneWidget);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['badgeSegmentFlag'],
      isNull,
    );

    // ✕ 收场即置位。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_bubble')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['badgeSegmentFlag'], isTrue);
  });

  testWidgets('细目标的最小宽度：1px 的线也点得着（洞两侧 10px 内仍在洞里）', (tester) async {
    var besideTaps = 0;
    final storage = InMemoryPrivateJsonStorage();
    final container = ProviderContainer(
      overrides: [
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (_, child) => GuideHost(child: child!),
          home: Scaffold(
            body: Stack(
              children: [
                // 1px 宽的「线」：首启「已经存好了」支指认锚的就是它。
                Positioned(
                  left: 100,
                  top: 40,
                  child: GuideAnchor(
                    anchorKey: importVideoAnchorKey,
                    child: Container(
                      key: const Key('thin_line'),
                      width: 1,
                      height: 120,
                      color: Colors.blue,
                    ),
                  ),
                ),
                // 距线中心约 10px 的控件：不放宽下限时它已在洞外、会被压暗
                // 吞掉；有 24 逻辑像素下限时它在洞内、点得着。
                Positioned(
                  left: 106,
                  top: 40,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => besideTaps++,
                    child: SizedBox(
                      key: const Key('beside_button'),
                      width: 9,
                      height: 120,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _resetFirstRunSession(container);
    await tester.pumpAndSettle();
    await _reachPointingStep(tester, container: container);
    expect(find.byKey(const Key('guide_bubble')), findsOneWidget);

    await tester.tap(find.byKey(const Key('beside_button')));
    await tester.pumpAndSettle();
    expect(besideTaps, 1, reason: '洞宽下限 24 逻辑像素：1px 细目标两侧仍在洞内，点得着');
  });

  testWidgets('锚点矩形变动即重演：不依赖其它帧源（真机首启锚点会挪位）', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = await _pumpHome(tester, storage);
    await _reachPointingStep(tester, container: container);
    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));

    // 真机首启：窗口尺寸就绪前锚点先报了一次退化矩形，随后才挪到位；演出层
    // 必须跟着最后一次上报走，而不是停最先那次。
    final host = ProviderScope.containerOf(
      tester.element(find.byType(GuideHost)),
      listen: false,
    );
    final moved = tester
        .getRect(find.byKey(const Key('import_video_button')))
        .shift(const Offset(-40, -120));
    host
        .read(guideAnchorRectsProvider.notifier)
        .report(importVideoAnchorKey, moved);
    expect(tester.binding.hasScheduledFrame, isTrue, reason: '上报后须排一帧');
    await tester.pump();

    final card = tester.getRect(find.byKey(const Key('guide_bubble')));
    final block = card.expandToInclude(
      tester.getRect(find.byKey(const Key('guide_arrow'))),
    );
    expect(
      (moved.top - block.bottom).abs(),
      lessThanOrEqualTo(40),
      reason: '提示块应贴住新的锚点矩形（$moved / 提示块 $block）',
    );
    expect(
      tester.getCenter(find.byKey(const Key('guide_arrow'))).dx,
      closeTo(moved.center.dx, 1),
      reason: '箭头应跟着新矩形走',
    );
  });

  testWidgets('锚点不在当前表面：撤下矩形不画引导层，回到该表面再出现', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final container = await _pumpHome(tester, storage);
    await _reachPointingStep(tester, container: container);
    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));

    // push 一层路由压住首页：首页锚点仍在树里、仍在布局，但它不是当前
    // 表面上的东西，不能拿它去画引导（跨表面残留会让框指向错的地方）。
    final navigator = Navigator.of(
      tester.element(find.byKey(const Key('import_video_button'))),
    );
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(find.byKey(const Key('guide_bubble')), findsNothing);

    // 回到首页：首启步还没走完，引导重新指向导入钮。
    navigator.pop();
    await tester.pumpAndSettle();
    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));
  });

  testWidgets('已看过首启：不出现引导层，界面照常可交互', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: const {
        'onboarding': {'firstRun': true},
      },
    );
    await _pumpHome(tester, storage);

    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(find.byKey(const Key('guide_one_shot')), findsNothing);
    expect(find.byKey(const Key('guide_close')), findsNothing);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
  });

  testWidgets('首启三段顺序推进：欢迎 → 下载图文 → 指认，都走完才置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await _pumpHome(tester, storage);

    // 欢迎卡：选「开始新手教程」后出现「下载视频」图文（与帮助中心教程同源），
    // 单元尚未置位。
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    expect(find.text(downloadVideoTutorialId), findsOneWidget);
    expect((storage.snapshot['onboarding'] as Map?)?['firstRun'], isNull);

    // 下载图文「已经存好了」：推进到指认步，锚在导入钮上；单元仍未置位。
    await tester.tap(find.text('已经存好了'));
    await tester.pumpAndSettle();
    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));
    expect((storage.snapshot['onboarding'] as Map?)?['firstRun'], isNull);

    // 指认步收场：整单元置位，之后不再出现（含重启）。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['firstRun'], isTrue);

    await _pumpHome(tester, storage);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(find.byKey(const Key('guide_one_shot')), findsNothing);
  });

  testWidgets('「跳过教程」同样走指认收场：两支都置位，重启后不再出现', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await _pumpHome(tester, storage);

    // 跳过图文直接指认「帮助」，收场即置位（指认这一步关掉才算走完）。
    await tester.tap(find.text(welcomeSkipLabel));
    await tester.pumpAndSettle();
    expectGuidePointsAt(tester, find.byKey(const Key('home_help_entry')));
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['firstRun'], isTrue);

    await _pumpHome(tester, storage);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(find.byKey(const Key('guide_one_shot')), findsNothing);
  });

  testWidgets('状态位写入失败静默：关闭仍生效，不弹错、不崩界面', (tester) async {
    final storage = _ThrowingPrivateJsonStorage();
    final container = await _pumpHome(tester, storage);

    await _reachPointingStep(tester, container: container);
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _ThrowingPrivateJsonStorage implements PrivateJsonStorage {
  @override
  Future<Map<String, dynamic>> read() async => const {};

  @override
  Future<void> write(Map<String, dynamic> json) async {
    throw Exception('disk full');
  }

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    mutate,
  ) async {
    throw Exception('disk full');
  }
}

///  沿用仓内首页部件测试的装配：内存替身覆盖落盘与引擎 provider。
Future<ProviderContainer> _pumpHome(
  WidgetTester tester,
  PrivateJsonStorage storage,
) async {
  tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(initial: VideoIndex.empty),
        ),
        practiceStatsStoreProvider.overrideWithValue(
          PracticeStatsStore(InMemoryPracticeStatsStorage()),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => InMemoryVideoDocumentStorage(),
        ),
        coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
        coverGenerationQueueProvider.overrideWith(
          (ref) => CoverGenerationQueue(run: (_) async => false),
        ),
        shareChannelProvider.overrideWithValue(FakeShareChannel()),
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GuideHost)),
  );
  // riverpod 3 的会话 provider 状态随测试进程存活、跨用例不随 ProviderScope
  // 重建：每次装配清掉首启的本会话进度，用例从欢迎卡起算。
  _resetFirstRunSession(container);
  return container;
}

/// 清掉首启的本会话进度（riverpod 3 的会话 provider 状态随测试进程存活、
/// 跨用例不随 ProviderScope 重建）。
void _resetFirstRunSession(ProviderContainer container) {
  container.read(guideSessionProvider.notifier).clearUnit('first_run');
}

/// 从欢迎卡走到首启指认步：欢迎卡选「开始新手教程」，下载图文再选
/// [downloadAction]。
Future<void> _reachPointingStep(
  WidgetTester tester, {
  required ProviderContainer container,
  String downloadAction = '已经存好了',
}) async {
  await tester.tap(find.text(welcomeTourLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(downloadAction));
  await tester.pumpAndSettle();
}
