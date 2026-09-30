import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart'
    show videoIndexStoreProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart'
    show PracticeStatsStore;
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
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

/// 包线遍历：计划页时间轴 pitch 按可用宽派生
/// （12 段月列等分 + 命中层按列宽换算），在包线两档 × 竖横 × 字号
/// 1.0×/1.6× 下断言不溢出、时间轴收在视口内。
void main() {
  for (final tier in [ViewportTier.small, ViewportTier.large]) {
    for (final landscape in [false, true]) {
      for (final textScale in [1.0, 1.6]) {
        final label = '${tier.name}${landscape ? ' 横屏' : ' 竖屏'} $textScale×';

        testWidgets('计划页时间轴 $label：不溢出，时间轴收在视口内', (tester) async {
          useNamedViewport(
            tester,
            tier,
            landscape: landscape,
            textScale: textScale,
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                practicePlanStorageProvider.overrideWithValue(
                  InMemoryPracticePlanStorage(),
                ),
                practiceStatsStoreProvider.overrideWithValue(
                  PracticeStatsStore(InMemoryPracticeStatsStorage()),
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
          await tester.tap(find.byKey(const Key('tab_plan')));
          await tester.pumpAndSettle();

          // 时间轴在页面级 ListView 内懒建：滚到可见再断言。
          final timeline = find.byKey(const Key('plan_timeline'));
          if (timeline.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              timeline,
              400,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
          }
          final view = tester.view;
          final screenWidth = view.physicalSize.width / view.devicePixelRatio;
          expect(tester.takeException(), isNull, reason: '$label 不溢出');
          expect(timeline, findsOneWidget, reason: '$label 时间轴在场（入口可达）');

          // 时间轴整行收在视口水平界内：pitch 派生几何的外部事实。
          final rect = tester.getRect(timeline);
          expect(rect.left, greaterThanOrEqualTo(0), reason: '不越左缘');
          expect(rect.right, lessThanOrEqualTo(screenWidth), reason: '不越右缘');
        });
      }
    }
  }
}
