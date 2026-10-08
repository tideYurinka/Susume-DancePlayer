import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart';
import 'package:dance_learning_app/cast/cast_render_executor_ffmpeg.dart';
import 'package:dance_learning_app/cast/cast_screen_awake.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/dlna_cast_session.dart';
import 'package:dance_learning_app/cast/encoder_realtime_capability.dart';
import 'package:dance_learning_app/cast/lan_cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/platform_encoder_realtime_capability.dart';
import 'package:dance_learning_app/cast/ssdp_receiver_discovery.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_render_executor.dart';
import '../helpers/fake_cast_screen_awake.dart';
import '../helpers/fake_cast_session.dart';
import '../helpers/fake_encoder_realtime_capability.dart';

/// 接缝的注入形状（沿仓内既有的「接口 + 真实实现 + Provider + 脚本化替身」
/// 范式）：#23 那四条（发现 / 会话 / 递出 / 渲染）加 #39 那条**投屏期屏幕
/// 唤醒**，再加 #36 那条**编码器 1× 实时能力查询**——缺省装配是真实实现，
/// 测试能逐条 override 成替身——投屏准备面板、投屏态与投屏期的屏幕常亮因此
/// 可以完全不碰真网络、不跑真 ffmpeg、不打真平台唤醒通道、不真问编码器。
void main() {
  test('缺省装配：六条接缝各走真实现——发现 SSDP / 会话 DLNA / 递出本机 HTTP / 渲染 ffmpeg / 能力手写通道 / 唤醒 wakelock_plus', () {
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
    expect(
      container.read(castEncoderRealtimeCapabilityProvider),
      isA<PlatformEncoderRealtimeCapability>(),
    );
    expect(
      // 唤醒真实现 = 计数语义 + `wakelock_plus` 那一下（与播放内核画面件同一条
      // 平台能力）；读它不碰平台通道，只有 hold / release 才打。
      container.read(castScreenAwakeProvider),
      isA<RefCountedCastScreenAwake>(),
    );
  });

  test('六条接缝都能注入脚本化替身', () async {
    final discovery = FakeCastReceiverDiscovery();
    final factory = FakeCastSessionFactory();
    final delivery = FakeCastDeliveryChannelFactory();
    final executor = FakeCastRenderExecutor();
    final capability = FakeEncoderRealtimeCapability();
    final awake = FakeCastScreenAwake();
    final container = ProviderContainer(
      overrides: [
        castReceiverDiscoveryProvider.overrideWithValue(discovery),
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelFactoryProvider.overrideWithValue(delivery.call),
        castRenderExecutorProvider.overrideWithValue(executor),
        castEncoderRealtimeCapabilityProvider.overrideWithValue(capability),
        castScreenAwakeProvider.overrideWithValue(awake),
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
    expect(
      await container.read(castEncoderRealtimeCapabilityProvider).query(),
      CastEncoderRealtime.guaranteed,
    );
    expect(capability.queryCalls, 1);
    expect(container.read(castScreenAwakeProvider), same(awake));
    expect(awake.calls, isEmpty, reason: '没人投屏时不碰唤醒');
  });
}
