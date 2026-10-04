import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 录制准备前导计算：
/// 起点前 **N 拍回退**（拍数独立设置、默认 8），回退按**派生网格的真实拍点**
/// ——起录点前可用的真实拍点少于设定拍数时**有几拍数几拍**（缩短，不整块
/// 静默）；**秒制兜底网格**（异常态）才走秒制兜底（≈4s、无节拍、无数字）。
/// 回退在有效区间内截断。纯函数收**非空网格**：「无网格」不用空值编码。
///
/// 纯件 seam：不启 Flutter、不读 provider，直接断言计划值。
void main() {
  /// 真实网格替身：拍点每 [stepMs] 一个、每 4 拍一个强拍（4/4）。
  BeatGrid gridOf({required int count, int stepMs = 500, int startMs = 0}) =>
      documentGridOf(
        marker_doc.BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 14),
          beats: [
            for (var i = 0; i < count; i++)
              marker_doc.BeatPoint(
                t: (startMs + i * stepMs) / 1000,
                down: i % 4 == 0,
              ),
          ],
        ),
      );

  group('录制准备前导计算', () {
    test('网格就绪且起录点前拍点足够：按 N 拍回退（回退点即第 N 个真实拍点）', () {
      final prep = computeRecordingPrep(
        startPointMs: 30000,
        rangeStartMs: 0,
        prepBeats: 8,
        grid: gridOf(count: 100),
      );
      expect(prep.leadStartMs, 26000, reason: '起录点前第 8 拍 = 26.0s');
      expect(prep.leadDurationMs, 4000);
      expect(prep.beatLed, isTrue);
      expect(prep.beatTimesMs, [for (var i = 0; i < 8; i++) 26000 + i * 500]);
    });

    test('起录点前可用真实拍点少于设定拍数：有几拍数几拍（缩短、仍节拍前导）', () {
      // 网格自 9.0s 起：起录点 10.5s 前只有 9.0/9.5/10.0 三个真实拍点。
      final prep = computeRecordingPrep(
        startPointMs: 10500,
        rangeStartMs: 0,
        prepBeats: 8,
        grid: gridOf(count: 40, startMs: 9000),
      );
      expect(prep.beatLed, isTrue, reason: '「有网格但不足」不是异常网格——不得退化成整块静默');
      expect(prep.beatTimesMs, [9000, 9500, 10000]);
      expect(prep.leadStartMs, 9000);
      expect(prep.leadDurationMs, 1500);
    });

    test('变拍长网格：回退的是 N 个真实拍点，不按名义拍长折算', () {
      // 拍长先密后疏（500ms → 1000ms）：起录点 10s 前的 4 拍自 7.0s 起。
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 14),
          beats: [
            for (var i = 0; i < 8; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
            for (var i = 0; i < 12; i++)
              marker_doc.BeatPoint(
                t: (5 + i).toDouble(),
                down: (i + 1) % 4 == 0,
              ),
          ],
        ),
      );
      final prep = computeRecordingPrep(
        startPointMs: 10000,
        rangeStartMs: 0,
        prepBeats: 4,
        grid: grid,
      );
      expect(prep.beatTimesMs, [
        6000,
        7000,
        8000,
        9000,
      ], reason: '名义拍长（500ms）会算出 8.5s 起，真实拍点回退应落到 6.0s');
      expect(prep.leadStartMs, 6000);
    });

    test('起录点前连一个真实拍点都没有：无前导（无数字、无声、到点即起录）', () {
      final prep = computeRecordingPrep(
        startPointMs: 5000,
        rangeStartMs: 0,
        prepBeats: 8,
        grid: gridOf(count: 20, startMs: 9000),
      );
      expect(prep.beatLed, isFalse, reason: '一个拍点都数不出来 → 不假装有节拍前导');
      expect(prep.beatTimesMs, isEmpty);
      expect(prep.leadDurationMs, 0, reason: '「有网格但没有可数的拍」不落秒制兜底的整块静默：到点即起录');
      expect(prep.leadStartMs, 5000);
    });

    test('准备拍数为 0：无前导（与「循环前导：不前导」同语义）', () {
      final prep = computeRecordingPrep(
        startPointMs: 30000,
        rangeStartMs: 0,
        prepBeats: 0,
        grid: gridOf(count: 100),
      );
      expect(prep.beatLed, isFalse);
      expect(prep.leadDurationMs, 0);
      expect(prep.leadStartMs, 30000);
    });

    test('网格首拍晚于起录点：无可用拍点 → 无前导（不借占位/秒制充数）', () {
      final prep = computeRecordingPrep(
        startPointMs: 9000,
        rangeStartMs: 0,
        prepBeats: 8,
        grid: gridOf(count: 20, startMs: 9500),
      );
      expect(prep.beatTimesMs, isEmpty);
      expect(prep.beatLed, isFalse);
      expect(prep.leadDurationMs, 0);
    });

    test('可用拍点受有效区间头截断（区间头之前的拍点不进准备拍序列）', () {
      final prep = computeRecordingPrep(
        startPointMs: 12000,
        rangeStartMs: 10000,
        prepBeats: 8,
        grid: gridOf(count: 100),
      );
      expect(prep.leadStartMs, 10000, reason: '区间头是回退的硬下界');
      expect(prep.beatTimesMs, [10000, 10500, 11000, 11500]);
      expect(prep.beatLed, isTrue);
    });

    test('秒制兜底网格（异常态，非空网格）：兜底 ≈4s、无节拍前导、无拍点', () {
      final prep = computeRecordingPrep(
        startPointMs: 30000,
        rangeStartMs: 0,
        prepBeats: 8,
        grid: const UnavailableBeatGrid(),
      );
      expect(prep.beatLed, isFalse);
      expect(prep.beatTimesMs, isEmpty);
      expect(prep.leadDurationMs, 4000);
      expect(prep.leadStartMs, 26000);
    });

    test('异常态兜底与占位同档位不等：占位 8 拍按真实拍距、异常固定兜底（判据上移后仍可分辨）', () {
      final prep = computeRecordingPrep(
        startPointMs: 30000,
        rangeStartMs: 0,
        prepBeats: 8,
        grid: placeholderBeatGrid,
      );
      expect(prep.beatLed, isTrue, reason: '占位是均匀节奏来源，照常给准备拍');
      expect(prep.leadDurationMs, 4000, reason: '占位 120bpm 八拍 = 4s（真实拍点路径）');
      expect(prep.beatTimesMs, [for (var i = 0; i < 8; i++) 26000 + i * 500]);
    });

    test('秒制兜底网格且区间头距起点 1.5s：兜底回退截断到 1.5s', () {
      final prep = computeRecordingPrep(
        startPointMs: 30000,
        rangeStartMs: 28500,
        prepBeats: 8,
        grid: const UnavailableBeatGrid(),
      );
      expect(prep.leadDurationMs, 1500);
      expect(prep.leadStartMs, 28500);
    });

    test('起点即区间头：无前导、到点即起录', () {
      final prep = computeRecordingPrep(
        startPointMs: 10000,
        rangeStartMs: 10000,
        prepBeats: 8,
        grid: gridOf(count: 100),
      );
      expect(prep.leadStartMs, 10000);
      expect(prep.leadDurationMs, 0);
      expect(prep.beatTimesMs, isEmpty);
    });
  });
}
