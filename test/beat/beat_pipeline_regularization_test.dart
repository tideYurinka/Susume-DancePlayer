import 'package:dance_learning_app/beat/beat_pipeline.dart'
    show regularizeDecodedBeats;
import 'package:dance_learning_app/core/beat_regularization.dart'
    show BeatRegularization, regularizeBeatTimes;
import 'package:dance_learning_app/persistence/marker_document.dart'
    show BeatGrid, BeatPoint, MarkersDocument;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/aquarium_beat_fixture.dart';
import '../helpers/beat_regularization_assertions.dart';

/// 识别拍点（毫秒）→ DBN 解码产物形态（t 秒 + beatNumber）。
List<({double t, int beatNumber})> decoded(List<int> timesMs) => [
  for (final (i, ms) in timesMs.indexed)
    (t: ms / 1000.0, beatNumber: i % 4 == 0 ? 1 : (i % 4) + 1),
];

/// 在管线产物上跑硬不变量：段结构取同一识别序列的规整结果（已逐段钉死），
/// 本测试只断言管线产物满足全部不变量。
void expectPipelineInvariants(List<int> recognitionMs, List<BeatPoint> out) {
  final recognition = [
    for (final ms in recognitionMs) Duration(milliseconds: ms),
  ];
  expectHardInvariants(
    recognition,
    BeatRegularization(
      times: [
        for (final p in out) Duration(milliseconds: (p.t * 1000).round()),
      ],
      runs: regularizeBeatTimes(recognition).runs,
    ),
  );
}

void main() {
  group('分析管线规整（规整在识别之后、拍点落盘之前执行一次）', () {
    test('真机 686 拍：满足全部硬不变量，强拍逐位不变', () {
      final input = decoded(aquariumBeatTimesMs);
      final out = regularizeDecodedBeats(input);

      expectPipelineInvariants(aquariumBeatTimesMs, out);
      for (var k = 0; k < input.length; k++) {
        expect(out[k].down, input[k].beatNumber == 1, reason: '强拍逐位不变');
      }
    });

    test('匀速 + 注入抖动：满足硬不变量，段首尾锚定识别拍点', () {
      final timesMs = [
        for (var i = 0; i < 16; i++) 500 + i * 500 + (i.isEven ? 1 : -1) * 8,
      ];
      final input = decoded(timesMs);
      final out = regularizeDecodedBeats(input);

      expectPipelineInvariants(timesMs, out);
      expect(out.first.t, input.first.t, reason: '段首锚定识别拍点');
      expect(out.last.t, input.last.t, reason: '段尾锚定识别拍点');
      expect(out[1].t, isNot(input[1].t), reason: '抖动被等时化的可观察差异');
    });

    test('真实相位跳变：满足硬不变量，跳变拍原样保留', () {
      final timesMs = [
        for (var i = 0; i < 8; i++) 500 + i * 500,
        for (var i = 8; i < 16; i++) 4620 + (i - 8) * 500,
      ];
      final out = regularizeDecodedBeats(decoded(timesMs));
      final ms = [for (final p in out) (p.t * 1000).round()];

      expectPipelineInvariants(timesMs, out);
      expect(ms.contains(4000), isTrue, reason: '跳变前末拍保留');
      expect(ms.contains(4620), isTrue, reason: '跳变后首拍 = 识别拍点，不被重排抹平');
    });

    test('落盘往返：beat 段 JSON 往返后仍是同一规整网格、满足硬不变量', () {
      final points = regularizeDecodedBeats(decoded(aquariumBeatTimesMs));
      final written = MarkersDocument(
        beat: BeatGrid(
          model: 'assets/models/madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 18),
          beats: points,
        ),
      );

      final restored = MarkersDocument.fromJson(written.toJson());
      final beats = restored.beat!.beats;
      expect(beats, hasLength(points.length));
      for (var k = 0; k < points.length; k++) {
        expect(beats[k], points[k], reason: '拍 $k 落盘往返逐位一致');
      }
      expectPipelineInvariants(aquariumBeatTimesMs, beats);
    });

    test('退化输入：不足两拍与非严格递增整条原样输出、不抛错', () {
      final single = regularizeDecodedBeats(decoded([1500]));
      expect([for (final p in single) (p.t * 1000).round()], [1500]);

      final flat = regularizeDecodedBeats(decoded([1000, 1000, 2000]));
      expect([for (final p in flat) (p.t * 1000).round()], [1000, 1000, 2000]);
      expect([for (final p in flat) p.down], [true, false, false]);
    });
  });
}
