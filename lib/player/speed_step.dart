/// 倍速步进参数模型（纯函数域，`player` 域）。
///
/// 语义（产品需求「倍速步进」）：从
/// 起步倍速开始，每个倍率循环每档遍数遍后增加递增量，直至封顶倍速，随后
/// 回到起步倍速重新循环。默认起步 0.5、封顶 1.0、每档 3 遍、递增量 0.1。
///
/// 本文件只含参数类型与纯函数（无 IO、无状态、无依赖），可单测直接验证；
/// 面板编辑与「激活段联动」不在本域，本域只就位参数模型与内核能力
/// （[PlaybackEngine.setRate]）。
library;

/// 倍速步进参数（起步倍速 / 封顶倍速 / 每档遍数 / 递增量）。
class SpeedStepParams {
  const SpeedStepParams({
    this.startRate = 0.5,
    this.maxRate = 1.0,
    this.lapsPerRate = 3,
    this.rateIncrement = 0.1,
  });

  /// 起步倍速（> 0）。
  final double startRate;

  /// 封顶倍速（>= [startRate]；步进序列末档收敛到此值，见 [speedStepRates]）。
  final double maxRate;

  /// 每档遍数：每个倍率循环的遍数（>= 1，整数）。
  final int lapsPerRate;

  /// 递增量：每遍循环后的增量（> 0）。
  final double rateIncrement;

  /// 参数是否合法（面板在非法时拒绝应用并提示）。
  bool get isValid =>
      startRate > 0 &&
      rateIncrement > 0 &&
      lapsPerRate >= 1 &&
      maxRate >= startRate - _rateEpsilon;

  SpeedStepParams copyWith({
    double? startRate,
    double? maxRate,
    int? lapsPerRate,
    double? rateIncrement,
  }) {
    return SpeedStepParams(
      startRate: startRate ?? this.startRate,
      maxRate: maxRate ?? this.maxRate,
      lapsPerRate: lapsPerRate ?? this.lapsPerRate,
      rateIncrement: rateIncrement ?? this.rateIncrement,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpeedStepParams &&
        other.startRate == startRate &&
        other.maxRate == maxRate &&
        other.lapsPerRate == lapsPerRate &&
        other.rateIncrement == rateIncrement;
  }

  @override
  int get hashCode =>
      Object.hash(startRate, maxRate, lapsPerRate, rateIncrement);

  @override
  String toString() =>
      'SpeedStepParams(startRate: $startRate, maxRate: $maxRate, '
      'lapsPerRate: $lapsPerRate, rateIncrement: $rateIncrement)';
}

/// 浮点比较容差（避免 0.5 + 0.1 之类的二进制表示误差）。
const double _rateEpsilon = 1e-9;

/// 倍率统一保留两位小数（与面板输入精度一致）。
///
/// 加 1e-6 抵消二进制表示的向下误差（如 `0.055 * 100` 实为 5.4999…），
/// 保证「四舍五入」按十进制语义生效。倍速域内（`player` 域）的两位小数
/// 取整一律走本函数（倍速设置钳制与步进档位共用，见 `speed_control.dart`）。
double roundRate(double value) => ((value * 100) + 1e-6).roundToDouble() / 100;

/// 步进档位序列：起步倍速、起步+递增量、…、直至封顶倍速（含，末档固定为封顶）。
///
/// 例（默认参数）：`[0.5, 0.6, 0.7, 0.8, 0.9, 1.0]`。
///
/// 若递增量不能整除 `(maxRate - startRate)`（如 0.5→0.8→1.1 越过封顶 1.0），
/// 越过封顶之前的中间档保留（0.5、0.8），再补上末档封顶（`[0.5, 0.8, 1.0]`），
/// 保证封顶倍速始终可达。
///
/// 参数非法（[SpeedStepParams.isValid] 为 false）时抛 [ArgumentError]。
List<double> speedStepRates(SpeedStepParams params) {
  _assertValid(params);
  final rates = <double>[];
  var rate = params.startRate;
  while (rate < params.maxRate - _rateEpsilon) {
    rates.add(roundRate(rate));
    rate = roundRate(rate + params.rateIncrement);
  }
  rates.add(params.maxRate);
  return List.unmodifiable(rates);
}

/// 第 [cycleIndex] 遍练习循环（0 起）应使用的倍率。
///
/// 每个倍率连续使用 [SpeedStepParams.lapsPerRate] 遍，用满后升一档；末档
/// （封顶）用满 [SpeedStepParams.lapsPerRate] 遍后回到起步倍速重新循环。
///
/// 例（默认参数）：cycleIndex 0–2 → 0.5；3–5 → 0.6；…；15–17 → 1.0；
/// 18 → 0.5（回到起步）。
double rateForStepCycle(SpeedStepParams params, int cycleIndex) {
  _assertValid(params);
  if (cycleIndex < 0) {
    throw ArgumentError.value(cycleIndex, 'cycleIndex', '不能为负');
  }
  final rates = speedStepRates(params);
  return rates[(cycleIndex ~/ params.lapsPerRate) % rates.length];
}

void _assertValid(SpeedStepParams params) {
  if (!params.isValid) {
    throw ArgumentError('非法倍速步进参数：起步倍速>0、递增量>0、每档遍数>=1、封顶>=起步（收到 $params）');
  }
}

/// 倍率展示格式：去掉末尾无意义的 0（1.00 → 1、0.50 → 0.5）。
// 自 speed_control.dart 归位纯函数域（预设参数摘要共用）。
String formatRate(double rate) =>
    rate.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

// ---------------------------------------------------------------------------
// 倍率候选集（倍率选择化——取消数字输入，所有倍率
// 取值经选择控件给出，非法/越界值不可达）。
// ---------------------------------------------------------------------------

/// 倍速标题与步进起步/封顶的全档候选：0.1–2.0 步 0.05（39 档）。
List<double> rateCandidates() =>
    List.unmodifiable([for (var i = 10; i <= 200; i += 5) roundRate(i / 100)]);

/// 每档遍数候选：1–20（整数）。
final List<int> lapsPerRateCandidates = List<int>.unmodifiable(
  List.generate(20, (i) => i + 1),
);

/// 递增量候选（固定集合）。
const List<double> rateIncrementCandidates = [0.05, 0.1, 0.2, 0.25, 0.5];

/// 倍速标题下拉的候选序列：当前值 + 常用/历史置顶（去重、
/// 保持给定次序），其余全档按 0.05 网格补齐在后。
List<double> pinnedRateCandidates({
  required double current,
  required List<double> common,
  required List<double> history,
}) {
  final seen = <double>{};
  final ordered = <double>[];
  void add(double rate) {
    final rounded = roundRate(rate);
    if (seen.add(rounded)) ordered.add(rounded);
  }

  add(current);
  common.forEach(add);
  history.forEach(add);
  rateCandidates().forEach(add);
  return List.unmodifiable(ordered);
}
