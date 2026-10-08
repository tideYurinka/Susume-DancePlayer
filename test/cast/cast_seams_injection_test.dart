import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart';
import 'package:dance_learning_app/cast/cast_render_executor_ffmpeg.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/dlna_cast_session.dart';
import 'package:dance_learning_app/cast/lan_cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/ssdp_receiver_discovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_render_executor.dart';
import '../helpers/fake_cast_session.dart';

/// 四条接缝的注入形状（沿仓内既有的「接口 + 真实实现 + Provider + 脚本化
/// 替身」范式）：缺省装配是真实实现，测试能逐条 override 成替身——投屏准备
/// 面板与投屏态因此可以完全不碰真网络、不跑真 ffmpeg。
void main() {
  test('缺省装配：发现走 SSDP、会话走 DLNA、递出走本机 HTTP 服务、渲染走已链接的 ffmpeg', () {
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
      // 递出通道给的是**取一份新通道的工厂**（一次性通道，见接缝注释）。
      container.read(castDeliveryChannelFactoryProvider)(),
      isA<LanCastDeliveryChannel>(),
    );
    expect(
      container.read(castRenderExecutorProvider),
      isA<FfmpegCastRenderExecutor>(),
    );
  });

  test('四条接缝都能注入脚本化替身', () async {
    final discovery = FakeCastReceiverDiscovery();
    final factory = FakeCastSessionFactory();
    final delivery = FakeCastDeliveryChannelFactory();
    final executor = FakeCastRenderExecutor();
    final container = ProviderContainer(
      overrides: [
        castReceiverDiscoveryProvider.overrideWithValue(discovery),
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelFactoryProvider.overrideWithValue(delivery.call),
        castRenderExecutorProvider.overrideWithValue(executor),
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
    // 工厂每次给一份**新的**通道：一次性通道不能被两次起投共用。
    expect(
      identical(
        container.read(castDeliveryChannelFactoryProvider)(),
        container.read(castDeliveryChannelFactoryProvider)(),
      ),
      isFalse,
    );
    expect(container.read(castRenderExecutorProvider), same(executor));
    expect(executor.ran, isFalse);
  });
}
