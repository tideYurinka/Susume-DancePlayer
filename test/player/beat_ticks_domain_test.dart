import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/segment_line.dart'
    show SegmentLine;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show effectiveAnnotationTimelineProvider;
import 'package:dance_learning_app/player/track_beat_ticks.dart'
    show BeatTicksRow, kEightCountLabelSlotHeight;
import 'package:dance_learning_app/player/track_geometry.dart'
    show TrackBandGeometry, kTrackPrefixWidth;
import 'package:dance_learning_app/player/track_row_table.dart'
    show kBeatTrackRowHeight;
import 'package:dance_learning_app/player/track_time.dart'
    show TimelineAxis, TimelineWindow;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kBeatTrackErrorBackground, kBeatTrackErrorTextColor;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';

/// 节拍刻度域直测：直接 pump 该模块、只注该域
/// 需要的少数 provider——不造整条带的布景。
///
/// 断言的是**渲染出来的**刻度几何、三态形态与八拍数标注，与整条带渲染
/// （`track_band_test.dart` 各节拍组）逐项同值。测试环境
/// `beatAnalyzingFlowProvider` 缺省静止（形态逐位同流动帧），占位态可直接
/// `pumpAndSettle`。
void main() {
  const total = Duration(seconds: 30);
  // 行高用生产行表的节拍轨行高：刻度让位与标注间隙的断言才有生产口径。
  const rowHeight = kBeatTrackRowHeight;
  const rowWidth = 300.0;

  /// 与生产同构的横向轴：全宽 0..total、让出轨道片头带宽。
  TimelineAxis axisOf({TimelineWindow? window}) => TrackBandGeometry.eval(
    total: total,
    window: window,
    width: rowWidth,
    prefixWidth: kTrackPrefixWidth,
  ).axis;

  /// 直接 pump 模块本体（行内只有它在渲染）。
  ///
  /// 生效时间线一律注入（缺省 = 整片单段、无分段线）：生产里「时间线未初始
  /// 化」的兜底读播放内核时长，本模块直测不为此搭引擎布景。
  Future<void> pumpRow(
    WidgetTester tester, {
    required BeatTrackState track,
    TimelineAxis? axis,
    AnnotationTimeline? timeline,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          beatTrackStateProvider.overrideWithBuild((ref, _) => track),
          effectiveAnnotationTimelineProvider.overrideWithValue(
            timeline ?? AnnotationTimeline.wholeVideo(total),
          ),
        ],
        child: MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: rowWidth,
              height: rowHeight,
              child: BeatTicksRow(axis: axis ?? axisOf(), height: rowHeight),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 0.5s 均匀拍点、每 4 拍一个强拍的就绪网格（八拍大线 t = 0、4、8…s）。
  BeatTrackState readyBeat() => uniformReadyBeatState(seconds: 30);

  double tickWidth(WidgetTester tester, Key key) =>
      tester.getSize(find.byKey(key)).width;

  double tickHeight(WidgetTester tester, Key key) =>
      tester.getSize(find.byKey(key)).height;

  Color tickColor(WidgetTester tester, Key key) => tester
      .widget<ColoredBox>(
        find.descendant(of: find.byKey(key), matching: find.byType(ColoredBox)),
      )
      .color;

  group('三态表现', () {
    testWidgets('占位：整行不定态进度条 +「节拍分析中……」，无任何刻度', (tester) async {
      await pumpRow(tester, track: const BeatTrackState.placeholder());

      expect(find.byKey(const Key('track_beat')), findsOneWidget);
      expect(find.byKey(const Key('beat_track_placeholder')), findsOneWidget);
      expect(find.text('节拍分析中……'), findsOneWidget);
      expect(find.byKey(const Key('beat_track_shimmer')), findsOneWidget);
      expect(
        tester
            .getSemantics(find.byKey(const Key('beat_track_placeholder')))
            .label,
        contains('节拍分析中'),
      );

      // 不画任何均匀占位刻度：占位态整行是横幅，行内既无刻度几何也无数字
      // ——整族刻度键在行内一个都不出现（含 0 拍点）。
      expect(
        find.descendant(
          of: find.byKey(const Key('track_beat')),
          matching: find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey &&
                (w.key! as ValueKey).value.toString().startsWith('beat_tick_'),
          ),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('track_beat')),
          matching: find.byWidgetPredicate((w) => w is Text),
        ),
        findsOneWidget, // 仅「节拍分析中……」一条
      );
    });

    testWidgets('就绪：整行直接换成真实刻度，无占位横幅', (tester) async {
      await pumpRow(tester, track: readyBeat());

      expect(find.byKey(const Key('beat_track_placeholder')), findsNothing);
      expect(find.text('节拍分析中……'), findsNothing);
      expect(find.byKey(const Key('beat_tick_0')), findsOneWidget);
    });

    testWidgets('异常：整行暖色底 +「节拍识别失败」，无任何刻度', (tester) async {
      await pumpRow(tester, track: const BeatTrackState.error());

      final failed = find.byKey(const Key('beat_track_failed'));
      expect(failed, findsOneWidget);
      expect(find.text('节拍识别失败'), findsOneWidget);
      expect(tester.getSemantics(failed).label, contains('节拍识别失败'));
      expect(find.byKey(const Key('beat_tick_0')), findsNothing);

      final background = tester
          .widget<ColoredBox>(
            find.descendant(of: failed, matching: find.byType(ColoredBox)),
          )
          .color;
      expect(background, kBeatTrackErrorBackground);
      final label = tester.widget<Text>(
        find.byKey(const Key('beat_track_failed_label')),
      );
      expect(label.style?.color, kBeatTrackErrorTextColor);
    });
  });

  group('三级刻度排布', () {
    testWidgets('宽按层级：八拍大线 1.5px、中/小线 1px；透明度 0.95/0.62/0.34', (tester) async {
      await pumpRow(tester, track: readyBeat());

      expect(tickWidth(tester, const Key('beat_tick_0')), 1.5);
      expect(tickWidth(tester, const Key('beat_tick_2000000')), 1.0);
      expect(tickWidth(tester, const Key('beat_tick_500000')), 1.0);
      expect(tickColor(tester, const Key('beat_tick_0')).a, 0.95);
      expect(tickColor(tester, const Key('beat_tick_2000000')).a, 0.62);
      expect(tickColor(tester, const Key('beat_tick_500000')).a, 0.34);
    });

    testWidgets('长按层级：大线 11 / 中线 8 / 小线 5，三级垂直居中且让开标注槽', (tester) async {
      await pumpRow(tester, track: readyBeat());

      expect(tickHeight(tester, const Key('beat_tick_0')), 11.0);
      expect(tickHeight(tester, const Key('beat_tick_2000000')), 8.0);
      expect(tickHeight(tester, const Key('beat_tick_500000')), 5.0);

      // 三级同为一行内「让位列」：列顶 = 标注槽高 + 2px 间隙、列底留 1px——
      // 让位列内垂直居中，故中点 = 让位列中点、上下间隙对称。
      const columnTop = kEightCountLabelSlotHeight + 2;
      const columnBottom = rowHeight - 1;
      for (final entry in const [
        (key: 'beat_tick_0', length: 11.0),
        (key: 'beat_tick_2000000', length: 8.0),
        (key: 'beat_tick_500000', length: 5.0),
      ]) {
        final rect = tester.getRect(find.byKey(Key(entry.key)));
        expect(rect.height, entry.length);
        expect(
          rect.center.dy,
          moreOrLessEquals((columnTop + columnBottom) / 2, epsilon: 0.01),
          reason: '${entry.key} 未在让位列内垂直居中',
        );
        expect(
          rect.top - columnTop,
          moreOrLessEquals(columnBottom - rect.bottom, epsilon: 0.01),
          reason: '${entry.key} 让位列内上下间隙不对称',
        );
      }
    });

    testWidgets('x 与时间轴换算逐位一致，刻度宽按层级居中于时刻', (tester) async {
      final axis = axisOf();
      await pumpRow(tester, track: readyBeat(), axis: axis);

      for (final time in const [
        Duration.zero,
        Duration(milliseconds: 500),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]) {
        final key = Key('beat_tick_${time.inMicroseconds}');
        expect(
          tester.getCenter(find.byKey(key)).dx,
          moreOrLessEquals(axis.timeToX(time), epsilon: 0.01),
          reason: '$time 刻度中心与轴换算不一致',
        );
      }
    });

    testWidgets('不显示半拍刻度线', (tester) async {
      await pumpRow(tester, track: readyBeat());

      expect(find.byKey(const Key('beat_tick_250000')), findsNothing);
      expect(find.byKey(const Key('beat_tick_750000')), findsNothing);
    });

    testWidgets('窗口不含时不画：窗口外刻度缺席、窗内刻度在场', (tester) async {
      // 窗口 3..6s：0/2s 刻度在窗内之外，4s 大线仍在窗内。
      final window = TimelineWindow(
        total: total,
        start: const Duration(seconds: 3),
        end: const Duration(seconds: 6),
      );
      await pumpRow(
        tester,
        track: readyBeat(),
        axis: axisOf(window: window),
      );

      expect(find.byKey(const Key('beat_tick_0')), findsNothing);
      expect(find.byKey(const Key('beat_tick_2000000')), findsNothing);
      expect(find.byKey(const Key('beat_tick_4000000')), findsOneWidget);
      expect(find.byKey(const Key('beat_tick_5000000')), findsOneWidget);
    });

    testWidgets('窗口退化（不可映射）时安静返回空刻度、行仍在', (tester) async {
      await pumpRow(
        tester,
        track: readyBeat(),
        axis: TrackBandGeometry.eval(
          total: Duration.zero,
          width: rowWidth,
          prefixWidth: kTrackPrefixWidth,
        ).axis,
      );

      expect(find.byKey(const Key('track_beat')), findsOneWidget);
      expect(find.byKey(const Key('beat_tick_0')), findsNothing);
    });
  });

  group('八拍数标注', () {
    testWidgets('按段内相对编号标注大线；标注槽在行顶、与大线留间隙', (tester) async {
      // 段起于 8s（八拍大线整点）：段首同位大线不标（由线表达）但仍占序号
      // ——其所在大线即段内序号 1，故 12/20s 大线为序号 2/4；序号对段全量
      // 大线计数（16s 不标但也占号，锚点让位同此口径）。次段（分段线 24s）
      // 内 28s 大线重数回 2（24s 段首占序号 1）。
      await pumpRow(
        tester,
        track: readyBeat(),
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 8),
          segmentLines: const [SegmentLine(position: Duration(seconds: 24))],
        ),
      );

      final rowTop = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      for (final entry in const [
        (time: Duration(seconds: 12), count: '2'),
        (time: Duration(seconds: 20), count: '4'),
        (time: Duration(seconds: 28), count: '2'),
      ]) {
        final labelRect = tester.getRect(
          find.byKey(Key('beat_count_${entry.time.inMicroseconds}')),
        );
        expect(labelRect.top, rowTop);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byKey(
                    Key('beat_count_${entry.time.inMicroseconds}'),
                  ),
                  matching: find.byType(Text),
                ),
              )
              .data,
          entry.count,
        );
        final tickRect = tester.getRect(
          find.byKey(Key('beat_tick_${entry.time.inMicroseconds}')),
        );
        expect(
          tickRect.top - labelRect.bottom,
          greaterThanOrEqualTo(1.0),
          reason: 't=${entry.time} 标注与大线重叠',
        );
      }
    });

    testWidgets('占位态不标注（无真实网格）', (tester) async {
      await pumpRow(tester, track: const BeatTrackState.placeholder());

      expect(
        find.descendant(
          of: find.byKey(const Key('track_beat')),
          matching: find.byType(Text),
        ),
        findsOneWidget, // 仅「节拍分析中……」一条
      );
    });
  });
}
