import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player_session/player_session.dart' show playerSessionProvider;
import 'brightness.dart';
import 'cast_run.dart' show castRunProvider;
import 'cast_volume.dart' show CastAwareSystemMediaVolumeController;
import 'system_volume.dart';

/// 屏幕亮度控制注入点（左半屏上下滑调亮度）：真实实现走
/// screen_brightness 应用级亮度；测试注入 fake 断言调用（见
/// `test/helpers/fake_brightness.dart`）。
final screenBrightnessControllerProvider = Provider<ScreenBrightnessController>(
  (ref) => const SystemScreenBrightnessController(),
);

/// 系统媒体音量控制注入点（右半屏上下滑调系统媒体音量）：
/// 真实实现走平台通道（AudioManager STREAM_MUSIC，与侧键同源）；测试注入
/// fake 断言调用（见 `test/helpers/fake_system_volume.dart`）。
///
/// **生产的手势音量走下面那条**（[gestureVolumeControllerProvider]，按会话模式
/// 分派）；这一条在生产路径上只剩「本机那一半」——它被手势那条包在里面用，
/// 其余消费者是测试里的 override（那些用例验的是非投屏行为，不受分派影响）。
/// 两条并存的理由见 `cast_volume.dart` 的库头：收成一条要同时改动一批既有
/// 用例的注入面，收益只是少一层 Provider。
final systemMediaVolumeControllerProvider =
    Provider<SystemMediaVolumeController>(
      (ref) => PlatformSystemMediaVolumeController(),
    );

/// 手势用的音量控制器（[LevelControl] 的注入点）：**按会话模式分派**——投屏
/// 态读写接收端（投屏会话的 `setVolume` / 起投探测读到的上报值），其余读写
/// [systemMediaVolumeControllerProvider]（本机系统媒体音量，行为逐位不变）。
/// 手势层只认这一条接缝（`player_page.dart` 把它交给 `LevelControl`），不新起
/// 第二条写入支路。
final gestureVolumeControllerProvider = Provider<SystemMediaVolumeController>(
  (ref) => CastAwareSystemMediaVolumeController(
    local: ref.watch(systemMediaVolumeControllerProvider),
    isCasting: () => ref.read(playerSessionProvider).isCast,
    cast: ref.read(castRunProvider.notifier),
  ),
);

/// 亮度与音量域：自持这两个调节量的初始化、取值维护与写入
/// 路径，宿主只启动会话、把纵向手势增量交给它。
///
/// - [start]：读取当前应用亮度与系统媒体音量为手势基准，并订阅系统媒体
///   音量变化流（侧键等应用外来源）——基线读取晚于外部流事件时让位，
///   读取失败保持默认（不阻塞播放）；
/// - [adjustBrightness] / [adjustVolume]：把纵向像素增量按手势作用区高度
///   归一化并累加到当前值（钳 0..1），随后写回对应系统面；返回值供手势
///   反馈层显示滑条填充。音量写入失败静默（平台通道未注册的测试环境），
///   亮度写入照既有路径不吞错；
/// - [adoptReportedVolume] / [refreshVolume]：会话模式切换时重取音量基准
///   （投屏态取**接收端上报**的音量，见 `cast_volume.dart` 的
///   `CastAwareSystemMediaVolumeController`）；
/// - [dispose]：取消音量流订阅。
///
/// **「音量这一项显不显示」不在这里**（票 #38）：遥控项的显示由投屏域的能力
/// 判据一处回答（`cast_session.dart` 的 `CastRemoteControls.shows`）。本域只管
/// **取值**——接收端报得上（[adoptReportedVolume] 给值）就把上报值当基准，
/// 读不到就保持现值、不显示 0；界面那边不再读本域另判一遍。
///
/// 单向依赖：本域只依赖两个接缝接口（[ScreenBrightnessController] /
/// [SystemMediaVolumeController]），不读构建上下文、不碰容器中枢。
class LevelControl {
  LevelControl({
    required this._brightnessController,
    required this._volumeController,
  });

  final ScreenBrightnessController _brightnessController;
  final SystemMediaVolumeController _volumeController;

  StreamSubscription<double>? _volumeSubscription;

  /// 应用亮度（0..1）：初始自控制器读取，手势按增量更新后回写。
  double _brightness = 1.0;

  /// 系统媒体音量（0..1 归一化）：初始自系统读取，手势按增量更新后回写；
  /// 侧键等应用外变化经 [SystemMediaVolumeController.volumeStream] 同步。
  double _volume = 1.0;

  /// 基线已就位标记：首个 volumeStream 事件（侧键等外部变化）先于异步
  /// 基线读取到达时，跳过基线写入——外部新值不被读取返回的陈旧值覆盖。
  bool _volumeBaselineReady = false;

  /// 会话已收尾：异步基线读取晚于 [dispose] 返回时不再写取值（既有
  /// 「widget 已卸载则不写」的生命周期口径）。
  bool _disposed = false;

  /// 当前应用亮度（0..1）。
  double get brightness => _brightness;

  /// 当前系统媒体音量（0..1）。
  double get volume => _volume;

  /// 本次手势会话的起手快照：首次调节动作时记录当时的取值，取消收尾写回；
  /// null = 本会话未产生过该轴的调节动作。
  double? _gestureBrightness;
  double? _gestureVolume;

  /// 会话启动：读取两个基线并开始跟随系统媒体音量的应用外变化。
  void start() {
    unawaited(_initBrightness());
    unawaited(_initVolume());
    _volumeSubscription = _volumeController.volumeStream.listen(
      (value) {
        _volume = value;
        _volumeBaselineReady = true;
      },
      // 平台通道未注册（非 Android/测试环境）时静默：基线读取失败同样
      // 兜底，不阻塞播放。
      onError: (Object _) {},
    );
  }

  /// 会话模式切换时更新音量基准（票 #38）。**投屏态**传起投探测那一次读到的
  /// 接收端上报值（`cast_run.dart` 的 `CastRunState.reportedVolume`）——它与
  /// 「音量遥控项显不显示」出自同一次探测，于是屏上的读数与那一项的在不在
  /// 不会互相打脸；没有可用的上报值（没端点 / 设备不答 / 非投屏）时传 null，
  /// 退到 [refreshVolume] 按当前会话模式读一次控制器（非投屏 = 本机系统媒体
  /// 音量，行为逐位不变）。
  ///
  /// 读出结果一律**只更新取值**：读失败保持现值（不是显示一个 0），可不可
  /// 显示由投屏域那一条判据回答。
  Future<void> adoptReportedVolume(double? reported) async {
    if (_disposed) return;
    if (reported == null) return refreshVolume();
    _volume = reported.clamp(0.0, 1.0);
    _volumeBaselineReady = true;
  }

  /// 重新读一次音量基准（**会话模式切换时**调用，票 #38）：投屏态下控制器
  /// 读的是**接收端上报**的音量，非投屏读的是本机系统媒体音量——进投屏态
  /// 与断开投屏各走一次，屏上的读数才跟着「现在是谁在出声」走。
  ///
  /// 读取失败（平台通道未注册的测试环境 / 接收端不报音量）：保持现值，
  /// 不阻塞手势、也不显示一个 0。
  Future<void> refreshVolume() async {
    try {
      final value = await _volumeController.volume;
      if (_disposed) return;
      _volume = value.clamp(0.0, 1.0);
      _volumeBaselineReady = true;
    } on Object {
      // 保持现值：显示面（音量滑条）取的就是这个值。
    }
  }

  /// 应用纵向增量并写回应用亮度；返回写入后的值（0..1）。写入排在调用方
  /// 呈现调节反馈之后（微任务），与既有「反馈先于写入」次序一致。
  double adjustBrightness({
    required double deltaPx,
    required double areaHeight,
  }) {
    _gestureBrightness ??= _brightness;
    _brightness = _advance(_brightness, deltaPx, areaHeight);
    final value = _brightness;
    scheduleMicrotask(() => _brightnessController.setBrightness(value));
    return value;
  }

  /// 应用纵向增量并写回系统媒体音量；返回写入后的值（0..1）。写入排在
  /// 调用方呈现调节反馈之后（微任务），与既有「反馈先于写入」次序一致。
  double adjustVolume({required double deltaPx, required double areaHeight}) {
    _gestureVolume ??= _volume;
    _volume = _advance(_volume, deltaPx, areaHeight);
    final value = _volume;
    scheduleMicrotask(() => _writeVolume(value));
    return value;
  }

  /// 手势会话收尾：[cancel] 为真时把首次调节动作前快照的亮度与音量写回
  /// 对应系统面（值未变化不重复写）；本会话
  /// 未产生过调节动作、未开会话或重复收尾均 no-op。写回走既有写面——亮度
  /// 与音量仍然只有这一个写者。
  void endGestureSession({required bool cancel}) {
    final brightness = _gestureBrightness;
    final volume = _gestureVolume;
    _gestureBrightness = null;
    _gestureVolume = null;
    if (!cancel) return;
    if (brightness != null && _brightness != brightness) {
      _brightness = brightness;
      scheduleMicrotask(() => _brightnessController.setBrightness(brightness));
    }
    if (volume != null && _volume != volume) {
      _volume = volume;
      scheduleMicrotask(() => _writeVolume(volume));
    }
  }

  void dispose() {
    _disposed = true;
    _volumeSubscription?.cancel();
    _volumeSubscription = null;
  }

  /// 把纵向像素增量按作用区高度归一化并累加到 [current]（整屏高度 ≈ 满量程）。
  double _advance(double current, double deltaPx, double areaHeight) {
    final delta = deltaPx / areaHeight;
    return (current + delta).clamp(0.0, 1.0);
  }

  Future<void> _writeVolume(double value) async {
    try {
      await _volumeController.setVolume(value);
    } on Object {
      // 平台通道未注册（非 Android/测试环境）静默：与基线读取/流订阅同一
      // 兜底口径，调节反馈已先于写入呈现。
    }
  }

  /// 读取当前应用亮度作为手势基准；读取失败或会话已收尾保持默认
  /// （不阻塞播放）。
  Future<void> _initBrightness() async {
    try {
      final value = await _brightnessController.brightness;
      if (_disposed) return;
      _brightness = value.clamp(0.0, 1.0);
    } on Object {
      // 保持默认亮度。
    }
  }

  /// 读取当前系统媒体音量作为手势基准（打开视频/切歌基线取自系统媒体
  /// 音量）；读取失败保持默认（不阻塞播放）。
  Future<void> _initVolume() async {
    try {
      final value = await _volumeController.volume;
      if (_disposed) return;
      if (!_volumeBaselineReady) _volume = value.clamp(0.0, 1.0);
    } on Object {
      // 保持默认音量。
    } finally {
      _volumeBaselineReady = true;
    }
  }
}
