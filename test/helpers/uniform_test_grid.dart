import 'package:dance_learning_app/core/beat_grid.dart';

/// 均匀测试网格（零 Flutter）：每 [beatInterval] 一拍、共 [beatCount] 拍、
/// 第 [firstDownbeatIndex] 拍为首个强拍（其后每 [beatsPerBar] 拍一根强拍）。
///
/// 供四拍桶纯件与记录器测试注入「真实网格」态——[nature] 恒 ready、
/// 末拍序号非空，因此 [BeatGridReads.hasRealBeats] 为真；与真实网格同边界
/// 语义（早于首拍定位 -1、越末拍钳到末拍）。
class UniformTestGrid implements BeatGrid {
  UniformTestGrid({
    this.beatInterval = const Duration(milliseconds: 500),
    this.firstDownbeatIndex = 0,
    this.beatCount = 64,
    this.beatsPerBar = 4,
  }) : assert(beatCount > 0);

  final Duration beatInterval;

  @override
  final int firstDownbeatIndex;

  final int beatCount;

  @override
  final int beatsPerBar;

  @override
  BeatGridNature get nature => BeatGridNature.ready;

  @override
  Duration beatTime(int index) => beatInterval * index;

  @override
  int beatIndexAt(Duration time) {
    if (time.isNegative) return -1;
    final index = time.inMicroseconds ~/ beatInterval.inMicroseconds;
    return index >= beatCount ? beatCount - 1 : index;
  }

  @override
  bool isDownbeat(int index) => (index - firstDownbeatIndex) % beatsPerBar == 0;

  @override
  int? get lastBeatIndex => beatCount - 1;

  @override
  Duration beatsDuration(int count, {int from = 0}) => beatInterval * count;

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) {
    final first = beatIndexAt(start);
    return [
      for (var i = first < 0 ? 0 : first; i < beatCount; i++)
        if (beatTime(i) <= end && beatTime(i) >= start) beatTime(i),
    ];
  }
}
