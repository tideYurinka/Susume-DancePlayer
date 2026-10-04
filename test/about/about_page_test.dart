import 'dart:async';

import 'package:dance_learning_app/about/about_page.dart';
import 'package:dance_learning_app/core/app_identity.dart';
import 'package:dance_learning_app/update/update_check.dart';
import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/fake_update_gateway.dart';
import '../helpers/update_manifest_fixture.dart';

/// 关于页新骨架：**应用信息头**（居中的圆形图标、应用名与一句话简介，不含任何
/// 操作）之下依次是**版本行**、更新说明行与贡献者名单行。版本行按七态映射上屏，
/// 中间格宽高写死、右侧按钮定尺寸，所以状态换来换去都不推动布局；开页不自动
/// 检查，检查由右端按钮发起，全部走与更新提示条共用的那台状态机。
void main() {
  testWidgets('应用信息头：居中的圆形图标、应用名与一句话简介', (tester) async {
    await _pumpAboutPage(tester);

    final header = find.byKey(const Key('about_app_info_header'));
    expect(header, findsOneWidget);
    final icon = find.byKey(const Key('about_app_icon'));
    expect(icon, findsOneWidget);
    expect(
      (tester.widget<Image>(icon).image as AssetImage).assetName,
      appIconAsset,
      reason: '头部画的是随包的应用图标',
    );
    expect(
      find.ancestor(of: icon, matching: find.byType(ClipOval)),
      findsOneWidget,
      reason: '图标圆形裁切',
    );
    expect(find.text(appDisplayName), findsOneWidget);
    expect(find.text(appTagline), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('应用信息头居中，且不含任何操作', (tester) async {
    await _pumpAboutPage(tester);

    final center = tester.getCenter(find.byKey(const Key('about_app_icon'))).dx;
    expect(
      tester.getCenter(find.text(appDisplayName)).dx,
      closeTo(center, 0.5),
      reason: '应用名与图标同一条中轴',
    );
    expect(
      tester.getCenter(find.text(appTagline)).dx,
      closeTo(center, 0.5),
      reason: '一句话简介与图标同一条中轴',
    );

    final header = find.byKey(const Key('about_app_info_header'));
    expect(
      find.descendant(of: header, matching: find.byType(ButtonStyleButton)),
      findsNothing,
      reason: '头部没有按钮',
    );
    expect(
      find.descendant(of: header, matching: find.byType(InkWell)),
      findsNothing,
      reason: '头部没有可点的行',
    );
  });

  testWidgets('信息头之下依次是版本行、更新说明行与贡献者名单行', (tester) async {
    await _pumpAboutPage(tester);

    final header = tester.getBottomLeft(
      find.byKey(const Key('about_app_info_header')),
    );
    final versionRow = tester.getTopLeft(
      find.byKey(const Key('about_version_row')),
    );
    final notesRow = tester.getTopLeft(
      find.byKey(const Key('about_update_notes_row')),
    );
    final contributorsRow = tester.getTopLeft(
      find.byKey(const Key('about_contributors_row')),
    );
    expect(versionRow.dy, greaterThanOrEqualTo(header.dy));
    expect(notesRow.dy, greaterThan(versionRow.dy));
    expect(contributorsRow.dy, greaterThan(notesRow.dy));
  });

  testWidgets('版本行横排三段：左版本值、中状态格、右按钮，没有前导图标那一段', (tester) async {
    await _pumpAboutPage(tester);

    final row = find.byKey(const Key('about_version_row'));
    expect(
      find.descendant(of: row, matching: find.byType(Icon)),
      findsNothing,
      reason: '横排三段，没有图标那一段',
    );

    final value = tester.getRect(find.byKey(const Key('about_version_value')));
    final middle = tester.getRect(
      find.byKey(const Key('about_version_middle')),
    );
    final action = tester.getRect(
      find.byKey(const Key('about_version_action')),
    );
    expect(value.right, lessThanOrEqualTo(middle.left), reason: '左段整个在中段左侧');
    expect(middle.right, lessThanOrEqualTo(action.left), reason: '中段整个在按钮左侧');
    expect(value.left, lessThan(middle.left));
  });

  testWidgets('开页不自动检查：未按下之前不碰网关', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2)],
    );
    await _pumpAboutPage(tester, gateway: gateway);

    expect(gateway.fetchCalls, 0, reason: '进关于页看版本号不花一次流量');
    expect(find.text('未检查'), findsOneWidget);
  });

  group('版本行七态', () {
    testWidgets('未检查：中间格写「未检查」，右端是空心的「检查更新」', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2)],
      );
      await _pumpAboutPage(tester, gateway: gateway);

      expect(_statusText(tester), '未检查');
      expect(_actionText(tester), '检查更新');
      expect(
        _actionButton(tester),
        isA<OutlinedButton>(),
        reason: '还没查到新版时按钮是空心的',
      );
    });

    testWidgets('按下「检查更新」才发起检查，结果落回中间格', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2)],
      );
      await _pumpAboutPage(tester, gateway: gateway);

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(gateway.fetchCalls, 1);
      expect(find.text('最新版本 0.1.0'), findsOneWidget);
    });

    testWidgets('检查中：中间格写「检查中…」，右端换成转圈且不能再按', (tester) async {
      final gate = Completer<void>();
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2)],
      )..gate = gate;
      await _pumpAboutPage(tester, gateway: gateway);

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pump();

      expect(_statusText(tester), '检查中…');
      expect(_actionText(tester), '', reason: '按钮上没有字，只有一枚转圈');
      expect(find.byKey(const Key('about_version_checking')), findsOneWidget);
      expect(_actionButton(tester).onPressed, isNull, reason: '检查中不能重复按');

      await tester.tap(
        find.byKey(const Key('about_version_action')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(gateway.fetchCalls, 1, reason: '在飞的检查不会因再按而重复发起');

      gate.complete();
      await tester.pumpAndSettle();
      expect(_statusText(tester), '最新版本 0.1.0');
    });

    testWidgets('无新版：中间格写「已是最新」，按钮回到空心的「检查更新」', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 1)],
      );
      await _pumpAboutPage(tester, gateway: gateway);

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(_statusText(tester), '已是最新');
      expect(_actionText(tester), '检查更新');
      expect(_actionButton(tester), isA<OutlinedButton>());
    });

    testWidgets('有新版：中间格写出最新版本名，按钮换成实心的「下载」', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
        ],
      );
      await _pumpAboutPage(tester, gateway: gateway);

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(_statusText(tester), '最新版本 0.1.1');
      expect(_actionText(tester), '下载');
      expect(_actionButton(tester), isA<FilledButton>(), reason: '有新版时按钮实心');
    });

    testWidgets('下载中：中间格写百分比并长出进度条，按钮换成「取消」；取消回到可下载', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(buildNumber: 2, size: 1024 * 1024),
        ],
      )..progressScript = const [(256 * 1024, 1024 * 1024)];
      gateway.downloadGate = Completer<void>();
      await _pumpAboutPage(tester, gateway: gateway);
      await _startDownload(tester);

      expect(
        _statusText(tester),
        '下载中 25%',
        reason: 'spec §6 表：下载中这一态只写「下载中 N%」',
      );
      expect(find.byKey(const Key('about_version_progress')), findsOneWidget);
      expect(_actionText(tester), '取消');

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(gateway.cancelCalls, 1, reason: '取消走既有那一份包的取消通路');
      expect(_statusText(tester), '最新版本 0.1.0');
      expect(_actionText(tester), '下载');
      expect(tester.takeException(), isNull);
    });

    testWidgets('待放行安装许可：中间格写缺的那一步，按钮换成实心的「前往设置」', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      )..canRequestInstallValue = false;
      await _pumpAboutPage(tester, gateway: gateway);
      await _startDownload(tester, settle: true);

      expect(_statusText(tester), '需要允许安装未知应用');
      expect(_actionText(tester), '前往设置');
      expect(_actionButton(tester), isA<FilledButton>());
      expect(gateway.openInstallSettingsCalls, 0, reason: '不自动跳转设置页');

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(gateway.openInstallSettingsCalls, 1, reason: '按下才走既有的设置页通路');
    });

    testWidgets('检查失败：中间格写「无法检查更新」并给「重试」，不假装已是最新', (tester) async {
      final gateway = FakeUpdateGateway(manifestScript: [null]);
      await _pumpAboutPage(tester, gateway: gateway);

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(_statusText(tester), '无法检查更新');
      expect(_actionText(tester), '重试');
      expect(find.text('已是最新'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('下载失败与检查失败分得开：中间格写「下载失败」，「重试」重新下载', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      )..downloadError = const UpdateDownloadException();
      await _pumpAboutPage(tester, gateway: gateway);
      await _startDownload(tester, settle: true);

      expect(_statusText(tester), '下载失败');
      expect(_actionText(tester), '重试');
      expect(find.text('无法检查更新'), findsNothing);

      gateway.downloadError = null;
      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(gateway.downloadCalls, 2, reason: '重试只重下这一份包，不重新检查');
      expect(gateway.fetchCalls, 1);
    });

    testWidgets('状态切换时行高与两侧位置不动', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(buildNumber: 1),
          updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
        ],
      );
      await _pumpAboutPage(tester, gateway: gateway);

      final before = _rowPieces(tester);
      // 未检查 → 已是最新
      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();
      expect(_rowPieces(tester), before, reason: '文字变短也不动布局');

      // 已是最新 → 有新版
      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();
      expect(_rowPieces(tester), before, reason: '按钮从空心换实心、文案变长也不动布局');
    });

    testWidgets('下载中多出进度条：行高、版本值与按钮位置都不动', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2)],
      )..progressScript = const [(20308641, 81234567)];
      gateway.downloadGate = Completer<void>();
      await _pumpAboutPage(tester, gateway: gateway);
      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      final before = _rowPieces(tester);
      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pump();

      expect(find.byKey(const Key('about_version_progress')), findsOneWidget);
      expect(_statusText(tester), '下载中 25%');
      expect(_rowPieces(tester), before, reason: '进度条长在自己的槽里，不推动行高');

      gateway.downloadGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('窄屏 320：中间格只写「下载中 N%」，不越出格、不压右侧按钮', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(buildNumber: 2, size: 1024 * 1024),
        ],
      )..progressScript = const [(256 * 1024, 1024 * 1024)];
      gateway.downloadGate = Completer<void>();
      await _pumpAboutPage(
        tester,
        gateway: gateway,
        viewport: const Size(320, 2000),
      );
      await _startDownload(tester);

      expect(_statusText(tester), '下载中 25%', reason: '这一态不写包体积，格子里放得下');
      expect(_statusLayoutOverflow(tester), lessThanOrEqualTo(0.5));
      final status = tester.getRect(
        find.byKey(const Key('about_version_status')),
      );
      final action = tester.getRect(
        find.byKey(const Key('about_version_action')),
      );
      expect(status.right, lessThanOrEqualTo(action.left), reason: '不压到右侧按钮');

      gateway.downloadGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('大字号：中间格里的状态文字收在格内，不画到右侧按钮上', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
        ],
      );
      await _pumpAboutPage(tester, gateway: gateway, textScale: 2.0);

      await tester.tap(find.byKey(const Key('about_version_action')));
      await tester.pumpAndSettle();

      expect(_statusText(tester), '最新版本 0.1.1');
      expect(
        _statusLayoutOverflow(tester),
        lessThanOrEqualTo(0.5),
        reason: '语义状态文字随系统字号缩放，盒子容量得跟上；窄于文字需要的一行宽就会画到格外',
      );
      final status = tester.getRect(
        find.byKey(const Key('about_version_status')),
      );
      final action = tester.getRect(
        find.byKey(const Key('about_version_action')),
      );
      expect(
        status.right,
        lessThanOrEqualTo(action.left + 0.5),
        reason: '不压到右侧按钮',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('版本行按钮的实际命中矩形不小于 48×48：靠透明外扩，视觉件不跟着变大', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2)],
      );
      await _pumpAboutPage(tester, gateway: gateway);
      final action = find.byKey(const Key('about_version_action'));

      final hit = tester.getRect(action);
      expect(hit.width, greaterThanOrEqualTo(48), reason: '命中矩形（不是视觉件矩形）的下限');
      expect(hit.height, greaterThanOrEqualTo(48), reason: '命中矩形（不是视觉件矩形）的下限');

      // 视觉件仍是那枚定尺寸按钮：为达下限把可见按钮撑大就不是透明外扩。
      final visual = tester.getRect(
        find.descendant(of: action, matching: find.byType(InkWell)),
      );
      expect(visual.height, lessThan(48), reason: '视觉件不高过命中盒');
      expect(visual.width, hit.width, reason: '横向本来就够，不外扩');

      // 外扩出来的那一条真的接住点按：命中盒顶缘按下也算按了这颗按钮。
      await tester.tapAt(Offset(hit.center.dx, hit.top + 1));
      await tester.pumpAndSettle();
      expect(gateway.fetchCalls, 1, reason: '透明外扩出来的命中域归这颗按钮');
    });

    testWidgets('交安装器在飞：版本行按钮同样不可按，状态文字照常可读', (tester) async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(
            buildNumber: 2,
            versionName: '0.1.1',
            size: 1000,
          ),
        ],
      )..installGate = Completer<void>();
      await _pumpAboutPage(tester, gateway: gateway);
      await _startDownload(tester, settle: true);

      expect(gateway.requestInstallCalls, 1, reason: '下载完成即交安装器，那一下还挂在那里');
      expect(_statusText(tester), '最新版本 0.1.1', reason: '状态文字照常可读，不留空白格');
      expect(
        _actionButton(tester).onPressed,
        isNull,
        reason: '在飞时与提示条同一结论：不接受第二次按下',
      );

      await tester.tap(
        find.byKey(const Key('about_version_action')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(gateway.downloadCalls, 1, reason: '在飞时不因再按而重下一份包');

      gateway.installGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  test('用户可见版本号只有版本名，构建号不显示', () {
    PackageInfo info(String version, String buildNumber) => PackageInfo(
      appName: 'Susume',
      packageName: 'dance_learning_app',
      version: version,
      buildNumber: buildNumber,
    );

    expect(aboutVersionLabel(info('0.1.0', '1')), '0.1.0');
    expect(aboutVersionLabel(info('1.2.3', '45')), '1.2.3');
    expect(aboutVersionLabel(info('0.1.0', '')), '0.1.0');
  });

  testWidgets('本机版本值只上屏版本名：构建号不进屏', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Susume',
      packageName: 'dance_learning_app',
      version: '0.1.0',
      buildNumber: '6',
      buildSignature: '',
    );
    await _pumpAboutPage(tester, realVersion: true);

    expect(
      tester.widget<Text>(find.byKey(const Key('about_version_value'))).data,
      '0.1.0',
    );
    expect(find.text('0.1.0+6'), findsNothing, reason: '构建号只留在诊断信息里');
  });

  testWidgets('版本信息读不出：页面照常，不崩', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000); // 合成档，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aboutAppVersionProvider.overrideWith(
            (ref) => Future<String>.error(StateError('平台通道不在')),
          ),
        ],
        child: const MaterialApp(home: AboutPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('about_app_info_header')), findsOneWidget);
    expect(find.text(appDisplayName), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 版本行里会被状态推动的几何：整行矩形、左端版本值的矩形、右端按钮的矩形。
/// 状态换来换去时它们应当一模一样。
List<double> _rowPieces(WidgetTester tester) => [
  ..._rect(tester, find.byKey(const Key('about_version_row'))),
  ..._rect(tester, find.byKey(const Key('about_version_value'))),
  ..._rect(tester, find.byKey(const Key('about_version_action'))),
];

List<double> _rect(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  return [rect.left, rect.top, rect.right, rect.bottom];
}

/// 版本行右端那颗按钮。
ButtonStyleButton _actionButton(WidgetTester tester) => tester
    .widget<ButtonStyleButton>(find.byKey(const Key('about_version_action')));

/// 先把版本行推到「有新版」，再按下「下载」；[settle] 为真时等下载走完。
Future<void> _startDownload(WidgetTester tester, {bool settle = false}) async {
  await tester.tap(find.byKey(const Key('about_version_action')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('about_version_action')));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// 版本行中间格上屏的那句状态文字。
String _statusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('about_version_status'))).data!;

/// 状态文字的排版盒比它自己排一行所需的宽度窄出多少；≤0 即整句话收在盒内。
/// 文字排不进自己的盒子时 Flutter 不报错（画到盒外就完了），故这是唯一量得
/// 出来的越界读数。
double _statusLayoutOverflow(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const Key('about_version_status')),
  );
  return box.getMaxIntrinsicWidth(double.infinity) - box.size.width;
}

/// 版本行右端那颗按钮上屏的字；没有文字（转圈）时为空串。
String _actionText(WidgetTester tester) {
  final text = find.descendant(
    of: find.byKey(const Key('about_version_action')),
    matching: find.byType(Text),
  );
  if (text.evaluate().isEmpty) return '';
  return tester.widget<Text>(text).data!;
}

/// 关于页 widget 测试共用的装配：版本 provider 给确定值（[realVersion] 为真时
/// 不覆写，走 `package_info_plus` 的假平台值），本机构建号与更新网关给确定
/// 替身——检查与下载都不发真实网络请求。
Future<void> _pumpAboutPage(
  WidgetTester tester, {
  String version = '0.1.0',
  bool realVersion = false,
  UpdateGateway? gateway,
  int localBuildNumber = 1,
  Size viewport = const Size(1000, 2000),
  double textScale = 1.0,
}) async {
  // 合成档视口（入参 viewport，默认 1000×2000dp；dpr 1.0），非设备档；
  // [textScale] 是系统字号档（默认 1.0×）。
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (!realVersion)
          aboutAppVersionProvider.overrideWith((ref) => version),
        localBuildNumberProvider.overrideWith((ref) => localBuildNumber),
        if (gateway != null) updateGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(home: AboutPage()),
    ),
  );
  await tester.pumpAndSettle();
}
