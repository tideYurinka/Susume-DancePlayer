/// [CastDeliveryChannel] 的真实实现：在设备 WiFi 地址上起一个**只在会话
/// 期内存在**的局域网 HTTP 服务。
///
/// 只认一个路径（`/cast/<一次性随机串>/<副本文件名>`），其余一律 404——
/// 目录不可枚举、路径猜不到。`Range` 用流式切片满足（接收端要能拖进度），
/// 会话结束 `close(force: true)` 立即停服。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'cast_delivery_channel.dart';
import 'cast_media.dart';

/// 递出服务的绑定地址：`0.0.0.0`（对外通告的地址另取网卡上的那个——见
/// [pickCastLanAddress]）。绑 `0.0.0.0` 而不是那一个地址，是为了网卡地址
/// 在会话期内变化时仍能收连接。
final InternetAddress kCastDeliveryBindAddress = InternetAddress.anyIPv4;

/// 从网卡地址里挑一个**局域网可达**的地址来通告。
///
/// 优先级：非环回、非链路本地的 IPv4（`192.168/10/172.16` 这些）→ 任意
/// IPv4 → 环回。只挑「第一个」是刻意的：投屏与手机同网，一张 WiFi 网卡
/// 的场景占绝大多数；挑错时用户看到的是「接收端拉不到」，而不是静默失败。
InternetAddress pickCastLanAddress(Iterable<InternetAddress> addresses) {
  final ipv4 = addresses
      .where((a) => a.type == InternetAddressType.IPv4)
      .toList();
  for (final address in ipv4) {
    if (address.isLoopback) continue;
    if (address.isLinkLocal) continue;
    return address;
  }
  if (ipv4.isNotEmpty) return ipv4.first;
  return InternetAddress.loopbackIPv4;
}

/// 递出通道的真实实现。
class LanCastDeliveryChannel implements CastDeliveryChannel {
  LanCastDeliveryChannel({
    Future<InternetAddress> Function()? resolveAddress,
    Random? random,
  }) : _resolveAddress = resolveAddress ?? _defaultAddress,
       _random = random ?? Random.secure();

  final Future<InternetAddress> Function() _resolveAddress;
  final Random _random;

  HttpServer? _server;
  String? _host;
  _ServedCastFile? _served;
  bool _closed = false;

  @override
  Future<Uri> serve(File file) async {
    if (_closed) throw const CastDeliveryClosed();
    var server = _server;
    if (server == null) {
      final address = await _resolveAddress();
      server = await HttpServer.bind(kCastDeliveryBindAddress, 0);
      server.listen(_handle);
      _server = server;
      _host = address.address;
    }
    final name = _fileNameOf(file.path);
    _served = _ServedCastFile(
      path: file.absolute.path,
      name: name,
      token: _mintToken(),
    );
    return Uri(
      scheme: 'http',
      host: _host,
      port: server.port,
      pathSegments: ['cast', _served!.token, name],
    );
  }

  @override
  Future<void> close() async {
    _closed = true;
    _served = null;
    final server = _server;
    _server = null;
    _host = null;
    if (server == null) return;
    await server.close(force: true);
  }

  /// 一次请求的收场：路径、方法、文件在场、区间四道门都过了才发字节；**任何
  /// 一道不过都有明确状态码**，读盘与客户端中断都在这里兜住，不让一个坏请求
  /// 带走整个服务。
  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final served = _served;
      if (served == null || !_isServedPath(request.uri, served)) {
        await _empty(response, HttpStatus.notFound);
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
        await _empty(response, HttpStatus.methodNotAllowed);
        return;
      }
      final file = File(served.path);
      if (!await file.exists()) {
        await _empty(response, HttpStatus.notFound);
        return;
      }

      final length = await file.length();
      final range = parseCastRangeHeader(
        request.headers.value(HttpHeaders.rangeHeader),
        length,
      );
      response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(
          HttpHeaders.contentTypeHeader,
          castContentTypeForName(served.name),
        )
        ..set(HttpHeaders.cacheControlHeader, 'no-store');

      switch (range) {
        case CastRangeUnsatisfiable():
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes */$length',
          );
          await _empty(response, HttpStatus.requestedRangeNotSatisfiable);
        case CastRangeAbsent():
          response
            ..statusCode = HttpStatus.ok
            ..contentLength = length;
          if (request.method == 'HEAD') {
            await response.close();
            return;
          }
          await response.addStream(file.openRead());
          await response.close();
        case CastRangeResolved(:final start, :final end):
          response
            ..statusCode = HttpStatus.partialContent
            ..contentLength = range.length
            ..headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-$end/$length',
            );
          if (request.method == 'HEAD') {
            await response.close();
            return;
          }
          await response.addStream(file.openRead(start, end + 1));
          await response.close();
      }
    } catch (_) {
      // 文件在两次读之间被删、客户端掐了连接：尽力收场，服务继续在。
      try {
        await response.close();
      } catch (_) {
        // 连接已经没了。
      }
    }
  }

  /// 请求路径必须**逐段**等于本次递出的那三段：`request.uri.path` 是编码
  /// 过的，路径里带中文或空格的文件名只能按解码后的段比。
  bool _isServedPath(Uri uri, _ServedCastFile served) {
    final segments = uri.pathSegments;
    if (segments.length != served.requestSegments.length) return false;
    for (var i = 0; i < segments.length; i++) {
      if (segments[i] != served.requestSegments[i]) return false;
    }
    return true;
  }

  Future<void> _empty(HttpResponse response, int statusCode) async {
    response.statusCode = statusCode;
    await response.close();
  }

  /// 一次性随机路径段：128 位随机数的 base64url（无填充）——猜不到、不可
  /// 枚举，也不带任何设备或文件名信息。
  String _mintToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String _fileNameOf(String path) {
    final name = p.basename(path);
    return name.isEmpty ? 'cast.mp4' : name;
  }

  static Future<InternetAddress> _defaultAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: true,
      );
      return pickCastLanAddress([
        for (final interface in interfaces) ...interface.addresses,
      ]);
    } catch (_) {
      return InternetAddress.loopbackIPv4;
    }
  }
}

/// 本次递出的那一份：路径、文件名与一次性随机串。
class _ServedCastFile {
  const _ServedCastFile({
    required this.path,
    required this.name,
    required this.token,
  });

  final String path;
  final String name;
  final String token;

  /// 服务只认这**三段**路径（含文件名，接收端按扩展名猜类型）。
  List<String> get requestSegments => ['cast', token, name];
}
