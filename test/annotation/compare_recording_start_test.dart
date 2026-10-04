/// 无激活段起录点与拒录判定的纯域直测：起点 = 当前相位下最近的八拍点（可能
/// 落在按下位置之前半个八拍内；相位不可用 = 按下位置原样）、早于有效区间头时
/// 钳到区间头；拒录判定随起录点——距有效区间尾不足一拍或已在尾线之后 → 拒录。
/// 零框架依赖、不启动 widget 环境。
library;

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/core/beat_grid.dart' show BeatGrid;
import 'package:dance_learning_app/core/eight_beat_phase.dart' show BeatPhase;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 真实网格替身：拍点每 500ms 一个、每 4 拍一个强拍（4/4）——八拍点每
/// 4000ms 一个（0、4、8…s）。
BeatGrid _gridOf({required int count}) => documentGridOf(
  marker_doc.BeatGrid(
    model: 'madmom_downbeat_rnn_full.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2026, 9, 16),
    beats: [
      for (var i = 0; i < count; i++)
        marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
    ],
  ),
);

RecordingStartDecision _decide({
  required int pressPositionMs,
  int rangeStartMs = 0,
  int rangeEndMs = 30000,
  int minTailMs = 500,
  BeatPhase? phase,
}) => computeRecordingStart(
  pressPositionMs: pressPositionMs,
  rangeStartMs: rangeStartMs,
  rangeEndMs: rangeEndMs,
  minTailMs: minTailMs,
  phase: phase,
);

void main() {
  group('无激活段起录点与拒录判定', () {
    test('边界表：首线之前 / 区间头 / 区间中段 → 可录，起点按口径取值', () {
      // 早于有效区间头：起点钳到区间头。
      expect(
        _decide(pressPositionMs: 8000, rangeStartMs: 10000).startPointMs,
        10000,
      );
      expect(
        _decide(pressPositionMs: 8000, rangeStartMs: 10000).recordable,
        isTrue,
      );
      // 恰在区间头。
      expect(
        _decide(pressPositionMs: 10000, rangeStartMs: 10000).startPointMs,
        10000,
      );
      // 区间中段：起点 = 按下位置原样。
      expect(_decide(pressPositionMs: 15000).startPointMs, 15000);
      expect(_decide(pressPositionMs: 15000).recordable, isTrue);
    });

    test('相位不可用：非八拍点位置原样返回（不吸附）', () {
      // 15333 既不是拍点（500ms 网格）也不是八拍点（4000ms 网格）。
      final decision = _decide(pressPositionMs: 15333);
      expect(decision.startPointMs, 15333);
      expect(decision.startPointMs % 500, isNot(0));
      expect(decision.startPointMs % 4000, isNot(0));
    });

    test('距尾线不足一拍 → 拒录（起点仍原样给出，拒录不改成吸附终点）', () {
      // 尾线 30s、一拍 500ms：29.7s 按下只剩 300ms。
      final decision = _decide(pressPositionMs: 29700);
      expect(decision.recordable, isFalse);
      expect(decision.startPointMs, 29700);
    });

    test('恰在尾线 / 尾线之后 → 拒录', () {
      expect(_decide(pressPositionMs: 30000).recordable, isFalse);
      expect(_decide(pressPositionMs: 30000).startPointMs, 30000);
      expect(_decide(pressPositionMs: 30500).recordable, isFalse);
      expect(_decide(pressPositionMs: 30500).startPointMs, 30500);
    });

    test('距尾线恰好一拍 → 可录（判据是「不足一拍」，不是「不足或等于」）', () {
      final decision = _decide(pressPositionMs: 29500);
      expect(decision.recordable, isTrue);
      expect(decision.startPointMs, 29500);
    });

    test('阈值是一拍的入参、不写死在会话里：换成两拍即按两拍判', () {
      expect(
        _decide(pressPositionMs: 29500, minTailMs: 1000).recordable,
        isFalse,
        reason: '距尾 500ms < 传入阈值 1000ms',
      );
      expect(
        _decide(pressPositionMs: 29000, minTailMs: 1000).recordable,
        isTrue,
      );
      // 阈值为 0：只有「已在尾线或之后」才拒（钳 0 的退化入参）。
      expect(_decide(pressPositionMs: 29999, minTailMs: 0).recordable, isTrue);
      expect(_decide(pressPositionMs: 30000, minTailMs: 0).recordable, isFalse);
    });

    test('尾线读不到（0 = 未知）：不拒录，终点交物理尾兜底', () {
      expect(
        _decide(pressPositionMs: 5000, rangeEndMs: 0).recordable,
        isTrue,
        reason: '尾线读不到时按物理尾收尾，不在这里误拒',
      );
    });

    test('早于区间头且区间头贴尾：钳到区间头后按区间头判拒录', () {
      final decision = _decide(
        pressPositionMs: 8000,
        rangeStartMs: 29900,
        rangeEndMs: 30000,
      );
      expect(decision.startPointMs, 29900);
      expect(decision.recordable, isFalse);
    });
  });

  group('起录点吸附八拍点（复用相位最近八拍点解析）', () {
    final phase = BeatPhase(grid: _gridOf(count: 100));

    test('按下位置吸附到当前相位下最近的八拍点（就近，可前可后）', () {
      // 15333 距 16s（667ms）近于 12s → 起点 = 16s。
      expect(_decide(pressPositionMs: 15333, phase: phase).startPointMs, 16000);
      // 12600 距 12s（600ms）近于 16s → 起点 = 12s（落在按下位置之前）。
      expect(_decide(pressPositionMs: 12600, phase: phase).startPointMs, 12000);
    });

    test('等距并列取靠后者（与相位解析同一口径）', () {
      // 14000 与 12s / 16s 等距 → 取 16s。
      expect(_decide(pressPositionMs: 14000, phase: phase).startPointMs, 16000);
    });

    test('相位不可用（null）：按下位置原样，不吸附', () {
      expect(_decide(pressPositionMs: 15333).startPointMs, 15333);
      expect(_decide(pressPositionMs: 15333).recordable, isTrue);
    });

    test('吸附点早于有效区间头：钳到区间头', () {
      // 8100 吸附到 8s，早于区间头 10s → 钳到 10s。
      final decision = _decide(
        pressPositionMs: 8100,
        rangeStartMs: 10000,
        phase: phase,
      );
      expect(decision.startPointMs, 10000);
      expect(decision.recordable, isTrue);
    });

    test('拒录判定随新起录点：吸附提前让原会被拒的按下变成可录', () {
      // 29800 原样判 = 距尾 200ms < 一拍（拒）；吸附到 28s 后距尾 2s → 可录。
      final decision = _decide(pressPositionMs: 29800, phase: phase);
      expect(decision.startPointMs, 28000);
      expect(decision.recordable, isTrue);
    });

    test('拒录判定随新起录点：吸附推后让原可录的按下变成拒录', () {
      // 27600 原样判 = 距尾 700ms ≥ 一拍（可录）；吸附到 28s 后距尾 300ms → 拒。
      final decision = _decide(
        pressPositionMs: 27600,
        rangeEndMs: 28300,
        phase: phase,
      );
      expect(decision.startPointMs, 28000);
      expect(decision.recordable, isFalse);
    });

    test('恰在八拍点按下：起点即按下位置（吸附恒等）', () {
      expect(_decide(pressPositionMs: 16000, phase: phase).startPointMs, 16000);
    });
  });
}
