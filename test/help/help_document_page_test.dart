import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:dance_learning_app/help/platform_help_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/help_assets_fixture.dart';
import '../helpers/help_document_harness.dart';
import '../helpers/markdown_text_assertions.dart';

/// 「下载视频」教程的条目目录。
const String _directory = downloadVideoTutorialDirectory;

/// 文档页的 Markdown 正文渲染：输入侧是假资产包，
/// 断言只落在**屏幕上看到的东西**上——各元素可见、图片取自同目录资产、缺图与
/// 缺正文不留空框、链接可点。
void main() {
  const directory = _directory;
  const imageKey = '$directory/shot.png';

  testWidgets('标题层级、有序与无序列表、引用块、粗体、图片、可点链接逐项可见', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '''
# 下载视频

开头一段。

## 方法一

1. 第一步
2. 第二步

- 无序项甲
- 无序项乙

> 注意：先存相册

普通**粗体**结尾。

![截图](shot.png)
''',
      binary: {imageKey: onePixelPng},
    );

    final texts = plainTexts(tester);
    // 标题层级：一级标题与二级标题各自成块。
    expect(texts, contains('下载视频'));
    expect(texts, contains('方法一'));
    // 有序与无序列表项逐项可见。
    expect(texts, contains('第一步'));
    expect(texts, contains('第二步'));
    expect(texts, contains('无序项甲'));
    expect(texts, contains('无序项乙'));
    // 引用块（提示块）照常渲染文字。
    expect(texts, contains('注意：先存相册'));
    // 粗体保留为加粗的富文本区间。
    final bold = textSpans(tester).firstWhere((span) => span.text == '粗体');
    expect(bold.style?.fontWeight, FontWeight.bold);
    // 图片按相对文件名解析到同目录资产。
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      imageKey,
      reason: '正文写相对文件名，渲染时取同目录资产',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('裸网址自动成可点链接；点一下交系统浏览器打开', (tester) async {
    const url = 'https://www.jijidown.com/';
    final opener = FakeHelpExternalLinkOpener();
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n官网 $url 有客户端。\n',
      overrides: [helpExternalLinkOpenerProvider.overrideWithValue(opener)],
    );

    final link = textSpans(tester)
        .firstWhere((span) => span.recognizer != null && span.text == url);
    expect(link.text, url, reason: '裸网址由渲染器扩展集自动成链接');

    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();

    expect(opener.opened, [url], reason: '裸网址同样交系统浏览器打开');
  });

  testWidgets('文件不存在的图片不渲染、不留空框，正文照常', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n正文照常。\n\n![缺图](missing.png)\n\n后面还有一段。\n',
    );

    expect(find.byType(Image), findsNothing);
    expect(plainTexts(tester), contains('正文照常。'));
    expect(plainTexts(tester), contains('后面还有一段。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页标题取正文的一级标题，而不是代码表标题', (tester) async {
    await pumpHelpDocumentPage(tester, markdown: '# 改过的标题\n\n正文。\n');

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('改过的标题')),
      findsOneWidget,
    );
  });

  testWidgets('一级标题只在标题栏，正文里不再重复那一行', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n正文一段。\n\n## 方法一\n\n1. 第一步\n',
    );

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('下载视频')),
      findsOneWidget,
      reason: '标题栏写这篇的标题',
    );
    expect(find.text('下载视频'), findsOneWidget, reason: '正文里没有那一行');
    expect(plainTexts(tester), contains('正文一段。'));
    expect(plainTexts(tester), contains('方法一'));
  });

  testWidgets('正文没有一级标题：文档页不崩，正文照常渲染', (tester) async {
    await pumpHelpDocumentPage(tester, markdown: '## 小节\n\n正文照常。\n');

    expect(find.text(downloadVideoTutorialId), findsOneWidget);
    expect(find.byKey(const Key('help_document_markdown')), findsOneWidget);
    expect(plainTexts(tester), contains('正文照常。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('正文只有一级标题没有正文：文档页不崩、正文区为空', (tester) async {
    await pumpHelpDocumentPage(tester, markdown: '# 下载视频\n');

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('下载视频')),
      findsOneWidget,
    );
    expect(find.text('下载视频'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('条目目录里没有正文：页面不崩，标题照常显示', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpAssetBundleProvider.overrideWithValue(
            FakeHelpAssetBundle(const {}),
          ),
        ],
        child: const MaterialApp(
          home: HelpDocumentPage(documentId: downloadVideoTutorialId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(downloadVideoTutorialId), findsOneWidget);
    expect(find.byKey(const Key('help_document_markdown')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('条目不在装载结果里：标题退回 id、正文区为空、不崩', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpAssetBundleProvider.overrideWithValue(
            FakeHelpAssetBundle(const {}),
          ),
        ],
        child: const MaterialApp(home: HelpDocumentPage(documentId: '不存在')),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('不存在')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('help_document_markdown')), findsNothing);
  });
  testWidgets('点正文里的锚点滚到那条标题：长文下方也能滚到位，落点不被图片撑高带偏', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      viewport: const Size(1000, 600),
      markdown:
          '''
# 下载视频

[跳到方法三](#方法三电脑下载b站视频)

![截图](shot.png)

${List.filled(20, '填充段落，把方法三压到长文下方。').join('\n\n')}

## 方法三：电脑下载B站视频

目标一段。

${List.filled(30, '目标之后的段落，保证目标标题能滚到视口顶端。').join('\n\n')}
''',
      binary: {imageKey: onePixelPng},
    );
    double offset() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(offset(), 0);

    // 图片预载与解码是真实异步：tap 之后泵帧与放行真实异步交替，直到链路
    // （预载 → 图齐帧 → 滚动动画）走完。
    await tester.runAsync(() async {
      await tester.tapOnText(find.textRange.ofSubstring('跳到方法三'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();

    expect(offset(), greaterThan(0), reason: '锚点命中目标标题，页面滚过去了');
    final headingTop = tester.getTopLeft(find.text('方法三：电脑下载B站视频')).dy;
    expect(headingTop, inInclusiveRange(0, 200), reason: '落点在目标标题处，不被图片撑高带偏');
  });

  testWidgets('锚点找不到目标：不滚、停在顶部，不报错', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      viewport: const Size(1000, 600),
      markdown:
          '# 下载视频\n\n[跳到没有的小节](#不存在的小节)\n\n${List.filled(20, '填充段落。').join('\n\n')}\n',
    );
    double offset() => tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;

    await tester.tapOnText(find.textRange.ofSubstring('跳到没有的小节'));
    await tester.pumpAndSettle();

    expect(offset(), 0);
    expect(tester.takeException(), isNull);
  });
}
