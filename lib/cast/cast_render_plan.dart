/// 投屏渲染的**命令行装配**（纯件，零 Flutter、零 IO）：一份
/// [CastRenderRequest] → 一串 ffmpeg 参数。
///
/// ## 这是外部契约
///
/// 滤镜图与命令行直接决定产物，所以它们是可直测、可按片段钉住的外部契约
/// （不是实现细节）。本件因此不碰进程、不碰文件：装配在测试里逐片段断言，
/// 执行在 `cast_render_executor.dart` 那条接缝上。
///
/// ## 两档的差别就是命令行的差别
///
/// - **只勾声音类**（且 1× 档）：`-c:v copy` —— 视频流原样复制、不重编码，
///   音轨重编码并把拍声 `amix` 进来。这是「秒级出结果」的全部机关。
/// - **勾了画面类**：视频重编码（`h264_mediacodec` + 显式码率/ GOP / 帧率 /
///   像素格式），画面滤镜链进 `filter_complex`；不勾声音类时音轨 `-c:a copy`。
///   画面链今天是「归一帧率与像素格式」这一条底链——后四票
///   （#27–#30）把镜像 / 取景 / 贴纸 / 数拍插进它的中段，链尾的 `[vout]` 与
///   编码参数不变。
/// - **都不勾** = 不装配：调用方（编排器）直接推原片，本函数报错。
///
/// ## 倍速档：一档一份副本
///
/// 倍速不靠接收端（DLNA 没有这门能力），靠**换文件**：`setpts` 压画面、
/// `atempo` 拉音轨（拍声轨跟着一起缩放，否则换档就错开）。1× 档一个字段都不
/// 写，与「不设倍速」逐字一致。**非 1× 档的视频不能复制**——`-c:v copy` 改不了
/// 时长，所以只勾声音类也只在那三档里保留「原样复制」，非 1× 档退化成重编码
/// （规格里「只勾声音 = 视频流不重编码」那条说的是 1× 这个默认档）。
///
/// ## 范围
///
/// 首线→尾线那段范围**不在本票**：规格要求「从 0 整片解码、用时间窗偏移
/// 表达、不用快速定位」，那条偏移属于画面滤镜链的中段（与局部镜像的时间窗
/// 同处），由渲染各票一并落。本件因此不产出 `-ss` / `-to` / `-t`——半吊子的
/// 关键帧切割会让副本范围对不上，且复制档根本切不准。
library;

import 'cast_render_request.dart';

/// 画面档的视频编码器：已链接 ffmpeg 包在 Android 上的 H.264 硬编
/// （ADR-0004 的渲染路线结论）。
const String kCastRenderVideoEncoder = 'h264_mediacodec';

/// 画面档的显式码率、GOP 与目标帧率（编码参数不靠默认值）。
const String kCastRenderVideoBitrate = '8M';
const int kCastRenderGop = 60;
const int kCastRenderFps = 30;

/// 音轨的重编码参数（拍声要进这条轨，统一到同一个采样格式）。
const String kCastRenderAudioBitrate = '192k';
const int kCastRenderSampleRate = 48000;
const int kCastRenderChannels = 2;

/// 装配一条投屏渲染命令。
///
/// [beatTrackPath] 是**拍声轨**（`cast_beat_track.dart` 的合成产物）的路径；
/// 勾了声音类时必须给出（没有它就没有拍声，宁可不做）。
List<String> buildCastRenderArguments({
  required CastRenderRequest request,
  required String outputPath,
  String? beatTrackPath,
}) {
  final choices = request.choices;
  if (!choices.renders) {
    throw ArgumentError('都不勾 = 不渲染：调用方直接推原片，不该走到命令装配');
  }
  if (choices.sound && beatTrackPath == null) {
    throw ArgumentError('勾了声音类却没有拍声轨路径');
  }

  final rate = request.speedTier.token;
  final slowed = request.speedTier != CastSpeedTier.full;
  // 非 1× 档的视频必须重编码（复制改不了时长）。
  final reencodeVideo = choices.picture || slowed;

  final filters = <String>[];
  if (reencodeVideo) {
    final speed = slowed ? 'setpts=PTS/$rate,' : '';
    filters.add('[0:v]${speed}fps=$kCastRenderFps,format=yuv420p[vout]');
  }
  if (choices.sound) {
    final speed = slowed ? 'atempo=$rate,' : '';
    filters.add('[0:a]${speed}aresample=$kCastRenderSampleRate[amain]');
    filters.add('[1:a]${speed}aresample=$kCastRenderSampleRate[abeat]');
    filters.add(
      '[amain][abeat]amix=inputs=2:duration=first:dropout_transition=0[aout]',
    );
  }

  return <String>[
    '-hide_banner',
    '-y',
    '-i',
    request.videoPath,
    if (choices.sound) ...<String>['-i', beatTrackPath!],
    if (filters.isNotEmpty) ...<String>['-filter_complex', filters.join(';')],
    '-map',
    reencodeVideo ? '[vout]' : '0:v',
    if (choices.sound) ...<String>[
      '-map',
      '[aout]',
    ] else if (choices.picture) ...<String>['-map', '0:a'],
    '-c:v',
    reencodeVideo ? kCastRenderVideoEncoder : 'copy',
    if (reencodeVideo) ...<String>[
      '-b:v',
      kCastRenderVideoBitrate,
      '-g',
      '$kCastRenderGop',
      '-r',
      '$kCastRenderFps',
      '-pix_fmt',
      'yuv420p',
    ],
    if (choices.sound) ...<String>[
      '-c:a',
      'aac',
      '-b:a',
      kCastRenderAudioBitrate,
      '-ar',
      '$kCastRenderSampleRate',
      '-ac',
      '$kCastRenderChannels',
    ] else ...<String>['-c:a', 'copy'],
    '-movflags',
    '+faststart',
    '-f',
    'mp4',
    outputPath,
  ];
}
