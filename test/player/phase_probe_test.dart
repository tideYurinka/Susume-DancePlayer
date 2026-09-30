import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/phase_probe.dart';

const int sr = 22050;

/// 在 [atMs] 处叠加一段短促指数衰减正弦（合成回录信号的最小单元）。
void addBurst(
  Float32List samples,
  int sampleRate, {
  required double atMs,
  required double hz,
  double amp = 0.8,
  double pulseMs = 40,
}) {
  final n = (pulseMs * sampleRate / 1000).round();
  final onset = (atMs * sampleRate / 1000).round();
  for (var j = 0; j < n && onset + j < samples.length; j++) {
    final env = math.pow(math.e, -4.0 * j / n).toDouble();
    samples[onset + j] += amp * env * math.sin(2 * math.pi * hz * j / sampleRate);
  }
}

/// 等拍网格拍点（毫秒）：`60000/bpm` 算术均匀，与夹具口径一致。
List<double> gridMs({required int bpm, required int beats, double offsetMs = 0}) =>
    List.generate(beats, (i) => offsetMs + i * 60000 / bpm);

Float32List synthRecording({
  required double beatLatencyMs,
  required double musicLatencyMs,
}) {
  final totalMs = 4000.0;
  final samples = Float32List((totalMs * sr / 1000).round());
  for (final g in gridMs(bpm: 120, beats: 8)) {
    // 节拍声：整拍段主频 880Hz；音乐内容：夹具整拍敲击 1500Hz（探针音乐频段）。
    addBurst(samples, sr, atMs: g + beatLatencyMs, hz: 880);
    addBurst(samples, sr, atMs: g + musicLatencyMs, hz: 1500, amp: 0.6);
  }
  return samples;
}

void main() {
  group('detectOnsets（频段起音检测）', () {
    test('已知起音的合成信号 → 起音毫秒逐个落在真值 ±5ms', () {
      final samples = Float32List((4.0 * sr).round());
      for (final g in gridMs(bpm: 120, beats: 8)) {
        addBurst(samples, sr, atMs: g, hz: 880);
      }
      final onsets = detectBandOnsets(
        samples,
        sr,
        const BandOnsetConfig(centerHz: 880, minGapMs: 150),
      ).map((o) => o.ms).toList();
      expect(onsets, hasLength(8));
      for (var i = 0; i < 8; i++) {
        expect((onsets[i] - gridMs(bpm: 120, beats: 8)[i]).abs(), lessThan(5));
      }
    });

    test('频段可分：混合录音里各起音归属包络占优的频段', () {
      final musicOnly = Float32List((4.0 * sr).round());
      for (final g in gridMs(bpm: 120, beats: 8)) {
        addBurst(musicOnly, sr, atMs: g, hz: 1500, amp: 0.6);
      }
      final separatedMusicOnly = detectSeparatedOnsets(musicOnly, sr,
          beatHz: 880, musicHz: 1500, minGapMs: 250);
      expect(separatedMusicOnly.beat, isEmpty);
      expect(separatedMusicOnly.music, hasLength(8));
      final both = synthRecording(beatLatencyMs: 37, musicLatencyMs: 0);
      final separated = detectSeparatedOnsets(both, sr,
          beatHz: 880, musicHz: 1500, minGapMs: 250);
      expect(separated.beat, hasLength(8));
      expect(separated.music, hasLength(8));
      expect(separated.beat.first, closeTo(37, 5));
      expect(separated.music.first, closeTo(0, 5));
    });
  });

  group('phaseReport（相位差读数）', () {
    test('固定延迟 37ms → 中位数 37ms、最大偏差 ~0', () {
      final expected = gridMs(bpm: 120, beats: 8);
      final report = phaseReport(
        expectedMs: expected,
        onsets: expected.map((g) => g + 37).toList(),
      );
      expect(report.matchedCount, 8);
      expect(report.medianMs, closeTo(37, 0.001));
      expect(report.maxDeviationMs, lessThan(0.001));
    });

    test('单拍抖动 → 最大偏差量出抖动幅度，中位数不被单拍带跑', () {
      final expected = gridMs(bpm: 120, beats: 8);
      final onsets = expected.map((g) => g + 37.0).toList()..[3] += 15.0;
      final report = phaseReport(expectedMs: expected, onsets: onsets);
      expect(report.medianMs, closeTo(37, 0.001));
      expect(report.maxDeviationMs, closeTo(15, 5));
    });

    test('窗口外起音不配对、漏拍可见', () {
      final expected = gridMs(bpm: 120, beats: 8);
      final onsets = expected.take(6).map((g) => g + 20).toList();
      final report = phaseReport(
        expectedMs: expected,
        onsets: onsets,
        toleranceMs: 80,
      );
      expect(report.matchedCount, 6);
      expect(report.medianMs, closeTo(20, 0.001));
    });
  });

  group('analyzePhaseRecording（一组回录 → 双相位读数）', () {
    test('节拍声 37ms / 音乐 0ms → 各自中位数与相对音乐读数', () {
      final report = analyzePhaseRecording(
        synthRecording(beatLatencyMs: 37, musicLatencyMs: 0),
        sr,
        bpm: 120,
        beats: 8,
      );
      expect(report.beat.matchedCount, 8);
      expect(report.music.matchedCount, 8);
      expect(report.beat.medianMs, closeTo(37, 3));
      expect(report.music.medianMs, closeTo(0, 3));
      expect(report.beatRelativeToMusicMs, closeTo(37, 5));
    });

    test('起点偏移对齐回录时间轴：偏移抵消已知延迟 → 读数归零', () {
      final samples = synthRecording(beatLatencyMs: 37, musicLatencyMs: 0);
      final report = analyzePhaseRecording(
        samples,
        sr,
        bpm: 120,
        beats: 8,
        startOffsetMs: 37,
      );
      expect(report.beat.matchedCount, 8);
      expect(report.beat.medianMs, closeTo(0, 3));
      expect(report.music.medianMs, closeTo(-37, 3));
    });
  });

  group('指令时刻 ↔ 原生播放头 trace', () {
    test('解析 logcat 行 → 指令提前量统计（中位数/最小/最大）', () {
      final stats = parsePhaseProbeTrace(const [
        'I flutter (12345): [beatAudio] phaseProbe cmdMs=500.0 estMs=400.0 leadMs=100.0 kind=light',
        'I flutter (12345): [beatAudio] phaseProbe cmdMs=1000.0 estMs=910.0 leadMs=90.0 kind=accent',
        'I flutter (12345): [beatAudio] phaseProbe cmdMs=1500.0 estMs=1380.0 leadMs=120.0 kind=light',
        'I flutter (12345): [beatAudio] 其它日志不参与',
      ]);
      expect(stats.count, 3);
      expect(stats.medianLeadMs, 100);
      expect(stats.minLeadMs, 90);
      expect(stats.maxLeadMs, 120);
    });

    test('排程判定：提前量在 [0, 前瞻窗] 为正常，越窗或负值报异常', () {
      expect(
        classifyScheduling(const SchedulingTraceStats(
          count: 3,
          medianLeadMs: 100,
          minLeadMs: 90,
          maxLeadMs: 120,
        )),
        SchedulingVerdict.onTime,
      );
      expect(
        classifyScheduling(const SchedulingTraceStats(
          count: 3,
          medianLeadMs: -20,
          minLeadMs: -30,
          maxLeadMs: -10,
        )),
        SchedulingVerdict.behindEstimate,
      );
      expect(
        classifyScheduling(const SchedulingTraceStats(
          count: 3,
          medianLeadMs: 400,
          minLeadMs: 390,
          maxLeadMs: 410,
        )),
        SchedulingVerdict.aheadOfLookahead,
      );
      expect(
        classifyScheduling(const SchedulingTraceStats(
          count: 0,
          medianLeadMs: 0,
          minLeadMs: 0,
          maxLeadMs: 0,
        )),
        SchedulingVerdict.noTrace,
      );
    });
  });
}
