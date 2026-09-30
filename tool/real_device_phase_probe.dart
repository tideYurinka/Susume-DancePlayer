/// 真机相位差探针 CLI：对一段回录 WAV（节拍声按当前
/// 实现播放 + 输出音频录回）与可选的 logcat trace 抓取，输出——
/// 「拍声 − 网格拍点」「音乐内容 − 网格拍点」两组相位差（中位数 + 最大
/// 偏差，毫秒）、以音乐起音为公共参照的「拍声 − 音乐」读数，以及「指令
/// 时刻 ↔ 原生播放头」的排程提前量统计与判定（排程对/错分开归因）。
///
/// 用法（在仓库根目录，完整流程见 scripts/real_device_phase_probe.sh 与
/// docs/acceptance/beat-audio-phase-probe.md）：
///   dart run tool/real_device_phase_probe.dart \
///     --recording /tmp/phase_probe_speaker.wav \
///     --bpm 120 --beats 64 [--start-offset-ms 0] [--tolerance-ms 100] \
///     [--trace /tmp/logcat.txt]
/// 退出码 0 = 两组读数齐备（拍声与音乐至少各配对 4 拍）；非 0 = 读数不足。
library;

import 'dart:io';

import 'package:dance_learning_app/player/beat_audio_native.dart'
    show decodeWavMono;
import 'phase_probe.dart';

Never _fail(String msg) {
  stderr.writeln('real_device_phase_probe: $msg');
  exit(2);
}

void main(List<String> args) {
  String? next(String flag) {
    final i = args.indexOf(flag);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final recording = next('--recording') ?? _fail('缺少 --recording <wav>');
  final bpm = int.tryParse(next('--bpm') ?? '120') ?? _fail('--bpm 需整数');
  final beats = int.tryParse(next('--beats') ?? '64') ?? _fail('--beats 需整数');
  final startOffsetMs =
      double.tryParse(next('--start-offset-ms') ?? '0') ?? 0.0;
  final toleranceMs = double.tryParse(next('--tolerance-ms') ?? '100') ?? 100.0;
  final tracePath = next('--trace');

  final bytes = File(recording).readAsBytesSync();
  final wav = decodeWavMono(bytes);
  final report = analyzePhaseRecording(
    wav.samples,
    wav.sampleRate,
    bpm: bpm,
    beats: beats,
    startOffsetMs: startOffsetMs,
    toleranceMs: toleranceMs,
  );

  stdout.writeln('# 真机相位差探针读数（$recording，$bpm bpm × $beats 拍，'
      '容差 ${toleranceMs.toStringAsFixed(0)}ms，'
      '回录 ${wav.sampleRate}Hz）');
  stdout.writeln('拍声−网格拍点：${report.beat}');
  stdout.writeln('音乐−网格拍点：${report.music}');
  stdout.writeln('拍声−音乐（公共参照）：'
      '${report.beatRelativeToMusicMs.toStringAsFixed(1)}ms '
      '（正 = 拍声比音乐晚；音乐组随拍声组一起错 → 排程错；'
      '只有拍声组错 → 输出/引擎管线延迟）');

  if (tracePath != null) {
    final lines = File(tracePath).readAsLinesSync();
    final stats = parsePhaseProbeTrace(lines);
    final verdict = classifyScheduling(stats);
    stdout.writeln('指令时刻↔原生播放头：$stats → ${verdict.name}');
  } else {
    stdout.writeln('指令时刻↔原生播放头：未提供 --trace（跳过排程判定）');
  }

  final ok = report.beat.matchedCount >= 4 && report.music.matchedCount >= 4;
  stdout.writeln(ok
      ? 'GREEN: 拍声/音乐读数齐备（配对 ≥4 拍），读数可留档'
      : 'RED: 配对不足（拍声 ${report.beat.matchedCount}/音乐 '
          '${report.music.matchedCount}，各需 ≥4）——检查回录起止对齐与'
          ' --bpm/--beats/--start-offset-ms');
  exit(ok ? 0 : 1);
}
