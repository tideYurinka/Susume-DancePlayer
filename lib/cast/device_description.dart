/// UPnP **设备描述**的解析纯件：把 SSDP 应答里那个 `LOCATION`
/// 拉回来的 XML，读成「往哪发 SOAP」与「用户认得出的名字」。**零网络**——
/// 拉取留在 `ssdp_receiver_discovery.dart`。
///
/// 认下的东西只有两样是必需的：**AVTransport 的控制端点**（没有它就没有
/// 遥控可发，这台设备不是投屏对象）与一个**名字**（读不出就用兜底名）。
library;

import 'package:xml/xml.dart';

/// 服务没给名字时的接收端名：宁可让用户看见一个诚实的兜底，
/// 也不在列表里留一行空白。
const String kUnnamedCastReceiverName = '未命名接收端';

/// AVTransport 服务的类型前缀（版本号后缀不固定，按前缀认）。
const String _avTransportType = 'urn:schemas-upnp-org:service:AVTransport:';

/// RenderingControl 服务的类型前缀（音量控制）。
const String _renderingControlType =
    'urn:schemas-upnp-org:service:RenderingControl:';

/// 一台接收端的两个控制端点：SOAP 打这两个地址（拿不到就是 null）。
class CastControlUrls {
  const CastControlUrls({this.avTransport, this.renderingControl});

  /// AVTransport：推片、播放暂停停止、跳转、查询传输状态与支持的动作。
  final Uri? avTransport;

  /// RenderingControl：音量。设备不提供时音量控制项不显示（静默降级）。
  final Uri? renderingControl;

  @override
  bool operator ==(Object other) =>
      other is CastControlUrls &&
      other.avTransport == avTransport &&
      other.renderingControl == renderingControl;

  @override
  int get hashCode => Object.hash(avTransport, renderingControl);

  @override
  String toString() =>
      'CastControlUrls(avTransport: $avTransport, renderingControl: $renderingControl)';
}

/// 设备描述里我们认下的东西。
class CastDeviceDescription {
  const CastDeviceDescription({
    required this.friendlyName,
    this.udn,
    required this.controlUrls,
  });

  /// 用户在列表里看到的那行字（读不出时是 [kUnnamedCastReceiverName]）。
  final String friendlyName;

  /// 设备唯一名（`UDN`，已去掉 `uuid:` 前缀）；缺就是 null。用来与 SSDP
  /// 的 USN 对上同一个身份。
  final String? udn;

  final CastControlUrls controlUrls;

  /// 能不能当投屏对象：有 AVTransport 控制端点才有得遥控。
  bool get canReceiveCast => controlUrls.avTransport != null;

  @override
  String toString() =>
      'CastDeviceDescription($friendlyName, udn: $udn, $controlUrls)';
}

/// 解析一份设备描述；**读不出设备节点或 XML 本身不合法就 null**（这台设备
/// 与投屏无关，忽略它，不抛）。
///
/// 控制地址是相对路径时按 `<URLBase>`（老设备写法，1.1 起已废弃）解析，
/// 没有 `URLBase` 就按 [baseUrl]（设备描述自己的地址）解析——两条路都通往
/// 「发 SOAP 的那个绝对地址」。
CastDeviceDescription? parseCastDeviceDescription(
  String xml, {
  required Uri baseUrl,
}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return null;
  } catch (_) {
    return null;
  }

  final device = document.findAllElements('device').firstOrNull;
  if (device == null) return null;

  final urlBase = _resolveUrlBase(document, baseUrl);
  final services = device.findAllElements('service').toList();

  Uri? controlUrlFor(String typePrefix) {
    for (final service in services) {
      final type = _textOf(service, 'serviceType');
      if (type == null || !type.startsWith(typePrefix)) continue;
      final control = _textOf(service, 'controlURL');
      if (control == null) continue;
      final resolved = urlBase.resolve(control);
      if (resolved.scheme == 'http' || resolved.scheme == 'https') {
        return resolved;
      }
    }
    return null;
  }

  final udn = _textOf(device, 'UDN')?.replaceFirst(RegExp(r'^uuid:'), '');

  return CastDeviceDescription(
    friendlyName:
        _textOf(device, 'friendlyName') ??
        _textOf(device, 'modelName') ??
        kUnnamedCastReceiverName,
    udn: (udn == null || udn.isEmpty) ? null : udn,
    controlUrls: CastControlUrls(
      avTransport: controlUrlFor(_avTransportType),
      renderingControl: controlUrlFor(_renderingControlType),
    ),
  );
}

/// 设备自述的 `URLBase`（绝对 http 地址才认）；它不是一个合法地址时退回
/// 设备描述自己的地址——**不因为这一处坏了就整台设备读不出**。
Uri _resolveUrlBase(XmlDocument document, Uri baseUrl) {
  final declared = document.findAllElements('URLBase').firstOrNull;
  if (declared == null) return baseUrl;
  final text = declared.innerText.trim();
  if (text.isEmpty) return baseUrl;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) return baseUrl;
  return uri;
}

/// 子元素的文本（去空白）；缺元素或文本为空时 null——空串与缺失同一口径，
/// 都不算「设备自述了这一项」。
String? _textOf(XmlElement parent, String name) {
  final element = parent.findElements(name).firstOrNull;
  if (element == null) return null;
  final text = element.innerText.trim();
  return text.isEmpty ? null : text;
}
