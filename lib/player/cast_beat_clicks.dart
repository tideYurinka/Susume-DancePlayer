/// 拍声排程派生（纯件，播放页侧）：把**节拍网格 + 音源段表 + 半拍线 + 音量
/// 口径**折成一份 [CastBeatClick] 列表，交给投屏渲染的拍声轨合成。
///
/// ## 为什么住在播放页侧
///
/// 段表、音源设置与音量口径都在播放页（`metronome_source_registry.dart`、
/// `song_loudness.dart`），而投屏域**不得 import 播放页**（依赖方向护栏钉住）。
/// 于是这条派生留在播放页，产出的是投屏域的值类型（数据，不是回调）——两边
/// 各自只依赖自己的东西。
///
/// ## 口径
///
/// - **整拍**：网格第 `0..末拍` 逐拍，时刻取 `beatTime(index)`；拍号 = 相对
///   首个强拍的 `index % beatsPerBar + 1`，选段经 core 的
///   [selectMetronomeSlot]（与手机本地发声同一条选段规则）；无界网格（占位 /
///   秒制兜底）按**素材时长**截断，不外推出片尾之外的拍。
/// - **半拍**：用户半拍线，开关开才排；与整拍同毫秒的线丢掉（同一刻一声）。
/// - **音量**：按槽位取（`metronomePlayVolumeProvider` 那份口径），
///   与本地播放共用同一个取值点。
/// - **待支持音源**（注册表 `available: false`，占位空段）：**一条都不排**——
///   手机本地此刻不发声，副本里也不该多出一轨拍声。
/// - **八拍号**（只对「按号发音」类音源有用）取自动相位口径；那类音源今天
///   都还是占位（上一条直接返回空表），等它们真出货时这里要接
///   `beatPhaseProvider` 的锚点求值（届时另开一条改动，不在本票暗中兜底）。
library;

import '../cast/cast_render_request.dart';
import '../core/beat_grid.dart';
import 'metronome_source_registry.dart';

/// 派生这份素材的拍声排程（升序）。
List<CastBeatClick> buildCastBeatClicks({
  required BeatGrid grid,
  required MetronomeSourceEntry source,
  required Duration duration,
  required double Function(MetronomeSegmentSlot slot) volumeOf,
  List<Duration> halfBeatLines = const [],
  bool halfBeatEnabled = false,
}) {
  // 待支持音源：本地不发声，排程也就是空的。
  if (!source.available) return const [];

  final table = MetronomeSegmentTable.of(source);
  final groupIndex = selectMetronomeSpeedGroupIndex(
    source.speedGroups,
    grid.nominalBeat.inMilliseconds,
  );
  String assetOf(MetronomeSegmentSlot slot) =>
      table.loads[metronomeSegmentIdOf(source, groupIndex, slot)].asset;

  final beatsPerBar = grid.beatsPerBar == 0 ? kBeatsPerBar : grid.beatsPerBar;
  final firstDownbeat = grid.firstDownbeatIndex;
  final last = grid.lastBeatIndex;

  final clicks = <CastBeatClick>[];
  for (var index = 0; ; index++) {
    if (last != null && index > last) break;
    final time = grid.beatTime(index);
    if (time >= duration) break; // 无界网格：素材时长之外不再排
    if (time < Duration.zero) continue; // 负平移产出的拍点：没有可放的画面
    final offset = index - firstDownbeat;
    final beatCount = ((offset % beatsPerBar) + beatsPerBar) % beatsPerBar + 1;
    final eightCount = offset < 0 ? 0 : offset ~/ kBeatsPerEightCount + 1;
    final slot = selectMetronomeSlot(
      eightCount: eightCount,
      beatCount: beatCount,
      mode: source.mode,
    );
    clicks.add(
      CastBeatClick(time: time, asset: assetOf(slot), volume: volumeOf(slot)),
    );
  }

  if (halfBeatEnabled) {
    final wholeBeats = {for (final click in clicks) click.time};
    for (final line in halfBeatLines) {
      if (line < Duration.zero || line >= duration) continue;
      if (wholeBeats.contains(line)) continue; // 与整拍同一刻：只留整拍那一声
      clicks.add(
        CastBeatClick(
          time: line,
          asset: assetOf(MetronomeSegmentSlot.half),
          volume: volumeOf(MetronomeSegmentSlot.half),
        ),
      );
    }
  }

  clicks.sort((a, b) => a.time.compareTo(b.time));
  return clicks;
}
