import 'package:dance_learning_app/help/platform_help_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/clipboard_capture.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/help_document_harness.dart';

/// 帮助正文里的外部链接：带 `http`/
/// `https` 的地址交系统浏览器打开；打不开（没交出去）时复制地址并提示
/// 「打不开，已复制地址」；不带 scheme 或带其它 scheme 的地址仍走复制并提示
/// 「已复制」。打开件是端口替身，不碰真浏览器。
void main() {
  const url = 'https://example.com/guide';

  Future<FakeHelpExternalLinkOpener> pumpWithOpener(
    WidgetTester tester,
    String markdown, {
    required bool openResult,
  }) async {
    final opener = FakeHelpExternalLinkOpener(result: openResult);
    await pumpHelpDocumentPage(
      tester,
      markdown: markdown,
      overrides: [helpExternalLinkOpenerProvider.overrideWithValue(opener)],
    );
    return opener;
  }

  testWidgets('显式 http 链接点一下交系统浏览器打开，不复制到剪贴板', (tester) async {
    final opener = await pumpWithOpener(
      tester,
      '# 下载视频\n\n见[网盘]($url)。\n',
      openResult: true,
    );
    final clipboardCalls = mockClipboard(tester);

    await tester.tapOnText(find.textRange.ofSubstring('网盘'));
    await tester.pumpAndSettle();

    expect(opener.opened, [url], reason: '地址原样交给打开件');
    expect(clipboardCalls, isEmpty, reason: '交出去了就不复制');
    expect(find.text('打不开，已复制地址'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开失败（没交出去）：复制该地址并提示「打不开，已复制地址」', (tester) async {
    final opener = await pumpWithOpener(
      tester,
      '# 下载视频\n\n见[网盘]($url)。\n',
      openResult: false,
    );
    final clipboardCalls = mockClipboard(tester);

    await tester.tapOnText(find.textRange.ofSubstring('网盘'));
    await tester.pumpAndSettle();

    expect(opener.opened, [url], reason: '先试过交出去');
    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.arguments, {'text': url});
    expect(find.text('打不开，已复制地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 scheme 的「点击复制」：复制到剪贴板并提示「已复制」，不交打开件', (tester) async {
    final opener = await pumpWithOpener(
      tester,
      '# 下载视频\n\n群号：1102058156 [点击复制](1102058156)\n',
      openResult: true,
    );
    final clipboardCalls = mockClipboard(tester);

    await tester.tapOnText(find.textRange.ofSubstring('点击复制'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.arguments, {'text': '1102058156'});
    expect(find.text('已复制'), findsOneWidget);
    expect(opener.opened, isEmpty, reason: '无 scheme 不交浏览器');
    expect(tester.takeException(), isNull);
  });

  testWidgets('其它 scheme（mailto）同样走复制 + 「已复制」', (tester) async {
    const mailto = 'mailto:author@example.com';
    final opener = await pumpWithOpener(
      tester,
      '# 下载视频\n\n[写邮件]($mailto)\n',
      openResult: true,
    );
    final clipboardCalls = mockClipboard(tester);

    await tester.tapOnText(find.textRange.ofSubstring('写邮件'));
    await tester.pumpAndSettle();

    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.arguments, {'text': mailto});
    expect(find.text('已复制'), findsOneWidget);
    expect(opener.opened, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
