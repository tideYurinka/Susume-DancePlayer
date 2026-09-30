import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatGridProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationEditorProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        selectedHalfBeatLineIndexProvider,
        selectedSegmentLineIndexProvider,
        selectedVideoRangeBoundaryProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHalfBeatLineColor, kSegmentLineSelectedColor;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/document_grid_of.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/video_index_fixtures.dart';

void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    BeatGrid? beatGrid,
  }) async {
    final resolved = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (beatGrid != null) beatGridProvider.overrideWithValue(beatGrid),
          playbackEngineProvider.overrideWithValue(engine),
          if (beatGrid == null)
            beatAnalysisPipelineProvider.overrideWithValue(
              hangingBeatPipeline,
            ),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(
                    filePath: resolved.toFilePath(),
                    mirrored: false,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: resolved)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 单击唤出控制层（等双击判定窗口过）。
  Future<void> singleTapShow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PlayerPage)));

  group('「插入半拍」工具（经「添加」菜单触达）', () {
    testWidgets('添加菜单选「半拍线」在预览位置就近吸附到最近半拍理论位置并插入半拍线', (tester) async {
      // 占位网格 120bpm：半拍位 = 250ms 倍数；预览停 10.3s → 吸附 10.25s。
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await engine.seek(const Duration(seconds: 10, milliseconds: 300));
      await engine.pause();
      await tester.pump();

      expect(find.byKey(const Key('half_beat_line_0')), findsNothing);
      await tester.tap(find.byKey(const Key('control_add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pumpAndSettle();

      final timeline = containerOf(
        tester,
      ).read(annotationTimelineProvider);
      expect(timeline.halfBeatLines, hasLength(1));
      expect(
        timeline.halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
      );
      expect(find.byKey(const Key('half_beat_line_0')), findsOneWidget);
    });

    testWidgets('锁定分段：「添加」钮正常、菜单照开；选「半拍线」照常插入、不弹锁提示', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      containerOf(tester).read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();
      await engine.seek(const Duration(seconds: 10));
      await engine.pause();
      await tester.pump();

      await tester.tap(find.byKey(const Key('control_add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_half_beat')));
      await tester.pumpAndSettle();

      expect(find.text('已锁定分段'), findsNothing);
      expect(
        containerOf(tester).read(annotationTimelineProvider).halfBeatLines,
        hasLength(1),
      );
      expect(find.byKey(const Key('half_beat_line_0')), findsOneWidget);
    });
  });

  group('半拍线拖动精调（松手强制吸附）', () {
    testWidgets('命中列水平拖动、松手吸到最近半拍格点；锁定时提示且不动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 15));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      final container = containerOf(tester);
      // 以带半拍线的时间线为起点（插入路径已在工具用例覆盖）。
      container
          .read(annotationEditorProvider)
          .submit(const AddHalfBeatLine(at: Duration(seconds: 10)));
      await tester.pumpAndSettle();

      // 窗口 15s（密度护栏下的疏档窗口）：带宽 800px → 80px
      // ≈ 1.5s；10s → 11.5s，拍点 12s 两侧等距取靠后 → 吸附 11.75s。
      final hit = find.byKey(const Key('half_beat_line_hit_0'));
      expect(hit, findsOneWidget);
      // 两段式按下即拖（与既有拖线同法）：第一段越过触摸 slop 触发
      // drag start，第二段作为 update 事件落位。
      final gesture = await tester.startGesture(tester.getCenter(hit));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      var after = container.read(annotationTimelineProvider);
      expect(
        after.halfBeatLines.single.position,
        const Duration(seconds: 11, milliseconds: 750),
      );

      // 锁定后拖动：半拍线不受锁，照常改位置、不弹锁提示。
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();
      final hit2 = find.byKey(const Key('half_beat_line_hit_0'));
      final gesture2 = await tester.startGesture(tester.getCenter(hit2));
      await gesture2.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture2.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture2.up();
      await tester.pumpAndSettle();

      after = container.read(annotationTimelineProvider);
      expect(
        after.halfBeatLines.single.position,
        isNot(const Duration(seconds: 11, milliseconds: 750)),
        reason: '锁定分段不挡半拍线拖动',
      );
      expect(find.text('已锁定分段'), findsNothing);
    });
  });

  group('半拍线命中列层序', () {
    /// 两段式按下即拖（既有手法）：第一段越过触摸 slop 触发 drag start，
    /// 第二段作为 update 事件落位。
    Future<void> pressAndDrag(
      WidgetTester tester,
      Offset start,
      double dx,
    ) async {
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// 播种一根 10.25s 半拍线 + 同位分段线，展开控制层并暂停。
    Future<ProviderContainer> pumpSamePositionLines(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
    }) async {
      await pumpPlayer(tester, engine: engine);
      final container = containerOf(tester);
      container
          .read(annotationEditorProvider)
          .submit(const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)));
      container
          .read(annotationEditorProvider)
          .submit(const AddSegmentLine(at: Duration(seconds: 10, milliseconds: 250)));
      await singleTapShow(tester);
      await engine.pause();
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('半拍线与分段线同位：节拍轨行横拖动的是半拍线，分段线与进度不动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 15));
      final container = await pumpSamePositionLines(tester, engine: engine);
      final positionBefore = engine.position;

      // 起手点 = 节拍轨行内半拍线线心（两段式按下即拖，既有手法）。
      final startX = tester.getCenter(
        find.byKey(const Key('half_beat_line_hit_0')),
      ).dx;
      final startY = trackRowCenterY(tester, 'track_beat');
      await pressAndDrag(tester, Offset(startX, startY), 40);

      final after = container.read(annotationTimelineProvider);
      expect(
        after.halfBeatLines.single.position,
        isNot(const Duration(seconds: 10, milliseconds: 250)),
        reason: '同位时节拍轨行横拖归半拍线',
      );
      expect(
        after.segmentLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
        reason: '同位时分段线不动',
      );
      expect(engine.position, positionBefore, reason: '播放进度不变');
    });

    testWidgets('同位时其它入口照常：学习段轨行点选分段线、手柄带控制柄拖动分段线', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpSamePositionLines(tester, engine: engine);
      final lineX = tester.getCenter(
        find.byKey(const Key('half_beat_line_hit_0')),
      ).dx;

      // 学习段轨行点选那条分段线（半拍线命中列只占节拍轨行，不越行）。
      await tester.tapAt(Offset(lineX, trackRowCenterY(tester, 'track_learning')));
      await tester.pumpAndSettle();
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      // 手柄带控制柄拖动分段线：位置变、半拍线不动。
      final handle = find.byKey(const Key('segment_line_0_handle'));
      await pressAndDrag(tester, tester.getCenter(handle), 40);

      final after = container.read(annotationTimelineProvider);
      expect(
        after.segmentLines.single.position,
        isNot(const Duration(seconds: 10, milliseconds: 250)),
        reason: '分段线仍可经控制柄拖动',
      );
      expect(
        after.halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
      );
    });

    testWidgets('半拍线命中列与首尾线命中列重叠：节拍轨行横拖动的是半拍线；首尾线仍可在手柄带抓取与点选', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 15));
      await pumpPlayer(tester, engine: engine);
      final container = containerOf(tester);
      container
          .read(annotationEditorProvider)
          .submit(const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)));
      container
          .read(annotationEditorProvider)
          .submit(
            const SetVideoRange(
              // 首线在半拍线旁 0.25s（列宽 40dp 内重叠）；半拍线须严格
              // 位于 (rangeStart, rangeEnd) 内，不能与首线严格同位。
              start: Duration(seconds: 10),
              end: Duration(seconds: 20),
            ),
          );
      await singleTapShow(tester);
      await engine.pause();
      await tester.pumpAndSettle();

      final startX = tester.getCenter(
        find.byKey(const Key('half_beat_line_hit_0')),
      ).dx;
      final startY = trackRowCenterY(tester, 'track_beat');
      await pressAndDrag(tester, Offset(startX, startY), 40);

      final afterDrag = container.read(annotationTimelineProvider);
      expect(
        afterDrag.halfBeatLines.single.position,
        isNot(const Duration(seconds: 10, milliseconds: 250)),
        reason: '列重叠时节拍轨行横拖归半拍线',
      );
      expect(afterDrag.rangeStart, const Duration(seconds: 10), reason: '首线不动');

      // 首线仍可在手柄带经控制柄点选与抓取拖动。
      await tester.tap(find.byKey(const Key('video_range_start_marker')));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedVideoRangeBoundaryProvider),
        VideoRangeBoundary.start,
        reason: '首线仍可在手柄带点选',
      );

      final handle = find.byKey(const Key('video_range_start_marker'));
      await pressAndDrag(tester, tester.getCenter(handle), 40);

      expect(
        container.read(annotationTimelineProvider).rangeStart,
        isNot(const Duration(seconds: 10)),
        reason: '首线仍可在手柄带抓取',
      );
    });

    testWidgets('播放头压线：线心重合处按下横拖归播放头（进度动、半拍线不动）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpSamePositionLines(tester, engine: engine);
      await engine.seek(const Duration(seconds: 10, milliseconds: 250));
      await tester.pumpAndSettle();
      final positionBefore = engine.position;

      // 按下点 = 播放头竖条与半拍线线心重合处（节拍轨行内）。
      final startX = tester.getCenter(find.byKey(const Key('preview_line'))).dx;
      final startY = trackRowCenterY(tester, 'track_beat');
      await pressAndDrag(tester, Offset(startX, startY), 40);

      expect(
        engine.position,
        isNot(positionBefore),
        reason: '重合 2dp 内拖动仍归播放头（拖进度）',
      );
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
        reason: '半拍线不动',
      );
    });

    testWidgets('落点偏出命中列（线心 20dp 外）：节拍轨行横拖仍是进度拖动、线不动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpSamePositionLines(tester, engine: engine);
      final positionBefore = engine.position;

      // 命中列 = 线心两侧各 20dp；线心 +30dp 起手在列外。
      final startX =
          tester.getCenter(find.byKey(const Key('half_beat_line_hit_0'))).dx +
          30;
      final startY = trackRowCenterY(tester, 'track_beat');
      await pressAndDrag(tester, Offset(startX, startY), 40);

      expect(engine.position, isNot(positionBefore), reason: '进度拖动照常');
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
        reason: '半拍线不动',
      );
    });
  });

  group('半拍线点选与上一帧/下一帧（编辑闭环）', () {
    /// 播种一根 10.25s（半拍格点上）的半拍线并展开控制层。
    Future<ProviderContainer> pumpWithHalfBeatLine(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
    }) async {
      await pumpPlayer(tester, engine: engine);
      final container = containerOf(tester);
      container
          .read(annotationEditorProvider)
          .submit(const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)));
      await singleTapShow(tester);
      await engine.pause();
      await tester.pumpAndSettle();
      return container;
    }

    Color halfBeatColor(WidgetTester tester) => tester
        .widget<ColoredBox>(find.byKey(const Key('half_beat_line_0')))
        .color;

    testWidgets('节拍轨行内单击选中（主青高亮）、再点取消', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
      expect(halfBeatColor(tester), kHalfBeatLineColor);

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
      expect(
        halfBeatColor(tester),
        kSegmentLineSelectedColor,
        reason: '选中视觉 = 主青高亮',
      );

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
      expect(halfBeatColor(tester), kHalfBeatLineColor);
    });

    testWidgets('与分段线选中互斥；其它操作（播放控制）清除选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      container
          .read(annotationEditorProvider)
          .submit(const AddSegmentLine(at: Duration(seconds: 12)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('segment_line_0_handle')));
      await tester.pumpAndSettle();
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
      expect(container.read(selectedSegmentLineIndexProvider), isNull);

      // 其它操作即清除：播放/暂停控制不针对选中线。
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });

    testWidgets('下一帧跳相邻半拍格点（10.25s → 10.75s）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 750),
      );

      await tester.tap(find.byKey(const Key('toolbar_frame_step_back')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
      );

      // 跳步入撤销。
      container.read(annotationEditorProvider).undo();
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 750),
      );
    });

    testWidgets('锁定分段：选中半拍线后步进照常（半拍线不受锁）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pump();

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();

      expect(find.text('已锁定分段'), findsNothing);
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 750),
      );
    });

    testWidgets('命中列仅限节拍轨行：学习段行/手柄带行同 x 点按不选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      final hitCenter = tester.getCenter(
        find.byKey(const Key('half_beat_line_hit_0')),
      );

      // 局部镜像行（带顶一行，实际落点）与手柄带行（带底一行）同 x 点按
      // 均不在节拍轨行命中列内。
      await tester.tapAt(
        Offset(hitCenter.dx, trackRowCenterY(tester, 'track_mirror')),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        Offset(hitCenter.dx, trackRowCenterY(tester, 'track_handle_strip_row')),
      );
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });
  });

  group('半拍线随 markers 公开侧落盘往返', () {
    testWidgets('打开恢复：markers 文档中的半拍线还原进时间线', (tester) async {
      // 模型层往返已在 marker_document / 编辑器 diff 用例覆盖；此处断言
      // 时间线归一化对文档值的相容（升序/去重后的文档值原样入时间线）。
      const doc = marker_doc.MarkersDocument(
        rangeStartMs: 0,
        rangeEndMs: 30000,
        halfBeatLines: [
          HalfBeatLine(position: Duration(milliseconds: 2500)),
        ],
      );
      final timeline = AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 30),
        rangeStart: Duration(milliseconds: doc.rangeStartMs),
        rangeEnd: Duration(milliseconds: doc.rangeEndMs),
        segmentLines: doc.segmentLines,
        halfBeatLines: doc.halfBeatLines,
      );
      expect(timeline.halfBeatLines, [
        const HalfBeatLine(position: Duration(milliseconds: 2500)),
      ]);
    });
  });

  group('半拍线删除', () {
    /// 播种一根 10.25s 的半拍线并展开控制层（复用点选组搭法）。
    Future<ProviderContainer> pumpWithHalfBeatLine(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
    }) async {
      await pumpPlayer(tester, engine: engine);
      final container = containerOf(tester);
      container
          .read(annotationEditorProvider)
          .submit(const AddHalfBeatLine(at: Duration(seconds: 10, milliseconds: 250)));
      await singleTapShow(tester);
      await engine.pause();
      await tester.pumpAndSettle();
      return container;
    }

    bool deleteSlotEnabled(WidgetTester tester) =>
        tester
            .widget<InkWell>(
              find
                  .descendant(
                    of: find.byKey(const Key('control_segment_delete')),
                    matching: find.byType(InkWell),
                  )
                  .first,
            )
            .onTap !=
        null;

    testWidgets('选中半拍线后删除槽启用；点按即删无确认框且清选中', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      expect(find.byKey(const Key('control_segment_delete')), findsOneWidget);
      expect(deleteSlotEnabled(tester), isTrue,
          reason: '无作用对象 → 置灰但按得动（弹做法）');

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
      expect(deleteSlotEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('half_beat_line_0')), findsNothing);
      expect(container.read(annotationTimelineProvider).halfBeatLines, isEmpty);
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
      expect(
        find.byKey(const Key('layout_lock_prompt')),
        findsNothing,
        reason: '未锁定时无锁定提示；点按即删，无确认框',
      );
    });

    testWidgets('锁定分段：选中半拍线时删除槽照常启用、单击即删（锁只护分段线）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      final container = await pumpWithHalfBeatLine(tester, engine: engine);
      container.read(layoutLockedProvider.notifier).replace(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
      expect(deleteSlotEnabled(tester), isTrue);

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('half_beat_line_0')), findsNothing,
          reason: '半拍线删除不受锁定分段');
      expect(find.byKey(const Key('layout_lock_prompt')), findsNothing);
    });
  });

  group('密度护栏：太密时半拍线不注册拖动、横拖归进度', () {
    /// 两段式按下即拖（既有手法）：第一段越过触摸 slop 触发 drag start，
    /// 第二段作为 update 事件落位。
    Future<void> pressAndDrag(
      WidgetTester tester,
      Offset start,
      double dx,
    ) async {
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      await gesture.moveBy(Offset(dx / 2, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// 播种一根 10.25s 半拍线、展开控制层并暂停。默认 150s 全宽窗口下
    /// 占位/兜底网格（拍长 0.5s）的半拍格点屏上间距约 1.3dp，低于 3dp 下限；
    /// 带宽 800px → 150s，半拍 0.25s ≈ 1.3px。
    Future<ProviderContainer> pumpDense(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
      BeatGrid? beatGrid,
    }) async {
      await pumpPlayer(tester, engine: engine, beatGrid: beatGrid);
      final container = containerOf(tester);
      container
          .read(annotationEditorProvider)
          .submit(
            const AddHalfBeatLine(
              at: Duration(seconds: 10, milliseconds: 250),
            ),
          );
      await singleTapShow(tester);
      await engine.pause();
      await tester.pumpAndSettle();
      return container;
    }

    Offset beatRowHitCenter(WidgetTester tester) => Offset(
      tester.getCenter(find.byKey(const Key('half_beat_line_hit_0'))).dx,
      trackRowCenterY(tester, 'track_beat'),
    );

    testWidgets('间距 < 3dp：横拖不改半拍线位置、进度照常被拖动（占位网格）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 150));
      final container = await pumpDense(tester, engine: engine);
      final positionBefore = engine.position;

      await pressAndDrag(tester, beatRowHitCenter(tester), 40);

      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
        reason: '太密时横拖不挪半拍线',
      );
      expect(engine.position, isNot(positionBefore), reason: '进度照常被拖动');
    });

    testWidgets('间距 < 3dp（秒制兜底网格）：同样横拖归进度、半拍线不动', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 150));
      final container = await pumpDense(
        tester,
        engine: engine,
        beatGrid: const UnavailableBeatGrid(),
      );
      final positionBefore = engine.position;

      await pressAndDrag(tester, beatRowHitCenter(tester), 40);

      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
      );
      expect(engine.position, isNot(positionBefore));
    });

    testWidgets('间距 ≥ 3dp（15s 窗口对照档）：横拖改线位置', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 15));
      final container = await pumpDense(tester, engine: engine);

      await pressAndDrag(tester, beatRowHitCenter(tester), 40);

      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        isNot(const Duration(seconds: 10, milliseconds: 250)),
        reason: '够疏时横拖照常挪半拍线',
      );
    });

    testWidgets('太密时点按仍能选中、再点取消', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 150));
      final container = await pumpDense(tester, engine: engine);

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);

      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), isNull);
    });

    testWidgets('太密时选中后仍能删除、能步进且播放头定格到新位置', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 150));
      final container = await pumpDense(tester, engine: engine);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toolbar_frame_step_forward')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '太密时步进照常按相邻半拍格点挪',
      );
      expect(
        engine.position,
        const Duration(seconds: 10, milliseconds: 750),
        reason: '步进后播放头定格到新位置',
      );

      await tester.tap(find.byKey(const Key('control_segment_delete')));
      await tester.pumpAndSettle();
      expect(
        container.read(annotationTimelineProvider).halfBeatLines,
        isEmpty,
        reason: '太密时删除照常',
      );
    });

    testWidgets('真实网格弱起区间（早于首拍）的半拍线照常渲染与点选，不因取间距抛错', (tester) async {
      // 网格首拍在 5s；线落 2s（弱起区间，beatIndexAt = -1）。
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 15));
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 14),
          beats: [
            for (var i = 0; i < 20; i++)
              marker_doc.BeatPoint(
                t: (5000 + i * 500) / 1000,
                down: i % 4 == 0,
              ),
          ],
        ),
      );
      final container = await pumpDense(tester, engine: engine, beatGrid: grid);

      expect(find.byKey(const Key('half_beat_line_hit_0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('half_beat_line_hit_0')));
      await tester.pumpAndSettle();
      expect(container.read(selectedHalfBeatLineIndexProvider), 0);
    });

    testWidgets('放大到间距 ≥ 3dp 后（缩放滑条）：同一根线横拖恢复改线位置', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 150));
      final container = await pumpDense(tester, engine: engine);

      // 前置：太密时横拖不动。
      await pressAndDrag(tester, beatRowHitCenter(tester), 40);
      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        const Duration(seconds: 10, milliseconds: 250),
      );

      // 回到线附近再经缩放滑条放大（150s 下最大倍率 30，滑条中点 ≈ 倍率
      // √30 ≈ 5.5 → 间距约 7.3dp ≥ 3dp），以播放头（线位）为锚缩放后线保持可见。
      await engine.seek(const Duration(seconds: 10, milliseconds: 250));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('track_zoom_slider')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      // 播放头挪离线位（播放头压线处按下横拖归播放头，语义）。
      await engine.seek(const Duration(seconds: 12));
      await tester.pumpAndSettle();

      await pressAndDrag(tester, beatRowHitCenter(tester), 40);

      expect(
        container.read(annotationTimelineProvider).halfBeatLines.single.position,
        isNot(const Duration(seconds: 10, milliseconds: 250)),
        reason: '放大到够疏后同一根线横拖恢复挪线',
      );
    });
  });
}
