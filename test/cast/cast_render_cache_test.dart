import 'dart:io';

import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 投屏缓存账直测：**键 → 一份产物**、命中不重渲、落定是原子换名、半成品
/// 不留在盘上。用真实临时目录测（沿分享包测试的既有做法）。
void main() {
  late Directory root;
  late CastRenderCache cache;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cast_render_cache_test');
    cache = CastRenderCache(directory: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  CastRenderRequest request({
    String videoId = 'vid-a',
    String videoPath = '/videos/客厅练习.mp4',
    CastRenderChoices choices = const CastRenderChoices(
      picture: false,
      sound: true,
    ),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastRenderSettings settings = const CastRenderSettings(),
    String annotationFingerprint = 'fp-1',
  }) => CastRenderRequest(
    videoPath: videoPath,
    videoId: videoId,
    duration: const Duration(seconds: 60),
    choices: choices,
    speedTier: speedTier,
    settings: settings,
    annotationFingerprint: annotationFingerprint,
  );

  test('没渲过 = 未命中；只问命中不写盘', () async {
    expect(await cache.find(request()), isNull);
    expect(root.listSync(), isEmpty, reason: '只问命中不落任何文件');
  });

  test('落定后命中同一份文件；键换一分量就换一份产物', () async {
    final part = await cache.partFileFor(request());
    File(part.path).writeAsStringSync('rendered');
    final stored = await cache.promote(part, request());

    expect(File(stored.path).existsSync(), isTrue);
    expect((await cache.find(request()))?.path, stored.path);

    final other = request(videoId: 'vid-b');
    expect(await cache.find(other), isNull, reason: '换了视频标识不该命中上一支舞的产物');
    expect((await cache.partFileFor(other)).path, isNot(part.path));
  });

  test('半成品与产物不同名：崩在中途不会被当成命中', () async {
    final part = await cache.partFileFor(request());
    File(part.path)
      ..createSync(recursive: true)
      ..writeAsStringSync('half');

    expect(await cache.find(request()), isNull, reason: '半成品不是产物');
    expect(
      p.basename(part.path),
      isNot(p.basename((await cache.productFileFor(request())).path)),
    );
  });

  test('promote 之后半成品不再存在（换名，不是复制）', () async {
    final part = await cache.partFileFor(request());
    File(part.path).writeAsStringSync('rendered');
    final stored = await cache.promote(part, request());

    expect(File(part.path).existsSync(), isFalse);
    expect(File(stored.path).readAsStringSync(), 'rendered');
  });

  test('discard 删掉半成品；文件不在也是空操作', () async {
    final part = await cache.partFileFor(request());
    File(part.path).writeAsStringSync('half');

    await cache.discard(part);
    expect(File(part.path).existsSync(), isFalse);
    await cache.discard(part); // 幂等
    await cache.discard(File(p.join(root.path, 'never.mp4')));
  });

  test('键落在目录名上：定长十六进制、不含路径分隔符与键里的任意字符', () async {
    final product = await cache.productFileFor(
      request(annotationFingerprint: 'a/b:c#d'),
    );
    final directoryName = p.basename(p.dirname(product.path));

    expect(directoryName, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(directoryName, isNot(contains('#')));
  });

  test('产物名沿用源片名：电视上看到的是舞名，不是一个摘要', () async {
    final product = await cache.productFileFor(
      request(videoPath: '/videos/客厅练习.mp4'),
    );

    expect(p.basename(product.path), '客厅练习.mp4');
  });

  test('不同键各自一份目录，互不覆盖', () async {
    final a = await cache.productFileFor(request());
    final b = await cache.productFileFor(request(videoId: 'vid-b'));

    expect(p.dirname(a.path), isNot(p.dirname(b.path)));
    expect(p.basename(a.path), p.basename(b.path));
  });

  test('目录解析失败在读取时抛出，不在建对象时（缓存不阻塞界面构建）', () async {
    final failing = CastRenderCache(
      directory: () async => throw const FileSystemException('no dir'),
    );
    expect(failing, isNotNull);
    await expectLater(
      failing.find(request()),
      throwsA(isA<FileSystemException>()),
    );
  });
}
