import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/core/playback/media_clock.dart'
    show MediaClockSync;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_audio_log.dart';
import 'package:dance_learning_app/player/beat_audio_native.dart';
import 'package:dance_learning_app/player/beat_schedule.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:dance_learning_app/player/native_scheduled_audio.dart';

import '../helpers/fake_beat_audio_sink.dart';
import '../helpers/fake_playback_engine.dart';

BeatScheduleCommand commandOf(
  int segmentId, {
  Duration at = const Duration(seconds: 1),
  double volume = 0.5,
}) => BeatScheduleCommand(
  beatMediaTime: at,
  segmentId: segmentId,
  volume: volume,
);

void main() {
  // 渲染器注入点经平台通道读设备音频输出流；本套件无 widget 用例，显式初始化绑定。
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 注入的资产装载器（真实 WAV 资产从仓库文件系统读取，不触 rootBundle）。
  Future<ByteData> realAssetLoader(String asset) async {
    final bytes = await File(asset).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  test('排程指令下推原生：段/音量/拍点媒介时间逐条入队', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    await renderer.schedule(
      commandOf(0, at: const Duration(seconds: 2), volume: 0.8),
    );
    await renderer.schedule(commandOf(1));
    await renderer.schedule(commandOf(2, volume: 0.9));

    expect(sink.enqueues, [
      (beatMediaTimeMs: 2000.0, segmentId: 0, volume: 0.8),
      (beatMediaTimeMs: 1000.0, segmentId: 1, volume: 0.5),
      (beatMediaTimeMs: 1000.0, segmentId: 2, volume: 0.9),
    ]);
  });

  // 入队返回值不再被静默丢弃——原生是否接受逐条上报给消费侧。
  test('入队返回值被检查：原生接受报真、未接受报假', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    expect(await renderer.schedule(commandOf(1)), isTrue);

    sink.acceptEnqueue = false;
    expect(
      await renderer.schedule(commandOf(1)),
      isFalse,
      reason: '原生未接受（丢弃/拒绝）时消费侧必须可见，不再静默',
    );
  });

  test('注册表三段（含段内拍点标记）随首次消费惰性加载且只加载一次', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);
    final normal = metronomeSourceEntryOfId(kNormalSourceId);

    await renderer.schedule(commandOf(1));
    await renderer.schedule(commandOf(1));

    // 段表按 id 顺序装载：0 = 重音资产段（号 1/5 槽）、1 = 整拍段
    // （其余整拍槽）、2 = 半拍段。
    expect(sink.loads.map((l) => l.segmentId).toList(), [0, 1, 2]);
    expect(sink.loads.map((l) => l.markerMs), [0, 0, 0]);
    expect(normal.speedGroups.single.slots.first.markerMs, 0);
  });

  test('加载的段 PCM 为真实资产解码（22050Hz 单声道非空）', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    await renderer.schedule(commandOf(1));

    expect(sink.loads.map((l) => l.sampleRate), everyElement(22050));
    expect(sink.loads.map((l) => l.frames), everyElement(greaterThan(0)));
  });

  test('原生容量校验：最坏音源所需段数 ≤ 注册表派生容量；越界段 id 拒绝装载', () async {
    // 容量由注册表派生（Dart 与原生同一份事实源）；全部音源都装得下。
    for (final entry in metronomeSourceRegistry) {
      final sink = FakeBeatAudioSink();
      final renderer = BeatAudioRenderer(
        sink: sink,
        entry: entry,
        loadAsset: realAssetLoader,
      );
      await renderer.schedule(commandOf(1));
      final expected = MetronomeSegmentTable.of(entry).loads
          .where((spec) => spec.asset.isNotEmpty)
          .length;
      expect(sink.loads.length, expected, reason: entry.id);
      expect(
        sink.loads.length,
        lessThanOrEqualTo(sink.segmentCapacity),
        reason: entry.id,
      );
    }

    // 容量不足 = 装载越界被拒（容量不足只会在 CI 失败，不在真机静默）。
    final tight = FakeBeatAudioSink()..segmentCapacity = 2;
    final renderer = BeatAudioRenderer(sink: tight, loadAsset: realAssetLoader);
    await renderer.schedule(commandOf(1));
    expect(tight.loads.length, 2);
  });

  // 渲染器不做任何估计——呈现下推的媒介时刻配对
  // 原样转发原生 sink（配对的另一半 = 原生自己的帧位，原生现取）。
  test('呈现下推的媒介时刻配对原样转发原生 sink', () async {
    final sink = FakeBeatAudioSink()..advanceMonotonicMs(1000);
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    renderer.onMediaNow(
      const MediaClockSync(mediaTimeMs: 5000, rate: 1.0, playing: false),
    );

    expect(sink.syncs.single, (mediaTimeMs: 5000.0, rate: 1.0, playing: false));
  });

  test('倍速与播放态随同一份下推转发；重复同值幂等无害', () async {
    final sink = FakeBeatAudioSink()..advanceMonotonicMs(1000);
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    renderer.onMediaNow(
      const MediaClockSync(mediaTimeMs: 5000, rate: 2.0, playing: true),
    );
    expect(sink.syncs.last.rate, 2.0);
    expect(sink.syncs.last.playing, isTrue);

    renderer.onMediaNow(
      const MediaClockSync(mediaTimeMs: 6000, rate: 2.0, playing: true),
    );
    expect(sink.syncs.last.rate, 2.0);
    expect(sink.syncs.last.mediaTimeMs, 6000.0);
  });

  // 渲染器不外推——「现在」全仓只有呈现那一份外推。
  test('estimatedMediaNow：只回最近下推的配对值，不外推；flush 清为无锚', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    // 起手无锚：0，且不下推、不伪造锚。
    expect(
      renderer.estimatedMediaNow(),
      Duration.zero,
      reason: '无下推即无锚：不把 0 伪造成锚',
    );
    await renderer.rebuildTransport();
    expect(sink.syncs, isEmpty, reason: '无锚时重建流对象也不下推伪造锚');

    renderer.onMediaNow(
      const MediaClockSync(mediaTimeMs: 5000, rate: 1.0, playing: true),
    );
    expect(renderer.estimatedMediaNow(), const Duration(seconds: 5));

    sink.advanceMonotonicMs(1000);
    expect(
      renderer.estimatedMediaNow(),
      const Duration(seconds: 5),
      reason: '渲染器不外推：墙钟前进不改变回答',
    );

    await renderer.flush();
    expect(
      renderer.estimatedMediaNow(),
      Duration.zero,
      reason: 'flush = 显式不连续：清配对，重立由呈现的下一次下推承担',
    );
  });

  test('flush 直接透传 sink（seek/暂停纪律）', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    await renderer.flush();

    expect(sink.flushCount, 1);
  });

  test('sink 不可用（非 Android 宿主）：全接口安全无行为不抛', () async {
    final renderer = BeatAudioRenderer();

    await renderer.schedule(commandOf(1));
    await renderer.flush();
    await renderer.onCalibrationSession(true);
    await renderer.onCalibrationSession(false);
    renderer.onMediaNow(
      const MediaClockSync(mediaTimeMs: 0, rate: 1.0, playing: true),
    );
    renderer.dispose();
  });

  test('dispose 释放原生句柄，后续调用安全无行为', () async {
    final sink = FakeBeatAudioSink();
    final renderer = BeatAudioRenderer(sink: sink, loadAsset: realAssetLoader);

    renderer.dispose();
    await renderer.schedule(commandOf(1));
    await renderer.flush();

    expect(sink.disposed, isTrue);
    expect(sink.enqueues, isEmpty);
    expect(sink.flushCount, 0);
  });

  group('校准会话模式：锚接线；流常开由深模块收口', () {
    test('进入会话：flush 旧锚 + 启用会话时钟源（会话锚 sync）；开流归深模块', () async {
      final sink = FakeBeatAudioSink()..advanceMonotonicMs(1234);
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );

      await renderer.onCalibrationSession(true);

      expect(sink.flushCount, 1);
      expect(sink.syncs.single, (mediaTimeMs: 0.0, rate: 1.0, playing: true));
      expect(sink.startCount, 0, reason: '开流策略在深模块，渲染器只管锚');
    });

    test('会话期间呈现下推不覆写会话时钟锚', () async {
      final sink = FakeBeatAudioSink();
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );
      await renderer.onCalibrationSession(true);

      renderer.onMediaNow(
        const MediaClockSync(mediaTimeMs: 5000, rate: 2.0, playing: true),
      );

      expect(sink.syncs, hasLength(1)); // 只有进入会话的会话锚
    });

    test('退出会话：flush + 清会话锚；停流归深模块', () async {
      final sink = FakeBeatAudioSink();
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );
      await renderer.onCalibrationSession(true);

      await renderer.onCalibrationSession(false);
      expect(sink.flushCount, 2);
      expect(sink.stopCount, 0, reason: '停流策略在深模块');
    });

    test('sink 不可用：会话进出全接口安全无行为不抛', () async {
      final renderer = BeatAudioRenderer();

      await renderer.onCalibrationSession(true);
      await renderer.onCalibrationSession(false);
    });

    test('dispose 后会话进出安全无行为', () async {
      final sink = FakeBeatAudioSink();
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );
      renderer.dispose();

      await renderer.onCalibrationSession(true);

      expect(sink.startCount, 0);
    });
  });

  group('流生命周期 seam：哑操作转发原生 sink', () {
    test('streamLost/openStream/stopStream 逐条转发；开流前段资产就位', () async {
      final sink = FakeBeatAudioSink();
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );

      expect(renderer.streamLost(), isFalse);
      await renderer.openStream();
      expect(sink.startCount, 1);
      expect(sink.loads.map((l) => l.segmentId).toList(), [
        0,
        1,
        2,
      ], reason: '开流含段资产就位');

      renderer.stopStream();
      expect(sink.calls.sublist(sink.calls.length - 2), [
        'flush',
        'stop',
      ], reason: '停流 = flush 未消费 + 停流');
    });

    test('rebuildTransport：换新流对象并按最近下推的配对重推同步对', () async {
      final sink = FakeBeatAudioSink()..advanceMonotonicMs(500);
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );
      renderer.onMediaNow(
        const MediaClockSync(mediaTimeMs: 5000, rate: 1.0, playing: true),
      );
      final syncsBefore = sink.syncs.length;

      await renderer.rebuildTransport();

      expect(sink.recoverCount, 1);
      expect(
        sink.syncs.length,
        greaterThan(syncsBefore),
        reason: '新流对象不带锚：重建后必须重推同步对，第一拍才落得下去',
      );
      expect(sink.syncs.last.mediaTimeMs, 5000.0);
    });

    test('重建时无锚不下推（不伪造锚）', () async {
      final sink = FakeBeatAudioSink();
      final renderer = BeatAudioRenderer(
        sink: sink,
        loadAsset: realAssetLoader,
      );

      await renderer.rebuildTransport();

      expect(sink.recoverCount, 1);
      expect(sink.syncs, isEmpty, reason: '无锚：不把 0 伪造成锚');
    });
  });

  test('WAV 解码：16-bit 立体声混单声道、采样率正确', () {
    final wav = decodeWavMono(
      pcm16Wav(sampleRate: 22050, channels: 2, frames: [0.0, 0.5, -1.0]),
    );

    expect(wav.sampleRate, 22050);
    expect(wav.samples.length, 3);
    expect(wav.samples[0], 0.0);
    expect(wav.samples[1], closeTo(0.5, 1e-4));
    expect(wav.samples[2], closeTo(-1.0, 1e-4));
  });

  test('WAV 解码：非法数据上抛', () {
    expect(() => decodeWavMono(Uint8List(4)), throwsArgumentError);
  });

  group('哑 sink 失败可见', () {
    test('原生渲染器不可用（非 Android 宿主）：回退哑 sink 并留单 tag 日志', () {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = original);

      final container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
      );
      addTearDown(container.dispose);

      // 宿主单测无 libaudio_native.so → open 上抛 → 回退哑 sink（不发声，但
      // 播放链路不受阻）；「不留无声的永久降级」= 这条降级必须可见。
      final renderer = container.read(beatAudioRendererProvider);
      expect(renderer.entry.id, kNormalSourceId);

      expect(
        logs.where(
          (l) =>
              l.startsWith(kBeatAudioLogTag) &&
              l.contains('哑 sink') &&
              l.contains('libaudio_native.so'),
        ),
        isNotEmpty,
        reason: '哑 sink 降级留日志（含原因）',
      );
    });
  });
}
