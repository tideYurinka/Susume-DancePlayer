/// 半拍吸附位置解析：把位置解析到
/// 节拍网格派生的**半拍格点**。
///
/// **半拍格点 = 仅相邻拍点之间的中点**（自首个强拍起、有界网格止于末拍，
/// 不外推虚假半拍位——与 `snap.dart` 格点边界约定一致）；候选集**不含拍点
/// 本身**（吸到拍点会与拍刻度重叠、失去半拍意义）。插入吸附（[resolveHalfBeatSnap]）、
/// 拖动吸附与帧步进（[nextHalfBeatPoint]/[previousHalfBeatPoint]）三处同源
/// 消费本文件的候选派生。派生在计算层完成、**不落盘计算**（落盘只存解析后
/// 的绝对时间点）。等距并列取时间靠后者（`snap.dart` 的 [nearestCandidate]
/// 收口）。网格无拍点返回 null（调用侧不插入/不步进）。
library;

import '../core/beat_grid.dart';
import 'snap.dart' show adjacentCandidate, nearestCandidate;

/// 无界网格邻域半径（以定位拍为中心上下各扫几拍生成中点候选；与
/// `snap.dart` 的邻域判定同一口径，不扫全轴）。
const int _unboundedNeighborhoodBeats = 2;

/// [start, end] 邻域内的中点候选（升序去重由网格单调性保证）。
Iterable<Duration> _midpointCandidates(
  BeatGrid grid,
  int firstBeat,
  int lastBeat,
) sync* {
  for (var i = firstBeat; i <= lastBeat; i++) {
    if (i < grid.firstDownbeatIndex) continue;
    yield _midpoint(grid.beatTime(i), grid.beatTime(i + 1));
  }
}

/// 解析 [position] 就近的半拍格点（相邻拍点中点）；网格无候选返回 null。
Duration? resolveHalfBeatSnap(Duration position, {required BeatGrid grid}) {
  final last = grid.lastBeatIndex;
  if (last != null && last < grid.firstDownbeatIndex) return null;
  final k = grid.beatIndexAt(position);
  final candidates = last == null
      // 无界网格（占位）：以定位拍为中心的邻近窗口内枚举中点。
      ? _midpointCandidates(
          grid,
          k - _unboundedNeighborhoodBeats,
          k + _unboundedNeighborhoodBeats,
        )
      // 有界网格：首强拍起到末拍前一拍的全部相邻中点。
      : _midpointCandidates(grid, grid.firstDownbeatIndex, last - 1);
  return nearestCandidate(candidates, position);
}

/// [position] 严格之后的相邻半拍格点；无（有界网格已到末中点之后）返回
/// null（调用侧 no-op）。
Duration? nextHalfBeatPoint(Duration position, {required BeatGrid grid}) =>
    _stepHalfBeatPoint(position, grid, forward: true);

/// [position] 严格之前的相邻半拍格点；无（首个中点之前——含弱起区间）
/// 返回 null（调用侧 no-op）。
Duration? previousHalfBeatPoint(Duration position, {required BeatGrid grid}) =>
    _stepHalfBeatPoint(position, grid, forward: false);

Duration? _stepHalfBeatPoint(
  Duration position,
  BeatGrid grid, {
  required bool forward,
}) {
  final last = grid.lastBeatIndex;
  if (last != null && last < grid.firstDownbeatIndex) return null;
  final k = grid.beatIndexAt(position);
  final candidates = last == null
      ? _midpointCandidates(
          grid,
          k - _unboundedNeighborhoodBeats,
          k + _unboundedNeighborhoodBeats,
        )
      : _midpointCandidates(grid, grid.firstDownbeatIndex, last - 1);

  return adjacentCandidate(candidates, position, forward: forward);
}

/// 相邻拍点的中点（半拍位；向下取整到微秒，与拍毫秒取整口径相容）。
Duration _midpoint(Duration a, Duration b) {
  final halfUs = (b.inMicroseconds - a.inMicroseconds) ~/ 2;
  return Duration(microseconds: a.inMicroseconds + halfUs);
}
