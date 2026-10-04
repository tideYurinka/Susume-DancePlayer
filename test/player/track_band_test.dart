import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackPhase, BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/dancer_roster_controller.dart'
    show dancerRosterControllerProvider;
import 'package:dance_learning_app/player/gestures.dart' show seekDeltaFor;
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show DelayedLoopBeats, delayedLoopProvider, prepBeatsProvider;
import 'package:dance_learning_app/player/preview_snap.dart'
    show PreviewSnapModel, previewSnapEnabledProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        annotationMemberSchemeReadonlyProvider,
        annotationCompareReadonlyProvider,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        learningEmphasisProvider,
        noteStickersProvider,
        practiceClipsProvider,
        selectedHalfBeatLineIndexProvider,
        selectedLearningSegmentRepresentativeProvider,
        selectedNoteFragmentIndexProvider,
        selectedSegmentLineIndexProvider,
        selectedVideoRangeBoundaryProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/help/content_registry.dart'
    show HandsOnCriterion;
import 'package:dance_learning_app/help/guide_state.dart'
    show guideSessionProvider;
import 'package:dance_learning_app/player/settings_cluster.dart';
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_geometry.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/player/track_time.dart';
import 'package:dance_learning_app/player/track_band_session.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/stats/selection_haptic.dart'
    show SelectionHapticController, selectionHapticProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_selection_haptic.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/pump_settle.dart';

/// 读取轨道带当前注解时间线（拖动写入经标注编辑模块进
/// provider，测试从容器读取断言，不再模拟宿主回调）。
AnnotationTimeline bandTimeline(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(TrackBand)))
        .read(annotationTimelineProvider);

/// 带内空白横滑 = 精细调整的接线由会话域提供，
/// 本文件与其余九个带内套件共用 [buildTrackBandSession] 这一份
/// 会话装配，不再各自搭同构接线。
/// 读取某学习段格框（key = `learning_segment_<i>_box`）的装饰
/// （格框渲染拆为发光层 + 格框本体，熟练度填充/描边在本体上）。
BoxDecoration learningSegmentBoxDecoration(WidgetTester tester, int index) {
  return tester
          .widget<DecoratedBox>(
            find.descendant(
              of: find.byKey(Key('learning_segment_$index')),
              matching: find.byKey(Key('learning_segment_${index}_box')),
            ),
          )
          .decoration
      as BoxDecoration;
}

/// 读取某学习段外发光层（key = `learning_segment_<i>_glow`）的装饰。
BoxDecoration learningSegmentGlowDecoration(WidgetTester tester, int index) {
  return tester
          .widget<Container>(find.byKey(Key('learning_segment_${index}_glow')))
          .decoration!
      as BoxDecoration;
}

/// 经控制柄（轨道手柄带）点击分段线（选中路径）。
Future<void> tapSegmentLineHandle(WidgetTester tester, int index) {
  return tester.tap(
    find.byKey(Key('segment_line_${index}_handle')),
    warnIfMissed: false,
  );
}

/// 拖线实时预览的 seek 目标约束：非空、逐帧目标只能是线（吸附/
/// 钳制后）位置的集合 [lineTargets] 之一（节流可丢中间目标），松手恢复
/// 点必达（末条 = Duration.zero，即测试几何下的起手定格点）。

void expectOnlyLinePreviewSeeks(
  FakePlaybackEngine engine,
  Set<Duration> lineTargets,
) {
  expect(engine.seekCalls, isNotEmpty, reason: '拖线实时预览 seek');
  expect(engine.seekCalls.last, Duration.zero, reason: '松手回起手定格点');
  for (final target in engine.seekCalls) {
    expect(
      target == Duration.zero || lineTargets.contains(target),
      isTrue,
      reason: 'seek 目标只能是线预览位置或恢复点：$target',
    );
  }
}

void main() {
  // Scaffold body 给满宽约束 → 轨道带全宽、节拍刻度按 0..total 满宽铺开。
  Future<void> pumpBand(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    AnnotationTimeline? timeline,
    TrackBandSession? session,
    TrackRowTable? rowTable,
    List<NoteSticker> notes = const [],
    VoidCallback? onCollapse,
    VoidCallback? onPreviewSnapHaptic,
    bool readyBeat = true,
    double? bandWidth,
    Set<int> emphasized = const {},
    bool compareReadonly = false,
    List<int> beatAnchors = const [],
    SelectionHapticController? selectionHaptic,
  }) async {
    // 会话域由带与设置簇共享（对应控制层的同一实例）。容器先建，
    // 使会话域的清循环落点与生产同构（越界即取消激活）。
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        // 光带流动开关在测试内强制开启——流动断言与占位形态
        // 断言共用本 harness；pumpSettle 兜住循环动画的永不收敛。
        beatAnalyzingFlowProvider.overrideWithValue(true),
        // 对比只读门禁（键盘微调被拒用例）。
        if (compareReadonly)
          annotationCompareReadonlyProvider.overrideWithValue(true),
        // 分段线落点解析在模块内消费就绪网格——缺省注入与
        // 占位网格同值的就绪态（拖动吸附期望值与旧占位格一致）。
        if (readyBeat)
          beatTrackStateProvider.overrideWithBuild((ref, _) {
            final seconds =
                (engine.duration ?? const Duration(seconds: 30))
                    .inMilliseconds /
                1000;
            return beatAnchors.isEmpty
                ? uniformReadyBeatState(seconds: seconds)
                : uniformDownbeatBeatState(
                    seconds: seconds,
                    anchors: beatAnchors,
                  );
          }),
        if (timeline != null)
          annotationTimelineProvider.overrideWithBuild((ref, _) => timeline),
        if (notes.isNotEmpty)
          noteStickersProvider.overrideWithBuild((ref, _) => notes),
        learningEmphasisProvider.overrideWithBuild((ref, _) => emphasized),
        // 圈选起手震动的注入接缝（与统计页同一 provider/fake）。
        if (selectionHaptic != null)
          selectionHapticProvider.overrideWithValue(selectionHaptic),
      ],
    );
    final bandSession =
        session ??
        buildTrackBandSession(
          engine: engine,
          timeline: timeline,
          container: container,
        );
    // 轨道带的输入值对象在本 harness 唯一构造——会话域句柄、行集
    // 与宿主动作回调一处给全；不演示自定义行集的用例用具名集 normal。
    final band = TrackBand(
      input: TrackBandInput(
        session: bandSession,
        rowTable: rowTable ?? TrackRowTable.normal,
        onCollapse: onCollapse,
        onPreviewSnapHaptic: onPreviewSnapHaptic,
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            // 设置簇迁至轨道带外右上（控制层承载）——本 harness 以
            // 同构布局（簇在带上方、共享可视窗口控制器）直接驱动 TrackBand
            // 与设置簇，保持带内交互用例与簇内控件（吸附菜单/缩放滑条/
            // 预览吸附开关/延迟循环）用例共用一套几何。
            body: Column(
              children: [
                SettingsCluster(session: bandSession),
                // bandWidth != null：按真机竖屏带宽（361.1）约束轨道带，
                // 钉判定带宽随渲染盒全宽成比例（默认 = 测试面全宽 800）；
                // 左对齐使带内局部 x = 屏上 x，与既有几何换算一致。
                if (bandWidth == null)
                  band
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: bandWidth, child: band),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await pumpSettle(tester);
  }

  /// 两段式按下即拖：拖动识别器在位移越过触摸 slop 的那次 move 才回调
  /// drag start（只触发 start 不触发 update），随后事件才逐次 update——
  /// 真实手指连续移动天然是多事件，测试里拆成两次 move 模拟。
  Future<void> dragBySteps(
    WidgetTester tester,
    TestGesture gesture,
    Offset total,
  ) async {
    await gesture.moveBy(total / 2);
    await tester.pump();
    await gesture.moveBy(total / 2);
    await tester.pump();
  }

  group('轨道带骨架结构', () {
    testWidgets('渲染备注/局部镜像/学习段/节拍/手柄带行五轨', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      expect(find.byKey(const Key('track_band')), findsOneWidget);
      expect(find.byKey(const Key('track_handle_strip_row')), findsOneWidget);
      expect(find.byKey(const Key('track_beat')), findsOneWidget);
      expect(find.byKey(const Key('track_learning')), findsOneWidget);
      // 局部镜像轨常驻显示（空轨亦显示、不隐藏）。
      expect(find.byKey(const Key('track_mirror')), findsOneWidget);
      // 备注轨 36dp 常驻显示——空轨亦占一行。
      expect(find.byKey(const Key('track_notes')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('track_notes'))).height,
        kNoteTrackRowHeight,
      );
    });

    testWidgets('自下而上 = 手柄带行(最底) → 节拍 → 学习段 → 局部镜像 → 备注(最顶)', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      final notesY = tester.getTopLeft(find.byKey(const Key('track_notes'))).dy;
      final mirrorY = tester
          .getTopLeft(find.byKey(const Key('track_mirror')))
          .dy;
      final learningY = tester
          .getTopLeft(find.byKey(const Key('track_learning')))
          .dy;
      final beatY = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      final stripRowY = tester
          .getTopLeft(find.byKey(const Key('track_handle_strip_row')))
          .dy;
      expect(notesY, lessThan(mirrorY));
      expect(mirrorY, lessThan(learningY));
      expect(learningY, lessThan(beatY));
      expect(beatY, lessThan(stripRowY));
    });

    testWidgets('每轨高度符合几何表：局部镜像 / 学习段 / 节拍 / 手柄带行 + 轨间隔', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      // 行高问行表（矩形的高），不再直读行几何常量。
      expect(
        tester.getSize(find.byKey(const Key('track_mirror'))).height,
        TrackRowTable.normal.rectOf(TrackRowId.localMirror).height,
      );
      expect(
        tester.getSize(find.byKey(const Key('track_learning'))).height,
        TrackRowTable.normal.rectOf(TrackRowId.learning).height,
      );
      expect(
        tester.getSize(find.byKey(const Key('track_beat'))).height,
        TrackRowTable.normal.rectOf(TrackRowId.beat).height,
      );
      expect(
        tester.getSize(find.byKey(const Key('track_handle_strip_row'))).height,
        TrackRowTable.normal.rectOf(TrackRowId.handleStrip).height,
      );
      expect(
        tester.getSize(find.byKey(const Key('track_band'))).height,
        // 整带高 = 本用例传进去的那份行集的派生值（≈ 屏高 33%）。
        TrackRowTable.normal.totalHeight,
      );
    });
  });

  group('轨道带行集', () {
    testWidgets('传自定义行集时行数与行序随之改变，整带高由行集派生', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      // 自定义两行集（节拍轨在上、学习段轨在下），行高与间隙均异于 normal。
      const custom = TrackRowTable(
        rows: [
          TrackRow(
            id: TrackRowId.beat,
            height: 20,
            key: 'track_beat',
            prefixLabel: '节拍',
          ),
          TrackRow(
            id: TrackRowId.learning,
            height: 40,
            key: 'track_learning',
            prefixLabel: '分段',
          ),
        ],
        gap: 6,
      );
      await pumpBand(tester, engine: engine, rowTable: custom);

      expect(find.byKey(const Key('track_beat')), findsOneWidget);
      expect(find.byKey(const Key('track_learning')), findsOneWidget);
      // 行集没声明的行不渲染。
      expect(find.byKey(const Key('track_mirror')), findsNothing);
      expect(find.byKey(const Key('track_handle_strip_row')), findsNothing);
      // 行序随行集：节拍轨在学习段轨之上。
      final beatY = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      final learningY = tester
          .getTopLeft(find.byKey(const Key('track_learning')))
          .dy;
      expect(beatY, lessThan(learningY));
      // 逐行高随行集。
      expect(tester.getSize(find.byKey(const Key('track_beat'))).height, 20);
      expect(
        tester.getSize(find.byKey(const Key('track_learning'))).height,
        40,
      );
      // 整带高 = Σ行高 + 间隙 × (行数 − 1) = 20 + 6 + 40（worked example）。
      expect(tester.getSize(find.byKey(const Key('track_band'))).height, 66);
    });

    testWidgets('交叉断言：渲染行矩形与行表逐位相等，整带高与行表派生一致', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      // 派生值 ↔ 实际渲染：整带矩形高 == 行表派生的整带高；四个行键的
      // 实测矩形与行表给出的矩形逐位相等——表与实际布局不许分家。
      const table = TrackRowTable.normal;
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      expect(bandRect.height, table.totalHeight);
      for (final row in table.rows) {
        final rendered = trackRowRect(tester, row.key);
        final expected = table.rectOf(row.id);
        expect(
          rendered.top - bandRect.top,
          expected.top,
          reason: '${row.key} 行顶',
        );
        expect(rendered.height, expected.height, reason: '${row.key} 行高');
      }
    });

    testWidgets('缺省行集渲染 normal 五行，整带高随备注轨行高派生', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      expect(find.byKey(const Key('track_notes')), findsOneWidget);
      expect(find.byKey(const Key('track_mirror')), findsOneWidget);
      expect(find.byKey(const Key('track_learning')), findsOneWidget);
      expect(find.byKey(const Key('track_beat')), findsOneWidget);
      expect(find.byKey(const Key('track_handle_strip_row')), findsOneWidget);
      // 36 + 30 + 48 + 24 + 30 + 10 × 4（worked example）：表自身的整带高
      // 与渲染出来的带宽同值。
      expect(TrackRowTable.normal.totalHeight, 208);
      expect(
        tester.getSize(find.byKey(const Key('track_band'))).height,
        TrackRowTable.normal.totalHeight,
      );
    });
  });

  group('对比行集', () {
    const total = Duration(minutes: 3);

    testWidgets('行序 = 备注轨(最顶、36dp) → 练习视频轨(常驻空行 48dp) → 学习段 → 节拍；'
        '无局部镜像轨、无轨道手柄带行；整带高 186', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);

      // 练习视频轨常驻空行（该轨不承载片段，空轨亦显示）。
      expect(find.byKey(const Key('track_practice')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('track_practice'))).height,
        48,
      );
      // 无局部镜像轨、无轨道手柄带行。
      expect(find.byKey(const Key('track_mirror')), findsNothing);
      expect(find.byKey(const Key('track_handle_strip_row')), findsNothing);
      // 行序：备注轨在最顶、练习视频轨在其下（自下而上 = 节拍 → 学习段 →
      // 练习视频 → 备注，与编辑态同一条带）。
      final practiceY = tester
          .getTopLeft(find.byKey(const Key('track_practice')))
          .dy;
      final notesY = tester.getTopLeft(find.byKey(const Key('track_notes'))).dy;
      final learningY = tester
          .getTopLeft(find.byKey(const Key('track_learning')))
          .dy;
      final beatY = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      expect(notesY, lessThan(practiceY));
      expect(practiceY, lessThan(learningY));
      expect(learningY, lessThan(beatY));
      // 整带高 = 48+36+48+24 + 10×3（worked example）。
      expect(
        tester.getSize(find.byKey(const Key('track_band'))).height,
        TrackRowTable.compare.totalHeight,
      );
    });

    testWidgets('跨面一致性：渲染行 == 对比行集声明逐位相等', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);

      const table = TrackRowTable.compare;
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      expect(bandRect.height, table.totalHeight);
      for (final row in table.rows) {
        final rendered = trackRowRect(tester, row.key);
        final expected = table.rectOf(row.id);
        expect(
          rendered.top - bandRect.top,
          expected.top,
          reason: '${row.key} 行顶',
        );
        expect(rendered.height, expected.height, reason: '${row.key} 行高');
      }
    });

    testWidgets('分段线全带可见、半拍线节拍轨行内可见、预览条照常', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        rowTable: TrackRowTable.compare,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 30))],
          halfBeatLines: const [HalfBeatLine(position: Duration(seconds: 20))],
        ),
      );

      // 分段线贯穿整带（高 == 整带高）。
      final segmentLine = tester.getRect(
        find.byKey(const Key('segment_line_0')),
      );
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      expect(segmentLine.height, bandRect.height);
      expect(segmentLine.top, bandRect.top);
      // 半拍线命中列只在节拍轨行内（顶与高 == 行矩形）。
      final beatRect = tester.getRect(find.byKey(const Key('track_beat')));
      final halfBeatHit = tester.getRect(
        find.byKey(const Key('half_beat_line_hit_0')),
      );
      expect(halfBeatHit.top, beatRect.top);
      expect(halfBeatHit.height, beatRect.height);
      // 预览条照常渲染。
      expect(find.byKey(const Key('preview_line')), findsOneWidget);
    });

    testWidgets('首尾线不渲染、控制柄不渲染；备注轨空白横滑走精细调整、'
        '松手保持暂停查看', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        rowTable: TrackRowTable.compare,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 20),
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
      );

      // 首尾线与其控制柄都不渲染。
      expect(find.byKey(const Key('video_range_start_line')), findsNothing);
      expect(find.byKey(const Key('video_range_end_line')), findsNothing);
      expect(find.byKey(const Key('segment_line_0_handle')), findsNothing);

      // 备注轨空白横滑走精细调整（对比行集同样成立）：首段 move 为识别
      // 器起手（无 update 帧），后 3 段累计 75px × 50ms = 3.75s，自 0 基准
      // 落在有效区间（10..20s）外——全程未播，松手保持暂停查看态。
      final y = trackRowCenterY(tester, 'track_notes');
      final g = await tester.startGesture(Offset(200, y));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls, isNotEmpty);
      expect(engine.seekCalls.last, const Duration(milliseconds: 3750));
      expect(engine.isPlaying, isFalse);
    });
  });

  group('轨道带几何消费', () {
    testWidgets('行集把手柄带行放在非最底行时，控制柄命中区随行矩形而非贴带底', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      // 手柄带行在最顶、节拍轨垫底的自定义行集：控制柄命中区必须跟行
      // 矩形（顶 0、高 30）——非缺省行集可把手柄带行放在带内任意位置。
      const custom = TrackRowTable(
        rows: [
          TrackRow(
            id: TrackRowId.handleStrip,
            height: 30,
            key: 'track_handle_strip_row',
            prefixLabel: '控制',
          ),
          TrackRow(
            id: TrackRowId.beat,
            height: 24,
            key: 'track_beat',
            prefixLabel: '节拍',
          ),
        ],
        gap: 10,
      );
      await pumpBand(
        tester,
        engine: engine,
        rowTable: custom,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          segmentLines: const [SegmentLine(position: Duration(seconds: 30))],
        ),
      );

      final stripRect = tester.getRect(
        find.byKey(const Key('track_handle_strip_row')),
      );
      // 命中区 = 控制柄视觉条（bottom:8 行内装饰）外层的 Listener 槽位，
      // 即手势真正落点的区域。
      final handleHitArea = find
          .ancestor(
            of: find.byKey(const Key('segment_line_0_handle')),
            matching: find.byType(Listener),
          )
          .first;
      final handleRect = tester.getRect(handleHitArea);
      // 命中区顶 = 行矩形顶、高 = 行高（整带高 30 + 10 + 24 = 64）。
      expect(handleRect.top, stripRect.top);
      expect(handleRect.height, stripRect.height);
    });
  });

  group('交叉断言：模块几何 vs 实际渲染像素', () {
    testWidgets('节拍刻度实测位置与学习段格框实测矩形 = TrackBandGeometry 求值', (tester) async {
      const total = Duration(minutes: 3);
      // 非全宽窗口（可视 60s..90s）：模块换算不是恒等映射，交叉断言才有
      // 区分度；学习段横跨窗口左右缘，同时钉住窗口裁剪。
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      final engine = FakePlaybackEngine(duration: total);
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 65)),
            SegmentLine(position: Duration(seconds: 75)),
          ],
        ),
      );
      session.updateWindow(win);
      await pumpSettle(tester);

      // 模块几何 = 带实测宽下由同一窗口/总时长求值（不读控件内部轴）；
      // 内容区左缘让出轨道片头带，模块与渲染同一口径。
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      final geometry = bandGeometryOf(
        total: total,
        window: win,
        width: bandRect.width,
      );

      // 期望三条以内：① 刻度位置、② 段左缘、③ 段宽——每条
      // 把整组实测值与模块求值逐项对上。
      // ① 刻度实际渲染位置：八拍大线（0.5s 拍距、每 8 拍 → t=60、64…s）
      // 实测中心相对带左缘 == 模块 timeToPixel；t=60 恰在窗口左缘（被
      // 裁剪钉住的位置）。
      const tickTimes = [
        Duration(seconds: 60),
        Duration(seconds: 64),
        Duration(seconds: 72),
        Duration(seconds: 88),
      ];
      expect(
        [
          for (final time in tickTimes)
            tester
                    .getRect(
                      find.byKey(ValueKey('beat_tick_${time.inMicroseconds}')),
                    )
                    .center
                    .dx -
                bandRect.left,
        ],
        [for (final t in tickTimes) closeTo(geometry.timeToPixel(t), 0.01)],
        reason: '刻度实际渲染位置与模块几何一致',
      );

      // ②③ 学习段格框：实测矩形（左缘、宽）== 模块换算的段矩形——窗口
      // 外裁剪到带内也与模块钳制一致（首段裁左缘、末段裁右缘）。
      final visible = deriveLearningSegments(bandTimeline(tester))
          .where((s) => s.end > win.start && s.start < win.end)
          .toList();
      expect(
        [
          for (final segment in visible)
            tester
                    .getRect(
                      find.byKey(Key('learning_segment_${segment.order}')),
                    )
                    .left -
                bandRect.left,
        ],
        [for (final s in visible) closeTo(geometry.timeToPixel(s.start), 0.01)],
        reason: '学习段左缘与模块几何一致',
      );
      expect(
        [
          for (final segment in visible)
            tester
                .getRect(find.byKey(Key('learning_segment_${segment.order}')))
                .width,
        ],
        [
          for (final s in visible)
            closeTo(
              geometry.timeToPixel(s.end) - geometry.timeToPixel(s.start),
              0.01,
            ),
        ],
        reason: '学习段宽与模块几何一致',
      );
    });
  });

  group('节拍轨三态', () {
    // 占位态注入（默认节拍轨状态模型即占位，不需要覆盖 provider）。

    testWidgets('占位态：整行不定态进度条 +「节拍分析中……」，无任何刻度标记', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);

      expect(find.byKey(const Key('beat_track_placeholder')), findsOneWidget);
      expect(find.text('节拍分析中……'), findsOneWidget);
      expect(find.byKey(const Key('beat_track_shimmer')), findsOneWidget);
      // 不画任何均匀占位刻度（含 0 拍点在内全轨无 beat_tick_*）。
      expect(find.byKey(const Key('beat_tick_0')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('track_beat')),
          matching: find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey &&
                (w.key as ValueKey).value.toString().startsWith('beat_tick_'),
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('占位态光带持续流动：两帧之间带体位置前进（不定态，非静止）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);

      final before = tester.getTopLeft(
        find.byKey(const Key('beat_track_shimmer')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final after = tester.getTopLeft(
        find.byKey(const Key('beat_track_shimmer')),
      );

      expect(after.dx, greaterThan(before.dx));
    });

    testWidgets('占位态光带流动只做平移：帧间槽位不动（不触发整行重新布局）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);

      final shimmer = find.byKey(const Key('beat_track_shimmer'));
      // 槽位 = 布局期定位（parentData 偏移）；绘制位移不进这里。
      Offset slotOffset() =>
          (tester.renderObject<RenderBox>(shimmer).parentData! as BoxParentData)
              .offset;

      final beforeSlot = slotOffset();
      final beforePaint = tester.getTopLeft(shimmer);
      await tester.pump(const Duration(milliseconds: 300));

      expect(slotOffset(), beforeSlot, reason: '动画只做绘制平移，槽位纹丝不动');
      // 位移速率 = 旧「每帧改对齐值」口径（整周期 1600ms 走满 1.68 倍行宽，
      // 即带体从左出视口到右出视口）：动画外观逐位不变。
      final rowWidth = tester.getSize(shimmer).width / 0.4;
      expect(
        tester.getTopLeft(shimmer).dx - beforePaint.dx,
        moreOrLessEquals(1.68 * rowWidth * 300 / 1600),
        reason: '带体照常前进且速率不变（流动外观不变）',
      );
    });

    testWidgets('占位态语义标签「节拍分析中」，不带百分比语义', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);

      final handle = tester.getSemantics(
        find.byKey(const Key('beat_track_placeholder')),
      );
      expect(handle.label, contains('节拍分析中'));
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('％'), findsNothing);
    });

    testWidgets('占位态不可点：点击整行不产生任何状态变化', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);

      await tester.tap(
        find.byKey(const Key('track_beat')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('track_beat'))),
      );
      expect(
        container.read(beatTrackStateProvider).phase,
        BeatTrackPhase.placeholder,
      );
      // 无弹层/无选中反馈出现。
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('就绪交接：占位 → 就绪直接换真实刻度，无「分析完成」过渡', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);

      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('track_beat'))),
      );
      container
          .read(beatTrackStateProvider.notifier)
          .replace(uniformReadyBeatState(seconds: 30));
      await pumpSettle(tester);

      expect(find.byKey(const Key('beat_track_placeholder')), findsNothing);
      expect(find.text('节拍分析中……'), findsNothing);
      expect(find.textContaining('分析完成'), findsNothing);
      // 真实三级刻度出现（0.5s 拍距、强拍每 4 拍 → 大线 t=0）。
      expect(find.byKey(const Key('beat_tick_0')), findsOneWidget);
    });

    testWidgets('异常态：整行暖色底 +「节拍识别失败」，无任何刻度', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);
      ProviderScope.containerOf(
            tester.element(find.byKey(const Key('track_beat'))),
          )
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pump(const Duration(milliseconds: 100));

      final failed = find.byKey(const Key('beat_track_failed'));
      expect(failed, findsOneWidget);
      expect(find.text('节拍识别失败'), findsOneWidget);
      expect(find.byKey(const Key('beat_tick_0')), findsNothing);
      // 整行暖色底：行体装饰色为暖色（红分量显著高于蓝分量）。
      final box = tester.widget<ColoredBox>(
        find.descendant(of: failed, matching: find.byType(ColoredBox)),
      );
      final color = box.color;
      expect(color.r, greaterThan(color.b));
      expect(color.g, lessThan(color.r));
    });

    testWidgets('异常态语义标签「节拍识别失败」，不带百分比语义', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);
      ProviderScope.containerOf(
            tester.element(find.byKey(const Key('track_beat'))),
          )
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pump(const Duration(milliseconds: 100));

      final handle = tester.getSemantics(
        find.byKey(const Key('beat_track_failed')),
      );
      expect(handle.label, contains('节拍识别失败'));
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('异常态不可点：点击整行不产生任何状态变化', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine, readyBeat: false);
      ProviderScope.containerOf(
            tester.element(find.byKey(const Key('track_beat'))),
          )
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(
        find.byKey(const Key('track_beat')),
        warnIfMissed: false,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        ProviderScope.containerOf(
          tester.element(find.byKey(const Key('track_beat'))),
        ).read(beatTrackStateProvider).phase,
        BeatTrackPhase.error,
      );
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('节拍轨三级刻度：均匀网格（经就绪态注入）', () {
    // 占位均匀网格 @120bpm：一拍 0.5s，downbeat 每 4 拍（2s），
    // 八拍区间 8 拍（4s）。
    double tickWidth(WidgetTester tester, Key key) =>
        tester.getSize(find.byKey(key)).width;

    Color tickColor(WidgetTester tester, Key key) => tester
        .widget<ColoredBox>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(ColoredBox),
          ),
        )
        .color;

    /// 刻度是否在让位列内垂直居中：三级刻度共用同一中心 y，
    /// 且该中心位于标注槽（行顶 10px）下方。
    bool verticallyCentered(WidgetTester tester, Key key) {
      final bandTop = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      final centers = [
        const Key('beat_tick_0'),
        const Key('beat_tick_2000000'),
        const Key('beat_tick_500000'),
      ].map((k) => tester.getCenter(find.byKey(k)).dy).toList();
      if (centers.any((y) => (y - centers.first).abs() >= 0.5)) return false;
      return centers.first > bandTop + kEightCountLabelSlotHeight;
    }

    testWidgets('刻度宽按层级：八拍大线 1.5px、中/小线 1px，透明度分级不变', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine);

      // 八拍大线 1.5px；四拍中线/一拍小线仍 1px；仅透明度递减：0.95 > 0.62 > 0.34。
      expect(tickWidth(tester, const Key('beat_tick_0')), 1.5);
      expect(tickWidth(tester, const Key('beat_tick_2000000')), 1.0);
      expect(tickWidth(tester, const Key('beat_tick_500000')), 1.0);
      expect(tickColor(tester, const Key('beat_tick_0')).a, 0.95);
      expect(tickColor(tester, const Key('beat_tick_2000000')).a, 0.62);
      expect(tickColor(tester, const Key('beat_tick_500000')).a, 0.34);
    });

    testWidgets('刻度垂直居中；八拍大线最长、一拍小线最短', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine);

      for (final key in [
        const Key('beat_tick_0'),
        const Key('beat_tick_2000000'),
        const Key('beat_tick_500000'),
      ]) {
        expect(verticallyCentered(tester, key), isTrue);
      }
      final eight = tester.getSize(find.byKey(const Key('beat_tick_0'))).height;
      final four = tester
          .getSize(find.byKey(const Key('beat_tick_2000000')))
          .height;
      final beat = tester
          .getSize(find.byKey(const Key('beat_tick_500000')))
          .height;
      // 让位后三级刻度长度精确为 11 / 8 / 5（分级不变）。
      expect(eight, 11.0);
      expect(four, 8.0);
      expect(beat, 5.0);
      expect(eight, greaterThan(four));
      expect(four, greaterThan(beat));
    });

    testWidgets('不显示半拍刻度线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(tester, engine: engine);

      expect(find.byKey(const Key('beat_tick_250000')), findsNothing);
      expect(find.byKey(const Key('beat_tick_750000')), findsNothing);
    });
  });

  group('节拍轨八拍数标注', () {
    // 就绪真实网格：0.5s 均匀拍点、downbeat 每 4 拍 → 八拍大线 t=0、4、8…s。
    Future<void> pumpReadyBand(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
      AnnotationTimeline? timeline,
      List<int> anchors = const [],
    }) async {
      final count = engine.duration!.inMilliseconds ~/ 500 + 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            if (timeline != null)
              annotationTimelineProvider.overrideWithBuild(
                (ref, _) => timeline,
              ),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  anchors: anchors,
                  beats: [
                    for (var i = 0; i < count; i++)
                      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
    }

    testWidgets('就绪网格：八拍数按学习段段内相对编号（段首 = 1、跨段重数、同位不标）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // 分段线 t=16 → 段 [0,16] 与 [16,30]；段首大线（t=0 首线、t=16
      // 分段线）不标但各占序号 1。
      await pumpReadyBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [SegmentLine(position: Duration(seconds: 16))],
        ),
      );

      // 段一：t=4 → 2、t=8 → 3、t=12 → 4；段二跨段重数：t=20 → 2、
      // t=24 → 3、t=28 → 4。
      for (final entry in {
        const Duration(seconds: 4): '2',
        const Duration(seconds: 8): '3',
        const Duration(seconds: 12): '4',
        const Duration(seconds: 20): '2',
        const Duration(seconds: 24): '3',
        const Duration(seconds: 28): '4',
      }.entries) {
        final label = find.byKey(Key('beat_count_${entry.key.inMicroseconds}'));
        expect(label, findsOneWidget, reason: 't=${entry.key} 缺标注');
        expect(
          tester
              .widget<Text>(
                find.descendant(of: label, matching: find.byType(Text)),
              )
              .data,
          entry.value,
          reason: 't=${entry.key} 序号错',
        );
        // 标注与大线同 x（刻度上方）；且位于节拍轨行内上半部。
        final labelX = tester.getCenter(label).dx;
        final tickX = tester
            .getCenter(find.byKey(Key('beat_tick_${entry.key.inMicroseconds}')))
            .dx;
        expect((labelX - tickX).abs(), lessThan(1.0));
        expect(
          tester.getCenter(label).dy,
          lessThan(trackRowCenterY(tester, 'track_beat')),
        );
      }
      // 段首同位大线（t=0 首线、t=16 分段线）不标。
      for (final t in const [Duration(seconds: 0), Duration(seconds: 16)]) {
        expect(find.byKey(Key('beat_count_${t.inMicroseconds}')), findsNothing);
      }
    });

    testWidgets('八拍数小数字与所在大线水平居中（含 textScale 1.3）', (tester) async {
      // 真机观察到数字偏左：OverflowBox 缺省继承入射 minWidth（= 槽宽），
      // Text 被拉宽到整槽、按 textAlign 左排。断言钉**文字自身**（RenderParagraph，
      // 非定宽槽）的中心 == 大线 x，含放大字号档。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpReadyBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [SegmentLine(position: Duration(seconds: 16))],
        ),
      );

      for (final t in const [
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 12),
        Duration(seconds: 20),
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find
              .descendant(
                of: find.byKey(Key('beat_count_${t.inMicroseconds}')),
                matching: find.byType(Text),
              )
              .first,
        );
        final textCenter =
            (paragraph.localToGlobal(Offset.zero) & paragraph.size).center.dx;
        final tickCenter = tester
            .getCenter(find.byKey(Key('beat_tick_${t.inMicroseconds}')))
            .dx;
        expect(
          (textCenter - tickCenter).abs(),
          lessThan(0.5),
          reason: 't=$t 的八拍数小数字应水平居中于大线',
        );
      }
    });

    testWidgets('锚点视觉仅待命态：非待命态完全不画锚点；待命态第二色大线 + '
        '轨顶圆点 + 该处让位不显示八拍数小数字', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      // 锚点拍 16（t=8s，八拍大线）；分段线 t=16。
      await pumpReadyBand(
        tester,
        engine: engine,
        anchors: const [16],
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [SegmentLine(position: Duration(seconds: 16))],
        ),
      );
      final markerKey = const ValueKey('beat_anchor_marker_8000000');
      Color tickColor(Key key) => tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;

      // 非待命态：与完全无锚点渲染一致——无轨顶标记、大线白色、八拍数照常。
      expect(find.byKey(markerKey), findsNothing);
      expect(tickColor(const Key('beat_tick_8000000')).a, 0.95);
      expect(
        tickColor(const Key('beat_tick_8000000')),
        isNot(kBeatAnchorLineColor),
      );
      expect(find.byKey(const Key('beat_count_8000000')), findsOneWidget);

      // 进入待命态：第二色大线 + 轨顶圆点出现，锚点处八拍数小数字让位。
      ProviderScope.containerOf(tester.element(find.byType(TrackBand)))
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.beatCorrectionStandby);
      await pumpSettle(tester);

      expect(find.byKey(markerKey), findsOneWidget);
      expect(tickColor(const Key('beat_tick_8000000')), kBeatAnchorLineColor);
      expect(find.byKey(const Key('beat_count_8000000')), findsNothing);
      // 让位不占号口径（与既有同位大线一致）：其余大线序号连续不重排——
      // 段一 t=8 让位（占序号 3）、段二 t=24 仍为序号 3。
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('beat_count_24000000')),
                matching: find.byType(Text),
              ),
            )
            .data,
        '3',
      );
    });

    testWidgets('数字底缘与大线顶端留间隙、不重叠', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpReadyBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [SegmentLine(position: Duration(seconds: 16))],
        ),
      );

      final bandTop = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      for (final t in const [
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 12),
      ]) {
        final labelRect = tester.getRect(
          find.byKey(Key('beat_count_${t.inMicroseconds}')),
        );
        final tickRect = tester.getRect(
          find.byKey(Key('beat_tick_${t.inMicroseconds}')),
        );
        // 标注槽位于行顶；八拍大线顶端在数字底缘之下、留正间隙。
        expect(labelRect.top, bandTop);
        expect(
          tickRect.top - labelRect.bottom,
          greaterThanOrEqualTo(1.0),
          reason: 't=$t 标注与大线重叠',
        );
      }
    });

    testWidgets('占位网格不标注', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      expect(
        find.descendant(
          of: find.byKey(const Key('track_beat')),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
    });

    testWidgets('就绪但整窗最小屏距不足 40px：八拍数全部不显示（严格两档）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpReadyBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          segmentLines: const [SegmentLine(position: Duration(seconds: 90))],
        ),
      );
      // 全宽 3 分钟 / ~800px：相邻八拍大线间距 ≈ 17.8px < 40 → 整窗一次
      // 判定全部不标（取代「隔一个放一个」的逐点贪心抽稀）。
      expect(
        find.descendant(
          of: find.byKey(const Key('track_beat')),
          matching: find.byWidgetPredicate(
            (w) => w is Text && int.tryParse(w.data ?? '') != null,
          ),
        ),
        findsNothing,
      );
    });
  });

  group('学习段内八拍数与重点星标', () {
    final total = const Duration(seconds: 30);

    // 与 组同几何的就绪真实网格：0.5s 均匀拍点、每 4 拍一个
    // downbeat → 八拍大线在 t = 0、4、8…s。
    Future<void> pumpReadyBandWithSegments(
      WidgetTester tester, {
      required List<Duration> segmentLines,
      Set<int> emphasized = const {},
      List<int> anchors = const [],
    }) async {
      final engine = FakePlaybackEngine(duration: total);
      final count = total.inMilliseconds ~/ 500 + 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.normalized(
                videoDuration: total,
                segmentLines: [
                  for (final position in segmentLines)
                    SegmentLine(position: position),
                ],
              ),
            ),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  anchors: anchors,
                  beats: [
                    for (var i = 0; i < count; i++)
                      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
                  ],
                ),
              ),
            ),
            learningEmphasisProvider.overrideWithBuild((ref, _) => emphasized),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
    }

    testWidgets('就绪网格且段长整八拍：段内居中淡字「N 个八拍」，N 按大线计数', (tester) async {
      // 线 t=8、16 → 段 [0,8]=2、[8,16]=2、[16,30] 尾非整点。
      await pumpReadyBandWithSegments(
        tester,
        segmentLines: [const Duration(seconds: 8), const Duration(seconds: 16)],
      );

      expect(find.text('2 个八拍'), findsNWidgets(2));
      expect(find.text('4 个八拍'), findsNothing);

      final seg = tester.getRect(find.byKey(const Key('learning_segment_0')));
      final label = tester.getCenter(
        find.byKey(const Key('learning_segment_0_eight_count_full')),
      );
      expect((label.dx - seg.center.dx).abs(), lessThan(1.0));
      expect((label.dy - seg.center.dy).abs(), lessThan(1.0));
    });

    testWidgets('半八拍段按 0.5 分度显示：「2.5 个八拍」与「5 个八拍」', (tester) async {
      // 锚点第 12 拍（t=6s）：八拍点 = 0 / 4 / 6 / 10 / 14…s；线 t=10s →
      // 段 [0,10] 权重 = 1 + 0.5 + 1 = 2.5、段 [10,30] = 5 个整八拍区间。
      await pumpReadyBandWithSegments(
        tester,
        segmentLines: [const Duration(seconds: 10)],
        anchors: const [12],
      );

      expect(find.text('2.5 个八拍'), findsOneWidget);
      expect(find.text('5 个八拍'), findsOneWidget);
      // 整数不带小数位：段内值 5 不显示为「5.0」。
      expect(find.text('5.0 个八拍'), findsNothing);
    });

    testWidgets('窄段退化为仅数字：半八拍值显示「2.5」不带全句', (tester) async {
      // 120s 视频、线 t=10s → 段 [0,10] 可用宽 ≈ 800 × 10/120 − 4 ≈ 62.7px：
      // 全句「2.5 个八拍」8 字形 × 10 = 80px 放不下，数字「2.5」30px 放得下。
      const long = Duration(seconds: 120);
      final engine = FakePlaybackEngine(duration: long);
      final count = long.inMilliseconds ~/ 500 + 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.normalized(
                videoDuration: long,
                segmentLines: const [
                  SegmentLine(position: Duration(seconds: 10)),
                ],
              ),
            ),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  anchors: const [12],
                  beats: [
                    for (var i = 0; i < count; i++)
                      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('learning_segment_0_eight_count_digits')),
            )
            .data,
        '2.5',
      );
      expect(find.text('2.5 个八拍'), findsNothing);
    });

    testWidgets('段首/段尾非八拍整点（旧数据）不显示该数字', (tester) async {
      // 线 t=5、16 → 段 [0,5] 首尾均非整点、[5,16] 首非整点、[16,30] 尾非整点。
      await pumpReadyBandWithSegments(
        tester,
        segmentLines: [const Duration(seconds: 5), const Duration(seconds: 16)],
      );

      expect(find.textContaining('个八拍'), findsNothing);
    });

    testWidgets('占位网格不显示该数字', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        readyBeat: false,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 8)),
            SegmentLine(position: Duration(seconds: 16)),
          ],
        ),
      );

      expect(find.textContaining('个八拍'), findsNothing);
    });

    testWidgets('重点星标位于段体左上角，与居中数字不重叠', (tester) async {
      await pumpReadyBandWithSegments(
        tester,
        segmentLines: [const Duration(seconds: 8), const Duration(seconds: 16)],
        emphasized: {0},
      );

      final seg = tester.getRect(find.byKey(const Key('learning_segment_0')));
      final star = tester.getCenter(
        find.byKey(const Key('learning_segment_0_emphasis')),
      );
      expect(star.dx, lessThan(seg.left + seg.width / 4));
      expect(star.dy, lessThan(seg.top + seg.height / 3));
      final label = tester.getCenter(
        find.byKey(const Key('learning_segment_0_eight_count_full')),
      );
      expect((label.dx - star.dx).abs(), greaterThan(1.0));
    });
  });

  group('学习段说明缩字', () {
    // 纯函数 seam：给定可用宽与文案返回 全句/仅数字/空。flutter_test 默认
    // Ahem 字体每字形宽 = fontSize，宽度按字形数可直接推算（独立基准）。
    group('seam：文本宽三级选择', () {
      // 全句 6 字形 × 10 = 60；数字 2 字形 × 10 = 20。
      const full = '12 个八拍';
      const digits = '12';
      const scaler = TextScaler.noScaling;

      test('可用宽放得下全句：显示全句', () {
        expect(
          learningCaptionFit(
            maxWidth: 60,
            fullText: full,
            digitsText: digits,
            textScaler: scaler,
          ),
          LearningCaptionFit.full,
        );
        expect(
          learningCaptionFit(
            maxWidth: 60.5,
            fullText: full,
            digitsText: digits,
            textScaler: scaler,
          ),
          LearningCaptionFit.full,
        );
      });

      test('放不下全句但放得下数字：仅数字', () {
        expect(
          learningCaptionFit(
            maxWidth: 59.9,
            fullText: full,
            digitsText: digits,
            textScaler: scaler,
          ),
          LearningCaptionFit.digits,
        );
        expect(
          learningCaptionFit(
            maxWidth: 20,
            fullText: full,
            digitsText: digits,
            textScaler: scaler,
          ),
          LearningCaptionFit.digits,
        );
      });

      test('数字也放不下：整行隐藏', () {
        expect(
          learningCaptionFit(
            maxWidth: 19.9,
            fullText: full,
            digitsText: digits,
            textScaler: scaler,
          ),
          LearningCaptionFit.hidden,
        );
        expect(
          learningCaptionFit(
            maxWidth: 0,
            fullText: full,
            digitsText: digits,
            textScaler: scaler,
          ),
          LearningCaptionFit.hidden,
        );
      });

      test('量测侧吃传入的缩放值：1.3× 下判定按缩放后实测宽', () {
        // 全句 6 字形 × 10 × 1.3 = 78px、数字 2 × 10 × 1.3 = 26px。
        const big = TextScaler.linear(1.3);
        expect(
          learningCaptionFit(
            maxWidth: 77.9,
            fullText: full,
            digitsText: digits,
            textScaler: big,
          ),
          LearningCaptionFit.digits,
          reason: '缩放值参与量测：判定按放大后的实测宽降级',
        );
        expect(
          learningCaptionFit(
            maxWidth: 26,
            fullText: full,
            digitsText: digits,
            textScaler: big,
          ),
          LearningCaptionFit.digits,
        );
        expect(
          learningCaptionFit(
            maxWidth: 25.9,
            fullText: full,
            digitsText: digits,
            textScaler: big,
          ),
          LearningCaptionFit.hidden,
        );
      });
    });

    // 与 组同几何：0.5s 均匀拍点、八拍大线 t=0、4、8…s；
    // 段 [0,8] 含 2 个八拍 → 全句「2 个八拍」5 字形 × 10 = 50px、
    // 数字「2」10px。段内可用宽 = 800 × 8/total − 段间缝 4。
    Future<void> pumpNarrowBand(
      WidgetTester tester, {
      required Duration videoDuration,
    }) async {
      final engine = FakePlaybackEngine(duration: videoDuration);
      final count = videoDuration.inMilliseconds ~/ 500 + 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.normalized(
                videoDuration: videoDuration,
                segmentLines: const [
                  SegmentLine(position: Duration(seconds: 8)),
                  SegmentLine(position: Duration(seconds: 16)),
                ],
              ),
            ),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  beats: [
                    for (var i = 0; i < count; i++)
                      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
    }

    testWidgets('中段（全句放不下、数字放得下）：仅显示 N', (tester) async {
      // total 200s → 段 0 宽 32px − 缝 4 = 28：50 放不下、10 放得下。
      await pumpNarrowBand(tester, videoDuration: const Duration(seconds: 200));

      // 断言限定段体内（轨上另有八拍数标注的「2」小字，非本说明）。
      for (final index in [0, 1]) {
        expect(
          find.descendant(
            of: find.byKey(Key('learning_segment_$index')),
            matching: find.text('2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(Key('learning_segment_$index')),
            matching: find.text('2 个八拍'),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('窄段（数字也放不下）：整行不显示', (tester) async {
      // total 600s → 段 0 宽 10.7px − 缝 4 = 6.7：连数字 10 也放不下。
      await pumpNarrowBand(tester, videoDuration: const Duration(minutes: 10));

      // 断言限定段体内（轨上另有八拍数标注的「2」小字，非本说明）。
      expect(
        find.descendant(
          of: find.byKey(const Key('learning_segment_0')),
          matching: find.text('2'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('learning_segment_0')),
          matching: find.text('2 个八拍'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const Key('learning_segment_0_eight_count_digits')),
        findsNothing,
      );
    });
  });

  // 判定与渲染同源（裁切回归）：说明文案的**量测样式与渲染样式必须同一份**
  // 且同不缩放。否则量测宽比渲染宽少一截（环境 DefaultTextStyle 的
  // letterSpacing 0.25 等按字形数累积），「全句放得下」的判定在临界段宽上
  // 会把末字挤到被 maxLines 丢掉的第二行——真机症状「4 个八拍」显示成
  // 「4 个八」（末字被吞、无省略号，看起来像数字错）。
  group('学习段说明缩字：判定与渲染同源（裁切回归）', () {
    // 段 0 = [0, 8s]、带全宽 800 → 段宽 = 800 × 8/total，段内可用宽 = 段宽 −
    // 段间缝。扫掠 total 即扫掠段内可用宽（0.5s 一步 ≈ 0.2px），覆盖
    // 「全句 / 仅数字」门槛两侧与临界带。
    const line = Duration(seconds: 8);
    const bandWidth = 800.0;

    // 内容区左缘让出轨道片头带，段宽按内容区宽算。
    final contentWidth = bandContentWidth(bandWidth);

    double innerWidthOf(Duration total) =>
        contentWidth * (line.inMilliseconds / total.inMilliseconds) -
        kSegmentBoxGap;

    /// 按**渲染实际样式**量测文案宽：`Text` 在 `style.inherit` 为 true 时会与
    /// 环境 [DefaultTextStyle] 合并（Material `bodyMedium` 带 letterSpacing
    /// 0.25 等），此处同口径求解——判定侧若与渲染侧同源，两者必然相等。
    double renderedTextWidth(WidgetTester tester, Finder finder) {
      final text = tester.widget<Text>(finder);
      final style = text.style!;
      final context = tester.element(finder);
      final effective = style.inherit
          ? DefaultTextStyle.of(context).style.merge(style)
          : style;
      final painter = TextPainter(
        text: TextSpan(text: text.data, style: effective),
        textDirection: TextDirection.ltr,
        textScaler: text.textScaler ?? MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    Future<void> pumpAtTotal(WidgetTester tester, Duration total) async {
      // 每个采样先卸掉旧树：ProviderScope 复用会让 annotationTimeline 覆盖
      // 保持首帧缓存（扫掠会退化成同一几何、静默失真）。
      await tester.pumpWidget(const SizedBox.shrink());
      final engine = FakePlaybackEngine(duration: total);
      final count = total.inMilliseconds ~/ 500 + 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.normalized(
                videoDuration: total,
                segmentLines: const [
                  SegmentLine(position: Duration(seconds: 8)),
                  SegmentLine(position: Duration(seconds: 16)),
                ],
              ),
            ),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  beats: [
                    for (var i = 0; i < count; i++)
                      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
    }

    testWidgets('任一段宽下被选中的说明变体必然放得下（不被软换行裁掉）', (tester) async {
      var sawFull = false;
      var sawDigits = false;
      // 全句「2 个八拍」实测宽 50px（5 字形 × 10）：全/仅数字门槛在内宽
      // 50px ≈ total 112.6s，扫掠区间两侧各覆盖多级并跨过门槛相邻采样。
      for (var ms = 98000; ms <= 122000; ms += 500) {
        final total = Duration(milliseconds: ms);
        await pumpAtTotal(tester, total);
        final inner = innerWidthOf(total);
        // 扫掠前提：可视窗口 = 全片（段宽随时长反比变化），公式与真几何一致
        // ——失真即报错，不让扫掠退化成空转。
        final segWidth = tester
            .getSize(find.byKey(const Key('learning_segment_0')))
            .width;
        expect(
          segWidth - kSegmentBoxGap,
          closeTo(inner, 0.05),
          reason: 'total=${ms}ms 的段内可用宽与公式不符，扫掠前提失真',
        );
        // 每段恰好渲染一级说明（本扫掠几何下可用宽 ≥ 45px > 数字宽 → 不会
        // 落到「隐藏」）：一级都没渲染 = 说明被静默吞掉，同样要报错。
        final found = <LearningCaptionFit, Finder>{};
        for (final variant in LearningCaptionFit.values) {
          final finder = find.byKey(
            Key('learning_segment_0_eight_count_${variant.name}'),
          );
          if (finder.evaluate().isNotEmpty) found[variant] = finder;
        }
        expect(
          found.keys,
          hasLength(1),
          reason:
              '段内可用宽 ${inner.toStringAsFixed(2)}px（total=${ms}ms）应恰好'
              '渲染一级说明，实得 ${found.keys}',
        );
        final variant = found.keys.single;
        final finder = found.values.single;
        sawFull |= variant == LearningCaptionFit.full;
        sawDigits |= variant == LearningCaptionFit.digits;
        // 门槛两侧：全句实测宽（5 字形 × 字号）是独立真值——可用宽达此值
        // 才该选全句，否则仅数字。既抓偏松（放不下却选全句），也抓偏严
        // （放得下却降级），让扫掠真正压在门槛上而不是只证明「选的放得下」。
        expect(
          variant,
          inner >= kLearningCaptionFontSize * 5
              ? LearningCaptionFit.full
              : LearningCaptionFit.digits,
          reason:
              '段内可用宽 ${inner.toStringAsFixed(2)}px（total=${ms}ms）'
              '选中的层级与实测门槛不符',
        );
        // ① 判定侧前提：按渲染实际样式量出的宽必须放得下。
        expect(
          renderedTextWidth(tester, finder),
          lessThanOrEqualTo(inner + 0.01),
          reason:
              '段内可用宽 ${inner.toStringAsFixed(2)}px（total=${ms}ms）选中 '
              '${variant.name}，但其渲染实际宽超出可用宽：量测宽比渲染宽小，'
              '末字被裁/被吞',
        );
        // ② 真实布局：画出来的字形盒也必须落在可用宽内——`softWrap: false`
        // 时溢出表现为右缘裁切（`didExceedMaxLines` 只反映纵向截断，此处恒
        // false，不作判据）。
        final text = tester.widget<Text>(finder);
        final inkBoxes = tester
            .renderObject<RenderParagraph>(finder)
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: (text.data ?? '').length,
              ),
            );
        expect(inkBoxes, isNotEmpty, reason: '选中一级说明却量不到任何字形盒');
        for (final ink in inkBoxes) {
          expect(
            ink.left,
            greaterThanOrEqualTo(-0.01),
            reason:
                '段内可用宽 ${inner.toStringAsFixed(2)}px（total=${ms}ms）'
                '字形盒越出左缘',
          );
          expect(
            ink.right,
            lessThanOrEqualTo(inner + 0.01),
            reason:
                '段内可用宽 ${inner.toStringAsFixed(2)}px（total=${ms}ms）选中 '
                '${variant.name} 的字形盒越出右缘：末字被裁',
          );
        }
      }
      expect(sawFull, isTrue, reason: '扫掠必须覆盖「全句」级');
      expect(sawDigits, isTrue, reason: '扫掠必须覆盖「仅数字」级');
    });

    testWidgets('说明随系统字号：1.3×/1.6× 说明宽按缩放重算（语义档）', (tester) async {
      // 语义档：说明承载语义、随系统字号缩放；判定侧与渲染侧
      // 吃同一个缩放值，层级选择由缩放后的实测宽决定。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      // total 30s → 段内可用宽 = 800 × 8/30 − 4 ≈ 209px，1.3× 全句宽
      // 5 × 10 × 1.3 = 65px，仍放得下全句。
      await pumpAtTotal(tester, const Duration(seconds: 30));

      final finder = find.byKey(
        const Key('learning_segment_0_eight_count_full'),
      );
      expect(finder, findsOneWidget, reason: '可用宽内 1.3× 仍是全句级');
      expect(
        renderedTextWidth(tester, finder),
        closeTo(kLearningCaptionFontSize * 5 * 1.3, 0.01),
        reason: 'Ahem 每字形 = 字号：5 字形「2 个八拍」1.3× = 65px',
      );

      // 1.6×：全句宽 5 × 10 × 1.6 = 80px 仍放得下，不裁不溢出。
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        renderedTextWidth(tester, finder),
        closeTo(kLearningCaptionFontSize * 5 * 1.6, 0.01),
      );
    });

    test('说明样式带单层深色字阴影（与重点星标同款取值，唯一声明处）', () {
      // 白字的对比度下限由字形自身的深色边缘承担，取值复用重点星标那套
      // 语言——一层 black87、blurRadius 2、无偏移。样式常量是唯一声明处。
      final shadows = kLearningCaptionTextStyle.shadows;
      expect(shadows, isNotNull, reason: '说明样式须带字阴影承载可读性');
      expect(shadows, hasLength(1), reason: '单层阴影，不叠加多层');
      final shadow = shadows!.single;
      expect(shadow.color, Colors.black87, reason: '与重点星标同款阴影色');
      expect(shadow.blurRadius, 2, reason: '与重点星标同款模糊半径');
      expect(shadow.offset, Offset.zero, reason: '无偏移');
    });

    testWidgets('说明文案用唯一样式渲染：切断环境样式且两侧吃同一缩放值', (tester) async {
      // 本几何放得下全句（段内可用宽足够大）。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAtTotal(tester, const Duration(seconds: 30));

      final finder = find.byKey(
        const Key('learning_segment_0_eight_count_full'),
      );
      expect(finder, findsOneWidget);
      final text = tester.widget<Text>(finder);
      expect(
        text.style?.inherit,
        isFalse,
        reason: '渲染样式须切断环境 DefaultTextStyle（否则渲染宽于量测宽）',
      );
      expect(
        text.style,
        kLearningCaptionTextStyle,
        reason: '量测与渲染共用同一实例，不设第二份取值',
      );
      expect(
        text.textScaler,
        MediaQuery.textScalerOf(tester.element(finder)),
        reason: '两侧同源：渲染缩放 = 环境缩放，量测侧取同一值',
      );
      expect(text.textScaler!.scale(10), 13.0, reason: '语义档随系统字号：1.3× 下真的放大');
    });

    testWidgets('两档边界：装饰片头文字固定排版、不随系统字号', (tester) async {
      // 装饰档：片头标签列（"学习/节拍/…"）不承载语义，保持固定排版。
      // 独立真值 = 自身在 1.0× 下的渲染宽；1.3× 下逐位不变，与同屏随字号
      // 的段说明（语义档）构成两档分界。
      final label = find.byKey(const ValueKey('track_prefix_label_learning'));
      await pumpAtTotal(tester, const Duration(seconds: 30));
      final widthAt1x = tester.getSize(label).width;

      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpAtTotal(tester, const Duration(seconds: 30));
      expect(
        tester.getSize(label).width,
        widthAt1x,
        reason: '装饰档不随系统字号（量测与渲染同用固定排版）',
      );
    });
  });

  group('学习段轨空轨（无分段线时不显示片段）', () {
    testWidgets('学习段轨存在且不含任何片段/分段线元素', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      expect(find.byKey(const Key('track_learning')), findsOneWidget);
      // 本测试无任何 segment / 分段线元素。
      expect(find.byKey(const Key('learning_segment_0')), findsNothing);
      expect(find.byKey(const Key('segment_line_0')), findsNothing);
    });
  });

  group('分段与学习段轨', () {
    final total = const Duration(seconds: 30);

    AnnotationTimeline timelineWithLines(List<Duration> positions) {
      return AnnotationTimeline.normalized(
        videoDuration: total,
        segmentLines: [
          for (final position in positions) SegmentLine(position: position),
        ],
      );
    }

    double lineWidth(WidgetTester tester, String keyName) {
      // 分段线视觉现为直接绘制的 ColoredBox 标记（key 即标记本体）。
      return tester.getSize(find.byKey(Key(keyName))).width;
    }

    testWidgets('分段线划分学习段：片段首尾相接、总长固定且轨道高 48dp', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([
          const Duration(seconds: 10),
          const Duration(seconds: 20),
        ]),
      );

      expect(find.byKey(const Key('learning_segment_0')), findsOneWidget);
      expect(find.byKey(const Key('learning_segment_1')), findsOneWidget);
      expect(find.byKey(const Key('learning_segment_2')), findsOneWidget);
      expect(find.byKey(const Key('segment_line_0')), findsOneWidget);
      expect(find.byKey(const Key('segment_line_1')), findsOneWidget);

      final width = tester
          .getSize(find.byKey(const Key('track_learning')))
          .width;
      final first = tester.getRect(find.byKey(const Key('learning_segment_0')));
      final middle = tester.getRect(
        find.byKey(const Key('learning_segment_1')),
      );
      final last = tester.getRect(find.byKey(const Key('learning_segment_2')));
      expect(first.height, trackRowRect(tester, 'track_learning').height);
      expect(first.right, middle.left);
      expect(middle.right, last.left);
      expect(last.right, closeTo(width, .5));
      // 内容区左缘让出轨道片头带。
      expect(first.width, closeTo(bandContentWidth(width) * 10 / 30, .5));
    });

    testWidgets('分段线贯穿轨道带并位于时间映射处', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 10)]),
      );

      final rect = tester.getRect(find.byKey(const Key('segment_line_0')));
      final band = tester.getRect(find.byKey(const Key('track_band')));
      expect(rect.top, band.top);
      expect(rect.bottom, band.bottom);
      expect(rect.center.dx, closeTo(bandX(10), 1));
    });

    testWidgets('长按分段线不再切换 flag（flag 只经「标记」按钮）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 10)]),
      );

      // 长按 + 静止抬起：手势废除，不产生 flag（仍是细线选中前的 1dp）。
      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await hold.up();
      await pumpSettle(tester);
      expect(lineWidth(tester, 'segment_line_0'), isNot(6));

      // flag 显示通路保持：经 timeline_ops 切 flag 后仍以 6dp 粗线渲染
      //（按钮入口接线归标注工具区，见 control_layer 测试）。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      container
          .read(annotationEditorProvider)
          .submit(ToggleSegmentFlag(index: 0));
      await tester.pump();
      expect(lineWidth(tester, 'segment_line_0'), 6);
    });

    testWidgets('flag 粗线单击不再跳转：进度不变、不触发收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10), flagged: true),
          ],
        ),
        onCollapse: () => collapses.value++,
      );
      engine.seekCalls.clear();

      await tapSegmentLineHandle(tester, 0);
      await pumpSettle(tester);

      // flag 单击跳转已取消：不 seek、不收起（定位由三指跳转/预览吸附承担）。
      expect(engine.seekCalls, isEmpty);
      expect(engine.position, Duration.zero);
      expect(collapses.value, 0);
    });

    testWidgets('flag 线与普通线交互一致：单击只 toggle 选中，激活保持', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 5), flagged: true),
            SegmentLine(position: Duration(seconds: 25), flagged: true),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      // 激活段 0（0..5s），随后点击 25s 处 flag 线。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});

      await tapSegmentLineHandle(tester, 1);
      await pumpSettle(tester);

      // 无跳转 → 激活不被清除；线被选中（flag+选中组合态可见）。
      expect(engine.seekCalls, isEmpty);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 1);
      // 再点同线取消选中（toggle，与普通线一致）。
      await tapSegmentLineHandle(tester, 1);
      await pumpSettle(tester);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
      );
    });

    testWidgets('flag 仍可被「标记」取消/删除：视觉保留粗线通路', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10), flagged: true),
          ],
        ),
      );

      // flag 显示通路保持：经 timeline_ops 切 flag 后回落细线。
      expect(lineWidth(tester, 'segment_line_0'), 6);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      container
          .read(annotationEditorProvider)
          .submit(ToggleSegmentFlag(index: 0));
      await tester.pump();
      expect(lineWidth(tester, 'segment_line_0'), 1);
    });

    testWidgets('手柄拖动分段线：无需长按，拖动调界且不切 flag', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 5), flagged: true),
          ],
        ),
      );

      // 拖动仅经轨道手柄带手柄起手（底行短横条）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      // flag 保持不变（6dp 粗线仍 flagged），位置已拖到 11s → 默认四拍格
      // 吸附为 12s。
      expect(lineWidth(tester, 'segment_line_0'), 6);
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(12), 1),
      );
    });

    testWidgets('手柄起手拖分段线：预览 seek 不动预览线、不触发收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 5)]),
        onCollapse: () => collapses.value++,
      );
      engine.seekCalls.clear();
      final beforeX = tester
          .getCenter(find.byKey(const Key('preview_line')))
          .dx;

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 拖线有逐帧预览 seek（线位置），但不是预览条 scrub——预览线
      // 不随动、松手回到原位、不收起。
      expect(engine.seekCalls, isNotEmpty, reason: '拖线实时预览 seek');
      expect(engine.seekCalls.last, Duration.zero, reason: '松手回预览线位置');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        beforeX,
        reason: '预览线不随拖线移动',
      );
      expect(collapses.value, 0);
    });

    testWidgets('槽宽命中：手柄中心偏 18dp 仍在槽内可拖动该线（半距法）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 5)]),
      );

      // 线 5s（x 133.3）距首尾都远 → 槽宽封顶 48dp（±24dp）：手柄中心偏
      // 18px 按下仍在槽内，起手拖动应命中并拖动该线。
      final center = tester.getCenter(
        find.byKey(const Key('segment_line_0_handle')),
      );
      final gesture = await tester.startGesture(center + const Offset(18, 0));
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 手指终点 x = 133.3 + 18 + 160 = 311.3 → 11.7s，按默认四拍格（2s）
      // 吸附为 12s（与线心起手的吸附结果一致）。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(12), 1),
      );
    });

    testWidgets('密集线取最近：两线手柄槽重叠时按下拖动最近的一条', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([
          const Duration(seconds: 14),
          const Duration(milliseconds: 14500),
        ]),
      );

      // 线 0 = 14s（x 373.3）、线 1 = 14.5s（x 386.7），间距 13.3px < 24dp
      // → 两槽按下限 24dp 分配并在按下点 x=376 处重叠；点距线 0 仅 2.7px、
      // 距线 1 有 10.7px——虽按下落在栈序更上的线 1 手柄上，也必须拖动更近
      // 的线 0。向左拖 160px（不越过邻线，避免相邻钳制干扰「拖的是谁」的
      // 判定）。手柄在轨道手柄带（底行轨道手柄带行）。
      final stripY = trackRowCenterY(tester, 'track_handle_strip_row');
      final gesture = await tester.startGesture(Offset(376, stripY));
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(-160, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(8), 1), // 8.1s → 四拍格吸附 8s。
        reason: '按下点最近的是 14s 线，应拖动它',
      );
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_1'))).dx,
        closeTo(bandX(14.5), 1),
        reason: '较远的 14.5s 线不动',
      );
    });

    testWidgets('按下未位移抬起 = 单击选中（不调界、不切 flag）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 5)]),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);

      expect(lineWidth(tester, 'segment_line_0'), 3);
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
      );
    });

    testWidgets('拖动分段线：只落八拍点（吸附开）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 5)]),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 5s + 160px(6s) = 11s → 就近八拍点 12s（八拍点 = 0/4/8/12…s）。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(12), 1),
      );
    });

    testWidgets('拖出有效区间或相邻边界时钳制不产生非法几何', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 5)]),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);

      // 目标 <= rangeStart 被 moveSegmentLine 拒绝，保留原 5s 位置。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
      );
    });

    testWidgets('点选/拖动片段与分段线不触发收起；空白单击仍收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 5)]),
        onCollapse: () => collapses.value++,
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      await tapSegmentLineHandle(tester, 0);
      await pumpSettle(tester);
      await tester.drag(
        find.byKey(const Key('learning_segment_0')),
        const Offset(60, 0),
      );
      await pumpSettle(tester);
      expect(collapses.value, 0);

      await tester.tap(find.byKey(const Key('track_handle_strip_row')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(collapses.value, 1);
    });

    testWidgets('点击学习段写入激活状态并显示激活样式，不触发收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([
          const Duration(seconds: 10),
          const Duration(seconds: 20),
        ]),
        onCollapse: () => collapses.value++,
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      // 激活态可见样式 = 激活色加粗边框（默认 #39C5BB）+ 静态外发光。
      final boxDecoration = learningSegmentBoxDecoration(tester, 0);
      expect(
        (boxDecoration.border! as Border).top.color,
        const Color(0xFF39C5BB),
      );
      expect(
        (boxDecoration.border! as Border).top.width,
        kSegmentSelectedBorderWidth,
      );
      expect(collapses.value, 0);

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      // 取消选中后无任何选中视觉（选中集合是唯一状态，取消即
      // 干净退出——外框回落默认、无发光、无任何白圈）：外框回落默认、无发光、
      final deselectedBorder =
          (learningSegmentBoxDecoration(tester, 0).border! as Border).top;
      expect(deselectedBorder.color, kSegmentBoxStrokeColor);
      expect(deselectedBorder.width, kSegmentBoxStrokeWidth);
      expect(
        learningSegmentBoxDecoration(tester, 0).boxShadow ?? const [],
        isEmpty,
      );
      expect(
        find.byKey(const Key('learning_segment_0_selected_ring')),
        findsNothing,
      );
      expect(collapses.value, 0);
    });
  });

  // ---- ：控制柄键盘微调 ----

  group('控制柄键盘微调', () {
    final total = const Duration(seconds: 30);

    AnnotationTimeline timelineWithLines(List<Duration> positions) =>
        AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: [
            for (final position in positions) SegmentLine(position: position),
          ],
        );

    double lineX(WidgetTester tester, String keyName) =>
        tester.getCenter(find.byKey(Key(keyName))).dx;

    /// 首尾线用例的时间线：首/尾线避开预览线（播放头 0）所在命中列。
    AnnotationTimeline rangeTimeline() => AnnotationTimeline.normalized(
      videoDuration: total,
      rangeStart: const Duration(seconds: 5),
      rangeEnd: const Duration(seconds: 25),
    );

    /// 点控制柄落焦（触摸路径照常选中），再发方向键。
    Future<void> nudge(
      WidgetTester tester,
      Key handleKey,
      int times, {
      required bool right,
    }) async {
      await tester.tap(find.byKey(handleKey));
      await tester.pump();
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(
          right ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowLeft,
        );
        await tester.pump();
      }
      await pumpSettle(tester);
    }

    testWidgets('分段线：左右方向键各挪一个八拍点（走拖动同一会话写入口）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 8)]),
      );

      await nudge(tester, const Key('segment_line_0_handle'), 1, right: true);
      expect(
        find.byKey(const Key('segment_line_0_handle_focus_ring')),
        findsOneWidget,
        reason: '控制柄落焦后焦点可见',
      );
      expect(lineX(tester, 'segment_line_0'), closeTo(bandX(12), 1));

      await nudge(tester, const Key('segment_line_0_handle'), 2, right: false);
      expect(lineX(tester, 'segment_line_0'), closeTo(bandX(4), 1));
    });

    testWidgets('分段线：八拍锚点重定相后仍按相位取相邻八拍点（唯一相位源）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        // 锚点 4 号拍（t=2s）把相位原点改到 2s：此后八拍点 = 2/6/10s…
        // 线若落在 4s，相邻的下一八拍点是 6s（裸网格 +8 拍会得 8s，
        // 就近吸附并列取后者 → 10s，跳过 6s）。
        beatAnchors: const [4],
        timeline: timelineWithLines([const Duration(seconds: 4)]),
      );

      await nudge(tester, const Key('segment_line_0_handle'), 1, right: true);
      expect(lineX(tester, 'segment_line_0'), closeTo(bandX(6), 1));
    });

    testWidgets('首线：右方向键挪一拍', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, timeline: rangeTimeline());

      await nudge(
        tester,
        const Key('video_range_start_marker'),
        1,
        right: true,
      );
      expect(lineX(tester, 'video_range_start_line'), closeTo(bandX(5.5), 1));
    });

    testWidgets('尾线：左方向键挪一拍', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, timeline: rangeTimeline());

      await nudge(tester, const Key('video_range_end_marker'), 1, right: false);
      expect(lineX(tester, 'video_range_end_line'), closeTo(bandX(24.5), 1));
    });

    testWidgets('分段锁：微调被拒，控制柄不动', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 8)]),
      );
      ProviderScope.containerOf(tester.element(find.byType(TrackBand)))
          .read(layoutLockedProvider.notifier)
          .toggle();
      await tester.pump();

      await nudge(tester, const Key('segment_line_0_handle'), 1, right: true);
      expect(
        lineX(tester, 'segment_line_0'),
        closeTo(bandX(8), 1),
        reason: '分段锁照旧拒写',
      );
    });

    testWidgets('对比只读：微调被拒，控制柄不动', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 5),
          rangeEnd: const Duration(seconds: 25),
          segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
        ),
        compareReadonly: true,
      );

      await nudge(tester, const Key('segment_line_0_handle'), 1, right: true);
      await nudge(
        tester,
        const Key('video_range_start_marker'),
        1,
        right: true,
      );
      expect(
        lineX(tester, 'segment_line_0'),
        closeTo(bandX(8), 1),
        reason: '对比只读照旧拒写分段线',
      );
      expect(
        lineX(tester, 'video_range_start_line'),
        closeTo(bandX(5), 1),
        reason: '对比只读照旧拒写首线',
      );
    });

    testWidgets('现有拖动手感不变：控制柄拖动仍调界且不触发焦点微调', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([const Duration(seconds: 8)]),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(320, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(lineX(tester, 'segment_line_0'), closeTo(bandX(20), 1));
    });
  });

  // ---- ：分段线选中 toggle 与选中/flag 分色 ----

  group('分段线选中 toggle 与选中/flag 分色', () {
    final total = const Duration(seconds: 30);

    AnnotationTimeline timelineWithLines(List<Duration> positions) {
      return AnnotationTimeline.normalized(
        videoDuration: total,
        segmentLines: [
          for (final position in positions) SegmentLine(position: position),
        ],
      );
    }

    Color lineColor(WidgetTester tester, String keyName) {
      return tester.widget<ColoredBox>(find.byKey(Key(keyName))).color;
    }

    testWidgets('再点同一分段线取消选中（toggle），线回落细线默认色', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([
          const Duration(seconds: 10),
          const Duration(seconds: 20),
        ]),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tapSegmentLineHandle(tester, 0);
      await pumpSettle(tester);
      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>(),
      );

      await tapSegmentLineHandle(tester, 0);
      await pumpSettle(tester);

      expect(container.read(annotationSelectionProvider), isNull);
      expect(
        tester.getSize(find.byKey(const Key('segment_line_0'))).width,
        kSegmentLineWidth,
      );
      expect(lineColor(tester, 'segment_line_0'), kSegmentLineColor);
    });

    testWidgets('点其它分段线替换选中（旧线回落细线默认色）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: timelineWithLines([
          const Duration(seconds: 10),
          const Duration(seconds: 20),
        ]),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tapSegmentLineHandle(tester, 0);
      await pumpSettle(tester);
      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>().having((s) => s.index, 'index', 0),
      );
      await tapSegmentLineHandle(tester, 1);
      await pumpSettle(tester);

      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>().having((s) => s.index, 'index', 1),
      );

      expect(
        tester.getSize(find.byKey(const Key('segment_line_0'))).width,
        kSegmentLineWidth,
      );
      expect(lineColor(tester, 'segment_line_0'), kSegmentLineColor);
      expect(
        tester.getSize(find.byKey(const Key('segment_line_1'))).width,
        kSegmentLineSelectedWidth,
      );
    });

    testWidgets('选中线 = 激活青、flag = 琥珀：两种状态颜色可区分', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10), flagged: true),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      await tapSegmentLineHandle(tester, 1);
      await pumpSettle(tester);

      final selectedColor = lineColor(tester, 'segment_line_1');
      final flaggedColor = lineColor(tester, 'segment_line_0');
      expect(selectedColor, kCyanAccentColor);
      expect(flaggedColor, kSegmentLineFlaggedColor);
      expect(selectedColor, isNot(flaggedColor));
    });

    testWidgets('flag 且选中 = 琥珀粗线叠青色外发光（组合态）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10), flagged: true),
          ],
        ),
      );

      await tapSegmentLineHandle(tester, 0);
      await pumpSettle(tester);

      expect(
        tester.getSize(find.byKey(const Key('segment_line_0'))).width,
        kSegmentLineFlaggedWidth,
      );
      expect(lineColor(tester, 'segment_line_0'), kSegmentLineFlaggedColor);
      final glow =
          tester
                  .widget<Container>(
                    find.byKey(const Key('segment_line_0_glow')),
                  )
                  .decoration!
              as BoxDecoration;
      expect(glow.boxShadow!.single.color, kCyanAccentColor);
    });
  });

  // ---- ：学习段格框渲染与激活外发光 ----

  group('学习段格框与激活外发光', () {
    final total = const Duration(seconds: 30);

    testWidgets('每个学习段渲染为独立圆角格框：圆角 + 段间留缝 + 1px 半透明白描边', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      for (var i = 0; i < 3; i++) {
        final decoration = learningSegmentBoxDecoration(tester, i);
        // 圆角格框（剪映式）。
        expect(
          decoration.borderRadius,
          BorderRadius.circular(kSegmentBoxBorderRadius),
        );
        // 半透明白 1px 描边（未练灰相邻段也界限分明）。
        final border = decoration.border! as Border;
        expect(border.top.color, kSegmentBoxStrokeColor);
        expect(border.top.width, kSegmentBoxStrokeWidth);
      }

      // 段间留缝：相邻格框之间有可见缝（各让 gap/2）。
      Rect boxRect(int i) =>
          tester.getRect(find.byKey(Key('learning_segment_${i}_box')));
      expect(boxRect(1).left - boxRect(0).right, closeTo(kSegmentBoxGap, 0.5));
      expect(boxRect(2).left - boxRect(1).right, closeTo(kSegmentBoxGap, 0.5));
      // 首段贴轨左缘留半缝、末段贴轨右缘留半缝（缝只在段间，段轨两端各让一半）。
      final trackLeft = tester
          .getTopLeft(find.byKey(const Key('track_learning')))
          .dx;
      final trackRight =
          trackLeft +
          tester.getSize(find.byKey(const Key('track_learning'))).width;
      // 段轨内容区左缘让出轨道片头带（首段贴内容区左缘）。
      expect(
        boxRect(0).left - (trackLeft + kTrackPrefixWidth),
        closeTo(kSegmentBoxGap / 2, 0.5),
      );
      expect(trackRight - boxRect(2).right, closeTo(kSegmentBoxGap / 2, 0.5));
    });

    testWidgets('同灰相邻段界限分明：未练灰填充保持、各段独立格框', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      // 相邻两段同为未练灰：填充色不因格框变化（熟练度主色语言不变）。
      expect(
        learningSegmentBoxDecoration(tester, 0).color,
        kMasteryUnlearnedColor,
      );
      expect(
        learningSegmentBoxDecoration(tester, 1).color,
        kMasteryUnlearnedColor,
      );
      // 且两框之间确有缝隙（界限分明）。
      final left0 = tester
          .getRect(find.byKey(const Key('learning_segment_0_box')))
          .right;
      final left1 = tester
          .getRect(find.byKey(const Key('learning_segment_1_box')))
          .left;
      expect(left1 - left0, greaterThanOrEqualTo(kSegmentBoxGap - 0.5));
    });

    testWidgets('激活段：静态外发光 + 加粗激活边框，熟练度填充不被覆盖', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      // 未激活：发光层装饰无阴影。
      expect(
        learningSegmentGlowDecoration(tester, 0).boxShadow ?? const [],
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      // 激活：静态外发光（激活色半透明阴影）。
      final shadows = learningSegmentGlowDecoration(tester, 0).boxShadow!;
      expect(shadows, hasLength(1));
      expect(
        shadows.single.color,
        kCyanAccentColor.withValues(alpha: kSegmentGlowOpacity),
      );
      expect(shadows.single.blurRadius, kSegmentGlowBlurRadius);
      // 加粗激活边框 + 熟练度填充不被覆盖。
      final box = learningSegmentBoxDecoration(tester, 0);
      expect((box.border! as Border).top.color, kCyanAccentColor);
      expect((box.border! as Border).top.width, kSegmentSelectedBorderWidth);
      expect(box.color, kMasteryUnlearnedColor);

      // 取消激活：发光消失（点选同时选中该段 → 描边回落为选中白框，
      // 半透明白描边回落已由首测覆盖）。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      expect(
        learningSegmentGlowDecoration(tester, 0).boxShadow ?? const [],
        isEmpty,
      );
      expect(
        (learningSegmentBoxDecoration(tester, 0).border! as Border).top.color,
        isNot(kCyanAccentColor),
      );
    });

    testWidgets('多段合并激活：各段逐段点亮连成一片', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      // 点选只产生单元素集合；多段选中由长按圈选产生，此处直接布置。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      container.read(selectedLearningSegmentsProvider.notifier).state = const {
        0,
        1,
      };
      await pumpSettle(tester);

      // 合并激活范围 {0,1}：两段各有外发光与加粗边框。
      expect(learningSegmentGlowDecoration(tester, 0).boxShadow, isNotEmpty);
      expect(learningSegmentGlowDecoration(tester, 1).boxShadow, isNotEmpty);
      // 未激活的段 2 不发光。
      expect(
        learningSegmentGlowDecoration(tester, 2).boxShadow ?? const [],
        isEmpty,
      );
    });

    testWidgets('选中且激活：青色 3dp 外框 + 静态外发光；内嵌白圈不再出现', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
        ),
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      // 激活青色 3dp 外框 + 静态外发光。
      final border = learningSegmentBoxDecoration(tester, 0).border! as Border;
      expect(border.top.color, kCyanAccentColor);
      expect(border.top.width, kSegmentSelectedBorderWidth);
      expect(learningSegmentGlowDecoration(tester, 0).boxShadow, isNotEmpty);
      // 内嵌白圈整体退场：选中只有一个状态、只留一套视觉。
      expect(
        find.byKey(const Key('learning_segment_0_selected_ring')),
        findsNothing,
      );
      // 熟练度填充不受影响。
      expect(
        learningSegmentBoxDecoration(tester, 0).color,
        kMasteryUnlearnedColor,
      );
    });
  });

  // ---- ：循环范围端标志只留 repeat 字形、激活帧与中段同形 ----

  group('循环范围两端字形', () {
    final total = const Duration(seconds: 30);

    /// 某段某端字形的 key。
    Key loopKey(int i, String suffix) => Key('learning_segment_$i$suffix');

    const suffixes = ['_loop_glyph_start', '_loop_glyph_end'];

    /// 断言段 [i] 的激活帧是完整圆角整框：四边 3dp 激活色 +
    /// `kSegmentBoxBorderRadius` 圆角——端点四角不被任何标记填成直角。
    void expectFullRoundedFrame(WidgetTester tester, int i) {
      final decoration = learningSegmentBoxDecoration(tester, i);
      final border = decoration.border! as Border;
      for (final side in [
        border.top,
        border.right,
        border.bottom,
        border.left,
      ]) {
        expect(side.color, kCyanAccentColor, reason: '段 $i');
        expect(side.width, kSegmentSelectedBorderWidth, reason: '段 $i');
      }
      final radius = decoration.borderRadius! as BorderRadius;
      for (final corner in [
        radius.topLeft,
        radius.topRight,
        radius.bottomLeft,
        radius.bottomRight,
      ]) {
        expect(
          corner,
          const Radius.circular(kSegmentBoxBorderRadius),
          reason: '段 $i 圆角完整',
        );
      }
    }

    /// 两矩形是否相交（遮让不变量断言用）。

    /// 断言段 [i] 完全没有循环标志（每条「有」配一条「没有」）。
    void expectNoLoopMarks(WidgetTester tester, int i) {
      for (final suffix in suffixes) {
        expect(
          find.byKey(loopKey(i, suffix)),
          findsNothing,
          reason: '未承担范围端的段不应有标志：segment $i$suffix',
        );
      }
    }

    testWidgets('单段激活：两端各一枚字形、激活帧与中段同形；未激活段没有标志', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      // 未激活：三段都没有任何循环标志。
      expectNoLoopMarks(tester, 0);
      expectNoLoopMarks(tester, 1);
      expectNoLoopMarks(tester, 2);

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      // 旧括号帽键不再存在：端标志只由 repeat 字形承担。
      expect(find.byKey(loopKey(0, '_loop_start')), findsNothing);
      expect(find.byKey(loopKey(0, '_loop_end')), findsNothing);

      // 单段承担两端：左右两端各一枚 repeat。
      for (final suffix in suffixes) {
        expect(find.byKey(loopKey(0, suffix)), findsOneWidget);
      }
      // 激活帧与中段逐像素同形：完整的 3dp 激活色圆角整框，端点四角
      // 不被任何标记填掉（左右两端都在这一个格框装饰上）。
      expectFullRoundedFrame(tester, 0);

      // 字形贴端 3dp、距底 3dp，在盒内。
      final box = tester.getRect(
        find.byKey(const Key('learning_segment_0_box')),
      );
      final glyphStart = tester.getRect(
        find.byKey(loopKey(0, '_loop_glyph_start')),
      );
      final glyphEnd = tester.getRect(
        find.byKey(loopKey(0, '_loop_glyph_end')),
      );
      expect(glyphStart.left, closeTo(box.left + kSegmentLoopGlyphInset, 0.5));
      expect(
        glyphStart.bottom,
        closeTo(box.bottom - kSegmentLoopGlyphInset, 0.5),
      );
      expect(glyphStart.longestSide, kSegmentLoopGlyphSize);
      expect(glyphEnd.right, closeTo(box.right - kSegmentLoopGlyphInset, 0.5));
      expect(
        glyphEnd.bottom,
        closeTo(box.bottom - kSegmentLoopGlyphInset, 0.5),
      );
      expect(glyphEnd.longestSide, kSegmentLoopGlyphSize);
      // 字形用激活色，不新增颜色。
      final icons = tester.widgetList<Icon>(
        find.descendant(
          of: find.byKey(const Key('learning_segment_0_box')),
          matching: find.byIcon(Icons.repeat),
        ),
      );
      expect(icons.length, 2);
      for (final icon in icons) {
        expect(icon.color, kCyanAccentColor);
      }

      // 未激活的段 1、2 一个标志都没有。
      expectNoLoopMarks(tester, 1);
      expectNoLoopMarks(tester, 2);
    });

    testWidgets('相邻三段合并激活：只有最外两段有标志，中间段没有钩也没有字形', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      // 点选只产生单元素集合；多段选中由长按圈选产生，此处直接布置。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      container.read(selectedLearningSegmentsProvider.notifier).state = const {
        0,
        1,
        2,
      };
      await pumpSettle(tester);

      // 首段只承担 start 端；末段只承担 end 端；中段两端都不承担。
      expect(find.byKey(loopKey(0, '_loop_glyph_start')), findsOneWidget);
      expect(find.byKey(loopKey(0, '_loop_glyph_end')), findsNothing);
      expectFullRoundedFrame(tester, 0);

      expect(find.byKey(loopKey(2, '_loop_glyph_end')), findsOneWidget);
      expect(find.byKey(loopKey(2, '_loop_glyph_start')), findsNothing);
      expectFullRoundedFrame(tester, 2);

      expectNoLoopMarks(tester, 1);
    });

    testWidgets('窄段（盒宽 < 26dp）：字形省略、激活帧仍完整', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            // 中段 0.75s → 800 满铺下约 20dp < 26dp。
            SegmentLine(position: Duration(milliseconds: 10750)),
          ],
        ),
      );
      // 前提确认：该段盒宽确实放不下两端字形（判据派生式）。
      final boxWidth = tester
          .getSize(find.byKey(const Key('learning_segment_1_box')))
          .width;
      expect(
        boxWidth,
        lessThan((kSegmentLoopGlyphSize + kSegmentLoopGlyphInset) * 2),
      );

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await pumpSettle(tester);

      // 窄段单段承担两端：字形放不下，两端都省略，不出现半个符号。
      expect(find.byKey(loopKey(1, '_loop_glyph_start')), findsNothing);
      expect(find.byKey(loopKey(1, '_loop_glyph_end')), findsNothing);
      // 判据不成立也不加替补标记：旧括号帽键不存在、帧仍完整。
      expect(find.byKey(loopKey(1, '_loop_start')), findsNothing);
      expect(find.byKey(loopKey(1, '_loop_end')), findsNothing);
      expectFullRoundedFrame(tester, 1);
    });

    testWidgets('遮让不变量：星标、居中八拍数、repeat 字形矩形两两不相交', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 8)),
            SegmentLine(position: Duration(seconds: 16)),
          ],
        ),
        emphasized: {0},
      );
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      final star = tester.getRect(
        find.byKey(const Key('learning_segment_0_emphasis')),
      );
      final label = tester.getRect(
        find.byKey(const Key('learning_segment_0_eight_count_full')),
      );
      final glyph = tester.getRect(find.byKey(loopKey(0, '_loop_glyph_start')));
      expect(star.overlaps(glyph), isFalse, reason: '星标不压字形');
      expect(label.overlaps(glyph), isFalse, reason: '居中数字不压字形');
      expect(star.overlaps(label), isFalse, reason: '星标不压居中数字（既有不变量）');
    });

    testWidgets('取消激活后标志一并消失；拖出范围的自动取消同样消失', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      for (final suffix in suffixes) {
        expect(find.byKey(loopKey(0, suffix)), findsOneWidget);
      }

      // 再次点按取消激活 → 字形一并消失。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      expectNoLoopMarks(tester, 0);

      // 重新激活后，进度拖出范围（带内空白横滑 seek 到 15s > 段尾 10s）
      // 触发自动取消 → 字形一并消失。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      expect(find.byKey(loopKey(0, '_loop_glyph_start')), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('track_notes')),
        const Offset(400, 0),
      );
      await pumpSettle(tester);
      expectNoLoopMarks(tester, 0);
    });
  });

  // ---- ：对比态学习段轨同一套视觉 ----

  group('对比态学习段轨同一套视觉', () {
    final total = const Duration(seconds: 30);

    Key loopKey(int i, String suffix) => Key('learning_segment_$i$suffix');

    testWidgets('对比行集的学习段轨：选中段同用青色整框 + 发光 + 两端字形，无白圈', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        rowTable: TrackRowTable.compare,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);

      final border = learningSegmentBoxDecoration(tester, 0).border! as Border;
      expect(border.top.color, kCyanAccentColor);
      expect(border.top.width, kSegmentSelectedBorderWidth);
      expect(learningSegmentGlowDecoration(tester, 0).boxShadow, isNotEmpty);
      expect(find.byKey(loopKey(0, '_loop_glyph_start')), findsOneWidget);
      expect(find.byKey(loopKey(0, '_loop_glyph_end')), findsOneWidget);
      // 内嵌白圈不因行集切换而回来。
      expect(
        find.byKey(const Key('learning_segment_0_selected_ring')),
        findsNothing,
      );
    });
  });

  // ---- ：学习段轨最近段命中 ----

  group('学习段最近段命中', () {
    final total = const Duration(seconds: 30);

    /// 全宽 800 满铺 0..total：时间 → x。
    double xOf(Duration t) => bandXOf(t, total: total, width: 800);

    /// 学习段轨行的中心 y（轨道带贴 Scaffold body 顶部，学习段为最上行）。
    double learningY(WidgetTester tester) =>
        tester.getCenter(find.byKey(const Key('track_learning'))).dy;

    testWidgets('短段无需精确点中：点按短段段体即选中该段（seam 解析）', (tester) async {
      // 段 1 = [14s, 16.5s)（约 67px）；点按距段中心偏 6.7px 处 → 命中解析
      // 选中短段并激活，不收起。注意点按位置须落在分段线 40dp 抓取带之外
      //（加宽后线优先于段体，见命中优先级测试）。
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 14)),
            SegmentLine(position: Duration(milliseconds: 16500)),
          ],
        ),
        onCollapse: () => collapses.value++,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tester.tapAt(
        Offset(xOf(const Duration(milliseconds: 15250)), learningY(tester)),
      );
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentRepresentativeProvider), 1);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(collapses.value, 0);
    });

    testWidgets('命中优先级：短段扩展区与分段线命中带重叠 → 线胜出（线 > 段体）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 14)),
            SegmentLine(position: Duration(milliseconds: 14500)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      // 14.52s 落在段 1 最小命中宽扩展区内，但也在 14.5s 分段线 24dp 命中带
      // 内 → 按优先级选中分段线（不选段体、不收起由线命中层兜住）。
      await tester.tapAt(
        Offset(xOf(const Duration(milliseconds: 14520)), learningY(tester)),
      );
      await pumpSettle(tester);

      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 1);
      expect(
        container.read(selectedLearningSegmentRepresentativeProvider),
        isNull,
      );
    });

    testWidgets('区间内点按长段 → 选中该长段、不收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
        onCollapse: () => collapses.value++,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tester.tapAt(
        Offset(xOf(const Duration(seconds: 5)), learningY(tester)),
      );
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentRepresentativeProvider), 0);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(collapses.value, 0);
    });

    testWidgets('学习段轨区间外点按仍单击收起（命中扩展不吞收起）', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 20),
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
        onCollapse: () => collapses.value++,
      );

      // 5s 位于有效区间（10..20s）外的片头空白。命中扩展不吞 → 仍为轨道
      // 空白单击；经约 300ms 双击判定窗口后收起（修订）。
      await tester.tapAt(
        Offset(xOf(const Duration(seconds: 5)), learningY(tester)),
      );
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(collapses.value, 1);
    });
  });

  // ---- ：预览条 / 缩放 ----

  /// 轨道带内一条「空白横滑行」的基准 y：取节拍轨行纵向中心（节拍刻度
  /// 纯视觉、不挂横滑识别器；学习段体/分段线等编辑内容命中才改写横滑
  /// 语义）。局部镜像轨叠于最顶，带内中心不再落于空白行，故显式
  /// 以节拍轨行为准而非整带矩形中心。
  double bandCenterY(WidgetTester tester) =>
      trackRowCenterY(tester, 'track_beat');

  /// 当前可见刻度（按拍序号升序，拍序号 = 时间/0.5s @120bpm 占位网格）——
  /// 窗口平移/缩放的可见性断言用（刻度为每拍一根）。
  List<int> tickIndexes(WidgetTester tester, {int maxIndex = 400}) {
    final out = <int>[];
    for (var i = 0; i <= maxIndex; i++) {
      if (tester.any(find.byKey(ValueKey('beat_tick_${i * 500000}')))) {
        out.add(i);
      }
    }
    return out;
  }

  /// 双指向两侧张开（放大）：焦点 [center] 不动、双手对称外移。
  Future<void> pinchOutward(
    WidgetTester tester,
    Offset center, {
    double spread = 80,
    double travel = 100,
  }) async {
    final g1 = await tester.startGesture(center - Offset(spread / 2, 0));
    final g2 = await tester.startGesture(center + Offset(spread / 2, 0));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await g1.moveBy(Offset(-travel / 4, 0));
      await g2.moveBy(Offset(travel / 4, 0));
      await tester.pump();
    }
    await g1.up();
    await g2.up();
    await tester.pump();
  }

  group('一个状态：选中集合升格为主状态', () {
    final total = const Duration(seconds: 30);

    Future<ProviderContainer> pumpTwoSegments(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
    }

    void expectSegmentGlow(WidgetTester tester, int index, bool present) {
      final shadow = learningSegmentGlowDecoration(tester, index).boxShadow;
      expect(shadow == null || shadow.isEmpty, !present);
    }

    testWidgets('点分段线选中不清学习段选中与循环', (tester) async {
      final container = await pumpTwoSegments(tester);

      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggle(SegmentLineSelection(0));
      await pumpSettle(tester);

      expect(container.read(selectedSegmentLineIndexProvider), 0);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(container.read(selectedLearningSegmentRepresentativeProvider), 0);
      expectSegmentGlow(tester, 0, true);
    });

    testWidgets('带内空白单击收起控制层：学习段选中与循环都留着', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
        ),
        onCollapse: () => collapses.value++,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      // 备注轨空白单击：转发带级空白仲裁（收起 + 清点选槽）。
      await tester.tap(
        find.byKey(const Key('track_notes')),
        warnIfMissed: false,
      );
      // 单击收起经带级判定窗口（双击判定窗过后才收起）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(collapses.value, 1);
      expect(container.read(annotationSelectionProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expectSegmentGlow(tester, 0, true);
    });

    testWidgets('段体横向快滑 = 清空后只选中这一段', (tester) async {
      final container = await pumpTwoSegments(tester);

      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});

      await tester.drag(
        find.byKey(const Key('learning_segment_1')),
        const Offset(60, 0),
      );
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(container.read(selectedLearningSegmentRepresentativeProvider), 1);
      expectSegmentGlow(tester, 1, true);
    });

    testWidgets('带内空白精细调整 seek：学习段选中与循环都留着（六处不清）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await pumpSettle(tester);
      // 空白横滑 = 精细调整 seek：目标 15s（300px × 50ms）落在选中段
      // [10s, 20s) 内 → 不越出循环范围，选中保留。
      await tester.drag(
        find.byKey(const Key('track_band')),
        const Offset(300, 0),
      );
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expectSegmentGlow(tester, 1, true);
    });
  });

  group('按下即选', () {
    final total = const Duration(seconds: 30);

    void expectSegmentGlow(WidgetTester tester, int index, bool present) {
      final shadow = learningSegmentGlowDecoration(tester, index).boxShadow;
      expect(shadow == null || shadow.isEmpty, !present);
    }

    Future<ProviderContainer> pumpThreeSegments(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
    }

    testWidgets('按下未选中的段：当帧即只选中这一段，循环范围就位；'
        '按下是静默写——播放位置不动、不 seek、不起播', (tester) async {
      final container = await pumpThreeSegments(tester);
      final engine =
          container.read(playbackEngineProvider) as FakePlaybackEngine;
      engine.seek(const Duration(seconds: 25));
      engine.callLog.clear();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expectSegmentGlow(tester, 1, true);
      expectSegmentGlow(tester, 0, false);
      expect(
        engine.position,
        const Duration(seconds: 25),
        reason: '按下不 seek，播放位置不动',
      );
      expect(engine.callLog, isEmpty, reason: '按下不打断播放');

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
    });

    testWidgets('按下已选中的段：按下期间选中不变；抬手清空、循环关掉', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(1);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expectSegmentGlow(tester, 1, false);
    });

    testWidgets('按下落在多段选中范围里：按下期间整片不变；抬手整片清空', (tester) async {
      final container = await pumpThreeSegments(tester);
      final domain = container.read(annotationSelectionDomainProvider);
      domain.press(0);
      domain.liftPress(0);
      domain.press(2);
      domain.liftPress(2);
      domain.beginDragSelect(0);
      domain.spanTo(2);
      domain.commitDragSelect();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });

    testWidgets('按下落被系统打断：静默回滚到按下前的选中与循环', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_2'))),
      );
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {2});

      await gesture.cancel();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expectSegmentGlow(tester, 0, true);
      expectSegmentGlow(tester, 2, false);
    });

    testWidgets('压在段上的缩放起手接管：静默回滚到按下前的选中', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);

      // 第一指按下段 2（按下即选落地），第二指加入并张开 → 缩放识别器抢
      // 走 arena，段体 tap 被拒 → 按下会话静默回滚。
      final first = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_2'))),
      );
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {2});

      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_0'))),
      );
      await first.moveBy(const Offset(80, -40));
      await second.moveBy(const Offset(-80, 40));
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {
        0,
      }, reason: '缩放起手接管 → 整片回滚到按下前');
      await first.up();
      await second.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {
        0,
      }, reason: '回滚不因松手再翻转');
    });

    testWidgets('横向快滑起手接管按下会话：净结果不变——只选中这一段，'
        '不回滚到按下前', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_2'))),
      );
      await pumpSettle(tester);
      // 横向划过 slop（段宽 ≈ 266px，快滑 60px 足够）。
      await gesture.moveBy(const Offset(60, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {2});
    });

    testWidgets('长按圈选从已选中的段起手：长按成立时该段不被提前清空'
        '（不出现熄-亮闪烁），圈选与提交照常', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(1);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});

      // 长按成立（越过阈值）：以落点段为起点进入圈选，段 1 始终在选中内。
      await tester.pump(const Duration(milliseconds: 700));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expectSegmentGlow(tester, 1, true);

      await gesture.moveBy(const Offset(-600, 0));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1});

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1});
    });

    testWidgets('教程「编辑态上手」判据：按下第一段即记入完成（不必抬手）；'
        '按下别的段不记入', (tester) async {
      final container = await pumpThreeSegments(tester);
      expect(
        container
            .read(guideSessionProvider)
            .criterionLatches
            .contains(HandsOnCriterion.editorIntroActivate),
        isFalse,
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await pumpSettle(tester);
      expect(
        container
            .read(guideSessionProvider)
            .criterionLatches
            .contains(HandsOnCriterion.editorIntroActivate),
        isFalse,
        reason: '落点不是第一段',
      );
      await gesture.cancel();

      final gesture0 = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_0'))),
      );
      await pumpSettle(tester);
      expect(
        container
            .read(guideSessionProvider)
            .criterionLatches
            .contains(HandsOnCriterion.editorIntroActivate),
        isTrue,
        reason: '按下第一段即记入，不等抬手',
      );
      await gesture0.cancel();
    });
  });

  group('长按拖动圈选', () {
    final total = const Duration(seconds: 30);

    void expectSegmentGlow(WidgetTester tester, int index, bool present) {
      final shadow = learningSegmentGlowDecoration(tester, index).boxShadow;
      expect(shadow == null || shadow.isEmpty, !present);
    }

    Future<ProviderContainer> pumpThreeSegments(WidgetTester tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
    }

    /// 长按某段体成立（越过长按阈值），返回在持手势供横拖/松手/取消。
    Future<TestGesture> holdSegment(WidgetTester tester, int index) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(Key('learning_segment_$index'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      return gesture;
    }

    testWidgets('长按成立：清空原选中、落点段立为起点，松手前即有视觉反馈', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);
      expectSegmentGlow(tester, 0, true);

      final gesture = await holdSegment(tester, 1);
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expectSegmentGlow(tester, 0, false);
      expectSegmentGlow(tester, 1, true);

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
    });

    testWidgets('长按不动松手＝只选中落点段', (tester) async {
      final container = await pumpThreeSegments(tester);

      final gesture = await holdSegment(tester, 1);
      await gesture.up();
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {1});
    });

    testWidgets('横拖右：实时圈出起点到手指的全部连续段，含两端', (tester) async {
      final container = await pumpThreeSegments(tester);

      final gesture = await holdSegment(tester, 0);
      // 段宽 = 800px ÷ 3 ≈ 266.7；拖 600px 从段 0 越过段 1 落进段 2。
      await gesture.moveBy(const Offset(600, 0));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
      expectSegmentGlow(tester, 0, true);
      expectSegmentGlow(tester, 2, true);

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
    });

    testWidgets('横拖左：方向对称，结果一致', (tester) async {
      final container = await pumpThreeSegments(tester);

      final gesture = await holdSegment(tester, 2);
      await gesture.moveBy(const Offset(-600, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
    });

    testWidgets('拖出末段方向：圈到末段为止，不越界', (tester) async {
      final container = await pumpThreeSegments(tester);

      final gesture = await holdSegment(tester, 1);
      await gesture.moveBy(const Offset(2000, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {1, 2});
    });

    testWidgets('拖出首段方向：圈到首段为止，不越界', (tester) async {
      final container = await pumpThreeSegments(tester);

      final gesture = await holdSegment(tester, 1);
      await gesture.moveBy(const Offset(-2000, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), const {0, 1});
    });

    testWidgets('手势取消：回到按下前的选中', (tester) async {
      final container = await pumpThreeSegments(tester);
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);

      final gesture = await holdSegment(tester, 2);
      await gesture.moveBy(const Offset(-600, 0));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});

      await gesture.cancel();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
    });

    testWidgets('多指起手不误判为长按圈选：选中保持为空', (tester) async {
      final container = await pumpThreeSegments(tester);

      final first = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_0'))),
      );
      final second = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_2'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);

      await second.up();
      await first.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });
  });

  group('圈选起手震一次', () {
    final total = const Duration(seconds: 30);

    Future<(ProviderContainer, FakeSelectionHapticController)> pumpHapticBand(
      WidgetTester tester, {
      bool memberReadonly = false,
    }) async {
      final haptic = FakeSelectionHapticController();
      await pumpBand(
        tester,
        engine: FakePlaybackEngine(duration: total),
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
        selectionHaptic: haptic,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      if (memberReadonly) {
        container
            .read(annotationMemberSchemeReadonlyProvider.notifier)
            .setLoaded(true);
      }
      return (container, haptic);
    }

    Future<TestGesture> holdSegment(WidgetTester tester, int index) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(Key('learning_segment_$index'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      return gesture;
    }

    testWidgets('长按成立震恰好一次；拖动跨边界、松手提交不额外震', (tester) async {
      final (container, haptic) = await pumpHapticBand(tester);

      final gesture = await holdSegment(tester, 0);
      await pumpSettle(tester);
      expect(haptic.impactCalls, 1);

      // 横拖跨过段边界：全程仍只震一次。
      await gesture.moveBy(const Offset(600, 0));
      await pumpSettle(tester);
      expect(haptic.impactCalls, 1);

      // 松手提交：不震。
      await gesture.up();
      await pumpSettle(tester);
      expect(haptic.impactCalls, 1);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
    });

    testWidgets('长按不动松手＝只选中落点段，仍恰好一次', (tester) async {
      final (container, haptic) = await pumpHapticBand(tester);

      final gesture = await holdSegment(tester, 1);
      await gesture.up();
      await pumpSettle(tester);

      expect(haptic.impactCalls, 1);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
    });

    testWidgets('手势取消回滚不额外震', (tester) async {
      final (container, haptic) = await pumpHapticBand(tester);

      final gesture = await holdSegment(tester, 2);
      await pumpSettle(tester);
      await gesture.moveBy(const Offset(-600, 0));
      await pumpSettle(tester);
      expect(haptic.impactCalls, 1);

      await gesture.cancel();
      await pumpSettle(tester);
      expect(haptic.impactCalls, 1);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });

    testWidgets('单击、横向快滑、点空白都不震', (tester) async {
      final (container, haptic) = await pumpHapticBand(tester);

      // 单击段体：点选语义，不震。
      await tester.tap(find.byKey(const Key('learning_segment_0')));
      await pumpSettle(tester);
      expect(haptic.impactCalls, 0);

      // 横向快滑（未过长按阈值）：不震。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('learning_segment_1'))),
      );
      await gesture.moveBy(const Offset(300, 0));
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);
      expect(haptic.impactCalls, 0);

      // 点空白（学习轨外的节拍轨行）：不震。
      await tester.tap(
        find.byKey(const Key('track_beat')),
        warnIfMissed: false,
      );
      await pumpSettle(tester);
      expect(haptic.impactCalls, 0);
      // 快滑＝清空后只选中这一段（既有语义），全程无震动。
      expect(container.read(selectedLearningSegmentsProvider), const {1});
    });

    testWidgets('组员方案只读：长按不进圈选也不震', (tester) async {
      final (container, haptic) = await pumpHapticBand(
        tester,
        memberReadonly: true,
      );

      final gesture = await holdSegment(tester, 1);
      await pumpSettle(tester);
      await gesture.up();
      await pumpSettle(tester);

      expect(haptic.impactCalls, 0);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });
  });

  group('长按判定区＝学习轨整行', () {
    final total = const Duration(seconds: 30);

    /// 线位可定制的三段轨 + 圈选起手震动的假实现（与统计页共用同一接缝）。
    Future<(ProviderContainer, FakeSelectionHapticController)> pumpWithLines(
      WidgetTester tester,
      List<Duration> lines,
    ) async {
      final haptic = FakeSelectionHapticController();
      await pumpBand(
        tester,
        engine: FakePlaybackEngine(duration: total),
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: [
            for (final position in lines) SegmentLine(position: position),
          ],
        ),
        selectionHaptic: haptic,
      );
      return (
        ProviderScope.containerOf(
          tester.element(find.byType(TrackBand)),
          listen: false,
        ),
        haptic,
      );
    }

    /// 长按某全局落点成立（越过长按阈值），返回在持手势。
    Future<TestGesture> holdAt(WidgetTester tester, Offset position) async {
      final gesture = await tester.startGesture(position);
      await tester.pump(const Duration(milliseconds: 700));
      return gesture;
    }

    double learningY(WidgetTester tester) =>
        tester.getCenter(find.byKey(const Key('learning_segment_0'))).dy;

    testWidgets('窄段：段体中心与线命中列内长按都成立，且与同点单击结果一致', (tester) async {
      // 段 1 = [15s, 16s)（约 25px，窄于 40px 线命中列）：两条线命中列把它
      // 整段盖住。
      final (container, haptic) = await pumpWithLines(tester, const [
        Duration(seconds: 15),
        Duration(seconds: 16),
      ]);
      final segment1Center = tester.getCenter(
        find.byKey(const Key('learning_segment_1')),
      );
      final segment0Center = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      final line0Center = tester.getCenter(
        find.byKey(const Key('segment_line_0')),
      );

      // 同一点单击：线窗只约束单击的触发，窗外回落段体 → 只选中该段。
      await tester.tapAt(segment1Center);
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});

      // 换个选中后同一点长按：一样只选中该段。
      await tester.tapAt(segment0Center);
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});

      final press = await holdAt(tester, segment1Center);
      await press.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(haptic.impactCalls, 1);

      // 线命中列正中心（离线段 ≤ 半宽）：按最近段解析并进入圈选，不因
      // 「命中到线」而落选。
      await tester.tapAt(segment0Center);
      await pumpSettle(tester);
      final onLine = await holdAt(tester, line0Center);
      await onLine.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(haptic.impactCalls, 2);
    });

    testWidgets('长按逐帧跨过分段线：实时圈选连续更新，不停顿', (tester) async {
      final (container, _) = await pumpWithLines(tester, const [
        Duration(seconds: 10),
        Duration(seconds: 20),
      ]);
      final segment0 = tester.getRect(
        find.byKey(const Key('learning_segment_0')),
      );

      final gesture = await holdAt(tester, segment0.center);
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});

      // 手指停在分段线右侧 5px（仍在线命中窗内，且已更近右段中心）：
      // 圈选当场延伸——逐帧解析不认线窗，跨线不停顿。
      await gesture.moveTo(Offset(segment0.right + 5, segment0.center.dy));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1});

      // 继续跨过第二条线：连续更新到末段。
      await gesture.moveBy(const Offset(300, 0));
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0, 1, 2});
    });

    testWidgets('长按落在首/尾线命中窗内：仍解析到首/末段，圈到边界为止', (tester) async {
      final (container, haptic) = await pumpWithLines(tester, const [
        Duration(seconds: 5),
        Duration(seconds: 20),
      ]);
      final y = learningY(tester);
      final first = tester.getRect(find.byKey(const Key('learning_segment_0')));
      final last = tester.getRect(find.byKey(const Key('learning_segment_2')));

      // 首线命中窗内（离片头 10px ≤ 半宽 20px）：钳到首段。
      final atStart = await holdAt(tester, Offset(first.left + 10, y));
      await atStart.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(haptic.impactCalls, 1);

      // 尾线命中窗内：钳到末段。
      final atEnd = await holdAt(tester, Offset(last.right - 10, y));
      await atEnd.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {2});
      expect(haptic.impactCalls, 2);
    });

    testWidgets('空白落点长按：不进圈选也不震', (tester) async {
      final haptic = FakeSelectionHapticController();
      await pumpBand(
        tester,
        engine: FakePlaybackEngine(duration: total),
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 20),
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
        selectionHaptic: haptic,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      final first = tester.getRect(find.byKey(const Key('learning_segment_0')));
      final bandLeft = tester
          .getTopLeft(find.byKey(const Key('track_band')))
          .dx;

      // 有效区间外（10s 之前）的带内空白：没有可圈的学习段。
      final before = await holdAt(
        tester,
        Offset(first.left - first.width, first.center.dy),
      );
      await before.up();
      await pumpSettle(tester);

      // 轨道片头带（时间轴零点之左）：空白。
      final prefix = await holdAt(
        tester,
        Offset(bandLeft + 10, first.center.dy),
      );
      await prefix.up();
      await pumpSettle(tester);

      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(haptic.impactCalls, 0);
    });
  });

  group('长按拖动圈选贴边滚屏', () {
    final total = const Duration(seconds: 30);

    Future<ProviderContainer> pumpThreeSegments(
      WidgetTester tester, {
      FakePlaybackEngine? engine,
    }) async {
      await pumpBand(
        tester,
        engine: engine ?? FakePlaybackEngine(duration: total),
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 10)),
            SegmentLine(position: Duration(seconds: 20)),
          ],
        ),
      );
      return ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
    }

    Future<TestGesture> holdSegment(WidgetTester tester, int index) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(Key('learning_segment_$index'))),
      );
      await tester.pump(const Duration(milliseconds: 700));
      return gesture;
    }

    /// 带右缘内 5px 的全局 x（边沿区内贴屏缘 = 满侵入深度）。
    double rightEdgeGlobalX(WidgetTester tester) {
      final origin = tester.getTopLeft(find.byKey(const Key('track_band')));
      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      return origin.dx + width - 5;
    }

    Future<void> pumpFrames(WidgetTester tester, int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    /// 长按段 0 后把手指拖到右缘（保持按住），返回该手势。
    Future<TestGesture> dragToRightEdge(WidgetTester tester, int index) async {
      final gesture = await holdSegment(tester, index);
      final startX = tester
          .getCenter(find.byKey(Key('learning_segment_$index')))
          .dx;
      await gesture.moveBy(Offset(rightEdgeGlobalX(tester) - startX, 0));
      await tester.pump();
      return gesture;
    }

    testWidgets('手指停在右缘：窗口持续右滚、圈选终点跟着延伸，滚动期间不 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpThreeSegments(tester, engine: engine);

      // seek 到 12s 再放大（锚点 = 预览线）：窗口 ≈ [10s, 15s]，
      // 首刻度离 t=0，贴边滚屏才有空间；预览线停在 x=320，避开起手点。
      await engine.seek(const Duration(seconds: 12));
      await tester.pump();
      await pinchOutward(tester, Offset(400, bandCenterY(tester)), travel: 200);
      await pumpSettle(tester);
      expect(tickIndexes(tester).first, greaterThan(0), reason: '前置：窗口已放大');

      final gesture = await dragToRightEdge(tester, 1);
      final seeksBeforeScroll = engine.seekCalls.length;
      final staticMax = container
          .read(selectedLearningSegmentsProvider)
          .reduce((a, b) => a > b ? a : b);
      final staticFirstTick = tickIndexes(tester).first;

      // 手指停在右缘不动：逐帧持续滚屏，窗口右移、圈选继续延伸。
      await pumpFrames(tester, 120);
      final scrolledFirstTick = tickIndexes(tester).first;
      expect(
        scrolledFirstTick,
        greaterThan(staticFirstTick),
        reason: '贴边滚屏：可视窗口持续向右平移',
      );
      expect(
        container
            .read(selectedLearningSegmentsProvider)
            .reduce((a, b) => a > b ? a : b),
        greaterThan(staticMax),
        reason: '圈选终点跟着滚出的段延伸',
      );
      // 滚屏期间不跳段首、不起播、不打断播放（无新增 seek）。
      expect(engine.seekCalls.length, seeksBeforeScroll);

      // 松手：提交圈选结果，滚屏一并停止（窗口不再变化）。
      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);
      await pumpFrames(tester, 10);
      expect(tickIndexes(tester).first, scrolledFirstTick, reason: '松手即停');
    });

    testWidgets('手指离开边缘即停止滚动，不再延伸', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpThreeSegments(tester, engine: engine);
      await engine.seek(const Duration(seconds: 15));
      await tester.pump();
      await pinchOutward(tester, Offset(400, bandCenterY(tester)), travel: 200);
      await pumpSettle(tester);

      final gesture = await dragToRightEdge(tester, 1);
      await pumpFrames(tester, 30);
      final selectionAtEdge = container.read(selectedLearningSegmentsProvider);
      final firstTickAtEdge = tickIndexes(tester).first;

      // 手指移回带中部（离开边沿区）→ 滚屏自停，窗口与圈选不再变。
      await gesture.moveBy(const Offset(-400, 0));
      await tester.pump();
      await pumpFrames(tester, 30);
      expect(tickIndexes(tester).first, firstTickAtEdge);
      expect(container.read(selectedLearningSegmentsProvider), selectionAtEdge);

      await gesture.up();
      await pumpSettle(tester);
    });

    testWidgets('滚到片尾/末段即停：窗口钳在界内、圈到末段为止，不越界', (tester) async {
      final container = await pumpThreeSegments(tester);

      final gesture = await dragToRightEdge(tester, 1);
      // 全宽窗口本就钳在 [0, total]：持续贴边也不越界，圈到末段为止。
      await pumpFrames(tester, 40);
      expect(tickIndexes(tester).length, 61);
      expect(tickIndexes(tester).first, 0);
      expect(container.read(selectedLearningSegmentsProvider), {1, 2});

      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), {1, 2});
    });

    testWidgets('圈到末段即停：窗口停在末段前（不等到片尾钳制）就不再滚', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpThreeSegments(tester, engine: engine);
      await engine.seek(const Duration(seconds: 12));
      await tester.pump();
      await pinchOutward(tester, Offset(400, bandCenterY(tester)), travel: 200);
      await pumpSettle(tester);

      // 窗口 ≈ [10s, 15s]：末段（20-30s）起手时不在窗内，贴边滚屏先滚出
      // 末段、命中钳住后即应停——窗口远未到片尾钳制点（25s）。
      final gesture = await dragToRightEdge(tester, 1);
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (container.read(selectedLearningSegmentsProvider).contains(2)) {
          break;
        }
      }
      expect(container.read(selectedLearningSegmentsProvider), {1, 2});
      final firstTick = tickIndexes(tester).first;
      expect(firstTick, lessThan(50), reason: '前置：窗口未到片尾钳制点(25s)');

      await pumpFrames(tester, 40);
      expect(tickIndexes(tester).first, firstTick, reason: '圈到末段即停');
      expect(container.read(selectedLearningSegmentsProvider), {1, 2});

      await gesture.up();
      await pumpSettle(tester);
    });

    testWidgets('手势取消回滚时滚屏一并停止，回到按下前的选中', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpThreeSegments(tester, engine: engine);
      await engine.seek(const Duration(seconds: 12));
      await tester.pump();
      await pinchOutward(tester, Offset(400, bandCenterY(tester)), travel: 200);
      await pumpSettle(tester);

      // 捏合起手清选中之后预置一个待回滚的选中。
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      await pumpSettle(tester);

      final gesture = await dragToRightEdge(tester, 1);
      await pumpFrames(tester, 20);

      await gesture.cancel();
      await pumpSettle(tester);
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      final firstTick = tickIndexes(tester).first;
      await pumpFrames(tester, 10);
      expect(tickIndexes(tester).first, firstTick, reason: '取消即停');
    });
  });

  Finder previewLine() => find.byKey(const Key('preview_line'));

  group('预览条：显示当前播放位置并随播放更新', () {
    testWidgets('预览条贯穿轨道带，位于当前位置 timeToX 处；seek 后移动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      // 初始 position 0 → 预览条贴左端（贯穿整带高）。
      expect(previewLine(), findsOneWidget);
      final bandHeight = tester
          .getSize(find.byKey(const Key('track_band')))
          .height;
      expect(
        tester.getSize(find.byKey(const Key('preview_line'))).height,
        bandHeight,
        reason: '预览条贯穿轨道（含轨间隙）',
      );

      // seek 到中点 → 预览条 x = timeToX(90s) = 半宽。
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      final laneWidth = tester
          .getSize(find.byKey(const Key('track_band')))
          .width;
      // 内容区左缘让出轨道片头带——期望值问模块同一口径。
      final axis = bandGeometryOf(
        total: const Duration(minutes: 3),
        width: laneWidth,
      ).axis;
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(axis.timeToX(const Duration(seconds: 90)), 1.0),
      );
    });

    testWidgets('播放推进时预览条随位置逐 tick 移动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      final before = tester.getCenter(find.byKey(const Key('preview_line'))).dx;

      await engine.play();
      await tester.pump(const Duration(seconds: 2)); // 播放 2s → position 92s
      await engine.pause();

      final laneWidth = tester
          .getSize(find.byKey(const Key('track_band')))
          .width;
      final axis = bandGeometryOf(
        total: const Duration(minutes: 3),
        width: laneWidth,
      ).axis;
      final after = tester.getCenter(find.byKey(const Key('preview_line'))).dx;
      expect(after, greaterThan(before));
      expect(after, closeTo(axis.timeToX(const Duration(seconds: 92)), 1.0));
    });

    testWidgets('播放头越出可视窗口（放大后播放）→ 窗口自动跟随，预览条保持可见', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();

      // 捏合放大到中段窗口（可视 < 全片）→ 早先刻度不可见。
      final y = bandCenterY(tester);
      await pinchOutward(tester, Offset(400, y));
      final before = tickIndexes(tester);
      expect(before.length, lessThan(361), reason: '放大后可视刻度变少');
      expect(before.contains(0), isFalse, reason: '窗口已离开 t=0');
      expect(before.contains(180), isTrue, reason: '锚点时间(90s)刻度仍在窗口内');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(400, 2.0),
        reason:
            '缩放以焦点(=预览条)为锚；窗口起点 > 0 后让位收回'
            '，90s 仍在窗内 50% → 400',
      );

      // 播放 40s：播放头越出窗口右缘 → 跟随平移（窗口向右追），预览条不消失。
      await engine.play();
      await tester.pump(const Duration(seconds: 40));
      await engine.pause();
      await tester.pump();

      expect(engine.isPlaying, isFalse);
      expect(previewLine(), findsOneWidget);
      final after = tickIndexes(tester);
      expect(after.first, greaterThan(before.first), reason: '窗口已右移跟随播放头');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        inInclusiveRange(0, 800),
      );
    });

    testWidgets('微调 scrub 落点越出可视窗口 → 位置 tick 跟随平移', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();

      // 捏合放大到中段窗口（可视 30s ≈ [75s, 105s]，锚点 = 预览线 90s）。
      final y = bandCenterY(tester);
      await pinchOutward(tester, Offset(400, y), travel: 200);
      final before = tickIndexes(tester);
      expect(before.length, lessThan(361), reason: '放大后可视刻度变少');

      // 带内空白横滑 = 微调 scrub（起手点避开预览线命中列）：累计 700px
      // × 50ms = 35s → 目标 125s 越出窗口右缘 → 位置 tick 跟随平移。
      final g = await tester.startGesture(Offset(200, y));
      await tester.pump();
      for (var i = 0; i < 7; i++) {
        await g.moveBy(const Offset(100, 0));
        // 过 seek 节流窗：落点逐帧落定 → 位置 tick 当场跟随（不等松手）。
        await tester.pump(const Duration(milliseconds: 20));
      }
      final during = tickIndexes(tester);
      expect(during.first, greaterThan(before.first), reason: '拖动中窗口已跟随落点');
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls.last, const Duration(seconds: 125));
      final after = tickIndexes(tester);
      expect(after.first, greaterThan(before.first), reason: '松手后窗口仍在落点处');
      expect(
        tester.getCenter(previewLine()).dx,
        inInclusiveRange(0, 800),
        reason: '跟随平移后预览线保持可见',
      );
    });
  });

  group('拖动预览条：帧级 seek（空白横滑 = 精细调整）', () {
    testWidgets('水平拖动轨道带空白 → 目标 = 累计位移 × 单指灵敏度', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      // 从中点(400) 向右拖 300 → 累计 300px × 50ms = 15s（与手指终点
      // x=700 的绝对位置 157.5s 无关）。
      await tester.drag(
        find.byKey(const Key('track_band')),
        const Offset(300, 0),
      );
      await pumpSettle(tester);

      final target = const Duration(seconds: 15);
      expect(engine.seekCalls, isNotEmpty);
      expect(engine.seekCalls.last, target);
      expect(engine.position, target);
      // 原暂停起手：微调只 seek、不播不停。
      expect(engine.callLog.where((c) => c == 'play' || c == 'pause'), isEmpty);
    });

    testWidgets('单击（未拖动）不触发 seek——预览条单击不算拖动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      engine.seekCalls.clear(); // 清掉测试自身 seek 的记录

      // 单击预览条所在位置 / 轨道带任意空白：均不 seek（空白判定归）。
      // 预览条 IgnorePointer（纯视觉），tap 落在其下的轨道带手势层。
      await tester.tap(find.byKey(const Key('track_band')));
      await tester.pump();
      await tester.tap(
        find.byKey(const Key('preview_line')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(engine.seekCalls, isEmpty);
      expect(engine.position, const Duration(seconds: 90));
    });

    testWidgets('竖直拖动（先垂直）不算预览条拖动：不 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      await tester.drag(
        find.byKey(const Key('track_band')),
        const Offset(0, 60),
      );
      await pumpSettle(tester);
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('斜向起手（早期纵向抖动后横向主导）仍进入拖动 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = bandCenterY(tester);

      // 起手先有轻微纵向抖动（轴锁定不得把整场误判为垂直忽略）……
      final g = await tester.startGesture(Offset(200, y));
      await tester.pump();
      await g.moveBy(const Offset(1, 8));
      await tester.pump();
      await g.moveBy(const Offset(1, 8));
      await tester.pump();
      // ……随后横向主导拖动到 x ≈ 200+2+300 = 502。
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(30, 0));
        await tester.pump();
      }
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls, isNotEmpty);
      // 锁定后逐帧 forwarded 的累计横向位移 = 10 × 30px → 15s（起手纵向
      // 抖动不计入目标）。
      final target = const Duration(seconds: 15);
      expect(engine.seekCalls.last, target);
      expect(engine.position, target);
    });
  });

  group('拖动跟手与性能（空白横滑 = 精细调整）', () {
    testWidgets('轴锁定起手的前段位移立即生效：锁定帧增量即进入微调目标', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = bandCenterY(tester);

      // 位移越过 slop 的首次 move 同时回调 start + update（含 slop 前后
      // 全部前段位移）：锁定帧增量立即计入微调目标，不等到下一次 move。
      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await g.moveBy(const Offset(30, 0));
      await pumpSettle(tester);

      expect(engine.seekCalls, isNotEmpty);
      expect(
        engine.seekCalls.first,
        seekDeltaFor(30, 1),
        reason: '锁定帧增量立即计入目标（前段位移不丢）',
      );
      await g.up();
      await pumpSettle(tester);
    });

    testWidgets('拖动序列逐帧推进：预览线随目标时间走（不贴手指）、松手收敛到累计落点', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(
        tester,
        engine: engine,
        onCollapse: () => collapses.value++,
      );
      final y = bandCenterY(tester);

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      // 越过 slop 的首次 move 即轴锁定并立即生效。
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      // 逐帧拖动：预览线（与入队 seek 同源）随目标时间移动——目标按累计
      // 位移走，不贴手指。
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await g.up();
      await pumpSettle(tester);

      // 松手收敛到最终落点：累计 30 + 12 × 10 = 150px → 7.5s。
      final finalTarget = const Duration(milliseconds: 7500);
      expect(
        engine.seekCalls.length,
        lessThanOrEqualTo(13),
        reason: '每帧至多一次 seek',
      );
      expect(engine.seekCalls.last, finalTarget);
      expect(engine.position, finalTarget, reason: '松手落点与目标一致');
      expect(
        tester.getCenter(previewLine()).dx,
        closeTo(bandX(7.5, total: 180), 2),
        reason: '预览线随目标时间移动、不贴手指（手指终点 x=580）',
      );
      expect(collapses.value, 0, reason: '拖动会话不触发空白收起');
    });

    testWidgets('播放中横滑语义回归：起手定格、松手按手势前播放态恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = bandCenterY(tester);

      await engine.play();
      await tester.pump(const Duration(milliseconds: 300));
      engine.callLog.clear();
      engine.seekCalls.clear();
      final baseAtPause = engine.position;

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.moveBy(const Offset(60, 0));
      await tester.pump();

      // 起手即定格：先 pause 再逐帧 seek（ScrubSession 不变量）。
      expect(engine.callLog.first, 'pause');
      expect(engine.isPlaying, isFalse);
      await g.up();
      await pumpSettle(tester);

      // 松手恢复手势前播放态，从累计落点（定格基准 + 90px → 4.5s）继续推进。
      expect(engine.callLog, contains('play'));
      final finalTarget = baseAtPause + const Duration(milliseconds: 4500);
      expect(engine.seekCalls.last, finalTarget);
      expect(engine.isPlaying, isTrue);
      final posAtRelease = engine.position;
      await tester.pump(FakePlaybackEngine.tick);
      expect(engine.position, greaterThan(posAtRelease));
      // 收尾停播（清掉播放周期 timer，测试不变量：结束无 pending timer）。
      await engine.pause();
    });
  });

  group('拖动贴近屏幕边缘：自动平移轨道显示范围（经预览线命中列路径）', () {
    // 带内空白横滑改走精细调整（目标按位移走、无手指位置），
    // 贴边平移 + 绝对跟手 seek 归预览线命中列接管路径（手柄带）。
    testWidgets('全宽时拖出右缘：seek 到结尾、窗口保持全宽（无处可平移）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      // 预览线 seek 到 x=700（157.5s），从其命中列（手柄带）起手。
      await engine.seek(const Duration(milliseconds: 157500));
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');

      final g = await tester.startGesture(Offset(700, y));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(15, 0)); // 越出带宽（>800）被钳到右缘
        await tester.pump();
      }
      await g.up();
      await pumpSettle(tester);

      // 全宽右缘 = 结尾；窗口无处可平移 → 刻度集合不变。
      expect(engine.seekCalls, isNotEmpty);
      expect(engine.position, const Duration(minutes: 3));
      expect(tickIndexes(tester).length, 361);
    });
    testWidgets('放大后向右拖过可视窗口右缘 → 窗口随拖平移、继续越过可视 seek', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      final y = bandCenterY(tester);

      // 先放大（可视窗口 < 全片）——记录窗口最左可见刻度。
      await pinchOutward(tester, Offset(400, y));
      final before = tickIndexes(tester);
      expect(before.first, greaterThan(0));

      // 从预览线当前位置的命中列（手柄带）起手，向右持续拖过右缘：
      // 起平移为时间平滑累积——每帧按侵入深度速度平移窗口再换算目标 →
      // seek 目标越过原可视窗口右端、窗口最左刻度右移。
      final px = tester.getCenter(previewLine()).dx;
      final g = await tester.startGesture(
        Offset(px, trackRowCenterY(tester, 'track_handle_strip_row')),
      );
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await g.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls, isNotEmpty);
      final after = tickIndexes(tester);
      expect(after.first, greaterThan(before.first), reason: '可视窗口已向右平移');
      expect(engine.position, greaterThanOrEqualTo(Duration.zero));
      expect(engine.position, lessThanOrEqualTo(const Duration(minutes: 3)));
    });
  });

  group('缩放滑条：时间密度', () {
    testWidgets('滑条置最大：以播放头为锚放大 → 预览条 x 不变、刻度按窗口重排', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();

      // 全宽：361 根刻度（每拍一根 @120bpm，0..180s 闭窗）、预览条在中点。
      expect(tickIndexes(tester).length, 361);

      // 滑到最右（最细可视 2s，锚定播放头 90s）。
      final slider = find.byKey(const Key('track_zoom_slider'));
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
      await tester.pump();

      // 缩放后预览条所在时间不变；窗口起点离开 0 后片头让位收回、整带宽
      // 归内容，锚时间 90s 仍在窗口 [89s,91s] 中点 → 带宽中点。
      final after = tester.getCenter(find.byKey(const Key('preview_line'))).dx;
      expect(
        after,
        closeTo(400, 2.0),
        reason: '窗口 [89s,91s] 起点 > 0：让位收回，90s 在满带宽中点',
      );
      // 节拍刻度随新密度重排：只剩 90s 拍（锚定时间仍在窗口内）。
      final zoomed = tickIndexes(tester);
      expect(zoomed, contains(180)); // 90s 拍
      expect(zoomed.length, lessThan(6));
      expect(zoomed.contains(0), isFalse);
      // 引擎位置不变（缩放不改播放位置）。
      expect(engine.position, const Duration(seconds: 90));

      // 滑回最左 → 恢复全宽、刻度全回来。
      await tester.tapAt(Offset(rect.left + 2, rect.center.dy));
      await tester.pump();
      expect(tickIndexes(tester).length, 361);
    });

    testWidgets('视频过短（无可缩放空间）→ 缩放滑条禁用', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
      await pumpBand(tester, engine: engine);

      final slider = tester.widget<Slider>(
        find.byKey(const Key('track_zoom_slider')),
      );
      expect(slider.onChanged, isNull);
    });
  });

  group('双指捏合缩放', () {
    testWidgets('张开放大：锚点=焦点时间，预览条 x 不变、刻度重排；收拢缩回全宽', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      final y = bandCenterY(tester);
      expect(tickIndexes(tester).length, 361);

      // 以预览条(400)为焦点张开 → 放大。
      await pinchOutward(tester, Offset(400, y));
      final zoomed = tickIndexes(tester);
      expect(zoomed.length, lessThan(361));
      expect(zoomed, isNot(contains(0)));
      expect(zoomed, contains(180), reason: '锚定时间 90s 仍在窗口内');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(400, 2.0),
        reason:
            '缩放以焦点为锚：锚 90s 保持窗内比例；窗口起点 > 0 后让位'
            '收回，90s 仍在窗口中点 → 带宽中点',
      );
      expect(engine.position, const Duration(seconds: 90));

      // 收拢（向内）→ 缩回直到全宽：全部刻度恢复。双指从放大终点跨度
      // (260..540) 回到起始跨度 (360..440) → scale ≈ 80/280 < 1。
      final g1 = await tester.startGesture(Offset(260, y));
      final g2 = await tester.startGesture(Offset(540, y));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(25, 0));
        await g2.moveBy(const Offset(-25, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump();
      expect(tickIndexes(tester).length, 361);
    });
  });

  group('双指缩放+平移联动', () {
    testWidgets('双指张开且中点右移：缩放生效、内容跟手（预览条随中点位移）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await tester.pump();
      final y = bandCenterY(tester);

      // 双指按下（中点 400）→ g2 独自右移 160px（跨度 80→240 = 放大 3×、
      // 中点右移 80px）：窗口以锚缩放到 [80s,100s] 再左移 80px（=2s）→
      // [78s,98s]；锚时间 90s（=预览条）跟手移到 x=480。
      final g1 = await tester.startGesture(Offset(360, y));
      final g2 = await tester.startGesture(Offset(440, y));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(Offset.zero);
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump();

      final ticks = tickIndexes(tester);
      expect(ticks.length, lessThan(361), reason: '张合缩放仍生效');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(480, 6),
        reason:
            '焦点（双指中点）右移 → 窗口平移、锚时间内容跟手；'
            '窗口 [78s,98s] 起点 > 0 后让位收回，90s 在窗内 60%'
            ' → 0.6 × 800 = 480',
      );
      expect(engine.seekCalls, [
        const Duration(seconds: 90),
      ], reason: '双指会话内不做进度 seek（仅保留测试预置的那次 seek）');
    });

    testWidgets('双指中点左移贴 0 缘：平移钳制不越界（窗口不越出 [0, total]）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = bandCenterY(tester);

      // 中点大幅左移（远超全宽窗口可平移空间）→ 钳制贴 0：tick 0 仍可见。
      final g1 = await tester.startGesture(Offset(500, y));
      final g2 = await tester.startGesture(Offset(580, y));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g1.moveBy(const Offset(-80, 0));
        await g2.moveBy(const Offset(-80, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump();

      expect(tickIndexes(tester), contains(0), reason: '窗口左移钳制贴 0');
    });
  });

  group('捏合锚点取预览线', () {
    testWidgets('预览线在窗口内：原地双指放大后预览线屏上 x 不变（焦点≠预览线）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      final y = bandCenterY(tester);

      // 预览线在 x=400（90s），双指中点在 x=600（135s）张开 → 锚 = 预览线
      // 90s：线在屏上的位置纹丝不动、线附近被铺开。
      await pinchOutward(tester, Offset(600, y));

      expect(tickIndexes(tester).length, lessThan(361), reason: '放大生效');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(400, 2.0),
        reason:
            '锚 = 预览线：90s 保持窗内比例不动；放大后窗口起点 > 0，'
            '让位收回满带宽摊开，90s 仍在窗内 50% → 400',
      );
    });

    testWidgets('预览线在窗口外：放大仍按手指中点进行（焦点附近内容被铺开）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      final y = bandCenterY(tester);

      // 先以预览线为锚放大（窗口 ≈ [64s,116s]），再纯平移把预览线推出
      // 窗口（右缘 < 90s）；随后在 x=200 处捏合：锚 = 手指焦点时间（≈46s），
      // 而不是被钳到窗口边缘的预览线时间（90s）。
      await pinchOutward(tester, Offset(600, y));
      final g1 = await tester.startGesture(Offset(300, y));
      final g2 = await tester.startGesture(Offset(500, y));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await g1.moveBy(const Offset(40, 0));
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump();
      expect(
        find.byKey(const Key('preview_line')),
        findsNothing,
        reason: '前置：预览线已被平移出可视窗口',
      );

      await pinchOutward(tester, Offset(200, y));

      final ticks = tickIndexes(tester);
      expect(ticks.length, lessThan(361), reason: '放大仍生效');
      expect(
        ticks,
        contains(90),
        reason:
            '锚 = 手指焦点（≈46s）：焦点附近内容留在窗口内铺开；'
            '若误以窗外预览线为锚，窗口会贴到 [75s,90s] 附近而看不到 45s',
      );
      expect(engine.position, const Duration(seconds: 90));
    });

    testWidgets('放大后继续双指平移可把预览线推出窗口，焦点不跳回预览线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      await engine.seek(const Duration(seconds: 90));
      await engine.pause();
      await tester.pump();
      final y = bandCenterY(tester);

      // 以预览线（x=400）为锚放大 → 继续双指右移（纯平移）把预览线推出
      // 窗口右缘：窗口不因播放头越出而拉回（捏合会话自己管窗口、锚整场
      // 不重算）。
      await pinchOutward(tester, Offset(400, y));
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        closeTo(400, 2.0),
        reason:
            '前置：预览线在窗口内（放大后窗口起点 > 0，让位收回 '
            '，90s 仍在窗内 50% → 400）',
      );
      final g1 = await tester.startGesture(Offset(300, y));
      final g2 = await tester.startGesture(Offset(500, y));
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await g1.moveBy(const Offset(40, 0));
        await g2.moveBy(const Offset(40, 0));
        await tester.pump();
      }
      await g1.up();
      await g2.up();
      await tester.pump();

      expect(
        find.byKey(const Key('preview_line')),
        findsNothing,
        reason: '双指平移把预览线推出可视窗口',
      );
      final ticks = tickIndexes(tester);
      expect(ticks.length, lessThan(361), reason: '仍处放大态');
      expect(ticks, contains(80), reason: '窗口停在预览线左侧（30s 附近，看更早内容），没有被拉回预览线');
      expect(engine.position, const Duration(seconds: 90), reason: '平移不改变播放位置');
    });
  });

  group('收起语义（轨道带单击收起）', () {
    Future<void> pumpCollapsible(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
      required ValueNotifier<int> collapses,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onCollapse: () => collapses.value++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
    }

    testWidgets('单击轨道带空白 → 经约 300ms 判定窗口后 onCollapse 一次', (tester) async {
      final collapses = ValueNotifier<int>(0);
      await pumpCollapsible(
        tester,
        engine: FakePlaybackEngine(duration: const Duration(minutes: 3)),
        collapses: collapses,
      );
      await tester.tap(find.byKey(const Key('track_band')));
      // 判定窗口内：尚未收起（双击共存语义）。
      await tester.pump();
      expect(collapses.value, 0);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(collapses.value, 1);
    });

    testWidgets('空白区单指双击 → onDoubleTap（收起 + 切播放），不触发单击收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      var doubleTaps = 0;
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onCollapse: () => collapses.value++,
                  onDoubleTap: () => doubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
      final center = tester.getCenter(
        find.byKey(const Key('track_handle_strip_row')),
      );
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      // 第二击即触发，不等判定窗口（收起由接收方 onDoubleTap 处理器一并
      // 完成——见 control_layer 集成断言；轨道带只负责手势判定）。
      expect(doubleTaps, 1);
      // 双击吞掉序列：窗口过后不触发孤立单击收起。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(doubleTaps, 1);
      expect(collapses.value, 0);
    });

    // 跨面双指会话在场（生产同款）时，带内 ≥2 指一律是「缩放+平移」会话：
    // 本 burst 的单指语义与双指 tap 一并抑制，带级 onTwoFingerDoubleTap
    // 不触发（空白面的双指双击由 control_layer_test 覆盖）。
    testWidgets('带内双指 = 跨面双指会话：双指双击不触发 onTwoFingerDoubleTap', (tester) async {
      var twoFingerDoubleTaps = 0;
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
      final center = tester.getCenter(
        find.byKey(const Key('track_handle_strip_row')),
      );
      Future<void> twoFingerTap() async {
        final g1 = await tester.startGesture(center);
        final g2 = await tester.startGesture(center + const Offset(30, 0));
        await tester.pump(const Duration(milliseconds: 50));
        await g1.up();
        await tester.pump(const Duration(milliseconds: 10));
        await g2.up();
        await tester.pump(const Duration(milliseconds: 50));
      }

      await twoFingerTap();
      await tester.pump(const Duration(milliseconds: 50));
      await twoFingerTap();
      await tester.pump(const Duration(milliseconds: 50));
      expect(twoFingerDoubleTaps, 0, reason: '带内双指归缩放会话，双指 tap 被抑制');
      // 双指单击（孤立）不触发单击收起路径。
      await tester.pump(kDoubleTapTimeout);
      expect(twoFingerDoubleTaps, 0);
    });

    testWidgets('水平拖动（预览条 seek）不触发 onCollapse', (tester) async {
      final collapses = ValueNotifier<int>(0);
      await pumpCollapsible(
        tester,
        engine: FakePlaybackEngine(duration: const Duration(minutes: 3)),
        collapses: collapses,
      );
      await tester.drag(
        find.byKey(const Key('track_band')),
        const Offset(300, 0),
      );
      await pumpSettle(tester);
      expect(collapses.value, 0);
    });

    testWidgets('系统取消的静止触摸（edge 手势抢占）不触发 onCollapse', (tester) async {
      final collapses = ValueNotifier<int>(0);
      await pumpCollapsible(
        tester,
        engine: FakePlaybackEngine(duration: const Duration(minutes: 3)),
        collapses: collapses,
      );
      // 按下后被系统取消（非正常抬起）：不是单击，不收起。
      final g = await tester.startGesture(const Offset(400, 30));
      await tester.pump();
      await g.cancel();
      await pumpSettle(tester);
      expect(collapses.value, 0);
    });
  });

  group('视频首/尾线', () {
    testWidgets('默认全片区间渲染贯穿首尾线、位置与总长一致', (tester) async {
      final total = const Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
      );

      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      final height = tester.getSize(find.byKey(const Key('track_band'))).height;
      final axis = bandGeometryOf(total: total, width: width).axis;
      for (final key in const [
        Key('video_range_start_line'),
        Key('video_range_end_line'),
        Key('video_range_start_marker'),
        Key('video_range_end_marker'),
      ]) {
        expect(find.byKey(key), findsOneWidget);
      }
      expect(
        tester.getSize(find.byKey(const Key('video_range_start_line'))).height,
        height,
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_start_line'))).dx,
        closeTo(axis.timeToX(Duration.zero), 1.0),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_end_line'))).dx,
        closeTo(axis.timeToX(total), 1.0),
      );
    });

    testWidgets('按下即拖首线：无需长按，位置换算回调；无网格自由落点', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
        ),
      );

      final center = tester.getCenter(
        find.byKey(const Key('video_range_start_marker')),
      );
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await dragBySteps(
        tester,
        gesture,
        const Offset(100, 0),
      ); // 100 px = 22.5s。
      await gesture.up();
      await pumpSettle(tester);

      // 写入经模块拖动会话（SetVideoRange 同一归一化钳制）。
      // 100px 按内容区宽（760px ↔ 180s）换算 = 23.68s → 落点
      // 33.68s，按就绪均匀网格（0.5s 拍点）归格为 33.5s。
      expect(
        bandTimeline(tester).rangeStart,
        const Duration(milliseconds: 33500),
      );
      expect(bandTimeline(tester).rangeEnd, const Duration(seconds: 100));
    });

    testWidgets('按下即拖尾线：无需长按，位置换算回调；无网格自由落点', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
        ),
      );

      final center = tester.getCenter(
        find.byKey(const Key('video_range_end_marker')),
      );
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await dragBySteps(
        tester,
        gesture,
        const Offset(-200, 0),
      ); // -200 px = -45s。
      await gesture.up();
      await pumpSettle(tester);

      expect(bandTimeline(tester).rangeStart, const Duration(seconds: 10));
      // -200px 按内容区宽换算 = -47.37s → 落点 52.63s，按就绪
      // 均匀网格归格为 52.5s。
      expect(
        bandTimeline(tester).rangeEnd,
        const Duration(milliseconds: 52500),
      );
    });

    testWidgets('按下即拖首线：预览 seek 不动预览线、不触发收起', (tester) async {
      const total = Duration(minutes: 3);
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
        onCollapse: () => collapses.value++,
      );
      // 适配：整片视图首线贴带左缘（x≈0），预览线初始也停在 0 →
      // 首线起手落在预览线命中列内会被接管为预览线拖动。先 seek 离开命中
      // 列；本用例测拖线的预览语义（接管语义由专项用例覆盖）。
      await engine.seek(const Duration(seconds: 60));
      await pumpSettle(tester);
      final initialPos = engine.position;
      engine.seekCalls.clear();
      final beforeX = tester
          .getCenter(find.byKey(const Key('preview_line')))
          .dx;

      final center = tester.getCenter(
        find.byKey(const Key('video_range_start_marker')),
      );
      final gesture = await tester.startGesture(center);
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(120, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 拖动起手在线上：调界走首/尾线换算；预览 seek 只作画面逐帧
      // 预览（目标=边界位置），不是预览条 scrub——预览线不随动、松手回
      // 原位、不收起。
      expect(engine.seekCalls, isNotEmpty, reason: '拖线实时预览 seek');
      expect(engine.seekCalls.last, initialPos, reason: '松手回预览线位置');
      expect(
        tester.getCenter(find.byKey(const Key('preview_line'))).dx,
        beforeX,
        reason: '预览线不随拖线移动',
      );
      expect(collapses.value, 0);
    });

    testWidgets('单击首线进入选中加粗态，且不触发收起', (tester) async {
      final total = const Duration(minutes: 3);
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
        onCollapse: () => collapses.value++,
      );

      final line = find.byKey(const Key('video_range_start_line'));
      expect(tester.getSize(line).width, kVideoRangeLineWidth);
      // 适配：默认播放头 0s 与首线（x=0）重合，预览线 2px 命中柱
      // 置顶后会吸收线心点击；先 seek 让预览线离开线位再验证首线点选加粗
      //（重合点击归属由专项用例覆盖，行为不变）。
      await engine.seek(const Duration(seconds: 60));
      await pumpSettle(tester);
      await tester.tap(line);
      await pumpSettle(tester);

      expect(tester.getSize(line).width, kVideoRangeSelectedLineWidth);
      expect(collapses.value, 0);
    });

    testWidgets('单击首/尾线是交互动作，不触发轨道空白收起', (tester) async {
      final total = const Duration(minutes: 3);
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
        onCollapse: () => collapses.value++,
      );
      await tester.tap(find.byKey(const Key('video_range_start_line')));
      await pumpSettle(tester);
      expect(collapses.value, 0);
    });
  });

  group('轨道手柄带拖动模型', () {
    final total = const Duration(seconds: 30);

    AnnotationTimeline linesAt(List<Duration> positions) {
      return AnnotationTimeline.normalized(
        videoDuration: total,
        segmentLines: [
          for (final position in positions) SegmentLine(position: position),
        ],
      );
    }

    testWidgets('分段线与首尾线在手柄带各有短横条手柄（底行轨道手柄带行）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: linesAt([const Duration(seconds: 10)]),
      );

      final stripRow = tester.getRect(
        find.byKey(const Key('track_handle_strip_row')),
      );
      // 分段线获得与首尾线端标同款式的短横条手柄，全部落在手柄带行内。
      for (final key in const [
        Key('segment_line_0_handle'),
        Key('video_range_start_marker'),
        Key('video_range_end_marker'),
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key 存在');
        final rect = tester.getRect(find.byKey(key));
        expect(rect.top, greaterThanOrEqualTo(stripRow.top));
        expect(rect.bottom, lessThanOrEqualTo(stripRow.bottom));
      }
      // 手柄条以线心居中：分段线 10s → x=266.7；首/尾线贴带缘 → 外扩
      // 补偿后手柄条仍在带内（中心分别约 12 / 788）。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))).dx,
        closeTo(bandX(10), 1),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_start_marker'))).dx,
        closeTo(bandX(0), 1),
      );
      expect(
        tester.getCenter(find.byKey(const Key('video_range_end_marker'))).dx,
        closeTo(bandXOf(total, total: total, width: 800) - 12, 1),
      );
    });

    testWidgets('手柄单击 = 线身单击：toggle 选中', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: linesAt([const Duration(seconds: 10)]),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tester.tap(find.byKey(const Key('segment_line_0_handle')));
      await pumpSettle(tester);
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 0);

      await tester.tap(find.byKey(const Key('segment_line_0_handle')));
      await pumpSettle(tester);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
      );
    });

    testWidgets('线身拖动不再移动线：整列按下拖动回落为空白精细调整', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: linesAt([const Duration(seconds: 5)]),
      );
      engine.seekCalls.clear();

      // 从分段线线身（节拍轨高度）按下横拖：不调线、不调界，回落为带内
      // 空白精细调整（目标 = 累计位移 × 单指灵敏度）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 线不动；微调 seek 生效（累计 160px → 8s，与手指终点无关）。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
        reason: '线身拖动不移动线',
      );
      expect(engine.seekCalls.last, const Duration(seconds: 8));
    });

    testWidgets('首尾线线身拖动不再调界：回落为预览条 scrub', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
        ),
      );
      engine.seekCalls.clear();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('video_range_start_line'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(120, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).rangeStart,
        const Duration(seconds: 10),
        reason: '线身拖动不调界',
      );
      expect(engine.seekCalls, isNotEmpty, reason: '线身拖动回落为 scrub');
    });

    testWidgets('手柄带行空白横滑走精细调整：拖动可跨过线列不被抢', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: linesAt([const Duration(seconds: 5)]),
      );
      engine.seekCalls.clear();

      // 从手柄带行内空白（x=300）左拖到 x=100：路径跨过分段线列与手柄槽。
      final stripY = trackRowCenterY(tester, 'track_handle_strip_row');
      final gesture = await tester.startGesture(Offset(300, stripY));
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(-200, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 线不动；微调目标 = -200px × 50ms，自 0 基准钳到 0。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
      );
      expect(engine.seekCalls.last, Duration.zero);
    });

    testWidgets('手柄槽重叠时命中优先级：分段线 > 首/尾线', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: linesAt([const Duration(milliseconds: 29500)]),
      );

      // 分段线 29.5s（x≈787.3）与尾线 30s（x=800）相距 12.7dp < 24 → 两
      // 槽紧邻（分段线槽在上）；按下 x=790 命中分段线手柄（线 > 首尾，栈序
      // 分段线在上），左拖 60px 应移动分段线而非尾线。
      final stripY = trackRowCenterY(tester, 'track_handle_strip_row');
      final gesture = await tester.startGesture(Offset(790, stripY));
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(-60, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(bandTimeline(tester).rangeEnd, total, reason: '尾线不被拖动');
      // 分段线 x 787.3 → 727.3（27.15s），吸附四拍格（2s）落到 28s。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(28), 1),
      );
    });
  });

  group('首尾线命中几何（贴边不被裁）', () {
    testWidgets('整片视图贴屏边首线：命中带内侧半宽按下即拖仍可抓取', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
      );

      // 适配：预览线初始停在 0，与贴边首线重合 → 起手在预览线命中
      // 列内会被接管为预览线拖动。先 seek 离开命中列；本用例测贴边命中
      // 几何，接管语义由专项用例覆盖。
      await engine.seek(const Duration(seconds: 60));
      await pumpSettle(tester);

      // 首线贴内容区左缘（x=40，片头在它之左）：从内侧 x=+6、
      // 轨道手柄带行内按下拖动——贴边线屏内仍可抓。
      final band = tester.getRect(find.byKey(const Key('track_band')));
      final stripY = trackRowCenterY(tester, 'track_handle_strip_row');
      final gesture = await tester.startGesture(
        Offset(band.left + kTrackPrefixWidth + 6, stripY),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);

      expect(bandTimeline(tester).rangeStart, greaterThan(Duration.zero));
      expect(
        bandTimeline(tester).rangeStart,
        lessThan(const Duration(seconds: 30)),
      );
    });

    testWidgets('整片视图尾线贴右缘：轨道带底行（手柄带一带）按下即拖仍可抓取', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
      );

      // 尾线贴带右缘（x=w）：手柄槽补偿为 [w-24,w]，从手柄带行高度、贴右缘
      // 内侧按下左拖——起手落在尾线手柄上拖动尾线（带内无 dock，
      // 不再有让位争抢）。
      final band = tester.getRect(find.byKey(const Key('track_band')));
      final gesture = await tester.startGesture(
        Offset(band.right - 4, band.bottom - 8),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);

      expect(bandTimeline(tester).rangeEnd, lessThan(total));
      expect(
        bandTimeline(tester).rangeEnd,
        greaterThan(const Duration(minutes: 2, seconds: 30)),
      );
    });
  });

  group('设置簇迁出轨道带（带外右上 [预览吸附｜滑条｜延迟循环]）', () {
    testWidgets('簇位于轨道带外（带上方）右对齐成组，组序 预览吸附→滑条→延迟循环；带内不再渲染 dock', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      final band = tester.getRect(find.byKey(const Key('track_band')));
      final previewSlot = tester.getRect(
        find.byKey(const Key('track_preview_snap_slot')),
      );
      final zoom = tester.getRect(find.byKey(const Key('track_zoom_dock')));
      final lock = tester.getRect(find.byKey(const Key('layout_lock_toggle')));

      // 带外（带上方）：簇全体底边不进入轨道带内。
      expect(previewSlot.bottom, lessThanOrEqualTo(band.top + 1));
      expect(lock.bottom, lessThanOrEqualTo(band.top + 1));
      expect(zoom.bottom, lessThanOrEqualTo(band.top + 1));
      // 右对齐、固定右缘（不再随尾线手柄让位）。
      final cluster = tester.getRect(find.byKey(const Key('settings_cluster')));
      expect(cluster.right, lessThanOrEqualTo(band.right));
      expect(cluster.right, greaterThan(band.right - 16));
      // 组序：预览吸附 < 锁定分段 < 缩放滑条（前导退场、滑条靠右）。
      expect(previewSlot.right, lessThanOrEqualTo(lock.left));
      expect(lock.right, lessThanOrEqualTo(zoom.left));
      // 放大镜：滑条左侧的纯装饰图标（不承载点击，行为用例见下）。
      expect(
        find.descendant(
          of: find.byKey(const Key('track_zoom_dock')),
          matching: find.byIcon(Icons.search),
        ),
        findsOneWidget,
      );
      // 带内不渲染 dock：设置簇控件都不在轨道带矩形内。
      for (final rect in [previewSlot, zoom, lock]) {
        expect(
          rect.intersect(band).isEmpty,
          isTrue,
          reason: '设置簇不得占轨道带内：$rect 与 $band 相交',
        );
      }
    });

    testWidgets('无时间线（引擎时长未知）时整簇隐藏', (tester) async {
      final engine = _DurationlessEngine();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SettingsCluster(
                    session: buildTrackBandSession(engine: engine),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      expect(find.byKey(const Key('settings_cluster')), findsNothing);
      expect(find.byKey(const Key('track_zoom_dock')), findsNothing);
      expect(find.byKey(const Key('delayed_loop_menu')), findsNothing);
    });

    testWidgets('前导选择器退场：入口不存在，默认档位仍 4 拍且写入口径照旧', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      // 入口退场：菜单键与全部前导文案都不在设置条里。
      expect(find.byKey(const Key('delayed_loop_menu')), findsNothing);
      expect(find.text('前导·不延迟'), findsNothing);
      expect(find.text('前导 2拍'), findsNothing);
      expect(find.text('前导 4拍'), findsNothing);
      expect(find.text('前导 8拍'), findsNothing);

      // 字段与默认档位照旧：会话设置默认 4 拍（行为不受摘除影响）。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.four);
      container.read(prepBeatsProvider.notifier).setLoopLead(8);
      expect(container.read(delayedLoopProvider), DelayedLoopBeats.eight);
    });

    testWidgets('放大镜图标点击不产生任何状态变化', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      final magnifier = find.descendant(
        of: find.byKey(const Key('track_zoom_dock')),
        matching: find.byIcon(Icons.search),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      final lockedBefore = container.read(layoutLockedProvider);
      final snapBefore = container.read(previewSnapEnabledProvider);
      await tester.tap(magnifier, warnIfMissed: false);
      await pumpSettle(tester);

      expect(container.read(layoutLockedProvider), lockedBefore);
      expect(container.read(previewSnapEnabledProvider), snapBefore);
      expect(
        tester.widget<Slider>(find.byKey(const Key('track_zoom_slider'))).value,
        0,
      );
    });

    // 拖动仅经手柄带起手，线身不再是拖动源；dock 已迁出
    // 带外、带顶不再有 dock。本用例钉住语义：线身起手拖动不移动尾线。
    testWidgets('整片视图尾线贴右缘：线身起手不拖动（带内无 dock）', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
      );

      // 尾线中心在带右缘（x=w）：从局部镜像行（带顶一行、无片段时整行
      // 空白）贴右缘内侧按下左拖——线身不再触发拖动（仅手柄拖动），
      // 尾线边界不变。
      final band = tester.getRect(find.byKey(const Key('track_band')));
      final gesture = await tester.startGesture(
        Offset(band.right - 4, trackRowCenterY(tester, 'track_mirror')),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);

      expect(bandTimeline(tester).rangeEnd, total, reason: '线身（非手柄）起手不移动尾线');
    });

    testWidgets('吸附设置入口已删除：设置条无吸附 pill 与菜单', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      expect(find.byKey(const Key('track_snap_menu')), findsNothing);
      expect(find.text('吸附 4拍'), findsNothing);
      expect(find.text('吸附关'), findsNothing);
    });
  });

  group('双指双击内容命中检查', () {
    /// 双指 tap（两指按下 → 50ms → 相继抬起）。
    Future<void> twoFingerTapAt(WidgetTester tester, Offset center) async {
      final g1 = await tester.startGesture(center);
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await tester.pump(const Duration(milliseconds: 10));
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('双指双击在段体上不触发 onTwoFingerDoubleTap / onCollapse', (
      tester,
    ) async {
      var twoFingerDoubleTaps = 0;
      var collapses = 0;
      final total = const Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.normalized(
                videoDuration: total,
                segmentLines: const [
                  SegmentLine(position: Duration(seconds: 10)),
                ],
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onCollapse: () => collapses++,
                  onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      final center = tester.getCenter(
        find.byKey(const Key('learning_segment_0')),
      );
      await twoFingerTapAt(tester, center);
      await twoFingerTapAt(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(twoFingerDoubleTaps, 0, reason: '段体上双指双击不触发');
      expect(collapses, 0);
    });

    testWidgets('双指双击在分段线上不触发（第二指落在线外空白也不触发）', (tester) async {
      var twoFingerDoubleTaps = 0;
      final total = const Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            annotationTimelineProvider.overrideWithBuild(
              (ref, _) => AnnotationTimeline.normalized(
                videoDuration: total,
                segmentLines: const [
                  SegmentLine(position: Duration(seconds: 10)),
                ],
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      final center = tester.getCenter(find.byKey(const Key('segment_line_0')));
      await twoFingerTapAt(tester, center);
      await twoFingerTapAt(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(twoFingerDoubleTaps, 0, reason: '分段线上双指双击不触发');
    });

    testWidgets('双指双击在首尾线上不触发', (tester) async {
      var twoFingerDoubleTaps = 0;
      final total = const Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      final center = tester.getCenter(
        find.byKey(const Key('video_range_start_line')),
      );
      await twoFingerTapAt(tester, center);
      await twoFingerTapAt(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(twoFingerDoubleTaps, 0, reason: '首尾线上双指双击不触发');
    });

    testWidgets('双指双击在预览条上不触发', (tester) async {
      var twoFingerDoubleTaps = 0;
      final total = const Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await engine.seek(const Duration(seconds: 90));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);
      expect(find.byKey(const Key('preview_line')), findsOneWidget);

      final center = tester.getCenter(find.byKey(const Key('preview_line')));
      await twoFingerTapAt(tester, center);
      await twoFingerTapAt(tester, center);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(twoFingerDoubleTaps, 0, reason: '预览条上双指双击不触发');
    });

    testWidgets('轨间隙空白的双指双击同样归跨面双指会话（不触发）', (tester) async {
      var twoFingerDoubleTaps = 0;
      final total = const Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                  onTwoFingerDoubleTap: () => twoFingerDoubleTaps++,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      // 轨间隙（学习段轨与节拍轨之间）在带内，仍属带面：双指归缩放会话。
      final learningBottom = tester
          .getBottomLeft(find.byKey(const Key('track_learning')))
          .dy;
      final beatTop = tester.getTopLeft(find.byKey(const Key('track_beat'))).dy;
      final gapY = (learningBottom + beatTop) / 2;
      final gapCenter = Offset(
        tester.getCenter(find.byKey(const Key('track_band'))).dx,
        gapY,
      );
      await twoFingerTapAt(tester, gapCenter);
      await twoFingerTapAt(tester, gapCenter);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));

      expect(twoFingerDoubleTaps, 0, reason: '带内（含轨间隙）双指一律归跨面双指会话，双指 tap 被抑制');
    });
  });

  group('临时衔接段', () {
    Future<ProviderContainer> pumpWithLines(
      WidgetTester tester,
      FakePlaybackEngine engine,
    ) async {
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 5)),
            SegmentLine(position: Duration(seconds: 15)),
            SegmentLine(position: Duration(seconds: 25)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      return container;
    }

    /// 学习轨行内、线 1（15s）x 处的点击位置（触发区路径）。
    /// 行中心 y 直接问渲染出的学习轨行。
    Offset learningRowLine1(WidgetTester tester) {
      final x = tester.getCenter(find.byKey(const Key('segment_line_1'))).dx;
      return Offset(x, trackRowCenterY(tester, 'track_learning'));
    }

    testWidgets('触发区（学习轨行）点击分段线激活临时段并选中该线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);

      final transition = container.read(transitionSegmentProvider)!;
      // 线 15s：理论 [11, 19]，起点 11s 取整到最近 2s 格 = 12s。
      expect(transition.lineIndex, 1);
      expect(transition.start, const Duration(seconds: 12));
      expect(transition.end, const Duration(seconds: 19));
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 1);
    });

    testWidgets('控制柄点击仅选中/再点取消，不触发临时段', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      await tapSegmentLineHandle(tester, 1);
      await pumpSettle(tester);

      expect(container.read(transitionSegmentProvider), isNull);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        1,
        reason: '控制柄点击=仅选中（供标记/删除）',
      );

      // 再点同一控制柄：取消选中，仍不触发临时段。
      await tapSegmentLineHandle(tester, 1);
      await pumpSettle(tester);

      expect(container.read(transitionSegmentProvider), isNull);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
        reason: '控制柄再点=取消选中',
      );
    });

    testWidgets('再点同线取消临时段并取消选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
      );
    });

    testWidgets('点其它线激活替换', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      final x1 = tester.getCenter(find.byKey(const Key('segment_line_1'))).dx;
      await tester.tapAt(Offset(x1, trackRowCenterY(tester, 'track_learning')));
      await pumpSettle(tester);
      // 线 2 的学习轨行纵带上部点击线身（临时段仅由
      // 学习轨行内点击线身触发）。y 取学习轨行顶下方（行矩形顶 + 4）。
      final x2 = tester.getCenter(find.byKey(const Key('segment_line_2'))).dx;
      await tester.tapAt(
        Offset(x2, trackRowRect(tester, 'track_learning').top + 4),
      );
      await pumpSettle(tester);

      final transition = container.read(transitionSegmentProvider)!;
      expect(transition.lineIndex, 2);
      // 线 25s：理论起点 21s 取整到最近八拍点（20s）= 20s → [20, 29]。
      expect(transition.start, const Duration(seconds: 20));
      expect(transition.end, const Duration(seconds: 29));
    });

    testWidgets('节拍轨行与轨间隙不触发线操作', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);
      final x = tester.getCenter(find.byKey(const Key('segment_line_1'))).dx;

      // 节拍轨行中心：不选中、不触发临时段。
      await tester.tapAt(Offset(x, trackRowCenterY(tester, 'track_beat')));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
        reason: '节拍轨行点击不触发线操作',
      );

      // 轨间隙（学习轨与节拍轨之间）：同样不触发线操作。
      await tester.tapAt(
        Offset(
          x,
          (trackRowRect(tester, 'track_learning').bottom +
                  trackRowRect(tester, 'track_beat').top) /
              2,
        ),
      );
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
        reason: '轨间隙点击不触发线操作',
      );
    });

    testWidgets('点真实学习段激活时替换临时段（互斥）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);

      // 点段 1（沿用既有点击目标几何）。
      await tester.tap(find.byKey(const Key('learning_segment_1')));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
    });

    testWidgets('窗内点线仍开关临时段（分侧公式线中心仍在窗内）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 4)),
            SegmentLine(position: Duration(seconds: 5)),
            SegmentLine(position: Duration(seconds: 25)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      // 线 1（5s）夹在 1s 窄段（4–5s）与 20s 宽段之间：显示宽 = 800px/30s
      // ≈ 26.7px；左窗 = 10% × 26.7px ≈ 2.7px（线中心仍在窗内）。
      final x1 = tester.getCenter(find.byKey(const Key('segment_line_1'))).dx;

      // 窗内（线中心）：激活临时段并选中该线（点按 y = 学习轨行中心）。
      await tester.tapAt(Offset(x1, trackRowCenterY(tester, 'track_learning')));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 1);
    });

    testWidgets('窗外点按落在段体上激活真实学习段（真实段优先）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 4)),
            SegmentLine(position: Duration(seconds: 5)),
            SegmentLine(position: Duration(seconds: 25)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      final x0 = tester.getCenter(find.byKey(const Key('segment_line_0'))).dx;
      final x1 = tester.getCenter(find.byKey(const Key('segment_line_1'))).dx;
      // 线 1 右侧邻宽段（20s，显示宽 ≈ 533px > 顶帽区）→ 右窗 = 20dp 上限。
      // 距线中心 21px（> 右窗上限、仍在最近线抓取范围内）→ 不触发临时段，
      // 回落激活真实段（线 1 右侧 = 段 2）。
      expect(
        x1 - x0,
        closeTo(bandContentWidth(800) / 30, 0.5),
        reason: '内容区 25.3px/s 显示密度',
      );
      final offWindow = kTransitionTriggerMaxSideHalfWidthPx + 1;
      await tester.tapAt(
        Offset(x1 + offWindow, trackRowCenterY(tester, 'track_learning')),
      );
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), const {2});
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
        reason: '窗外点按不选中分段线',
      );

      // 对照：同一点按高度，线 1 右侧窗内（< 右窗上限 20dp）仍开关
      // 临时段（宽侧窗保持 20dp 顶帽，不随左窄段收窄）。同一点按高度落学习轨行。
      await tester.tapAt(
        Offset(
          x1 + kTransitionTriggerMaxSideHalfWidthPx - 5,
          trackRowCenterY(tester, 'track_learning'),
        ),
      );
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 1);
    });

    testWidgets('分侧不对称——窄段一侧窗外即激活真实窄段（≥80% 保留）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 4)),
            SegmentLine(position: Duration(seconds: 5)),
            SegmentLine(position: Duration(seconds: 25)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      final x0 = tester.getCenter(find.byKey(const Key('segment_line_0'))).dx;
      final x1 = tester.getCenter(find.byKey(const Key('segment_line_1'))).dx;
      // 线 1 左侧邻窄段（1s，显示宽 ≈ 26.7px）→ 左窗 = 10% ≈ 2.7px，远小
      // 于右侧窗上限（20dp）：分侧不对称。距线中心 5px 在线命中层内、但已
      // 在左窗外 → 激活真实窄段（段 1）而非误开临时段。
      final narrowSidePx = x1 - x0;
      expect(narrowSidePx * 0.1, lessThan(5));
      await tester.tapAt(
        Offset(x1 - 5, trackRowCenterY(tester, 'track_learning')),
      );
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
        reason: '窗外点按不选中分段线',
      );
    });

    testWidgets('青边框跨段框住临时范围（按时间映射，跨真实段）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpWithLines(tester, engine);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);

      final overlay = find.byKey(const Key('transition_segment_overlay'));
      expect(overlay, findsOneWidget);
      // 800px 测试宽 / 30s：[12s, 19s] → x ∈ [320, 506.67]；跨过 15s、25s
      // 两条分段线（真实段边界不参与）。
      final rect = tester.getRect(overlay);
      expect(rect.left, closeTo(bandX(12), 0.5));
      expect(rect.width, closeTo(bandX(19) - bandX(12), 0.5));
      expect(rect.height, trackRowRect(tester, 'track_learning').height);
      // 取消后 overlay 消失。
      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(overlay, findsNothing);
    });

    testWidgets('激活报身份触发短暂提示（渲染归演出层宿主）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      final trigger = container.read(
        noticeTriggerProvider(NoticeId.transition).notifier,
      );
      expect(trigger.state, 0);
      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);

      expect(trigger.state, 1, reason: '激活即向触发面报身份');
      // 取消（异线替换/清除同报）不在此重复：浮层显隐归宿主接缝。
    });

    testWidgets('几何变化（拖线）自动清除临时段与 overlay', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);

      // 拖动线 1 的手柄（几何变化）→ 临时段清除。
      final handle = find.byKey(const Key('segment_line_1_handle'));
      final g = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await dragBySteps(tester, g, const Offset(60, 0));
      await g.up();
      await pumpSettle(tester);

      expect(container.read(transitionSegmentProvider), isNull);
      expect(find.byKey(const Key('transition_segment_overlay')), findsNothing);
    });

    /// 临时段两端字形的 key 后缀。
    const transitionSuffixes = ['_loop_glyph_start', '_loop_glyph_end'];

    /// 断言临时段完全没有两端标志。
    void expectNoTransitionLoopMarks(WidgetTester tester) {
      for (final suffix in transitionSuffixes) {
        expect(
          find.byKey(Key('transition_segment$suffix')),
          findsNothing,
          reason: '退出/未激活的临时段不应有标志：transition_segment$suffix',
        );
      }
    }

    testWidgets('激活时两端字形同在、几何与学习段一致、发光不在', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpWithLines(tester, engine);

      // 未激活：没有任何两端标志。
      expectNoTransitionLoopMarks(tester);

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);

      // 临时段自己承担两端：左右各一枚 repeat（[12s,19s] ≈ 187px，
      // 远超 26dp 判据）；旧括号帽键不再存在。
      for (final suffix in transitionSuffixes) {
        expect(
          find.byKey(Key('transition_segment$suffix')),
          findsOneWidget,
          reason: 'transition_segment$suffix',
        );
      }
      // 旧括号帽键不再存在：端标志只由 repeat 字形承担。
      expect(
        find.byKey(const Key('transition_segment_loop_start')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('transition_segment_loop_end')),
        findsNothing,
      );

      // 几何与学习段同一份实现：字形贴端 3dp、距底 3dp、10dp。
      final overlay = tester.getRect(
        find.byKey(const Key('transition_segment_overlay')),
      );
      final glyphStart = tester.getRect(
        find.byKey(const Key('transition_segment_loop_glyph_start')),
      );
      final glyphEnd = tester.getRect(
        find.byKey(const Key('transition_segment_loop_glyph_end')),
      );
      expect(
        glyphStart.left,
        closeTo(overlay.left + kSegmentLoopGlyphInset, 0.5),
      );
      expect(
        glyphStart.bottom,
        closeTo(overlay.bottom - kSegmentLoopGlyphInset, 0.5),
      );
      expect(glyphStart.longestSide, kSegmentLoopGlyphSize);
      expect(
        glyphEnd.right,
        closeTo(overlay.right - kSegmentLoopGlyphInset, 0.5),
      );
      expect(
        glyphEnd.bottom,
        closeTo(overlay.bottom - kSegmentLoopGlyphInset, 0.5),
      );
      expect(glyphEnd.longestSide, kSegmentLoopGlyphSize);

      // 字形用激活色，不新增颜色。
      for (final suffix in transitionSuffixes) {
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(Key('transition_segment$suffix')),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.color, kCyanAccentColor);
      }

      // 发光专属真实激活：临时段 overlay 只是描边装饰，没有 boxShadow。
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.byKey(const Key('transition_segment_overlay')),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.boxShadow, isNull);
    });

    testWidgets('切走（再次点按）后两端标志与 overlay 一并消失', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpWithLines(tester, engine);
      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(
        find.byKey(const Key('transition_segment_loop_glyph_start')),
        findsOneWidget,
      );

      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expectNoTransitionLoopMarks(tester);
      expect(find.byKey(const Key('transition_segment_overlay')), findsNothing);
    });

    testWidgets('几何变化（拖线）后两端标志一并消失', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithLines(tester, engine);
      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);
      expect(
        find.byKey(const Key('transition_segment_loop_glyph_start')),
        findsOneWidget,
      );

      final handle = find.byKey(const Key('segment_line_1_handle'));
      final g = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await dragBySteps(tester, g, const Offset(60, 0));
      await g.up();
      await pumpSettle(tester);

      expect(container.read(transitionSegmentProvider), isNull);
      expectNoTransitionLoopMarks(tester);
    });

    testWidgets('进度拖出范围（自动取消）后两端标志一并消失', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 30),
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 5)),
            SegmentLine(position: Duration(seconds: 15)),
            SegmentLine(position: Duration(seconds: 25)),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      await tester.tapAt(learningRowLine1(tester));
      await pumpSettle(tester);
      expect(container.read(transitionSegmentProvider), isNotNull);

      // 带内空白横滑 seek：临时范围 [12s,19s]，600px ≈ 22.5s > 19s 段尾。
      await tester.drag(
        find.byKey(const Key('track_notes')),
        const Offset(600, 0),
      );
      await pumpSettle(tester);

      expect(container.read(transitionSegmentProvider), isNull);
      expectNoTransitionLoopMarks(tester);
    });
  });

  group('拖动永不收起铁律的会话位移闩锁', () {
    testWidgets('未锁轴的纯纵向往返位移（净位移归零）不视为静止单击：不收起', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(
        tester,
        engine: engine,
        onCollapse: () => collapses.value++,
      );
      final y = bandCenterY(tester);

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await g.moveBy(const Offset(0, 40));
      await tester.pump();
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
      await g.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(collapses.value, 0, reason: '往返位移是拖动会话，不触发空白收起');
    });
  });

  group('预览线吸附 + 震动', () {
    // 全宽 800、总 180s：1px = 0.225s；吸附半径 12dp → ±2.7s（±12px）。
    AnnotationTimeline bandWithLines(List<Duration> positions) {
      return AnnotationTimeline.normalized(
        videoDuration: const Duration(minutes: 3),
        segmentLines: [for (final p in positions) SegmentLine(position: p)],
      );
    }

    /// 空白横滑改走精细调整后，预览磁吸经**预览线命中列接管
    /// 路径**（手柄带）生效——先把预览线 seek 到起手 x=100 处，再
    /// 从命中列起手水平拖到手指 x=[fingerX]（两段 move 模拟连续拖动，
    /// 首段越过 slop 触发轴锁定 + 立即 seek；绝对跟手 + 吸附解析照旧）。
    Future<void> scrubTo(
      WidgetTester tester,
      FakePlaybackEngine engine,
      double fingerX,
    ) async {
      final total = engine.duration ?? const Duration(minutes: 3);
      await engine.seek(bandTimeAt(100, total: total, width: 800));
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');
      final g = await tester.startGesture(Offset(100, y));
      await tester.pump();
      await g.moveBy(Offset((fingerX - 100) / 2, 0)); // 越过 slop，锁定+立即 seek
      await tester.pump();
      await g.moveBy(Offset((fingerX - 100) / 2, 0));
      await tester.pump();
      await g.up();
      await pumpSettle(tester);
    }

    testWidgets('拖到分段线吸附半径内 → 吸附到该线（松手落点=线时间）+ 震动一次', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithLines(const [Duration(seconds: 90)]),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 拖到 x=410 → 目标 87.63s，距 90s 线 2.37s < 2.84s 半径 → 吸附 90s。
      await scrubTo(tester, engine, 410);

      expect(engine.seekCalls, isNotEmpty);
      expect(engine.seekCalls.last, const Duration(seconds: 90));
      expect(engine.position, const Duration(seconds: 90));
      expect(haptics, 1, reason: '进入吸附目标震动一次');
    });

    testWidgets('半径外不吸附、无震动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithLines(const [Duration(seconds: 90)]),
        onPreviewSnapHaptic: () => haptics++,
      );
      // 拖到 x=445 → 95.92s，距 90s 线 5.92s > 2.84s（12px 半径按内容区
      // 宽折算）。
      await scrubTo(tester, engine, 445);

      expect(
        engine.seekCalls.last,
        bandTimeAt(445, total: const Duration(minutes: 3), width: 800),
        reason: '半径外保持手指位置，不吸附',
      );
      expect(haptics, 0);
    });

    testWidgets('吸附后停留同线不重复震动；切换到另一条线再震一次', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithLines(const [
          Duration(seconds: 60),
          Duration(seconds: 120),
        ]),
        onPreviewSnapHaptic: () => haptics++,
      );
      // 从预览线命中列（手柄带）起手——先把预览线 seek 到
      // x=87.5（11.25s，内容区宽换算）。
      const total = Duration(minutes: 3);
      final startX = bandX(11.25, total: 180);
      await engine.seek(bandTimeAt(startX, total: total, width: 800));
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');

      final g = await tester.startGesture(Offset(startX, y));
      await tester.pump();
      // 进入 60s 线（x = bandX(60)）吸附半径：停在距线 8px 处（半径 12px）。
      await g.moveBy(Offset(bandX(60, total: 180) - startX - 8, 0));
      await tester.pump();
      expect(haptics, 1);
      // 同线吸附半径内小幅往返（距线 ≤10px < 12px，仍吸附 60s）：不重复
      // 震动。
      await g.moveBy(const Offset(2, 0));
      await tester.pump();
      await g.moveBy(const Offset(-2, 0));
      await tester.pump();
      expect(haptics, 1);
      // 拖到 120s 线（x = bandX(120)）附近（距线 8px）→ 切换吸附目标。
      await g.moveBy(Offset(bandX(120, total: 180) - bandX(60, total: 180), 0));
      await tester.pump();
      await g.up();
      await pumpSettle(tester);

      expect(haptics, 2, reason: '切换吸附目标再震一次');
      expect(engine.seekCalls.last, const Duration(seconds: 120));
    });

    testWidgets('开关默认开、位于吸附网格设置左侧；点击关闭后无吸附无震动，再点恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithLines(const [Duration(seconds: 90)]),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 组序（钉住）：开关在缩放滑条左侧。
      final slot = tester.getRect(
        find.byKey(const Key('track_preview_snap_slot')),
      );
      final zoom = tester.getRect(find.byKey(const Key('track_zoom_dock')));
      expect(slot.right, lessThanOrEqualTo(zoom.left));

      // 关闭开关。
      await tester.tap(find.byKey(const Key('track_preview_snap_slot')));
      await pumpSettle(tester);

      // 手指 410（87.63s）：开则吸附 90s。
      await scrubTo(tester, engine, 410);

      expect(
        engine.seekCalls.last,
        bandTimeAt(410, total: const Duration(minutes: 3), width: 800),
        reason: '关闭后无磁性吸附，落点=手指位置',
      );
      expect(haptics, 0);

      // 再点恢复开：吸附行为回归。
      await tester.tap(find.byKey(const Key('track_preview_snap_slot')));
      await pumpSettle(tester);
      await scrubTo(tester, engine, 410);
      expect(engine.seekCalls.last, const Duration(seconds: 90));
      expect(haptics, 1);
    });

    testWidgets('与拖线互不干扰：拖分段线手柄移动线，无吸附震动、无 scrub seek', (tester) async {
      // 与 拖线用例同几何（总 30s），网格吸附落点可直接复算。
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 手柄带路径：拖 segment_line_0_handle 移动线本身。
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, g, const Offset(160, 0));
      await g.up();
      await pumpSettle(tester);

      // 拖线期间的 seek 是实时预览（目标=吸附后线位置 8s/12s，
      // 松手回定格点 0），不是 scrub（预览线不随手指/线移动）、无吸附震动。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(12), 1),
        reason: '线经拖动+网格吸附移动（语义不变）',
      );
      expectOnlyLinePreviewSeeks(engine, {
        const Duration(seconds: 8),
        const Duration(seconds: 12),
      });
      expect(haptics, 0, reason: '拖线不触发预览吸附震动');
    });
  });

  group('预览磁吸到首/尾线', () {
    // 几何同 组：全宽 800、总 180s：1px = 0.225s；吸附半径 12dp
    // → ±2.7s（±12px）。首线 30s（x=133.3）、尾线 150s（x=666.7）、
    // 分段线 90s。
    AnnotationTimeline bandWithRange(List<Duration> positions) {
      return AnnotationTimeline.normalized(
        videoDuration: const Duration(minutes: 3),
        rangeStart: const Duration(seconds: 30),
        rangeEnd: const Duration(minutes: 2, seconds: 30),
        segmentLines: [for (final p in positions) SegmentLine(position: p)],
      );
    }

    /// 空白横滑改走精细调整后，预览磁吸经预览线命中列接管路径
    /// （手柄带）生效——先把预览线 seek 到起手 x，再从命中列起手拖动。
    Future<TestGesture> snapDragStart(
      WidgetTester tester,
      FakePlaybackEngine engine,
      double startX,
    ) async {
      final total = engine.duration ?? const Duration(minutes: 3);
      await engine.seek(bandTimeAt(startX, total: total, width: 800));
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');
      return tester.startGesture(Offset(startX, y));
    }

    testWidgets('拖到首线吸附半径内 → 吸附到首线 + 震动一次', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithRange(const [Duration(seconds: 90)]),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 手指落在 28.2s（距首线 30s 1.8s < 2.84s 半径）→ 吸附首线。
      final g = await snapDragStart(tester, engine, 100);
      await tester.pump();
      await g.moveBy(Offset(bandX(28.2, total: 180) - 100, 0));
      await tester.pump();
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls.last, const Duration(seconds: 30));
      expect(haptics, 1, reason: '进入首线吸附目标震动一次');
    });

    testWidgets('拖到尾线吸附半径内 → 吸附到尾线 + 震动一次', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithRange(const [Duration(seconds: 90)]),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 手指落在 148.2s（距尾线 150s 1.8s < 2.84s 半径）→ 吸附尾线。
      final g = await snapDragStart(tester, engine, 600);
      await tester.pump();
      await g.moveBy(Offset(bandX(148.2, total: 180) - 600, 0));
      await tester.pump();
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls.last, const Duration(minutes: 2, seconds: 30));
      expect(haptics, 1, reason: '进入尾线吸附目标震动一次');
    });

    testWidgets('半径内取最近者：距首线更近吸首线，距分段线更近吸分段线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithRange(const [Duration(seconds: 34)]),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 首线 30s、分段线 34s：手指落在 32.2s，距首线 2.2s、距分段线
      // 1.8s，均 < 2.84s → 最近者 = 分段线。
      final g = await snapDragStart(tester, engine, 100);
      await tester.pump();
      await g.moveBy(Offset(bandX(32.2, total: 180) - 100, 0));
      await tester.pump();
      expect(engine.seekCalls.last, const Duration(seconds: 34));
      expect(haptics, 1);

      // 手指回到 30.6s：距首线 0.6s、距分段线 3.4s（半径外）→ 切换吸附
      // 首线，再震一次。
      await g.moveBy(
        Offset(bandX(30.6, total: 180) - bandX(32.2, total: 180), 0),
      );
      await tester.pump();
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls.last, const Duration(seconds: 30));
      expect(haptics, 2, reason: '分段线 → 首线切换再震一次');
    });

    testWidgets('开关关闭后首/尾线不吸附不震动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: bandWithRange(const []),
        onPreviewSnapHaptic: () => haptics++,
      );
      // 关闭开关。
      await tester.tap(find.byKey(const Key('track_preview_snap_slot')));
      await pumpSettle(tester);

      // 手指落在 28.2s（距首线 1.8s，若开则吸附）→ 关闭保持手指位置。
      final targetX = bandX(28.2, total: 180);
      final g = await snapDragStart(tester, engine, 100);
      await tester.pump();
      await g.moveBy(Offset(targetX - 100, 0));
      await tester.pump();
      await g.up();
      await pumpSettle(tester);

      expect(
        engine.seekCalls.last,
        bandTimeAt(targetX, total: const Duration(minutes: 3), width: 800),
      );
      expect(haptics, 0);
    });

    testWidgets('无首尾偏移（默认区间 0..总时长）时首尾线照常可吸附', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      var haptics = 0;
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          segmentLines: const [SegmentLine(position: Duration(seconds: 90))],
        ),
        onPreviewSnapHaptic: () => haptics++,
      );

      // 首线 = 0：起手落在 1.8s（距 0 1.8s < 2.84s 半径；内容区
      // 左缘让出轨道片头带，起手须落在内容上），两段左移后落点仍在半径内。
      final g = await snapDragStart(tester, engine, bandX(1.8, total: 180));
      await tester.pump();
      await g.moveBy(const Offset(-20, 0));
      await tester.pump();
      await g.moveBy(const Offset(-20, 0));
      await tester.pump();
      await g.up();
      await pumpSettle(tester);

      expect(engine.seekCalls.last, Duration.zero);
      expect(haptics, 1);
    });
  });

  group('拖线实时预览', () {
    // 几何同 拖线用例：总 30s、带宽 800 → 1px = 37.5ms；线 5s
    // （x≈133.3），dragBySteps(+160px) 两次 move 各 80px（各 +3s）——
    // 首次 move 目标 8s（已在默认四拍格上），末次 11s → 吸附 12s。
    const total = Duration(seconds: 30);
    final lineAt5s = AnnotationTimeline.normalized(
      videoDuration: total,
      segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
    );

    double previewLineX(WidgetTester tester) =>
        tester.getCenter(find.byKey(const Key('preview_line'))).dx;

    /// 会话内在场断言（须在松手前读取：松手续播后预览线随播放推进）：
    /// 拖动预览只入队、不写显示位（writeDisplay: false），预览线停在起手位置。
    void expectPreviewLineUnmoved(WidgetTester tester, double beforeX) =>
        expect(previewLineX(tester), beforeX, reason: '拖线预览不改播放头显示值');

    testWidgets('在播拖分段线：按下即暂停，画面逐帧预览线位置，松手回预览线位置续播', (tester) async {
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: lineAt5s,
        onCollapse: () => collapses.value++,
      );
      await engine.play();
      engine.callLog.clear();
      engine.seekCalls.clear();
      final beforeX = previewLineX(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      expectPreviewLineUnmoved(tester, beforeX);
      await gesture.up();
      await pumpSettle(tester);

      // 松手后：回预览线位置（0）续播。
      expect(
        engine.seekCalls.last,
        Duration.zero,
        reason: '拖线不改变播放位置，松手回起手定格点',
      );
      expect(engine.isPlaying, isTrue, reason: '原在播松手续播');
      // 暂停先于首个预览 seek（FakeEngine callLog 顺序断言，同款）。
      final firstPause = engine.callLog.indexOf('pause');
      final firstSeek = engine.callLog.indexOf('seek');
      expect(firstPause, greaterThanOrEqualTo(0), reason: '在播按下即暂停');
      expect(firstPause, lessThan(firstSeek), reason: '暂停定格先于逐帧预览');
      expect(engine.callLog.last, 'play', reason: '恢复播放是收尾动作');
      // 拖动期间只有逐帧预览 seek：目标只能是吸附后线位置（节流可丢弃
      // 中间目标，末目标必达），不出现其它 scrub 目标。
      expectOnlyLinePreviewSeeks(engine, {
        const Duration(seconds: 8),
        const Duration(seconds: 12),
      });
      expect(collapses.value, 0, reason: '拖动会话不触发空白收起（铁律）');
      await engine.pause(); // 清 ticker：测试收尾不留周期定时器。
    });

    testWidgets('暂停拖分段线：不暂停不续播，松手停在预览线位置', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, timeline: lineAt5s);
      engine.seekCalls.clear();
      final beforeX = previewLineX(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      expectPreviewLineUnmoved(tester, beforeX);
      await gesture.up();
      await pumpSettle(tester);

      expect(
        engine.callLog.where((c) => c == 'pause' || c == 'play'),
        isEmpty,
        reason: '原暂停：无暂停/续播动作',
      );
      expect(engine.seekCalls.last, Duration.zero, reason: '停在预览线位置');
      expect(engine.seekCalls, isNotEmpty, reason: '拖动期间仍逐帧预览');
      expect(engine.isPlaying, isFalse);
      expect(engine.position, Duration.zero);
      // 线位置调整本身不受预览影响（吸附回归）。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(12), 1),
      );
    });

    testWidgets('在播拖首线：预览随边界目标逐帧，松手回预览线位置续播、不收起', (tester) async {
      const total3min = Duration(minutes: 3);
      final collapses = ValueNotifier<int>(0);
      final engine = FakePlaybackEngine(duration: total3min);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total3min),
        onCollapse: () => collapses.value++,
      );
      // 适配：首线手柄在带左缘（x≈12），预览线初始停在 0 → 起手在
      // 预览线命中列内会被接管为预览线拖动。先 seek 离开命中列（60s ≈
      // x267）；本用例测首线逐帧预览语义，接管语义由专项
      // 用例覆盖。
      await engine.seek(const Duration(seconds: 60));
      await pumpSettle(tester);
      await engine.play();
      engine.callLog.clear();
      engine.seekCalls.clear();
      final initialPos = engine.position;
      final beforeX = previewLineX(tester);
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('video_range_start_marker'))),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 50));
      expectPreviewLineUnmoved(tester, beforeX);
      await gesture.up();
      await pumpSettle(tester);

      expect(engine.callLog.first, 'pause', reason: '在播按下即暂停');
      expect(engine.callLog.last, 'play', reason: '松手续播');
      // 画面随拖动目标逐帧预览（目标 = moveTo 返回的钳制后
      // 真实边界落点）。
      final previewSeeks = engine.seekCalls
          .where((t) => t != initialPos)
          .toSet();
      expect(previewSeeks, isNotEmpty, reason: '拖动期间逐帧预览边界帧');
      expect(engine.seekCalls.last, initialPos, reason: '松手回起手定格点');
      expect(engine.isPlaying, isTrue);
      expect(collapses.value, 0, reason: '拖动不触发空白收起');
      await engine.pause(); // 清 ticker：测试收尾不留周期定时器。
    });
  });

  group('手柄槽等分互斥分区', () {
    testWidgets('起手在预览线命中列内 → 拖预览线，不移动分段线', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );

      // 预览线 seek 到分段线位置 → 与该线手柄槽重合（真机"与预览线重合
      // 时误移线"场景）。
      await engine.seek(const Duration(seconds: 5));
      await pumpSettle(tester);

      final lineBefore = tester
          .getCenter(find.byKey(const Key('segment_line_0')))
          .dx;
      final handleCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0_handle')),
      );

      final g = await tester.startGesture(handleCenter);
      await tester.pump();
      await dragBySteps(tester, g, const Offset(160, 0));
      await g.up();
      await pumpSettle(tester);

      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        lineBefore,
        reason: '预览线命中列内起手 → 拖预览线，不移动分段线',
      );
      expect(engine.seekCalls, isNotEmpty, reason: '拖动走预览线 scrub seek');
      // 手指终点 = 手柄中心 + 160 → 换算时间（800px ↔ 30s）。
      final fingerX = handleCenter.dx + 160;
      expect(
        engine.seekCalls.last.inMilliseconds,
        closeTo(
          bandTimeAt(
            fingerX,
            total: total,
            width: 800,
          ).inMilliseconds.toDouble(),
          200,
        ),
        reason: 'seek 目标 = 手指位置帧级换算',
      );
      // 预览线跟随拖动目标移动到手指处。
      expect(
        tester.getCenter(previewLine()).dx,
        closeTo(fingerX, 2),
        reason: '预览线随拖动移动',
      );
    });

    testWidgets('列内起手加指再抬回单指：仍归预览线内容拖动，不误入空白微调', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );
      await engine.seek(const Duration(seconds: 5));
      await pumpSettle(tester);

      // 从预览线命中列（分段线 5s 处手柄中心）起手。
      final handleCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0_handle')),
      );
      final g = await tester.startGesture(handleCenter);
      await tester.pump();
      await dragBySteps(tester, g, const Offset(60, 0)); // 列内起手拖预览线

      // 加指（带内）→ 缩放；抬回单指后继续横拖：仍走绝对跟手（落点随
      // 手指位置换算），而非从定格基准累计的微调。
      final second = await tester.startGesture(
        Offset(handleCenter.dx + 60, handleCenter.dy + 30),
      );
      await tester.pump();
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await second.up();
      await tester.pump();
      await dragBySteps(tester, g, const Offset(60, 0));
      await g.up();
      await pumpSettle(tester);

      // 末次 seek = 抬回单指后的手指位置（绝对换算），不是累计微调值。
      final fingerX = handleCenter.dx + 60 + 80 + 60;
      expect(
        engine.seekCalls.last.inMilliseconds,
        closeTo(
          bandTimeAt(
            fingerX,
            total: total,
            width: 800,
          ).inMilliseconds.toDouble(),
          200,
        ),
        reason: '抬回单指后仍是列内预览线拖动（绝对跟手），未误入微调',
      );
    });

    testWidgets('密集线视觉短条随槽收缩：三条密排中间控制条收窄不压邻线', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 10000)),
            SegmentLine(position: Duration(milliseconds: 10300)),
            SegmentLine(position: Duration(milliseconds: 10600)),
          ],
        ),
      );
      // 预览线远离密排区，避免命中列干扰。
      await engine.seek(const Duration(seconds: 1));
      await pumpSettle(tester);

      // 800px ↔ 30s → 三线 x ≈ 266.7/274.7/282.7，间距 8px < 48：
      // 中间槽被两侧中点（270.7/278.7）截成 8dp → 视觉把手随之收窄到 8dp，
      // 不再以 32dp 固定宽视觉压过邻线；外侧槽宽 = min(目标半宽, 邻界)
      // 起步（条宽 24 → 32，条取 min(32, 槽宽)，截成 8dp 的
      // 用例数值不变）。
      expect(
        tester.getSize(find.byKey(const Key('segment_line_1_handle'))).width,
        closeTo(8, 0.5),
        reason: '中间槽收缩 → 短条随槽收窄',
      );
      expect(
        tester.getSize(find.byKey(const Key('segment_line_0_handle'))).width,
        closeTo(28, 0.5),
        reason:
            '外侧槽向空余扩展但被邻线分界截到 28dp（线心 ± 24 目标半宽 '
            '与两侧中点相交）→ 条取 min(32, 槽宽)（24 时代槽宽 '
            '28 已够 24，故旧值不变）',
      );
      expect(
        tester.getSize(find.byKey(const Key('segment_line_2_handle'))).width,
        closeTo(28, 0.5),
      );
    });

    testWidgets('控制柄把手化上屏：32×18 胶囊在手柄带行内垂直居中', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );
      await pumpSettle(tester);
      final rowTop = tester
          .getTopLeft(find.byKey(const Key('track_handle_strip_row')))
          .dy;
      final bar = find.byKey(const Key('segment_line_0_handle'));
      final size = tester.getSize(bar);
      expect(size.width, closeTo(32, 0.1), reason: '条宽 24 → 32');
      expect(size.height, closeTo(18, 0.1), reason: '条高 4 → 18');
      expect(
        tester.getTopLeft(bar).dy - rowTop,
        closeTo(6, 0.1),
        reason: '行高 30、条高 18 → 行内垂直居中，上下各 6dp',
      );
    });

    testWidgets('起手在预览线命中列外 → 仍拖分段线（列内优先不误伤）', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );

      // 预览线仍贴带左端（x≈0），远离分段线手柄（x≈133）→ 拖线语义不变。
      final g = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, g, const Offset(160, 0));
      await g.up();
      await pumpSettle(tester);

      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(12), 1),
        reason: '列外起手 → 拖线移动（语义回归）',
      );
      // 合并后语义：原暂停拖线不暂停/续播，但仍有逐帧预览 seek
      //（目标=吸附后线位置 12s）与松手回预览线原位（0）——不是预览条
      // scrub（预览线不随动，见上组用例）。
      expect(engine.seekCalls.last, Duration.zero, reason: '松手回预览线原位');
      expect(
        engine.callLog.where((c) => c == 'pause' || c == 'play'),
        isEmpty,
        reason: '原暂停：无暂停/续播动作',
      );
      expect(
        tester.getCenter(previewLine()).dx,
        closeTo(bandX(0), 2),
        reason: '预览线不随拖线移动（非 scrub）',
      );
    });

    testWidgets('首尾线手柄一致：列内起手拖预览线，不改 range 边界', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 5),
          rangeEnd: const Duration(seconds: 25),
        ),
      );

      // 预览线 seek 到首线位置 → 与首线手柄槽重合。
      await engine.seek(const Duration(seconds: 5));
      await pumpSettle(tester);

      final markerCenter = tester.getCenter(
        find.byKey(const Key('video_range_start_marker')),
      );

      final g = await tester.startGesture(markerCenter);
      await tester.pump();
      await dragBySteps(tester, g, const Offset(80, 0));
      await g.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).rangeStart,
        const Duration(seconds: 5),
        reason: '首线手柄列内起手 → 拖预览线，不改 range 边界（首尾/分段一致）',
      );
      expect(engine.seekCalls, isNotEmpty, reason: '拖动走预览线 scrub seek');
      final fingerX = markerCenter.dx + 80;
      expect(
        engine.seekCalls.last.inMilliseconds,
        closeTo(
          bandTimeAt(
            fingerX,
            total: total,
            width: 800,
          ).inMilliseconds.toDouble(),
          200,
        ),
      );
    });
  });

  group('预览线 z 序置顶', () {
    bool isAncestorOf(Element candidate, Element target) {
      var found = false;
      target.visitAncestorElements((ancestor) {
        if (ancestor == candidate) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    /// [target] 在 [stack] 直系子元素中的绘制序下标（后 = 上层）。
    int paintIndexOf(Element stack, Element target) {
      final children = <Element>[];
      stack.visitChildElements(children.add);
      for (var i = 0; i < children.length; i++) {
        if (children[i] == target || isAncestorOf(children[i], target)) {
          return i;
        }
      }
      fail('目标不在 Stack 直系子树内');
    }

    /// 预览线与 [other] 的最近公共祖先 Stack（分段线标记/手柄/首尾线/
    /// 临时段边框与预览线同栈，绘制序 = 子序，后入在上）。
    Element sharedStackOf(WidgetTester tester, Finder other) {
      Element? shared;
      tester.element(other).visitAncestorElements((ancestor) {
        if (ancestor.widget is Stack &&
            isAncestorOf(ancestor, tester.element(previewLine()))) {
          shared = ancestor;
          return false;
        }
        return true;
      });
      expect(shared, isNotNull, reason: '两目标应共享同一 Stack');
      return shared!;
    }

    testWidgets('预览线绘制于分段线视觉/命中层、首尾线、控制柄之后（栈序）', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
      );

      final stack = sharedStackOf(
        tester,
        find.byKey(const Key('segment_line_0')),
      );
      final previewIndex = paintIndexOf(stack, tester.element(previewLine()));
      // 分段线视觉标记、手柄、首尾线视觉线与手柄都应在预览线之下。
      for (final key in const [
        Key('segment_line_0'),
        Key('segment_line_0_handle'),
        Key('video_range_start_line'),
        Key('video_range_end_line'),
        Key('video_range_start_marker'),
        Key('video_range_end_marker'),
      ]) {
        expect(
          paintIndexOf(stack, tester.element(find.byKey(key))),
          lessThan(previewIndex),
          reason: '$key 应绘制在预览线之下',
        );
      }
    });

    testWidgets('临时衔接段边框仍在预览线之上（dock/浮层让位例外不动）', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
      );
      // 学习轨行点击线身激活临时段（触发区；点按 y = 学习轨行中心）。
      await tester.tapAt(
        Offset(
          tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
          trackRowCenterY(tester, 'track_learning'),
        ),
      );
      await pumpSettle(tester);

      final stack = sharedStackOf(
        tester,
        find.byKey(const Key('transition_segment_overlay')),
      );
      expect(
        paintIndexOf(stack, tester.element(previewLine())),
        lessThan(
          paintIndexOf(
            stack,
            tester.element(find.byKey(const Key('transition_segment_overlay'))),
          ),
        ),
        reason: '临时衔接段边框应在预览线之上',
      );
    });

    testWidgets('重合点击归属：预览线 2px 柱吸收线心点击，命中带其余仍选中', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await engine.seek(const Duration(seconds: 15));
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 15))],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      final lineX = tester
          .getCenter(find.byKey(const Key('segment_line_0')))
          .dx;
      // 带内中心已不是空行（局部镜像行落地后落在学习轨行内），空白点击
      // 基准改问节拍轨行中心（刻度纯视觉、无命中层）。
      final y = trackRowCenterY(tester, 'track_beat');

      // 线心（2px 柱内）点击 → 预览线吸收，不切换分段线选中。
      await tester.tapAt(Offset(lineX, y));
      await pumpSettle(tester);
      expect(
        container.read(annotationSelectionProvider).asSegmentLineIndex,
        isNull,
        reason: '预览线命中柱吸收线心点击',
      );

      // 命中带内、柱外（+10px < ±20dp）→ 线仍可点选。合并后语义适配
      //点击选中仅经控制柄路径——学习轨行内线身点击归临时段
      // 触发，故柱外点选断言改落在控制柄中心 +10px（仍在
      // 手柄槽/命中带内）。
      final handleCenter = tester.getCenter(
        find.byKey(const Key('segment_line_0_handle')),
      );
      await tester.tapAt(handleCenter + const Offset(10, 0));
      await pumpSettle(tester);
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 0);
    });

    testWidgets('重合拖动归属：预览线柱内起手不拖线（柱外手柄仍可拖）', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await engine.seek(const Duration(seconds: 5));
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );
      engine.seekCalls.clear();

      final handle = find.byKey(const Key('segment_line_0_handle'));
      final handleCenter = tester.getCenter(handle);

      // 柱内（手柄条中心 = 线心 = 预览线位置）起手拖动 → 不移动线
      //（命中被预览线吸收，回落为带级 scrub seek，归属规则）。
      final g = await tester.startGesture(handleCenter);
      await tester.pump();
      await dragBySteps(tester, g, const Offset(60, 0));
      await g.up();
      await pumpSettle(tester);
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
        reason: '预览线柱内起手不拖动分段线',
      );
      expect(engine.seekCalls, isNotEmpty, reason: '回落为带级 scrub');

      // 柱外（+6px，仍在手柄槽内）起手拖动 → 线正常拖动。
      // 合并后语义适配：上一步柱内拖动已把预览线带到手指处
      //（x≈193），+6px 起手点本已在命中列外；但先 seek(0) 让预览线回到
      // 带左端，保证列外前置稳定成立（列内接管语义由专项用例覆盖）。
      await engine.seek(Duration.zero);
      await pumpSettle(tester);
      engine.seekCalls.clear();
      final g2 = await tester.startGesture(handleCenter + const Offset(6, 0));
      await tester.pump();
      await dragBySteps(tester, g2, const Offset(60, 0));
      await g2.up();
      await pumpSettle(tester);
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        // 手指终点 = 线心 +6 +60px → 7.475s，吸附 2s 网格 → 8s。
        closeTo(bandX(8), 1),
        reason: '预览线柱外手柄拖动仍移动分段线',
      );
      // 合并后语义适配：原暂停拖线不再是无 seek 的纯位置调整，
      // 而是逐帧预览线位置（目标=吸附后线位 6s/8s）+ 松手回起手定格点
      //（0）——非 scrub（预览线不随动、线照常移动）。
      expectOnlyLinePreviewSeeks(engine, {
        const Duration(seconds: 6),
        const Duration(seconds: 8),
      });
      expect(
        tester.getCenter(previewLine()).dx,
        closeTo(bandX(0), 2),
        reason: '预览线不随拖线移动（非 scrub）',
      );
    });
  });

  group('首尾线选中上提', () {
    final total = const Duration(seconds: 30);

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(TrackBand)),
          listen: false,
        );

    testWidgets('线身单击选中可带外读取：首/尾端标、同端取消、异端替换', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
      );
      final container = containerOf(tester);
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);

      // 适配：预览线默认与首线（x=0）重合并吸收线心点击，先 seek 让
      // 预览线离开线位（同既有首线点选用例先例）。
      await engine.seek(const Duration(seconds: 15));
      await pumpSettle(tester);

      await tester.tap(find.byKey(const Key('video_range_start_line')));
      await pumpSettle(tester);
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.start,
      );

      // 同端再点取消。
      await tester.tap(find.byKey(const Key('video_range_start_line')));
      await pumpSettle(tester);
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);

      // 异端替换：尾线线身贴带缘、中心在带外（同 先例改由手柄带端标
      // 单击，toggle 与线身同一入口）。
      await tester.tap(
        find.byKey(const Key('video_range_end_marker')),
        warnIfMissed: false,
      );
      await pumpSettle(tester);
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.end,
      );
    });

    testWidgets('与分段线选中互斥：点选端标清除线选中、点选线清除端标选中', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
        ),
      );
      final container = containerOf(tester);

      // 预览线让开线位（适配，同上）。
      await engine.seek(const Duration(seconds: 5));
      await pumpSettle(tester);

      // 端标选中后点分段线 → 端标选中被替换。
      await tester.tap(find.byKey(const Key('video_range_start_line')));
      await pumpSettle(tester);
      await tester.tap(find.byKey(const Key('segment_line_0_handle')));
      await pumpSettle(tester);
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      // 反向：线选中后点端标（尾线线身贴带缘中心在带外，同上改由手柄带
      // 端标单击，toggle 与线身同一入口）→ 线选中被替换。
      await tester.tap(
        find.byKey(const Key('video_range_end_marker')),
        warnIfMissed: false,
      );
      await pumpSettle(tester);
      expect(container.read(selectedSegmentLineIndexProvider), isNull);
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.end,
      );
    });
  });

  group('贴边平移参数修订：判定带宽 = 带宽 ÷ 4、出缘归一 700px/s', () {
    // Widget seam：放大后拖到边沿区，窗口随时间渐进平移。
    // 带内空白横滑改走精细调整，贴边平移经预览线命中列接管
    // 路径（手柄带）触发——预览线先 seek 到起手 x 再从列内起手。
    testWidgets('手指进入边沿区静置：窗口即开始渐进平移（进入即移、无位移也移）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(tester, engine: engine, session: session);
      // 放大：可视 60s..90s（30s / 800px = 37.5ms/px）。
      session.updateWindow(
        TimelineWindow(
          total: const Duration(minutes: 3),
          start: const Duration(seconds: 60),
          end: const Duration(seconds: 90),
        ),
      );
      await pumpSettle(tester);

      // 预览线 seek 到 x=100（放大窗口 [60s,90s]，内容区宽换算
      // → 61.58s），从其命中列起手。
      const zoomWindow = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      await engine.seek(
        bandTimeAt(
          100,
          total: const Duration(minutes: 3),
          width: 800,
          window: zoomWindow,
        ),
      );
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');
      final g = await tester.startGesture(Offset(100, y));
      await tester.pump();
      await g.moveBy(const Offset(-70, 0)); // 越过 slop，锁定+立即 seek
      await tester.pump();
      await g.moveBy(const Offset(0, 0)); // 手指停在 x=30（左缘区，深度 170）
      await tester.pump();
      final startBefore = session.window!.start;

      // 静置 1s（分帧泵）：时间平滑累积平移。
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        session.window!.start,
        lessThan(startBefore),
        reason: '手指停在左缘区内不动，窗口仍随时间渐进左移（看更早内容）',
      );
      await g.up();
      await pumpSettle(tester);
    });

    testWidgets('侵入越深平移越快；带中部不平移', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));

      Future<Duration> panAfterHold({required double startX}) async {
        final session = buildTrackBandSession(engine: engine);
        await pumpBand(tester, engine: engine, session: session);
        session.updateWindow(
          TimelineWindow(
            total: const Duration(minutes: 3),
            start: const Duration(seconds: 60),
            end: const Duration(seconds: 90),
          ),
        );
        await pumpSettle(tester);
        // 预览线 seek 到 x=100（按内容区宽换算），从其命中列（手柄带）起手。
        const zoomWindow = TimelineWindow(
          total: Duration(minutes: 3),
          start: Duration(seconds: 60),
          end: Duration(seconds: 90),
        );
        await engine.seek(
          bandTimeAt(
            100,
            total: const Duration(minutes: 3),
            width: 800,
            window: zoomWindow,
          ),
        );
        await pumpSettle(tester);
        final y = trackRowCenterY(tester, 'track_handle_strip_row');
        final g = await tester.startGesture(Offset(100, y));
        await tester.pump();
        await g.moveBy(Offset(startX - 100, 0));
        await tester.pump();
        final before = session.window!.start;
        await tester.pump(const Duration(milliseconds: 500));
        await g.up();
        await pumpSettle(tester);
        return session.window!.start - before;
      }

      final midPan = await panAfterHold(startX: 400);
      expect(midPan, Duration.zero, reason: '带中部无边缘平移');

      // 左缘区：窗口向左平移（看更早内容），越深移动量越大。
      final shallowPan = await panAfterHold(startX: 180); // 深度 20
      final deepPan = await panAfterHold(startX: 120); // 深度 80
      expect(shallowPan, lessThan(Duration.zero));
      expect(deepPan, lessThan(shallowPan), reason: '越深越快（渐进）');
    });

    testWidgets('真机竖屏带宽 361.1：带中部拖动不自动平移，贴到边缘才移', (tester) async {
      const w = 361.1;
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));

      Future<Duration> panAfterHold({required double startX}) async {
        final session = buildTrackBandSession(engine: engine);
        await pumpBand(tester, engine: engine, session: session, bandWidth: w);
        const zoomWindow = TimelineWindow(
          total: Duration(minutes: 3),
          start: Duration(seconds: 60),
          end: Duration(seconds: 90),
        );
        session.updateWindow(zoomWindow);
        await pumpSettle(tester);
        // 预览线 seek 到 x=100，从其命中列起手，再移到 startX。
        await engine.seek(
          bandTimeAt(
            100,
            total: const Duration(minutes: 3),
            width: w,
            window: zoomWindow,
          ),
        );
        await pumpSettle(tester);
        final y = trackRowCenterY(tester, 'track_handle_strip_row');
        final g = await tester.startGesture(Offset(100, y));
        await tester.pump();
        await g.moveBy(Offset(startX - 100, 0));
        await tester.pump();
        final before = session.window!.start;
        await tester.pump(const Duration(milliseconds: 500));
        await g.up();
        await pumpSettle(tester);
        return session.window!.start - before;
      }

      // 判定带宽 90.275：带中部 [90.3, 270.8] 不命中（旧 200dp 常量下
      // 竖屏几乎全带命中，中心也有约 20px 深度）。
      expect(
        await panAfterHold(startX: 180),
        Duration.zero,
        reason: '竖屏带中部拖动不自动平移（可小范围微调落点）',
      );
      // x=30：左缘区深度 60.275 → 开始自动平移（看更早内容）。
      expect(
        await panAfterHold(startX: 30),
        lessThan(Duration.zero),
        reason: '竖屏进入边沿区即自动平移',
      );
    });

    testWidgets('双指在场时贴边平移冻结，抬回单指后恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(tester, engine: engine, session: session);
      const zoomWindow = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      session.updateWindow(zoomWindow);
      await pumpSettle(tester);
      await engine.seek(
        bandTimeAt(
          100,
          total: const Duration(minutes: 3),
          width: 800,
          window: zoomWindow,
        ),
      );
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');
      final g1 = await tester.startGesture(Offset(100, y));
      await tester.pump();
      await g1.moveBy(const Offset(-70, 0)); // x=30：左缘区，深度 170。
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        session.window!.start,
        lessThan(const Duration(seconds: 60)),
        reason: '前置：单指贴边平移已在推进',
      );
      // 回到 x=80（仍在左缘区，深度 120）：抬指重启时预览线距起手点
      // x=100 仅 20，仍落在预览线命中列 ±24 内。
      await g1.moveBy(const Offset(50, 0));
      await tester.pump();

      // 第二指落下：冻结贴边平移（不与捏合平移相抗）。
      final g2 = await tester.startGesture(Offset(300, y));
      await tester.pump(const Duration(milliseconds: 100));
      final frozenStart = session.window!.start;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(session.window!.start, frozenStart, reason: '双指在场时贴边平移冻结');

      // 抬回单指：本 burst 仍是混区 burst（闩锁到全部指针抬起），单指语义
      // 整场抑制——贴边平移不在同一 burst 内恢复。
      await g2.up();
      await tester.pump();
      await g1.moveBy(const Offset(-5, 0));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        session.window!.start,
        frozenStart,
        reason: '同一 burst 内混区闩锁整场抑制（整场按缩放+平移会话处理）',
      );
      await g1.up();
      await pumpSettle(tester);

      // 下一 burst 的单指会话恢复贴边平移：预览线回到手指下的命中列，
      // 再从边沿区起手。
      await engine.seek(
        bandTimeAt(
          80,
          total: const Duration(minutes: 3),
          width: 800,
          window: session.window!,
        ),
      );
      await pumpSettle(tester);
      final resumedBefore = session.window!.start;
      final g3 = await tester.startGesture(Offset(80, y));
      await tester.pump();
      await g3.moveBy(const Offset(-50, 0)); // x=30：左缘区，深度 170。
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        session.window!.start,
        lessThan(resumedBefore),
        reason: '抬回单指后的新会话恢复贴边平移',
      );
      await g3.up();
      await pumpSettle(tester);
    });

    testWidgets('离开边沿区或抬手立即停止平移', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(tester, engine: engine, session: session);
      const zoomWindow = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      session.updateWindow(zoomWindow);
      await pumpSettle(tester);
      await engine.seek(
        bandTimeAt(
          100,
          total: const Duration(minutes: 3),
          width: 800,
          window: zoomWindow,
        ),
      );
      await pumpSettle(tester);
      final y = trackRowCenterY(tester, 'track_handle_strip_row');
      final g = await tester.startGesture(Offset(100, y));
      await tester.pump();
      await g.moveBy(const Offset(-70, 0)); // x=30：左缘区，深度 170。
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        session.window!.start,
        lessThan(const Duration(seconds: 60)),
        reason: '前置：进入边沿区后窗口已在平移',
      );

      // 移回带中部（x=400，判定带宽 200 的中部，深度 0）→ 立即停止平移。
      await g.moveBy(const Offset(370, 0));
      await tester.pump();
      final atMiddle = session.window!.start;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(session.window!.start, atMiddle, reason: '离开边沿区立即停止平移');

      // 再回边沿区 → 恢复平移；抬手立即停止。
      await g.moveBy(const Offset(-370, 0)); // x=30，左缘区。
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(session.window!.start, lessThan(atMiddle), reason: '回到边沿区恢复平移');
      await g.up();
      await tester.pump();
      final atLift = session.window!.start;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(session.window!.start, atLift, reason: '抬手立即停止平移');
      await pumpSettle(tester);
    });

    testWidgets('窗口钳制：平移不越出 [0, total]', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(tester, engine: engine, session: session);
      // 窗口已贴右端 150s..180s：右缘区持续平移不得越出 total。
      session.updateWindow(
        TimelineWindow(
          total: const Duration(minutes: 3),
          start: const Duration(seconds: 150),
          end: const Duration(minutes: 3),
        ),
      );
      await pumpSettle(tester);
      // 贴边平移只在预览线拖动路径上（带内空白横滑是微调）：预览线先
      // seek 到起手 x，再从该列起手。
      final y = trackRowCenterY(tester, 'track_handle_strip_row');
      await engine.seek(
        bandTimeAt(
          700,
          total: const Duration(minutes: 3),
          width: 800,
          window: session.window!,
        ),
      );
      await pumpSettle(tester);
      final g = await tester.startGesture(Offset(700, y));
      await tester.pump();
      await g.moveBy(const Offset(95, 0)); // x=795（右缘区，深度 195）
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await g.up();
      await pumpSettle(tester);

      final win = session.window!;
      expect(win.end.inMicroseconds, lessThanOrEqualTo(180000000));
      expect(
        win.end.inMicroseconds,
        closeTo(180000000, 5000),
        reason: '右端钳制在 total（逐帧取整容差 ≤5ms）',
      );
      expect(win.start.inMicroseconds, closeTo(150000000, 5000));
    });
  });

  group('锁定分段', () {
    /// 经 ProviderScope 容器开启锁定分段（会话内状态），返回容器供断言。
    ProviderContainer enableLock(WidgetTester tester) {
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      container.read(layoutLockedProvider.notifier).toggle();
      return container;
    }

    testWidgets('设置簇组序：锁定分段 < 缩放滑条；开关默认关', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      final lock = tester.getRect(find.byKey(const Key('layout_lock_toggle')));
      final zoom = tester.getRect(find.byKey(const Key('track_zoom_dock')));
      expect(lock.right, lessThanOrEqualTo(zoom.left));

      // 默认关（会话内开关）；状态文字常显。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );
      expect(container.read(layoutLockedProvider), isFalse);
      expect(find.text('锁定分段·关'), findsOneWidget);
    });

    testWidgets('点开关写回会话设置：开 ↔ 关', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
        listen: false,
      );

      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await pumpSettle(tester);
      expect(container.read(layoutLockedProvider), isTrue);
      expect(find.text('锁定分段·开'), findsOneWidget);

      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await pumpSettle(tester);
      expect(container.read(layoutLockedProvider), isFalse);
      // 关态文字常显「·关」并随状态即时切换。
      expect(find.text('锁定分段·关'), findsOneWidget);
    });

    testWidgets('预览吸附/锁定分段 标签恒显当前状态；前导标签随入口退场', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);

      // 预览吸附默认开：恒显「·开」。
      expect(find.text('预览吸附·开'), findsOneWidget);
      expect(find.text('预览吸附·关'), findsNothing);
      // 吸附设置入口已删除。
      expect(find.text('吸附 4拍'), findsNothing);
      // 前导选择器退场：恒显标签不再存在。
      expect(find.text('前导 4拍'), findsNothing);

      // 状态切换即换文字：预览吸附关、锁定分段开。
      await tester.tap(find.byKey(const Key('track_preview_snap_slot')));
      await tester.tap(find.byKey(const Key('layout_lock_toggle')));
      await pumpSettle(tester);
      expect(find.text('预览吸附·关'), findsOneWidget);
      expect(find.text('预览吸附·开'), findsNothing);
      expect(find.text('锁定分段·开'), findsOneWidget);
      expect(find.text('锁定分段·关'), findsNothing);
    });

    testWidgets('锁定后手柄拖动分段线：弹一次「已锁定分段」、线不动、无预览 seek', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );
      final container = enableLock(tester);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 线仍在 5s（不执行移动）。锁定下拖动**首次位移成立那刻**弹一次
      //「已锁定分段」并放弃本次手势：本手势已多次 move，
      // 计数器仍为 1 = 一次手势只弹一次。
      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
      );
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        1,
        reason: '首次位移成立弹一次「已锁定分段」',
      );
      // 不进入拖线预览会话（无预览 seek；拖线放行时的对照见其它用例）。
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('锁定后分段线控制柄单击仍可选中（选中不受锁）', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
        ),
      );
      final container = enableLock(tester);
      await pumpSettle(tester);

      await tester.tap(find.byKey(const Key('segment_line_0_handle')));
      await pumpSettle(tester);
      expect(container.read(annotationSelectionProvider).asSegmentLineIndex, 0);
      // 单击不是被阻止操作：不触发提示。
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    testWidgets('锁定后按住分段线控制柄不位移：起手静默不弹提示', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );
      final container = enableLock(tester);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        0,
        reason: '起手（未越过拖动阈值）静默',
      );
      await gesture.up();
      await pumpSettle(tester);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    testWidgets('锁定后拖视频首尾边界：弹一次「已锁定分段」、边界不动、无预览 seek', (tester) async {
      const total = Duration(seconds: 100);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
        ),
      );
      final container = enableLock(tester);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('video_range_start_marker'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(120, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 边界仍在 10s（不执行调界），无预览 seek。锁定下拖动首次位移成立
      // 即弹一次「已锁定分段」并放弃本次手势（多次 move 仍为 1）。
      expect(
        bandTimeline(tester).rangeStart,
        const Duration(seconds: 10),
        reason: '首尾线拖动被锁',
      );
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(seconds: 10),
      );
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        1,
        reason: '首次位移成立弹一次「已锁定分段」',
      );
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('锁定后首尾线控制柄单击仍可选中（选中不受锁）', (tester) async {
      const total = Duration(seconds: 100);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
        ),
      );
      final container = enableLock(tester);
      await pumpSettle(tester);

      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await pumpSettle(tester);
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.start,
      );
      // 单击不是被阻止操作：不触发提示。
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });
  });

  /// 首/尾控制柄拖动宿主（写入经标注编辑模块拖动
  /// 会话进 provider，返回拖动后的容器时间线；[previewSnapEnabled] 指预览
  /// 磁吸开关不影响首尾线拖动；[readyGrid] 注入就绪真实
  /// 网格（0.5s 均匀拍点，与占位 120bpm 逐位同拍）——无网格时自由落点）。
  Future<AnnotationTimeline> pumpAndDragRangeHandle(
    WidgetTester tester, {
    required AnnotationTimeline initial,
    required Key markerKey,
    required Offset totalDelta,
    bool previewSnapEnabled = true,
    bool readyGrid = false,
  }) async {
    final engine = FakePlaybackEngine(duration: initial.videoDuration);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          annotationTimelineProvider.overrideWithBuild((ref, _) => initial),
          if (readyGrid)
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  beats: [
                    for (var i = 0; i < 360; i++)
                      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
                  ],
                ),
              ),
            ),
          if (!previewSnapEnabled)
            previewSnapEnabledProvider.overrideWith(_PreviewSnapOffModel.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: buildTrackBandSession(engine: engine),
                rowTable: TrackRowTable.normal,
              ),
            ),
          ),
        ),
      ),
    );
    await pumpSettle(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(markerKey)),
    );
    await tester.pump();
    // 同 dragBySteps：分两步移动并逐拍泵帧。
    await gesture.moveBy(totalDelta / 2);
    await tester.pump();
    await gesture.moveBy(totalDelta / 2);
    await tester.pump();
    await gesture.up();
    await pumpSettle(tester);
    return bandTimeline(tester);
  }

  group('首/尾控制柄拖动归格（强制对齐真实拍点）', () {
    // 几何：带宽 800px、总长 180s → 4.4444px/s；注入就绪真实网格 0.5s
    // 均匀拍点，对齐落点 = 覆盖区内全部真实拍点（0/0.5/1…s）。落点在
    // 网格覆盖区内逐帧归格（磁吸分段线不参与首尾线拖动）；覆盖区外或
    // 无网格（占位/异常）自由跟手；「预览吸附」开关只作用于预览条拖动。
    testWidgets('拖首线落点归格到最近真实拍点（磁吸分段线不参与）', (tester) async {
      final timeline = await pumpAndDragRangeHandle(
        tester,
        initial: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
          // 落点 31.4s 距该线 0.4s（预览磁吸半径内）→ 归格 32s 而非磁吸。
          segmentLines: const [SegmentLine(position: Duration(seconds: 31))],
        ),
        markerKey: const Key('video_range_start_marker'),
        // 首线 10s → 落点 31.4s（内容区宽换算）：最近真实拍点
        // 31.5s。
        totalDelta: Offset(bandX(31.4, total: 180) - bandX(10, total: 180), 0),
        readyGrid: true,
      );
      expect(
        timeline.rangeStart,
        const Duration(seconds: 31, milliseconds: 500),
      );
    });

    testWidgets('拖尾线落点归格到最近真实拍点（磁吸分段线不参与）', (tester) async {
      final timeline = await pumpAndDragRangeHandle(
        tester,
        initial: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 110),
          // 落点 98.6s 距该线 0.4s（预览磁吸半径内）→ 归格 98s 而非磁吸。
          segmentLines: const [SegmentLine(position: Duration(seconds: 99))],
        ),
        markerKey: const Key('video_range_end_marker'),
        // 尾线 110s → 落点 98.6s（内容区宽换算）：最近真实拍点 98.5s。
        totalDelta: Offset(bandX(98.6, total: 180) - bandX(110, total: 180), 0),
        readyGrid: true,
      );
      expect(timeline.rangeEnd, const Duration(seconds: 98, milliseconds: 500));
    });

    testWidgets('「预览吸附」开关关闭：首尾线拖动仍归格（开关只作用于预览条）', (tester) async {
      final timeline = await pumpAndDragRangeHandle(
        tester,
        initial: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
          segmentLines: const [SegmentLine(position: Duration(seconds: 31))],
        ),
        markerKey: const Key('video_range_start_marker'),
        // 落点 31.4s → 最近真实拍点 31.5s。
        totalDelta: Offset(bandX(31.4, total: 180) - bandX(10, total: 180), 0),
        previewSnapEnabled: false,
        readyGrid: true,
      );
      expect(
        timeline.rangeStart,
        const Duration(seconds: 31, milliseconds: 500),
      );
    });

    testWidgets('无网格（占位）：自由落点；落点可越过原尾线', (tester) async {
      final timeline = await pumpAndDragRangeHandle(
        tester,
        initial: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
        ),
        markerKey: const Key('video_range_end_marker'),
        // 尾线 100s → 落点 ≈115s（内容区宽换算）：无网格自由落点，可拖出
        // 节拍生成区域。
        totalDelta: Offset(bandX(115, total: 180) - bandX(100, total: 180), 0),
      );
      expect(timeline.rangeEnd.inMilliseconds, closeTo(115000, 300));
    });

    testWidgets('就绪网格覆盖区内越过原尾线：照常归格（可拖过旧边界）', (tester) async {
      final timeline = await pumpAndDragRangeHandle(
        tester,
        initial: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 100),
        ),
        markerKey: const Key('video_range_end_marker'),
        // 尾线 100s → 落点 ≈115s（就绪网格覆盖区 0..179.5s 内，内容区宽
        // 换算）：归最近真实拍点 115s。
        totalDelta: Offset(bandX(115, total: 180) - bandX(100, total: 180), 0),
        readyGrid: true,
      );
      expect(timeline.rangeEnd, const Duration(seconds: 115));
    });

    testWidgets('就绪网格覆盖区外（末拍之后）：自由落点、不吸回末格点', (tester) async {
      final timeline = await pumpAndDragRangeHandle(
        tester,
        initial: AnnotationTimeline.normalized(
          videoDuration: const Duration(minutes: 3),
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 165),
        ),
        markerKey: const Key('video_range_end_marker'),
        // 就绪网格覆盖区止于末拍 179.5s；尾线 165s → 落点 ≈180s（钳到视频
        // 尾 180s）在覆盖区外 → 自由落点，不吸回 178s 末格点。
        totalDelta: const Offset(66.7, 0),
        readyGrid: true,
      );
      expect(timeline.rangeEnd.inMilliseconds, closeTo(180000, 300));
    });
  });

  /// 拖动会话迁移：轨道带拖动手势改走标注编辑模块会话对象
  /// （beginLineDrag/beginRangeDrag→moveTo→end），widget 只做意图陈述——
  /// 一次拖动单步入史、无净变化不入史、预览由 moveTo 返回的真实落点驱动。
  group('拖动会话迁移', () {
    AnnotationTimeline seeded(
      Iterable<SegmentLine> lines, {
      Duration? rangeStart,
      Duration? rangeEnd,
    }) => AnnotationTimeline.normalized(
      videoDuration: const Duration(seconds: 30),
      rangeStart: rangeStart ?? Duration.zero,
      rangeEnd: rangeEnd ?? const Duration(seconds: 30),
      segmentLines: lines.toList(),
    );

    testWidgets('拖分段线一次会话单步入史：撤销一步回拖动前，再撤销 no-op', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: seeded([
          const SegmentLine(position: Duration(seconds: 10)),
          const SegmentLine(position: Duration(seconds: 20)),
        ]),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );

      // 几何清除冒烟——拖线（几何变化）经模块路径
      // 仍清除激活学习段。
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(40, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        container.read(selectedLearningSegmentsProvider),
        isEmpty,
        reason: '几何变化清除激活（模块路径）',
      );
      final history = container.read(annotationEditHistoryProvider);
      expect(history.canUndo, isTrue, reason: '一次拖动 = 一条历史');
      expect(history.canRedo, isFalse);
      expect(
        bandTimeline(tester).segmentLines[0].position,
        isNot(const Duration(seconds: 10)),
        reason: '拖动生效',
      );

      container.read(annotationEditorProvider).undo();
      expect(
        bandTimeline(tester).segmentLines[0].position,
        const Duration(seconds: 10),
        reason: '撤销一步回拖动前（非逐帧）',
      );
      expect(container.read(annotationEditHistoryProvider).canUndo, isFalse);
    });

    testWidgets('拖分段线无净变化（触界钳制丢弃）：不入史', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: seeded([const SegmentLine(position: Duration(seconds: 10))]),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );

      // 向左拖出有效区间（越触界 → 模块钳制丢弃，整帧 no-op）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(-600, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).segmentLines[0].position,
        const Duration(seconds: 10),
      );
      expect(
        container.read(annotationEditHistoryProvider).canUndo,
        isFalse,
        reason: '无净变化不入史',
      );
    });

    testWidgets('系统取消拖线与松手同走 end：单步入史、无悬挂会话', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: seeded([const SegmentLine(position: Duration(seconds: 10))]),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );

      // 拖动生效后系统取消（onDragCancel 与 onDragEnd 同走 end 收口）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(40, 0));
      await gesture.cancel();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).segmentLines[0].position,
        isNot(const Duration(seconds: 10)),
        reason: '已写入的帧保留',
      );
      final history = container.read(annotationEditHistoryProvider);
      expect(history.canUndo, isTrue, reason: '取消收口仍单步入史');
      expect(history.canRedo, isFalse);

      container.read(annotationEditorProvider).undo();
      expect(
        bandTimeline(tester).segmentLines[0].position,
        const Duration(seconds: 10),
        reason: 'end 幂等：取消后无第二次收口/第二条历史',
      );
    });

    testWidgets('拖首线一次会话单步入史；起点=终点会话不入史', (tester) async {
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: seeded(
          [],
          rangeStart: const Duration(seconds: 10),
          rangeEnd: const Duration(seconds: 25),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('video_range_start_marker'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(40, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).rangeStart,
        isNot(const Duration(seconds: 10)),
      );
      expect(container.read(annotationEditHistoryProvider).canUndo, isTrue);

      container.read(annotationEditorProvider).undo();
      expect(bandTimeline(tester).rangeStart, const Duration(seconds: 10));
      expect(container.read(annotationEditHistoryProvider).canUndo, isFalse);
      await pumpSettle(tester); // 撤销后泵帧：UI 重建回 10s 位置再起手。

      // 起点即终点（同一会话内拖出又拖回原位，净变化为零）：不入史。
      final g2 = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('video_range_start_marker'))),
      );
      await tester.pump();
      await dragBySteps(tester, g2, const Offset(40, 0));
      await dragBySteps(tester, g2, const Offset(-40, 0));
      await g2.up();
      await pumpSettle(tester);
      expect(
        container.read(annotationEditHistoryProvider).canUndo,
        isFalse,
        reason: '起点=终点会话不入史',
      );
    });
  });

  group('节拍轨三态', () {
    testWidgets('异常态：整行暖色底，轨内显示「节拍识别失败」，不画刻度', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => const BeatTrackState.error(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      expect(find.byKey(const Key('beat_track_failed')), findsOneWidget);
      expect(find.text('节拍识别失败'), findsOneWidget);
      expect(find.byKey(const ValueKey('beat_tick_0')), findsNothing);

      // 轨道高度与布局不跳：节拍轨行高不变，
      // 异常态不弹任何提示（无 Dialog/SnackBar）。
      final trackSize = tester.getSize(find.byKey(const Key('track_beat')));
      expect(
        trackSize.height,
        TrackRowTable.normal.rectOf(TrackRowId.beat).height,
      );
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('就绪态：按真实拍时刻绘制刻度（非均匀占位）', (tester) async {
      final total = const Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            beatTrackStateProvider.overrideWithBuild(
              (ref, _) => BeatTrackState.ready(
                marker_doc.BeatGrid(
                  model: 'm',
                  fps: 100,
                  generatedAt: DateTime.utc(2026, 9, 6),
                  beats: [
                    marker_doc.BeatPoint(t: 0.25, down: true),
                    marker_doc.BeatPoint(t: 0.9, down: false),
                    marker_doc.BeatPoint(t: 1.7, down: false),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: buildTrackBandSession(engine: engine),
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        ),
      );
      await pumpSettle(tester);

      // 刻度落在真实拍时刻（微秒键），占位 2s 格点不再出现。
      expect(find.byKey(const ValueKey('beat_tick_250000')), findsOneWidget);
      expect(find.byKey(const ValueKey('beat_tick_900000')), findsOneWidget);
      expect(find.byKey(const ValueKey('beat_tick_1700000')), findsOneWidget);
      expect(find.byKey(const ValueKey('beat_tick_0')), findsNothing);

      // 强拍强调：downbeat 刻度显著亮于普通拍刻度（t=0.25 down=true）。
      Color tickColor(Key key) => tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      expect(
        tickColor(const ValueKey('beat_tick_250000')).a,
        greaterThan(tickColor(const ValueKey('beat_tick_900000')).a),
      );
      // 三级层级宽同样适用就绪态：首 downbeat = 八拍大线（宽 1.5）。
      expect(
        tester.getSize(find.byKey(const ValueKey('beat_tick_250000'))).width,
        1.5,
      );
    });
  });

  group('备注轨行与备注片段呈现', () {
    const total = Duration(minutes: 3);

    testWidgets('备注片段与时间窗等宽呈现于备注轨行内，放大后框内显出文本', (tester) async {
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      final engine = FakePlaybackEngine(duration: total);
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        notes: const [NoteSticker(startMs: 63000, endMs: 73000, text: '这里注意手')],
      );
      session.updateWindow(win);
      await pumpSettle(tester);

      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      final notesRowRect = tester.getRect(find.byKey(const Key('track_notes')));
      final blockRect = tester.getRect(
        find.byKey(const Key('note_fragment_0')),
      );

      // 块体落在备注轨行内（纵向贴行矩形）。
      expect(blockRect.top, notesRowRect.top);
      expect(blockRect.height, notesRowRect.height);
      // 与时间窗等宽：模块几何 = 带实测宽下同一窗口求值（交叉断言；
      // 内容区左缘让出轨道片头带）。
      final geometry = bandGeometryOf(
        total: total,
        window: win,
        width: bandRect.width,
      );
      expect(
        blockRect.left - bandRect.left,
        closeTo(
          geometry.timeToPixel(const Duration(milliseconds: 63000)),
          0.01,
        ),
      );
      expect(
        blockRect.width,
        closeTo(
          geometry.timeToPixel(const Duration(milliseconds: 73000)) -
              geometry.timeToPixel(const Duration(milliseconds: 63000)),
          0.01,
        ),
      );
      // 框内文本：块体放得下全句时整句显出（与贴纸逐字一致）。
      expect(
        find.descendant(
          of: find.byKey(const Key('note_fragment_0')),
          matching: find.text('这里注意手'),
        ),
        findsOneWidget,
      );
    });

    group('备注片段框内文本', () {
      const total = Duration(minutes: 3);

      RenderParagraph inlineParagraph(WidgetTester tester) =>
          tester.renderObject<RenderParagraph>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('note_fragment_0_text')),
                  matching: find.byType(RichText),
                )
                .first,
          );

      /// 同样式（框内文本具名字号）下整句的自然宽度（独立真源：测试侧
      /// 自行排版，不读实现）。
      double naturalWidth(String text) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(inherit: false, fontSize: kNoteInlineTextFontSize),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final width = tp.size.width;
        tp.dispose();
        return width;
      }

      /// 框内文本实际画出的墨迹宽（可见字形，含截断时的省略号）。
      double inkWidth(RenderParagraph paragraph) {
        final plain = paragraph.text.toPlainText();
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length),
        );
        return boxes.last.right - boxes.first.left;
      }

      testWidgets('放不下全句时省略号截断（截断不丢语义文本、不留残字）', (tester) async {
        // 2s 窗在 800px 带宽下 1s = 400px：180ms 片段 = 72px 块宽，
        // 扣两侧内边距后放不下 9 个字。
        const win = TimelineWindow(
          total: total,
          start: Duration(seconds: 60),
          end: Duration(seconds: 62),
        );
        final engine = FakePlaybackEngine(duration: total);
        final session = buildTrackBandSession(engine: engine);
        await pumpBand(
          tester,
          engine: engine,
          session: session,
          notes: const [
            NoteSticker(startMs: 60000, endMs: 60180, text: '这里注意手腕的转动方向'),
          ],
        );
        session.updateWindow(win);
        await pumpSettle(tester);

        final paragraph = inlineParagraph(tester);
        expect(paragraph.text.toPlainText(), '这里注意手腕的转动方向');
        // 截断生效：可见墨迹窄于整句自然宽（省略号替代了被裁的内容，
        // 字形边界收口、无半个字的残字）。
        expect(inkWidth(paragraph), lessThan(naturalWidth('这里注意手腕的转动方向')));
      });

      testWidgets('连省略号也放不下时完全不显示内容（无最小显示宽）', (tester) async {
        // 默认缩放看全片：3 分钟在 800px 带宽下 1s ≈ 4.4px，窄于省略号。
        const win = TimelineWindow(
          total: total,
          start: Duration.zero,
          end: total,
        );
        final engine = FakePlaybackEngine(duration: total);
        final session = buildTrackBandSession(engine: engine);
        await pumpBand(
          tester,
          engine: engine,
          session: session,
          notes: const [
            NoteSticker(startMs: 60000, endMs: 61000, text: '这里注意手'),
          ],
        );
        session.updateWindow(win);
        await pumpSettle(tester);

        expect(
          find.byKey(const ValueKey('note_fragment_0_text')),
          findsNothing,
        );
        expect(find.text('这里注意手'), findsNothing);
      });

      testWidgets('可用宽为正但窄于省略号：按实测宽度判「不显示」', (tester) async {
        // 默认缩放看全片：3 分钟在 800px 带宽下 1s ≈ 4.4px。2s 片段约
        // 8.9px 块宽，扣两侧内边距后可用宽约 2.9px——**正数**（不是"宽度
        // 非正"的早退），但窄于省略号自身宽度，故走「连省略号也放不下」
        // 那一支：判据只有实测宽度。
        const win = TimelineWindow(
          total: total,
          start: Duration.zero,
          end: total,
        );
        final engine = FakePlaybackEngine(duration: total);
        final session = buildTrackBandSession(engine: engine);
        await pumpBand(
          tester,
          engine: engine,
          session: session,
          notes: const [
            NoteSticker(startMs: 60000, endMs: 62000, text: '这里注意手'),
          ],
        );
        session.updateWindow(win);
        await pumpSettle(tester);

        final block = tester.getRect(
          find.byKey(const ValueKey('note_fragment_0')),
        );
        final available = block.width - 2 * kNoteInlineTextHorizontalPadding;
        expect(available, greaterThan(0), reason: '可用宽为正，排除"宽度非正"早退');
        expect(available, lessThan(naturalWidth('…')), reason: '窄于省略号自身宽度');
        expect(
          find.byKey(const ValueKey('note_fragment_0_text')),
          findsNothing,
        );
      });

      testWidgets('锁定标识优先占位：先扣角标位置再判文本，两者不重叠', (tester) async {
        // 72px 块宽：不锁时 6 字全显（可用 66px ≥ 60px）；锁定后扣掉
        // 角标占位 16dp（圆角 4 + 角标 10 + 间隙 2），可用 50px < 60px。
        const win = TimelineWindow(
          total: total,
          start: Duration(seconds: 60),
          end: Duration(seconds: 62),
        );
        NoteSticker note(bool locked) => NoteSticker(
          startMs: 60000,
          endMs: 60180,
          text: '这里注意手腕',
          locked: locked,
        );
        final engine = FakePlaybackEngine(duration: total);
        final session = buildTrackBandSession(engine: engine);
        Widget band(List<NoteSticker> notes, Key scopeKey) => ProviderScope(
          key: scopeKey,
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            noteStickersProvider.overrideWithBuild((ref, _) => notes),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TrackBand(
                input: TrackBandInput(
                  session: session,
                  rowTable: TrackRowTable.normal,
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(band([note(false)], const ValueKey('free')));
        session.updateWindow(win);
        await pumpSettle(tester);

        final unlockedRect = tester.getRect(
          find.byKey(const ValueKey('note_fragment_0_text')),
        );
        final blockRect = tester.getRect(
          find.byKey(const Key('note_fragment_0')),
        );
        expect(
          unlockedRect.width,
          blockRect.width - 2 * kNoteInlineTextHorizontalPadding,
        );
        // 全显档：可见墨迹 = 整句自然宽（测试字体每字advance略有出入，容差 2px）。
        expect(
          inkWidth(inlineParagraph(tester)),
          closeTo(naturalWidth('这里注意手腕'), 2),
        );

        await tester.pumpWidget(band([note(true)], const ValueKey('locked')));
        await pumpSettle(tester);

        final lockedRect = tester.getRect(
          find.byKey(const ValueKey('note_fragment_0_text')),
        );
        // 文本区右移且收窄：让出的正是角标占位（先扣后判），锁定后放
        // 不下全句（转入省略号档）。
        expect(
          lockedRect.left - blockRect.left,
          kNoteBlockCornerRadius +
              kNoteLockBadgeSize +
              kNoteLockTextGap +
              kNoteInlineTextHorizontalPadding,
        );
        expect(
          lockedRect.width,
          blockRect.width -
              kNoteBlockCornerRadius -
              kNoteLockBadgeSize -
              kNoteLockTextGap -
              2 * kNoteInlineTextHorizontalPadding,
        );
        // 让位后放不下全句：可见墨迹窄于整句自然宽（省略号档）。
        expect(
          inkWidth(inlineParagraph(tester)),
          lessThan(naturalWidth('这里注意手腕')),
        );
        // 两者不重叠：文本区左缘不越过角标右缘。
        final badgeRect = tester.getRect(
          find.byKey(const ValueKey('note_fragment_0_lock')),
        );
        expect(lockedRect.left, greaterThanOrEqualTo(badgeRect.right));
      });

      testWidgets('点名语法与贴纸同源：隐藏 @ 与紧随空格、名字按代表色', (tester) async {
        const win = TimelineWindow(
          total: total,
          start: Duration(seconds: 60),
          end: Duration(seconds: 90),
        );
        final engine = FakePlaybackEngine(duration: total);
        final session = buildTrackBandSession(engine: engine);
        await pumpBand(
          tester,
          engine: engine,
          session: session,
          notes: const [
            NoteSticker(startMs: 63000, endMs: 73000, text: '@果 走位偏左'),
          ],
        );
        session.updateWindow(win);
        await ProviderScope.containerOf(tester.element(find.byType(TrackBand)))
            .read(dancerRosterControllerProvider)
            .addDancer('果', color: 0xFFE53935);
        await pumpSettle(tester);

        // 与贴纸逐字一致：语法字符（@ 与分隔空格）不显示。
        expect(find.text('果走位偏左'), findsOneWidget);
        expect(find.textContaining('@'), findsNothing);
        // 点名段按代表色着色（与贴纸同一套配色）。
        final textWidget = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('note_fragment_0_text')),
                matching: find.byType(Text),
              ),
            )
            .single;
        final spans = (textWidget.textSpan! as TextSpan).children!
            .cast<TextSpan>()
            .toList();
        expect(spans.first.text, '果');
        expect(spans.first.style!.color, const Color(0xFFE53935));
        expect(spans.last.text, '走位偏左');
      });

      testWidgets('语义档：量测与渲染吃同一个系统字号缩放值', (tester) async {
        // 90s 窗、10s 片段 → 块宽足够放全句 6 字（60px）；1.3× 下整句宽
        // 78px 仍放得下，渲染宽必须按 1.3× 计。
        const win = TimelineWindow(
          total: total,
          start: Duration(seconds: 60),
          end: Duration(seconds: 70),
        );
        final engine = FakePlaybackEngine(duration: total);
        final session = buildTrackBandSession(engine: engine);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpBand(
          tester,
          engine: engine,
          session: session,
          notes: const [
            NoteSticker(startMs: 60000, endMs: 70000, text: '这里注意手腕'),
          ],
        );
        session.updateWindow(win);
        await pumpSettle(tester);

        expect(tester.takeException(), isNull);
        final paragraph = inlineParagraph(tester);
        expect(
          paragraph.textScaler.scale(10),
          13.0,
          reason: '语义档随系统字号：1.3× 下真的放大',
        );
        // 两侧同源：渲染吃环境缩放值（量测侧 [_fitNoteInlineText] 取同一值，
        // 「判定放得下」即「渲染放得下」）。
        final textWidget = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('note_fragment_0_text')),
                matching: find.byType(Text),
              ),
            )
            .first;
        expect(
          textWidget.textScaler,
          MediaQuery.textScalerOf(
            tester.element(find.byKey(const ValueKey('note_fragment_0_text'))),
          ),
        );
        // 全显档：可见墨迹 = 整句 1.3× 自然宽（判定按缩放后实测重算）。
        expect(inkWidth(paragraph), closeTo(naturalWidth('这里注意手腕') * 1.3, 2.6));
      });
    });

    testWidgets('备注块体几何消费共用件 intervalBlockRect：窗外裁切与渲染像素逐位一致', (tester) async {
      // 时间窗起点越出可视窗口左缘 → 裁切后块左缘贴窗；块右缘在窗内。
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      final engine = FakePlaybackEngine(duration: total);
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        notes: const [
          NoteSticker(startMs: 30000, endMs: 70000),
          NoteSticker(startMs: 80000, endMs: 88000),
        ],
      );
      session.updateWindow(win);
      await pumpSettle(tester);

      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      // 窗口起点 > 0 时让位宽 = 片头可见右缘（此处已滑出 → 0），
      // 期望口径与渲染同读一份几何。
      final geometry = bandGeometryOf(
        total: total,
        window: win,
        width: bandRect.width,
      );
      final contentLeft = geometry.contentLeft;
      final contentWidth = geometry.contentWidth;
      const windowMs = IntervalSpan(startMs: 60000, endMs: 90000);
      const spans = [
        IntervalSpan(startMs: 30000, endMs: 70000),
        IntervalSpan(startMs: 80000, endMs: 88000),
      ];
      for (var i = 0; i < spans.length; i++) {
        final expected = intervalBlockRect(
          span: spans[i],
          window: windowMs,
          trackWidth: contentWidth,
          contentLeft: contentLeft,
        )!;
        final rendered = tester.getRect(find.byKey(Key('note_fragment_$i')));
        expect(
          rendered.left - bandRect.left,
          closeTo(expected.left, 0.01),
          reason: '片段 $i 左缘与共用件几何一致',
        );
        expect(
          rendered.width,
          closeTo(expected.width, 0.01),
          reason: '片段 $i 宽与共用件几何一致（窗口外裁切）',
        );
      }
      // 第一条裁切后左缘恰贴可视窗口左缘（= 内容区左缘；让位
      // 收回后内容区左缘 = 带左缘）。
      expect(
        tester.getRect(find.byKey(const Key('note_fragment_0'))).left,
        bandRect.left + contentLeft,
      );
    });

    testWidgets('窄块按几何原样渲染不缩水，块体仍可辨', (tester) async {
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      final engine = FakePlaybackEngine(duration: total);
      final session = buildTrackBandSession(engine: engine);
      // 200ms 窗在 800px 宽带 ≈ 5.3px：窄块不因窄而缩到 0 或消失。
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        notes: const [NoteSticker(startMs: 65000, endMs: 65200)],
      );
      session.updateWindow(win);
      await pumpSettle(tester);

      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      // 内容区宽随让位收回而变，期望口径与渲染同读一份几何。
      final geometry = bandGeometryOf(
        total: total,
        window: win,
        width: bandRect.width,
      );
      final expected = intervalBlockRect(
        span: const IntervalSpan(startMs: 65000, endMs: 65200),
        window: const IntervalSpan(startMs: 60000, endMs: 90000),
        trackWidth: geometry.contentWidth,
        contentLeft: geometry.contentLeft,
      )!;
      final rendered = tester.getRect(find.byKey(const Key('note_fragment_0')));
      expect(rendered.width, closeTo(expected.width, 0.01));
      expect(rendered.width, greaterThan(0));
    });

    testWidgets('完全在可视窗口外的备注不渲染', (tester) async {
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      final engine = FakePlaybackEngine(duration: total);
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        notes: const [NoteSticker(startMs: 10000, endMs: 20000)],
      );
      session.updateWindow(win);
      await pumpSettle(tester);

      expect(find.byKey(const Key('note_fragment_0')), findsNothing);
    });

    testWidgets('备注轨常驻：无备注时行背景照常渲染（空轨亦显示）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine);

      expect(find.byKey(const Key('track_notes')), findsOneWidget);
      expect(find.byKey(const Key('note_fragment_0')), findsNothing);
    });
  });

  group('练习片段轨', () {
    const total = Duration(minutes: 3);

    PracticeClip clipOf(String id, int startMs, int endMs) => PracticeClip(
      id: id,
      materialId: 'mat_$id',
      materialSourceStartMs: 0,
      inMs: startMs,
      outMs: endMs,
    );

    /// pump 后直写片段列表会话值（provider 由 widget 树内读取，免改
    /// pumpBand harness 的 override 集）。
    Future<void> giveClips(WidgetTester tester, List<PracticeClip> clips) {
      ProviderScope.containerOf(tester.element(find.byType(TrackBand)))
              .read(practiceClipsProvider.notifier)
              .state =
          clips;
      return tester.pumpAndSettle();
    }

    testWidgets('练习片段渲染为轨上块，位置 = 源时间区间；空轨无块', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);
      await giveClips(tester, [clipOf('c1', 60000, 90000)]);

      final block = tester.getRect(find.byKey(const Key('practice_clip_c1')));
      final row = tester.getRect(find.byKey(const Key('track_practice')));
      // 块落在行内（纵向贴合行），横向按 60s..90s / 180s 全窗线性映射。
      expect(block.top, row.top);
      expect(block.height, row.height);
      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      // 位置按内容区宽（带宽让出轨道片头带）线性映射。
      expect(block.left, closeTo(bandX(60, total: 180), 0.5));
      expect(
        block.width,
        closeTo(bandContentWidth(width) * 30000 / 180000, 0.5),
      );

      // 多片段并存。
      await giveClips(tester, [
        clipOf('c1', 60000, 90000),
        clipOf('c2', 120000, 150000),
      ]);
      expect(find.byKey(const Key('practice_clip_c1')), findsOneWidget);
      expect(find.byKey(const Key('practice_clip_c2')), findsOneWidget);

      // 空轨：无块、行仍常驻显示。
      await giveClips(tester, const []);
      expect(find.byKey(const Key('practice_clip_c1')), findsNothing);
      expect(find.byKey(const Key('track_practice')), findsOneWidget);
    });

    testWidgets('位置固定：横向拖动块体不换位（拖动无效）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);
      await giveClips(tester, [clipOf('c1', 60000, 90000)]);

      final before = tester.getRect(find.byKey(const Key('practice_clip_c1')));
      final gesture = await tester.startGesture(before.center);
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      await gesture.up();
      await pumpSettle(tester);

      expect(tester.getRect(find.byKey(const Key('practice_clip_c1'))), before);
    });
  });

  group('练习片段截取：端点拖的可见行为', () {
    const total = Duration(minutes: 3);

    // 源区间 60s–90s：素材源起点 60000、素材全长 30000、截取范围 0–30000
    // （素材全长）——端点可截的两侧都有余量口径。
    const clip = PracticeClip(
      id: 'c1',
      materialId: 'm1',
      materialSourceStartMs: 60000,
      inMs: 0,
      outMs: 30000,
      materialDurationMs: 30000,
    );

    Future<void> giveClips(WidgetTester tester, List<PracticeClip> clips) {
      ProviderScope.containerOf(tester.element(find.byType(TrackBand)))
          .read(practiceClipsProvider.notifier)
          .restore(clips);
      return tester.pumpAndSettle();
    }

    /// 从端点带中心起手水平拖动 [dx] 像素（分步移动越过拖动 slop）。
    Future<void> dragEdge(WidgetTester tester, Key edgeKey, double dx) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(edgeKey)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      const steps = 12;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveBy(Offset(dx / steps, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await pumpSettle(tester);
    }

    /// 按期望的请求位移（毫秒 → 全窗线性像素 + 拖动 slop 补偿）拖端点。
    /// 带宽 800（测试面）下 1px ≈ 225ms，补偿取拖动识别的 ~18px slop；
    /// 期望落点两侧的吸附窗（±2s）远大于补偿误差。
    Future<void> dragEdgeByMs(
      WidgetTester tester,
      Key edgeKey,
      int deltaMs,
    ) async {
      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      final dx = deltaMs * width / 180000 + (deltaMs > 0 ? 18.0 : -18.0);
      await dragEdge(tester, edgeKey, dx);
    }

    testWidgets('拖尾端点：吸附拍点、只缩块尾（素材内 out 变化）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);
      await giveClips(tester, [clip]);

      final width = tester.getSize(find.byKey(const Key('track_band'))).width;
      // 请求 = 90s − 18s = 72s → 吸 72s 八拍点。
      await dragEdgeByMs(
        tester,
        const Key('practice_clip_c1_edge_end'),
        -18000,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      final trimmed = container.read(practiceClipsProvider).single;
      expect(trimmed.inMs, 0, reason: '另一端不动');
      expect(trimmed.outMs, 12000, reason: '吸附到 72s 八拍点（素材内 12000）');
      expect(trimmed.materialSourceStartMs, 60000, reason: '素材引用不动');
      expect(trimmed.materialDurationMs, 30000, reason: '素材全长记录不动');
      // 块可见范围跟随截取：60s–72s。
      final block = tester.getRect(find.byKey(const Key('practice_clip_c1')));
      expect(block.left, closeTo(bandX(60, total: 180), 0.5));
      expect(
        block.width,
        closeTo(bandContentWidth(width) * 12000 / 180000, 0.5),
      );
    });

    testWidgets('拖首端点：吸附拍点、只缩块首（素材内 in 变化）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);
      await giveClips(tester, [clip]);

      // 请求 = 60s + 9s = 69s → 吸 68s 八拍点。
      await dragEdgeByMs(
        tester,
        const Key('practice_clip_c1_edge_start'),
        9000,
      );

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      final trimmed = container.read(practiceClipsProvider).single;
      expect(trimmed.inMs, 8000, reason: '吸附到 68s 八拍点（素材内 8000）');
      expect(trimmed.outMs, 30000, reason: '另一端不动');
      final block = tester.getRect(find.byKey(const Key('practice_clip_c1')));
      expect(block.left, closeTo(bandX(68, total: 180), 0.5));
    });

    testWidgets('钳在素材时长内：拖越素材尾到头停住（无净变化、不入史）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);
      await giveClips(tester, [clip]);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      final before = container.read(practiceClipsProvider).single;

      // 请求远越素材尾（90s + 45s）→ 钳素材全长 = 现值，无净变化。
      await dragEdgeByMs(tester, const Key('practice_clip_c1_edge_end'), 45000);

      expect(container.read(practiceClipsProvider).single, before);
      expect(container.read(annotationEditHistoryProvider).length, 0);
    });
  });

  group('对比态只读：带级只读的可见行为', () {
    const total = Duration(minutes: 1);

    /// 泵对比行集 + 进入对比-控制层（模块门禁第二原因的单一事实源），
    /// 返回宿主容器供断言。
    Future<ProviderContainer> pumpCompareBand(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
      AnnotationTimeline? timeline,
      List<NoteSticker> notes = const [],
      VoidCallback? onCollapse,
    }) async {
      await pumpBand(
        tester,
        engine: engine,
        rowTable: TrackRowTable.compare,
        timeline: timeline,
        notes: notes,
        onCollapse: onCollapse,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await pumpSettle(tester);
      return container;
    }

    // 半拍线只读拖动的「起手被拒、状态与历史不动」由域直测与模块只读套件
    // 承担：track_band_drag_test.dart「起手门序言 / 门禁表拒绝」；模块侧
    // annotation_editor_compare_readonly_test.dart「对比态下几何 verb 全部被拒」。

    testWidgets('半拍线只读：点选不选中（静默不参与）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpCompareBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          halfBeatLines: const [HalfBeatLine(position: Duration(seconds: 20))],
        ),
      );
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await pumpSettle(tester);
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });

    testWidgets('分段线只读：控制柄拖动不启动（线不动、无 seek、不弹提示）', (tester) async {
      // 缺省行集（非对比行集）+ 对比会话：起手拦截由目标声明表回答，不靠
      // 「对比行集恰好不含此行」的巧合（去掉声明里的 compareReadonly 即放行）。
      const total = Duration(seconds: 30);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 5))],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('segment_line_0_handle'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(160, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        tester.getCenter(find.byKey(const Key('segment_line_0'))).dx,
        closeTo(bandX(5), 1),
        reason: '只读：拖动后线位一位不动',
      );
      // 静默不参与：不弹锁提示、不入史、不进拖线预览（无预览 seek）。
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('首尾端标只读：控制柄拖动不启动（边界不动、无 seek）', (tester) async {
      const total = Duration(seconds: 100);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 10),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await pumpSettle(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('video_range_start_marker'))),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(120, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).rangeStart,
        const Duration(seconds: 10),
        reason: '只读：边界一位不动',
      );
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(engine.seekCalls, isEmpty);
    });

    testWidgets('备注轨只渲染不参与命中：点片段不选中、不进编辑器', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpCompareBand(
        tester,
        engine: engine,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '手')],
      );
      final rect = tester.getRect(find.byKey(const Key('track_notes')));
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
      await pumpSettle(tester);
      expect(container.read(annotationSelectionProvider), isNull);
      expect(find.byKey(const Key('note_expand_bubble')), findsNothing);
    });

    testWidgets('备注轨不吞指针：空白单击照常落穿带级空白仲裁（收起）', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      var collapses = 0;
      await pumpCompareBand(
        tester,
        engine: engine,
        notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '手')],
        onCollapse: () => collapses++,
      );
      final rect = tester.getRect(find.byKey(const Key('track_notes')));
      // 片段区间（10–18s）之外的备注轨空白处。
      await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
      // 单击收起经带级判定窗口（双击判定窗过后才收起）。
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(collapses, 1, reason: '备注轨只读但空白语义与带内其它位置一致');
    });

    testWidgets('分段线全带可见但只读：选中/拖动入口结构性不可达', (tester) async {
      final engine = FakePlaybackEngine(duration: total);
      final container = await pumpCompareBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 30))],
        ),
      );
      expect(
        find.byKey(const Key('segment_line_0')),
        findsOneWidget,
        reason: '分段线全带可见',
      );
      // 控制柄行缺席 → 拖动/选中入口结构性不可达（已断言不渲染）；
      // 模块门禁兜底：无任何路径能把分段线拖动会话建立起来。
      expect(find.byKey(const Key('segment_line_0_handle')), findsNothing);
      expect(container.read(selectedSegmentLineIndexProvider), isNull);
    });
  });

  group('带内空白横滑 = 精细调整', () {
    /// 备注/镜像轨行级点按层在场时，scale 识别器到首次 move 越过 slop 才
    /// 赢得 arena（起手帧不产生 update 帧）——首段 move 起手、次段 move 出
    /// 首个 update 帧：累计目标 = [px]。
    Future<void> fineDrag(WidgetTester tester, TestGesture g, int px) async {
      await g.moveBy(Offset(px.toDouble(), 0));
      await tester.pump();
      await g.moveBy(Offset(px.toDouble(), 0));
      await tester.pump();
    }

    testWidgets('备注轨空白单指横滑：起手定格、目标随累计位移（预览线不贴手指）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = trackRowCenterY(tester, 'track_notes');
      await engine.play();
      await tester.pump();
      engine.callLog.clear();
      engine.seekCalls.clear();

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      // 两段 move（起手段 + update 段）：累计 +30px → 目标 +1.5s（与手指
      // 绝对位置无关）。
      await fineDrag(tester, g, 30);
      await pumpSettle(tester);

      expect(engine.isPlaying, isFalse, reason: '起手即定格（原在播先暂停）');
      expect(engine.callLog.first, 'pause');
      expect(
        engine.seekCalls.last,
        seekDeltaFor(30.toDouble(), 1),
        reason: '目标按累计位移走',
      );
      expect(
        tester.getCenter(previewLine()).dx,
        closeTo(bandX(1.5, total: 180), 2),
        reason: '预览线随目标时间移动、不贴手指',
      );

      await g.up();
      await pumpSettle(tester);
      expect(engine.isPlaying, isTrue, reason: '松手恢复手势前播放态');
      await engine.pause();
    });

    testWidgets('局部镜像轨空白横滑同一语义', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = trackRowCenterY(tester, 'track_mirror');

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await fineDrag(tester, g, 30);
      await pumpSettle(tester);

      expect(
        engine.seekCalls.last,
        seekDeltaFor(30.toDouble(), 1),
        reason: '目标按累计位移走',
      );
      await g.up();
      await pumpSettle(tester);
    });

    testWidgets('原暂停起手：全程不播、松手仍暂停（无意外开始播放）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = trackRowCenterY(tester, 'track_notes');

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await fineDrag(tester, g, 30);
      await g.up();
      await pumpSettle(tester);

      expect(engine.callLog.where((c) => c == 'play' || c == 'pause'), isEmpty);
      expect(engine.isPlaying, isFalse);
      expect(engine.seekCalls.last, seekDeltaFor(30.toDouble(), 1));
    });

    testWidgets('加指冻结：冻结期目标不动；下一 burst 的单指横滑恢复推进', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      final y = trackRowCenterY(tester, 'track_notes');

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await fineDrag(tester, g, 30); // 累计 +30px → 1.5s
      final frozenAt = seekDeltaFor(30.toDouble(), 1);

      // 加指：冻结（scale 会话重启不当作松手、目标与播放态不动）。
      final second = await tester.startGesture(Offset(420, y + 30));
      await tester.pump();
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(engine.seekCalls.last, frozenAt, reason: '冻结期目标不动');
      expect(engine.isPlaying, isFalse, reason: '冻结期保持定格');

      // 抬回单指：本 burst 仍是混区 burst（闩锁到全部指针抬起），单指语义
      // 整场抑制——同一 burst 内微调不恢复。
      await second.up();
      await tester.pump();
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
      await g.moveBy(const Offset(20, 0));
      await tester.pump();
      expect(
        engine.seekCalls.last,
        frozenAt,
        reason: '同一 burst 内混区闩锁整场抑制，目标不动',
      );
      await g.up();
      await pumpSettle(tester);

      // 下一 burst 的单指横滑重新起手：目标从新基准照常推进。
      final resumed = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await fineDrag(tester, resumed, 30);
      // 串行队列按帧节流：落定后再断言（pumpSettle 排空节流窗口）。
      await pumpSettle(tester);
      expect(
        engine.seekCalls.last,
        greaterThan(frozenAt),
        reason: '抬回单指后的新会话恢复微调推进',
      );
      await resumed.up();
      await pumpSettle(tester);
    });

    testWidgets('对比行集下备注轨空白横滑同样成立', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);
      final y = trackRowCenterY(tester, 'track_notes');
      await engine.play();
      await tester.pump();
      engine.callLog.clear();

      final g = await tester.startGesture(Offset(400, y));
      await tester.pump();
      await fineDrag(tester, g, 30);
      await pumpSettle(tester);

      expect(engine.isPlaying, isFalse, reason: '起手即定格');
      expect(engine.seekCalls.last, seekDeltaFor(30.toDouble(), 1));
      await g.up();
      await pumpSettle(tester);
      expect(engine.isPlaying, isTrue, reason: '松手恢复播放');
      await engine.pause();
    });

    testWidgets('片段块体上起手仍走整体平移：不进入微调（无 pause、预览线不随动）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine);
      // 学习段块体起手（块体拖动 = 整体平移的既有锚点行为；预览线不随动）。
      final y = trackRowCenterY(tester, 'track_learning');
      engine.seekCalls.clear();

      final g = await tester.startGesture(Offset(100, y));
      await tester.pump();
      await dragBySteps(tester, g, const Offset(50, 0));
      await g.up();
      await pumpSettle(tester);

      expect(
        engine.callLog.where((c) => c == 'pause' || c == 'play'),
        isEmpty,
        reason: '块体拖动不是微调：不起手定格',
      );
    });
  });

  group('轨道片头', () {
    Finder prefix() => find.byKey(const Key('track_prefix'));
    Finder prefixLabel(TrackRowId id) =>
        find.byKey(ValueKey('track_prefix_label_${id.name}'));

    /// 两段式横滑（起手段 + update 段），与带内空白横滑用例同款。
    Future<void> fineDrag(WidgetTester tester, TestGesture g, int px) async {
      await g.moveBy(Offset(px.toDouble(), 0));
      await tester.pump();
      await g.moveBy(Offset(px.toDouble(), 0));
      await tester.pump();
    }

    testWidgets('默认全片视图：编辑态五条标签完整可见、自下而上 = 控制/节拍/分段/镜像/备注', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(tester, engine: engine);
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));

      expect(prefix(), findsOneWidget);
      // 标签列的条数与文字 == 该态行集的声明（自下而上读序）。
      const bottomUp = [
        TrackRowId.handleStrip,
        TrackRowId.beat,
        TrackRowId.learning,
        TrackRowId.localMirror,
        TrackRowId.note,
      ];
      const expectedBottomUpLabels = ['控制', '节拍', '分段', '镜像', '备注'];
      expect([
        for (final id in bottomUp) tester.widget<Text>(prefixLabel(id)).data,
      ], expectedBottomUpLabels);
      // 行集声明与本态读序一致（条数与文案的单一来源）。
      expect(
        TrackRowTable.normal.prefixLabels.reversed.toList(),
        expectedBottomUpLabels,
      );
      // 行集之外的行没有标签。
      expect(prefixLabel(TrackRowId.practiceVideo), findsNothing);
      // 自下而上读序：dy 递减。
      final ys = [
        for (final id in bottomUp) tester.getCenter(prefixLabel(id)).dy,
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], lessThan(ys[i - 1]), reason: '片头列自下而上');
      }
      // 与所属行纵向对齐（行中心逐位一致）。
      for (final row in TrackRowTable.normal.rows) {
        expect(
          tester.getCenter(prefixLabel(row.id)).dy,
          closeTo(trackRowCenterY(tester, row.key), 0.01),
          reason: '片头标签与 ${row.key} 纵向对齐',
        );
      }
      // 位于时间轴零点之左并占满那一段：左缘贴带左缘、右缘 = 零点。
      final geometry = bandGeometryOf(total: total, width: bandRect.width);
      final rect = tester.getRect(prefix());
      expect(rect.left - bandRect.left, closeTo(geometry.prefixLeft, 0.01));
      expect(rect.right - bandRect.left, closeTo(geometry.prefixRight, 0.01));
      // 片头不改整带高（纵向几何与行矩形逐位不变）。
      expect(rect.top, bandRect.top);
      expect(rect.height, bandRect.height);
      expect(bandRect.height, TrackRowTable.normal.totalHeight);
      // 片头带与轨道内容之间一条视觉分界。
      expect(find.byKey(const Key('track_prefix_divider')), findsOneWidget);
    });

    testWidgets('对比态：四条标签（练习视频轨显「练习」，无「镜像」这一条）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpBand(tester, engine: engine, rowTable: TrackRowTable.compare);

      expect(prefix(), findsOneWidget);
      const bottomUp = [
        TrackRowId.beat,
        TrackRowId.learning,
        TrackRowId.practiceVideo,
        TrackRowId.note,
      ];
      const expectedBottomUpLabels = ['节拍', '分段', '练习', '备注'];
      expect([
        for (final id in bottomUp) tester.widget<Text>(prefixLabel(id)).data,
      ], expectedBottomUpLabels);
      expect(
        TrackRowTable.compare.prefixLabels.reversed.toList(),
        expectedBottomUpLabels,
      );
      // 对比态行集没有局部镜像轨与轨道手柄带行 → 片头也没有它们。
      expect(prefixLabel(TrackRowId.localMirror), findsNothing);
      expect(prefixLabel(TrackRowId.handleStrip), findsNothing);
      expect(
        tester.getCenter(prefixLabel(TrackRowId.practiceVideo)).dy,
        closeTo(trackRowCenterY(tester, 'track_practice'), 0.01),
      );
    });

    testWidgets('平移与缩放：片头随轨道内容一起走——右侧观察不可见，回开头又可见', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        // 备注块 0..5s：平移后被窗外裁切，左缘贴窗口起点（= 内容区左缘），
        // 用于钉「片头仍可见时与内容齐平」。
        notes: const [NoteSticker(startMs: 0, endMs: 5000)],
      );
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      TrackBandGeometry geometry(TimelineWindow? window) =>
          bandGeometryOf(total: total, window: window, width: bandRect.width);
      double prefixRightOnBand() =>
          tester.getRect(prefix()).right - bandRect.left;

      // 默认全片视图：完整可见。
      expect(prefixRightOnBand(), closeTo(geometry(null).prefixRight, 0.01));

      // 平移到轨道右侧观察：零点离开可视带 → 片头不可见（不是钉在屏幕左边
      // 的常驻侧栏）。
      const right = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      session.updateWindow(right);
      await pumpSettle(tester);
      expect(geometry(right).prefixVisible, isFalse, reason: '模块口径：已滑出可视带');
      expect(prefix(), findsNothing, reason: '滑出可视带即不画');

      // 轻微平移：片头部分仍在带内、屏上位置 = 模块求值（与内容同坐标），
      // 且仍与所属行纵向对齐。
      const nudged = TimelineWindow(
        total: total,
        start: Duration(seconds: 1),
        end: Duration(seconds: 91),
      );
      session.updateWindow(nudged);
      await pumpSettle(tester);
      expect(prefixRightOnBand(), closeTo(geometry(nudged).prefixRight, 0.01));
      expect(
        tester.getCenter(prefixLabel(TrackRowId.note)).dy,
        closeTo(trackRowCenterY(tester, 'track_notes'), 0.01),
      );
      // 让位收回 = 片头可见右缘 → 片头右缘与内容区左缘（窗外
      // 裁切的备注块左缘）渲染像素齐平，中间无空隙。
      expect(
        tester.getRect(find.byKey(const Key('note_fragment_0'))).left -
            bandRect.left,
        closeTo(prefixRightOnBand(), 0.01),
        reason: '片头仍可见时：片头右缘与片段左缘齐平（渲染层像素钉）',
      );

      // 缩放（可视窗变短）：片头仍随内容走（右缘仍 = 零点屏上 x）且逐行
      // 纵向对齐不变。
      const zoomed = TimelineWindow(
        total: total,
        start: Duration(seconds: 1),
        end: Duration(seconds: 61),
      );
      session.updateWindow(zoomed);
      await pumpSettle(tester);
      expect(prefixRightOnBand(), closeTo(geometry(zoomed).prefixRight, 0.01));
      for (final row in TrackRowTable.normal.rows) {
        expect(
          tester.getCenter(prefixLabel(row.id)).dy,
          closeTo(trackRowCenterY(tester, row.key), 0.01),
          reason: '缩放后片头仍与 ${row.key} 纵向对齐',
        );
      }

      // 平移回开头之前：又能在开头之前看到。
      session.updateWindow(null);
      await pumpSettle(tester);
      expect(prefix(), findsOneWidget);
      expect(prefixRightOnBand(), closeTo(geometry(null).prefixRight, 0.01));
    });

    testWidgets('片头区起手等同按在带上空白：不选中、不拖动、不吸附', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      final collapses = ValueNotifier<int>(0);
      await pumpBand(
        tester,
        engine: engine,
        onCollapse: () => collapses.value++,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          segmentLines: const [SegmentLine(position: Duration(seconds: 30))],
        ),
        notes: const [NoteSticker(startMs: 0, endMs: 5000, text: '开头备注')],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      final prefixRect = tester.getRect(prefix());

      // ① 定点单击（备注轨行内、片头中心）：不选中备注片段、不选中首线
      //（首线在时间轴零点，其 40dp 命中带一半压在片头里），按空白语义收起。
      await tester.tapAt(
        Offset(prefixRect.center.dx, trackRowCenterY(tester, 'track_notes')),
      );
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(container.read(selectedNoteFragmentIndexProvider), isNull);
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);
      expect(collapses.value, 1, reason: '片头等同带上空白：单击收起');

      // ①b 长按：不触发内容锁（片段锁定开关只在片段上切换）。
      await tester.longPressAt(
        Offset(prefixRect.center.dx, trackRowCenterY(tester, 'track_notes')),
      );
      await pumpSettle(tester);
      expect(
        container.read(noteStickersProvider).single.locked,
        isFalse,
        reason: '片头区长按不切换内容锁',
      );

      // ② 单指横滑（学习段轨行、片头中心）：不拖动首线、不吸附，与空白
      // 横滑同一语义（起手定格、目标按累计位移走、预览线不贴手指）。
      // 手柄带行那一段已归首线控制柄（见「首线控制柄延入片头」
      // 组），片头的**其它行**仍是空白语义。
      engine.seekCalls.clear();
      engine.callLog.clear();
      final g = await tester.startGesture(
        Offset(prefixRect.center.dx, trackRowCenterY(tester, 'track_learning')),
      );
      await tester.pump();
      await fineDrag(tester, g, 30);
      await pumpSettle(tester);
      await g.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).rangeStart,
        Duration.zero,
        reason: '片头区起手不拖动首线',
      );
      expect(container.read(selectedVideoRangeBoundaryProvider), isNull);
      // 片头区没有第二套识别器争仲裁 → scale 会话起手即成立，两段 30px
      // 都是微调帧（累计 60px），目标按累计位移走、不吸附。
      expect(
        engine.seekCalls.last,
        seekDeltaFor(60.toDouble(), 1),
        reason: '片头区横滑 = 带上空白横滑（目标按累计位移，不吸附）',
      );
      expect(container.read(selectedNoteFragmentIndexProvider), isNull);
    });
    testWidgets('片头滑出可视带后：让位收回、片段左缘贴带左缘（零点之左归内容）', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      final collapses = ValueNotifier<int>(0);
      final session = buildTrackBandSession(engine: engine);
      await pumpBand(
        tester,
        engine: engine,
        session: session,
        onCollapse: () => collapses.value++,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 60),
          rangeEnd: const Duration(seconds: 120),
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        notes: const [
          NoteSticker(startMs: 60000, endMs: 70000, text: '窗口起点备注'),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TrackBand)),
      );
      // 平移到中段观察：片头整列滑出可视带。让位宽收回为 0、
      // 整带归内容——不再保留「零点之左空白带」守卫，窗口起点处的内容
      // （备注 60s 起）左缘贴带左缘、可被点中。
      const win = TimelineWindow(
        total: total,
        start: Duration(seconds: 60),
        end: Duration(seconds: 90),
      );
      session.updateWindow(win);
      await pumpSettle(tester);
      expect(prefix(), findsNothing, reason: '前置：片头已滑出可视带');
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      expect(
        tester.getRect(find.byKey(const Key('note_fragment_0'))).left -
            bandRect.left,
        closeTo(0, 0.5),
        reason: '让位收回：窗口起点片段左缘贴带左缘，不留 40dp 空条',
      );
      final gutter = Offset(
        bandRect.left + kTrackPrefixWidth / 2,
        trackRowCenterY(tester, 'track_notes'),
      );

      // 原片头位置起手 = 内容命中：单击选中窗口起点处的备注片段。
      await tester.tapAt(gutter);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(
        container.read(selectedNoteFragmentIndexProvider),
        0,
        reason: '零点之左已归内容：点中窗口起点备注',
      );
    });
  });

  group('首线控制柄延入片头', () {
    Finder prefix() => find.byKey(const Key('track_prefix'));

    testWidgets('默认视图：按在片头范围内的手柄带行上横拖 = 拖首线', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.wholeVideo(total),
      );
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));
      final prefixRect = tester.getRect(prefix());
      final marker = find.byKey(const Key('video_range_start_marker'));

      // 前置：片头贴着带左缘，首线站在内容区左缘；控制柄短条以线心居中。
      expect(prefixRect.left - bandRect.left, 0);
      expect(
        tester.getCenter(marker).dx - bandRect.left,
        closeTo(bandX(0, total: 180), 1),
        reason: '首线控制柄短条仍以线心居中',
      );

      engine.seekCalls.clear();
      // 起手贴带左缘（4dp 处）——首线槽的左界已从内容区左缘顶到带左缘，
      // 片头整段都在它的触发区内。
      final gesture = await tester.startGesture(
        Offset(
          bandRect.left + 4,
          trackRowCenterY(tester, 'track_handle_strip_row'),
        ),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(76, 0));
      await gesture.up();
      await pumpSettle(tester);

      // 移动的是首线：起手 x=4 → 位移 76px → 落点 x=80 = 9.47s，按内容区宽
      // 换算并吸附就绪均匀网格（0.5s 拍点）为 9.5s。不是 seek 预览线（接管
      // 会把线拖到手指底下、首线不动），也不是空白横滑（首线不动、走累计
      // 位移微调）。
      expect(
        bandTimeline(tester).rangeStart,
        const Duration(milliseconds: 9500),
      );
      expect(
        tester.getCenter(marker).dx - bandRect.left,
        closeTo(bandX(9.5, total: 180), 1),
      );
    });

    testWidgets('首线在带中：手柄带行左侧空白横滑仍是微调（不拖首线）', (tester) async {
      const total = Duration(minutes: 3);
      final engine = FakePlaybackEngine(duration: total);
      await pumpBand(
        tester,
        engine: engine,
        timeline: AnnotationTimeline.normalized(
          videoDuration: total,
          rangeStart: const Duration(seconds: 60),
        ),
      );
      final bandRect = tester.getRect(find.byKey(const Key('track_band')));

      // 首线在 60s（内容区里 x ≈ 293.3）：向带左缘的顶满只发生在片头列那
      // 一段，它左侧的手柄带行空白仍归空白横滑。
      engine.seekCalls.clear();
      final gesture = await tester.startGesture(
        Offset(
          bandRect.left + 100,
          trackRowCenterY(tester, 'track_handle_strip_row'),
        ),
      );
      await tester.pump();
      await dragBySteps(tester, gesture, const Offset(76, 0));
      await gesture.up();
      await pumpSettle(tester);

      expect(
        bandTimeline(tester).rangeStart,
        const Duration(seconds: 60),
        reason: '首线不被拖动',
      );
      expect(
        engine.seekCalls.last,
        seekDeltaFor(76.toDouble(), 1),
        reason: '按累计位移走的空白微调',
      );
    });
  });
}

/// 吸附关闭注入模型：直接以 build 覆盖为 false。
class _PreviewSnapOffModel extends PreviewSnapModel {
  @override
  bool build() => false;
}

/// 时长未知的测试引擎（覆盖 duration getter 为 null；同 player_page_test
/// 先例）——「无时间线时整簇隐藏」用。
class _DurationlessEngine extends FakePlaybackEngine {
  _DurationlessEngine() : super(duration: const Duration(minutes: 3));

  @override
  Duration? get duration => null;
}
