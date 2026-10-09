import 'dart:io';

import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/persistence/index_file_provider.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    CastRenderResolution resolution = CastRenderResolution.p1080,
    CastRenderSettings settings = const CastRenderSettings(),
    String annotationFingerprint = 'fp-1',
  }) => CastRenderRequest(
    videoPath: videoPath,
    videoId: videoId,
    duration: const Duration(seconds: 60),
    choices: choices,
    speedTier: speedTier,
    resolution: resolution,
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

  test('降级与不降级不互相命中：分辨率档是键的一维', () async {
    final source = request();
    final downgraded = request(resolution: CastRenderResolution.p720);
    final part = await cache.partFileFor(source);
    File(part.path).writeAsStringSync('rendered');
    final stored = await cache.promote(part, source);

    expect((await cache.find(source))?.path, stored.path);
    expect(
      await cache.find(downgraded),
      isNull,
      reason: '保证档渲的那一份不该被降级请求命中（同一支舞、同一勾选、同一倍速档）',
    );
    expect(
      (await cache.partFileFor(downgraded)).path,
      isNot(part.path),
      reason: '两份各占各的键目录',
    );
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

  group('占用账', () {
    test('占用 = 缓存区里真实字节和（产物与半成品都算）；没渲过 = 0', () async {
      expect(await cache.usageBytes(), 0, reason: '缓存区还没建就是零占用');

      final product = await cache.productFileFor(request(videoId: 'vid-a'));
      product.writeAsBytesSync(List.filled(1000, 1));
      final part = await cache.partFileFor(request(videoId: 'vid-b'));
      part.writeAsBytesSync(List.filled(76, 2));

      expect(await cache.usageBytes(), 1076);
    });

    test('清空：缓存区里的东西全删（产物、半成品、孤儿），占用归零；幂等', () async {
      await cache.clear(); // 缓存区还没建：空操作

      final product = await cache.productFileFor(request(videoId: 'vid-a'));
      product.writeAsBytesSync(List.filled(1000, 1));
      final part = await cache.partFileFor(request(videoId: 'vid-b'));
      part.writeAsBytesSync(List.filled(76, 2));
      File(p.join(root.path, 'orphan.tmp')).writeAsStringSync('来源不明');

      await cache.clear();

      expect(await cache.usageBytes(), 0);
      expect(await cache.find(request(videoId: 'vid-a')), isNull);
      expect(root.listSync(), isEmpty, reason: '缓存区里一件不剩');
      await cache.clear(); // 再清一次是空操作
    });

    test('清空不动标注与设置：两份文档与设备级设置逐字节不变', () async {
      final support = Directory(p.join(root.path, 'support'))..createSync();
      final cacheDirectory = Directory(p.join(support.path, 'cast_render'));
      final container = ProviderContainer(
        overrides: [
          castRenderCacheDirectoryProvider.overrideWithValue(
            () async => cacheDirectory,
          ),
          importIndexFileProvider.overrideWithValue(
            Future.value(File(p.join(support.path, 'index.json'))),
          ),
          privateJsonFileProvider.overrideWithValue(
            Future.value(File(p.join(support.path, 'global_private.json'))),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 这支舞的标注（公开标记文件 + 本地文档）与设备级设置先落盘。
      final documents = container.read(videoDocumentStorageFactoryProvider)(
        'vid-a',
      );
      await documents.saveMarkers({
        'version': 9,
        'meta': {'coverPositionMs': 42000},
      });
      await documents.saveLocal({
        'version': 3,
        'prefs': {'mirror': true},
      });
      await container.read(privateJsonStorageProvider).write({
        'mirrorDefault': true,
        'prepBeats': {'delayedPlay': 4},
      });

      // 缓存区里有一份投屏副本（生产路径经 provider 取缓存）。
      final cache = container.read(castRenderCacheProvider);
      final product = await cache.productFileFor(request(videoId: 'vid-a'));
      product.writeAsBytesSync(List.filled(1000, 1));
      expect(await cache.usageBytes(), 1000);

      final before = {
        for (final name in [
          'markers_vid-a.json',
          'local_vid-a.json',
          'global_private.json',
        ])
          name: File(p.join(support.path, name)).readAsBytesSync(),
      };
      expect(before.length, 3, reason: '三份文件都该先落在盘上');

      await cache.clear();

      expect(await cache.usageBytes(), 0);
      for (final entry in before.entries) {
        expect(
          File(p.join(support.path, entry.key)).readAsBytesSync(),
          entry.value,
          reason: '${entry.key} 不该被清缓存动到',
        );
      }
    });
  });

  group('容量上限与淘汰', () {
    /// 落定一份 [bytes] 字节的产物（走上限收紧同一条路：promote）。
    Future<void> settle(
      CastRenderCache target,
      String videoId,
      int bytes,
    ) async {
      final req = request(videoId: videoId);
      final part = await target.partFileFor(req);
      part.writeAsBytesSync(List.filled(bytes, 1));
      await target.promote(part, req);
    }

    test('超限即按最近使用淘汰：只留得下最新一份时，前两份在各自落定后就被淘汰', () async {
      // 上限 1500：一份 1000 字节的产物放得下，两份放不下。
      final limited = CastRenderCache(
        directory: () async => root,
        limitBytes: 1500,
      );

      await settle(limited, 'vid-a', 1000);
      await settle(limited, 'vid-b', 1000);
      await settle(limited, 'vid-c', 1000);

      expect(await limited.find(request(videoId: 'vid-a')), isNull);
      expect(await limited.find(request(videoId: 'vid-b')), isNull);
      expect(
        await limited.find(request(videoId: 'vid-c')),
        isNotNull,
        reason: '刚落定的那一份是新渲出来的，不能被自己挤掉',
      );
      expect(await limited.usageBytes(), lessThanOrEqualTo(1500));
    });

    test('缓存区根上的残渣也算占用：超限先清残渣，不动用得到的产物', () async {
      // 上限 2500：a（1000）+ 残渣（600）+ 落定的 b（1000）= 2600 超限，但清掉
      // 残渣就回到上限以内——两把键的产物都该留下。
      final limited = CastRenderCache(
        directory: () async => root,
        limitBytes: 2500,
      );
      await settle(limited, 'vid-a', 1000);
      final orphan = File(p.join(root.path, 'orphan.tmp'))
        ..writeAsBytesSync(List.filled(600, 3));
      expect(await limited.usageBytes(), 1600);

      await settle(limited, 'vid-b', 1000);

      expect(orphan.existsSync(), isFalse, reason: '不属于任何一把键的残渣先走');
      expect(await limited.find(request(videoId: 'vid-a')), isNotNull);
      expect(await limited.find(request(videoId: 'vid-b')), isNotNull);
      expect(await limited.usageBytes(), 2000);
    });

    test('单份比上限还大：宁可超限也不删刚渲好的那一份', () async {
      final limited = CastRenderCache(
        directory: () async => root,
        limitBytes: 500,
      );

      await settle(limited, 'vid-a', 1000);

      expect(await limited.find(request(videoId: 'vid-a')), isNotNull);
      expect(await limited.usageBytes(), 1000, reason: '一份也删不得时如实超限');
    });

    test('用过一次的排在后面：「最近使用」刷新后，淘汰落在最久没用过的那份身上', () async {
      // 上限 3500：三份 1000 字节都放得下，第四份落定才超限。
      final limited = CastRenderCache(
        directory: () async => root,
        limitBytes: 3500,
      );
      await settle(limited, 'vid-a', 1000);
      await settle(limited, 'vid-b', 1000);
      await settle(limited, 'vid-c', 1000);

      // 把「最近使用时间」拉开（三次落定可能同在一毫秒里）。
      Future<void> usedAt(String videoId, DateTime at) async {
        final product = await limited.productFileFor(request(videoId: videoId));
        product.setLastModifiedSync(at);
      }

      final base = DateTime(2020, 1, 1);
      await usedAt('vid-a', base);
      await usedAt('vid-b', base.add(const Duration(minutes: 1)));
      await usedAt('vid-c', base.add(const Duration(minutes: 2)));

      // a 刚被用过（命中缓存投了一次）：它的最近使用时间跳到最前。
      await limited.markUsed(request(videoId: 'vid-a'));

      await settle(limited, 'vid-d', 1000);

      expect(
        await limited.find(request(videoId: 'vid-b')),
        isNull,
        reason: '最久没用过的是 b，不是刚用过一次的 a',
      );
      expect(await limited.find(request(videoId: 'vid-a')), isNotNull);
      expect(await limited.find(request(videoId: 'vid-c')), isNotNull);
      expect(await limited.find(request(videoId: 'vid-d')), isNotNull);
    });

    test('没用过的键记一次使用是空操作：不建目录、不动占用', () async {
      final limited = CastRenderCache(
        directory: () async => root,
        limitBytes: 1500,
      );

      await limited.markUsed(request(videoId: 'vid-never'));

      expect(await limited.usageBytes(), 0);
      expect(root.listSync(), isEmpty);
    });
  });
}
