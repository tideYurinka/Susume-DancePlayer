import 'package:dance_learning_app/cast/soap.dart';
import 'package:flutter_test/flutter_test.dart';

/// SOAP 报文：投屏的遥控全部是
/// 「一条 SOAP POST + 一份应答」。装配与解析都是纯件——不碰网；非法与缺字段
/// 输入一律归到一条**说不清原因的故障**（错误码 -1），不抛。
void main() {
  group('请求装配', () {
    test('SOAPAction 头是「服务类型#动作」，带引号', () {
      expect(
        CastUpnpService.avTransport.actionHeader('Play'),
        '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
      );
      expect(
        CastUpnpService.renderingControl.actionHeader('SetVolume'),
        '"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"',
      );
    });

    test('信封把动作放进 Body，参数逐个成子元素', () {
      final envelope = buildCastSoapEnvelope(
        service: CastUpnpService.avTransport,
        action: 'Seek',
        arguments: {'InstanceID': '0', 'Unit': 'REL_TIME', 'Target': '0:00:30'},
      );

      expect(envelope, contains('s:Envelope'));
      expect(
        envelope,
        contains('xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"'),
        reason: '动作元素的命名空间就是服务身份',
      );
      expect(envelope, contains('<u:Seek'));
      expect(envelope, contains('<InstanceID>0</InstanceID>'));
      expect(envelope, contains('<Unit>REL_TIME</Unit>'));
      expect(envelope, contains('<Target>0:00:30</Target>'));
      expect(envelope, contains('</u:Seek>'));
    });

    test('参数值里的 XML 特殊字符被转义（文件名会带 & 与引号）', () {
      final envelope = buildCastSoapEnvelope(
        service: CastUpnpService.avTransport,
        action: 'SetAVTransportURI',
        arguments: {
          'InstanceID': '0',
          'CurrentURI': 'http://10.0.0.2:8080/cast/tok/a&b"c.mp4',
        },
      );

      expect(envelope, contains('a&amp;b&quot;c.mp4'));
      expect(envelope, isNot(contains('a&b"c.mp4')));
    });
  });

  group('应答解析', () {
    const successBody =
        '<?xml version="1.0"?>\n'
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">\n'
        '  <s:Body>\n'
        '    <u:GetTransportInfoResponse '
        'xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">\n'
        '      <CurrentTransportState>PLAYING</CurrentTransportState>\n'
        '      <CurrentTransportStatus>OK</CurrentTransportStatus>\n'
        '      <CurrentSpeed>1</CurrentSpeed>\n'
        '    </u:GetTransportInfoResponse>\n'
        '  </s:Body>\n'
        '</s:Envelope>';

    test('成功应答：输出参数读成名字到值的表', () {
      final outcome = parseCastSoapResponse(successBody);

      expect(outcome, isA<CastSoapSuccess>());
      expect((outcome as CastSoapSuccess).values, {
        'CurrentTransportState': 'PLAYING',
        'CurrentTransportStatus': 'OK',
        'CurrentSpeed': '1',
      });
    });

    test('命名空间前缀不是 s: 也认（设备的实现参差）', () {
      final outcome = parseCastSoapResponse(
        '<SOAP-ENV:Envelope '
        'xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">'
        '<SOAP-ENV:Body><u:GetVolumeResponse '
        'xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">'
        '<CurrentVolume>40</CurrentVolume>'
        '</u:GetVolumeResponse></SOAP-ENV:Body></SOAP-ENV:Envelope>',
      );

      expect((outcome as CastSoapSuccess).values['CurrentVolume'], '40');
    });

    test('Fault：读出 UPnP 错误码与描述', () {
      final outcome = parseCastSoapResponse(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body><s:Fault><faultcode>s:Client</faultcode>'
        '<detail><UPnPError '
        'xmlns="urn:schemas-upnp-org:control-1-0">'
        '<errorCode>701</errorCode>'
        '<errorDescription>Transition not available</errorDescription>'
        '</UPnPError></detail></s:Fault></s:Body></s:Envelope>',
      );

      expect(outcome, isA<CastSoapFault>());
      final fault = outcome as CastSoapFault;
      expect(fault.errorCode, 701);
      expect(fault.description, 'Transition not available');
    });

    test('Fault 缺 errorCode：归到 -1，不抛', () {
      final outcome = parseCastSoapResponse(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body><s:Fault><faultcode>s:Server</faultcode></s:Fault>'
        '</s:Body></s:Envelope>',
      );

      expect(outcome, isA<CastSoapFault>());
      expect(
        (outcome as CastSoapFault).errorCode,
        kCastSoapUnparsableErrorCode,
      );
    });

    test('不是 XML / 空正文 / 没有 Body：都归到 -1，不抛', () {
      for (final body in ['', 'not xml', '<html><body>404</body></html>']) {
        final outcome = parseCastSoapResponse(body);
        expect(outcome, isA<CastSoapFault>(), reason: '输入：$body');
        expect(
          (outcome as CastSoapFault).errorCode,
          kCastSoapUnparsableErrorCode,
        );
      }
    });

    test('响应体里没有输出参数（空动作应答）：成功但值为空表', () {
      final outcome = parseCastSoapResponse(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body><u:StopResponse '
        'xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/>'
        '</s:Body></s:Envelope>',
      );

      expect(outcome, isA<CastSoapSuccess>());
      expect((outcome as CastSoapSuccess).values, isEmpty);
    });
  });
}
