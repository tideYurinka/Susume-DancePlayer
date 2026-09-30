/// 帧时间显示与帧换算的共享纯函数。
///
/// 时间读数（控制层）与观看态 scrub 浮层共用 [formatFrameTime]（mm:ss:ff，
/// 帧号自 0 起）——消除既有「控制层 m:ss 秒级」与「浮层 mm:ss.d 十分位」
/// 两处私有格式分叉；帧时长换算（[frameDurationFor] / [kDefaultFrameDuration]）
/// 供帧步进复用。
///
/// 帧率来源：引擎/适配层可暴露的视频帧率（demux-fps，见
/// `PlaybackEngine.videoFps`）优先；取不到时用 [kDefaultVideoFps] 常量
/// 30fps（帧显示决策；不做自动探测算法）。
/// 全文件无 UI、无引擎依赖。
library;

/// 默认视频帧率：引擎/适配层取不到 demux-fps 时的回落值。
const double kDefaultVideoFps = 30;

/// 默认帧时长 = 1 / [kDefaultVideoFps]（1/30s，微秒精度向下取整）。
///
/// 供帧步进直接使用；非默认帧率时用 [frameDurationFor]。
const Duration kDefaultFrameDuration = Duration(microseconds: 33333);

/// 按帧率换算单帧时长（微秒级精度，向下取整）。
Duration frameDurationFor(double fps) =>
    Duration(microseconds: Duration.microsecondsPerSecond ~/ fps);

/// 把播放时长格式化为帧号时间文本：
/// 「mm:ss:ff」——分钟补足两位（分钟数 >= 10 后自然超出两位不封顶）、
/// 秒与帧号各补足两位、帧号自 0 起（秒内时刻 ÷ 单帧时长向下取整）。
///
/// [fps] 缺省为 [kDefaultVideoFps]；引擎可暴露 demux-fps 时由调用侧
/// 传入真实帧率。
String formatFrameTime(Duration duration, {double fps = kDefaultVideoFps}) {
  final frameDuration = frameDurationFor(fps);
  final minutes = duration.inMinutes;
  // 以微秒为基数取余（负时长不出现：播放位置恒 ≥ 0）。
  final remainderAfterMinutes = Duration(
    microseconds: duration.inMicroseconds % Duration.microsecondsPerMinute,
  );
  final seconds = remainderAfterMinutes.inSeconds;
  final frame = remainderAfterMinutes.inMicroseconds %
      Duration.microsecondsPerSecond ~/
      frameDuration.inMicroseconds;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}:'
      '${frame.toString().padLeft(2, '0')}';
}
