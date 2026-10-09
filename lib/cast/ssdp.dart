/// SSDP（UPnP 设备发现）的报文纯件：**零 Flutter、零网络**——只把
/// 「怎么问」与「回来的答怎么读」写成文本进、文本出的规则，发与收留在
/// `ssdp_receiver_discovery.dart`。
///
/// 投屏的发现只认 [kMediaRendererSearchTarget]：**接收端**是自己在局域网上
/// 解码播放的那台设备，别的 UPnP 设备（网关、打印机）不是投屏对象。
library;

/// SSDP 的固定组播地址与端口（UPnP 规定，不是可配项）。
const String kSsdpMulticastAddress = '239.255.255.250';
const int kSsdpMulticastPort = 1900;

/// 搜索目标：媒体渲染器。
const String kMediaRendererSearchTarget =
    'urn:schemas-upnp-org:device:MediaRenderer:1';

/// 装配一条 M-SEARCH 请求（`ssdp:discover`）。
///
/// `MX` 是设备应答前随机等待的秒数上界，UPnP 限定 **1–5 的整数**：不足一秒
/// 按 1 发（`MX: 0` 会被设备直接忽略），超过五秒按 5 截住（发现不该为了
/// 保底等待拖成十几秒）。
String buildSsdpSearchRequest({
  required Duration timeout,
  String searchTarget = kMediaRendererSearchTarget,
}) {
  final seconds = timeout.inMilliseconds / 1000;
  final mx = seconds < 1 ? 1 : (seconds > 5 ? 5 : seconds.floor());
  return 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: $kSsdpMulticastAddress:$kSsdpMulticastPort\r\n'
      'MAN: "ssdp:discover"\r\n'
      'MX: $mx\r\n'
      'ST: $searchTarget\r\n'
      '\r\n';
}

/// 一条 SSDP 应答里我们认下的两样：设备描述地址与 USN。
class CastSsdpResponse {
  const CastSsdpResponse({required this.location, this.usn});

  /// 设备描述的绝对地址（`LOCATION`）——接着去拉它的地方。
  final Uri location;

  /// 设备唯一名（`USN`）；设备没给就是 null。
  final String? usn;

  /// 设备身份：USN 优先，缺 USN 时退到设备描述地址——**兜底不是编造**，
  /// 同一个身份用来去重。
  String get deviceId => usn ?? location.toString();

  @override
  bool operator ==(Object other) =>
      other is CastSsdpResponse &&
      other.location == location &&
      other.usn == usn;

  @override
  int get hashCode => Object.hash(location, usn);

  @override
  String toString() => 'CastSsdpResponse($deviceId → $location)';
}

/// 解析一条 SSDP 应答；**认不出就 null**（忽略这条，不抛）。
///
/// 认下的前提只有两条：状态行是 `2xx`（设备回的才是发现结果，`NOTIFY`
/// 广播不是），且带一个能解析的绝对 http(s) `LOCATION`（缺了它就没有下一步
/// 可走）。头部名不分大小写、裸 `\n` 行尾也认——设备实现参差。
CastSsdpResponse? parseSsdpResponse(String message) {
  final lines = message.split('\n');
  if (lines.isEmpty) return null;
  final statusLine = lines.first.trim();
  if (!RegExp(r'^HTTP/\d\.\d\s+2\d\d\b').hasMatch(statusLine)) return null;

  String? location;
  String? usn;
  for (final line in lines.skip(1)) {
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final name = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    if (value.isEmpty) continue;
    switch (name) {
      case 'location':
        location ??= value;
      case 'usn':
        usn ??= value;
    }
  }

  if (location == null) return null;
  final uri = Uri.tryParse(location);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return CastSsdpResponse(location: uri, usn: usn);
}

/// 应答去重：同一台设备（USN 或设备描述地址相同）只留第一条。
///
/// 设备常常对一条 M-SEARCH 答多次（不同 ST），广播与单播也会各来一份——
/// 发现结果里不该出现同一台电视两遍。
List<CastSsdpResponse> dedupeSsdpResponses(
  Iterable<CastSsdpResponse> responses,
) {
  final seen = <String>{};
  final deduped = <CastSsdpResponse>[];
  for (final response in responses) {
    if (seen.add(response.deviceId)) deduped.add(response);
  }
  return deduped;
}
