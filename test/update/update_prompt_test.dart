import 'dart:async';

import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/update/update_check.dart';
import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:dance_learning_app/update/update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/fake_update_gateway.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/update_manifest_fixture.dart';

/// 启动静默检查、更新提示条与安装请求：断言只
/// 落在用户看得见的态上——条出不出现、写的哪句话、按下发生什么、切 Tab 后还在
/// 不在、未授权时走设置页、从设置页返回后能不能接着装；下载的文件落点由真实网
/// 关的测试覆盖。
void main() {
  test('包体积按 1024 进制换算成一位小数的 MB', () {
    expect(formatUpdateSize(81234567), '77.5 MB');
    expect(formatUpdateSize(1024 * 1024), '1.0 MB');
    expect(formatUpdateSize(0), '0.0 MB');
  });

  testWidgets('启动后自动评估一次；构建号不更大时提示条完全不出现', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 1)],
    );
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);

    expect(find.byKey(const Key('update_prompt_bar')), findsNothing);
    expect(gateway.fetchCalls, 1, reason: '启动后自己静默问了一次');
    expect(tester.takeException(), isNull);
  });

  testWidgets('取不到清单（无网/超时/解析失败）：提示条不出现，不弹错误', (tester) async {
    final gateway = FakeUpdateGateway();
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);

    expect(find.byKey(const Key('update_prompt_bar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('网关抛错：提示条不出现、不弹错误，启动照常', (tester) async {
    final gateway = FakeUpdateGateway()..fetchError = StateError('boom');
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);

    expect(find.byKey(const Key('update_prompt_bar')), findsNothing);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有新版本：左下角出现提示条，写明包体积，带「下载」与关闭叉', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [
        updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
      ],
    );
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);

    final bar = find.byKey(const Key('update_prompt_bar'));
    expect(bar, findsOneWidget);
    expect(find.text('新版本 0.1.1（77.5 MB）'), findsOneWidget);
    expect(find.byKey(const Key('update_prompt_action')), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.byKey(const Key('update_prompt_dismiss')), findsOneWidget);
    expect(tester.getTopLeft(bar).dx, 16, reason: '贴左下角');
    expectButtonSemantics(tester, const Key('update_prompt_action'));
    expectButtonSemantics(tester, const Key('update_prompt_dismiss'));
    expect(find.byTooltip('关闭'), findsOneWidget);
  });

  testWidgets('关闭叉只关本次：切 Tab 不回来；重建根壳（下次启动）再次出现', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [
        updateManifestFixture(buildNumber: 2),
        updateManifestFixture(buildNumber: 2),
      ],
    );
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('update_prompt_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update_prompt_bar')), findsNothing);

    await _switchTab(tester, 'tab_stats');
    await _switchTab(tester, 'tab_home');
    expect(
      find.byKey(const Key('update_prompt_bar')),
      findsNothing,
      reason: '关掉的是这一次，同一会话里不回来',
    );

    // 重建根壳 = 下一次启动：不写任何持久状态，条再次出现。
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);
  });

  testWidgets('提示条跨三个 Tab 存活：切 Tab 不消失', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2)],
    );
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);

    for (final tab in const ['tab_stats', 'tab_plan', 'tab_home']) {
      await _switchTab(tester, tab);
      expect(
        find.byKey(const Key('update_prompt_bar')),
        findsOneWidget,
        reason: '切到 $tab 后提示条仍在',
      );
    }
  });

  testWidgets('按下「下载」显示进度，下载用的是清单里的地址', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [
        updateManifestFixture(buildNumber: 2, size: 1000),
      ],
    )..progressScript = const [(250, 1000)];
    final gate = Completer<void>();
    gateway.downloadGate = gate;

    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pump();

    expect(find.text('下载中 25%'), findsOneWidget);
    expect(find.byKey(const Key('update_prompt_progress')), findsOneWidget);
    expect(gateway.downloadCalls, 1);
    expect(gateway.lastDownloadUrl, updateManifestFixtureApkUrl);
    expect(find.text('下载'), findsNothing, reason: '下载中不再显示「下载」');

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);
  });

  testWidgets('下载中点关闭叉 = 取消：条消失且网关收到取消', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2)],
    );
    gateway.downloadGate = Completer<void>();

    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pump();
    expect(find.textContaining('下载中'), findsOneWidget);

    await tester.tap(find.byKey(const Key('update_prompt_dismiss')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update_prompt_bar')), findsNothing);
    expect(gateway.cancelCalls, 1, reason: '下载中点叉即取消在飞的下载');
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载失败给一句人话 + 「重试」；重试重新下载', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [
        updateManifestFixture(buildNumber: 2, size: 1000),
        updateManifestFixture(buildNumber: 2, size: 1000),
      ],
    )..downloadError = const UpdateDownloadException();

    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();

    expect(find.text('下载失败，请检查网络后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    gateway.downloadError = null;
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();
    expect(gateway.downloadCalls, 2, reason: '重试重新下载');
    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载完成后授权为真：拉起系统安装器，装的是刚下载的那个包', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [
        updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
      ],
    );
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();

    expect(gateway.requestInstallCalls, 1, reason: '下载完成即请求安装');
    expect(gateway.lastRequestInstallPath, gateway.downloadedFilePath);
    expect(find.text('新版本 0.1.1（77.5 MB）'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget, reason: '拉起安装器后回到可重下的位置');
    expect(tester.takeException(), isNull);
  });

  testWidgets('未获授权：下载完成后提示条改为「需要允许安装未知应用」+ 前往设置，不自动跳转', (
    tester,
  ) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
    )..canRequestInstallValue = false;
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);
    expect(find.text('需要允许安装未知应用'), findsOneWidget);
    expect(find.text('前往设置'), findsOneWidget);
    expect(gateway.requestInstallCalls, 0, reason: '没授权就不拉起安装器');
    expect(gateway.openInstallSettingsCalls, 0, reason: '不自动跳转设置页');
    expect(tester.takeException(), isNull);
  });

  testWidgets('授权查询失败：按未获授权处理，引导去设置而不是假装能装', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
    )..canRequestInstallError = StateError('通道不在');
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();

    expect(find.text('需要允许安装未知应用'), findsOneWidget);
    expect(gateway.requestInstallCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('按下「前往设置」才跳设置页', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
    )..canRequestInstallValue = false;
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();
    expect(gateway.openInstallSettingsCalls, 0);

    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();

    expect(gateway.openInstallSettingsCalls, 1);
    expect(find.text('需要允许安装未知应用'), findsOneWidget, reason: '按下后仍停在原态');
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置页打开开关后返回：继续完成安装', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
    )..canRequestInstallValue = false;
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();
    expect(gateway.requestInstallCalls, 0);

    gateway.canRequestInstallValue = true;
    await _resume(tester);

    expect(gateway.requestInstallCalls, 1, reason: '授权放行后继续完成安装');
    expect(gateway.lastRequestInstallPath, gateway.downloadedFilePath);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('需要允许安装未知应用'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从设置页返回但没打开开关：提示条仍在，可再次按下前去设置', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
    )..canRequestInstallValue = false;
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();

    await _resume(tester);

    expect(find.text('需要允许安装未知应用'), findsOneWidget);
    expect(gateway.requestInstallCalls, 0);
    await tester.tap(find.byKey(const Key('update_prompt_action')));
    await tester.pumpAndSettle();
    expect(gateway.openInstallSettingsCalls, 1, reason: '可再次按下前去设置');
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于页那一行与提示条读同一份结论：启动那一查之后开页不再发请求', (tester) async {
    final gateway = FakeUpdateGateway(
      manifestScript: [
        updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
      ],
    );
    await _pumpApp(tester, gateway: gateway, localBuildNumber: 1);
    expect(find.byKey(const Key('update_prompt_bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home_more_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('about_menu_item')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('关于')),
      findsOneWidget,
    );
    expect(
      find.text('最新版本 0.1.1'),
      findsOneWidget,
      reason: '关于页版本行读的是同一份结论',
    );
    expect(gateway.fetchCalls, 1, reason: '同一次更新只发一次请求');
    expect(tester.takeException(), isNull);
  });
}

/// 模拟从系统设置页返回应用：先退后台再回前台，触发根壳的生命周期回调。
Future<void> _resume(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

/// 切一个 Tab 并让切换落定：统计/计划页有自己的装载动画，`pumpAndSettle`
/// 会一直等下去，这里只推进两帧拿到切换后的树。
Future<void> _switchTab(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// 起一次 App（真实根壳），把网关与本机构建号换成确定的替身。
Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeUpdateGateway gateway,
  required int localBuildNumber,
}) async {
  useNamedViewport(tester, ViewportTier.compact);
  await tester.pumpWidget(
    ProviderScope(
      // 每次起 App 都是一个全新的容器：重建根壳 = 下一次启动，提示条的
      // 「只关本次」也就不会跨这一次重建留下来。
      key: UniqueKey(),
      overrides: [
        updateGatewayProvider.overrideWithValue(gateway),
        localBuildNumberProvider.overrideWith((ref) async => localBuildNumber),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
}
