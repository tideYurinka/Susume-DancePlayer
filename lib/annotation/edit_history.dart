/// 会话内编辑命令历史（撤销/重做）的纯函数值类型。
///
/// 历史以「前后状态快照对」记录每个编辑命令（before/after）；撤销/重做
/// 只返回应回放的目标快照，由调用侧经既有模型操作写回（重放语义），本
/// 类不接触任何模型。不变式：
///
///   1. 容量上限 50 条（[defaultCapacity]），超限丢弃最旧；
///   2. 撤销后新记录清除重做分支（标准线性历史语义）。
///
/// no-op 过滤不在本类——提交链按段判空后 no-op 不到达 [record]，
/// 上层收口 seam 是唯一入史入口。
library;

/// 一条编辑命令：编辑前快照 [before] 与编辑后快照 [after]。
class EditHistoryEntry<T> {
  const EditHistoryEntry({required this.before, required this.after});

  final T before;
  final T after;

  @override
  bool operator ==(Object other) =>
      other is EditHistoryEntry<T> &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(before, after);
}

/// 不可变撤销/重做历史（记录/撤销/重做/清空均为返回新实例的纯操作）。
class EditHistory<T> {
  /// 会话内命令历史上限。
  static const int defaultCapacity = 50;

  const EditHistory._(this._entries, this._cursor, this.capacity)
    : assert(_cursor >= 0 && _cursor <= _entries.length),
      assert(_entries.length <= capacity);

  const EditHistory.empty({this.capacity = defaultCapacity})
    : _entries = const [],
      _cursor = 0;

  /// 已撤销条目居左、未撤销条目居右的单一游标实现：
  /// `_entries` 全量保存，`_cursor` 指向「当前时间点」——左侧为可重做
  /// （含 cursor 位置起），cursor 之前为已撤销、之后为已记录。
  final List<EditHistoryEntry<T>> _entries;

  final int _cursor;

  /// 历史容量（测试可注入小值验证淘汰）。
  final int capacity;

  /// 可撤销的命令条数（同时 = 撤销栈深度）。
  int get length => _cursor;

  bool get canUndo => _cursor > 0;

  bool get canRedo => _cursor < _entries.length;

  /// 记录一条编辑命令；新记录清除重做分支。
  EditHistory<T> record(T before, T after) {
    final kept = List<EditHistoryEntry<T>>.of(_entries.take(_cursor))
      ..add(EditHistoryEntry(before: before, after: after));
    // 超容量丢弃最旧（游标随之上移，保持 canUndo 语义）。
    var dropped = 0;
    if (kept.length > capacity) {
      dropped = kept.length - capacity;
      kept.removeRange(0, dropped);
    }
    return EditHistory._(
      List.unmodifiable(kept),
      _cursor + 1 - dropped,
      capacity,
    );
  }

  /// 撤销一步（快照对缝）：返回（新历史, 被撤销条目的前后快照对）；
  /// 无可撤销时条目为 null 且历史不变。回放语义（含逐 id 作用域）由
  /// 调用侧决定，本类只交出值。
  (EditHistory<T>, EditHistoryEntry<T>?) undoEntry() {
    if (!canUndo) return (this, null);
    return (
      EditHistory._(_entries, _cursor - 1, capacity),
      _entries[_cursor - 1],
    );
  }

  /// 重做一步（快照对缝）：返回（新历史, 被重做条目的前后快照对）；
  /// 无可重做时条目为 null 且历史不变。
  (EditHistory<T>, EditHistoryEntry<T>?) redoEntry() {
    if (!canRedo) return (this, null);
    return (EditHistory._(_entries, _cursor + 1, capacity), _entries[_cursor]);
  }

  /// 撤销一步：返回（新历史, 应回放的 before 快照）；无可撤销时快照为
  /// null 且历史不变。
  (EditHistory<T>, T?) undo() {
    final (next, entry) = undoEntry();
    return (next, entry?.before);
  }

  /// 重做一步：返回（新历史, 应回放的 after 快照）；无可重做时同上。
  (EditHistory<T>, T?) redo() {
    final (next, entry) = redoEntry();
    return (next, entry?.after);
  }

  /// 清空全部历史（换视频/重新打开）。
  EditHistory<T> clear() => EditHistory.empty(capacity: capacity);

  @override
  bool operator ==(Object other) {
    if (other is! EditHistory<T>) return false;
    if (other._cursor != _cursor ||
        other.capacity != capacity ||
        other._entries.length != _entries.length) {
      return false;
    }
    for (var i = 0; i < _entries.length; i++) {
      if (other._entries[i] != _entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(_cursor, capacity, Object.hashAll(_entries));
}
