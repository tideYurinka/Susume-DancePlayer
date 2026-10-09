/// 投屏渲染的**命令行装配**（纯件，零 Flutter、零 IO）：一份
/// [CastRenderRequest]（这次渲什么）+ 一份 [CastRenderStaging]（这次装哪几样
/// 边车、各在 `-i` 里的第几路）→ 一串 ffmpeg 参数。
///
/// ## 这是外部契约
///
/// 滤镜图与命令行直接决定产物，所以它们是可直测、可按片段钉住的外部契约
/// （不是实现细节）。本件因此不碰进程、不碰文件：装配在测试里逐片段断言，
/// 执行在 `cast_render_executor.dart` 那条接缝上。
///
/// **「这次装什么」由暂存输入回答**（`#47`）：混不混拍声、装不装数拍层、有没有
/// 贴纸图，读的都是编排层刚备好的那份 `CastRenderStaging`——装配层不从勾选档
/// 推导第二遍，也再没有「勾了却没有」这类要靠运行期报错兜的组合。贴纸那一路
/// 的「装哪几条」由 `cast_render_request.dart` 的 `castStagedStickerSlots`
/// 一处回答（编排层按它落盘，测试替身读同一条），装配层读的是它的产物。`#21`
/// 整改前这里有第二道按勾选档的剔除，把「暂存表与规则不一致」在测试里抹平了。
///
/// ## 两档的差别就是命令行的差别
///
/// - **只勾声音类**（且 1× 档）：`-c:v copy` —— 视频流原样复制、不重编码，
///   音轨重编码并把拍声 `amix` 进来。这是「秒级出结果」的全部机关。
/// - **勾了画面类**：视频重编码（`h264_mediacodec` + 显式码率/ GOP / 帧率 /
///   像素格式），画面滤镜链进 `filter_complex`；不勾声音类时音轨 `-c:a copy`
///   （**有例外**：范围生效或非 1× 档时音轨也得重编码——复制改不了范围、也改
///   不了时长，音轨不跟着收 / 不跟着缩放就会与画面错开）。
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
/// `atempo` 拉音轨（拍声轨跟着一起缩放，否则换档就错开）。1× 档**倍速**这两句
/// 一个字段都不写，与「不设倍速」逐字一致（范围生效时链上另会多出 `trim` /
/// `setpts=PTS-STARTPTS` 那一对，见下节——与倍速无关）。**非 1× 档的视频不能
/// 复制**——`-c:v copy` 改不了时长，所以只勾声音类也只在那三档里保留「原样
/// 复制」，非 1× 档退化成重编码（规格里「只勾声音 = 视频流不重编码」那条说的是
/// 1× 这个默认档）。
///
/// ## 范围：首线→尾线，落在链的**中段**
///
/// 规格要求「从 0 整片解码、用时间窗偏移表达、不用快速定位」。本件因此不产出
/// `-ss` / `-to` / `-t`（快速定位会把滤镜的时间基准归零，各闸门的时间窗就会与
/// 手机上那一份错开），范围由 `cast_range_gate.dart` 的 `trim` / `atrim` 表达：
/// 它们排在**全部层之后、倍速 `setpts` 之前**（与其他时间窗同处源时间轴那一段），
/// 紧接一句 `setpts=PTS-STARTPTS` 把副本自己的时间轴挪到 0。画面与音轨（含拍声
/// 轨）收在同一段上。
///
/// **复制档明确不接受范围**：只勾声音类 + 1× 档是唯一一条视频流原样复制的路
/// （`-c:v copy`），复制出来的流改不了长度、滤镜链也碰不到它——那一档推的是
/// 整片，音轨同样照整片混。范围落在视频被重编码的那些档（勾了画面类，或非 1×
/// 档）。详见 `cast_range_gate.dart` 的库头。
///
/// ## 分辨率档：链尾一个缩放节点（#36）
///
/// 画面链尾按**渲染分辨率档**装一枚 `scale=-2:'min(<上限>,ih)',setsar=1`：保证
/// 档上限是 1080 行、720p 档是 720 行——高过上限才降、**不足上限原样留着**
/// （只降不升；取景窗口比上限小时放大与「不足以 1× 实时就宁可降分辨率」相反，
/// 见 `cast_encoder_realtime.dart`），宽度按源画面比例现算（`-2` 顺带保证
/// 偶数），**不拉伸**画面，方像素由那条 `setsar=1` 钉住（`scale` 自己会改 SAR
/// 去保 DAR）。码率跟着档走（1080p 档 8M / 720p 档 4M）。它只在**视频真重编码**
/// 时才进命令：只勾声音 + 1× 是 `-c:v copy`，没有可降的编码
/// （[castRenderReencodesVideo]）。
///
/// **链序（#37 与 #36 合起来定死）**：范围 `trim` / 音轨 `atrim` 在**全部
/// overlay 之后、倍速 `setpts` 之前**（它们判的是源时间轴那一段）；分辨率档的
/// `scale` 与码率在**链尾 `fps` 之前**。两段互不干涉：缩放不改 `t`，时间窗也不
/// 看像素尺寸——`trim → setpts → scale → fps → format` 这个次序同时满足两条规格。
library;

import 'cast_beat_gate.dart';
import 'cast_framing_gate.dart';
import 'cast_mirror_gate.dart';
import 'cast_range_gate.dart';
import 'cast_render_request.dart';
import 'cast_sticker_gate.dart';

/// 画面档的视频编码器：已链接 ffmpeg 包在 Android 上的 H.264 硬编
/// （ADR-0004 的渲染路线结论）。
const String kCastRenderVideoEncoder = 'h264_mediacodec';

/// 画面档的 GOP 与目标帧率（编码参数不靠默认值）。帧率与**问编码器的那一档**
/// 是同一个数（`kCastGuaranteeQueryTarget.fps`）：问什么就渲什么。
/// **码率不在这里**：它随**渲染分辨率档**走（1080p 档 8M / 720p 档 4M，见
/// `cast_encoder_realtime.dart`）。
const int kCastRenderGop = 60;
const int kCastRenderFps = 30;

/// 音轨的重编码参数（拍声要进这条轨，统一到同一个采样格式）。
const String kCastRenderAudioBitrate = '192k';
const int kCastRenderSampleRate = 48000;
const int kCastRenderChannels = 2;

/// 装配一条投屏渲染命令。
///
/// [staging] 是**这一次的暂存输入**（`#47`）：编排层刚备好的边车文件与它们在
/// `-i` 里的下标（`cast_render_request.dart` 的 `CastRenderStaging`）。装配层
/// 只按这份输入落命令——**这次装什么**（混不混拍声、装不装数拍层、有没有贴纸
/// 图）读的都是它，不从勾选档推导第二遍；路径与下标成对给全，`-i` 表与滤镜图
/// 因此不可能对不齐（这三条以前靠运行期 `throw` 兜）。
List<String> buildCastRenderArguments({
  required CastRenderRequest request,
  required String outputPath,
  required CastRenderStaging staging,
}) {
  final choices = request.choices;
  if (!choices.renders) {
    throw ArgumentError('都不勾 = 不渲染：调用方直接推原片，不该走到命令装配');
  }

  final rate = request.speedTier.token;
  final slowed = request.speedTier != CastSpeedTier.full;
  // 非 1× 档的视频必须重编码（复制改不了时长）。
  final reencodeVideo = castRenderReencodesVideo(
    request.choices,
    request.speedTier,
  );
  // **分辨率档**（#36）：保证 1× 实时 = 保证档（链尾钉高 1080 行）；不保证或
  // 问不到 = 720p（链尾钉高 720 行）。两档的宽度都按源画面比例、都只降不升。
  // 它只在**视频真重编码**时才进命令——只勾声音 + 1× 是 `-c:v copy`，没有可降
  // 的编码（那时分辨率档只活在缓存键里，见 `cast_render_request.dart`）。
  final scaleNode = '${request.resolution.scaleNode},';

  // **这次装什么，读的是暂存输入**：拍声轨在不在就是混不混拍声，数拍序列清单
  // 在不在就是装不装数拍层（清单自带要装的那一层），贴纸图与请求里的贴纸成对
  // （条数不可能对不上）。**贴纸这一路同样只读暂存表**（`#21` 整改）：装哪几条
  // 是编排层按 `castStagedStickerSlots` 一条规则备的料，装配层不从勾选档再剔
  // 一遍——「这次装什么」只有一处回答，测试替身与编排层读的也是它。
  final picture = choices.picture;
  final beatTrack = staging.beatTrack;
  final beatSlides = staging.beatSlides;
  final stickers = staging.stickers;
  final beatGraph = beatSlides == null
      ? const CastBeatCountGraph(nodes: [], endLabel: 'vbase')
      : castBeatCountGraph(
          slides: beatSlides,
          startLabel: 'vbase',
          endLabel: 'vbeat',
          fps: kCastRenderFps,
        );
  final beatActive = picture && beatGraph.nodes.isNotEmpty;

  final filters = <String>[];
  // **范围**（#37）：首线→尾线，源时间轴上的半开区间。复制档明确不收（见
  // `cast_range_gate.dart` 库头），故这里拿到非空范围的档，视频一定在重编码。
  // 节点由**范围自己**给（`CastRange.videoNodes` / `audioNodes`），前缀拼接
  // 走 `cast_range_gate.dart` 那一处共用件——链上三处形状一致，不各写一遍。
  final range = castActiveRangeOf(request);
  final rangeVideoPrefix = castFilterNodesPrefix(
    range == null ? const [] : range.videoNodes,
  );
  final rangeAudioPrefix = castFilterNodesPrefix(
    range == null ? const [] : range.audioNodes,
  );
  // **音轨要不要重编码**：混拍声（暂存里有那条轨）、非 1× 档（复制改不了时长
  // ——视频按 `setpts` 缩放了，音轨不跟就会与画面错开）、或范围生效（复制改不
  // 了范围）。三者都是「`-c:a copy` 做不到」的事；只有「1× + 无范围 + 不混拍
  // 声」这一档仍原样复制音轨。
  final reencodeAudio = beatTrack != null || slowed || range != null;
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
    // **链尾只此一处**：范围 → 倍速 → 分辨率档 → `fps` / 像素格式收尾。前段接
    // 在哪个标签上由下面两条分支定，尾段两边逐字相同。
    final videoTail =
        '$rangeVideoPrefix$speed$scaleNode'
        'fps=$kCastRenderFps,format=yuv420p[vout]';
    final layered = beatActive || stickers.isNotEmpty;
    if (layered) {
      // 要接层（数拍 / 贴纸）时先给内容层落一个标签；没有内容层就是 `null` 直通
      // （链上总得有个上游）。
      filters.add(
        '[0:v]${content.isEmpty ? 'null' : content.join(',')}[vbase]',
      );
      var label = 'vbase';
      if (beatActive) {
        // **数拍层**（#30）接在取景之后、贴纸**之前**：上屏的层序是数拍浮层
        // 挂在贴纸浮层之下（`presentation_layer.dart`），副本照这个层序。
        // 它同样排在 `setpts` 之前——时间窗判的是源时间轴（与镜像闸门同款口径）。
        filters.addAll(beatGraph.nodes);
        label = beatGraph.endLabel;
      }
      if (stickers.isNotEmpty) {
        // **备注贴纸**（#29）是第二路输入，接在取景（与数拍）之后、`setpts`
        // 之前——于是 `enable` 判的也是源时间轴（见 `cast_sticker_gate.dart`
        // 库头）。没有备注时链的形状与今天逐字一致（不引入多余的中间标签）。
        final graph = castStickerGraph(
          // 贴纸与它的图成对给全：空窗的贴纸不装节点，但**仍占一个输入位**
          // （错位比多喂一个输入危险得多）。
          sheets: stickers,
          flip: castMirrorGateOf(request),
          selection: request.framingSelection,
          startLabel: label,
          endLabel: 'vstk',
          fps: kCastRenderFps,
        );
        filters.addAll(graph.nodes);
        label = graph.endLabel;
      }
      filters.add('[$label]$videoTail');
    } else {
      filters.add('[0:v]${castFilterNodesPrefix(content)}$videoTail');
    }
  }
  if (reencodeAudio) {
    final speed = slowed ? 'atempo=$rate,' : '';
    filters.add(
      '[0:a]$rangeAudioPrefix${speed}aresample=$kCastRenderSampleRate[amain]',
    );
    if (beatTrack != null) {
      filters.add(
        '[${beatTrack.index}:a]$rangeAudioPrefix'
        '${speed}aresample=$kCastRenderSampleRate[abeat]',
      );
      filters.add(
        '[amain][abeat]amix=inputs=2:duration=first:dropout_transition=0[aout]',
      );
    }
  }

  return <String>[
    '-hide_banner',
    '-y',
    '-i',
    request.videoPath,
    // 边车输入的次序 = 它们在**暂存输入**里的下标次序：拍声轨 → 数拍序列 →
    // 逐条贴纸图。路径与下标同出一处，命令行与滤镜图不可能各说各话。
    if (beatTrack != null) ...<String>['-i', beatTrack.path],
    // **数拍层**的输入是那份 `-f concat` 清单（一格一张同尺寸 PNG、每格一段
    // 时长＝那一拍的半开窗）——整条序列只占**一路输入**。
    if (beatActive) ...<String>[
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      beatSlides!.sidecar.path,
    ],
    // 贴纸图排在拍声轨（与数拍序列）**之后**：源片恒是 0 号输入，每条贴纸的下
    // 标由暂存输入给全（`castStickerGraph` 的 `sheets` 读同一个数）。
    for (final sheet in stickers) ...<String>['-i', sheet.sidecar.path],
    if (filters.isNotEmpty) ...<String>['-filter_complex', filters.join(';')],
    '-map',
    reencodeVideo ? '[vout]' : '0:v',
    if (beatTrack != null) ...<String>[
      '-map',
      '[aout]',
    ] else if (reencodeAudio) ...<String>[
      // 不混拍声但音轨也得重编码（范围收了这一段，或这一档要跟画面一起缩放）：
      // 取上面那条收窄 / 缩放过的 `[amain]`，而不是原样复制整片音轨。
      '-map',
      '[amain]',
    ] else if (choices.picture) ...<String>['-map', '0:a'],
    '-c:v',
    reencodeVideo ? kCastRenderVideoEncoder : 'copy',
    if (reencodeVideo) ...<String>[
      '-b:v',
      request.resolution.bitrate,
      '-g',
      '$kCastRenderGop',
      '-r',
      '$kCastRenderFps',
      '-pix_fmt',
      'yuv420p',
    ],
    if (reencodeAudio) ...<String>[
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
