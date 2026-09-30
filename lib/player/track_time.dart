/// 轨道时间几何纯函数与值类型（基础映射 + 时间缩放）。
///
/// 展开态轨道带内各元素（预览条 / 分段线 / 视频首/尾线 / 缩放）共用同一
/// 时间→x 换算，故把「时间轴」抽成值类型
/// [TimelineAxis]（总时长 × 像素宽 × 可视窗口），换算逻辑集中一处、调用侧
/// 只传时间点。
///
/// 「双指捏合 + 滑条调节时间密度」= 把映射窗口从整片 0..duration 缩到
/// 一段子区间再满宽显示：窗口几何（纯时间域）独立成 [TimelineWindow]（缩放
/// 锚点保持/平移钳制/播放头跟随/最细可视下限），像素换算仍由 [TimelineAxis]
/// 承担——窗口只在状态层随手势更新，渲染层仍只经 timeToX/xToTime 换算。
/// 全文件无 UI、无引擎依赖，仅做 [Duration] ↔ 像素换算。
library;

import 'dart:math' as math;

/// 缩放下限：可视窗口最短时长（再放大节拍刻度过稀、逐帧编辑失去参照意义）。
const Duration kMinZoomVisibleDuration = Duration(seconds: 2);

/// 播放中播放头越出可视窗口时的跟随落点：把窗口平移使播放头位于窗口
/// [kPlayheadFollowFraction] 处（自窗口左端起；0.25 = 左 1/4），避免播放头
/// 刚越出右缘就整窗跳、内容追不上的观感。
const double kPlayheadFollowFraction = 0.25;

/// 时间轴：把可视窗口 [start, end]（默认全宽 0..total）映射到横向像素
/// `[contentLeft, width]`。
///
/// 供预览条/分段线/首/尾线/缩放共用（基础时间映射）；换算以微秒为
/// 分母（避免毫秒取整损失）。[window] 为 null 时 = 整片 `0..total` 满宽
/// （骨架行为），后续缩放只换窗口不改总时长语义。
///
/// [contentLeft] 是**内容区左缘**：轨道带把时间轴零点之左那
/// 一段让给轨道片头，时间映射因此落在 `[contentLeft, width]`（0 = 不让位，
/// 时间映射占满带宽）。构造点（[TrackBandGeometry.axis]）已把它钳在
/// `[0, width]`；窗口平移/缩放只改窗口，内容区位置不变。
class TimelineAxis {
  const TimelineAxis({
    required this.total,
    required this.width,
    required this.contentLeft,
    this.window,
  });

  /// 时间线总时长（整片或有效区间，由调用侧决定）。
  final Duration total;

  /// 映射到的横向像素宽度（映射区间右缘）。
  final double width;

  /// 可视窗口（[TimelineWindow]，缩放后 = 只显示片段的子区间）；null = 全宽
  /// `0..total`。
  final TimelineWindow? window;

  /// 内容区左缘（时间轴零点在带内的落位；0 = 内容区占满带宽）。
  final double contentLeft;

  /// 可视窗口左端（null 窗口 = 0）。
  Duration get _start => window?.start ?? Duration.zero;

  /// 可视窗口右端（null 窗口 = [total]）。
  Duration get _end => window?.end ?? total;

  /// 内容区宽（映射区间跨度）。
  double get _span => width - contentLeft;

  /// 内容区宽（时间映射的像素跨度）。
  double get contentWidth => _span;

  /// 是否无可用映射（[total] ≤ 0、内容区宽 ≤ 0 或可视窗口退化）→ 换算
  /// 短路返回 0/zero。
  bool get isEmpty =>
      total <= Duration.zero ||
      _span <= 0 ||
      _end <= _start;

  /// 时间 → 横向像素：可视窗口 [start,end] 满宽映射到 `[contentLeft, width]`，越界
  /// 钳制（窗口内元素映射到窗口两端）。
  double timeToX(Duration time) {
    if (isEmpty) return 0;
    final startUs = _start.inMicroseconds.toDouble();
    final endUs = _end.inMicroseconds.toDouble();
    var t = time.inMicroseconds.toDouble();
    if (t < startUs) t = startUs;
    if (t > endUs) t = endUs;
    return contentLeft + (t - startUs) / (endUs - startUs) * _span;
  }

  /// 横向像素 → 时间（[timeToX] 的逆；内容区右缘 [width] 对应可视窗口
  /// 右端）。
  ///
  /// [x] 钳制到内容区 `[contentLeft, width]`——落在内容区之左（轨道片头）的像素
  /// 归窗口左端。供手势把拖到位移换算回时间点（帧级 seek / 缩放锚点取
  /// 焦点时间）。
  Duration xToTime(double x) {
    if (isEmpty) return Duration.zero;
    final startUs = _start.inMicroseconds;
    final spanUs = (_end - _start).inMicroseconds;
    var xc = x - contentLeft;
    if (xc < 0) xc = 0;
    if (xc > _span) xc = _span;
    return Duration(
      microseconds: startUs + (xc / _span * spanUs).round(),
    );
  }
}

/// 时间线可视窗口（纯时间域；像素映射由 [TimelineAxis] 承担）：把
/// [total] 上的一段可视区间 `[start, end]`（⊆ [0, total]）映射到轨道满宽。
///
/// 「时间密度缩放」的状态载体：捏合/滑条只改窗口（start/end），
/// 映射正确性由窗口 + [TimelineAxis] 共同保证——缩放后预览条所在时间不变
/// （锚点 [zoomed] 保持锚时间在窗口内的相对位置 → 屏上 x 不变）。
class TimelineWindow {
  const TimelineWindow({
    required this.total,
    required this.start,
    required this.end,
  });

  /// 全宽窗口（0..total；缩放的初始态）。
  factory TimelineWindow.full(Duration total) =>
      TimelineWindow(total: total, start: Duration.zero, end: total);

  /// 时间线总时长。
  final Duration total;

  /// 可视窗口左端（含）。
  final Duration start;

  /// 可视窗口右端（含）。
  final Duration end;

  /// 窗口是否可用：total > 0 且 0 ≤ start < end ≤ total。
  bool get isValid =>
      total > Duration.zero &&
      start >= Duration.zero &&
      start < end &&
      end <= total;

  /// 可视时长（end - start）。
  Duration get visible => end - start;

  /// 缩放倍率 = total / visible（全宽 = 1，放大 > 1；滑条值映射基准）。
  double get zoomFactor {
    final visibleUs = visible.inMicroseconds;
    if (visibleUs <= 0) return 1;
    return total.inMicroseconds / visibleUs.toDouble();
  }

  /// [t] 是否落在可视窗口内（含两端）。
  bool contains(Duration t) => t >= start && t <= end;

  /// 每像素微秒数（边缘平移换算用）。
  double microsecondsPerPixel(double width) =>
      visible.inMicroseconds / width;

  /// 平移可视窗口 [delta]（正 = 窗口右移、看更晚的内容），窗口时长不变、
  /// 结果钳制在 `[0, total]` 内。
  TimelineWindow pannedBy(Duration delta) {
    if (!isValid) return this;
    final totalUs = total.inMicroseconds;
    final visibleUs = visible.inMicroseconds;
    final rawStart = start.inMicroseconds + delta.inMicroseconds;
    final s = rawStart.clamp(0, totalUs - visibleUs);
    return TimelineWindow(
      total: total,
      start: Duration(microseconds: s),
      end: Duration(microseconds: s + visibleUs),
    );
  }

  /// 缩放钳制到全宽时的微尘容差（微秒）：链式缩放（放大→再缩回）中每步的
  /// µs 取整会累积亚微秒误差，离全宽 <1ms 时应视作全宽（否则窗口右缘/左缘
  /// 差几 µs，边缘刻度/预览条丢失）。
  static const int kFullViewSnapUs = 1000;

  /// 以 [anchor] 为锚缩放 [factor] 倍（>1 = 放大、可视窗口变短；<1 = 缩小、
  /// 可视变长至多到全宽）：锚点在窗口内的相对位置不变 → 锚时间在屏上 x
  /// 不动（捏合焦点下方内容不漂、滑条缩放以播放头为锚时预览条 x 不变）。
  ///
  /// 结果钳制：可视时长 ∈ `[min(total, kMinZoomVisibleDuration), total]`、
  /// 窗口 ∈ `[0, total]`（接近全宽的微尘误差吸附为全宽）。
  TimelineWindow zoomed({
    required Duration anchor,
    required double factor,
  }) {
    if (!isValid || factor <= 0) return this;
    final totalUs = total.inMicroseconds;
    final visibleUs = visible.inMicroseconds;
    final minUs = math.min(
      kMinZoomVisibleDuration.inMicroseconds,
      totalUs,
    );
    var targetUs =
        (visibleUs / factor).round().clamp(minUs, totalUs);
    if (totalUs - targetUs <= kFullViewSnapUs) targetUs = totalUs;
    // 锚在窗口内的相对位置（钳到 [0,1]；锚在窗外时贴边）。
    final anchorUs = anchor.inMicroseconds.toDouble();
    final startUs = start.inMicroseconds.toDouble();
    final p = ((anchorUs - startUs) / visibleUs).clamp(0.0, 1.0);
    // targetUs == totalUs 时上界为 0 → s 钳到 0 = 全宽（p/锚点不再有意义）。
    final s = (anchorUs - p * targetUs).round().clamp(0, totalUs - targetUs);
    return TimelineWindow(
      total: total,
      start: Duration(microseconds: s),
      end: Duration(microseconds: s + targetUs),
    );
  }

  /// 平移窗口使 [time] 位于窗口 [fraction]（0..1，自窗口左端起）处；
  /// [time] 已在窗口内则不动（返回自身）。播放头越出可视窗口时的跟随落点。
  TimelineWindow keepingVisible(
    Duration time, {
    double fraction = kPlayheadFollowFraction,
  }) {
    if (!isValid || contains(time)) return this;
    final totalUs = total.inMicroseconds;
    final visibleUs = visible.inMicroseconds;
    final s = (time.inMicroseconds -
            visibleUs * fraction.clamp(0.0, 1.0))
        .round()
        .clamp(0, totalUs - visibleUs);
    return TimelineWindow(
      total: total,
      start: Duration(microseconds: s),
      end: Duration(microseconds: s + visibleUs),
    );
  }

  /// 以 [anchor] 为中心、可视时长 [span] 的新窗口（落半拍线后收拢视野到
  /// 该线附近）。窗口整体钳制在 `[0, total]`；
  /// [span] ≥ total（或非正）回全宽窗口。
  factory TimelineWindow.centeredOn({
    required Duration total,
    required Duration anchor,
    required Duration span,
  }) {
    final totalUs = total.inMicroseconds;
    final spanUs = span.inMicroseconds;
    if (totalUs <= 0 || spanUs <= 0 || spanUs >= totalUs) {
      return TimelineWindow.full(total);
    }
    final anchorUs = anchor.inMicroseconds.clamp(0, totalUs);
    final s = (anchorUs - spanUs ~/ 2).clamp(0, totalUs - spanUs);
    return TimelineWindow(
      total: total,
      start: Duration(microseconds: s),
      end: Duration(microseconds: s + spanUs),
    );
  }
}

/// 双指缩放+平移联动换算（「双指=缩放+平移」）：在 [base]
/// 窗口上先以 [anchor] 为锚按累计倍率 [factor] 缩放（[TimelineWindow.zoomed]，
/// 沿用既有缩放上下限与整片钳制），再按双指焦点水平位移 [focalDeltaDx]
/// 平移——手指右移（>0）= 内容跟手右移 = 看更早内容 → 窗口左移；位移按
/// **缩放后**窗口的每像素微秒数换算（当前屏上比例），平移钳制在
/// `[0, total]`。[width] ≤ 0 或窗口无效 → 原样返回；[factor] ≈1 且无焦点
/// 位移时窗口不变。
TimelineWindow pinchPanZoomed({
  required TimelineWindow base,
  required Duration anchor,
  required double factor,
  required double focalDeltaDx,
  required double width,
}) {
  if (!base.isValid || width <= 0) return base;
  var win = base;
  if ((factor - 1).abs() >= 1e-4) {
    win = win.zoomed(anchor: anchor, factor: factor);
  }
  if (focalDeltaDx != 0) {
    final usPerPx = win.microsecondsPerPixel(width);
    if (usPerPx > 0) {
      win = win.pannedBy(
        Duration(microseconds: (-focalDeltaDx * usPerPx).round()),
      );
    }
  }
  return win;
}

/// 捏合锚点取预览线：预览线时间
/// [previewLineTime] 落在起手窗口 [window] 内（**含左右端点**）→ 锚点 =
/// 预览线时间（原地放大时线在屏上的位置不动、线附近被铺开）；不在窗口内
/// → 锚点 = 手指焦点时间 [fingerFocalTime]（「想看哪儿就放大哪儿」照旧）。
///
/// 纯规则、不含手势状态——「哪一帧判」由调用方决定（三条捏合路径都在会话
/// 激活帧调用一次）。窗口退化（零宽 / 零时长 / 无效）不含端点语义，按
/// 「不在窗口内」取手指焦点时间，恒有确定取值、不抛错。
Duration pinchAnchorTime({
  required TimelineWindow window,
  required Duration previewLineTime,
  required Duration fingerFocalTime,
}) {
  if (window.isValid && window.contains(previewLineTime)) {
    return previewLineTime;
  }
  return fingerFocalTime;
}

/// 滑条缩放的倍率上限（滑条值 1 对应把可视窗口缩到 [kMinZoomVisibleDuration]）：
/// total / min(total, kMinZoomVisibleDuration)；[total] ≤ 缩放下限时 = 1
/// （无可缩放空间，滑条应禁用）。
double maxZoomFactorFor(Duration total) {
  if (total <= Duration.zero) return 1;
  final totalUs = total.inMicroseconds.toDouble();
  final minUs = math.min(
    kMinZoomVisibleDuration.inMicroseconds.toDouble(),
    totalUs,
  );
  return totalUs / minUs;
}

/// 滑条取值 NaN 过滤（「缩放链路防御性 clamp」）：
/// 异常取值（NaN）归 0 再进 Slider/倍率换算，静默钳制、不抛错。
double sanitizeZoomSliderValue(double value) => value.isNaN ? 0.0 : value;

/// 滑条值（0..1）→ 缩放倍率：指数插值 1..[maxZoomFactorFor]，让滑条中点
/// 落在几何中位（线性倍率会让大部分滑条行程集中在全宽附近）。
/// 取值先经 [sanitizeZoomSliderValue] 过滤 NaN。
double zoomFactorForSliderValue(Duration total, double value) {
  final maxFactor = maxZoomFactorFor(total);
  if (maxFactor <= 1) return 1;
  final v = sanitizeZoomSliderValue(value).clamp(0.0, 1.0);
  return math.pow(maxFactor, v).toDouble();
}

/// 当前窗口缩放倍率 → 滑条值（[zoomFactorForSliderValue] 的逆）；全宽 = 0。
double zoomSliderValueFor(TimelineWindow window) {
  final maxFactor = maxZoomFactorFor(window.total);
  if (!window.isValid || maxFactor <= 1) return 0;
  final factor = window.zoomFactor.clamp(1.0, maxFactor);
  return (math.log(factor) / math.log(maxFactor)).clamp(0.0, 1.0);
}
