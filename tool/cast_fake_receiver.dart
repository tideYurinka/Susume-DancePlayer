/// 仓内的**假接收端**：SSDP 应答 + 设备描述 + AVTransport /
/// RenderingControl 两条 SOAP 服务。
///
/// 两个用途：
/// 1. **CI 的端到端基线**——`test/cast/fake_receiver_e2e_test.dart` 起它跑完
///    「发现 → 推 → 播 → 暂停 → 跳转 → 音量 → 断开」，不依赖真电视；
/// 2. **真机验收的替代接收端**——手边只有电脑时
///    `dart run tool/cast_fake_receiver.dart` 在电脑上起一台，手机 App 能发现
///    它、并把它收到的每条 SOAP 指令打印出来（核对我们发出去的就是那些）。
///
/// 它**刻意不 import `lib/cast/`**：一个独立的实现才能当我们自己的对照。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

/// 假接收端。
class FakeDlnaReceiver {
  FakeDlnaReceiver._({
    required this.address,
    required this.advertisedAddress,
    required this.ssdpPort,
    required this.friendlyName,
    required this.httpServer,
    required this.ssdpSocket,
    required this.udn,
    required this.supportedActions,
    required this.refusePlay,
    required this.unimplementedActions,
    required this.ssdpRepliesPerSearch,
  });

  /// 起一台假接收端：UDP 听 SSDP 搜索（端口 0 = 系统分配），HTTP 提供设备
  /// 描述与两条控制端点。
  static Future<FakeDlnaReceiver> start({
    InternetAddress? address,
    InternetAddress? advertisedAddress,
    String friendlyName = 'CI 假接收端',
    int ssdpPort = 0,
    int httpPort = 0,
    Set<String> supportedActions = const {'Play', 'Pause', 'Stop', 'Seek'},
    bool refusePlay = false,
    Set<String> unimplementedActions = const {},
    int ssdpRepliesPerSearch = 1,
    String udn = 'uuid:fake-susume-receiver',
  }) async {
    final host = address ?? InternetAddress.loopbackIPv4;
    final http = await HttpServer.bind(host, httpPort);
    final socket = await RawDatagramSocket.bind(host, ssdpPort);
    try {
      // 真机验收时手机把 M-SEARCH 发到组播地址：不加入组就收不到（macOS /
      // Windows 上尤其如此）。测试走环回单播，加不进去也不影响。
      socket.joinMulticast(InternetAddress('239.255.255.250'));
    } catch (_) {
      // 平台不允许加入组播组：环回单播那条路照旧可用。
    }
    return FakeDlnaReceiver._(
      address: host,
      advertisedAddress:
          advertisedAddress ??
          (host.address == InternetAddress.anyIPv4.address
              ? await _defaultAdvertisedAddress()
              : host),
      ssdpPort: socket.port,
      friendlyName: friendlyName,
      httpServer: http,
      ssdpSocket: socket,
      udn: udn,
      supportedActions: supportedActions,
      refusePlay: refusePlay,
      unimplementedActions: unimplementedActions,
      ssdpRepliesPerSearch: ssdpRepliesPerSearch,
    ).._listen(http, socket);
  }

  /// 绑定地址（`--` 起服务时是 `0.0.0.0`）。
  final InternetAddress address;

  /// 通告给手机的那个地址：设备描述、控制端点与 SSDP 的 `LOCATION` 都用
  /// 它——绑 `0.0.0.0` 时不能把 `0.0.0.0` 说给手机听。
  final InternetAddress advertisedAddress;

  final int ssdpPort;
  final String friendlyName;
  final HttpServer httpServer;
  final RawDatagramSocket ssdpSocket;
  final String udn;

  /// 这台设备自述支持哪些传输动作（`GetCurrentTransportActions` 的应答）。
  final Set<String> supportedActions;

  /// 置真时 `Play` 回一条 UPnP 701 的 Fault（拒播用例）。
  bool refusePlay;

  /// 不回实现、直接回 501 Fault 的动作（探测失败用例）。
  final Set<String> unimplementedActions;

  /// 一条 M-SEARCH 答几遍（去重用例：设备常常答多次）。
  final int ssdpRepliesPerSearch;

  /// 收到的 SOAP 动作名，按顺序（端到端要断言的就是这个序列）。
  final List<String> receivedActions = [];

  /// 收到的 SOAP 请求体原文（真机排查时打印它核对参数）。
  final List<String> receivedSoapBodies = [];

  /// 最近一次 `SetAVTransportURI` 给的地址与元数据。
  String? currentUri;
  String? currentUriMetadata;

  /// 假播放时钟的读数与状态。
  String transportState = 'NO_MEDIA_PRESENT';
  int volume = 30;

  /// 假接收端按 [currentUri] 自己拉了一次片（**带 Range**）：拿到多少字节、
  /// 什么状态码——递出通道真的被接收端用上了的证据。
  int? fetchedBytes;
  int? fetchedStatusCode;
  String? fetchError;

  int get httpPort => httpServer.port;

  /// 发现时把 M-SEARCH 发给这个目的地（测试里是环回单播，真机是组播）。
  (InternetAddress, int) get ssdpSearchTarget => (address, ssdpPort);

  Uri get descriptionUrl => Uri.parse(
    'http://${advertisedAddress.address}:$httpPort/description.xml',
  );

  Uri get avTransportControlUrl => Uri.parse(
    'http://${advertisedAddress.address}:$httpPort/upnp/control/AVTransport',
  );

  Uri get renderingControlUrl => Uri.parse(
    'http://${advertisedAddress.address}:$httpPort/upnp/control/RenderingControl',
  );

  /// 停掉这台假接收端（两条通道都关）。
  Future<void> stop() async {
    ssdpSocket.close();
    await httpServer.close(force: true);
  }

  /// 当前播放位置（假时钟：Play 起跑、Pause 停表、Seek 挪基准）。
  Duration position = Duration.zero;
  final Stopwatch _clock = Stopwatch();
  bool get _playing => _clock.isRunning;
  Duration get currentPosition =>
      position + (_playing ? _clock.elapsed : Duration.zero);

  void _listen(HttpServer http, RawDatagramSocket socket) {
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final request = utf8.decode(datagram.data, allowMalformed: true);
      if (!request.startsWith('M-SEARCH')) return;
      final response = _ssdpResponse();
      for (var i = 0; i < ssdpRepliesPerSearch; i++) {
        socket.send(utf8.encode(response), datagram.address, datagram.port);
      }
    });
    http.listen(_handleRequest);
  }

  String _ssdpResponse() =>
      'HTTP/1.1 200 OK\r\n'
      'CACHE-CONTROL: max-age=1800\r\n'
      'EXT:\r\n'
      'LOCATION: $descriptionUrl\r\n'
      'SERVER: Dart/3 SusumeFake/1 UPnP/1.0\r\n'
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      'USN: $udn::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      '\r\n';

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/description.xml') {
        await _sendXml(request.response, _deviceDescription());
        return;
      }
      if (request.method == 'POST' &&
          (path == '/upnp/control/AVTransport' ||
              path == '/upnp/control/RenderingControl')) {
        await _handleSoap(request, path);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {
        // 连接已经没了。
      }
    }
  }

  Future<void> _handleSoap(HttpRequest request, String path) async {
    final body = await utf8.decodeStream(request);
    final action = _actionOf(request);
    receivedActions.add(action);
    receivedSoapBodies.add(body);
    final arguments = _argumentsOf(body);
    final service = path.endsWith('AVTransport')
        ? 'urn:schemas-upnp-org:service:AVTransport:1'
        : 'urn:schemas-upnp-org:service:RenderingControl:1';

    if (unimplementedActions.contains(action)) {
      await _sendFault(request.response, 501, 'Action $action not implemented');
      return;
    }

    if (action == 'Play') {
      if (refusePlay) {
        await _sendFault(request.response, 701, 'Transition not available');
        return;
      }
      position = currentPosition;
      _clock
        ..reset()
        ..start();
      transportState = 'PLAYING';
      await _sendXml(request.response, _soapResponse(service, action, {}));
      return;
    }

    switch (action) {
      case 'SetAVTransportURI':
        currentUri = arguments['CurrentURI'];
        currentUriMetadata = arguments['CurrentURIMetaData'];
        transportState = 'STOPPED';
        position = Duration.zero;
        _clock
          ..stop()
          ..reset();
        await _sendXml(request.response, _soapResponse(service, action, {}));
        unawaited(_fetchCurrentUri());
        return;
      case 'Pause':
        position = currentPosition;
        _clock
          ..stop()
          ..reset();
        transportState = 'PAUSED_PLAYBACK';
        await _sendXml(request.response, _soapResponse(service, action, {}));
        return;
      case 'Stop':
        position = Duration.zero;
        _clock
          ..stop()
          ..reset();
        transportState = 'STOPPED';
        await _sendXml(request.response, _soapResponse(service, action, {}));
        return;
      case 'Seek':
        final target = _durationOf(arguments['Target']);
        if (target == null) {
          await _sendFault(request.response, 711, 'Illegal seek target');
          return;
        }
        position = target;
        _clock
          ..stop()
          ..reset();
        if (transportState == 'PLAYING') _clock.start();
        await _sendXml(request.response, _soapResponse(service, action, {}));
        return;
      case 'GetTransportInfo':
        await _sendXml(
          request.response,
          _soapResponse(service, action, {
            'CurrentTransportState': transportState,
            'CurrentTransportStatus': 'OK',
            'CurrentSpeed': '1',
          }),
        );
        return;
      case 'GetPositionInfo':
        await _sendXml(
          request.response,
          _soapResponse(service, action, {
            'Track': '0',
            'TrackDuration': '0:10:00',
            'RelTime': _formatDuration(currentPosition),
            'AbsTime': _formatDuration(currentPosition),
          }),
        );
        return;
      case 'GetCurrentTransportActions':
        await _sendXml(
          request.response,
          _soapResponse(service, action, {
            'Actions': supportedActions.join(','),
          }),
        );
        return;
      case 'GetVolume':
        await _sendXml(
          request.response,
          _soapResponse(service, action, {'CurrentVolume': '$volume'}),
        );
        return;
      case 'SetVolume':
        volume = int.tryParse(arguments['DesiredVolume'] ?? '') ?? volume;
        await _sendXml(request.response, _soapResponse(service, action, {}));
        return;
      default:
        await _sendFault(
          request.response,
          501,
          'Action $action not implemented',
        );
        return;
    }
  }

  /// 按 `SetAVTransportURI` 给的地址自己拉一段（带 `Range`）——把递出通道
  /// 也拉进端到端链路：接收端真的从我们这台机器上取到了字节。
  Future<void> _fetchCurrentUri() async {
    final uri = currentUri;
    if (uri == null) return;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client.getUrl(Uri.parse(uri));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final response = await request.close();
      fetchedStatusCode = response.statusCode;
      var bytes = 0;
      await for (final chunk in response) {
        bytes += chunk.length;
      }
      fetchedBytes = bytes;
    } catch (error) {
      fetchError = '$error';
    } finally {
      client.close(force: true);
    }
  }

  String _deviceDescription() =>
      '<?xml version="1.0"?>\n'
      '<root xmlns="urn:schemas-upnp-org:device-1-0">\n'
      '  <specVersion><major>1</major><minor>0</minor></specVersion>\n'
      '  <device>\n'
      '    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>\n'
      '    <friendlyName>${_escape(friendlyName)}</friendlyName>\n'
      '    <manufacturer>Susume</manufacturer>\n'
      '    <modelName>Susume Fake Receiver</modelName>\n'
      '    <UDN>$udn</UDN>\n'
      '    <serviceList>\n'
      '      <service>\n'
      '        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>\n'
      '        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>\n'
      '        <controlURL>/upnp/control/AVTransport</controlURL>\n'
      '        <eventSubURL>/upnp/event/AVTransport</eventSubURL>\n'
      '        <SCPDURL>/AVTransport.xml</SCPDURL>\n'
      '      </service>\n'
      '      <service>\n'
      '        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>\n'
      '        <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>\n'
      '        <controlURL>/upnp/control/RenderingControl</controlURL>\n'
      '        <eventSubURL>/upnp/event/RenderingControl</eventSubURL>\n'
      '        <SCPDURL>/RenderingControl.xml</SCPDURL>\n'
      '      </service>\n'
      '    </serviceList>\n'
      '  </device>\n'
      '</root>\n';

  String _soapResponse(
    String service,
    String action,
    Map<String, String> values,
  ) {
    final buffer = StringBuffer()
      ..write('<?xml version="1.0"?>')
      ..write(
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
        's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
      )
      ..write('<s:Body>')
      ..write('<u:${action}Response xmlns:u="$service">');
    for (final entry in values.entries) {
      buffer.write('<${entry.key}>${_escape(entry.value)}</${entry.key}>');
    }
    buffer
      ..write('</u:${action}Response>')
      ..write('</s:Body>')
      ..write('</s:Envelope>');
    return buffer.toString();
  }

  Future<void> _sendFault(HttpResponse response, int code, String description) {
    response.statusCode = HttpStatus.internalServerError;
    return _sendXml(
      response,
      '<?xml version="1.0"?>'
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
      '<s:Body><s:Fault><faultcode>s:Client</faultcode>'
      '<faultstring>UPnPError</faultstring><detail>'
      '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
      '<errorCode>$code</errorCode>'
      '<errorDescription>${_escape(description)}</errorDescription>'
      '</UPnPError></detail></s:Fault></s:Body></s:Envelope>',
    );
  }

  Future<void> _sendXml(HttpResponse response, String body) async {
    response.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');
    final bytes = utf8.encode(body);
    response.contentLength = bytes.length;
    response.add(bytes);
    await response.close();
  }

  /// 从 `SOAPAction` 头取动作名：`"urn:...:service:AVTransport:1#Play"`。
  String _actionOf(HttpRequest request) {
    final header = request.headers.value('SOAPAction') ?? '';
    final cleaned = header.replaceAll('"', '').trim();
    final hash = cleaned.indexOf('#');
    return hash < 0 ? cleaned : cleaned.substring(hash + 1);
  }

  /// 从请求体取参数（按本地名读，SOAP 前缀由调用方定）。
  Map<String, String> _argumentsOf(String body) {
    try {
      final document = XmlDocument.parse(body);
      final elements = document.descendants.whereType<XmlElement>().toList();
      final bodyElement = elements
          .where((element) => element.name.local == 'Body')
          .firstOrNull;
      final action = bodyElement?.childElements.firstOrNull;
      if (action == null) return const {};
      return {
        for (final child in action.childElements)
          child.name.local: child.innerText,
      };
    } catch (_) {
      return const {};
    }
  }

  static Duration? _durationOf(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(':');
    if (parts.length != 3) return null;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) return null;
    return Duration(
      milliseconds: ((hours * 3600 + minutes * 60) * 1000 + seconds * 1000)
          .round(),
    );
  }

  static String _formatDuration(Duration duration) {
    final seconds = duration.inMilliseconds ~/ 1000;
    return '${seconds ~/ 3600}:'
        '${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// 绑 `0.0.0.0` 时对外通告哪个地址：第一个非环回、非链路本地的 IPv4；
  /// 一个都没有（离线开发机）就退到环回——**不空口白话**，也不通告 `0.0.0.0`。
  static Future<InternetAddress> _defaultAdvertisedAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: true,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback || address.isLinkLocal) continue;
          return address;
        }
      }
    } catch (_) {
      // 读不到网卡：退到环回。
    }
    return InternetAddress.loopbackIPv4;
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

/// 在电脑上起一台假接收端，供真机验收时当替代接收端用。
///
/// 用法：`dart run tool/cast_fake_receiver.dart [--name 客厅电视]
/// [--ssdp-port 1900]`。
/// 它会打印设备描述地址与两条控制端点，并把收到的每条 SOAP 指令（动作名 +
/// 请求体）逐条打印出来——核对手机发出的就是那些指令。
Future<void> main(List<String> arguments) async {
  String valueOf(String flag) {
    final index = arguments.indexOf(flag);
    return index >= 0 && index + 1 < arguments.length
        ? arguments[index + 1]
        : '';
  }

  final friendlyName = valueOf('--name').isEmpty
      ? 'Susume 假接收端'
      : valueOf('--name');
  final ssdpPort = int.tryParse(valueOf('--ssdp-port')) ?? 1900;
  final FakeDlnaReceiver receiver;
  try {
    receiver = await FakeDlnaReceiver.start(
      address: InternetAddress.anyIPv4,
      // 手机把 M-SEARCH 发到 well-known 的 1900：起真机验收用的这台时必须
      // 占住它，否则收不到组播搜索。
      ssdpPort: ssdpPort,
      friendlyName: friendlyName,
    );
  } catch (error) {
    stderr
      ..writeln('起不了假接收端：$error')
      ..writeln('UDP 1900 可能已被别的 DLNA/UPnP 服务占用（rygel、minidlna 等）：')
      ..writeln('先停掉它，或用 --ssdp-port 换一个（那时手机也发现不到）。');
    exit(1);
  }

  stdout
    ..writeln('假接收端已起：$friendlyName')
    ..writeln('  设备描述：${receiver.descriptionUrl}')
    ..writeln('  AVTransport 控制端点：${receiver.avTransportControlUrl}')
    ..writeln('  RenderingControl 控制端点：${receiver.renderingControlUrl}')
    ..writeln('  自述支持的动作：${receiver.supportedActions.join(', ')}')
    ..writeln('把手机与这台电脑接到同一个 Wi-Fi，然后在 App 里投屏：')
    ..writeln('手机发现要能到这台机器，「推片」后这里会逐条打印收到的 SOAP 指令。')
    ..writeln('Ctrl-C 退出。');

  var printed = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
    while (printed < receiver.receivedActions.length) {
      final index = printed++;
      stdout
        ..writeln('--- SOAP #${index + 1}: ${receiver.receivedActions[index]}')
        ..writeln(receiver.receivedSoapBodies[index]);
    }
  });

  ProcessSignal.sigint.watch().listen((_) async {
    timer.cancel();
    await receiver.stop();
    exit(0);
  });
}
