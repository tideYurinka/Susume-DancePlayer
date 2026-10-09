/// **投屏范围闸门**（纯件，零 Flutter、零 IO；`#37`）：把「这支舞的首线→尾线」
/// 折成画面滤镜链中段的 `trim` 节点与音轨链的 `atrim` 节点，并回答这份请求的
/// 副本覆盖源时间轴上的哪一段、烤出来多长。
///
/// ## 范围是**源时间轴**上的半开区间 `[起, 止)`
///
/// 口径与既有各时间窗（局部镜像片段、贴纸窗、数拍格）逐字一致：左端在范围里、
/// 右端不在——`trim=start=起:end=止` / `atrim=start=起:end=止` 判的就是这一条
/// （`between` 那种两端都含的写法在本域一概不用，见
/// `cast_mirror_gate.dart`）。端点因此与手机上「按源位置求值」的那一份对齐：
/// 首线那一刻已经在新副本里、尾线那一刻已经不在了。
///
/// ## 为什么不用快速定位（`-ss`）
///
/// `-ss` 会把滤镜的时间基准归零：各闸门的 `enable`（局部镜像、贴纸）与数拍
/// 序列的每一格判的都是**源时间轴**上的时刻，基准一归零，同一个窗就会与手机上
/// 那一份错开「起」那么多。范围因此用 `trim` 这类**中段**表达——它落在滤镜链
/// 里、与其他时间窗同处（都在倍速 `setpts` 之前），输入端仍是「从 0 整片解码」。
/// 命令行首/尾不出现 `-ss` / `-t` / `-to`（`cast_render_plan_test.dart` 有在场
/// 与不在场断言）。
///
/// ## 范围排在**所有层之后**、倍速 `setpts` 之前
///
/// 层（局部镜像闸门、取景、数拍、贴纸）判的都是源时间轴，收窄范围必须发生在
/// 它们**都看过整片之后**：`trim` 排在链的最后一层之后，于是「哪一帧该翻、
/// 哪一帧该有贴纸」在裁掉范围外那些帧之前就已经定好；第二路输入（贴纸单帧与
/// 数拍序列）也因此仍与主片同轴（它们没有跟着范围被偏移过）。
/// `setpts=PTS-STARTPTS` 紧接 `trim`：副本自己的时间轴从 0 起（接收端按「从
/// 文件头开始的相对时间」报位置），倍速 `setpts` 排在它之后——先后定死。
///
/// ## 复制档明确**不接受**范围
///
/// **只勾声音类 + 1× 档**是唯一一条视频流原样复制的路（`-c:v copy`，秒级出结果
/// 的机关）。复制出来的流改不了长度：滤镜链碰不到它，而命令行上的
/// `-ss` / `-t` 又是本票明确不用的东西。本票的回答是：**这一档不收范围**——
/// 它推的就是整片，音轨也照整片混（只收视频、不收音轨会让两者对不上）。范围落
/// 在**视频被重编码的那些档**（勾了画面类，或非 1× 档）：那些档里 `trim` 与
/// `atrim` 一起生效，画面与音轨收在同一段上。
///
/// ## 首尾线在缓存键里已经覆盖
///
/// 首尾线是**标注内容**的一部分：`cast_annotation_fingerprint.dart` 收的
/// 「首尾区间」就是 `rangeStart` / `rangeEnd`。改首尾线即换指纹、即换缓存键，
/// 重渲是键的结构性后果——范围因此**不**作为新的独立分量重复进键（重复只会让
/// 键更长，挡不住一次多出来的漏命中）。
///
/// ## 副本的时间轴原点挪到了首线
///
/// 副本自己的时间轴从 0 起（`setpts=PTS-STARTPTS`），于是「源坐标 ↔ 副本坐标」
/// 不再是单纯的按倍率缩放：副本 0 现在对应**首线**。这份换算由运行域
/// （`player/cast_run.dart`）按 [castCopyDurationOf] 与 [CastRange.start] 做，
/// 进度分母（`cast_render_orchestrator.dart`）读的也是同一条时长。
library;

import 'cast_mirror_gate.dart' show castSeconds;
import 'cast_render_request.dart';
import 'cast_speed_tier.dart';

/// 投屏副本的范围（**源时间轴**上的半开区间 `[start, end)`）：这支舞的
/// 首线 → 尾线（`AnnotationTimeline.rangeStart` / `rangeEnd`）。
class CastRange {
  const CastRange({required this.start, required this.end});

  /// 起点（含）：这支舞的**首线**。
  final Duration start;

  /// 终点（不含）：这支舞的**尾线**。
  final Duration end;

  /// 空区间（起点不早于终点）：没有可收的一段，链上一个节点都不装。
  bool get isEmpty => end <= start;

  /// 这一段有多长（空区间给零，不造出负数时长）。
  Duration get duration => end > start ? end - start : Duration.zero;

  /// 是不是**整片**：起点不晚于 0、终点不早于整片时长。
  bool isWholeVideo(Duration videoDuration) =>
      start <= Duration.zero && end >= videoDuration;

  /// 画面链的**范围节点**（`trim` + 时间基准归零）：无范围 = 空表。
  ///
  /// 排在链的最后一层之后、倍速 `setpts` 之前（见库头）。
  List<String> get videoNodes => <String>[
    'trim=start=${castSeconds(start.inMilliseconds / 1000)}:'
        'end=${castSeconds(end.inMilliseconds / 1000)}',
    'setpts=PTS-STARTPTS',
  ];

  /// 音轨链的**范围节点**（`atrim` + 时间基准归零）：无范围 = 空表。
  ///
  /// 源音轨与拍声轨各接一份：两条收在同一段上，混出来的拍声才不偏。
  List<String> get audioNodes => <String>[
    'atrim=start=${castSeconds(start.inMilliseconds / 1000)}:'
        'end=${castSeconds(end.inMilliseconds / 1000)}',
    'asetpts=PTS-STARTPTS',
  ];

  @override
  bool operator ==(Object other) =>
      other is CastRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() =>
      'CastRange(${start.inMilliseconds}ms–${end.inMilliseconds}ms)';
}

/// 这块范围这次落不落进链：请求没带范围（null）、空区间、整片都算「不收」。
///
/// **整片不装节点**是硬口径：未设首尾线的舞（首线 0、尾线就是视频时长）产出的
/// 命令行与不设范围逐字一致——没有多余的 `trim` / `setpts`，音轨也不因此多走
/// 一次重编码。
bool castRangeActive(CastRange? range, Duration videoDuration) =>
    range != null && !range.isEmpty && !range.isWholeVideo(videoDuration);

/// 这次**生效的范围**（null = 收整片）——复制档明确不收（见库头）。
CastRange? castActiveRangeOf(CastRenderRequest request) {
  // 复制档（`-c:v copy`）：视频流原样复制，滤镜链碰不到它，范围切不动。
  // 「这次要不要重编码视频」问的是唯一那一处判据
  // （`cast_render_request.dart` 的 `castRenderReencodesVideo`），不在这里手写
  // 第二份同样的条件。
  if (!castRenderReencodesVideo(request.choices, request.speedTier)) {
    return null;
  }
  return castRangeActive(request.range, request.duration)
      ? request.range
      : null;
}

/// 一串滤镜节点 → 它们在**滤镜链里的前缀写法**：空表给空串，否则把节点用
/// `,` 连起来再补一个尾逗号（好接在链的下一段前面）。
///
/// 链上三处（范围画面节点、范围音轨节点、取景那条内容节点）都是这个形状：
/// 「有就接上、没有就一个字不写」——收成一处，免得每处各写一遍前缀拼接。
String castFilterNodesPrefix(List<String> nodes) =>
    nodes.isEmpty ? '' : '${nodes.join(',')},';

/// 这份请求的副本覆盖的**源时间跨度**：范围生效 = 那一段；否则整片。
Duration castCopySourceDurationOf(CastRenderRequest request) {
  final range = castActiveRangeOf(request);
  return range?.duration ?? request.duration;
}

/// 这份请求烤出来的**副本时长**（进度分母、遥控坐标钳制）：源跨度按
/// **投屏倍速档**换算（`setpts=PTS/rate` 的直接后果；0.5× 档是它的两倍）。
Duration castCopyDurationOf(CastRenderRequest request) =>
    castCopyDuration(castCopySourceDurationOf(request), request.speedTier);

/// 这份请求的副本的**时间轴原点**落在源时间轴上的哪一刻：范围生效 = 首线，
/// 否则源片 0（复制档不收范围，故原点也留在 0）。
///
/// 副本 0 对应源上的这一刻——运行域（`player/cast_run.dart`）的源坐标 ↔ 副本
/// 坐标换算从它起算，不是从源片 0 起算。
Duration castCopySourceStartOf(CastRenderRequest request) =>
    castActiveRangeOf(request)?.start ?? Duration.zero;
