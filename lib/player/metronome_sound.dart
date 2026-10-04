/// 中立音声 home：音源/声音反馈总开关/半拍声设置槽。
///
/// 依赖方向纪律：发声链/渲染接线/seek 提交口只 import 本文件，
/// 不 import 动画渲染文件 beat_animation.dart；动画渲染文件可 import
/// 本文件，反向禁止。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    ref.read(beatPromptMemoryProvider.notifier).setSound(enabled);
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
