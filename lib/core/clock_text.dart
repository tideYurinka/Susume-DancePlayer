/// 时长时钟文案：全 App 两条口径，调用方按展示语义各取其一。
///
/// - [clockMmSs]：`mm:ss`。分钟按 60 取余——满一小时回绕、不进位不显示
///   小时（素材区间与录制区间用它，区间是片段内相对长度）。
/// - [clockMss]：`m:ss`。分钟取全量——小时折进分钟、分钟不补零（源时间轴
///   上的绝对时刻用它，超过一小时仍读作连续分钟）。
///
/// 两条口径的秒都按 60 取余、两位补零；负时长的行为与 `Duration` 一致，
/// 不另行钳制。
library;

/// `mm:ss`：分钟取 60 余数（不显小时）、分秒各两位补零。
String clockMmSs(Duration time) {
  final minutes = time.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

/// `m:ss`：分钟取全量（小时折进分钟、不补零）、秒两位补零。
String clockMss(Duration time) {
  final seconds = time.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${time.inMinutes}:$seconds';
}
