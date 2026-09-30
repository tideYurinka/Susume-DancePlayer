import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../beat_track_state/beat_track_state.dart' show beatGridProvider;
import '../core/beat_grid.dart' show BeatGrid, BeatGridReads;
import '../core/playback/playback_engine.dart' show PlaybackEngine;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'av_sync.dart';
import 'calibration_session_grid.dart'
    show CalibrationSessionBpmTier, CalibrationSessionGrid;

/// 音画同步校准会话状态：会话活跃态 + 会话试听值 Δ（内存态）+ BPM
/// 档位（会话参数）+ 设备切换提示 + 刻度带重启记号。
class AvSyncCalibrationSessionState {
  const AvSyncCalibrationSessionState({
    this.active = false,
    this.trialMs = 0,
    this.tier = CalibrationSessionBpmTier.bpm120,
    this.deviceKey = avSyncUnknownDeviceKey,
    this.deviceLabel = avSyncUnknownDeviceKey,
    this.notice,
    this.restartToken = 0,
  });

  /// 会话是否活跃（打开「音画同步」工具即进入）。
  final bool active;

  /// 会话试听值 Δ（ms，正 = 声音晚到）；只在会话内存活，应用才落盘。
  final int trialMs;

  /// 会话 BPM 节奏档（歌曲节拍/120/160；会话参数，与 active/trialMs 同
  /// 生命周期）。决策层按拍读取，换档自下一拍生效；设备切换重置不清档。
  final CalibrationSessionBpmTier tier;

  /// 当前设备键（应用时的写入目标）。
  final String deviceKey;

  /// 当前设备显示名（切换提示/设备名读出）。
  final String deviceLabel;

  /// 短暂提示文案（设备切换「输出设备已切换为 X」；null = 无提示）。
  final String? notice;

  /// 刻度带重启记号（会话进入与设备切换自增；气泡侧据此重启闪亮）。
  final int restartToken;

  AvSyncCalibrationSessionState copyWith({
    bool? active,
    int? trialMs,
    CalibrationSessionBpmTier? tier,
    String? deviceKey,
    String? deviceLabel,
    String? notice,
    int? restartToken,
  }) {
    return AvSyncCalibrationSessionState(
      active: active ?? this.active,
      trialMs: trialMs ?? this.trialMs,
      tier: tier ?? this.tier,
      deviceKey: deviceKey ?? this.deviceKey,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      notice: notice,
      restartToken: restartToken ?? this.restartToken,
    );
  }
}

/// 音画同步校准会话控制器：打开「音画同步」即进入——暂停播放
/// （记住进入前播放态、退出还原，暂停沿即触发既有显式停声纪律）、初始
/// 试听值 = 当前设备记忆值（未校准 = 0）；试听值变更零写盘零引擎应用；
/// 「应用」才经 [AvSyncDelaysStorage] 恰好一次写当前设备键 + 引擎值更新
/// + 退出还原播放。取消 / 关闭气泡 / 切其它工具 / 退后台 / 会话中手动
/// 恢复播放均丢弃试听值并还原。会话中输出设备切换 → 会话随新设备重置
/// （试听值复位为新设备记忆值、重启记号自增）并提示。无闲置超时。
///
/// 本类是**自足会话状态模块**：持有会话活跃态、试听值、BPM 档位、视觉
/// 脉冲出口（[beatPulse]——节拍音频深模块每产出一条会话拍指令经页面
/// 接线点火一次，刻度带与发声同一拍点时刻表、同一拍序）。会话发声决策
/// （拍序、档位生效、进出场纪律）收在节拍音频深模块内：
/// 进/出经页面哑转发走深模块 [setCalibrationSession] 入口
/// （本控制器只翻会话状态，活跃/重启记号变化即进/出场）。会话滴答不经
/// 「声音反馈」总开关（深模块结构性例外）。
class AvSyncCalibrationSessionModel
    extends Notifier<AvSyncCalibrationSessionState> {
  @override
  AvSyncCalibrationSessionState build() {
    // 会话中手动恢复播放 = 放弃未应用调整并退出；退出后
    // 的播放沿（应用还原播放）不再触发。
    _playingSubscription = ref
        .read(playbackEngineProvider)
        .isPlayingStream
        .listen((playing) {
          if (playing && state.active) {
            _exit(restorePlaying: false);
          }
        });
    // 会话中输出设备切换 → 会话随新设备重置。非会话期的
    // 设备换值由 [AvSyncModel] 负责，本控制器仅在活跃期消费事件。
    _deviceSubscription = ref
        .read(audioOutputDeviceControllerProvider)
        .deviceStream
        .listen((device) {
          if (device != null && state.active) {
            unawaited(_resetForDevice(device));
          }
        });
    // 渲染器随生效音源 seam（设置槽 + 会话回落普通）变化重建：实例一变
    // 即 re-arm（先 flush 旧实例、再接线新实例），会话滴答不因渲染器换
    // 实例而失联。检测走 tick 现读（不建编译期依赖——
    // 渲染器 provider 链 watch 本会话活跃态，build 期 listen 即循环）。
    ref.onDispose(() {
      unawaited(_playingSubscription?.cancel());
      unawaited(_deviceSubscription?.cancel());
      unawaited(_beatPulse.close());
      _playingSubscription = null;
      _deviceSubscription = null;
    });
    return const AvSyncCalibrationSessionState();
  }

  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<AvSyncDeviceInfo?>? _deviceSubscription;

  /// 进入前播放态（退出还原）。
  bool _initialPlaying = false;

  /// 应用落盘链尾（测试「恰好一次写」同步点）。
  Future<void> _applyChain = Future<void>.value();

  /// 最近一次应用是否完成（测试同步点：await 后写与引擎更新必已落定）。
  Future<void> get applyDone => _applyChain;

  /// 会话拍视觉脉冲出口（broadcast）：节拍音频深模块每产出一条会话拍
  /// 指令经页面接线点火一次；刻度带订阅消费，与发声同一拍点时刻表、
  /// 同一拍序。
  final StreamController<void> _beatPulse = StreamController<void>.broadcast();

  /// 视觉脉冲订阅口（气泡刻度带；纯渲染，不持会话逻辑）。
  Stream<void> get beatPulse => _beatPulse.stream;

  /// 会话拍脉冲点火（页面自深模块接线转发；模块外唯一入口）。
  void fireBeatPulse() {
    if (!_beatPulse.isClosed) {
      _beatPulse.add(null);
    }
  }

  /// 会话网格决策层的档位默认值依据（有已对齐网格 = 歌曲节拍，否则回落
  /// 120；进入与退出复位共用）。
  CalibrationSessionBpmTier get _defaultTier =>
      CalibrationSessionGrid.isTierAvailable(
        CalibrationSessionBpmTier.song,
        _songGrid(),
      )
      ? CalibrationSessionBpmTier.song
      : CalibrationSessionBpmTier.bpm120;

  AvSyncDelaysStorage get _storage => ref.read(avSyncDelaysStorageProvider);

  PlaybackEngine get _engine => ref.read(playbackEngineProvider);

  /// 已对齐歌曲节拍网格（歌曲档间隔来源；不可用 = null）。
  ///
  /// 严格读法：真实拍点可用才取（[BeatGridReads.hasRealBeats]）——
  /// 「就绪但 beat 段为空」的潜伏态（App 自身写入路径产不出，只有手改或
  /// 分享来的标记文件会有）会把映射点回落出的占位均匀网格当歌曲节拍
  /// 网格。
  BeatGrid? _songGrid() => ref.read(beatGridProvider).hasRealBeats
      ? ref.read(beatGridProvider)
      : null;

  /// 进入会话：暂停被调 + 初始试听值 = 当前设备记忆值（未校准 = 0）。
  /// 已活跃时 no-op（不重暂停、不重置试听值）。设备快照取数期间若有
  /// 路由切换事件，事件回调因会话尚未活跃而被丢弃——建会话后重读一次
  /// 设备快照，落后即走设备重置口径（消除 enter 竞态窗口）。
  Future<void> enter() async {
    if (state.active || !ref.mounted || _enterInFlight) return;
    _enterInFlight = true;
    _exitDuringEnter = false;
    try {
      _initialPlaying = _engine.isPlaying;
      final device =
          await ref.read(audioOutputDeviceControllerProvider).get() ??
          const AvSyncDeviceInfo.unknown();
      if (_enterInterrupted()) {
        _initialPlaying = false;
        return;
      }
      final ms = await _storedMs(device.key);
      if (_enterInterrupted()) {
        _initialPlaying = false;
        return;
      }
      state = state.copyWith(
        active: true,
        trialMs: ms,
        tier: _defaultTier,
        deviceKey: device.key,
        deviceLabel: device.label,
        restartToken: state.restartToken + 1,
      );
      // 建会话后复检设备：快照已过期（取数期间路由切换）→ 随新设备重置。
      final latest = await ref.read(audioOutputDeviceControllerProvider).get();
      if (latest != null && latest.key != state.deviceKey && ref.mounted) {
        await _resetForDevice(latest);
      }
      if (_initialPlaying) {
        await _engine.pause();
      }
    } finally {
      _enterInFlight = false;
      _exitDuringEnter = false;
    }
  }

  /// 进入流程在途标记（设备快照 + 存储读的 async 窗口）。
  bool _enterInFlight = false;

  /// 进入完成前收到退出请求（点开即点空白）：进入收尾检测即放弃——
  /// 不置活跃、不暂停、不遗留活跃会话。
  bool _exitDuringEnter = false;

  /// 进入流程是否已被打断（未挂载 / 已活跃——进入收尾期间被正常退出
  /// 赶先 / 进入期间收到退出请求）。为真时放弃进入：不置活跃、不暂停、
  /// 清除进入前播放态记忆（此时尚未暂停，无还原可言）。
  /// 已活跃后才到的退出走正常 `_exit`：终态一致，
  /// enter 尾段不再复检。
  bool _enterInterrupted() => !ref.mounted || state.active || _exitDuringEnter;

  /// 会话节奏档意图（气泡 BPM 快选）：写入会话 state（气泡按钮读
  /// `state.tier`）；深模块会话拍序按当拍读取档间隔，变更自下一拍生效。
  /// 非活跃期为 no-op（档位是会话参数）。
  void setTier(CalibrationSessionBpmTier tier) {
    if (!state.active || tier == state.tier) return;
    state = state.copyWith(tier: tier);
  }

  /// 会话试听值直接设值（滑条；越界钳制）。零写盘、零引擎应用。
  void setTrialMs(int ms) {
    if (!state.active) return;
    state = state.copyWith(trialMs: clampAvSyncMs(ms));
  }

  /// 会话试听值增量调节（−/＋ 细调，UI 单步传 ±[kAvSyncStepMs]）。
  void stepBy(int deltaMs) => setTrialMs(state.trialMs + deltaMs);

  /// 试听值重置归 0（会话内存态，不落盘）。
  void reset() => setTrialMs(0);

  /// 应用：把试听值保存为当前输出设备的延迟记忆值（恰好一次写当前设备
  /// 键）+ 引擎值更新 + 播放侧模型采纳 + 退出还原进入前播放态。
  Future<void> apply() async {
    if (!state.active) return;
    final key = state.deviceKey;
    final ms = state.trialMs;
    _applyChain = _applyChain.then((_) async {
      // 键/值在调用时点捕获：链上若晚于设备切换执行，不误写新设备键。
      await _storage.update((delays) async => delays[key] = ms);
      if (!ref.mounted) return;
      await _applyToEngine(ms);
      // 播放侧采纳同样只对捕获时点的设备生效：链执行时设备已切走则
      // 不回写（新设备记忆值不被旧设备试听值覆盖，播放侧换值由
      // [AvSyncModel] 的设备事件订阅负责）。
      if (ref.read(avSyncProvider).deviceKey == key) {
        ref.read(avSyncProvider.notifier).adopt(ms);
      }
    });
    _exit(restorePlaying: true);
  }

  /// 取消（空白关闭 / 收起气泡 / 互斥切其它工具 / 退后台同口径）：丢弃
  /// 试听值退出，零写盘。进入流程在途时收到 → 置位进入打断标记，进入
  /// 收尾检测即放弃（竞态守卫）。
  Future<void> cancel() async {
    if (!state.active) {
      if (_enterInFlight) _exitDuringEnter = true;
      return;
    }
    _exit(restorePlaying: true);
  }

  /// 退出会话；[restorePlaying] 为真时还原进入前播放态（进入前在播且
  /// 当前未播 → 续播；原本暂停则保持暂停）。先置非活跃，再还原播放——
  /// 退出后的 isPlaying 真边沿不再被当作「手动恢复播放」。渲染器会话
  /// 模式停用（flush + 停流）与播放侧重锚由页面哑转发经深模块
  /// [setCalibrationSession] 入口随活跃沿在此触发，不依赖视图卸载时序。
  void _exit({required bool restorePlaying}) {
    final resume = restorePlaying && _initialPlaying;
    _initialPlaying = false;
    state = state.copyWith(active: false, trialMs: 0, tier: _defaultTier);
    if (resume && !_engine.isPlaying) {
      unawaited(_engine.play());
    }
  }

  /// 设备切换重置：试听值复位为新设备记忆值（未校准 = 0）+ 重启记号自增
  /// + 提示；不写任何设备键。会话发声侧（渲染器会话锚重立、会话拍游标
  /// 重置）由页面哑转发随重启记号走深模块会话入口。
  Future<void> _resetForDevice(AvSyncDeviceInfo device) async {
    final ms = await _storedMs(device.key);
    if (!ref.mounted || !state.active) return;
    state = state.copyWith(
      trialMs: ms,
      deviceKey: device.key,
      deviceLabel: device.label,
      notice: '输出设备已切换为 ${device.label}',
      restartToken: state.restartToken + 1,
    );
  }

  /// 读取设备已存延迟；存储不可用兜底 0（不以异步错误冒泡）。
  Future<int> _storedMs(String deviceKey) async {
    var delays = const <String, int>{};
    try {
      delays = await _storage.load();
    } on Exception {
      return 0;
    }
    return clampAvSyncMs(delays[deviceKey] ?? 0);
  }

  Future<void> _applyToEngine(int ms) async {
    try {
      await _engine.setAvSyncDelayMs(ms);
    } on Exception {
      // 引擎不可用（测试壳无引擎覆盖等）：补偿不应用，不阻断会话。
    }
  }
}

/// 校准会话注入点（测试注入 fake 播放/存储/设备事件）。
final avSyncCalibrationSessionProvider =
    NotifierProvider<
      AvSyncCalibrationSessionModel,
      AvSyncCalibrationSessionState
    >(AvSyncCalibrationSessionModel.new);
