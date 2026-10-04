import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart'
    show coverCacheProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 每日练习柱状图坐标轴：x 轴标签行高与 y 轴
/// 刻度列宽按系统字号求值——1.3×/1.6× 下刻度不与柱重叠、轴区不换行撑破。
PracticeSessionRecord _record(DateTime at, double seconds, String videoId) =>
    PracticeSessionRecord(
      videoId: videoId,
      start: at,
      signature: const SongSignature(song: '歌'),
      wallSeconds: seconds,
    );

Future<void> _pumpStats(WidgetTester tester) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);
  final statsStorage = InMemoryPracticeStatsStorage()
    ..rawJson = PracticeStatsDocument(
      sessions: [
        for (var i = 0; i < 7; i++)
          _record(today.subtract(Duration(days: i)), 300 + 60.0 * i, 'v$i'),
      ],
    ).toJson();
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
  await tester.scrollUntilVisible(
    find.byKey(const Key('daily_chart')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Finder _ticks() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('daily_axis_tick_');
});

void main() {
  for (final scale in [1.3, 1.6]) {
    testWidgets('系统字号 $scale×：刻度不压柱、轴区不溢出换行', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpStats(tester);

      expect(tester.takeException(), isNull, reason: '$scale× 下无溢出');

      // 刻度全部单行在场且不与柱区重叠：最宽刻度的右缘不越过任意柱的左缘。
      final barFinder = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('daily_bar_2');
      });
      expect(barFinder, findsWidgets);
      final barLeft = tester.getTopLeft(barFinder.first).dx;
      for (final Element tick in _ticks().evaluate()) {
        final rect = tester.getRect(find.byWidget(tick.widget));
        expect(rect.height, lessThan(60), reason: '刻度未换行撑破');
        expect(
          rect.right,
          lessThanOrEqualTo(barLeft + 0.5),
          reason: '刻度 ${tick.widget.key} 不与柱重叠',
        );
      }
    });
  }
}
