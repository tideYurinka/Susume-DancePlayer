/// 局部镜像片段值对象（可持久化区间片段）。
///
/// 时间区间为半开 `[startMs, endMs)`（毫秒）；片段表的不变量与编辑几何住
/// `lib/annotation/local_mirror.dart`，本件只承载值对象与其自带编解码。
library;

import 'document_codec.dart';

/// 局部镜像片段字段 id（元素类型自带字段单一声明）。
enum LocalMirrorFragmentField { startMs, endMs }

/// 一条局部镜像片段（不可变值对象）。
///
/// 时间区间为半开 `[startMs, endMs)`（毫秒），钳在视频首尾有效区间内。
/// 同视频的片段表保持按 [startMs] 升序且两两不重叠
/// （见 [isSortedAndNonOverlapping]）——不变量由编辑侧逐 verb 维持。
class LocalMirrorFragment {
  const LocalMirrorFragment({
    required this.startMs,
    required this.endMs,
    this.extra = const {},
  });

  /// 区间起点（毫秒，含）。
  final int startMs;

  /// 区间终点（毫秒，不含——半开区间）。
  final int endMs;

  /// 未知键保底区（原样带回、写回原样；不参与相等比较）。
  final Map<String, Object?> extra;

  LocalMirrorFragment copyWith({
    int? startMs,
    int? endMs,
    Map<String, Object?>? extra,
  }) {
    return LocalMirrorFragment(
      startMs: startMs ?? this.startMs,
      endMs: endMs ?? this.endMs,
      extra: extra ?? this.extra,
    );
  }

  /// 相等/哈希由字段声明派生（保底区不参与）。
  @override
  bool operator ==(Object other) =>
      other is LocalMirrorFragment && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);

  @override
  String toString() => 'LocalMirrorFragment(startMs: $startMs, endMs: $endMs)';

  /// 片段自带编解码（键名/读/写/相等在同一处声明）。
  static const RecordCodec<LocalMirrorFragment, LocalMirrorFragmentField>
  codec = RecordCodec<LocalMirrorFragment, LocalMirrorFragmentField>(
    ids: LocalMirrorFragmentField.values,
    decl: _decl,
    build: _build,
    extraOf: _extraOf,
    withExtra: _withExtra,
    required: {
      LocalMirrorFragmentField.startMs,
      LocalMirrorFragmentField.endMs,
    },
  );

  /// 写出（元素层保底区先展开，已登记字段后写）。
  Map<String, Object?> toJson() => codec.encode(this);

  /// 读取；`startMs`/`endMs` 任一缺失或类型不符（必填）视为损坏条目，
  /// 返回 null（调用方丢弃）。
  static LocalMirrorFragment? fromJson(Object? raw) => codec.tryDecode(raw);

  /// 元素表 ↔ JSON 数组：跳过损坏条目、保留合法项。
  static List<LocalMirrorFragment> fromJsonList(Object? raw) =>
      codec.decodeList(raw);
}

FieldDecl<LocalMirrorFragment> _decl(LocalMirrorFragmentField id) =>
    switch (id) {
      LocalMirrorFragmentField.startMs => FieldDecl(
        key: 'startMs',
        read: (json) => switch (json['startMs']) {
          int v => v,
          _ => null,
        },
        write: (fragment) => fragment.startMs,
        equal: (a, b) => a.startMs == b.startMs,
      ),
      LocalMirrorFragmentField.endMs => FieldDecl(
        key: 'endMs',
        read: (json) => switch (json['endMs']) {
          int v => v,
          _ => null,
        },
        write: (fragment) => fragment.endMs,
        equal: (a, b) => a.endMs == b.endMs,
      ),
    };

LocalMirrorFragment _build(Map<LocalMirrorFragmentField, Object?> values) =>
    LocalMirrorFragment(
      startMs: values[LocalMirrorFragmentField.startMs] as int? ?? 0,
      endMs: values[LocalMirrorFragmentField.endMs] as int? ?? 0,
    );

Map<String, Object?> _extraOf(LocalMirrorFragment fragment) => fragment.extra;

LocalMirrorFragment _withExtra(
  LocalMirrorFragment fragment,
  Map<String, Object?> extra,
) => fragment.copyWith(extra: extra);
