import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/practice_clip_table_algebra.dart';

PracticeClip clip(String id, int inMs, int outMs) => PracticeClip(
      id: id,
      materialId: 'm_$id',
      materialSourceStartMs: 0,
      inMs: inMs,
      outMs: outMs,
    );

void main() {
  group('逐 id 三方合并（撤销/重做回放）', () {
    test('正常回退：当前[id] == after[id] 时写回 before[id]，其余 id 不动', () {
      final before = [clip('a', 0, 100)];
      final after = [clip('a', 20, 100)];
      final current = [clip('a', 20, 100), clip('b', 200, 300)];

      final result = replayClipTableBySnapshotPair(
        before: before,
        after: after,
        current: current,
      );

      expect(result.clips, [clip('a', 0, 100), clip('b', 200, 300)]);
      expect(result.skippedIds, isEmpty);
    });

    test('冲突跳过：当前[id] != after[id] 视为外部写过，跳过该 id', () {
      final before = [clip('a', 0, 100)];
      final after = [clip('a', 20, 100)];
      final current = [clip('a', 50, 100), clip('b', 200, 300)];

      final result = replayClipTableBySnapshotPair(
        before: before,
        after: after,
        current: current,
      );

      expect(result.clips, [clip('a', 50, 100), clip('b', 200, 300)]);
      expect(result.skippedIds, {'a'});
    });

    test('删除撤销复活：after 无该 id、当前也无 → 写回 before[id]', () {
      final before = [clip('a', 0, 100), clip('b', 200, 300)];
      final after = [clip('b', 200, 300)];
      final current = [clip('b', 200, 300)];

      final result = replayClipTableBySnapshotPair(
        before: before,
        after: after,
        current: current,
      );

      expect(result.clips, [clip('b', 200, 300), clip('a', 0, 100)]);
      expect(result.skippedIds, isEmpty);
    });

    test('删除回放：当前 == after、before 无该 id → 从当前表移除', () {
      final before = [clip('a', 0, 100)];
      final after = [clip('a', 0, 100), clip('b', 200, 300)];
      final current = [clip('a', 0, 100), clip('b', 200, 300)];

      final result = replayClipTableBySnapshotPair(
        before: before,
        after: after,
        current: current,
      );

      expect(result.clips, [clip('a', 0, 100)]);
      expect(result.skippedIds, isEmpty);
    });

    test('混合：正常 id 回退与冲突 id 跳过并存', () {
      final before = [clip('a', 0, 100), clip('c', 400, 500)];
      final after = [clip('a', 20, 100), clip('c', 420, 500)];
      final current = [clip('a', 20, 100), clip('c', 999, 1000)];

      final result = replayClipTableBySnapshotPair(
        before: before,
        after: after,
        current: current,
      );

      expect(result.clips, [clip('a', 0, 100), clip('c', 999, 1000)]);
      expect(result.skippedIds, {'c'});
    });
  });

  group('碰过的 id 集合', () {
    test('before 与 after 有差异的 id 即碰过（改/删/增）', () {
      final before = [
        clip('a', 0, 100),
        clip('b', 200, 300),
        clip('c', 400, 500),
      ];
      final after = [
        clip('a', 20, 100),
        clip('b', 200, 300),
        clip('d', 600, 700),
      ];

      expect(
        clipIdsTouchedByEdit(before: before, after: after),
        {'a', 'c', 'd'},
      );
    });

    test('无差异 = 未碰过', () {
      final table = [clip('a', 0, 100), clip('b', 200, 300)];
      expect(clipIdsTouchedByEdit(before: table, after: table), isEmpty);
    });
  });

  group('表规范化（升序 + 两两不重叠）', () {
    test('按源起点升序重排', () {
      final result = normalizePracticeClipTable([
        clip('b', 200, 300),
        clip('a', 0, 100),
      ]);
      expect(result, [clip('a', 0, 100), clip('b', 200, 300)]);
    });

    test('部分重叠裁到不重叠：钳到邻居边界', () {
      final result = normalizePracticeClipTable([
        clip('a', 0, 100),
        clip('b', 50, 150),
      ]);
      expect(result, [clip('a', 0, 100), clip('b', 100, 150)]);
    });

    test('被完全覆盖的删除', () {
      final result = normalizePracticeClipTable([
        clip('b', 0, 100),
        clip('a', 20, 80),
      ]);
      expect(result, [clip('b', 0, 100)]);
    });

    test('裁后无单一不重叠区间的删除（互罩）', () {
      final result = normalizePracticeClipTable([
        clip('a', 0, 100),
        clip('b', 30, 70),
      ]);
      expect(result, [clip('a', 0, 100)]);
    });

    test('同起点吞没不删：裁掉已收条目区间后仍有单一区间', () {
      final result = normalizePracticeClipTable([
        clip('a', 0, 100),
        clip('b', 0, 150),
      ]);
      expect(result, [clip('a', 0, 100), clip('b', 100, 150)]);
    });
  });
}
