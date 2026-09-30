/// 节拍规整：预算驱动的有界相位等时化。
///
/// 把识别拍点序列切成「相位预算」驱动的段，段内按两端锚定线性插值等时化。
/// 切分与等时化同处一个零框架依赖的纯函数：[regularizeBeatTimes]。
///
/// 切分：从锚点 `s` 向后试长候选段 `[s..e]`，段内所有拍相对两端锚定直线
/// `t[s] → t[e]` 的偏离不超过 [phaseBudgetMs] 就继续；越界即在上一拍封段
/// `[s..e−1]`、以 `e−1`（识别拍点）为下一段锚点。段边界拍恒为识别拍点原样，
/// 故跨段相位连续；真实相位跳变瞬间击穿预算、天然断段且不被重排；慢漂移
/// 累积到预算就重锚，误差永不越界。
///
/// 等时化：段内 `t'[k] = round(t[s] + (t[e] − t[s])·(k − s)/(e − s))`；
/// 段首尾精确等于识别拍点（整段零累计漂移）。不足 [minRunBeats] 拍的段不
/// 等时化、原样直通。
///
/// 退化（绝不失败）：拍点不足 2 个、输入非严格递增、算法内部异常、或取整后
/// 不再严格递增——任一发生即整条原样输出（等于未规整，`runs` 为空），
/// 不抛错、不阻断。
library;

/// 相位预算（毫秒）：段内任一拍相对两端锚定直线的偏离上限。
const double phaseBudgetMs = 25;

/// 最小等时化段拍数（一个八拍）；不足不等时化、原样直通。
const int minRunBeats = 8;

/// 规整段（拍序号闭区间）。相邻段共享边界拍（前一段末拍 = 后一段锚点）。
class RegularizationRun {
  const RegularizationRun({required this.startIndex, required this.endIndex});

  /// 首拍序号（含）。
  final int startIndex;

  /// 末拍序号（含）。
  final int endIndex;

  int get beatCount => endIndex - startIndex + 1;

  /// 短段：不足 [minRunBeats] 拍，不等时化、原样直通。
  bool get isShort => beatCount < minRunBeats;

  @override
  bool operator ==(Object other) =>
      other is RegularizationRun &&
      other.startIndex == startIndex &&
      other.endIndex == endIndex;

  @override
  int get hashCode => Object.hash(startIndex, endIndex);
}

/// 规整结果：等时化后的时刻序列（同长、整数毫秒）+ 段结构。
class BeatRegularization {
  const BeatRegularization({required this.times, required this.runs});

  /// 规整拍点（严格递增、整毫秒）；退化时即识别拍点原样。
  final List<Duration> times;

  /// 段结构；退化时为 `[]`。
  final List<RegularizationRun> runs;
}

/// 规整识别拍点序列（升序）→ 等时化后的拍点序列。
BeatRegularization regularizeBeatTimes(List<Duration> beatTimes) {
  try {
    if (beatTimes.length < 2) return _passthrough(beatTimes);

    final ms = [for (final t in beatTimes) t.inMilliseconds];
    for (var i = 1; i < ms.length; i++) {
      if (ms[i] <= ms[i - 1]) return _passthrough(beatTimes);
    }

    final runs = _segment(ms);
    final out = [...ms];
    for (final run in runs) {
      if (run.isShort) continue;
      final s = run.startIndex;
      final e = run.endIndex;
      for (var k = s + 1; k < e; k++) {
        out[k] = ms[s] + _lineOffset(ms, s, e, k).round();
      }
    }

    // 取整后不再严格递增：整条原样输出。
    for (var i = 1; i < out.length; i++) {
      if (out[i] <= out[i - 1]) return _passthrough(beatTimes);
    }

    return BeatRegularization(
      times: [for (final value in out) Duration(milliseconds: value)],
      runs: runs,
    );
  } catch (_) {
    return _passthrough(beatTimes);
  }
}

BeatRegularization _passthrough(List<Duration> beatTimes) =>
    BeatRegularization(times: List.of(beatTimes), runs: const []);

/// 预算驱动的锚点切分：候选段 [s..e] 越界即封段 [s..e−1]、以 e−1 为新锚点。
List<RegularizationRun> _segment(List<int> ms) {
  final runs = <RegularizationRun>[];
  var start = 0;
  var end = start + 1;
  while (end < ms.length) {
    if (_fits(ms, start, end)) {
      end += 1;
      continue;
    }
    runs.add(RegularizationRun(startIndex: start, endIndex: end - 1));
    start = end - 1;
    end = start + 1;
  }
  runs.add(RegularizationRun(startIndex: start, endIndex: ms.length - 1));
  return runs;
}

/// 候选段 [s..e] 内所有拍相对两端锚定直线 `t[s] → t[e]` 的偏离 ≤ 预算。
bool _fits(List<int> ms, int s, int e) {
  for (var k = s; k <= e; k++) {
    final projected = ms[s] + _lineOffset(ms, s, e, k);
    if ((projected - ms[k]).abs() > phaseBudgetMs) return false;
  }
  return true;
}

/// 段 [s..e] 内第 k 拍相对段首锚点的线性偏移（毫秒，未取整）。
double _lineOffset(List<int> ms, int s, int e, int k) =>
    (ms[e] - ms[s]) * (k - s) / (e - s);
