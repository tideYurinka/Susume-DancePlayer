/// 接收端发现的真实实现：**SSDP**（UPnP 设备发现）。
///
/// 一条 M-SEARCH 发到组播地址，收齐 `MX` 秒内的应答，逐台按 `LOCATION` 拉
/// 设备描述，读得出 AVTransport 控制端点的才算**接收端**。**不引第三方投屏
/// 包**；本域唯一的网络落点（除递出通道外）就在这里。
///
/// 目标地址可注入：真机走组播 `239.255.255.250:1900`，测试把 M-SEARCH 直接
/// 发给本机假接收端（环回单播）——同一条代码路径、同一份报文，只是目的地
/// 不同，CI 因此不必依赖组播可达。这一点是仓内假接收端能当端到端基线的
/// 前提。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cast_receiver.dart';
import 'device_description.dart';
import 'ssdp.dart';

/// 拉设备描述的超时：LAN 内一次 GET，2 秒足够；拉不回来就跳过这台设备
/// （**静默降级**——一台答得响却读不出描述的设备不该拖住整次发现）。
const Duration kCastDescriptionTimeout = Duration(seconds: 2);

/// 一次 GET 拉设备描述（[CastReceiver.descriptionUrl] 那份 XML）。
///
/// 读不出（连不上、非 200、不是设备描述、超时）返回 null——发现侧把 null
/// 当成「这台设备不是投屏对象」。
Future<CastDeviceDescription?> loadCastDeviceDescription(
  Uri descriptionUrl, {
  Duration timeout = kCastDescriptionTimeout,
}) async {
  final http = HttpClient();
  http.connectionTimeout = timeout;
  try {
    final request = await http.getUrl(descriptionUrl).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) return null;
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return parseCastDeviceDescription(body, baseUrl: descriptionUrl);
  } catch (_) {
    return null;
  } finally {
    http.close(force: true);
  }
}

/// 设备描述的注入点（测试注入「读不出」或一份固定描述，不碰网）。
typedef CastDeviceDescriptionLoader = Future<CastDeviceDescription?> Function(
  Uri descriptionUrl,
);

/// SSDP 发现的真实实现。
class SsdpCastReceiverDiscovery implements CastReceiverDiscovery {
  SsdpCastReceiverDiscovery({
    InternetAddress? target,
    this.port = kSsdpMulticastPort,
    CastDeviceDescriptionLoader? loadDescription,
  }) : target = target ?? InternetAddress(kSsdpMulticastAddress),
       _loadDescription = loadDescription ?? loadCastDeviceDescription;

  /// 搜索目的地：真机是 SSDP 组播地址，测试是本机假接收端的环回地址。
  final InternetAddress target;

  /// 搜索目的端口。
  final int port;

  final CastDeviceDescriptionLoader _loadDescription;

  @override
  Future<List<CastReceiver>> discover({
    Duration timeout = kCastDiscoveryTimeout,
  }) async {
    final responses = await _search(timeout);
    if (responses.isEmpty) return const [];

    final receivers = await Future.wait(
      responses.map((response) async {
        try {
          final description = await _loadDescription(response.location);
          if (description == null || !description.canReceiveCast) return null;
          return CastReceiver(
            id: description.udn ?? response.deviceId,
            friendlyName: description.friendlyName,
            descriptionUrl: response.location,
            controlUrls: description.controlUrls,
          );
        } catch (_) {
          // 读不通的设备与读不出的设备同一处理：跳过，发现不因一台坏设备中断。
          return null;
        }
      }),
    );
    return [for (final receiver in receivers) ?receiver]
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  /// 发一条 M-SEARCH 并收齐应答（等到 [timeout] 用完为止——设备在 `MX`
  /// 秒内随机挑时刻答，提前收摊会漏掉慢的那几台）。
  ///
  /// 组播发不出去（无网、没有可用网卡、接口不可用）时返回空表：搜不到不是
  /// 错误，准备面板要显示的是「一个都没发现」的空态。发一条 M-SEARCH 到组播
  /// 地址**不需要任何权限**，收回来的是设备给的单播应答。
  Future<List<CastSsdpResponse>> _search(Duration timeout) async {
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      return const [];
    }
    final responses = <CastSsdpResponse>[];
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final parsed = parseSsdpResponse(
        utf8.decode(datagram.data, allowMalformed: true),
      );
      if (parsed != null) responses.add(parsed);
    });
    try {
      socket.broadcastEnabled = true;
      try {
        socket.multicastHops = 4;
      } catch (_) {
        // 平台不支持设跳数：用默认值发，不影响单播回来的应答。
      }
      socket.send(
        utf8.encode(buildSsdpSearchRequest(timeout: timeout)),
        target,
        port,
      );
      await Future<void>.delayed(timeout);
    } catch (_) {
      return const [];
    } finally {
      await subscription.cancel();
      socket.close();
    }
    return dedupeSsdpResponses(responses);
  }
}
