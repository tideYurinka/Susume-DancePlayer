import 'package:dance_learning_app/cast/device_description.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设备描述的解析：SSDP 应答给的 `LOCATION` 拉回来就是这份 XML，投屏要从
/// 里面读出**往哪发 SOAP**（AVTransport / RenderingControl 控制端点）与
/// 用户认得出的**接收端名**。纯件——不碰网；非法与缺字段输入各有兜底。
void main() {
  const descriptionUrl = 'http://192.168.1.7:49152/description.xml';

  String description(String deviceBody, {String serviceList = ''}) =>
      '<?xml version="1.0"?>\n'
      '<root xmlns="urn:schemas-upnp-org:device-1-0">\n'
      '  <specVersion><major>1</major><minor>0</minor></specVersion>\n'
      '  <device>\n'
      '    $deviceBody\n'
      '    <serviceList>$serviceList</serviceList>\n'
      '  </device>\n'
      '</root>';

  String service(String type, String controlPath) =>
      '<service><serviceType>$type</serviceType>'
      '<serviceId>$type</serviceId>'
      '<controlURL>$controlPath</controlURL>'
      '<eventSubURL>$controlPath/event</eventSubURL>'
      '<SCPDURL>$controlPath.xml</SCPDURL></service>';

  const avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';
  const renderingControl = 'urn:schemas-upnp-org:service:RenderingControl:1';

  test('读出友好名、UDN 与两个控制端点（相对地址按描述地址解析）', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>客厅的电视</friendlyName>'
        '<UDN>uuid:abc-123</UDN>'
        '<modelName>FakeTV</modelName>',
        serviceList:
            '${service(avTransport, '/upnp/control/AVTransport')}'
            '${service(renderingControl, '/upnp/control/RenderingControl')}',
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(parsed, isNotNull);
    expect(parsed!.friendlyName, '客厅的电视');
    expect(parsed.udn, 'abc-123', reason: 'UDN 去掉 uuid: 前缀后与 SSDP 的 USN 同源');
    expect(
      parsed.controlUrls.avTransport,
      Uri.parse('http://192.168.1.7:49152/upnp/control/AVTransport'),
    );
    expect(
      parsed.controlUrls.renderingControl,
      Uri.parse('http://192.168.1.7:49152/upnp/control/RenderingControl'),
    );
    expect(parsed.canReceiveCast, isTrue);
  });

  test('控制端点是绝对地址时原样取，不被描述地址改写', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>TV</friendlyName>',
        serviceList: service(avTransport, 'http://10.0.0.5:8080/avt'),
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(
      parsed!.controlUrls.avTransport,
      Uri.parse('http://10.0.0.5:8080/avt'),
    );
  });

  test('设备自述 URLBase 时按它解析控制地址（老设备的写法）', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>TV</friendlyName>'
        '<URLBase>http://10.0.0.5:9999/base/</URLBase>',
        serviceList: service(avTransport, 'avt'),
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(
      parsed!.controlUrls.avTransport,
      Uri.parse('http://10.0.0.5:9999/base/avt'),
    );
  });

  test('缺友好名退到型号名；两样都缺退到固定名，不编造', () {
    final withModel = parseCastDeviceDescription(
      description(
        '<modelName>FakeTV</modelName>',
        serviceList: service(avTransport, '/avt'),
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );
    final bare = parseCastDeviceDescription(
      description('', serviceList: service(avTransport, '/avt')),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(withModel!.friendlyName, 'FakeTV');
    expect(bare!.friendlyName, kUnnamedCastReceiverName);
  });

  test('没有 AVTransport：不是投屏对象，两个端点都空着', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>只看得见的设备</friendlyName>',
        serviceList: service(
          'urn:schemas-upnp-org:service:ConnectionManager:1',
          '/upnp/control/ConnectionManager',
        ),
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(parsed, isNotNull);
    expect(parsed!.canReceiveCast, isFalse);
    expect(parsed.controlUrls.avTransport, isNull);
    expect(parsed.controlUrls.renderingControl, isNull);
  });

  test('只有 AVTransport：音量控制端点缺，按「没有」处理', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>TV</friendlyName>',
        serviceList: service(avTransport, '/avt'),
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(parsed!.controlUrls.avTransport, isNotNull);
    expect(parsed.controlUrls.renderingControl, isNull);
  });

  test('服务的 controlURL 缺失或为空：该服务不认，不编造端点', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>TV</friendlyName>',
        serviceList:
            '<service><serviceType>$avTransport</serviceType>'
            '<controlURL></controlURL></service>',
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(parsed!.controlUrls.avTransport, isNull);
  });

  test('服务类型的版本号不同也认（AVTransport:2 同样是 AVTransport）', () {
    final parsed = parseCastDeviceDescription(
      description(
        '<friendlyName>TV</friendlyName>',
        serviceList: service(
          'urn:schemas-upnp-org:service:AVTransport:2',
          '/avt',
        ),
      ),
      baseUrl: Uri.parse(descriptionUrl),
    );

    expect(parsed!.controlUrls.avTransport, isNotNull);
  });

  test('不是 XML / 空 / 没有 device 节点：读不出东西，返回 null', () {
    expect(
      parseCastDeviceDescription(
        '<html>不是设备描述</html>',
        baseUrl: Uri.parse(descriptionUrl),
      ),
      isNull,
    );
    expect(
      parseCastDeviceDescription('', baseUrl: Uri.parse(descriptionUrl)),
      isNull,
    );
    expect(
      parseCastDeviceDescription(
        '<root><foo/></root>',
        baseUrl: Uri.parse(descriptionUrl),
      ),
      isNull,
    );
  });
}
