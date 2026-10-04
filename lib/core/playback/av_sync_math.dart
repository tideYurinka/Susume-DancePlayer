/// 音画同步换算纯函数：UI 延迟值（ms，正 = 声音晚到）与
/// 媒体层 / 节拍声触发的换算收口。
///
/// 符号口径（方向同源，± 以真机听感校准为准）：正 Δ = 声音晚到 →
/// **延迟视频对齐声音**。媒体层取 mpv `audio-delay` 负值（mpv 语义
/// 正=延迟音频）；节拍声触发读取正平移（嗒声提前 Δ）。视觉链
/// 不消费 Δ：屏幕上的拍点只由视频时间轴与节拍网格决定。
library;

/// 数值边界与步长（ms）。
const int kAvSyncMinMs = -1000;
const int kAvSyncMaxMs = 1000;
const int kAvSyncStepMs = 10;

/// 越界钳制（±1000 双向）。
int clampAvSyncMs(int ms) => ms.clamp(kAvSyncMinMs, kAvSyncMaxMs);

/// 媒体层偏移（纯函数）：mpv `audio-delay` 秒值 = −Δ·rate（负 = 延迟
/// 视频；倍速下墙钟延迟恒为 Δ，媒体偏移随倍速缩放）。
double avSyncAudioDelaySeconds({required int delayMs, required double rate}) {
  return -delayMs / 1000 * rate;
}

/// 节拍声触发读平移缝（纯函数）：把 UI 延迟值换算为**媒体时间**
/// 平移量，加到节拍声触发读上（`reading + shift`）。这是 Δ×倍速的**唯一
/// 具名换算**：媒体轴（正式播放）与会话轴（校准
/// 会话，倍速因子取 1）都经本函数取平移，乘法算式只活在此处。符号口径
/// （正 Δ =
/// 声音晚到）与媒体层同源，媒体时间平移方向相反：嗒声**提前** Δ 墙钟
/// 秒（触发读取更靠后的媒体时间 = 拍点尚未到达即发声；媒体时间随倍速
/// 缩放，墙钟提前恒为 Δ）——校准后拍声同卡轨上刻度。延迟 0 = 零平移，
/// 行为与现状一致。
Duration avSyncTickTriggerShiftMedia({
  required int delayMs,
  required double rate,
}) {
  return Duration(microseconds: (delayMs * 1000 * rate).round());
}
