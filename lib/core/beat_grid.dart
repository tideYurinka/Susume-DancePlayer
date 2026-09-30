/// 节拍 seam：节奏来源唯一入口。
///
/// 向消费方（节拍轨渲染、吸附网格、拍数等待换算）暴露拍序列（时刻 +
/// downbeat/小节结构）与定位/换算原语（时间↔拍序号、任意 N 拍时长、
/// 开窗取拍）。真实网格（节拍识别产出）与均匀占位（无网格回退）双实现
/// 收在本 seam 后；测试注入的 fake 真实网格走同一条缝。
///
/// 占位实现为 demoBpm 语义（120 bpm、毫秒四舍五入取整），均匀 BPM 只
/// 存在于占位实现内部，对外不散点暴露。
///
/// 边界约定：占位网格在时间轴上无界（任意拍序号合法）；真实网格有界
/// （拍序号越界抛 [RangeError]，早于首拍的时间定位为 -1），实现侧在
/// 文档中标注各自边界语义。
library;

/// 节奏来源性质（三态落值）：网格值自陈自己是
/// 哪一种节奏来源——
///
/// - [BeatGridNature.ready] 就绪：节拍识别产出的真实网格（有界）；
/// - [BeatGridNature.placeholder] 占位：分析中/未开始的均匀占位网格
///   （无界，demoBpm 语义）；
/// - [BeatGridNature.secondsFallback] 秒制兜底：本次分析失败的异常态
///   哨兵网格（无界，每拍 [sentinelBeat]）。
///
/// 这是网格值上唯一的状态判别成员；其余读面全是同一处的派生（见
/// [BeatGridReads]）。判别由三个实现各自表态，映射点（节拍网格
/// provider）按节拍轨三态选实现、不自陈性质。
enum BeatGridNature { ready, placeholder, secondsFallback }

/// 异常态哨兵拍长（0.5 秒，唯一出处）：秒制兜底网格的单拍长度——
/// 异常态「一个八拍」等待 4 秒（[secondsFallbackEightBeat]）与「拒录
/// 阈值 = 名义一拍」（500ms，取值条款）共同取值的算术基点。
const Duration sentinelBeat = Duration(milliseconds: 500);

/// 八拍标称的秒制兜底（4 秒，唯一出处）：异常态「一个八拍」的时长。
/// 它是哨兵算术的结果（8 × [sentinelBeat]）而非特例——占位网格按
/// demoBpm 算八拍同样得 4 秒，两条路径殊途同归。
const Duration secondsFallbackEightBeat = Duration(milliseconds: 4000);

/// 小节拍数（4/4 固定先验，唯一出处）：三个网格实现与 DBN 配置缺省读
/// 此处，「一小节几拍」只有一个答案。
const int kBeatsPerBar = 4;

/// 八拍长度 = 两小节（唯一出处）：数拍拍号回卷、节拍动画八拍窗口、音源
/// 注册表重音槽位、八拍相位周期（八拍点间距 = 本常量拍数）同读此处
/// ——改拍号体系口径只改 [kBeatsPerBar] 一处。
const int kBeatsPerEightCount = kBeatsPerBar * 2;

/// 节拍网格 seam：拍序列 + 定位/换算原语。
abstract interface class BeatGrid {
  /// 节奏来源性质：本网格自陈的三态（[BeatGridNature]）。三个实现各自
  /// 表态。
  BeatGridNature get nature;

  /// 小节拍数（4/4 固定先验，取值唯一出处 = [kBeatsPerBar]）。
  int get beatsPerBar;

  /// 第 [index] 拍的时刻（0 起）。
  Duration beatTime(int index);

  /// 不晚于 [time] 的最近拍序号（占位网格以时间轴 0 对齐，负时间按 0；
  /// 真实网格早于首拍为 -1）。
  int beatIndexAt(Duration time);

  /// 第 [index] 拍是否 downbeat（小节首拍，强拍）。
  bool isDownbeat(int index);

  /// 首个 downbeat（强拍）拍序号（格点 0 = 首个强拍）。就绪真实网格 =
  /// 第一个 downbeat 拍序号（弱起时 > 0）；占位/
  /// 异常均匀实现恒 0；真实网格无 downbeat 时回落 0。
  int get firstDownbeatIndex;

  /// 末拍序号；无界网格（占位/异常均匀实现）为 null，真实网格 = 拍数 − 1
  /// （有界格点序列的终止判定，不外推出虚假格点）。
  int? get lastBeatIndex;

  /// 从第 [from] 拍起连续 [count] 拍的时长（相邻拍间距累加）。
  Duration beatsDuration(int count, {int from});

  /// `[start, end]` 闭窗内的拍时刻序列（升序）。
  List<Duration> beatsInWindow(Duration start, Duration end);
}

/// 网格派生读面：全部由性质 + 既有
/// 原语在同一处派生，零框架依赖——标注域纯函数可直接 import。可用性
/// 词汇只有两个谓词（[BeatGridReads.hasRealBeats] /
/// [BeatGridReads.isSecondsFallback]）；时长基准只有三条（[nominalBeat] /
/// [eightBeatNominal] / [leadTier]）。
extension BeatGridReads on BeatGrid {
  /// 真实拍点可用：就绪且拍点非空。不变式「性质为真实 ⟺ 末拍序号非空」
  /// （由测试钉住）。
  bool get hasRealBeats =>
      nature == BeatGridNature.ready && lastBeatIndex != null;

  /// 秒制兜底（异常态）：节拍不可用，等待换算走「档位数字即秒」。
  bool get isSecondsFallback => nature == BeatGridNature.secondsFallback;

  /// 有强拍：有界网格扫全拍，无界网格（占位/异常均匀铺拍，每小节首拍
  /// 恒为强拍）恒真——取代各消费点手写的强拍存在性判断。
  bool get hasStrongBeats {
    final last = lastBeatIndex;
    if (last == null) return true;
    for (var i = 0; i <= last; i++) {
      if (isDownbeat(i)) return true;
    }
    return false;
  }

  /// 名下单拍：一拍多长（拒录阈值的取值条款——异常态即哨兵
  /// [sentinelBeat] 500ms）。
  Duration get nominalBeat => beatsDuration(1);

  /// 八拍标称：8 × 拍长。异常态得 [secondsFallbackEightBeat]（4 秒，哨兵
  /// 算术的结果）；占位按 demoBpm 同得 4 秒；就绪按真实拍距累加。
  Duration get eightBeatNominal => beatsDuration(kBeatsPerEightCount);

  /// 前导档位：异常态档位数字即秒（2→2s / 4→4s / 8→8s），否则档位 ×
  /// 名义拍长；档位 0 两支都得零（`0 档特例`消失）。
  Duration leadTier(int tier) => isSecondsFallback
      ? Duration(seconds: tier)
      : nominalBeat * tier;

  /// 定位 [position] 所属拍的**唯一拍边界求值**：
  /// 早于首拍的时间钳到首拍（[BeatBoundary.beforeFirst] 置位），有界网格
  /// 末拍无下一拍（[BeatBoundary.nextBeat] 为 null）。求值层
  ///（`evaluateCurrentBeat`）与动画层（`deriveBeatPhase`、
  /// `projectUserHalfBeatLines`）同读这一份守卫，不再各写一种钳制写法。
  BeatBoundary beatBoundaryAt(Duration position) {
    final rawIndex = beatIndexAt(position);
    final index = rawIndex < 0 ? 0 : rawIndex;
    final start = beatTime(index);
    final last = lastBeatIndex;
    final nextBeat = last != null && index >= last ? null : beatTime(index + 1);
    return BeatBoundary(
      index: index,
      beforeFirst: rawIndex < 0,
      beatStart: start,
      nextBeat: nextBeat,
    );
  }
}

/// 拍边界求值结果（[BeatGridReads.beatBoundaryAt] 的产出值）。
class BeatBoundary {
  const BeatBoundary({
    required this.index,
    required this.beforeFirst,
    required this.beatStart,
    required this.nextBeat,
  });

  /// 所属拍序号（早于首拍的时间钳到首拍）。
  final int index;

  /// 位置早于网格首拍（真实网格定位 -1 的钳制标记）。
  final bool beforeFirst;

  /// 本拍起点（媒介时刻）。
  final Duration beatStart;

  /// 下一拍起点；有界网格末拍为 null。
  final Duration? nextBeat;

  /// 本拍终点 = 下一拍起点；有界网格末拍钳回拍首（拍内相位 0）。
  Duration get beatEnd => nextBeat ?? beatStart;
}

/// 占位节拍 BPM：均匀节奏来源只定义在本 seam。
const double placeholderBpm = 120.0;

/// 均匀占位网格：无网格数据时的回退实现，沿用既有 demoBpm 语义
/// （120 bpm：一拍 500ms；N 拍 = `N·60000/bpm` 毫秒四舍五入取整；
/// 4/4 小节，每 4 拍一个 downbeat，时间轴 0 对齐）。
class UniformBeatGrid implements BeatGrid {
  const UniformBeatGrid({this.bpm = placeholderBpm})
    : assert(bpm > 0, 'bpm 必须为正');

  /// 占位均匀节拍 BPM（仅本占位实现内部可见的节奏来源）。
  final double bpm;

  @override
  BeatGridNature get nature => BeatGridNature.placeholder;

  @override
  int get beatsPerBar => kBeatsPerBar;

  @override
  Duration beatTime(int index) =>
      Duration(milliseconds: (index * 60000 / bpm).round());

  @override
  int beatIndexAt(Duration time) {
    final index = (time.inMilliseconds * bpm / 60000).floor();
    return index < 0 ? 0 : index;
  }

  @override
  bool isDownbeat(int index) => index % beatsPerBar == 0;

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => null;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) {
    final beatMs = 60000 / bpm;
    final first = (start.inMilliseconds / beatMs).ceil();
    final last = (end.inMilliseconds / beatMs).floor();
    return [for (var i = first; i <= last; i++) beatTime(i)];
  }
}

/// 占位均匀网格共享实例：迁移期消费方（吸附/节拍轨/拍等待）的默认节奏
/// 来源；真实网格接入后由状态层替换为就绪/异常态实现。
const UniformBeatGrid placeholderBeatGrid = UniformBeatGrid();

/// 异常态回退网格：节拍不可用时「一个八拍」
/// 等待兜底 4 秒——每拍 [sentinelBeat] 0.5s（[beatTime] 以哨兵拍长均匀铺
/// 在时间轴 0 上），8 拍 = [secondsFallbackEightBeat] 4s；该网格仅作固定
/// 八拍等待与拍刻度兜底来源，吸附在此态停用、前导时长走 [BeatGridReads.leadTier]
///（档位数字即秒，由读面承载）。
class UnavailableBeatGrid implements BeatGrid {
  const UnavailableBeatGrid();

  @override
  BeatGridNature get nature => BeatGridNature.secondsFallback;

  @override
  int get beatsPerBar => kBeatsPerBar;

  @override
  Duration beatTime(int index) => sentinelBeat * index;

  @override
  int beatIndexAt(Duration time) {
    final index = time.inMilliseconds ~/ sentinelBeat.inMilliseconds;
    return index < 0 ? 0 : index;
  }

  @override
  bool isDownbeat(int index) => index % beatsPerBar == 0;

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => null;

  @override
  Duration beatsDuration(int count, {int from = 0}) => sentinelBeat * count;

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) {
    final beatMs = sentinelBeat.inMilliseconds;
    final first = (start.inMilliseconds / beatMs).ceil();
    final last = end.inMilliseconds ~/ beatMs;
    return [
      for (var i = first; i <= last; i++) Duration(milliseconds: i * beatMs),
    ];
  }
}
