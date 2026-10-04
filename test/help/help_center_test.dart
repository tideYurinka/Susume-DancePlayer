import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/dance/cover_frame_providers.dart'
    show coverCacheProvider, coverGenerationQueueProvider;
import 'package:dance_learning_app/dance/cover_generation_queue.dart'
    show CoverGenerationQueue;
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_units_page.dart';
import 'package:dance_learning_app/help/help_center_page.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_share_channel.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/guide_copy_fixture.dart';

/// 真资产装载结果，懒算一次：目录结构、标题与小节断言都按这一份现算。
HelpContent? _helpContentCache;

Future<HelpContent> _loadedHelpContent() async =>
    _helpContentCache ??= await loadHelpContent(rootBundle);

/// 已经取到的那一份；由 [setUpAll] 保证填好（各用例都在它之后跑）。
HelpContent _loadedHelpContentSync() {
  final content = _helpContentCache;
  expect(content, isNotNull, reason: 'setUpAll 已装载过真资产');
  return content!;
}

/// 手册各章的显示标题（正文一级标题），按目录数字前缀序。取自装载结果自己，
/// 改章节标题不必动本套件。
List<String> get _chapterDisplayTitles => [
  for (final chapter in _loadedHelpContentSync().manualChapters)
    chapter.displayTitle,
];

/// 帮助中心：目录条目集合与顺序、标题与一句说明
/// 由正文现算、缺图条目只用图标方框、章节页与教程页渲染 Markdown 正文、
/// 引导页列出全部单元、首页帮助钮 push 帮助中心。
void main() {
  group('扫到的目录表', () {
    late HelpContent content;
    setUpAll(() async {
      content = await _loadedHelpContent();
    });

    test('使用手册：各章标题、一句说明与次序由正文与目录前缀现算', () {
      final chapters = content.manualChapters;
      expect(chapters, isNotEmpty, reason: '手册分组不该是空的');

      // 次序按目录数字前缀升序；标题取正文一级标题、一句说明取标题后第一段。
      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        expect(chapter.displayTitle, isNotEmpty, reason: chapter.directory);
        expect(chapter.title, chapter.displayTitle, reason: chapter.directory);
        expect(
          chapter.listDescription,
          isNotEmpty,
          reason: chapter.displayTitle,
        );
        if (i > 0) {
          expect(
            _numberPrefix(chapter.directory),
            greaterThan(_numberPrefix(chapters[i - 1].directory)),
            reason: '${chapter.directory} 应排在 ${chapters[i - 1].directory} 之后',
          );
        }
      }
    });

    test('各章的二级小节按正文次序，标题逐条取正文原文', () {
      for (final chapter in content.manualChapters) {
        final titles = _secondLevelHeadings(content, chapter.id);
        expect(
          titles,
          everyElement(isNotEmpty),
          reason: '${chapter.displayTitle} 有空的二级标题',
        );
        expect(
          titles.toSet(),
          hasLength(titles.length),
          reason: '${chapter.displayTitle} 的二级标题有重复，锚点会撞车',
        );
      }
    });

    test('引导步承诺的那句手势在手册正文里同口径出现', () {
      // 同口径 = 引导步那一句话的核心说法在手册某章正文里找得到。核心说法从
      // 引导文案自己切出来、章也不指定，两侧都不钉死写了什么。
      final stepMessage = guideStepMessage('badge_three_finger_jump_step');
      final core = _corePhraseOf(stepMessage);
      expect(core, isNotEmpty, reason: '引导步那一句话是口径来源：$stepMessage');

      final hit = content.manualChapters
          .where((chapter) => chapter.markdown.contains(core))
          .toList();
      expect(
        hit.map((chapter) => chapter.displayTitle).toList(),
        hasLength(1),
        reason:
            '「$core」应在手册里恰好一章讲，实际：'
            '${content.manualChapters.map((c) => c.displayTitle).toList()}',
      );
    });

    test('教程：目录 id 取目录名，标题取正文一级标题，次序按数字前缀', () {
      final tutorials = content.tutorials;
      expect(tutorials, isNotEmpty, reason: '教程分组不该是空的');

      // 与手册分组同一口径：id 由目录名现算、标题取正文一级标题、说明非空、
      // 次序按目录数字前缀——改教程内容与增删条目都不必动本用例。
      for (var i = 0; i < tutorials.length; i++) {
        final tutorial = tutorials[i];
        expect(tutorial.id, helpDocumentIdOfDirectory(tutorial.directory));
        expect(tutorial.displayTitle, isNotEmpty, reason: tutorial.directory);
        expect(tutorial.listDescription, isNotEmpty, reason: tutorial.id);
        if (i > 0) {
          expect(
            _numberPrefix(tutorial.directory),
            greaterThan(_numberPrefix(tutorials[i - 1].directory)),
            reason:
                '${tutorial.directory} 应排在 ${tutorials[i - 1].directory} 之后',
          );
        }
      }
    });

    test('「免费视频变清晰」作为第二条教程被扫到，说明与图标照常', () {
      final entry = content.document('免费视频变清晰');
      expect(entry, isNotNull);
      // 装载结果里不再有「列表缩略图」这一项：行图标按 id 查表取。
      expect(entry!.listDescription, isNotEmpty);
      expect(
        helpEntryIcon(entry.id, fallbackIcon: helpTutorialEntryFallbackIcon),
        Icons.auto_fix_high,
      );
    });

    test('引导表声明 14 个单元，含 id、形态、标题与一句话', () {
      expect(helpGuideUnits, hasLength(14));
      expect(
        helpGuideUnits.map((u) => u.id).toSet().length,
        14,
        reason: '单元 id 与状态位一一对应，不得重复',
      );
      for (final unit in helpGuideUnits) {
        expect(guideUnitTitle(unit.id), isNotEmpty);
        expect(guideUnitDescription(unit.id), isNotEmpty);
      }
      expect(GuideUnitForm.values, hasLength(4));
      expect(helpGuideSteps.map((s) => s.form).toSet(), {
        GuideUnitForm.inplaceTour,
        GuideUnitForm.handsOnDrill,
        GuideUnitForm.transientHint,
        GuideUnitForm.oneShotCard,
      }, reason: '名册短暂提示、首启一次性图文与编辑态上手动手两步都落演出层步表');
      expect(
        helpGuideUnits.any((u) => u.id == playerDrillUnitId),
        isTrue,
        reason: '动手演练单元照常在册',
      );
    });
  });

  group('帮助中心页', () {
    testWidgets('一屏可见：新手引导入口卡 + 教程 4 条 + 使用手册 10 章，顺序固定', (tester) async {
      await _pumpCenter(tester);

      final firstItem = _topOf(tester, find.text('新手引导'));
      final tutorialHeader = _topOf(tester, find.text('教程'));
      final tutorial = _topOf(tester, find.text('下载视频'));
      final manualHeader = _topOf(tester, find.text('使用手册'));
      final chapterTops = [
        for (final title in _chapterDisplayTitles)
          _topOf(tester, find.text(title)),
      ];

      // 教程排在手册之前，开页即见。
      expect(firstItem.dy, lessThan(tutorialHeader.dy));
      expect(tutorialHeader.dy, lessThan(tutorial.dy));
      expect(tutorial.dy, lessThan(manualHeader.dy));
      for (var i = 1; i < chapterTops.length; i++) {
        expect(chapterTops[i - 1].dy, lessThan(chapterTops[i].dy));
      }
      expect(manualHeader.dy, lessThan(chapterTops.first.dy));
    });

    testWidgets('列表项 = 图标方框 + 标题 + 一句说明；每行图标按 id 查表', (tester) async {
      await _pumpCenter(tester);

      // 已登记十四条：每行左缘都出一枚图标方框，框内即登记表里那枚图标
      // （登记表本身的取值由 help_assets_test 全量钉住）。
      for (final entry in helpEntryIcons.entries) {
        expect(
          find.descendant(
            of: find.byKey(helpEntryKey(entry.key)),
            matching: find.byIcon(entry.value),
          ),
          findsOneWidget,
          reason: entry.key,
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('点章节与教程都渲染 Markdown 正文', (tester) async {
      await _loadedHelpContent();
      await _pumpCenter(tester);

      // 章与教程都从装载结果里现取，正文断言用它们自己的标题与小节名——改哪
      // 一章、哪一篇的内容都不必动本用例。
      final chapter = _loadedHelpContentSync().manualChapters.first;
      final chapterSections = _secondLevelHeadings(
        _loadedHelpContentSync(),
        chapter.id,
      );
      await tester.tap(find.text(chapter.displayTitle));
      await tester.pumpAndSettle();
      expect(find.byType(HelpDocumentPage), findsOneWidget);
      expect(find.byKey(const Key('help_document_markdown')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(chapter.title!),
        ),
        findsOneWidget,
        reason: '章节页标题取正文一级标题',
      );
      for (final section in chapterSections) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('下载视频'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpDocumentPage), findsOneWidget);
      // 正文来自那条教程自己的一级标题之后的段落，渲染成 Markdown 正文区。
      expect(find.text(_firstSectionHeading('下载视频')), findsOneWidget);
    });

    testWidgets('点「问题反馈」进文档页', (tester) async {
      await _pumpCenter(tester);

      await tester.tap(find.text('问题反馈'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpDocumentPage), findsOneWidget);
      expect(find.byKey(const Key('help_document_markdown')), findsOneWidget);
    });

    testWidgets('章节页把该章各级小节按正文次序渲染出来', (tester) async {
      await _loadedHelpContent();
      await _pumpCenter(tester);

      // 挑标题层级最全的一章来断言渲染：只挑「有小节」的章会漏掉三级、四级
      // 标题的渲染。章与标题都从装载结果里现找、现算，改章节内容不必动用例。
      final chapter = _richestHeadingChapter(_loadedHelpContentSync());
      final titles = _allHeadingTitles(chapter.markdown);
      expect(
        _headingLevels(chapter.markdown).length,
        greaterThan(1),
        reason: '样本章要覆盖不止一级标题，否则断言不到层级渲染',
      );

      await tester.tap(find.text(chapter.displayTitle));
      await tester.pumpAndSettle();
      expect(find.byType(HelpDocumentPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 一级标题只出现在标题栏（正文里不再重复那一行）；其余各级标题逐条上屏。
      final bodyTitles = [
        for (final title in titles)
          if (title != chapter.title) title,
      ];
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(chapter.title!),
        ),
        findsOneWidget,
        reason: '章节页标题取正文一级标题',
      );
      for (final title in bodyTitles) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      final onScreen = [
        for (final title in bodyTitles) _topOf(tester, find.text(title)).dy,
      ];
      for (var i = 1; i < onScreen.length; i++) {
        expect(
          onScreen[i - 1],
          lessThan(onScreen[i]),
          reason: '${bodyTitles[i - 1]} 应排在 ${bodyTitles[i]} 之前',
        );
      }
    });

    testWidgets('概览章里点《下载视频》跨条目链接，进那篇教程', (tester) async {
      await _pumpCenter(tester);

      await tester.tap(find.text('Susume使用概览'));
      await tester.pumpAndSettle();
      expect(find.byType(HelpDocumentPage), findsOneWidget);

      await tester.tapOnText(find.textRange.ofSubstring('《下载视频》'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('下载视频')),
        findsOneWidget,
        reason: '落在《下载视频》教程页',
      );
      expect(find.text(_firstSectionHeading('下载视频')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('首项进新手引导，列出 14 个引导单元（标题 + 一句说明）', (tester) async {
      await _pumpCenter(tester);

      await tester.tap(find.text('新手引导'));
      await tester.pumpAndSettle();
      expect(find.byType(GuideUnitsPage), findsOneWidget);
      expect(find.byKey(const Key('guide_unit_first_run')), findsOneWidget);
      expect(find.byKey(const Key('guide_unit_player_drill')), findsOneWidget);
      for (final unit in helpGuideUnits) {
        expect(find.byKey(Key('guide_unit_${unit.id}')), findsOneWidget);
        expect(find.text(guideUnitTitle(unit.id)), findsOneWidget);
        expect(find.text(guideUnitDescription(unit.id)), findsOneWidget);
      }
    });
  });

  group('首页入口', () {
    testWidgets('顶栏动作 [帮助, ⋯]：帮助钮在 ⋯ 左边，点开 push 帮助中心', (tester) async {
      await _pumpHome(tester);

      final helpButton = find.byKey(const Key('home_help_entry'));
      final moreButton = find.byKey(const Key('home_more_menu'));
      expect(helpButton, findsOneWidget);
      expect(moreButton, findsOneWidget);
      expect(
        tester.getTopLeft(helpButton).dx,
        lessThan(tester.getTopLeft(moreButton).dx),
      );

      await tester.tap(helpButton);
      await tester.pumpAndSettle();
      expect(find.byType(HelpCenterPage), findsOneWidget);
      expect(find.text('新手引导'), findsOneWidget);
      expect(find.text('下载视频'), findsOneWidget);
    });
  });
}

Offset _topOf(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder.first);

/// 一句话里的核心说法：按中文句读切开后最长的那一段。用来断言手册正文与引导
/// 文案同口径，两侧都不必钉死原句。
String _corePhraseOf(String message) {
  final parts = message
      .split(RegExp(r'[，。；：、,.;:!?！？\s]+'))
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return message.trim();
  parts.sort((a, b) => b.length.compareTo(a.length));
  return parts.first;
}

/// 该条正文里用到的标题层级（1 起），升序去重。
List<int> _headingLevels(String markdown) {
  final levels = <int>{
    for (final line in markdown.split('\n'))
      if (RegExp(r'^#{1,4} ').hasMatch(line)) line.indexOf(' '),
  };
  return levels.toList()..sort();
}

/// 标题层级最全的那一章（同级时取靠前的）：拿它当层级渲染断言的样本。
HelpDocumentContent _richestHeadingChapter(HelpContent content) {
  final chapters = content.manualChapters;
  expect(chapters, isNotEmpty, reason: '手册不该是空的');
  return chapters.reduce(
    (best, chapter) =>
        _headingLevels(chapter.markdown).length >
            _headingLevels(best.markdown).length
        ? chapter
        : best,
  );
}

/// 该条正文里的各级标题文字，按出现次序（一至四级；去掉 `#` 记号与尾随空格）。
List<String> _allHeadingTitles(String markdown) => [
  for (final line in markdown.split('\n'))
    if (RegExp(r'^#{1,4} ').hasMatch(line))
      line.replaceFirst(RegExp(r'^#+ '), '').trim(),
];

/// 该条正文里的二级标题（`## `）原文，按出现次序。取的是正文自己写的那几条，
/// 不钉死写的是什么，改文案不必动本套件。
List<String> _secondLevelHeadings(HelpContent content, String id) => [
  for (final line in content.document(id)!.markdown.split('\n'))
    if (line.startsWith('## ')) line.substring(3).trim(),
];

/// 条目目录名的数字前缀（定序用）。
int _numberPrefix(String directory) => int.parse(
  RegExp(r'^(\d+)').firstMatch(directory.split('/').last)!.group(1)!,
);

/// 那一条条目的第一个二级标题文字（去掉 `## ` 记号）：它在文档页上是一行
/// 普通标题文字，用来断言正文真的渲染到了屏上。取的是正文自己的那句标题，
/// 不钉死写的是什么，改文案不必动。
String _firstSectionHeading(String documentId) {
  final entry = _loadedHelpContentSync().document(documentId);
  expect(entry, isNotNull, reason: documentId);
  return entry!.markdown
      .split('\n')
      .firstWhere((line) => line.startsWith('## '))
      .substring(3)
      .trim();
}

/// 放大视口：目录全条目同屏（一屏可见），懒建列表才能按位置断言整表次序。
Future<void> _pumpCenter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // 新手引导页读状态位（每个单元的「已完成 / 未完成」），装配上私密 JSON
  // 注入点；本套件只断言目录结构与条目，状态位不预置（全按未完成）。
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(
          InMemoryPrivateJsonStorage(),
        ),
      ],
      child: const MaterialApp(home: HelpCenterPage()),
    ),
  );
  await tester.pumpAndSettle();
}

/// 沿用仓内首页部件测试的装配：内存替身覆盖全部落盘与引擎 provider。
Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(initial: VideoIndex.empty),
        ),
        practiceStatsStoreProvider.overrideWithValue(
          PracticeStatsStore(InMemoryPracticeStatsStorage()),
        ),
        privateJsonStorageProvider.overrideWithValue(
          InMemoryPrivateJsonStorage(
            initial: const {
              'onboarding': {'firstRun': true},
            },
          ),
        ),
        fourBeatBucketStoreProvider.overrideWithValue(
          FourBeatBucketStore(InMemoryFourBeatBucketStorage()),
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
        beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
        systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
        screenBrightnessControllerProvider.overrideWithValue(
          FakeScreenBrightnessController(),
        ),
        systemMediaVolumeControllerProvider.overrideWithValue(
          FakeSystemMediaVolumeController(),
        ),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
}
