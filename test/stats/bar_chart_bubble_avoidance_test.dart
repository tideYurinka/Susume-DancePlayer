// 柱状图气泡避让与纵向跟手的页面级测试：气泡矩形与目标柱矩形
// 不相交、柱顶数值不被遮挡、纵向中心对齐手指 y 并钳在绘图区内、拖动全程
// 实时更新并重新避让。
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
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

PracticeSessionRecord _record(
  DateTime start,
  double seconds, {
  String videoId = 'v1',
}) => PracticeSessionRecord(
  start: start,
  videoId: videoId,
  signature: SongSignature(song: videoId),
  wallSeconds: seconds,
);

String _dayKey(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

Finder _bar(DateTime day) => find.byKey(Key('daily_bar_${_dayKey(day)}'));

Finder _bubble() => find.byKey(const Key('bar_chart_bubble'));

Rect _plotRect(WidgetTester tester) =>
    tester.getRect(find.byKey(const Key('daily_gridlines')));

Future<void> _pump(
  WidgetTester tester, {
  required List<PracticeSessionRecord> records,
}) async {
  final statsStorage = InMemoryPracticeStatsStorage();
  statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
  useNamedViewport(tester, ViewportTier.compact);
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
  // 统一切到近 7 天：柱数固定 7、柱顶数值可见（避让与遮挡断言的口径）。
  await tester.tap(find.byKey(const Key('filter_window_7')));
  await tester.pumpAndSettle();
}

/// 在指定柱的全高列上、绘图区内给定纵向比例处按下 → 拾起（点选该柱）。
Future<void> _tapBarAt(
  WidgetTester tester,
  Finder bar,
  double fractionOfPlotHeight,
) async {
  final barRect = tester.getRect(bar);
  final plot = _plotRect(tester);
  final y = plot.top + (plot.height * fractionOfPlotHeight);
  final gesture = await tester.startGesture(Offset(barRect.center.dx, y));
  await gesture.up();
  await tester.pumpAndSettle();
}

String _bubbleHeadline(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: _bubble(), matching: find.byType(Text)).first,
    )
    .data!;

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);
  // 近 7 天窗口：today 是最右列（右半），5 天前是左半。
  final fiveDaysAgo = today.subtract(const Duration(days: 5));

  testWidgets('点按左半柱：气泡靠右、与目标柱矩形不相交、跟手且钳在绘图区内', (tester) async {
    await _pump(tester, records: [_record(fiveDaysAgo, 600)]);
    await tester.ensureVisible(_bar(fiveDaysAgo));
    await tester.pumpAndSettle();

    await _tapBarAt(tester, _bar(fiveDaysAgo), 0.7);
    final plot = _plotRect(tester);
    final bubbleRect = tester.getRect(_bubble());
    final barRect = tester.getRect(_bar(fiveDaysAgo));

    // 与目标柱矩形不相交（目标在左半 → 气泡整体靠右）。
    expect(bubbleRect.left, greaterThanOrEqualTo(barRect.right));
    // 完整落在绘图区内。
    expect(bubbleRect.top, greaterThanOrEqualTo(plot.top));
    expect(bubbleRect.bottom, lessThanOrEqualTo(plot.bottom));
    expect(bubbleRect.left, greaterThanOrEqualTo(plot.left));
    expect(bubbleRect.right, lessThanOrEqualTo(plot.right));
    // 纵向中心对齐手指 y（点在 0.7 高度处，气泡四行高以内应能对齐）；
    // 量测与期望同式折算，容差只吸收浮点舍入（1e-6 远小于 1dp 观感差）。
    expect(
      (bubbleRect.top + bubbleRect.bottom) / 2,
      closeTo(plot.top + plot.height * 0.7, 1e-6),
    );
  });

  testWidgets('点按末列柱：气泡靠左、与目标柱矩形不相交、柱顶数值不被遮挡', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await tester.ensureVisible(_bar(today));
    await tester.pumpAndSettle();

    await _tapBarAt(tester, _bar(today), 0.5);
    final plot = _plotRect(tester);
    final bubbleRect = tester.getRect(_bubble());
    final barRect = tester.getRect(_bar(today));

    expect(bubbleRect.right, lessThanOrEqualTo(barRect.left + 0.01));
    expect(bubbleRect.top, greaterThanOrEqualTo(plot.top));
    expect(bubbleRect.bottom, lessThanOrEqualTo(plot.bottom));
    // 柱顶数值在目标柱列内 → 气泡不与之相交即不遮挡。
    final valueRect = tester.getRect(
      find.byKey(Key('daily_bar_value_${_dayKey(today)}')),
    );
    expect(
      bubbleRect.right <= valueRect.left + 0.01 ||
          valueRect.right <= bubbleRect.left + 0.01,
      isTrue,
    );
  });

  testWidgets('纵向钳制：手指在绘图区顶部/底部时气泡不出绘图区', (tester) async {
    await _pump(tester, records: [_record(fiveDaysAgo, 600)]);
    await tester.ensureVisible(_bar(fiveDaysAgo));
    await tester.pumpAndSettle();

    for (final fraction in [0.05, 0.95]) {
      await _tapBarAt(tester, _bar(fiveDaysAgo), fraction);
      final plot = _plotRect(tester);
      final bubbleRect = tester.getRect(_bubble());
      expect(bubbleRect.top, greaterThanOrEqualTo(plot.top));
      expect(bubbleRect.bottom, lessThanOrEqualTo(plot.bottom));
    }
  });

  testWidgets('系统字号放大 1.2×：气泡实测与渲染同源，跟手后仍钳在绘图区内', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // 同日三支舞 → 气泡四行，放大后实测高度若不吃 TextScaler 会显著
    // 小于渲染高度，指尖近底时钳制失准、气泡底部越出绘图区。
    await _pump(
      tester,
      records: [
        _record(fiveDaysAgo, 60, videoId: 'a'),
        _record(fiveDaysAgo, 60, videoId: 'b'),
        _record(fiveDaysAgo, 60, videoId: 'c'),
      ],
    );
    // 大字号下页面更长：先滚动把柱状图构建出来。
    await tester.dragUntilVisible(
      _bar(fiveDaysAgo),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.ensureVisible(_bar(fiveDaysAgo));
    await tester.pumpAndSettle();

    await _tapBarAt(tester, _bar(fiveDaysAgo), 0.95);
    final plot = _plotRect(tester);
    final bubbleRect = tester.getRect(_bubble());
    expect(bubbleRect.top, greaterThanOrEqualTo(plot.top - 0.01));
    expect(bubbleRect.bottom, lessThanOrEqualTo(plot.bottom + 0.01));
    expect(bubbleRect.left, greaterThanOrEqualTo(plot.left - 0.01));
    expect(bubbleRect.right, lessThanOrEqualTo(plot.right + 0.01));
  });

  testWidgets('横向拖动滑过柱：气泡实时更新并重新避让', (tester) async {
    await _pump(
      tester,
      records: [
        _record(fiveDaysAgo, 600),
        _record(today, 1200, videoId: 'v2'),
      ],
    );
    await tester.ensureVisible(_bar(fiveDaysAgo));
    await tester.pumpAndSettle();

    final startRect = tester.getRect(_bar(fiveDaysAgo));
    final endRect = tester.getRect(_bar(today));
    final plot = _plotRect(tester);
    // 起手点取柱内左 1/4 处：compact 档柱宽收窄后，越过 slop（18）的
    // 位移仍留在起点柱内（1/4 柱心距 + slop < 柱宽）。
    final startX = startRect.left + startRect.width * 0.25;
    final gesture = await tester.startGesture(
      Offset(startX, plot.top + plot.height * 0.5),
    );
    // 先拖过 slop 选中起点柱，再滑向最右列。
    await gesture.moveBy(const Offset(19, 0));
    await tester.pump();
    expect(
      _bubbleHeadline(tester),
      contains('${fiveDaysAgo.month}月${fiveDaysAgo.day}日'),
    );

    // 滑到最右列：气泡实时换日并重新避让（气泡在目标柱左侧）。
    await gesture.moveBy(Offset(endRect.center.dx - startX - 19, 0));
    await tester.pump();
    expect(_bubbleHeadline(tester), contains('${today.month}月${today.day}日'));
    final bubbleRect = tester.getRect(_bubble());
    expect(bubbleRect.right, lessThanOrEqualTo(endRect.left + 0.01));

    await gesture.up();
    await tester.pumpAndSettle();
  });
}
