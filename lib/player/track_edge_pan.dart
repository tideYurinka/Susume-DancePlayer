/// 贴边平移会话：预览条拖动贴近屏幕边缘时自动平移可视窗口的整件——侵入
/// 深度→速度曲线（纯函数群）与逐帧会话（ticker 生命周期、帧间 dt 累积、
/// 平移后按同一手指位重算的驱动者）。
///
/// **接口只有四个成员**：[EdgePanSession.hold] 逐帧登记手指位与「平移后重算」
/// 的驱动者、[EdgePanSession.stop] 收口、[EdgePanSession.pointerCount] 交下
/// 冻结判据（第二指落下）、[EdgePanSession.dispose] 释放 ticker。tick 循环、
/// 幂等复用与「滚到头/圈到头停 ticker」的约定都藏在实现里。
///
/// **冻结判据不复制事实源**：双指在场由注入谓词读取（缩放/预览线拖动/学习段
/// 圈选三族共用同一份事实），会话只按谓词答案停 ticker。
///
/// **驱动者返回值约定**：`drive(windowMoved)` 返回 false = 滚到头/圈到头，
/// 停 ticker（逐族语义由各自闭包回答）。
///
/// **依赖方向（单向）**：本件 → 时间轴与窗口值对象（`track_time.dart`）、
/// 横向几何纯件（`track_geometry.dart`：每像素微秒与轨道片头带宽）、Flutter
/// 调度器与渲染盒类型。不读 provider、不碰容器句柄、不 import 带级库。
library;

import 'dart:ui' show Offset;

import 'package:flutter/rendering.dart' show RenderBox;
import 'package:flutter/scheduler.dart' show Ticker;

import 'track_geometry.dart' show TrackBandGeometry, kTrackPrefixWidth;
import 'track_time.dart' show TimelineWindow;

/// 拖动几何快照：总时长、生效窗口与轨道带渲染盒齐备时才有拖动换算语义
/// （预览线拖动与命中列判定共用；由带级现势求值，逐个消费点一次性受益）。
typedef DragContext = ({Duration total, TimelineWindow window, RenderBox box});

/// 预览条拖动时贴近屏幕边缘触发可视窗口自动平移的**判定带宽**（左右各）：
/// 轨道带宽 ÷ 4 —— 该次量测所用视口下：竖屏 361.1 → 90.3、横屏 781.7 → 195.4。判定带宽随
/// 带宽成比例，小屏带中部因此仍留出可微调的安全区；带宽口径 = 调用点的
/// 渲染盒全宽（沿用既有调用点，不换内容区宽口径）。
double edgePanZonePx(double width) => width / 4;

/// 贴边平移的**出缘最快速度**（像素/秒）：侵入深度达判定带宽（手指贴到
/// 屏幕边缘）时即本值，任何屏宽下恒等。
const double kPlayheadEdgePanMaxVelocityPxPerSec = 700;

/// 手指 [x]（带内局部坐标）在左右边沿区内的**侵入深度**（像素）：0 =
/// 不在边沿区（不平移）；越贴近屏幕边缘深度越大，钳在 `[0, 判定带宽]`
/// （贴屏缘 = 满深度）。
double edgePanDepthPx({required double x, required double width}) {
  final zone = edgePanZonePx(width);
  if (x < zone) return (zone - x).clamp(0.0, zone);
  if (x > width - zone) return (x - (width - zone)).clamp(0.0, zone);
  return 0;
}

/// 贴边平移速度曲线（像素/秒）：归一化线性
/// `v = 700 × (深度 ÷ 判定带宽)` —— 零深度零速；随侵入深度线性递增；
/// 出缘（深度 = 判定带宽）恒 [kPlayheadEdgePanMaxVelocityPxPerSec]，
/// 与带宽无关（竖屏与横屏同值）。
double edgePanVelocityPxPerSec(double depthPx, {required double width}) {
  final zone = edgePanZonePx(width);
  return kPlayheadEdgePanMaxVelocityPxPerSec * depthPx / zone;
}

/// 时间平滑累积一步：侵入 [depthPx] 持续 [elapsed] 的窗口平移量（线性速度
/// 与时长成正比；零时长为零）；[microsecondsPerPixel] 把像素速度换算为
/// 时间速度（随当前可视窗口密度）。方向（左/右缘）由调用方按手指所在侧
/// 确定。
Duration edgePanShiftFor({
  required double depthPx,
  required double width,
  required Duration elapsed,
  required double microsecondsPerPixel,
}) {
  if (elapsed <= Duration.zero) return Duration.zero;
  final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  final shiftPx = edgePanVelocityPxPerSec(depthPx, width: width) * seconds;
  return Duration(microseconds: (shiftPx * microsecondsPerPixel).round());
}

/// 拖动 seek 的公共换算（提取自轨道带预览条拖动，控制层空白横滑
/// 共用——同一跟手链路不重造）：以当前可视窗口把手指 [x] 换算为目标时间。
///  起**贴边平移不再在本换算内做位移式平移**（每次事件跳一截的突跳
/// 来源），改由拖动会话内的逐帧时间累积平移（见 [EdgePanSession]）——仅轨道
/// 带预览条拖动触发，本换算保持纯时间换算。内容区口径即本带口径：时间轴零点
/// 之左让出 [kTrackPrefixWidth] 的轨道片头带，片头不吃时间映射。
({TimelineWindow window, Duration target}) seekTargetForFingerX({
  required Duration total,
  required TimelineWindow window,
  required double width,
  required double x,
}) {
  final target = TrackBandGeometry.eval(
    total: total,
    window: window,
    width: width,
    prefixWidth: kTrackPrefixWidth,
  ).axis.xToTime(x);
  return (window: window, target: target);
}

/// 贴边平移会话（带内唯一一份 ticker）：三条路径共用——带内空白精细调整的
/// 命中列路径、预览线拖动族（第九族）与学习段圈选族（第十族）。手指位与
/// 「平移后重算」的驱动者随会话登记，不因拆族而复制 ticker。
///
/// 构造注入四件事：ticker 工厂（宿主 vsync）、现势拖动几何快照、窗口写回与
/// 双指在场谓词；逐帧调用只经 [hold]。
class EdgePanSession {
  EdgePanSession({
    required this.createTicker,
    required this.context,
    required this.updateWindow,
    required this.pinchActive,
  });

  /// ticker 工厂（宿主 vsync）：tick 回调即本会话的逐帧体。
  final Ticker Function(void Function(Duration) onTick) createTicker;

  /// 现势拖动几何快照（总时长 + 生效窗口 + 渲染盒；不齐备 = 空 → 停）。
  final DragContext? Function() context;

  /// 可视窗口写回（平移一步）。
  final void Function(TimelineWindow) updateWindow;

  /// 双指在场读取（冻结判据的真实来源）。
  final bool Function() pinchActive;

  /// 本次贴边平移的手指位。
  Offset? _finger;

  /// 本次贴边平移的逐帧驱动者：平移窗口后按同一手指位重算落点；返回 false =
  /// 滚到头/圈到头，停 ticker（既有语义逐族如实保留）。
  bool Function(bool windowMoved)? _drive;

  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  /// scrub 会话中的指针数（第二指落下冻结 seek 的同款语义——冻结期
  /// 也不平移；预览线接管路径恒为 1）。
  int _pointerCount = 1;

  /// scrub 会话中的指针数写点。
  set pointerCount(int value) => _pointerCount = value;

  /// 逐帧交下本次的手指点与「平移后重算」的驱动者（贴边平移会话的唯一登记
  /// 口）：进入边沿区即启 ticker。
  void hold(Offset finger, bool Function(bool windowMoved) drive) {
    _finger = finger;
    _drive = drive;
    final ctx = context();
    if (ctx != null &&
        edgePanDepthPx(x: finger.dx, width: ctx.box.size.width) > 0) {
      _startTicker();
    }
  }

  /// 拖动会话结束（scale 会话收口/预览线拖动收口/圈选收口）：停 ticker、
  /// 清手指位与驱动者。
  void stop() {
    _finger = null;
    _drive = null;
    _stopTicker();
  }

  /// 释放 ticker（宿主 dispose）。
  void dispose() => _ticker?.dispose();

  /// 贴边平移会话 ticker（带内唯一一份）：手指位于边沿区内时逐帧驱动，空闲
  /// 也持续（手指静止仍平移）；离开边沿区即停（后续 move 重进再启）。已存在
  /// 即幂等复用。
  void _startTicker() {
    if (_ticker != null) return;
    _lastElapsed = Duration.zero;
    _pointerCount = 1;
    _ticker = createTicker(_onTick)..start();
  }

  void _stopTicker() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
  }

  /// 逐帧贴边平移：手指在边沿区内 → 按侵入深度取速度（出缘归一
  /// 线性渐进），以帧间时长平滑累积平移窗口，再把「平移后的重算」交给本次
  /// 会话登记的驱动者（预览线拖动按同位置重 seek、学习段圈选按同位置重新
  /// 解析并延伸圈选；帧级预览与窗口钳制不变——[TimelineWindow.pannedBy]
  /// 钳制在 `[0, total]`）。第二指落下冻结期不平移（与 seek 冻结同语义）；
  /// 离开边沿区停 ticker。
  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final finger = _finger;
    // 双指在场冻结贴边平移（贴边平移的 seek 落点不经过子级拖拽
    // 守卫，须在此拦下，避免与双指会话的窗口驱动相抗）；抬回单指后
    // 驱动者重启 ticker。scale-scrub 加指冻结（>=2）同语义。
    if (finger == null || _pointerCount >= 2 || pinchActive()) {
      _stopTicker();
      return;
    }
    final ctx = context();
    if (ctx == null) {
      _stopTicker();
      return;
    }
    final w = ctx.box.size.width;
    final depth = edgePanDepthPx(x: finger.dx, width: w);
    if (depth <= 0) {
      _stopTicker();
      return;
    }
    final shift = edgePanShiftFor(
      depthPx: depth,
      width: w,
      elapsed: dt,
      microsecondsPerPixel: TrackBandGeometry.eval(
        total: ctx.total,
        window: ctx.window,
        width: w,
        prefixWidth: kTrackPrefixWidth,
      ).microsecondsPerPixel,
    );
    if (shift == Duration.zero) return;
    // 左缘 → 窗口左移（看更早内容）；右缘 → 右移（看更晚内容）。
    final signed = finger.dx <= w / 2 ? -shift : shift;
    final win = ctx.window;
    final panned = win.pannedBy(signed);
    final moved = panned.start != win.start || panned.end != win.end;
    if (moved) updateWindow(panned);
    // 平移后的重算归驱动者：返回 false = 滚到头/圈到头，停 ticker
    // （长按拖动圈选「窗口已钳在片首/片尾即停、圈到首/末段即停」的既有语义
    // 住在那条驱动闭包里）。
    if (!(_drive?.call(moved) ?? true)) _stopTicker();
  }
}
