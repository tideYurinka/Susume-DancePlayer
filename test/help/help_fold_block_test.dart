import 'dart:io';

import 'package:dance_learning_app/help/content_registry.dart'
    show downloadVideoTutorialId, helpGuideSteps;
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:dance_learning_app/help/platform_help_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/first_run_harness.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/help_assets_fixture.dart';
import '../helpers/help_document_harness.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 正文里的折叠块：文档页与一次性图文卡里都渲染成
/// 「一行标题 + 展开箭头」，默认收起，点开才出现块内的段落、图片与提示块；不记
/// 展开状态，也不影响锚点。
void main() {
  const directory = downloadVideoTutorialDirectory;
  const markdownKey = '$directory/下载视频.md';
  const imageKey = '$directory/reward.png';
  const foldMarkdown =
      '# 下载视频\n'
      '\n'
      '开头一段。\n'
      '\n'
      '<details>\n'
      '<summary>帮助作者</summary>\n'
      '非常感谢\n'
      '\n'
      '- 甲\n'
      '- 乙\n'
      '\n'
      '> 提示一句\n'
      '\n'
      '![赞赏码](reward.png)\n'
      '</details>\n';

  testWidgets('文档页：折叠块默认收起，屏上只有一行标题', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: foldMarkdown,
      binary: {imageKey: onePixelPng},
    );

    expect(find.text('帮助作者'), findsOneWidget);
    expect(find.text('非常感谢'), findsNothing, reason: '收起时块内内容不在屏上');
    expect(find.text('甲'), findsNothing);
    expect(find.text('提示一句'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：点一下标题展开、再点收起，块内的字与图各出现各消失一遍', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: foldMarkdown,
      binary: {imageKey: onePixelPng},
    );

    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();

    // 块内是整块 Markdown：段落、列表、提示块与图片照常渲染。
    expect(find.text('非常感谢'), findsOneWidget);
    expect(find.text('甲'), findsOneWidget);
    expect(find.text('乙'), findsOneWidget);
    expect(find.text('提示一句'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      imageKey,
      reason: '块内图片照常解析到同目录资产',
    );

    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();

    expect(find.text('非常感谢'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：折叠块里的链接沿用现有行为：外部网址交系统浏览器打开、锚点滚到标题', (tester) async {
    final opener = FakeHelpExternalLinkOpener();
    await pumpHelpDocumentPage(
      tester,
      viewport: const Size(1000, 600),
      overrides: [helpExternalLinkOpenerProvider.overrideWithValue(opener)],
      markdown:
          '# 下载视频\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '[官网](https://example.com)\n'
          '\n'
          '[跳到目标](#目标小节)\n'
          '</details>\n'
          '\n'
          '${List.filled(20, '填充段落。').join('\n\n')}\n'
          '\n'
          '## 目标小节\n'
          '\n'
          '目标一段。\n',
    );
    double offset() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();

    await tester.tapOnText(find.textRange.ofSubstring('官网'));
    await tester.pumpAndSettle();
    expect(opener.opened, ['https://example.com'], reason: '块内外部网址同样交系统浏览器');

    await tester.tapOnText(find.textRange.ofSubstring('跳到目标'));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0), reason: '块内锚点照旧滚到目标标题');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：写坏的折叠块（缺 `<summary>`）不显示、不崩，正文照常', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown:
          '# 下载视频\n'
          '\n'
          '前面一段。\n'
          '\n'
          '<details>\n'
          '块内文字。\n'
          '</details>\n'
          '\n'
          '后面一段。\n',
    );

    expect(find.text('前面一段。'), findsOneWidget);
    expect(find.text('后面一段。'), findsOneWidget);
    expect(find.text('块内文字。'), findsNothing, reason: '未识别的块照旧不显示');
    expect(find.textContaining('<details>'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：展开后离开再回来，折叠块仍是收起（不记展开状态）', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000); // 合成档 1000×2000dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpAssetBundleProvider.overrideWithValue(
            FakeHelpAssetBundle({markdownKey: foldMarkdown}),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const HelpDocumentPage(
                        documentId: downloadVideoTutorialId,
                      ),
                    ),
                  ),
                  child: const Text('打开文档'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开文档'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();
    expect(find.text('非常感谢'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开文档'));
    await tester.pumpAndSettle();

    expect(find.text('非常感谢'), findsNothing, reason: '再进页面仍是收起');
  });

  testWidgets('文档页：折叠块不影响锚点；指向块内标题的锚点不滚、不报错', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      viewport: const Size(1000, 600),
      markdown:
          '# 下载视频\n'
          '\n'
          '[跳到块内](#块内小节)\n'
          '\n'
          '[跳到目标](#目标小节)\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '## 块内小节\n'
          '块内正文。\n'
          '</details>\n'
          '\n'
          '${List.filled(20, '填充段落。').join('\n\n')}\n'
          '\n'
          '## 目标小节\n'
          '\n'
          '目标一段。\n',
    );
    double offset() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    // 块内标题不参与锚点登记：锚点解析不到，停在顶部、不报错。
    await tester.tapOnText(find.textRange.ofSubstring('跳到块内'));
    await tester.pumpAndSettle();
    expect(offset(), 0);
    expect(tester.takeException(), isNull);

    // 展开块内内容：里面的标题照常渲染成标题，但仍不登记锚点。
    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();
    expect(find.text('块内小节'), findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring('跳到块内'));
    await tester.pumpAndSettle();
    expect(offset(), 0);

    // 正文里的普通锚点照旧滚到目标标题。
    await tester.tapOnText(find.textRange.ofSubstring('跳到目标'));
    await tester.pumpAndSettle();
    expect(offset(), greaterThan(0), reason: '普通锚点照旧滚过去');
    expect(tester.takeException(), isNull);
  });

  // —— 折叠块里的图片宽度——
  // 块内的图按可用宽度六成居中（宽高按原比例），块外的图照旧铺满可用宽度。

  testWidgets('文档页：折叠块里的图占可用宽度的六成且居中，块外那张仍铺满', (tester) async {
    const coverKey = '$directory/cover.png';
    await pumpHelpDocumentPage(
      tester,
      markdown:
          '# 下载视频\n'
          '\n'
          '![封面](cover.png "封面提示")\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '![赞赏码](reward.png "赞赏码提示")\n'
          '</details>\n',
      binary: {coverKey: onePixelPng, imageKey: onePixelPng},
    );

    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();
    // 图片解码是真实异步：放行真实事件循环再泵帧，图真的排进布局、高度才量得准。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    final cover = _imageWithAsset(coverKey);
    final reward = _imageWithAsset(imageKey);
    // 文档页可用宽度 = 视口 1000 − 渲染件左右各 16 的正文内边距。
    _expectOutsideFullInsideSixty(
      tester,
      outside: cover,
      inside: reward,
      available: 1000.0 - 32,
    );
    expect(
      tester.getSize(reward).height,
      tester.getSize(reward).width,
      reason: '1×1 的图按原比例，高等于宽（没被压扁裁切）',
    );
    // alt 与 title 仍都不显示：不出图注、不出悬浮提示（块内块外一致）。
    expect(find.text('封面'), findsNothing);
    expect(find.text('赞赏码'), findsNothing);
    expect(find.text('封面提示'), findsNothing);
    expect(find.text('赞赏码提示'), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一次性图文卡：折叠块里的图按卡内可用宽度算，不按屏幕宽度算', (tester) async {
    const coverKey = '$directory/cover.png';
    const tutorial =
        '# 下载视频\n'
        '\n'
        '把视频存下来。\n'
        '\n'
        '## 方法一\n'
        '\n'
        '一段够长的说明，让卡撑到宽度上限。一段够长的说明，让卡撑到宽度上限。\n'
        '\n'
        '![封面](cover.png)\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '![赞赏码](reward.png)\n'
        '</details>\n'
        '\n'
        '## 方法二\n'
        '\n'
        '后面的方法。\n';
    await _pumpFirstRunCard(
      tester,
      tutorialMarkdown: tutorial,
      images: {coverKey: onePixelPng},
    );

    expect(
      tester.getSize(find.byKey(const Key('guide_one_shot'))).width,
      320,
      reason: '卡撑到宽度上限，才有「卡内可用宽度」可算',
    );

    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();

    final cover = _imageWithAsset(coverKey);
    final reward = _imageWithAsset(imageKey);
    // 卡宽 320、卡内边距 20：块内的图占 (320 − 40) × 0.6 = 168，而不是按
    // 1000 宽的屏幕算出的 600——宽度取的是卡内约束。
    _expectOutsideFullInsideSixty(
      tester,
      outside: cover,
      inside: reward,
      available: 320.0 - 40,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('一次性图文卡：第一节里的折叠块同形（块内标题不算节边界）', (tester) async {
    // 折叠块里写了 `##`：卡照旧整块放进第一节，块内标题只在展开后出现，
    // 块外的下一个 `##` 才是切片的收口。
    const tutorial =
        '# 下载视频\n'
        '\n'
        '把视频存下来。\n'
        '\n'
        '## 方法一\n'
        '\n'
        '1. 第一步\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '非常感谢\n'
        '\n'
        '## 块内小节\n'
        '\n'
        '![赞赏码](reward.png)\n'
        '</details>\n'
        '\n'
        '## 方法二\n'
        '\n'
        '后面的方法。\n';
    await _pumpFirstRunCard(tester, tutorialMarkdown: tutorial);

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(find.text('方法一'), findsOneWidget);
    expect(find.text('帮助作者'), findsOneWidget);
    expect(find.text('非常感谢'), findsNothing, reason: '卡里默认收起');
    expect(find.text('块内小节'), findsNothing, reason: '块内标题收起时不在屏上');
    expect(find.text('后面的方法。'), findsNothing, reason: '卡照旧只切第一节');

    await tester.tap(find.text('帮助作者'));
    await tester.pumpAndSettle();

    expect(find.text('非常感谢'), findsOneWidget);
    expect(find.text('块内小节'), findsOneWidget, reason: '块内标题照常渲染成标题');
    final image = tester.widget<Image>(
      find.descendant(
        of: find.byKey(const Key('guide_one_shot')),
        matching: find.byType(Image),
      ),
    );
    expect((image.image as AssetImage).assetName, imageKey);
    expect(find.text('后面的方法。'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// 按资产 key 找正文里画出来的那张图（折叠块内外各一张时用）。
Finder _imageWithAsset(String assetKey) => find.byWidgetPredicate(
  (widget) =>
      widget is Image && (widget.image as AssetImage).assetName == assetKey,
);

/// 同一篇正文里的两张图：块外的 [outside] 铺满**可用宽度** [available]，块内的
/// [inside] 占它的六成且水平居中（沿 [outside] 的宽度规则；可用宽度
/// 取渲染件的约束宽度，由调用方按场景给出）。
void _expectOutsideFullInsideSixty(
  WidgetTester tester, {
  required Finder outside,
  required Finder inside,
  required double available,
}) {
  expect(tester.getSize(outside).width, available, reason: '块外的图照旧铺满可用宽度');
  expect(
    tester.getSize(inside).width,
    closeTo(available * 0.6, 0.5),
    reason: '块内的图占可用宽度的六成',
  );
  expect(
    tester.getCenter(inside).dx,
    tester.getCenter(outside).dx,
    reason: '块内的图水平居中，与块外的图同一条中线',
  );
}

/// 走首启到「下载视频」一次性图文卡；教程正文换成假资产里的 [tutorialMarkdown]，
/// 引导文案仍取仓库里的随包文件；[images] 补进假资产包（正文里除赞赏码外还引用
/// 别的图时用）。
Future<void> _pumpFirstRunCard(
  WidgetTester tester, {
  required String tutorialMarkdown,
  Map<String, Uint8List> images = const {},
}) async {
  expect(
    helpGuideSteps.any(
      (step) => step.sourceDocumentId == downloadVideoTutorialId,
    ),
    isTrue,
    reason: '首启必须有一条取教程正文的引导步，卡才有正文可渲染',
  );
  await pumpFirstRunHost(
    tester,
    storage: InMemoryPrivateJsonStorage(),
    helpAssets: FakeHelpAssetBundle(
      {
        onboardingCopyAssetKey: File(onboardingCopyAssetKey).readAsStringSync(),
        '$downloadVideoTutorialDirectory/下载视频.md': tutorialMarkdown,
      },
      binary: {
        '$downloadVideoTutorialDirectory/reward.png': onePixelPng,
        ...images,
      },
    ),
  );
  resetFirstRunSession(tester);
  await tester.pump();

  await tester.tap(find.text(welcomeTourLabel));
  await tester.pumpAndSettle();
}
