/// 媒介时钟同步值类型：同步路径下推原生的**配对**
/// ——「媒介时刻」取自节拍呈现的唯一外推（`beat_presentation.dart`），
/// 配对的另一半（原生自己的帧位）由原生在收到下推时现取。倍速与播放态
/// 随同一份外推同源下推。仅服务发声排程，不参与视觉相位内插链。
library;

/// 同步对（单口 seam 值）：媒介时刻 + 倍速 + 播放态，同一份外推的一次读出。
class MediaClockSync {
  const MediaClockSync({
    required this.mediaTimeMs,
    required this.rate,
    required this.playing,
  });

  /// 下推时刻的媒介时间（毫秒；节拍呈现外推的读出）。
  final int mediaTimeMs;

  final double rate;

  /// 是否播放中。暂停/应活转停同样照实下推（原生按此停排新指令）。
  final bool playing;
}
