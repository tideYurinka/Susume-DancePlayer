import 'dart:async';

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'av_sync_math.dart' show avSyncAudioDelaySeconds;
import 'display_aspect_ratio.dart';
import 'playback_engine.dart';

/// media_kit 适配器（ADR-0001）：mpv 内核，默认帧级精确 seek（hr-seek）、
/// `setRate` 支持任意倍速（0.1 步进轻而易举）。
///
/// 使用前提：在 main() 调用 [MediaKit.ensureInitialized]（幂等）。
///
/// 真机冒烟清单（打开视频 / 播放暂停 / seek / 倍速）见
///
/// 冒烟属真机步骤，不在无头测试环境跑真实解码。
class MediaKitPlaybackEngine implements PlaybackEngine {
  MediaKitPlaybackEngine() {
    _positionSubscription = _player.stream.position.listen((p) {
      // 快速寻址闭环：mpv 的 position 事件即「在途 seek 完成」信号。
      if (_fastBusy) _onFastCompleted();
      _position.add(p);
    });
    _playingSubscription = _player.stream.playing.listen(_playing.add);
    _completedSubscription = _player.stream.completed
        .where((completed) => completed)
        .listen((_) => _completed.add(null));
    _videoParamsSubscription = _player.stream.videoParams.listen((params) {
      // dw/dh 为像素校正后的宽高（不含旋转，旋转量单独给出）；缺失时退回
      // 原始 w/h。比例按显示朝向算，判据见 display_aspect_ratio.dart。
      _videoAspectRatio = displayAspectRatio(
        width: params.dw ?? params.w,
        height: params.dh ?? params.h,
        rotation: params.rotate,
      );
    });
  }

  final Player _player = Player();

  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();
  final StreamController<void> _completed = StreamController<void>.broadcast();
  final StreamController<bool> _playing = StreamController<bool>.broadcast();

  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<bool> _completedSubscription;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<VideoParams> _videoParamsSubscription;

  bool _disposed = false;
  double? _videoAspectRatio;

  @override
  double get rate => _player.state.rate;

  @override
  bool get isPlaying => _player.state.playing;

  @override
  Duration get position => _player.state.position;

  @override
  Duration? get duration {
    final value = _player.state.duration;
    // media_kit 未加载时为 Duration.zero，映射为“未知”。
    return value == Duration.zero ? null : value;
  }

  @override
  double? get videoAspectRatio => _videoAspectRatio;

  // demux-fps 暴露属 P1（Out of Scope：帧率不做自动探测）；
  // 现阶段恒 null → 调用侧回落默认 30fps。
  @override
  double? get videoFps => null;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Stream<bool> get isPlayingStream => _playing.stream;

  @override
  Future<void> open(Uri source, {bool play = false}) async {
    // Media 构造自动归一化：file:// 与绝对路径、Android content:// 均可。
    await _player.open(Media(source.toString()), play: play);
    // media_kit 在流/解复用就绪后异步填充 state.duration——open() 返回时
    // 时长常常仍为 null。此处有界等待其就绪，保证 open 返回后 [duration]
    // 可用（player_page 据此重建标注时间线；真机实测否则时间线停在零时长，
    // 分段/首尾工具全部失效）。本地文件通常毫秒级就绪；超时（如时长永不可知
    // 的异常源）则带 null 返回，标注工具保持禁用态（优雅降级）。
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline) && duration == null) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) async {
    _noteSeek(position);
    await _player.seek(position);
    // seek 完成后补发一次位置事件（对齐 FakePlaybackEngine.seek
    // 语义）——mpv 暂停态 seek 后 position 流可能不再自发更新，消费方
    // （数拍锚点切换的时钟对齐）依赖该事件落定。事件携带 seek
    // 目标而非 `state.position`——mpv seek 写入即返回，此刻内核态仍是
    // seek 之前的陈旧位置（lap 回跳实测 echo=99146 ≥ 段尾），会把刚起的
    // 循环前导判成「已出前导区」取消。
    _position.add(position);
  }

  // ---- 快速寻址（scrub 画面跟手）----
  //
  // media_kit 的 seek() 是假异步：mpv `seek absolute` 命令写入即返回
  // （实测 0–12ms），不等待寻址完成。上层 SerialSeekQueue 的 latest-wins
  // 「在途一条」门控因此失效——拖动（scrub）时以 10–30ms 间隔连发精确
  // seek，mpv 丢弃进行中的 seek（只生效突发首条），画面在拖动期间停格。
  //
  // 方案 C：seek 时间线上识别「拖动突发」——距上一条 seek <
  // [_fastSeekBurstWindow] 的后续 seek 视为拖动帧，期间把 mpv `hr-seek`
  // 切为 `no`（关键帧快速寻址，毫秒级、不丢弃，画面跟手）；拖动期间
  // **闭环派发**：同一时刻只在途一条 seek，待 mpv 报告该条完成（position
  // 事件）才派发「最新待发目标」——更新率自动锁定在内核真实完成节奏上，
  // 帧间隔均匀（开环定间隔派发会随跳变距离波动，实测帧率忽快忽慢）；
  // 超过 [_fastSeekStallTimeout] 无完成事件按超时续发兜底。突发静默
  // [_fastSeekSettleDelay] 后恢复默认精确寻址，并对最后一个拖动目标单发
  // 一次精确 seek 收尾（拖动落点只到最近关键帧，收尾保证帧级准确）。
  // 手势层与 seek 队列零改动，所有 seek 入口（全屏单/双指、控制层微调/
  // 横滑、轨道带预览条）自动覆盖。

  /// 判定「拖动突发」的相邻 seek 间隔上限。
  static const Duration _fastSeekBurstWindow = Duration(milliseconds: 300);

  /// 在途 seek 的完成事件等待上限（超时按已完成续发，防卡死）。
  static const Duration _fastSeekStallTimeout = Duration(milliseconds: 500);

  /// 突发静默多久后恢复精确寻址并收尾。
  static const Duration _fastSeekSettleDelay = Duration(milliseconds: 250);

  /// 当前是否处于快速寻址（hr-seek=no）。
  bool _fastSeekActive = false;

  /// 上一条 seek 的派发时刻（突发判定用）。
  DateTime? _lastSeekAt;

  /// 最后一个拖动目标（收尾精确 seek 用；非突发路径清除）。
  Duration? _lastFastTarget;

  /// 收尾定时器（每次拖动帧重置）。
  Timer? _fastSettleTimer;

  /// 在途期间到达的新目标（最新覆盖次新；在途完成即发它）。
  Duration? _pendingFastTarget;

  /// 是否有一条快速 seek 在途（未收到完成事件）。
  bool _fastBusy = false;

  /// 在途完成等待超时兜底。
  Timer? _fastStallTimer;

  /// mpv 命令串行链：属性切换与 seek 的多步序列按派发顺序执行，避免
  /// 「恢复精确」与「新的拖动帧切快速」交错时命令乱序。
  Future<void> _opChain = Future.value();

  void _noteSeek(Duration position) {
    final now = DateTime.now();
    final burst =
        _lastSeekAt != null &&
        now.difference(_lastSeekAt!) < _fastSeekBurstWindow;
    _lastSeekAt = now;
    _fastSettleTimer?.cancel();
    if (burst || _fastSeekActive) {
      _lastFastTarget = position;
      _fastSettleTimer = Timer(_fastSeekSettleDelay, _settleFastSeek);
    } else {
      _lastFastTarget = null;
    }
    if (burst || _fastSeekActive) {
      // 闭环：只记最新待发；在途空缺才立即派发。
      _pendingFastTarget = position;
      _pumpFastSeek();
      return;
    }
    _dispatchSeek(position, false);
  }

  /// 派发最新待发目标（在途空缺时）。
  void _pumpFastSeek() {
    if (_fastBusy || _disposed) return;
    final target = _pendingFastTarget;
    if (target == null) return;
    _pendingFastTarget = null;
    _fastBusy = true;
    _fastStallTimer?.cancel();
    _fastStallTimer = Timer(_fastSeekStallTimeout, _onFastStall);
    _dispatchSeek(target, true);
  }

  /// 在途 seek 完成（mpv position 事件）：释放忙位、续发最新待发。
  void _onFastCompleted() {
    if (!_fastBusy) return;
    _fastBusy = false;
    _fastStallTimer?.cancel();
    _fastStallTimer = null;
    _pumpFastSeek();
  }

  /// 完成事件超时：按已完成续发（mpv 暂停态可能不发 position 事件）。
  void _onFastStall() {
    _onFastCompleted();
  }

  void _dispatchSeek(Duration position, bool wantFast) {
    _opChain = _opChain.then((_) async {
      if (_disposed) return;
      if (wantFast != _fastSeekActive) {
        await _setHrSeek(wantFast);
        _fastSeekActive = wantFast;
      }
      await _player.seek(position);
      // 与 seek() 同一条修正——补发事件携带 seek 目标（快速寻址
      // 闭环上的同类补发），不携带内核态的陈旧位置。
      _position.add(position);
    });
  }

  /// 突发静默收尾：恢复精确寻址，并对最后一个拖动目标单发精确 seek。
  void _settleFastSeek() {
    _fastStallTimer?.cancel();
    _fastStallTimer = null;
    _pendingFastTarget = null;
    _fastBusy = false;
    final target = _lastFastTarget;
    _lastFastTarget = null;
    _opChain = _opChain.then((_) async {
      if (_disposed || !_fastSeekActive) return;
      await _setHrSeek(true);
      _fastSeekActive = false;
      if (target != null) {
        await _player.seek(target);
        // 收尾 seek 同口径——补发事件携带目标位置。
        _position.add(target);
      }
    });
  }

  /// 切换 mpv `hr-seek`：true = 默认（绝对寻址帧级精确）；false = no
  ///（关键帧快速寻址）。非 NativePlayer（如测试替身 platform）为 no-op。
  Future<void> _setHrSeek(bool exact) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    await platform.setProperty('hr-seek', exact ? 'default' : 'no');
  }

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setMuted(bool muted) =>
      // mpv/media_kit 的音量是 0–100 的百分比：静音即 0。
      _player.setVolume(muted ? 0 : 100);

  @override
  Future<void> setAvSyncDelayMs(int delayMs) {
    // media_kit Dart 面无 audio-delay API，走 NativePlayer.setProperty
    // （mpv 属性）：秒值 = −Δ·rate（负 = 延迟视频；墙钟延迟恒为 Δ，
    // 媒体偏移随倍速缩放），换算见 av_sync_math.dart。
    final native = _player.platform as NativePlayer;
    return native.setProperty(
      'audio-delay',
      avSyncAudioDelaySeconds(
        delayMs: delayMs,
        rate: _player.state.rate,
      ).toString(),
    );
  }

  @override
  Widget buildVideoSurface() => _MediaKitVideoSurface(engine: this);

  @override
  Future<void> dispose() async {
    if (_disposed) return; // 幂等
    _disposed = true;
    _fastSettleTimer?.cancel();
    await _positionSubscription.cancel();
    await _completedSubscription.cancel();
    await _playingSubscription.cancel();
    await _videoParamsSubscription.cancel();
    await _player.dispose();
    await _position.close();
    await _completed.close();
    await _playing.close();
  }
}

/// media_kit 画面控件：持有单个 [VideoController]（只在 initState 创建一次、跨
/// rebuild 复用，绝不进入 build 路径重建）。
class _MediaKitVideoSurface extends StatefulWidget {
  const _MediaKitVideoSurface({required this.engine});

  final MediaKitPlaybackEngine engine;

  @override
  State<_MediaKitVideoSurface> createState() => _MediaKitVideoSurfaceState();
}

class _MediaKitVideoSurfaceState extends State<_MediaKitVideoSurface> {
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  Future<void> _initController() async {
    final controller = VideoController(
      widget.engine._player,
      configuration: await _videoControllerConfiguration(),
    );
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      // 控制器异步创建期间（毫秒级）：纯黑占位，避免空控制器渲染。
      return const ColoredBox(color: Colors.black);
    }
    return Video(
      controller: controller,
      fit: BoxFit.contain,
      fill: Colors.black,
      controls: NoVideoControls,
    );
  }
}

/// media_kit 视频渲染配置。
///
/// hwdec 显式指定 `mediacodec`：默认 `auto-safe` 在部分真机上
/// 不启用 MediaCodec（拖动 seek 渲染延迟 ~300ms/帧、更新仅 ~3fps）；
/// 强制 mediacodec 后实测拖动更新 ~9fps（间隔 56–197ms）。失败时 mpv
/// 自动回落软解，无黑屏风险。
///
/// 模拟器特例（media-kit#1343，API 36 系统镜像实测）：新版 guest 侧 EGL
/// 拒绝 mpv 的 EGL 上下文创建（`EGL_BAD_ATTRIBUTE`，画面黑屏），任何宿主
/// GPU 设置都无法修复；改用 `vo=mediacodec_embed`（MediaCodec 解码并直接
/// 渲染进 Surface，完全绕开 EGL/GL 管线）。真机保持 vo=gpu（保留 GL 能力：
/// 截图/字幕/滤镜等）。
Future<VideoControllerConfiguration> _videoControllerConfiguration() async {
  if (!Platform.isAndroid) return const VideoControllerConfiguration();
  final info = await DeviceInfoPlugin().androidInfo;
  if (info.isPhysicalDevice) {
    return const VideoControllerConfiguration(hwdec: 'mediacodec');
  }
  return const VideoControllerConfiguration(
    vo: 'mediacodec_embed',
    hwdec: 'mediacodec',
  );
}
