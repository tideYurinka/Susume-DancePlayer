import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/interval_fragment_row.dart';

void main() {
  group('区间映射：时间窗 → 块矩形', () {
    const window = IntervalSpan(startMs: 1000, endMs: 11000);
    const trackWidth = 500.0;

    test('窗内整段映射：起点贴窗左、宽度按窗口比例', () {
      final rect = intervalBlockRect(
        span: const IntervalSpan(startMs: 2000, endMs: 4000),
        window: window,
        trackWidth: trackWidth,
        contentLeft: 0,
      );
      // 窗 10s 对应 500px：1s = 50px。
      expect(rect, const IntervalBlockRect(left: 50, width: 100));
    });

    test('起点越出窗左：裁到窗起点', () {
      final rect = intervalBlockRect(
        span: const IntervalSpan(startMs: 500, endMs: 3000),
        window: window,
        trackWidth: trackWidth,
        contentLeft: 0,
      );
      expect(rect, const IntervalBlockRect(left: 0, width: 100));
    });

    test('终点越出窗右：裁到窗终点', () {
      final rect = intervalBlockRect(
        span: const IntervalSpan(startMs: 9000, endMs: 15000),
        window: window,
        trackWidth: trackWidth,
        contentLeft: 0,
      );
      expect(rect, const IntervalBlockRect(left: 400, width: 100));
    });

    test('整段罩住窗口：裁为全宽', () {
      final rect = intervalBlockRect(
        span: const IntervalSpan(startMs: 0, endMs: 20000),
        window: window,
        trackWidth: trackWidth,
        contentLeft: 0,
      );
      expect(rect, const IntervalBlockRect(left: 0, width: 500));
    });

    test('内容区左缘让位：块矩形整体偏移到内容区左缘', () {
      final rect = intervalBlockRect(
        span: const IntervalSpan(startMs: 3000, endMs: 5000),
        window: window,
        trackWidth: 260,
        contentLeft: 40,
      );
      // 窗 10s 对应 260px：2s = 52px，整体落在 40 之后。
      expect(rect, const IntervalBlockRect(left: 40 + 52, width: 52));
    });

    test('内容区左缘 = 0：块矩形从行左缘起算', () {
      final rect = intervalBlockRect(
        span: const IntervalSpan(startMs: 3000, endMs: 5000),
        window: window,
        trackWidth: 260,
        contentLeft: 0,
      );
      expect(rect, const IntervalBlockRect(left: 52, width: 52));
    });

    test('完全在窗外（左）：返回空', () {
      expect(
        intervalBlockRect(
          span: const IntervalSpan(startMs: 0, endMs: 500),
          window: window,
          trackWidth: trackWidth,
          contentLeft: 0,
        ),
        isNull,
      );
    });

    test('完全在窗外（右）：返回空', () {
      expect(
        intervalBlockRect(
          span: const IntervalSpan(startMs: 12000, endMs: 13000),
          window: window,
          trackWidth: trackWidth,
          contentLeft: 0,
        ),
        isNull,
      );
    });

    test('零宽区间：返回空', () {
      expect(
        intervalBlockRect(
          span: const IntervalSpan(startMs: 3000, endMs: 3000),
          window: window,
          trackWidth: trackWidth,
          contentLeft: 0,
        ),
        isNull,
      );
    });

    test('倒置区间：返回空', () {
      expect(
        intervalBlockRect(
          span: const IntervalSpan(startMs: 5000, endMs: 2000),
          window: window,
          trackWidth: trackWidth,
          contentLeft: 0,
        ),
        isNull,
      );
    });

    test('窗倒置：返回空', () {
      expect(
        intervalBlockRect(
          span: const IntervalSpan(startMs: 2000, endMs: 4000),
          window: const IntervalSpan(startMs: 11000, endMs: 1000),
          trackWidth: trackWidth,
          contentLeft: 0,
        ),
        isNull,
      );
    });

    test('带宽非正：返回空', () {
      expect(
        intervalBlockRect(
          span: const IntervalSpan(startMs: 2000, endMs: 4000),
          window: window,
          trackWidth: 0,
          contentLeft: 0,
        ),
        isNull,
      );
    });
  });

  group('命中解析：对称扩展 + 最近中心', () {
    test('宽段不收缩：命中域就是几何区间（半开右端）', () {
      final spans = [const IntervalSpan(startMs: 100, endMs: 300)];
      expect(
        resolveIntervalHit(spans: spans, positionMs: 299, minHitWidthMs: 100),
        0,
      );
      // 右端点半开：落在 300 不命中。
      expect(
        resolveIntervalHit(spans: spans, positionMs: 300, minHitWidthMs: 100),
        isNull,
      );
    });

    test('窄段对称扩展至最小命中宽：只向上、两侧各扩差值一半', () {
      final spans = [const IntervalSpan(startMs: 200, endMs: 250)];
      // 宽 50、最小命中 100 → 两侧各扩 25，命中域 [175, 275)。
      expect(
        resolveIntervalHit(spans: spans, positionMs: 175, minHitWidthMs: 100),
        0,
      );
      expect(
        resolveIntervalHit(spans: spans, positionMs: 174, minHitWidthMs: 100),
        isNull,
      );
      expect(
        resolveIntervalHit(spans: spans, positionMs: 274, minHitWidthMs: 100),
        0,
      );
      expect(
        resolveIntervalHit(spans: spans, positionMs: 275, minHitWidthMs: 100),
        isNull,
      );
    });

    test('扩展量下取整：奇数差时命中域总宽为最小命中宽 − 1', () {
      final spans = [const IntervalSpan(startMs: 200, endMs: 251)];
      // 宽 51、最小命中 100 → 每侧扩 (100-51)~/2 = 24，命中域 [176, 275)。
      expect(
        resolveIntervalHit(spans: spans, positionMs: 176, minHitWidthMs: 100),
        0,
      );
      expect(
        resolveIntervalHit(spans: spans, positionMs: 175, minHitWidthMs: 100),
        isNull,
      );
      expect(
        resolveIntervalHit(spans: spans, positionMs: 274, minHitWidthMs: 100),
        0,
      );
      expect(
        resolveIntervalHit(spans: spans, positionMs: 275, minHitWidthMs: 100),
        isNull,
      );
    });

    test('多候选取距中心最近', () {
      final spans = [
        const IntervalSpan(startMs: 0, endMs: 100),
        const IntervalSpan(startMs: 120, endMs: 220),
      ];
      // 中心 50 / 170：点 130 距 170 更近 → 命中第 2 段。
      expect(
        resolveIntervalHit(spans: spans, positionMs: 130, minHitWidthMs: 0),
        1,
      );
    });

    test('同距取靠前', () {
      final spans = [
        const IntervalSpan(startMs: 0, endMs: 100),
        const IntervalSpan(startMs: 50, endMs: 150),
      ];
      // 点 75 距两中心（50/100）同为 25 → 取下标 0。
      expect(
        resolveIntervalHit(spans: spans, positionMs: 75, minHitWidthMs: 0),
        0,
      );
    });

    test('无候选返回空', () {
      final spans = [const IntervalSpan(startMs: 0, endMs: 100)];
      expect(
        resolveIntervalHit(spans: spans, positionMs: 500, minHitWidthMs: 40),
        isNull,
      );
      expect(
        resolveIntervalHit(spans: const [], positionMs: 50, minHitWidthMs: 40),
        isNull,
      );
    });
  });

  group('命中区域划分：块体 / 端点带 / 窄块抑制', () {
    const edgeBandWidth = 14.0;
    const narrowWidth = 40.0;

    test('块中部：块体', () {
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: 50,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.body,
      );
    });

    test('左端点带：偏移落在左带内', () {
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: 0,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.startEdge,
      );
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: 13.5,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.startEdge,
      );
    });

    test('左/右端点带边界：恰好带宽处归块体、右带起点归右带', () {
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: 14,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.body,
      );
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: 86,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.endEdge,
      );
    });

    test('块外：返回空', () {
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: -0.1,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        isNull,
      );
      expect(
        intervalHitRegion(
          blockWidth: 100,
          offsetInBlock: 100,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        isNull,
      );
    });

    test('窄块阈值抑制端点带：整块都是块体', () {
      // 块宽恰为阈值：不抑制。
      expect(
        intervalHitRegion(
          blockWidth: 40,
          offsetInBlock: 0,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.startEdge,
      );
      // 块宽低于阈值：两端偏移都归块体。
      expect(
        intervalHitRegion(
          blockWidth: 39.9,
          offsetInBlock: 0,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.body,
      );
      expect(
        intervalHitRegion(
          blockWidth: 39.9,
          offsetInBlock: 39,
          edgeBandWidth: edgeBandWidth,
          narrowWidth: narrowWidth,
        ),
        IntervalHitRegion.body,
      );
    });
  });

  group('端点命中域分配：自适应让位与选中端点柄', () {
    const bandWidth = 14.0;
    const selectedBandWidth = 24.0;

    IntervalEdgeHitAllocation allocate({
      double startAvailable = 100,
      double endAvailable = 100,
      bool selected = false,
    }) {
      return allocateIntervalEdgeHitDomains(
        startAvailable: startAvailable,
        endAvailable: endAvailable,
        bandWidth: bandWidth,
        selectedBandWidth: selectedBandWidth,
        selected: selected,
      );
    }

    test('空间充足：两端各得整条端点带', () {
      final a = allocate();
      expect(a.startWidth, bandWidth);
      expect(a.endWidth, bandWidth);
      expect(a.wholeBlockIsMove, isFalse);
    });

    test('冲突处让出：可用空间不足时只给放得下的部分', () {
      final a = allocate(startAvailable: 5, endAvailable: 0);
      expect(a.startWidth, 5, reason: 'start 侧只给空隙放得下的部分');
      expect(a.endWidth, 0, reason: 'end 侧无空隙（贴相邻片段/带缘）不给');
      expect(a.wholeBlockIsMove, isFalse);
    });

    test('最坏退化：两端都放不下 → 整块归移动', () {
      final a = allocate(startAvailable: 0, endAvailable: 0);
      expect(a.startWidth, 0);
      expect(a.endWidth, 0);
      expect(a.wholeBlockIsMove, isTrue);
    });

    test('选中后命中域更长：同侧可用空间下选中比未选中给得多', () {
      const available = 20.0;
      final unselected = allocate(startAvailable: available, endAvailable: 0);
      final selected = allocate(
        startAvailable: available,
        endAvailable: 0,
        selected: true,
      );
      expect(unselected.startWidth, bandWidth);
      expect(
        selected.startWidth,
        available,
        reason: '选中目标带宽 24 > 空隙 20，能放多少给多少',
      );
      expect(selected.startWidth, greaterThan(unselected.startWidth));
      // 空隙充足时选中给满柄宽，同样长于未选中。
      final selectedRoomy = allocate(selected: true);
      expect(selectedRoomy.startWidth, selectedBandWidth);
      expect(selectedRoomy.startWidth, greaterThan(bandWidth));
    });

    test('任何一侧输出都不越出该侧可用空间（带内可用横向范围）', () {
      final a = allocate(startAvailable: 7.5, endAvailable: 3.25);
      expect(a.startWidth, lessThanOrEqualTo(7.5));
      expect(a.endWidth, lessThanOrEqualTo(3.25));
    });

    test('负可用空间按无空间处理', () {
      final a = allocate(startAvailable: -1, endAvailable: -0.5);
      expect(a.wholeBlockIsMove, isTrue);
    });
  });

  group('新建截断：起点 + 宽，向区间末与右邻起点截断', () {
    test('无右邻且宽不越尾：原样成形', () {
      expect(
        truncatedNewSpan(
          spans: const [],
          startMs: 10000,
          widthMs: 4000,
          rangeEndMs: 60000,
        ),
        const IntervalSpan(startMs: 10000, endMs: 14000),
      );
    });

    test('宽越区间末：向尾截断', () {
      expect(
        truncatedNewSpan(
          spans: const [],
          startMs: 57500,
          widthMs: 4000,
          rangeEndMs: 60000,
        ),
        const IntervalSpan(startMs: 57500, endMs: 60000),
      );
    });

    test('宽越右邻起点：向最近右邻起点截断', () {
      expect(
        truncatedNewSpan(
          spans: const [
            IntervalSpan(startMs: 5000, endMs: 6000),
            IntervalSpan(startMs: 12000, endMs: 20000),
            IntervalSpan(startMs: 30000, endMs: 34000),
          ],
          startMs: 10000,
          widthMs: 4000,
          rangeEndMs: 60000,
        ),
        const IntervalSpan(startMs: 10000, endMs: 12000),
      );
    });

    test('半开共享端点的大右邻起点不截断（视为不重叠）', () {
      expect(
        truncatedNewSpan(
          spans: const [IntervalSpan(startMs: 14000, endMs: 20000)],
          startMs: 10000,
          widthMs: 4000,
          rangeEndMs: 60000,
        ),
        const IntervalSpan(startMs: 10000, endMs: 14000),
      );
    });

    test('截后零宽/倒置：返回空', () {
      expect(
        truncatedNewSpan(
          spans: const [],
          startMs: 60000,
          widthMs: 4000,
          rangeEndMs: 60000,
        ),
        isNull,
      );
      expect(
        truncatedNewSpan(
          spans: const [],
          startMs: 10000,
          widthMs: 0,
          rangeEndMs: 60000,
        ),
        isNull,
        reason: '零宽新建不成立',
      );
    });
  });

  group('保序插入位：第一条起点不小于插入起点的区间位置', () {
    const spans = [
      IntervalSpan(startMs: 0, endMs: 4000),
      IntervalSpan(startMs: 10000, endMs: 14000),
      IntervalSpan(startMs: 20000, endMs: 24000),
    ];

    test('空表：追加到末尾（0）', () {
      expect(spanInsertionIndex(const [], 5000), 0);
    });

    test('落在两段之间：插到右邻之前', () {
      expect(spanInsertionIndex(spans, 5000), 1);
    });

    test('与既有起点重合：插到该条之前（升序稳定）', () {
      expect(spanInsertionIndex(spans, 10000), 1);
    });

    test('在所有既有之后：追加到末尾', () {
      expect(spanInsertionIndex(spans, 25000), 3);
    });
  });
}
