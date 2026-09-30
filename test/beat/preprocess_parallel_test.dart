import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/beat/preprocess.dart';

/// 并行前处理与串行参考逐位一致（ANR 修复：分段切片后仍须逐位一致）。
void main() {
  test('preprocessPcmParallel 与 preprocessPcm 逐位一致', () async {
    final rng = Random(42);
    for (final nSamples in [1, 441, 10000, 200001]) {
      final pcm = Float32List(nSamples);
      for (var i = 0; i < nSamples; i++) {
        pcm[i] = rng.nextDouble() * 2 - 1;
      }
      final fbs = _fakeFbs();
      final ref = preprocessPcm(pcm, fbs);
      final out = await preprocessPcmParallel(pcm, fbs);
      expect(out.length, ref.length, reason: 'nSamples=$nSamples');
      for (var i = 0; i < ref.length; i++) {
        final eq = ref[i] == out[i] || (ref[i].isNaN && out[i].isNaN);
        if (!eq) {
          fail('nSamples=$nSamples bit mismatch at $i: '
              '${ref[i]} vs ${out[i]}');
        }
      }
    }
  });
}

List<Filterbank> _fakeFbs() => [
      for (var i = 0; i < kFrameSizes.length; i++)
        Filterbank(
          kFrameSizes[i] ~/ 2,
          kLogDims[i],
          Float32List.fromList(List.generate(
            kFrameSizes[i] ~/ 2 * kLogDims[i],
            (j) => ((j * 37) % 101) / 101 - 0.5,
          )),
        ),
    ];
