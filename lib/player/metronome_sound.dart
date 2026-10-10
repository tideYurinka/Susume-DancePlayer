/// 中立音声 home：音源/声音反馈总开关/半拍声/视频静音设置槽。
///
/// 依赖方向纪律：发声链/渲染接线/seek 提交口只 import 本文件，
/// 不 import 动画渲染文件 beat_animation.dart；动画渲染文件可 import
/// 本文件，反向禁止。
///
/// 视频静音是「另一路输出」那一侧的值（只静视频，节拍声照旧），故经
/// `playback_engine_providers.dart` 写播放内核——本层唯一直接写内核的
/// 设置槽。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'beat_prompt_memory.dart';
import 'metronome_settings_store.dart';
import 'metronome_source_registry.dart';

/// 声音类型（仅落类型枚举 + 设置槽）。
enum MetronomeSoundType { normal, vocal, geigi }

extension MetronomeSoundTypeX on MetronomeSoundType {
  /// 对应音源段注册表项（id = 枚举名，与设置槽存值一致）。
  MetronomeSourceEntry get sourceEntry => metronomeSourceEntryOfId(name);

  /// 是否待支持（注册表 available:false = 置灰不可选、选到时不发声）。
  bool get samplePending => !sourceEntry.available;
}

/// 音源解码/编码（设备级默认层与记忆字段共用；非「普通」值——人声/歌姬
/// 已置灰不可选——读取一律归一为普通）。
MetronomeSoundType? decodeMetronomeSoundType(Object? raw) =>
    raw == 'normal' ? MetronomeSoundType.normal : null;

Object? encodeMetronomeSoundType(MetronomeSoundType type) => switch (type) {
  MetronomeSoundType.vocal => 'vocal',
  MetronomeSoundType.geigi => 'geigi',
  MetronomeSoundType.normal => 'normal',
};

/// 音源设备级「新舞默认」槽（`metronomeSettings.soundType`）。
final metronomeSoundTypeDefaultProvider =
    NotifierProvider<MetronomeSoundTypeDefaultModel, MetronomeSoundType>(
      MetronomeSoundTypeDefaultModel.new,
    );

class MetronomeSoundTypeDefaultModel
    extends PersistedSettingModel<MetronomeSoundType> {
  @override
  String get settingField => 'soundType';

  @override
  MetronomeSoundType? Function(Object? raw) get decode =>
      decodeMetronomeSoundType;

  @override
  Object? Function(MetronomeSoundType value) get encode =>
      encodeMetronomeSoundType;

  @override
  MetronomeSoundType get defaultValue => MetronomeSoundType.normal;
}

/// 音源生效值设置槽：记忆有值用记忆值，缺席回落设备级「新舞
/// 默认」；用户选择双写记忆与设备级字段。UI 以「音源」列表呈现。
final metronomeSoundTypeProvider =
    NotifierProvider<MetronomeSoundTypeModel, MetronomeSoundType>(
      MetronomeSoundTypeModel.new,
    );

class MetronomeSoundTypeModel
    extends BeatPromptEffectiveModel<MetronomeSoundType> {
  @override
  MetronomeSoundType? memoryValueOf(memory) {
    final raw = memory?.soundType;
    return raw == null ? null : decodeMetronomeSoundType(raw);
  }

  @override
  MetronomeSoundType watchDeviceDefault() =>
      ref.watch(metronomeSoundTypeDefaultProvider);

  @override
  void persistDeviceDefault(MetronomeSoundType value) =>
      ref.read(metronomeSoundTypeDefaultProvider.notifier).set(value);

  @override
  void writeMemoryField(MetronomeSoundType value) =>
      ref.read(beatPromptMemoryProvider.notifier).setSoundType(value.name);
}

/// 声音反馈总开关生效值设置槽（面板「声音反馈」开关；随舞记忆、无设备级
/// 对应值：记忆缺席一律关——开箱不自动出声，用户选择只写这支舞的记忆）。
final metronomeSoundEnabledProvider =
    NotifierProvider<MetronomeSoundEnabledModel, bool>(
      MetronomeSoundEnabledModel.new,
    );

class MetronomeSoundEnabledModel extends Notifier<bool> {
  @override
  bool build() => ref.watch(beatPromptMemoryProvider)?.sound ?? false;

  void set(bool enabled) {
    if (!ref.mounted || enabled == state) return;
    // 关掉本组总开关即一并解除视频静音：不出现「视频静音 + 没有节拍声」
    // 的全静音（用户读到的会是软件坏了）。
    if (!enabled) ref.read(videoMutedProvider.notifier).set(false);
    ref.read(beatPromptMemoryProvider.notifier).setSound(enabled);
  }
}

/// 视频静音设置槽（面板「关闭视频声音」）：勾选只静这支视频的声音，
/// 节拍声（含半拍声，另一条独立原生输出）照常。
///
/// 会话值、**不落盘**（不进节拍提示记忆、不进节拍器设置）：它的失效后果是
/// 用户以为软件坏了，所以换视频、离开播放页、关掉「声音反馈」总开关都回到
/// 有声音，勾选值本身也不留给下一次。
final videoMutedProvider = NotifierProvider<VideoMutedModel, bool>(
  VideoMutedModel.new,
);

class VideoMutedModel extends Notifier<bool> {
  @override
  bool build() => false;

  /// 用户勾选/取消：值 + 播放内核。
  void set(bool muted) {
    if (!ref.mounted || muted == state) return;
    state = muted;
    ref.read(playbackEngineProvider).setVideoMuted(muted);
  }

  /// 会话复位（换视频、离开播放页）：值回 false，并把内核无条件写回
  /// 不静音——内核是应用级单例，静音属性会跨视频留着，打开一支新舞必须先
  /// 把它抹掉。
  void reset() {
    if (!ref.mounted) return;
    if (state) state = false;
    ref.read(playbackEngineProvider).setVideoMuted(false);
  }
}

/// 半拍声设备级「新舞默认」槽（`metronomeSettings.halfBeatEnabled`）。
final metronomeHalfBeatEnabledDefaultProvider =
    NotifierProvider<MetronomeHalfBeatEnabledDefaultModel, bool>(
      MetronomeHalfBeatEnabledDefaultModel.new,
    );

class MetronomeHalfBeatEnabledDefaultModel extends PersistedSettingModel<bool> {
  @override
  String get settingField => 'halfBeatEnabled';

  @override
  bool? Function(Object? raw) get decode =>
      (raw) => raw is bool ? raw : null;

  @override
  Object? Function(bool value) get encode =>
      (value) => value;

  @override
  bool get defaultValue => true;
}

/// 半拍声生效值设置槽：记忆有值用记忆值，缺席回落设备级「新舞
/// 默认」；用户选择双写记忆与设备级字段。
final metronomeHalfBeatEnabledProvider =
    NotifierProvider<MetronomeHalfBeatEnabledModel, bool>(
      MetronomeHalfBeatEnabledModel.new,
    );

class MetronomeHalfBeatEnabledModel extends BeatPromptEffectiveModel<bool> {
  @override
  bool? memoryValueOf(memory) => memory?.halfBeat;

  @override
  bool watchDeviceDefault() =>
      ref.watch(metronomeHalfBeatEnabledDefaultProvider);

  @override
  void persistDeviceDefault(bool value) =>
      ref.read(metronomeHalfBeatEnabledDefaultProvider.notifier).set(value);

  @override
  void writeMemoryField(bool value) =>
      ref.read(beatPromptMemoryProvider.notifier).setHalfBeat(value);
}
