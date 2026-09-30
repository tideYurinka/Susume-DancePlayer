import 'package:flutter/foundation.dart' show listEquals;

import 'speed_step.dart';

/// 倍速步进预设：命名参数集。
///
/// - 内置预设由 [builtinSpeedStepPresets] 工厂常量给出，可修改（内置
///   覆盖）、可经恢复默认回到出厂值，也可删除（删除不可恢复，存储里
///   少一条即已删）；
/// - 自定义预设由用户新建/删除/命名。
class SpeedStepPreset {
  const SpeedStepPreset({
    required this.id,
    required this.name,
    required this.builtin,
    required this.params,
  });

  /// 稳定标识（内置 `builtin_*`；自定义 `custom_<毫秒时间戳>`，见
  /// `newCustomPresetId`）。
  final String id;

  final String name;

  /// 是否内置预设（出厂预设；仅内置提供一键「恢复默认」）。
  final bool builtin;

  /// 步进参数（恒合法，[SpeedStepParams.isValid]）。
  final SpeedStepParams params;

  SpeedStepPreset copyWith({String? name, SpeedStepParams? params}) {
    return SpeedStepPreset(
      id: id,
      name: name ?? this.name,
      builtin: builtin,
      params: params ?? this.params,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'builtin': builtin,
        'params': {
          'startRate': params.startRate,
          'maxRate': params.maxRate,
          'lapsPerRate': params.lapsPerRate,
          'rateIncrement': params.rateIncrement,
        },
      };

  factory SpeedStepPreset.fromJson(Map<String, dynamic> json) {
    final params = json['params'];
    return SpeedStepPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      builtin: json['builtin'] as bool? ?? false,
      params: params is Map<String, dynamic>
          ? SpeedStepParams(
              startRate: (params['startRate'] as num).toDouble(),
              maxRate: (params['maxRate'] as num).toDouble(),
              lapsPerRate: (params['lapsPerRate'] as num).toInt(),
              rateIncrement: (params['rateIncrement'] as num).toDouble(),
            )
          : const SpeedStepParams(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpeedStepPreset &&
      other.id == id &&
      other.name == name &&
      other.builtin == builtin &&
      other.params == params;

  @override
  int get hashCode => Object.hash(id, name, builtin, params);
}

/// 内置预设（「初见·大量练习」为默认参数）。
const List<SpeedStepPreset> builtinSpeedStepPresets = [
  SpeedStepPreset(
    id: 'builtin_first',
    name: '初见·大量练习',
    builtin: true,
    params: SpeedStepParams(
      startRate: 0.5,
      maxRate: 1.0,
      lapsPerRate: 3,
      rateIncrement: 0.1,
    ),
  ),
  SpeedStepPreset(
    id: 'builtin_review',
    name: '复习',
    builtin: true,
    params: SpeedStepParams(
      startRate: 0.5,
      maxRate: 1.0,
      lapsPerRate: 2,
      rateIncrement: 0.25,
    ),
  ),
];

/// 默认选中的预设 id（首个内置）。
const String defaultSelectedPresetId = 'builtin_first';

/// 内置预设的出厂参数（「恢复默认」回到此值）。
SpeedStepPreset builtinDefault(String id) {
  for (final p in builtinSpeedStepPresets) {
    if (p.id == id) return p;
  }
  throw ArgumentError('非内置预设 id：$id');
}

/// 新建自定义预设的 id（调用方保证时间戳唯一性足够；同毫秒连建由
/// Notifier 侧去重避让）。
String newCustomPresetId(DateTime now) =>
    'custom_${now.millisecondsSinceEpoch}';

/// 新建预设的默认名「自定义 N」：N 为避开
/// [existingNames] 中同名冲突的最小正整数。
String defaultCustomPresetName(Iterable<String> existingNames) {
  final taken = existingNames.toSet();
  for (var n = 1; ; n++) {
    final candidate = '自定义 $n';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// 预设单选行的参数摘要（气泡 UI 与测试共用）。
String speedStepPresetSummary(SpeedStepParams p) =>
    '起步 ${formatRate(p.startRate)} → 封顶 ${formatRate(p.maxRate)} · '
    '每档 ${p.lapsPerRate} 遍 · +${formatRate(p.rateIncrement)}';

/// 按 id 在 [doc] 中查预设（编辑任意预设经同一查找入口；store 与
/// 气泡 UI 共用，消除重复线性扫描）。
SpeedStepPreset? presetById(SpeedStepPresetDoc doc, String id) {
  for (final p in doc.presets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 预设持久化文档（设备级私密 JSON 的 player 域视图）：
/// 预设列表（内置覆盖/自定义）+ 当前选中预设。
class SpeedStepPresetDoc {
  const SpeedStepPresetDoc({required this.presets, required this.selectedId});

  /// 预设列表（含内置——以文件中的值覆盖出厂，支持「内置可修改」）。
  final List<SpeedStepPreset> presets;

  final String selectedId;

  /// 全新文档：仅内置预设、选中首个。
  static const SpeedStepPresetDoc fresh = SpeedStepPresetDoc(
    presets: builtinSpeedStepPresets,
    selectedId: defaultSelectedPresetId,
  );

  /// 缺失选中项等损坏情形的兜底：回落到全新文档语义由调用方（store）
  /// 处理；本工厂只做忠实反序列化。
  SpeedStepPresetDoc copyWith({
    List<SpeedStepPreset>? presets,
    String? selectedId,
  }) {
    return SpeedStepPresetDoc(
      presets: presets ?? this.presets,
      selectedId: selectedId ?? this.selectedId,
    );
  }

  Map<String, dynamic> toJson() => {
        'presets': [for (final p in presets) p.toJson()],
        'selectedId': selectedId,
      };

  factory SpeedStepPresetDoc.fromJson(Map<String, dynamic> json) {
    final raw = json['presets'];
    return SpeedStepPresetDoc(
      presets: [
        if (raw is List)
          for (final item in raw)
            if (item is Map<String, dynamic>) SpeedStepPreset.fromJson(item),
      ],
      selectedId: json['selectedId'] as String? ?? defaultSelectedPresetId,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SpeedStepPresetDoc &&
      other.selectedId == selectedId &&
      listEquals(other.presets, presets);

  @override
  int get hashCode => Object.hash(Object.hashAll(presets), selectedId);
}
