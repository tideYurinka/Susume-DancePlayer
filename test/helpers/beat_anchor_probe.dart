import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/current_beat.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';

/// 数拍锚解析的公开求值口探针：`resolveBeatAnchor` 已并入
/// `current_beat.dart` 转私有，纯函数级用例改经 [evaluateBeatCountAnchor]
/// 断言。两种探针网格下归位为恒等，逐位等同旧私有解析：
/// - [gridLastBeatTime] 为空 → 占位无界网格（不归位、无末拍上限）；
/// - 非空 → 有界就绪但**无强拍**网格（八拍相位无原点，归位恒等），
///   末拍时刻即传入值。
Duration? resolveBeatAnchorProbe({
  required Duration? activeAnchor,
  Duration? recordingAnchor,
  Duration? delayAnchor,
  required Iterable<Duration> segmentLines,
  required Duration firstLine,
  required Duration position,
  required Duration? gridLastBeatTime,
}) {
  final grid = gridLastBeatTime == null
      ? const UniformBeatGrid()
      : _NoDownbeatBoundedGrid(gridLastBeatTime.inMilliseconds ~/ 500);
  return evaluateBeatCountAnchor(
    grid: grid,
    phase: BeatPhase(grid: grid),
    recordingAnchor: recordingAnchor,
    delayAnchor: delayAnchor,
    activeAnchor: activeAnchor,
    segmentLines: segmentLines.toList(),
    firstLine: firstLine,
    position: position,
  );
}

/// 数拍锚归位的公开求值口探针：`alignBeatCountAnchorToGrid` 已转私有，用例
/// 改经 [evaluateBeatCountAnchor]（就绪网格下 = 解析复合归位）。锚以
/// [BeatPhase] 自己的网格为准，位置即锚自身（解析恒返回锚），首线取足够早。
Duration? alignBeatCountAnchorToGridProbe({
  required BeatPhase phase,
  required Duration anchor,
}) {
  return evaluateBeatCountAnchor(
    grid: phase.grid,
    phase: phase,
    recordingAnchor: null,
    delayAnchor: null,
    activeAnchor: anchor,
    segmentLines: const [],
    firstLine: const Duration(seconds: -100),
    position: anchor,
  );
}

/// 就绪有界但无强拍的网格：无八拍相位原点，归位恒等。
class _NoDownbeatBoundedGrid implements BeatGrid {
  const _NoDownbeatBoundedGrid(this.lastIndex);

  final int lastIndex;

  @override
  BeatGridNature get nature => BeatGridNature.ready;

  @override
  int get lastBeatIndex => lastIndex;

  @override
  int get beatsPerBar => kBeatsPerBar;

  @override
  Duration beatTime(int index) => Duration(milliseconds: 500 * index);

  @override
  int beatIndexAt(Duration time) =>
      time.inMilliseconds < 0 ? -1 : time.inMilliseconds ~/ 500;

  @override
  bool isDownbeat(int index) => false;

  @override
  int get firstDownbeatIndex => 0;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}
