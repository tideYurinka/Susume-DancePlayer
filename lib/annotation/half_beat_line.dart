/// 半拍线：用户手动标记的半拍位置标记。
///
/// 与分段线并列的**视频属性公共标记**：随 markers 落盘、可分享
/// （公开侧，落盘见 `persistence/marker_document.dart`）。
/// 位置为时间轴上的**绝对
/// 时间点**（[Duration]），插入时经 `half_beat_snap.dart` 吸附解析、插入
/// 后可拖动精调；不参与学习段几何派生（学习段只由分段线决定）。
library;

import '../core/document_codec.dart';

/// 半拍线字段 id（元素类型自带字段单一声明）。
enum HalfBeatLineField { timeMs }

/// 一条半拍线（不可变值对象）。
class HalfBeatLine {
  const HalfBeatLine({required this.position, this.extra = const {}});

  /// 半拍线在时间轴上的位置（绝对时间点，受视频首/尾区间约束）。
  final Duration position;

  /// 未知键保底区（原样带回、写回原样；不参与相等比较）。
  final Map<String, Object?> extra;

  HalfBeatLine copyWith({Duration? position, Map<String, Object?>? extra}) {
    return HalfBeatLine(
      position: position ?? this.position,
      extra: extra ?? this.extra,
    );
  }

  /// 相等/哈希由字段声明派生（保底区不参与）。
  @override
  bool operator ==(Object other) =>
      other is HalfBeatLine && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);

  @override
  String toString() => 'HalfBeatLine(position: $position)';

  /// 半拍线自带编解码（键名/读/写/相等在同一处声明）。
  static const RecordCodec<HalfBeatLine, HalfBeatLineField> codec =
      RecordCodec<HalfBeatLine, HalfBeatLineField>(
        ids: HalfBeatLineField.values,
        decl: _decl,
        build: _build,
        extraOf: _extraOf,
        withExtra: _withExtra,
        required: {HalfBeatLineField.timeMs},
      );

  /// 写出（元素层保底区先展开，已登记字段后写）。
  Map<String, Object?> toJson() => codec.encode(this);

  /// 读取；`timeMs` 缺失或类型不符（必填）视为损坏条目，返回 null
  /// （调用方丢弃）。
  static HalfBeatLine? fromJson(Object? raw) => codec.tryDecode(raw);

  /// 元素表 ↔ JSON 数组：跳过损坏条目、保留合法项。
  static List<HalfBeatLine> fromJsonList(Object? raw) => codec.decodeList(raw);
}

FieldDecl<HalfBeatLine> _decl(HalfBeatLineField id) => switch (id) {
  HalfBeatLineField.timeMs => FieldDecl(
    key: 'timeMs',
    read: (json) => switch (json['timeMs']) {
      int v => v,
      _ => null,
    },
    write: (line) => line.position.inMilliseconds,
    equal: (a, b) => a.position == b.position,
  ),
};

HalfBeatLine _build(Map<HalfBeatLineField, Object?> values) => HalfBeatLine(
  position: Duration(
    milliseconds: values[HalfBeatLineField.timeMs] as int? ?? 0,
  ),
);

Map<String, Object?> _extraOf(HalfBeatLine line) => line.extra;

HalfBeatLine _withExtra(HalfBeatLine line, Map<String, Object?> extra) =>
    line.copyWith(extra: extra);
