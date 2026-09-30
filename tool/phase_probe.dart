import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dance_learning_app/player/beat_schedule.dart'
    show kMetronomeLookaheadWindow;

/// 真机相位差探针：对「节拍声按当前实现播放 + 回录输出
/// 音频」的合成/真机录音做频段起音检测，量出「拍声 − 网格拍点」「音乐内容
/// − 网格拍点」两组相位差（毫秒），并解析播放路径上的「指令时刻 ↔ 原生
/// 播放头」trace 行——用于把「排程错」与「输出/引擎管线延迟」分开。
///
/// 纯 Dart（无 Flutter/IO 依赖）：宿主用已知相位差的合成信号直测口径，
/// 真机录音由 `tool/real_device_phase_probe.dart` 解码 WAV 后走同一组函数。

/// 一个频段的起音检测配置：复解调中心频率 + 起音最小间隔 + 门限比例。
class BandOnsetConfig {
  const BandOnsetConfig({
    required this.centerHz,
    this.minGapMs = 150,
    this.thresholdRatio = 0.3,
  });

  /// 复解调中心频率（Hz）。
  final double centerHz;

  /// 相邻起音的最小间隔（毫秒，按半拍间距以下取值防双检）。
  final double minGapMs;

  /// 起音门限 = 该频段包络峰值 × 该比例。
  final double thresholdRatio;
}

/// 节拍声「普通」音源整拍段主频（音源资产实测）：
/// 回录分离的「拍声」频段。号 1/5 重音资产 1315Hz 与夹具敲击 1000Hz 邻近，
/// 不参与分离。
const double kProbePlainHz = 880;

/// 夹具敲击非重音整拍主频（`tool/generate_metronome_fixture.dart` 敲击
/// 重音 1000Hz、其余整拍 1500Hz）：「音乐内容」频段取整拍敲击——与拍声
/// 整拍段 880Hz 失谐 620Hz（包络窗下互漏 ~3%），而重音 1000Hz 与 880Hz
/// 只差 120Hz，不可分。
const double kProbeMusicHz = 1500;

/// 包络低通窗（样本数）：固定窗长让两个频段的包络可直接比较幅值（分离的
/// 依据）。默认 ≈ 6.3ms（22050Hz 下 138 样本）：邻频串扰（≥120Hz 失谐）
/// 衰减一个量级以上，起音定位精度仍在几毫秒。
int envelopeWindow(int sampleRate) => math.max(1, sampleRate ~/ 160);

/// 单频段包络：复解调（乘 e^{-iωn}）→ 滑动等权低通 → 幅值。
/// 低通窗带来的群延迟 ≈ 半窗，由调用方回补。
Float32List _bandEnvelope(
  Float32List samples,
  int sampleRate,
  double centerHz,
  int w,
) {
  final n = samples.length;
  final omega = 2 * math.pi * centerHz / sampleRate;
  var cosI = 1.0;
  var sinI = 0.0;
  final cosStep = math.cos(omega);
  final sinStep = math.sin(omega);
  final cosBack = math.cos(omega * w);
  final sinBack = math.sin(omega * w);
  var reSum = 0.0;
  var imSum = 0.0;
  final env = Float32List(n);
  for (var i = 0; i < n; i++) {
    reSum += samples[i] * cosI;
    imSum -= samples[i] * sinI;
    if (i >= w) {
      final jw = i - w;
      final cosJ = cosI * cosBack + sinI * sinBack; // cos(ω(i−w))
      final sinJ = sinI * cosBack - cosI * sinBack; // sin(ω(i−w))
      reSum -= samples[jw] * cosJ;
      imSum += samples[jw] * sinJ;
    }
    final nextCos = cosI * cosStep - sinI * sinStep;
    final nextSin = sinI * cosStep + cosI * sinStep;
    cosI = nextCos;
    sinI = nextSin;
    if (i >= w - 1) {
      env[i] = math.sqrt(reSum * reSum + imSum * imSum);
    }
  }
  return env;
}

/// 一条起音：时刻（毫秒）+ 所属频段在该时刻的包络幅值。
class Onset {
  const Onset({required this.ms, required this.strength});

  final double ms;
  final double strength;
}

/// [detectSeparatedOnsets] 的底层：单频段起音检测。包络过门限
/// （峰值 × [BandOnsetConfig.thresholdRatio]）的上沿为起音，留最小间隔防
/// 双检；回溯到包络 10% 上沿并补回半窗群延迟。
///
/// 门限相对本频段峰值——其它频段的串扰同样会过门限，**频段归属**由
/// [detectSeparatedOnsets] 的双频段幅值支配比较决定；单独调用本函数时
/// 不要把它的输出直接当某一频段的专属起音。
List<Onset> detectBandOnsets(
  Float32List samples,
  int sampleRate,
  BandOnsetConfig config,
) {
  final n = samples.length;
  if (n == 0) return const [];
  final w = envelopeWindow(sampleRate);
  final env = _bandEnvelope(samples, sampleRate, config.centerHz, w);
  var peak = 0.0;
  for (var i = 0; i < n; i++) {
    if (env[i] > peak) peak = env[i];
  }
  final threshold = peak * config.thresholdRatio;
  final floor = peak * 0.1;
  final minGap = (config.minGapMs * sampleRate / 1000).round();
  final groupDelay = (w / 2).round();
  final onsets = <Onset>[];
  var lastAt = -minGap;
  var armed = true;
  for (var i = 0; i < n; i++) {
    if (env[i] >= threshold) {
      if (armed && i - lastAt >= minGap) {
        var start = i;
        while (start > 0 && env[start] > floor && i - start < minGap) {
          start--;
        }
        lastAt = start;
        onsets.add(Onset(
          ms: math.max(0, start - groupDelay) * 1000 / sampleRate,
          strength: env[i],
        ));
        armed = false;
      }
    } else {
      armed = true;
    }
  }
  return onsets;
}

/// 双频段分离：在 [beatHz]（拍声）与 [musicHz]（音乐内容）两频段分别检测
/// 候选起音（同窗长、各自相对门限），每条候选归属**包络幅值更大**的频段
/// ——同窗长下幅值可直接比较，邻频串扰（低于真起音一个量级）被支配淘汰。
({List<double> beat, List<double> music}) detectSeparatedOnsets(
  Float32List samples,
  int sampleRate, {
  required double beatHz,
  required double musicHz,
  required double minGapMs,
  double thresholdRatio = 0.3,
}) {
  final beatCfg = BandOnsetConfig(
    centerHz: beatHz,
    minGapMs: minGapMs,
    thresholdRatio: thresholdRatio,
  );
  final musicCfg = BandOnsetConfig(
    centerHz: musicHz,
    minGapMs: minGapMs,
    thresholdRatio: thresholdRatio,
  );
  final w = envelopeWindow(sampleRate);
  final beatEnv = _bandEnvelope(samples, sampleRate, beatHz, w);
  final musicEnv = _bandEnvelope(samples, sampleRate, musicHz, w);
  // 起音瞬态是宽带的（两频段都抬升），归属比较取起音后 8–30ms 的稳态段：
  // 真所属频段包络满幅、串扰频段回到泄漏底。
  bool ownsSteadyState(Onset o, Float32List own, Float32List other) {
    final from =
        ((o.ms + 8) * sampleRate / 1000).round().clamp(0, own.length - 1);
    final to = ((o.ms + 30) * sampleRate / 1000)
        .round()
        .clamp(from + 1, own.length);
    var ownMax = 0.0;
    var otherMax = 0.0;
    for (var i = from; i < to; i++) {
      if (own[i] > ownMax) ownMax = own[i];
      if (other[i] > otherMax) otherMax = other[i];
    }
    return ownMax >= otherMax;
  }

  final beat = <double>[];
  for (final o in detectBandOnsets(samples, sampleRate, beatCfg)) {
    if (ownsSteadyState(o, beatEnv, musicEnv)) beat.add(o.ms);
  }
  final music = <double>[];
  for (final o in detectBandOnsets(samples, sampleRate, musicCfg)) {
    if (ownsSteadyState(o, musicEnv, beatEnv)) music.add(o.ms);
  }
  return (beat: beat, music: music);
}

/// 一组相位差读数：逐拍差 + 中位数 + 最大偏差（相对中位数）。
class PhaseReport {
  const PhaseReport({
    required this.diffsMs,
    required this.matchedCount,
    required this.expectedCount,
    required this.medianMs,
    required this.maxDeviationMs,
    required this.maxAbsMs,
  });

  /// 配对成功的逐拍相位差（onset − 网格拍点，毫秒，按拍序）。
  final List<double> diffsMs;

  final int matchedCount;
  final int expectedCount;

  /// 相位差中位数（毫秒）——「拍声 − 网格拍点」的读数本体。
  final double medianMs;

  /// 逐拍差相对中位数最大偏差（毫秒）——抖动/离散度。
  final double maxDeviationMs;

  /// 逐拍差绝对值最大（毫秒）。
  final double maxAbsMs;

  @override
  String toString() =>
      '拍$matchedCount/$expectedCount 中位数=${medianMs.toStringAsFixed(1)}ms '
      '最大偏差=${maxDeviationMs.toStringAsFixed(1)}ms '
      'maxAbs=${maxAbsMs.toStringAsFixed(1)}ms';
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/// 把起音列表配对到已知网格拍点：逐拍取窗内最近起音，窗内无起音 = 漏拍。
PhaseReport phaseReport({
  required List<double> expectedMs,
  required List<double> onsets,
  double toleranceMs = 100,
}) {
  final diffs = <double>[];
  var searchFrom = 0;
  for (final g in expectedMs) {
    var best = -1.0;
    var bestAt = -1;
    for (var i = searchFrom; i < onsets.length; i++) {
      final d = onsets[i] - g;
      if (onsets[i] > g + toleranceMs) break;
      if (d.abs() <= toleranceMs && (best < 0 || d.abs() < best.abs())) {
        best = d;
        bestAt = i;
      }
    }
    if (bestAt >= 0) {
      diffs.add(best);
      searchFrom = bestAt + 1;
    }
  }
  final median = diffs.isEmpty ? 0.0 : _median(diffs);
  var maxDev = 0.0;
  var maxAbs = 0.0;
  for (final d in diffs) {
    maxDev = math.max(maxDev, (d - median).abs());
    maxAbs = math.max(maxAbs, d.abs());
  }
  return PhaseReport(
    diffsMs: diffs,
    matchedCount: diffs.length,
    expectedCount: expectedMs.length,
    medianMs: median,
    maxDeviationMs: maxDev,
    maxAbsMs: maxAbs,
  );
}

/// 一组回录的双相位读数：拍声、音乐内容，以及以音乐起音为公共参照的
/// 「拍声相对音乐」相位差（= 拍声中位数 − 音乐中位数，用于把「排程错」
/// 与「输出/引擎管线延迟」分开：前者两组一起错，后者只有拍声组错）。
class DualPhaseReport {
  const DualPhaseReport({
    required this.beat,
    required this.music,
    required this.beatRelativeToMusicMs,
  });

  final PhaseReport beat;
  final PhaseReport music;

  /// 拍声相对音乐内容的相位差（毫秒）：正 = 拍声比音乐晚。
  final double beatRelativeToMusicMs;

  @override
  String toString() =>
      '拍声−网格：$beat\n音乐−网格：$music\n拍声−音乐：'
      '${beatRelativeToMusicMs.toStringAsFixed(1)}ms';
}

/// 分析一段回录：在拍声频段（[kProbePlainHz]）与音乐频段
/// （[kProbeMusicHz]）分离检测起音，与等拍网格（[bpm] × [beats]；
/// [startOffsetMs] = 回录起点相对媒体起点的偏移，用于对齐回录与媒体
/// 时间轴）配对，[toleranceMs] = 逐拍配对窗。
DualPhaseReport analyzePhaseRecording(
  Float32List samples,
  int sampleRate, {
  required int bpm,
  required int beats,
  double startOffsetMs = 0,
  double toleranceMs = 100,
}) {
  final beatMs = 60000 / bpm;
  final expected = List.generate(
      beats, (i) => startOffsetMs + i * beatMs);
  final separated = detectSeparatedOnsets(
    samples,
    sampleRate,
    beatHz: kProbePlainHz,
    musicHz: kProbeMusicHz,
    minGapMs: beatMs / 2,
  );
  final beat = phaseReport(
    expectedMs: expected,
    onsets: separated.beat,
    toleranceMs: toleranceMs,
  );
  final music = phaseReport(
    expectedMs: expected,
    onsets: separated.music,
    toleranceMs: toleranceMs,
  );
  return DualPhaseReport(
    beat: beat,
    music: music,
    beatRelativeToMusicMs: beat.medianMs - music.medianMs,
  );
}

/// 「指令时刻 ↔ 原生播放头」trace 统计（解析
/// `[beatAudio] phaseProbe cmdMs=… estMs=… leadMs=… kind=…` 行；[leadMs] =
/// 指令目标媒介时刻 − 当时估计可听媒介时刻，即排程提前量）。
class SchedulingTraceStats {
  const SchedulingTraceStats({
    required this.count,
    required this.medianLeadMs,
    required this.minLeadMs,
    required this.maxLeadMs,
  });

  final int count;
  final double medianLeadMs;
  final double minLeadMs;
  final double maxLeadMs;

  @override
  String toString() => '指令$count条 提前量中位数='
      '${medianLeadMs.toStringAsFixed(1)}ms '
      '[${minLeadMs.toStringAsFixed(1)}, ${maxLeadMs.toStringAsFixed(1)}]';
}

/// 排程判定：指令本身是否落在正确时刻。
enum SchedulingVerdict {
  /// 提前量落在 (0, 前瞻窗]：指令时刻正确，可听相位差归输出/引擎管线。
  onTime,

  /// 提前量为负：指令落在估计可听时刻之后（排程错/被钳到当下）。
  behindEstimate,

  /// 提前量超出前瞻窗：排程比设计提前过多（锚/速率换算可疑）。
  aheadOfLookahead,

  /// 无 trace 行：构建未开 `BEAT_AUDIO_PHASE_PROBE` 或指令未流经渲染器。
  noTrace,
}

final double _kLookaheadMs =
    kMetronomeLookaheadWindow.inMilliseconds.toDouble();

SchedulingVerdict classifyScheduling(SchedulingTraceStats stats) {
  if (stats.count == 0) return SchedulingVerdict.noTrace;
  if (stats.medianLeadMs <= 0) return SchedulingVerdict.behindEstimate;
  if (stats.maxLeadMs > _kLookaheadMs) {
    return SchedulingVerdict.aheadOfLookahead;
  }
  return SchedulingVerdict.onTime;
}

final RegExp _traceLine = RegExp(
  r'phaseProbe cmdMs=([\d.eE+-]+) estMs=([\d.eE+-]+) leadMs=([\d.eE+-]+)',
);

/// 从 logcat 抓取的文本行里解析 phaseProbe trace 行，聚合提前量统计。
SchedulingTraceStats parsePhaseProbeTrace(Iterable<String> lines) {
  final leads = <double>[];
  for (final line in lines) {
    final m = _traceLine.firstMatch(line);
    if (m != null) leads.add(double.parse(m.group(3)!));
  }
  if (leads.isEmpty) {
    return const SchedulingTraceStats(
      count: 0,
      medianLeadMs: 0,
      minLeadMs: 0,
      maxLeadMs: 0,
    );
  }
  return SchedulingTraceStats(
    count: leads.length,
    medianLeadMs: _median(leads),
    minLeadMs: leads.reduce(math.min),
    maxLeadMs: leads.reduce(math.max),
  );
}
