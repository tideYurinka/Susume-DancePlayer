import 'package:dance_learning_app/about/contributor_intro_page.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:dance_learning_app/help/platform_help_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/contributor_assets_fixture.dart';
import '../helpers/contributor_pages_harness.dart';
import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/markdown_text_assertions.dart';

/// **个人介绍页**：顶端是那位**贡献者**的小块档案，其下是他的个人介绍正文——
/// 与**帮助文档**同一套 Markdown 方言与渲染件。断言只落在屏幕上看到的东西与
/// 按下发生的事上。
void main() {
  const id = 'yurinka';
  final avatarKey = contributorAvatarAsset(id, 'me.webp');
  final rewardKey = '${contributorDirectory(id)}/reward.png';

  /// 装个人介绍页：正文取 [markdown]，`reward.png` 与一张头像在盘上，另放一条
  /// 帮助条目供正文里的**条目链接**指向。
  Future<void> pumpIntro(
    WidgetTester tester,
    String markdown, {
    List<Override> overrides = const [],
  }) async {
    await pumpContributorSurface(
      tester,
      home: const ContributorIntroPage(contributorId: id),
      bundle: contributorBundle(
        records: [
          ContributorFixture(id, '汐荧_yurinka', '项目发起者', avatar: 'me.webp'),
        ],
        intros: {id: markdown},
        assets: const {
          'assets/help/guide/01-快捷手势/快捷手势.md': '# 快捷手势\n\n手势正文。\n',
        },
        binary: {rewardKey: onePixelPng, avatarKey: onePixelPng},
      ),
      overrides: overrides,
    );
  }

  testWidgets('顶端是那位贡献者的档案头：头像、显示名与角色', (tester) async {
    await pumpIntro(tester, '# 汐荧_yurinka\n\n自述。\n');

    final header = find.byKey(const Key('contributor_profile_header'));
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.text('汐荧_yurinka')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text('项目发起者')),
      findsOneWidget,
    );
    final avatar = find.descendant(of: header, matching: find.byType(Image));
    expect(
      (tester.widget<Image>(avatar).image as AssetImage).assetName,
      avatarKey,
    );
  });

  testWidgets('正文按帮助文档那套方言渲染：分节、列表、图片与折叠块', (tester) async {
    await pumpIntro(
      tester,
      '# 汐荧_yurinka\n'
      '\n'
      '## 作者想说的\n'
      '\n'
      '泥嚎，我是汐荧_yurinka。\n'
      '\n'
      '### 在这些地方找到我\n'
      '\n'
      '- 无序项甲\n'
      '- 无序项乙\n'
      '\n'
      '> 提示块一句话\n'
      '\n'
      '![赞赏码](reward.png)\n'
      '\n'
      '<details>\n'
      '<summary>投喂作者</summary>\n'
      '\n'
      '赞赏说明。\n'
      '\n'
      '</details>\n',
    );

    final texts = plainTexts(tester);
    expect(texts, contains('作者想说的'), reason: '二级标题成节');
    expect(texts, contains('在这些地方找到我'), reason: '三级标题也照常');
    expect(texts, contains('泥嚎，我是汐荧_yurinka。'));
    expect(texts, contains('无序项甲'));
    expect(texts, contains('无序项乙'));
    expect(texts, contains('提示块一句话'));

    // 正文里的图按相对文件名解析到他目录里的那份资产。
    final image = find.descendant(
      of: find.byKey(const Key('contributor_intro_markdown')),
      matching: find.byType(Image),
    );
    expect(
      (tester.widget<Image>(image).image as AssetImage).assetName,
      rewardKey,
      reason: '图取他自己目录里的资产',
    );

    // 折叠块默认收起，点开才出现块内内容。
    expect(texts, isNot(contains('赞赏说明。')));
    await tester.tap(find.text('投喂作者'));
    await tester.pumpAndSettle();
    expect(plainTexts(tester), contains('赞赏说明。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文里的条目链接点一下推入目标帮助文档页', (tester) async {
    await pumpIntro(
      tester,
      '# 汐荧_yurinka\n'
      '\n'
      '见[快捷手势](../../help/guide/01-快捷手势/快捷手势.md)。\n',
    );

    await tester.tapOnText(find.textRange.ofSubstring('快捷手势'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpDocumentPage), findsOneWidget);
    expect(find.text('手势正文。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文里的外部网址点一下交系统浏览器打开', (tester) async {
    const url = 'https://space.bilibili.com/1922939099';
    final opener = FakeHelpExternalLinkOpener();
    await pumpIntro(
      tester,
      '# 汐荧_yurinka\n\n- [Bilibili @潮汐_荧灵]($url)\n',
      overrides: [helpExternalLinkOpenerProvider.overrideWithValue(opener)],
    );

    await tester.tapOnText(find.textRange.ofSubstring('Bilibili'));
    await tester.pumpAndSettle();

    expect(opener.opened, [url], reason: '地址原样交给打开件');
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文里的图仍能打开大图并长按保存', (tester) async {
    final saver = FakeHelpImageSaver();
    await pumpIntro(
      tester,
      '# 汐荧_yurinka\n\n![赞赏码](reward.png)\n',
      overrides: [helpImageSaverProvider.overrideWithValue(saver)],
    );
    await _settleImages(tester);
    final thumbnail = _introImage();

    await tester.tap(thumbnail);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('help_image_viewer')),
      findsOneWidget,
      reason: '点一下弹全屏查看器',
    );

    await tester.longPress(find.byKey(const Key('help_image_viewer_image')));
    await tester.pumpAndSettle();
    expect(saver.names, ['reward.png'], reason: '文件名取资产文件名');
    expect(saver.bytes, [onePixelPng], reason: '字节是这张图从资产包读出的');
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文里的缩略图长按直接存进相册，不弹菜单', (tester) async {
    final saver = FakeHelpImageSaver();
    await pumpIntro(
      tester,
      '# 汐荧_yurinka\n\n![赞赏码](reward.png)\n',
      overrides: [helpImageSaverProvider.overrideWithValue(saver)],
    );
    await _settleImages(tester);

    await tester.longPress(_introImage());
    await tester.pumpAndSettle();

    expect(saver.names, ['reward.png']);
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(find.byType(PopupMenuItem<Object>), findsNothing, reason: '长按直接保存，不弹菜单');
    expect(tester.takeException(), isNull);
  });
}

/// 正文里那张图（档案头的头像不算）：断言落在它身上。
Finder _introImage() => find.descendant(
  of: find.byKey(const Key('contributor_intro_markdown')),
  matching: find.byType(Image),
);

/// 等假资产里的图片真解码完（图片走异步解码，与帮助域既有用例同一手法）。
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
