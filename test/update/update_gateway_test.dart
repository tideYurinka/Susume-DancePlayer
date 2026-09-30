import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/update/platform_update_gateway.dart';
import 'package:dance_learning_app/update/update_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 更新网关的网络请求形状与下载行为：清单
/// 地址是 HTTPS 且指向本项目自定义域；请求除一个时间戳查询串外零参数。下载
/// 与取消跑真实 `HttpClient` + 本地 `HttpServer`，只断言外部可观察的结果——
/// 包落在给定目录、进度报到位、取消后目录里没有半成品。安装请求通道的转发形
/// 状另见 `platform_install_channel_test.dart`（那里要起 test binding，而
/// test binding 会让本文件的真实网络请求返回 400）。
void main() {
  late Directory baseDirectory;

  setUp(() async {
    baseDirectory = await Directory.systemTemp.createTemp('update_gateway_test');
  });

  tearDown(() async {
    if (baseDirectory.existsSync()) await baseDirectory.delete(recursive: true);
  });

  File targetFile() =>
      File(p.join(baseDirectory.path, updateApkFileName));

  test('清单地址是 HTTPS 且指向本项目的自定义域', () {
    expect(updateManifestUrl.scheme, 'https');
    expect(updateManifestUrl.host, 'dl.yurinka.top');
    expect(updateManifestUrl.path, '/latest.json');
  });

  test('清单请求只多一个时间戳查询串，没有别的参数', () {
    final uri = updateManifestRequestUri(
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    expect(uri.queryParameters, {'t': '1700000000000'});
    expect(uri.fragment, isEmpty);
    expect(uri.userInfo, isEmpty);
  });

  test('下载把包整份写进给定目录，并逐段报出进度', () async {
    final payload = List<int>.generate(200000, (i) => i % 251);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..contentLength = payload.length
        ..add(payload);
      unawaited(request.response.close());
    });
    addTearDown(() => server.close(force: true));

    final gateway = PlatformUpdateGateway(
      resolveBaseDirectory: () async => baseDirectory,
    );
    final progress = <(int, int)>[];
    final savedPath = await gateway.downloadApk(
      url: 'http://127.0.0.1:${server.port}/susume.apk',
      onProgress: (received, total) => progress.add((received, total)),
    );

    expect(savedPath, targetFile().path, reason: '下载完成返回安装包落点');
    expect(await targetFile().readAsBytes(), payload);
    expect(progress, isNotEmpty, reason: '下载过程要报进度');
    expect(progress.last.$1, payload.length, reason: '最后一段是整包');
    expect(progress.last.$2, payload.length, reason: '总长取自响应');
  });

  test('开始新下载前清掉上一个包：失败时也不留旧包', () async {
    await targetFile().writeAsBytes(List<int>.filled(16, 9));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.statusCode = HttpStatus.notFound;
      unawaited(request.response.close());
    });
    addTearDown(() => server.close(force: true));

    final gateway = PlatformUpdateGateway(
      resolveBaseDirectory: () async => baseDirectory,
    );

    await expectLater(
      gateway.downloadApk(
        url: 'http://127.0.0.1:${server.port}/missing.apk',
        onProgress: (_, _) {},
      ),
      throwsA(isA<UpdateDownloadException>()),
    );
    expect(await targetFile().exists(), isFalse, reason: '失败的下载不留半成品/旧包');
  });

  test('下载中取消：等半成品被删掉才返回', () async {
    final firstProgress = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = 100000000;
        for (var i = 0; i < 100; i++) {
          request.response.add(List<int>.filled(100000, 7));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await request.response.close();
      } catch (_) {
        // 客户端取消后连接被强关：服务端侧的正常收场。
      }
    });
    addTearDown(() => server.close(force: true));

    final gateway = PlatformUpdateGateway(
      resolveBaseDirectory: () async => baseDirectory,
    );
    final download = gateway.downloadApk(
      url: 'http://127.0.0.1:${server.port}/susume.apk',
      onProgress: (_, _) {
        if (!firstProgress.isCompleted) firstProgress.complete();
      },
    );
    final expectation = expectLater(
      download,
      throwsA(isA<UpdateDownloadCancelled>()),
    );

    await firstProgress.future;
    await gateway.cancelDownload();

    await expectation;
    expect(
      await targetFile().exists(),
      isFalse,
      reason: '取消后目录里没有半成品',
    );
  });
}
