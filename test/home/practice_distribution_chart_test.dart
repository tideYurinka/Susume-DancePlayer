import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/core/mastery_colors.dart';
import 'package:dance_learning_app/dance/practice_distribution.dart';
import 'package:dance_learning_app/dance/segment_practice_aggregation.dart';
import 'package:dance_learning_app/home/practice_distribution_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 练习分布曲线卡页面级测试：纵轴刻度列与长横虚线、熟练度色带
/// 段级选中与选中边框、图例与熟练度菜单按钮
/// 时间标签就位、四拍序号不出现、只连线无数据点、两行芯片照常、
/// 空态文案。
void main() {
  /// 12 个均匀 2s 桶（中点 1, 3, …, 23s），值 0…11。
  final buckets = [
    for (var i = 0; i < 12; i++)
      PracticeDistributionBucket(
        start: Duration(seconds: 2 * i),
        end: Duration(seconds: 2 * i + 2),
        duration: Duration(seconds: i),
        count: 11 - i,
      ),
  ];

  Future<void> pumpCard(
    WidgetTester tester, {
    double width = 320,
    List<PracticeDistributionBucket>? data,
    bool beatGridNotReady = false,
    double textScale = 1.0,
    List<LearningSegment> segments = const [],
    Map<int, LearningMastery> masteries = const {},
    List<SegmentPractice> segmentPractices = const [],
    void Function(int order, LearningMastery mastery)?
    onSegmentMasteryChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: _CardHolder(
                buckets: data ?? buckets.take(12).toList(),
                beatGridNotReady: beatGridNotReady,
                segments: segments,
                masteries: masteries,
                segmentPractices: segmentPractices,
                onSegmentMasteryChanged:
                    onSegmentMasteryChanged ?? (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DistributionPainter painterOf(WidgetTester tester) =>
      tester
              .widget<CustomPaint>(
                find.byWidgetPredicate(
                  (widget) =>
                      widget is CustomPaint &&
                      widget.painter is DistributionPainter,
                ),
              )
              .painter!
          as DistributionPainter;

  /// 画出来的选中边框：主色矩形即左右两条竖边（色带是淡色填充、曲线是
  /// 路径，主色矩形只有这一处）。颜色按 ARGB 比——`Paint.color` 取回的是
  /// 8bit 量化后的 Color，逐分量比较会因浮点表示判不等。
  List<Rect> selectionBorderOf(WidgetTester tester) {
    final painter = painterOf(tester);
    final box = tester.renderObject<RenderBox>(
      find.byKey(const Key('practice_gridlines')),
    );
    final canvas = _RecordingCanvas();
    painter.paint(canvas, box.size);
    final target = painter.color.toARGB32();
    return [
      for (final (rect, color) in canvas.rects)
        if (color.toARGB32() == target) rect,
    ];
  }

  testWidgets('时间标签就位：最多 4 档 m:ss（首 / 约 1/3 / 约 2/3 / 末）', (tester) async {
    await pumpCard(tester);
    // 12 点取 [0, 4, 7, 11]：中点 1s / 9s / 15s / 23s。
    expect(find.byKey(const Key('practice_time_label_0')), findsOneWidget);
    expect(find.byKey(const Key('practice_time_label_4')), findsOneWidget);
    expect(find.byKey(const Key('practice_time_label_7')), findsOneWidget);
    expect(find.byKey(const Key('practice_time_label_11')), findsOneWidget);
    expect(find.byKey(const Key('practice_time_label_1')), findsNothing);
    expect(find.text('0:01'), findsOneWidget);
    expect(find.text('0:09'), findsOneWidget);
    expect(find.text('0:15'), findsOneWidget);
    expect(find.text('0:23'), findsOneWidget);
  });

  testWidgets('标签按真实时间几何摆位：首标签贴左、末标签贴右、中间随时间落位', (
    tester,
  ) async {
    await pumpCard(tester, width: 320);
    const pad = 18.0;
    // 卡片内衬 12：绘图区宽 = 320 − 24 − 刻度列（28 + 4）= 264。
    final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
    final plotWidth = plot.width;
    double labelCenterX(String suffix) => tester
        .getRect(find.byKey(Key('practice_time_label_$suffix')))
        .center
        .dx;
    // 第 0 点 x = pad，末点 x = plotWidth − pad；曲线与标签行同宽同原点。
    final first = labelCenterX('0') - plot.left;
    final last = labelCenterX('11') - plot.left;
    expect(first, closeTo(pad, 30)); // 60 宽标签盒居中于 x。
    expect(last, closeTo(plotWidth - pad, 30));
    // 中间档：中点 15s 在 1–23s 跨度的 14/22 处，等距分档（5/11）不是这个值。
    final middle = labelCenterX('7') - plot.left;
    final byTime = pad + (plotWidth - pad * 2) * 14 / 22;
    expect(middle, closeTo(byTime, 1));
  });

  testWidgets('四拍序号全图不出现：无「第 N 段 / 八拍」文案、无数据点与圆点', (tester) async {
    await pumpCard(tester);
    expect(find.textContaining('第 '), findsNothing);
    expect(find.textContaining('八拍'), findsNothing);
    expect(find.byKey(const Key('practice_point_0')), findsNothing);
    expect(find.byKey(const Key('practice_dot_0')), findsNothing);
    expect(find.byKey(const Key('practice_distribution_selected')), findsNothing);
  });

  testWidgets('两行芯片保留：纵轴与范围口径各行其是', (tester) async {
    await pumpCard(tester);
    expect(find.byKey(const Key('practice_axis_segment')), findsNothing);
    expect(find.byKey(const Key('practice_axis_eightBeat')), findsNothing);
    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('practice_metric_duration')),
      ).selected,
      isTrue,
    );
    expect(
      tester.widget<ChoiceChip>(
        find.byKey(const Key('practice_range_cumulative')),
      ).selected,
      isTrue,
    );
    expect(find.byKey(const Key('practice_metric_count')), findsOneWidget);
    expect(find.byKey(const Key('practice_range_today')), findsOneWidget);
  });

  testWidgets('空态：网格未就绪沿用既有文案；无数据也有默认空态', (tester) async {
    await pumpCard(tester, data: const [], beatGridNotReady: true);
    expect(find.text('该时段无节拍数据'), findsOneWidget);
    expect(find.byKey(const Key('practice_distribution_chart')), findsNothing);

    await pumpCard(tester, data: const []);
    expect(find.text('暂无数据'), findsOneWidget);
  });

  testWidgets('空态不出现刻度列与虚线', (tester) async {
    await pumpCard(tester, data: const [], beatGridNotReady: true);
    expect(find.byKey(const Key('practice_axis_column')), findsNothing);
    expect(
      find.byKey(const Key('practice_distribution_chart')),
      findsNothing,
    );
    await pumpCard(tester, data: const []);
    expect(find.byKey(const Key('practice_axis_column')), findsNothing);
    expect(find.byKey(const Key('practice_gridlines')), findsNothing);
  });

  group('纵轴刻度纯件（复用统计页口径）', () {
    test('时长口径：单点极高 300s → 步长 1、上界 5、6 档；极小值 10s → 上界 1', () {
      final tall = [
        PracticeDistributionBucket(
          start: Duration.zero,
          end: const Duration(seconds: 2),
          duration: const Duration(seconds: 300),
          count: 0,
        ),
      ];
      final axis = practiceDistributionAxis(
        tall,
        PracticeDistributionMetric.duration,
      );
      expect(axis.step, 1);
      expect(axis.upperBound, 5);
      expect(axis.ticks, [0, 1, 2, 3, 4, 5]);

      final tiny = [
        PracticeDistributionBucket(
          start: Duration.zero,
          end: const Duration(seconds: 2),
          duration: const Duration(seconds: 10),
          count: 0,
        ),
      ];
      final tinyAxis = practiceDistributionAxis(
        tiny,
        PracticeDistributionMetric.duration,
      );
      expect(tinyAxis.step, 1);
      expect(tinyAxis.upperBound, 1);
      expect(tinyAxis.ticks, [0, 1]);
    });

    test('时长口径：全零退化为单档（上界 1 分钟）', () {
      final axis = practiceDistributionAxis(
        const [
          PracticeDistributionBucket(
            start: Duration.zero,
            end: Duration(seconds: 2),
            duration: Duration.zero,
            count: 0,
          ),
        ],
        PracticeDistributionMetric.duration,
      );
      expect(axis.step, 1);
      expect(axis.upperBound, 1);
      expect(axis.ticks, [0, 1]);
    });

    test('次数口径：次数 1 → 上界 1；单点极高 200 次 → 步长 50、上界 200', () {
      final one = practiceDistributionAxis(
        const [
          PracticeDistributionBucket(
            start: Duration.zero,
            end: Duration(seconds: 2),
            duration: Duration.zero,
            count: 1,
          ),
        ],
        PracticeDistributionMetric.count,
      );
      expect(one.step, 1);
      expect(one.upperBound, 1);
      expect(one.ticks, [0, 1]);

      final tall = practiceDistributionAxis(
        const [
          PracticeDistributionBucket(
            start: Duration.zero,
            end: Duration(seconds: 2),
            duration: Duration.zero,
            count: 200,
          ),
        ],
        PracticeDistributionMetric.count,
      );
      expect(tall.step, 50);
      expect(tall.upperBound, 200);
      expect(tall.ticks, [0, 50, 100, 150, 200]);

      final zero = practiceDistributionAxis(
        const [],
        PracticeDistributionMetric.count,
      );
      expect(zero.upperBound, 1);
      expect(zero.ticks, [0, 1]);
    });
  });

  testWidgets('刻度列就位：0 与上界各一条刻度文本，虚线画布就位', (tester) async {
    // 时长最大 11s → 向上取整 1 分 → 刻度 [0, 1]。
    await pumpCard(tester);
    expect(find.byKey(const Key('practice_axis_tick_0')), findsOneWidget);
    expect(find.byKey(const Key('practice_axis_tick_1')), findsOneWidget);
    expect(find.byKey(const Key('practice_axis_tick_2')), findsNothing);
    expect(find.byKey(const Key('practice_gridlines')), findsOneWidget);
  });

  testWidgets('长横虚线：每档一条含 0 基线，6dp 实 / 4dp 空，贯穿整宽', (tester) async {
    await pumpCard(tester);
    final painter = tester
        .widget<CustomPaint>(find.byKey(const Key('practice_gridlines')))
        .painter!;
    final box = tester.renderObject<RenderBox>(
      find.byKey(const Key('practice_gridlines')),
    );
    final canvas = _RecordingCanvas();
    painter.paint(canvas, box.size);

    // 刻度 [0, 1] → 2 条虚线：y=height（0 基线）与 y=0（上界）。
    final ys = canvas.lines.map((l) => l.$1.dy).toSet();
    expect(ys.length, 2);
    expect(ys.any((y) => (y - box.size.height).abs() < 0.01), isTrue);
    expect(ys.any((y) => y < 0.01), isTrue);

    for (final y in [0.0, box.size.height]) {
      final segments =
          canvas.lines.where((l) => (l.$1.dy - y).abs() < 0.01).toList()
            ..sort((a, b) => a.$1.dx.compareTo(b.$1.dx));
      expect(segments, isNotEmpty);
      var x = 0.0;
      for (final segment in segments) {
        expect(segment.$1.dy, segment.$2.dy, reason: '应为水平线段');
        expect(segment.$1.dx, closeTo(x, 0.01));
        expect(
          segment.$2.dx,
          closeTo((x + 6).clamp(0.0, box.size.width), 0.01),
          reason: '节拍应为 6dp 实',
        );
        x += 10;
      }
      expect(x - 4, closeTo(box.size.width, 6), reason: '应贯穿整宽');
    }
  });

  testWidgets('曲线高度按同一上界归一：顶点与上界刻度线同尺', (tester) async {
    final data = [
      PracticeDistributionBucket(
        start: Duration.zero,
        end: const Duration(seconds: 2),
        duration: const Duration(seconds: 30),
        count: 0,
      ),
      PracticeDistributionBucket(
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 4),
        duration: const Duration(seconds: 60),
        count: 0,
      ),
    ];
    await pumpCard(tester, data: data);
    final painter = tester
        .widget<CustomPaint>(find.byKey(const Key('practice_gridlines')))
        .painter!;
    final box = tester.renderObject<RenderBox>(
      find.byKey(const Key('practice_gridlines')),
    );
    final canvas = _RecordingCanvas();
    painter.paint(canvas, box.size);

    // 上界 1 分：60s 桶顶点 y=0 与上界刻度线同尺；30s 桶在半高。
    expect(canvas.pathTop, isNotNull);
    expect(canvas.pathTop!, closeTo(0, 0.01));
    expect(canvas.pathBottom, closeTo(box.size.height / 2, 0.01));
  });

  testWidgets('系统字号放大时刻度列变宽、不与绘图区重叠；缩小档不收缩', (tester) async {
    await pumpCard(tester, width: 480, textScale: 1.0);
    final normalWidth = tester.getSize(
      find.byKey(const Key('practice_axis_column')),
    ).width;
    final normalPlotLeft = tester.getTopLeft(
      find.byKey(const Key('practice_gridlines')),
    ).dx;

    await pumpCard(tester, width: 480, textScale: 2.0);
    final largeWidth = tester.getSize(
      find.byKey(const Key('practice_axis_column')),
    ).width;
    final largePlotLeft = tester.getTopLeft(
      find.byKey(const Key('practice_gridlines')),
    ).dx;
    expect(largeWidth, greaterThan(normalWidth));
    // 刻度列右缘与绘图区左缘之间隔着 4dp 间隙，不重叠。
    final axisRight = tester.getTopRight(
      find.byKey(const Key('practice_axis_column')),
    ).dx;
    expect(largePlotLeft - axisRight, closeTo(4, 0.5));

    await pumpCard(tester, width: 480, textScale: 0.5);
    final smallWidth = tester.getSize(
      find.byKey(const Key('practice_axis_column')),
    ).width;
    expect(smallWidth, closeTo(normalWidth, 0.01));
    expect(normalPlotLeft, greaterThan(0));
  });

  testWidgets('时间标签行高随系统字号放大（与统计页同款）；缩小档不收缩', (tester) async {
    await pumpCard(tester, textScale: 1.0);
    final normalHeight = tester.getSize(
      find.byKey(const Key('practice_time_label_row')),
    ).height;

    await pumpCard(tester, textScale: 2.0);
    final largeHeight = tester.getSize(
      find.byKey(const Key('practice_time_label_row')),
    ).height;
    expect(largeHeight, greaterThan(normalHeight));

    await pumpCard(tester, textScale: 0.5);
    expect(
      tester.getSize(find.byKey(const Key('practice_time_label_row'))).height,
      closeTo(normalHeight, 0.01),
    );
  });

  group('熟练度色带', () {
    // 桶中点域 1–23s，绘图区宽由纵轴刻度列实测得出，内缩 18：
    // x(t) = 18 + (宽−36)·(t−1)/22。段 [0,10s] 首端钳到 18；段 [15,20s]
    // 落在时间域内；中缝无段覆盖。
    final gapSegments = [
      LearningSegment(
        order: 0,
        start: Duration.zero,
        end: const Duration(seconds: 10),
      ),
      LearningSegment(
        order: 1,
        start: const Duration(seconds: 15),
        end: const Duration(seconds: 20),
      ),
    ];
    final gapMasteries = {
      0: LearningMastery.learning,
      1: LearningMastery.mastered,
    };

    testWidgets('有段覆盖的时段有色带、颜色与档位对应；无段时段无色带', (tester) async {
      await pumpCard(tester, segments: gapSegments, masteries: gapMasteries);
      final bands = painterOf(tester).bands;
      expect(bands, hasLength(2));
      // 绘图区实测宽：时间域首/末（1s / 23s）映射到 [18, 宽−18]。
      final plotWidth = tester
          .getSize(find.byKey(const Key('practice_gridlines')))
          .width;
      double x(int seconds) =>
          18 + (plotWidth - 36) * (seconds - 1) / 22;
      expect(bands[0].left, 18);
      expect(bands[0].right, closeTo(x(10), 0.01));
      expect(bands[1].left, closeTo(x(15), 0.01));
      expect(bands[1].right, closeTo(x(20), 0.01));
      // 中缝不被任何色带覆盖（无段渗漏）。
      expect(bands[0].right < bands[1].left, isTrue);
      // 颜色即档位色（与播放器段体同一套五档色）。
      expect(bands[0].mastery, LearningMastery.learning);
      expect(bands[1].mastery, LearningMastery.mastered);
      expect(learningMasteryColor(bands[1].mastery), kMasteryMasteredColor);
    });

    testWidgets('段间空隙处过渡带为 0；相邻共界段有窄过渡', (tester) async {
      await pumpCard(tester, segments: gapSegments, masteries: gapMasteries);
      var bands = painterOf(tester).bands;
      expect(bands[0].trailTransition, 0);
      expect(bands[1].leadTransition, 0);

      final adjacent = [
        LearningSegment(
          order: 0,
          start: Duration.zero,
          end: const Duration(seconds: 10),
        ),
        LearningSegment(
          order: 1,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        ),
      ];
      await pumpCard(tester, segments: adjacent, masteries: gapMasteries);
      bands = painterOf(tester).bands;
      // 两段都远宽于 40px ⇒ 过渡带取满 12dp，以段界为中心。
      expect(bands[0].trailTransition, 12);
      expect(bands[1].leadTransition, 12);
    });

    testWidgets('切换纵轴口径与范围口径后色带不变', (tester) async {
      await pumpCard(tester, segments: gapSegments, masteries: gapMasteries);
      final before = painterOf(tester).bands;
      await tester.tap(find.byKey(const Key('practice_metric_count')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice_range_today')));
      await tester.pumpAndSettle();
      // 色带不随纵轴与范围切换改变：段档位序列与时间铺位不变（按绘图区宽
      // 归一比较——刻度列宽可随口径微变，时间铺位本身不变）。
      final after = painterOf(tester).bands;
      expect(
        after.map((b) => b.mastery).toList(),
        before.map((b) => b.mastery).toList(),
      );
      final widthBefore = tester
          .getSize(find.byKey(const Key('practice_gridlines')))
          .width;
      double fraction(double value) => (value - 18) / (widthBefore - 36);
      expect(fraction(after[0].left), closeTo(fraction(before[0].left), 0.01));
      expect(
        fraction(after[1].right),
        closeTo(fraction(before[1].right), 0.01),
      );
      expect(after[0].right < after[1].left, isTrue);
    });

    testWidgets('色带只表达熟练度：不叠「练过 / 没练过」第二层标记', (tester) async {
      await pumpCard(tester, segments: gapSegments, masteries: gapMasteries);
      expect(find.textContaining('练过'), findsNothing);
      expect(find.textContaining('没练'), findsNothing);
      expect(find.byKey(const Key('practice_covered_marker')), findsNothing);
    });

    testWidgets('无分段：无色带', (tester) async {
      await pumpCard(tester);
      expect(painterOf(tester).bands, isEmpty);
    });
  });

  group('段级选中与气泡', () {
    // 两段：[0,10s) 带空隙 [10,15s)、[15,20s)。桶中点域 1–23s，绘图区宽
    // 264、内缩 18 ⇒ x(t) = 18 + 228·(t−1)/22。
    final segments = [
      LearningSegment(order: 0, start: Duration.zero, end: const Duration(seconds: 10)),
      LearningSegment(
        order: 1,
        start: const Duration(seconds: 15),
        end: const Duration(seconds: 20),
      ),
    ];
    final masteries = {
      0: LearningMastery.learning,
      1: LearningMastery.mastered,
    };
    final practices = [
      const SegmentPractice(
        practiceDuration: Duration(seconds: 30),
        practiceCount: 2,
        beatGridNotReady: false,
      ),
      const SegmentPractice(
        practiceDuration: Duration(seconds: 10),
        practiceCount: 1,
        beatGridNotReady: false,
      ),
    ];

    double xOfTime(int seconds) => 18 + 228 * (seconds - 1) / 22;

    /// 绘图区内的全局点：可选 dy 偏移（绘图区局部 y，默认竖直居中）。
    Offset plotPointAt(WidgetTester tester, int seconds, {double dy = 70}) =>
        tester.getRect(find.byKey(const Key('practice_gridlines'))).topLeft +
        Offset(xOfTime(seconds), dy);

    Future<void> tapAt(WidgetTester tester, Offset point) async {
      await tester.tapAt(point);
      await tester.pumpAndSettle();
    }

    Future<void> selectSegment(WidgetTester tester, int seconds) =>
        tapAt(tester, plotPointAt(tester, seconds));

    testWidgets('点按段内时刻选中该段：选中边框跨该段像素区间、气泡出段文案', (tester) async {
      await pumpCard(
        tester,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 5);

      // 气泡：段标签 + 秒级时间区间 + 练习时长 + 练习遍数 + 熟练度档位。
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);
      final bubble = find.byKey(const Key('practice_segment_bubble'));
      expect(find.text('第 1 段 · 0:00–0:10'), findsOneWidget);
      expect(find.text('练习 0:30 · 2 遍'), findsOneWidget);
      // 档位名在气泡里（图例也有一份同名文案）。
      expect(
        find.descendant(of: bubble, matching: find.text('学习中')),
        findsOneWidget,
      );

      // 选中边框：左右两条 2dp 主色竖边，跨度等于该段像素区间（首端钳到
      // 绘图区）；纵向与色带同一份上下内缩（绘图区高 140、内缩 18），横向
      // 向段内缩半个线宽，不画上下边。
      final selection = painterOf(tester).selection;
      expect(selection, isNotNull);
      expect(selection!.left, 18);
      expect(selection.right, closeTo(xOfTime(10), 0.01));
      final border = selectionBorderOf(tester);
      expect(border, hasLength(2));
      expect(border[0].left, selection.left);
      expect(border[0].right, selection.left + 2);
      expect(border[1].left, selection.right - 2);
      expect(border[1].right, selection.right);
      for (final rect in border) {
        expect(rect.top, 18, reason: '纵向与色带同一份上内缩');
        expect(rect.bottom, 122, reason: '纵向与色带同一份下内缩');
        expect(rect.width, 2, reason: '2dp 主色竖边');
        expect(rect.height, greaterThan(rect.width), reason: '竖边：不画上下边');
      }
    });

    testWidgets('末段贴绘图区右缘：右边竖边仍完整落在区内、不被裁', (tester) async {
      // 末段 [15s, 30s) 的右界越出时间域（桶中点域 1–23s），钳到绘图区右缘。
      final edgeSegments = [
        LearningSegment(
          order: 0,
          start: Duration.zero,
          end: const Duration(seconds: 15),
        ),
        LearningSegment(
          order: 1,
          start: const Duration(seconds: 15),
          end: const Duration(seconds: 30),
        ),
      ];
      await pumpCard(
        tester,
        segments: edgeSegments,
        masteries: masteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 17);

      final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
      final border = selectionBorderOf(tester);
      expect(border, hasLength(2));
      // 右竖边整条落在绘图区内：右沿即绘图区右缘，左沿向内 2dp。
      expect(border.last.right, closeTo(plot.width - 18, 0.01));
      expect(border.last.left, closeTo(plot.width - 20, 0.01));
    });

    testWidgets('气泡避让选中段：不相交、与段不留缝、纵向跟手指 y、钳在绘图区内', (tester) async {
      await pumpCard(
        tester,
        // 测试字体的字形等宽 1em：0.5 档让气泡窄到放得进绘图区一侧，避让
        // 可直证。
        textScale: 0.5,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
      // 手指点在绘图区上部：气泡纵向中心对齐手指 y（钳在绘图区内）。
      await tester.tapAt(plot.topLeft + Offset(xOfTime(17), 10));
      await tester.pumpAndSettle();
      final bubble = tester.getRect(
        find.byKey(const Key('practice_segment_bubble')),
      );
      // 选中段 2 [15s,20s) 的中心落在绘图区右半 → 气泡整体靠左、贴该段左缘
      // 不留缝，两者横向不相交。
      final segmentLeft = plot.left + xOfTime(15);
      expect(bubble.right, closeTo(segmentLeft, 0.01));
      // 纵向钳在绘图区内：手指 y=10 会让气泡上缘钳到绘图区顶。
      expect(bubble.top, plot.top);
      expect(bubble.bottom, lessThanOrEqualTo(plot.bottom));
      // 横向不出绘图区（卡片内钳制的更严形态）。
      expect(bubble.left, greaterThanOrEqualTo(plot.left));
      expect(bubble.right, lessThanOrEqualTo(plot.right));
    });

    testWidgets('选中段宽到左右都放不下：气泡仍完整落在绘图区内', (tester) async {
      // 整曲只有一段 [0,30s)：段界覆盖整个时间域，气泡两侧都放不下。
      final wholeSong = [
        LearningSegment(
          order: 0,
          start: Duration.zero,
          end: const Duration(seconds: 30),
        ),
      ];
      await pumpCard(
        tester,
        segments: wholeSong,
        masteries: const {0: LearningMastery.mastered},
        segmentPractices: const [
          SegmentPractice(
            practiceDuration: Duration(seconds: 30),
            practiceCount: 2,
            beatGridNotReady: false,
          ),
        ],
      );
      final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
      await tester.tapAt(plot.topLeft + Offset(plot.width / 2, 70));
      await tester.pumpAndSettle();

      final bubble = tester.getRect(
        find.byKey(const Key('practice_segment_bubble')),
      );
      expect(find.text('第 1 段 · 0:00–0:30'), findsOneWidget);
      expect(bubble.left, greaterThanOrEqualTo(plot.left));
      expect(bubble.right, lessThanOrEqualTo(plot.right));
      expect(bubble.top, greaterThanOrEqualTo(plot.top));
      expect(bubble.bottom, lessThanOrEqualTo(plot.bottom));
    });

    testWidgets('横向滑动经过的每一段依次成为选中段：气泡与选中边框跟手更新', (tester) async {
      await pumpCard(
        tester,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      final start = plotPointAt(tester, 5);
      await tester.dragFrom(start, Offset(xOfTime(17) - xOfTime(5), 0));
      await tester.pumpAndSettle();

      expect(find.text('第 2 段 · 0:15–0:20'), findsOneWidget);
      expect(find.text('练习 0:10 · 1 遍'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('practice_segment_bubble')),
          matching: find.text('掌握'),
        ),
        findsOneWidget,
      );
      final selection = painterOf(tester).selection!;
      expect(selection.left, closeTo(xOfTime(15), 0.01));
      expect(selection.right, closeTo(xOfTime(20), 0.01));
      final border = selectionBorderOf(tester);
      expect(border, hasLength(2));
      expect(border[0].left, selection.left);
      expect(border[1].right, selection.right);
      // 气泡随选中段变化实时重新避让（默认字号下气泡宽到该段右侧放不下，
      // 落到「左右都放不下」分支）：仍完整落在绘图区内、不越出卡片。
      final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
      final bubble = tester.getRect(
        find.byKey(const Key('practice_segment_bubble')),
      );
      expect(bubble.left, greaterThanOrEqualTo(plot.left));
      expect(bubble.right, lessThanOrEqualTo(plot.right));
      expect(bubble.top, greaterThanOrEqualTo(plot.top));
      expect(bubble.bottom, lessThanOrEqualTo(plot.bottom));
    });

    testWidgets('滑动跟手：气泡随选中段变化实时换侧避让', (tester) async {
      await pumpCard(
        tester,
        // 0.5 档让气泡放得进绘图区一侧，换侧避让可直证。
        textScale: 0.5,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      final plot = tester.getRect(find.byKey(const Key('practice_gridlines')));
      Rect bubbleRect() =>
          tester.getRect(find.byKey(const Key('practice_segment_bubble')));

      // 起点段 1 中心在绘图区左半 → 气泡贴该段右缘。
      final gesture = await tester.startGesture(
        plot.topLeft + Offset(xOfTime(5), 70),
      );
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      expect(bubbleRect().left, closeTo(plot.left + xOfTime(10), 0.01));

      // 滑到段 2（中心在绘图区右半）→ 气泡随即换到该段左缘。
      await gesture.moveBy(Offset(xOfTime(17) - xOfTime(5) - 24, 0));
      await tester.pump();
      expect(find.text('第 2 段 · 0:15–0:20'), findsOneWidget);
      expect(bubbleRect().right, closeTo(plot.left + xOfTime(15), 0.01));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('点无学习段覆盖的时段（段间空隙）清除选中并收起气泡', (tester) async {
      await pumpCard(
        tester,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 5);
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);

      // 点段间空隙（12s，避开气泡矩形的下部）清除选中并收起气泡。
      await tapAt(tester, plotPointAt(tester, 12, dy: 125));
      expect(find.byKey(const Key('practice_segment_bubble')), findsNothing);
      expect(painterOf(tester).selection, isNull);
      expect(selectionBorderOf(tester), isEmpty);
    });

    testWidgets('点气泡本身不清除选中', (tester) async {
      await pumpCard(
        tester,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 5);
      final bubble = tester.getRect(find.byKey(const Key('practice_segment_bubble')));

      // 点气泡内一段「本无段覆盖」的横位（段间空隙 12s）：若无气泡豁免，
      // 这一击会按空隙规则清掉选中。
      final gapPoint = plotPointAt(tester, 12);
      expect(
        bubble.contains(gapPoint),
        isTrue,
        reason: '前置：该点落在气泡矩形内，豁免才被触发',
      );
      await tapAt(tester, gapPoint);
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);
      expect(find.text('第 1 段 · 0:00–0:10'), findsOneWidget);
    });

    testWidgets('从气泡上起拖：气泡对拖动透明，仍依次切换选中段', (tester) async {
      await pumpCard(
        tester,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 5);
      final bubble = tester.getRect(find.byKey(const Key('practice_segment_bubble')));

      await tester.dragFrom(
        bubble.center,
        plotPointAt(tester, 17) - bubble.center,
      );
      await tester.pumpAndSettle();
      expect(find.text('第 2 段 · 0:15–0:20'), findsOneWidget);
    });

    testWidgets('气泡读数跟随纵轴口径：换口径后练习行文案跟着变', (tester) async {
      await pumpCard(
        tester,
        segments: segments,
        masteries: masteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 5);
      expect(find.text('练习 0:30 · 2 遍'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice_metric_count')));
      await tester.pumpAndSettle();
      expect(find.text('练习 0:30 · 2 遍'), findsNothing);
      expect(find.text('2 遍 · 练习 0:30'), findsOneWidget);
      // 气泡保持打开。
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);
    });

    testWidgets('无分段：点图不清出气泡与选中边框', (tester) async {
      await pumpCard(tester);
      await selectSegment(tester, 5);
      expect(find.byKey(const Key('practice_segment_bubble')), findsNothing);
      expect(painterOf(tester).selection, isNull);
      expect(selectionBorderOf(tester), isEmpty);
    });

    testWidgets('段很窄：选中边框两条竖边仍各画得出、不消失', (tester) async {
      // 窄段 [10s, 10.1s] 夹在中间：像素宽约 1px，不足 2dp 线宽，两条边仍
      // 各画一条（收到段内、重合成一条也不省略）。
      final narrow = [
        LearningSegment(order: 0, start: Duration.zero, end: const Duration(seconds: 10)),
        LearningSegment(
          order: 1,
          start: const Duration(seconds: 10),
          end: const Duration(milliseconds: 10100),
        ),
        LearningSegment(
          order: 2,
          start: const Duration(milliseconds: 10100),
          end: const Duration(seconds: 20),
        ),
      ];
      final narrowMasteries = {
        0: LearningMastery.learning,
        1: LearningMastery.keepingUp,
        2: LearningMastery.mastered,
      };
      await pumpCard(
        tester,
        segments: narrow,
        masteries: narrowMasteries,
        segmentPractices: practices,
      );
      await selectSegment(tester, 10); // 时刻 10s 落在窄段（左闭右开）
      final selection = painterOf(tester).selection;
      expect(selection, isNotNull);
      expect(selection!.right - selection.left, lessThan(2));
      final border = selectionBorderOf(tester);
      expect(border, hasLength(2));
      for (final rect in border) {
        expect(rect.left, greaterThanOrEqualTo(selection.left));
        expect(rect.right, lessThanOrEqualTo(selection.right));
        expect(rect.width, greaterThan(0));
        expect(rect.height, greaterThan(0));
      }
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);
    });
  });

  group('图例与熟练度菜单按钮', () {
    // 与「段级选中与气泡」组同一套几何：两段 [0,10s) / [10,20s)，桶中点域 1–23s，
    // 绘图区宽 264、内缩 18 ⇒ x(t) = 18 + 228·(t−1)/22。
    final legendSegments = [
      LearningSegment(order: 0, start: Duration.zero, end: const Duration(seconds: 10)),
      LearningSegment(
        order: 1,
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 20),
      ),
    ];
    const practices = [
      SegmentPractice(
        practiceDuration: Duration(seconds: 30),
        practiceCount: 2,
        beatGridNotReady: false,
      ),
      SegmentPractice(
        practiceDuration: Duration(seconds: 10),
        practiceCount: 1,
        beatGridNotReady: false,
      ),
    ];

    double xOfTime(int seconds) => 18 + 228 * (seconds - 1) / 22;

    Offset plotPointAt(WidgetTester tester, int seconds, {double dy = 70}) =>
        tester.getRect(find.byKey(const Key('practice_gridlines'))).topLeft +
        Offset(xOfTime(seconds), dy);

    Future<void> selectSegment(WidgetTester tester, int seconds) async {
      await tester.tapAt(plotPointAt(tester, seconds));
      await tester.pumpAndSettle();
    }

    testWidgets('图例行左侧五档图例：色点配档位名，色点取与色带同一入口', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('practice_mastery_legend')), findsOneWidget);
      final expected = {
        LearningMastery.unlearned: '未练',
        LearningMastery.learning: '学习中',
        LearningMastery.keepingUp: '能跟上',
        LearningMastery.familiar: '较熟',
        LearningMastery.mastered: '掌握',
      };
      for (final entry in expected.entries) {
        expect(find.byKey(Key('practice_legend_dot_${entry.key.name}')),
            findsOneWidget);
        final dot = tester.widget<Container>(
          find.byKey(Key('practice_legend_dot_${entry.key.name}')),
        );
        final decoration = dot.decoration! as BoxDecoration;
        expect(decoration.color, learningMasteryColor(entry.key));
        expect(find.text(entry.value), findsOneWidget);
      }
    });

    testWidgets('无分段时按钮不出现，图例仍在', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('practice_mastery')), findsNothing);
      expect(find.byKey(const Key('practice_mastery_legend')), findsOneWidget);
    });

    testWidgets('未选中任何段时按钮置灰不可点', (tester) async {
      await pumpCard(tester, segments: legendSegments);
      expect(
        tester.widget<PopupMenuButton<LearningMastery>>(
          find.byKey(const Key('practice_mastery')),
        ).enabled,
        isFalse,
      );
      // 未选中显示「熟练度」占位，不借未练档位名顶位。
      expect(
        find.descendant(
          of: find.byKey(const Key('practice_mastery')),
          matching: find.text('熟练度'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('practice_mastery')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('practice_mastery_learning')), findsNothing);
    });

    testWidgets('选中段后按钮显示该段档位名，点开是既有五档菜单且当前档高亮', (tester) async {
      await pumpCard(
        tester,
        segments: legendSegments,
        masteries: {0: LearningMastery.learning},
      );
      await selectSegment(tester, 5); // 选中段 1（order 0，学习中）
      // 按钮文案 = 当前选中段的档位名（图例与气泡里的同名文案不算）。
      expect(
        find.descendant(
          of: find.byKey(const Key('practice_mastery')),
          matching: find.text('学习中'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('practice_mastery')));
      await tester.pumpAndSettle();
      for (final name in LearningMastery.values) {
        expect(
          find.byKey(Key('practice_mastery_${name.name}')),
          findsOneWidget,
        );
      }
      expect(
        tester.widget<CheckedPopupMenuItem<LearningMastery>>(
          find.byKey(const Key('practice_mastery_learning')),
        ).checked,
        isTrue,
      );
      expect(
        tester.widget<CheckedPopupMenuItem<LearningMastery>>(
          find.byKey(const Key('practice_mastery_mastered')),
        ).checked,
        isFalse,
      );
    });

    testWidgets('改档后就地更新：回调带段序与新档位，色带换色、选中边框仍在、气泡档位名就地变且气泡保持打开', (tester) async {
      var masteries = {
        0: LearningMastery.learning,
        1: LearningMastery.mastered,
      };
      int? changedOrder;
      LearningMastery? changedMastery;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) => PracticeDistributionCard(
                    buckets: buckets,
                    metric: PracticeDistributionMetric.duration,
                    range: PracticeDistributionRange.cumulative,
                    beatGridNotReady: false,
                    segments: legendSegments,
                    masteries: masteries,
                    segmentPractices: practices,
                    onSegmentMasteryChanged: (order, mastery) => setState(() {
                      changedOrder = order;
                      changedMastery = mastery;
                      masteries = {...masteries, order: mastery};
                    }),
                    onMetricChanged: (_) {},
                    onRangeChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectSegment(tester, 5); // 选中段 1（order 0，学习中）
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice_mastery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('practice_mastery_mastered')));
      await tester.pumpAndSettle();

      // 回调带选中段序与新档位；读面更新后整链就地换新——色带换色、
      // 选中边框仍在、气泡里的档位名就地变、气泡保持打开。
      expect(changedOrder, 0);
      expect(changedMastery, LearningMastery.mastered);
      final bands = painterOf(tester).bands;
      expect(bands, hasLength(2));
      expect(bands[0].mastery, LearningMastery.mastered);
      final selection = painterOf(tester).selection;
      expect(selection, isNotNull);
      expect(selection!.left, 18);
      expect(selection.right, closeTo(xOfTime(10), 0.01));
      expect(selectionBorderOf(tester), hasLength(2));
      expect(find.byKey(const Key('practice_segment_bubble')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('practice_segment_bubble')),
          matching: find.text('掌握'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('practice_mastery')),
          matching: find.text('掌握'),
        ),
        findsOneWidget,
      );
    });
  });
}

/// 记录 drawLine、drawRect 与 drawPath 包围盒的画布（虚线、色带 / 选中边框
/// 与曲线几何断言用）。
class _RecordingCanvas implements Canvas {
  final lines = <(Offset, Offset, Color)>[];
  final rects = <(Rect, Color)>[];
  double? pathTop;
  double pathBottom = double.infinity;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add((p1, p2, paint.color));

  @override
  void drawRect(Rect rect, Paint paint) => rects.add((rect, paint.color));

  @override
  void drawPath(Path path, Paint paint) {
    final bounds = path.getBounds();
    pathTop = bounds.top;
    pathBottom = bounds.bottom;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 卡片外壳：持两轴状态，芯片回调就地生效（页面里由详情页状态承担）。
class _CardHolder extends StatefulWidget {
  const _CardHolder({
    required this.buckets,
    required this.beatGridNotReady,
    required this.segments,
    required this.masteries,
    required this.segmentPractices,
    required this.onSegmentMasteryChanged,
  });

  final List<PracticeDistributionBucket> buckets;
  final bool beatGridNotReady;
  final List<LearningSegment> segments;
  final Map<int, LearningMastery> masteries;
  final List<SegmentPractice> segmentPractices;
  final void Function(int order, LearningMastery mastery)
  onSegmentMasteryChanged;

  @override
  State<_CardHolder> createState() => _CardHolderState();
}

class _CardHolderState extends State<_CardHolder> {
  PracticeDistributionMetric _metric = PracticeDistributionMetric.duration;
  PracticeDistributionRange _range = PracticeDistributionRange.cumulative;

  @override
  Widget build(BuildContext context) {
    return PracticeDistributionCard(
      buckets: widget.buckets,
      metric: _metric,
      range: _range,
      beatGridNotReady: widget.beatGridNotReady,
      segments: widget.segments,
      masteries: widget.masteries,
      segmentPractices: widget.segmentPractices,
      onSegmentMasteryChanged: widget.onSegmentMasteryChanged,
      onMetricChanged: (metric) => setState(() => _metric = metric),
      onRangeChanged: (range) => setState(() => _range = range),
    );
  }
}
