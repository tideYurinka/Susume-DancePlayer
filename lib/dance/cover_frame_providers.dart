/// 封面取帧的装配层：把缓存与取帧执行器装成封面生成
/// 入口，并暴露缓存给舞库读面与删除清理。
///
/// 生成是**惰性**的：导入路径不触取帧；卡片/详情需要封面时才调用
/// [CoverGenerator.generate]。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cover_frame.dart';
import '../core/cover_frame_ffmpeg.dart';
import '../persistence/cover_cache_directory.dart'
    show coverCacheDirectoryProvider;
import 'cover_cache.dart';
import 'cover_generation_queue.dart';
import 'cover_generator.dart';

/// 封面缓存注入点（唯一路径来源：读写、就绪判定与删除清理共用同一实例，
/// 因此同一支舞的封面文件只有一处命名口径）。
final coverCacheProvider = FutureProvider<CoverCache>((ref) async {
  final directory = await ref.watch(coverCacheDirectoryProvider.future);
  return FileCoverCache(() => directory);
});

/// 取帧执行器注入点（生产为 ffmpeg 同步执行 + 返回码；测试注入内存替身）。
final coverFrameExecutorProvider = Provider<CoverFrameExecutor>(
  (ref) => const FfmpegCoverFrameExecutor(),
);

/// 封面生成入口（惰性取帧 + 会话内失败不重试的唯一实例）。
final coverGeneratorProvider = FutureProvider<CoverGenerator>((ref) async {
  return FfmpegCoverGenerator(
    cache: await ref.watch(coverCacheProvider.future),
    executor: ref.watch(coverFrameExecutorProvider),
  );
});

/// 封面取帧队列（应用内单例）：可见优先、同时最多两条，完成后页面刷新该卡。
///
/// 会话内的请求去重与失败不重试状态住在队列里，因此不做 autoDispose——离开
/// 首页回来仍复用同一份会话状态（重启后才再试一次）。
final coverGenerationQueueProvider = Provider<CoverGenerationQueue>((ref) {
  return CoverGenerationQueue(
    run: (request) async {
      final generator = await ref.read(coverGeneratorProvider.future);
      return generator.generate(
        videoId: request.videoId,
        sourcePath: request.sourcePath,
        position: request.position,
      );
    },
  );
});
