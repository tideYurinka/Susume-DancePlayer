import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/core/cover_frame.dart';
import 'package:dance_learning_app/dance/cover_cache.dart';
import 'package:dance_learning_app/dance/cover_generation_queue.dart';
import 'package:dance_learning_app/dance/cover_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 封面取帧队列直测：可见优先次序、并发上限、同一支舞
/// 只取一次、失败本会话不重试。用真实生成编排 + 内存执行器替身驱动——断言
/// 外部可观察的命令次序与结果，不看队列内部。
void main() {
  late Directory tempDir;
  late CoverCache cache;
  late _BlockingExecutor executor;
  late CoverGenerationQueue queue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cover_queue_test');
    cache = FileCoverCache(() async => tempDir);
    executor = _BlockingExecutor();
    final generator = FfmpegCoverGenerator(cache: cache, executor: executor);
    queue = CoverGenerationQueue(
      run: (request) => generator.generate(
        videoId: request.videoId,
        sourcePath: request.sourcePath,
        position: request.position,
      ),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  CoverFrameRequest request(String videoId) => (
    videoId: videoId,
    sourcePath: '/videos/$videoId.mp4',
    position: const Duration(seconds: 3),
  );

  test('可见优先次序 + 并发上限：同时最多两条，先入队的先取', () async {
    final results = [
      queue.request(request('v1')),
      queue.request(request('v2')),
      queue.request(request('v3')),
    ];
    await _settleIo();

    // 只有前两条真的起了解码进程；第三条在排队。
    expect(executor.started, ['/videos/v1.mp4', '/videos/v2.mp4']);

    executor.release('/videos/v1.mp4');
    await _settleIo();

    // 第一条完成后第三条才起步（并发上限腾出空位）。
    expect(executor.started, [
      '/videos/v1.mp4',
      '/videos/v2.mp4',
      '/videos/v3.mp4',
    ]);

    executor.release('/videos/v2.mp4');
    executor.release('/videos/v3.mp4');
    expect(await Future.wait(results), [true, true, true]);
  });

  test('同一支舞只排队一次：重复请求复用同一结果，不重复取帧', () async {
    final first = queue.request(request('v1'));
    final second = queue.request(request('v1'));
    await _settleIo();

    expect(executor.started, ['/videos/v1.mp4']);

    executor.release('/videos/v1.mp4');

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(executor.started, hasLength(1));
  });

  test('同一支舞位置变了算另一次请求：不复用旧结果，按新位置再取', () async {
    final first = queue.request(request('v1'));
    await _settleIo();
    executor.release('/videos/v1.mp4');
    expect(await first, isTrue);

    final second = queue.request((
      videoId: 'v1',
      sourcePath: '/videos/v1.mp4',
      position: const Duration(seconds: 30),
    ));
    await _settleIo();

    expect(executor.started, hasLength(2));
    executor.release('/videos/v1.mp4');
    expect(await second, isTrue);
  });

  test('取帧失败：返回 false；本会话内重复请求不再起第二次解码', () async {
    executor.fail('/videos/v1.mp4');
    final first = queue.request(request('v1'));
    await _settleIo();
    executor.release('/videos/v1.mp4');
    expect(await first, isFalse);

    final again = queue.request(request('v1'));
    await _settleIo();

    expect(await again, isFalse);
    expect(executor.started, hasLength(1));
  });
}


/// 让真实文件 IO（缓存 rename / 位置标记）跑完若干轮事件循环。
Future<void> _settleIo() => Future<void>.delayed(const Duration(milliseconds: 20));

/// 内存执行器替身：记录起步次序，等用例显式放行才完成（据此观察并发上限）。
class _BlockingExecutor implements CoverFrameExecutor {
  final List<String> started = [];
  final Map<String, Completer<void>> _gates = {};
  final Set<String> _failures = {};

  void release(String sourcePath) => _gates[sourcePath]!.complete();

  void fail(String sourcePath) => _failures.add(sourcePath);

  @override
  Future<bool> execute(List<String> arguments) async {
    final source = arguments[arguments.indexOf('-i') + 1];
    started.add(source);
    final gate = Completer<void>();
    _gates[source] = gate;
    await gate.future;
    if (_failures.contains(source)) return false;
    final output = File(arguments.last);
    await output.parent.create(recursive: true);
    await output.writeAsString('fake-jpeg');
    return true;
  }
}
