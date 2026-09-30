import 'package:dance_learning_app/player/overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('姿态 × 对比 → 格 resolveOverlayPlacementCell', () {
    test('非对比的两个组合落在两个普通格', () {
      expect(
        resolveOverlayPlacementCell(landscape: false, compare: false),
        OverlayPlacementCell.portraitNormal,
      );
      expect(
        resolveOverlayPlacementCell(landscape: true, compare: false),
        OverlayPlacementCell.landscapeNormal,
      );
    });

    test('对比的两个组合落在两个对比格', () {
      expect(
        resolveOverlayPlacementCell(landscape: false, compare: true),
        OverlayPlacementCell.portraitCompare,
      );
      expect(
        resolveOverlayPlacementCell(landscape: true, compare: true),
        OverlayPlacementCell.landscapeCompare,
      );
    });

    test('四个组合映射到四个互不相同的格', () {
      final cells = {
        for (final landscape in [false, true])
          for (final compare in [false, true])
            resolveOverlayPlacementCell(landscape: landscape, compare: compare),
      };
      expect(cells, hasLength(4));
      expect(cells, hasLength(OverlayPlacementCell.values.length));
    });
  });

  group('默认位 defaultOverlayOffset', () {
    test('贴左、纵向 = 视口高 × 12%', () {
      expect(defaultOverlayOffset(const Size(400, 800)), const Offset(0, 96));
      expect(defaultOverlayOffset(const Size(400, 500)), const Offset(0, 60));
    });

    test('随视口高变化、与视口宽（浮层自身宽度）无关', () {
      final narrow = defaultOverlayOffset(const Size(200, 800));
      final wide = defaultOverlayOffset(const Size(1200, 800));
      expect(narrow, const Offset(0, 96));
      expect(wide, narrow);
    });
  });

  group('四格容器 OverlayPlacements', () {
    test('未自定义的格读不到值', () {
      const placements = OverlayPlacements();
      for (final cell in OverlayPlacementCell.values) {
        expect(placements.offsetFor(cell), isNull);
      }
    });

    test('一格写入后读得到该值、且不干扰其它格与原容器', () {
      const placements = OverlayPlacements();
      final written = placements.withOffset(
        OverlayPlacementCell.landscapeCompare,
        const Offset(12, 34),
      );
      expect(
        written.offsetFor(OverlayPlacementCell.landscapeCompare),
        const Offset(12, 34),
      );
      expect(written.offsetFor(OverlayPlacementCell.portraitNormal), isNull);
      expect(
        placements.offsetFor(OverlayPlacementCell.landscapeCompare),
        isNull,
      );
    });

    test('写入 null 即清除该格、清除后回到未自定义', () {
      final written = const OverlayPlacements().withOffset(
        OverlayPlacementCell.portraitCompare,
        const Offset(5, 6),
      );
      final cleared = written.withOffset(
        OverlayPlacementCell.portraitCompare,
        null,
      );
      expect(cleared.offsetFor(OverlayPlacementCell.portraitCompare), isNull);
      expect(cleared, const OverlayPlacements());
    });

    test('写入格不改变两个尺寸系数', () {
      final written = const OverlayPlacements()
          .withOffset(
            OverlayPlacementCell.portraitNormal,
            const Offset(1, 2),
          )
          .withOffset(
            OverlayPlacementCell.landscapeNormal,
            const Offset(3, 4),
          );
      expect(written.rectWidthFactor, 1.0);
      expect(written.pendulumScale, 1.0);
    });

    test('改尺寸系数不改变任何一格的值、原容器不变', () {
      final base = const OverlayPlacements()
          .withOffset(
            OverlayPlacementCell.portraitNormal,
            const Offset(1, 2),
          )
          .withOffset(
            OverlayPlacementCell.landscapeCompare,
            const Offset(3, 4),
          );
      final resized = base.withFactors(rectWidthFactor: 2.0, pendulumScale: 0.5);
      expect(resized.rectWidthFactor, 2.0);
      expect(resized.pendulumScale, 0.5);
      for (final cell in OverlayPlacementCell.values) {
        expect(resized.offsetFor(cell), base.offsetFor(cell));
      }
      expect(base.rectWidthFactor, 1.0);
      expect(base.pendulumScale, 1.0);
    });

    test('只改一个尺寸系数时另一个保持现值', () {
      final resized = const OverlayPlacements().withFactors(
        rectWidthFactor: 1.5,
      );
      expect(resized.rectWidthFactor, 1.5);
      expect(resized.pendulumScale, 1.0);
    });

    test('相等性按内容判定：offsets 与两个系数都参与', () {
      final a = const OverlayPlacements().withOffset(
        OverlayPlacementCell.portraitNormal,
        const Offset(1, 2),
      );
      final b = const OverlayPlacements().withOffset(
        OverlayPlacementCell.portraitNormal,
        const Offset(1, 2),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const OverlayPlacements()));
      expect(
        a,
        isNot(
          a.withOffset(
            OverlayPlacementCell.portraitNormal,
            const Offset(1, 3),
          ),
        ),
      );
      expect(a, isNot(a.withFactors(rectWidthFactor: 2.0)));
      expect(a, isNot(a.withFactors(pendulumScale: 2.0)));
    });

    test('相等性与哈希不受格写入顺序影响', () {
      final forward = const OverlayPlacements()
          .withOffset(
            OverlayPlacementCell.portraitNormal,
            const Offset(1, 2),
          )
          .withOffset(
            OverlayPlacementCell.landscapeCompare,
            const Offset(3, 4),
          );
      final reverse = const OverlayPlacements()
          .withOffset(
            OverlayPlacementCell.landscapeCompare,
            const Offset(3, 4),
          )
          .withOffset(
            OverlayPlacementCell.portraitNormal,
            const Offset(1, 2),
          );
      expect(forward, reverse);
      expect(forward.hashCode, reverse.hashCode);
    });

    test('等值容器可安全用作相等性防环（Set 去重）', () {
      final first = const OverlayPlacements().withOffset(
        OverlayPlacementCell.portraitNormal,
        const Offset(1, 2),
      );
      final second = const OverlayPlacements().withOffset(
        OverlayPlacementCell.portraitNormal,
        const Offset(1, 2),
      );
      expect({first, second}, hasLength(1));
    });
  });
}
