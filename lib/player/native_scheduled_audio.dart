/// 原生排程音频：排程消费 seam 与流生命周期 seam 的
/// 生产实现——[BeatAudioRenderer] 把排程指令下推原生 AAudio 低延迟流，并把
/// 节拍呈现下推的媒介时刻配对转发原生时基。
///
/// 依赖方向：本文件 import `beat_schedule.dart` 的三个 seam 接口与原生 sink
/// 打开、`metronome_source_registry.dart` 的段表与生效音源注入点、
/// `media_clock.dart`（同步值类型）及原生绑定，零 import 中枢。
///
/// **本类不做任何时间估计**：「此刻媒介走到哪」全仓
/// 只有节拍呈现那一份外推；本类只把呈现下推的
/// `(媒介时刻, 倍速, 播放态)` 配对转发原生 sink——配对的另一半（原生自己
/// 的帧位）由原生在收到下推时现取。无锚（起手/flush 后）时不下推、不伪造
/// 锚。
library;

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/media_clock.dart';
import 'beat_audio_log.dart';
import 'beat_audio_native.dart';
import 'beat_schedule.dart';
import 'metronome_source_registry.dart';

/// 排程消费 seam 与流生命周期 seam 的生产实现（流生命
/// 周期收进深模块 =）：深模块排程指令下推原生 AAudio 低
/// 延迟渲染器按时渲染（原生哑渲染，不做拍序决策）。
///
/// - **媒介时刻配对转发**：呈现下推的同步对原样
///   转发原生 sink；播放位置事件不再由本类估计，锚采纳与外推都在呈现。
/// - **流生命周期策略全在深模块**：本类只实现哑操作面
///   [BeatStreamControl]（探测/开流/停流/重建流对象/单调时基），应活判定、
///   自愈探测、冷却重试、重建预算、并发合流都由节拍呈现对象内部
///   收口——模块之外没有任何流生命周期代码。
/// - **校准会话模式**：进入 = flush 旧锚 + 会话时钟源锚（会话
///   时间轴 → 原生帧位，速率 1、playing 真）；退出 = flush + 清会话锚。会话
///   期间流的常开与自愈同样由深模块经 [BeatStreamControl] 收口。
/// - **段资产**：随当前音源项（注册表三段 + 段内拍点标记）惰性预载一次，
///   失败重置以便下次重试；原生按实际流采样率重采样、标记换算采样偏移。
/// - sink 不可用（非 Android 宿主/单测）= 哑 sink：全部调用安全无行为，
///   播放链路不受阻（发声需真机原生路径，纪律真机回归确认）。
///
/// 亦是渲染器时基 seam（[BeatAudioRendererLifecycle]）的生产适配器：会话
/// 模式开关走该 seam 的 [BeatAudioRendererLifecycle.onCalibrationSession]
/// ——本类保持哑渲染：只收 seam 调用，不读任何设置槽/provider/复位信号。
class BeatAudioRenderer
    implements
        BeatScheduleConsumer,
        BeatStreamControl,
        BeatAudioRendererLifecycle {
  BeatAudioRenderer({
    BeatAudioSink? sink,
    MetronomeSourceEntry? entry,
    Future<ByteData> Function(String asset)? loadAsset,
  }) : _sink = sink, // ignore: prefer_initializing_formals
       _entry = entry ?? metronomeSourceEntryOfId(kNormalSourceId),
       _loadAsset = loadAsset ?? rootBundle.load;

  final BeatAudioSink? _sink;
  final MetronomeSourceEntry _entry;

  /// 当前音源段表（组序、槽 → 哑段 id）：装载按 [MetronomeSegmentTable.loads]
  /// 逐 id 装载，转发按指令自带的 id 原样下推（查表在段表内，不在本类）。
  late final MetronomeSegmentTable _segmentTable = MetronomeSegmentTable.of(
    _entry,
  );
  final Future<ByteData> Function(String asset) _loadAsset;

  /// 当前音源项（生效音源 seam 的只读观察口；测试断言重建用）。
  MetronomeSourceEntry get entry => _entry;

  bool _calibrationSession = false;
  bool _disposed = false;

  // ---- 最近一次呈现下推的时基（配对的原样转发用；null = 无锚）----

  int? _anchorMediaMs;
  double _rate = 1.0;
  bool _playing = false;

  /// 会话时钟源锚的单调墙钟时刻（[BeatAudioRenderer.monotonicMs] 同一
  /// 时基；null = 无会话锚）。会话模式收窄为校准会话专用，
  /// 故本锚的唯一来源就是校准会话。
  int? _sessionAnchorWallMs;

  /// 相位差探针 trace：仅当构建以
  /// `--dart-define=BEAT_AUDIO_PHASE_PROBE=true` 开启时，逐条指令打一行
  /// `[beatAudio] phaseProbe cmdMs=… estMs=… leadMs=… kind=…`——cmdMs =
  /// 指令目标媒介时刻，estMs = 最近一次下推的媒介时刻（呈现唯一外推的
  /// 读出，推进内即推即用），leadMs = 两者差（排程提前量）。
  /// 真机流程与口径见 `docs/acceptance/beat-audio-phase-probe.md`；默认
  /// 关闭，热路径零成本。
  static const bool phaseProbeTrace = bool.fromEnvironment(
    'BEAT_AUDIO_PHASE_PROBE',
  );

  Future<void>? _loading;

  /// 时基下推：呈现下推的媒介时刻配对原样转发原生
  /// sink。校准会话期间不收（会话锚是权威锚，媒体轴不掺会话时间轴）。
  @override
  void onMediaNow(MediaClockSync sync) {
    if (_disposed || _calibrationSession) return;
    _anchorMediaMs = sync.mediaTimeMs;
    _rate = sync.rate;
    _playing = sync.playing;
    _pushSync();
  }

  /// 最近一次下推的媒介时刻（探针/测试面，生产接缝上已无读者，
  /// 唯一读者是 `--dart-define` 门控的相位探针 trace 与宿主直测）；无锚
  /// （起手/flush 后）为 0。渲染器不外推——「现在」全仓只有节拍呈现那一份
  /// 外推。校准会话期间回答会话时钟（自会话锚起的墙钟时长，速率 1）——
  /// 会话轴维持既有口径。
  Duration estimatedMediaNow() {
    if (_disposed) return Duration.zero;
    if (_calibrationSession) {
      final anchor = _sessionAnchorWallMs;
      if (anchor == null) return Duration.zero;
      return Duration(milliseconds: (_sink?.monotonicMs() ?? 0) - anchor);
    }
    return Duration(milliseconds: _anchorMediaMs ?? 0);
  }

  /// 播放态边沿（时基纪律）：播放 = 恢复外推，暂停/退后台 = 冻结外推。
  /// 流的开/停不在此处（生命周期策略在深模块，经
  /// [BeatStreamControl] 收口）。

  @override
  Future<void> onCalibrationSession(bool active) async {
    if (_disposed) return;
    _calibrationSession = active;
    if (active) {
      await flush();
      _pushSessionSync();
    } else {
      _sessionAnchorWallMs = null;
      _sink?.flush();
    }
  }

  /// 排程一条指令（入队返回值被检查——原生未接受时报告失败，由
  /// 深模块记一行诊断并按流记账触发自愈重试；本类保持哑渲染，不承载
  /// 流生命周期策略）。
  @override
  Future<bool> schedule(BeatScheduleCommand command) async {
    if (_disposed) return false;
    final sink = _sink;
    if (sink == null) return false;
    if (phaseProbeTrace) {
      final estMs = estimatedMediaNow().inMicroseconds / 1000.0;
      final cmdMs = command.beatMediaTime.inMicroseconds / 1000.0;
      beatAudioLog(
        'phaseProbe cmdMs=$cmdMs estMs=$estMs '
        'leadMs=${cmdMs - estMs} segmentId=${command.segmentId}',
      );
    }
    await _ensureLoaded();
    if (_disposed) return false;
    return sink.enqueue(
      beatMediaTimeMs: command.beatMediaTime.inMilliseconds.toDouble(),
      segmentId: command.segmentId,
      volume: command.volume,
    );
  }

  /// flush = 显式不连续（暂停/seek/lap 回跳/切会话）：丢弃原生未消费指令 +
  /// 清最近下推的媒介时刻（无锚不下推、不伪造；重立由呈现的下一次配对
  /// 下推承担）。
  @override
  Future<void> flush() async {
    if (_disposed) return;
    _anchorMediaMs = null;
    _sink?.flush();
  }

  /// 释放原生渲染器（ProviderScope 销毁收口）。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sink?.dispose();
  }

  // ---- 流生命周期 seam（[BeatStreamControl]）：哑操作转发，无策略 ----

  @override
  bool streamLost() {
    final sink = _sink;
    if (sink == null || _disposed) return false;
    return sink.streamLost();
  }

  @override
  Future<void> openStream() async {
    final sink = _sink;
    if (sink == null || _disposed) return;
    await _ensureLoaded();
    if (_disposed) return;
    sink.start();
  }

  @override
  void stopStream() {
    final sink = _sink;
    if (sink == null || _disposed) return;
    sink.flush();
    sink.stop();
  }

  @override
  Future<void> rebuildTransport() async {
    final sink = _sink;
    if (sink == null || _disposed) return;
    // 只清原生事件环，不清媒介时刻配对：新流对象不带锚，紧随其后的
    // _pushSync 按最近下推的配对重立（无锚则不推、不伪造）。
    sink.flush();
    sink.recoverTransport();
    // 新流对象不带锚：立刻按当前时间轴源重立锚，重建后的第一拍才落得下去
    // （会话模式用会话锚、播放模式用呈现下推的媒介配对，与失败前同一条来源）。
    if (_calibrationSession) {
      _pushSessionSync();
    } else {
      _pushSync();
    }
  }

  @override
  int monotonicMs() => _sink?.monotonicMs() ?? 0;

  void _pushSync() {
    final sink = _sink;
    if (sink == null) return;
    final anchorMs = _anchorMediaMs;
    if (anchorMs == null) return; // 无锚：不下推、不伪造
    sink.sync(mediaTimeMs: anchorMs.toDouble(), rate: _rate, playing: _playing);
  }

  /// 会话时钟源锚：会话时间轴（自会话启动 0 起算）→ 墙钟
  /// 单调时刻，速率 1、playing 真——会话拍指令按会话时间排程，原生排程
  /// 换算与媒介时钟同一条锚算术（哑渲染对时间轴来源无感知）。
  void _pushSessionSync() {
    final sink = _sink;
    if (sink == null) return;
    _sessionAnchorWallMs = sink.monotonicMs();
    sink.sync(mediaTimeMs: 0, rate: 1.0, playing: true);
  }

  /// 段资产惰性预载一次（当前音源段表的去重段清单按 id 装载 + 标记下传
  /// 原生）；失败重置以便下次重试——发声不可用不应影响播放链路。
  Future<void> _ensureLoaded() {
    return _loading ??= _loadSegments();
  }

  Future<void> _loadSegments() async {
    final sink = _sink;
    if (sink == null) return;
    final table = _segmentTable;
    try {
      for (var id = 0; id < table.loads.length; id++) {
        final spec = table.loads[id];
        if (spec.asset.isEmpty) continue; // 待支持音源占位段无资产
        final data = await _loadAsset(spec.asset);
        final wav = decodeWavMono(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        sink.loadSegment(
          segmentId: id,
          pcm: wav.samples,
          sampleRate: wav.sampleRate,
          markerMs: spec.markerMs,
        );
      }
    } on Object {
      _loading = null;
    }
  }
}

/// 原生排程渲染器注入点：生产实现 = [BeatAudioRenderer]（媒介
/// 时刻配对转发 + 排程指令下推原生 AAudio 低延迟流）。音源项随「生效音源
/// id」变化重建（[effectiveMetronomeSourceIdProvider]：设置槽 + 会话回落，
/// watch，不首读固化）；ProviderScope 销毁时释放原生句柄；sink 经
/// [openNativeBeatAudioSink] 打开。
final beatAudioRendererProvider = Provider<BeatAudioRenderer>((ref) {
  final renderer = BeatAudioRenderer(
    sink: openNativeBeatAudioSink(),
    entry: metronomeSourceEntryOfId(
      ref.watch(effectiveMetronomeSourceIdProvider),
    ),
  );
  ref.onDispose(renderer.dispose);
  return renderer;
});
