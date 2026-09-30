import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/av_sync.dart';
import 'package:dance_learning_app/player/speed_control.dart'
    show speedControlProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 测试用音频输出设备控制器（设备事件 seam）：记录调用、
/// 可直呼模拟设备切换（与 FakeSystemMediaVolumeController 同先例）。
class FakeAudioOutputDeviceController implements AudioOutputDeviceController {
  final StreamController<AvSyncDeviceInfo?> _changes =
      StreamController<AvSyncDeviceInfo?>.broadcast();

  /// 当前设备（emitDevice 前先更新，与真实系统一致）。
  AvSyncDeviceInfo? current;

  @override
  Future<AvSyncDeviceInfo?> get() async => current;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => _changes.stream;

  /// 测试直呼：模拟系统路由切换（切蓝牙耳机/拔耳机等）。
  void emitDevice(AvSyncDeviceInfo? device) {
    current = device;
    _changes.add(device);
  }
}

void main() {
  group('音画同步纯函数', () {
    test('钳制：±1000 双向、越界收边', () {
      expect(clampAvSyncMs(0), 0);
      expect(clampAvSyncMs(1000), 1000);
      expect(clampAvSyncMs(-1000), -1000);
      expect(clampAvSyncMs(1200), 1000);
      expect(clampAvSyncMs(-1200), -1000);
    });

    test('设备键：类型+产品名；产品缺失归「其它设备」', () {
      const bt = AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
      expect(bt.key, '蓝牙|X 耳机');
      expect(bt.label, '蓝牙·X 耳机');

      const noProduct = AvSyncDeviceInfo(typeLabel: '蓝牙', product: null);
      expect(noProduct.key, avSyncUnknownDeviceKey);
      expect(noProduct.label, avSyncUnknownDeviceKey);
      expect(noProduct.key, const AvSyncDeviceInfo.unknown().key);
    });

    test('净化：非 Map 兜底空、非法项丢弃、越界钳制', () {
      expect(sanitizeAvSyncDelays(null), isEmpty);
      expect(sanitizeAvSyncDelays('x'), isEmpty);
      expect(
        sanitizeAvSyncDelays({
          '蓝牙|A': 120,
          '蓝牙|B': 'x',
          '蓝牙|C': 5000,
          '蓝牙|D': -5000,
        }),
        {'蓝牙|A': 120, '蓝牙|C': 1000, '蓝牙|D': -1000},
      );
    });

    test('节拍声触发读平移缝：正延迟 = 嗒声提前，触发读 +Δ·rate 媒体秒', () {
      expect(
        avSyncTickTriggerShiftMedia(delayMs: 100, rate: 1.0),
        const Duration(milliseconds: 100),
      );
      expect(
        avSyncTickTriggerShiftMedia(delayMs: 100, rate: 2.0),
        const Duration(milliseconds: 200),
      );
      expect(
        avSyncTickTriggerShiftMedia(delayMs: -50, rate: 2.0),
        const Duration(milliseconds: -100),
      );
      // 延迟 0：行为与现状一致（零平移）。
      expect(
        avSyncTickTriggerShiftMedia(delayMs: 0, rate: 1.5),
        Duration.zero,
      );
    });

    test('媒体层偏移：mpv audio-delay 秒值 = −Δ·rate（负=延迟视频）', () {
      expect(avSyncAudioDelaySeconds(delayMs: 100, rate: 1.0), closeTo(-0.1, 1e-9));
      expect(avSyncAudioDelaySeconds(delayMs: 100, rate: 2.0), closeTo(-0.2, 1e-9));
      expect(avSyncAudioDelaySeconds(delayMs: -30, rate: 2.0), closeTo(0.06, 1e-9));
    });
  });

  group('设备级 store seam', () {
    test('update 只写本键、保留同文件其它键（不复刻 clear+addAll）', () async {
      final storage = InMemoryPrivateJsonStorage(initial: {
        'speedStepPresets': {'presets': [1]},
        'metronomeSettings': {'soundType': 'ping'},
        'avSyncDelays': {'其它设备': 60},
      });
      final store = AvSyncDelaysStore(storage);

      await store.update((delays) async {
        delays['其它设备'] = 70;
        delays['蓝牙|X'] = -40;
      });

      final json = storage.snapshot;
      expect(json['avSyncDelays'], {'其它设备': 70, '蓝牙|X': -40});
      // 同文件其它键原样保留。
      expect(json['speedStepPresets'], {'presets': [1]});
      expect(json['metronomeSettings'], {'soundType': 'ping'});
    });

    test('load 净化：缺失/损坏兜底空 Map', () async {
      expect(
        await AvSyncDelaysStore(
          InMemoryPrivateJsonStorage(),
        ).load(),
        isEmpty,
      );
      expect(
        await AvSyncDelaysStore(
          InMemoryPrivateJsonStorage(initial: {'avSyncDelays': 7}),
        ).load(),
        isEmpty,
      );
    });
  });

  group('音画同步模型（恢复/变更即存/设备切换换值/引擎应用）', () {
    late FakePlaybackEngine engine;
    late FakeAudioOutputDeviceController deviceController;
    late InMemoryPrivateJsonStorage storage;
    late ProviderContainer container;

    AvSyncModel model() =>
        container.read(avSyncProvider.notifier);

    setUp(() {
      engine = FakePlaybackEngine();
      deviceController = FakeAudioOutputDeviceController();
      storage = InMemoryPrivateJsonStorage();
      container = ProviderContainer(overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(storage),
        avSyncDelaysAutoRestoreProvider.overrideWithValue(true),
        audioOutputDeviceControllerProvider
            .overrideWithValue(deviceController),
      ]);
      addTearDown(container.dispose);
    });

    test('启动恢复：读当前设备（默认其它设备）的已存值并应用到引擎', () async {
      await container.read(avSyncDelaysStorageProvider).update(
        (d) async => d[avSyncUnknownDeviceKey] = 120,
      );
      // 重新构建容器走恢复路径。
      final fresh = ProviderContainer(overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(storage),
        avSyncDelaysAutoRestoreProvider.overrideWithValue(true),
        audioOutputDeviceControllerProvider
            .overrideWithValue(deviceController),
      ]);
      addTearDown(fresh.dispose);
      await fresh.read(avSyncProvider.notifier).restoreDone;
      expect(fresh.read(avSyncProvider).delayMs, 120);
      expect(engine.avSyncDelayCalls, [120]);
    });

    test('采纳会话应用值：状态更新；调节不写盘', () async {
      await model().restoreDone;
      model().adopt(10);
      expect(container.read(avSyncProvider).delayMs, 10);
      model().adopt(-1020);
      expect(container.read(avSyncProvider).delayMs, -1000);
      // 调节不再写盘（会话值不写，应用才写——写路径归校准会话）；
      // 引擎应用也由会话在「应用」时完成，本模型不直推。
      expect(engine.avSyncDelayCalls, isEmpty);
      final saved = storage.snapshot;
      expect(saved.containsKey('avSyncDelays'), isFalse);
    });

    test('设备切换 seam：自动换用对应设备已存值并应用到引擎；不改其它设备键',
        () async {
      await container.read(avSyncDelaysStorageProvider).update(
        (d) async {
          d[avSyncUnknownDeviceKey] = 60;
          d['蓝牙|X 耳机'] = -40;
        },
      );
      await model().restoreDone;
      expect(container.read(avSyncProvider).delayMs, 60);

      deviceController.emitDevice(
        const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
      );
      // 设备事件 → 换值是异步链（广播流 + 存储读取），等事件队列排空。
      await Future<void>.delayed(Duration.zero);
      expect(container.read(avSyncProvider).delayMs, -40);
      expect(container.read(avSyncProvider).deviceLabel, '蓝牙·X 耳机');
      expect(engine.avSyncDelayCalls, [60, -40]);

      // 切换本身不写盘：两键仍是原值。
      final saved = storage.snapshot['avSyncDelays'] as Map;
      expect(saved[avSyncUnknownDeviceKey], 60);
      expect(saved['蓝牙|X 耳机'], -40);
    });

    test('设备切到无记录设备：回 0（默认），该设备键随后首次调节时才建项',
        () async {
      await container.read(avSyncDelaysStorageProvider).update(
        (d) async => d[avSyncUnknownDeviceKey] = 60,
      );
      await model().restoreDone;
      deviceController.emitDevice(
        const AvSyncDeviceInfo(typeLabel: '有线耳机', product: 'USB-C'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(avSyncProvider).delayMs, 0);
      expect(container.read(avSyncProvider).deviceLabel, '有线耳机·USB-C');
    });

    test('关闭自动恢复（测试确定性）：保持出厂 0', () async {      await container.read(avSyncDelaysStorageProvider).update(
        (d) async => d[avSyncUnknownDeviceKey] = 120,
      );
      final fresh = ProviderContainer(overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(storage),
        avSyncDelaysAutoRestoreProvider.overrideWithValue(false),
        audioOutputDeviceControllerProvider
            .overrideWithValue(deviceController),
      ]);
      addTearDown(fresh.dispose);
      await fresh.read(avSyncProvider.notifier).restoreDone;
      expect(fresh.read(avSyncProvider).delayMs, 0);
    });

    test('倍速变化：媒体层偏移按新倍速重应用（Δ·rate 同源）', () async {
      await model().restoreDone;
      model().adopt(100);
      // 采纳本身不推引擎（应用链归会话）；改倍速 → 引擎 seam 以当前 ms
      // 重新应用（实现内部按新 rate 换算）。
      expect(engine.avSyncDelayCalls, isEmpty);
      await container.read(speedControlProvider.notifier).setRate(2.0);
      expect(engine.avSyncDelayCalls, [100]);

      // 延迟为 0 时改倍速不重应用（无偏移无需换算）。
      model().adopt(0);
      await container.read(speedControlProvider.notifier).setRate(1.0);
      expect(engine.avSyncDelayCalls, [100]);
    });
  });
}
