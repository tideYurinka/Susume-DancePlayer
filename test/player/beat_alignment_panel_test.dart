
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatAlignPreviewOffsetProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationEditorProvider, annotationTimelineProvider;
import 'package:dance_learning_app/player/beat_alignment_panel.dart';
import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_bubble_text.dart';
import '../helpers/document_grid_of.dart';
import '../helpers/fake_playback_engine.dart';

/// 面板「节拍对齐」组：纯函数步长换算/读数换算 + widget 置灰/
/// 预览两阶段。
void main() {
  group('纯函数：步长换算与读数换算', () {
    test('步长三档：1 拍按当前网格拍距、½拍为其半、10ms 恒定', () {
      final grid = documentGridOf(
        BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: const [
            BeatPoint(t: 0.5, down: true),
            BeatPoint(t: 1.0, down: false),
          ],
        ),
      );
      expect(beatShiftStep(BeatShiftStepUnit.oneBeat, grid),
          const Duration(milliseconds: 500));
      expect(beatShiftStep(BeatShiftStepUnit.halfBeat, grid),
          const Duration(milliseconds: 250));
      expect(beatShiftStep(BeatShiftStepUnit.tenMs, grid),
          const Duration(milliseconds: 10));
    });

    test('读数换算：偏移秒 → 拍数（按拍距）+ 毫秒，含负偏移', () {
      final readout = beatShiftReadout(0.25, const Duration(milliseconds: 500));
      expect(readout.beats, 0.5);
      expect(readout.ms, 250);

      final negative =
          beatShiftReadout(-0.5, const Duration(milliseconds: 500));
      expect(negative.beats, -1.0);
      expect(negative.ms, -500);
    });

    test('状态小字三态：未应用 / 已应用 / 已改·未应用（预览差异判定）', () {
      // 未应用：committed 为 0、无预览。
      expect(beatAlignStatusLabel(committed: 0.0, preview: null), '未应用');
      // 已应用：committed 非零、无预览。
      expect(beatAlignStatusLabel(committed: 0.5, preview: null), '已应用');
      // 已改·未应用：预览与 committed 不同（预览优先，尚未提交）。
      expect(
        beatAlignStatusLabel(committed: 0.0, preview: 0.5),
        '已改·未应用',
      );
      // 预览与 committed 相同（如：reset 到已应用的 0 后）按 committed 判。
      expect(beatAlignStatusLabel(committed: 0.0, preview: 0.0), '未应用');
    });
  });

  group('面板「节拍对齐」组（widget seam）', () {
    const total = Duration(minutes: 1);

    late ProviderContainer container;
    late FakePlaybackEngine engine;

    /// 就绪网格文档：拍点 0.5/1.0/1.5/2.0s，第 1 拍 downbeat。
    void seedReadyGrid({double shift = 0}) {
      final track = BeatTrackState.ready(
        BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          shift: shift,
          beats: const [
            BeatPoint(t: 0.5, down: true),
            BeatPoint(t: 1.0, down: false),
            BeatPoint(t: 1.5, down: false),
            BeatPoint(t: 2.0, down: false),
          ],
        ),
      );
      container.read(beatTrackStateProvider.notifier).replace(track);
    }

    Future<void> pumpHost(WidgetTester tester) async {
      engine = FakePlaybackEngine(duration: total);
      // 节拍气泡三段内容宽（重校后 740，列间距 17 口径）按
      // 横屏宽屏消费，默认测试面 800 会硬截内容 → 用横屏宽测试面
      // （生产为 2736×1264）。
      tester.view.physicalSize = const Size(1600, 800); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            metronomeSettingsAutoRestoreProvider.overrideWithValue(false),
            playbackEngineProvider.overrideWithValue(engine),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                // 气泡内容经 [SpeedBubble] 消费（生产同路径）。
                return const Scaffold(body: SpeedBubble());
              },
            ),
          ),
        ),
      );
    }

    Future<void> openPanel(WidgetTester tester) async {
      await pumpHost(tester);
      // 本组已自「节拍提示」气泡第三列迁入**独立对齐气泡**
      // （节拍提示气泡第三列是「节拍矫正」菜单列，只放两个入口）。
      container.read(speedBubbleSessionProvider.notifier).open(
            SpeedBubbleMode.beatAlign,
          );
      await tester.pumpAndSettle();
    }

    Future<void> tapPanel(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    /// 经模块命令播种一条分段线。
    void seedSegmentLine() {
      container
          .read(annotationEditorProvider)
          .submit(const AddSegmentLine(at: Duration(seconds: 10)));
    }

    tearDown(() => container.dispose());

    testWidgets('默认占位态：组存在但全部控件置灰、读数不误导读', (tester) async {
      await openPanel(tester);

      expect(find.byKey(const Key('beat_align_group')), findsOneWidget);
      expect(
        tester.widget<IconButton>(
          find.byKey(const Key('beat_align_minus')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(
          find.byKey(const Key('beat_align_plus')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(
          find.byKey(const Key('beat_align_reset')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<ButtonStyleButton>(
          find.byKey(const Key('beat_align_apply')),
        ).onPressed,
        isNull,
      );
      // 无对齐试听按钮。
      expect(find.byKey(const Key('beat_align_audition')), findsNothing);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
    });

    testWidgets('异常态：控件置灰', (tester) async {
      await openPanel(tester);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pump();

      expect(
        tester.widget<IconButton>(
          find.byKey(const Key('beat_align_plus')),
        ).onPressed,
        isNull,
      );
      expect(
        tester.widget<ButtonStyleButton>(
          find.byKey(const Key('beat_align_apply')),
        ).onPressed,
        isNull,
      );
    });

    testWidgets('就绪态：步长 1 拍 + 预览偏移与读数（拍 + 毫秒）', (tester) async {
      await openPanel(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.5);

      // 读数：拍 + 毫秒双显示。
      expect(find.byKey(const Key('beat_align_readout')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+1 拍'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+500 ms'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('就绪态：已应用平移非零时读数显示已应用值', (tester) async {
      await openPanel(tester);
      seedReadyGrid(shift: 0.25);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+0.5 拍'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+250 ms'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('步长可切 ½拍/10ms；− 反向预览', (tester) async {
      await openPanel(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapPanel(tester, find.text('½拍'));
      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.25);

      await tapPanel(tester, find.byKey(const Key('beat_align_minus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.0);

      await tapPanel(tester, find.byKey(const Key('beat_align_minus')));
      expect(container.read(beatAlignPreviewOffsetProvider), -0.25);

      await tapPanel(tester, find.text('10ms'));
      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), -0.24);
    });

    testWidgets('重置归零；预览阶段不改线不写盘', (tester) async {
      await openPanel(tester);
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附。
      seedSegmentLine();
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.5);

      // 预览阶段：已落盘线与 beat 段平移量都不动。
      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.segmentLines.single.position,
          const Duration(seconds: 10));
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.0);

      await tapPanel(tester, find.byKey(const Key('beat_align_reset')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.0);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        const Duration(seconds: 10),
      );
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.0);
    });

    testWidgets('应用：调用 #17 应用命令提交，线平移、平移量写定、预览清空',
        (tester) async {
      await openPanel(tester);
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附。
      seedSegmentLine();
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      await tapPanel(tester, find.byKey(const Key('beat_align_apply')));
      await tester.pump();

      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        const Duration(milliseconds: 10500),
      );
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.5);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
    });

    testWidgets('退出面板：预览即弃（不自动应用），线不动', (tester) async {
      await openPanel(tester);
      // 先播种线（就绪网格未注入 → 加线不经吸附直通）、后注入
      // 就绪网格；既有线不回溯吸附。
      seedSegmentLine();
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.5);

      // 关闭气泡（本宿主直挂 SpeedBubble 无遮罩，经会话收起——点外收起
      // 路径在 beat_prompt_panel_test 宿主覆盖）。
      container.read(speedBubbleSessionProvider.notifier).close();
      await tester.pumpAndSettle();

      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        const Duration(seconds: 10),
      );
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.0);
    });

    testWidgets('A 排布：行1 步长+重置、行2 −读数＋ 左侧 + 应用正对重置下方、'
        '末行状态右对齐', (tester) async {
      await openPanel(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      // 关键件齐备（含末行状态文本键）。
      for (final key in const [
        'beat_align_step',
        'beat_align_reset',
        'beat_align_minus',
        'beat_align_readout',
        'beat_align_plus',
        'beat_align_apply',
        'beat_align_status',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }

      // 读数「拍+毫秒」两行（复用既有双行断言键）。
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+0 拍'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+0 ms'),
        ),
        findsOneWidget,
      );

      // 重置在步长所在行（同一横向跨度内），读数行居左。
      final stepCenter = tester.getCenter(find.byKey(const Key('beat_align_step')));
      final reset = tester.getCenter(find.byKey(const Key('beat_align_reset')));
      final readout = tester.getCenter(find.byKey(const Key('beat_align_readout')));
      expect((reset.dy - stepCenter.dy).abs() < 40, isTrue,
          reason: '重置与步长同一行');
      expect(stepCenter.dx < reset.dx, isTrue, reason: '重置在步长右方');

      // 读数居左（相对整组中点偏左），不居中。
      final groupCenter = tester.getCenter(find.byKey(const Key('beat_align_group')));
      expect(readout.dx < groupCenter.dx, isTrue, reason: '读数不居中、居左');

      // 行2 簇（−/读数/＋）起始与行1 分段控件左缘对齐；两行左内边距一致。
      final stepLeft = tester.getTopLeft(find.byKey(const Key('beat_align_step')));
      final minus = tester.getTopLeft(find.byKey(const Key('beat_align_minus')));
      expect((minus.dx - stepLeft.dx).abs() < 6, isTrue,
          reason: '− 读数簇与分段控件起始对齐');

      // 应用正对重置下方：应用中心 x 与重置同列，且在重置之下。
      final apply = tester.getCenter(find.byKey(const Key('beat_align_apply')));
      final resetCenter = tester.getCenter(
        find.byKey(const Key('beat_align_reset')),
      );
      expect(
        (apply.dx - resetCenter.dx).abs() < 20,
        isTrue,
        reason: '应用与重置同列',
      );
      expect(apply.dy > resetCenter.dy, isTrue, reason: '应用在重置下方');

      // 末行状态文本右对齐（位于右侧、在重置/应用之下）。
      final statusCenter = tester.getCenter(
        find.byKey(const Key('beat_align_status')),
      );
      expect(statusCenter.dx > groupCenter.dx, isTrue, reason: '状态右对齐');
      expect(statusCenter.dy > apply.dy, isTrue, reason: '状态在末行');
    });

    testWidgets('状态小字端到端：未应用 → 已改·未应用 → 已应用', (tester) async {
      await openPanel(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      // 初始：无预览、committed 0 → 未应用。
      expect(find.text('未应用'), findsOneWidget);

      // ± 预览：尚未提交 → 已改·未应用。
      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(find.text('已改·未应用'), findsOneWidget);

      // 应用提交：预览清空、committed 非零 → 已应用。
      await tapPanel(tester, find.byKey(const Key('beat_align_apply')));
      await tester.pump();
      expect(find.text('已应用'), findsOneWidget);
    });

    testWidgets('大字号 1.3×（就绪 + 最长读数）：复位/应用与读数不被裁切、无溢出', (tester) async {
      // 系统字号放大到 1.3×、注入就绪网格把读数
      // 步进到最长值，控件仍须整组在场且不得行内横向溢出（溢出会抛
      // RenderFlex overflow 使测试失败）。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openPanel(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      // 步进到最长读数（± 与读数随步进变宽）。
      for (var i = 0; i < 3; i++) {
        await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_align_group')), findsOneWidget);
      expect(find.byKey(const Key('beat_align_reset')), findsOneWidget);
      expect(find.byKey(const Key('beat_align_apply')), findsOneWidget);
      expect(find.byKey(const Key('beat_align_readout')), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);
      expect(find.text('应用'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 控件未被裁切：重置/应用完整落在气泡内容盒内。
      final bubble = tester.getRect(find.byKey(const Key('beat_align_bubble')));
      for (final key in const ['beat_align_reset', 'beat_align_apply']) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.left, greaterThanOrEqualTo(bubble.left - 0.5), reason: key);
        expect(rect.right, lessThanOrEqualTo(bubble.right + 0.5), reason: key);
      }
    });

    testWidgets('气泡内文字是亮字（近黑底上不读成置灰）', (tester) async {
      await openPanel(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      expectLightText(tester, find.text('节拍对齐'));
      expectLightText(
        tester,
        find
            .descendant(
              of: find.byKey(const Key('beat_align_readout')),
              matching: find.byType(Text),
            )
            .first,
      );
    });
  });
}
