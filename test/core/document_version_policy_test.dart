import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/core/document_version_policy.dart';

/// 文档版本政策纯件（缝 1 · 版本政策值）——只喂盘上 JSON，断言读结局
/// （升位后的 JSON + 可写性），不碰文件系统。
void main() {
  const floor = 7;

  DocumentVersionPolicy policy() => DocumentVersionPolicy(
    floor: floor,
    steps: [
      // 两步链：7 → 8 → 9。每级只改形状，不写版本号。
      MigrationStep(
        7,
        (json) => {...json, 'shape': 'v8', 'saw': json['version']},
      ),
      MigrationStep(
        8,
        (json) => {...json, 'shape': 'v9', 'saw2': json['version']},
      ),
    ],
  );

  group('六支分类梯', () {
    test('文件不在 → 空 JSON 且可写', () {
      final r = policy().upgrade(null);
      expect(r.json, isEmpty);
      expect(r.writable, isTrue);
    });

    test('本体非对象 → 不认且不可写', () {
      final r = policy().upgrade('not a map');
      expect(r.writable, isFalse);
    });

    test('版本头不是整数 → 不认且不可写', () {
      final r = policy().upgrade({'version': '7', 'x': 1});
      expect(r.writable, isFalse);
    });

    test('类型参数不符的 Map 收敛进判据，不逃出分类梯', () {
      final odd = <String, int>{'version': 7};
      final r = policy().upgrade(odd);
      expect(r.writable, isTrue);
      expect(r.json['version'], 9);
      // 非 String 键收敛不出对象 → 不认且不可写。
      final nonStringKeys = <int, String>{7: 'seven'};
      final r2 = policy().upgrade(nonStringKeys);
      expect(r2.writable, isFalse);
    });

    test('高于本版 → 原样且不可写（零拷贝）', () {
      final raw = <String, Object?>{'version': 10, 'x': 1};
      final r = policy().upgrade(raw);
      expect(r.writable, isFalse);
      expect(identical(r.json, raw), isTrue);
      expect(r.json['x'], 1);
    });

    test('低于地板 → 空 JSON 且不可写（低于地板属只读）', () {
      final r = policy().upgrade({'version': 5, 'x': 1});
      expect(r.json, isEmpty);
      expect(r.writable, isFalse);
    });

    test('在链上 → 升到本版且可写', () {
      final r = policy().upgrade({'version': 7, 'x': 1});
      expect(r.writable, isTrue);
      expect(r.json['version'], 9);
      expect(r.json['shape'], 'v9');
      expect(r.json['x'], 1);
    });
  });

  group('按序迁移链', () {
    test('中间版本逐级升位：两级按序各跑一次，版本逐级 +1', () {
      final seen = <Object?>[];
      final p = DocumentVersionPolicy(
        floor: 7,
        steps: [
          MigrationStep(7, (json) {
            seen.add(json['version']);
            return {...json, 'a': 1};
          }),
          MigrationStep(8, (json) {
            seen.add(json['version']);
            return {...json, 'b': 2};
          }),
        ],
      );
      final r = p.upgrade({'version': 7});
      expect(r.writable, isTrue);
      expect(r.json['version'], 9);
      expect(r.json['a'], 1);
      expect(r.json['b'], 2);
      // 政策在每级之后自己写版本号：第一级进来 7、第二级进来 8。
      expect(seen, [7, 8]);
    });

    test('步骤不写版本号也成立（本版版本号是链尾派生量）', () {
      final p = DocumentVersionPolicy(
        floor: 3,
        steps: [
          MigrationStep(3, (json) => <String, Object?>{'only': 'shape'}),
          MigrationStep(4, (json) => <String, Object?>{'again': true}),
        ],
      );
      final r = p.upgrade({'version': 3});
      expect(r.json['version'], 5);
      expect(p.currentVersion, 5);
    });

    test('同版本打开零拷贝，不走升位链', () {
      final raw = <String, Object?>{'version': 9, 'x': 1};
      final r = policy().upgrade(raw);
      expect(r.writable, isTrue);
      expect(identical(r.json, raw), isTrue);
    });

    test('坏文件两支（非对象、版本头非整数）都不走升位链', () {
      var called = false;
      final p = DocumentVersionPolicy(
        floor: 7,
        steps: [
          MigrationStep(7, (json) {
            called = true;
            return json;
          }),
          MigrationStep(8, (json) => json),
        ],
      );
      p.upgrade([1, 2]);
      p.upgrade({'version': '7'});
      expect(called, isFalse);
    });
  });

  group('陌生键保底区随行', () {
    test('文档级、段级、元素级陌生键在升位后仍在', () {
      final p = DocumentVersionPolicy(
        floor: 1,
        steps: [
          MigrationStep(1, (json) {
            // 只动已登记形状：重写 sections 列表里的已知字段，逐层展开时
            // 保留各自未认识的键。
            final sections = (json['sections'] as List).map((raw) {
              final seg = Map<String, Object?>.from(raw as Map);
              final elements = (seg['elements'] as List).map((e) {
                final el = Map<String, Object?>.from(e as Map);
                return {...el, 'label': 'kept'};
              }).toList();
              return {...seg, 'elements': elements, 'title': 'kept'};
            }).toList();
            return {...json, 'sections': sections};
          }),
        ],
      );
      final r = p.upgrade({
        'version': 1,
        'docUnknown': 'doc-level',
        'sections': [
          {
            'segUnknown': 'seg-level',
            'elements': [
              {'elUnknown': 'element-level'},
            ],
          },
        ],
      });
      expect(r.writable, isTrue);
      expect(r.json['docUnknown'], 'doc-level');
      final seg = (r.json['sections'] as List).first as Map;
      expect(seg['segUnknown'], 'seg-level');
      final el = (seg['elements'] as List).first as Map;
      expect(el['elUnknown'], 'element-level');
    });

    test('迁移不改写输入的 JSON（步骤浅拷贝，原对象不被共享可变状态污染）', () {
      final raw = <String, Object?>{'version': 7, 'x': 1};
      policy().upgrade(raw);
      expect(raw, {'version': 7, 'x': 1});
    });
  });

  group('写侧可写性判定（唯一入口）', () {
    test('可写性与 upgrade 一致；空 Map 按「文件不在」判（原始文件缝哨兵）', () {
      expect(policy().isWritable(null), isTrue);
      expect(policy().isWritable({'version': 7}), isTrue);
      expect(policy().isWritable({'version': 10}), isFalse);
      expect(policy().isWritable({'version': '7'}), isFalse);
      expect(policy().isWritable({'version': 5}), isFalse);
      expect(policy().isWritable('not a map'), isFalse);
      // `AtomicJsonFile.read` 以空 Map 表示「文件不在/损坏」：按文件不在判，
      // 首建不被版本门挡住。
      expect(policy().isWritable(const <String, Object?>{}), isTrue);
    });
  });

  group('异常与构造期护栏', () {
    test('步骤抛出的异常向上穿透，绝不下降为空态', () {
      final p = DocumentVersionPolicy(
        floor: 7,
        steps: [
          MigrationStep(
            7,
            (json) => throw StateError('bad migration'),
          ),
          MigrationStep(8, (json) => json),
        ],
      );
      expect(() => p.upgrade({'version': 7}), throwsStateError);
    });

    test('乱序或倒退声明在构造期即失败', () {
      expect(
        () => DocumentVersionPolicy(
          floor: 7,
          steps: [
            MigrationStep(8, (json) => json),
            MigrationStep(7, (json) => json),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('重复声明在构造期即失败', () {
      expect(
        () => DocumentVersionPolicy(
          floor: 7,
          steps: [
            MigrationStep(7, (json) => json),
            MigrationStep(7, (json) => json),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('抬版本号却缺一级不可表达：跳级声明构造期即失败', () {
      expect(
        () => DocumentVersionPolicy(
          floor: 7,
          steps: [
            MigrationStep(7, (json) => json),
            MigrationStep(9, (json) => json),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('首级不落在地板上在构造期即失败', () {
      expect(
        () => DocumentVersionPolicy(
          floor: 7,
          steps: [MigrationStep(6, (json) => json)],
        ),
        throwsArgumentError,
      );
    });
  });
}
