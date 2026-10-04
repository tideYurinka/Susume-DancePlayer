/// 轨道带几何值对象：横向几何读取侧的单一来源。
///
/// 由「生效窗口 + 总时长 + 带宽（+ 轨道片头带宽）」求值的恒非空值对象：把
/// 「当前几何是什么」收成一处。接口三层——
///
/// ① **可映射吗**（[isMappable]）：唯一空态谓词，覆盖总时长未知/非正、
///    内容区宽非正（带宽减轨道片头带）；窗口退化在求值时即归一
///    为全宽（[effectiveWindow]），不进入空态。
/// ② **原语**：每像素微秒（[microsecondsPerPixel]）、像素→时长
///    （[pixelToDuration]）、时间→像素（[timeToPixel]）、像素→时间
///    （[pixelToTime]），含带内像素钳制（[clampPixel]）。
/// ③ **便捷答案**：给局部像素点得到学习段轨命中目标（[learningHitAt]），
///    三个命中宽度常量按同一取整口径换算为时长，支持收窄触发窗覆盖参数
///    （[TrackBandGeometry.learningHitAt] 的 `narrowedLineHalfWidth`）；
///    段体专用答案 [learningSegmentHitAt] 供长按圈选（不认线与首尾线的
///    命中窗）。
/// 「某纵坐标属于哪一行」（[rowAt]）委派轨道行表（[TrackRowTable]），不
/// 重复实现。
///
/// **内容区**：时间轴零点之左那一段让给**轨道片头**列
/// （[prefixWidth]，0 = 不让位）。内容映射因此落在 `[contentLeft, width]`；
/// 片头列占 `[prefixLeft, prefixRight]`（右缘 = 非钳制的零点屏上 x，随窗口
/// 平移滑出可视带）。让位宽随窗口收回：[contentLeft] = 片头列
/// 在带内的可见宽，零点完全滑出后归 0、整带归内容；片头位置与让位宽同出
/// 一份「不让位」参考映射，不自指。片头只借横向的一段，不改纵向几何、
/// 不参与行命中。
///
/// ## 模块不变量
///
/// 1. 几何值与时间轴恒非空；「没有可映射几何」只由 [TrackBandGeometry.isMappable]
///    一种谓词表达，不与读取层可空并存（见下）。
/// 2. [TrackBandGeometry.effectiveWindow] 永不返回不合法窗口：null、倒序、
///    零长、越界、与总时长不匹配一律归一为全宽；[TrackBandGeometry.effectiveWindowOrNull]
///    只在总时长未知/非正时为 null（读取层真缺失），判据与带宽无关。
/// 3. 不可映射时全部原语与便捷答案安静返回零值/空：不发生除零、不发生对
///    无穷取整——内容区宽 ≤ 0 与「总时长未知」同级，守卫收在
///    [TrackBandGeometry.eval] 唯一求值入口。
/// 4. 时间轴构造只经 [TrackBandGeometry.axis]（本模块是全仓唯一的
///    [TimelineAxis] 构造点）；每像素微秒只有 [TrackBandGeometry.microsecondsPerPixel]
///    一个式子，[TrackBandGeometry.pixelToDuration] 是唯一取整口径。
/// 5. 纯读：求值与读取无副作用；生效窗口的写回不在本层（仍在播放位置
///    tick 的跟随路径一处显式发生）。
///
/// ## 两处收口
///
/// - **装饰层代偿**：轨道带的 `_PlayheadLayer`（播放头）与临时衔接段覆盖层
///   （住 `track_learning_row.dart` 的学习段轨域）的父级分支判
///   [TrackBandGeometry.isMappable] 自身完整，子件早退保留为防御。
/// - **无主死支**：每像素微秒只余本模块的一个式子，全仓不出现
///   `win?.microsecondsPerPixel(w) ?? 总时长 / 带宽` 这类可空回退式。
///
/// 带宽 ≤ 0 并入不可映射，安静降级为不生效（不抛错）；其余可达路径的
/// 几何取值、命中结果、吸附口径与窗口写回时机与既有像素级断言一致。
///
/// **两个谓词、两层，语义不重叠**：调用侧用可空的 `total`（与
/// [effectiveWindowOrNull] 的 null）表达读取层的「真缺失」（总时长未知 →
/// 根本没有窗口）；本层的 [isMappable] 表达几何层的「退化」（带宽非正
/// 等）。真缺失必然不可映射，反之不然。轨道带内的「没有可映射几何」只由
/// [isMappable] 一种谓词表达：几何值与时间轴恒非空。
///
/// **零框架依赖**：不引 Flutter、不引 dart:ui；只收局部像素点与带宽，不碰
/// 渲染盒与全局坐标，可在不启动 widget 环境的情况下直测。
library;

import '../annotation/learning_segments.dart';
import '../annotation/segment_hit.dart';
import '../annotation/segment_line.dart';
import 'track_row_table.dart';
import 'track_time.dart';

/// 轨道片头带宽（dp）：轨道最左、时间轴零点**之左**那一列短
/// 文字标签的定宽。让位后内容映射起于 [TrackBandGeometry.contentLeft]、
/// 宽 [TrackBandGeometry.contentWidth]；轨道带与共享同一时间轴的消费面
/// （空白区捏合、跨面双指会话）都传本值，映射口径只有一条。
const double kTrackPrefixWidth = 40;

/// 分段线触控宽度（px，全宽；视觉线居中）。
///
/// 一处声明、两个读法：渲染层按全宽铺线身抓取层；命中解析层按半宽换算时长
/// （见 [TrackBandGeometry.learningHitAt]）。
const double kSegmentLineHitWidth = 40;

/// 视频首/尾线触控宽度（px，全宽；视觉线居中）。
///
/// 一处声明、两个读法：渲染层按全宽铺端标抓取层；命中解析层按半宽判定
/// 距首/尾边界的端标命中区。
const double kVideoRangeHitWidth = 40;

/// 学习段最小命中全宽（px）：窄段对称扩展至此宽度。装配侧命中宽度只由
/// 本模块持有。
const double kTrackGeometryLearningSegmentMinHitWidth = 24;

/// 带内局部 x → 时间：拖动逐帧换算的唯一规范层入口。轴不可映射即 null
/// （逐帧据此成为空操作），否则交 [TimelineAxis.xToTime]（内容区之左钳到
/// 窗口起点，口径全在时间轴一处）。调用点各自选轴来源（带读现势窗口求值、
/// 行域用 build 期轴）——新鲜度因此显式可见，不藏在各份私有拷贝里。
Duration? dragTimeAt(TimelineAxis axis, double localX) =>
    axis.isEmpty ? null : axis.xToTime(localX);

/// 轨道带几何：生效窗口 + 总时长 + 带宽求出的横向几何。
class TrackBandGeometry {
  /// 求值：[total] 为 null 表达总时长未知（读取层真缺失）；[window] 为
  /// null = 全宽 0..total，不合法（倒序/零长/越界/与 [total] 不匹配）则
  /// 归一为全宽，合法则原样透出。[prefixWidth] 为轨道片头带宽：
  /// 时间轴零点之左让出这一段给片头列，内容映射因此起于 [contentLeft]、
  /// 宽 [contentWidth]；0 = 不让位（时间映射占满带宽）。**必填**——内容区
  /// 口径是几何的一部分，漏传即编译期报错，不静默退回占满带宽的映射。
  const TrackBandGeometry.eval({
    required this.total,
    this.window,
    required this.width,
    required this.prefixWidth,
  });

  /// 时间线总时长；null = 总时长未知。
  final Duration? total;

  /// 生效可视窗口；null = 全宽 `0..total`。
  final TimelineWindow? window;

  /// 带宽（横向局部像素宽度）。
  final double width;

  /// 轨道片头带宽（dp；0 = 本带无片头）。
  final double prefixWidth;

  /// 内容区左缘（时间轴零点在带内的落位）：= 「不让位参考尺度」
  /// 下片头右缘（[prefixRight] 同式）钳进 `[0, min(片头带宽, width)]`——片头
  /// 让出多少，内容就多吃多少；片头滑走多少就收回多少，零点完全滑出后让位
  /// 为 0、整带归内容。窗口起点为 0 时 = 片头带宽（与既有常量让位逐位一致）。
  /// 无片头恒为 0。片头列占 `[0, contentLeft)`、内容占
  /// `[contentLeft, width]`，两者不重叠（片头不侵占内容区）。
  /// 常量让位上限：片头带宽钳进 `[0, width]`。
  double get _reserve => prefixWidth >= width ? width : prefixWidth;

  /// 内容区左缘（时间轴零点在带内的落位）：= 「不让位参考尺度」
  /// 下片头右缘（[prefixRight] 同式）钳进 `[0, min(片头带宽, width)]`——片头
  /// 让出多少，内容就多吃多少；片头滑走多少就收回多少，零点完全滑出后让位
  /// 为 0、整带归内容。窗口起点为 0 时 = 片头带宽（与既有常量让位逐位一致）。
  /// 无片头恒为 0。片头列占 `[0, contentLeft)`、内容占
  /// `[contentLeft, width]`，两者不重叠（片头不侵占内容区）。
  double get contentLeft {
    if (prefixWidth <= 0) return 0;
    if (_reserve <= 0) return _reserve;
    return _referencePrefixRight.clamp(0.0, _reserve).toDouble();
  }

  /// 「不让位参考尺度」下的零点屏上 x：片头带宽按常量让位
  /// （左缘 = 片头带宽、内容区宽 = width − 片头带宽）时时间轴零点的屏上 x。
  /// 片头绘制位置与让位宽（[contentLeft]）同出这一份参考映射，不互相喂值
  /// （避免「让位宽 = 真实映射下片头可见宽」的自指退化）。不可映射时贴
  /// 内容区左缘。
  double get _referencePrefixRight {
    final reserve = _reserve;
    // 不经 [isMappable]（其判据含 contentWidth，会与本式成环）；可映射性
    // 里与内容区无关的判据只有总时长，这里只看它。
    final t = total;
    if (t == null || t <= Duration.zero) return reserve;
    final win = effectiveWindow;
    final spanUs = win.visible.inMicroseconds;
    final refContentWidth = width - reserve;
    if (spanUs <= 0 || refContentWidth <= 0) return reserve;
    return reserve - win.start.inMicroseconds / spanUs * refContentWidth;
  }

  /// 内容区宽（时间映射的像素跨度）。
  double get contentWidth => width - contentLeft;

  /// 是否有可用映射。假 = 总时长未知/非正或内容区宽非正；此态下全部原语
  /// 与便捷答案安静返回零值/空，不发生除零、不发生对无穷取整。
  bool get isMappable =>
      total != null && total! > Duration.zero && contentWidth > 0;

  /// 生效可视窗口：合法窗口原样透出；null 或不合法（倒序/零长/越界/与
  /// [total] 不匹配）归一为全宽 `0..total`。不可映射时值为全宽零时长
  /// （占位，勿用）。
  TimelineWindow get effectiveWindow {
    final w = window;
    final t = total;
    if (w != null &&
        t != null &&
        t > Duration.zero &&
        w.total == t &&
        w.start >= Duration.zero &&
        w.start < w.end &&
        w.end <= t) {
      return w;
    }
    return TimelineWindow.full(t ?? Duration.zero);
  }

  /// 读取层的可空窗口：[total] 未知/非正 → null（读取层「真缺失」，根本
  /// 没有窗口）；否则 = [effectiveWindow]（合法原样透出、不合法归一全宽）。
  /// 判据只看总时长，与带宽无关——带宽退化属几何层（[isMappable]），不吞
  /// 窗口。纯读，无副作用；写回仍只发生在播放位置 tick 的跟随路径。
  TimelineWindow? get effectiveWindowOrNull {
    final t = total;
    if (t == null || t <= Duration.zero) return null;
    return effectiveWindow;
  }

  /// 时间轴：全部时间轴构造点的唯一入口。由本值对象的生效
  /// 窗口、总时长与内容区（带宽减片头带）构造——不合法窗口在此已归一为
  /// 全宽，轴上不再出现退化窗口；不可映射时返回空轴（换算安静返回 0/零
  /// 时长）。轴恒非空：空态只由 [isMappable] 一种谓词表达。
  TimelineAxis get axis => TimelineAxis(
    total: total ?? Duration.zero,
    width: width,
    window: effectiveWindow,
    contentLeft: contentLeft,
  );

  /// 每像素微秒：可视窗口微秒数 ÷ **内容区宽**（唯一取值口径，与时间轴
  /// 换算自洽；片头不吃速度口径）。不可映射时安静返回 0。
  double get microsecondsPerPixel {
    if (!isMappable) return 0;
    return effectiveWindow.visible.inMicroseconds / contentWidth;
  }

  /// 像素 → 时长，取整口径 = `(px × 每像素微秒).round()`。不可映射时
  /// 安静返回零时长。
  Duration pixelToDuration(double px) =>
      Duration(microseconds: (px * microsecondsPerPixel).round());

  /// 时间 → 横向像素：可视窗口满宽映射到内容区 `[contentLeft, width]`，越界
  /// 钳到窗口两端。不可映射时安静返回 0。
  double timeToPixel(Duration time) {
    if (!isMappable) return 0;
    final win = effectiveWindow;
    final startUs = win.start.inMicroseconds.toDouble();
    final endUs = win.end.inMicroseconds.toDouble();
    var t = time.inMicroseconds.toDouble();
    if (t < startUs) t = startUs;
    if (t > endUs) t = endUs;
    return contentLeft + (t - startUs) / (endUs - startUs) * contentWidth;
  }

  /// 横向像素 → 时间（[timeToPixel] 的逆）：内容区之左（轨道片头）的像素
  /// 钳到窗口起点。不可映射时安静返回零时长。
  Duration pixelToTime(double x) {
    if (!isMappable) return Duration.zero;
    final win = effectiveWindow;
    final rel = (clampPixel(x) - contentLeft).clamp(0.0, contentWidth);
    return Duration(
      microseconds:
          win.start.inMicroseconds +
          (rel / contentWidth * win.visible.inMicroseconds).round(),
    );
  }

  /// 带内像素钳制：把横向局部像素钳到 `[0, width]`。
  double clampPixel(double x) => x.clamp(0.0, width).toDouble();

  /// 轨道片头带右缘屏上 x（07）：= 时间轴零点在带内的屏上 x，取
  /// 「不让位参考尺度」（[_referencePrefixRight]），**未按内容区
  /// 钳制**——窗口平移到零点之后（start > 0）时随内容一起左移、可为负
  /// （片头因此会滑出可视带）。不可映射时贴内容区左缘。
  double get prefixRight => _referencePrefixRight;

  /// 轨道片头带左缘屏上 x（[prefixRight] 之左一个片头宽）。
  double get prefixLeft => prefixRight - prefixWidth;

  /// 片头带是否与可视带相交（不相交则整列不画）。片头宽非正、内容区无宽
  /// 或整列落在带外时为假。
  bool get prefixVisible =>
      prefixWidth > 0 &&
      contentWidth > 0 &&
      prefixRight > 0 &&
      prefixLeft < width;

  /// 便捷答案：学习段轨局部点按命中。命中入参由三个命中宽度常量按
  /// [pixelToDuration] 的统一取整口径换算为时长，命中解析委派
  /// [resolveLearningTrackHit]；[narrowedLineHalfWidth] 为收窄触发窗覆盖
  /// 参数（覆盖默认线命中半宽，供「窗外回落时用点按侧的窗宽」路径）。
  /// 不可映射时安静返回空命中。
  LearningTrackHitTarget? learningHitAt({
    required double dx,
    required List<SegmentLine> segmentLines,
    required Duration rangeStart,
    required Duration rangeEnd,
    required List<LearningSegment> segments,
    Duration? narrowedLineHalfWidth,
  }) {
    if (!isMappable) return null;
    return resolveLearningTrackHit(
      segmentLines: segmentLines,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      segments: segments,
      time: pixelToTime(dx),
      lineHalfWidth:
          narrowedLineHalfWidth ?? pixelToDuration(kSegmentLineHitWidth / 2),
      edgeHalfWidth: pixelToDuration(kVideoRangeHitWidth / 2),
      minSegmentHitWidth: pixelToDuration(
        kTrackGeometryLearningSegmentMinHitWidth,
      ),
    );
  }

  /// 便捷答案：学习段轨局部点按的**段体**命中（不认分段线与首尾线的命中
  /// 窗）——长按圈选的起手与逐帧走这条，拖动逐帧跨过分段线
  /// 连续解析到相邻段。最小命中宽同由
  /// [kTrackGeometryLearningSegmentMinHitWidth] 换算。不可映射时安静返回
  /// 空命中。
  SegmentHitTarget? learningSegmentHitAt({
    required double dx,
    required List<LearningSegment> segments,
  }) {
    if (!isMappable) return null;
    return resolveLearningSegmentHit(
      segments: segments,
      time: pixelToTime(dx),
      minSegmentHitWidth: pixelToDuration(
        kTrackGeometryLearningSegmentMinHitWidth,
      ),
    );
  }

  /// 行归属：某纵向局部坐标落在哪一行，委派轨道行表 [rows]（默认具名行集
  /// `normal`）。横向不可映射时安静返回空——「整带无可用映射则整带无
  /// 命中」，纵向坐标本身与带宽/总时长无关，此门禁是有意并入同一谓词。
  TrackRowId? rowAt(double dy, {TrackRowTable rows = TrackRowTable.normal}) {
    if (!isMappable) return null;
    return rows.rowAt(dy);
  }
}
