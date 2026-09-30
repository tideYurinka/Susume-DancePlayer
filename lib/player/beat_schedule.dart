/// 排程消费 seam（本文件只有原生 sink 契约——`(拍点媒介时间, 段, 音量)`
/// 排程指令与消费接口；决策逻辑在节拍呈现对象 `beat_presentation.dart`）。
///
/// - **排程指令** [BeatScheduleCommand]：拍点媒介时间（已含音画同步与残差
///   补偿）+ 哑段 id（段表下标）+ 音量；决策不传段标记（标记是原生加载属
///   性），渲染器与原生只按段 id 查表。
/// - **排程消费 seam** [BeatScheduleConsumer]：深模块产出 → 消费者接口；
///   生产实现 = 原生排程渲染器（`native_scheduled_audio.dart` 经 ffi 下推
///   AAudio 低延迟流），测试注入 fake 断言「哪拍、何时、哪段、多大音量」。
/// - **排程消费 seam 注入点** [beatScheduleConsumerProvider]：生产实现 =
///   `native_scheduled_audio.dart` 的渲染器注入点。
///
/// 依赖方向：本文件 import 渲染器注入点所在的 `native_scheduled_audio.dart`、
/// 供原生 sink 打开用的 `beat_audio_native.dart`/`beat_audio_log.dart`、
/// 共享内核的时基同步值类型（`media_clock.dart`，只取值不取估计器）与
/// Riverpod，零 import 中枢。同域的
/// `native_scheduled_audio.dart` import 本文件的三个 seam 接口
/// （[BeatScheduleConsumer]/[BeatStreamControl]/[BeatAudioRendererLifecycle]）
/// ——契约与它在同域内的实现互相可见。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/media_clock.dart' show MediaClockSync;
import 'beat_audio_log.dart';
import 'beat_audio_native.dart';
import 'native_scheduled_audio.dart';

/// **前瞻窗**：游标推进的上界 = 估计当前媒介时间 + 本窗，
/// 把即将到达的拍提前交给原生按墙钟响（人耳不再听到一个位置事件间隔的
/// 固有延迟）。上界按**指令时刻**（拍点 − Δ·rate）取：正 Δ 的提前量
/// 由拍点窗整体前移承担（`beat_presentation` 的 `_BeatScanWindow`），本
/// 窗只量位置事件间隔与周期 top-up 粒度。
const Duration kMetronomeLookaheadWindow = Duration(milliseconds: 150);

/// 一条排程指令：拍点媒介时间 + 哑段 id + 音量。
class BeatScheduleCommand {
  const BeatScheduleCommand({
    required this.beatMediaTime,
    required this.segmentId,
    required this.volume,
  });

  /// 拍点媒介时间（音画同步延迟与残差已作偏移叠加：= 拍点 − Δ·rate − 残差）。
  final Duration beatMediaTime;

  /// 哑段 id（当前音源段表下标；渲染器与原生只按 id 查槽，不知道八拍 /
  /// 节拍 / 速度 / 回卷）。
  final int segmentId;

  /// 样本级响度（0.0–1.0，按段口径：含半拍响度拉平）。
  final double volume;

  @override
  bool operator ==(Object other) =>
      other is BeatScheduleCommand &&
      other.beatMediaTime == beatMediaTime &&
      other.segmentId == segmentId &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(beatMediaTime, segmentId, volume);

  @override
  String toString() =>
      'BeatScheduleCommand($beatMediaTime, $segmentId, $volume)';
}

/// 排程消费 seam：节拍音频深模块产出指令的唯一出口。
abstract interface class BeatScheduleConsumer {
  /// 排程一条指令（在 [BeatScheduleCommand.beatMediaTime] 消费）。返回
  /// 原生是否接受入队（入队失败由调用侧记一行诊断并按流记账触发自愈）。
  Future<bool> schedule(BeatScheduleCommand command);

  /// 丢弃全部未消费指令（暂停/退后台/不连续：错过的拍不补发）。
  Future<void> flush();
}

/// 流生命周期 seam：深模块对流对象的唯一操作面——**哑
/// 操作，无策略**（应活判定、自愈探测、冷却重试、重建预算、并发合流全在
/// 深模块内部）。生产实现 = 原生排程渲染器（转发原生 sink）；测试注入
/// fake 断言调用序列。
abstract interface class BeatStreamControl {
  /// 流是否已被系统错误关闭（拔耳机/路由切换/设备异常）。探测本身抛异常 =
  /// 句柄不可信，由模块按「已失效」处理（真机实测路径）。
  bool streamLost();

  /// 开流（含段资产就位）。失败抛异常，由模块记账并按冷却重试。
  Future<void> openStream();

  /// 停流（流不空耗；flush 未消费指令由模块经消费 seam 另行收口）。
  void stopStream();

  /// 重建原生流对象（旧对象被系统判失效后同流重开永远开不起来，换新对象
  /// 是唯一出路）；重建后按当前时间轴源重立原生锚，重建后的第一拍才落得
  /// 下去。
  Future<void> rebuildTransport();

  /// 单调毫秒（冷却计时；与原生同一 CLOCK_MONOTONIC 时基）。
  int monotonicMs();
}

/// 渲染器时基 seam：深模块对接当前渲染器的哑渲染面（媒介时刻配对下推 +
/// 会话边沿）。生产实现 = 原生排程渲染器（`BeatAudioRenderer`，
/// `native_scheduled_audio.dart`）；测试注入 fake 断言调用序列。渲染器
/// 保持哑渲染：只收 seam 调用、不读设置/信号、不做任何时间估计——
/// 「现在」全仓只有节拍呈现那一份外推。
abstract interface class BeatAudioRendererLifecycle {
  /// 时基下推（配对）：媒介时刻取自节拍呈现的唯一
  /// 外推（[MediaClockSync.mediaTimeMs]），倍速与播放态随同一份外推同源；
  /// 配对的另一半 = 原生自己的帧位，由原生在收到本下推时现取。渲染器
  /// 原样转发原生 sink，不做锚采纳、不做外推。
  void onMediaNow(MediaClockSync sync);

  /// 校准会话模式：进入 = flush 旧锚 + 会话时钟锚
  /// 重立（会话时间轴 → 原生帧位，速率 1、playing 真）；退出 = 清锚 + flush。
  Future<void> onCalibrationSession(bool active);
}

/// 排程消费 seam 注入点：生产实现 = 原生渲染器适配（节拍声的
/// 唯一发声出口）；测试注入 fake 断言「哪拍、何时、哪段、多大音量」。
final beatScheduleConsumerProvider = Provider<BeatScheduleConsumer>((ref) {
  return ref.watch(beatAudioRendererProvider);
});

/// 原生 sink 打开（dart:ffi + AAudio）；非 Android 宿主/加载失败回退哑
/// sink（不发声，播放链路不受阻；纪律真机回归确认原生路径）。
///
/// 「哑 sink 不留无声的永久降级」：回退**必须留日志**（含
/// 原因），现场可据单 tag 查证「开着却不响」是否走的是这条路径。
BeatAudioSink? openNativeBeatAudioSink() {
  try {
    return BeatAudioNative.open();
  } on Object catch (error) {
    beatAudioLog('原生渲染器不可用（$error）：回退哑 sink，本次进程不发声');
    return null;
  }
}
