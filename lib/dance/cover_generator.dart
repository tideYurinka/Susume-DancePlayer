import 'dart:io';

import 'cover_cache.dart';
import '../core/cover_frame.dart';

/// 封面生成端口：确保某支舞在给定位置的封面缓存就绪。
abstract interface class CoverGenerator {
  /// 确保该舞的封面缓存就绪（[position] = 封面位置，缺省语义由读面求值）。
  ///
  /// 返回 true = 此刻缓存已有图片（本就就绪或本次生成成功）；false = 尚无
  /// 图片（取帧失败或本会话已失败过）。页面据此渲染占位图。
  Future<bool> generate({
    required String videoId,
    required String sourcePath,
    required Duration position,
  });
}

/// 封面生成编排：装配取帧命令 → 注入执行器取帧 → 产物
/// 原子替换进缓存。裁切比例与输出尺寸住在命令的滤镜里（见
/// [buildCoverFrameArguments]）。
///
/// 失败**不缓存失败**：缓存里不留占位/空图，只记本次
/// 应用会话内已失败过的舞——同一支舞不再重复起解码进程；重启后可以再试
/// 一次。惰性生成：只在卡片或详情需要封面时调用，导入路径不触取帧。
class FfmpegCoverGenerator implements CoverGenerator {
  FfmpegCoverGenerator({required this.cache, required this.executor});

  final CoverCache cache;
  final CoverFrameExecutor executor;

  /// 本次会话内取帧失败过的舞（不落盘：重启即清空，允许再试一次）。
  final Set<String> _failedThisSession = {};

  @override
  Future<bool> generate({
    required String videoId,
    required String sourcePath,
    required Duration position,
  }) async {
    if (await cache.readyCover(videoId, position) != null) return true;
    if (_failedThisSession.contains(videoId)) return false;

    final tempFile = await cache.tempFileFor(videoId);
    // ffmpeg 不自建输出目录：发取帧命令前先备好输出位置（目录缺失时它以
    // 非成功返回码结束、一帧不写）。建目录失败没起解码进程，不是「取帧
    // 失败」——如实回落占位图，但不记入本会话的失败集合，下次请求还能再试。
    try {
      await tempFile.parent.create(recursive: true);
    } on FileSystemException {
      return false;
    }
    try {
      final arguments = buildCoverFrameArguments(
        videoPath: sourcePath,
        position: position,
        outputPath: tempFile.path,
      );
      final extracted = await executor.execute(arguments);
      // 取到帧 = 执行成功 **且** 真产出了非空图片：目标时刻落在片尾之外时
      // ffmpeg 能以成功返回码结束却一帧不写——那仍是「取不到帧」，按失败
      // 处理（渲染占位图），不把空图当封面发布。
      final produced =
          extracted && await tempFile.exists() && await tempFile.length() > 0;
      if (!produced) {
        _failedThisSession.add(videoId);
        return false;
      }
      final written = await cache.writeFrom(videoId, tempFile, position);
      if (!written) _failedThisSession.add(videoId);
      return written;
    } on Object {
      _failedThisSession.add(videoId);
      return false;
    } finally {
      // 失败/异常路径不留半截临时文件（成功路径的 rename 已把它移走）。
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on FileSystemException {
          // 清理失败只留孤儿临时文件，不影响封面状态。
        }
      }
    }
  }
}
