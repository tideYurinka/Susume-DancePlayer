import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/beat/beat_pipeline.dart'
    show BeatAnalysisPipeline;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatPhaseProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationEditorProvider, layoutLockedProvider;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/beat_correction.dart'
    show beatCorrectionAvailableProvider;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show overlayPlacementProvider;
import 'package:dance_learning_app/player/overlay.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/preview_snap.dart'
    show previewSnapEnabledProvider;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 八拍矫正待命态与锚点视觉：
///
/// - 入口：气泡第三列「八拍矫正」按下 → 关气泡 + 进控制层 + 待命态；
///   仅真实网格就绪可用（占位/异常置灰）；观看态同一气泡按钮不置灰不隐藏。
/// - 待命态：工具槽整排换装（原标注工具全不显示）；「设为八拍线」在预览
///   位置已有锚点时**置灰且不可点**（视觉与命中同一谓词）；退出/收起控制层
///   后工具槽恢复原样；网格无强拍（识别退化）时入口置灰（无合法落点）。
/// - 预览线恒定吸附最近强拍（不受「预览吸附」开关影响）。
/// - 锚点视觉：第二色大线 + 轨顶小标记；大线因锚点升/降级不弹额外提示。
///
/// 待命态「取消八拍线」/「清除所有八拍线」两组（互斥置灰、点击即原子写、
/// 当帧刷新、单步可撤销、锁门禁）与入口退出完整化（观看态角标入口、
/// 四条退出路径）。

void main() {
  /// 某标注工具槽内的文案（轨道片头标签与槽文案同字，如「分段」，
  /// 断言按槽键圈定，不被带内标签命中）。
  Finder slotText(Key slot, String text) =>
      find.descendant(of: find.byKey(slot), matching: find.text(text));
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    bool readyBeat = true,
    List<int> anchors = const [],
    BeatAnalysisPipeline? beatPipeline,
  }) async {
    final resolved = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(
            beatPipeline ?? hangingBeatPipeline,
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
    // 节拍动画总开关默认关——本组用例针对观看态角标与浮层
    // 机制，先置开。
    turnBeatAnimationOn(tester);
    await tester.pump();
    if (readyBeat) {
      final seconds =
          (engine.duration ?? const Duration(seconds: 60)).inMilliseconds /
          1000;
      await injectBeatState(
        tester,
        uniformDownbeatBeatState(seconds: seconds, anchors: anchors),
      );
    }
  }

  Future<void> singleTapShow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  List<int> anchorsOf(WidgetTester tester) =>
      containerOf(tester).read(beatTrackStateProvider).grid?.anchors ??
      const [];

  /// 打开节拍提示气泡（编辑态顶栏工具）。
  Future<void> openBeatPromptBubble(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tool_beat_prompt')));
    await tester.pumpAndSettle();
  }

  /// 进入待命态（唤出控制层 → 气泡第三列「八拍矫正」）：控制层已展开时
  /// 不再点画面（避免把展开态收起来）。
  Future<void> enterStandby(WidgetTester tester) async {
    if (find.byKey(const Key('control_layer')).evaluate().isEmpty) {
      await singleTapShow(tester);
    }
    if (find.byKey(const Key('beat_prompt_panel')).evaluate().isEmpty) {
      await openBeatPromptBubble(tester);
    }
    await tester.tap(
      find.byKey(const Key('beat_correction_eight_beat_button')),
    );
    await tester.pumpAndSettle();
  }

  OutlinedButton eightBeatButton(WidgetTester tester) =>
      tester.widget<OutlinedButton>(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );

  /// 槽位图标色（置灰 = 白 38 —— 与既有标注工具同一套置灰外观）。
  Color slotIconColor(WidgetTester tester, String slotKey) => tester
      .widget<Icon>(
        find
            .descendant(
              of: find.byKey(Key(slotKey)),
              matching: find.byType(Icon),
            )
            .first,
      )
      .color!;

  bool slotEnabled(WidgetTester tester, String slotKey) =>
      tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byKey(Key(slotKey)),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .onTap !=
      null;

  group('入口：气泡第三列「八拍矫正」', () {
    testWidgets('就绪网格：按钮可点（不再置灰、无「待支持」），按下关气泡 + 进待命态', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);
      await openBeatPromptBubble(tester);

      expect(
        find.byKey(const Key('beat_correction_eight_beat_pending')),
        findsNothing,
        reason: '不再是待支持占位',
      );
      expect(eightBeatButton(tester).onPressed, isNotNull);

      await tester.tap(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('beat_prompt_panel')),
        findsNothing,
        reason: '按下即关闭节拍提示气泡',
      );
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isTrue,
        reason: '进入待命态',
      );
      expect(find.byKey(const Key('control_beat_anchor_add')), findsOneWidget);
      expect(
        find.byKey(const Key('control_beat_correction_exit')),
        findsOneWidget,
      );
    });

    testWidgets('占位/异常网格：按钮置灰（真实网格就绪才可用）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      await singleTapShow(tester);
      await openBeatPromptBubble(tester);

      expect(eightBeatButton(tester).onPressed, isNull, reason: '占位态置灰');

      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pumpAndSettle();
      expect(eightBeatButton(tester).onPressed, isNull, reason: '异常态置灰');
    });

    testWidgets('观看态同一气泡：按钮不置灰不隐藏', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      // 观看态：不唤出控制层，直接打开气泡（与浮层角标同一组件）。
      containerOf(tester)
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.beat);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(eightBeatButton(tester).onPressed, isNotNull);

      // 按下同样自动进控制层 + 关气泡 + 进待命态。观看态气泡
      // 与浮层/手势层同屏，测试视口下按钮命中点被上层浮层遮挡（真机由角标
      // 入口驱动，归既有入口套件），此处直调按钮回调以钉住同一条
      // 接线（回调本身即生产接线）。
      eightBeatButton(tester).onPressed!();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(find.byKey(const Key('control_beat_anchor_add')), findsOneWidget);
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isTrue,
      );
    });
  });

  group('待命态工具槽整排换装', () {
    testWidgets('原标注工具全部不显示；退出后恢复原样', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await enterStandby(tester);

      for (final entry in const [
        (Key('control_segment'), '分段'),
        (Key('control_add'), '添加'),
        (Key('control_auto_range'), '自动分段'),
      ]) {
        expect(
          slotText(entry.$1, entry.$2),
          findsNothing,
          reason: '待命态不显示「${entry.$2}」',
        );
      }
      expect(find.byKey(const Key('control_segment_delete')), findsNothing);
      expect(find.byKey(const Key('control_mastery')), findsNothing);
      expect(find.text('设为八拍线'), findsOneWidget);
      expect(find.text('退出八拍矫正'), findsOneWidget);

      await tester.tap(find.byKey(const Key('control_beat_correction_exit')));
      await tester.pumpAndSettle();

      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isFalse,
      );
      expect(find.byKey(const Key('control_beat_anchor_add')), findsNothing);
      expect(slotText(const Key('control_segment'), '分段'), findsOneWidget);
      expect(slotText(const Key('control_auto_range'), '自动分段'), findsOneWidget);
    });

    testWidgets('收起控制层即结束待命态（锚点不丢），再展开工具槽原样', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28]);
      await enterStandby(tester);
      expect(find.byKey(const Key('control_beat_anchor_add')), findsOneWidget);

      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();

      expect(find.byKey(const Key('control_layer')), findsNothing);
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isFalse,
      );
      expect(anchorsOf(tester), [28], reason: '退出待命态锚点不丢');
    });
  });

  group('落锚与互斥置灰', () {
    testWidgets('点「设为八拍线」落锚：写定该强拍、当帧变灰（预览位置已有锚点）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await enterStandby(tester);

      // 预览位置落在非强拍 13.5s（最近强拍 14s = 第 8 个强拍）。
      await engine.seek(const Duration(milliseconds: 13500));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_beat_anchor_add'), isTrue);

      await tester.tap(find.byKey(const Key('control_beat_anchor_add')));
      await tester.pumpAndSettle();

      expect(anchorsOf(tester), [28], reason: '13.5s 就近强拍 = 14s');
      expect(
        slotEnabled(tester, 'control_beat_anchor_add'),
        isFalse,
        reason: '预览位置已是锚点 → 添加不可点（互斥置灰）',
      );
      expect(
        slotIconColor(tester, 'control_beat_anchor_add'),
        Colors.white38,
        reason: '且外观置灰（与「分段」「删除」同一套置灰视觉）',
      );

      // 挪回无锚点位置 → 恢复可点、外观恢复常态。
      await engine.seek(const Duration(milliseconds: 8500));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_beat_anchor_add'), isTrue);
      expect(
        slotIconColor(tester, 'control_beat_anchor_add'),
        isNot(Colors.white38),
      );
    });

    testWidgets('就绪但网格无强拍（识别退化）：入口置灰、无落锚工具', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(
            BeatTrackState.ready(
              // 就绪但**无强拍**（识别退化）：全部拍点非强拍。
              marker_doc.BeatGrid(
                model: 'fake.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2024),
                beats: const [
                  marker_doc.BeatPoint(t: 0.5, down: false),
                  marker_doc.BeatPoint(t: 1.0, down: false),
                ],
              ),
            ),
          );
      await tester.pumpAndSettle();

      expect(
        containerOf(tester).read(beatCorrectionAvailableProvider),
        isFalse,
        reason: '无强拍即无合法落点',
      );
      await singleTapShow(tester);
      await openBeatPromptBubble(tester);
      expect(eightBeatButton(tester).onPressed, isNull, reason: '入口置灰：修正无意义');
    });

    testWidgets('锁定分段：落锚照常（八拍锚点不受锁，不弹提示）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await enterStandby(tester);

      await engine.seek(const Duration(milliseconds: 13500));
      await tester.pumpAndSettle();
      containerOf(tester).read(layoutLockedProvider.notifier).replace(true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('control_beat_anchor_add')));
      await tester.pumpAndSettle();

      expect(anchorsOf(tester), [28], reason: '八拍锚点不受锁定分段');
      expect(find.text('已锁定分段'), findsNothing);
    });

    testWidgets('非就绪网格（占位）：待命入口不可用，落锚无从进入', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, readyBeat: false);
      await singleTapShow(tester);

      expect(
        containerOf(tester).read(beatCorrectionAvailableProvider),
        isFalse,
      );
      expect(find.byKey(const Key('control_beat_anchor_add')), findsNothing);
    });
  });

  group('预览线恒定吸附最近强拍（待命态硬约束）', () {
    testWidgets('「预览吸附」开关关闭时仍吸附最近强拍；常态不吸附', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 带内空白横滑 = 精细调整（不经吸附解析）；吸附语义经
      // 预览线命中列接管路径（手柄带）验证。
      containerOf(tester)
          .read(previewSnapEnabledProvider.notifier)
          .replace(false);

      // 预览线 seek 到 x=100（内容区宽换算），从其命中列
      //（手柄带）起手拖动。
      Future<TestGesture> columnDrag() async {
        await engine.seek(
          bandTimeAt(100, total: const Duration(minutes: 3), width: 800),
        );
        await tester.pumpAndSettle();
        final y = tester
            .getCenter(find.byKey(const Key('track_handle_strip_row')))
            .dy;
        return tester.startGesture(Offset(100, y));
      }

      // 常态：开关关 + 无分段线 → 拖动落点为手指位置（未吸附）。
      var g = await columnDrag();
      await tester.pump();
      await g.moveBy(const Offset(160, 0)); // 越过 slop，锁定+立即 seek
      await tester.pump();
      await g.moveBy(const Offset(160, 0)); // 手指落在 90s 处，无吸附
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      expect(
        engine.seekCalls.last,
        const Duration(milliseconds: 90000),
        reason: '常态无吸附目标 → 帧级落点',
      );

      // 待命态：恒定吸最近强拍（强拍每 2s）。
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.beatCorrectionStandby);
      await tester.pump();
      g = await columnDrag();
      await tester.pump();
      engine.seekCalls.clear(); // 清掉预定位 seek，只考察拖动落点
      await g.moveBy(const Offset(160, 0)); // 中途停点 → 吸最近强拍
      await tester.pump();
      await g.moveBy(const Offset(160, 0)); // 手指落在 90s 处 → 吸 90s
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();

      expect(engine.seekCalls, isNotEmpty);
      for (final target in engine.seekCalls) {
        expect(target.inMilliseconds % 2000, 0, reason: '待命态落点恒为强拍：$target');
      }
      expect(engine.seekCalls.last, const Duration(seconds: 90));
    });
  });

  group('锚点视觉（仅待命态出现）', () {
    testWidgets('非待命态完全不画锚点：无第二色大线、无轨顶圆点（与无锚点渲染一致）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28]);
      await singleTapShow(tester);

      // 无轨顶小标记；锚点刻度与自动大线同为白色系。
      expect(
        find.byKey(const ValueKey('beat_anchor_marker_14000000')),
        findsNothing,
      );
      final tick = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const ValueKey('beat_tick_14000000')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(tick.color, isNot(kBeatAnchorLineColor));
      expect(tick.color.a, greaterThan(0.0));
    });

    testWidgets('待命态：第二色大线 + 轨顶小标记；白色自动大线照旧；不弹额外提示', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28]);
      await enterStandby(tester);

      // 锚点 14s（拍序号 28）：轨顶小标记 + 该刻度为第二色。
      expect(
        find.byKey(const ValueKey('beat_anchor_marker_14000000')),
        findsOneWidget,
      );
      final anchorTick = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const ValueKey('beat_tick_14000000')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(anchorTick.color, kBeatAnchorLineColor);

      // 自动大线（0s / 4s）仍为白色系（可区分）。
      final autoTick = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byKey(const ValueKey('beat_tick_0')),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(autoTick.color, isNot(kBeatAnchorLineColor));
      expect(autoTick.color.a, greaterThan(0.0));

      // 大线因锚点升/降级不弹额外提示（无任何浮层提示）。
      expect(find.text('已锁定分段'), findsNothing);
    });
  });

  group('待命态工具槽：删除八拍线与清除所有锚点', () {
    testWidgets('四槽换装：无锚点时「取消八拍线」「清除所有八拍线」均置灰且不可点', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await enterStandby(tester);

      expect(find.byKey(const Key('control_beat_anchor_add')), findsOneWidget);
      expect(find.text('取消八拍线'), findsOneWidget);
      expect(find.text('清除所有八拍线'), findsOneWidget);
      expect(
        find.byKey(const Key('control_beat_correction_exit')),
        findsOneWidget,
      );
      expect(slotEnabled(tester, 'control_beat_anchor_remove'), isFalse);
      expect(
        slotIconColor(tester, 'control_beat_anchor_remove'),
        Colors.white38,
      );
      expect(slotEnabled(tester, 'control_beat_anchors_clear'), isFalse);
      expect(
        slotIconColor(tester, 'control_beat_anchors_clear'),
        Colors.white38,
      );
    });

    testWidgets('互斥置灰：预览位置无锚点 → 添加可点/删除置灰；已有锚点 → 反之', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28]);
      await enterStandby(tester);

      // 预览位置 13.5s 就近强拍 14s = 锚点 28（已有锚点）。
      await engine.seek(const Duration(milliseconds: 13500));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_beat_anchor_add'), isFalse);
      expect(
        slotEnabled(tester, 'control_beat_anchor_remove'),
        isTrue,
        reason: '预览位置有锚点 → 删除可点',
      );
      expect(
        slotIconColor(tester, 'control_beat_anchor_remove'),
        isNot(Colors.white38),
      );

      // 挪到无锚点的强拍 8s（拍序号 16）：谓词翻转，两槽互斥。
      await engine.seek(const Duration(milliseconds: 8000));
      await tester.pumpAndSettle();
      expect(slotEnabled(tester, 'control_beat_anchor_add'), isTrue);
      expect(slotEnabled(tester, 'control_beat_anchor_remove'), isFalse);
      expect(
        slotIconColor(tester, 'control_beat_anchor_remove'),
        Colors.white38,
      );
    });

    testWidgets('点「取消八拍线」：删掉预览位置锚点 + 当帧刷新派生面 + 单步可撤销', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28]);
      await enterStandby(tester);
      expect(
        find.byKey(const ValueKey('beat_anchor_marker_14000000')),
        findsOneWidget,
      );

      await engine.seek(const Duration(milliseconds: 13500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_beat_anchor_remove')));
      await tester.pumpAndSettle();

      expect(anchorsOf(tester), isEmpty, reason: '该锚点被删掉');
      expect(
        find.byKey(const ValueKey('beat_anchor_marker_14000000')),
        findsNothing,
        reason: '当帧刷新轨道锚点视觉',
      );
      expect(
        [
          for (final t
              in containerOf(tester)
                  .read(beatPhaseProvider)
                  .pointsInWindow(Duration.zero, const Duration(seconds: 20)))
            t.inMilliseconds,
        ],
        [0, 4000, 8000, 12000, 16000, 20000],
        reason: '相位源当帧回到无锚点口径（派生面逐位可观察）',
      );
      expect(
        slotEnabled(tester, 'control_beat_anchor_add'),
        isTrue,
        reason: '删后预览位置无锚点 → 添加恢复可点（同一谓词）',
      );

      containerOf(tester).read(annotationEditorProvider).undo();
      await tester.pumpAndSettle();
      expect(anchorsOf(tester), [28], reason: '一次删除 = 单步可撤销');
    });

    testWidgets('「清除所有八拍线」：多锚点下一次点击清空 + 当帧刷新 + 单步可撤销', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      await enterStandby(tester);
      // 经 UI 落两个锚点（各自一次标注编辑，留在历史里供撤销）。
      await engine.seek(const Duration(milliseconds: 13500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_beat_anchor_add')));
      await tester.pumpAndSettle();
      await engine.seek(const Duration(milliseconds: 20000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('control_beat_anchor_add')));
      await tester.pumpAndSettle();
      expect(anchorsOf(tester), [28, 40]);
      expect(slotEnabled(tester, 'control_beat_anchors_clear'), isTrue);

      await tester.tap(find.byKey(const Key('control_beat_anchors_clear')));
      await tester.pumpAndSettle();

      expect(anchorsOf(tester), isEmpty);
      expect(
        find.byKey(const ValueKey('beat_anchor_marker_14000000')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('beat_anchor_marker_20000000')),
        findsNothing,
      );
      expect(
        slotEnabled(tester, 'control_beat_anchors_clear'),
        isFalse,
        reason: '清空后无锚点 → 本槽当帧置灰',
      );

      containerOf(tester).read(annotationEditorProvider).undo();
      await tester.pumpAndSettle();
      expect(anchorsOf(tester), [28, 40], reason: '一次清空 = 单步可撤销');
    });

    testWidgets('锁定分段：删除/清空照常（八拍锚点不受锁，不弹提示）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28, 40]);
      await enterStandby(tester);
      await engine.seek(const Duration(milliseconds: 13500));
      await tester.pumpAndSettle();
      containerOf(tester).read(layoutLockedProvider.notifier).replace(true);
      await tester.pumpAndSettle();
      final promptBefore = containerOf(tester)
          .read(noticeTriggerProvider(NoticeId.layoutLock));

      await tester.tap(find.byKey(const Key('control_beat_anchor_remove')));
      await tester.pumpAndSettle();
      expect(anchorsOf(tester), [40], reason: '锁定分段下删除照常');
      expect(
        containerOf(tester).read(noticeTriggerProvider(NoticeId.layoutLock)),
        promptBefore,
        reason: '八拍锚点不受锁，不弹提示',
      );

      await tester.tap(find.byKey(const Key('control_beat_anchors_clear')));
      await tester.pumpAndSettle();
      expect(anchorsOf(tester), isEmpty, reason: '锁定分段下清空照常');
      expect(
        containerOf(tester).read(noticeTriggerProvider(NoticeId.layoutLock)),
        promptBefore,
      );
    });
  });

  group('入口退出完整化（验收）', () {
    testWidgets('观看态角标 → 同一气泡（「八拍矫正」不置灰不隐藏）→ 按下自动进控制层 + 关气泡 + 待命态', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine);
      expect(
        find.byKey(const Key('control_layer')),
        findsNothing,
        reason: '观看态',
      );

      // 浮层先挪到视口中部：角标锚出的气泡在测试视口下不被顶栏遮挡
      // （真机默认位不受影响，气泡宿主自带屏内钳位）。测试视口 800×600
      // 为横屏，写入横屏·普通格。
      containerOf(tester)
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {OverlayPlacementCell.landscapeNormal: Offset(280, 250)},
            ),
          );
      await tester.pumpAndSettle();

      // 观看态：点选数拍浮层 → 左下角角工具（节拍提示入口）。
      final gesture = await tester.startGesture(const Offset(350, 290));
      await gesture.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_prompt_panel')),
        findsNothing,
        reason: '角标按下前无气泡：气泡确实由本入口打开',
      );

      await tester.tap(find.byKey(const Key('metronome_overlay_beat_panel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(eightBeatButton(tester).onPressed, isNotNull, reason: '不置灰不隐藏');

      await tester.tap(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isTrue,
      );
      expect(find.byKey(const Key('control_beat_anchor_add')), findsOneWidget);
    });

    testWidgets('退出路径：底排退出 / 收起控制层 / 返回首页 都结束待命态，锚点不丢、工具槽恢复原样', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      await pumpPlayer(tester, engine: engine, anchors: const [28]);

      // ① 底排「退出八拍矫正」。
      await enterStandby(tester);
      await tester.tap(find.byKey(const Key('control_beat_correction_exit')));
      await tester.pumpAndSettle();
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isFalse,
      );
      expect(anchorsOf(tester), [28]);

      // ② 收起控制层。
      await enterStandby(tester);
      await tester.tap(find.byKey(const Key('control_layer_blank')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isFalse,
      );
      expect(anchorsOf(tester), [28], reason: '退出待命态锚点不丢');

      // ③ 返回首页（标题栏「退出」= 既有的返回首页按钮）。
      await enterStandby(tester);
      await tester.tap(find.byKey(const Key('control_layer_back')));
      await tester.pumpAndSettle();
      expect(
        containerOf(tester).read(playerSessionProvider).isBeatCorrectionStandby,
        isFalse,
      );
      expect(anchorsOf(tester), [28]);

      // 工具槽恢复原样（锚点工具全不显示、原标注工具回来）。
      expect(find.byKey(const Key('control_beat_anchor_add')), findsNothing);
      expect(find.byKey(const Key('control_beat_anchor_remove')), findsNothing);
      expect(find.byKey(const Key('control_beat_anchors_clear')), findsNothing);
      expect(slotText(const Key('control_segment'), '分段'), findsOneWidget);
      expect(slotText(const Key('control_auto_range'), '自动分段'), findsOneWidget);
    });
  });
}
