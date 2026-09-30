/// 封面取帧的命令装配：**零 Flutter 纯件**——输入视频
/// 路径、时刻与输出路径，输出 ffmpeg 参数表。比例是图片自身的属性，不落盘
/// 任何尺寸字段。
library;

/// 像素宽高（封面 JPEG 的头部尺寸）。
class VideoFrameSize {
  const VideoFrameSize({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is VideoFrameSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'VideoFrameSize(${width}x$height)';
}

/// 输入前快进量：目标前约 2 秒（双 seek 的第一段，见 [buildCoverFrameArguments]）。
const Duration kCoverFastSeekLead = Duration(seconds: 2);

/// 卡片封面未就绪时的占位比例（3:4）：与竖屏封面同款，就绪后换真图。
/// 图片头部读不出比例时也用这一兜底。
const double kCoverPlaceholderAspectRatio = 3 / 4;

/// JPEG 质量档。
///
/// mjpeg 的 `-q:v` 是 **qscale 1–31（小 = 好）**，不是 libjpeg 的 0–100；
/// 直接传 82 会被钳到 31（最差档，实测与 31 字节数完全相同）。qscale 4 的
/// 输出与 libjpeg quality 82 等价（同帧 540×720：qscale 4 = 26238 B，
/// ImageMagick `-quality 82` = 26288 B；qscale 3 = 29957 B ≈ quality 85）。
const int kCoverJpegQuality = 4;

/// 画面竖着：高**严格大于**宽（正方形不算竖屏，与既有口径一致）。
const String _portrait = r'gt(ih\,iw)';

/// 裁后帧横着：宽 ≥ 高（裁后帧已是目标比例，两档必居其一）。
const String _wide = r'gte(iw\,ih)';

/// 封面长边与短边（像素）：输出恒为「长边 720、短边 540」。
const int kCoverLongSide = 720;
const int kCoverShortSide = 540;

/// 目标比例表达式：竖着取 3:4，横着（含正方形）取 4:3。
///
/// 判据是**滤镜看到的解码帧宽高**——ffmpeg 已按旋转元数据把画面转正，滤镜所见
/// 就是用户看到的朝向。
const String _targetAspect = 'if($_portrait\\,3/4\\,4/3)';

/// 输出尺寸表达式：裁后帧横着出 720×540，竖着出 540×720。
const String _outputWidth = 'if($_wide\\,$kCoverLongSide\\,$kCoverShortSide)';
const String _outputHeight = 'if($_wide\\,$kCoverShortSide\\,$kCoverLongSide)';

/// 中心裁切 + 缩放到长边 720：先在画面里取目标比例的**最大居中窗口**，再缩放
/// 到输出尺寸。窗口宽高都受 `iw`/`ih` 约束、比例恒等于目标比例——因此不会把
/// 16:9 的画面压成 4:3（那是变形，不是裁切）。
const String _coverFilter =
    'crop=min(iw\\,ih*$_targetAspect):min(ih\\,iw/$_targetAspect):'
    '(iw-ow)/2:(ih-oh)/2,'
    'scale=$_outputWidth:$_outputHeight';

/// 装配「取某时刻的画面成一张 JPEG」的 ffmpeg 参数表。
///
/// 定位用**双 seek**：`-ss` 在 `-i` 之前先快进到目标前约 2 秒（关键帧级，
/// 快），`-ss` 在 `-i` 之后再精确定位到该帧——保证取到的就是所选那一帧，
/// 不被关键帧间距吃掉。零/负时刻（钳到片头）时省掉输入前的零秒 seek。
///
/// 裁切在取帧时一次决定：由滤镜按解码帧朝向中心裁到 3:4 / 4:3 并缩放到长边
/// 720，JPEG 质量 [kCoverJpegQuality]。
///
/// `-f mjpeg` 是必需的：输出目标是缓存的临时文件（`…jpg.tmp`），ffmpeg 只按
/// 扩展名猜封装格式，`.tmp` 猜不出会直接失败——不显式给格式就没有图片可落盘。
List<String> buildCoverFrameArguments({
  required String videoPath,
  required Duration position,
  required String outputPath,
}) {
  // 越界（负时刻）钳到片头：不为负数产出 seek。
  final target = position < Duration.zero ? Duration.zero : position;
  final clock = target - kCoverFastSeekLead;
  final fastSeek = clock > Duration.zero ? clock : Duration.zero;
  final preciseSeek = target - fastSeek;

  return [
    '-y',
    '-loglevel',
    'error',
    if (fastSeek > Duration.zero) ...[
      '-ss',
      _seconds(fastSeek),
    ],
    '-i',
    videoPath,
    '-ss',
    _seconds(preciseSeek),
    '-frames:v',
    '1',
    '-vf',
    _coverFilter,
    '-q:v',
    '$kCoverJpegQuality',
    '-f',
    'mjpeg',
    '-an',
    '-sn',
    outputPath,
  ];
}

/// 秒 → ffmpeg 时间串（毫秒精度）。
String _seconds(Duration duration) =>
    (duration.inMilliseconds / 1000).toStringAsFixed(3);

/// 执行一步取帧命令的注入点（唯一的执行 seam）：
/// 生产为 [FfmpegCoverFrameExecutor]（同步执行 + 返回码，见
/// `cover_frame_ffmpeg.dart`），测试注入内存替身——不依赖真实解码。
abstract interface class CoverFrameExecutor {
  /// 执行装配好的 ffmpeg 参数表；true = 返回码为成功。
  Future<bool> execute(List<String> arguments);
}
