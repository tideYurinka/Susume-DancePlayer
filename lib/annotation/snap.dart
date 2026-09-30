/// 首尾线强制对齐：把时间点无条件对齐
/// 到节拍网格覆盖内的**真实拍点**。
///
/// 本 seam 没有配置参数，各线无条件
/// 对齐各自固定网格——首尾线 = 真实拍点（本文件）、分段线 = 八拍点（经
/// 相位源求值，见 `core/eight_beat_phase.dart`）、半拍线 = 半拍格点
///（`half_beat_snap.dart`）、临时衔接段起点 = 八拍点取整
///（`transition_segment.dart`）。
///
/// 首尾线网格语义：**真实拍点可用**（[BeatGridReads.hasRealBeats]）的
/// 覆盖区（首拍..末拍）内全部真实拍点（含弱起拍）均为对齐候选；覆盖区外
/// 或网格不可用（占位/异常均匀实现）自由落点/不可步进。吸附结果仍为
/// **绝对时间点**；落到有效区间边界等无效位置由调用侧（首尾线拖动/步进）
/// 再校验。等距并列取时间靠后者（[nearestCandidate] 收口）。
library;

import '../core/beat_grid.dart';

/// 候选集最近解析：从 [candidates] 中取距 [position]
/// 最近者；**等距并列取时间靠后者**。空候选集返回 null。首尾线真实拍点
/// 解析、半拍格点解析（`half_beat_snap.dart`）与八拍点解析（经相位源，
/// `core/eight_beat_phase.dart`）共用本收口，避免最近邻比较形状重复。
Duration? nearestCandidate(Iterable<Duration> candidates, Duration position) {
  Duration? best;
  var bestDistance = -1;
  for (final candidate in candidates) {
    final distance =
        (candidate.inMilliseconds - position.inMilliseconds).abs();
    if (best == null || distance <= bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

/// 候选集中严格越过 [position] 的相邻者（[forward] = 之后最近 / 之前最
/// 近）；无越过候选返回 null。首尾线真实拍点步进与半拍格点步进
///（`half_beat_snap.dart`）共用本收口，避免方向扫描形状重复。
Duration? adjacentCandidate(
  Iterable<Duration> candidates,
  Duration position, {
  required bool forward,
}) {
  Duration? best;
  for (final candidate in candidates) {
    final beyond = forward ? candidate > position : candidate < position;
    if (!beyond) continue;
    final currentBest = best;
    if (currentBest == null ||
        (forward ? candidate < currentBest : candidate > currentBest)) {
      best = candidate;
    }
  }
  return best;
}

/// 首尾线吸附（收敛为无条件）：真实拍点可用且落点在网格
/// 覆盖区内（首拍..末拍之间）→ 吸最近**真实拍点**（含弱起拍）；网格
/// 覆盖区外或网格不可用（占位/异常均匀实现，视为未就绪）→ 自由落点
///（返回原位置）。
///
/// 与首尾线可拖范围的关系：首尾线可拖到全视频 0..total，覆盖区外落点
/// 不回拉到末拍点。无「关闭吸附」分支——对齐无条件生效。
Duration snapRangeBoundary(
  Duration position, {
  required BeatGrid grid,
}) {
  if (!grid.hasRealBeats) return position; // 无网格语义：自由。
  final last = grid.lastBeatIndex!;
  if (position < grid.beatTime(0) || position > grid.beatTime(last)) {
    return position; // 网格覆盖区外：自由落点。
  }
  return nearestCandidate(
        grid.beatsInWindow(grid.beatTime(0), grid.beatTime(last)),
        position,
      ) ??
      position;
}

/// [position] 严格之后的相邻真实拍点时刻；无（网格不可用 / 已到末拍之后）
/// 返回 null（调用侧 no-op）。
Duration? nextBeatPoint(
  Duration position, {
  required BeatGrid grid,
}) => _adjacentBeatPoint(position, grid, forward: true);

/// [position] 严格之前的相邻真实拍点时刻；无（网格不可用 / 首拍之前）
/// 返回 null（调用侧 no-op）。
Duration? previousBeatPoint(
  Duration position, {
  required BeatGrid grid,
}) => _adjacentBeatPoint(position, grid, forward: false);

Duration? _adjacentBeatPoint(
  Duration position,
  BeatGrid grid, {
  required bool forward,
}) {
  if (!grid.hasRealBeats) return null;
  return adjacentCandidate(
    grid.beatsInWindow(grid.beatTime(0), grid.beatTime(grid.lastBeatIndex!)),
    position,
    forward: forward,
  );
}
