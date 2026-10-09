import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/beat_point.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/player/cast_beat_clicks.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 拍声排程派生直测（纯件）：哪一拍、在哪个时刻、放哪一段、多大音量——投屏
/// 副本里的拍声与手机本地播放同一份口径。
void main() {
  /// 「普通」音源：小节首重音、其余整拍、半拍各一段。
  final normal = metronomeSourceEntryOfId(kNormalSourceId);

  /// 按槽位给一个可辨认的音量（顺序即槽位序）。
  double volumeOf(MetronomeSegmentSlot slot) =>
      (MetronomeSegmentSlot.values.indexOf(slot) + 1) / 16;

  List<CastBeatClick> clicks({
    BeatGrid? grid,
    MetronomeSourceEntry? source,
    Duration duration = const Duration(seconds: 3),
    List<Duration> halfBeatLines = const [],
    bool halfBeatEnabled = false,
  }) => buildCastBeatClicks(
    grid: grid ?? const UniformBeatGrid(bpm: 120),
    source: source ?? normal,
    duration: duration,
    volumeOf: volumeOf,
    halfBeatLines: halfBeatLines,
    halfBeatEnabled: halfBeatEnabled,
  );

  test('整拍逐拍落点：占位网格 120bpm、3 秒 = 6 拍', () {
    final result = clicks();

    expect(result.map((c) => c.time.inMilliseconds).toList(), [
      0,
      500,
      1000,
      1500,
      2000,
      2500,
    ]);
  });

  test('段资产按拍号选：小节首用重音段、其余整拍段', () {
    final assets = clicks().map((c) => c.asset).toList();

    expect(assets, [
      'assets/sounds/metronome_strong.wav',
      'assets/sounds/metronome_beat.wav',
      'assets/sounds/metronome_beat.wav',
      'assets/sounds/metronome_beat.wav',
      'assets/sounds/metronome_strong.wav',
      'assets/sounds/metronome_beat.wav',
    ]);
  });

  test('音量按槽位口径原样带上', () {
    final volumes = clicks().map((c) => c.volume).toList();

    expect(volumes, [0.0625, 0.125, 0.1875, 0.25, 0.0625, 0.125]);
  });

  test('超出素材时长的拍点不进排程（副本不会有片尾多出来的拍）', () {
    final result = clicks(duration: const Duration(milliseconds: 1200));

    expect(result.map((c) => c.time.inMilliseconds).toList(), [0, 500, 1000]);
  });

  test('真实网格有界：到末拍为止，不外推出虚假格点', () {
    final grid = DocumentBeatGrid(
      beats: const [
        BeatPoint(t: 0.2, down: true),
        BeatPoint(t: 0.7, down: false),
        BeatPoint(t: 1.2, down: false),
      ],
    );

    final result = clicks(grid: grid, duration: const Duration(seconds: 10));

    expect(result.map((c) => c.time.inMilliseconds).toList(), [200, 700, 1200]);
    expect(result.first.asset, 'assets/sounds/metronome_strong.wav');
  });

  test('半拍：开关开且有线才排，落在半拍格点、用半拍段', () {
    final result = clicks(
      halfBeatLines: const [Duration(milliseconds: 250)],
      halfBeatEnabled: true,
    );

    final half = result.singleWhere(
      (c) => c.asset == 'assets/sounds/metronome_half.wav',
    );
    expect(half.time, const Duration(milliseconds: 250));
    expect(half.volume, 0.5625);
    expect(result.map((c) => c.time.inMilliseconds).toList(), [
      0,
      250,
      500,
      1000,
      1500,
      2000,
      2500,
    ]);
  });

  test('半拍开关关：线在场也不排（与手机本地发声同一开关）', () {
    final result = clicks(
      halfBeatLines: const [Duration(milliseconds: 250)],
      halfBeatEnabled: false,
    );

    expect(result.any((c) => c.asset.contains('half')), isFalse);
  });

  test('半拍线与整拍重合：只留整拍那一声', () {
    final result = clicks(
      halfBeatLines: const [Duration(milliseconds: 500)],
      halfBeatEnabled: true,
    );

    expect(
      result.where((c) => c.time == const Duration(milliseconds: 500)).length,
      1,
    );
  });

  test('待支持音源（占位段、无声）：一条排程都不出', () {
    final result = clicks(source: metronomeSourceEntryOfId('vocal'));

    expect(result, isEmpty, reason: '手机本地不发声，电视上也不该多出拍声');
  });

  test('排程按时刻升序（半拍插在整拍之间）', () {
    final times = clicks(
      halfBeatLines: const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 1250),
      ],
      halfBeatEnabled: true,
    ).map((c) => c.time.inMilliseconds).toList();

    expect(times, [0, 250, 500, 1000, 1250, 1500, 2000, 2500]);
  });
}
