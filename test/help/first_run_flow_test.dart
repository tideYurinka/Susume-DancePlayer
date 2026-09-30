import 'dart:io';

import 'package:dance_learning_app/help/content_registry.dart'
    show FirstRunChoice, downloadVideoTutorialId, helpGuideUnits;
import 'package:dance_learning_app/help/guide_state.dart'
    show onboardingFlagFields;
import 'package:dance_learning_app/help/help_documents.dart'
    show
        HelpContent,
        HelpDocumentContent,
        loadHelpContent,
        onboardingCopyAssetKey;
import 'package:dance_learning_app/help/help_markdown.dart' show resolveHelpAnchor;
import 'package:dance_learning_app/help/platform_help_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/first_run_harness.dart';
import '../helpers/guide_assertions.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/help_assets_fixture.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/device_viewport.dart';

/// 真资产装载结果，懒算一次：一次性图文卡渲染的是教程正文，用例里的标题、
/// 引言段与截图期望都从这一份现算，不钉死教程写了什么。
HelpContent? _helpContentCache;

Future<HelpContent> _loadedHelpContent() async =>
    _helpContentCache ??= await loadHelpContent(rootBundle);

/// 一次性图文的按钮（定位 key 即分支取值）。
Finder welcomeAction(FirstRunChoice choice) =>
    find.byKey(Key('guide_one_shot_action_${choice.name}'));

/// 首启三段：欢迎图文 → 「下载视频」图文 → 指认一步。
///
/// 接缝 = 喂状态位与首启分支，断言此刻屏幕上
/// 出现哪条引导步、按钮把下一步指到哪个锚点、收场后状态位怎么变。
void main() {
  testWidgets('首次进首页先弹欢迎图文：标题 + 简介 + 两个按钮；点外面关不掉', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);
    await _loadedHelpContent();

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(find.byKey(const Key('guide_one_shot_title')), findsOneWidget);
    expect(
      find.text(guideStepMessageLines('first_run_welcome')[0]),
      findsOneWidget,
    );
    expect(
      find.text(guideStepMessageLines('first_run_welcome')[1]),
      findsOneWidget,
    );
    expect(find.text(welcomeTourLabel), findsOneWidget);
    expect(find.text(welcomeSkipLabel), findsOneWidget);
    // 两枚按钮的先后由结构声明的次序给出——那排按钮右对齐，声明在后的在右：
    // 左「跳过教程」、右「开始新手教程」；文案按分支取值，与位置无关。
    expect(
      tester.getTopLeft(welcomeAction(FirstRunChoice.skip)).dx,
      lessThan(tester.getTopLeft(welcomeAction(FirstRunChoice.tour)).dx),
      reason: '左「跳过教程」、右「开始新手教程」',
    );
    // 那排按钮真的贴卡片内右缘（卡内边距 20）：只断次序会漏掉「整排偏左」。
    expect(
      tester.getRect(welcomeAction(FirstRunChoice.tour)).right,
      closeTo(tester.getRect(find.byKey(const Key('guide_one_shot'))).right - 20, 1),
      reason: '出口按钮右对齐',
    );
    expect(
      find.descendant(
        of: welcomeAction(FirstRunChoice.skip),
        matching: find.text(welcomeSkipLabel),
      ),
      findsOneWidget,
      reason: '左按钮取「跳过」这一支的文案',
    );
    expect(
      find.descendant(
        of: welcomeAction(FirstRunChoice.tour),
        matching: find.text(welcomeTourLabel),
      ),
      findsOneWidget,
      reason: '右按钮取「开始新手教程」这一支的文案',
    );
    // 一次性图文只有卡片自己的按钮：没有就地讲解的 ✕ / 下一步 / 高亮洞。
    expect(find.byKey(const Key('guide_close')), findsNothing);
    expect(find.byKey(const Key('guide_highlight')), findsNothing);

    // 点卡片外面（暗背景上）：卡片不关、不推进。
    await tester.tapAt(
      tester.getTopLeft(find.byKey(const Key('guide_one_shot'))) -
          const Offset(40, 0),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect((storage.snapshot['onboarding'] as Map?)?['firstRun'], isNull);
  });

  testWidgets('窄屏 320 × 2.0 倍字号：欢迎图文四行不溢出', (tester) async {
    await pumpFirstRunHost(tester, storage: InMemoryPrivateJsonStorage());
    resetFirstRunSession(tester);
    // 装配后再压窄视口、放大字号：四行文案（含 QQ 群号那行）都得在，卡不溢出。
    useNamedViewport(tester, ViewportTier.small, textScale: 2.0);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    for (final line in guideStepMessageLines('first_run_welcome')) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(find.text(welcomeTourLabel), findsOneWidget);
    expect(find.text(welcomeSkipLabel), findsOneWidget);
    // 换行后每一行仍贴卡片内右缘。
    expect(
      tester.getRect(welcomeAction(FirstRunChoice.tour)).right,
      closeTo(tester.getRect(find.byKey(const Key('guide_one_shot'))).right - 20, 1),
      reason: '窄屏换行后仍右对齐',
    );
    expect(tester.takeException(), isNull, reason: '320 宽 + 2.0 倍字号下不得溢出');
  });

  testWidgets('文件里 actions 的书写次序不决定按钮的左右次序', (tester) async {
    await pumpFirstRunHost(
      tester,
      storage: InMemoryPrivateJsonStorage(),
      // 同一套分支键，只把 `tour` 写在 `skip` 前面（与随包文件的次序相反），
      // 文案也换成本地取值——按钮的左右与配对都不该跟着文件走。
      helpAssets: FakeHelpAssetBundle({
        onboardingCopyAssetKey: _tourWrittenFirstWelcomeCard,
      }),
    );
    resetFirstRunSession(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(
      tester.getTopLeft(welcomeAction(FirstRunChoice.skip)).dx,
      lessThan(tester.getTopLeft(welcomeAction(FirstRunChoice.tour)).dx),
      reason: '按钮的左右次序由结构声明给出，文件里把 tour 写在前面也不变',
    );
    expect(
      find.descendant(
        of: welcomeAction(FirstRunChoice.skip),
        matching: find.text('先不要'),
      ),
      findsOneWidget,
      reason: '倒着写既不移动「跳过」这一支，也不把它换成别的文案',
    );
    expect(
      find.descendant(
        of: welcomeAction(FirstRunChoice.tour),
        matching: find.text('逛一圈'),
      ),
      findsOneWidget,
      reason: '倒着写既不移动「教程」这一支，也不把它换成别的文案',
    );
  });

  testWidgets('「开始新手教程」→「下载视频」图文与帮助中心教程同源；「已经存好了」→ 指「导入视频」并置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);
    await _loadedHelpContent();

    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();

    // 卡头 = 条目标题；正文 = 教程第一个二级标题那一节（提示块、步骤、截图
    // 都在），引言段与其后的方法不出现。期望值取自教程正文自己：卡渲染的是
    // 哪一节、哪两张截图，这里按同一份正文现算，改教程不必动本用例。
    final tutorial = _downloadVideoContent();
    // 卡里那一节 = 第一个二级标题那一节，其后是下一节。
    final sectionHeading = _secondLevelHeadings(tutorial).first;
    final laterHeading = _secondLevelHeadings(tutorial).elementAt(1);

    expect(find.text(downloadVideoTutorialId), findsOneWidget);
    expect(find.text(sectionHeading), findsOneWidget);
    expect(
      find.text(_introLine(tutorial)),
      findsNothing,
      reason: '引言段不在卡里',
    );
    expect(
      find.text(laterHeading),
      findsNothing,
      reason: '后面的方法不在卡里',
    );
    expect(find.text('等会儿再下载'), findsOneWidget);
    expect(find.text('已经存好了'), findsOneWidget);

    // 卡内 Markdown 用一档收紧的字号：卡头 16、二级标题 15、正文与提示块 14。
    // 卡头自己带 titleMedium 样式；卡内 Markdown 经 Text.rich 承载——根
    // TextSpan 挂 DefaultTextStyle，实际字号挂在最内层带样式的 TextSpan 上。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('guide_one_shot_title')))
          .style!
          .fontSize,
      16,
    );
    double fontSize(Finder finder, String text) {
      final root = tester.widget<RichText>(finder).text as TextSpan;
      TextSpan? matched;
      void walk(TextSpan span) {
        if (span.toPlainText().contains(text) && span.style != null) {
          matched = span;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          if (child is TextSpan) walk(child);
        }
      }

      walk(root);
      return matched!.style!.fontSize!;
    }

    Finder rich(String text) => find.textContaining(text, findRichText: true);
    // 二级标题 15、正文 14：取这一节里真实存在的标题与正文行来量。
    expect(fontSize(rich(sectionHeading), sectionHeading), 15);
    final bodyLine = _firstProseLine(_firstSectionLines(tutorial));
    expect(fontSize(rich(bodyLine), bodyLine), 14);

    // 图片按宽度铺满、保持原比例（不裁成 16:9），且只出卡里那一节的两张截图。
    final cardImages = tester.widgetList<Image>(
      find.descendant(
        of: find.byKey(const Key('guide_one_shot')),
        matching: find.byType(Image),
      ),
    );
    final assetNames = cardImages
        .map((image) => (image.image as AssetImage).assetName)
        .toSet();
    // 只出卡里那一节自己引用到的截图：期望集按该节正文现算。
    expect(
      assetNames,
      {
        for (final match in RegExp(
          r'!\[[^\]]*\]\(([^)]+)\)',
        ).allMatches(tutorial.firstSectionMarkdown))
          '${tutorial.directory}/${match.group(1)}',
      },
      reason: '卡里的图与该节正文引用的截图一一对应',
    );
    for (final image in cardImages) {
      expect(image.fit, BoxFit.fitWidth, reason: '图片按宽度铺满');
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('guide_one_shot')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is AspectRatio &&
              (widget.aspectRatio - 16 / 9).abs() < 0.01,
        ),
      ),
      findsNothing,
      reason: '不再裁成 16:9',
    );

    await tester.tap(find.text('已经存好了'));
    await tester.pumpAndSettle();

    expectGuidePointsAt(tester, find.byKey(const Key('import_video_button')));
    expect(find.text(guideStepMessage('first_run_import')), findsOneWidget);
    expect((storage.snapshot['onboarding'] as Map?)?['firstRun'], isNull);

    // 指认步关掉（✕）：首启置位，此后不再出现。
    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    expect((storage.snapshot['onboarding'] as Map)['firstRun'], isTrue);
  });

  testWidgets('「等会儿再下载」也置位下载图文这一步，指认落在「帮助」上', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);
    await _loadedHelpContent();

    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('等会儿再下载'));
    await tester.pumpAndSettle();

    expectGuidePointsAt(tester, find.byKey(const Key('home_help_entry')));
    expect(find.text(guideStepMessage('first_run_help_download')), findsOneWidget);
  });

  testWidgets('「跳过教程」→ 不出现图文直接指「帮助」；按下即全部置位', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);
    await _loadedHelpContent();

    await tester.tap(find.text(welcomeSkipLabel));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot')), findsNothing);
    expectGuidePointsAt(tester, find.byKey(const Key('home_help_entry')));
    expect(find.text(guideStepMessage('first_run_help')), findsOneWidget);

    // 按下那一刻 14 个单元就已经全部置位：这次指认只是欠的一次演出，不再
    // 决定置位（新手引导页此刻已是全部「已完成」）。
    final afterPress = storage.snapshot['onboarding'] as Map;
    for (final unit in helpGuideUnits) {
      expect(
        afterPress[onboardingFlagFields[unit.id]],
        isTrue,
        reason: '${unit.id} 应在按下「跳过教程」那一刻即置位',
      );
    }

    await tester.tap(find.byKey(const Key('guide_close')));
    await tester.pumpAndSettle();

    // 指认收场后仍是同一事实，且此后不再出现。
    expect(find.byKey(const Key('guide_highlight')), findsNothing);
    final flags = storage.snapshot['onboarding'] as Map;
    expect(flags['firstRun'], isTrue);
    for (final unit in helpGuideUnits) {
      if (unit.id == 'first_run') continue;
      expect(
        flags[onboardingFlagFields[unit.id]],
        isTrue,
        reason: '${unit.id} 应随「跳过教程」一次置位',
      );
    }
  });

  testWidgets('卡里点跨节锚点：打开完整正文停在目标标题；返回后卡还在这一步', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);
    await _loadedHelpContent();

    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();

    // 卡里引用块那条链接指向篇末另一节（目标标题不在卡的切片里）。链接文字与
    // 目标标题都按教程正文现算：指哪条、滚到哪，改教程不必动本用例。
    final tutorial = _downloadVideoContent();
    final link = _firstAnchorLink(tutorial);
    if (link == null || !link.onCard) return;
    final headingText = _anchorHeadingText(tutorial, link);
    await tester.runAsync(() async {
      await tester.tapOnText(find.textRange.ofSubstring(link.label));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();

    // 完整正文页压在首页上：卡与遮罩随「当前表面」机制收起。
    expect(find.byKey(const Key('guide_one_shot')), findsNothing);

    // 目标标题在下一节（不在卡的切片里），所以是「滚过去」到位的：位置要动、
    // 目标题要落在视口内（与 help_document_page_test 用尾部长文断言上缘落点
    // 互补）。目标若本来就落在篇首、根本不用滚，位置断言不成立。
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final headingTop = tester.getTopLeft(find.text(headingText)).dy;
    expect(headingTop, inInclusiveRange(0, MediaQuery.sizeOf(tester.element(find.byType(Scrollable).first)).height), reason: '目标标题在视口内');
    if (_targetIsInFirstSection(tutorial, link.anchor)) return;
    expect(position.pixels, greaterThan(0), reason: '正文页朝目标标题滚过去');

    // 返回：卡原样回来、仍等那两个按钮之一，本步未被消耗（无任何置位）。
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(find.text('等会儿再下载'), findsOneWidget);
    expect(find.text('已经存好了'), findsOneWidget);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['firstRun'],
      isNull,
      reason: '打开完整正文不消耗这一步，不写任何状态位',
    );
  });

  testWidgets('卡里点跨条目链接：推入目标条目页停在落点；返回后卡还在这一步', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(
      tester,
      storage: storage,
      helpAssets: FakeHelpAssetBundle({
        // 引导文案取仓库里的随包文件；教程正文换成带跨条目链接的那一份。
        onboardingCopyAssetKey: File(onboardingCopyAssetKey).readAsStringSync(),
        '$downloadVideoTutorialDirectory/下载视频.md':
            '# 下载视频\n'
            '\n'
            '引言一段。\n'
            '\n'
            '## 方法一\n'
            '\n'
            '先看[《问题反馈》](../03-问题反馈/问题反馈.md)，再回来。\n'
            '\n'
            '截图一张。\n',
        '$feedbackTutorialDirectory/问题反馈.md': '# 问题反馈\n\n在群里说一句。\n',
      }),
    );
    resetFirstRunSession(tester);

    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('《问题反馈》'));
    await tester.pumpAndSettle();

    // 卡与遮罩随「当前表面」机制收起，推入的是目标条目的文档页。
    expect(find.byKey(const Key('guide_one_shot')), findsNothing);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('问题反馈')),
      findsOneWidget,
    );
    expect(find.text('在群里说一句。'), findsOneWidget);

    // 返回：卡原样回来、仍等那两个按钮之一，本步未被消耗。
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(find.text('已经存好了'), findsOneWidget);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['firstRun'],
      isNull,
      reason: '点跨条目链接不消耗这一步，不写任何状态位',
    );
  });

  testWidgets('卡里点外部网址：地址交给打开件，卡还在这一步', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    final opener = FakeHelpExternalLinkOpener();
    await pumpFirstRunHost(
      tester,
      storage: storage,
      overrides: [helpExternalLinkOpenerProvider.overrideWithValue(opener)],
      helpAssets: FakeHelpAssetBundle({
        // 引导文案取仓库里的随包文件；教程正文换成带外部网址的那一份。
        onboardingCopyAssetKey: File(onboardingCopyAssetKey).readAsStringSync(),
        '$downloadVideoTutorialDirectory/下载视频.md':
            '# 下载视频\n'
            '\n'
            '引言一段。\n'
            '\n'
            '## 方法一\n'
            '\n'
            '见[官网](https://example.com/tool)。\n',
      }),
    );
    resetFirstRunSession(tester);

    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('官网'));
    await tester.pumpAndSettle();

    expect(
      opener.opened,
      ['https://example.com/tool'],
      reason: '图文卡与文档页共用渲染件，外部网址同样交打开件',
    );
    expect(
      find.byKey(const Key('guide_one_shot')),
      findsOneWidget,
      reason: '交出去不推入新页，卡还停在原地',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('分支事实不落盘：选过之后中途杀掉 App，下次打开从头走首启', (tester) async {
    final storage = InMemoryPrivateJsonStorage();
    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);
    await _loadedHelpContent();

    // 走到第 2 步（分支已产生）后「杀掉 App」：同一份落盘、全新会话重挂。
    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);

    await pumpFirstRunHost(tester, storage: storage);
    resetFirstRunSession(tester);

    // 「杀掉 App」= 会话态随进程消失：riverpod 3 的会话 provider 状态随
    // 测试进程存活，显式清零才等效「下次打开」（上面的
    // resetFirstRunSession 即完成此事），清完重演从欢迎卡起算。
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot_title')), findsOneWidget);
    expect(find.text(welcomeTourLabel), findsOneWidget);
    expect(
      find.text(downloadVideoTutorialId),
      findsNothing,
      reason: '分支只在会话里：重启后不直接落在下载图文上',
    );
  });
}

/// 一份最小可用的假文案：欢迎卡照旧只声明 `skip` / `tour` 两个分支键，但
/// `tour` 写在前面——用来验证按钮的左右次序与分支配对都不读文件里的先后。
const String _tourWrittenFirstWelcomeCard = '''
units:
  first_run:
    title: 首启
    description: 单元说明
steps:
  first_run_welcome:
    title: 欢迎
    message: |-
      第一行
      第二行
      第三行
    actions:
      tour: 逛一圈
      skip: 先不要
ui:
  next: 继续
  skip: 稍后
  guide_units_title: 引导
  reset_all: 全重置
  reset_dialog_title: 全重置？
  reset_dialog_body: 正文
  reset_dialog_cancel: 取消
  reset_dialog_confirm: 确定
''';

/// 「下载视频」那条教程的装载结果：一次性图文卡渲染的是它正文的第一节，
/// 用例里的标题与截图期望都从这里现算，不钉死教程写了什么。
HelpDocumentContent _downloadVideoContent() {
  final content = _helpContentCache;
  expect(content, isNotNull, reason: '用例开头已 await 过装配');
  final entry = content!.document(downloadVideoTutorialId);
  expect(entry, isNotNull, reason: downloadVideoTutorialId);
  return entry!;
}

/// 教程里的二级标题文字（去掉 `## ` 记号），按出现次序。
List<String> _secondLevelHeadings(HelpDocumentContent tutorial) => [
  for (final line in tutorial.markdown.split('\n'))
    if (line.startsWith('## ')) line.substring(3).trim(),
];

/// 教程引言段那一行（一级标题之后、第一个二级标题之前的第一段）。
String _introLine(HelpDocumentContent tutorial) => _firstProseLine(
  tutorial.markdown.split('\n').takeWhile((line) => !line.startsWith('## ')),
);

/// 卡里那一节（第一个二级标题到下一个二级标题之间）的正文行。
Iterable<String> _firstSectionLines(HelpDocumentContent tutorial) =>
    tutorial.markdown
        .split('\n')
        .skipWhile((line) => !line.startsWith('## '))
        .skip(1)
        .takeWhile((line) => !line.startsWith('## '));

/// 一组正文行里的第一行普通文字：跳过标题行与图片行，并按渲染后的样子剥掉
/// 行内标记与提示块的 `>` 记号——那些记号都不出现在屏上。
String _firstProseLine(Iterable<String> lines) {
  final line = lines
      .map((line) => line.trim())
      .firstWhere(
        (line) => line.isNotEmpty && !line.startsWith('#') && !line.startsWith('!['),
      );
  return line
      .replaceFirst(RegExp(r'^>+\s*'), '')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m.group(1)!)
      .replaceAllMapped(RegExp(r'\*\*([^*]*)\*\*'), (m) => m.group(1)!)
      .replaceAll('`', '')
      .trim();
}

/// 卡里那一节里的第一条本文锚点链接（`[文字](#锚点)`）；那一节没写锚点链接
/// 时退回全文第一条。[onCard] 表示那条链接就在卡渲染的切片里、屏上点得到。
({String label, String anchor, bool onCard})? _firstAnchorLink(
  HelpDocumentContent tutorial,
) {
  final inSection = RegExp(
    r'\[([^\]]+)\]\(#([^)]+)\)',
  ).firstMatch(_firstSectionLines(tutorial).join('\n'));
  if (inSection != null) {
    return (
      label: inSection.group(1)!,
      anchor: inSection.group(2)!,
      onCard: true,
    );
  }
  final anywhere = RegExp(
    r'\[([^\]]+)\]\(#([^)]+)\)',
  ).firstMatch(tutorial.markdown);
  if (anywhere == null) return null;
  return (
    label: anywhere.group(1)!,
    anchor: anywhere.group(2)!,
    onCard: false,
  );
}

/// 锚点指向的那条标题原文（按装载侧同一套 slug 规则解析）。
String _anchorHeadingText(
  HelpDocumentContent tutorial,
  ({String label, String anchor, bool onCard}) link,
) {
  final slug = resolveHelpAnchor(tutorial.headings, link.anchor);
  expect(slug, isNotNull, reason: '锚点应解析得到目标标题');
  return tutorial.headings.firstWhere((h) => h.slug == slug).text;
}

/// 锚点指向的标题是否就落在卡渲染的那一节里（真落在里面就不必滚动）。
bool _targetIsInFirstSection(HelpDocumentContent tutorial, String anchor) {
  final section = _firstSectionLines(tutorial).join('\n');
  final slug = resolveHelpAnchor(tutorial.headings, anchor);
  if (slug == null) return false;
  final heading = tutorial.headings.firstWhere((h) => h.slug == slug);
  return section.contains(heading.text);
}

void expectGuidePointsAtImport(WidgetTester tester) {
  _expectGuideAnchoredAt(tester, find.byKey(const Key('import_video_button')));
}

void expectGuidePointsAtHelp(WidgetTester tester) {
  _expectGuideAnchoredAt(tester, find.byKey(const Key('home_help_entry')));
}

/// 断言指认步锚在真实控件上、箭头对准（同 guide_assertions 的口径，本地收敛
/// 为私有副本以免跨文件共享状态）。
void _expectGuideAnchoredAt(WidgetTester tester, Finder anchor) {
  expect(find.byKey(const Key('guide_highlight')), findsOneWidget);
  expect(find.byKey(const Key('guide_bubble')), findsOneWidget);
  final anchorRect = tester.getRect(anchor);
  final cardRect = tester.getRect(find.byKey(const Key('guide_bubble')));
  final arrowRect = tester.getRect(find.byKey(const Key('guide_arrow')));
  final blockRect = cardRect.expandToInclude(arrowRect);
  final gap = blockRect.bottom <= anchorRect.top
      ? anchorRect.top - blockRect.bottom
      : blockRect.top - anchorRect.bottom;
  expect(gap, inInclusiveRange(0, 40));
  expect(
    tester.getCenter(find.byKey(const Key('guide_arrow'))).dx,
    closeTo(anchorRect.center.dx, 1),
  );
}
