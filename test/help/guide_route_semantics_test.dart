import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart'
    show coverCacheProvider, coverGenerationQueueProvider;
import 'package:dance_learning_app/dance/cover_generation_queue.dart'
    show CoverGenerationQueue;
import 'package:dance_learning_app/help/content_registry.dart'
    show downloadVideoTutorialId;
import 'package:dance_learning_app/help/guide_host.dart' show GuideHost;
import 'package:dance_learning_app/help/guide_state.dart'
    show
        guideSessionProvider;
import 'package:dance_learning_app/help/help_documents.dart' show HelpContent, loadHelpContent;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_share_channel.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 真资产装载结果，懒算一次：卡的正文期望值从这一份现算。
HelpContent? _helpContentCache;

/// 一次性图文引导卡的路由语义：卡片是独立的
/// 界面区域（路由语义），模态底板不再是无名可点节点，卡内文字按阅读
/// 顺序可读——全部是读屏用户能听到/听不到的外部行为。
void main() {
  testWidgets('欢迎卡：卡片声明路由语义，底板不产生可点语义节点', (tester) async {
    final semantics = tester.ensureSemantics();

    final storage = InMemoryPrivateJsonStorage();
    await _pumpHome(tester, storage);

    // 卡片是路由：语义节点带 scopesRoute + namesRoute。
    final cardNode = tester.getSemantics(
      find.byKey(const Key('guide_one_shot')),
    );
    final cardData = cardNode.getSemanticsData();
    expect(
      cardData.flagsCollection.scopesRoute,
      isTrue,
      reason: '引导卡应是独立界面区域（scopesRoute）',
    );
    expect(cardData.flagsCollection.namesRoute, isTrue, reason: '引导卡应给这条路由起名');
    expect(cardData.role, SemanticsRole.dialog, reason: '引导卡是对话框');

    // 底板不再是无名可点节点：卡片自身与其每一层祖先（模态底板所在层）都
    // 不带点按动作——底板挡指针，但不在无障碍树里挡出一个可点节点。
    final root = RendererBinding
        .instance
        .rootPipelineOwner
        .semanticsOwner
        ?.rootSemanticsNode;
    final parents = <int, SemanticsNode>{};
    void record(SemanticsNode node) {
      for (final child in node.debugListChildrenInOrder(
        DebugSemanticsDumpOrder.traversalOrder,
      )) {
        parents[child.id] = node;
        record(child);
      }
    }

    if (root != null) record(root);
    var chainNode = cardNode;
    var depth = 0;
    while (true) {
      expect(
        chainNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
        reason: depth == 0 ? '引导卡本身不该是可点节点' : '引导卡第 $depth 层祖先（模态底板一侧）不该是可点节点',
      );
      final parent = parents[chainNode.id];
      if (parent == null) break;
      chainNode = parent;
      depth += 1;
    }

    // 卡内按钮仍可点（防止断言本身空转）。
    expect(_hasTapInSubtree(cardNode), isTrue, reason: '卡片按钮应可点');

    // 阅读顺序：标题在前，动作按钮在后；左「跳过教程」先于右「开始新手教程」。
    final labels = _labelsInTraversalOrder(cardNode);
    final titleIndex = labels.indexOf('欢迎使用 Susume');
    final skipIndex = labels.indexOf(welcomeSkipLabel);
    final tourIndex = labels.indexOf(welcomeTourLabel);
    expect(titleIndex, isNonNegative);
    expect(
      skipIndex,
      greaterThan(titleIndex),
      reason: '按钮应在标题之后被读到，实际顺序：$labels',
    );
    expect(
      tourIndex,
      greaterThan(skipIndex),
      reason: '左「跳过教程」应在右「开始新手教程」之前被读到，实际顺序：$labels',
    );
    semantics.dispose();
  });

  testWidgets('下载图文卡：文档标题在引言正文之前被读到', (tester) async {
    final semantics = tester.ensureSemantics();

    final storage = InMemoryPrivateJsonStorage();
    await _pumpHome(tester, storage);
    _helpContentCache ??= await loadHelpContent(rootBundle);

    // 从欢迎卡推进到下载图文卡（带文档卡片的一次性图文）。
    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);

    final cardNode = tester.getSemantics(
      find.byKey(const Key('guide_one_shot')),
    );
    final labels = _labelsInTraversalOrder(cardNode);

    final titleIndex = labels.indexOf('下载视频');
    expect(titleIndex, isNonNegative);
    final firstActionIndex = labels.indexWhere(
      (label) => label == '等会儿再下载' || label == '已经存好了',
    );
    expect(
      firstActionIndex > titleIndex,
      isTrue,
      reason: '按钮应在标题之后被读到，实际顺序：$labels',
    );

    // 卡片正文取教程第一个二级标题那一节，紧跟在文档标题之后被读到（阅读
    // 顺序）。期望的那一句按教程正文现算，改教程不必动本用例。
    final markdown = _downloadVideoMarkdown();
    final sectionHeading = markdown
        .split('\n')
        .firstWhere((line) => line.startsWith('## '))
        .substring(3)
        .trim();
    final sectionIndex = labels.indexOf(sectionHeading);
    expect(
      sectionIndex,
      greaterThan(titleIndex),
      reason: '小节正文应在文档标题之后，实际顺序：$labels',
    );
    expect(
      labels.any((label) => label.contains(_introLine(markdown))),
      isFalse,
      reason: '引言段与其后的方法不在卡里',
    );
    semantics.dispose();
  });
}

/// 「下载视频」教程的正文原文：一次性图文卡的期望值从这一份现算。
String _downloadVideoMarkdown() {
  final content = _helpContentCache;
  expect(content, isNotNull, reason: '用例开头已 await 过装配');
  final entry = content!.document(downloadVideoTutorialId);
  expect(entry, isNotNull, reason: downloadVideoTutorialId);
  return entry!.markdown;
}

/// 教程引言段那一行（一级标题之后、第一个二级标题之前的第一段）。
String _introLine(String markdown) => markdown
    .split('\n')
    .takeWhile((line) => !line.startsWith('## '))
    .map((line) => line.trim())
    .firstWhere((line) => line.isNotEmpty && !line.startsWith('#'));

/// [node] 子树里是否存在带点按动作的语义节点。
bool _hasTapInSubtree(SemanticsNode node) {
  if (node.getSemanticsData().hasAction(SemanticsAction.tap)) return true;
  for (final child in node.debugListChildrenInOrder(
    DebugSemanticsDumpOrder.traversalOrder,
  )) {
    if (_hasTapInSubtree(child)) return true;
  }
  return false;
}

/// 从 [node] 起按读屏的遍历顺序收集所有非空标签。
List<String> _labelsInTraversalOrder(SemanticsNode node) {
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final label = node.getSemanticsData().label.trim();
    if (label.isNotEmpty) labels.add(label);
    for (final child in node.debugListChildrenInOrder(
      DebugSemanticsDumpOrder.traversalOrder,
    )) {
      visit(child);
    }
  }

  visit(node);
  return labels;
}

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
  container.read(guideSessionProvider.notifier).clearUnit('first_run');
  await tester.pumpAndSettle();
  return container;
}
