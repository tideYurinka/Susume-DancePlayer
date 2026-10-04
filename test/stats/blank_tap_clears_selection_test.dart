import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/stats/heatmap_selection.dart'
    show heatmapCellPitch;
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
        practiceStatsStoreProvider.overrideWithValue(
          PracticeStatsStore(statsStorage),
        ),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(initial: VideoIndex.empty),
        ),
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

/// 选中一天并滚回页顶（气泡可见、明细已展开）。
Future<void> _selectDay(WidgetTester tester, DateTime day) async {
  await tester.ensureVisible(_cell(day));
  await tester.pumpAndSettle();
  await tester.tap(_cell(day));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);
}

/// 空白单击的公共断言：气泡与明细一起收起。
void _expectSelectionCleared(WidgetTester tester) {
  expect(find.byKey(const Key('heatmap_bubble')), findsNothing);
  expect(find.byKey(const Key('day_detail')), findsNothing);
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);
  final yesterday = today.subtract(const Duration(days: 1));

  testWidgets('单击热力图卡内标题行与图例：取消选择，气泡与明细收起', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);
    await _expectClearedAfterTap(
      tester,
      find.byKey(const Key('heatmap_total')),
    );
    await _selectDay(tester, today);
    await _expectClearedAfterTap(tester, find.text('少'));
  });

  testWidgets('单击柱状图卡内标题与 x 轴日期标签：取消选择，气泡与明细收起', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);
    await _expectClearedAfterTap(
      tester,
      find.byKey(const Key('daily_chart_title')),
    );
    await _selectDay(tester, today);
    // x 轴只有 4 个日期标签，末日 = 今天。
    await _expectClearedAfterTap(
      tester,
      find.byKey(Key('daily_x_label_${_dayKey(today)}')),
    );
  });

  testWidgets('单击两图卡以外的空白（仪表盘卡）：取消选择，气泡与明细收起', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);
    // compact 档视口更矮：仪表盘可能已出懒建缓存，滚回视野再点（空白）。
    final blank = find.byKey(const Key('dashboard_total'));
    await ensureScrollVisible(tester, blank);
    await tester.tap(find.byKey(const Key('dashboard_total')));
    await tester.pumpAndSettle();
    _expectSelectionCleared(tester);
  });

  testWidgets('单击未渲染的未来格位置：取消选择（空白），气泡与明细收起', (tester) async {
    // 热力图末列是今天所在周，周日已是本周最后一格，没有未来格可断言。
    if (today.weekday == DateTime.sunday) return;
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);
    // 未来的日子没有矩形但仍占位，点它算空白。
    final futureDay = today.add(const Duration(days: 1));
    await tester.tap(_cell(futureDay));
    await tester.pumpAndSettle();
    _expectSelectionCleared(tester);
  });

  testWidgets('无练习日的空格子仍是数据点：照旧选中该日出「这天没有练习」', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);

    final emptyDay = yesterday;
    await tester.tap(_cell(emptyDay));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('heatmap_bubble')),
              matching: find.byType(Text),
            ),
          )
          .data,
      '${emptyDay.month}月${emptyDay.day}日 · 这天没有练习',
    );
    // 明细卡在柱状图下方（页面级 ListView 懒建），滚到位再断言。
    await tester.scrollUntilVisible(
      find.byKey(const Key('day_detail')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_detail')), findsOneWidget);
  });

  testWidgets('拖动与长按不误清：横向滚动热力图、柱状图拖动选日、长按进模式都保住选中日', (tester) async {
    final haptic = await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);

    // 热力图横向滚动：不清空。
    await tester.drag(_cell(today), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);

    // 长按进模式：选中日仍在（滚动后先把今天的格滚回可视区）。
    await tester.ensureVisible(_cell(today));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(_cell(today)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptic.impactCalls, 1);
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);

    // 柱状图横向拖动选日：选中日跟着走、不清空。
    final bars = find.byKey(const Key('daily_chart'));
    await tester.ensureVisible(bars);
    await tester.pumpAndSettle();
    final center = tester.getCenter(bars);
    await tester.dragFrom(center, const Offset(-60, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);
  });

  testWidgets('无选中日时单击空白无副作用：不出气泡、不出明细、不震动', (tester) async {
    final haptic = await _pump(tester, records: [_record(today, 600)]);
    await tester.tap(find.byKey(const Key('heatmap_total')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dashboard_total')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('heatmap_bubble')), findsNothing);
    expect(find.byKey(const Key('day_detail')), findsNothing);
    expect(haptic.impactCalls, 0);
  });

  testWidgets('滑动选择模式里拖过未来格不清空（拖动不算单击空白）', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);

    // 长按进模式后，从今天的格向下拖进同一列的未来格占位。
    final gesture = await tester.startGesture(tester.getCenter(_cell(today)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveBy(const Offset(0, heatmapCellPitch * 1.5));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 选中日与模式都还在（退出只有单击空白一条路径）。
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);
    final labels = find.byKey(const Key('heatmap_month_labels'));
    final before = tester.getTopLeft(labels);
    await tester.drag(_cell(today), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(labels), before);
  });

  testWidgets('单击热力图卡内非数据区也退出滑动选择模式（不再豁免）', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    await _selectDay(tester, today);

    // 长按进模式（进模式已震一次），模式内横向滚动被禁。
    final gesture = await tester.startGesture(tester.getCenter(_cell(today)));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();

    // 单击卡内图例：清空选中日并退出模式（横向滚动恢复）。
    await tester.tap(find.text('少'));
    await tester.pumpAndSettle();
    _expectSelectionCleared(tester);
    final labels = find.byKey(const Key('heatmap_month_labels'));
    final before = tester.getTopLeft(labels);
    await tester.drag(_cell(today), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(labels).dx, greaterThan(before.dx));
  });
}

/// 点一个空白目标并断言气泡与明细收起（多次复用的单击步骤）。
Future<void> _expectClearedAfterTap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
  _expectSelectionCleared(tester);
}
