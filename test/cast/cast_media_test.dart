import 'package:dance_learning_app/cast/cast_media.dart';
import 'package:dance_learning_app/cast/soap.dart';
import 'package:flutter_test/flutter_test.dart';

/// 递出这份片子时对外的两份说法（HTTP 的 `Content-Type` 与推片时的
/// DIDL-Lite 元数据）是同一份判据；元数据进 SOAP 参数值**只转义一次**。
void main() {
  test('按扩展名认视频类型；认不出就说 application/octet-stream', () {
    expect(castContentTypeForName('a.mp4'), 'video/mp4');
    expect(castContentTypeForName('A.M4V'), 'video/mp4');
    expect(castContentTypeForName('a.mkv'), 'video/x-matroska');
    expect(castContentTypeForName('a.mov'), 'video/quicktime');
    expect(castContentTypeForName('a.webm'), 'video/webm');
    expect(castContentTypeForName('a.avi'), 'video/x-msvideo');
    expect(castContentTypeForName('a.ts'), 'video/mp2t');
    expect(castContentTypeForName('a.unknown'), kCastFallbackContentType);
  });

  test('DIDL-Lite 元数据：视频类目 + 一条带类型的 res', () {
    final url = Uri.parse('http://192.168.1.7:8080/cast/tok/练习.mp4');
    final didl = buildCastDidlMetadata(url: url, title: '练习');

    expect(didl, contains('DIDL-Lite'));
    expect(didl, contains('<upnp:class>object.item.videoItem</upnp:class>'));
    expect(
      didl,
      contains('protocolInfo="http-get:*:video/mp4:*"'),
      reason: 'res 的类型要与递出时说的 Content-Type 一致',
    );
    expect(
      didl,
      contains(url.toString()),
      reason: 'res 里就是递出地址本身（编码形式由 Uri 决定，两处必须同一份）',
    );
  });

  test('片名与地址里的 XML 特殊字符在元数据内部就转义', () {
    final didl = buildCastDidlMetadata(
      url: Uri.parse('http://10.0.0.2/cast/tok/a&b.mp4'),
      title: 'A & B "练习"',
    );

    expect(didl, contains('<dc:title>A &amp; B &quot;练习&quot;</dc:title>'));
    expect(didl, contains('a&amp;b.mp4'));
  });

  test('元数据作为 SOAP 参数值只被转义一次', () {
    final didl = buildCastDidlMetadata(
      url: Uri.parse('http://10.0.0.2/cast/tok/a.mp4'),
      title: '练习',
    );
    final envelope = buildCastSoapEnvelope(
      service: CastUpnpService.avTransport,
      action: 'SetAVTransportURI',
      arguments: {
        'InstanceID': '0',
        'CurrentURI': 'http://10.0.0.2/cast/tok/a.mp4',
        'CurrentURIMetaData': didl,
      },
    );

    expect(envelope, contains('&lt;DIDL-Lite'));
    expect(
      envelope,
      isNot(contains('&amp;lt;')),
      reason: '双转义会让接收端收到一份字面的 &lt;DIDL-Lite 文本',
    );
  });
}
