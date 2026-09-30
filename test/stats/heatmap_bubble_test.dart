import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/stats/heatmap_selection.dart';
import 'package:dance_learning_app/stats/selection_haptic.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/fake_selection_haptic.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

PracticeSessionRecord _record(DateTime start, double seconds,
        {String videoId = 'v1'}) =>
    PracticeSessionRecord(
      start: start,
      videoId: videoId,
      signature: const SongSignature(song: 'My Love'),
      wallSeconds: seconds,
    );

String _dayKey(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

Finder _cell(DateTime day) => find.byKey(Key('heatmap_cell_${_dayKey(day)}'));

Finder _bubble() => find.byKey(const Key('heatmap_bubble'));

String _bubbleText(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: _bubble(), matching: find.byType(Text)))
    .data!;

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
        selectionHapticProvider.overrideWithValue(haptic),
        practiceStatsStoreProvider
            .overrideWithValue(PracticeStatsStore(statsStorage)),
        videoIndexStoreProvider
            .overrideWithValue(InMemoryVideoIndexStorage(initial: VideoIndex.empty)),
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
  return haptic;
}

/// 长按某格并保持手势：进入滑动选择模式后返回手势（未抬手）。
Future<TestGesture> _enterSelectionMode(
  WidgetTester tester,
  DateTime day,
) async {
  final gesture = await tester.startGesture(tester.getCenter(_cell(day)));
  await tester.pump(const Duration(milliseconds: 700));
  return gesture;
}

Future<void> _exitSelectionModeOutside(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('dashboard_total')));
  await tester.pumpAndSettle();
}

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 10);

  testWidgets('点格出单行气泡并联动下方明细', (tester) async {
    await _pump(
      tester,
      records: [_record(today, 42 * 60 + 30)],
    );

    await tester.ensureVisible(_cell(today));
    await tester.pumpAndSettle();
    await tester.tap(_cell(today));
    await tester.pumpAndSettle();

    expect(
      _bubbleText(tester),
      '${today.month}月${today.day}日 · 练习 42:30',
    );
    // 气泡夹在热力图卡内。
    final card = tester.getRect(find.byKey(const Key('heatmap_card')));
    final bubbleRect = tester.getRect(_bubble());
    expect(bubbleRect.left, greaterThanOrEqualTo(card.left));
    expect(bubbleRect.right, lessThanOrEqualTo(card.right));

    await tester.scrollUntilVisible(
      find.byKey(const Key('day_detail')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_detail')), findsOneWidget);
    expect(find.text('42:30'), findsWidgets);
  });

  testWidgets('无练习日的气泡有专属文案', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    final emptyDay = today.subtract(const Duration(days: 3));

    await tester.ensureVisible(_cell(emptyDay));
    await tester.pumpAndSettle();
    await tester.tap(_cell(emptyDay));
    await tester.pumpAndSettle();

    expect(
      _bubbleText(tester),
      '${emptyDay.month}月${emptyDay.day}日 · 这天没有练习',
    );
  });

  testWidgets('长按进入模式：震动一次、滑动实时改选中日与气泡、抬手保留模式', (tester) async {
    final haptic = await _pump(tester, records: [_record(today, 600)]);

    final gesture = await _enterSelectionMode(tester, today);
    expect(haptic.impactCalls, 1);
    expect(
      _bubbleText(tester),
      '${today.month}月${today.day}日 · 练习 10:00',
    );

    // 滑出今天所在列：选中日实时改为更早的无练习日，气泡实时跟随。
    var moved = 0;
    while (_bubbleText(tester).contains('练习') && moved < 6) {
      await gesture.moveBy(const Offset(-heatmapCellPitch / 2, 0));
      await tester.pump();
      moved++;
    }
    expect(moved, greaterThan(0), reason: '滑动应改选到别的日子');
    expect(_bubbleText(tester), contains('这天没有练习'));
    final bubbleDay = RegExp(r'(\d+)月(\d+)日').firstMatch(_bubbleText(tester))!;
    expect(
      DateTime(today.year, int.parse(bubbleDay.group(1)!),
              int.parse(bubbleDay.group(2)!))
          .isBefore(today),
      isTrue,
    );

    // 抬手后仍留在模式里。
    await gesture.up();
    await tester.pumpAndSettle();
    expect(haptic.impactCalls, 1, reason: '进入模式只震一次，滑动与抬手不额外震动');

    // 选中日跟随到前天；起点热力图以外的单击同时取消选择，
    // 气泡与明细一起收起。
    await _exitSelectionModeOutside(tester);
    expect(find.byKey(const Key('heatmap_bubble')), findsNothing);
    expect(find.byKey(const Key('day_detail')), findsNothing);
  });

  testWidgets('点热力图以外任意处退出模式', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    final gesture = await _enterSelectionMode(tester, today);
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dashboard_total')));
    await tester.pumpAndSettle();

    // 退出后横向滚动恢复（模式内禁滚动）。
    final labels = find.byKey(const Key('heatmap_month_labels'));
    final before = tester.getTopLeft(labels);
    await tester.drag(_cell(today), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(labels).dx, greaterThan(before.dx));
  });

  testWidgets('对已选格再长按一次退出模式', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    final gesture = await _enterSelectionMode(tester, today);
    await gesture.up();
    await tester.pumpAndSettle();

    final second = await tester.startGesture(tester.getCenter(_cell(today)));
    await tester.pump(const Duration(milliseconds: 700));
    await second.up();
    await tester.pumpAndSettle();

    // 退出后横向滚动恢复（模式内禁滚动）。
    final labels2 = find.byKey(const Key('heatmap_month_labels'));
    final before2 = tester.getTopLeft(labels2);
    await tester.drag(_cell(today), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(labels2).dx, greaterThan(before2.dx));
  });

  testWidgets('模式内拖动不产生横向滚动', (tester) async {
    await _pump(tester, records: [_record(today, 600)]);
    final gesture = await _enterSelectionMode(tester, today);
    await gesture.up();
    await tester.pumpAndSettle();

    final labels = find.byKey(const Key('heatmap_month_labels'));
    final before = tester.getTopLeft(labels);
    await tester.drag(_cell(today), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(labels), before);
  });
}
