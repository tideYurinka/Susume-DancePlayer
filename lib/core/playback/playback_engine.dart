import 'package:flutter/widgets.dart';

/// 播放内核抽象（PlaybackEngine）。
///
/// App 的播放依赖全部经由该接口（ADR-0001 据此选用 media_kit 作为真实内核）：
/// 打开视频、播放/暂停、帧级 seek（hr-seek）、任意倍速（setRate）、
/// position 流、播放完成事件、dispose。
///
/// 测试注入 [FakePlaybackEngine]（`test/helpers/fake_playback_engine.dart`），
/// 不依赖真实解码；好测试的标准是只观察本接口可观测的状态与事件
/// （position、完成事件、rate）。
///
/// 行为契约（doc 收编，不加 API）：
/// - [open] 返回后 [duration] 应可用（真实内核有界等待 media_kit 解析就绪；
///   异常源超时则带 `null` 返回、调用侧优雅降级）。
/// - [positionStream] 节拍 ≈100ms × rate（真实内核按底层回调转发，
///   测试内核按定时器推进）；消费者（如 PlaybackLoopLayer 的区间循环
///   seek 容忍）据此设定容忍度，不得假设更细粒度。
///
/// AB/学习段区间循环薄层（监听 position 到 B 点帧级 seek 回 A）在
/// `playback_loop_layer.dart` 里实现，不进本接口。
///
/// 渲染接缝（候选 3）：各 adapter 经 [buildVideoSurface] 自供画面
/// 控件，消费方 widget 只认识本接口、不做具体内核类型分支。
abstract interface class PlaybackEngine {
  /// 打开 [source] 并准备播放；[play] 为 true 时打开即开始播放。
  ///
  /// [source] 支持本地文件路径（`file://` 或绝对路径）与 Android
  /// `content://` URI。
  Future<void> open(Uri source, {bool play = false});

  Future<void> play();

  Future<void> pause();

  /// 帧级 seek（hr-seek）到 [position]（毫秒级；mpv 按帧对齐）。
  ///
  /// 越界目标（< 0 或 > 时长）由实现钳制到 `[0, duration]`；widget 手势层
  /// 也会先钳制再调用（进度手势）。
  ///
  /// seek 完成后补发一次 position 事件（暂停态同样更新；对齐
  /// FakePlaybackEngine 语义——真实内核暂停态 position 流可能不再自发
  /// 更新，消费方依赖该事件落定）。该事件携带 [position]（seek
  /// 目标），不携带内核态的陈旧位置——任何消费方都不得被 seek 前的旧
  /// 位置误导。
  Future<void> seek(Duration position);

  /// 设置任意倍速（mpv 实际范围 ≈0.01–100；UI 侧按 0.1 步进约束）。
  Future<void> setRate(double rate);

  /// 音画同步：按「声音晚到 Δ（正 ms）→ 延迟视频对齐声音」
  /// 应用媒体层音视频偏移（media_kit `NativePlayer.setProperty(
  /// 'audio-delay', …)`，取 mpv 负值语义 = 延迟视频）；符号以真机听感
  /// 校准为准。Δ 只由声音侧与媒体层消费（浮层与刻度不平移）。
  Future<void> setAvSyncDelayMs(int delayMs);

  double get rate;

  bool get isPlaying;

  /// isPlaying 边沿流（练舞统计的播放边沿来源）：每次播放态
  /// 变化发出一次（开始/暂停/到尾停止/打开重置）。广播流，不缓存现值，
  /// 消费方以边沿为准、不依赖订阅瞬间的补发。
  Stream<bool> get isPlayingStream;

  /// 当前播放位置（同步读取；进度手势 seek 的基准位置）。
  ///
  /// 与 [positionStream] 同源（media_kit `Player.state.position`），
  /// 未打开时为 `Duration.zero`。
  Duration get position;

  /// 当前视频时长；未打开或未知时为 `null`。
  Duration? get duration;

  /// 视频画面宽高比（宽 / 高，含像素校正与**显示朝向**）；未打开或未知时
  /// 为 `null`。显示朝向 = 编码宽高按旋转元数据换算后用户在屏幕上看到的
  /// 朝向（横向编码 + 旋转元数据的竖屏素材即此类），与实际画面同源。
  ///
  /// 渲染层据此做 contain 布局（竖屏源视频横屏时两侧留黑、不裁剪）；
  /// 未知时回退为填满可用区域、由内核自行 contain。
  double? get videoAspectRatio;

  /// 视频帧率（demux-fps，帧/秒）；适配层取不到时为 `null` → 调用侧
  /// 回落默认 30fps 常量（帧显示；帧号时间文本与帧步进共用）。
  double? get videoFps;

  /// position 流：播放期间持续发出当前播放位置。
  Stream<Duration> get positionStream;

  /// 播放完成事件：每次播放到尾发出一次。
  Stream<void> get completedStream;

  /// 释放底层资源；之后不应再调用任何方法。
  Future<void> dispose();

  /// 构建视频画面控件（渲染接缝）。
  ///
  /// 各 adapter 自供渲染：
  /// - 真实内核（media_kit）→ 其 `Video`（media_kit_video）控件：填满可用
  ///   区域，contain 与旋转元数据由 media_kit 内部处理（竖屏源横屏时两侧
  ///   留黑、不裁剪），外层不再叠 AspectRatio。
  /// - 其他内核（测试 `FakePlaybackEngine`）→ 按 [videoAspectRatio] 用
  ///   Center + AspectRatio 约束的带 key 占位控件（contain 语义）；
  ///   宽高比未知时填满可用区域。
  ///
  /// 契约：
  /// - 返回的控件跨 widget rebuild 复用内部资源：真实内核的 VideoController
  ///   只在控件 State 的 initState 创建一次、绝不进入 build 路径重建。
  /// - 镜像翻转由消费方对返回控件做水平 Transform，本方法
  ///   不感知镜像。
  Widget buildVideoSurface();
}
