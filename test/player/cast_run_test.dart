import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/player/cast_run.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_session.dart';

/// 投屏运行域直测：起投（起通道 → 连 → 推 → 播）、断开（停服 + 断连 + 回
/// 编辑态）、复位触发断开、遥控镜像与失败收口。经 #23 那三条接缝的脚本化
/// 替身，不碰真网络、不启动 widget。
void main() {
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannel delivery;
  late ProviderContainer container;

  CastReceiver receiverNamed(String name) => CastReceiver(
    id: 'udn-$name',
    friendlyName: name,
    descriptionUrl: Uri.parse('http://192.168.1.9:8080/desc.xml'),
    controlUrls: CastControlUrls(
      avTransport: Uri.parse('http://192.168.1.9:8080/avt'),
      renderingControl: Uri.parse('http://192.168.1.9:8080/rcs'),
    ),
  );

  final file = File('/videos/这支舞.mp4');

  CastRunModel run() => container.read(castRunProvider.notifier);
  CastRunState state() => container.read(castRunProvider);
  PlayerSession session() => container.read(playerSessionProvider);
  int interruptedNotices() =>
      container.read(noticeTriggerProvider(NoticeId.castInterrupted));

  setUp(() {
    factory = FakeCastSessionFactory();
    delivery = FakeCastDeliveryChannel();
    container = ProviderContainer(
      overrides: [
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelProvider.overrideWithValue(delivery),
      ],
    );
    addTearDown(container.dispose);
  });

  group('起投', () {
    test('起投顺序：起递出通道 → 连会话 → 推片 → 起播；状态 = 正投那台', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();

      expect(delivery.served, [file], reason: '推的是这支舞的原片');
      expect(factory.connectCalls, 1);
      expect(factory.lastReceiver?.friendlyName, '客厅电视');
      final cast = factory.sessions.single;
      expect(cast.calls, ['push', 'play']);
      expect(cast.pushedUri, delivery.url);
      expect(state().receiver?.friendlyName, '客厅电视');
      expect(state().active, isTrue);
    });

    test('一次只投一台：再起投先收掉上一条（停服 + 断连）', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final first = factory.sessions.single;
      await run().start(receiver: receiverNamed('卧室盒子'), file: file);
      await pumpEventQueue();

      expect(first.disconnected, isTrue);
      expect(delivery.closeCalls, greaterThanOrEqualTo(1));
      expect(state().receiver?.friendlyName, '卧室盒子');
    });

    test('连不上：异常上抛、状态回未投屏、通道已停服、模式值一位不动', () async {
      factory.connectError = const CastReceiverUnreachable('端点连不通');

      await expectLater(
        run().start(receiver: receiverNamed('客厅电视'), file: file),
        throwsA(isA<CastReceiverUnreachable>()),
      );
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(delivery.closed, isTrue, reason: '起投失败也要把已起的通道收干净');
      expect(session().mode, PlayerSessionMode.watching);
    });

    test('推片被拒：零残留（断连 + 停服 + 状态回未投屏）', () async {
      factory.configure = (session) =>
          session.pushError = const CastActionRefused('拒播');

      await expectLater(
        run().start(receiver: receiverNamed('客厅电视'), file: file),
        throwsA(isA<CastActionRefused>()),
      );
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(factory.sessions.single.disconnected, isTrue);
      expect(delivery.closed, isTrue);
    });

    test('换接收端失败：不留「在投屏态却没有会话」的悬挂面（回编辑态）', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      factory.connectError = const CastReceiverUnreachable('端点连不通');

      await expectLater(
        run().start(receiver: receiverNamed('卧室盒子'), file: file),
        throwsA(isA<CastReceiverUnreachable>()),
      );
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
    });
  });

  group('断开（唯一出口）', () {
    test('断开：停服 + 断连 + 回编辑态', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().disconnect();
      await pumpEventQueue();

      expect(factory.sessions.single.disconnected, isTrue);
      expect(delivery.closed, isTrue, reason: '递出通道随断开立即停服');
      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
    });

    test('未投屏时断开是空操作：模式值一位不动、不报错', () async {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      await run().disconnect();
      await pumpEventQueue();

      expect(session().mode, PlayerSessionMode.editing);
      expect(delivery.closeCalls, 0);
    });

    test('重复断开：幂等（第二次不再碰通道与会话）', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await run().disconnect();
      final closes = delivery.closeCalls;
      await run().disconnect();
      expect(delivery.closeCalls, closes);
    });
  });

  group('断开触发点收在既有复位一处', () {
    test('复位（换视频 / 离开播放页）离开投屏态即断开并停服', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      // 既有复位一处：换视频与离开播放页都经这一次调用。
      container.read(playerSessionProvider.notifier).reset();
      await pumpEventQueue();

      expect(factory.sessions.single.disconnected, isTrue);
      expect(delivery.closed, isTrue);
      expect(state().active, isFalse);
    });

    test('退出投屏态（exitCast）同样触发断开：边沿只有「离开投屏态」一条', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castWatching,
      );

      container.read(playerSessionProvider.notifier).exitCast();
      await pumpEventQueue();

      expect(factory.sessions.single.disconnected, isTrue);
      expect(delivery.closed, isTrue);
    });
  });

  group('遥控镜像（投屏态内本机动作作用于接收端）', () {
    test('未投屏：播放 / 暂停 / 跳转都是空操作', () async {
      await run().play();
      await run().pause();
      await run().seek(const Duration(seconds: 5));
      expect(factory.sessions, isEmpty);
      expect(interruptedNotices(), 0);
    });

    test('投屏态内：play / pause / seek 逐条落到接收端', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;

      await run().pause();
      await run().seek(const Duration(seconds: 12));
      await run().play();

      expect(cast.calls, ['push', 'play', 'pause', 'seek', 'play']);
      expect(cast.seeks, [const Duration(seconds: 12)]);
    });

    test('遥控失败（掉线）：断开 + 回编辑态 + 短暂提示', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      cast.actionError = const CastSessionDropped('连接被掐');
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().pause();
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(cast.disconnected, isTrue);
      expect(delivery.closed, isTrue);
      expect(session().mode, PlayerSessionMode.editing);
      expect(interruptedNotices(), 1);
    });

    test('失败只收口一次：并发失败不重复弹提示', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      factory.sessions.single.actionError = const CastSessionDropped('掉线');
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().pause();
      await run().play();
      await pumpEventQueue();

      expect(interruptedNotices(), 1);
    });
  });
}
