import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/device_description.dart';
import 'package:dance_learning_app/cast/dlna_cast_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/cast_fake_receiver.dart';
import '../helpers/fake_cast_session.dart';

/// 投屏会话接缝：真实实现（DLNA/UPnP 的 SOAP）打本机假接收端，钉的是
/// **外部可观察的行为**——接收端收到的指令序列与三类失败的清晰归属；
/// 替身侧钉「脚本化替换」这一条。
void main() {
  group('真实 DLNA 会话（打本机假接收端）', () {
    late FakeDlnaReceiver receiver;
    const factory = DlnaCastSessionFactory();

    tearDown(() async {
      await receiver.stop();
    });

    Future<CastReceiver> receiverOf(
      FakeDlnaReceiver fake, {
      String friendlyName = 'CI 假接收端',
    }) async => CastReceiver(
      id: 'fake-susume-receiver',
      friendlyName: friendlyName,
      descriptionUrl: fake.descriptionUrl,
      controlUrls: CastControlUrls(
        avTransport: fake.avTransportControlUrl,
        renderingControl: fake.renderingControlUrl,
      ),
    );

    test('连上后断开：接收端收到 Stop，断开不再可用', () async {
      receiver = await FakeDlnaReceiver.start();
      final session = await factory.connect(await receiverOf(receiver));

      await session.disconnect();
      await session.disconnect();

      expect(receiver.receivedActions, ['GetTransportInfo', 'Stop']);
      expect(receiver.transportState, 'STOPPED');
      await expectLater(session.play(), throwsA(isA<CastSessionDropped>()));
    });

    test('没有 AVTransport 控制端点：连不上（不是投屏对象）', () async {
      final receiverWithoutAvTransport = CastReceiver(
        id: 'no-avt',
        friendlyName: '只看得见的设备',
        descriptionUrl: Uri.parse('http://10.0.0.9:80/d.xml'),
        controlUrls: const CastControlUrls(),
      );

      await expectLater(
        factory.connect(receiverWithoutAvTransport),
        throwsA(isA<CastReceiverUnreachable>()),
      );
    });

    test('控制端点连不通：连不上', () async {
      final fake = await FakeDlnaReceiver.start();
      final target = await receiverOf(fake);
      await fake.stop();

      await expectLater(
        factory.connect(target),
        throwsA(isA<CastReceiverUnreachable>()),
      );
    });

    test('拒播：接收端回 UPnP 错误码 701，抛 CastActionRefused', () async {
      receiver = await FakeDlnaReceiver.start(refusePlay: true);
      final session = await factory.connect(await receiverOf(receiver));

      await expectLater(
        session.play(),
        throwsA(
          isA<CastActionRefused>().having(
            (failure) => failure.upnpErrorCode,
            'upnpErrorCode',
            701,
          ),
        ),
      );
      await session.disconnect();
    });

    test('中途掉线：会话建立后连接断了，抛 CastSessionDropped', () async {
      final fake = await FakeDlnaReceiver.start();
      final session = await factory.connect(await receiverOf(fake));
      await fake.stop();

      await expectLater(session.play(), throwsA(isA<CastSessionDropped>()));
    });

    test('音量与位置：设下去、读回来都对得起', () async {
      receiver = await FakeDlnaReceiver.start();
      final session = await factory.connect(await receiverOf(receiver));

      await session.push(
        Uri.parse('http://192.168.1.7:8080/cast/token/投屏副本.mp4'),
      );
      await session.play();
      await session.seek(const Duration(seconds: 12));
      await session.setVolume(0.4);

      expect(receiver.volume, 40);
      expect(await session.volume(), closeTo(0.4, 0.0001));
      expect(await session.position(), const Duration(seconds: 12));
      expect(await session.playbackState(), CastPlaybackState.playing);

      await session.disconnect();
    });

    test('推片把地址与 DIDL 元数据一起交过去', () async {
      receiver = await FakeDlnaReceiver.start();
      final session = await factory.connect(await receiverOf(receiver));
      final source = Uri.parse('http://192.168.1.7:8080/cast/token/投屏副本.mp4');

      await session.push(source);

      expect(receiver.currentUri, source.toString());
      expect(receiver.currentUriMetadata, contains('object.item.videoItem'));
      expect(
        receiver.currentUriMetadata,
        contains(
          'http://192.168.1.7:8080/cast/token/%E6%8A%95%E5%B1%8F%E5%89%AF%E6%9C%AC.mp4',
        ),
        reason: '元数据里的 res 就是递出地址本身',
      );
      await session.disconnect();
    });

    test('支持的动作：设备自述几个就是几个', () async {
      receiver = await FakeDlnaReceiver.start(
        supportedActions: const {'Play', 'Stop'},
      );
      final session = await factory.connect(await receiverOf(receiver));

      final actions = await session.supportedTransportActions();

      expect(actions.actions, {
        CastTransportAction.play,
        CastTransportAction.stop,
      });
      expect(
        CastRemoteControls.of(
          actions: actions,
          hasVolumeControl: true,
        ).showsSeek,
        isFalse,
        reason: '设备不支持跳转，那一项就不该显示',
      );
      await session.disconnect();
    });

    test('探测支持的动作失败：空集，静默降级不抛', () async {
      receiver = await FakeDlnaReceiver.start(
        unimplementedActions: const {'GetCurrentTransportActions'},
      );
      final session = await factory.connect(await receiverOf(receiver));

      expect((await session.supportedTransportActions()).isEmpty, isTrue);
      await session.disconnect();
    });
  });

  group('脚本化替身（注入点形状）', () {
    final receiver = CastReceiver(
      id: 'uuid:a',
      friendlyName: '电视',
      descriptionUrl: Uri.parse('http://10.0.0.9:49152/d.xml'),
      controlUrls: CastControlUrls(
        avTransport: Uri.parse('http://10.0.0.9:49152/avt'),
      ),
    );

    test('逐次给出会话、记录遥控与参数', () async {
      final factory = FakeCastSessionFactory();
      final session = await factory.connect(receiver) as FakeCastSession;

      await session.push(Uri.parse('http://10.0.0.2:8080/cast/t/a.mp4'));
      await session.play();
      await session.pause();
      await session.seek(const Duration(seconds: 30));
      await session.setVolume(0.75);
      await session.disconnect();

      expect(factory.connectCalls, 1);
      expect(factory.lastReceiver, receiver);
      expect(session.pushedUri, Uri.parse('http://10.0.0.2:8080/cast/t/a.mp4'));
      expect(session.calls, ['push', 'play', 'pause', 'seek', 'setVolume']);
      expect(session.seeks, [const Duration(seconds: 30)]);
      expect(session.volumes, [0.75]);
      expect(session.disconnectCalls, 1);
    });

    test('注入失败：连不上与拒播各按脚本抛出', () async {
      final factory = FakeCastSessionFactory()
        ..connectError = const CastReceiverUnreachable('连不上');
      await expectLater(
        factory.connect(receiver),
        throwsA(isA<CastReceiverUnreachable>()),
      );

      final refusing = FakeCastSessionFactory()
        ..configure = (session) =>
            session.pushError = const CastActionRefused('拒播');
      final session = await refusing.connect(receiver);
      await expectLater(
        session.push(Uri.parse('http://10.0.0.2/cast/t/a.mp4')),
        throwsA(isA<CastActionRefused>()),
      );
    });
  });
}
