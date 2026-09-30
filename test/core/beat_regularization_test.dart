import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:dance_learning_app/core/beat_regularization.dart';

import '../helpers/aquarium_beat_fixture.dart';
import '../helpers/beat_fixtures.dart';
import '../helpers/beat_regularization_assertions.dart';

List<Duration> _times(List<int> milliseconds) => [
  for (final ms in milliseconds) Duration(milliseconds: ms),
];

/// 毫秒镜像（识别拍点时刻落在整毫秒栅格上）。
List<int> _ms(List<Duration> times) => [
  for (final t in times) t.inMilliseconds,
];

/// 匀速 + 有界注入抖动（零累计漂移）：每拍 ±10ms 交替，整条相对两端锚定
/// 直线的偏离恒 ≤20ms < 预算，故预算内应尽量长成一段。
List<Duration> boundedJitterTimes(int count, {int baseIntervalMs = 312}) => [
  for (var i = 0; i < count; i++)
    Duration(milliseconds: i * baseIntervalMs + (i.isEven ? 10 : -10)),
];

/// 精确匀速（零抖动）：真实跳变夹具的稳态基座。
List<Duration> exactUniformTimes(int count, {int intervalMs = 312}) => [
  for (var i = 0; i < count; i++) Duration(milliseconds: i * intervalMs),
];

void main() {
  group('regularizeBeatTimes 硬不变量', () {
    test('匀速 + 注入抖动：预算内尽量长成一段、段内逐拍等时', () {
      final recognition = boundedJitterTimes(400);
      final result = regularizeBeatTimes(recognition);

      expect(result.runs, [
        const RegularizationRun(startIndex: 0, endIndex: 399),
      ]);
      expectHardInvariants(recognition, result);
      final out = _ms(result.times);
      for (var k = 1; k < out.length; k++) {
        expect((out[k] - out[k - 1] - 312).abs(), lessThanOrEqualTo(1));
      }
    });

    test('真实跳变（吞拍 + 整体后移）：跳变处断段、两侧各自等时、跳变不重排', () {
      final recognition = jumpTimes(exactUniformTimes(400));
      final result = regularizeBeatTimes(recognition);
      final rec = _ms(recognition);
      final out = _ms(result.times);

      // 吞拍与整体后移处都断段（两个异常各产生一个边界拍）。
      expect(result.runs.any((r) => r.endIndex == 99), isTrue);
      expect(result.runs.any((r) => r.startIndex == 100), isTrue);
      expect(result.runs.any((r) => r.endIndex == 338), isTrue);
      expect(result.runs.any((r) => r.startIndex == 339), isTrue);
      // 边界拍恒为识别拍点原样 ⇒ 跨段相位连续、跳变不被重排。
      expect(out[99], rec[99]);
      expect(out[100], rec[100]);
      expect(out[99] - out[98], rec[99] - rec[98]);
      expect(out[100] - out[99], rec[100] - rec[99]);
      expect(out[338], rec[338]);
      expect(out[339], rec[339]);
      expect(out[339] - out[338], rec[339] - rec[338]);
      expectHardInvariants(recognition, result);
    });

    test('慢漂移（±0.3ms/拍）：按预算多次重锚、误差不越界', () {
      // 拍距绕 312ms 缓慢起伏 ±0.3ms（周期 400 拍）：相对整条两端锚定直线
      // 的偏离会累积到远超预算，故必须多次重锚、误差始终不越界。
      final recognition = <Duration>[];
      var t = 0.0;
      for (var i = 0; i < 1200; i++) {
        recognition.add(Duration(milliseconds: t.round()));
        t += 312 + 0.6 * math.sin(2 * math.pi * i / 400);
      }
      final result = regularizeBeatTimes(recognition);

      expect(result.runs.length, greaterThan(1), reason: '慢漂移必须多次重锚');
      expectHardInvariants(recognition, result);
    });

    test('短促变速：不足一个八拍的段原样直通、不被硬性等时化', () {
      final recognition = [
        for (var i = 0; i < 300; i++) Duration(milliseconds: i * 312),
      ];
      // 拍 200–205 短促提速（拍距 270ms，持续 6 拍）后恢复。
      final rubato = <Duration>[...recognition.sublist(0, 201)];
      var t = recognition[200].inMilliseconds;
      for (var i = 201; i <= 205; i++) {
        t += 270;
        rubato.add(Duration(milliseconds: t));
      }
      rubato.addAll([
        for (final time in recognition.sublist(206))
          time + Duration(milliseconds: t - recognition[205].inMilliseconds),
      ]);
      final result = regularizeBeatTimes(rubato);

      expectHardInvariants(rubato, result);
      // 变速中段所在段是短段（直通），故其时刻原样保留。
      final out = _ms(result.times);
      final rec = _ms(rubato);
      final containing = result.runs.firstWhere(
        (r) => r.startIndex <= 203 && 203 <= r.endIndex,
      );
      expect(containing.isShort, isTrue, reason: '短促变速应落在短段内直通');
      expect(out[203], rec[203]);
    });

    test('退化输入整条原样返回，不抛错、不阻断', () {
      for (final recognition in <List<Duration>>[
        const <Duration>[],
        const [Duration(milliseconds: 1000)],
        // 非严格递增：相等与回退各一例。
        const [
          Duration(milliseconds: 0),
          Duration(milliseconds: 500),
          Duration(milliseconds: 500),
        ],
        const [
          Duration(milliseconds: 0),
          Duration(milliseconds: 900),
          Duration(milliseconds: 800),
        ],
      ]) {
        final result = regularizeBeatTimes(recognition);
        expect(_ms(result.times), _ms(recognition));
      }
    });

    test('算法内部异常：整条原样返回，不抛错', () {
      final result = regularizeBeatTimes(const [
        _ThrowingDuration(),
        _ThrowingDuration(),
      ]);
      expect(result.times, hasLength(2));
      expect(result.runs, isEmpty);
    });
  });

  group('真机《恋爱水族馆》686 拍夹具', () {
    test('段数与段结构被钉住（防止参数漂移）', () {
      final result = regularizeBeatTimes(_times(aquariumBeatTimesMs));
      expect(result.times, hasLength(686));
      expect(result.runs.map((r) => (r.startIndex, r.endIndex)), const [
        (0, 9),
        (9, 10),
        (10, 16),
        (16, 19),
        (19, 21),
        (21, 23),
        (23, 26),
        (26, 30),
        (30, 34),
        (34, 57),
        (57, 185),
        (185, 253),
        (253, 312),
        (312, 350),
        (350, 359),
        (359, 448),
        (448, 452),
        (452, 457),
        (457, 482),
        (482, 528),
        (528, 545),
        (545, 581),
        (581, 628),
        (628, 673),
        (673, 680),
        (680, 685),
      ]);
    });

    test('硬不变量：全程相位偏离 ≤25ms', () {
      final recognition = _times(aquariumBeatTimesMs);
      expectHardInvariants(recognition, regularizeBeatTimes(recognition));
    });
  });
}

/// 读 `inMilliseconds` 即抛错的 Duration，用于注入「算法内部异常」。
class _ThrowingDuration extends Duration {
  const _ThrowingDuration() : super(milliseconds: 0);

  @override
  int get inMilliseconds => throw StateError('注入的内部异常');
}
