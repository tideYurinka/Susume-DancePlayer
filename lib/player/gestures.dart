/// 基础播放手势：贴近主流播放器的全屏手势。
///
/// 单一 ScaleGestureRecognizer 按 pointerCount 分支：
/// pan 与 scale 互斥不可并存，而 scale 的 `focalPointDelta` 按帧报告位移、
/// `pointerCount` 是判断手指数的权威方式——用一个
/// `GestureDetector.onScaleStart/onScaleUpdate` 同时覆盖单指/双指拖动：
///
/// - 单指水平滑 → 调进度（低灵敏度，每像素 [kSeekSensitivityMsPerPx] 毫秒）
/// - 双指水平滑 → 调进度（高灵敏度，× [kSeekDoubleFingerMultiplier]）
/// - 单指垂直滑 → 起始点在右半屏调音量、左半屏调亮度（向上为增）
/// - 双指垂直滑：不绑定动作
///
/// 双击暂停/播放用标准双击识别器（GestureDetector.onDoubleTap），不在此类。
/// 灵敏度数值为合理初值，后续标定。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart' show EdgeInsets, Offset, Size;

/// scrub 取消区尺寸上限：定义与半径/判定纯件收在 `editor_skeleton.dart`，
/// 此处仅按既有 import 面原样转出。
export 'editor_skeleton.dart' show kScrubCancelZoneSize;


/// 手势动作类型。
enum PlayerGestureActionType { seek, volume, brightness }

/// 一次 [PlayerGestureInterpreter.update] 映射出的动作。
class PlayerGestureAction {
  const PlayerGestureAction(this.type, this.deltaPx);

  final PlayerGestureActionType type;

  /// 沿动作正方向的像素增量：进度手势向右为正；音量/亮度向上为正。
  final double deltaPx;
}

/// 手势轴向：越过 slop 后锁定，锁定后不再切换（避免抖动翻转）。
enum PlayerGestureAxis { horizontal, vertical }

/// 轴向锁定阈值（逻辑像素）。对应 kTouchSlop（18px）。
const double kAxisLockSlop = 18.0;

/// 进度手势灵敏度（初值）：单指（低灵敏度）每像素毫秒数。
const double kSeekSensitivityMsPerPx = 50.0;

/// 双指（高灵敏度）灵敏度倍率（初值 3.0）。
const double kSeekDoubleFingerMultiplier = 3.0;

/// 三指滑动跳转触发阈值（逻辑像素）：并入 scale 流程后，横向累计位移
/// 首次超过该值即一次性方向跳转（左=首/右=尾；无标记分段线时回退视频
/// 首/尾）。
const double kThreeFingerJumpThresholdPx = 40.0;

/// 系统手势让路区固定下限（逻辑像素）：
/// 上报值小于下限的边取下限（API 30 以下恒为零上报，下限是必需项）。
const double kGestureYieldTopMinPx = 48.0;
const double kGestureYieldBottomMinPx = 44.0;
const double kGestureYieldSideMinPx = 16.0;

/// 系统手势让路区：四边内缩（逻辑像素），每边已按
/// `max(系统上报值, 固定下限)` 求值。
class SystemGestureYieldInsets {
  const SystemGestureYieldInsets({
    required this.top,
    required this.bottom,
    required this.left,
    required this.right,
  });

  final double top;
  final double bottom;
  final double left;
  final double right;
}

/// 让路区几何：以系统上报的手势内缩为入参，按每边
/// `max(上报值, 固定下限)` 求值。入参只取上报值，不读构建上下文、
/// 不依赖视口尺寸。
SystemGestureYieldInsets systemGestureYieldInsets({
  required EdgeInsets system,
}) => SystemGestureYieldInsets(
  top: math.max(system.top, kGestureYieldTopMinPx),
  bottom: math.max(system.bottom, kGestureYieldBottomMinPx),
  left: math.max(system.left, kGestureYieldSideMinPx),
  right: math.max(system.right, kGestureYieldSideMinPx),
);

/// 起手判定：本 burst 首指按下位置落在让路区内时返回被禁的轴集合
/// （顶/底 → 垂直，左右 → 水平；顶区与侧区重叠时两轴同时被禁）。
/// [downPosition] 为 null（起手点缺失）时不让路。
Set<PlayerGestureAxis> yieldedAxes({
  required Offset? downPosition,
  required Size screen,
  required SystemGestureYieldInsets insets,
}) {
  final down = downPosition;
  if (down == null) return const {};
  final vertical = down.dy <= insets.top || down.dy >= screen.height - insets.bottom;
  final horizontal = down.dx <= insets.left || down.dx >= screen.width - insets.right;
  return {
    if (vertical) PlayerGestureAxis.vertical,
    if (horizontal) PlayerGestureAxis.horizontal,
  };
}

/// 全屏单指长按 2×触发等待时长：播放中按下不动约 0.45s 即进入
/// 临时 2 倍速（指定约 0.45s）。
const Duration kLongPressDoubleSpeedTimeout = Duration(milliseconds: 450);

/// 长按 2× 的临时倍率：生效期间把内核切到此倍速（控制器经
/// `engine.setRate` 施加），松开恢复手势前生效倍速。数值即面板允许的上界
/// [speedRateMax]（2.0）。倍率恒为整数档；画面「2 倍速」提示文本为固定
/// 文案，不随本常量派生（见 `hold_double_speed.dart`）。
const double kLongPressDoubleSpeedRate = 2.0;

/// scrub 指示浮层几何常量（手势反馈浮层共用，
/// 「几何与时长常量集中于手势常量文件便于后续调参」）。
///
/// 屏幕正中迷你进度条宽度 ≈ 屏宽 60%。
const double kScrubIndicatorWidthFraction = 0.6;

/// 迷你进度条轨道高度（逻辑像素）。
const double kScrubIndicatorBarHeight = 4.0;

/// 时间文本与进度条之间的纵向间距（逻辑像素）。
const double kScrubIndicatorTextGap = 6.0;

/// 音量/亮度横向滑条整体宽度：约占屏宽比例（屏幕正中横向滑条约屏宽
/// 40%）。几何常量集中于此文件便于后续调参。
const double kLevelAdjustSliderWidthFraction = 0.4;

/// 音量/亮度横向滑条部件几何常量（图标/底轨/胶囊样式，
/// 宽度比例见 [kLevelAdjustSliderWidthFraction]）。
const double kLevelAdjustIconSize = 20.0;
const double kLevelAdjustIconTrackGap = 8.0;
const double kLevelAdjustTrackHeight = 6.0;
const double kLevelAdjustPillPaddingH = 10.0;
const double kLevelAdjustPillPaddingV = 8.0;
const double kLevelAdjustPillRadius = 20.0;

/// 把进度手势的像素增量换算为 seek 时间增量；[pointerCount] 决定灵敏度
/// （单指低灵敏度、双指高灵敏度）。
Duration seekDeltaFor(double deltaPx, int pointerCount) {
  final multiplier = pointerCount >= 2 ? kSeekDoubleFingerMultiplier : 1.0;
  return Duration(
    milliseconds: (deltaPx * kSeekSensitivityMsPerPx * multiplier).round(),
  );
}

/// 基础手势解释器：一次手势会话（onScaleStart → update×N → end）的纯逻辑。
///
/// 无 Flutter 依赖，可单测；widget 层把结果应用到
/// [PlaybackEngine.seek] / SystemMediaVolumeController
/// （`lib/player/system_volume.dart`：音量即系统媒体音量）/
/// ScreenBrightnessController（`lib/player/brightness.dart`）。
class PlayerGestureInterpreter {
  int? _pointerCount;
  bool? _startOnRightSide;
  PlayerGestureAxis? _axis;
  Set<PlayerGestureAxis> _yieldedAxes = const {};
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;

  /// 开始一次手势会话（onScaleStart）。
  ///
  /// [startX] 为手势起点 x（逻辑像素），[screenWidth] 为手势作用区宽度；
  /// 起始点在右半屏 → 垂直滑调音量，左半屏 → 调亮度。[yieldedAxes] 为本次
  /// 会话被禁的轴（系统手势让路）：轴向锁定规则不变，锁定到的
  /// 轴属于被禁集合时本次会话此后一律不产出动作、不退化为另一轴。
  void start({
    required int pointerCount,
    required double startX,
    required double screenWidth,
    Set<PlayerGestureAxis> yieldedAxes = const {},
  }) {
    _pointerCount = pointerCount;
    _startOnRightSide = startX >= screenWidth / 2;
    _axis = null;
    _yieldedAxes = yieldedAxes;
    _accumulatedDx = 0;
    _accumulatedDy = 0;
  }

  /// 处理一帧位移增量（onScaleUpdate 的 focalPointDelta）。
  ///
  /// 返回相对上一帧的动作增量；未越过轴向锁定阈值（或未 start）返回 null。
  /// 越过阈值后锁定轴向：水平 → 进度；垂直 → 单指按起始侧音量/亮度，
  /// 双指不绑定动作。
  PlayerGestureAction? update({required double dx, required double dy}) {
    final pointerCount = _pointerCount;
    if (pointerCount == null) return null;

    _accumulatedDx += dx;
    _accumulatedDy += dy;

    final axis = _axis ?? _resolveAxis();
    if (axis == null) return null; // 尚未越过轴向锁定阈值
    _axis = axis;
    if (_yieldedAxes.contains(axis)) return null; // 锁到被禁轴：整场无动作

    switch (axis) {
      case PlayerGestureAxis.horizontal:
        return PlayerGestureAction(PlayerGestureActionType.seek, dx);
      case PlayerGestureAxis.vertical:
        if (pointerCount != 1) return null; // 双指垂直滑不绑定
        final type = _startOnRightSide!
            ? PlayerGestureActionType.volume
            : PlayerGestureActionType.brightness;
        // 向上滑（dy < 0）为增。
        return PlayerGestureAction(type, -dy);
    }
  }

  /// 结束会话（onScaleEnd / onScaleCancel）：清空状态。
  void end() {
    _pointerCount = null;
    _startOnRightSide = null;
    _axis = null;
    _yieldedAxes = const {};
    _accumulatedDx = 0;
    _accumulatedDy = 0;
  }

  PlayerGestureAxis? _resolveAxis() {
    final dxAbs = _accumulatedDx.abs();
    final dyAbs = _accumulatedDy.abs();
    if (dxAbs < kAxisLockSlop && dyAbs < kAxisLockSlop) return null;
    return dxAbs >= dyAbs
        ? PlayerGestureAxis.horizontal
        : PlayerGestureAxis.vertical;
  }
}
