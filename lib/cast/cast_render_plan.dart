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
///   画面链的中段是**镜像闸门**（#27，见 `cast_mirror_gate.dart`）、**取景
///   窗口**（#28，见 `cast_framing_gate.dart`）、**数拍层**（#30，见
///   `cast_beat_gate.dart`：一路图像序列输入 + 一个 `overlay` 时间窗）与
///   **备注贴纸**（#29，见 `cast_sticker_gate.dart`：第二路输入 + `overlay`
///   时间窗）；层序与上屏一致（贴纸画在数拍之上），链尾的 `fps` / 像素格式与
///   `[vout]` 不变。
/// - **都不勾** = 不装配：调用方（编排器）直接推原片，本函数报错。
///
/// ## 镜像闸门为什么排在倍速之前、取景为什么排在镜像之后
///
/// 闸门的 `enable` 表达式按 `t` 判定，而**局部镜像是源时间轴上的半开区间**：
/// 闸门排在 `setpts` 之后，`t` 已被拉伸，同一个窗在 0.5 / 0.75 档就会与手机上
/// 按源位置求值的那一份错开。排在 `setpts` 之前，`t` 就是源片时间——窗与倍速
/// 档不耦合，也与手机上「按显示位置求值」的判法同一口径。
///
/// 取景的裁切排在镜像**之后**：手机上翻转是画面件的显示层变换、取景是包在它
/// 外面的那层剪辑窗，窗里那块像素是「翻过的画面」在那块矩形上的样子；且局部
/// 镜像是**时间窗**而 `crop` 不支持时间窗（规格的 Further Notes），只有
/// 「先翻、后切窗」这一种写法能让窗逐帧跟着翻转走（见 `cast_framing_gate.dart`
/// 库头与 `cast_framing_gate_test.dart` 的逐帧比对）。
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

import 'cast_beat_gate.dart';
import 'cast_framing_gate.dart';
import 'cast_mirror_gate.dart';
import 'cast_render_request.dart';
import 'cast_sticker_gate.dart';

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
///
/// [stickerPaths] 是**备注贴纸图**（`player/cast_sticker_sheet.dart` 的带 alpha
/// 单帧 PNG；渲染编排按请求里的贴纸逐条落盘）的路径，与 `request.stickers`
/// 一一对应、次序相同。勾了画面类且这支舞有备注时才该给出；不勾画面类时贴纸
/// 一律不进命令（用户没勾画面类，画面内容类的东西就不该被烤进去）。
///
/// [beatSlidesPath] 是**数拍层图像序列的 `-f concat` 清单**（`player/
/// cast_beat_sheet.dart` 的逐格 PNG + `cast_beat_gate.dart` 的清单正文；
/// `#30`）：序列里一格一张同尺寸 PNG，每格的时长就是那一拍的半开窗。装了数拍
/// 层时必给（没给就是编程错误）；没装时传 null。
List<String> buildCastRenderArguments({
  required CastRenderRequest request,
  required String outputPath,
  String? beatTrackPath,
  String? beatSlidesPath,
  List<String> stickerPaths = const [],
}) {
  final choices = request.choices;
  if (!choices.renders) {
    throw ArgumentError('都不勾 = 不渲染：调用方直接推原片，不该走到命令装配');
  }
  if (choices.sound && beatTrackPath == null) {
    throw ArgumentError('勾了声音类却没有拍声轨路径');
  }
  if (choices.picture && stickerPaths.length != request.stickers.length) {
    throw ArgumentError(
      '贴纸图（${stickerPaths.length}）与请求里的贴纸'
      '（${request.stickers.length}）对不上',
    );
  }

  final rate = request.speedTier.token;
  final slowed = request.speedTier != CastSpeedTier.full;
  // 非 1× 档的视频必须重编码（复制改不了时长）。
  final reencodeVideo = choices.picture || slowed;

  // **数拍层**（#30）只在勾了画面类时装：它属于画面内容类。装了就要有序列清单
  // （没有清单就是编程错误，宁可不装配一条读不出东西的链）。
  final picture = choices.picture;
  final beatOverlay = request.beatOverlay;
  final beatLayer = picture && castBeatCountActive(beatOverlay);
  if (beatLayer && beatSlidesPath == null) {
    throw ArgumentError('数拍层要装却没有序列清单路径');
  }
  // 数拍层的输入下标：源片恒是 0 号，拍声轨（勾了声音类时）是 1 号，
  // 数拍序列紧随其后。
  final beatInputIndex = choices.sound ? 2 : 1;
  final beatGraph = beatLayer
      ? castBeatCountGraph(
          overlay: beatOverlay!,
          startLabel: 'vbase',
          endLabel: 'vbeat',
          inputIndex: beatInputIndex,
          fps: kCastRenderFps,
        )
      : const CastBeatCountGraph(nodes: [], endLabel: 'vbase');
  final beatActive = beatGraph.nodes.isNotEmpty;
  // 贴纸图的下标：源片 + 拍声轨 + 数拍序列之后。
  final firstStickerInput =
      1 + (choices.sound ? 1 : 0) + (beatActive ? 1 : 0);

  final filters = <String>[];
  if (reencodeVideo) {
    // **镜像闸门**（#27）与**取景窗口**（#28）只在勾了画面类时装上：非 1× 档的
    // 「只勾声音类」也会重编码画面（复制改不了时长），但那一次重编码只为倍速
    // ——用户没勾画面类，画面内容类的东西就不该被烤进去。
    //
    // 闸门排在 `setpts` **之前**：`enable` 判的是**源时间轴**，局部镜像片段正是
    // 源时间轴上的半开区间；排在倍速之后，`t` 会被拉伸、窗就与倍速档错开。
    final mirror = picture
        ? castMirrorFilterNodes(castMirrorGateOf(request))
        : const <String>[];
    // **取景排在镜像之后**（#28）：手机上翻转是画面件的显示层变换、取景是包在
    // 它外面的剪辑窗，窗里的像素是「翻过的画面」在那块矩形上的样子；且局部镜像
    // 是时间窗而 `crop` 不支持时间窗，只有「先翻后切窗」能逐帧跟上（见
    // `cast_framing_gate.dart` 库头）。
    final framing = picture
        ? castFramingFilterNodes(castFramingGateOf(request))
        : const <String>[];
    final content = <String>[...mirror, ...framing];
    final speed = slowed ? 'setpts=PTS/$rate,' : '';
    final layered = beatActive || (picture && request.stickers.isNotEmpty);
    if (layered) {
      // **数拍层**（#30）接在取景之后、贴纸**之前**：上屏的层序是数拍浮层
      // 挂在贴纸浮层之下（`presentation_layer.dart`），副本照这个层序。
      // 它同样排在 `setpts` 之前——时间窗判的是源时间轴（与镜像闸门同款口径）。
      filters.add(
        '[0:v]${content.isEmpty ? 'null' : content.join(',')}[vbase]',
      );
      filters.addAll(beatGraph.nodes);
      var label = beatGraph.endLabel;
      // **备注贴纸**（#29）是第二路输入，接在取景（与数拍）之后、`setpts`
      // 之前——于是 `enable` 判的也是源时间轴（见 `cast_sticker_gate.dart`
      // 库头）。没有备注时链的形状与今天逐字一致（不引入多余的中间标签）。
      if (picture && request.stickers.isNotEmpty) {
        final graph = castStickerGraph(
          stickers: request.stickers,
          // 路径表与请求一一对应：空窗的贴纸不装节点，但**仍占一个输入位**
          // （错位比多喂一个输入危险得多）。
          stickerPaths: stickerPaths,
          flip: castMirrorGateOf(request),
          selection: request.framingSelection,
          startLabel: label,
          endLabel: 'vstk',
          firstInputIndex: firstStickerInput,
          fps: kCastRenderFps,
        );
        filters.addAll(graph.nodes);
        label = graph.endLabel;
      }
      filters.add(
        '[$label]${speed}fps=$kCastRenderFps,format=yuv420p[vout]',
      );
    } else {
      final contentPrefix = content.isEmpty ? '' : '${content.join(',')},';
      filters.add(
        '[0:v]$contentPrefix${speed}fps=$kCastRenderFps,format=yuv420p[vout]',
      );
    }
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
    // **数拍层**的输入是那份 `-f concat` 清单（一格一张同尺寸 PNG、每格一段
    // 时长＝那一拍的半开窗）——整条序列只占**一路输入**，下标紧跟拍声轨。
    if (beatActive) ...<String>[
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      beatSlidesPath!,
    ],
    // 贴纸图排在拍声轨（与数拍序列）**之后**：源片恒是 0 号输入、拍声轨恒是
    // 1 号（只勾声音类时视频流原样复制的那条路一个字都不动），贴纸从 1/2/3 号
    // 起——下标由 `castStickerGraph` 的 `firstInputIndex` 与这里保持一致。
    if (picture && request.stickers.isNotEmpty) ...<String>[
      for (final path in stickerPaths) ...<String>['-i', path],
    ],
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
