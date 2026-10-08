/// 渲染路线关卡（#24）计时入口的**纯件**：固定输入规格、投屏渲染的完整滤镜图
/// 与命令行、计时统计、产物可播放性判定、编码器组件名解读。
///
/// 这一层不 import Flutter、不 import ffmpeg 包、不碰 IO：设备入口
/// （`tool/cast_render_bench.dart`，走已链接的 ffmpeg 包）与宿主入口
/// （`tool/cast_render_bench_host.dart`，走本机 ffmpeg CLI）把**同一份命令**
/// 交给各自的执行器，读数也走**同一组判定**——两侧读数因此可比。
library;

import 'dart:convert';

/// 局部镜像的一个时间窗，单位秒。区间口径是**半开** `[起, 止)`。
///
/// 这是 ADR-0004 与投屏渲染口径的硬要求：`between` 两端都含、会多翻一帧，
/// 所以时间窗一律写成 `gte(t,起)*lt(t,止)`。
class BenchWindow {
  const BenchWindow(this.start, this.end);

  /// 窗口起点（含）。
  final double start;

  /// 窗口终点（不含）。
  final double end;

  /// 该窗的 `enable` 表达式。
  String get enableExpression =>
      'gte(t,${benchSeconds(start)})*lt(t,${benchSeconds(end)})';
}

/// 秒数的字面量写法：整秒不写成 `2.0`——滤镜图是要进留档文档的外部契约，
/// 读数人看到的是锚点本身（`2`）、不是它的浮点表示。
String benchSeconds(double seconds) => seconds == seconds.roundToDouble()
    ? seconds.toInt().toString()
    : seconds.toString();

/// 把若干时间窗并成一条 `enable` 表达式（按 `+` 相加：叠交只是真值非零）。
///
/// 空窗集给恒假表达式 `0`——用它的滤镜在该时段**照原样通过**，这正是我们的
/// 口径：窗外的帧不翻。
String unionEnableExpression(List<BenchWindow> windows) {
  if (windows.isEmpty) {
    return '0';
  }
  return windows.map((w) => w.enableExpression).join('+');
}

/// 固定输入规格：30 秒、1080p、30fps 的源片，一张带 alpha 的贴纸，
/// 一条 120bpm 的拍声。三样都在**渲染之前**落定，渲染命令只读它们——
/// 同一串参数生成同一份输入，"输入固定"因此可以复算、可以留档哈希。
const int kBenchDurationSeconds = 30;
const int kBenchFps = 30;
const int kBenchSourceWidth = 1920;
const int kBenchSourceHeight = 1080;
const int kBenchSampleRate = 48000;
const int kBenchBpm = 120;

/// 局部镜像的时间窗（与生产口径同款：半开区间）。
const List<BenchWindow> kBenchLocalMirrorWindows = <BenchWindow>[
  BenchWindow(2, 4),
  BenchWindow(10, 12.5),
];

/// 贴纸可见的时间窗（半开区间）。
const BenchWindow kBenchStickerWindow = BenchWindow(6, 9);

/// 贴纸在**源画面矩形**上的归一化落位（左上角 + 尺寸）。
const double kBenchStickerLeft = 0.05;
const double kBenchStickerTop = 0.07;
const double kBenchStickerWidth = 0.25;
const double kBenchStickerHeight = 0.15;

/// 取景在**源画面矩形**上的归一化选区。
const double kBenchFramingLeft = 0.05;
const double kBenchFramingTop = 0.05;
const double kBenchFramingWidth = 0.9;
const double kBenchFramingHeight = 0.9;

/// 编码器参数里显式给出的 GOP 与帧率。
const int kBenchGop = 60;

/// 已链接的 ffmpeg 包在 Android 上唯一的 H.264 编码器（硬编）。
const String kDeviceEncoder = 'h264_mediacodec';

/// 贴纸 PNG 的像素尺寸：由归一化落位换算，两处只有一份真相。
int get kBenchStickerPixelWidth =>
    (kBenchSourceWidth * kBenchStickerWidth).round();
int get kBenchStickerPixelHeight =>
    (kBenchSourceHeight * kBenchStickerHeight).round();

/// 量哪一档输出分辨率。同一张滤镜图，只有末段 scale 与码率不同——
/// 「分辨率对耗时的影响系数」才有意义。
enum BenchResolution {
  p1080(1920, 1080, '8M'),
  p720(1280, 720, '4M');

  const BenchResolution(this.width, this.height, this.bitrate);

  final int width;
  final int height;

  /// 该档的显式码率。
  final String bitrate;
}

/// 完整滤镜图：全局镜像 → 时间窗局部镜像 → 贴纸 → 取景裁切缩放 → 拍声混音。
///
/// 输入次序固定：`0` 源片、`1` 贴纸（单帧 PNG）、`2` 拍声。
String renderFilterGraph(BenchResolution resolution) {
  final overlayX = (kBenchSourceWidth * kBenchStickerLeft).round();
  final overlayY = (kBenchSourceHeight * kBenchStickerTop).round();
  final cropX = (kBenchSourceWidth * kBenchFramingLeft).round();
  final cropY = (kBenchSourceHeight * kBenchFramingTop).round();
  final cropW = (kBenchSourceWidth * kBenchFramingWidth).round();
  final cropH = (kBenchSourceHeight * kBenchFramingHeight).round();
  return <String>[
    '[0:v]fps=$kBenchFps,format=yuv420p,hflip[g0]',
    "[g0]hflip=enable='${unionEnableExpression(kBenchLocalMirrorWindows)}'[g1]",
    '[1:v]format=rgba,fps=$kBenchFps[stk]',
    "[g1][stk]overlay=x=$overlayX:y=$overlayY"
        ":enable='${kBenchStickerWindow.enableExpression}'"
        ':format=rgb:eof_action=repeat[g2]',
    '[g2]crop=$cropW:$cropH:$cropX:$cropY'
        ',scale=${resolution.width}:${resolution.height}'
        ',setsar=1,format=yuv420p[vout]',
    '[0:a]aresample=$kBenchSampleRate[amain]',
    '[2:a]aresample=$kBenchSampleRate,volume=0.6[abeat]',
    '[amain][abeat]amix=inputs=2:duration=first:dropout_transition=0[aout]',
  ].join(';');
}

/// 投屏渲染的完整命令行（设备与宿主共用同一串，只换编码器）。
///
/// `limitSeconds` 只给「先点一把火」的冒烟用：同样一张图、同样一个编码器，
/// 但只产出前一秒——滤镜、贴纸输入与编码器初始化全都会真跑一遍，几分钟的
/// 整片渲染因此不必在一条根本不成立的链路上白等。
List<String> renderArgs({
  required BenchResolution resolution,
  required String sourcePath,
  required String stickerPath,
  required String beatPath,
  required String outputPath,
  String encoder = kDeviceEncoder,
  double? limitSeconds,
}) {
  return <String>[
    '-hide_banner',
    '-y',
    '-i', sourcePath,
    '-i', stickerPath,
    '-i', beatPath,
    '-filter_complex', renderFilterGraph(resolution),
    '-map', '[vout]',
    '-map', '[aout]',
    '-c:v', encoder,
    '-b:v', resolution.bitrate,
    '-g', '$kBenchGop',
    '-r', '$kBenchFps',
    '-pix_fmt', 'yuv420p',
    '-c:a', 'aac',
    '-b:a', '192k',
    '-ar', '$kBenchSampleRate',
    '-ac', '2',
    '-movflags', '+faststart',
    if (limitSeconds != null) ...<String>['-t', benchSeconds(limitSeconds)],
    '-f', 'mp4',
    outputPath,
  ];
}

/// 源片生成参数：`testsrc2` 画面 + 440Hz 音轨，参数里写死 30s/1080p/30fps。
List<String> sourceGenerationArgs({
  required String outputPath,
  String encoder = kDeviceEncoder,
}) {
  return <String>[
    '-hide_banner',
    '-y',
    '-f', 'lavfi',
    '-i', 'testsrc2=size=${kBenchSourceWidth}x$kBenchSourceHeight'
        ':rate=$kBenchFps:duration=$kBenchDurationSeconds',
    '-f', 'lavfi',
    '-i', 'sine=frequency=440:sample_rate=$kBenchSampleRate'
        ':duration=$kBenchDurationSeconds',
    '-c:v', encoder,
    '-b:v', '6M',
    '-pix_fmt', 'yuv420p',
    '-g', '$kBenchFps',
    '-r', '$kBenchFps',
    '-c:a', 'aac',
    '-b:a', '128k',
    '-ar', '$kBenchSampleRate',
    '-ac', '2',
    '-movflags', '+faststart',
    '-f', 'mp4',
    outputPath,
  ];
}

/// 贴纸生成参数：带 alpha 的**单帧** PNG（源只有一帧，靠 overlay 的
/// `eof_action=repeat` 铺满时间轴，所以输入侧不配 `-loop 1`）。
///
/// `format=rgba` 必须留在 **lavfi 输入图里**：挂在 `-vf` 上时，色源在自己那段
/// 图里已经按 yuv420p 协商完、alpha 当场没了，再转回 rgba 只剩不透明的 255。
List<String> stickerGenerationArgs({required String outputPath}) {
  return <String>[
    '-hide_banner',
    '-y',
    '-f', 'lavfi',
    '-i', 'color=c=yellow@0.6'
        ':s=${kBenchStickerPixelWidth}x$kBenchStickerPixelHeight'
        ',format=rgba',
    '-frames:v', '1',
    '-f', 'image2',
    outputPath,
  ];
}

/// 拍声生成参数：880Hz 正弦按 120bpm 开 60ms 的闸——整拍一声，30 秒。
List<String> beatGenerationArgs({required String outputPath}) {
  final period = 60 / kBenchBpm;
  return <String>[
    '-hide_banner',
    '-y',
    '-f', 'lavfi',
    '-i', 'sine=frequency=880:sample_rate=$kBenchSampleRate'
        ':duration=$kBenchDurationSeconds'
        ",volume=volume='lt(mod(t,$period),0.06)'",
    '-c:a', 'pcm_s16le',
    '-ar', '$kBenchSampleRate',
    '-ac', '2',
    '-f', 'wav',
    outputPath,
  ];
}

/// 一次计时跑的全部读数。
class BenchRunResult {
  const BenchRunResult({
    required this.resolution,
    required this.wallClockMs,
    required this.rendered,
    required this.artifact,
    this.fullyDecodable,
    this.decodedFrames,
    this.codecPick,
    this.stdoutTail,
  });

  /// 这一跑的输出分辨率档。
  final BenchResolution resolution;

  /// 墙钟毫秒（只包住渲染那一次执行，不含准备输入）。
  final int wallClockMs;

  /// ffmpeg 返回码为 0。
  final bool rendered;

  /// 产物可播放性判定。
  final ArtifactVerdict artifact;

  /// 整片解码校验（`-f null -`）是否无错；没跑这项时为 null。
  final bool? fullyDecodable;

  /// 整片解码出的帧数（读不出时为 null）。
  final int? decodedFrames;

  /// 日志里读到的 MediaCodec 组件名（读不到为 null）。
  final MediaCodecPick? codecPick;

  /// 命令输出的尾巴，留档用。
  final String? stdoutTail;

  /// 这一跑是否进统计：渲染成功、产物可播、整片解码也没报错。
  bool get usable =>
      rendered && artifact.ok && (fullyDecodable ?? true);
}

/// 一档分辨率的计时读数。
class ResolutionTiming {
  const ResolutionTiming(this.samplesMs);

  /// 进统计的各次墙钟毫秒（按发生次序）。
  final List<int> samplesMs;

  List<int> get _sorted => List<int>.of(samplesMs)..sort();

  int get medianMs => _sorted[_sorted.length ~/ 2];
  int get minMs => _sorted.first;
  int get maxMs => _sorted.last;

  /// 实时倍率：素材时长 ÷ 中位墙钟。>1 表示比实时快。
  double get realtimeFactor => kBenchDurationSeconds * 1000 / medianMs;
}

/// 计时汇总。
class BenchTimingSummary {
  const BenchTimingSummary({
    required this.p1080,
    required this.p720,
    required this.rejected,
  });

  final ResolutionTiming? p1080;
  final ResolutionTiming? p720;

  /// 不进统计的那些跑（渲染失败、产物不可播）。
  final List<BenchRunResult> rejected;

  /// 分辨率对耗时的影响系数：1080p 中位数 ÷ 720p 中位数。缺一档时为空。
  double? get resolutionCoefficient {
    if (p1080 == null || p720 == null) {
      return null;
    }
    return p1080!.medianMs / p720!.medianMs;
  }
}

/// 把若干跑汇总成计时读数。不可用的跑**不进中位数**，另列在旁。
BenchTimingSummary summarizeBenchRuns(List<BenchRunResult> runs) {
  ResolutionTiming? timingOf(BenchResolution resolution) {
    final samples = runs
        .where((r) => r.resolution == resolution && r.usable)
        .map((r) => r.wallClockMs)
        .toList();
    return samples.isEmpty ? null : ResolutionTiming(samples);
  }

  return BenchTimingSummary(
    p1080: timingOf(BenchResolution.p1080),
    p720: timingOf(BenchResolution.p720),
    rejected: runs.where((r) => !r.usable).toList(),
  );
}

/// 从 ffprobe / FFprobeKit 读到的产物事实。
class ArtifactReading {
  const ArtifactReading({
    required this.durationSeconds,
    required this.width,
    required this.height,
    required this.hasVideoStream,
    required this.hasAudioStream,
  });

  final double? durationSeconds;
  final int? width;
  final int? height;
  final bool hasVideoStream;
  final bool hasAudioStream;
}

/// 产物可播放性判定：四件事各自点出来，不合成一个不透明的布尔。
class ArtifactVerdict {
  const ArtifactVerdict({required this.ok, required this.problems});

  final bool ok;
  final List<String> problems;
}

/// 按预期档位判产物能不能播：两路流齐备、分辨率对得上、时长在容差内，
/// 若给了整片解码的帧数，还要与「时长 × 帧率」对得上——**掉帧的产物不算可播**。
ArtifactVerdict judgeArtifact(
  ArtifactReading reading, {
  required BenchResolution expected,
  double durationToleranceSeconds = 1.0,
  int? decodedFrames,
}) {
  final problems = <String>[];
  if (!reading.hasVideoStream) {
    problems.add('缺视频流');
  }
  if (!reading.hasAudioStream) {
    problems.add('缺音轨');
  }
  if (reading.width != expected.width || reading.height != expected.height) {
    problems.add(
      '分辨率是 ${reading.width}x${reading.height}，'
      '预期 ${expected.width}x${expected.height}',
    );
  }
  final duration = reading.durationSeconds;
  if (duration == null) {
    problems.add('时长读不到');
  } else if ((duration - kBenchDurationSeconds).abs() > durationToleranceSeconds) {
    problems.add(
      '时长 ${duration.toStringAsFixed(2)}s 偏出 '
      '${kBenchDurationSeconds}s ±${durationToleranceSeconds}s',
    );
  }
  if (decodedFrames != null) {
    final expectedFrames = kBenchDurationSeconds * kBenchFps;
    if ((decodedFrames - expectedFrames).abs() > kBenchFrameTolerance) {
      problems.add(
        '整片解码出 $decodedFrames 帧，预期 $expectedFrames'
        '（±$kBenchFrameTolerance）',
      );
    }
  }
  return ArtifactVerdict(ok: problems.isEmpty, problems: problems);
}

/// 解码帧数的容差（帧）：编码器边界上多一帧少一帧不算丢帧，成片的丢帧必须露头。
const int kBenchFrameTolerance = 5;

/// 从 ffprobe 的 JSON 输出里读出产物事实。
///
/// 宿主走 `ffprobe -print_format json`，设备走 ffprobe 会话的日志——同一份
/// JSON、同一个解析，两侧读数因此可比。读不出 JSON 时给 null。
ArtifactReading? parseFfprobeOutput(String output) {
  final start = output.indexOf('{');
  final end = output.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(output.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final streams = (decoded['streams'] as List<Object?>? ?? <Object?>[])
      .whereType<Map<String, Object?>>()
      .toList();
  final video = streams.where((s) => s['codec_type'] == 'video').toList();
  final audio = streams.where((s) => s['codec_type'] == 'audio').toList();
  final format =
      decoded['format'] as Map<String, Object?>? ?? <String, Object?>{};
  return ArtifactReading(
    durationSeconds: double.tryParse('${format['duration']}'),
    width: video.isEmpty ? null : (video.first['width'] as num?)?.toInt(),
    height: video.isEmpty ? null : (video.first['height'] as num?)?.toInt(),
    hasVideoStream: video.isNotEmpty,
    hasAudioStream: audio.isNotEmpty,
  );
}

/// 整片解码命令：`-stats` 是帧数的唯一来源（`-v error` 平时把 stats 关掉了）。
List<String> decodeCheckArgs(String path) {
  return <String>[
    '-hide_banner',
    '-v', 'error',
    '-stats',
    '-i', path,
    '-f', 'null',
    '-',
  ];
}

/// 整片解码的日志里除 stats 行以外还有内容 = 解码报了错。
///
/// stats 行（`frame= … fps= …`）是进度，不是错误——它带着 `-stats` 一起进来，
/// 判定时得先把这些行摘掉。
bool hasDecodeErrors(String logs) {
  return logs
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim())
      .any((line) => line.isNotEmpty && !line.startsWith('frame='));
}

/// 从解码日志末尾的 stats 行读出解码帧数。读不出给 null。
int? parseDecodedFrameCount(String logs) {
  final matches = RegExp(r'frame=\s*(\d+)').allMatches(logs);
  if (matches.isEmpty) {
    return null;
  }
  return int.tryParse(matches.last.group(1)!);
}

/// ffmpeg 选中的 MediaCodec 组件。
class MediaCodecPick {
  const MediaCodecPick({
    required this.component,
    required this.hardwareAccelerated,
  });

  final String component;

  /// 组件名是否指向硬件实现。`c2.android.*` 与 `OMX.google.*` 是 AOSP 的
  /// 软件实现，其余（`c2.qti.*`、`c2.mtk.*`、`OMX.qcom.*` …）按硬编处理。
  final bool hardwareAccelerated;
}

/// 从 ffmpeg 日志里读出 `MediaCodec started successfully: codec = <名>`。
///
/// 读不到就返回 null——**不猜**：留档里宁可写「未读出」，也不写一个错的组件名。
MediaCodecPick? parseMediaCodecPick(Iterable<String> logLines) {
  final pattern = RegExp(r'codec = ([A-Za-z0-9_.\-]+)');
  for (final line in logLines) {
    final match = pattern.firstMatch(line);
    if (match == null) {
      continue;
    }
    final component = match.group(1)!;
    final software = component.startsWith('c2.android.') ||
        component.startsWith('OMX.google.');
    return MediaCodecPick(
      component: component,
      hardwareAccelerated: !software,
    );
  }
  return null;
}

/// 一次 PSNR 对照的两个读数：产物与该段参考的相似度。
class PsnrPair {
  const PsnrPair({required this.plain, required this.flipped});

  /// 与「没翻过的参考」的平均 PSNR（越高越像）。
  final double plain;

  /// 与「翻过的参考」的平均 PSNR。
  final double flipped;
}

/// 镜像闸门的验收结论。
class FlipGateVerdict {
  const FlipGateVerdict({required this.ok, required this.problems});

  final bool ok;
  final List<String> problems;
}

/// 判镜像闸门是否按口径生效：**窗内像未翻的那份、窗外像翻过的那份**。
///
/// 这是 ADR-0004 那条「源画面方向 = 全局镜像 ⊕（局部镜像 ∧ 在区间内）」
/// 在像素上的样子；它同时钉住半开区间——窗的终点那一帧必须算窗外。
FlipGateVerdict judgeFlipGate({
  required PsnrPair insideWindow,
  required PsnrPair outsideWindow,
  double margin = 3.0,
}) {
  final problems = <String>[];
  if (insideWindow.plain - insideWindow.flipped < margin) {
    problems.add(
      '窗内不像未翻的原片（未翻 ${insideWindow.plain.toStringAsFixed(1)}dB '
      'vs 翻过 ${insideWindow.flipped.toStringAsFixed(1)}dB）',
    );
  }
  if (outsideWindow.flipped - outsideWindow.plain < margin) {
    problems.add(
      '窗外不像翻过的原片（翻过 ${outsideWindow.flipped.toStringAsFixed(1)}dB '
      'vs 未翻 ${outsideWindow.plain.toStringAsFixed(1)}dB）',
    );
  }
  return FlipGateVerdict(ok: problems.isEmpty, problems: problems);
}

/// 解析 ffmpeg `psnr` 滤镜汇总行里的 `average:`。
double? parsePsnrAverage(String line) {
  final match = RegExp(r'average:([0-9.]+|inf)').firstMatch(line);
  if (match == null) {
    return null;
  }
  final raw = match.group(1)!;
  return raw == 'inf' ? double.infinity : double.tryParse(raw);
}

/// 编码器能力查询：问的是同一个编码器的帮助页（像素格式、档次、码率区间
/// 都在里面）。真机上这一步同时说明「这个编码器在本包里在不在」。
List<String> encoderCapabilityArgs({String encoder = kDeviceEncoder}) {
  return <String>['-hide_banner', '-h', 'encoder=$encoder'];
}

/// 组件名探针：一小段（0.5s、320x240）带 debug 日志的编码，输出到 `null`。
///
/// 它只为读出 ffmpeg 实际选中的 MediaCodec 组件名（`c2.android.*` 是 AOSP
/// 软件实现、厂商名是硬编），不落任何文件。
List<String> encoderProbeArgs({String encoder = kDeviceEncoder}) {
  return <String>[
    '-hide_banner',
    '-loglevel', 'debug',
    '-f', 'lavfi',
    '-i', 'testsrc2=size=320x240:rate=$kBenchFps:duration=0.5',
    '-c:v', encoder,
    '-b:v', '1M',
    '-pix_fmt', 'yuv420p',
    '-f', 'null',
    'null',
  ];
}

/// 从能力输出里认出编码器条目（`Encoder <名> [描述]:`）。认不出给 null。
String? encoderCapabilityName(Iterable<String> lines) {
  final pattern = RegExp(r'^Encoder ([A-Za-z0-9_.\-]+) ');
  for (final line in lines) {
    final match = pattern.firstMatch(line.trim());
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

/// 参考帧的滤镜链：与投屏渲染**共用同一段取景几何**（裁切起点、尺寸、缩放、
/// 像素格式），只去掉贴纸、镜像闸门与混音。
///
/// 镜像闸门的像素级验收拿它做两份对照（翻过 / 未翻），所以几何只有一处真相。
String referenceFilterChain(BenchResolution resolution, {bool mirrored = false}) {
  final cropX = (kBenchSourceWidth * kBenchFramingLeft).round();
  final cropY = (kBenchSourceHeight * kBenchFramingTop).round();
  final cropW = (kBenchSourceWidth * kBenchFramingWidth).round();
  final cropH = (kBenchSourceHeight * kBenchFramingHeight).round();
  return <String>[
    '[0:v]fps=$kBenchFps,format=yuv420p',
    if (mirrored) 'hflip',
    'crop=$cropW:$cropH:$cropX:$cropY',
    'scale=${resolution.width}:${resolution.height}',
    'setsar=1,format=yuv420p[ref]',
  ].join(',');
}
