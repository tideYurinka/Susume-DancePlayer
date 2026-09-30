import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationGestureTarget, DurationDragSession;
import 'package:dance_learning_app/player/track_band_drag.dart';
import 'package:dance_learning_app/player/track_practice_row.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假模块会话：记录每一次请求，按注入的落点规则返回；收口计数。
class FakeTrimSession implements DurationDragSession {
  FakeTrimSession(this.requests, this.landing);

  final List<Duration> requests;
  final Duration? Function(Duration request) landing;
  int ends = 0;

  @override
  Duration? moveTo(Duration target) {
    requests.add(target);
    return landing(target);
  }

  @override
  void end() => ends++;
}

/// 练习片段轨域直测：直接 pump 该模块，只注它
/// 自己读的那几个 provider——不建整条带、不造标注布景。
///
/// 断言全落在外部可观察行为上：按输入渲染出的块体矩形与端点带（与搬迁前带级
/// 渲染逐项一致）；空列表与窗口不含时的退化；该行命中给出与今天同样的目标
/// （含纵带与窗口两处否决）；截取拖动经族句柄的落点回写与落点钩子（恰好一次、
/// 空落点不触发）；族声明经按族注册入口登记、越界与几何不可用时起手为空。
void main() {
  const total = Duration(seconds: 180);
  const contentLeft = 60.0;
  const trackWidth = 540.0;

  /// 与搬迁前带级几何同口径的时间轴：时间零点让出轨道片头带。
  TimelineAxis axisOf({TimelineWindow? window}) => TimelineAxis(
    total: total,
    width: trackWidth + contentLeft,
    contentLeft: contentLeft,
    window: window ?? TimelineWindow.full(total),
  );

  /// 源时间区间 = [startMs, endMs) 的片段（素材引用落在同一区间上）。
  PracticeClip clipOf(String id, int startMs, int endMs) => PracticeClip(
    id: id,
    materialId: 'mat_$id',
    materialSourceStartMs: startMs,
    inMs: 0,
    outMs: endMs - startMs,
    materialDurationMs: 180000,
  );

  /// 一次域装配：拖动域（本族注册表）+ 截取句柄 + 请求/落点记录器。
  ({
    TrackPracticeRowTrim trim,
    TrackBandDragFamilies families,
    List<Duration> requests,
  })
  harness({
    List<PracticeClip>? clips,
    Duration? Function(double localX, double bandWidth)? toTimeMs,
    Duration? Function(Duration request)? landingRule,
  }) {
    final families = TrackBandDragFamilies();
    final domain = TrackBandDragSession(
      families: families,
      isPinchActive: () => false,
      isMixedBurstActive: () => false,
      loadGateActive: () => false,
      gestureStartRejected: (_) => false,
      promptOnReject: (_) {},
      bandWidth: () => 800,
    );
    final clipList = clips ?? [clipOf('c1', 60000, 90000)];
    final requests = <Duration>[];
    final rule = landingRule ?? (Duration request) => request;
    final trim = TrackPracticeRowTrim(
      dragDomain: domain,
      toTimeMs:
          toTimeMs ??
          (localX, bandWidth) => const Duration(milliseconds: 25000),
      clips: () => clipList,
      beginSession: (target) => FakeTrimSession(requests, rule),
    )..install(families);
    return (trim: trim, families: families, requests: requests);
  }

  /// 本行的行矩形（对比行集里练习视频轨的带内顶与高）。
  final rowRect = TrackRowTable.compare.rectOf(TrackRowId.practiceVideo);

  /// 直接 pump 本模块：片段列表经输入值对象给全，不建整条带、不造标注布景。
  Future<void> pumpRow(
    WidgetTester tester, {
    required List<PracticeClip> clips,
    required TrackPracticeRowTrim trim,
    TimelineWindow? window,
    void Function(PracticeClip)? onToggle,
  }) async {
    final axis = axisOf(window: window);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: trackWidth + contentLeft,
              height: TrackRowTable.compare.totalHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: TrackPracticeRow(
                      input: TrackPracticeRowInput(
                        clips: clips,
                        rowRect: rowRect,
                        bandHeight: TrackRowTable.compare.totalHeight,
                        axis: axis,
                        playhead: () => Duration.zero,
                        onToggleClip: onToggle ?? (_) {},
                        trim: trim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('块体矩形与端点带（与搬迁前带级渲染逐项一致）', () {
    testWidgets('块体矩形 = 源区间经内容区线性映射：左右缘与宽度逐项一致', (tester) async {
      final trim = harness().trim;
      await pumpRow(tester, clips: [clipOf('c1', 60000, 90000)], trim: trim);

      final block = tester.getRect(find.byKey(const Key('practice_clip_c1')));
      expect(
        block.left,
        closeTo(contentLeft + trackWidth * 60000 / 180000, 0.5),
      );
      expect(block.width, closeTo(trackWidth * 30000 / 180000, 0.5));
      expect(block.top, rowRect.top, reason: '纵向贴合行');
      expect(block.height, rowRect.height, reason: '纵向贴合行');
    });

    testWidgets('窗口放大后块体按窗口裁切（窗口外不渲染）', (tester) async {
      final trim = harness().trim;
      await pumpRow(
        tester,
        clips: [clipOf('c1', 0, 30000), clipOf('c2', 120000, 150000)],
        trim: trim,
        window: const TimelineWindow(
          total: total,
          start: Duration(seconds: 120),
          end: Duration(seconds: 150),
        ),
      );

      expect(
        find.byKey(const Key('practice_clip_c1')),
        findsNothing,
        reason: '窗口外不渲染',
      );
      final block = tester.getRect(find.byKey(const Key('practice_clip_c2')));
      expect(block.left, closeTo(contentLeft, 0.5));
      expect(block.width, closeTo(trackWidth, 0.5));
    });

    testWidgets('端点带：宽块两端各一条，窄块整段抑制', (tester) async {
      final trim = harness().trim;
      await pumpRow(tester, clips: [clipOf('wide', 60000, 90000)], trim: trim);
      expect(
        find.byKey(const Key('practice_clip_wide_edge_start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('practice_clip_wide_edge_end')),
        findsOneWidget,
      );
      // 端点带几何：宽度 = 共用命中宽度、贴块内側两角、行高。
      final block = tester.getRect(find.byKey(const Key('practice_clip_wide')));
      final start = tester.getRect(
        find.byKey(const Key('practice_clip_wide_edge_start')),
      );
      final end = tester.getRect(
        find.byKey(const Key('practice_clip_wide_edge_end')),
      );
      expect(start.width, kLocalMirrorEdgeHitWidth);
      expect(end.width, kLocalMirrorEdgeHitWidth);
      expect(start.left, block.left, reason: '首端点带贴块内側左角');
      expect(end.right, block.right, reason: '尾端点带贴块内側右角');
      expect(start.top, rowRect.top);
      expect(start.height, rowRect.height);
      expect(end.height, rowRect.height);

      // 窄块：10 秒块宽 ≈ 30dp < 窄块阈值 40 ⇒ 端点带整段抑制。
      await pumpRow(
        tester,
        clips: [clipOf('narrow', 10000, 20000)],
        trim: trim,
      );
      expect(
        find.byKey(const Key('practice_clip_narrow_edge_start')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('practice_clip_narrow_edge_end')),
        findsNothing,
      );
    });

    testWidgets('空列表：安静返回（无块、无命中层）', (tester) async {
      final trim = harness().trim;
      await pumpRow(tester, clips: const [], trim: trim);

      expect(find.byKey(const Key('practice_clip_c1')), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  group('点按', () {
    testWidgets('块体点按：回调恰好一次、拿到的就是本片段', (tester) async {
      final trim = harness().trim;
      final toggled = <String>[];
      await pumpRow(
        tester,
        clips: [clipOf('c1', 60000, 90000)],
        trim: trim,
        onToggle: (clip) => toggled.add(clip.id),
      );

      await tester.tap(find.byKey(const Key('practice_clip_c1')));
      await tester.pump();
      expect(toggled, ['c1']);
    });

    testWidgets('端点带点按走同一条点选路径（不再是死区）', (tester) async {
      final trim = harness().trim;
      final toggled = <String>[];
      await pumpRow(
        tester,
        clips: [clipOf('c1', 60000, 90000)],
        trim: trim,
        onToggle: (clip) => toggled.add(clip.id),
      );

      await tester.tap(find.byKey(const Key('practice_clip_c1_edge_end')));
      await tester.pump();
      expect(toggled, ['c1']);
    });
  });

  group('该行命中解析（带级判定共用的同一入口）', () {
    final rowTable = TrackRowTable.compare;
    final clips = [clipOf('c1', 60000, 90000)];

    test('命中块体：返回该片段', () {
      final axis = axisOf();
      final rect = practiceClipBlockRect(clips.single, axis: axis)!;
      expect(
        practiceClipHitAtLocal(
          Offset(rect.left + 1, rowRect.top + 1),
          axis: axis,
          rowTable: rowTable,
          clips: clips,
        )?.id,
        'c1',
      );
    });

    test('右缘闭区间也算压在块上（刚停录的那一点）', () {
      final axis = axisOf();
      final rect = practiceClipBlockRect(clips.single, axis: axis)!;
      expect(
        practiceClipHitAtLocal(
          Offset(rect.left + rect.width, rowRect.top + 1),
          axis: axis,
          rowTable: rowTable,
          clips: clips,
        )?.id,
        'c1',
      );
    });

    test('纵带否决：块体 x 区间内、落在备注轨行高 = 不命中', () {
      final axis = axisOf();
      final rect = practiceClipBlockRect(clips.single, axis: axis)!;
      final noteRect = rowTable.rectOf(TrackRowId.note);
      expect(rowTable.rowAt(noteRect.top + 1), TrackRowId.note);
      expect(
        practiceClipHitAtLocal(
          Offset(rect.left + 1, noteRect.top + 1),
          axis: axis,
          rowTable: rowTable,
          clips: clips,
        ),
        isNull,
      );
    });

    test('块外 x 与空列表：安静返回空', () {
      final axis = axisOf();
      final rect = practiceClipBlockRect(clips.single, axis: axis)!;
      expect(
        practiceClipHitAtLocal(
          Offset(rect.left - 5, rowRect.top + 1),
          axis: axis,
          rowTable: rowTable,
          clips: clips,
        ),
        isNull,
      );
      expect(
        practiceClipHitAtLocal(
          Offset(rect.left + 1, rowRect.top + 1),
          axis: axis,
          rowTable: rowTable,
          clips: const [],
        ),
        isNull,
      );
    });

    test('窗口不含该块：空值（无几何可命中）', () {
      final window = TimelineWindow(
        total: total,
        start: const Duration(seconds: 120),
        end: const Duration(seconds: 150),
      );
      final axis = axisOf(window: window);
      expect(practiceClipBlockRect(clips.single, axis: axis), isNull);
      expect(
        practiceClipHitAtLocal(
          Offset(70, rowRect.top + 1),
          axis: axis,
          rowTable: rowTable,
          clips: clips,
        ),
        isNull,
      );
    });
  });

  group('截取拖动经族句柄（起手/逐帧/收口）', () {
    test('族声明经按族注册入口登记：门禁目标 = 练习片段截取，且无视觉钩子', () {
      final h = harness();
      expect(h.families.gates, [AnnotationGestureTarget.practiceClipTrim]);
      final declaration = h.families.declarationFor(
        AnnotationGestureTarget.practiceClipTrim,
      );
      expect(declaration, isNotNull);
      // 如实随迁：本族没有起手/逐帧/收口视觉钩子（与其余七族的实时预览形态
      // 刻意不对称），逐帧落点只经句柄交回。
      expect(declaration!.onBegin, isNull);
      expect(declaration.onFrame, isNull);
      expect(declaration.onEnd, isNull);
      expect(declaration.yieldOnMixedBurst, isTrue);
      expect(declaration.promptOnGateReject, isFalse);
    });

    test('起手成立后逐帧把请求交给模块会话，并交回写后真实落点', () {
      final h = harness(
        toTimeMs: (localX, bandWidth) => Duration(milliseconds: localX.round()),
        landingRule: (request) => const Duration(seconds: 72),
      );
      h.trim.begin(0, IntervalEdge.end, 100);
      expect(h.requests, isEmpty, reason: '起手本身不落点');

      // 逐帧局部 x 经域钳到带宽（800）后换算：700 +（90000 − 100）。
      expect(h.trim.update(700), const Duration(seconds: 72));
      expect(h.requests, [const Duration(milliseconds: 90600)]);

      expect(h.trim.update(800), const Duration(seconds: 72));
      expect(h.requests.length, 2, reason: '逐帧仍经同一句柄');
      h.trim.end();
    });

    test('抓取偏移：请求落点 = 换算时间 −（手指时间 − 端点时刻）', () {
      // 换算取「局部 x 即毫秒」，源区间 60000..90000。
      Duration? toTime(double localX, double bandWidth) =>
          Duration(milliseconds: localX.round());

      // 抓尾端：起手 x=100 → 手指 100，偏移 = 100 − 90000；逐帧 x=700
      // → 请求 = 700 + 90000 − 100 = 90600（尾端跟上手指）。
      final tail = harness(toTimeMs: toTime);
      tail.trim.begin(0, IntervalEdge.end, 100);
      tail.trim.update(700);
      expect(tail.requests, [const Duration(milliseconds: 90600)]);

      // 抓首端：偏移 = 100 − 60000；逐帧 x=700 → 700 + 60000 − 100。
      final head = harness(toTimeMs: toTime);
      head.trim.begin(0, IntervalEdge.start, 100);
      head.trim.update(700);
      expect(head.requests, [const Duration(milliseconds: 60600)]);
    });

    test('越界下标：静默不建会话（零请求）', () {
      final h = harness();
      h.trim.begin(3, IntervalEdge.end, 100);
      expect(h.trim.update(100), isNull);
      expect(h.requests, isEmpty);
    });

    test('收口幂等：句柄置空后逐帧与再次收口都不再动会话', () {
      final h = harness();
      h.trim.begin(0, IntervalEdge.end, 100);
      h.trim.update(100);
      h.trim.end();
      h.trim.end();
      expect(h.trim.update(300), isNull, reason: '收口后逐帧是空操作');
      expect(h.requests.length, 1);
    });

    test('落点为空（无净变化）：句柄交回空', () {
      final h = harness(landingRule: (_) => null);
      h.trim.begin(0, IntervalEdge.end, 100);
      expect(h.trim.update(100), isNull);
      expect(h.requests.length, 1);
      h.trim.end();
    });

    test('几何不可用（换算返回空）：起手即空、零请求', () {
      final h = harness(toTimeMs: (_, _) => null);
      h.trim.begin(0, IntervalEdge.end, 100);
      expect(h.requests, isEmpty);
    });
  });
}
