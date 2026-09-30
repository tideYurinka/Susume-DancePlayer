import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart'
    show PracticeStatsDocument, PracticeSessionRecord, PracticeStatsStore;
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 包线遍历：统计页图表 plot 宽度参与几何，
/// 在包线两档 × 竖横 × 字号 1.0×/1.6× 下断言不溢出、图表卡收在视口内。
void main() {
  final today = DateTime.now();
  final records = [
    for (var i = 0; i < 5; i++)
      PracticeSessionRecord(
        start: DateTime(
          today.year,
          today.month,
          today.day,
        ).subtract(Duration(days: i)),
        videoId: 'v$i',
        signature: const SongSignature(song: '一支舞'),
        wallSeconds: 60 * (i + 1),
      ),
  ];

  for (final tier in [ViewportTier.small, ViewportTier.large]) {
    for (final landscape in [false, true]) {
      for (final textScale in [1.0, 1.6]) {
        final label = '${tier.name}${landscape ? ' 横屏' : ' 竖屏'} $textScale×';

        testWidgets('统计页图表 $label：不溢出，图表卡收在视口内', (tester) async {
          useNamedViewport(
            tester,
            tier,
            landscape: landscape,
            textScale: textScale,
          );
          final statsStorage = InMemoryPracticeStatsStorage();
          statsStorage.rawJson = PracticeStatsDocument(sessions: records)
              .toJson();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                practicePlanStorageProvider.overrideWithValue(
                  InMemoryPracticePlanStorage(),
                ),
                practiceStatsStoreProvider.overrideWithValue(
                  PracticeStatsStore(statsStorage),
                ),
                videoIndexStoreProvider.overrideWithValue(
                  InMemoryVideoIndexStorage(initial: VideoIndex.empty),
                ),
                videoDocumentStorageFactoryProvider.overrideWithValue(
                  (videoId) => InMemoryVideoDocumentStorage(),
                ),
                coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
              ],
              child: const DanceLearningApp(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('tab_stats')));
          await tester.pumpAndSettle();

          // 图表卡在页面下方，页面级 ListView 懒建：滚到可见再断言。
          final chart = find.byKey(const Key('daily_chart_card'));
          if (chart.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              chart,
              400,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
          }

          final view = tester.view;
          final screenWidth = view.physicalSize.width / view.devicePixelRatio;
          expect(tester.takeException(), isNull, reason: '$label 不溢出');

          // 图表 plot（柱族）横向收进视口：宽度派生几何的外部事实。柱族懒建，
          // 页面本身可竖向滚动，只对在场件断言。
          expect(chart, findsOneWidget, reason: '$label 图表卡在场（入口可达）');
          final chartRect = tester.getRect(chart);
          expect(chartRect.left, greaterThanOrEqualTo(0), reason: '图表卡不越左缘');
          expect(
            chartRect.right,
            lessThanOrEqualTo(screenWidth),
            reason: '图表卡不越右缘',
          );
          for (final bar
              in find
                  .byWidgetPredicate(
                    (widget) =>
                        widget.key is Key &&
                        (widget.key as Key).toString().contains(
                          'daily_bar_fill_',
                        ),
                  )
                  .evaluate()) {
            final rect = tester.getRect(find.byWidget(bar.widget));
            expect(
              rect.left,
              greaterThanOrEqualTo(chartRect.left - 0.5),
              reason: '柱不越图表卡左缘',
            );
            expect(
              rect.right,
              lessThanOrEqualTo(chartRect.right + 0.5),
              reason: '柱不越图表卡右缘',
            );
          }
        });
      }
    }
  }
}
