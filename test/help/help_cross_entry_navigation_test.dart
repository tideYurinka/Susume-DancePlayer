import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/clipboard_capture.dart';
import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/help_assets_fixture.dart';
import '../helpers/markdown_text_assertions.dart';

/// 跨条目链接的点击与返回：正文里写仓内相对
/// 路径，点一下推入目标条目的文档页（可带锚点），返回回到上一篇；解析不到
/// 条目或锚点找不到时按外部链接处理（复制到剪贴板 + 提示），不弹错、不崩。
void main() {
  const manualDirectory = '$helpGuideAssetDir/02-控制界面概述';
  const segmentDirectory = '$helpGuideAssetDir/04-分段';
  const manualDocumentId = '控制界面概述';
  const segmentDocumentId = '分段';

  /// 目标条目正文；[long] 时在目标标题前后各堆一段长文，用于断言滚动落点。
  String segmentMarkdown({bool long = false}) =>
      '# 分段\n'
      '\n'
      '分段说明第一段。\n'
      '\n'
      '${long ? '${List.filled(20, '前填充。').join('\n\n')}\n\n' : ''}'
      '## 调进度\n'
      '\n'
      '拖动即可。\n'
      '${long ? '\n${List.filled(20, '后填充。').join('\n\n')}\n' : ''}';

  /// 起页（控制界面概述）正文里写一条指向《分段》的链接；[href] 换成别的
  /// 地址即可测不同分支。
  FakeHelpAssetBundle bundleWithLink(String href, {bool long = false}) =>
      FakeHelpAssetBundle({
        onboardingCopyAssetKey: helpOnboardingStub,
        '$manualDirectory/控制界面概述.md':
            '# 控制界面概述\n'
            '\n'
            '见[《分段》]($href)那章。\n',
        '$segmentDirectory/分段.md': segmentMarkdown(long: long),
      });

  Future<void> pumpManual(
    WidgetTester tester, {
    required String href,
    bool long = false,
    Size viewport = const Size(1000, 2000),
  }) async {
    // 合成档视口（入参 viewport，默认 1000×2000dp；dpr 1.0），非设备档。
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpAssetBundleProvider.overrideWithValue(
            bundleWithLink(href, long: long),
          ),
        ],
        child: const MaterialApp(
          home: HelpDocumentPage(documentId: manualDocumentId),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 断言当前页的标题栏写着 [title]。
  void expectAppBarTitle(String title) => expect(
    find.descendant(of: find.byType(AppBar), matching: find.text(title)),
    findsOneWidget,
  );

  testWidgets('点跨条目链接推入目标条目的文档页，返回回到上一篇', (tester) async {
    await pumpManual(tester, href: '../04-分段/分段.md');

    expectAppBarTitle(manualDocumentId);

    await tester.tapOnText(find.textRange.ofSubstring('《分段》'));
    await tester.pumpAndSettle();

    expectAppBarTitle(segmentDocumentId);
    expect(plainTexts(tester), contains('分段说明第一段。'));
    expect(find.text('控制界面概述'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expectAppBarTitle(manualDocumentId);
    expect(plainTexts(tester), contains('见《分段》那章。'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('带锚点的跨条目链接：落在目标条目的那条标题上', (tester) async {
    await pumpManual(
      tester,
      href: '../04-分段/分段.md#调进度',
      long: true,
      viewport: const Size(1000, 600),
    );

    await tester.tapOnText(find.textRange.ofSubstring('《分段》'));
    await tester.pumpAndSettle();
    // 落点靠首帧之后的「预载图 → 滚动」链路，与既有的带锚点进入同一套驱动。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pumpAndSettle();

    expectAppBarTitle(segmentDocumentId);
    final offset = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(offset, greaterThan(0), reason: '停在目标锚点');
    expect(tester.getTopLeft(find.text('调进度')).dy, inInclusiveRange(0, 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('解析不到条目：按外部链接处理，复制到剪贴板、不推入新页', (tester) async {
    await pumpManual(tester, href: '../99-不存在的章/不存在.md');
    final clipboardCalls = mockClipboard(tester);

    await tester.tapOnText(find.textRange.ofSubstring('《分段》'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1), reason: '按外部链接处理：复制 + 提示');
    // 地址照原样复制（渲染器交回的是百分号转义形式，解回来即作者写的那条）。
    final copied = (clipboardCalls.single.arguments as Map)['text'] as String;
    expect(Uri.decodeFull(copied), '../99-不存在的章/不存在.md');
    expectAppBarTitle(manualDocumentId);
    expect(find.text('已复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('锚点在目标条目里找不到：同上按外部链接处理，不弹错', (tester) async {
    await pumpManual(tester, href: '../04-分段/分段.md#没有的小节');
    final clipboardCalls = mockClipboard(tester);

    await tester.tapOnText(find.textRange.ofSubstring('《分段》'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    expectAppBarTitle(manualDocumentId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('指回本文的相对路径也走推入通路：压一条路由、返回即上一篇', (tester) async {
    await pumpManual(tester, href: '控制界面概述.md');
    expect(find.byType(BackButton), findsNothing, reason: '起页没有可返回的上一页');

    await tester.tapOnText(find.textRange.ofSubstring('《分段》'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget, reason: '推入了目标页面');

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsNothing);
    expectAppBarTitle(manualDocumentId);
    expect(tester.takeException(), isNull);
  });
}
