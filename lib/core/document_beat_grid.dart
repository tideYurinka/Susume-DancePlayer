import 'beat_grid.dart';
import 'beat_point.dart';

/// 真实节拍网格：markers `beat` 段的 seam 实现。
///
/// 拍序列来自节拍识别产出（时刻 + downbeat/小节结构，4/4 固定先验）；
/// 网格有界——拍序号越界抛 [RangeError]，早于首拍的时间定位为 -1
/// （[BeatGrid] seam 的真实网格边界语义）。
class DocumentBeatGrid implements BeatGrid {
  DocumentBeatGrid({
    required List<BeatPoint> beats,
    double shift = 0,
    double density = 1,
    this.segmentDensities = const {},
    this.segments = const [],
  }) : _points = deriveBeatPoints(
         beats: beats,
         shiftMs: (shift * 1000).round(),
         density: density,
         segmentDensities: segmentDensities,
         segments: segments,
       ) {
    if (beats.isEmpty) {
      throw ArgumentError('真实网格至少需要一个拍点');
    }
  }

  /// 逐段档（见词条「段内倍频」）：键为段序、
  /// 值为档位数值（0.5 / 2；缺省空 = 全部段原样）。生效倍数 = 整曲档
  /// （[deriveBeatPoints] 的 density 入参）× 该段段内档，可超出整曲五档范围、
  /// 不钳制；只改段区间内的拍点与强拍，时刻类标注一律不动。
  final Map<int, double> segmentDensities;

  /// 分段几何（下标 = 段序，与 [segmentDensities] 的键对齐）：毫秒半开
  /// 区间 `[startMs, endMs)`，由学习段几何（首/尾 + 分段线）换算而来。
  final List<({int startMs, int endMs})> segments;

  /// 拍点（派生时刻毫秒 + down，按时刻升序）；拍序号即本列表下标。
  ///
  /// 派生时刻 = 网格拍点 + 节拍对齐平移量（shift 秒，
  /// 纯函数、非破坏——文档网格拍点不动；整体等距平移不改变升序与
  /// downbeat 结构，0 平移恒等）+ 节拍倍频重采样（density，
  /// 与平移量正交、可交换）。派生时刻**不钳**
  /// 0..视频时长（只对线平移要求钳制）：负平移可产出早于 0 的拍时刻
  /// （该拍对数拍/开窗仍为合法格点，消费方各自的区间边界语义不受影响）。
  final List<(int, bool)> _points;

  @override
  int get beatsPerBar => kBeatsPerBar;

  @override
  BeatGridNature get nature => BeatGridNature.ready;

  void _checkIndex(int index) {
    if (index < 0 || index >= _points.length) {
      throw RangeError('真实网格拍序号越界：$index（共 ${_points.length} 拍）');
    }
  }

  @override
  Duration beatTime(int index) {
    _checkIndex(index);
    return Duration(milliseconds: _beatMs(index));
  }

  /// 拍时刻毫秒；超出末拍时按末段拍间距线性外推（等待换算等消费方可能
  /// 越过末拍——拍等待发生在视频尾部时不少于拍数所需的时长），直接访问
  /// 仍受界（[beatTime] 对负序号抛错）。
  int _beatMs(int index) {
    if (index < _points.length) return _points[index].$1;
    final last = _points.length - 1;
    final interval = _points.length >= 2
        ? _points[last].$1 - _points[last - 1].$1
        : 500;
    return _points[last].$1 + (index - last) * interval;
  }

  @override
  int beatIndexAt(Duration time) {
    // 二分找不晚于 time 的最后一拍；早于首拍为 -1。
    if (_points.isEmpty || time.inMilliseconds < _points.first.$1) return -1;
    var lo = 0;
    var hi = _points.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_points[mid].$1 <= time.inMilliseconds) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  @override
  bool isDownbeat(int index) {
    _checkIndex(index);
    return _points[index].$2;
  }

  @override
  int get firstDownbeatIndex {
    for (var i = 0; i < _points.length; i++) {
      if (_points[i].$2) return i;
    }
    return 0; // 无 downbeat（识别退化）：锚定回落首拍。
  }

  @override
  int get lastBeatIndex => _points.length - 1;

  @override
  Duration beatsDuration(int count, {int from = 0}) {
    if (from < 0) {
      throw RangeError('真实网格拍序号越界：$from');
    }
    return Duration(milliseconds: _beatMs(from + count) - _beatMs(from));
  }

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) {
    final first = beatIndexAt(start);
    final times = <Duration>[];
    for (var i = first < 0 ? 0 : first; i < _points.length; i++) {
      final t = Duration(milliseconds: _points[i].$1);
      if (t > end) break;
      if (t >= start) times.add(t);
    }
    return times;
  }
}

/// 倍频派生（见词条「节拍倍频」「段内倍频」）：「网格拍点 + 平移量 +
/// 整曲档 + 逐段档 + 分段几何」的**纯函数**——统计投影按任意档位重建
/// 「记录时的桶格」也走本入口（不读文档字段；统计投影只传整曲档，桶格
/// 恒取整曲档）。
///
/// 整曲档部分（density）：
///
/// - 缺省（density = 1）= 原样：派生拍点 = 网格拍点 + 平移，down 位照搬
///   （用户可见行为零变化）；
/// - 快方向（density > 1）：相邻原拍之间插等分中点（×2 二等分、×4 四等分）；
/// - 慢方向（density < 1）：按**原首个强拍**定相位等距抽样（×½ 隔一原拍、
///   ×¼ 每四原拍取一——步长为整数个原拍，原强拍全部留下、不因取整错位）；
/// - **新强拍 = 自原首个强拍的派生序号起每 4 个派生拍一个**（照搬原 down
///   位会让小节仍长一倍）；原首个强拍的时刻位置在两方向
///   都保持不变。快方向拍数 = (N−1)×d+1（首末原拍固定，「×2 拍数翻倍」
///   在此口径下是约数——重采样不外推越过末原拍）。
///
/// 逐段档部分（[segmentDensities] + [segments]，
/// 见词条「段内倍频」）：[segments] 为分段几何（下标 = 段序，毫秒半开区间
/// `[startMs, endMs)`），[segmentDensities] 键为段序、值为档位数值
/// （0.5 / 2；1 = 原样 = 无键）。段序有几何且档位非原样时，该段区间内的
/// 派生整体改写：
///
/// - **生效倍数 = 整曲档 × 该段段内档**，自**节拍网格拍点**按生效倍数对
///   该段区间重采样（快方向同整曲一套等分插点、慢方向按**段首**定相等距
///   抽样——相位取段首所在的最后一个原拍），可超出整曲五档范围、不钳制；
/// - **段首恒是拍点**（无派生点落在段首时补一拍）且即该段**第一个强拍**，
///   段内强拍自段首起每 4 个派生拍一个——该段数拍与重音自段首 1｜1 起；
/// - **段内不消费八拍锚点**：锚点是整曲派生拍序号上的读面重定相（不在本
///   函数入参里），段内相位一律取段首，不存在第二种口径；
/// - **段尾不是整拍时收在段尾之前最后一拍**（区间外推不越段界）；段界上
///   的原拍归段外（下一段以其为段首）；段外回到整曲档拍序。
///
/// 前提：拍序列含强拍（识别正常产出 down 位）。无强拍的退化输入按首拍
/// 定相回落（与 [DocumentBeatGrid.firstDownbeatIndex] 同口径）。
List<(int, bool)> deriveBeatPoints({
  required List<BeatPoint> beats,
  required int shiftMs,
  double density = 1,
  Map<int, double> segmentDensities = const {},
  List<({int startMs, int endMs})> segments = const [],
}) {
  final shifted = [
    for (final beat in beats) ((beat.t * 1000).round() + shiftMs, beat.down),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (shifted.isEmpty) return shifted;
  final base = _resample(shifted, density);

  final applied = <({int startMs, int endMs, double factor})>[
    for (var order = 0; order < segments.length; order++)
      if (segmentDensities[order] != null && segmentDensities[order] != 1)
        (
          startMs: segments[order].startMs,
          endMs: segments[order].endMs,
          factor: density * segmentDensities[order]!,
        ),
  ];
  if (applied.isEmpty) return base;

  // 段外 = 整曲档派生剔除落进生效段区间的点（段界时刻归段外/下一段首）。
  final merged = <int, bool>{
    for (final p in base)
      if (!applied.any(
        (s) => p.$1 >= s.startMs && p.$1 < s.endMs,
      ))
        p.$1: p.$2,
  };
  final rawTimes = [for (final p in shifted) p.$1];
  for (final s in applied) {
    // 段首恒是拍点（局部下标 0）且即第一个强拍；其后为段区间内的重采样点。
    final segmentTimes = [s.startMs, ..._resampleWindow(rawTimes, s)];
    for (var i = 0; i < segmentTimes.length; i++) {
      merged[segmentTimes[i]] = i % kBeatsPerBar == 0;
    }
  }
  final keys = merged.keys.toList()..sort();
  return [for (final t in keys) (t, merged[t]!)];
}

/// 段区间内的重采样点（严格落在 `(startMs, endMs)` 内、升序去重）：段首
/// 拍由调用方补，段界上的点不属段内。
List<int> _resampleWindow(
  List<int> raw,
  ({int startMs, int endMs, double factor}) segment,
) {
  final start = segment.startMs;
  final end = segment.endMs;
  final factor = segment.factor;
  bool inside(int t) => t > start && t < end;
  final times = <int>[];
  if (factor > 1) {
    final d = factor.round();
    for (var i = 0; i < raw.length - 1; i++) {
      final a = raw[i];
      final b = raw[i + 1];
      if (b <= start || a >= end) continue;
      for (var j = 0; j < d; j++) {
        final t = a + ((b - a) * j / d).round();
        if (inside(t)) times.add(t);
      }
    }
    final last = raw.last;
    if (inside(last)) times.add(last);
  } else if (factor < 1) {
    final step = (1 / factor).round();
    // 相位取段首：锚定段首所在的最后一个原拍（段首早于首拍时回落首拍）。
    var anchor = 0;
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] <= start) {
        anchor = i;
      } else {
        break;
      }
    }
    for (var i = anchor; i < raw.length; i += step) {
      if (inside(raw[i])) times.add(raw[i]);
    }
  } else {
    times.addAll(raw.where(inside));
  }
  final deduped = <int>[];
  for (final t in times..sort()) {
    if (deduped.isEmpty || deduped.last != t) deduped.add(t);
  }
  return deduped;
}

/// 整曲档重采样（时刻 + down 结构，见 [deriveBeatPoints] 整曲档部分）。
List<(int, bool)> _resample(List<(int, bool)> shifted, double density) {
  if (density == 1) return shifted;

  final firstDown = shifted.indexWhere((p) => p.$2);
  var times = <int>[];
  if (density > 1) {
    final d = density.round();
    for (var i = 0; i < shifted.length - 1; i++) {
      final a = shifted[i].$1;
      final b = shifted[i + 1].$1;
      for (var j = 0; j < d; j++) {
        times.add(a + ((b - a) * j / d).round());
      }
    }
    times.add(shifted.last.$1);
  } else {
    final step = (1 / density).round();
    // 识别退化无强拍时回落首拍定相（与 [DocumentBeatGrid.firstDownbeatIndex]
    // 的无 downbeat 回落同口径）。
    final start = firstDown < 0 ? 0 : firstDown;
    for (var i = start; i < shifted.length; i += step) {
      times.add(shifted[i].$1);
    }
  }

  // 新强拍：自原首个强拍的派生序号起每 4 个派生拍一个。
  final firstDownDerived =
      density > 1 ? (firstDown < 0 ? 0 : firstDown * density.round()) : 0;
  return [
    for (var i = 0; i < times.length; i++)
      (times[i], i >= firstDownDerived && (i - firstDownDerived) % kBeatsPerBar == 0),
  ];
}

/// 锚点就地烘焙（见词条「八拍锚点」）：把「从 [fromDensity] 档改到
/// [toDensity] 档」后的八拍锚点集合按 `原序号 × 倍率` 重写——锚点指的
/// 是音乐位置，不是「第几拍」。
///
/// 入参 [anchors] 是 [fromDensity] 档派生网格上的拍序号；返回值是
/// [toDensity] 档派生网格上的拍序号。规则两方向统一：
///
/// - **快方向**：网格拍点全部留在派生序列里，旧锚点时刻在新序列中逐位
///   找到、序号按倍率放大，时刻与「它是不是八拍点」的判定都不变；
/// - **慢方向**：只保住落在新强拍（新派生网格的 down 位）上的锚点，
///   落不到的被丢弃——丢掉的正是识别给多了的那半数伪强拍（由新网格
///   的 down 位判定，与 [BeatPhase] 的锚点规范化同一条规则）。
///
/// 两档派生都按平移量 0 求值（平移不改变拍序与序号映射，与密度可交换）。
/// 越界旧锚点直接丢弃，不抛。
List<int> rebakeEightBeatAnchors({
  required List<BeatPoint> beats,
  required double fromDensity,
  required double toDensity,
  required List<int> anchors,
}) {
  final from = deriveBeatPoints(beats: beats, shiftMs: 0, density: fromDensity);
  final to = deriveBeatPoints(beats: beats, shiftMs: 0, density: toDensity);
  final toIndexByMs = {for (var i = 0; i < to.length; i++) to[i].$1: i};
  final rebaked = <int>[];
  for (final anchor in anchors) {
    if (anchor < 0 || anchor >= from.length) continue;
    final index = toIndexByMs[from[anchor].$1];
    if (index != null && to[index].$2) rebaked.add(index);
  }
  final deduped = <int>[];
  for (final index in rebaked..sort()) {
    if (deduped.isEmpty || deduped.last != index) deduped.add(index);
  }
  return deduped;
}
