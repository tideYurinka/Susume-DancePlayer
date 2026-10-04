import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/cover_frame.dart' show kCoverPlaceholderAspectRatio;
import '../core/jpeg_size.dart' show parseJpegSize;

/// 封面图片缓存：每支舞一份图片，住设备本地缓存位置
/// （与文档同级）。封面图片**不是**媒体种类——不进任何分享包、不进整机
/// 备份；删除一支舞时随该舞清除。
///
/// 写入为**同名原子替换**：先生成到同目录临时文件，再 rename 覆盖同名
/// 目标——读侧永不看到半截 JPEG，换封面不产生第二份图片（缓存不随换封面
/// 次数膨胀）。文件缺失即视为未就绪（读面据此渲染占位图）。
///
/// 图片旁边记一份**生成位置**（同名 sidecar）：封面位置改了（首线跟随变化或
/// 用户换封面）旧图即失效，卡片按新位置重取——「首线一改封面跟着改」由此
/// 落到缓存就绪判定上，而不是读面自己拼路径。位置字段的唯一记录仍住公开
/// 标记文件，sidecar 只是本地缓存的失效判据。
///
/// 抽象成接口是为了 widget 测试注入内存替身：读面要问「这张卡片有没有
/// 封面」，而 fake async 时钟下真实文件 IO 不可完成（与按视频文档存取
/// 同款先例）。
abstract interface class CoverCache {
  /// 该舞封面图片的目标文件（路径唯一来源；页面不自己拼路径）。
  Future<File> fileFor(String videoId);

  /// 该舞在 [position] 处的就绪封面（图片 + 图片自身宽高比）；未就绪
  /// （图片不存在，或生成位置不是 [position]）或读失败为 null。图与比例
  /// 一次取回：调用方不再分两步拼装，中间也没有缓存被换掉的窗口。
  Future<({File file, double aspectRatio})?> readyCover(
    String videoId,
    Duration position,
  );

  /// 位置 → 就绪封面的宽高比（宽 ÷ 高）。输入 = 各舞当前封面位置；只有
  /// 「图片存在且生成位置与当前位置一致」的舞才在结果里。头部读不出比例
  /// （损坏图）时按竖屏 3:4 兜底——与未就绪占位同款，不额外做比例预判。
  Future<Map<String, double>> readyCovers(Map<String, Duration> positions);

  /// 取帧命令的输出目标：与目标文件同目录、同批次的临时名，rename 覆盖
  /// 因此是同一文件系统内的原子替换（跨设备 rename 会失败）。**父目录由
  /// 调用方在发命令前备好**——ffmpeg 不自建输出目录。
  Future<File> tempFileFor(String videoId);

  /// 把取帧产物 [tempFile] 原子替换进该舞的缓存位置（记录生成位置
  /// [position]）；成功返回 true。失败（临时文件缺失/rename 失败）返回
  /// false 并保持原图不变。
  Future<bool> writeFrom(String videoId, File tempFile, Duration position);

  /// 清除该舞的封面缓存（图 + 位置 sidecar；缺失视作已清、不抛错）；删除
  /// 一支舞时随该舞调用一次（best-effort，失败只留孤儿文件）。
  Future<void> deleteFor(String videoId);
}

/// 真实文件实现：缓存目录由调用方解析（生产 = 应用文档目录；测试注入
/// 临时目录）。
class FileCoverCache implements CoverCache {
  FileCoverCache(this._directory);

  final FutureOr<Directory> Function() _directory;

  @override
  Future<File> fileFor(String videoId) async =>
      File(p.join((await _directory()).path, 'cover_$videoId.jpg'));

  @override
  Future<({File file, double aspectRatio})?> readyCover(
    String videoId,
    Duration position,
  ) async {
    final file = await fileFor(videoId);
    if (!await file.exists()) return null;
    try {
      final recorded = await (await _positionFileFor(videoId)).readAsString();
      if (recorded != '${position.inMilliseconds}') return null;
      return (file: file, aspectRatio: await _aspectRatio(file));
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<Map<String, double>> readyCovers(
    Map<String, Duration> positions,
  ) async {
    final covers = <String, double>{};
    await Future.wait([
      for (final entry in positions.entries)
        () async {
          // 单支舞的读失败（并发删除 / 损坏）只让这一支按未就绪处理，
          // 不拖垮整库封面读面。
          final ready = await readyCover(entry.key, entry.value);
          if (ready != null) covers[entry.key] = ready.aspectRatio;
        }(),
    ]);
    return covers;
  }

  /// 图片自身的宽高比；头部不可解时按竖屏 3:4 兜底。
  Future<double> _aspectRatio(File file) async {
    final size = parseJpegSize(await file.readAsBytes());
    if (size == null) return kCoverPlaceholderAspectRatio;
    return size.width / size.height;
  }

  @override
  Future<File> tempFileFor(String videoId) async =>
      File('${(await fileFor(videoId)).path}.tmp');

  @override
  Future<bool> writeFrom(
    String videoId,
    File tempFile,
    Duration position,
  ) async {
    final target = await fileFor(videoId);
    try {
      await target.parent.create(recursive: true);
      await tempFile.rename(target.path);
    } on FileSystemException {
      return false;
    }
    // 图片已就位后再标记位置：标记写失败只让这张图看起来「不是这个位置
    // 生成的」（下次重取），不会让读侧把旧位置的图当新封面。写失败与
    // rename 失败同列返回 false（调用方按取不到帧处理）。
    try {
      await (await _positionFileFor(videoId))
          .writeAsString('${position.inMilliseconds}');
    } on FileSystemException {
      return false;
    }
    return true;
  }

  @override
  Future<void> deleteFor(String videoId) async {
    final target = await fileFor(videoId);
    if (await target.exists()) await target.delete();
    final temp = await tempFileFor(videoId);
    if (await temp.exists()) await temp.delete();
    final position = await _positionFileFor(videoId);
    if (await position.exists()) await position.delete();
  }

  /// 生成位置 sidecar（本地缓存的一部分，不是公开字段）。
  Future<File> _positionFileFor(String videoId) async =>
      File('${(await fileFor(videoId)).path}.position');
}
