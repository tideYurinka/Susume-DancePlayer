/// SOAP 报文的纯件：投屏的每条遥控都是一次
/// 「SOAP POST → 一份应答」，这里只装配请求体、读应答体——**零网络、零
/// Flutter**，发与收留在 `dlna_cast_session.dart`。
library;

import 'package:xml/xml.dart';

/// 读不出原因时的故障码：设备给的 Fault 缺 `errorCode`、或应答根本不是
/// SOAP。它与 UPnP 的数字错误码不同域（UPnP 用非负整数），故取负数。
const int kCastSoapUnparsableErrorCode = -1;

/// 投屏要打的两个 UPnP 服务。
enum CastUpnpService {
  /// 推片、播放暂停停止、跳转、查询传输状态与支持的动作。
  avTransport('urn:schemas-upnp-org:service:AVTransport:1'),

  /// 音量。
  renderingControl('urn:schemas-upnp-org:service:RenderingControl:1');

  const CastUpnpService(this.serviceType);

  /// 服务类型串：同时是动作元素的命名空间与 `SOAPAction` 头的前半段。
  final String serviceType;

  /// `SOAPAction` 头的值（**带引号**，照 UPnP 的老规矩）：`"<服务类型>#<动作>"`。
  String actionHeader(String action) => '"$serviceType#$action"';
}

/// `SOAPAction` 头的值。真实实现把它放进请求头，测试直接断言这个串。
String castSoapActionHeaderValue(CastUpnpService service, String action) =>
    service.actionHeader(action);

/// 装配一条 SOAP 请求体：动作元素挂在 Body 下、命名空间是服务类型，参数
/// 逐个成子元素（值里的 XML 特殊字符转义——递出地址里会带 `&` 与引号）。
String buildCastSoapEnvelope({
  required CastUpnpService service,
  required String action,
  Map<String, String> arguments = const {},
}) {
  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="utf-8"?>')
    ..write(
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
      's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
    )
    ..write('<s:Body>')
    ..write('<u:${_escapeXml(action)} xmlns:u="${service.serviceType}">');
  for (final entry in arguments.entries) {
    buffer.write(
      '<${_escapeXml(entry.key)}>${_escapeXml(entry.value)}'
      '</${_escapeXml(entry.key)}>',
    );
  }
  buffer
    ..write('</u:${_escapeXml(action)}>')
    ..write('</s:Body>')
    ..write('</s:Envelope>');
  return buffer.toString();
}

/// 一次 SOAP 调用的结局：要么拿到输出参数，要么是设备回绝/应答读不出。
sealed class CastSoapOutcome {
  const CastSoapOutcome();
}

/// 成功：动作应答里的输出参数（名字 → 文本；空动作应答是空表）。
final class CastSoapSuccess extends CastSoapOutcome {
  const CastSoapSuccess(this.values);

  final Map<String, String> values;
}

/// 故障：设备回的 SOAP Fault（UPnP 错误码 + 描述），或应答根本读不出
/// （[kCastSoapUnparsableErrorCode]）。
final class CastSoapFault extends CastSoapOutcome {
  const CastSoapFault(this.errorCode, this.description);

  final int errorCode;
  final String description;
}

/// 解析一份 SOAP 应答体。
///
/// **认不出的一律归到 [CastSoapFault]（错误码 -1）**：设备回的正文不是 XML、
/// 缺 Body、Fault 里缺 `errorCode`——这些都得有明确结局，不能吞成「成功但
/// 什么都没读到」。
CastSoapOutcome parseCastSoapResponse(String body) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } catch (_) {
    return const CastSoapFault(kCastSoapUnparsableErrorCode, '');
  }

  final bodyElement = _elementsNamed(document, 'Body').firstOrNull;
  if (bodyElement == null) {
    return const CastSoapFault(kCastSoapUnparsableErrorCode, '');
  }

  final fault = _elementsNamed(bodyElement, 'Fault').firstOrNull;
  if (fault != null) return _parseFault(fault);

  final response = bodyElement.childElements.firstOrNull;
  if (response == null) {
    return const CastSoapFault(kCastSoapUnparsableErrorCode, '');
  }

  final values = <String, String>{};
  for (final child in response.childElements) {
    values[child.name.local] = child.innerText.trim();
  }
  return CastSoapSuccess(values);
}

/// Fault → 错误码与描述：UPnP 的错误码在 `UPnPError/errorCode` 里；缺了
/// 就退到 -1（**不猜**成别的码）。
CastSoapFault _parseFault(XmlElement fault) {
  final code = int.tryParse(
    _elementsNamed(fault, 'errorCode').firstOrNull?.innerText.trim() ?? '',
  );
  final description =
      _elementsNamed(fault, 'errorDescription').firstOrNull?.innerText.trim() ??
      '';
  return CastSoapFault(code ?? kCastSoapUnparsableErrorCode, description);
}

/// 按**本地名**找元素：SOAP 信封的前缀由设备自定（`s:` / `SOAP-ENV:` /
/// 无前缀），按限定名找会漏掉一半设备。
Iterable<XmlElement> _elementsNamed(XmlNode node, String localName) => node
    .descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == localName);

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
