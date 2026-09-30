/// 分段线：在时间轴上划分学习段落的位置标记。
///
/// 分段线贯穿轨道、默认细线；可置位 [flagged]（flag）变为粗线作为进度标记。
/// 位置为时间轴上的**绝对时间点**（[Duration]）。
///
/// 字段归属（双文件分层）：分段线及其 [flag] 为**可分享**字段，
/// 落盘时写入公开标记文件（`markers_<hash>.json`）。
library;

import '../core/document_codec.dart';

/// 分段线字段 id（元素类型自带字段单一声明）。
enum SegmentLineField { timeMs, flag }

/// 一条分段线（不可变值对象）。
class SegmentLine {
  const SegmentLine({
    required this.position,
    this.flagged = false,
    this.extra = const {},
  });

  /// 分段线在时间轴上的位置（绝对时间点，受视频首/尾区间约束）。
  final Duration position;

  /// 是否为分段线标记（flag）：置位时以粗线显示。
  final bool flagged;

  /// 未知键保底区（原样带回、写回原样；不参与相等比较）。
  final Map<String, Object?> extra;

  SegmentLine copyWith({
    Duration? position,
    bool? flagged,
    Map<String, Object?>? extra,
  }) {
    return SegmentLine(
      position: position ?? this.position,
      flagged: flagged ?? this.flagged,
      extra: extra ?? this.extra,
    );
  }

  /// 相等/哈希由字段声明派生（保底区不参与）。
  @override
  bool operator ==(Object other) =>
      other is SegmentLine && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);

  @override
  String toString() => 'SegmentLine(position: $position, flagged: $flagged)';

  /// 分段线自带编解码（键名/读/写/相等在同一处声明）。
  static const RecordCodec<SegmentLine, SegmentLineField> codec =
      RecordCodec<SegmentLine, SegmentLineField>(
        ids: SegmentLineField.values,
        decl: _decl,
        build: _build,
        extraOf: _extraOf,
        withExtra: _withExtra,
        required: {SegmentLineField.timeMs},
      );

  /// 写出（元素层保底区先展开，已登记字段后写）。
  Map<String, Object?> toJson() => codec.encode(this);

  /// 读取；`timeMs` 缺失或类型不符（必填）视为损坏条目，返回 null
  /// （调用方丢弃）。
  static SegmentLine? fromJson(Object? raw) => codec.tryDecode(raw);

  /// 元素表 ↔ JSON 数组：跳过损坏条目、保留合法项。
  static List<SegmentLine> fromJsonList(Object? raw) => codec.decodeList(raw);
}

FieldDecl<SegmentLine> _decl(SegmentLineField id) => switch (id) {
  SegmentLineField.timeMs => FieldDecl(
    key: 'timeMs',
    read: (json) => switch (json['timeMs']) {
      int v => v,
      _ => null,
    },
    write: (line) => line.position.inMilliseconds,
    equal: (a, b) => a.position == b.position,
  ),
  SegmentLineField.flag => FieldDecl(
    key: 'flag',
    read: (json) => json['flag'] as bool? ?? false,
    write: (line) => line.flagged,
    equal: (a, b) => a.flagged == b.flagged,
  ),
};

SegmentLine _build(Map<SegmentLineField, Object?> values) => SegmentLine(
  position: Duration(
    milliseconds: values[SegmentLineField.timeMs] as int? ?? 0,
  ),
  flagged: values[SegmentLineField.flag] as bool,
);

Map<String, Object?> _extraOf(SegmentLine line) => line.extra;

SegmentLine _withExtra(SegmentLine line, Map<String, Object?> extra) =>
    line.copyWith(extra: extra);
