import 'package:dance_learning_app/dance/practice_distribution.dart';
import 'package:dance_learning_app/home/practice_distribution_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';

/// 包线遍历：练舞分布图刻度列与绘图区宽度参与
/// 几何，在包线两档 × 竖横 × 字号 1.0×/1.6× 下断言不溢出、图表收在视口内。
void main() {
  // 12 个均匀 2s 桶（与既有页面级测试同一夹具）。
  final buckets = [
    for (var i = 0; i < 12; i++)
      PracticeDistributionBucket(
        start: Duration(seconds: 2 * i),
        end: Duration(seconds: 2 * i + 2),
        duration: Duration(seconds: i),
        count: 11 - i,
      ),
  ];

  for (final tier in [ViewportTier.small, ViewportTier.large]) {
    for (final landscape in [false, true]) {
      for (final textScale in [1.0, 1.6]) {
        final label = '${tier.name}${landscape ? ' 横屏' : ' 竖屏'} $textScale×';

        testWidgets('练舞分布图 $label：不溢出，图表卡落在视口内', (tester) async {
          useNamedViewport(
            tester,
            tier,
            landscape: landscape,
            textScale: textScale,
          );
          await tester.pumpWidget(
            MaterialApp(
              // 与生产同构：分布卡住在详情页 ListView（竖向滚动）内，
              // 卡高超出视口由滚动承接，宽度几何才是本遍历的对象。
              home: Scaffold(
                body: ListView(
                  children: [
                    PracticeDistributionCard(
                      buckets: buckets,
                      metric: PracticeDistributionMetric.duration,
                      range: PracticeDistributionRange.cumulative,
                      beatGridNotReady: false,
                      onSegmentMasteryChanged: (_, _) {},
                      onMetricChanged: (_) {},
                      onRangeChanged: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final view = tester.view;
          final screenWidth = view.physicalSize.width / view.devicePixelRatio;
          expect(tester.takeException(), isNull, reason: '$label 不溢出');

          final card = find.byKey(const Key('practice_distribution_card'));
          expect(card, findsOneWidget, reason: '$label 图表卡在场（入口可达）');
          final rect = tester.getRect(card);
          expect(rect.left, greaterThanOrEqualTo(0), reason: '不越左缘');
          expect(rect.right, lessThanOrEqualTo(screenWidth), reason: '不越右缘');
          expect(rect.top, greaterThanOrEqualTo(0), reason: '不越顶缘');
          final chart = find.byKey(const Key('practice_distribution_chart'));
          if (chart.evaluate().isNotEmpty) {
            final chartRect = tester.getRect(chart);
            expect(
              chartRect.right,
              lessThanOrEqualTo(screenWidth),
              reason: '绘图区不越右缘',
            );
          }
        });
      }
    }
  }
}
