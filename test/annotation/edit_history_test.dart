import 'package:dance_learning_app/annotation/edit_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  EditHistory<int> record3(EditHistory<int> h) => h
      .record(0, 1)
      .record(1, 2)
      .record(2, 3);

  group('EditHistory 纯函数（撤销/重做命令历史）', () {
    test('空历史：不可撤销不可重做，undo/redo 返回 null 且不改变历史', () {
      const history = EditHistory<int>.empty();
      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);

      final (afterUndo, undoValue) = history.undo();
      expect(undoValue, isNull);
      expect(afterUndo, history);

      final (afterRedo, redoValue) = history.redo();
      expect(redoValue, isNull);
      expect(afterRedo, history);
    });

    test('记录后可撤销到 before，再重做到 after', () {
      final history = EditHistory<int>.empty().record(0, 1);
      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);

      final (undone, undoValue) = history.undo();
      expect(undoValue, 0);
      expect(undone.canUndo, isFalse);
      expect(undone.canRedo, isTrue);

      final (redone, redoValue) = undone.redo();
      expect(redoValue, 1);
      expect(redone.canUndo, isTrue);
      expect(redone.canRedo, isFalse);
    });

    test('连续多步：逐次撤销逆序回放，重做正序回放', () {
      final history = record3(const EditHistory.empty());
      expect(history.length, 3);

      final (h1, v1) = history.undo();
      final (h2, v2) = h1.undo();
      final (h3, v3) = h2.undo();
      expect(v1, 2);
      expect(v2, 1);
      expect(v3, 0);
      expect(h3.canUndo, isFalse);

      final (r1, rv1) = h3.redo();
      final (r2, rv2) = r1.redo();
      final (r3, rv3) = r2.redo();
      expect(rv1, 1);
      expect(rv2, 2);
      expect(rv3, 3);
      expect(r3.canRedo, isFalse);
    });

    test('撤销后新记录清除重做分支', () {
      final history = record3(const EditHistory.empty()).undo().$1;
      expect(history.canRedo, isTrue);

      final branched = history.record(2, 9);
      expect(branched.canRedo, isFalse);
      expect(branched.length, 3);
      expect(branched.undo().$2, 2);
    });

    test('no-op 过滤不在本类（提交链按段判空后 no-op 不到达 record）', () {
      // 纯库不再防御 before==after（上层收口 seam 已按段判空，
      // 重复不变量已删）——同值对入史照记。
      final history = EditHistory<int>.empty().record(0, 1).record(1, 1);
      expect(history.length, 2);
    });

    test('容量上限：超过 50 步丢弃最旧', () {
      var history = const EditHistory<int>.empty();
      for (var i = 0; i < 55; i++) {
        history = history.record(i, i + 1);
      }
      expect(history.length, 50);

      // 最旧可撤销到的 before = 第 6 次编辑前（0..5 已被丢弃）。
      var h = history;
      int? lastUndo;
      while (h.canUndo) {
        final (next, value) = h.undo();
        lastUndo = value;
        h = next;
      }
      expect(lastUndo, 5);
    });

    test('clear 清空撤销与重做', () {
      final history = record3(const EditHistory.empty()).undo().$1;
      final cleared = history.clear();
      expect(cleared.canUndo, isFalse);
      expect(cleared.canRedo, isFalse);
      expect(cleared.length, 0);
    });
  });
}
