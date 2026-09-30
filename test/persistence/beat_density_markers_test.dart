import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

/// 公开 markers `corrections` 段的节拍倍频字段：
/// 缺省不写该键 = 原样；升 v7、升 v8，旧版本文件读为空。

BeatGrid grid({double density = 1}) => BeatGrid(
  model: 'm.onnx',
  fps: 100,
  generatedAt: DateTime.utc(2026, 9, 17),
  density: density,
  beats: const [BeatPoint(t: 0.5, down: true)],
);

void main() {
  group('corrections 段节拍倍频字段', () {
    test('缺省 = 原样：不写 density 键；读回为 1', () {
      final json = MarkersDocument(beat: grid()).toJson();
      expect(
        (json['corrections'] as Map).containsKey('density'),
        isFalse,
      );
      final restored = MarkersDocument.fromJson(json);
      expect(restored.beat?.density, 1);
    });

    test('写定档位往返：JSON 键 corrections.density，读回同档', () {
      final doc = MarkersDocument(beat: grid(density: 2));
      expect(doc.toJson()['corrections']['density'], 2);
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.beat?.density, 2);
    });

    test('五档值均可往返；损坏值（不在五档内）读为原样兜底', () {
      for (final value in const [0.25, 0.5, 1.0, 2.0, 4.0]) {
        final restored = MarkersDocument.fromJson(
          MarkersDocument(beat: grid(density: value)).toJson(),
        );
        expect(restored.beat?.density, value);
      }
      final corrupt = MarkersDocument.fromJson(const {
        'version': 8,
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
        'corrections': {'density': 3},
      });
      expect(corrupt.beat?.density, 1);
    });

    test('corrections 段未知键保底不变（density 与陌生键共存）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
        'corrections': {'density': 2, 'futureKey': {'a': 1}},
      });
      expect(doc.beat?.density, 2);
      expect(doc.correctionsExtra, {
        'futureKey': {'a': 1},
      });
      final out = doc.toJson()['corrections'] as Map;
      expect(out['futureKey'], {'a': 1});
    });

    test('历史文件形态：无 density 键读为原样（density 引入前的所有档位缺省）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
        'corrections': {'shift': 0.25, 'anchors': [4]},
      });
      expect(doc.beat?.density, 1);
      expect(doc.beat?.shift, 0.25);
      expect(doc.beat?.anchors, [4]);
    });
  });

  group('版本门（v9）', () {
    test('当前 schema 版本 = 9', () {
      expect(MarkersDocument.versionPolicy.currentVersion, 9);
      final doc = MarkersDocument(beat: grid(density: 2));
      expect(doc.toJson()['version'], 9);
    });

    test('v6 旧文件读为空态：识别拍点语义与规整产物不同，整份丢弃', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 6,
        'meta': {'mirrored': true},
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
        'corrections': {'density': 2},
      });
      expect(doc, const MarkersDocument.empty());
      expect(doc.beat, isNull);
      expect(doc.mirrored, isFalse);
    });

    test('v5 旧文件读为空态', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 5,
        'meta': {'mirrored': true},
        'beat': {
          'model': 'm.onnx',
          'fps': 100,
          'beats': [
            {'t': 0.5, 'down': true},
          ],
        },
        'corrections': {'density': 2},
      });
      expect(doc.beat, isNull);
      expect(doc.mirrored, isFalse);
    });
  });

  group('段值装配（MarkerCorrectionsValue）', () {
    test('withCorrections 装配平移量 + 倍频 + 锚点', () {
      final doc = MarkersDocument(beat: grid()).withCorrections(
        const MarkerCorrectionsValue(
          shiftSeconds: 0.25,
          density: 0.5,
          eightBeatAnchors: [2],
        ),
      );
      expect(doc.beat?.shift, 0.25);
      expect(doc.beat?.density, 0.5);
      expect(doc.beat?.anchors, [2]);
    });

    test('段值相等性含倍频（无变化不重写门禁覆盖）', () {
      expect(
        const MarkerCorrectionsValue(density: 2),
        const MarkerCorrectionsValue(density: 2),
      );
      expect(
        const MarkerCorrectionsValue(density: 2),
        isNot(const MarkerCorrectionsValue(density: 4)),
      );
    });
  });
}
