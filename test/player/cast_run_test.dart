import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/cast_run.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_session.dart';
import '../helpers/fake_playback_engine.dart';

/// 投屏运行域直测：起投（起通道 → 连 → 推 → 播）、断开（停服 + 断连 + 回
/// 编辑态）、复位触发断开、遥控镜像与失败收口。经 #23 那三条接缝的脚本化
/// 替身，不碰真网络、不启动 widget。
///
/// 递出通道经**替身工厂**注入（与生产装配同款）：每次起投一份新的，且替身
/// 如实建模真通道的一次性（停服之后再要地址抛 `CastDeliveryClosed`）——
/// 「断开 → 重选 → 再投」这条路上复用一份已停的通道会当场露馅。
void main() {
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannelFactory delivery;
  late FakePlaybackEngine engine;
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
    delivery = FakeCastDeliveryChannelFactory();
    engine = FakePlaybackEngine();
    container = ProviderContainer(
      overrides: [
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelFactoryProvider.overrideWithValue(delivery.call),
        // 本机播放态来源（回前台续上时本机界面追的就是它）：替身注入，
        // 不碰真解码。
        playbackEngineProvider.overrideWithValue(engine),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(engine.dispose);
  });

  group('起投', () {
    test('起投顺序：起递出通道 → 连会话 → 推片 → 起播；状态 = 正投那台', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();

      expect(delivery.served, [file], reason: '推的是这支舞的原片');
      expect(factory.connectCalls, 1);
      expect(factory.lastReceiver?.friendlyName, '客厅电视');
      final cast = factory.sessions.single;
      expect(
        cast.calls,
        ['push', 'play', 'supportedTransportActions', 'volume'],
        reason: '起投探测同时问动作集与音量（问一次答一次）',
      );
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

  group('遥控项判据（接收端能力，票 #38）', () {
    test('起投时问一次动作集与音量：判据与基线进运行账', () async {
      factory.configure = (session) {
        session.reportedActions = const CastTransportActions({
          CastTransportAction.play,
          CastTransportAction.pause,
          CastTransportAction.seek,
        });
        session.reportedVolume = 0.4;
      };

      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();

      final controls = state().remoteControls;
      expect(controls.showsPlayPause, isTrue);
      expect(controls.showsSeek, isTrue);
      expect(
        controls.showsVolume,
        isTrue,
        reason: '端点在场且探测读到了上报值：音量遥控项显示',
      );
      expect(controls.shows(CastRemoteItem.progress), isTrue);
      expect(controls.shows(CastRemoteItem.playPause), isTrue);
      expect(controls.shows(CastRemoteItem.volume), isTrue);
      expect(
        state().reportedVolume,
        closeTo(0.4, 1e-9),
        reason: '同一次探测读到的值就是音量显示的基线',
      );
      expect(
        factory.sessions.single.calls,
        ['push', 'play', 'supportedTransportActions', 'volume'],
        reason: '问一次答一次：音量与动作集各问一遍，都只在起投探测里',
      );
    });

    test('设备描述里没有 RenderingControl 端点：音量项不显示，也不问音量', () async {
      final noVolume = CastReceiver(
        id: 'udn-无音量端点',
        friendlyName: '无音量端点',
        descriptionUrl: Uri.parse('http://192.168.1.9:8080/desc.xml'),
        controlUrls: CastControlUrls(
          avTransport: Uri.parse('http://192.168.1.9:8080/avt'),
        ),
      );

      await run().start(receiver: noVolume, file: file);
      await pumpEventQueue();

      expect(state().remoteControls.showsVolume, isFalse);
      expect(state().remoteControls.showsPlayPause, isTrue);
      expect(state().reportedVolume, isNull);
      expect(
        factory.sessions.single.calls,
        isNot(contains('volume')),
        reason: '没有端点就不问（省一次注定失败的往返）',
      );
    });

    test('有端点但设备不报音量：音量项不显示（不是显示 0）', () async {
      factory.configure = (session) => session.volumeError =
          const CastActionRefused('设备不报音量');

      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();

      expect(
        state().remoteControls.showsVolume,
        isFalse,
        reason: '「问不到音量」与「没有端点」收敛到同一个出口',
      );
      expect(state().reportedVolume, isNull);
      expect(state().remoteControls.showsPlayPause, isTrue, reason: '动作集那一路不受影响');
      expect(state().active, isTrue, reason: '探测失败不该把投屏整条收掉');
      expect(interruptedNotices(), 0);
    });

    test('探测失败（设备不答 / 掉线）：收敛到「哪一项都不显示」，会话照旧', () async {
      factory.configure = (session) =>
          session.actionsError = const CastActionRefused('设备不答');

      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();

      expect(state().remoteControls, const CastRemoteControls.none());
      expect(state().active, isTrue, reason: '探测失败不该把投屏整条收掉');
      expect(factory.sessions.single.disconnected, isFalse);
      expect(interruptedNotices(), 0);
    });

    test('不支持的遥控项：镜像不发出去（播放 / 暂停 / 跳转一条都不发）', () async {
      factory.configure = (session) =>
          session.reportedActions = const CastTransportActions.none();

      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();
      final cast = factory.sessions.single;
      final before = List.of(cast.calls);

      await run().play();
      await run().pause();
      await run().seek(const Duration(seconds: 12));

      expect(
        cast.calls,
        before,
        reason: '判据说不显示的那几项，遥控镜像一条都不发',
      );
    });

    test('音量：读的是起投探测读到的那条上报值、写 SetVolume', () async {
      factory.configure = (session) => session.reportedVolume = 0.4;

      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();
      final cast = factory.sessions.single;
      final afterProbe = List.of(cast.calls);

      expect(await run().reportedVolume(), closeTo(0.4, 1e-9));
      expect(
        cast.calls,
        afterProbe,
        reason: '读显示值不再向接收端问一遍（探测那一次就是唯一一次）',
      );

      await run().setVolume(0.7);
      expect(cast.volumes, [0.7]);

      // 断开之后：读为 null、写是空操作（不再碰已断的会话）。
      await run().disconnect();
      expect(await run().reportedVolume(), isNull);
      await run().setVolume(0.9);
      expect(cast.volumes, [0.7]);
    });

    test('有端点但起投探测问不到音量：读为 null、写是空操作（静默降级）', () async {
      factory.configure = (session) =>
          session.volumeError = const CastActionRefused('不报音量');

      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();

      expect(await run().reportedVolume(), isNull);
      expect(
        factory.sessions.single.volumes,
        isEmpty,
        reason: '判据说这一项不显示：写也不发出去',
      );
      expect(state().active, isTrue);
      expect(interruptedNotices(), 0);
    });
  });

  group('遥控项显示的唯一回答处（票 #44）', () {
    test('非投屏态：三枚恒显示（「非投屏恒显示」的短路写在判据里面一次）', () {
      final shown = container.read(castRemoteItemShownProvider);
      for (final item in CastRemoteItem.values) {
        expect(shown(item), isTrue, reason: '$item：非投屏态恒显示');
      }
    });

    test('投屏态：逐项照接收端能力判据，不另判一套', () async {
      factory.configure = (session) {
        session.reportedActions = const CastTransportActions({
          CastTransportAction.play,
          CastTransportAction.pause,
        });
        session.reportedVolume = 0.4;
      };
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await pumpEventQueue();
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castControl);

      final shown = container.read(castRemoteItemShownProvider);
      final controls = container.read(castRemoteControlsProvider);
      for (final item in CastRemoteItem.values) {
        expect(shown(item), controls.shows(item), reason: '$item');
      }
      expect(shown(CastRemoteItem.progress), isFalse, reason: '设备没自述 Seek');
      expect(shown(CastRemoteItem.playPause), isTrue);
      expect(shown(CastRemoteItem.volume), isTrue);
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

  group('断开后再投（递出通道是一次性的）', () {
    test('替身如实建模真通道的一次性：停服之后再要地址抛 CastDeliveryClosed', () async {
      final channel = FakeCastDeliveryChannel();
      await channel.serve(file);
      await channel.close();

      await expectLater(channel.serve(file), throwsA(isA<CastDeliveryClosed>()));
    });

    test('投 → 断开 → 重选 → 再投：第二次起投取一份新通道，推片 + 起播重新发生', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      await run().disconnect();
      await pumpEventQueue();

      // 反向钉住「断开后不停服会漏」：断开的那一刻当次那一份必须已经停了
      // （停服漏了，出站服务与在飞连接会一直挂到进程结束）。
      expect(delivery.channels, hasLength(1), reason: '第一次起投一份通道');
      expect(delivery.closeCalls, 1, reason: '断开时把当次那一份停掉，不是留着');
      expect(delivery.channels.single.closed, isTrue);

      await run().start(receiver: receiverNamed('卧室盒子'), file: file);
      await pumpEventQueue();

      expect(delivery.channels, hasLength(2), reason: '第二次起投另取一份新通道');
      expect(
        identical(delivery.channels.first, delivery.channels.last),
        isFalse,
        reason: '复用上一份（已 close 成终态）会让第二次起投必然失败',
      );
      expect(delivery.channels.last.closed, isFalse, reason: '这一份正在用');
      expect(
        delivery.served,
        [file, file],
        reason: '第二次 serve 真的发生了（断开后再投不是一条死路）',
      );
      expect(
        delivery.channels.last.url,
        isNot(delivery.channels.first.url),
        reason: '一次性路径：第二份拿到的是新地址',
      );

      expect(factory.sessions, hasLength(2), reason: '会话重新建立');
      final second = factory.sessions.last;
      expect(
        second.calls,
        ['push', 'play', 'supportedTransportActions', 'volume'],
        reason: '会话被重新推片 + 起播，并重新问一次遥控项判据（含音量）',
      );
      expect(second.pushedUri, delivery.channels.last.url);
      expect(state().receiver?.friendlyName, '卧室盒子');
      expect(state().active, isTrue);
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

    test('离开投屏态（exitCast）同样触发断开投屏：边沿只有「离开投屏态」一条', () async {
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

      expect(cast.calls, [
        'push',
        'play',
        'supportedTransportActions',
        'volume',
        'pause',
        'seek',
        'play',
      ]);
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

  group('电视端停止（接收端自己停了）', () {
    test('停播上报：断开 + 停服 + 回编辑态 + 短暂提示', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().handlePlaybackState(CastPlaybackState.stopped);
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(cast.disconnected, isTrue);
      expect(delivery.closed, isTrue);
      expect(session().mode, PlayerSessionMode.editing);
      expect(interruptedNotices(), 1);
    });

    test('无媒体上报（电视那边把片子卸了）同一条收场', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().handlePlaybackState(CastPlaybackState.noMedia);
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
      expect(interruptedNotices(), 1);
    });

    test('还在播 / 暂停 / 过渡 / 问不到：不是停止，会话一位不动', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      for (final report in const [
        CastPlaybackState.playing,
        CastPlaybackState.paused,
        CastPlaybackState.transitioning,
        CastPlaybackState.unknown,
      ]) {
        await run().handlePlaybackState(report);
        expect(state().active, isTrue, reason: '$report');
        expect(cast.disconnected, isFalse, reason: '$report');
        expect(interruptedNotices(), 0, reason: '$report');
      }
    });

    test('未投屏：空操作、不弹提示', () async {
      await run().handlePlaybackState(CastPlaybackState.stopped);
      expect(delivery.closeCalls, 0);
      expect(interruptedNotices(), 0);
    });

    test('回前台问一次：接收端报停了就收口', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      cast.reportedState = CastPlaybackState.stopped;

      await run().refreshPlaybackState();
      await pumpEventQueue();

      expect(cast.calls, contains('playbackState'), reason: '问的就是接收端');
      expect(state().active, isFalse);
      expect(cast.disconnected, isTrue);
      expect(delivery.closed, isTrue);
      expect(session().mode, PlayerSessionMode.editing);
      expect(interruptedNotices(), 1);
    });

    test('回前台问一次：还在播就一位不动', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().refreshPlaybackState();
      await pumpEventQueue();

      expect(state().active, isTrue);
      expect(cast.disconnected, isFalse);
      expect(interruptedNotices(), 0);
    });

    test('回前台问不到（掉线）：会话建立之后的失败同样收口', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      cast.actionError = const CastSessionDropped('连接早就没了');

      await run().refreshPlaybackState();
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(delivery.closed, isTrue);
      expect(session().mode, PlayerSessionMode.editing);
      expect(interruptedNotices(), 1);
    });

    test('未投屏：回前台问一次是空操作（不碰接收端）', () async {
      await run().refreshPlaybackState();
      expect(factory.connectCalls, 0);
      expect(interruptedNotices(), 0);
    });
  });

  group('退后台 / 锁屏 = 投屏视为暂停；回前台按接收端上报续上', () {
    test('退后台：让接收端停下（会话不散、本机界面不预判）', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      final before = cast.calls.length;

      await run().pauseForBackground();
      await pumpEventQueue();

      expect(
        cast.calls.sublist(before),
        ['pause'],
        reason: '「视为暂停」落在会话层：让接收端停下（不引前台服务）',
      );
      expect(cast.disconnected, isFalse, reason: '退后台不断会话，只是把它按停');
      expect(state().active, isTrue);
      expect(
        session().mode,
        PlayerSessionMode.castControl,
        reason: '本机界面不在这里预判——续上只发生在回前台那一次',
      );
      expect(interruptedNotices(), 0);
    });

    test('未投屏：退后台是空操作', () async {
      await run().pauseForBackground();
      await pumpEventQueue();
      expect(factory.connectCalls, 0);
      expect(delivery.closeCalls, 0);
      expect(interruptedNotices(), 0);
    });

    test('退后台按不停（掉线）：走既有失败收口，不另开第二条路', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      cast.actionError = const CastSessionDropped('连接被掐');

      await run().pauseForBackground();
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(cast.disconnected, isTrue);
      expect(delivery.closed, isTrue);
      expect(session().mode, PlayerSessionMode.editing);
      expect(interruptedNotices(), 1);
    });

    test('退后台按停 → 回前台接收端报 paused：本机停在暂停态、不自动抢播', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      await engine.play();
      await run().pauseForBackground();
      final before = cast.calls.length;
      cast.reportedState = CastPlaybackState.paused;

      await run().refreshPlaybackState();
      await pumpEventQueue();

      expect(
        cast.calls.sublist(before),
        ['playbackState'],
        reason: '只问一次：接收端已暂停，不再发 play 去抢播',
      );
      expect(engine.isPlaying, isFalse, reason: '本机界面同步为暂停态');
      expect(engine.callLog, contains('pause'));
      expect(state().active, isTrue, reason: '会话照旧，电视停在暂停处等用户按');
      expect(interruptedNotices(), 0);
    });

    test('回前台接收端仍在播：本机界面同步为播放态（不重推接收端）', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      await engine.pause();
      final before = cast.calls.length;
      cast.reportedState = CastPlaybackState.playing;

      await run().refreshPlaybackState();
      await pumpEventQueue();

      expect(
        cast.calls.sublist(before),
        ['playbackState'],
        reason: '接收端已经在播：本机追上去就好，不向它重推动作',
      );
      expect(engine.isPlaying, isTrue);
      expect(state().active, isTrue);
      expect(interruptedNotices(), 0);
    });

    test('回前台问不到 / 过渡中：本机界面一位不动（不猜）', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      final before = cast.calls.length;
      final beforeEngine = engine.callLog.length;

      for (final report in const [
        CastPlaybackState.transitioning,
        CastPlaybackState.unknown,
      ]) {
        cast.reportedState = report;
        await run().refreshPlaybackState();
        expect(
          engine.callLog.sublist(beforeEngine),
          isEmpty,
          reason: '$report：不猜，本机界面一位不动',
        );
        expect(state().active, isTrue, reason: '$report');
        expect(interruptedNotices(), 0, reason: '$report');
      }
      expect(cast.calls.sublist(before), ['playbackState', 'playbackState']);
    });
  });

  group('递出通道立即停服（含异常路径）', () {
    test('停服不等接收端的收尾回应：断连还挂在飞时通道已经停了', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final gate = Completer<void>();
      factory.sessions.single.disconnectGate = gate;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      final closing = run().disconnect();
      await pumpEventQueue();

      expect(delivery.closed, isTrue, reason: '「立刻不可达」不依赖接收端回应');
      gate.complete();
      await closing;
      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
    });

    test('停服本身抛：不阻断断连，也不向上抛', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final cast = factory.sessions.single;
      delivery.closeError = StateError('端口已被人抢了');
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().disconnect();
      await pumpEventQueue();

      expect(cast.disconnected, isTrue);
      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
    });

    test('断连本身抛：停服已经先做了，收场照旧', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      factory.sessions.single.disconnectError = StateError('连接早就没了');
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );

      await run().disconnect();
      await pumpEventQueue();

      expect(delivery.closed, isTrue);
      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
    });

    test('递出通道起不来（serve 抛）：零残留、模式值一位不动', () async {
      delivery.serveError = StateError('没有可用的局域网地址');
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.editing,
      );

      await expectLater(
        run().start(receiver: receiverNamed('客厅电视'), file: file),
        throwsA(isA<StateError>()),
      );
      await pumpEventQueue();

      expect(state().active, isFalse);
      expect(factory.connectCalls, 0, reason: '通道没起起来就不连接收端');
      expect(session().mode, PlayerSessionMode.editing);
    });
  });

  group('换接收端失败（会话建立之后的失败也回编辑态）', () {
    test('换一台连不上：上一条收干净、模式回编辑态、零残留', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: file);
      final first = factory.sessions.single;
      container.read(playerSessionProvider.notifier).enter(
        PlayerSessionMode.castControl,
      );
      factory.connectError = const CastReceiverUnreachable('端点连不通');

      await expectLater(
        run().start(receiver: receiverNamed('卧室盒子'), file: file),
        throwsA(isA<CastReceiverUnreachable>()),
      );
      await pumpEventQueue();

      expect(first.disconnected, isTrue, reason: '上一条会话先收掉');
      expect(delivery.closed, isTrue, reason: '递出通道一并停服');
      expect(state().active, isFalse);
      expect(session().mode, PlayerSessionMode.editing);
      expect(session().pendingEntry, isNull);
      // 失败后再断一次是幂等空操作：不留悬挂的收尾。
      await run().disconnect();
      expect(delivery.closeCalls, greaterThanOrEqualTo(1));
    });
  });
}
