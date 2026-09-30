import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_units_page.dart';
import 'package:dance_learning_app/help/help_boxes.dart';
import 'package:dance_learning_app/help/help_center_page.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_private_json_storage.dart';

/// 帮助中心的版式：新手引导入口卡 → 教程分组 → 使用手册分组；每个分组的描边
/// 方框带组名与条数，框内每条带右箭头、整行可点；每行左缘出 64×44 图标方框
/// （与入口卡同款）。条目集合与次序以磁盘上的真资产为准（列表与页顶读数都与
/// 磁盘目录一致），内容契约另由 `help_center_test` / `help_assets_test` 钉住。
void main() {
  /// 真资产扫到的两组条目（id 按数字前缀序）；断言与页面读数都从它现算，
  /// 新增一章不必改这里的字面量。
  late List<String> chapterIds;
  late List<String> tutorialIds;

  /// 手册第一章的条目：目录行的通用断言拿它当样本，改章节标题不必动这里。
  late HelpDocumentContent sampleChapter;

  setUpAll(() async {
    final content = await loadHelpContent(rootBundle);
    chapterIds = [for (final c in content.manualChapters) c.id];
    tutorialIds = [for (final t in content.tutorials) t.id];
    sampleChapter = content.manualChapters.first;
  });

  Finder entryCard() => find.byKey(helpEntryKey('guide'));

  Finder viewGuideButton() => find.byKey(const Key('help_entry_view_guide'));

  Finder tutorialGroup() => find.byKey(const Key('help_group_tutorials'));

  Finder manualGroup() => find.byKey(const Key('help_group_manual'));

  Finder tileOf(String id) => find.byKey(helpEntryKey(id));

  Offset topOf(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder.first);

  group('目录次序', () {
    testWidgets('入口卡 → 教程分组 → 使用手册分组，组内按数字前缀序', (tester) async {
      await pumpHelpCenter(tester);

      expect(topOf(tester, entryCard()).dy, lessThan(topOf(tester, tutorialGroup()).dy));
      expect(
        topOf(tester, tutorialGroup()).dy,
        lessThan(topOf(tester, manualGroup()).dy),
      );
      // 教程在手册之前，开页即见。
      expect(
        topOf(tester, tileOf(downloadVideoTutorialId)).dy,
        lessThan(topOf(tester, manualGroup()).dy),
      );

      var previous = topOf(tester, manualGroup()).dy;
      for (final id in chapterIds) {
        final top = topOf(tester, tileOf(id)).dy;
        expect(top, greaterThan(previous), reason: '$id 按数字前缀序');
        previous = top;
      }
    });

    testWidgets('手机竖屏 360×800：开页不滚动即见入口卡与教程条目，使用手册往下滚', (tester) async {
      tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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

      expect(tester.takeException(), isNull);
      expect(entryCard(), findsOneWidget);
      expect(tileOf(downloadVideoTutorialId), findsOneWidget);
      expect(
        tester.getBottomRight(tileOf(downloadVideoTutorialId)).dy,
        lessThanOrEqualTo(800),
        reason: '开页即见教程条目，不必先滚动',
      );
    });
  });

  group('分组方框', () {
    testWidgets('教程分组：框顶写组名与磁盘条数，框内含全部教程条目', (tester) async {
      await pumpHelpCenter(tester);

      expect(
        find.descendant(of: tutorialGroup(), matching: find.text('教程')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tutorialGroup(),
          matching: find.text('${tutorialIds.length} 条'),
        ),
        findsOneWidget,
      );
      for (final id in tutorialIds) {
        expect(
          find.descendant(of: tutorialGroup(), matching: tileOf(id)),
          findsOneWidget,
          reason: '$id 在教程框内',
        );
      }
    });

    testWidgets('使用手册分组：框顶写组名与磁盘章数，框内含全部章节', (tester) async {
      await pumpHelpCenter(tester);

      expect(
        find.descendant(of: manualGroup(), matching: find.text('使用手册')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: manualGroup(),
          matching: find.text('${chapterIds.length} 章'),
        ),
        findsOneWidget,
      );
      for (final id in chapterIds) {
        expect(
          find.descendant(of: manualGroup(), matching: tileOf(id)),
          findsOneWidget,
          reason: '$id 在手册框内',
        );
      }
    });
  });

  group('框内每一条', () {
    testWidgets('带右箭头、整行可点进对应的章节页', (tester) async {
      await pumpHelpCenter(tester);

      final chapterTile = tileOf(sampleChapter.id);
      expect(
        find.descendant(
          of: chapterTile,
          matching: find.byIcon(Icons.chevron_right),
        ),
        findsOneWidget,
      );

      await tester.tap(chapterTile);
      await tester.pumpAndSettle();
      expect(find.byType(HelpDocumentPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(sampleChapter.displayTitle),
        ),
        findsOneWidget,
        reason: '章节页标题取正文一级标题',
      );
    });

    testWidgets('没有去处的条目不出右箭头（右箭头只承诺可点）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HelpEntryTile(
              title: '不可点条目',
              description: '没有去处',
              icon: Icons.menu_book_outlined,
            ),
          ),
        ),
      );

      expect(find.text('不可点条目'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('每行左缘出 64×44 图标方框，与入口卡同款、各行左缘对齐', (tester) async {
      await pumpHelpCenter(tester);

      // 教程与手册的每一行左缘都是同一款 64×44 图标方框。
      for (final id in [...tutorialIds, ...chapterIds]) {
        final box = find.descendant(
          of: tileOf(id),
          matching: find.byType(HelpIconBox),
        );
        expect(box, findsOneWidget, reason: id);
        final size = tester.getSize(box);
        expect(size, const Size(64, 44), reason: id);
      }

      // 教程行与手册行的图标方框左缘对齐。
      final tutorialLeft = topOf(
        tester,
        find.descendant(
          of: tileOf(downloadVideoTutorialId),
          matching: find.byType(HelpIconBox),
        ),
      ).dx;
      final manualLeft = topOf(
        tester,
        find.descendant(
          of: tileOf(sampleChapter.id),
          matching: find.byType(HelpIconBox),
        ),
      ).dx;
      expect(manualLeft, tutorialLeft, reason: '教程与手册两行的行左缘对齐');
      expect(tester.takeException(), isNull);
    });

    testWidgets('命中盒不低于 48：入口卡的「查看」与每条目录行', (tester) async {
      await pumpHelpCenter(tester);

      final viewSize = tester.getSize(viewGuideButton());
      expect(viewSize.width, greaterThanOrEqualTo(48));
      expect(viewSize.height, greaterThanOrEqualTo(48));

      for (final id in [...tutorialIds, ...chapterIds]) {
        final size = tester.getSize(tileOf(id));
        expect(size.height, greaterThanOrEqualTo(48), reason: id);
      }
      final cardSize = tester.getSize(entryCard());
      expect(cardSize.height, greaterThanOrEqualTo(48));
    });

    testWidgets('窄屏 320 × 2.0 倍字号：不溢出、可滚动看全', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(320, 3000); // 合成档 320×3000dp，非设备档。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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

      expect(tester.takeException(), isNull, reason: '320 宽 + 2.0 倍字号下不得溢出');
      expect(entryCard(), findsOneWidget);
      await tester.scrollUntilVisible(
        tileOf(chapterIds.last),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tileOf(chapterIds.last), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('新手引导入口卡', () {
    testWidgets('主色卡 + 图标方框 + 标题 + 一句说明 + 「查看」按钮，说明不含「重看」', (tester) async {
      await pumpHelpCenter(tester);

      expect(entryCard(), findsOneWidget);
      final card = tester.widget<Card>(entryCard());
      final primary = Theme.of(
        tester.element(entryCard()),
      ).colorScheme.primary;
      expect(card.color, primary, reason: '入口卡是主色卡，颜色取自主题');

      expect(
        find.descendant(
          of: entryCard(),
          matching: find.byKey(const Key('help_entry_icon_box')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: entryCard(), matching: find.text('新手引导')),
        findsOneWidget,
      );
      final description = tester.widget<Text>(
        find.descendant(
          of: entryCard(),
          matching: find.byKey(const Key('help_entry_guide_description')),
        ),
      );
      expect(description.data, isNot(contains('重看')));
      expect(viewGuideButton(), findsOneWidget);
    });

    testWidgets('点卡片进新手引导页', (tester) async {
      await pumpHelpCenter(tester);

      await tester.tap(entryCard());
      await tester.pumpAndSettle();

      expect(find.byType(GuideUnitsPage), findsOneWidget);
    });

    testWidgets('点「查看」按钮也进新手引导页', (tester) async {
      await pumpHelpCenter(tester);

      await tester.tap(viewGuideButton());
      await tester.pumpAndSettle();

      expect(find.byType(GuideUnitsPage), findsOneWidget);
    });
  });
}

/// 帮助中心页：放大视口让懒建列表把全部条目都建出来，便于按位置断言整表次序。
Future<void> pumpHelpCenter(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2000); // 合成档 1000×2000dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
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
