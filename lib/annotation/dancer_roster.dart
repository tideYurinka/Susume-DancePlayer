/// 舞者名册条目（markers 顶层 `roster` 段的元素值对象）。
///
/// 名册 = 名字 + 代表色（`lib/annotation/GLOSSARY.md` 词条「舞者名册」「代表色」），随公开
/// 标记文件按视频分享还原、**不跨视频关联**。条目不可变；同表按名字
/// 唯一（[normalizeRoster] 维持，历史重复项在整表补写时合并修复）。
library;

import '../core/document_codec.dart';

/// 名册条目字段 id（元素类型自带字段单一声明）。
enum DancerRosterEntryField { name, color }

/// 名册里的一个舞者：[name] + 代表色（ARGB）。
class DancerRosterEntry {
  const DancerRosterEntry({
    required this.name,
    required this.color,
    this.extra = const {},
  });

  /// 舞者名（备注文本按名字匹配着色的键）。
  final String name;

  /// 代表色（ARGB 整数）。
  final int color;

  /// 未知键保底区（原样带回、写回原样；不参与相等比较）。
  final Map<String, Object?> extra;

  /// 写定代表色（纯函数：返回新实例，原实例不变；保底区原样携带）。
  DancerRosterEntry withColor(int color) =>
      DancerRosterEntry(name: name, color: color, extra: extra);

  /// 相等/哈希由字段声明派生（保底区不参与）。
  @override
  bool operator ==(Object other) =>
      other is DancerRosterEntry && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);

  @override
  String toString() => 'DancerRosterEntry(name: $name, color: $color)';

  /// 自带编解码（键名/读/写/相等在同一处声明）。
  static const RecordCodec<DancerRosterEntry, DancerRosterEntryField> codec =
      RecordCodec<DancerRosterEntry, DancerRosterEntryField>(
        ids: DancerRosterEntryField.values,
        decl: _decl,
        build: _build,
        extraOf: _extraOf,
        withExtra: _withExtra,
        required: {DancerRosterEntryField.name, DancerRosterEntryField.color},
      );

  /// 写出（元素层保底区先展开，已登记字段后写）。
  Map<String, Object?> toJson() => codec.encode(this);

  /// 读取；`name`/`color` 任一缺失或类型不符（必填）视为损坏条目，
  /// 返回 null（调用方丢弃）。
  static DancerRosterEntry? fromJson(Object? raw) => codec.tryDecode(raw);

  /// 元素表 ↔ JSON 数组：跳过损坏条目、保留合法项。
  static List<DancerRosterEntry> fromJsonList(Object? raw) =>
      codec.decodeList(raw);
}

FieldDecl<DancerRosterEntry> _decl(DancerRosterEntryField id) => switch (id) {
  DancerRosterEntryField.name => FieldDecl(
    key: 'name',
    read: (json) => switch (json['name']) {
      String v => v,
      _ => null,
    },
    write: (entry) => entry.name,
    equal: (a, b) => a.name == b.name,
  ),
  DancerRosterEntryField.color => FieldDecl(
    key: 'color',
    read: (json) => switch (json['color']) {
      int v => v,
      _ => null,
    },
    write: (entry) => entry.color,
    equal: (a, b) => a.color == b.color,
  ),
};

DancerRosterEntry _build(Map<DancerRosterEntryField, Object?> values) =>
    DancerRosterEntry(
      name: values[DancerRosterEntryField.name] as String,
      color: values[DancerRosterEntryField.color] as int,
    );

Map<String, Object?> _extraOf(DancerRosterEntry entry) => entry.extra;

DancerRosterEntry _withExtra(
  DancerRosterEntry entry,
  Map<String, Object?> extra,
) => DancerRosterEntry(name: entry.name, color: entry.color, extra: extra);

/// 名册规范化（纯函数）：同名条目合并为一条、**后出现的颜色胜**（整表
/// 补写「最新优先」口径），顺序按首次出现位。历史重复项（异常输入或
/// 旧文件遗留）经任何一次整表补写即被修复。
List<DancerRosterEntry> normalizeRoster(Iterable<DancerRosterEntry> entries) {
  final list = entries.toList();
  final latestColor = <String, int>{
    for (final entry in list) entry.name: entry.color,
  };
  final seen = <String>{};
  return [
    for (final entry in list)
      if (seen.add(entry.name)) entry.withColor(latestColor[entry.name]!),
  ];
}
