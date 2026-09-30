import 'dart:async';

import 'package:dance_learning_app/update/update_check.dart';
import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:dance_learning_app/update/update_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_update_gateway.dart';
import '../helpers/update_manifest_fixture.dart';

/// 更新状态机：一台机器两个读面（版本行与提示条），假网关直测每一态与两种失败
/// 的分野——**检查结论**说有没有新版，**下载阶段**说包在做什么，两者互相独立。
void main() {
  /// 起一台状态机：更新网关与本机构建号换成确定的替身。
  ({ProviderContainer container, UpdateController controller}) startMachine({
    required UpdateGateway gateway,
    int? localBuildNumber = 1,
  }) {
    final container = ProviderContainer(
      overrides: [
        updateGatewayProvider.overrideWithValue(gateway),
        localBuildNumberProvider.overrideWith((ref) async => localBuildNumber),
      ],
    );
    addTearDown(container.dispose);
    return (
      container: container,
      controller: container.read(updateProvider.notifier),
    );
  }

  UpdateState stateOf(ProviderContainer container) =>
      container.read(updateProvider);

  group('检查结论', () {
    test('还没查过：未检查，提示条不出现', () {
      final machine = startMachine(gateway: FakeUpdateGateway());

      final state = stateOf(machine.container);
      expect(state.conclusion, UpdateConclusion.notChecked);
      expect(state.versionRowStatus, VersionRowStatus.notChecked);
      expect(state.promptVisible, isFalse);
    });

    test('查过、没有新版：已是最新，提示条不出现', () async {
      final machine = startMachine(
        gateway: FakeUpdateGateway(
          manifestScript: [updateManifestFixture(buildNumber: 1)],
        ),
      );

      await machine.controller.check();

      final state = stateOf(machine.container);
      expect(state.conclusion, UpdateConclusion.upToDate);
      expect(state.versionRowStatus, VersionRowStatus.upToDate);
      expect(state.promptVisible, isFalse, reason: '没有新版不弹条');
    });

    test('查过、有新版：结论带着那份清单，两个读面都读到', () async {
      final machine = startMachine(
        gateway: FakeUpdateGateway(
          manifestScript: [
            updateManifestFixture(buildNumber: 2, versionName: '0.1.1'),
          ],
        ),
      );

      await machine.controller.check();

      final state = stateOf(machine.container);
      expect(state.conclusion, UpdateConclusion.available);
      expect(state.manifest?.versionName, '0.1.1');
      expect(state.versionRowStatus, VersionRowStatus.updateAvailable);
      expect(state.promptVisible, isTrue);
    });

    test('清单读不到：检查失败，而不是假装已是最新；提示条不出现', () async {
      final machine = startMachine(
        gateway: FakeUpdateGateway(manifestScript: [null]),
      );

      await machine.controller.check();

      final state = stateOf(machine.container);
      expect(state.conclusion, UpdateConclusion.checkFailed);
      expect(state.versionRowStatus, VersionRowStatus.checkFailed);
      expect(state.promptVisible, isFalse, reason: '静默失败与没有网络一样不出声');
    });

    test('网关抛错：同样收敛成检查失败', () async {
      final machine = startMachine(
        gateway: FakeUpdateGateway()..fetchError = StateError('网关违约'),
      );

      await machine.controller.check();

      expect(
        stateOf(machine.container).conclusion,
        UpdateConclusion.checkFailed,
      );
    });

    test('本机构建号读不出：无从比对，也算检查失败', () async {
      final machine = startMachine(
        gateway: FakeUpdateGateway(
          manifestScript: [updateManifestFixture(buildNumber: 2)],
        ),
        localBuildNumber: null,
      );

      await machine.controller.check();

      expect(
        stateOf(machine.container).conclusion,
        UpdateConclusion.checkFailed,
      );
    });

    test('检查在飞：读数是检查中；再按不重复发起', () async {
      final gate = Completer<void>();
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2)],
      )..gate = gate;
      final machine = startMachine(gateway: gateway);

      final inFlight = machine.controller.check();
      // 让第一次检查走到网关（还挂在闸门上），读数先落在「检查中」。
      await Future<void>.delayed(Duration.zero);
      expect(
        stateOf(machine.container).versionRowStatus,
        VersionRowStatus.checking,
      );

      await machine.controller.check();
      expect(gateway.fetchCalls, 1, reason: '在飞的检查不会因再按而重复发起');

      gate.complete();
      await inFlight;
      expect(
        stateOf(machine.container).versionRowStatus,
        VersionRowStatus.updateAvailable,
      );
    });
  });

  group('下载阶段与检查结论互相独立', () {
    test('下载中：阶段是下载中并带进度；再按不重复下一份包', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      )..progressScript = const [(250, 1000)];
      gateway.downloadGate = Completer<void>();
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();

      final inFlight = machine.controller.download();

      final state = stateOf(machine.container);
      expect(state.phase, UpdateDownloadPhase.downloading);
      expect(state.versionRowStatus, VersionRowStatus.downloading);
      expect(state.progress, 0.25);
      expect(state.promptVisible, isTrue);

      await machine.controller.download();
      expect(gateway.downloadCalls, 1, reason: '在飞的下载不会因再按而下一份');

      gateway.downloadGate!.complete();
      await inFlight;
    });

    test('下载失败：阶段是下载失败，但结论仍是有新版——与检查失败分得开', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      )..downloadError = const UpdateDownloadException();
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();

      await machine.controller.download();

      final state = stateOf(machine.container);
      expect(state.phase, UpdateDownloadPhase.failed);
      expect(
        state.conclusion,
        UpdateConclusion.available,
        reason: '有没有新版这件事没有变',
      );
      expect(state.versionRowStatus, VersionRowStatus.downloadFailed);
      expect(state.promptVisible, isTrue, reason: '包还在，提示条给「重试」');
    });

    test('未获授权：阶段是等放行，读数要用户去放行', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      )..canRequestInstallValue = false;
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();

      await machine.controller.download();

      final state = stateOf(machine.container);
      expect(state.phase, UpdateDownloadPhase.needsInstallPermission);
      expect(state.versionRowStatus, VersionRowStatus.needsInstallPermission);
      expect(state.promptVisible, isTrue);
      expect(gateway.requestInstallCalls, 0);
    });
  });

  group('✕ 只关提示条', () {
    test('按过 ✕ 之后再查一次：结论照常更新，提示条不自己冒回来', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [
          updateManifestFixture(buildNumber: 2, size: 1000),
          updateManifestFixture(buildNumber: 2, size: 1000),
        ],
      );
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();
      expect(stateOf(machine.container).promptVisible, isTrue);

      machine.controller.dismiss();
      expect(stateOf(machine.container).promptVisible, isFalse);

      await machine.controller.check();

      final state = stateOf(machine.container);
      expect(
        state.conclusion,
        UpdateConclusion.available,
        reason: '版本行照常读得到结论',
      );
      expect(state.versionRowStatus, VersionRowStatus.updateAvailable);
      expect(state.promptVisible, isFalse, reason: '✕ 的语义不被削弱');
    });

    test('下载中按 ✕：取消在飞的那份包，回到可下载', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      );
      gateway.downloadGate = Completer<void>();
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();
      final inFlight = machine.controller.download();

      machine.controller.dismiss();
      await inFlight;

      final state = stateOf(machine.container);
      expect(gateway.cancelCalls, 1);
      expect(state.phase, UpdateDownloadPhase.available);
      expect(state.promptVisible, isFalse);
    });
  });

  group('取消（版本行）', () {
    test('中断在飞的那份包、回到可下载；结论不变、提示条不因此关掉', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      );
      gateway.downloadGate = Completer<void>();
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();
      final inFlight = machine.controller.download();
      expect(
        stateOf(machine.container).versionRowStatus,
        VersionRowStatus.downloading,
      );

      machine.controller.cancelDownload();
      await inFlight;

      final state = stateOf(machine.container);
      expect(gateway.cancelCalls, 1, reason: '取消的是这一次在飞的下载');
      expect(state.phase, UpdateDownloadPhase.available);
      expect(
        state.conclusion,
        UpdateConclusion.available,
        reason: '有没有新版这件事没有变',
      );
      expect(state.versionRowStatus, VersionRowStatus.updateAvailable);
      expect(state.promptVisible, isTrue, reason: '提示条照常给「下载」');
      expect(state.dismissed, isFalse, reason: '取消不等于按过 ✕');
    });
  });

  group('交安装器', () {
    test('交安装器在飞：那段时间里不再发起第二次下载', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      );
      final installGate = Completer<void>();
      gateway.installGate = installGate;
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();

      final inFlight = machine.controller.download();
      await Future<void>.delayed(Duration.zero);
      expect(stateOf(machine.container).inFlight, UpdateInFlight.installing);

      await machine.controller.download();
      expect(gateway.downloadCalls, 1, reason: '交安装器期间不再下一份包');

      installGate.complete();
      await inFlight;
      expect(stateOf(machine.container).inFlight, UpdateInFlight.none);
    });

    test('从设置页放行回来：继续交安装器', () async {
      final gateway = FakeUpdateGateway(
        manifestScript: [updateManifestFixture(buildNumber: 2, size: 1000)],
      )..canRequestInstallValue = false;
      final machine = startMachine(gateway: gateway);
      await machine.controller.check();
      await machine.controller.download();
      expect(
        stateOf(machine.container).phase,
        UpdateDownloadPhase.needsInstallPermission,
      );

      gateway.canRequestInstallValue = true;
      await machine.controller.onAppResumed();

      expect(gateway.requestInstallCalls, 1);
      final state = stateOf(machine.container);
      expect(state.versionRowStatus, VersionRowStatus.updateAvailable);
      expect(state.promptVisible, isTrue);
    });
  });
}
