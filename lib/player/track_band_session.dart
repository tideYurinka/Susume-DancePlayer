/// 轨道带会话域。
///
/// 收「**这一次编辑会话的窗口与手指下时间**」一件事：可视窗口跟随、预览线
/// 显示值、拖动进行中标记、编辑态微调 scrub、跨面捏合五件。控制层、设置簇
/// 与轨道带各持一个引用——「这五样要一起传」不再是一条只写在参数文档里的
/// 纪律，而是类型。
///
/// ## 依赖方向（单向）
///
/// 本域 → 播放内核接缝、seek 提交器、拖动会话、跨面捏合会话、轨道几何纯值
/// 库；**反向无**——三个消费方（control_layer / settings_cluster /
/// track_band）依赖本域，本域不 import 它们中的任何一个，也不 import 播放页。
/// 窗口存取是本域内部件：「谁是窗口的写者」因此是结构事实而不是注释。
///
/// 构造收显式依赖（引擎读取、时间线读取、清循环回调、控制层宽读取），不读
/// 构建上下文、不注容器，可在无 `ProviderScope`、无 widget pump 下直测。
///
/// ## 单一求值点
///
/// 三处各收成一处：
///
/// - **窗口跟随**：只有一个写点——[followPosition]（位置 tick 做陈旧窗口
///   归一与跟随）；seek 提交口只写预览线显示值，不各自跟随；
/// - **捏合锚点的「手指下时间」**：只有一个来源——预览线显示值
///   （[previewLine]），不再读引擎位置流；
/// - **按下中点簿记**：只有一份——[beginPinch] 收下各指针的面内局部 x，
///   本域求按下瞬间的中点（两个触发面因此不各算一份）；按下点 → 面内局部 x
///   的映射也共用一处（[localDownXs]）。
///
/// ## 两套捏合带宽口径（契约）
///
/// 面内捏合有两条几何路径，换算带宽各按自己的宽度，**这个差是固有性质、
/// 不是待修的 bug**：
///
/// - **跨面**（[CrossSurfacePinchSession]，两面原始指针聚合，含带内单独双指）
///   与**空白面**捏合：换算带宽 = **控制层宽**；
/// - **带内容**口径（[TrackPinchSurface.band]）：换算带宽 = **带内容区宽**
///   （带宽减轨道片头带，片头不吃像素↔时间换算）。
///
/// 两条口径的平移量因此相差约「片头带宽 ÷ 带宽」——片头占位的代价。
///
/// ## 内部件（原样持有）
///
/// 窗口存取件（本文件私有）、[ScrubSession]、[SeekSubmitter] 与
/// [CrossSurfacePinchSession] 由本域持有与装配、内部逻辑一字不动。面内捏合
/// （scale 识别器路径）的会计——基准窗口、锚时间、焦点基准 x、换算带宽与
/// 口径——也住在本域：空白面与带内两条 scale 路径共用这一套（同一时刻只有
/// 一条在场），跨面会话的会计在它自己内部（原始指针跨度与中点），两者互不
/// 重算。
///
/// ## 编辑态 seek 只有一条装配
///
/// 本域自持**一只** [SeekSubmitter]，供微调 scrub 与带内预览线拖动共用；
/// 拖线实时预览（预览线显示值不随动）经 [submitPicturePreview] 走
/// 同一只提交器的静默分支。微调 [ScrubSession] 的五轴取值为：无反馈浮层、
/// 无指示位、无取消区、需时长已知、恢复区间并入时间线区间判定；全屏
/// seek/scrub 域（engine_seek.dart）自持它自己的那一套，两者互不引用。
library;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../annotation/annotation_timeline.dart';
import '../core/playback/playback_engine.dart';
import 'gestures.dart' show seekDeltaFor;
import 'scrub_session.dart';
import '../core/playback/seek_submitter.dart';
import '../core/playback/serial_seek.dart' show kScrubSeekMinInterval;
import 'track_geometry.dart';
import 'track_time.dart';
import 'two_finger_session.dart';

/// 面内捏合的几何口径：跨面/空白面按控制层宽，带内按带内容区宽（见库头
/// 「两套捏合带宽口径」）。
enum TrackPinchSurface {
  /// 控制层空白面（含跨面会话）的捏合。
  blank,

  /// 轨道带内的捏合（片头不吃像素↔时间换算）。
  band,
}

/// 按下点 → 面内局部 x 列表（**两个触发面共用的一处映射**）：[downPositions]
/// 是宿主推送的按下瞬间各指针位置，[toLocal] 是宿主侧的全局 → 本面局部换算
/// （会话域不读渲染盒，故由宿主给出）。空表 = 无按下点快照。
List<double> localDownXs(
  Iterable<Offset> downPositions,
  Offset Function(Offset global) toLocal,
) => [for (final p in downPositions) toLocal(p).dx];

/// 轨道带会话域（会话域：无 widget 子树）。
class TrackBandSession implements CrossSurfacePinchForwarder {
  TrackBandSession({
    required this.engine,
    required this.timeline,
    required this.clearLoops,
    required this.layerWidth,
    this.onScrubCommitted,
  }) {
    _submitter = SeekSubmitter(
      engineSeek: engine.seek,
      minInterval: kScrubSeekMinInterval,
      total: () => engine.duration,
      timeline: timeline,
      clearLoops: clearLoops,
      displayHead: _previewLine,
    );
    // 微调 scrub：无反馈浮层、无指示位、无取消角（编辑态不显示
    // 进度浮层）；时长未知静默不起会话；恢复区间判定并入时间线区间。
    _fineScrub = ScrubSession(
      seek: _submitter,
      pause: engine.pause,
      play: engine.play,
      isPlaying: () => engine.isPlaying,
      position: () => engine.position,
      resumeRange: _resumeRange,
      onCommit: onScrubCommitted,
    );
    _crossSurface = CrossSurfacePinchSession(
      () => engine.duration,
      () => layerWidth(),
      () => _effectiveWindow(),
      updateWindow,
      () => _previewLine.value,
    );
  }

  /// 播放内核（总时长/位置/播放态与 seek 的唯一来源）。
  final PlaybackEngine engine;

  /// 生效时间线读取（清循环判定、微调恢复区间判定）。
  final AnnotationTimeline Function() timeline;

  /// 清循环激活回调（宿主绑容器的完整 helper，恒含临时衔接段）。
  final void Function(AnnotationTimeline timeline, Duration position)
  clearLoops;

  /// 控制层宽读取（跨面与空白面捏合的换算带宽；见库头两套口径）。
  final double Function() layerWidth;

  /// 会话收口落点回报（非取消收口时以最终落点回调一次）。
  final ValueChanged<Duration>? onScrubCommitted;

  late final SeekSubmitter _submitter;
  late final ScrubSession _fineScrub;
  late final CrossSurfacePinchSession _crossSurface;

  /// 可视窗口控制器（本域内部件，不出类型）。
  final _TimelineWindowController _windows = _TimelineWindowController();

  /// 面内捏合快照：基准窗口、锚时间、换算带宽与口径、焦点基准 x。
  TimelineWindow? _pinchBaseWindow;
  Duration _pinchAnchor = Duration.zero;
  double _pinchLastFocalX = 0;
  double _pinchWidth = 0;
  TrackPinchSurface _pinchSurface = TrackPinchSurface.blank;

  // ---- 窗口读写面（消费方只经这三条读写窗口） ----

  /// 当前可视窗口；null = 全宽（未缩放）。
  TimelineWindow? get window => _windows.window;

  /// 写入窗口（几何未变时 no-op，判定收在控制器内）。
  void updateWindow(TimelineWindow? value) => _windows.update(value);

  /// 收拢视野到 [anchor] 附近，可视宽 = [span]（落半拍线后播放域自己的
  /// 动作——每次落成都收，与引导是否在场、当前缩放到什么程度无关；收拢后
  /// 窗口照常可写，捏合缩放与平移不受影响）。
  /// 总时长未知时不动作（窗口无从谈起）。
  void collapseAround(Duration anchor, {required Duration span}) {
    final total = engine.duration;
    if (total == null || total <= Duration.zero) return;
    _windows.update(
      TimelineWindow.centeredOn(total: total, anchor: anchor, span: span),
    );
  }

  /// 窗口变化监听面（读法之一）：只交出 [Listenable]——窗口控制器类型因此
  /// 不外露给消费方，「谁是窗口的写者」仍由本域回答。
  Listenable get windowChanges => _windows;

  /// 位置 tick 的窗口求值（**窗口跟随的唯一一处**）：先把陈旧窗口（时长
  /// 事后刷新/换片使旧窗口不可用）归一，再让落点保持可见。消费方在位置
  /// tick 上调用——捏合与拖线实时预览自己管窗口，由消费方让位不调。
  ///
  /// 全宽（[window] 为 null）无窗口可归一与跟随，为 no-op。
  void followPosition(Duration position) {
    final win = _windows.window;
    if (win == null) return;
    final effective = _effectiveWindow();
    if (effective == null || !identical(effective, win)) {
      _windows.update(effective);
      return;
    }
    _windows.update(win.keepingVisible(position));
  }

  // ---- 预览线显示值与拖动进行中标记 ----

  final ValueNotifier<Duration> _previewLine = ValueNotifier(Duration.zero);

  /// 预览线（播放头）显示值（读面）：本域是它唯一的写者——seek 落点经
  /// [submit] 写、播放位置 tick 经 [setPreviewLine] 写；带内预览线叶子层
  /// 订阅它单独重绘（分层刷新）。它同时是捏合锚点的「手指下时间」
  /// 唯一来源（见 [beginPinch]）。
  ValueListenable<Duration> get previewLine => _previewLine;

  /// 写预览线显示值（播放位置 tick 路径；拖动目标走 [submit] 的显示位）。
  void setPreviewLine(Duration time) => _previewLine.value = time;

  final ValueNotifier<bool> _dragActive = ValueNotifier(false);

  /// 微调 scrub 会话进行中（播放 tick 据此让位于拖动目标、不自动跟随）。
  ValueListenable<bool> get dragActive => _dragActive;

  /// 生效窗口读取（总时长未知 → null）；窗口归一收在几何模块一处。
  TimelineWindow? _effectiveWindow() => TrackBandGeometry.eval(
    total: engine.duration,
    window: _windows.window,
    width: 0,
    // 只读窗口（不映射像素）。
    prefixWidth: 0,
  ).effectiveWindowOrNull;

  /// 微调恢复守卫（并入时间线的区间判定）：落点在生效区间内才续播。
  bool _resumeRange(Duration target) {
    final total = engine.duration;
    if (total == null || total <= Duration.zero) return false;
    final effective = timeline();
    return target >= effective.rangeStart && target <= effective.rangeEnd;
  }

  // ---- 编辑态 seek 装配（唯一一条） ----

  /// 编辑态拖动落点（微调 scrub 与带内预览线拖动共用 [SeekSubmitter]）：
  /// 钳制 → 清循环 → 串行入队 → 预览线显示位；**不写窗口**（跟随归位置
  /// tick 的 [followPosition] 一处）。
  Duration submit(Duration target) => _submitter.submit(target);

  /// 拖线实时预览落点：只入队——预览线显示值不随动、窗口由手势
  /// 自管，故走同一只提交器的静默分支。
  Duration submitPicturePreview(Duration target) =>
      _submitter.submit(target, writeDisplay: false);

  /// 拖线实时预览收尾：seek 回起手定格点后等队列排空（「落定后续播」类
  /// 顺序语义）。
  Future<void> settlePicturePreview(Duration target) =>
      _submitter.submitAndSettle(target, writeDisplay: false);

  // ---- 编辑态微调 scrub ----

  /// 微调单帧：先确保会话已起始（时长未知则静默丢弃本帧），再按累计位移
  /// 推进落点并点亮拖动标记。
  Future<void> fineScrubFrame(double dxPixels) async {
    await _fineScrub.begin();
    if (!_fineScrub.isActive) return;
    _dragActive.value = true;
    _fineScrub.moveBy(seekDeltaFor(dxPixels, 1));
  }

  /// 微调收尾（松手 / 指针取消 / 加指冻结转捏合）：恢复手势前播放态、恢复
  /// 守卫与落点回报由本域持有的拖动会话收口；未激活时 no-op。
  Future<void> endFineScrub() async {
    if (!_fineScrub.isActive) return;
    _dragActive.value = false;
    await _fineScrub.end();
  }

  /// 微调会话是否激活。
  bool get fineScrubbing => _fineScrub.isActive;

  // ---- 跨面双指会话（两面原始指针转发 + 两个读法） ----

  @override
  void trackBandPointerDown(int pointer, Offset global) =>
      _crossSurface.trackBandPointerDown(pointer, global);

  @override
  void trackBandPointerMove(int pointer, Offset global) =>
      _crossSurface.trackBandPointerMove(pointer, global);

  @override
  void trackBandPointerUp(int pointer) =>
      _crossSurface.trackBandPointerUp(pointer);

  @override
  void trackBandPointerCancel(int pointer) =>
      _crossSurface.trackBandPointerCancel(pointer);

  @override
  void blankPointerDown(int pointer, Offset global) =>
      _crossSurface.blankPointerDown(pointer, global);

  @override
  void blankPointerMove(int pointer, Offset global) =>
      _crossSurface.blankPointerMove(pointer, global);

  @override
  void blankPointerUp(int pointer) => _crossSurface.blankPointerUp(pointer);

  @override
  void blankPointerCancel(int pointer) =>
      _crossSurface.blankPointerCancel(pointer);

  /// 双指会话当前在场（活跃 ≥2 指且至少一指在轨道带面）：子级拖拽让位。
  @override
  bool get mixedActive => _crossSurface.mixedActive;

  @override
  bool get burstEverMixed => _crossSurface.burstEverMixed;

  // ---- 面内捏合（band/blank 两条 scale 识别器路径） ----

  /// 面内捏合起手：快照起始窗口、锚时间与焦点基准 x。[width] = 本面换算
  /// 带宽（空白面/跨面 = 控制层宽，带内 = 带宽）；[downXs] = 按下瞬间各指针
  /// 的面内局部 x（由宿主推送，见 [localDownXs]）；不足两个时退回
  /// [fallbackFocalX]（scale 会话起手焦点 x——识别器位移过阈才回调，其焦点
  /// 已偏出真实按下中点）。
  ///
  /// 按下中点的求值只有这一处（两个触发面不各算一份）；锚点取预览线**显示
  /// 值**（[previewLine]，用户此刻看到的那条线），判定规则见 [pinchAnchorTime]；
  /// 仅激活帧判定一次，整场不重算。
  void beginPinch({
    required TrackPinchSurface surface,
    required double width,
    required List<double> downXs,
    required double fallbackFocalX,
  }) {
    _pinchBaseWindow = null;
    if (width <= 0) return;
    final geometry = _geometry(width: width, surface: surface, window: window);
    final win = geometry.effectiveWindowOrNull;
    if (win == null) return;
    _pinchSurface = surface;
    _pinchWidth = width;
    _pinchBaseWindow = win;
    final x = _downMidpointX(downXs, fallbackFocalX).clamp(0.0, width);
    _pinchAnchor = pinchAnchorTime(
      window: win,
      previewLineTime: _previewLine.value,
      fingerFocalTime: geometry.axis.xToTime(x),
    );
    _pinchLastFocalX = x;
  }

  /// 按下瞬间双指中点的面内局部 x（**唯一一份中点簿记**）：≥2 个按下点取
  /// 均值；否则退回 [fallbackFocalX]。
  double _downMidpointX(List<double> downXs, double fallbackFocalX) {
    if (downXs.length < 2) return fallbackFocalX;
    var sum = 0.0;
    for (final dx in downXs) {
      sum += dx;
    }
    return sum / downXs.length;
  }

  /// 面内捏合单帧：张合（[factor] = 自起手的累计倍率）以锚缩放，焦点水平
  /// 位移（[focalX] 与起手基点的差）平移窗口——换算带宽按起手时记录的口径。
  void pinchFrame({required double factor, required double focalX}) {
    final base = _pinchBaseWindow;
    if (base == null) return;
    final win = pinchPanZoomed(
      base: base,
      anchor: _pinchAnchor,
      factor: factor,
      focalDeltaDx: focalX - _pinchLastFocalX,
      width: _geometry(
        width: _pinchWidth,
        surface: _pinchSurface,
        window: base,
      ).contentWidth,
    );
    if (!identical(win, base)) updateWindow(win);
  }

  /// 面内捏合收尾：清基准窗口（帧在收尾后到达即 no-op）。
  void endPinch() {
    _pinchBaseWindow = null;
  }

  /// 按口径求值几何：空白面/跨面不让位片头，带内让出 [kTrackPrefixWidth]。
  TrackBandGeometry _geometry({
    required double width,
    required TrackPinchSurface surface,
    required TimelineWindow? window,
  }) => TrackBandGeometry.eval(
    total: engine.duration,
    window: window,
    width: width,
    prefixWidth: surface == TrackPinchSurface.band ? kTrackPrefixWidth : 0,
  );

  /// 收尾本域自建的那些（窗口控制器与两个显示值）。
  void dispose() {
    _windows.dispose();
    _previewLine.dispose();
    _dragActive.dispose();
  }
}

/// 轨道可视窗口（null = 全宽 0..total）的存取 + 变更通知：本域私有件。
class _TimelineWindowController extends ChangeNotifier {
  TimelineWindow? _window;

  /// 当前可视窗口；null = 全宽（未缩放）。
  TimelineWindow? get window => _window;

  /// 写入窗口（几何未变 no-op：相同实例或 total/start/end 等值的窗口不触发
  /// 多余重建——拖动/播放 tick 高频路径每次都会派生等值的新窗口实例，几何
  /// 没变就不该让整带重建；等值比较收在本件内，不改变 [TimelineWindow] 的
  /// 公开相等语义）。
  void update(TimelineWindow? value) {
    if (identical(value, _window)) return;
    final cur = _window;
    if (value != null &&
        cur != null &&
        value.total == cur.total &&
        value.start == cur.start &&
        value.end == cur.end) {
      return;
    }
    _window = value;
    notifyListeners();
  }
}
