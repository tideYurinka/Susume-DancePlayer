import 'dart:async';

import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/av_sync.dart';
import 'package:dance_learning_app/player/av_sync_bubble.dart';
import 'package:dance_learning_app/player/av_sync_session.dart';
import 'package:dance_learning_app/player/calibration_session_grid.dart'
    show CalibrationSessionBpmTier;
import 'package:dance_learning_app/player/speed_bubble.dart'
    show SpeedBubbleMode, speedBubbleSessionProvider;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHighlightAmber;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/semantics_assertions.dart';

/// 测试用音频输出设备控制器（设备事件 seam 直呼模拟）。
class FakeAudioOutputDeviceController implements AudioOutputDeviceController {
  FakeAudioOutputDeviceController(this.current);

  AvSyncDeviceInfo? current;

  final _events = StreamController<AvSyncDeviceInfo?>.broadcast();

  @override
  Future<AvSyncDeviceInfo?> get() async => current;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => _events.stream;

  Future<void> setDevice(AvSyncDeviceInfo? device) async => current = device;

  /// 会话中设备切换事件（气泡内直呼模拟）。
  Future<void> emitDevice(AvSyncDeviceInfo? device) async {
    current = device;
    _events.add(device);
  }

  void disposeEvents() => unawaited(_events.close());
}

/// 气泡测试壳：最小 ProviderScope + Material，直接挂内容 widget——挂载
/// 即进入校准会话、卸载即取消。返回容器供测试读同步点与注入
/// 节拍轨状态。[deviceController] 可外置以便会话中直呼设备切换事件。
Future<ProviderContainer> pumpBubble(
  WidgetTester tester, {
  required FakePlaybackEngine engine,
  required InMemoryPrivateJsonStorage storage,
  AvSyncDeviceInfo? device,
  FakeAudioOutputDeviceController? deviceController,
}) async {
  final controller =
      deviceController ?? FakeAudioOutputDeviceController(device);
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      privateJsonStorageProvider.overrideWithValue(storage),
      avSyncDelaysAutoRestoreProvider.overrideWithValue(false),
      audioOutputDeviceControllerProvider.overrideWithValue(controller),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(controller.disposeEvents);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AvSyncBubbleContent())),
    ),
  );
  // 会话 enter 是异步链（设备快照 + 存储读）：固定帧推进至稳定。
  await tester.pump();
  await tester.pump();
  return container;
}

/// 沿滑条轨道把值拖到目标增量像素（中心起手，[dx] 正 = 向右）。
///
/// 活动会话持续收脉冲（见 `_AvSyncSessionPulse`），不可 pumpAndSettle；
/// 固定帧推进交互落定。
Future<void> dragSliderBy(WidgetTester tester, double dx) async {
  final center = tester.getCenter(find.byKey(const Key('av_sync_slider')));
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(Offset(dx, 0));
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// 就绪网格（拍点每 0.5s 一拍，歌曲档一拍间隔 = 500ms）注入节拍轨。
void seedReadyGrid(ProviderContainer container) {
  container
      .read(beatTrackStateProvider.notifier)
      .replace(uniformReadyBeatState());
}

void main() {
  testWidgets('气泡内容顺序：设备名 → 刻度带（8 格）→ BPM 三档 → 滑条 → 细调读数重置 → 应用/取消', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
      device: const AvSyncDeviceInfo.unknown(),
    );

    final deviceDy = tester
        .getCenter(find.byKey(const Key('av_sync_device')))
        .dy;
    final bandDy = tester.getCenter(find.byKey(const Key('av_sync_band'))).dy;
    final bpmDy = tester.getCenter(find.byKey(const Key('av_sync_bpm'))).dy;
    final sliderDy = tester
        .getCenter(find.byKey(const Key('av_sync_slider')))
        .dy;
    final readoutDy = tester
        .getCenter(find.byKey(const Key('av_sync_readout')))
        .dy;
    final applyDy = tester.getCenter(find.byKey(const Key('av_sync_apply'))).dy;
    expect(deviceDy, lessThan(bandDy));
    expect(bandDy, lessThan(bpmDy));
    expect(bpmDy, lessThan(sliderDy));
    expect(sliderDy, lessThan(readoutDy));
    expect(readoutDy, lessThan(applyDy));

    expect(find.byKey(const Key('av_sync_band_cell_0')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_band_cell_7')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_bpm_song')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_bpm_120')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_bpm_160')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_minus')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_plus')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_reset')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_cancel')), findsOneWidget);
  });

  testWidgets('静态迷你时间轴与「节拍声参考」开关被移除（自足会话取代）', (tester) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    expect(find.byKey(const Key('av_sync_reference')), findsNothing);
    expect(find.byKey(const Key('av_sync_reference_toggle')), findsNothing);
    expect(find.byKey(const Key('av_sync_reference_flash')), findsNothing);
    expect(find.byKey(const Key('av_sync_reference_tick')), findsNothing);
    expect(find.text('节拍声参考（边播边听）'), findsNothing);
  });

  testWidgets('刻度带随会话拍脉冲闪亮：脉冲数即格位（8 格循环、自重启归零）', (tester) async {
    final container = await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );
    Future<void> fire(int n) async {
      for (var i = 0; i < n; i++) {
        container
            .read(avSyncCalibrationSessionProvider.notifier)
            .fireBeatPulse();
        await tester.pump(const Duration(milliseconds: 1));
      }
    }

    // 0 脉冲：无格亮。
    expect(find.byKey(const Key('av_sync_band_cell_0_on')), findsNothing);

    // 第 1 拍（重音）→ 格 0 亮。
    await fire(1);
    expect(find.byKey(const Key('av_sync_band_cell_0_on')), findsOneWidget);
    expect(find.byKey(const Key('av_sync_band_cell_1_on')), findsNothing);

    // 第 2/3/4 拍 → 格 1/2/3 依次亮。
    await fire(3);
    expect(find.byKey(const Key('av_sync_band_cell_3_on')), findsOneWidget);

    // 第 5 拍 → 格 4（每 4 拍重音、8 格循环）。
    await fire(1);
    expect(find.byKey(const Key('av_sync_band_cell_4_on')), findsOneWidget);
  });

  testWidgets('BPM 三档：默认 120（无已对齐网格歌曲档禁用）；有网格歌曲档可用且为默认', (tester) async {
    final container = await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    // 无已对齐网格：歌曲档禁用、默认 120 档。
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('av_sync_bpm_song')))
          .onPressed,
      isNull,
    );

    // 注入已对齐网格：歌曲档启用且成为默认档（歌曲 0.5s/拍）。
    seedReadyGrid(container);
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('av_sync_bpm_song')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('设备切换：提示呈现 + 试听值复位为新设备记忆值', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: {
        avSyncDelaysKey: {'蓝牙|Y 耳机': 120},
      },
    );
    final controller = FakeAudioOutputDeviceController(
      const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
    );
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: storage,
      deviceController: controller,
    );
    await dragSliderBy(tester, 2000);
    expect(find.text('+1000 ms'), findsOneWidget);

    await controller.emitDevice(
      const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'Y 耳机'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('输出设备已切换为 蓝牙·Y 耳机'), findsOneWidget);
    expect(find.text('+120 ms'), findsOneWidget);

    // 短暂提示：数秒后自动隐去（气泡内展示态，实现定 3s）。
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('av_sync_device_notice')), findsNothing);
  });

  testWidgets('BPM 快选读写会话状态：按钮读 state.tier、点击经 setTier 写意图；设备切换不清档', (
    tester,
  ) async {
    final controller = FakeAudioOutputDeviceController(
      const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
    );
    final container = await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
      deviceController: controller,
    );
    AvSyncCalibrationSessionState state() =>
        container.read(avSyncCalibrationSessionProvider);

    Color? selectedColor(Key key) => tester
        .widget<TextButton>(find.byKey(key))
        .style
        ?.foregroundColor
        ?.resolve(const {});

    // 进入默认档（无网格回落 120）。
    expect(selectedColor(const Key('av_sync_bpm_120')), kHighlightAmber);
    expect(state().tier, CalibrationSessionBpmTier.bpm120);

    // 点击 160：写意图入会话 state，按钮选中态跟随 state.tier。
    await tester.tap(find.byKey(const Key('av_sync_bpm_160')));
    await tester.pump();
    expect(state().tier, CalibrationSessionBpmTier.bpm160);
    expect(selectedColor(const Key('av_sync_bpm_160')), kHighlightAmber);
    expect(selectedColor(const Key('av_sync_bpm_120')), isNot(kHighlightAmber));

    // 设备切换：试听值复位 + 刻度带重启，档位保留。
    await controller.emitDevice(
      const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'Z 耳机'),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('输出设备已切换为 蓝牙·Z 耳机'), findsOneWidget);
    expect(state().tier, CalibrationSessionBpmTier.bpm160);
    expect(selectedColor(const Key('av_sync_bpm_160')), kHighlightAmber);
  });

  testWidgets('应用：试听值写入当前设备键 + 引擎应用 + 退出还原播放 + 收泡', (tester) async {
    final engine = FakePlaybackEngine();
    final storage = InMemoryPrivateJsonStorage(
      initial: {
        avSyncDelaysKey: {'蓝牙|X 耳机': 60},
      },
    );
    await engine.open(Uri.parse('file:///a.mp4'));
    await engine.play();
    final container = await pumpBubble(
      tester,
      engine: engine,
      storage: storage,
      device: const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
    );
    // 进入会话 = 暂停被调（记住进入前在播）。
    expect(engine.isPlaying, isFalse);
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.avSync);
    await tester.pump();

    await dragSliderBy(tester, -2000);
    expect(find.text('-1000 ms'), findsOneWidget);
    await tester.tap(find.byKey(const Key('av_sync_apply')));
    await tester.pump();
    await container.read(avSyncCalibrationSessionProvider.notifier).applyDone;

    expect((storage.snapshot[avSyncDelaysKey] as Map)['蓝牙|X 耳机'], kAvSyncMinMs);
    expect(engine.avSyncDelayCalls, [kAvSyncMinMs]);
    // 退出还原进入前播放态（进入前在播 → 续播）。
    expect(engine.isPlaying, isTrue);
    // 应用后收泡（互斥会话关闭）。
    expect(container.read(speedBubbleSessionProvider).open, isNull);
    await engine.pause(); // 收尾停表（fake ticker 需在测试结束前停止）。
  });

  testWidgets('取消：丢弃试听值退出（零写盘）+ 还原播放 + 收泡', (tester) async {
    final engine = FakePlaybackEngine();
    final storage = InMemoryPrivateJsonStorage();
    await engine.open(Uri.parse('file:///a.mp4'));
    await engine.play();
    final container = await pumpBubble(
      tester,
      engine: engine,
      storage: storage,
    );
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.avSync);
    await tester.pump();

    await dragSliderBy(tester, 2000);
    await tester.tap(find.byKey(const Key('av_sync_cancel')));

    expect(engine.isPlaying, isTrue);
    expect(storage.snapshot.containsKey(avSyncDelaysKey), isFalse);
    expect(engine.avSyncDelayCalls, isEmpty);
    expect(container.read(speedBubbleSessionProvider).open, isNull);
    await engine.pause(); // 收尾停表（fake ticker 需在测试结束前停止）。
  });

  testWidgets('滑条主交互：向右拖改正试听值（读数带符号、零写盘、零引擎应用）', (tester) async {
    final engine = FakePlaybackEngine();
    final storage = InMemoryPrivateJsonStorage();
    await pumpBubble(
      tester,
      engine: engine,
      storage: storage,
      device: const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
    );

    // 拖动幅度远超滑条右缘：钳制到 +1000。
    await dragSliderBy(tester, 2000);
    expect(find.text('+1000 ms'), findsOneWidget);
    // 会话试听值不写盘（应用才写）。
    expect(storage.snapshot.containsKey(avSyncDelaysKey), isFalse);
    expect(engine.avSyncDelayCalls, isEmpty);
  });

  testWidgets('滑条：向左拖为负延迟（− 符号）', (tester) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    await dragSliderBy(tester, -2000);
    expect(find.text('-1000 ms'), findsOneWidget);
  });

  testWidgets('＋：单步 +10ms（读数带符号）；−：单步 −10ms', (tester) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    await tester.tap(find.byKey(const Key('av_sync_plus')));
    await tester.pump();
    expect(find.text('+10 ms'), findsOneWidget);

    await tester.tap(find.byKey(const Key('av_sync_minus')));
    await tester.pump();
    expect(find.text('0 ms'), findsOneWidget);
  });

  testWidgets('＋/−：报按钮角色与名字；读屏激活确实步进', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    expectButtonSemantics(tester, const Key('av_sync_minus'), label: '音画同步减一档');
    expectButtonSemantics(tester, const Key('av_sync_plus'), label: '音画同步加一档');

    activateBySemantics(tester, const Key('av_sync_plus'));
    await tester.pump();
    expect(find.text('+10 ms'), findsOneWidget, reason: '读屏双击＋应真的步进');

    activateBySemantics(tester, const Key('av_sync_minus'));
    await tester.pump();
    expect(find.text('0 ms'), findsOneWidget, reason: '读屏双击−应真的步进');
    handle.dispose();
  });

  testWidgets('按住连续：长按＋重复单步（400ms 阈值后每 100ms 一步）', (tester) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('av_sync_plus'))),
    );
    await tester.pump();
    // 阈值前：仅按下那一步。
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('+10 ms'), findsOneWidget);
    // 进入重复（阈值 400ms 后每 100ms 一步）：再两步。
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('+30 ms'), findsOneWidget);
    await gesture.up();
  });

  testWidgets('重置：调节后一键归 0（会话内存态）', (tester) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
    );

    await tester.tap(find.byKey(const Key('av_sync_plus')));
    await tester.tap(find.byKey(const Key('av_sync_reset')));
    await tester.pump();
    expect(find.text('0 ms'), findsOneWidget);
  });

  testWidgets('设备名：可辨识设备显示 类型·产品名；未知设备兜底「其它设备」', (tester) async {
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
      device: const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
    );
    expect(find.text('蓝牙·X 耳机'), findsOneWidget);

    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: InMemoryPrivateJsonStorage(),
      device: const AvSyncDeviceInfo.unknown(),
    );
    expect(find.text('其它设备'), findsOneWidget);
  });

  testWidgets('进入会话初始试听值 = 当前设备记忆值', (tester) async {
    final storage = InMemoryPrivateJsonStorage(
      initial: {
        avSyncDelaysKey: {'蓝牙|X 耳机': 80},
      },
    );
    await pumpBubble(
      tester,
      engine: FakePlaybackEngine(),
      storage: storage,
      device: const AvSyncDeviceInfo(typeLabel: '蓝牙', product: 'X 耳机'),
    );

    expect(find.text('+80 ms'), findsOneWidget);
  });
}
