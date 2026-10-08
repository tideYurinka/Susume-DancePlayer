import 'dart:io';

import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/dlna_cast_session.dart';
import 'package:dance_learning_app/cast/lan_cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/ssdp_receiver_discovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../tool/cast_fake_receiver.dart';

/// **端到端基线**：三条真实接缝（SSDP 发现 / DLNA 会话 / 递出通道）接本机
/// **假接收端**，在 CI 里跑完「发现 → 推 → 播 → 暂停 → 跳转 → 音量 → 断开」，
/// 以及「会话结束即停服」。
///
/// 真机与真电视的行为（rygel、客厅电视）仍归真机验收——与分享面板那条口径
/// 一致；步骤见 `lib/cast/docs/real-device-acceptance.md`。
void main() {
  late Directory baseDirectory;
  late FakeDlnaReceiver receiver;
  late LanCastDeliveryChannel channel;
  late File video;
  final payload = List<int>.generate(4096, (i) => i % 251);

  setUp(() async {
    baseDirectory = await Directory.systemTemp.createTemp('cast_e2e');
    video = File(p.join(baseDirectory.path, '投屏副本.mp4'));
    await video.writeAsBytes(payload);
    receiver = await FakeDlnaReceiver.start(friendlyName: 'CI 假接收端');
    channel = LanCastDeliveryChannel(
      resolveAddress: () async => InternetAddress.loopbackIPv4,
    );
  });

  tearDown(() async {
    await channel.close();
    await receiver.stop();
    if (baseDirectory.existsSync()) {
      await baseDirectory.delete(recursive: true);
    }
  });

  Future<void> waitUntil(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('等到超时：假接收端没有拉片（${receiver.fetchError}）');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('发现 → 推 → 播 → 暂停 → 跳转 → 音量 → 断开：接收端看到的指令序列', () async {
    // 1. 发现：真发一条 M-SEARCH（环回单播），真拉设备描述。
    final discovery = SsdpCastReceiverDiscovery(
      target: receiver.address,
      port: receiver.ssdpPort,
    );
    final receivers = await discovery.discover(
      timeout: const Duration(milliseconds: 300),
    );
    expect(receivers, hasLength(1), reason: '假接收端要被发现到');
    final found = receivers.single;
    expect(found.friendlyName, 'CI 假接收端');
    expect(found.canReceiveCast, isTrue);

    // 2. 连上它。
    final session = await const DlnaCastSessionFactory().connect(found);

    // 3. 递出：真起一个局域网 HTTP 服务，路径一次性。
    final url = await channel.serve(video);
    expect(url.host, '127.0.0.1');

    // 4. 推 → 播 → 暂停 → 跳转 → 音量。
    await session.push(url);
    await session.play();
    await session.pause();
    await session.seek(const Duration(seconds: 12));
    await session.setVolume(0.4);

    // 5. 接收端上报的读数：支持的动作、状态、位置、音量。
    final actions = await session.supportedTransportActions();
    expect(actions.actions, {
      CastTransportAction.play,
      CastTransportAction.pause,
      CastTransportAction.stop,
      CastTransportAction.seek,
    });
    expect(await session.playbackState(), CastPlaybackState.paused);
    expect(await session.position(), const Duration(seconds: 12));
    expect(await session.volume(), closeTo(0.4, 0.0001));

    // 6. 接收端确实从递出通道取到了字节，而且是**带 Range 取的**（要能拖
    //    进度）。
    await waitUntil(() => receiver.fetchedStatusCode != null);
    expect(receiver.fetchedStatusCode, HttpStatus.partialContent);
    expect(receiver.fetchedBytes, 1024, reason: 'Range: bytes=0-1023');
    expect(receiver.currentUri, url.toString());
    expect(receiver.currentUriMetadata, contains('object.item.videoItem'));

    // 7. 断开：接收端收到 Stop，会话不再可用。
    await session.disconnect();
    expect(receiver.transportState, 'STOPPED');

    // 全链的指令序列就是下面这串（多一条少一条都是行为变了）。
    expect(receiver.receivedActions, [
      'GetTransportInfo',
      'SetAVTransportURI',
      'Play',
      'Pause',
      'Seek',
      'SetVolume',
      'GetCurrentTransportActions',
      'GetTransportInfo',
      'GetPositionInfo',
      'GetVolume',
      'Stop',
    ]);
  });

  test('会话结束即停服：断开并停服后接收端拉不到那份副本', () async {
    final receivers = await SsdpCastReceiverDiscovery(
      target: receiver.address,
      port: receiver.ssdpPort,
    ).discover(timeout: const Duration(milliseconds: 300));
    final session = await const DlnaCastSessionFactory().connect(
      receivers.single,
    );
    final url = await channel.serve(video);
    await session.push(url);

    // 先证明会话期内接收端真拉得到（带 Range）。
    await waitUntil(() => receiver.fetchedStatusCode != null);
    expect(receiver.fetchedStatusCode, HttpStatus.partialContent);

    // 断开 + 停服：同一条地址此后连不上。
    await session.disconnect();
    await channel.close();

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    Future<void> fetchOnce() async {
      final response = await (await client.getUrl(url)).close();
      await response.drain<void>();
    }

    await expectLater(
      fetchOnce(),
      throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
    );
  });
}
