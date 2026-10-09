import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/lan_cast_delivery_channel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 递出通道：本机只在**投屏会话期内**为这一个文件开一个局域网可达的 HTTP
/// 服务。区间解析是纯件；HTTP 行为跑真实 `HttpServer` + 环回 `HttpClient`，
/// 只断言外部可观察的结果（状态码、头、字节、停服后连不上）——沿更新网关
/// 那套真实网络的既有做法。
/// 停服之后客户端的可观察结局：连接被拒（`SocketException`）或在读到头之前
/// 被掐（`HttpException`）——两者都是「这台服务不在了」。
final refusesConnection = throwsA(
  anyOf(isA<SocketException>(), isA<HttpException>()),
);

void main() {
  group('Range 头解析', () {
    test('没有 Range / 不认的写法：整份发', () {
      for (final header in [
        null,
        '',
        'items=0-1',
        'bytes=',
        'bytes=0-1,5-6',
        'bytes=abc-def',
        'bytes=5-2',
      ]) {
        expect(
          parseCastRangeHeader(header, 1000),
          isA<CastRangeAbsent>(),
          reason: '输入：$header',
        );
      }
    });

    test('单区间三种写法解析成闭区间', () {
      expect(
        parseCastRangeHeader('bytes=0-99', 1000),
        const CastRangeResolved(start: 0, end: 99),
      );
      expect(
        parseCastRangeHeader('bytes=100-', 1000),
        const CastRangeResolved(start: 100, end: 999),
      );
      expect(
        parseCastRangeHeader('bytes=-100', 1000),
        const CastRangeResolved(start: 900, end: 999),
      );
      expect(
        parseCastRangeHeader('bytes=5-5', 1000),
        const CastRangeResolved(start: 5, end: 5),
      );
    });

    test('末端越界钳到文件尾；后缀长度超过整份就是整份', () {
      expect(
        parseCastRangeHeader('bytes=0-99999', 1000),
        const CastRangeResolved(start: 0, end: 999),
      );
      expect(
        parseCastRangeHeader('bytes=-5000', 1000),
        const CastRangeResolved(start: 0, end: 999),
      );
    });

    test('真正越界的才回 416：起点在文件之外、后缀为 0、空文件上的区间', () {
      expect(
        parseCastRangeHeader('bytes=1000-', 1000),
        isA<CastRangeUnsatisfiable>(),
      );
      expect(
        parseCastRangeHeader('bytes=1000-2000', 1000),
        isA<CastRangeUnsatisfiable>(),
      );
      expect(
        parseCastRangeHeader('bytes=-0', 1000),
        isA<CastRangeUnsatisfiable>(),
      );
      expect(
        parseCastRangeHeader('bytes=0-', 0),
        isA<CastRangeUnsatisfiable>(),
      );
    });
  });

  group('真实环回服务', () {
    late Directory baseDirectory;
    late File video;
    late LanCastDeliveryChannel channel;
    late HttpClient client;
    final payload = List<int>.generate(4096, (i) => i % 251);

    setUp(() async {
      baseDirectory = await Directory.systemTemp.createTemp('cast_delivery');
      video = File(p.join(baseDirectory.path, '客厅 舞&a.mp4'));
      await video.writeAsBytes(payload);
      channel = LanCastDeliveryChannel(
        resolveAddress: () async => InternetAddress.loopbackIPv4,
      );
      client = HttpClient();
    });

    tearDown(() async {
      await channel.close();
      client.close(force: true);
      if (baseDirectory.existsSync()) {
        await baseDirectory.delete(recursive: true);
      }
    });

    Future<HttpClientResponse> get(Uri url, {String? range}) async {
      final request = await client.getUrl(url);
      if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
      return request.close();
    }

    Future<List<int>> bodyOf(HttpClientResponse response) =>
        response.fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));

    test('递出地址指向本机地址与一次性随机路径，整份 GET 拿得到全部字节', () async {
      final url = await channel.serve(video);

      expect(url.scheme, 'http');
      expect(url.host, '127.0.0.1');
      expect(url.pathSegments, hasLength(3));
      expect(url.pathSegments.first, 'cast');
      expect(url.pathSegments.last, '客厅 舞&a.mp4');
      expect(
        url.pathSegments[1].length,
        greaterThanOrEqualTo(20),
        reason: '一次性随机串；路径不可枚举也猜不到',
      );

      final response = await get(url);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
      expect(
        response.headers.contentType?.mimeType,
        'video/mp4',
        reason: '接收端按 Content-Type 决定认不认这份片子',
      );
      expect(await bodyOf(response), payload);
    });

    test('Range 请求回 206 与切片：起点区间、开口区间、后缀区间都对', () async {
      final url = await channel.serve(video);

      final middle = await get(url, range: 'bytes=100-199');
      expect(middle.statusCode, HttpStatus.partialContent);
      expect(
        middle.headers.value(HttpHeaders.contentRangeHeader),
        'bytes 100-199/${payload.length}',
      );
      expect(await bodyOf(middle), payload.sublist(100, 200));

      final open = await get(url, range: 'bytes=4000-');
      expect(open.statusCode, HttpStatus.partialContent);
      expect(await bodyOf(open), payload.sublist(4000));

      final suffix = await get(url, range: 'bytes=-16');
      expect(suffix.statusCode, HttpStatus.partialContent);
      expect(await bodyOf(suffix), payload.sublist(payload.length - 16));
    });

    test('越界 Range 回 416 并带上总长', () async {
      final url = await channel.serve(video);

      final response = await get(url, range: 'bytes=99999-');

      expect(response.statusCode, HttpStatus.requestedRangeNotSatisfiable);
      expect(
        response.headers.value(HttpHeaders.contentRangeHeader),
        'bytes */${payload.length}',
      );
      await response.drain<void>();
    });

    test('HEAD 只回头不回字节（接收端探测用）', () async {
      final url = await channel.serve(video);

      final request = await client.headUrl(url);
      final response = await request.close();

      expect(response.statusCode, HttpStatus.ok);
      expect(response.contentLength, payload.length);
      expect(await bodyOf(response), isEmpty);
    });

    test('路径一次性且不可枚举：只有那三段路径能拿到东西', () async {
      final url = await channel.serve(video);
      final token = url.pathSegments[1];

      for (final other in [
        Uri.parse('http://127.0.0.1:${url.port}/'),
        Uri.parse('http://127.0.0.1:${url.port}/cast'),
        Uri.parse('http://127.0.0.1:${url.port}/cast/'),
        Uri.parse('http://127.0.0.1:${url.port}/$token/客厅 舞&a.mp4'),
        Uri.parse('http://127.0.0.1:${url.port}/cast/另一串/客厅 舞&a.mp4'),
        Uri.parse('http://127.0.0.1:${url.port}/cast/$token/别的.mp4'),
      ]) {
        final response = await get(other);
        expect(
          response.statusCode,
          HttpStatus.notFound,
          reason: '这个路径不该有东西：$other',
        );
        await response.drain<void>();
      }
    });

    test('再递一份就换新路径：旧路径立刻失效', () async {
      final first = await channel.serve(video);
      final second = await channel.serve(video);

      expect(second.pathSegments[1], isNot(first.pathSegments[1]));
      final old = await get(first);
      expect(old.statusCode, HttpStatus.notFound);
      await old.drain<void>();
      final fresh = await get(second);
      expect(fresh.statusCode, HttpStatus.ok);
      await fresh.drain<void>();
    });

    test('会话结束立即停服：连不上，重复停服是空操作', () async {
      final url = await channel.serve(video);
      expect((await get(url)).statusCode, HttpStatus.ok);

      await channel.close();
      await channel.close();

      await expectLater(get(url), refusesConnection);
    });

    test('异常路径：文件在会话中被删 → 404，服务还在，收尾仍能停服', () async {
      final url = await channel.serve(video);
      await video.delete();

      final gone = await get(url);
      expect(gone.statusCode, HttpStatus.notFound);
      await gone.drain<void>();

      await channel.close();
      await expectLater(get(url), refusesConnection);
    });

    test('异常路径：下载中途停服不挂住（在飞连接被强断）', () async {
      final big = File(p.join(baseDirectory.path, 'big.mp4'));
      await big.writeAsBytes(List<int>.filled(8 * 1024 * 1024, 7));
      final url = await channel.serve(big);

      final response = await get(url);
      expect(response.statusCode, HttpStatus.ok);
      // 不读正文直接停服：close 必须自己回来，不等在飞连接。
      await channel.close().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('停服被在飞连接挂住'),
      );

      client.close(force: true);
    });

    test('停服后再要地址：抛 CastDeliveryClosed，不静默重开', () async {
      await channel.serve(video);
      await channel.close();

      await expectLater(
        channel.serve(video),
        throwsA(isA<CastDeliveryClosed>()),
      );
    });
  });

  group('本机地址挑选', () {
    test('优先非环回非链路本地的 IPv4', () {
      expect(
        pickCastLanAddress([
          InternetAddress('127.0.0.1'),
          InternetAddress('169.254.3.4'),
          InternetAddress('192.168.1.7'),
        ]).address,
        '192.168.1.7',
      );
    });

    test('只有环回就退到环回；一个 IPv4 都没有也退到环回（宁可本机也不空口白话）', () {
      expect(
        pickCastLanAddress([InternetAddress('127.0.0.1')]).address,
        '127.0.0.1',
      );
      expect(pickCastLanAddress([]).address, '127.0.0.1');
      expect(
        pickCastLanAddress([InternetAddress('fe80::1')]).address,
        '127.0.0.1',
      );
    });
  });
}
