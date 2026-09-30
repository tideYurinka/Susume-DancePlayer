import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/stats/heatmap_selection.dart'
    show heatmapCellPitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/semantics_assertions.dart';

/// 热力图日格命中盒与语义：日格视觉 12dp 撑不到
/// 下限，靠透明外扩到 48×48；每格报出日期与练习量并可经无障碍点按选日，
/// 指针命中仍由整片网格按最近格换算。
void main() {
  PracticeSessionRecord sessionRecord(DateTime start, double seconds) =>
      PracticeSessionRecord(
        start: start,
        videoId: 'v1',
        signature: const SongSignature(song: 'My Love'),
        wallSeconds: seconds,
      );

  String dayKey(DateTime day) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}';
  }

  Future<void> pumpStats(
    WidgetTester tester, {
    required List<PracticeSessionRecord> records,
  }) async {
    final statsStorage = InMemoryPracticeStatsStorage();
    statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
    useNamedViewport(tester, ViewportTier.compact);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(statsStorage),
          ),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: VideoIndex.empty),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();
  }

  testWidgets('日格 48×48 语义命中层；每格报日期与练习量；视觉格仍 12dp', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    await pumpStats(
      tester,
      records: [sessionRecord(today, 600), sessionRecord(yesterday, 300)],
    );

    for (final entry in [(today, '练习 10:00'), (yesterday, '练习 5:00')]) {
      final key = Key('heatmap_hit_${dayKey(entry.$1)}');
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expectButtonSemantics(tester, key);
      final semantics = semanticsOfKey(tester, key);
      expect(
        semantics.properties.label,
        '${entry.$1.year}年${entry.$1.month}月${entry.$1.day}日',
      );
      expect(semantics.properties.value, entry.$2);
    }

    // 视觉格与网格几何没有因为外扩而改变：格件（含对半格间距的 margin）
    // 仍是 12 + 2 = 14（= heatmapCellPitch）。
    final cell = tester.getSize(
      find.byKey(Key('heatmap_cell_${dayKey(today)}')),
    );
    expect(cell.width, heatmapCellPitch);
    expect(cell.height, heatmapCellPitch);
  });

  testWidgets('无障碍点按日格选中该日；指针命中按最近格换算', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await pumpStats(tester, records: [sessionRecord(today, 600)]);

    final key = Key('heatmap_hit_${dayKey(today)}');
    final layerBox = tester.renderObject<RenderBox>(find.byKey(key));
    // 指针真命中这枚 48 层（不是只存在于无障碍树）：格中心落进层内。
    final cell = find.byKey(Key('heatmap_cell_${dayKey(today)}'));
    final hit = tester.hitTestOnBinding(tester.getCenter(cell));
    expect(
      hit.path.any((entry) => entry.target == layerBox),
      isTrue,
      reason: '日格中心必须命中 48 命中层自身',
    );

    final semantics = semanticsOfKey(tester, key);
    expect(semantics.properties.onTap, isNotNull);
    semantics.properties.onTap!();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);
    expect(
      find.text('${today.month}月${today.day}日 · 练习 10:00'),
      findsOneWidget,
    );
  });
}
