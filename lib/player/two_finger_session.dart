/// 跨手势面的双指缩放+平移会话（「双指=缩放+平移」）。
///
/// 控制层的两块手势面——中部非交互空白区与轨道带——各挂一个 scale 识别器，
/// 各自只统计**落在本面**的指针：混区起手（一指压轨道内容/带内空白、另一指
/// 压空白区）时两个识别器都只见一指，会各自误入单指语义（带内 seek、空白
/// 微调 seek）。本类聚合两面的**原始指针**（[PointerDownEvent] 级，不经
/// 识别器），当活跃指针 ≥2 且至少一指在轨道带面时接管为一次双指会话：
/// 双指中点（焦点）位移 → `pannedBy` 平移、张合（跨度比）→ 以起始中点
/// 对应时间为锚缩放（换算复用 [pinchPanZoomed] 纯函数，钳制规则一致）。
///  起推广到整条轨道带内：手柄带控制柄、学习段体等子级横向拖区上
/// 双指起手同样激活（不依赖子树单祖先 Scale 识别器赢竞技场——子级拖拽
/// 识别器先过 slop 赢 arena 时父 Scale 被拒收，原始指针会话不受影响；
/// 子级拖拽由宿主按 [mixedActive] 让位）；两指同落空白面不激活（该面捏合
/// 归既有 scale 路径）。
///
/// 落在交互控件（按钮/面板/dock/轨道设置条）上的指针不经过两面 Listener、
/// 天然不参与本会话；会话期间两面各自的识别器经 [burstEverMixed] 抑制单指
/// 语义（不 seek、不选中、不收起）。换算只用横向分量（轨道窗口是一维的）。
library;

import 'package:flutter/widgets.dart';

import 'track_geometry.dart';
import 'track_time.dart';

/// 指针来源面（轨道带 / 非交互空白区）。
enum _Surface { band, blank }

/// 跨面双指会话的**转发面**（接缝，不是域身份）：两面 Listener 经输入会话
/// 簿记壳把原始指针交给持有者。[CrossSurfacePinchSession] 自身实现它；吸收
/// 该会话的轨道带会话域（track_band_session.dart）同样实现它——簿记壳因此
/// 只认这个面，不认持有者是谁（簿记壳不依赖会话域，会话域也不依赖簿记壳）。
abstract interface class CrossSurfacePinchForwarder {
  void trackBandPointerDown(int pointer, Offset global);

  void trackBandPointerMove(int pointer, Offset global);

  void trackBandPointerUp(int pointer);

  void trackBandPointerCancel(int pointer);

  void blankPointerDown(int pointer, Offset global);

  void blankPointerMove(int pointer, Offset global);

  void blankPointerUp(int pointer);

  void blankPointerCancel(int pointer);

  /// 双指会话当前在场（活跃 ≥2 指且至少一指在轨道带面）：子级拖拽让位依据。
  bool get mixedActive;

  /// 本 burst 曾进入 mixed 会话（识别器侧单指语义抑制依据）。
  bool get burstEverMixed;
}

/// 跨面双指会话：轨道带与空白区 Listener 各自转发原始指针事件
/// （[trackBandPointerDown] 系标注来源面，[blankPointerDown] 系空白面）。
class CrossSurfacePinchSession implements CrossSurfacePinchForwarder {
  /// 创建会话；参数依次为时间线总时长读取（null = 无映射，会话不动窗口）、
  /// 换算带宽（空白区与轨道带同宽）、当前窗口读取、窗口写入（同一窗口写
  /// 入口）、预览线时间读取（null = 未知，锚点退回
  /// 手指焦点）。
  ///
  /// **换算带宽 = 控制层宽**（本会话的单一换算口径）：本会话只管两面的原始
  /// 指针聚合，混区 burst 内轨道带自己的识别器让位（[burstEverMixed] 抑制），
  /// 因此混区手势的窗口换算全部由本会话按控制层宽给出。轨道带单独双指
  /// （无混区）走带内内容区口径（轨道片头让位）——两种起手方式的
  /// 平移量相差约片头带宽/带宽，是片头占位的代价。
  CrossSurfacePinchSession(
    this._total,
    this._width,
    this._window,
    this._update,
    this._previewTime,
  );

  final Duration? Function() _total;
  final double Function() _width;
  final TimelineWindow? Function() _window;
  final void Function(TimelineWindow) _update;
  final Duration? Function() _previewTime;

  /// 活跃指针：id → (全局位置, 来源面)。
  final Map<int, (Offset, _Surface)> _points = {};

  /// 会话基准（mixed 激活瞬间快照）：起始窗口、锚时间（按下瞬间双指中点
  /// 对应时间）、起始跨度、按下瞬间焦点 x（平移累计基准，不再逐帧更新
  /// ——平移每帧按「当前焦点 − 基准」累计重算，见 [_move]）。
  TimelineWindow? _baseWindow;
  Duration _anchor = Duration.zero;
  double _startSpan = 0;
  Offset? _lastFocal;

  /// 本 burst（自上一轮全部抬起起）曾进入 mixed 会话：latch 到下一次
  /// [指针落下且当前无活跃指针] 才复位——与 [PointerBurstTracker] 的证据
  /// 存档同语义，保护 scale 识别器在双指抬起后重启的少指会话不误判单指
  /// 语义/空闲单击（同源场景）。
  bool _burstEverMixed = false;

  /// 当前是否处于双指会话（推广：活跃 ≥2 指且至少一指在轨道带面
  /// ——手柄带控制柄、学习段体等子级横向拖区起手同样激活；两指同落空白
  /// 面不激活，空白面捏合仍归该面既有 scale 识别器路径）。
  @override
  bool get mixedActive {
    if (_points.length < 2) return false;
    for (final (_, s) in _points.values) {
      if (s == _Surface.band) return true;
    }
    return false;
  }

  /// 本 burst 曾进入 mixed 会话（识别器侧单指语义抑制依据）。
  @override
  bool get burstEverMixed => _burstEverMixed;

  // ---- 指针转发入口（两面 Listener 各自调用） ----

  @override
  void trackBandPointerDown(int pointer, Offset global) =>
      _down(pointer, global, _Surface.band);

  @override
  void trackBandPointerMove(int pointer, Offset global) =>
      _move(pointer, global);

  @override
  void trackBandPointerUp(int pointer) => _up(pointer);

  @override
  void trackBandPointerCancel(int pointer) => _up(pointer);

  @override
  void blankPointerDown(int pointer, Offset global) =>
      _down(pointer, global, _Surface.blank);

  @override
  void blankPointerMove(int pointer, Offset global) => _move(pointer, global);

  @override
  void blankPointerUp(int pointer) => _up(pointer);

  @override
  void blankPointerCancel(int pointer) => _up(pointer);

  void _down(int pointer, Offset global, _Surface surface) {
    if (_points.isEmpty) _burstEverMixed = false; // 新 burst 起复位证据。
    _points[pointer] = (global, surface);
    if (!mixedActive) return;
    // mixed 激活瞬间：快照起始窗口 + 按下瞬间双指中点对应时间为锚。
    _burstEverMixed = true;
    final base = _window();
    final w = _width();
    if (base == null || w <= 0) return;
    final total = _total();
    if (total == null || total <= Duration.zero) return;
    final focal = _focal();
    _baseWindow = base;
    _lastFocal = focal;
    _startSpan = _span();
    final focalTime = TrackBandGeometry.eval(
      total: total,
      window: base,
      width: w,
      prefixWidth: 0,
    ).axis.xToTime(focal.dx.clamp(0.0, w));
    // 锚点判定规则见 [pinchAnchorTime]；预览线未知（null）退回手指焦点。
    // 仅此一帧判定，整场不重算。
    _anchor = pinchAnchorTime(
      window: base,
      previewLineTime: _previewTime() ?? focalTime,
      fingerFocalTime: focalTime,
    );
  }

  void _move(int pointer, Offset global) {
    final existing = _points[pointer];
    if (existing == null) return;
    _points[pointer] = (global, existing.$2);
    if (!mixedActive) return;
    final base = _baseWindow;
    if (base == null) return;
    final w = _width();
    if (w <= 0) return;
    final focal = _focal();
    final span = _span();
    final factor = _startSpan > 0 ? span / _startSpan : 1.0;
    // 累计焦点位移（自按下瞬间中点起算）：窗口每帧都从起始快照重算
    // （缩放是累计倍率），平移必须同为累计量才不被覆盖；逐帧增量会被
    // 每帧的快照重算丢弃。
    final focalDeltaDx = _lastFocal == null ? 0.0 : focal.dx - _lastFocal!.dx;
    final win = pinchPanZoomed(
      base: base,
      anchor: _anchor,
      factor: factor,
      focalDeltaDx: focalDeltaDx,
      width: w,
    );
    if (!identical(win, base)) _update(win);
  }

  void _up(int pointer) {
    _points.remove(pointer);
    if (_points.isEmpty) {
      // 会话基准清空；[burstEverMixed] 保留至下一次 burst（识别器重启的
      // 少指会话仍可读，同源保护）。
      _baseWindow = null;
      _lastFocal = null;
      _startSpan = 0;
    }
  }

  /// 双指中点（焦点）＝全部活跃指针的全局位置均值。
  Offset _focal() {
    var x = 0.0;
    var y = 0.0;
    for (final (p, _) in _points.values) {
      x += p.dx;
      y += p.dy;
    }
    final n = _points.length;
    return Offset(x / n, y / n);
  }

  /// 双指跨度（活跃指针间最大两两距离；两指时即指间距离）。
  double _span() {
    var max = 0.0;
    final values = _points.values.toList();
    for (var i = 0; i < values.length; i++) {
      for (var j = i + 1; j < values.length; j++) {
        final d = (values[i].$1 - values[j].$1).distance;
        if (d > max) max = d;
      }
    }
    return max;
  }
}
