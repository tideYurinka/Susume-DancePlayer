import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/framing_selection.dart' show FramingSelection;

/// 取景会话态：取景只有**源画面**一份，取值
/// 即**取景选区** [FramingSelection]（源画面上圈出的矩形，四边按源画面原相
/// 归一化）。没有可切换的作用对象，也就没有「当前作用侧」。
///
/// **取值随这支舞记住**：住公开标记文件 `meta` 段，打开恢复由装载表
/// 的公开标记文件行就位（组员方案装载时取方案文档里的值）；调整经「变更即存」
/// 直写标记文件（不入撤销史、不受锁定分段门禁）。本地文档不承载取景。
class FramingState {
  const FramingState({this.source});

  /// 源画面取景选区；null = 未调过（按整帧 contain 起手）。
  final FramingSelection? source;

  /// 源画面是否已被调过（取值非空即真）。
  bool get sourceTouched => source != null;

  @override
  bool operator ==(Object other) =>
      other is FramingState && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

/// 取景会话值模型：写意图各有具名入口——[applySource]（手势提交的取值，
/// null = 清除）、[restoreSource]（打开恢复）、[reset] 清源侧选区（复位 =
/// 清除取值，回整帧）。
class FramingSessionModel extends Notifier<FramingState> {
  @override
  FramingState build() => const FramingState();

  /// 唯一提交点（值没变就不惊动监听者——同值时 no-op，避免空写触发
  /// 「变更即存」）。
  void _commit(FramingState next) {
    if (next != state) state = next;
  }

  /// 写入源画面取景选区（调用方先经纯件钳制）；null = 清除取值。选区非空即
  /// 「已调过」。
  void applySource(FramingSelection? selection) =>
      _commit(FramingState(source: selection));

  /// 源画面取景选区的打开恢复：由装载表的公开标记文件行就位（组员
  /// 方案装载时即方案文档里的值——方案值生效）。null = 该文档未调过；只读
  /// 装载，不产生写盘（与 [applySource] 同走唯一提交点：值没变就不惊动
  /// 监听者，不触发空写）。
  void restoreSource(FramingSelection? selection) {
    _commit(FramingState(source: selection));
  }

  /// 复位：**清源侧选区**（回整帧）；只改会话值，
  /// 不改素材或任何文件。
  void reset() {
    _commit(const FramingState());
  }
}

/// 取景会话态注入点。
final framingStateProvider =
    NotifierProvider<FramingSessionModel, FramingState>(
      FramingSessionModel.new,
    );
