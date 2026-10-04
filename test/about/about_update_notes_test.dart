import 'package:dance_learning_app/about/about_page.dart';
import 'package:dance_learning_app/help/platform_help_actions.dart';
import 'package:dance_learning_app/update/update_check.dart';
import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/clipboard_capture.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/fake_update_gateway.dart';

/// 关于页「更新说明」行：点一下交系统浏览器打开官网下载页的更新说明锚点
/// （落地即展开）；打不开时按既有**外部网址**口径收场——把地址复制到剪贴板并
/// 提示「打不开，已复制地址」。打开件是既有那条缝的替身，不碰真浏览器。
/// 落点取实现导出的 [aboutUpdateNotesUrl]：地址写错、锚点丢了都在下面这组
/// 断言里现形，用例不另抄一份字面量当期望值。
void main() {
  test('落点是官网下载页的更新说明锚点', () {
    final uri = Uri.parse(aboutUpdateNotesUrl);
    expect(uri.scheme, 'https');
    expect(uri.host, 'susume.yurinka.top', reason: '官网下载页的固定地址');
    expect(uri.path, '/download/', reason: '落点是下载页');
    expect(uri.fragment, isNotEmpty, reason: '地址带更新说明锚点，浏览器落在锚点上即展开那一块');
  });

  testWidgets('点「更新说明」把下载页的更新说明锚点交系统浏览器打开', (tester) async {
    final opener = FakeHelpExternalLinkOpener();
    await _pumpAboutPage(tester, opener: opener);
    final clipboardCalls = mockClipboard(tester);

    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('about_update_notes_row')))
          .onTap,
      isNotNull,
      reason: '这一行点得动',
    );
    await tester.tap(find.byKey(const Key('about_update_notes_row')));
    await tester.pumpAndSettle();

    expect(opener.opened, [aboutUpdateNotesUrl], reason: '地址原样交给打开件');
    expect(
      Uri.parse(opener.opened.single).hasFragment,
      isTrue,
      reason: '交出去的地址带锚点',
    );
    expect(clipboardCalls, isEmpty, reason: '交出去了就不复制');
    expect(find.text('打不开，已复制地址'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打不开：复制地址并提示「打不开，已复制地址」', (tester) async {
    final opener = FakeHelpExternalLinkOpener(result: false);
    await _pumpAboutPage(tester, opener: opener);
    final clipboardCalls = mockClipboard(tester);

    await tester.tap(find.byKey(const Key('about_update_notes_row')));
    await tester.pumpAndSettle();

    expect(opener.opened, [aboutUpdateNotesUrl], reason: '先试过交出去');
    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.arguments, {'text': aboutUpdateNotesUrl});
    expect(find.text('打不开，已复制地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 关于页 widget 测试的装配：版本 provider 与更新网关给确定替身，打开件换成
/// 既有那条缝的替身——点行不碰真浏览器、也不发真实网络请求。
Future<void> _pumpAboutPage(
  WidgetTester tester, {
  required FakeHelpExternalLinkOpener opener,
}) async {
  tester.view.physicalSize = const Size(1000, 2000); // 合成档，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aboutAppVersionProvider.overrideWith((ref) => '0.1.0'),
        localBuildNumberProvider.overrideWith((ref) => 1),
        updateGatewayProvider.overrideWithValue(FakeUpdateGateway()),
        helpExternalLinkOpenerProvider.overrideWithValue(opener),
      ],
      child: const MaterialApp(home: AboutPage()),
    ),
  );
  await tester.pumpAndSettle();
}
