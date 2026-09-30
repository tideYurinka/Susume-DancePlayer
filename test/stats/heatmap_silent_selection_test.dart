import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/selection_haptic.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/scroll_reveal.dart';
import '../helpers/fake_selection_haptic.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

PracticeSessionRecord _record(DateTime start, double seconds) =>
    PracticeSessionRecord(
      start: start,
      videoId: 'v1',
      signature: const SongSignature(song: 'My Love'),
      wallSeconds: seconds,
    );

String _dayKey(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

Finder _cell(DateTime day) => find.byKey(Key('heatmap_cell_${_dayKey(day)}'));

Future<FakeSelectionHapticController> _pump(
  WidgetTester tester, {
  required List<PracticeSessionRecord> records,
}) async {
  final statsStorage = InMemoryPracticeStatsStorage();
  statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
  final haptic = FakeSelectionHapticController();
  useNamedViewport(tester, ViewportTier.compact);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practiceStatsStoreProvider
            .overrideWithValue(PracticeStatsStore(statsStorage)),
        videoIndexStoreProvider
            .overrideWithValue(InMemoryVideoIndexStorage(initial: VideoIndex.empty)),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => InMemoryVideoDocumentStorage(),
        ),
        selectionHapticProvider.overrideWithValue(haptic),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('tab_stats')));
  await tester.pumpAndSettle();
  return haptic;
}

/// 长按某格并抬手：已进入滑动选择模式。
Future<void> _longPressCell(WidgetTester tester, DateTime day) async {
  final gesture = await tester.startGesture(tester.getCenter(_cell(day)));
  await tester.pump(const Duration(milliseconds: 700));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// 热力图卡内气泡以外的 Text 数量（进模式前后应一致；选中日带来的气泡
/// 与明细变化除外）。
int _cardTextCountOutsideBubble(WidgetTester tester) {
  final bubbleTexts = find
      .descendant(
        of: find.byKey(const Key('heatmap_bubble')),
        matching: find.byType(Text),
      )
      .evaluate()
      .toSet();
  return find
      .descendant(
        of: find.byKey(const Key('heatmap_card')),
        matching: find.byType(Text),
      )
      .evaluate()
      .where((element) => !bubbleTexts.contains(element))
      .length;
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);
  final threeDaysAgo = today.subtract(const Duration(days: 3));

  testWidgets('长按进模式经震动接缝震一次，滑动、抬手、退出不额外震', (tester) async {
    final haptic = await _pump(tester, records: [_record(today, 600)]);

    await _longPressCell(tester, today);
    expect(haptic.impactCalls, 1);

    // 模式内点按另一格：继续选日并留在模式，不额外震。
    await tester.ensureVisible(_cell(threeDaysAgo));
    await tester.pumpAndSettle();
    await tester.tap(_cell(threeDaysAgo));
    await tester.pumpAndSettle();
    expect(haptic.impactCalls, 1);

    // 点热力图以外退出：不额外震。
    // compact 档视口更矮：仪表盘可能已出懒建缓存，滚回视野再点（空白）。
    final blank = find.byKey(const Key('dashboard_total'));
    await ensureScrollVisible(tester, blank);
    await tester.tap(find.byKey(const Key('dashboard_total')));
    await tester.pumpAndSettle();
    expect(haptic.impactCalls, 1);

    // 长按选中的日子随这次空白单击一并清空（气泡与明细收起）。
    expect(find.byKey(const Key('heatmap_bubble')), findsNothing);
    expect(find.byKey(const Key('day_detail')), findsNothing);
  });

  testWidgets('对已选格再长按退出不额外震', (tester) async {
    final haptic = await _pump(tester, records: [_record(today, 600)]);

    await _longPressCell(tester, today);
    expect(haptic.impactCalls, 1);

    await _longPressCell(tester, today);
    expect(haptic.impactCalls, 1);
  });

  testWidgets('模式内外渲染一致：无「选择中」提示、无退出入口、卡内控件数不变', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);

    // 先选中一天让气泡出现，再数卡内气泡以外的控件。
    await tester.tap(_cell(today));
    await tester.pumpAndSettle();
    final before = _cardTextCountOutsideBubble(tester);

    await _longPressCell(tester, today);
    expect(find.byKey(const Key('heatmap_selecting_banner')), findsNothing);
    expect(find.text('选择中：滑动或点按选择日期'), findsNothing);
    expect(find.byKey(const Key('heatmap_exit_selection')), findsNothing);
    expect(find.text('退出选择'), findsNothing);

    // 进模式改选了别的日不影响：气泡仍是唯一新增，其余控件数不变。
    await tester.tap(_cell(threeDaysAgo));
    await tester.pumpAndSettle();
    expect(_cardTextCountOutsideBubble(tester), before);
  });
}
