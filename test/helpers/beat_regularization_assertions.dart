/// 节拍规整硬不变量的共用断言（规整纯函数单测与管线级断言同源）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:dance_learning_app/core/beat_regularization.dart';

/// 毫秒镜像（识别拍点时刻落在整毫秒栅格上）。
List<int> _ms(List<Duration> times) => [
  for (final t in times) t.inMilliseconds,
];

/// 硬不变量：同长、`∀k |规整 − 识别| ≤ B`、严格递增、段内相邻间隔
/// 残差 ≤1ms；短段（不足一个八拍）整段原样直通。
void expectHardInvariants(
  List<Duration> recognition,
  BeatRegularization result,
) {
  final rec = _ms(recognition);
  final out = _ms(result.times);
  expect(out, hasLength(rec.length), reason: '拍数不变');
  for (var k = 0; k < rec.length; k++) {
    expect(
      (out[k] - rec[k]).abs(),
      lessThanOrEqualTo(phaseBudgetMs),
      reason: '拍 $k 相位偏离越界',
    );
  }
  for (var k = 1; k < out.length; k++) {
    expect(out[k], greaterThan(out[k - 1]), reason: '拍 $k 非严格递增');
  }
  for (final run in result.runs) {
    if (run.isShort) {
      for (var k = run.startIndex; k <= run.endIndex; k++) {
        expect(out[k], rec[k], reason: '短段拍 $k 应原样直通');
      }
      continue;
    }
    final avg =
        (out[run.endIndex] - out[run.startIndex]) /
        (run.endIndex - run.startIndex);
    for (var k = run.startIndex; k < run.endIndex; k++) {
      expect(
        ((out[k + 1] - out[k]) - avg).abs(),
        lessThanOrEqualTo(1.0),
        reason: '段 [${run.startIndex}..${run.endIndex}] 拍 $k 间隔残差',
      );
    }
  }
}
