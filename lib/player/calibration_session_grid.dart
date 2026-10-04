/// 校准会话等拍网格纯函数：会话时间轴的拍点来源——
/// BPM 三档（歌曲节拍 / 120 / 160）、档可用性（无已对齐网格 → 歌曲档
/// 禁用、间隔回落默认 120）、每小节重音、无半拍。
///
/// 只含纯数据与判定；会话拍序（游标推进、进出场、档位变更自下一拍生效）
/// 收在节拍呈现对象（`beat_presentation.dart`）内部——会话不再有独立
/// 决策层。
library;

import '../core/beat_grid.dart';

/// 会话节奏档（歌曲节拍 / 120 / 160）。
enum CalibrationSessionBpmTier { song, bpm120, bpm160 }

/// 会话网格纯函数：等拍时刻表 + 档可用性 + 重音判定。
abstract final class CalibrationSessionGrid {
  /// 歌曲档在已对齐网格缺失时回落的默认 BPM。
  static const double defaultBpm = 120.0;

  /// 档可用性：歌曲档要求已对齐网格（能取到歌曲一拍间隔）；120/160 恒可用。
  static bool isTierAvailable(
    CalibrationSessionBpmTier tier,
    BeatGrid? songGrid,
  ) => tier == CalibrationSessionBpmTier.song
      ? _songIntervalOf(tier, songGrid) != null
      : true;

  /// 档节拍间隔（等拍）：歌曲档取已对齐网格自首个强拍起的一拍时长，
  /// 网格缺失回落默认 120；120/160 档按固定 BPM。
  static Duration beatIntervalOf(
    CalibrationSessionBpmTier tier,
    BeatGrid? songGrid,
  ) {
    return _songIntervalOf(tier, songGrid) ??
        Duration(milliseconds: (60000 / _fixedBpmOf(tier)).round());
  }

  /// 歌曲档且有已对齐网格时的一拍间隔；其余档 null（回落固定 BPM）。
  static Duration? _songIntervalOf(
    CalibrationSessionBpmTier tier,
    BeatGrid? songGrid,
  ) => tier == CalibrationSessionBpmTier.song && songGrid != null
      ? songGrid.beatsDuration(1, from: songGrid.firstDownbeatIndex)
      : null;

  /// 固定 BPM 档的 BPM 值（120/160；歌曲档无网格回落默认 120）。
  static double _fixedBpmOf(CalibrationSessionBpmTier tier) => switch (tier) {
    CalibrationSessionBpmTier.bpm160 => 160.0,
    _ => defaultBpm,
  };

  /// 第 [index] 拍（0 起）是否重音：每小节（[kBeatsPerBar] 拍）一个重音。
  static bool isAccent(int index) => index % kBeatsPerBar == 0;
}
