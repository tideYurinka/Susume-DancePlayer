/// **投屏贴纸闸门**（纯件，零 Flutter、零 IO）：把「一条备注贴纸 + 取景选区 +
/// 镜像闸门」折成画面滤镜链里的**第二路输入**与 `overlay` 节点。
///
/// ## 贴纸是第二路输入（不是画上去的字）
///
/// 贴纸的字形、点名取色与描边由播放页侧按**上屏同一份 span 与样式**光栅化成
/// 一张带 alpha 的单帧 PNG（`player/cast_sticker_sheet.dart`），这里只管把它
/// 当第二路输入接进画面链。ffmpeg 的 `drawtext` 做不到「逐帧与手机一致」：字体
/// 度量、点名分段取色、纯白点名的双层描边都得按 Flutter 那一套来，而在链上再
/// 拼一遍等于把样式口径声明两处。
///
/// ## 三条硬口径（规格的 Further Notes 与票的要点）
///
/// - **归到主片帧率网格**：第二路显式过 `fps=<主片帧率>`。两路帧率不同时，
///   时间窗的判定网格会与主片错开——窗的进出就会漏一帧或多一帧。
/// - **全分辨率 alpha**：输入流进 `format=rgba`，`scale2ref` 缩过之后再送回
///   一次 `format=rgba`（不带这一句，alpha 会在格式协商里当场丢掉、贴纸变不
///   透明），混合在 `overlay=…:format=rgb` 里做——**乘**着 alpha 混合，而不是
///   设一个透明度。任何改写 alpha 的节点（`alphaextract` / `geq` / `lut` /
///   `format=yuva420p`）都不出现。
/// - **单帧输入不配循环、不取最短**：PNG 只解出一帧，靠 `overlay` 的
///   `eof_action=repeat` 把末帧铺满时间轴，因此输入侧不配 `-loop 1`、全命令也
///   不配 `-shortest`（配了会把副本截到一帧）。
///
/// ## 与上屏同源
///
/// 落位走的是上屏那一份数学（`player/note_sticker_layout.dart` 的
/// `noteStickerRect`）：几何先按**取景窗口**换算（`(源点 − 选区原点) ÷ 选区
/// 尺寸`）、再按**源视频面方向**做水平翻转（镜像时 `x → 1 - x`，贴纸仍贴它
/// 标的那个舞者）、最后逐轴钳进画面矩形（该轴装不下即居中）。尺寸**不随取景
/// 缩放**——宽度分数就是「上屏量测尺寸 ÷ 上屏画面矩形」。
///
/// 镜像状态是**逐帧**的（全局 ⊕ 局部片段）：同一张贴纸的窗口跨过片段端点时，
/// 它的横向落位在那一刻换一次。因此一张贴纸按**镜像状态不变的分段**出多条
/// `overlay` 节点——每段各自一条半开时间窗、各自的落位，合起来恰好盖满贴纸的
/// 窗口（不重不漏）。
///
/// ## 链上的位置
///
/// 贴纸节点接在**取景之后**（贴的是取景后那一块画面）、倍速 `setpts` **之前**
/// ——于是 `enable` 判的是源时间轴，与手机上按源位置求值的那一份同轴（与镜像
/// 闸门同款口径）。
///
/// ## 尺寸为什么靠 `scale2ref`
///
/// 输出帧尺寸 = 取景裁切出来的那一块（源尺寸与选区决定，**装配期未知**，见
/// `cast_framing_gate.dart`），而贴纸的尺寸是「帧的一个比例」。比例要落在帧上
/// 就得读主路尺寸，`overlay` 自己不做缩放，于是第二路先过 `scale2ref`（它读
/// 参考路的 `main_w`/`main_h` 成比例缩放），再把参考路送回 overlay 当主路。
library;

import '../annotation/framing_selection.dart';
import '../surface_direction/surface_direction.dart';
import 'cast_framing_gate.dart' show castFramingActive, castRatioLiteral;
import 'cast_mirror_gate.dart' show castSeconds;
import 'cast_render_request.dart';

/// 贴纸在**上屏画面矩形**（取景后那一块 = 投屏副本的帧）里的落位：中心 + 尺寸
/// 全按该矩形归一化（0–1 向右/向下）。
class CastStickerPlacement {
  const CastStickerPlacement({
    required this.centerX,
    required this.centerY,
    required this.width,
    required this.height,
  });

  /// 落位中心横坐标（含随面翻转与钳制后的取值）。
  final double centerX;

  /// 落位中心纵坐标。
  final double centerY;

  /// 落位宽（帧宽的比例）。
  final double width;

  /// 落位高（帧高的比例）。
  final double height;

  /// `overlay` 的横向表达式：`(W*中心)-(w/2)`（`w` 是被缩放后的第二路宽度）。
  String get overlayX => '(W*${castRatioLiteral(centerX)})-(w/2)';

  /// `overlay` 的纵向表达式。
  String get overlayY => '(H*${castRatioLiteral(centerY)})-(h/2)';

  @override
  bool operator ==(Object other) =>
      other is CastStickerPlacement &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(centerX, centerY, width, height);

  @override
  String toString() =>
      'CastStickerPlacement($centerX, $centerY, $width×$height)';
}

/// 贴纸可见的一段：**镜像状态不变**的半开时间窗 `[startMs, endMs)` + 那一刻的
/// 落位。一张贴纸的窗口跨过局部镜像片段的端点时会有多段。
class CastStickerSegment {
  const CastStickerSegment({
    required this.startMs,
    required this.endMs,
    required this.mirrored,
    required this.placement,
  });

  /// 这一段在**源时间轴**上的起点（毫秒，含）。
  final int startMs;

  /// 这一段在源时间轴上的终点（毫秒，不含）。
  final int endMs;

  /// 这一段的源视频面是否呈镜像（与 [SourceVideoFlip.mirroredAt] 同判）。
  final bool mirrored;

  /// 这一段的落位。
  final CastStickerPlacement placement;

  /// 这一段的 `enable` 表达式：半开区间 `[起, 止)` → `gte(t,起)*lt(t,止)`，
  /// **不用 `between`**（它两端都含、会多一帧）。
  String get enableExpression =>
      'gte(t,${castSeconds(startMs / 1000)})*lt(t,${castSeconds(endMs / 1000)})';

  @override
  String toString() =>
      'CastStickerSegment($startMs–$endMs, mirrored: $mirrored)';
}

/// 一条贴纸在给定镜像状态下的落位；取值退化（非有限、零/负尺寸）时给 `null`
/// ——**不装**这一条，而不是往滤镜图里塞一个坏表达式。
CastStickerPlacement? castStickerPlacementOf({
  required CastSticker sticker,
  required FramingSelection? selection,
  required bool mirrored,
}) {
  final width = sticker.widthFraction;
  final height = sticker.heightFraction;
  if (!width.isFinite ||
      !height.isFinite ||
      width <= 0 ||
      height <= 0 ||
      !sticker.centerX.isFinite ||
      !sticker.centerY.isFinite) {
    return null;
  }
  // 取景窗口换算：只有**生效的**选区才成窗（整帧 / 退化选区 = 未取景，与裁切
  // 闸门同判）——未取景时窗口即整帧、映射恒等。
  final window = castFramingActive(selection) ? selection : null;
  final mappedX = window == null
      ? sticker.centerX
      : (sticker.centerX - window.left) / window.width;
  final mappedY = window == null
      ? sticker.centerY
      : (sticker.centerY - window.top) / window.height;
  // 随面翻转：镜像时贴纸仍贴它标的那个舞者（横向取反，文字本身不翻）。
  final placedX = mirrored ? 1 - mappedX : mappedX;
  // 逐轴钳制：轴上装得下 → 中心钳进框（贴纸完整留在画面内）；装不下 → 该轴
  // 居中（与上屏 noteStickerRect 的钳制退化同款）。
  return CastStickerPlacement(
    centerX: width >= 1 ? 0.5 : placedX.clamp(width / 2, 1 - width / 2),
    centerY: height >= 1 ? 0.5 : mappedY.clamp(height / 2, 1 - height / 2),
    width: width,
    height: height,
  );
}

/// 一条贴纸的可见分段（源时间轴、升序、首尾相接、半开区间）。
///
/// 分段依据是**源视频面翻转闸门**（[SourceVideoFlip]——那是源视频面方向的唯一
/// 声明处）：全局镜像整片施加、局部镜像总开关关掉时片段整组不参与，于是
/// 「镜像 / 不镜像」在贴纸窗内交替出现，端点即片段端点。空窗与倒置窗给空表。
List<CastStickerSegment> castStickerSegmentsOf({
  required CastSticker sticker,
  required FramingSelection? selection,
  required SourceVideoFlip flip,
}) {
  if (!sticker.visible) return const [];
  final local = <(int, int)>[
    for (final window in flip.localActiveWindows)
      if (window.startMs < window.endMs) (window.startMs, window.endMs),
  ];
  // 切分点 = 贴纸窗两端 + 落在窗内的每个片段端点。
  final cuts = <int>{sticker.startMs, sticker.endMs};
  for (final (start, end) in local) {
    if (start > sticker.startMs && start < sticker.endMs) cuts.add(start);
    if (end > sticker.startMs && end < sticker.endMs) cuts.add(end);
  }
  final points = cuts.toList()..sort();
  final segments = <CastStickerSegment>[];
  for (var i = 0; i + 1 < points.length; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (end <= start) continue;
    // 半开区间：左端点就在这一段里，用它判状态即可（端点即片段边界）。
    final localActive = local.any(
      (window) => window.$1 <= start && start < window.$2,
    );
    final mirrored = flip.globalMirrored ^ localActive;
    final placement = castStickerPlacementOf(
      sticker: sticker,
      selection: selection,
      mirrored: mirrored,
    );
    if (placement == null) return const [];
    // 相邻同状态的两段接起来（片段端点落在贴纸窗内、状态却没变时不分叉）。
    final previous = segments.isEmpty ? null : segments.last;
    if (previous != null &&
        previous.mirrored == mirrored &&
        previous.endMs == start) {
      segments[segments.length - 1] = CastStickerSegment(
        startMs: previous.startMs,
        endMs: end,
        mirrored: mirrored,
        placement: placement,
      );
      continue;
    }
    segments.add(
      CastStickerSegment(
        startMs: start,
        endMs: end,
        mirrored: mirrored,
        placement: placement,
      ),
    );
  }
  return segments;
}

/// 贴纸闸门在画面链里装出来的东西：节点表 + 要追加的输入路径 + 接续标签。
class CastStickerGraph {
  const CastStickerGraph({
    required this.nodes,
    required this.inputPaths,
    required this.endLabel,
  });

  /// 进 `filter_complex` 的贴纸节点（按贴纸次序、按分段次序）。
  final List<String> nodes;

  /// 要追加成 `-i` 的贴纸 PNG 路径（次序 = 请求里的贴纸次序，下标即输入序号；
  /// 没装节点的那一条仍然占一个输入位——多喂一个输入是无害的，错位才是有害的）。
  final List<String> inputPaths;

  /// 贴纸链的输出标签（无贴纸时等于 [startLabel]）。
  final String endLabel;
}

/// 装配贴纸节点。
///
/// [firstInputIndex] 是第一条贴纸 PNG 在 `-i` 里的下标（源片 `0`、拍声轨可能是
/// `1`）；[startLabel] 是前置画面链（镜像 + 取景）的输出标签；[fps] 是主片帧率
/// （第二路归到它上面，且与链尾那个 `fps` 同一个值）。
CastStickerGraph castStickerGraph({
  required List<CastSticker> stickers,
  required List<String> stickerPaths,
  required SourceVideoFlip flip,
  required String startLabel,
  required String endLabel,
  required int firstInputIndex,
  required int fps,
  FramingSelection? selection,
}) {
  if (stickerPaths.length != stickers.length) {
    throw ArgumentError(
      '贴纸路径（${stickerPaths.length}）与贴纸（${stickers.length}）对不上',
    );
  }
  final allSegments = <List<CastStickerSegment>>[
    for (final sticker in stickers)
      castStickerSegmentsOf(sticker: sticker, selection: selection, flip: flip),
  ];
  // 最后一个**真装出节点**的贴纸：只有它的末段用链尾标签（空窗的贴纸不占
  // 标签，链尾不能挂在一条根本不存在的节点上）。
  var lastSticker = -1;
  for (var i = 0; i < allSegments.length; i++) {
    if (allSegments[i].isNotEmpty) lastSticker = i;
  }
  if (lastSticker < 0) {
    return CastStickerGraph(
      nodes: const [],
      inputPaths: stickerPaths,
      endLabel: startLabel,
    );
  }
  final nodes = <String>[];
  var label = startLabel;
  for (var i = 0; i <= lastSticker; i++) {
    final segments = allSegments[i];
    if (segments.isEmpty) continue;
    final input = firstInputIndex + i;
    // 一条贴纸一条输入流；窗口跨过镜像片段端点时这一条流要**分叉**给多条
    // overlay 链（滤波器的一个输出 pad 只能被连一次——不分叉就是
    // 「stream specifier matches no streams」）。
    nodes.add('[$input:v]format=rgba,fps=$fps[csti$i]');
    final streamLabels = <String>[];
    if (segments.length == 1) {
      streamLabels.add('csti$i');
    } else {
      for (var j = 0; j < segments.length; j++) {
        streamLabels.add('csti${i}_$j');
      }
      nodes.add(
        '[csti$i]split=${segments.length}'
        '${streamLabels.map((label) => '[$label]').join()}',
      );
    }
    for (var j = 0; j < segments.length; j++) {
      final segment = segments[j];
      // 每段一条链：第二路先按帧的比例缩放（读参考路的 main_w/main_h），
      // 缩完把 alpha 送回全分辨率，再叠到主路上。
      // `iw`/`ih` 是 `scale2ref` 里**参考路**（第二路输入 = 取景后的画面）的尺寸
      // ——读 ffmpeg 的 `scale_eval_dimensions`：`inlink = inputs[1]`、`main_w` 才是
      // 被缩放那一路自己的宽。用 `main_w` 会把贴纸按它**自己的像素数**缩放（同一
      // 张图换个密度就换大小）；用 `iw` 才是「帧的一个比例」，与 PNG 的像素尺寸
      // 无关。
      nodes.add(
        '[${streamLabels[j]}][$label]scale2ref='
        'w=iw*${castRatioLiteral(segment.placement.width)}:'
        'h=ih*${castRatioLiteral(segment.placement.height)}'
        '[cstk${i}_$j][cstr${i}_$j]',
      );
      nodes.add('[cstk${i}_$j]format=rgba[csta${i}_$j]');
      final last = i == lastSticker && j == segments.length - 1;
      final output = last ? endLabel : 'csm${i}_$j';
      nodes.add(
        '[cstr${i}_$j][csta${i}_$j]overlay='
        'x=${segment.placement.overlayX}:'
        'y=${segment.placement.overlayY}:'
        "enable='${segment.enableExpression}':"
        'format=rgb:eof_action=repeat[$output]',
      );
      label = output;
    }
  }
  return CastStickerGraph(
    nodes: nodes,
    inputPaths: stickerPaths,
    endLabel: label,
  );
}
