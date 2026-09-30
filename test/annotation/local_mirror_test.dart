import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';

///  数据基座直测：局部镜像片段值类型与升序/不重叠不变量谓词。
void main() {
  group('LocalMirrorFragment 值类型', () {
    test('构造只持有 startMs/endMs 两字段（片段 = 纯区间）', () {
      const fragment = LocalMirrorFragment(startMs: 1000, endMs: 3000);
      expect(fragment.startMs, 1000);
      expect(fragment.endMs, 3000);
    });

    test('copyWith 只改声明字段，其余保持', () {
      const fragment = LocalMirrorFragment(startMs: 1000, endMs: 3000);
      final moved = fragment.copyWith(startMs: 2000);
      expect(moved, const LocalMirrorFragment(startMs: 2000, endMs: 3000));
      expect(fragment, const LocalMirrorFragment(startMs: 1000, endMs: 3000));
    });

    test('相等按两字段深比较、参与 hashCode', () {
      const a = LocalMirrorFragment(startMs: 1000, endMs: 3000);
      const b = LocalMirrorFragment(startMs: 1000, endMs: 3000);
      const c = LocalMirrorFragment(startMs: 1000, endMs: 3001);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('片段表升序/不重叠不变量谓词（纯结构）', () {
    test('空表与单元素恒成立', () {
      expect(isSortedAndNonOverlapping(const []), isTrue);
      expect(
        isSortedAndNonOverlapping(const [
          LocalMirrorFragment(startMs: 1000, endMs: 3000),
        ]),
        isTrue,
      );
    });

    test('按 startMs 升序且两两不重叠成立', () {
      expect(
        isSortedAndNonOverlapping(const [
          LocalMirrorFragment(startMs: 1000, endMs: 2000),
          LocalMirrorFragment(startMs: 2000, endMs: 3000),
          LocalMirrorFragment(startMs: 5000, endMs: 6000),
        ]),
        isTrue,
      );
    });

    test('相邻半开区间共享端点为不重叠（endMs <= 下一 startMs）', () {
      expect(
        isSortedAndNonOverlapping(const [
          LocalMirrorFragment(startMs: 1000, endMs: 2000),
          LocalMirrorFragment(startMs: 2000, endMs: 3000),
        ]),
        isTrue,
      );
    });

    test('重叠（后段起点落入前段）判否', () {
      expect(
        isSortedAndNonOverlapping(const [
          LocalMirrorFragment(startMs: 1000, endMs: 2500),
          LocalMirrorFragment(startMs: 2000, endMs: 3000),
        ]),
        isFalse,
      );
    });

    test('乱序（未按 startMs 升序）判否', () {
      expect(
        isSortedAndNonOverlapping(const [
          LocalMirrorFragment(startMs: 3000, endMs: 4000),
          LocalMirrorFragment(startMs: 1000, endMs: 2000),
        ]),
        isFalse,
      );
    });
  });
}
