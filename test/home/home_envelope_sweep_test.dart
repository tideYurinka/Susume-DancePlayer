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

/// 包线遍历：首页瀑布流列宽参与卡片几何，
/// 在包线两档 × 竖横 × 字号 1.0×/1.6× 下断言不溢出、可见卡片收在视口内。
VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '舞曲 $videoId 一段相当长的名字用来压一压列宽',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

void main() {
  for (final tier in [ViewportTier.small, ViewportTier.large]) {
    for (final landscape in [false, true]) {
      for (final textScale in [1.0, 1.6]) {
        final label = '${tier.name}${landscape ? ' 横屏' : ' 竖屏'} $textScale×';

        testWidgets('首页瀑布流 $label：不溢出，可见卡片落在视口内', (tester) async {
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
                  InMemoryVideoIndexStorage(
                    initial: VideoIndex(
                      entries: [_entry('v1'), _entry('v2'), _entry('v3')],
                    ),
                  ),
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

          final view = tester.view;
          final screenWidth = view.physicalSize.width / view.devicePixelRatio;
          expect(tester.takeException(), isNull, reason: '$label 不溢出');

          // 可见卡片整卡收在视口水平界内（瀑布流列宽派生几何的外部事实）。
          const cardKeySubParts = [
            'state_',
            'open_',
            'title_',
            'detail_',
            'percent_',
            'average_',
            'cover_info_',
            'badge_overdue_',
          ];
          bool isCard(Widget widget) {
            final key = widget.key;
            if (key is! Key || !key.toString().contains('dance_card_')) {
              return false;
            }
            return !cardKeySubParts.any(key.toString().contains);
          }

          final cards = find.byWidgetPredicate(isCard);
          expect(cards, findsWidgets, reason: '$label 卡片在场（入口可达）');
          for (final card in cards.evaluate()) {
            final rect = tester.getRect(find.byWidget(card.widget));
            expect(rect.left, greaterThanOrEqualTo(0), reason: '卡片不越左缘');
            expect(
              rect.right,
              lessThanOrEqualTo(screenWidth),
              reason: '卡片不越右缘',
            );
          }
        });
      }
    }
  }
}
