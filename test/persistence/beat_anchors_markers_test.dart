import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/persistence/marker_document.dart';

/// 公开 markers `corrections` 段的八拍锚点与节拍对齐平移量：
/// 锚点 = **拍序号数组**（升序、去重），随标记文件保存与分享；两者是
/// 对 `beat` 生成物的人工修正、与拍点表分段正交。
/// 参与文档相等性判定（「无变化不重写」写盘门禁自动覆盖）。

BeatGrid grid({double shift = 0, List<int> anchors = const []}) => BeatGrid(
  model: 'm.onnx',
  fps: 100,
  generatedAt: DateTime.utc(2026, 9, 10),
  shift: shift,
  anchors: anchors,
  beats: const [BeatPoint(t: 0.5, down: true)],
);

void main() {
  group('corrections 段八拍锚点与平移量', () {
    test('缺省 = 空/0；写定值往返；JSON 键名为 corrections.shift/anchors', () {
      final emptyDoc = MarkersDocument(beat: grid());
      expect(emptyDoc.beat?.anchors, isEmpty);
      expect(emptyDoc.beat?.shift, 0);
      final emptyJson = emptyDoc.toJson();
      expect(emptyJson['corrections']['shift'], 0);
      // 承诺：无锚点时 corrections 不产出 anchors 键。
      expect((emptyJson['corrections'] as Map).containsKey('anchors'), isFalse);

      final anchored = MarkersDocument(
        beat: grid(shift: 0.37, anchors: const [4, 12]),
      );
      final restored = MarkersDocument.fromJson(anchored.toJson());
      expect(restored.beat?.anchors, [4, 12]);
      expect(restored.beat?.shift, 0.37);
    });

    test('beat 段是纯生成物：shift/anchors 不在 beat 段内', () {
      final json = MarkersDocument(beat: grid(shift: 0.25, anchors: const [4]))
          .toJson();
      expect(json['beat'], {
        'model': 'm.onnx',
        'fps': 100,
        'generatedAt': '2026-09-10T00:00:00.000Z',
        'beats': [
          {'t': 0.5, 'down': true},
        ],
      });
      expect(json['corrections'], {
        'shift': 0.25,
        'anchors': [4],
      });
    });

    test('文件缺 corrections 键读为 0/空；corrections 段未知键保留', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'generatedAt': '2026-09-10T00:00:00.000Z',
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
      });
      expect(doc.beat?.anchors, isEmpty);
      expect(doc.beat?.shift, 0);

      final withFuture = MarkersDocument.fromJson(const {
        'version': 8,
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'generatedAt': '2026-09-10T00:00:00.000Z',
          'beats': [],
        },
        'corrections': {'shift': 0.25, 'corrFuture': 1},
      });
      final written = withFuture.toJson();
      expect(written['corrections']['corrFuture'], 1);
      expect(written['corrections']['shift'], 0.25);
    });

    test('读入规范化：升序去重、只收整数、忽略非法项', () {
      final parsed = MarkersDocument.fromJson(const {
        'version': 8,
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'generatedAt': '2026-09-10T00:00:00.000Z',
          'beats': [],
        },
        'corrections': {
          'anchors': [12, 4, 4, 'x', 7.5, null],
        },
      });
      expect(parsed.beat?.anchors, [4, 12]);
    });

    test('已登记边缘态：corrections 在而 beat 缺席 → 修正值丢弃（与 v1 等价）', () {
      // corrections 只在网格就绪后经编辑链产生，正常文件不会出现该形态；
      // 行为在此显式登记：无处装配的修正值被丢弃、写回为 {shift: 0.0}。
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'corrections': {
          'shift': 0.25,
          'anchors': [4],
        },
      });
      expect(doc.beat, isNull);
      expect(doc.toJson()['corrections'], {'shift': 0.0});
    });

    test('withAnchors 纯函数；withShift 保留锚点（节拍对齐不甩锚）', () {
      final base = grid(anchors: const [4]);
      final shifted = base.withShift(0.37);

      expect(shifted.anchors, [4], reason: 'Δ 平移只改派生时刻、不改锚点序号');
      expect(shifted.shift, 0.37);
      expect(base.shift, 0, reason: '非破坏：原实例不变');
      expect(base.withAnchors(const [8]).anchors, [8]);
      expect(base.anchors, [4]);
    });

    test('锚点与平移量参与相等性判定与哈希（仅其一变化亦视为有变化）', () {
      expect(grid(anchors: const [4]), grid(anchors: const [4]));
      expect(
        grid(anchors: const [4]).hashCode,
        grid(anchors: const [4]).hashCode,
      );
      expect(grid(anchors: const [4]) == grid(anchors: const [4, 12]), isFalse);
      expect(grid() == grid(anchors: const [4]), isFalse);
      expect(grid(shift: 0.25) == grid(), isFalse);
      expect(
        MarkersDocument(beat: grid(anchors: const [4])),
        MarkersDocument(beat: grid(anchors: const [4])),
      );
      expect(
        MarkersDocument(beat: grid(anchors: const [4])) ==
            MarkersDocument(beat: grid()),
        isFalse,
      );
    });
  });
}
