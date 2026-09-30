import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart'
    show LearningMastery;
import 'package:dance_learning_app/annotation/segment_line.dart'
    show SegmentLine;
import 'package:dance_learning_app/annotation/transition_segment.dart'
    show TransitionSegment;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/mastery_colors.dart'
    show learningMasteryColor;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationGestureTarget;
import 'package:dance_learning_app/player/track_band_drag.dart';
import 'package:dance_learning_app/player/track_learning_row.dart';
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowRect;
import 'package:dance_learning_app/player/track_time.dart'
    show TimelineAxis, TimelineWindow;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kCyanAccentColor, kSegmentBoxStrokeColor;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';

/// 直测默认回调：顶层函数声明，故同一份 tear-off 恒相等——域输入按字段
/// 判等（含回调）时，「字段全等、实例不同」的输入才真等值。
void _noopSegmentOrder(int _) {}
void _noopTapUp(TapUpDetails _) {}
void _noopLineTap(int _, Offset _) {}
int? _noSpanOrder(Offset _) => null;
Offset? _sameLocal(Offset globalPosition) => globalPosition;

/// 学习段轨域直测：直接 pump 本域的三件
/// widget（轨道本体 / 线段点按命中层 / 覆盖层），只注它真正需要的那一个
/// provider（节拍轨三态，供段内八拍数）。断言口径是外部可观察行为——按输入
/// 渲染出的段体、回调收到的段序、覆盖层与命中列的形态、输入判等下的子重建
/// 纪律；不断言实现细节。
void main() {
  const width = 400.0;
  const rowHeight = 48.0;

  /// 行矩形固定：本域只吃它做纵向几何（顶/高）。
  const rowRect = TrackRowRect(top: 0, height: rowHeight);

  AnnotationTimeline timelineWith(
    List<Duration> lines, {
    Duration total = const Duration(seconds: 30),
    Duration? rangeEnd,
  }) => AnnotationTimeline.normalized(
    videoDuration: total,
    rangeEnd: rangeEnd ?? total,
    segmentLines: [
      for (final position in lines) SegmentLine(position: position),
    ],
  );

  TimelineAxis axisFor(Duration total) => TimelineAxis(
    total: total,
    width: width,
    contentLeft: 0,
    window: TimelineWindow.full(total),
  );

  TrackLearningRowInput buildInput({
    required AnnotationTimeline timeline,
    required TimelineAxis axis,
    Map<int, LearningMastery> mastery = const {},
    Set<int> emphasizedSegments = const {},
    Set<int> activatedSegments = const {},
    TransitionSegment? transition,
    ValueChanged<int>? onSegmentDragStart,
    GestureTapUpCallback? onSegmentTapUp,
    ValueChanged<int>? onSegmentTapDown,
    ValueChanged<int>? onSegmentTapCancel,
    void Function(int index, Offset globalPosition)? onSegmentLineTap,
    TrackBandDragSession? dragDomain,
    int? Function(Offset globalPosition)? resolveSpanOrder,
    Offset? Function(Offset globalPosition)? bandLocalAt,
  }) => TrackLearningRowInput(
    rowRect: rowRect,
    axis: axis,
    window: axis.window ?? TimelineWindow.full(axis.total),
    timeline: timeline,
    mastery: mastery,
    emphasizedSegments: emphasizedSegments,
    activatedSegments: activatedSegments,
    transition: transition,
    onSegmentDragStart: onSegmentDragStart ?? _noopSegmentOrder,
    onSegmentTapUp: onSegmentTapUp ?? _noopTapUp,
    onSegmentTapDown: onSegmentTapDown ?? _noopSegmentOrder,
    onSegmentTapCancel: onSegmentTapCancel ?? _noopSegmentOrder,
    onSegmentLineTap: onSegmentLineTap ?? _noopLineTap,
    dragDomain: dragDomain ?? _emptyDragDomain(),
    resolveSpanOrder: resolveSpanOrder ?? _noSpanOrder,
    bandLocalAt: bandLocalAt ?? _sameLocal,
  );

  /// 直测布景：只给域件一个定宽布局盒与 ProviderScope；不造整条带的布景。
  Widget mount(
    Widget child, {
    List<Override> overrides = const [],
    double height = rowHeight,
  }) => ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(children: [child]),
          ),
        ),
      ),
    ),
  );

  testWidgets('按输入渲染段体：熟练度取色、重点星标、激活外发光与循环端标', (tester) async {
    final total = const Duration(seconds: 30);
    final input = buildInput(
      timeline: timelineWith(const [
        Duration(seconds: 10),
        Duration(seconds: 20),
      ]),
      axis: axisFor(total),
      mastery: const {
        0: LearningMastery.mastered,
        1: LearningMastery.learning,
      },
      emphasizedSegments: const {0},
      activatedSegments: const {0},
    );
    await tester.pumpWidget(mount(TrackLearningRow(input: input)));

    // 段数 = 分段线数 + 1，逐段各自成体。
    for (final index in const [0, 1, 2]) {
      expect(
        find.byKey(ValueKey('learning_segment_$index')),
        findsOneWidget,
        reason: '段 $index 的段体应渲染',
      );
    }
    // 填充唯一取熟练度色（缺省段 = 未练）。
    BoxDecoration boxOf(int index) => tester
        .widget<DecoratedBox>(
          find.byKey(ValueKey('learning_segment_${index}_box')),
        )
        .decoration as BoxDecoration;
    expect(boxOf(0).color, learningMasteryColor(LearningMastery.mastered));
    expect(boxOf(1).color, learningMasteryColor(LearningMastery.learning));
    expect(boxOf(2).color, learningMasteryColor(LearningMastery.unlearned));
    // 未激活段 = 默认描边；激活段 = 青色加粗整框。
    expect(boxOf(1).border!.top.color, kSegmentBoxStrokeColor);
    expect(boxOf(0).border!.top.color, kCyanAccentColor);

    // 重点星只在重点段上。
    expect(
      find.byKey(const ValueKey('learning_segment_0_emphasis')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('learning_segment_1_emphasis')),
      findsNothing,
    );

    // 激活外发光只在激活段上（层始终占位）。
    BoxDecoration glowOf(int index) => tester
        .widget<Container>(
          find.byKey(ValueKey('learning_segment_${index}_glow')),
        )
        .decoration as BoxDecoration;
    expect(glowOf(0).boxShadow, isNotEmpty);
    expect(glowOf(1).boxShadow, isEmpty);

    // 循环范围两端：单段激活自己承担两端。
    expect(
      find.byKey(const ValueKey('learning_segment_0_loop_glyph_start')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('learning_segment_0_loop_glyph_end')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('learning_segment_1_loop_glyph_start')),
      findsNothing,
    );
  });

  testWidgets('空轨形态：无分段线时不出段体、不出命中列与覆盖层', (tester) async {
    final total = const Duration(seconds: 30);
    final input = buildInput(
      timeline: timelineWith(const []),
      axis: axisFor(total),
    );
    await tester.pumpWidget(
      mount(
        Stack(
          children: [
            TrackLearningRow(input: input),
            TrackLearningLineHitLayer(input: input),
            TrackLearningRowOverlay(input: input),
          ],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('learning_segment_0')), findsNothing);
    expect(
      find.descendant(
        of: find.byType(TrackLearningLineHitLayer),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
      reason: '空轨无线段命中列',
    );
    expect(
      find.byKey(const Key('transition_segment_overlay')),
      findsNothing,
    );
  });

  testWidgets('段体交互：点按报该段序、横滑起手报该段序，不误报抬手', (tester) async {
    final total = const Duration(seconds: 30);
    final tapsDown = <int>[];
    final tapsUp = <int>[];
    final drags = <int>[];
    final input = buildInput(
      timeline: timelineWith(const [
        Duration(seconds: 10),
        Duration(seconds: 20),
      ]),
      axis: axisFor(total),
      onSegmentTapDown: tapsDown.add,
      onSegmentTapUp: (_) => tapsUp.add(1),
      onSegmentDragStart: drags.add,
    );
    await tester.pumpWidget(mount(TrackLearningRow(input: input)));

    // 点按落在哪一段就报哪一段的段序（命中解析归带级 seam，域内只按段
    // 自身身份报事件）。
    await tester.tap(find.byKey(const ValueKey('learning_segment_1')));
    await tester.pump();
    expect(tapsDown, [1]);
    expect(tapsUp, hasLength(1));

    // 横向快滑起手接管按下会话：报该段序，且不再报抬手。
    await tester.drag(
      find.byKey(const ValueKey('learning_segment_2')),
      const Offset(24, 0),
    );
    await tester.pump();
    expect(drags, [2]);
    expect(tapsUp, hasLength(1), reason: '横滑起手后不报抬手');
  });

  testWidgets('窄段仍成体：段宽不足一像素级命中盒仍报该段序', (tester) async {
    final total = const Duration(seconds: 30);
    final tapsDown = <int>[];
    final input = buildInput(
      // 段 0 = 0..0.5s（屏上约 6.7px），段 1 = 0.5..30s。
      timeline: timelineWith(const [Duration(milliseconds: 500)]),
      axis: axisFor(total),
      onSegmentTapDown: tapsDown.add,
    );
    await tester.pumpWidget(mount(TrackLearningRow(input: input)));

    expect(
      tester.getSize(find.byKey(const ValueKey('learning_segment_0'))).width,
      closeTo(6.67, 0.01),
    );
    await tester.tap(find.byKey(const ValueKey('learning_segment_0')));
    await tester.pump();
    expect(tapsDown, [0]);
  });

  testWidgets('八拍数说明按实测宽三档：全句 / 仅数字 / 隐藏', (tester) async {
    Future<void> pumpWithTotal(Duration total) async {
      final input = buildInput(
        timeline: timelineWith(
          const [Duration(seconds: 8), Duration(seconds: 16)],
          total: total,
          rangeEnd: const Duration(seconds: 24),
        ),
        axis: axisFor(total),
      );
      await tester.pumpWidget(
        mount(
          TrackLearningRow(input: input),
          overrides: [
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => uniformReadyBeatState(seconds: 600),
            ),
          ],
        ),
      );
    }

    // 段宽充裕（8s → 106.7px）：全句。
    await pumpWithTotal(const Duration(seconds: 30));
    expect(
      find.byKey(const ValueKey('learning_segment_0_eight_count_full')),
      findsOneWidget,
    );
    expect(find.text('2 个八拍'), findsWidgets);

    // 段宽只放得下数字（8s → 26.7px）：仅数字。
    await pumpWithTotal(const Duration(seconds: 120));
    expect(
      find.byKey(const ValueKey('learning_segment_0_eight_count_digits')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('learning_segment_0_eight_count_full')),
      findsNothing,
    );

    // 段宽放不下数字（8s → 10.7px）：整行隐藏。
    await pumpWithTotal(const Duration(seconds: 300));
    expect(
      find.byKey(const ValueKey('learning_segment_0_eight_count_digits')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('learning_segment_0_eight_count_full')),
      findsNothing,
    );
  });

  testWidgets('线段点按命中层：只铺窗口内的线，点按报该线下标', (tester) async {
    final total = const Duration(seconds: 30);
    final recorded = <int>[];
    final input = buildInput(
      timeline: timelineWith(const [
        Duration(seconds: 10),
        Duration(seconds: 20),
      ]),
      axis: axisFor(total),
      onSegmentLineTap: (index, _) => recorded.add(index),
    );
    await tester.pumpWidget(
      mount(TrackLearningLineHitLayer(input: input), height: 140),
    );

    // 线心 x = 10/30 × 400 ≈ 133.3；落在学习段轨行内（y = 20）。
    await tester.tapAt(const Offset(133.3, 20));
    await tester.pump();
    expect(recorded, [0]);
    await tester.tapAt(const Offset(266.7, 20));
    await tester.pump();
    expect(recorded, [0, 1]);

    // 窗口不含的线不铺命中列。
    final zoomed = buildInput(
      timeline: timelineWith(const [
        Duration(seconds: 10),
        Duration(seconds: 20),
      ]),
      axis: TimelineAxis(
        total: total,
        width: width,
        contentLeft: 0,
        window: const TimelineWindow(
          total: Duration(seconds: 30),
          start: Duration(seconds: 12),
          end: Duration(seconds: 30),
        ),
      ),
    );
    await tester.pumpWidget(
      mount(TrackLearningLineHitLayer(input: zoomed), height: 140),
    );
    expect(
      find.descendant(
        of: find.byType(TrackLearningLineHitLayer),
        matching: find.byType(GestureDetector),
      ),
      findsOneWidget,
      reason: '窗外线无命中列',
    );
  });

  testWidgets('覆盖层：有临时衔接段画青边框与两端字形，无则不画', (tester) async {
    final total = const Duration(seconds: 30);
    final input = buildInput(
      timeline: timelineWith(const [Duration(seconds: 10)]),
      axis: axisFor(total),
      transition: const TransitionSegment(
        lineIndex: 0,
        start: Duration(seconds: 10),
        end: Duration(seconds: 20),
      ),
    );
    await tester.pumpWidget(
      mount(TrackLearningRowOverlay(input: input), height: 140),
    );

    expect(find.byKey(const Key('transition_segment_overlay')), findsOneWidget);
    expect(
      find.byKey(const Key('transition_segment_loop_glyph_start')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('transition_segment_loop_glyph_end')),
      findsOneWidget,
    );

    // 无临时段：覆盖层只剩长按识别层，不画边框。
    final none = buildInput(
      timeline: timelineWith(const [Duration(seconds: 10)]),
      axis: axisFor(total),
    );
    await tester.pumpWidget(
      mount(TrackLearningRowOverlay(input: none), height: 140),
    );
    expect(find.byKey(const Key('transition_segment_overlay')), findsNothing);
  });

  testWidgets('长按识别层：准入通过才起手/逐帧/收口，准入拒绝不进 arena', (tester) async {
    final total = const Duration(seconds: 30);
    var allows = true;
    final span = _SpanRecorder();
    final input = buildInput(
      timeline: timelineWith(const [Duration(seconds: 10)]),
      axis: axisFor(total),
      dragDomain: span.domain,
      resolveSpanOrder: (_) => allows ? 0 : null,
      bandLocalAt: (globalPosition) => globalPosition,
    );
    await tester.pumpWidget(
      mount(TrackLearningRowOverlay(input: input), height: 140),
    );

    final gesture = await tester.startGesture(const Offset(50, 20));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(span.begins.single.index, 0, reason: '起手承载落点解析出的段序');
    expect(
      span.begins.single.gateTarget,
      AnnotationGestureTarget.learningTrackTap,
    );
    expect(span.moves, isNotEmpty);
    expect(span.exits, ['commit'], reason: '松手走提交路径');

    // 准入拒绝（落点解析不出可圈学习段）：识别器不进 arena，一条都不报。
    allows = false;
    final rejected = await tester.startGesture(const Offset(50, 20));
    await tester.pump(const Duration(milliseconds: 600));
    await rejected.moveBy(const Offset(30, 0));
    await tester.pump();
    await rejected.up();
    await tester.pump();
    expect(span.begins.length, 1, reason: '拒绝的落点不起手');
    expect(span.exits, ['commit']);
  });

  testWidgets('长按取消：走取消路径（回到起手前），不走提交', (tester) async {
    final total = const Duration(seconds: 30);
    final span = _SpanRecorder();
    final input = buildInput(
      timeline: timelineWith(const [Duration(seconds: 10)]),
      axis: axisFor(total),
      dragDomain: span.domain,
      resolveSpanOrder: (_) => 0,
      bandLocalAt: (globalPosition) => globalPosition,
    );
    await tester.pumpWidget(
      mount(TrackLearningRowOverlay(input: input), height: 140),
    );

    final gesture = await tester.startGesture(const Offset(50, 20));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.cancel();
    await tester.pump();
    expect(span.exits, ['cancel']);
    expect(span.moves, isEmpty);
  });

  test('说明文字量测面三档判定语义不变', () {
    const scaler = TextScaler.noScaling;
    expect(
      learningCaptionFit(
        maxWidth: 200,
        fullText: '2 个八拍',
        digitsText: '2',
        textScaler: scaler,
      ),
      LearningCaptionFit.full,
    );
    expect(
      learningCaptionFit(
        maxWidth: 30,
        fullText: '2 个八拍',
        digitsText: '2',
        textScaler: scaler,
      ),
      LearningCaptionFit.digits,
    );
    expect(
      learningCaptionFit(
        maxWidth: 5,
        fullText: '2 个八拍',
        digitsText: '2',
        textScaler: scaler,
      ),
      LearningCaptionFit.hidden,
    );
    expect(kLearningCaptionFontSize, 10);
  });
}

/// 空拖动域（未登记任何族）：起手一律为空——供不关心圈选的用例复用。
/// 单例：域输入按字段判等，两次装配要拿到同一个实例。
TrackBandDragSession? _emptyDomain;
TrackBandDragSession _emptyDragDomain() => _emptyDomain ??= TrackBandDragSession(
  families: TrackBandDragFamilies(),
  isPinchActive: () => false,
  isMixedBurstActive: () => false,
  loadGateActive: () => false,
  gestureStartRejected: (_) => false,
  promptOnReject: (_) {},
  bandWidth: () => 400,
);

/// 第十族（学习段圈选）在测试里的自家帧装配：起手、逐帧与两条收口各记一笔。
class _SpanRecorder {
  _SpanRecorder() {
    domain = TrackBandDragSession(
      families: families,
      isPinchActive: () => false,
      isMixedBurstActive: () => false,
      loadGateActive: () => false,
      gestureStartRejected: (_) => false,
      promptOnReject: (_) {},
      bandWidth: () => 400,
    );
    families.register(
      AnnotationGestureTarget.learningTrackTap,
      TrackBandDragDeclaration(
        beginFrame: (target) {
          begins.add(target);
          return TrackBandDragFrame(
            moveTo: moves.add,
            end: () => exits.add('commit'),
            cancel: () => exits.add('cancel'),
          );
        },
      ),
    );
  }

  final families = TrackBandDragFamilies();
  final begins = <TrackBandDragTarget>[];
  final moves = <Offset>[];
  final exits = <String>[];
  late final TrackBandDragSession domain;
}
