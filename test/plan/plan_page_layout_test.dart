import 'package:dance_learning_app/persistence/practice_plan.dart';
import 'package:dance_learning_app/plan/plan_mark_kind.dart';
import 'package:dance_learning_app/plan/plan_page_layout.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _day(int y, int m, int d) => DateTime(y, m, d);

void main() {
  group('月视图网格（周一为首列）', () {
    test('2026-10：首列周一起、10-01（周四）前补 3 个跨月日、尾补成整周', () {
      // 2026-10-01 是周四：周一为首列时前面补 09-28..09-30 三天；
      // 34 格补成 5 行 35 格，末格是跨月的 11-01。
      final grid = buildPlanMonthGrid(_day(2026, 10, 1));
      expect(grid.month.year, 2026);
      expect(grid.month.month, 10);
      expect(grid.weeks.first.first, _day(2026, 9, 28));
      expect(grid.weeks.first[3], _day(2026, 10, 1));
      expect(grid.weeks.last.last, _day(2026, 11, 1));
      expect(grid.weeks.length, 5);
      for (final week in grid.weeks) {
        expect(week.length, 7);
      }
    });

    test('首日即周一、末尾补跨月日成整周（2026-11）', () {
      // 2026-11-01 是周日：首行以 10-26 起头补 6 天；11-30 是周一，
      // 末行以 12-01..12-06 补满。
      final grid = buildPlanMonthGrid(_day(2026, 11, 1));
      expect(grid.weeks.first.first, _day(2026, 10, 26));
      expect(grid.weeks.first.last, _day(2026, 11, 1));
      expect(grid.weeks.last.first, _day(2026, 11, 30));
      expect(grid.weeks.last.last, _day(2026, 12, 6));
    });

    test('isInMonth 区分本月与跨月补位日', () {
      final grid = buildPlanMonthGrid(_day(2026, 10, 1));
      expect(grid.isInMonth(_day(2026, 10, 15)), isTrue);
      expect(grid.isInMonth(_day(2026, 9, 28)), isFalse);
      expect(grid.isInMonth(_day(2026, 11, 1)), isFalse);
    });
  });

  group('时间轴条：固定一年窗口', () {
    Map<PlanMarkKind, Iterable<DateTime>> marks({
      Iterable<DateTime> ddl = const [],
      Iterable<DateTime> social = const [],
      Iterable<DateTime> teamCheck = const [],
    }) => {
      PlanMarkKind.ddl: ddl,
      PlanMarkKind.social: social,
      PlanMarkKind.teamCheck: teamCheck,
    };

    test('固定当前月起 12 段（跨年不跳月），不随计划跨度伸缩', () {
      final timeline = buildPlanTimeline(marks(), now: _day(2026, 10, 8));
      expect(
        [for (final s in timeline.segments) '${s.month.year}-${s.month.month}'],
        [
          '2026-10',
          '2026-11',
          '2026-12',
          '2027-1',
          '2027-2',
          '2027-3',
          '2027-4',
          '2027-5',
          '2027-6',
          '2027-7',
          '2027-8',
          '2027-9',
        ],
      );
      expect(timeline.segments.first.daysInMonth, 31);
      expect(timeline.segments[4].daysInMonth, 28);
    });

    test('早于当前月与超出 12 个月窗口的计划日不入段', () {
      final timeline = buildPlanTimeline(
        marks(
          ddl: [
            _day(2026, 9, 30),
            _day(2026, 10, 5),
            _day(2027, 9, 30),
            _day(2027, 10, 1),
          ],
        ),
        now: _day(2026, 10, 8),
      );
      final all = <int>{
        for (final segment in timeline.segments)
          ...segment.markedDaysOf(PlanMarkKind.ddl),
      };
      expect(all, {5, 30});
      expect(timeline.segments.first.markedDaysOf(PlanMarkKind.ddl), {5});
      expect(timeline.segments.last.markedDaysOf(PlanMarkKind.ddl), {30});
    });

    test('三类计划日按类型分列归集，同日多类并存', () {
      final timeline = buildPlanTimeline(
        marks(
          ddl: [_day(2026, 10, 5)],
          social: [_day(2026, 10, 5), _day(2026, 10, 20)],
          teamCheck: [_day(2026, 10, 5)],
        ),
        now: _day(2026, 10, 8),
      );
      final first = timeline.segments.first;
      expect(first.markedDaysOf(PlanMarkKind.ddl), {5});
      expect(first.markedDaysOf(PlanMarkKind.social), {5, 20});
      expect(first.markedDaysOf(PlanMarkKind.teamCheck), {5});
      // 同日多类：该日的类型按声明序给出并排位次。
      expect(first.marksByDay, {
        5: [PlanMarkKind.ddl, PlanMarkKind.social, PlanMarkKind.teamCheck],
        20: [PlanMarkKind.social],
      });
    });

    test('列内日位置比例：月首为 0、月末为 (天数 - 1) / 天数', () {
      final timeline = buildPlanTimeline(marks(), now: _day(2026, 10, 8));
      final october = timeline.segments.first;
      expect(october.daysInMonth, 31);
      expect(october.markerFraction(1), 0);
      expect(october.markerFraction(15), 14 / 31);
      expect(october.markerFraction(31), 30 / 31);
      // 2027-2 是 28 天：月末比例按该月天数归一。
      final february = timeline.segments[4];
      expect(february.month.month, 2);
      expect(february.daysInMonth, 28);
      expect(february.markerFraction(28), 27 / 28);
    });

    test('年份分段：首段恒有、1 月处断段，各段列数即该年在窗口内的列数', () {
      // 9 月起：2026 盖 9–12 月（4 列），2027 从 1 月起盖 1–8 月（8 列）。
      final fromSeptember = buildPlanTimeline(marks(), now: _day(2026, 9, 8));
      expect(
        [
          for (final span in fromSeptember.yearSpans)
            '${span.year}:${span.columnCount}',
        ],
        ['2026:4', '2027:8'],
      );
      // 1 月起：单段跨 12 列，窗口内不再断段。
      final fromJanuary = buildPlanTimeline(marks(), now: _day(2026, 1, 8));
      expect(
        [
          for (final span in fromJanuary.yearSpans)
            '${span.year}:${span.columnCount}',
        ],
        ['2026:12'],
      );
      // 12 月起：2026 只一列，2027 十一列。
      final fromDecember = buildPlanTimeline(marks(), now: _day(2026, 12, 8));
      expect(
        [
          for (final span in fromDecember.yearSpans)
            '${span.year}:${span.columnCount}',
        ],
        ['2026:1', '2027:11'],
      );
      // 分段列数合计恒为窗口列数。
      for (final timeline in [fromSeptember, fromJanuary, fromDecember]) {
        expect(
          timeline.yearSpans.fold<int>(
            0,
            (sum, span) => sum + span.columnCount,
          ),
          timeline.segments.length,
        );
      }
    });

    test('该月有无计划：有计划日的月为 true、空月为 false', () {
      final timeline = buildPlanTimeline(
        marks(ddl: [_day(2026, 10, 5)], social: [_day(2026, 12, 1)]),
        now: _day(2026, 10, 8),
      );
      expect(timeline.segments.first.hasMarks, isTrue);
      expect(timeline.segments[1].hasMarks, isFalse);
      expect(timeline.segments[2].hasMarks, isTrue);
      expect(timeline.segments.skip(3).every((s) => !s.hasMarks), isTrue);
    });

    test('月分隔虚线在月列左边界、且首列之前不画', () {
      final timeline = buildPlanTimeline(marks(), now: _day(2026, 10, 8));
      expect(timeline.segments.first.hasLeadingDivider, isFalse);
      expect(timeline.segments[1].hasLeadingDivider, isTrue);
    });

    test('「今天」竖线落在当月列内的真实位置', () {
      final timeline = buildPlanTimeline(marks(), now: _day(2026, 10, 8));
      expect(timeline.todayDayNumber, 8);
      // 2026-10 共 31 天，8 号是第 8 天 → (8−1)/31。
      expect(timeline.todayFraction, 7 / 31);
      // 计划日越靠后越靠右：20 号在 3 号右侧。
      final first = timeline.segments.first;
      expect(first.markerFraction(20), greaterThan(first.markerFraction(3)));
    });
  });

  group('月视图翻月与月份归属', () {
    test('翻月目标月：上月 / 下月，跨年由日期归一', () {
      expect(planShiftMonth(_day(2026, 12, 1), 1), _day(2027, 1, 1));
      expect(planShiftMonth(_day(2026, 1, 1), -1), _day(2025, 12, 1));
      expect(planShiftMonth(_day(2026, 10, 31), 1), _day(2026, 11, 1));
      expect(planShiftMonth(_day(2026, 10, 15), 0), _day(2026, 10, 1));
    });

    test('跨月补位日归其所属月；月键为补零 yyyyMM', () {
      expect(planMonthOf(_day(2026, 9, 28)), _day(2026, 9, 1));
      expect(planMonthOf(_day(2026, 11, 1)), _day(2026, 11, 1));
      expect(planMonthKey(_day(2026, 10, 5)), '202610');
      expect(planMonthKey(_day(2026, 9, 1)), '202609');
    });

    test('手势三态：累计位移 ≥40px 才切；左滑下一月、右滑上一月', () {
      expect(
        planMonthSwipe(totalDx: -39, totalDy: 0, velocityX: 0),
        PlanMonthSwipe.none,
      );
      expect(
        planMonthSwipe(totalDx: -40, totalDy: 0, velocityX: 0),
        PlanMonthSwipe.next,
      );
      expect(
        planMonthSwipe(totalDx: 40, totalDy: 0, velocityX: 0),
        PlanMonthSwipe.previous,
      );
    });

    test('速度 ≥300px/s 也触发；垂直分量占优不切；两者都够取位移方向', () {
      expect(
        planMonthSwipe(totalDx: -10, totalDy: 0, velocityX: -300),
        PlanMonthSwipe.next,
      );
      expect(
        planMonthSwipe(totalDx: -10, totalDy: 0, velocityX: -299),
        PlanMonthSwipe.none,
      );
      expect(
        planMonthSwipe(totalDx: -100, totalDy: 200, velocityX: 0),
        PlanMonthSwipe.none,
      );
      expect(
        planMonthSwipe(totalDx: 100, totalDy: -20, velocityX: -400),
        PlanMonthSwipe.previous,
      );
    });

    test('一次手势只切一月：越阈值即结算，后续增量与结束都不再触发', () {
      final tracker = PlanMonthSwipeTracker()..start();
      expect(tracker.update(-20, 0), PlanMonthSwipe.none);
      expect(tracker.update(-30, 5), PlanMonthSwipe.next);
      expect(tracker.update(-100, 0), PlanMonthSwipe.none);
      expect(tracker.finish(velocityX: -900), PlanMonthSwipe.none);
      // 新手势重新累计：位移不足时由速度补判。
      tracker.start();
      expect(tracker.update(-10, 0), PlanMonthSwipe.none);
      expect(tracker.finish(velocityX: -350), PlanMonthSwipe.next);
    });
  });

  group('有计划日子的归集', () {
    test('三类计划日分列：DDL 日、随舞日、团检日（本地日归一、去重）', () {
      final marks = planMarksByKind(
        [
          DancePlanEntry(
            videoId: 'a',
            ddl: DanceDdl(date: _day(2026, 10, 5)),
          ),
          DancePlanEntry(
            videoId: 'b',
            ddl: DanceDdl(date: DateTime(2026, 10, 5, 18, 30)),
          ),
          DancePlanEntry(videoId: 'c'),
        ],
        events: [
          PlanEvent(id: 'e1', date: _day(2026, 10, 5)),
          PlanEvent(
            id: 'e2',
            date: _day(2026, 10, 6),
            type: kPlanEventTypeTeamCheck,
          ),
          PlanEvent(id: 'e3', date: _day(2026, 10, 5)),
        ],
      );
      expect(marks[PlanMarkKind.ddl], {_day(2026, 10, 5)});
      expect(marks[PlanMarkKind.social], {_day(2026, 10, 5)});
      expect(marks[PlanMarkKind.teamCheck], {_day(2026, 10, 6)});
    });

    test('事件类型 → 标记类型：两类各归其位，未知类型为 null', () {
      expect(eventMarkKind(kPlanEventTypeSocial), PlanMarkKind.social);
      expect(eventMarkKind(kPlanEventTypeTeamCheck), PlanMarkKind.teamCheck);
      expect(eventMarkKind('unknown'), isNull);
      // 归集与「待复习」目标类型共用这一处映射：未知类型不入任何一类。
      final marks = planMarksByKind(
        const [],
        events: [PlanEvent(id: 'e1', date: _day(2026, 10, 5), type: 'unknown')],
      );
      expect(marks.values.every((days) => days.isEmpty), isTrue);
    });

    test('某日的 DDL 行：按 videoId 升序、带场合标签，无 DDL 条目不出', () {
      final rows = ddlsOnDay([
        DancePlanEntry(
          videoId: 'b',
          ddl: DanceDdl(date: _day(2026, 10, 5), occasion: '演出'),
        ),
        DancePlanEntry(
          videoId: 'a',
          ddl: DanceDdl(date: _day(2026, 10, 5)),
        ),
        DancePlanEntry(
          videoId: 'd',
          ddl: DanceDdl(date: _day(2026, 10, 6)),
        ),
        DancePlanEntry(videoId: 'c'),
      ], day: _day(2026, 10, 5));
      expect(rows.map((row) => (row.videoId, row.occasion)), [
        ('a', ''),
        ('b', '演出'),
      ]);
    });
  });

  group('planDayKey 与页面键口径一致', () {
    test('日键为补零 yyyy-MM-dd', () {
      expect(planDayKey(_day(2026, 3, 5)), '2026-03-05');
    });
  });

  group('随舞事件', () {
    PlanEvent ev(
      String id,
      String date, {
      String? startTime,
      List<String> danceIds = const [],
    }) => PlanEvent(
      id: id,
      date: DateTime.parse(date),
      startTime: startTime,
      danceIds: danceIds,
    );

    test('eventsOnDay：只收当天事件，按开始时间升序、无时间排后', () {
      final events = [
        ev('b', '2026-10-05', startTime: '19:00'),
        ev('a', '2026-10-05', startTime: '18:00'),
        ev('c', '2026-10-05'),
        ev('d', '2026-10-06'),
      ];
      expect(eventsOnDay(events, day: _day(2026, 10, 5)).map((e) => e.id), [
        'a',
        'b',
        'c',
      ]);
    });

    test('defaultEventDanceIds：排除显式关的舞与空 id，保持曲库次序', () {
      expect(
        defaultEventDanceIds(
          ['v1', 'off', '', 'v2'],
          disabledIds: const {'off'},
        ),
        ['v1', 'v2'],
      );
    });
  });
}
