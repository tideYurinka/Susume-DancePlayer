import 'dart:async';

import 'dart:math' as math;

import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/av_sync.dart';
import 'package:dance_learning_app/player/av_sync_session.dart';
import 'package:dance_learning_app/player/metronome_sound.dart'
    show MetronomeSoundType, metronomeSoundTypeProvider;
import 'package:dance_learning_app/player/calibration_session_grid.dart'
    show CalibrationSessionBpmTier;
import 'package:dance_learning_app/player/metronome_source_registry.dart'
    show effectiveMetronomeSourceIdProvider;
import 'package:dance_learning_app/player/native_scheduled_audio.dart'
    show beatAudioRendererProvider;
import 'package:dance_learning_app/player/speed_bubble.dart'
    show SpeedBubbleMode, speedBubbleSessionProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 测试用音频输出设备控制器（设备事件 seam，可直呼模拟路由切换）。
class FakeAudioOutputDeviceController implements AudioOutputDeviceController {
  final StreamController<AvSyncDeviceInfo?> _changes =
      StreamController<AvSyncDeviceInfo?>.broadcast();

  AvSyncDeviceInfo? current;

  @override
  Future<AvSyncDeviceInfo?> get() async => current;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => _changes.stream;

  void emitDevice(AvSyncDeviceInfo? device) {
    current = device;
    _changes.add(device);
  }
}

/// get() 逐次换设备的 fake（复现 enter 取数期间路由切换的竞态窗口）。
class ShiftingAudioOutputDeviceController
    implements AudioOutputDeviceController {
  ShiftingAudioOutputDeviceController(this.snapshotSequence);

  /// get() 按序返回的设备（耗尽后停在最后一个）。
  final List<AvSyncDeviceInfo?> snapshotSequence;
  int _calls = 0;

  @override
  Future<AvSyncDeviceInfo?> get() async {
    final index = math.min(_calls, snapshotSequence.length - 1);
    _calls += 1;
    return snapshotSequence[index];
  }

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => const Stream.empty();
}

/// 写计数存储 fake：委托
/// [AvSyncDelaysStore] 真语义，只额外记录 update 次数与写入键值序列。
class CountingAvSyncStorage implements AvSyncDelaysStorage {
  CountingAvSyncStorage(this._inner);

  final AvSyncDelaysStorage _inner;

  /// update 调用次数（会话提交门断言「恰好一次写 / 零写」）。
  int updateCalls = 0;

  /// 每次 update 落下的 {键: 值} 增量（按序）。
  final List<Map<String, int>> writtenKeys = [];

  /// 清零计数（预置数据写入后，只统计被测行为的写）。
  void resetCounters() {
    updateCalls = 0;
    writtenKeys.clear();
  }

  @override
  Future<Map<String, int>> load() => _inner.load();

  @override
  Future<void> update(
    FutureOr<void> Function(Map<String, int> delays) mutate,
  ) {
    updateCalls += 1;
    final captured = <String, int>{};
    return _inner.update((delays) async {
      final before = Map<String, int>.of(delays);
      await mutate(delays);
      delays.forEach((key, value) {
        if (before[key] != value) captured[key] = value;
      });
      writtenKeys.add(captured);
    });
  }
}

void main() {
  group('音画同步校准会话（会话状态与应用门）', () {
    late FakePlaybackEngine engine;
    late FakeAudioOutputDeviceController deviceController;
    late InMemoryPrivateJsonStorage privateJson;
    late CountingAvSyncStorage storage;
    late ProviderContainer container;

    AvSyncCalibrationSessionModel session() =>
        container.read(avSyncCalibrationSessionProvider.notifier);

    AvSyncCalibrationSessionState state() =>
        container.read(avSyncCalibrationSessionProvider);

    /// 预置设备延迟表（经真实 store 写入，不计入会话写计数）。
    Future<void> seedDelays(Map<String, int> delays) async {
      await container.read(avSyncDelaysStorageProvider).update((d) async {
        d.addAll(delays);
      });
      storage.resetCounters();
    }

    setUp(() {
      engine = FakePlaybackEngine();
      deviceController = FakeAudioOutputDeviceController();
      privateJson = InMemoryPrivateJsonStorage();
      storage = CountingAvSyncStorage(AvSyncDelaysStore(privateJson));
      container = ProviderContainer(overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(privateJson),
        avSyncDelaysStorageProvider.overrideWithValue(storage),
        audioOutputDeviceControllerProvider
            .overrideWithValue(deviceController),
      ]);
      addTearDown(container.dispose);
    });

    test('进入会话：暂停被调 + 初始试听值 = 当前设备记忆值（未校准 = 0）', () async {
      await seedDelays({avSyncUnknownDeviceKey: 120});
      await engine.open(Uri.parse('file:///a.mp4'));
      await engine.play();
      expect(engine.isPlaying, isTrue);

      await session().enter();

      expect(state().active, isTrue);
      expect(state().trialMs, 120);
      expect(engine.isPlaying, isFalse);
      expect(engine.callLog, contains('pause'));

      // 未校准设备：初始试听值 = 0。
      await session().cancel();
      deviceController.emitDevice(
        const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'Y 耳机'),
      );
      await Future<void>.delayed(Duration.zero);
      await session().enter();
      expect(state().trialMs, 0);
    });

    test('进入前已暂停：保持暂停（不额外还原播放）', () async {
      await engine.open(Uri.parse('file:///a.mp4'));
      await session().enter();

      await session().cancel();
      expect(engine.isPlaying, isFalse);
      expect(engine.callLog, isNot(contains('play')));
    });

    test('试听值变更：即改即生效（钳制）且零存储写、零引擎应用', () async {
      await session().enter();
      final updateCallsAtEnter = storage.updateCalls;

      session().setTrialMs(300);
      expect(state().trialMs, 300);
      session().stepBy(10);
      expect(state().trialMs, 310);
      session().setTrialMs(5000);
      expect(state().trialMs, kAvSyncMaxMs);

      expect(storage.updateCalls, updateCallsAtEnter);
      expect(engine.avSyncDelayCalls, isEmpty);
    });

    test('应用：恰好一次写当前设备键 + 引擎值更新 + 退出还原进入前播放态', () async {
      await seedDelays({avSyncUnknownDeviceKey: 60});
      deviceController.current =
          const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
      await engine.open(Uri.parse('file:///a.mp4'));
      await engine.play();

      await session().enter();
      expect(state().deviceKey, '蓝牙|X 耳机');
      session().setTrialMs(-40);

      await session().apply();
      await session().applyDone;

      expect(storage.updateCalls, 1);
      expect(storage.writtenKeys.single, {'蓝牙|X 耳机': -40});
      expect(
        (privateJson.snapshot['avSyncDelays'] as Map)['蓝牙|X 耳机'],
        -40,
      );
      expect(engine.avSyncDelayCalls, [-40]);
      // 退出会话并还原进入前播放态（进入前在播 → 续播）。
      expect(state().active, isFalse);
      expect(engine.isPlaying, isTrue);
    });

    test('应用后生效值进入音画同步模型（播放侧/视觉链读当前延迟）', () async {
      await session().enter();
      session().setTrialMs(90);
      await session().apply();
      await session().applyDone;

      expect(container.read(avSyncProvider).delayMs, 90);
    });

    test('取消：零写盘 + 还原进入前播放态', () async {
      deviceController.current =
          const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
      await seedDelays({'蓝牙|X 耳机': 60});
      await engine.open(Uri.parse('file:///a.mp4'));
      await engine.play();

      await session().enter();
      session().setTrialMs(500);
      await session().cancel();

      expect(storage.updateCalls, 0);
      expect(engine.avSyncDelayCalls, isEmpty);
      expect(state().active, isFalse);
      expect(engine.isPlaying, isTrue);
      // 试听值未落盘：已存键仍是原值，未新增键。
      final delays = privateJson.snapshot['avSyncDelays'] as Map;
      expect(delays, {'蓝牙|X 耳机': 60});
    });

    test('会话中手动恢复播放 = 放弃未应用调整并退出（零写盘）', () async {
      await engine.open(Uri.parse('file:///a.mp4'));
      await engine.play();
      await session().enter();
      expect(state().active, isTrue);
      session().setTrialMs(200);

      // 用户在画面上手动恢复播放（fake 直呼 play → isPlaying 真边沿）。
      await engine.play();
      await Future<void>.delayed(Duration.zero);

      expect(state().active, isFalse);
      expect(storage.updateCalls, 0);
      expect(engine.avSyncDelayCalls, isEmpty);
    });

    test('退后台：等同取消（零写盘 + 退出会话；播放页退后台直调 cancel）',
        () async {
      await engine.open(Uri.parse('file:///a.mp4'));
      await engine.play();
      await session().enter();
      session().setTrialMs(200);

      await session().cancel();

      expect(state().active, isFalse);
      expect(storage.updateCalls, 0);
      expect(engine.avSyncDelayCalls, isEmpty);
    });

    test('设备切换：会话重置为新设备记忆值（未校准 = 0）+ 切换提示 + 刻度带重启；零写盘',
        () async {
      deviceController.current =
          const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
      await seedDelays({'蓝牙|X 耳机': 60, '蓝牙|Z 耳机': -30});
      await session().enter();
      session().setTrialMs(300);
      final tokenAtEnter = state().restartToken;

      deviceController.emitDevice(
        const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'Z 耳机'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(state().active, isTrue);
      expect(state().deviceKey, '蓝牙|Z 耳机');
      expect(state().deviceLabel, '蓝牙·Z 耳机');
      expect(state().trialMs, -30);
      expect(state().notice, '输出设备已切换为 蓝牙·Z 耳机');
      expect(state().restartToken, greaterThan(tokenAtEnter));
      expect(storage.updateCalls, 0);

      // 重置后的试听值不误写任何设备键（应用只写当前设备键）。
      session().setTrialMs(10);
      await session().apply();
      await session().applyDone;
      expect(storage.writtenKeys.single, {'蓝牙|Z 耳机': 10});
      final delays = privateJson.snapshot['avSyncDelays'] as Map;
      expect(delays['蓝牙|X 耳机'], 60);
    });

    test('切到无记录设备：试听值复位 0', () async {
      deviceController.current =
          const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
      await seedDelays({'蓝牙|X 耳机': 60});
      await session().enter();
      session().setTrialMs(300);

      deviceController.emitDevice(
        const AvSyncDeviceInfo(typeLabel: '有线耳机', product: 'USB-C'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(state().trialMs, 0);
      expect(state().notice, '输出设备已切换为 有线耳机·USB-C');
    });

    test('前台无闲置超时：停留任意时长会话仍活跃（无自动退出）', () async {
      await session().enter();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state().active, isTrue);
    });

    test('未进入会话时的调节/应用/取消为无害 no-op', () async {
      session().setTrialMs(100);
      expect(state().trialMs, 0);
      await session().apply();
      await session().applyDone;
      await session().cancel();
      expect(storage.updateCalls, 0);
      expect(state().active, isFalse);
    });

    test('进入已活跃会话：no-op（不重暂停、不重置试听值）', () async {
      await engine.open(Uri.parse('file:///a.mp4'));
      await engine.play();
      await session().enter();
      session().setTrialMs(80);

      await session().enter();

      expect(state().trialMs, 80);
      expect(engine.isPlaying, isFalse);
    });

    test('enter 取数期间设备切换：建会话后复检快照，随新设备重置（竞态回归）',
        () async {
      const deviceA = AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
      const deviceB = AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'Z 耳机');
      await seedDelays({'蓝牙|X 耳机': 60, '蓝牙|Z 耳机': -30});
      final shifting = ShiftingAudioOutputDeviceController([deviceA, deviceB]);
      final raceContainer = ProviderContainer(overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(privateJson),
        avSyncDelaysStorageProvider.overrideWithValue(storage),
        audioOutputDeviceControllerProvider.overrideWithValue(shifting),
      ]);
      addTearDown(raceContainer.dispose);

      await raceContainer
          .read(avSyncCalibrationSessionProvider.notifier)
          .enter();

      final raceState = raceContainer.read(avSyncCalibrationSessionProvider);
      // 第一次快照给出旧设备 A（记忆值 60），复检发现已切到 B → 试听值
      // 复位为 B 记忆值（-30）并提示。
      expect(raceState.active, isTrue);
      expect(raceState.deviceKey, '蓝牙|Z 耳机');
      expect(raceState.trialMs, -30);
      expect(raceState.notice, '输出设备已切换为 蓝牙·Z 耳机');
      expect(storage.updateCalls, 0);
    });
  });

  group('校准会话生效音源（待支持音源回落普通）', () {
    late FakePlaybackEngine engine;
    late FakeAudioOutputDeviceController deviceController;
    late InMemoryPrivateJsonStorage privateJson;
    late CountingAvSyncStorage storage;
    late ProviderContainer container;

    setUp(() {
      engine = FakePlaybackEngine();
      deviceController = FakeAudioOutputDeviceController();
      privateJson = InMemoryPrivateJsonStorage();
      storage = CountingAvSyncStorage(AvSyncDelaysStore(privateJson));
      container = ProviderContainer(overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        privateJsonStorageProvider.overrideWithValue(privateJson),
        avSyncDelaysStorageProvider.overrideWithValue(storage),
        audioOutputDeviceControllerProvider
            .overrideWithValue(deviceController),
      ]);
      addTearDown(container.dispose);
    });

    Future<void> enterSession() async {
      await container
          .read(avSyncCalibrationSessionProvider.notifier)
          .enter();
    }

    void setSource(MetronomeSoundType type) => container
        .read(metronomeSoundTypeProvider.notifier)
        .set(type);

    test('会话活跃 + 待支持音源：会话滴答回落「普通」，退出还原原音源', () async {
      setSource(MetronomeSoundType.vocal);
      expect(container.read(effectiveMetronomeSourceIdProvider), 'vocal');

      await enterSession();
      expect(container.read(effectiveMetronomeSourceIdProvider), 'normal');

      await container
          .read(avSyncCalibrationSessionProvider.notifier)
          .cancel();
      expect(container.read(effectiveMetronomeSourceIdProvider), 'vocal');
    });

    test('会话活跃 + 普通音源：不变（无回落）', () async {
      setSource(MetronomeSoundType.normal);
      await enterSession();
      expect(container.read(effectiveMetronomeSourceIdProvider), 'normal');
    });

    test('回落只改会话发声：设置槽存值不被改写', () async {
      setSource(MetronomeSoundType.geigi);
      await enterSession();
      expect(container.read(effectiveMetronomeSourceIdProvider), 'normal');
      // 会话活跃期间与退出后，设置槽读态保持用户所选。
      expect(
        container.read(metronomeSoundTypeProvider),
        MetronomeSoundType.geigi,
      );
      await container
          .read(avSyncCalibrationSessionProvider.notifier)
          .cancel();
      expect(
        container.read(metronomeSoundTypeProvider),
        MetronomeSoundType.geigi,
      );
    });

    test('渲染器音源项随生效音源重建：会话回落换 entry、退出还原', () async {
      setSource(MetronomeSoundType.vocal);
      expect(
        container.read(beatAudioRendererProvider).entry.id,
        'vocal',
      );

      await enterSession();
      expect(
        container.read(beatAudioRendererProvider).entry.id,
        'normal',
      );

      await container
          .read(avSyncCalibrationSessionProvider.notifier)
          .cancel();
      expect(
        container.read(beatAudioRendererProvider).entry.id,
        'vocal',
      );
    });
  });

  tierState();
  unifiedExitWithRaceGuard();
}

/// BPM 档位入会话状态：档位属会话参数（与 active/trialMs 同生命周期）、
/// 气泡经 `setTier` 写意图、设备切换不清档、换档自下一拍生效。
void tierState() {
  late FakePlaybackEngine engine;
  late FakeAudioOutputDeviceController deviceController;
  late InMemoryPrivateJsonStorage privateJson;
  late CountingAvSyncStorage storage;
  late ProviderContainer container;

  AvSyncCalibrationSessionModel session() =>
      container.read(avSyncCalibrationSessionProvider.notifier);

  AvSyncCalibrationSessionState state() =>
      container.read(avSyncCalibrationSessionProvider);

  setUp(() {
    engine = FakePlaybackEngine();
    deviceController = FakeAudioOutputDeviceController();
    privateJson = InMemoryPrivateJsonStorage();
    storage = CountingAvSyncStorage(AvSyncDelaysStore(privateJson));
    container = ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      privateJsonStorageProvider.overrideWithValue(privateJson),
      avSyncDelaysStorageProvider.overrideWithValue(storage),
      audioOutputDeviceControllerProvider
          .overrideWithValue(deviceController),
    ]);
    addTearDown(container.dispose);
  });

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  void seedReadyGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState());
  }

  test('进入默认档：有已对齐网格 = 歌曲节拍；无网格回落 120（容器级）', () async {
    await session().enter();
    expect(state().active, isTrue);
    expect(state().tier, CalibrationSessionBpmTier.bpm120);

    await session().cancel();
    seedReadyGrid();
    await session().enter();
    expect(state().tier, CalibrationSessionBpmTier.song);
  });

  test('行为修正：就绪但拍点为空 ⇒ 歌曲档不可用，回落 120', () async {
    // 潜伏态：App 自身写入路径产不出（只有手改或分享来的标记文件会有）——
    // beat 段存在但拍点列表为空；占位均匀节奏不得冒充歌曲节拍。
    container
        .read(beatTrackStateProvider.notifier)
        .replace(readyEmptyBeatsBeatState());
    await session().enter();
    expect(state().active, isTrue);
    expect(state().tier, CalibrationSessionBpmTier.bpm120);
  });

  test('档位写意图：setTier 写入会话 state（读 state.tier）；非活跃 no-op', () async {
    session().setTier(CalibrationSessionBpmTier.bpm160);
    expect(state().tier, CalibrationSessionBpmTier.bpm120);

    await session().enter();
    session().setTier(CalibrationSessionBpmTier.bpm160);
    expect(state().tier, CalibrationSessionBpmTier.bpm160);
    session().setTier(CalibrationSessionBpmTier.song);
    expect(state().tier, CalibrationSessionBpmTier.song);
  });

  test('设备切换保留用户已选档位（不清档；零写盘）', () async {
    deviceController.current =
        const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
    await session().enter();
    session().setTier(CalibrationSessionBpmTier.bpm160);
    final tokenAtSwitch = state().restartToken;

    deviceController.emitDevice(
      const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'Z 耳机'),
    );
    await pump();

    expect(state().active, isTrue);
    expect(state().tier, CalibrationSessionBpmTier.bpm160);
    expect(state().restartToken, greaterThan(tokenAtSwitch));
    expect(storage.updateCalls, 0);
  });

  test('退出丢弃档位（与 trialMs 同生命周期）；重进入按默认重算', () async {
    await session().enter();
    session().setTier(CalibrationSessionBpmTier.bpm160);
    await session().cancel();
    expect(state().tier, CalibrationSessionBpmTier.bpm120);
  });
}

/// get() 可门控的设备控制器 fake（复现进入流程在途的 async 窗口）。
class GatedAudioOutputDeviceController
    implements AudioOutputDeviceController {
  Completer<void>? gate;

  @override
  Future<AvSyncDeviceInfo?> get() async {
    final pending = gate;
    if (pending != null) {
      gate = null;
      await pending.future;
    }
    return const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机');
  }

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => const Stream.empty();
}

/// 统一退出 + 进入竞态守卫。
/// 各退出通道同走模块 `_exit` 统一路径（零写盘 + 还原进入前播放态，
/// 不依赖气泡内容卸载）；进入完成前收到退出请求不遗留活跃会话、不误
/// 暂停；退出沿 in-flight 会话拍指令被世代守卫丢弃。
void unifiedExitWithRaceGuard() {
  late FakePlaybackEngine engine;
  late FakeAudioOutputDeviceController deviceController;
  late InMemoryPrivateJsonStorage privateJson;
  late CountingAvSyncStorage storage;
  late ProviderContainer container;

  setUp(() {
    engine = FakePlaybackEngine();
    deviceController = FakeAudioOutputDeviceController();
    privateJson = InMemoryPrivateJsonStorage();
    storage = CountingAvSyncStorage(AvSyncDelaysStore(privateJson));
    container = ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      privateJsonStorageProvider.overrideWithValue(privateJson),
      avSyncDelaysStorageProvider.overrideWithValue(storage),
      audioOutputDeviceControllerProvider
          .overrideWithValue(deviceController),
    ]);
    addTearDown(container.dispose);
  });

  /// 进入会话前置：打开媒体、播放中进入（进入前在播）并调过试听值。
  Future<void> enterWhilePlaying() async {
    await engine.open(Uri.parse('file:///a.mp4'));
    await engine.play();
    await container
        .read(avSyncCalibrationSessionProvider.notifier)
        .enter();
    container.read(avSyncCalibrationSessionProvider.notifier).setTrialMs(500);
  }

  group('统一退出：气泡离开 avSync 模式', () {
    test('收起/空白关闭：显式取消还原，零写盘', () async {
      await enterWhilePlaying();
      final bubbleSession = container.read(speedBubbleSessionProvider.notifier);
      bubbleSession.open(SpeedBubbleMode.avSync);

      // 纯容器级显式触发（无任何 widget 卸载时序参与）：点气泡外遮罩/收起。
      bubbleSession.close();

      final state = container.read(avSyncCalibrationSessionProvider);
      expect(state.active, isFalse);
      expect(storage.updateCalls, 0);
      expect(engine.avSyncDelayCalls, isEmpty);
      expect(engine.isPlaying, isTrue);
    });

    test('互斥切其它工具：显式取消还原，零写盘', () async {
      await enterWhilePlaying();
      final bubbleSession = container.read(speedBubbleSessionProvider.notifier);
      bubbleSession.open(SpeedBubbleMode.avSync);

      bubbleSession.open(SpeedBubbleMode.speed);

      final state = container.read(avSyncCalibrationSessionProvider);
      expect(state.active, isFalse);
      expect(storage.updateCalls, 0);
      expect(engine.isPlaying, isTrue);
    });
  });

  test('进入竞态守卫：进入完成前收到退出请求 → 不置活跃、不暂停（点开即点空白回归）',
      () async {
    final gatedDevice = GatedAudioOutputDeviceController();
    final gatedContainer = ProviderContainer(overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      privateJsonStorageProvider.overrideWithValue(privateJson),
      avSyncDelaysStorageProvider.overrideWithValue(storage),
      audioOutputDeviceControllerProvider
          .overrideWithValue(gatedDevice),
    ]);
    addTearDown(gatedContainer.dispose);
    await engine.open(Uri.parse('file:///a.mp4'));
    await engine.play();

    // 进入流程停在设备快照取数（在途），此时用户点开即点空白。
    final notifier =
        gatedContainer.read(avSyncCalibrationSessionProvider.notifier);
    gatedDevice.gate = Completer<void>();
    final gate = gatedDevice.gate!;
    final entering = notifier.enter();
    await Future<void>.delayed(Duration.zero);
    await notifier.cancel();
    gate.complete();
    await entering;

    final state = gatedContainer.read(avSyncCalibrationSessionProvider);
    expect(state.active, isFalse);
    // 未进入即未暂停：播放保持（「卡在暂停」回归）。
    expect(engine.isPlaying, isTrue);
    expect(engine.callLog, isNot(contains('pause')));
    expect(storage.updateCalls, 0);
    // 守卫后可正常进入。
    await notifier.enter();
    expect(
      gatedContainer.read(avSyncCalibrationSessionProvider).active,
      isTrue,
    );
  });

}
