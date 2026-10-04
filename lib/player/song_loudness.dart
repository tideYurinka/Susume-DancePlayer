import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/private_json.dart';
import '../beat/loudness_probe.dart';
import 'metronome_settings_store.dart' show PersistedSettingModel;
import 'metronome_source_registry.dart' show MetronomeSegmentSlot;

// 响度测量 seam 与 PCM RMS 纯函数定义在 `beat/loudness_probe.dart`
// （与节拍分析解码共用），此处转出供本模块消费方统一引用。
export '../beat/loudness_probe.dart' show SongLoudnessProbe, pcmRms;

/// 歌曲响度基准与节拍音量。
///
/// - **滑条**：声音反馈组内「节拍音量」，设备级 `metronomeVolume`
///   （0–100，默认 50），经 [MetronomeVolumeModel] 走 `metronomeSettings`
///   既有恢复/落盘同步。
/// - **响度模型**：实际发声响度 = 该歌曲响度自动均衡基准 × 滑条增益
///   （50% → 1.0×基准，100% → 2.0×基准，线性），最终钳制 ≤ 1.0 防削波。
/// - **基准缓存**：每歌测量一次（节拍分析解码顺带测量；无分析记录先按
///   默认基准、后台补测后更新），按视频 id 存 `global_private.json` 的
///   `songLoudnessBaselines` 键（本地私密，不随分享/导出流出）。

/// 出厂默认歌曲响度基准（未测量时按 1.0，即不缩放）。
const double kDefaultSongLoudnessBaseline = 1.0;

/// 基准映射的钳制下界（响度极大的歌不再压低基准）。
const double kMinSongLoudnessBaseline = 0.25;

/// 基准映射的钳制上界（近静音的歌不无限放大底噪）。
const double kMaxSongLoudnessBaseline = 4.0;

/// 基准映射的目标 PCM RMS（≈ −18 dBFS）：实测 RMS 归一到此响度。
const double kTargetPcmRms = 0.125;

/// 半拍样本内部响度拉平增益（约 +6dB ≈ 振幅 ×2，不改资产文件）。
const double kHalfBeatLoudnessCompensation = 2.0;

/// 滑条百分比 → 增益（纯函数）：线性 `percent / 50`，输入越界钳制
/// 0–100（字段解码已保证 0–100，此处为纯函数防御）。
double metronomeSliderGain(int percent) =>
    (percent.clamp(0, 100) / 50).toDouble();

/// 一次发声的实际响度（纯函数）：歌曲响度基准 × 滑条增益；半拍样本
/// 先乘内部拉平增益再统一钳制 ≤ 1.0 防削波。
double metronomeSampleVolume({
  required int volumePercent,
  required double baseline,
  bool halfBeat = false,
}) {
  final raw =
      baseline *
      metronomeSliderGain(volumePercent) *
      (halfBeat ? kHalfBeatLoudnessCompensation : 1.0);
  return raw.clamp(0.0, 1.0).toDouble();
}

/// PCM RMS 纯函数见 `beat/loudness_probe.dart`（本库转出）。

/// 实测 PCM RMS → 歌曲响度基准（纯函数）：目标响度 / 实测响度，钳制
/// [kMinSongLoudnessBaseline, kMaxSongLoudnessBaseline]；静音/非法兜底
/// 默认基准。
double loudnessBaselineFromRms(double rms) {
  if (rms <= 0 || rms.isNaN || rms.isInfinite) {
    return kDefaultSongLoudnessBaseline;
  }
  return (kTargetPcmRms / rms).clamp(
    kMinSongLoudnessBaseline,
    kMaxSongLoudnessBaseline,
  );
}

/// 歌曲响度基准按视频缓存（`global_private.json` 的
/// `songLoudnessBaselines` 键，videoId → 基准）；读改写保留同文件其它键。
class SongLoudnessBaselineStore {
  SongLoudnessBaselineStore(this._storage);

  static const _key = 'songLoudnessBaselines';

  final PrivateJsonStorage _storage;

  /// 读取某视频基准；缺失/损坏兜底 null（调用方按默认基准处理）。
  Future<double?> load(String videoId) async {
    final raw = (await _storage.read())[_key];
    final baselines = raw is Map ? raw : const {};
    return _decode(baselines[videoId]);
  }

  /// 写入某视频基准（原子读改写，保留同文件其它键）。
  Future<void> save(String videoId, double baseline) {
    return _storage.mutate((json, {required bool present}) {
      final raw = json[_key];
      final baselines = Map<String, dynamic>.from(raw is Map ? raw : {});
      baselines[videoId] = baseline;
      json[_key] = baselines;
    });
  }

  static double? _decode(Object? raw) {
    if (raw is! num) return null;
    final value = raw.toDouble();
    if (!value.isFinite || value <= 0) return null;
    return value;
  }
}

/// 基准缓存注入点（测试经内存私密 JSON 覆盖）。
final songLoudnessBaselineStorageProvider = Provider<SongLoudnessBaselineStore>(
  (ref) => SongLoudnessBaselineStore(ref.watch(privateJsonStorageProvider)),
);

/// 会话内当前视频的响度基准（默认基准起；打开新视频复位，测量/缓存命中
/// 后更新）。
final songLoudnessBaselineProvider =
    NotifierProvider<SongLoudnessBaselineModel, double>(
      SongLoudnessBaselineModel.new,
    );

class SongLoudnessBaselineModel extends Notifier<double> {
  @override
  double build() => kDefaultSongLoudnessBaseline;

  void set(double value) => state = value;

  /// 打开新视频复位出厂默认（上一视频的基准不得串入）。
  void reset() => state = kDefaultSongLoudnessBaseline;
}

/// 测量注入点。
final songLoudnessProbeProvider = Provider<SongLoudnessProbe>(
  (ref) => const FfmpegSongLoudnessProbe(),
);

/// 响度基准编排：
///
/// - [recordRms]：节拍分析解码顺带测量入口——基准映射后即时更新会话态
///   并按视频落盘（分析在途被取消也不回滚：测量值本身有效）。
/// - [ensureBaseline]：打开视频时对齐基准——缓存命中直接采用；无缓存
///   先按默认基准、后台补测一次（代际号防跨视频串写）。
class SongLoudnessCoordinator {
  SongLoudnessCoordinator(this._ref);

  final Ref _ref;

  int _generation = 0;

  /// 节拍分析解码顺带测量的入口（分析在途被取消也不回滚：测量值本身
  /// 有效）。
  void recordRms(String videoId, double rms) {
    unawaited(_apply(videoId, loudnessBaselineFromRms(rms)));
  }

  Future<void> _apply(String videoId, double baseline) async {
    _ref.read(songLoudnessBaselineProvider.notifier).set(baseline);
    try {
      await _ref
          .read(songLoudnessBaselineStorageProvider)
          .save(videoId, baseline);
    } on Object {
      // 写失败不抛到分析/打开链路（会话基准已生效，下次再落盘）。
    }
  }

  /// 打开视频时对齐基准（缓存命中即用；否则后台补测后更新）。
  Future<void> ensureBaseline({
    required String videoPath,
    required String videoId,
  }) async {
    double? cached;
    try {
      cached = await _ref
          .read(songLoudnessBaselineStorageProvider)
          .load(videoId);
    } on Object {
      cached = null; // 缓存不可读按未测处理（后台补测）。
    }
    if (!_ref.mounted) return;
    if (cached != null) {
      _ref.read(songLoudnessBaselineProvider.notifier).set(cached);
      return;
    }
    final generation = ++_generation;
    try {
      final rms = await _ref.read(songLoudnessProbeProvider).pcmRms(videoPath);
      if (generation != _generation) return; // 已切换视频：不串写。
      await _apply(videoId, loudnessBaselineFromRms(rms));
    } on Object {
      // 补测失败维持默认基准（下次打开再试）。
    }
  }

  /// 取消在途补测（打开新视频）。
  void cancel() {
    _generation++;
  }
}

/// 基准编排注入点。
final songLoudnessCoordinatorProvider = Provider<SongLoudnessCoordinator>(
  (ref) => SongLoudnessCoordinator(ref),
);

/// 节拍音量设置槽（设备级 `metronomeSettings.metronomeVolume`，0–100，
/// 默认 50）。
final metronomeVolumeProvider = NotifierProvider<MetronomeVolumeModel, int>(
  MetronomeVolumeModel.new,
);

class MetronomeVolumeModel extends PersistedSettingModel<int> {
  @override
  String get settingField => 'metronomeVolume';

  @override
  int? Function(Object? raw) get decode =>
      (raw) => raw is int && raw >= 0 && raw <= 100 ? raw : null;

  @override
  Object? Function(int value) get encode =>
      (value) => value;

  @override
  int get defaultValue => 50;
}

/// 发声响度工厂注入点：按段槽位取当前实际响度（歌曲响度基准 ×
/// 滑条增益；半拍槽含内部拉平增益），节拍声/前导共用。
final metronomePlayVolumeProvider =
    Provider<double Function(MetronomeSegmentSlot slot)>((ref) {
      return (slot) => metronomeSampleVolume(
        volumePercent: ref.read(metronomeVolumeProvider),
        baseline: ref.read(songLoudnessBaselineProvider),
        halfBeat: slot == MetronomeSegmentSlot.half,
      );
    });

/// 发声响度工厂注入点的整拍槽取值（前导/延迟播放占位提示用整拍段）。
double metronomePlayBeatVolume(Ref ref) =>
    ref.read(metronomePlayVolumeProvider)(MetronomeSegmentSlot.count2);
