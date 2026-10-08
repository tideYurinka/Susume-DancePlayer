/// 递出这份片子时对外说的**媒体类型**与随 URL 一起交给接收端的
/// **DIDL-Lite 元数据**：递出通道的 `Content-Type` 与推片时的
/// `CurrentURIMetaData` 共用同一份判据——两处说成两样，接收端就会挑一个信。
library;

/// 认不出扩展名时对外说的类型（接收端多半会拒绝，但至少不说谎）。
const String kCastFallbackContentType = 'application/octet-stream';

/// 按文件名认视频类型。投屏递出的是本机导入的视频副本，扩展名来自导入时
/// 保留的原名。
String castContentTypeForName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
  if (lower.endsWith('.mkv')) return 'video/x-matroska';
  if (lower.endsWith('.mov')) return 'video/quicktime';
  if (lower.endsWith('.webm')) return 'video/webm';
  if (lower.endsWith('.avi')) return 'video/x-msvideo';
  if (lower.endsWith('.ts')) return 'video/mp2t';
  return kCastFallbackContentType;
}

/// 装配 `SetAVTransportURI` 的 `CurrentURIMetaData`：一份最小但完整的
/// DIDL-Lite（**未转义的 XML 文本**——它作为 SOAP 参数值进信封，由
/// `buildCastSoapEnvelope` 统一转义一次）。
///
/// 不少接收端（含 rygel）**不靠 URL 猜片子的类别**，而是看这份元数据里的
/// `upnp:class` 与 `res`；给一份空的元数据，它们会当成「不知道要播什么」
/// 而拒播。故这里给出 `object.item.videoItem` + 一条 `res`（地址与类型与
/// 递出时说的那份一致）。
String buildCastDidlMetadata({
  required Uri url,
  required String title,
  String? contentType,
}) {
  final type = contentType ?? castContentTypeForName(url.path);
  return '<DIDL-Lite '
      'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
      '<item id="0" parentID="-1" restricted="1">'
      '<dc:title>${escapeXmlText(title)}</dc:title>'
      '<upnp:class>object.item.videoItem</upnp:class>'
      '<res protocolInfo="http-get:*:$type:*">'
      '${escapeXmlText(url.toString())}'
      '</res>'
      '</item>'
      '</DIDL-Lite>';
}

/// 一段文本进 XML 文本节点时的转义（`&` 必须第一个换）。
String escapeXmlText(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
