/// 最近强拍解析：八拍锚点的唯一
/// 合法落点 = **强拍**（八拍大线或四拍中线）——把任意请求位置解析为网格上
/// 最近的强拍时刻，落在非强拍上的请求由此被拉回强拍（「非强拍上无落点」）。
///
/// 与 `half_beat_snap.dart` 同族：纯函数 seam、
/// 不经 UI。区别在**目标集合**——本文件解的是 downbeat（强拍）本身，与八拍
/// 相位无关（相位由 `core/eight_beat_phase.dart` 的 [BeatPhase] 另行求值，
/// 锚点只改"哪根强拍是八拍点"，不改"哪拍是强拍"）。
///
/// 三态边界语义（与同族一致）：
///
///   - **有界真实网格** → 覆盖区（首拍..末拍）内全部强拍为候选；请求位置
///     早于首拍/晚于末拍时贴首/末强拍（**不越界**、不外推虚假强拍）；
///     网格无强拍（识别退化）返回 null（调用侧拒绝落点）。
///   - **无界均匀网格**（占位/异常态）→ 按定位拍邻域（± 一小节）枚举强拍
///     候选；就绪门在调用侧（生产入口由就绪置灰门挡住）。
///
/// 等距并列取时间靠后者（[nearestCandidate] 收口，与既有对齐落点纪律一致）。
library;

import '../core/beat_grid.dart';
import 'snap.dart' show nearestCandidate;

/// 强拍落点（[resolveDownbeatLanding] 的结果）：**时刻 + 拍序号**成对返回
/// ——锚点身份 = 拍序号，落点的两个面必须同源解析，调用方不得
/// 自行从时刻反查序号。
class DownbeatLanding {
  const DownbeatLanding({required this.beatIndex, required this.time});

  /// 该强拍的拍序号（锚点身份）。
  final int beatIndex;

  /// 该强拍时刻（吸附后的落点）。
  final Duration time;
}

/// 解析 [position] 就近的强拍落点；网格无强拍返回 null。
DownbeatLanding? resolveDownbeatLanding(
  Duration position, {
  required BeatGrid grid,
}) {
  final last = grid.lastBeatIndex;
  final candidates = <(int, Duration)>[];
  if (last != null) {
    if (last < 0) return null;
    for (var i = 0; i <= last; i++) {
      if (grid.isDownbeat(i)) candidates.add((i, grid.beatTime(i)));
    }
  } else {
    // 无界网格：以定位拍为中心、± 一小节内枚举强拍（不扫全轴）。
    final center = grid.beatIndexAt(position);
    for (
      var i = center - grid.beatsPerBar;
      i <= center + grid.beatsPerBar;
      i++
    ) {
      if (i >= 0 && grid.isDownbeat(i)) candidates.add((i, grid.beatTime(i)));
    }
  }
  // 最近邻比较复用既有收口（等距并列取靠后者），再把时刻对回其拍序号
  // ——两个面同源解析，调用方不自行反查。
  final time = nearestCandidate([
    for (final candidate in candidates) candidate.$2,
  ], position);
  if (time == null) return null;
  final match = candidates.firstWhere((candidate) => candidate.$2 == time);
  return DownbeatLanding(beatIndex: match.$1, time: time);
}

/// 解析 [position] 就近的强拍时刻；网格无强拍返回 null（[resolveDownbeatLanding]
/// 的时刻面）。
Duration? resolveDownbeatSnap(Duration position, {required BeatGrid grid}) =>
    resolveDownbeatLanding(position, grid: grid)?.time;
