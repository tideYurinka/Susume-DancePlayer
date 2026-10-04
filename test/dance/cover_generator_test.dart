import 'dart:io';

import 'package:dance_learning_app/dance/cover_cache.dart';
import 'package:dance_learning_app/core/cover_frame.dart';
import 'package:dance_learning_app/dance/cover_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 就绪判据（缓存接口只出原子读：图 + 比例），非空即就绪。
Future<bool> _isReady(
  CoverCache cache,
  String videoId,
  Duration position,
) async => await cache.readyCover(videoId, position) != null;

/// 封面生成编排直测：内存替身驱动取帧执行器——成功即
/// 产出缓存文件、失败零副作用且本次会话不再重试同一支舞。
void main() {
  late Directory tempDir;
  late CoverCache cache;
  late _FakeExecutor executor;
  late FfmpegCoverGenerator generator;

  /// 同一套取帧替身上的生成编排（换缓存实现即另一支舞的现场）。
  FfmpegCoverGenerator generatorOver(CoverCache cache) =>
      FfmpegCoverGenerator(cache: cache, executor: executor);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cover_generator_test');
    cache = FileCoverCache(() async => tempDir);
    executor = _FakeExecutor();
    generator = generatorOver(cache);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('取帧成功：按所选时刻装配命令、产物落进缓存', () async {
    executor.result = true;

    expect(
      await generator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: const Duration(seconds: 7),
      ),
      isTrue,
    );

    expect(executor.commands, hasLength(1));
    final args = executor.commands.single;
    expect(args[args.indexOf('-i') + 1], '/videos/v1.mp4');
    // 双 seek：先快进到 5s（7s − 2s），再精确定位 2s。
    expect(args[args.indexOf('-i') - 1], '5.000');
    expect(args[args.lastIndexOf('-ss') + 1], '2.000');
    expect(await _isReady(cache, 'v1', const Duration(seconds: 7)), isTrue);
    expect(await (await cache.fileFor('v1')).readAsString(), 'fake-jpeg');
    // 临时产物不残留。
    expect((await cache.tempFileFor('v1')).existsSync(), isFalse);
  });

  test('缓存目录尚不存在：先备好输出位置再取帧，封面照样就绪', () async {
    final coversDir = Directory('${tempDir.path}/covers');
    final nestedCache = FileCoverCache(() async => coversDir);
    final nestedGenerator = generatorOver(nestedCache);

    expect(
      await nestedGenerator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: Duration.zero,
      ),
      isTrue,
    );

    // 取帧命令执行那一刻，输出位置的父目录已经在（替身缺它即失败）。
    expect(executor.outputParentExisted, [true]);
    expect(await _isReady(nestedCache, 'v1', Duration.zero), isTrue);
  });

  test('建目录失败不算取帧失败：位置恢复后仍能取到封面', () async {
    // 输出位置的父路径被一个同名文件占住 → 建目录必失败（瞬时故障的替身）。
    final blocker = File('${tempDir.path}/blocked')
      ..writeAsStringSync('not a directory');
    final flakyCache = FileCoverCache(
      () async => Directory('${blocker.path}/covers'),
    );
    final flakyGenerator = generatorOver(flakyCache);

    expect(
      await flakyGenerator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: Duration.zero,
      ),
      isFalse,
    );

    // 现场恢复：那一步没起解码进程，不该继承「本次会话不再重试」。
    await blocker.delete();
    expect(
      await flakyGenerator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: Duration.zero,
      ),
      isTrue,
    );
    expect(await _isReady(flakyCache, 'v1', Duration.zero), isTrue);
  });

  test('已就绪：不取帧（重复请求是空操作）', () async {
    final temp = await cache.tempFileFor('v1');
    await temp.parent.create(recursive: true);
    await temp.writeAsString('existing');
    await cache.writeFrom('v1', temp, const Duration(seconds: 3));

    expect(
      await generator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: const Duration(seconds: 3),
      ),
      isTrue,
    );

    expect(executor.commands, isEmpty);
    expect(await (await cache.fileFor('v1')).readAsString(), 'existing');
  });

  test('取帧失败：不缓存失败（未就绪）、无缓存文件、无临时残留', () async {
    executor.result = false;

    expect(
      await generator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: const Duration(seconds: 3),
      ),
      isFalse,
    );

    expect(await _isReady(cache, 'v1', const Duration(seconds: 3)), isFalse);
    expect((await cache.tempFileFor('v1')).existsSync(), isFalse);
  });

  test('执行成功但一帧未写（时刻落在片尾外）：按取不到帧处理，不发布空图', () async {
    // ffmpeg 对越界时刻可以成功返回码结束却不写任何帧。
    executor.result = true;
    executor.writeBytes = false;

    expect(
      await generator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: const Duration(seconds: 999),
      ),
      isFalse,
    );

    expect(await _isReady(cache, 'v1', const Duration(seconds: 999)), isFalse);
    expect((await cache.tempFileFor('v1')).existsSync(), isFalse);
  });

  test('空文件产物同样不算取到帧：未就绪且无临时残留', () async {
    executor.result = true;
    executor.emptyProduct = true;

    expect(
      await generator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: const Duration(seconds: 999),
      ),
      isFalse,
    );

    expect(await _isReady(cache, 'v1', const Duration(seconds: 999)), isFalse);
    expect((await cache.tempFileFor('v1')).existsSync(), isFalse);
  });

  test('会话内不再重试同一支舞；另一支舞照常尝试', () async {
    executor.result = false;

    await generator.generate(
      videoId: 'v1',
      sourcePath: '/videos/v1.mp4',
      position: Duration.zero,
    );
    await generator.generate(
      videoId: 'v1',
      sourcePath: '/videos/v1.mp4',
      position: const Duration(seconds: 1),
    );
    await generator.generate(
      videoId: 'v2',
      sourcePath: '/videos/v2.mp4',
      position: const Duration(seconds: 1),
    );

    // v1 只试过一次；v2 试过一次（失败也是各自一次）。
    expect(executor.commands, hasLength(2));
  });

  test('成功之后不再取帧：同位置重开页面不重算（就绪即短路）', () async {
    executor.result = true;

    await generator.generate(
      videoId: 'v1',
      sourcePath: '/videos/v1.mp4',
      position: const Duration(seconds: 3),
    );
    await generator.generate(
      videoId: 'v1',
      sourcePath: '/videos/v1.mp4',
      position: const Duration(seconds: 3),
    );

    expect(executor.commands, hasLength(1));
  });

  test('封面位置改了（首线跟随变化 / 换封面）：旧图不算就绪，按新位置重取', () async {
    executor.result = true;

    await generator.generate(
      videoId: 'v1',
      sourcePath: '/videos/v1.mp4',
      position: const Duration(seconds: 3),
    );
    expect(
      await generator.generate(
        videoId: 'v1',
        sourcePath: '/videos/v1.mp4',
        position: const Duration(seconds: 9),
      ),
      isTrue,
    );

    expect(executor.commands, hasLength(2));
    // 新图确实落在新位置：按旧位置看不再就绪、按新位置看就绪。
    expect(await _isReady(cache, 'v1', const Duration(seconds: 3)), isFalse);
    expect(await _isReady(cache, 'v1', const Duration(seconds: 9)), isTrue);
  });
}

class _FakeExecutor implements CoverFrameExecutor {
  bool result = true;

  /// 成功返回但一帧不写（模拟越界时刻：ffmpeg 返回码 0、无产物）。
  bool writeBytes = true;

  /// 成功返回但写一个空文件。
  bool emptyProduct = false;

  final List<List<String>> commands = [];

  /// 每次执行时输出位置的父目录是否存在（与真实 ffmpeg 同款的硬前提）。
  final List<bool> outputParentExisted = [];

  @override
  Future<bool> execute(List<String> arguments) async {
    commands.add(arguments);
    if (!result) return false;
    // 取帧产物：命令末元素是输出路径（与真实 ffmpeg 命令同构）。ffmpeg
    // 不自建输出目录：父目录不存在即以非成功返回码结束、一帧不写。
    final output = File(arguments.last);
    outputParentExisted.add(output.parent.existsSync());
    if (!output.parent.existsSync()) return false;
    if (!writeBytes) return true;
    await output.writeAsString(emptyProduct ? '' : 'fake-jpeg');
    return true;
  }
}
