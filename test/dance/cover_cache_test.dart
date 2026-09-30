import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/core/cover_frame.dart'
    show kCoverPlaceholderAspectRatio;
import 'package:dance_learning_app/dance/cover_cache.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/jpeg_bytes.dart';

/// 封面缓存存取直测：写入为同名原子替换、删除随舞、
/// 缺失或**生成位置与当前位置不一致**即未就绪。真实临时目录里的真实文件
/// ——「文件真在/真被换掉/位置真被记下」是外部可观察行为。
void main() {
  late Directory tempDir;
  late CoverCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cover_cache_test');
    cache = FileCoverCache(() async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// 就绪判据：缓存接口只出原子读（图 + 比例），非空即就绪。
  Future<bool> isReady(String videoId, Duration position) async =>
      await cache.readyCover(videoId, position) != null;

  Future<File> seed(
    String videoId,
    List<int> bytes, {
    Duration position = Duration.zero,
  }) async {
    final temp = await cache.tempFileFor(videoId);
    await temp.parent.create(recursive: true);
    await temp.writeAsBytes(bytes);
    await cache.writeFrom(videoId, temp, position);
    return cache.fileFor(videoId);
  }

  /// 文本产物（非 JPEG）走同一写入路径。
  Future<File> seedText(
    String videoId,
    String bytes, {
    Duration position = Duration.zero,
  }) => seed(videoId, utf8.encode(bytes), position: position);

  test('缺失即未就绪；写入后立即可用', () async {
    expect(await isReady('v1', Duration.zero), isFalse);

    await seedText('v1', 'first-image');

    expect(await isReady('v1', Duration.zero), isTrue);
    expect(await (await cache.fileFor('v1')).readAsString(), 'first-image');
  });

  test('同一支舞写入是同名替换：旧图消失、只剩一份图与位置标记、无临时残留', () async {
    final first = await seedText('v1', 'first-image');
    expect(File('${first.path}.tmp').existsSync(), isFalse);

    final second = await seedText('v1', 'second-image');

    expect(await second.readAsString(), 'second-image');
    expect(
      tempDir.listSync().map((e) => p.basename(e.path)).toList()..sort(),
      ['cover_v1.jpg', 'cover_v1.jpg.position'],
    );
    expect(await isReady('v2', Duration.zero), isFalse);
  });

  test('首线一改：位置变了旧图不再算就绪，同位置仍是就绪', () async {
    await seedText('v1', 'image', position: const Duration(seconds: 10));

    expect(await isReady('v1', const Duration(seconds: 10)), isTrue);
    expect(await isReady('v1', const Duration(seconds: 30)), isFalse);
    expect(await isReady('v1', Duration.zero), isFalse);
  });

  test('删除随舞：该舞图片、位置标记与临时残留一并清除，别的舞不受影响', () async {
    await seedText('v1', 'one');
    await seedText('v2', 'two');
    final staleTemp = await cache.tempFileFor('v1');
    await staleTemp.writeAsString('half-written');

    await cache.deleteFor('v1');

    expect(await isReady('v1', Duration.zero), isFalse);
    expect(await staleTemp.exists(), isFalse);
    expect(
      tempDir.listSync().map((e) => p.basename(e.path)).toList()..sort(),
      ['cover_v2.jpg', 'cover_v2.jpg.position'],
    );
    expect(await isReady('v2', Duration.zero), isTrue);
  });

  test('删除不存在的舞：视作已清、不抛错', () async {
    await cache.deleteFor('missing');

    expect(await isReady('missing', Duration.zero), isFalse);
  });

  test('取帧产物缺失：写入失败且不产生缓存文件（保持未就绪）', () async {
    final missingProduct = File(p.join(tempDir.path, 'never-written.jpg'));

    expect(
      await cache.writeFrom('v1', missingProduct, Duration.zero),
      isFalse,
    );
    expect(await isReady('v1', Duration.zero), isFalse);
  });

  test('就绪比例按图片自身头部给出：竖屏 3:4、横屏 4:3；未就绪/位置不符不出现', () async {
    await seed('v1', fakeJpegBytes(width: 540, height: 720));
    await seed(
      'v2',
      fakeJpegBytes(width: 720, height: 540),
      position: const Duration(seconds: 5),
    );

    final covers = await cache.readyCovers({
      'v1': Duration.zero,
      'v2': const Duration(seconds: 5),
      // v3 没有缓存；v2 换个位置即旧图不算数。
      'v3': Duration.zero,
      'v4': const Duration(seconds: 9),
    });

    expect(covers.keys, unorderedEquals(['v1', 'v2']));
    expect(covers['v1'], closeTo(3 / 4, 1e-9));
    expect(covers['v2'], closeTo(4 / 3, 1e-9));
    expect(
      await cache.readyCovers({'v2': const Duration(seconds: 6)}),
      isEmpty,
    );
  });

  test('就绪但头部不可解：仍算就绪，比例按竖屏 3:4 兜底', () async {
    await seedText('v1', 'not-a-jpeg');

    expect(await cache.readyCovers({'v1': Duration.zero}), {
      'v1': kCoverPlaceholderAspectRatio,
    });
  });

  test('单舞原子读：一次返回图与自身比例；未就绪 / 位置不符为 null', () async {
    expect(await cache.readyCover('v1', Duration.zero), isNull);

    await seed('v1', fakeJpegBytes(width: 720, height: 540));

    final ready = await cache.readyCover('v1', Duration.zero);
    expect(ready, isNotNull);
    expect(ready!.file.path, (await cache.fileFor('v1')).path);
    expect(ready.aspectRatio, closeTo(4 / 3, 1e-9));
    // 位置变了旧图不再算就绪。
    expect(await cache.readyCover('v1', const Duration(seconds: 5)), isNull);
  });
}
