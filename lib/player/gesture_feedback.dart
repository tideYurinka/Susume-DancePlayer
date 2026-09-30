import 'package:flutter/widgets.dart';

/// 播放手势反馈相位。
///
/// 手势反馈状态控制器只描述「当前处于哪个手势反馈相位」——
/// 具体指示内容由浮层部件挂载到 [GestureFeedbackOverlay]；
/// 三指跳转短提示为事件+定时驱动、不属手势会话相位，以独立
/// 「控制器 + IgnorePointer 浮层」落地（见 `notice.dart`）。
enum GestureFeedbackPhase {
  idle,

  /// 进度拖动中（scrubbing）：画面随目标帧逐帧定格预览。
  scrubbing,

  /// 音量/亮度调节中（levelAdjust）：单指垂直滑自轴向锁定起，
  /// 屏幕正中显示横向滑条（图标 + 按当前值填充），松手即消失。
  levelAdjust,
}

/// 音量/亮度调节对象（横向滑条左端图标按此区分）。
///
/// 与手势轴向分支同源（单指垂直滑按起始半区，右半屏=音量、左半屏=亮度，
/// 向上为增，见 `lib/player/gestures.dart`）：亮度用太阳图标、音量用喇叭图标。
enum LevelAdjustKind { volume, brightness }

/// 手势反馈状态控制器。
///
/// 播放手势作用期间的纯视觉提示统一走「状态控制器 + IgnorePointer 浮层」
/// 模式（与循环/延迟播放提示同构）：本控制器维护相位
/// （idle/scrubbing/levelAdjust）与音量/亮度调节的瞬时数据
/// （调节对象/当前值）并在变化时通知监听者；指示内容在
/// [GestureFeedbackOverlay] 中按相位挂载，浮层用
/// [IgnorePointer] 包裹——不拦截触摸、不与手势争 arena。三指跳转短提示
/// 不属手势会话相位：事件触发、约 0.6s 定时淡出，走同构的
/// 独立控制器 + 浮层（`notice.dart`），不挤占本相位机。
///
/// 本控制器不持有引擎；暂停/恢复与逐帧 seek 由播放器页在相位切换时编排
/// （引擎调用序列由 FakeEngine 断言）。
class GestureFeedbackController extends ChangeNotifier {
  GestureFeedbackPhase _phase = GestureFeedbackPhase.idle;

  // 进度拖动取消区待取消：仅 scrubbing 相位下有效。
  bool _cancelArmed = false;

  // 音量/亮度调节的瞬时数据：仅 levelAdjust 相位下有效。
  LevelAdjustKind _levelKind = LevelAdjustKind.volume;
  double _levelValue = 0.0;

  // 本次手势的起始手指数（见 [startPointerCount]）。
  int _startPointerCount = 1;

  GestureFeedbackPhase get phase => _phase;

  /// 是否处于进度拖动定格预览（scrubbing）。
  bool get isScrubbing => _phase == GestureFeedbackPhase.scrubbing;

  /// 是否处于音量/亮度调节反馈（levelAdjust）。
  bool get isLevelAdjusting => _phase == GestureFeedbackPhase.levelAdjust;

  /// 是否处于进度拖动「取消区」待取消：scrubbing 相位下手指焦点
  /// 是否进入画面左上角取消区（扇形判定）。待取消 → 浮层转
  /// 警示色并显示「松开取消」；在此松开即取消本次进度调整（seek 回退到轴
  /// 锁定暂停点快照、恢复手势前播放态）。非 scrubbing 相位下恒为 false。
  bool get cancelArmed => _cancelArmed;

  /// 是否有激活的反馈相位（[GestureFeedbackOverlay] 据此显隐）。
  bool get isActive => _phase != GestureFeedbackPhase.idle;

  /// 当前音量/亮度调节对象（levelAdjust 相位下有效）。
  LevelAdjustKind get levelKind => _levelKind;

  /// 当前音量/亮度值（0..1；levelAdjust 相位下有效，滑条填充长度据此
  /// 从左到右实时更新）。
  double get levelValue => _levelValue;

  /// 本次手势的起始手指数（进度拖动两档灵敏度按它分：1 = 低灵敏度、
  /// ≥2 = 高灵敏度）；手势会话开始时由仲裁域写入，缺省 1。
  int get startPointerCount => _startPointerCount;

  /// 记录本次手势的起始手指数（onScaleStart 一次性写入；瞬时数据，不通知）。
  void noteStartPointerCount(int count) => _startPointerCount = count;

  /// 进入 scrubbing（进度拖动轴锁定起、引擎暂停定格时调用；幂等）。
  void beginScrubbing() {
    if (_phase == GestureFeedbackPhase.scrubbing) return;
    _phase = GestureFeedbackPhase.scrubbing;
    _cancelArmed = false; // 新会话复位待取消
    notifyListeners();
  }

  /// 结束 scrubbing（手势结束、恢复播放或保持暂停时调用；幂等）。
  void endScrubbing() {
    if (_phase == GestureFeedbackPhase.idle) return;
    _phase = GestureFeedbackPhase.idle;
    _cancelArmed = false;
    notifyListeners();
  }

  /// 更新进度拖动取消区待取消态（仅 scrubbing 相位下调用有效，
  /// 逐帧以手指焦点位置判定）：进入取消区 [armed]=true（浮层转警示色 +
  /// 「松开取消」）、移出 false；变化才通知。非 scrubbing 相位调用无副作用
  /// （状态在下一次进入 scrubbing 时复位）。
  void setCancelArmed(bool armed) {
    if (_phase != GestureFeedbackPhase.scrubbing) return;
    if (_cancelArmed == armed) return;
    _cancelArmed = armed;
    notifyListeners();
  }

  /// 显示/更新音量/亮度调节反馈（自轴锁定起每次音量/亮度动作时调用）：
  /// 记录调节对象 [kind] 与当前值 [value]（0..1，越界钳制、未变化不通知）；
  /// 尚未处于 levelAdjust 相位则进入（滑条随轴锁定出现），已处于则只更新
  /// 当前值（填充实时更新）。结束用 [endLevelAdjust]。
  void showLevelAdjust({required LevelAdjustKind kind, required double value}) {
    final clamped = value.clamp(0.0, 1.0);
    final changed =
        _phase != GestureFeedbackPhase.levelAdjust ||
        _levelKind != kind ||
        _levelValue != clamped;
    _levelKind = kind;
    _levelValue = clamped;
    if (changed) {
      _phase = GestureFeedbackPhase.levelAdjust;
      notifyListeners();
    }
  }

  /// 结束音量/亮度调节反馈（手势结束立即调用，松手即消失、无延迟淡出；
  /// 幂等）。
  void endLevelAdjust() {
    if (_phase != GestureFeedbackPhase.levelAdjust) return;
    _phase = GestureFeedbackPhase.idle;
    notifyListeners();
  }
}

/// 手势反馈浮层宿主。
///
/// 播放手势作用期间的纯视觉提示统一经此宿主叠加到画面之上：监听
/// [GestureFeedbackController]，相位激活（非 idle）时把 [contentBuilder]
/// 产出的内容以 [IgnorePointer] 包裹显示——不拦截任何触摸，手势可继续
/// 拖动（scrubbing seek 持续生效）。相位回到 idle 即不占空间。
///
/// 指示内容（屏幕正中迷你进度条/时间、音量亮度横向滑条）在此挂载；
/// 本文件只落地「状态控制器 + 宿主」共享骨架。三指跳转短提示
/// 为事件+定时驱动（非手势会话相位），不在此挂载——以独立的
/// `notice.dart` 浮层叠加（模式同构：IgnorePointer 纯提示）。
class GestureFeedbackOverlay extends StatelessWidget {
  const GestureFeedbackOverlay({
    super.key,
    required this.controller,
    required this.contentBuilder,
  });

  final GestureFeedbackController controller;

  /// 相位激活时构建浮层内容（纯视觉，IgnorePointer 包裹）。
  final Widget Function(BuildContext context) contentBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isActive) return const SizedBox.shrink();
        return IgnorePointer(child: contentBuilder(context));
      },
    );
  }
}
