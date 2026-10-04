import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/av_sync_math.dart';
import '../core/playback/playback_engine.dart';
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../core/private_json.dart';
import 'speed_control.dart' show speedControlProvider;

export '../core/playback/av_sync_math.dart'
    show
        avSyncAudioDelaySeconds,
        avSyncTickTriggerShiftMedia,
        clampAvSyncMs,
        kAvSyncMaxMs,
        kAvSyncMinMs,
        kAvSyncStepMs;

/// 音画同步：按输出设备记忆的音频延迟补偿（±1000ms、正 = 声音晚到）。
///
/// 三条 seam：
/// - 设备键 store（`global_private.json` 的 `avSyncDelays` 键，
///   [AvSyncDelaysStore]，写路径保留同文件其它键）；
/// - 设备事件（[AudioOutputDeviceController]，真实实现走 Android 平台
///   通道 `dance_learning_app/audio_output_device`，测试注入 fake）；
/// - 补偿应用：媒体层引擎偏移（[PlaybackEngine.setAvSyncDelayMs]）+
///   节拍声触发读平移缝（[avSyncTickTriggerShiftMedia]）：这是 Δ×倍速的
///   **唯一具名换算**，真正的消费方 = 节拍呈现
///   对象的媒体轴与会话轴产出（`beat_presentation.dart` 的
///   `_advanceMedia` / `_advanceSession`；会话轴倍速因子取 1——会话时钟
///   走墙钟）。正延迟 = 嗒声提前。视觉链不消费
///   Δ：数拍数字/节拍动画/摆锤与节拍轨刻度同读视频时间轴。

/// 私密 JSON 中的键名（与 speedStepPresets / metronomeSettings 并列）。
const String avSyncDelaysKey = 'avSyncDelays';

/// 未知设备（识别不到/产品名缺失）归一的设备键与显示名。
const String avSyncUnknownDeviceKey = '其它设备';

/// 音频输出设备信息（类型标签 + 产品名）。
class AvSyncDeviceInfo {
  const AvSyncDeviceInfo({required this.typeLabel, this.product});

  /// 识别不到时的兜底设备（「其它设备」）。
  const AvSyncDeviceInfo.unknown()
    : typeLabel = avSyncUnknownDeviceKey,
      product = null;

  /// 输出类型标签（蓝牙/扬声器/有线耳机…，平台通道给出）。
  final String typeLabel;

  /// 产品名；缺失/不可辨识为 null（回退归「其它设备」）。
  final String? product;

  /// 是否可辨识（产品名在场）。
  bool get identifiable => product != null && product!.trim().isNotEmpty;

  /// 设备键（未知设备归「其它设备」共用一项）。
  String get key =>
      identifiable ? '$typeLabel|${product!.trim()}' : avSyncUnknownDeviceKey;

  /// 显示名（类型·产品名；未知设备显示「其它设备」）。
  String get label =>
      identifiable ? '$typeLabel·${product!.trim()}' : avSyncUnknownDeviceKey;

  /// 平台通道载荷解码（缺失/非 Map → 未知设备）。
  static AvSyncDeviceInfo decode(Object? raw) {
    if (raw is! Map) return const AvSyncDeviceInfo.unknown();
    final type = raw['type'];
    final product = raw['product'];
    if (type is! String || type.isEmpty) {
      return const AvSyncDeviceInfo.unknown();
    }
    return AvSyncDeviceInfo(
      typeLabel: type,
      product: product is String ? product : null,
    );
  }
}

/// 设备延迟表净化：整体非 Map → 空；逐项 int 钳制、非法项丢弃。
Map<String, int> sanitizeAvSyncDelays(Object? raw) {
  if (raw is! Map) return const {};
  final result = <String, int>{};
  raw.forEach((key, value) {
    if (key is! String) return;
    if (value is! int) return;
    result[key] = clampAvSyncMs(value);
  });
  return result;
}

/// 设备级音画同步存取 seam：`avSyncDelays` 键下的
/// `{设备键: ms}` 表 + 「读 → 改 → 写」串行存取（保留同文件其它键）。
abstract interface class AvSyncDelaysStorage {
  /// 读取设备延迟表；缺失/损坏兜底空表。
  Future<Map<String, int>> load();

  /// 原子「读 → [mutate] → 写」（同文件其它键保留）。
  Future<void> update(FutureOr<void> Function(Map<String, int> delays) mutate);
}

/// [AvSyncDelaysStorage] 的私密 JSON 实现（键作用域与节拍器设置 store
/// 同款——只动本键、其余键原样）。
class AvSyncDelaysStore implements AvSyncDelaysStorage {
  AvSyncDelaysStore(this._storage);

  final PrivateJsonStorage _storage;

  @override
  Future<Map<String, int>> load() async =>
      sanitizeAvSyncDelays((await _storage.read())[avSyncDelaysKey]);

  @override
  Future<void> update(FutureOr<void> Function(Map<String, int> delays) mutate) {
    return _storage.mutate((json, {required bool present}) async {
      final delays = Map<String, int>.of(
        sanitizeAvSyncDelays(json[avSyncDelaysKey]),
      );
      await mutate(delays);
      json[avSyncDelaysKey] = delays;
    });
  }
}

/// 存取注入点（测试经内存私密 JSON 覆盖）。
final avSyncDelaysStorageProvider = Provider<AvSyncDelaysStorage>((ref) {
  return AvSyncDelaysStore(ref.watch(privateJsonStorageProvider));
});

/// 是否在启动时自动恢复持久化延迟（测试可关掉以隔离确定性初始态）。
final avSyncDelaysAutoRestoreProvider = Provider<bool>((ref) => true);

/// 音频输出设备控制器 seam：真实实现走平台通道
/// （Android `AudioManager.getDevices` 快照 + `AudioDeviceCallback`
/// 事件，枚举/路由监听无需权限）；非 Android/测试环境事件流静默无值
/// → 恒「其它设备」（设备识别仅 Android）。
abstract interface class AudioOutputDeviceController {
  /// 当前输出设备快照；识别失败返回 null（调用方兜底未知设备）。
  Future<AvSyncDeviceInfo?> get();

  /// 设备路由变化流（切蓝牙/插拔耳机等）；广播流，不缓存现值。
  Stream<AvSyncDeviceInfo?> get deviceStream;
}

/// 真实实现：平台通道 `dance_learning_app/audio_output_device`
/// （Android 原生见 `android/.../AudioOutputDevicePlugin.kt`）。
class PlatformAudioOutputDeviceController
    implements AudioOutputDeviceController {
  static const MethodChannel _channel = MethodChannel(
    'dance_learning_app/audio_output_device',
  );
  static const EventChannel _eventChannel = EventChannel(
    'dance_learning_app/audio_output_device_events',
  );

  @override
  Future<AvSyncDeviceInfo?> get() async {
    try {
      return AvSyncDeviceInfo.decode(
        await _channel.invokeMapMethod<String, Object?>('get'),
      );
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream {
    // 自管广播流包装：先探测方法通道（get）可用性——通道未注册（非
    // Android/测试环境）时 MissingPluginException 在此承接、不订阅事件
    // 通道（避免 stream 激活错误以平台异常冒泡），消费方零行为。
    late final StreamController<AvSyncDeviceInfo?> controller;
    StreamSubscription<dynamic>? subscription;
    controller = StreamController<AvSyncDeviceInfo?>.broadcast(
      onListen: () async {
        try {
          await _channel.invokeMapMethod<String, Object?>('get');
        } on Exception {
          return;
        }
        subscription = _eventChannel.receiveBroadcastStream().listen(
          (event) => controller.add(AvSyncDeviceInfo.decode(event)),
          onError: (Object _) {},
          cancelOnError: false,
        );
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}

/// 设备控制器注入点（测试注入 fake 记录/直呼模拟）。
final audioOutputDeviceControllerProvider =
    Provider<AudioOutputDeviceController>((ref) {
      return PlatformAudioOutputDeviceController();
    });

/// 音画同步会话状态（当前生效值 + 当前设备显示名）。
class AvSyncState {
  const AvSyncState({
    this.delayMs = 0,
    this.deviceKey = avSyncUnknownDeviceKey,
    this.deviceLabel = avSyncUnknownDeviceKey,
  });

  /// 当前设备的生效延迟（ms，正 = 声音晚到）。
  final int delayMs;

  /// 当前设备键（持久化定位）。
  final String deviceKey;

  /// 当前设备显示名（气泡读出）。
  final String deviceLabel;

  AvSyncState copyWith({int? delayMs, String? deviceKey, String? deviceLabel}) {
    return AvSyncState(
      delayMs: delayMs ?? this.delayMs,
      deviceKey: deviceKey ?? this.deviceKey,
      deviceLabel: deviceLabel ?? this.deviceLabel,
    );
  }
}

/// 音画同步模型：启动恢复、设备切换自动换值、值
/// 应用到媒体层引擎（视觉链不消费 Δ）。本模型不落盘：调节走校准会话
/// 控制器，「应用」由会话写存储并经 [adopt] 回写本模型。
class AvSyncModel extends Notifier<AvSyncState> {
  @override
  AvSyncState build() {
    // 设备路由监听：切换即换用对应设备的已存值（不写盘）。
    _deviceSubscription = ref
        .read(audioOutputDeviceControllerProvider)
        .deviceStream
        .listen((device) {
          if (device != null) _switchDevice(device);
        });
    ref.onDispose(() {
      unawaited(_deviceSubscription?.cancel());
      _deviceSubscription = null;
    });
    // 倍速变化边沿：媒体层 audio-delay 的 Δ·rate 换算在设值时刻取当时
    // 倍速，改倍速后需以当前 ms 重新应用。无偏移（0）时无需重应用。
    ref.listen(
      speedControlProvider.select((control) => control.effectiveRate),
      (previous, next) {
        if (previous == next || state.delayMs == 0) return;
        unawaited(_applyToEngine(state.delayMs));
      },
    );
    restoreDone = _initDevice().then((device) {
      if (device != null && ref.mounted) {
        state = state.copyWith(
          deviceKey: device.key,
          deviceLabel: device.label,
        );
      }
      // 通道 `get` 可能晚于 provider 销毁才返回：此后不得再读 ref。
      if (!ref.mounted) return null;
      if (!ref.read(avSyncDelaysAutoRestoreProvider)) {
        return null;
      }
      return _restore();
    });
    return const AvSyncState();
  }

  StreamSubscription<AvSyncDeviceInfo?>? _deviceSubscription;

  /// 启动恢复是否完成（测试等价「重启后读态」的同步点）。
  late Future<void> restoreDone;

  /// 当前输出设备快照（通道 `get`；识别失败/非 Android → null，保持
  /// 「其它设备」）。事件流负责后续路由变化。
  Future<AvSyncDeviceInfo?> _initDevice() async {
    try {
      return await ref.read(audioOutputDeviceControllerProvider).get();
    } on Exception {
      return null;
    }
  }

  Future<void> _restore() async {
    var disposed = false;
    ref.onDispose(() => disposed = true);
    // 存储不可用（测试壳无 path_provider 等）：兜底空表保持出厂 0，
    // 不以异步错误冒泡（practice_stats 文件解析同款降级口径）。
    var delays = const <String, int>{};
    try {
      delays = await ref.read(avSyncDelaysStorageProvider).load();
    } on Exception {
      return;
    }
    if (disposed) return;
    final ms = clampAvSyncMs(delays[state.deviceKey] ?? 0);
    if (ms == state.delayMs) return;
    state = state.copyWith(delayMs: ms);
    await _applyToEngine(ms);
  }

  /// 值应用到媒体层引擎（视觉链不消费 Δ，无需直推）。
  Future<void> _applyToEngine(int ms) async {
    try {
      await ref.read(playbackEngineProvider).setAvSyncDelayMs(ms);
    } on Exception {
      // 引擎不可用（测试壳无引擎覆盖等）：补偿不应用，不阻断会话。
    }
  }

  /// 设备切换：换用目标设备已存值（缺省 0）；不写盘
  /// （只有用户调节才落盘）。
  Future<void> _switchDevice(AvSyncDeviceInfo device) async {
    var delays = const <String, int>{};
    try {
      delays = await ref.read(avSyncDelaysStorageProvider).load();
    } on Exception {
      return;
    }
    if (!ref.mounted) return;
    final ms = clampAvSyncMs(delays[device.key] ?? 0);
    state = state.copyWith(
      deviceKey: device.key,
      deviceLabel: device.label,
      delayMs: ms,
    );
    await _applyToEngine(ms);
  }

  /// 采纳校准会话「应用」提交的当前设备延迟值：只更新播放侧状态；
  /// 落盘与引擎应用由会话控制器完成。
  void adopt(int ms) {
    state = state.copyWith(delayMs: clampAvSyncMs(ms));
  }
}

/// 音画同步注入点。
final avSyncProvider = NotifierProvider<AvSyncModel, AvSyncState>(
  AvSyncModel.new,
);
