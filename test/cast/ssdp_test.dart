import 'package:dance_learning_app/cast/ssdp.dart';
import 'package:flutter_test/flutter_test.dart';

/// SSDP 的请求文本与应答解析：投屏发现只认
/// 自己发出去的 M-SEARCH 与局域网回来的应答。全部是纯件——不碰网、不起
/// 服务，非法与缺字段输入各有兜底（忽略，不抛）。
void main() {
  group('M-SEARCH 请求', () {
    test('是完整的 ssdp:discover 报文：MAN / MX / ST 一行不缺，以空行收尾', () {
      final request = buildSsdpSearchRequest(
        timeout: const Duration(seconds: 2),
      );

      expect(request, startsWith('M-SEARCH * HTTP/1.1\r\n'));
      expect(request, contains('\r\nMAN: "ssdp:discover"\r\n'));
      expect(request, contains('\r\nMX: 2\r\n'));
      expect(
        request,
        contains('\r\nST: $kMediaRendererSearchTarget\r\n'),
        reason: '搜索目标恒是媒体渲染器：投屏只认自己解码播放的设备',
      );
      expect(
        request,
        contains('\r\nHOST: $kSsdpMulticastAddress:$kSsdpMulticastPort\r\n'),
      );
      expect(request, endsWith('\r\n\r\n'), reason: '头部以空行收尾');
    });

    test('MX 是 1–5 秒的整数：UPnP 规定这个区间，越界钳进去', () {
      expect(buildSsdpSearchRequest(timeout: Duration.zero), contains('MX: 1'));
      expect(
        buildSsdpSearchRequest(timeout: const Duration(seconds: 30)),
        contains('MX: 5'),
      );
      expect(
        buildSsdpSearchRequest(timeout: const Duration(milliseconds: 900)),
        contains('MX: 1'),
        reason: '不足一秒也发 1：MX: 0 会被设备忽略',
      );
    });
  });

  group('SSDP 应答解析', () {
    test('读出 LOCATION / USN / ST 三样', () {
      final response = parseSsdpResponse(
        'HTTP/1.1 200 OK\r\n'
        'CACHE-CONTROL: max-age=1800\r\n'
        'LOCATION: http://192.168.1.7:49152/description.xml\r\n'
        'ST: $kMediaRendererSearchTarget\r\n'
        'USN: uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
        'SERVER: Linux/5 UPnP/1.0 Rygel/0.42\r\n'
        '\r\n',
      );

      expect(response, isNotNull);
      expect(
        response!.location,
        Uri.parse('http://192.168.1.7:49152/description.xml'),
      );
      expect(
        response.usn,
        'uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1',
      );
      expect(response.searchTarget, kMediaRendererSearchTarget);
      expect(
        response.deviceId,
        'uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1',
      );
    });

    test('头部名不分大小写、裸 LF 行尾也认（设备实现参差）', () {
      final response = parseSsdpResponse(
        'HTTP/1.0 200 OK\n'
        'location:   http://10.0.0.9:80/d.xml  \n'
        'uSn: uuid:xyz\n'
        '\n',
      );

      expect(response, isNotNull);
      expect(response!.location, Uri.parse('http://10.0.0.9:80/d.xml'));
      expect(response.usn, 'uuid:xyz');
      expect(response.searchTarget, isNull, reason: '缺 ST = 不认，不编一个');
    });

    test('缺 LOCATION：忽略这条应答，不抛', () {
      expect(
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nST: $kMediaRendererSearchTarget\r\n\r\n',
        ),
        isNull,
      );
    });

    test('LOCATION 不是绝对 http 地址：忽略，不抛', () {
      expect(
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: /description.xml\r\n\r\n',
        ),
        isNull,
        reason: '相对地址取不到设备描述，等同于没有这条应答',
      );
      expect(
        parseSsdpResponse('HTTP/1.1 200 OK\r\nLOCATION: not a url\r\n\r\n'),
        isNull,
      );
    });

    test('不是应答的报文（NOTIFY / 乱码 / 空）：忽略，不抛', () {
      expect(parseSsdpResponse(''), isNull);
      expect(parseSsdpResponse('garbage'), isNull);
      expect(
        parseSsdpResponse(
          'NOTIFY * HTTP/1.1\r\nLOCATION: http://10.0.0.9:80/d.xml\r\n\r\n',
        ),
        isNull,
        reason: '只有 200 应答才算发现结果',
      );
      expect(
        parseSsdpResponse(
          'HTTP/1.1 404 Not Found\r\nLOCATION: http://a/b\r\n\r\n',
        ),
        isNull,
      );
    });

    test('缺 USN：身份退到设备描述地址（兜底不是编造）', () {
      final response = parseSsdpResponse(
        'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/d.xml\r\n\r\n',
      );

      expect(response, isNotNull);
      expect(response!.usn, isNull);
      expect(
        response.deviceId,
        response.location.toString(),
        reason: '缺 USN 时身份退到设备描述地址本身，不另编一个串',
      );
    });
  });

  group('应答去重', () {
    test('同一台设备（USN 相同）答两次只留第一条', () {
      const usn = 'uuid:abc::urn:schemas-upnp-org:device:MediaRenderer:1';
      final deduped = dedupeSsdpResponses([
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/d.xml\r\nUSN: $usn\r\n\r\n',
        )!,
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/other.xml\r\nUSN: $usn\r\n\r\n',
        )!,
      ]);

      expect(deduped, hasLength(1));
      expect(deduped.single.location, Uri.parse('http://10.0.0.9:80/d.xml'));
    });

    test('两台不同设备各留一条', () {
      final deduped = dedupeSsdpResponses([
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/d.xml\r\nUSN: uuid:a\r\n\r\n',
        )!,
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.8:80/d.xml\r\nUSN: uuid:b\r\n\r\n',
        )!,
      ]);

      expect(deduped, hasLength(2));
    });

    test('都没有 USN 时按设备描述地址去重', () {
      final deduped = dedupeSsdpResponses([
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/d.xml\r\n\r\n',
        )!,
        parseSsdpResponse(
          'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/d.xml\r\n\r\n',
        )!,
      ]);

      expect(deduped, hasLength(1));
    });
  });
}
