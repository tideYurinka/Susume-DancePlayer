import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/dlna_cast_session.dart';
import 'package:dance_learning_app/cast/lan_cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/ssdp_receiver_discovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_session.dart';

/// 三条接缝的注入形状（沿仓内既有的「接口 + 真实实现 + Provider + 脚本化
/// 替身」范式）：缺省装配是真实实现，测试能逐条 override 成替身——投屏准备
/// 面板与投屏态因此可以完全不碰真网络。
void main() {
  test('缺省装配：发现走 SSDP、会话走 DLNA、递出走本机 HTTP 服务', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(castReceiverDiscoveryProvider),
      isA<SsdpCastReceiverDiscovery>(),
    );
    expect(
      container.read(castSessionFactoryProvider),
      isA<DlnaCastSessionFactory>(),
    );
    expect(
      container.read(castDeliveryChannelProvider),
      isA<LanCastDeliveryChannel>(),
    );
  });

  test('三条接缝都能注入脚本化替身', () async {
    final discovery = FakeCastReceiverDiscovery();
    final factory = FakeCastSessionFactory();
    final delivery = FakeCastDeliveryChannel();
    final container = ProviderContainer(
      overrides: [
        castReceiverDiscoveryProvider.overrideWithValue(discovery),
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelProvider.overrideWithValue(delivery),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container
          .read(castReceiverDiscoveryProvider)
          .discover(timeout: const Duration(milliseconds: 1)),
      isEmpty,
    );
    expect(discovery.discoverCalls, 1);
    expect(factory.connectCalls, 0);
    expect(delivery.served, isEmpty);
  });
}
