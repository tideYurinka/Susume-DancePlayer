import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_screen_awake.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/player/cast_run.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_screen_awake.dart';
import '../helpers/fake_cast_session.dart';

/// 投屏期屏幕唤醒（票 #39，规格 #21）的**进出**：
///
/// - 进投屏态即持有唤醒、离开即释放——断开 / 换视频 / 离开播放页都经既有复位
///   一处（`_teardown`），分离的释放点一个都不新写；
/// - 一次投屏**一次持有**：起投失败、重复起投、断开后再投都不留累积的持有；
/// - 起投的失败（连不上 / 推片被拒）不留半持状态。
///
/// 唤醒接缝经替身注入（记录拿 / 放次数），不碰真平台通道；真机上「屏幕到底
/// 熄不熄」归真机验收（`lib/cast/docs/real-device-acceptance.md` 路径 O）。
/// 画面开关打开时**不重复持有**那条在 widget 层
/// （`test/player/cast_picture_test.dart`：预览画面件是唯一在场者那一路）。
void main() {
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannelFactory delivery;
  late FakeCastScreenAwake awake;
  late ProviderContainer container;

  CastReceiver receiverNamed(String name) => CastReceiver(
    id: 'udn-$name',
    friendlyName: name,
    descriptionUrl: Uri.parse('http://192.168.1.9:8080/desc.xml'),
    controlUrls: CastControlUrls(
      avTransport: Uri.parse('http://192.168.1.9:8080/avt'),
    ),
  );

  final file = File('/videos/这支舞.mp4');

  CastRunModel run() => container.read(castRunProvider.notifier);
  PlayerSession session() => container.read(playerSessionProvider);

  Future<void> startCast() =>
      run().start(receiver: receiverNamed('客厅电视'), file: file);

  setUp(() {
    factory = FakeCastSessionFactory();
    delivery = FakeCastDeliveryChannelFactory();
    awake = FakeCastScreenAwake();
    container = ProviderContainer(
      overrides: [
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelFactoryProvider.overrideWithValue(delivery.call),
        castScreenAwakeProvider.overrideWithValue(awake),
      ],
    );
    addTearDown(container.dispose);
  });

  group('进投屏态即持有', () {
    test('起投成功那一刻持有一次唤醒', () async {
      await startCast();
      await pumpEventQueue();

      expect(awake.calls, ['hold'], reason: '进投屏态即持有唤醒');
      expect(awake.held, 1);
    });

    test('起投失败（连不上）：会话没建立就不曾持有', () async {
      factory.connectError = const CastReceiverUnreachable('端点连不通');

      await expectLater(startCast(), throwsA(isA<CastReceiverUnreachable>()));
      await pumpEventQueue();

      expect(awake.holdCalls, 0, reason: '没进投屏态就不该持有');
      expect(awake.releaseCalls, 0, reason: '也没得放（不留一次多余的空放）');
    });

    test('起投失败（推片被拒）：零残留——拿了的那一次收干净', () async {
      factory.configure = (session) =>
          session.pushError = const CastActionRefused('拒播');

      await expectLater(startCast(), throwsA(isA<CastActionRefused>()));
      await pumpEventQueue();

      expect(awake.calls, ['hold', 'release'], reason: '进出台阶配平，不留半持');
      expect(awake.held, 0);
    });

    test('推片在飞时已经持有着：起播前的等待期屏幕不熄', () async {
      final gate = Completer<void>();
      factory.configure = (session) => session.pushGate = gate;

      final starting = startCast();
      await pumpEventQueue();

      expect(awake.held, 1, reason: '进投屏态那一刻就持有，不等起播');

      gate.complete();
      await starting;
      expect(awake.held, 1);
    });
  });

  group('离开即释放（与投屏会话的既有复位同一处）', () {
    test('断开投屏：放掉唤醒', () async {
      await startCast();
      await run().disconnect();
      await pumpEventQueue();

      expect(awake.calls, ['hold', 'release']);
      expect(awake.held, 0);
    });

    test('既有复位一处（换视频 / 离开播放页）：放掉唤醒', () async {
      await startCast();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castControl);

      // 换视频与离开播放页都经这一次调用。
      container.read(playerSessionProvider.notifier).reset();
      await pumpEventQueue();

      expect(awake.calls, ['hold', 'release']);
      expect(awake.held, 0);
    });

    test('离开投屏态（exitCast）：放掉唤醒', () async {
      await startCast();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castWatching);

      container.read(playerSessionProvider.notifier).exitCast();
      await pumpEventQueue();

      expect(awake.calls, ['hold', 'release']);
      expect(awake.held, 0);
    });

    test('会话建立之后的失败（电视端停止）：收口时一并放掉', () async {
      await startCast();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castControl);

      await run().handlePlaybackState(CastPlaybackState.stopped);
      await pumpEventQueue();

      expect(awake.calls, ['hold', 'release'], reason: '回编辑态那一刻不再需要常亮');
      expect(awake.held, 0);
      expect(session().mode, PlayerSessionMode.editing);
    });

    test('未投屏时断开是空操作：不产生一次多余的释放', () async {
      await run().disconnect();
      await pumpEventQueue();

      expect(awake.releaseCalls, 0, reason: '没持有时不放——放了会关掉别人的唤醒');
    });

    test('重复断开：只放一次', () async {
      await startCast();
      await run().disconnect();
      await run().disconnect();
      await pumpEventQueue();

      expect(awake.releaseCalls, 1);
      expect(awake.held, 0);
    });
  });

  group('一次投屏一次持有（不累积、不漏放）', () {
    test('投 → 断开 → 再投 → 再断开：进出各两次，配平', () async {
      await startCast();
      await run().disconnect();
      await startCast();
      await run().disconnect();
      await pumpEventQueue();

      expect(awake.calls, ['hold', 'release', 'hold', 'release']);
      expect(awake.held, 0);
    });

    test('换接收端（再起投先收掉上一条）：不叠加第二份持有', () async {
      await startCast();
      await startCast();

      expect(awake.calls, ['hold', 'release', 'hold'], reason: '先收上一条再持新的');
      expect(awake.held, 1, reason: '换一台接收端不该同时持两份');
    });
  });
}
