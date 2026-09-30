/// 自动分段序列派生（锚点刀与半八拍左端顺延）。
///
/// 纯函数：由**八拍相位**（网格 + 八拍锚点）派生自动分段的分段线下刀位置
/// ——自**整曲第一个八拍点**起算，**每段 4 个整八拍区间**一条切割线；段内
/// 出现的**半八拍不占这 4 个配额、并入本段**（每个算 0.5，段长 = 4 +
/// 0.5 × 段内半八拍数，不设上限）。两刀规则：
///
/// - **锚点强制下刀**：八拍锚点处必有一条切割线并**清空配额**（锚点即新段
///   起点，其后重新数 N 个整八拍）；**锚点优先于配额刀**——配额未满也下刀
///   （段长按真实长度，如「半八拍结束于锚点」的 3.5 个八拍）、恰满同点只下
///   一刀。锚点密集产生的 1.0／2.0 短段接受、不设最短段限制。
/// - **半八拍左端顺延**：配额满点恰好落在某半八拍区间的**左端**时，切割线
///   **顺延**到该半八拍区间的**右端**（右端即其后锚点，锚点刀承担）——半
///   八拍归其前面那一段（该段 4.5），不切出 0.5 八拍的碎段。
///
/// 末段不足 4 个整八拍并入最后一段、收在尾线。落点必须严格位于首/尾线**开
/// 区间**内：与尾线同刻的刀位不下（无法产生非零末段；锚点刀同守卫）。
///
/// **无锚点等价域**：按**首线相位**等距切片（第 32n 拍）与按**首个八拍点**
/// 起算区间这两条规则，在**首个八拍点 = 首线（首拍即强拍）时逐点等价**——
/// 无锚点时区间恒为整八拍，半八拍与锚点刀都不触发，这也是全部既有网格与
/// 4/4 先验的常态；弱起网格（首拍非强拍、`firstDownbeatIndex > 0`）下切点
/// 自首个八拍点起算、整体后移 `firstDownbeatIndex` 拍——按首线相位的切点
/// 本不落在八拍点上，本口径要求切点必落八拍点，故二者在弱起网格上不可
/// 兼得，以本口径为准。
///
/// 区间口径与配额取整都读 `core/eight_beat_phase.dart` 的共用原语
///（[eightBeatIntervals] / [eightBeatIntervalWeight]），本函数不自实现相位
/// 或 stride 算术。
library;

import '../core/eight_beat_phase.dart';

/// 拍点秒时刻 → 毫秒取整 [Duration]（拍点换算共用原语）。
Duration durationFromSeconds(double seconds) =>
    Duration(milliseconds: (seconds * 1000).round());

/// 「分析完成即自动执行」默认档（每段 4 个整八拍区间）；菜单两档显式
/// 给 4 / 8，本常量只承载无交互路径的默认口径。
const int kAutoSegmentDefaultTier = 4;

/// 派生自动分段切点（升序）。
///
/// [phase] = 八拍相位派生源（网格 + 八拍锚点）——八拍点序列与区间宽度都
/// 取自它，故改锚点后再生成即按新相位重算；[startLine]/[endLine] = 首/尾
/// 线时刻（切割线只落二者的开区间内）；[fullIntervalsPerSegment] = 每段
/// 整八拍区间配额（档位：4 或 8，由「自动分段」菜单档位给出）。
///
/// 区间配额口径：区间**权重向下取整**即该区间占的配额——整八拍区间（相隔
/// 一个 stride 拍）占 1、半八拍区间（相隔一个小节）占 0（不占配额）。锚点
/// 刀与顺延规则见文件头。
List<Duration> deriveAutoSegmentCuts({
  required BeatPhase phase,
  required Duration startLine,
  required Duration endLine,
  required int fullIntervalsPerSegment,
}) {
  if (endLine <= startLine) return const [];
  final grid = phase.grid;
  // 锚点刀位置 = 锚点拍时刻（锚点自身恒为八拍点，必在区间序列端点集内）。
  final anchorTimes = {for (final anchor in phase.anchors) grid.beatTime(anchor)};
  final intervals = eightBeatIntervals(phase, startLine, endLine);
  final cuts = <Duration>[];
  var quota = 0;
  for (var i = 0; i < intervals.length; i++) {
    final interval = intervals[i];
    quota += eightBeatIntervalWeight(interval.beatGap, grid: grid).floor();
    final endIsAnchor = anchorTimes.contains(interval.end);
    // 半八拍左端顺延：配额满点落在下一半八拍区间的左端时不在本端下刀
    // ——切割线顺延到该半八拍右端（其锚点刀 / 后续配额刀承担）。权重只有
    // 0/1 且配额一到 N（[fullIntervalsPerSegment]）即下刀（顺延/锚点刀
    // 除外），故本判定处配额恒恰为 N，「≥」与「=」逐位一致。
    if (!endIsAnchor &&
        quota >= fullIntervalsPerSegment &&
        i + 1 < intervals.length &&
        eightBeatIntervalWeight(intervals[i + 1].beatGap, grid: grid)
                .floor() ==
            0) {
      continue;
    }
    // 锚点刀（锚点优先于配额刀，未满配额也下）与配额刀。
    if (!endIsAnchor && quota < fullIntervalsPerSegment) continue;
    quota = 0;
    // 开区间守卫：与尾线同刻的刀位不下（升序序列其后无刀可下）；
    // 末段不足配额的整段并入最后一段、收在尾线（循环自然结束、不下刀）。
    if (interval.end >= endLine) break;
    cuts.add(interval.end);
  }
  return List.unmodifiable(cuts);
}
