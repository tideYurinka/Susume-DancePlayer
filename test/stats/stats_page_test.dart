import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/home/home_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart'
    show practicePlanStorageProvider;
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/stats/stats_page.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_cover_cache.dart';
import '../helpers/device_viewport.dart';
import '../helpers/scroll_reveal.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// 统计 Tab 汇总卡与两 Tab 壳的页面级测试：内存 fake store 注入，
/// 断言两 Tab 可达、默认落首页、汇总四项数值与无记录空态。
void main() {
  testWidgets('底部两 Tab：默认落首页，点统计进统计页', (tester) async {
    await _pump(tester);

    // 默认首页：首页在树中、统计页尚未构建。
    expect(_selectedTab(tester), 0);
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(StatsPage), findsNothing);

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    expect(_selectedTab(tester), 1);
    expect(find.byType(StatsPage), findsOneWidget);
    expect(find.byKey(const Key('stats_empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();

    expect(_selectedTab(tester), 0);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
  });

  testWidgets('首页顶栏不再有统计入口，旧按天/按署名页不再存在', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('stats_entry_button')), findsNothing);
    expect(find.text('按天'), findsNothing);
    expect(find.text('按歌曲署名'), findsNothing);

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    expect(find.text('按天'), findsNothing);
    expect(find.text('按歌曲署名'), findsNothing);
  });

  testWidgets('仪表盘五项数值与手算一致', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final longAgo = today.subtract(const Duration(days: 400));
    await _pump(
      tester,
      records: [
        _record(today, 372, 'a'),
        _record(today.add(const Duration(hours: 1)), 4500, 'b'),
        _record(yesterday, 600, 'c'),
        _record(longAgo, 65, 'd'),
      ],
    );

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    // 今日 = 372 + 4500 = 4872s = 1:21:12；累计 = 5537s = 1:32:17；昨天与
    // 今天相邻 → 当前连续 2 天；今天练过 → 最长连续也是 2 天。
    _expectDashboardValue(tester, 'dashboard_today', '1:21:12');
    // 本周按自然周（周一起算）：昨天落在本周内时含 600s = 1:31:12；周一
    // 当天昨天属上一周，本周只余今日 = 1:21:12。
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    _expectDashboardValue(
      tester,
      'dashboard_week',
      yesterday.isBefore(weekStart) ? '1:21:12' : '1:31:12',
    );
    _expectDashboardValue(tester, 'dashboard_total', '1:32:17');
    _expectDashboardValue(tester, 'dashboard_current_streak', '2 天');
    _expectDashboardValue(tester, 'dashboard_longest_streak', '2 天');

    // 上行两张宽卡（今日 / 累计）、下行三张窄卡（本周 / 当前 / 最长）。
    final todayTop = tester
        .getTopLeft(find.byKey(const Key('dashboard_today')))
        .dy;
    final totalTop = tester
        .getTopLeft(find.byKey(const Key('dashboard_total')))
        .dy;
    final weekTop = tester
        .getTopLeft(find.byKey(const Key('dashboard_week')))
        .dy;
    final currentTop = tester
        .getTopLeft(find.byKey(const Key('dashboard_current_streak')))
        .dy;
    final longestTop = tester
        .getTopLeft(find.byKey(const Key('dashboard_longest_streak')))
        .dy;
    expect(todayTop, totalTop);
    expect(todayTop, lessThan(weekTop));
    expect(weekTop, currentTop);
    expect(currentTop, longestTop);
  });

  testWidgets('今天没练：当前连续为 0，最长连续不回退', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today.subtract(const Duration(days: 1)), 600, 'a'),
        _record(today.subtract(const Duration(days: 2)), 600, 'b'),
      ],
    );

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    _expectDashboardValue(tester, 'dashboard_current_streak', '0 天');
    _expectDashboardValue(tester, 'dashboard_longest_streak', '2 天');
  });

  testWidgets('仪表盘数字大号加粗在上、口径说明灰色小字在下', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    final theme = Theme.of(
      tester.element(find.byKey(const Key('dashboard_card'))),
    );
    final tiles = find.descendant(
      of: find.byKey(const Key('dashboard_card')),
      matching: find.byType(Text),
    );
    final texts = tester.widgetList<Text>(tiles).toList();
    expect(texts.length, greaterThanOrEqualTo(10));

    final valueStyle = texts.first.style!;
    expect(
      valueStyle.fontSize,
      greaterThan(theme.textTheme.bodyMedium!.fontSize!),
    );
    final captionStyle = texts[1].style!;
    expect(
      captionStyle.fontSize,
      lessThan(theme.textTheme.bodyMedium!.fontSize!),
    );
  });

  testWidgets('区块次序为仪表盘 → 热力图 → 柱状图 → 明细 → 排行', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': _documents(rangeStartMs: 0, rangeEndMs: 100000)},
      records: [_record(today, 300, 'v1', song: 'Alpha')],
    );
    await _openStats(tester);
    await _tapHeatmapCell(tester, today);

    // 懒建 ListView：滚动到排行时仪表盘可能已退场，逐块滚入视野、把视口
    // 内坐标加上滚动偏移折算成页面绝对位置再比较。
    double absoluteTop(String key) {
      final rect = tester.getRect(find.byKey(Key(key)));
      final pixels = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      return rect.top + pixels;
    }

    final tops = <double>[];
    for (final key in [
      'dashboard_card',
      'heatmap_card',
      'daily_chart_card',
      'day_detail',
      'ranking_card',
    ]) {
      final target = find.byKey(Key(key));
      if (target.evaluate().isEmpty) {
        // compact 档视口更矮：滚到热力图后仪表盘可能已出懒建缓存，须向
        // 上滚回；其余区块按页序逐个向下滚入。
        await tester.scrollUntilVisible(
          target,
          key == 'dashboard_card' ? -400 : 400,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.pumpAndSettle();
      tops.add(absoluteTop(key));
    }
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: '区块 $i 次序错误');
    }
  });

  testWidgets('窄屏下仪表盘数字单行缩放不溢出', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 4872, 'a')]);
    // 360 逻辑宽窄屏量级（_pump 内先铺常规视口，这里覆盖为窄屏）：
    // 取 compact 档（361.1×781.7dp，dpr 3.5 随档）。
    useNamedViewport(tester, ViewportTier.compact);
    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    for (final key in [
      'dashboard_today',
      'dashboard_week',
      'dashboard_total',
      'dashboard_current_streak',
      'dashboard_longest_streak',
    ]) {
      final tile = tester.getRect(find.byKey(Key(key)));
      // 卡面首个 Text 是大号数字：单行（高度不超字号行高）且不越出卡面。
      final value = tester.getRect(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      );
      expect(value.height, lessThanOrEqualTo(40), reason: key);
      expect(value.left, greaterThanOrEqualTo(tile.left), reason: key);
      expect(value.right, lessThanOrEqualTo(tile.right), reason: key);
    }
  });

  testWidgets('无任何记录：整页空态引导，不出汇总卡', (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stats_empty')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_card')), findsNothing);
  });

  testWidgets('只有 0 秒记录：仍是空态引导，不出零值汇总卡', (tester) async {
    final now = DateTime.now();
    await _pump(
      tester,
      records: [_record(DateTime(now.year, now.month, now.day, 10), 0, 'a')],
    );

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stats_empty')), findsOneWidget);
    expect(find.byKey(const Key('dashboard_card')), findsNothing);
  });

  testWidgets('再进统计 Tab 重新装入记录：空态转为当日数值', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stats_empty')), findsOneWidget);

    // 在统计页之外练一次（写入 store 并落盘）。
    final now = DateTime.now();
    await store.recordPlaying(
      videoId: 'v1',
      signature: const SongSignature(song: 'My Love'),
      start: DateTime(now.year, now.month, now.day, 10),
      end: DateTime(now.year, now.month, now.day, 10, 3),
    );
    await store.settle();

    await tester.tap(find.byKey(const Key('tab_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab_stats')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('stats_empty')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard_today')),
        matching: find.text('3:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('每日柱状图默认近 30 天，可切近 7 与近 90', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    expect(find.byKey(const Key('daily_chart')), findsOneWidget);
    expect(_barFills(), findsNWidgets(30));
    expect(find.byKey(Key('daily_bar_fill_${_dayKey(today)}')), findsOneWidget);

    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    expect(_barFills(), findsNWidgets(7));

    await _tapFilter(tester, 'filter_window_90');
    await tester.pumpAndSettle();
    expect(_barFills(), findsNWidgets(90));
  });

  testWidgets('筛选行：时间维度与单位两组控件，默认近 30 天 / 按时间', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    expect(find.byKey(const Key('filter_row')), findsOneWidget);
    expect(_chipSelected(tester, 'filter_window_30'), isTrue);
    expect(_chipSelected(tester, 'filter_window_7'), isFalse);
    expect(_chipSelected(tester, 'filter_window_90'), isFalse);
    expect(_chipSelected(tester, 'filter_unit_time'), isTrue);
    expect(_chipSelected(tester, 'filter_unit_count'), isFalse);
  });

  testWidgets('切换单位后热力图、柱状图、明细、排行同时按场次重算', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      records: [
        // 四个非零日（含今天）：v2 按总时长领先（9:10），v1 场次多但每次短。
        // 今天：v2 一场 200s + v1 两场各 30s；昨天 v2 300s；前天 v1 40s；
        // 大前天 v2 50s。今天按时长 = P75 边界（档 3），按次数是唯一最大
        // （档 4），切到按次数色深变深。
        _record(today, 200, 'v2', song: 'Beta'),
        _record(today.add(const Duration(hours: 1)), 30, 'v1', song: 'Alpha'),
        _record(today.add(const Duration(hours: 2)), 30, 'v1', song: 'Alpha'),
        _record(
          today.subtract(const Duration(days: 1)),
          300,
          'v2',
          song: 'Beta',
        ),
        _record(
          today.subtract(const Duration(days: 2)),
          40,
          'v1',
          song: 'Alpha',
        ),
        _record(
          today.subtract(const Duration(days: 3)),
          50,
          'v2',
          song: 'Beta',
        ),
      ],
    );
    await _openStats(tester);

    // 按时长：排行 v2（9:10）在前。
    final heatToday = _cellColor(tester, today);
    expect(_fillHeight(tester, today), greaterThan(0));
    await _scrollToRanking(tester);
    _expectRankingOrder(tester, ['v2', 'v1']);
    expect(_rankingKeyValue(tester, 'v2'), '9:10');

    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();

    // 按次数：点开今天的明细，行值变为场次且按场次降序。
    await _tapHeatmapCell(tester, today);
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_v1')),
        matching: find.text('2 次'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_v2')),
        matching: find.text('1 次'),
      ),
      findsOneWidget,
    );
    final aTop = tester
        .getTopLeft(find.byKey(const Key('day_detail_row_v1')))
        .dy;
    final bTop = tester
        .getTopLeft(find.byKey(const Key('day_detail_row_v2')))
        .dy;
    expect(aTop, lessThan(bTop));

    await _scrollToRanking(tester);
    _expectRankingOrder(tester, ['v1', 'v2']);
    expect(_rankingKeyValue(tester, 'v1'), '3 次');
    expect(_rankingKeyValue(tester, 'v2'), '3 次');
    // 热力图也随单位重算：今天按时长 = P75 边界（档 3），按次数超过全部
    // 边界（档 4），色深变深。
    expect(_cellColor(tester, today).a, greaterThan(heatToday.a));
  });

  testWidgets('切换单位清空已选日与明细；时间维度只改柱状图窗口', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final tenDaysAgo = today.subtract(const Duration(days: 10));
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('a')]),
      records: [_record(today, 300, 'a'), _record(tenDaysAgo, 600, 'a')],
    );
    await _openStats(tester);

    // 热力图窗口基准：53 周、371 格，不随时间维度变化。
    expect(_heatmapWeeks(), findsNWidgets(53));
    expect(_heatmapCells(), findsNWidgets(371));

    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);
    expect(find.byKey(const Key('day_detail')), findsOneWidget);

    // 切单位：明细退场（选中日被清空）。
    await _scrollToTop(tester);
    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_detail')), findsNothing);

    // 柱数不变（单位只换量不换窗口）。
    expect(_barFills(), findsNWidgets(30));

    // 切窗口：柱变 7 根，热力图仍 371 格。
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    expect(_barFills(), findsNWidgets(7));
    expect(_heatmapCells(), findsNWidgets(371));

    // 点开旧窗口内的日再切回近 7 天：明细一起退场。
    await _tapFilter(tester, 'filter_window_30');
    await tester.pumpAndSettle();
    await _tapDailyBar(tester, tenDaysAgo);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);
    expect(find.byKey(const Key('day_detail_row_a')), findsOneWidget);
    await _scrollToTop(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('day_detail')), findsNothing);
  });

  testWidgets('柱状图与排行卡内不再保留自己的范围 / 排序键控件', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      records: [_record(today, 300, 'v1')],
    );
    await _openStats(tester);

    expect(find.byKey(const Key('daily_range_7')), findsNothing);
    expect(find.byKey(const Key('ranking_key_total')), findsNothing);
    expect(find.byKey(const Key('ranking_key_average')), findsNothing);
  });

  testWidgets('无练习的日子柱高为 0，有练习的日子随当天的量成比例', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await _pump(
      tester,
      records: [_record(today, 300, 'a'), _record(yesterday, 60, 'b')],
    );
    await _openStats(tester);

    // 窗口内最长为 300s → 今天满高、昨天 1/5、空日为 0。
    expect(_fillHeight(tester, today), greaterThan(0));
    expect(
      _fillHeight(tester, yesterday),
      closeTo(_fillHeight(tester, today) / 5, 0.5),
    );
    expect(_fillHeight(tester, twoDaysAgo), 0);
  });

  testWidgets('有练习的极短一天不读成断档：柱高有最小可见高度', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await _pump(
      tester,
      records: [_record(today, 1, 'a'), _record(yesterday, 3600, 'b')],
    );
    await _openStats(tester);

    // 1s 对 3600s 归一后不足 1px，仍给最小可见高度；空日仍为 0。
    expect(_fillHeight(tester, today), greaterThanOrEqualTo(2));
    expect(_fillHeight(tester, twoDaysAgo), 0);
  });

  testWidgets('近 7 天柱顶出现数值，近 30 / 90 天不出现', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    // 默认近 30 天：柱太挤，不标柱顶数值。
    expect(_barValues(), findsNothing);

    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('daily_bar_value_${_dayKey(today)}')),
      findsOneWidget,
    );
    // 按时间标分钟数（300s = 5 分）。
    expect(
      tester
          .widget<Text>(find.byKey(Key('daily_bar_value_${_dayKey(today)}')))
          .data,
      '5',
    );

    await _tapFilter(tester, 'filter_window_90');
    await tester.pumpAndSettle();
    expect(_barValues(), findsNothing);
  });

  testWidgets('卡片标题含单位与窗口合计，随单位切换', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    await _pump(
      tester,
      records: [_record(today, 300, 'a'), _record(yesterday, 60, 'b')],
    );
    await _openStats(tester);

    // 近 30 天窗口合计：300 + 60 = 360s = 6:00。
    expect(find.text('每日练习时长（分钟） · 合计 6:00'), findsOneWidget);

    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();
    expect(find.text('每日练习次数 · 合计 2 次'), findsOneWidget);
  });

  testWidgets('选中柱有竖向虚线，未选中柱没有', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    expect(_barDashes(), findsNothing);

    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('daily_bar_dashes_${_dayKey(today)}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('daily_bar_dashes_${_dayKey(yesterday)}')),
      findsNothing,
    );
  });

  testWidgets('x 轴有 4 个 M/d 日期标签：首日、约 1/3、约 2/3、末日', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();

    String label(DateTime day) => '${day.month}/${day.day}';
    final expected = [
      today.subtract(const Duration(days: 6)),
      today.subtract(const Duration(days: 4)),
      today.subtract(const Duration(days: 2)),
      today,
    ].map(label);
    for (final text in expected) {
      expect(find.text(text), findsOneWidget, reason: '缺日期标签 $text');
    }
    expect(_xLabels(), findsNWidgets(4));
  });

  testWidgets('y 轴有整齐刻度与网格线，柱顶与刻度同尺', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    await _pump(
      tester,
      records: [_record(today, 300, 'a'), _record(yesterday, 150, 'b')],
    );
    await _openStats(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();

    // 窗口最大 300s = 5 分 → 上界 5、步长 1，刻度 0–5。
    for (final tick in [0, 1, 2, 3, 4, 5]) {
      expect(
        find.byKey(Key('daily_axis_tick_$tick')),
        findsOneWidget,
        reason: '缺刻度 $tick',
      );
    }
    expect(find.byKey(const Key('daily_gridlines')), findsOneWidget);

    // 柱高按上界 5 分归一：300s 满高，150s 恰为其一半（同尺）。
    final full = _fillHeight(tester, today);
    expect(full, greaterThan(0));
    expect(_fillHeight(tester, yesterday), closeTo(full / 2, 0.5));
  });

  testWidgets('点柱展开当天各舞与时长，按时长降序', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today, 100, 'a', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 300, 'b', song: 'Beta'),
      ],
    );
    await _openStats(tester);

    expect(find.byKey(const Key('day_detail')), findsNothing);

    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);

    expect(find.byKey(const Key('day_detail')), findsOneWidget);
    expect(find.byKey(const Key('day_detail_row_b')), findsOneWidget);
    expect(find.byKey(const Key('day_detail_row_a')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_b')),
        matching: find.text('5:00'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_a')),
        matching: find.text('1:40'),
      ),
      findsOneWidget,
    );

    // 「Beta」行在「Alpha」行上方（降序）。
    final betaTop = tester
        .getTopLeft(find.byKey(const Key('day_detail_row_b')))
        .dy;
    final alphaTop = tester
        .getTopLeft(find.byKey(const Key('day_detail_row_a')))
        .dy;
    expect(betaTop, lessThan(alphaTop));
  });

  testWidgets('点明细行 push 该舞详情', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'v1', song: 'Alpha')]);
    await _openStats(tester);

    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);

    final row = find.byKey(const Key('day_detail_row_v1'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(DanceDetailPage), findsOneWidget);
  });

  testWidgets('明细行为排行同款版式：行内单值、进度条按当天最大值归一', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today, 100, 'a', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 300, 'b', song: 'Beta'),
      ],
    );
    await _openStats(tester);
    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);

    // 行内只有当前单位的一个数值（按时长写时长），无第二个单位并列。
    List<String> rowTexts(String videoId) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key('day_detail_row_$videoId')),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data ?? '')
        .toList();
    expect(rowTexts('a'), ['Alpha', '1:40']);
    expect(rowTexts('b'), ['Beta', '5:00']);

    // 进度条比例 = 该行值 ÷ 当天最大值；最大那支舞的条为满。
    expect(_dayDetailBarValue(tester, 'b'), 1.0);
    expect(_dayDetailBarValue(tester, 'a'), closeTo(100 / 300, 0.001));
  });

  testWidgets('切换单位后明细行数值与进度条一起换口径', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today, 200, 'v2', song: 'Beta'),
        _record(today.add(const Duration(hours: 1)), 30, 'v1', song: 'Alpha'),
        _record(today.add(const Duration(hours: 2)), 30, 'v1', song: 'Alpha'),
      ],
    );
    await _openStats(tester);

    // 切到按次数再选当天：v1 两场为最大、条满；v2 一场、条为一半。
    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();
    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_v1')),
        matching: find.text('2 次'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_v2')),
        matching: find.text('1 次'),
      ),
      findsOneWidget,
    );
    expect(_dayDetailBarValue(tester, 'v1'), 1.0);
    expect(_dayDetailBarValue(tester, 'v2'), closeTo(0.5, 0.001));
  });

  testWidgets('没有练习的日子也能点开，明细显示空', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    await _tapDailyBar(tester, twoDaysAgo);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);

    expect(find.byKey(const Key('day_detail')), findsOneWidget);
    expect(find.byKey(const Key('day_detail_empty')), findsOneWidget);
    expect(find.text('这天没有练习'), findsOneWidget);
    expect(find.byKey(const Key('day_detail_row_a')), findsNothing);

    // 换成有记录的日子：空态消失、行出现。
    await _scrollToTop(tester);
    await _tapDailyBar(tester, yesterday);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);
    expect(find.byKey(const Key('day_detail_empty')), findsOneWidget);

    await _scrollToTop(tester);
    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);
    expect(find.byKey(const Key('day_detail_empty')), findsNothing);
    expect(find.byKey(const Key('day_detail_row_a')), findsOneWidget);
  });

  testWidgets('切换范围只改窗口：窗口外的柱与已选明细一起退场', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final tenDaysAgo = today.subtract(const Duration(days: 10));
    await _pump(
      tester,
      records: [_record(today, 300, 'a'), _record(tenDaysAgo, 600, 'b')],
    );
    await _openStats(tester);

    final oldBar = find.byKey(Key('daily_bar_${_dayKey(tenDaysAgo)}'));
    expect(oldBar, findsOneWidget);

    await _tapDailyBar(tester, tenDaysAgo);
    await tester.pumpAndSettle();
    await _scrollToDayDetail(tester);
    expect(find.byKey(const Key('day_detail_row_b')), findsOneWidget);

    // 近 7 天窗口不含 10 天前：该柱与已选明细一起退场。
    await _scrollToTop(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    expect(oldBar, findsNothing);
    expect(find.byKey(const Key('day_detail')), findsNothing);
    expect(find.byKey(Key('daily_bar_fill_${_dayKey(today)}')), findsOneWidget);
  });

  testWidgets('年热力图：53 列、371 格，今天所在格在末列', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    expect(find.byKey(const Key('heatmap_card')), findsOneWidget);
    expect(_heatmapWeeks(), findsNWidgets(53));
    expect(_heatmapCells(), findsNWidgets(371));
    expect(find.byKey(Key('heatmap_cell_${_dayKey(today)}')), findsOneWidget);

    // 末列（本周）最后一格是本周日，首格是本周一。
    final monday = today.subtract(Duration(days: today.weekday - 1));
    expect(find.byKey(Key('heatmap_cell_${_dayKey(monday)}')), findsOneWidget);
    expect(
      find.byKey(
        Key('heatmap_cell_${_dayKey(monday.add(const Duration(days: 6)))}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('热力图色深按当日时长分档：空格最浅，练得多的更深', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await _pump(
      tester,
      records: [
        _record(today, 45 * 60, 'a'), // 45 分 → 高档
        _record(yesterday, 5 * 60, 'b'), // 5 分 → 低档
      ],
    );
    await _openStats(tester);

    final empty = _cellColor(tester, twoDaysAgo);
    final low = _cellColor(tester, yesterday);
    final high = _cellColor(tester, today);
    expect(empty, isNot(low));
    expect(high, isNot(low));
    expect(high.a, greaterThan(low.a));
  });

  testWidgets('点热力图格打开当日明细（与柱状图同一读面）', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today, 100, 'a', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 300, 'b', song: 'Beta'),
      ],
    );
    await _openStats(tester);

    expect(find.byKey(const Key('day_detail')), findsNothing);
    await _tapHeatmapCell(tester, today);

    expect(find.byKey(const Key('day_detail')), findsOneWidget);
    expect(find.byKey(const Key('day_detail_row_b')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_b')),
        matching: find.text('5:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('热力图的空格也能点开，明细显示空', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    await _tapHeatmapCell(tester, twoDaysAgo);

    expect(find.byKey(const Key('day_detail')), findsOneWidget);
    expect(find.byKey(const Key('day_detail_empty')), findsOneWidget);
  });

  testWidgets('年热力图默认滚到最近一周：今天所在格首屏可见', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    final card = tester.getRect(find.byKey(const Key('heatmap_card')));
    final cell = tester.getRect(
      find.byKey(Key('heatmap_cell_${_dayKey(today)}')),
    );
    expect(cell.left, greaterThanOrEqualTo(card.left));
    expect(cell.right, lessThanOrEqualTo(card.right));
  });

  testWidgets('未来格不可点：本周内还没到的日子不展开明细', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    // 周日：今天已是本周最后一格，本周没有未来格可断言。
    if (today.weekday == DateTime.sunday) return;
    final tomorrow = today.add(const Duration(days: 1));
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);

    final cell = find.byKey(Key('heatmap_cell_${_dayKey(tomorrow)}'));
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.tap(cell);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('day_detail')), findsNothing);
  });

  testWidgets('排行按窗口 × 单位求值：默认按时长；窗口内没练的不出行', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final eightDaysAgo = today.subtract(const Duration(days: 8));
    await _pump(
      tester,
      index: VideoIndex(
        entries: [_entry('v1'), _entry('v2'), _entry('v3'), _entry('v4')],
      ),
      records: [
        _record(today, 300, 'v1', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 120, 'v2', song: 'Beta'),
        _record(eightDaysAgo, 600, 'v4', song: 'Delta'), // 近 7 天窗口外
      ],
    );
    await _openStats(tester);
    await _scrollToRanking(tester);

    expect(find.byKey(const Key('ranking_card')), findsOneWidget);
    // 默认近 30 天按时长降序：v1 5:00 > v2 2:00；v3 窗口内没练不出行；
    // v4 只在近 30 天窗口内（8 天前）。
    expect(_rankingRows(), findsNWidgets(3));
    _expectRankingOrder(tester, ["v4", "v1", "v2"]);
    expect(_rankingKeyValue(tester, 'v1'), '5:00');

    // 切近 7 天：滚回筛选行点近 7 天，窗口外的 v4 退场。
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ranking_row_v4')), findsNothing);
  });

  testWidgets('行只显示当前单位的一个数值', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      records: [_record(today, 300, 'v1', song: 'Alpha')],
    );
    await _openStats(tester);
    await _scrollToRanking(tester);

    expect(_rankingKeyValue(tester, 'v1'), '5:00');

    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();

    expect(_rankingKeyValue(tester, 'v1'), '1 次');
  });

  testWidgets('只列现存舞：已删舞的时长仍进汇总卡，不进排行', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': _documents(rangeStartMs: 0, rangeEndMs: 100000)},
      records: [
        _record(today, 300, 'v1', song: 'Alpha'),
        _record(
          today.add(const Duration(hours: 1)),
          600,
          'ghost',
          song: 'Ghost',
        ),
      ],
    );
    await _openStats(tester);

    // 汇总卡含已删舞的 600s：300 + 600 = 900s = 15:00。
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard_total')),
        matching: find.text('15:00'),
      ),
      findsOneWidget,
    );

    await _scrollToRanking(tester);
    expect(find.byKey(const Key('ranking_row_v1')), findsOneWidget);
    expect(find.byKey(const Key('ranking_row_ghost')), findsNothing);
  });

  testWidgets('窗口内无任何练习：排行显示空文案，不出空排行', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(tester, records: [_record(today, 300, 'ghost', song: 'Ghost')]);
    await _openStats(tester);

    // 记录仍在，汇总卡照出；排行无现存舞可列。
    expect(find.byKey(const Key('dashboard_card')), findsOneWidget);
    await _scrollToRanking(tester);
    expect(find.byKey(const Key('ranking_empty')), findsOneWidget);
    expect(_rankingRows(), findsNothing);
  });

  group('热力图版式与动态分档', () {
    Future<void> openAndRevealHeatmap(WidgetTester tester) async {
      await _openStats(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('heatmap_card')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('标题为单行「过去一年已练习 …」（合计只出现一次），跟随单位', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      await _pump(
        tester,
        records: [
          _record(today, 300, 'a'),
          _record(today.subtract(const Duration(days: 8)), 600, 'b'),
          // 未来日与窗口外记录不计入标题合计。
          _record(today.add(const Duration(days: 3)), 300, 'c'),
          _record(today.subtract(const Duration(days: 400)), 600, 'd'),
        ],
      );
      await openAndRevealHeatmap(tester);

      final card = find.byKey(const Key('heatmap_card'));
      expect(find.text('过去一年已练习 15:00'), findsOneWidget);
      // 仪表盘恒按时长，合计数值只在热力图标题行出现一次。
      expect(
        find.descendant(of: card, matching: find.text('15:00')),
        findsNothing,
      );
      expect(find.byKey(const Key('heatmap_total')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('filter_unit_count')));
      await tester.pumpAndSettle();
      await _tapFilter(tester, 'filter_unit_count');
      await tester.pumpAndSettle();

      expect(find.text('过去一年已练习 2 次'), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('2 次')),
        findsNothing,
      );
    });

    testWidgets('中文月份标签与周一/周三/周五三行星期标签就位', (tester) async {
      await _pump(tester, records: [_record(DateTime.now(), 300, 'a')]);
      await openAndRevealHeatmap(tester);

      expect(find.text('周一'), findsOneWidget);
      expect(find.text('周三'), findsOneWidget);
      expect(find.text('周五'), findsOneWidget);

      // 几何对齐：三行标签的中心分别落在网格第 1/3/5 行的中心。
      double labelCenterDy(String label) =>
          tester.getCenter(find.text(label)).dy;
      final gridTop = tester
          .getRect(find.byKey(const Key('heatmap_month_labels')))
          .bottom;
      final firstRowCenter = gridTop + 7; // 半个格距（格 12 + 间距 2）
      expect(labelCenterDy('周一'), firstRowCenter);
      expect(labelCenterDy('周三'), firstRowCenter + 2 * 14);
      expect(labelCenterDy('周五'), firstRowCenter + 4 * 14);

      // 53 周窗口内每个出现过「1 号」的月份都有一个标签。
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final firstDay = monday.subtract(const Duration(days: 52 * 7));
      var month = DateTime(firstDay.year, firstDay.month);
      var labels = 0;
      while (month.isBefore(today.add(const Duration(days: 1)))) {
        if (!month.add(const Duration(days: 1)).isBefore(firstDay)) {
          expect(find.text('${month.month}月'), findsWidgets);
          labels++;
        }
        month = DateTime(month.year, month.month + 1);
      }
      expect(labels, greaterThan(10));
    });

    testWidgets('月份标签与周列在同一个横向滚动容器里（随网格滚动）', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      await _pump(tester, records: [_record(today, 300, 'a')]);
      await openAndRevealHeatmap(tester);

      final monthLabel = find.byKey(const Key('heatmap_month_labels'));
      final cell = find.byKey(Key('heatmap_cell_${_dayKey(today)}'));
      final monthScrolls = find
          .ancestor(
            of: monthLabel,
            matching: find.byType(SingleChildScrollView),
          )
          .evaluate()
          .toSet();
      final cellScrolls = find
          .ancestor(of: cell, matching: find.byType(SingleChildScrollView))
          .evaluate()
          .toSet();
      expect(monthScrolls.intersection(cellScrolls), isNotEmpty);
    });

    testWidgets('未来日不渲染矩形且星期行仍对齐', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      // 周日：本周没有未来格可断言。
      if (today.weekday == DateTime.sunday) return;
      final tomorrow = today.add(const Duration(days: 1));
      await _pump(tester, records: [_record(today, 300, 'a')]);
      await openAndRevealHeatmap(tester);

      // 占位还在（星期行对齐），但没有填充；尺寸与数据格一致。
      expect(_cellColorOrNull(tester, tomorrow), isNull);
      expect(
        tester.getSize(find.byKey(Key('heatmap_cell_${_dayKey(tomorrow)}'))),
        tester.getSize(find.byKey(Key('heatmap_cell_${_dayKey(today)}'))),
      );
      expect(_cellColorOrNull(tester, today), isNotNull);
    });

    testWidgets('图例只剩「少 ▢▢▢▢▢ 多」色块，分档说明不出现，随单位一致', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10);
      final yesterday = today.subtract(const Duration(days: 1));
      await _pump(
        tester,
        records: [
          _record(today, 45 * 60, 'a'),
          _record(yesterday, 5 * 60, 'b'),
        ],
      );
      await openAndRevealHeatmap(tester);
      await tester.ensureVisible(find.byKey(const Key('heatmap_legend')));
      await tester.pumpAndSettle();

      expect(find.text('少'), findsOneWidget);
      expect(find.text('多'), findsOneWidget);
      for (var level = 0; level <= 4; level++) {
        expect(find.byKey(Key('heatmap_legend_swatch_$level')), findsOneWidget);
      }
      expect(find.textContaining('按当天练习时长分档'), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('filter_unit_count')));
      await tester.pumpAndSettle();
      await _tapFilter(tester, 'filter_unit_count');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('heatmap_legend')));
      await tester.pumpAndSettle();

      // 图例不随单位改变：仍是同一组色块与两端文字，无任何分档说明。
      expect(find.text('少'), findsOneWidget);
      expect(find.text('多'), findsOneWidget);
      for (var level = 0; level <= 4; level++) {
        expect(find.byKey(Key('heatmap_legend_swatch_$level')), findsOneWidget);
      }
      expect(find.textContaining('按当天练习场次分档'), findsNothing);
    });
  });

  testWidgets('点排行行 push 该舞详情', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      documents: {'v1': _documents(rangeStartMs: 0, rangeEndMs: 100000)},
      records: [_record(today, 300, 'v1', song: 'Alpha')],
    );
    await _openStats(tester);
    await _scrollToRanking(tester);

    final row = find.byKey(const Key('ranking_row_v1'));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(DanceDetailPage), findsOneWidget);
  });

  testWidgets('行尾进度条：填充比例 = 该行值 ÷ 列表最大值，固定宽度、主题主色', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      records: [
        _record(today, 300, 'v1', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 60, 'v2', song: 'Beta'),
      ],
    );
    await _openStats(tester);
    await _scrollToRanking(tester);

    final primary = Theme.of(
      tester.element(find.byKey(const Key('ranking_card'))),
    ).colorScheme.primary;

    // v1 300s 是最大值，占满；v2 60s 为 60/300 = 0.2。
    expect(_rankingBar(tester, 'v1').value, 1.0);
    expect(_rankingBar(tester, 'v2').value, closeTo(0.2, 1e-9));

    // 固定宽度：两行进度条同宽，且与行文本左缘不重叠。
    expect(
      tester.getSize(_rankingBarFinder('v1')).width,
      tester.getSize(_rankingBarFinder('v2')).width,
    );
    expect(tester.getSize(_rankingBarFinder('v1')).width, lessThan(120));

    // 主题主色，不改主题、不引品牌色。
    expect(_rankingBar(tester, 'v1').color, primary);
  });

  testWidgets('排行数值在进度条上方水平居中、字号大于说明字、行内只有一个数值', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      records: [
        _record(today, 300, 'v1', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 60, 'v2', song: 'Beta'),
      ],
    );
    await _openStats(tester);
    await _scrollToRanking(tester);

    for (final videoId in ['v1', 'v2']) {
      final keyFinder = find.byKey(Key('ranking_row_key_$videoId'));
      final barRect = tester.getRect(_rankingBarFinder(videoId));
      final valueRect = tester.getRect(keyFinder);

      // 数值在进度条上方：数值底边不高于进度条顶边。
      expect(valueRect.bottom, lessThanOrEqualTo(barRect.top + 0.5));

      // 数值水平中心与进度条水平中心对齐（1px 容差）。
      expect(
        (valueRect.center.dx - barRect.center.dx).abs(),
        lessThanOrEqualTo(1.0),
      );

      // 字号大于灰字说明（titleMedium > bodySmall）。
      final valueStyle = tester.widget<Text>(keyFinder).style!;
      expect(valueStyle.fontSize!, greaterThan(12.0));
    }

    // 行内只出现一个单位的数值：v1 行内只有舞名与数值两个 Text。
    final rowTexts = find.descendant(
      of: find.byKey(const Key('ranking_row_v1')),
      matching: find.byType(Text),
    );
    expect(rowTexts, findsExactly(2));
    expect(_rankingKeyValue(tester, 'v1'), '5:00');
  });

  testWidgets('切换单位后进度条比例按新口径的最大值归一', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
      records: [
        _record(today, 300, 'v1', song: 'Alpha'),
        // v2 一场 60s：按时间是 60/300=0.2，按场次是 1/1=1.0。
        _record(today.add(const Duration(hours: 1)), 60, 'v2', song: 'Beta'),
      ],
    );
    await _openStats(tester);
    await _scrollToRanking(tester);
    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();

    expect(_rankingBar(tester, 'v1').value, 1.0);
    expect(_rankingBar(tester, 'v2').value, 1.0);
  });

  testWidgets('柱状图横向拖动连续选日：经过的柱依次成为选中日', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final day2 = today.subtract(const Duration(days: 2));
    final day4 = today.subtract(const Duration(days: 4));
    await _pump(
      tester,
      records: [
        _record(today, 300, 'a'),
        _record(day2, 120, 'b'),
        _record(day4, 60, 'c'),
      ],
    );
    await _openStats(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();

    expect(_barDashes(), findsNothing);

    // 拖动跨过数根柱：今天 → 前天 → 大前天，途中每一步都选中所在柱。
    Offset center(DateTime day) =>
        tester.getCenter(find.byKey(Key('daily_bar_${_dayKey(day)}')));
    // compact 档视口更矮：柱状图须先滚入视口再起手拖动。
    await tester.ensureVisible(find.byKey(Key('daily_bar_${_dayKey(today)}')));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(center(today));
    await tester.pump();
    await gesture.moveBy(center(day2) - center(today));
    await tester.pump();
    expect(
      find.byKey(Key('daily_bar_dashes_${_dayKey(day2)}')),
      findsOneWidget,
    );
    await gesture.moveBy(center(day4) - center(day2));
    await tester.pump();
    expect(
      find.byKey(Key('daily_bar_dashes_${_dayKey(day4)}')),
      findsOneWidget,
    );
    expect(find.byKey(Key('daily_bar_dashes_${_dayKey(day2)}')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();

    // 明细实时跟随最后的选中日（大前天只有 c 练了 60s = 1:00）。
    await _scrollToDayDetail(tester);
    expect(
      find.descendant(
        of: find.byKey(const Key('day_detail_row_c')),
        matching: find.text('1:00'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('气泡首行日期+合计，分解行最多前 3 支舞按时长降序', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today, 300, 'b', song: 'Beta'),
        _record(today.add(const Duration(hours: 1)), 200, 'd', song: 'Delta'),
        _record(today.add(const Duration(hours: 2)), 100, 'a', song: 'Alpha'),
        _record(today.add(const Duration(hours: 3)), 50, 'c', song: 'Gamma'),
      ],
    );
    await _openStats(tester);
    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();

    // 首行「8月22日 合计 10:50」（合计 650s = 10:50）。
    expect(find.text('${today.month}月${today.day}日 合计 10:50'), findsOneWidget);
    // 分解行只取按时长降序的前 3 支：Beta 5:00、Delta 3:20、Alpha 1:40。
    for (final videoId in ['b', 'd', 'a']) {
      expect(find.byKey(Key('bar_chart_bubble_row_$videoId')), findsOneWidget);
    }
    expect(find.byKey(const Key('bar_chart_bubble_row_c')), findsNothing);
    final bTop = tester
        .getTopLeft(find.byKey(const Key('bar_chart_bubble_row_b')))
        .dy;
    final dTop = tester
        .getTopLeft(find.byKey(const Key('bar_chart_bubble_row_d')))
        .dy;
    final aTop = tester
        .getTopLeft(find.byKey(const Key('bar_chart_bubble_row_a')))
        .dy;
    expect(bTop, lessThan(dTop));
    expect(dTop, lessThan(aTop));
  });

  testWidgets('按场次时气泡分解行按场次降序', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    await _pump(
      tester,
      records: [
        _record(today, 300, 'a', song: 'Alpha'),
        _record(today.add(const Duration(hours: 1)), 100, 'b', song: 'Beta'),
        _record(today.add(const Duration(hours: 2)), 100, 'b', song: 'Beta'),
        _record(today.add(const Duration(hours: 3)), 100, 'b', song: 'Beta'),
      ],
    );
    await _openStats(tester);
    await _tapFilter(tester, 'filter_unit_count');
    await tester.pumpAndSettle();
    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();

    expect(find.text('${today.month}月${today.day}日 合计 4 次'), findsOneWidget);
    // 按场次：Beta 3 次在 Alpha 1 次之上（按时间是 Alpha 在上）。
    final bTop = tester
        .getTopLeft(find.byKey(const Key('bar_chart_bubble_row_b')))
        .dy;
    final aTop = tester
        .getTopLeft(find.byKey(const Key('bar_chart_bubble_row_a')))
        .dy;
    expect(bTop, lessThan(aTop));

    expect(
      tester.widget<Text>(find.byKey(const Key('bar_chart_bubble_row_b'))).data,
      'Beta 3 次',
    );
  });

  testWidgets('气泡水平夹在柱状图卡内：首日与末日都被钳住', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final firstDay = today.subtract(const Duration(days: 6));
    await _pump(tester, records: [_record(today, 300, 'a')]);
    await _openStats(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();

    // 钳制域是图区（网格线铺满的绘图区），不是整卡。
    final plot = find.byKey(const Key('daily_gridlines'));
    Finder bubble() => find.byKey(const Key('bar_chart_bubble'));

    await _tapDailyBar(tester, firstDay);
    await tester.pumpAndSettle();
    var bubbleRect = tester.getRect(bubble());
    expect(bubbleRect.left, greaterThanOrEqualTo(tester.getRect(plot).left));
    expect(bubbleRect.right, lessThanOrEqualTo(tester.getRect(plot).right));

    await _tapDailyBar(tester, today);
    await tester.pumpAndSettle();
    bubbleRect = tester.getRect(bubble());
    expect(bubbleRect.left, greaterThanOrEqualTo(tester.getRect(plot).left));
    expect(bubbleRect.right, lessThanOrEqualTo(tester.getRect(plot).right));
  });

  testWidgets('柱状图与热力图共用选中日：任一图选日另一图同步', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 10);
    final yesterday = today.subtract(const Duration(days: 1));
    await _pump(
      tester,
      records: [_record(today, 300, 'a'), _record(yesterday, 120, 'b')],
    );
    await _openStats(tester);
    await _tapFilter(tester, 'filter_window_7');
    await tester.pumpAndSettle();

    // 热力图选今天 → 柱状图选中态同步（选中柱虚线）。
    await _tapHeatmapCell(tester, today);
    expect(
      find.byKey(Key('daily_bar_dashes_${_dayKey(today)}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('heatmap_bubble')), findsOneWidget);

    // 柱状图选昨天 → 热力图气泡同步跳到昨天。
    await _scrollToTop(tester);
    // 点按落在图区的透明选日手势层上（柱内点按与拖动同走这一层）。
    await _tapDailyBar(tester, yesterday);
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('daily_bar_dashes_${_dayKey(yesterday)}')),
      findsOneWidget,
    );
    final bubbleText = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('heatmap_bubble')),
            matching: find.byType(Text),
          ),
        )
        .data!;
    expect(bubbleText, startsWith('${yesterday.month}月${yesterday.day}日'));
  });
}

/// 排行行尾进度条。
Finder _rankingBarFinder(String videoId) => find.descendant(
  of: find.byKey(Key('ranking_row_$videoId')),
  matching: find.byType(LinearProgressIndicator),
);

LinearProgressIndicator _rankingBar(WidgetTester tester, String videoId) =>
    tester.widget<LinearProgressIndicator>(_rankingBarFinder(videoId));

/// 仪表盘某卡面的大号数字文案（卡 key 下的首个 Text）。
void _expectDashboardValue(WidgetTester tester, String key, String text) {
  expect(
    find.descendant(of: find.byKey(Key(key)), matching: find.text(text)),
    findsOneWidget,
    reason: '$key 应显示 $text',
  );
}

/// 本地日键（柱族 `daily_bar_` 与热力图格 `heatmap_cell_` 共用 `<yyyy-MM-dd>`）。
String _dayKey(DateTime day) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${day.year}-${two(day.month)}-${two(day.day)}';
}

Finder _heatmapCells() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('heatmap_cell_');
});

Finder _heatmapWeeks() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('heatmap_week_');
});

/// 日格填充色（经格 key 下的装饰盒取色，不假设格的具体 widget 类型）；
/// 未来日无填充，返回 null。
Color? _cellColorOrNull(WidgetTester tester, DateTime day) {
  final decorated = find.descendant(
    of: find.byKey(Key('heatmap_cell_${_dayKey(day)}')),
    matching: find.byType(DecoratedBox),
  );
  if (decorated.evaluate().isEmpty) return null;
  return (tester.widget<DecoratedBox>(decorated).decoration as BoxDecoration)
      .color;
}

Color _cellColor(WidgetTester tester, DateTime day) =>
    _cellColorOrNull(tester, day)!;

/// 滚到当天明细卡：卡片在柱状图下方，页面级 ListView 懒建。
Future<void> _scrollToDayDetail(WidgetTester tester) async {
  final card = find.byKey(const Key('day_detail'));
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      400,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
}

/// 滚回页顶：明细卡断言之后，筛选行与柱状图重新可点。
Future<void> _scrollToTop(WidgetTester tester) async {
  final top = find.byKey(const Key('dashboard_card'));
  if (top.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      top,
      -400,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.pumpAndSettle();
}

/// 点筛选行控件：compact 档视口更矮，筛选行可能已滚出视口甚至出懒建
/// 缓存（可达 = 滚动可及），先滚回再点。
Future<void> _tapFilter(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  await ensureScrollVisible(tester, target);
  await tester.tap(target);
}

/// 点选某日柱：compact 档视口更矮，柱状图常需滚动才进视口（可达 = 滚动
/// 可及），先 ensureVisible 再点。
Future<void> _tapDailyBar(WidgetTester tester, DateTime day) async {
  final bar = find.byKey(Key('daily_bar_${_dayKey(day)}'));
  await ensureScrollVisible(tester, bar);
  await tester.tap(bar);
}

Future<void> _tapHeatmapCell(WidgetTester tester, DateTime day) async {
  final cell = find.byKey(Key('heatmap_cell_${_dayKey(day)}'));
  await tester.ensureVisible(cell);
  await tester.pumpAndSettle();
  // 日格视觉件被 48 命中层盖住：点落点而不是点视觉件（命中按最近格换算）。
  await tester.tapAt(tester.getCenter(cell));
  await tester.pumpAndSettle();
}

PracticeSessionRecord _record(
  DateTime start,
  double seconds,
  String videoId, {
  String song = 'My Love',
}) => PracticeSessionRecord(
  start: start,
  videoId: videoId,
  signature: SongSignature(song: song),
  wallSeconds: seconds,
);

/// 柱族键（与页面口径一致：`daily_bar_<yyyy-MM-dd>` / 填充 `daily_bar_fill_`）。
Finder _barFills() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('daily_bar_fill_');
});

double _fillHeight(WidgetTester tester, DateTime day) =>
    tester.getSize(find.byKey(Key('daily_bar_fill_${_dayKey(day)}'))).height;

/// 明细行尾进度条的当前填充比例。
double _dayDetailBarValue(WidgetTester tester, String videoId) => tester
    .widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(Key('day_detail_bar_$videoId')),
        matching: find.byType(LinearProgressIndicator),
      ),
    )
    .value!;

Future<void> _openStats(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tab_stats')));
  await tester.pumpAndSettle();
}

Future<PracticeStatsStore> _pump(
  WidgetTester tester, {
  List<PracticeSessionRecord> records = const [],
  VideoIndex index = VideoIndex.empty,
  Map<String, InMemoryVideoDocumentStorage> documents = const {},
}) async {
  final statsStorage = InMemoryPracticeStatsStorage();
  if (records.isNotEmpty) {
    statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
  }
  final store = PracticeStatsStore(statsStorage);
  useNamedViewport(tester, ViewportTier.compact);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practicePlanStorageProvider.overrideWithValue(
          InMemoryPracticePlanStorage(),
        ),
        practiceStatsStoreProvider.overrideWithValue(store),
        videoIndexStoreProvider.overrideWithValue(
          InMemoryVideoIndexStorage(initial: index),
        ),
        videoDocumentStorageFactoryProvider.overrideWithValue(
          (videoId) => documents[videoId] ?? InMemoryVideoDocumentStorage(),
        ),
        coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
      ],
      child: const DanceLearningApp(),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// 柱顶数值（`daily_bar_value_<yyyy-MM-dd>`）。
Finder _barValues() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('daily_bar_value_');
});

/// 选中柱的竖向虚线（`daily_bar_dashes_<yyyy-MM-dd>`）。
Finder _barDashes() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('daily_bar_dashes_');
});

/// x 轴日期标签（`daily_x_label_<yyyy-MM-dd>`）。
Finder _xLabels() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('daily_x_label_');
});

/// 排行行的现行单位值（tile 尾部的主数值）。
String? _rankingKeyValue(WidgetTester tester, String videoId) =>
    tester.widget<Text>(find.byKey(Key('ranking_row_key_$videoId'))).data;

bool _chipSelected(WidgetTester tester, String key) =>
    tester.widget<ChoiceChip>(find.byKey(Key(key))).selected;

Finder _rankingRows() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('ranking_row_') &&
      !key.value.startsWith('ranking_row_key_');
});

/// 断言给定 videoId 序列自上而下排列（只保序，不管是否有额外行）。
void _expectRankingOrder(WidgetTester tester, List<String> videoIds) {
  final tops = [
    for (final videoId in videoIds)
      tester.getTopLeft(find.byKey(Key('ranking_row_$videoId'))).dy,
  ];
  for (var i = 1; i < tops.length; i++) {
    expect(tops[i], greaterThan(tops[i - 1]), reason: '第 $i 行应在上一行之下');
  }
}

/// 滚到排行卡：卡片在页面底部，页面级 ListView 懒建。
Future<void> _scrollToRanking(WidgetTester tester) async {
  final card = find.byKey(const Key('ranking_card'));
  if (card.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      card,
      400,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(card);
  await tester.pumpAndSettle();
}

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

/// 该舞的标记文件（有效区间决定平均练习遍数的分母）。
InMemoryVideoDocumentStorage _documents({
  required int rangeStartMs,
  required int rangeEndMs,
}) => InMemoryVideoDocumentStorage(
  markers: MarkersDocument(
    rangeStartMs: rangeStartMs,
    rangeEndMs: rangeEndMs,
  ).toJson(),
  local: const LocalDocument.empty().toJson(),
);
