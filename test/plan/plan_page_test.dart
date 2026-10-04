import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/home/dance_detail_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/persistence/practice_plan_providers.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/plan/plan_mark_kind.dart';
import 'package:dance_learning_app/plan/plan_marker_palette.dart';
import 'package:dance_learning_app/plan/plan_page.dart';
import 'package:dance_learning_app/plan/plan_page_layout.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/scroll_reveal.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_plan_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/plan_wheel_driver.dart';
import '../helpers/semantics_assertions.dart';

/// 包装内存实现，统计装载次数（「首次进入才装载」的断言口径）。
class _CountingPlanStorage implements PracticePlanStorage {
  _CountingPlanStorage(this._inner);

  final InMemoryPracticePlanStorage _inner;
  int loadCount = 0;

  @override
  Future<Map<String, dynamic>?> loadOrNull() async {
    loadCount++;
    return _inner.loadOrNull();
  }

  @override
  Future<void> save(Map<String, dynamic> json) => _inner.save(json);
}

int _selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

String _dayKey(DateTime day) => planDayKey(day);

/// 本月 15 号：恒在本月，月视图与时间轴当前段都能容纳。
DateTime get _ddlDay {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 15);
}

PracticeSessionRecord _record(DateTime start, double seconds, String videoId) =>
    PracticeSessionRecord(
      start: start,
      videoId: videoId,
      signature: SongSignature(song: 'Alpha'),
      wallSeconds: seconds,
    );

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);

Future<_CountingPlanStorage> _pump(
  WidgetTester tester, {
  List<PracticeSessionRecord> records = const [],
  VideoIndex index = VideoIndex.empty,
  Map<String, dynamic>? planJson,
  Map<String, InMemoryVideoDocumentStorage> documents = const {},
}) async {
  final planStorage = InMemoryPracticePlanStorage();
  if (planJson != null) planStorage.rawJson = planJson;
  final counting = _CountingPlanStorage(planStorage);
  final statsStorage = InMemoryPracticeStatsStorage();
  if (records.isNotEmpty) {
    statsStorage.rawJson = PracticeStatsDocument(sessions: records).toJson();
  }
  useNamedViewport(tester, ViewportTier.compact);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        practicePlanStorageProvider.overrideWithValue(counting),
        practiceStatsStoreProvider.overrideWithValue(
          PracticeStatsStore(statsStorage),
        ),
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
  return counting;
}

/// 点下栏行（随舞 / 团检）：compact 档视口更矮，先滚回视野再点。
Future<void> _tapPanelRow(WidgetTester tester, Finder row) async {
  await ensureScrollVisible(tester, row);
  await tester.tap(row);
}

/// 点页面控件：compact 档视口更矮，先滚回视野再点。
Future<void> _tapKey(WidgetTester tester, Key key) async {
  await ensureScrollVisible(tester, find.byKey(key));
  await tester.tap(find.byKey(key));
}

Future<void> _openPlan(WidgetTester tester) async {
  await _tapKey(tester, const Key('tab_plan'));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _planJson(DateTime day, String videoId) =>
    PracticePlanDocument(
      entries: [
        DancePlanEntry(
          videoId: videoId,
          ddl: DanceDdl(date: day, occasion: '演出'),
        ),
      ],
    ).toJson();

/// 从页面上取回注入的 store（断言存储内容用）。
PracticePlanStore _storeOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PlanPage)))
        .read(practicePlanStoreProvider);

Finder _panelEventRow(String id) => find.byKey(Key('plan_panel_event_$id'));

void main() {
  testWidgets('底部三 Tab 可达：默认首页，点计划进计划页', (tester) async {
    final storage = await _pump(tester);

    expect(_selectedTab(tester), 0);
    expect(find.byType(PlanPage), findsNothing);

    await _openPlan(tester);

    expect(_selectedTab(tester), 2);
    expect(find.byType(PlanPage), findsOneWidget);
    expect(storage.loadCount, 1);

    // 切走再回来：同一容器内存储只装载一次。
    await _tapKey(tester, const Key('tab_home'));
    await tester.pumpAndSettle();
    await _openPlan(tester);
    expect(storage.loadCount, 1);
  });

  testWidgets('无任何计划：页内提示条 + 时间轴与月视图常显，下栏与日程三组不出', (tester) async {
    await _pump(tester);
    await _openPlan(tester);

    expect(find.byKey(const Key('plan_empty')), findsNothing);
    expect(find.byKey(const Key('plan_empty_hint')), findsOneWidget);
    expect(find.byKey(const Key('plan_timeline')), findsOneWidget);
    expect(find.byKey(const Key('plan_month_grid')), findsOneWidget);
    expect(find.byKey(const Key('plan_day_panel')), findsNothing);
    // 无计划：三组日程都不出现。
    expect(find.byKey(const Key('plan_agenda_due_header')), findsNothing);
    expect(find.byKey(const Key('plan_agenda_review_header')), findsNothing);
    expect(find.byKey(const Key('plan_agenda_social_header')), findsNothing);
  });

  testWidgets('有计划：时间轴条 → 月视图 → 下栏次序，有计划日与当前时间有标记', (tester) async {
    final now = localToday();
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      planJson: _planJson(_ddlDay, 'v1'),
    );
    await _openPlan(tester);

    expect(find.byKey(const Key('plan_empty')), findsNothing);
    expect(find.byKey(const Key('plan_timeline')), findsOneWidget);
    expect(find.byKey(const Key('plan_timeline_now')), findsOneWidget);
    expect(
      find.byKey(Key('plan_timeline_marker_${_dayKey(_ddlDay)}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('plan_month_grid')), findsOneWidget);
    expect(
      find.byKey(Key('plan_day_dot_ddl_${_dayKey(_ddlDay)}')),
      findsOneWidget,
    );
    // 无计划的日子没有标记。
    final plain = now.add(const Duration(days: 1));
    expect(find.byKey(Key('plan_day_dot_ddl_${_dayKey(plain)}')), findsNothing);

    // 区块次序：时间轴条在月视图上方，月视图在点日下栏（未选中不出）之外。
    expect(
      tester.getTopLeft(find.byKey(const Key('plan_timeline'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('plan_month_grid'))).dy),
    );
  });

  group('时间轴一年窗口与图例', () {
    Future<void> pumpPlan(WidgetTester tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: _planJson(_ddlDay, 'v1'),
      );
      await _openPlan(tester);
    }

    /// 某日在时间轴上的横向位置：月列左缘 + 列内比例 × 列宽。
    double dayXOf(WidgetTester tester, DateTime day) {
      final column = find.byKey(
        Key('plan_timeline_segment_${planMonthKey(day)}'),
      );
      final daysInMonth = DateTime(day.year, day.month + 1, 0).day;
      return tester.getTopLeft(column).dx +
          (day.day - 1) / daysInMonth * tester.getSize(column).width;
    }

    testWidgets('12 列等宽铺满卡宽、无横向滚动', (tester) async {
      await pumpPlan(tester);

      final timeline = find.byKey(const Key('plan_timeline'));
      expect(
        find.descendant(of: timeline, matching: find.byType(Scrollable)),
        findsNothing,
      );
      final columns = [
        for (var offset = 0; offset < 12; offset++)
          find.byKey(
            Key(
              'plan_timeline_segment_'
              '${planMonthKey(planShiftMonth(localToday(), offset))}',
            ),
          ),
      ];
      for (final column in columns) {
        expect(column, findsOneWidget);
      }
      final widths = [
        for (final column in columns) tester.getSize(column).width,
      ];
      for (final width in widths) {
        expect(width, closeTo(widths.first, 0.5));
      }
      // 铺满卡宽：12 列总宽 = 卡内一行图例的宽度。
      final contentWidth = tester
          .getSize(find.byKey(const Key('plan_timeline_legend')))
          .width;
      expect(
        widths.fold<double>(0, (sum, width) => sum + width),
        closeTo(contentWidth, 1),
      );
    });

    testWidgets('「今天」竖线落在当月列内今天的比例位置', (tester) async {
      await pumpPlan(tester);

      expect(
        tester.getTopLeft(find.byKey(const Key('plan_timeline_now'))).dx,
        closeTo(dayXOf(tester, localToday()), 0.5),
      );
    });

    testWidgets('灰虚线分月、列下月号与跨年年份、图例三类恒显', (tester) async {
      await pumpPlan(tester);

      expect(find.byKey(const Key('plan_timeline_legend')), findsOneWidget);
      for (final slug in ['ddl', 'social', 'teamcheck']) {
        expect(find.byKey(Key('plan_timeline_legend_$slug')), findsOneWidget);
      }
      // 12 列各有一个月号。
      for (var offset = 0; offset < 12; offset++) {
        final month = planShiftMonth(localToday(), offset);
        expect(
          find.byKey(Key('plan_timeline_month_label_${planMonthKey(month)}')),
          findsOneWidget,
        );
      }
      // 首列之前不画分隔；下月列左边界有一条灰虚线。
      expect(
        find.byKey(
          Key(
            'plan_timeline_divider_'
            '${_dayKey(DateTime(localToday().year, localToday().month, 1))}',
          ),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          Key(
            'plan_timeline_divider_'
            '${_dayKey(DateTime(localToday().year, localToday().month + 1, 1))}',
          ),
        ),
        findsOneWidget,
      );
      // 年份标注：首列与窗口内跨年的一月各一个。
      for (final year in {
        localToday().year,
        for (var offset = 1; offset < 12; offset++)
          if (planShiftMonth(localToday(), offset).month == 1)
            planShiftMonth(localToday(), offset).year,
      }) {
        expect(find.byKey(Key('plan_timeline_year_$year')), findsOneWidget);
      }
    });

    testWidgets('年份分段行在轨道上方：段宽 = 该年列数、年份贴段左缘', (tester) async {
      await pumpPlan(tester);

      final today = localToday();
      final nowLine = find.byKey(const Key('plan_timeline_now'));
      final columnWidth = tester
          .getSize(
            find.byKey(Key('plan_timeline_segment_${planMonthKey(today)}')),
          )
          .width;
      // 该年在窗口内的列数。
      final columnCounts = <int, int>{};
      for (var offset = 0; offset < 12; offset++) {
        final year = planShiftMonth(today, offset).year;
        columnCounts[year] = (columnCounts[year] ?? 0) + 1;
      }
      // 该年在窗口内的首列（年份段左缘与之对齐）。
      DateTime firstMonthOfYear(int year) {
        for (var offset = 0; offset < 12; offset++) {
          final month = planShiftMonth(today, offset);
          if (month.year == year) return month;
        }
        throw StateError('窗口内没有 $year');
      }

      for (final entry in columnCounts.entries) {
        final span = find.byKey(Key('plan_timeline_year_${entry.key}'));
        expect(span, findsOneWidget);
        // 年份段整体在轨道上方。
        expect(
          tester.getBottomLeft(span).dy,
          lessThanOrEqualTo(tester.getTopLeft(nowLine).dy),
        );
        // 段宽 = 该年列数 ÷ 12 卡宽。
        expect(
          tester.getSize(span).width,
          closeTo(columnWidth * entry.value, 0.5),
        );
        // 段左缘与该年首列左缘对齐。
        expect(
          tester.getTopLeft(span).dx,
          closeTo(
            tester
                .getTopLeft(
                  find.byKey(
                    Key(
                      'plan_timeline_segment_'
                      '${planMonthKey(firstMonthOfYear(entry.key))}',
                    ),
                  ),
                )
                .dx,
            0.5,
          ),
        );
        // 年份文字贴段左缘、段首留 4dp。
        final label = find.descendant(
          of: span,
          matching: find.text('${entry.key}'),
        );
        expect(label, findsOneWidget);
        expect(
          tester.getTopLeft(label).dx - tester.getTopLeft(span).dx,
          closeTo(4, 0.5),
        );
      }
    });

    testWidgets('轨道下方只剩月号行，卡底间距 4dp', (tester) async {
      await pumpPlan(tester);

      final column = find.byKey(
        Key('plan_timeline_segment_${planMonthKey(localToday())}'),
      );
      // 列内只有月号一枚文字。
      expect(
        find.descendant(of: column, matching: find.byType(Text)),
        findsOneWidget,
      );
      final monthLabel = find.byKey(
        Key('plan_timeline_month_label_${planMonthKey(localToday())}'),
      );
      expect(
        tester.getBottomLeft(monthLabel).dy,
        closeTo(tester.getBottomLeft(column).dy, 0.5),
      );
      // 月号行与图例之间 4dp 卡底间距。
      expect(
        tester.getTopLeft(find.byKey(const Key('plan_timeline_legend'))).dy -
            tester.getBottomLeft(column).dy,
        closeTo(4, 0.5),
      );
    });

    testWidgets('底带只包轨道与月号两行，不含年份行', (tester) async {
      await pumpPlan(tester);

      final yearSpan = find.byKey(
        Key('plan_timeline_year_${localToday().year}'),
      );
      final band = find.byKey(const Key('plan_timeline_selected_month'));
      expect(band, findsOneWidget);
      expect(find.descendant(of: band, matching: yearSpan), findsNothing);
      // 年份行整体在底带上方。
      expect(
        tester.getBottomLeft(yearSpan).dy,
        lessThanOrEqualTo(tester.getTopLeft(band).dy),
      );
      // 底带底即月号底：带内只有轨道与月号两行。
      expect(
        tester.getBottomLeft(band).dy,
        closeTo(
          tester
              .getBottomLeft(
                find.byKey(
                  Key(
                    'plan_timeline_month_label_${planMonthKey(localToday())}',
                  ),
                ),
              )
              .dy,
          0.5,
        ),
      );
    });

    testWidgets('空月月号淡显，有计划的月月号不淡', (tester) async {
      await pumpPlan(tester);

      Color labelColor(DateTime month) => tester
          .widget<Text>(
            find.byKey(Key('plan_timeline_month_label_${planMonthKey(month)}')),
          )
          .style!
          .color!;

      // 当前月有 DDL（15 号），下月为空。
      expect(labelColor(localToday()).a, greaterThan(0.9));
      expect(
        labelColor(planShiftMonth(localToday(), 1)).a,
        lessThan(labelColor(localToday()).a),
      );
    });

    testWidgets('同日多类型竖线以当天位置为中心并排、各自一色', (tester) async {
      final day = _ddlDay;
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: day),
            ),
          ],
          events: [
            PlanEvent(id: 'ev-social', date: day, danceIds: const ['v1']),
            PlanEvent(
              id: 'ev-team',
              date: day,
              type: kPlanEventTypeTeamCheck,
              danceIds: const ['v1'],
            ),
          ],
        ).toJson(),
      );
      await _openPlan(tester);

      final key = _dayKey(day);
      final ddl = find.byKey(Key('plan_timeline_marker_$key'));
      final social = find.byKey(Key('plan_timeline_marker_social_$key'));
      final teamCheck = find.byKey(Key('plan_timeline_marker_teamcheck_$key'));
      expect(ddl, findsOneWidget);
      expect(social, findsOneWidget);
      expect(teamCheck, findsOneWidget);
      // 2px 竖线、各自取类型配色。
      expect(tester.getSize(ddl).width, 2);
      expect(tester.getSize(social).width, 2);
      expect(tester.getSize(teamCheck).width, 2);
      expect(
        tester.widget<Container>(ddl).color,
        planMarkColor(PlanMarkKind.ddl),
      );
      expect(
        tester.widget<Container>(social).color,
        planMarkColor(PlanMarkKind.social),
      );
      expect(
        tester.widget<Container>(teamCheck).color,
        planMarkColor(PlanMarkKind.teamCheck),
      );
      // 以当天位置为中心并排：最左与最右两条的中点即当天位置。
      final centers = [
        tester.getCenter(ddl).dx,
        tester.getCenter(social).dx,
        tester.getCenter(teamCheck).dx,
      ];
      expect(centers[0], lessThan(centers[1]));
      expect(centers[1], lessThan(centers[2]));
      expect(
        (centers.first + centers.last) / 2,
        closeTo(dayXOf(tester, day), 0.5),
      );
    });
  });

  group('月视图翻月与时间轴联动', () {
    String monthTitle(DateTime month) => '${month.year}年${month.month}月';

    String titleOf(WidgetTester tester) =>
        tester.widget<Text>(find.byKey(const Key('plan_month_title'))).data!;

    /// 该月的跨月补位日（首尾各试；极少数月份无补位日时返回 null）。
    DateTime? crossMonthDay(DateTime month) {
      final grid = buildPlanMonthGrid(month);
      for (final week in grid.weeks) {
        for (final day in week) {
          if (!grid.isInMonth(day)) return day;
        }
      }
      return null;
    }

    Future<void> pumpPlan(WidgetTester tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: _planJson(_ddlDay, 'v1'),
      );
      await _openPlan(tester);
    }

    testWidgets('初始所示月 = 当前月，无「今天」按钮', (tester) async {
      await pumpPlan(tester);

      expect(titleOf(tester), monthTitle(localToday()));
      expect(find.byKey(const Key('plan_month_today')), findsNothing);
      // 日历所示月 = 当前月：网格首周含本月初所在的整周。
      final grid = buildPlanMonthGrid(localToday());
      expect(grid.weeks.first.first.weekday, DateTime.monday);
      expect(
        find.byKey(Key('plan_day_${planDayKey(localToday())}')),
        findsOneWidget,
      );
    });

    testWidgets('头部左右按钮逐月翻看，翻到当前月之前也不设边界', (tester) async {
      await pumpPlan(tester);

      await _tapKey(tester, const Key('plan_month_next'));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), 1)));

      await _tapKey(tester, const Key('plan_month_next'));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), 2)));

      await _tapKey(tester, const Key('plan_month_prev'));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), 1)));

      await _tapKey(tester, const Key('plan_month_prev'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_month_prev'));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), -1)));
    });

    testWidgets('切月清除选中日、下栏收起', (tester) async {
      await pumpPlan(tester);

      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_day_panel')), findsOneWidget);

      await _tapKey(tester, const Key('plan_month_next'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan_day_panel')), findsNothing);
      expect(
        find.byKey(Key('plan_day_selected_${_dayKey(_ddlDay)}')),
        findsNothing,
      );
    });

    testWidgets('所示月非当前月才出「今天」，点它回当前月并选中今天', (tester) async {
      await pumpPlan(tester);

      await _tapKey(tester, const Key('plan_month_next'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_month_today')), findsOneWidget);

      await _tapKey(tester, const Key('plan_month_today'));
      await tester.pumpAndSettle();

      expect(titleOf(tester), monthTitle(localToday()));
      expect(
        find.byKey(Key('plan_day_selected_${_dayKey(localToday())}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('plan_day_panel')), findsOneWidget);
      expect(find.byKey(const Key('plan_month_today')), findsNothing);
    });

    testWidgets('网格左右滑动翻月；一次手势只切一月', (tester) async {
      await pumpPlan(tester);
      final grid = find.byKey(const Key('plan_month_grid'));

      await tester.drag(grid, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), 1)));

      // 同一手势内位移再大也只切一月。
      await tester.drag(grid, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), 2)));

      await tester.drag(grid, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(planShiftMonth(localToday(), 1)));
    });

    testWidgets('点跨月补位日即切到它所在的月并选中它', (tester) async {
      await pumpPlan(tester);
      final filler = crossMonthDay(localToday());
      // 极少数月份（周一起、整四周）没有补位日，此时无此路径可验。
      if (filler == null) return;

      await _tapKey(tester, Key('plan_day_${_dayKey(filler)}'));
      await tester.pumpAndSettle();

      expect(titleOf(tester), monthTitle(filler));
      expect(
        find.byKey(Key('plan_day_selected_${_dayKey(filler)}')),
        findsOneWidget,
      );
    });

    testWidgets('点时间轴月列切月，所示月列带高亮带', (tester) async {
      await pumpPlan(tester);
      final targetMonth = planShiftMonth(localToday(), 2);
      final target = find.byKey(
        Key('plan_timeline_segment_${planMonthKey(targetMonth)}'),
      );

      // 初始高亮落在当前月列。
      expect(
        find.descendant(
          of: find.byKey(
            Key('plan_timeline_segment_${planMonthKey(localToday())}'),
          ),
          matching: find.byKey(const Key('plan_timeline_selected_month')),
        ),
        findsOneWidget,
      );

      await tester.tapAt(
        tester.getCenter(
          find.byKey(Key('plan_timeline_hit_${planMonthKey(targetMonth)}')),
        ),
      );
      await tester.pumpAndSettle();

      expect(titleOf(tester), monthTitle(targetMonth));
      // 高亮带随之移到所示月列、盖住整列，且全轴只有一条。
      final band = find.byKey(const Key('plan_timeline_selected_month'));
      expect(find.descendant(of: target, matching: band), findsOneWidget);
      expect(band, findsOneWidget);
      expect(tester.getTopLeft(band), tester.getTopLeft(target));
      expect(
        tester.getSize(band).height,
        closeTo(tester.getSize(target).height, 0.5),
      );
    });

    testWidgets('点已高亮的当月列不算切月：选中日与下栏保留', (tester) async {
      await pumpPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_day_panel')), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(
          find.byKey(Key('plan_timeline_hit_${planMonthKey(localToday())}')),
        ),
      );
      await tester.pumpAndSettle();

      expect(titleOf(tester), monthTitle(localToday()));
      expect(find.byKey(const Key('plan_day_panel')), findsOneWidget);
      expect(
        find.byKey(Key('plan_day_selected_${_dayKey(_ddlDay)}')),
        findsOneWidget,
      );
    });

    testWidgets('月列切月命中层 ≥48×48、带按钮语义，点按按最近列换算到目标月', (tester) async {
      await pumpPlan(tester);

      // 12 列各一枚 48×48 透明命中层；视觉列宽 ≈26（撑不到下限）。
      for (var offset = 0; offset < 12; offset++) {
        final month = planShiftMonth(localToday(), offset);
        final key = Key('plan_timeline_hit_${planMonthKey(month)}');
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expectButtonSemantics(
          tester,
          key,
          label: '切到${month.year}年${month.month}月',
        );
      }

      // 视觉列宽仍是约 26dp（命中盒是透明外扩、不是把列改宽）。
      final column = find.byKey(
        Key('plan_timeline_segment_${planMonthKey(localToday())}'),
      );
      expect(tester.getSize(column).width, lessThan(48));

      // 点第 3 列的命中层中心：目标月成为所示月。
      final targetMonth = planShiftMonth(localToday(), 2);
      final targetLayer = find.byKey(
        Key('plan_timeline_hit_${planMonthKey(targetMonth)}'),
      );
      // 中间列的层是自己命中的目标（不是只存在于布局里、被上层裁掉）。
      final targetBox = tester.renderObject<RenderBox>(targetLayer);
      final hit = tester.hitTestOnBinding(tester.getCenter(targetLayer));
      expect(
        hit.path.any((entry) => entry.target == targetBox),
        isTrue,
        reason: '目标月命中层中心必须命中该层自身',
      );
      await tester.tapAt(tester.getCenter(targetLayer));
      await tester.pumpAndSettle();
      expect(titleOf(tester), monthTitle(targetMonth));
    });
  });

  testWidgets('点某日选中它并出下栏：当日 DDL 舞与当日练习时长', (tester) async {
    final now = localToday();
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      records: [_record(DateTime(now.year, now.month, 15, 10), 3720, 'v1')],
      planJson: _planJson(_ddlDay, 'v1'),
    );
    await _openPlan(tester);

    expect(find.byKey(const Key('plan_day_panel')), findsNothing);
    await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plan_day_panel')), findsOneWidget);
    expect(
      find.byKey(Key('plan_day_selected_${_dayKey(_ddlDay)}')),
      findsOneWidget,
    );
    // 当日练习时长 = 3720s = 1:02:00，恒按时间口径。
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_panel_practice'))).data,
      '1:02:00',
    );
    // 下栏行 = 当天到期 DDL 的舞。
    expect(find.byKey(const Key('plan_panel_ddl_v1')), findsOneWidget);
    expect(find.textContaining('演出'), findsOneWidget);
  });

  testWidgets('下栏点舞行 push 该舞详情页', (tester) async {
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      planJson: _planJson(_ddlDay, 'v1'),
    );
    await _openPlan(tester);
    await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('plan_panel_ddl_v1'));
    await tester.pumpAndSettle();

    expect(find.byType(DanceDetailPage), findsOneWidget);
  });

  testWidgets('选中无计划日：下栏照出，给当日练习（无则零）与无 DDL 文案', (tester) async {
    final now = localToday();
    final plain = DateTime(now.year, now.month, 20);
    await _pump(
      tester,
      index: VideoIndex(entries: [_entry('v1')]),
      records: [_record(DateTime(now.year, now.month, 20, 9), 60, 'v1')],
      planJson: _planJson(_ddlDay, 'v1'),
    );
    await _openPlan(tester);
    await _tapKey(tester, Key('plan_day_${_dayKey(plain)}'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('plan_day_panel')), findsOneWidget);
    expect(find.byKey(Key('plan_panel_ddl_v1')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('plan_panel_practice'))).data,
      '1:00',
    );
  });

  group('随舞事件', () {
    testWidgets('新建随舞：默认带入随舞曲库开的舞、关的舞不勾；保存后下栏出事件行、日历出事件点', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
            // v2 关掉随舞曲库：不被新建事件默认带入。
            DancePlanEntry(videoId: 'v2', socialLibrary: false),
          ],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();

      await _tapKey(tester, const Key('plan_panel_add_event'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_event_dialog')), findsOneWidget);
      // 全屏表单页，不是弹框。
      expect(find.byType(AlertDialog), findsNothing);
      await scrollPlanEditorTo(tester, const Key('plan_event_dance_v2'));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('plan_event_dance_v1')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('plan_event_dance_v2')),
            )
            .value,
        isFalse,
      );

      // 滑选时间与地点、加一项准备清单后保存。
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_time'));
      await selectPlanTime(tester, 'plan_event_dialog_time', target: 19 * 60);
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_name'));
      await tester.enterText(
        find.byKey(const Key('plan_event_dialog_name')),
        '操场',
      );
      await scrollPlanEditorTo(tester, const Key('plan_event_checklist_input'));
      await tester.enterText(
        find.byKey(const Key('plan_event_checklist_input')),
        '带水',
      );
      await _tapKey(tester, const Key('plan_event_checklist_add'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();

      final events = await _storeOf(tester).events();
      expect(events.length, 1);
      final event = events.single;
      expect(event.startTime, '19:00');
      expect(event.location, '操场');
      expect(event.danceIds, ['v1']);
      expect(event.checklist.single.text, '带水');

      expect(_panelEventRow(event.id), findsOneWidget);
      expect(
        find.byKey(Key('plan_day_dot_social_${_dayKey(_ddlDay)}')),
        findsOneWidget,
      );
    });

    testWidgets('同日 DDL 与事件分别呈现：两枚圆点、下栏两类行并存', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay, occasion: '演出'),
            ),
          ],
          events: [
            PlanEvent(id: 'ev-1', date: _ddlDay, danceIds: const ['v1']),
          ],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('plan_day_dot_ddl_${_dayKey(_ddlDay)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('plan_day_dot_social_${_dayKey(_ddlDay)}')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('plan_panel_ddl_v1')), findsOneWidget);
      expect(_panelEventRow('ev-1'), findsOneWidget);
    });

    testWidgets('事件独有日：只出事件点，不出 DDL 点', (tester) async {
      final now = localToday();
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [
            PlanEvent(
              id: 'ev-1',
              date: DateTime(now.year, now.month, 20),
              danceIds: const ['v1'],
            ),
          ],
        ).toJson(),
      );
      await _openPlan(tester);

      final eventDay = DateTime(now.year, now.month, 20);
      expect(
        find.byKey(Key('plan_day_dot_social_${_dayKey(eventDay)}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('plan_day_dot_ddl_${_dayKey(eventDay)}')),
        findsNothing,
      );
      // DDL 日的 DDL 点不受影响。
      expect(
        find.byKey(Key('plan_day_dot_ddl_${_dayKey(_ddlDay)}')),
        findsOneWidget,
      );
    });

    testWidgets('无计划时点某日即从下栏新建第一场随舞，不必先设 DDL', (tester) async {
      await _pump(tester, index: VideoIndex(entries: [_entry('v1')]));
      await _openPlan(tester);

      expect(find.byKey(const Key('plan_empty_hint')), findsOneWidget);
      expect(find.byKey(const Key('plan_day_panel')), findsNothing);
      await _tapKey(tester, Key('plan_day_${_dayKey(localToday())}'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_panel_add_event'));
      await tester.pumpAndSettle();
      await scrollPlanEditorTo(tester, const Key('plan_event_dance_v1'));
      // 曲库开的舞默认带入（v1 无开关条目 = 开）。
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const Key('plan_event_dance_v1')),
            )
            .value,
        isTrue,
      );
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();

      final events = await _storeOf(tester).events();
      expect(events.length, 1);
      expect(events.single.danceIds, ['v1']);
      expect(find.byKey(const Key('plan_empty_hint')), findsNothing);
      expect(find.byKey(const Key('plan_month_grid')), findsOneWidget);
      // 下栏仍指今天，事件行照出。
      expect(_panelEventRow(events.single.id), findsOneWidget);
    });

    testWidgets('点事件行进编辑：预填当前值，改备注保存读回', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [
            PlanEvent(
              id: 'ev-1',
              date: _ddlDay,
              remark: '旧备注',
              danceIds: const ['v1'],
            ),
          ],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      await _tapPanelRow(tester, _panelEventRow('ev-1'));
      await tester.pumpAndSettle();
      // compact 档视口更矮：备注框先滚入视口（惰性构建）再读。
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_remark'));

      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('plan_event_dialog_remark')),
            )
            .controller!
            .text,
        '旧备注',
      );
      await tester.enterText(
        find.byKey(const Key('plan_event_dialog_remark')),
        '新备注',
      );
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();

      final event = (await _storeOf(tester).events()).single;
      expect(event.id, 'ev-1');
      expect(event.remark, '新备注');
    });

    testWidgets('点事件行进编辑：改开始时间与提前 N 天滚轮保存读回，滑回空档写 null', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [
            PlanEvent(
              id: 'ev-1',
              date: _ddlDay,
              startTime: '19:00',
              leadDays: 2,
              danceIds: const ['v1'],
            ),
          ],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      await _tapPanelRow(tester, _panelEventRow('ev-1'));
      await tester.pumpAndSettle();

      // 不动滚轮直接保存：时间与提前量保持既有值（先滚到该值）。
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();
      var event = (await _storeOf(tester).events()).single;
      expect(event.startTime, '19:00');
      expect(event.leadDays, 2);

      // 改时间与提前量。
      await _tapPanelRow(tester, _panelEventRow('ev-1'));
      await tester.pumpAndSettle();
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_time'));
      await selectPlanTime(
        tester,
        'plan_event_dialog_time',
        target: 20 * 60 + 30,
      );
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_lead'));
      await selectPlanLead(
        tester,
        const Key('plan_event_dialog_lead_wheel'),
        target: 5,
      );
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();
      event = (await _storeOf(tester).events()).single;
      expect(event.startTime, '20:30');
      expect(event.leadDays, 5);

      // 滑回空档：时间「不设」与提前「不提醒」都写回 null。
      await _tapPanelRow(tester, _panelEventRow('ev-1'));
      await tester.pumpAndSettle();
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_time'));
      await selectPlanTime(tester, 'plan_event_dialog_time', target: null);
      await scrollPlanEditorTo(tester, const Key('plan_event_dialog_lead'));
      await selectPlanLead(
        tester,
        const Key('plan_event_dialog_lead_wheel'),
        target: null,
      );
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();
      event = (await _storeOf(tester).events()).single;
      expect(event.startTime, isNull);
      expect(event.leadDays, isNull);
    });

    testWidgets('删除事件：下栏行与日历事件点消失、存储里事件连同准备清单消失，DDL 仍在', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [
            PlanEvent(
              id: 'ev-1',
              date: _ddlDay,
              checklist: const [PlanChecklistItem(text: '带水')],
            ),
          ],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      await _tapPanelRow(tester, _panelEventRow('ev-1'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_event_delete'));
      await tester.pumpAndSettle();
      // 先确认：取消 = 什么都不发生（编辑页仍在，存储未删）。
      expect(find.byKey(const Key('plan_event_delete_dialog')), findsOneWidget);
      await _tapKey(tester, const Key('plan_event_delete_cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_event_delete_dialog')), findsNothing);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(_panelEventRow('ev-1'), findsOneWidget);
      expect((await _storeOf(tester).events()).single.id, 'ev-1');

      // 确认后才删除落盘。
      await _tapPanelRow(tester, _panelEventRow('ev-1'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_event_delete'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_event_delete_confirm'));
      await tester.pumpAndSettle();

      expect(_panelEventRow('ev-1'), findsNothing);
      expect(
        find.byKey(Key('plan_day_dot_social_${_dayKey(_ddlDay)}')),
        findsNothing,
      );
      expect(await _storeOf(tester).events(), isEmpty);
      // DDL 不受影响，下栏仍列 DDL。
      expect(find.byKey(const Key('plan_panel_ddl_v1')), findsOneWidget);
    });

    testWidgets('无事件日下栏只列 DDL；新建随舞开始时间默认「不设」', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan_panel_ddl_v1')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is Key &&
              (w.key as Key).toString().contains('plan_panel_event_'),
        ),
        findsNothing,
      );

      // 滚轮只产出合法档位：不碰时间列直接保存 = 无开始时间。
      await _tapKey(tester, const Key('plan_panel_add_event'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_event_dialog_save'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_event_dialog')), findsNothing);
      final events = await _storeOf(tester).events();
      expect(events.single.startTime, isNull);
    });
  });

  group('团内检查与达标门', () {
    // 三条分段线派生的学习段，全部段同档：档位集由 [mastery] 决定。
    InMemoryVideoDocumentStorage docWithMasteries(
      List<LearningMastery> masteries,
    ) => InMemoryVideoDocumentStorage(
      markers: MarkersDocument(
        rangeStartMs: 0,
        rangeEndMs: 100000,
        segmentLines: [
          for (var i = 0; i < 3; i++)
            SegmentLine(position: Duration(milliseconds: i * 10000)),
        ],
      ).toJson(),
      local: LocalDocument(
        mastery: {
          // 3 条分段线把区间切成 4 段，全部段同档。
          for (var i = 0; i < 4; i++) i: masteries[i % masteries.length],
        },
      ).toJson(),
    );

    Finder teamCheckRow(String id) =>
        find.byKey(Key('plan_panel_teamcheck_$id'));

    String teamCheckMode(WidgetTester tester) => tester
        .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
        .groupValue!;

    testWidgets('下栏可新建团检：默认门较熟、方式到场排练、无提交控件', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: _planJson(_ddlDay, 'v1'),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();

      await _tapKey(tester, const Key('plan_panel_add_teamcheck'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_teamcheck_dialog')), findsOneWidget);
      // 全屏表单页，不是弹框。
      expect(find.byType(AlertDialog), findsNothing);
      // 到场排练方式：提交控件不出现。
      expect(find.byKey(const Key('plan_teamcheck_submitted')), findsNothing);
      expect(
        find.byKey(const Key('plan_teamcheck_submitted_on')),
        findsNothing,
      );
      // 勾上关联舞后出门选择器，默认较熟。
      await _tapKey(tester, const Key('plan_event_dance_v1'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byKey(const Key('plan_teamcheck_gate_v1')),
            )
            .value,
        'familiar',
      );
      // 方式默认到场排练。
      expect(teamCheckMode(tester), 'rehearsal');
      await _tapKey(tester, const Key('plan_teamcheck_dialog_save'));
      await tester.pumpAndSettle();

      final events = await _storeOf(tester).events();
      expect(events.single.type, kPlanEventTypeTeamCheck);
      expect(events.single.checkMode, 'rehearsal');
      expect(events.single.danceGates, {'v1': 'familiar'});
      expect(events.single.submittedOn, isNull);
      expect(teamCheckRow(events.single.id), findsOneWidget);
    });

    testWidgets('检查方式切到录视频提交出提交控件；勾已提交带日期并落盘', (tester) async {
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: _planJson(_ddlDay, 'v1'),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('plan_panel_add_teamcheck'));
      await tester.pumpAndSettle();

      await scrollPlanEditorTo(tester, const Key('plan_teamcheck_mode_video'));
      await _tapKey(tester, const Key('plan_teamcheck_mode_video'));
      await tester.pumpAndSettle();
      // 录视频提交：提交控件出现。
      expect(find.byKey(const Key('plan_teamcheck_submitted')), findsOneWidget);
      // 勾「已提交」并滑选提交日期。
      await scrollPlanEditorTo(tester, const Key('plan_teamcheck_submitted'));
      await _tapKey(tester, const Key('plan_teamcheck_submitted'));
      await tester.pumpAndSettle();
      await scrollPlanEditorTo(
        tester,
        const Key('plan_teamcheck_submitted_on'),
      );
      await selectPlanSubmittedDate(
        tester,
        'plan_teamcheck_submitted_on',
        target: DateTime(2026, 1, 2),
        fallback: _ddlDay,
        today: localToday(),
      );
      await _tapKey(tester, const Key('plan_teamcheck_dialog_save'));
      await tester.pumpAndSettle();

      final event = (await _storeOf(tester).events()).single;
      expect(event.checkMode, 'videoSubmission');
      expect(event.submittedOn, DateTime(2026, 1, 2));

      // 再编辑：方式切回到场排练 → 提交控件隐藏。
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      await tester.tap(teamCheckRow(event.id));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_teamcheck_submitted')), findsOneWidget);
      await scrollPlanEditorTo(
        tester,
        const Key('plan_teamcheck_mode_rehearsal'),
      );
      await _tapKey(tester, const Key('plan_teamcheck_mode_rehearsal'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_teamcheck_submitted')), findsNothing);
      await _tapKey(tester, const Key('plan_teamcheck_dialog_save'));
      await tester.pumpAndSettle();
      final reopened = (await _storeOf(tester).events()).single;
      expect(reopened.checkMode, 'rehearsal');
      expect(reopened.submittedOn, isNull);
    });

    testWidgets('团检提交日期滑回「不填」：编辑页打开即预填，年列回空档写 null', (tester) async {
      final event = PlanEvent(
        id: 'tc-1',
        type: kPlanEventTypeTeamCheck,
        date: _ddlDay,
        checkMode: kTeamCheckModeVideoSubmission,
        submittedOn: DateTime(2026, 1, 2),
        danceIds: const ['v1'],
      );
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [event],
        ).toJson(),
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      await _tapPanelRow(tester, teamCheckRow('tc-1'));
      await tester.pumpAndSettle();
      // 不动滚轮直接保存：提交日期保持既有值（先滚到该值）。
      await _tapKey(tester, const Key('plan_teamcheck_dialog_save'));
      await tester.pumpAndSettle();
      expect(
        (await _storeOf(tester).events()).single.submittedOn,
        DateTime(2026, 1, 2),
      );

      // 再进编辑页：年列滑回「不填」即写回 null。
      await _tapPanelRow(tester, teamCheckRow('tc-1'));
      await tester.pumpAndSettle();
      await scrollPlanEditorTo(
        tester,
        const Key('plan_teamcheck_submitted_on'),
      );
      await clearPlanSubmittedDate(tester, 'plan_teamcheck_submitted_on');
      await _tapKey(tester, const Key('plan_teamcheck_dialog_save'));
      await tester.pumpAndSettle();

      expect((await _storeOf(tester).events()).single.submittedOn, isNull);
    });

    testWidgets('舞级达标显示：达标 / 未达标 / 不参与判定（不设与零段）', (tester) async {
      final event = PlanEvent(
        id: 'tc-1',
        type: kPlanEventTypeTeamCheck,
        date: _ddlDay,
        danceIds: const ['v1', 'v2', 'v3', 'v4'],
        danceGates: const {
          'v1': 'familiar',
          'v2': 'familiar',
          'v3': 'unset',
          'v4': 'familiar',
        },
      );
      await _pump(
        tester,
        index: VideoIndex(
          entries: [_entry('v1'), _entry('v2'), _entry('v3'), _entry('v4')],
        ),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [event],
        ).toJson(),
        documents: {
          // 全段较熟 → 达标。
          'v1': docWithMasteries([
            LearningMastery.familiar,
            LearningMastery.familiar,
          ]),
          // 有段只到能跟上 → 未达标。
          'v2': docWithMasteries([
            LearningMastery.mastered,
            LearningMastery.keepingUp,
          ]),
          // 门不设 → 不参与判定（即使全掌握）。
          'v3': docWithMasteries([
            LearningMastery.mastered,
            LearningMastery.mastered,
          ]),
          // 零段（无标记文件）→ 不参与判定。
          'v4': InMemoryVideoDocumentStorage(),
        },
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();

      String danceStatus(String videoId) => tester
          .widget<Text>(
            find.byKey(Key('plan_panel_teamcheck_tc-1_dance_$videoId')),
          )
          .data!;
      expect(danceStatus('v1'), '达标');
      expect(danceStatus('v2'), '未达标');
      expect(danceStatus('v3'), '不参与判定');
      expect(danceStatus('v4'), '不参与判定');
      // 事件级：有一段未达标 → 事件未达标。
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('plan_panel_teamcheck_tc-1_status')),
            )
            .data!,
        '未达标',
      );
    });

    testWidgets('事件级达标：参与判定的舞全部达标 → 事件达标；提交标记只对录视频提交出现', (tester) async {
      final videoSubmitted = PlanEvent(
        id: 'tc-1',
        type: kPlanEventTypeTeamCheck,
        date: _ddlDay,
        danceIds: const ['v1'],
        danceGates: const {'v1': 'mastered'},
        checkMode: kTeamCheckModeVideoSubmission,
        submittedOn: DateTime(2026, 1, 2),
      );
      final rehearsal = PlanEvent(
        id: 'tc-2',
        type: kPlanEventTypeTeamCheck,
        date: _ddlDay,
        danceIds: const ['v2'],
        danceGates: const {'v2': 'familiar'},
      );
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1'), _entry('v2')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [videoSubmitted, rehearsal],
        ).toJson(),
        documents: {
          'v1': docWithMasteries([
            LearningMastery.mastered,
            LearningMastery.mastered,
          ]),
          'v2': docWithMasteries([LearningMastery.familiar]),
        },
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('plan_panel_teamcheck_tc-1_status')),
            )
            .data!,
        '达标',
      );
      // 录视频提交：带「已提交」标记与日期。
      expect(
        find.byKey(const Key('plan_panel_teamcheck_tc-1_submitted')),
        findsOneWidget,
      );
      // 到场排练：不显示提交控件。
      expect(
        find.byKey(const Key('plan_panel_teamcheck_tc-2_submitted')),
        findsNothing,
      );
      // 日历上团检与随舞圆点分列：团检出专属点。
      expect(
        find.byKey(Key('plan_day_dot_teamcheck_${_dayKey(_ddlDay)}')),
        findsOneWidget,
      );
    });

    testWidgets('进计划 Tab 重读段档位：标注页改档后达标状态随之更新', (tester) async {
      final markers = MarkersDocument(
        rangeStartMs: 0,
        rangeEndMs: 100000,
        segmentLines: [
          for (var i = 0; i < 3; i++)
            SegmentLine(position: Duration(milliseconds: i * 10000)),
        ],
      ).toJson();
      final doc = InMemoryVideoDocumentStorage(
        markers: markers,
        local: LocalDocument(
          mastery: const {
            0: LearningMastery.keepingUp,
            1: LearningMastery.keepingUp,
            2: LearningMastery.keepingUp,
            3: LearningMastery.keepingUp,
          },
        ).toJson(),
      );
      await _pump(
        tester,
        index: VideoIndex(entries: [_entry('v1')]),
        planJson: PracticePlanDocument(
          entries: [
            DancePlanEntry(
              videoId: 'v1',
              ddl: DanceDdl(date: _ddlDay),
            ),
          ],
          events: [
            PlanEvent(
              id: 'tc-1',
              type: kPlanEventTypeTeamCheck,
              date: _ddlDay,
              danceIds: const ['v1'],
              danceGates: const {'v1': 'familiar'},
            ),
          ],
        ).toJson(),
        documents: {'v1': doc},
      );
      await _openPlan(tester);
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('plan_panel_teamcheck_tc-1_dance_v1')),
            )
            .data!,
        '未达标',
      );

      // 模拟在标注页把档位补到较熟（直接改内存文档），再进计划 Tab 重读。
      final local = LocalDocument.fromJson(doc.localSnapshot);
      await doc.saveLocal(
        local.withMasteryMap(const {
          0: LearningMastery.familiar,
          1: LearningMastery.familiar,
          2: LearningMastery.familiar,
          3: LearningMastery.familiar,
        }).toJson(),
      );
      await _tapKey(tester, const Key('tab_home'));
      await tester.pumpAndSettle();
      await _tapKey(tester, const Key('tab_plan'));
      await tester.pumpAndSettle();
      await _tapKey(tester, Key('plan_day_${_dayKey(_ddlDay)}'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('plan_panel_teamcheck_tc-1_dance_v1')),
            )
            .data!,
        '达标',
      );
    });
  });
}
