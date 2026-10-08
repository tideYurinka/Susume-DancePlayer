import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/device_description.dart';
import 'package:dance_learning_app/cast/ssdp.dart';
import 'package:dance_learning_app/cast/ssdp_receiver_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/cast_fake_receiver.dart';
import '../helpers/fake_cast_receiver_discovery.dart';

/// 接收端发现接缝：真实实现（SSDP + 设备描述）打**本机假接收端**跑环回，
/// 不依赖真电视、也不依赖组播可达；替身侧只钉「脚本化替换」这一条。
void main() {
  group('真实 SSDP 发现（打本机假接收端）', () {
    late FakeDlnaReceiver receiver;

    tearDown(() async {
      await receiver.stop();
    });

    test('发现 → 读出友好名、UDN 身份与两条控制端点', () async {
      receiver = await FakeDlnaReceiver.start(friendlyName: '客厅的电视');
      final discovery = SsdpCastReceiverDiscovery(
        target: receiver.address,
        port: receiver.ssdpPort,
      );

      final receivers = await discovery.discover(
        timeout: const Duration(milliseconds: 300),
      );

      expect(receivers, hasLength(1));
      final found = receivers.single;
      expect(found.friendlyName, '客厅的电视');
      expect(found.id, 'fake-susume-receiver', reason: '身份取设备描述的 UDN');
      expect(found.descriptionUrl, receiver.descriptionUrl);
      expect(found.controlUrls.avTransport, receiver.avTransportControlUrl);
      expect(found.controlUrls.renderingControl, receiver.renderingControlUrl);
      expect(found.canReceiveCast, isTrue);
    });

    test('同一台设备答多次：去重成一台', () async {
      receiver = await FakeDlnaReceiver.start(ssdpRepliesPerSearch: 3);
      final discovery = SsdpCastReceiverDiscovery(
        target: receiver.address,
        port: receiver.ssdpPort,
      );

      final receivers = await discovery.discover(
        timeout: const Duration(milliseconds: 300),
      );

      expect(receivers, hasLength(1));
    });

    test('一台都没有：空表，不抛（搜不到的是一条用户看得见的状态）', () async {
      receiver = await FakeDlnaReceiver.start();
      await receiver.stop();
      final discovery = SsdpCastReceiverDiscovery(
        target: receiver.address,
        port: receiver.ssdpPort,
      );

      expect(
        await discovery.discover(timeout: const Duration(milliseconds: 200)),
        isEmpty,
      );
    });

    test('设备描述拉不回来：跳过这台设备，不抛', () async {
      receiver = await FakeDlnaReceiver.start();
      final discovery = SsdpCastReceiverDiscovery(
        target: receiver.address,
        port: receiver.ssdpPort,
        loadDescription: (url) async => null,
      );

      expect(
        await discovery.discover(timeout: const Duration(milliseconds: 300)),
        isEmpty,
      );
    });

    test('描述里没有 AVTransport 控制端点：不是投屏对象，跳过', () async {
      receiver = await FakeDlnaReceiver.start();
      final discovery = SsdpCastReceiverDiscovery(
        target: receiver.address,
        port: receiver.ssdpPort,
        loadDescription: (url) async => const CastDeviceDescription(
          friendlyName: '只看得见的设备',
          udn: 'only-visible',
          controlUrls: CastControlUrls(),
        ),
      );

      expect(
        await discovery.discover(timeout: const Duration(milliseconds: 300)),
        isEmpty,
      );
    });
  });

  group('缺省目的地', () {
    test('真机走 SSDP 组播地址与 1900（不是环回）', () {
      final discovery = SsdpCastReceiverDiscovery();

      expect(discovery.target.address, kSsdpMulticastAddress);
      expect(discovery.port, kSsdpMulticastPort);
    });
  });

  group('脚本化替身（注入点形状）', () {
    test('逐次给出名单、记录调用次数与等待时长，用尽后是空表', () async {
      final receiver = CastReceiver(
        id: 'uuid:a',
        friendlyName: '电视',
        descriptionUrl: CastReceiverStub.descriptionUrl,
        controlUrls: CastControlUrls(),
      );
      final discovery = FakeCastReceiverDiscovery(
        script: [
          [receiver],
        ],
      );

      expect(
        await discovery.discover(timeout: const Duration(milliseconds: 50)),
        [receiver],
      );
      expect(await discovery.discover(timeout: kCastDiscoveryTimeout), isEmpty);
      expect(discovery.discoverCalls, 2);
      expect(discovery.lastTimeout, kCastDiscoveryTimeout);
    });

    test('注入失败：抛出替身给的那个错', () async {
      final discovery = FakeCastReceiverDiscovery()
        ..error = const SocketExceptionStub();

      await expectLater(
        discovery.discover(timeout: Duration.zero),
        throwsA(isA<SocketExceptionStub>()),
      );
    });
  });
}

/// 一个只用来当"替身注入的失败"的异常（测试里不需要真的网络异常）。
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

/// 替身用例里的接收端描述地址（`Uri` 不是常量构造，故放在这里一次）。
abstract final class CastReceiverStub {
  static final descriptionUrl = Uri.parse('http://10.0.0.9:49152/d.xml');
}
