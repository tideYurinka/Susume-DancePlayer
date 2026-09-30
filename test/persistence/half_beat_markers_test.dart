import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

void main() {
  group('MarkersDocument：半拍线落盘往返（公开 markers 侧）', () {
    test('toJson/fromJson 往返保真', () {
      const doc = MarkersDocument(
        rangeStartMs: 0,
        rangeEndMs: 30000,
        halfBeatLines: [HalfBeatLine(position: Duration(milliseconds: 2500))],
      );
      final restored = MarkersDocument.fromJson(doc.toJson());
      expect(restored.halfBeatLines, doc.halfBeatLines);
    });

    test('withHalfBeatLines 补写不丢其它字段', () {
      const doc = MarkersDocument(mirrored: true, rangeStartMs: 100);
      final next = doc.withHalfBeatLines([
        const HalfBeatLine(position: Duration(milliseconds: 5000)),
      ]);
      expect(next.mirrored, isTrue);
      expect(next.rangeStartMs, 100);
      expect(next.halfBeatLines.length, 1);
    });

    test('旧版本缺字段按空列表兜底；未知字段保留', () {
      final doc = MarkersDocument.fromJson({
        'version': 8,
        'custom': {'a': 1},
      });
      expect(doc.halfBeatLines, isEmpty);
      expect(doc.extra['custom'], {'a': 1});
      final written = doc.toJson();
      expect(written['custom'], {'a': 1});
      expect(
        (written['annotations'] as Map).containsKey('halfBeatLines'),
        isTrue,
      );
    });

    test('损坏条目按缺省兜底不崩溃', () {
      final doc = MarkersDocument.fromJson({
        'version': 8,
        'annotations': {
          'halfBeatLines': ['bad', 42, {'timeMs': 1.5}, {'timeMs': 2500}],
        },
      });
      expect(doc.halfBeatLines, [
        const HalfBeatLine(position: Duration(milliseconds: 2500)),
      ]);
    });
  });

  group('AnnotationSectionDiff / 编排器：半拍线随 annotations 段入队', () {
    test('isEmpty 计入半拍线所在段', () {
      expect(
        const AnnotationSectionDiff().isEmpty,
        isTrue,
      );
      expect(
        const AnnotationSectionDiff(
          annotations: MarkerAnnotationsValue(
            halfBeatLines: [HalfBeatLine(position: Duration.zero)],
          ),
        ).isEmpty,
        isFalse,
      );
    });
  });
}
