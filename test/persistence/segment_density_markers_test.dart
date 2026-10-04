import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

/// 公开 markers `annotations` 段的逐段档字段（见词条「段内倍频」）：
/// 键为段序、值只收 ×½ / ×2 两档，只写非原样档；
/// 逐段档字段升版（v8），旧版本文件读为空。

void main() {
  group('annotations 段逐段档字段', () {
    test('缺省不写：无逐段档时文件无 segmentDensities 键，读回空表', () {
      final json = MarkersDocument().toJson();
      expect(
        (json['annotations'] as Map).containsKey('segmentDensities'),
        isFalse,
      );
      final restored = MarkersDocument.fromJson(json);
      expect(restored.segmentDensities, isEmpty);
    });

    test('写定档位往返：JSON 键 annotations.segmentDensities，键为段序字符串', () {
      const doc = MarkersDocument(segmentDensities: {0: 0.5, 2: 2.0});
      expect(doc.toJson()['annotations']['segmentDensities'], {
        '0': 0.5,
        '2': 2.0,
      });
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.segmentDensities, {0: 0.5, 2: 2.0});
      expect(restored, doc);
    });

    test('只写非原样档：档值 1 不落键；原样键读回即消失（删键语义）', () {
      final written = MarkersDocument(segmentDensities: {0: 1.0, 1: 2.0})
          .toJson()['annotations']['segmentDensities'];
      expect(written, {'1': 2.0});
      // 回原样后重写：该键从文件消失。
      final afterReset = MarkersDocument(segmentDensities: {0: 2.0})
          .toJson()['annotations']['segmentDensities'];
      expect(afterReset, {'0': 2.0});
      final cleared = MarkersDocument.fromJson(
        MarkersDocument(segmentDensities: {0: 2.0}).toJson(),
      );
      expect(
        MarkersDocument(segmentDensities: {})
            .toJson()['annotations']
            .containsKey('segmentDensities'),
        isFalse,
      );
      expect(cleared.segmentDensities, {0: 2.0});
    });

    test('损坏值兜底：未知档位 / 负段序 / 非整数键 / 类型不符读为空表', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'annotations': {
          'segmentDensities': {
            '0': 3.0,
            '1': 1.0,
            '-2': 2.0,
            'x': 2.0,
            '4': '2',
            '5': 0.5,
          },
        },
      });
      expect(doc.segmentDensities, {5: 0.5});
    });

    test('annotations 段未知键保底不变（segmentDensities 与陌生键共存）', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'annotations': {
          'segmentDensities': {'0': 2.0},
          'futureKey': {'a': 1},
        },
      });
      expect(doc.segmentDensities, {0: 2.0});
      expect(doc.annotationsExtra, {
        'futureKey': {'a': 1},
      });
      final out = doc.toJson()['annotations'] as Map;
      expect(out['futureKey'], {'a': 1});
    });

    test('逐段档不触碰其它面：线与几何时刻原样往返', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 8,
        'annotations': {
          'range': {'startMs': 0, 'endMs': 60000},
          'segmentLines': [
            {'timeMs': 5000, 'flag': false},
          ],
          'halfBeatLines': [
            {'timeMs': 2500},
          ],
          'localMirrorFragments': [
            {'startMs': 1000, 'endMs': 2000},
          ],
          'segmentDensities': {'0': 2.0},
        },
      });
      expect(doc.segmentLines.first.position, const Duration(seconds: 5));
      expect(
        doc.halfBeatLines.first.position,
        const Duration(milliseconds: 2500),
      );
      expect(doc.localMirrorFragments.first.startMs, 1000);
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.segmentLines, doc.segmentLines);
      expect(restored.halfBeatLines, doc.halfBeatLines);
      expect(restored.localMirrorFragments, doc.localMirrorFragments);
    });
  });

  group('版本门（v9）', () {
    test('当前 schema 版本 = 9', () {
      expect(MarkersDocument.versionPolicy.currentVersion, 9);
      final doc = MarkersDocument(segmentDensities: {0: 2.0});
      expect(doc.toJson()['version'], 9);
    });

    test('v7 旧文件沿迁移链读起：内容照读、不整份丢弃', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 7,
        'meta': {'mirrored': true},
      });
      expect(doc.mirrored, isTrue);
      // 旧文件没有逐段档键：缺省即「原样」，不预写。
      expect(doc.segmentDensities, isEmpty);
    });

    test('v6 更老且无迁移：仍整份丢弃', () {
      final doc = MarkersDocument.fromJson(const {
        'version': 6,
        'meta': {'mirrored': true},
      });
      expect(doc, const MarkersDocument.empty());
      expect(doc.segmentDensities, isEmpty);
      expect(doc.mirrored, isFalse);
    });
  });

  group('段值装配（MarkerAnnotationsValue）', () {
    test('withAnnotations 装配逐段档与其它标注面', () {
      final doc = MarkersDocument().withAnnotations(
        const MarkerAnnotationsValue(
          emphasizedSegments: {1},
          segmentDensities: {0: 0.5, 3: 2.0},
        ),
      );
      expect(doc.segmentDensities, {0: 0.5, 3: 2.0});
      expect(doc.emphasizedSegments, [1]);
    });

    test('段值相等性含逐段档（无变化不重写门禁覆盖）', () {
      expect(
        const MarkerAnnotationsValue(segmentDensities: {0: 2.0}),
        const MarkerAnnotationsValue(segmentDensities: {0: 2.0}),
      );
      expect(
        const MarkerAnnotationsValue(segmentDensities: {0: 2.0}),
        isNot(const MarkerAnnotationsValue(segmentDensities: {0: 0.5})),
      );
      expect(
        const MarkerAnnotationsValue(segmentDensities: {0: 2.0}),
        isNot(const MarkerAnnotationsValue(segmentDensities: {1: 2.0})),
      );
    });
  });
}
