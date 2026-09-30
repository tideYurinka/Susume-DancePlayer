import 'package:dance_learning_app/core/beat_grid.dart' as grid_seam;
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 真实网格文档（4 拍：0.5s 起，每 0.5s 一拍，第 1 拍 downbeat）。
MarkersDocument docWithBeats() => MarkersDocument(
  beat: BeatGrid(
    model: 'madmom_downbeat_rnn_full.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2026, 9, 6),
    beats: [
      BeatPoint(t: 0.5, down: true),
      BeatPoint(t: 1.0, down: false),
      BeatPoint(t: 1.5, down: false),
      BeatPoint(t: 2.0, down: false),
    ],
  ),
);

void main() {
  group('DocumentBeatGrid（markers beat 段的真实网格 seam 实现）', () {
    test('拍时刻/downbeat/小节结构按文档拍序列', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(grid.beatsPerBar, 4);
      expect(grid.beatTime(0), const Duration(milliseconds: 500));
      expect(grid.beatTime(3), const Duration(seconds: 2));
      expect(grid.isDownbeat(0), isTrue);
      expect(grid.isDownbeat(1), isFalse);
    });

    test('定位换算：时间↔拍序号（早于首拍为 -1）', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(grid.beatIndexAt(const Duration(milliseconds: 499)), -1);
      expect(grid.beatIndexAt(const Duration(milliseconds: 500)), 0);
      expect(grid.beatIndexAt(const Duration(milliseconds: 999)), 0);
      expect(grid.beatIndexAt(const Duration(seconds: 30)), 3);
    });

    test('任意 N 拍时长 = 相邻拍间距累加', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(grid.beatsDuration(2), const Duration(seconds: 1));
      expect(grid.beatsDuration(4), const Duration(seconds: 2));
      expect(grid.beatsDuration(2, from: 1), const Duration(seconds: 1));
    });

    test('开窗取拍：闭窗内拍时刻升序', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(
        grid.beatsInWindow(
          const Duration(milliseconds: 900),
          const Duration(seconds: 2),
        ),
        [
          const Duration(seconds: 1),
          const Duration(milliseconds: 1500),
          const Duration(seconds: 2),
        ],
      );
      // 早于首拍的开窗仍取到窗内全部拍。
      expect(
        grid.beatsInWindow(Duration.zero, const Duration(milliseconds: 600)),
        [const Duration(milliseconds: 500)],
      );
    });

    test('边界：负拍序号抛 RangeError；末拍之后按末段间距线性外推', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(() => grid.beatTime(-1), throwsRangeError);
      expect(() => grid.beatTime(4), throwsRangeError);
      expect(() => grid.isDownbeat(4), throwsRangeError);
      // 拍等待发生在视频尾部：越过末拍的 N 拍时长按末段拍间距外推。
      expect(grid.beatsDuration(1, from: 4), const Duration(milliseconds: 500));
      expect(grid.beatsDuration(8, from: 0), const Duration(seconds: 4));
    });

    test('首个强拍序号与末拍：非弱起 = 0、末拍 = 拍数 − 1；弱起取首个 downbeat', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(grid.firstDownbeatIndex, 0);
      expect(grid.lastBeatIndex, 3);
      final pickup = documentGridOf(
        MarkersDocument(
          beat: BeatGrid(
            model: 'm',
            fps: 100,
            generatedAt: DateTime.utc(2026, 9, 6),
            beats: [
              BeatPoint(t: 0.5, down: false),
              BeatPoint(t: 1.0, down: false),
              BeatPoint(t: 1.5, down: true),
              BeatPoint(t: 2.0, down: false),
            ],
          ),
        ).beat!,
      );
      expect(pickup.firstDownbeatIndex, 2);
    });

    test('空拍序列构造抛 ArgumentError（无拍点视为分析失败，不入网格）', () {
      expect(
        () => documentGridOf(
          MarkersDocument(
            beat: BeatGrid(
              model: 'm',
              fps: 100,
              generatedAt: DateTime.utc(2026, 9, 6),
            ),
          ).beat!,
        ),
        throwsArgumentError,
      );
    });
  });

  group('平移量派生（节拍对齐，派生时刻 = 原拍点 + 平移量）', () {
    test('0 平移恒等：派生网格与原拍点一致', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(grid.beatTime(0), const Duration(milliseconds: 500));
      expect(grid.beatsInWindow(Duration.zero, const Duration(seconds: 3)), [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1),
        const Duration(milliseconds: 1500),
        const Duration(seconds: 2),
      ]);
    });

    test('正平移：全消费原语（beatTime/beatIndexAt/开窗/N 拍时长）读平移后网格', () {
      final grid = documentGridOf(docWithBeats().beat!.withShift(0.25));
      expect(grid.beatTime(0), const Duration(milliseconds: 750));
      expect(grid.beatTime(3), const Duration(milliseconds: 2250));
      expect(grid.beatIndexAt(const Duration(milliseconds: 749)), -1);
      expect(grid.beatIndexAt(const Duration(milliseconds: 750)), 0);
      expect(grid.beatsDuration(2), const Duration(seconds: 1));
      expect(
        grid.beatsInWindow(
          const Duration(seconds: 1),
          const Duration(seconds: 2),
        ),
        [
          const Duration(milliseconds: 1250),
          const Duration(milliseconds: 1750),
        ],
      );
    });

    test('负平移：拍点整体前移，downbeat 结构不变', () {
      final doc = docWithBeats().beat!;
      final grid = documentGridOf(doc.withShift(-0.25));
      expect(grid.beatTime(0), const Duration(milliseconds: 250));
      expect(grid.isDownbeat(0), isTrue);
      expect(grid.isDownbeat(1), isFalse);
      expect(grid.firstDownbeatIndex, 0);
      expect(grid.lastBeatIndex, 3);
    });

    test('派生时刻不钳 0..total：负平移越出 0 的拍仍是合法格点（语义固化）', () {
      final grid = documentGridOf(docWithBeats().beat!.withShift(-0.75));
      // 首拍 0.5s − 0.75s = −0.25s：时刻为负仍可读，序号定位按平移后序列。
      expect(grid.beatTime(0), const Duration(milliseconds: -250));
      expect(grid.beatIndexAt(const Duration(milliseconds: -250)), 0);
      expect(grid.beatTime(3), const Duration(milliseconds: 1250));
    });

    test('非破坏：平移不改动文档原始拍点，原网格可恢复', () {
      final doc = docWithBeats().beat!;
      final original = List.of(doc.beats);
      documentGridOf(doc.withShift(0.25));
      expect(doc.beats, original);
      expect(doc.shift, 0);
      expect(
        documentGridOf(doc).beatTime(0),
        const Duration(milliseconds: 500),
      );
    });
  });

  group('UnavailableBeatGrid（异常态秒制兜底网格）', () {
    const grid = grid_seam.UnavailableBeatGrid();

    test('每拍 0.5s：固定「一个八拍」等待 = 4s', () {
      expect(grid.beatTime(1), const Duration(milliseconds: 500));
      expect(grid.beatsDuration(8), const Duration(seconds: 4));
      expect(grid.beatsDuration(1), const Duration(milliseconds: 500));
    });

    test('首个强拍序号 = 0、无界（末拍为 null）', () {
      expect(grid.firstDownbeatIndex, 0);
      expect(grid.lastBeatIndex, isNull);
    });

    test('均匀 4/4 结构与开窗', () {
      expect(grid.beatsPerBar, 4);
      expect(grid.isDownbeat(0), isTrue);
      expect(grid.isDownbeat(3), isFalse);
      expect(grid.beatIndexAt(const Duration(milliseconds: 900)), 1);
      expect(
        grid.beatsInWindow(
          const Duration(milliseconds: 600),
          const Duration(milliseconds: 1400),
        ),
        [const Duration(seconds: 1)],
      );
    });
  });

  group('网格性质与派生读面（Seam A）', () {
    test('真实网格：nature 就绪、性质为真实 ⟺ 末拍序号非空、基准按真实拍距', () {
      final grid = documentGridOf(docWithBeats().beat!);
      expect(grid.nature, grid_seam.BeatGridNature.ready);
      expect(grid.hasRealBeats, isTrue);
      expect(grid.lastBeatIndex, isNotNull); // 不变式「真实 ⟺ 末拍非空」
      expect(grid.isSecondsFallback, isFalse);
      expect(grid.hasStrongBeats, isTrue);
      expect(grid.nominalBeat, const Duration(milliseconds: 500));
      expect(grid.eightBeatNominal, const Duration(seconds: 4));
      expect(grid.leadTier(2), const Duration(seconds: 1));
    });

    test('秒制兜底网格：nature 异常、基准走哨兵算术、前导档位即秒', () {
      const grid = grid_seam.UnavailableBeatGrid();
      expect(grid.nature, grid_seam.BeatGridNature.secondsFallback);
      expect(grid.hasRealBeats, isFalse);
      expect(grid.isSecondsFallback, isTrue);
      expect(grid.hasStrongBeats, isTrue);
      expect(grid.nominalBeat, grid_seam.sentinelBeat);
      expect(grid.eightBeatNominal, grid_seam.secondsFallbackEightBeat);
      expect(grid.leadTier(0), Duration.zero);
      expect(grid.leadTier(4), const Duration(seconds: 4));
      expect(grid.leadTier(8), const Duration(seconds: 8));
    });
  });
}
