import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatAlignPreviewOffsetProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_prompt_panel.dart';
import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/speed_step_preset_store.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 「节拍矫正」菜单列与「节拍对齐」独立气泡：
///
/// - 第三列 = 标题「节拍矫正」+ 一行小字说明 + 竖排三个按钮（各带一行使用
///   提示，增至三个条目），不再承载对齐控件本体；
/// - 点「节拍对齐」→ 节拍提示气泡消失、独立对齐气泡出现在同一入口链接下，
///   两气泡互斥单开；关闭/切走即弃未应用预览；再点入口切回节拍提示气泡；
/// - 「八拍矫正」为**真实入口**：仅真实网格就绪可用（占位/
///   异常置灰），按下即关本气泡 + 进控制层待命态。
///
/// 交互面断言只钉外部可见语义（键、文案、置灰、气泡互斥与锚定），不断言
/// 内部实现与像素级排版。
void main() {
  /// 气泡宿主：入口钮（CompositedTransformTarget）+ 共享 [SpeedBubbleHost]，
  /// 与生产同路径（会话单值互斥 + 点气泡外收起）。入口离左右缘足够远——
  /// 锚定居中不触发水平钳制，命中位置即绘制位置。
  final LayerLink link = LayerLink();

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    double entryLeft = 200,
  }) async {
    final engine = FakePlaybackEngine();
    final storage = InMemoryPrivateJsonStorage();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          metronomeSettingsAutoRestoreProvider.overrideWithValue(false),
          playbackEngineProvider.overrideWithValue(engine),
          speedStepPresetStorageProvider.overrideWithValue(
            SpeedStepPresetStore(storage),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return Scaffold(
                body: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: entryLeft, top: 40),
                        child: CompositedTransformTarget(
                          link: link,
                          child: Consumer(
                            builder: (context, ref, _) => IconButton(
                              key: const Key('beat_entry'),
                              onPressed: () {
                                // 生产入口语义（编辑态顶栏 / 观看态角工具）：
                                // 已是节拍提示气泡则收起，否则切到节拍提示气泡
                                // ——对齐气泡打开时再点即「切回」。
                                final session = ref.read(
                                  speedBubbleSessionProvider,
                                );
                                final bubble = ref.read(
                                  speedBubbleSessionProvider.notifier,
                                );
                                if (session.open == SpeedBubbleMode.beat) {
                                  bubble.close();
                                } else {
                                  bubble.open(SpeedBubbleMode.beat);
                                }
                              },
                              icon: const Icon(Icons.music_note),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SpeedBubbleHost(
                      linkFor: (_) => link,
                      targetAnchor: Alignment.bottomCenter,
                      followerAnchor: Alignment.topCenter,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    return container;
  }

  /// 气泡内容超出一屏时可滚动：先确保可见再点。
  Future<void> tapPanel(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<ProviderContainer> openBeatBubble(
    WidgetTester tester, {
    double entryLeft = 200,
  }) async {
    final container = await pumpHost(tester, entryLeft: entryLeft);
    addTearDown(container.dispose);
    await tester.tap(find.byKey(const Key('beat_entry')));
    await tester.pumpAndSettle();
    return container;
  }

  group('节拍矫正菜单列（第三列）', () {
    testWidgets('标题「节拍矫正」+ 一行小字说明', (tester) async {
      await openBeatBubble(tester);

      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(find.text('节拍矫正'), findsOneWidget);
      expect(find.text('修正整曲或局部的节拍错位'), findsOneWidget);
    });

    testWidgets('三个按钮竖排、各带一行使用提示（增至三个条目）', (tester) async {
      await openBeatBubble(tester);

      // 三个按钮都在场且文案与声明一致。
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_density_button')),
        findsOneWidget,
      );
      // 各带一行使用提示小字。
      expect(find.byKey(const Key('beat_correction_align_hint')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_eight_beat_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_density_hint')),
        findsOneWidget,
      );
      expect(find.text('整首偏移时用'), findsOneWidget);
      expect(find.text('八拍点错位 / 半八拍时用'), findsOneWidget);
      // 占位态：使用提示说明原因。
      expect(find.text('节拍分析完成后可用'), findsOneWidget);

      // 竖排：八拍矫正在对齐之下、节拍倍频在八拍矫正之下。
      final align = tester.getRect(
        find.byKey(const Key('beat_correction_align_button')),
      );
      final eight = tester.getRect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      final density = tester.getRect(
        find.byKey(const Key('beat_correction_density_button')),
      );
      expect(eight.top, greaterThanOrEqualTo(align.bottom));
      expect(density.top, greaterThanOrEqualTo(eight.bottom));
    });

    testWidgets('「八拍矫正」占位/异常网格置灰（既有「待支持」占位已退役）', (tester) async {
      final container = await openBeatBubble(tester);

      // 缺省节拍轨 = 占位（分析中/未开始）→ 置灰不可用。
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      expect(button.onPressed, isNull, reason: '占位网格不可用');
      expect(button.enabled, isFalse);
      expect(
        find.byKey(const Key('beat_correction_eight_beat_pending')),
        findsNothing,
        reason: '不再是待支持占位',
      );

      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_correction_eight_beat_button')),
            )
            .enabled,
        isFalse,
        reason: '异常网格不可用',
      );
      // 置灰按钮不产生任何会话/视图变化（仍是节拍提示气泡）。
      await tester.tap(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beat,
      );
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
    });

    testWidgets('「八拍矫正」就绪网格可点：关气泡 + 落进入待办（非宿主发起落待办，编排与提交归宿主）', (tester) async {
      final container = await openBeatBubble(tester);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(
            BeatTrackState.ready(
              BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 6),
                beats: const [
                  BeatPoint(t: 0.5, down: true),
                  BeatPoint(t: 1.0, down: false),
                ],
              ),
            ),
          );
      await tester.pumpAndSettle();

      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(speedBubbleSessionProvider).open,
        isNull,
        reason: '按下即关闭节拍提示气泡',
      );
      expect(
        container.read(playerSessionProvider).pendingEntry?.target,
        PlayerSessionMode.beatCorrectionStandby,
        reason: '非宿主发起 = 落待办（宿主听待办槽编排后经唯一提交入口提交）',
      );
    });

    testWidgets('「节拍对齐」按钮可点（不再置灰，且不因网格未就绪置灰）', (tester) async {
      await openBeatBubble(tester);

      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('beat_correction_align_button')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('四行小字均单行完整可读（默认字号下不被省略号截断，增至四行）', (tester) async {
      await openBeatBubble(tester);

      for (final key in const [
        'beat_correction_column_hint',
        'beat_correction_align_hint',
        'beat_correction_eight_beat_hint',
        'beat_correction_density_hint',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(Key(key)),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$key 应单行完整显示（列说明与两行使用提示不被截断）',
        );
      }
    });

    testWidgets('第三列不再是对齐控件本体：对齐键不在节拍提示气泡内', (tester) async {
      await openBeatBubble(tester);

      expect(find.byKey(const Key('beat_align_group')), findsNothing);
      expect(find.byKey(const Key('beat_align_step')), findsNothing);
      expect(find.byKey(const Key('beat_align_plus')), findsNothing);
      expect(find.byKey(const Key('beat_align_apply')), findsNothing);
      expect(find.byKey(const Key('beat_align_status')), findsNothing);
    });

    test('列宽口径：菜单列按自身内容实测钉值，明显窄于旧对齐列 344 预算', () {
      // 不再沿用对齐气泡内容宽预算；钉值 = 最长单行文案在 textScale 1.3 下
      // 不换行的实测宽（上取整到 4px 档）。
      expect(BeatPromptBubbleContent.correctionColWidth, lessThan(320));
      expect(BeatPromptBubbleContent.correctionColWidth, 312);
      // 气泡总宽随单源列宽收窄：158 + 17 + 204 + 17 + 312 = 708（旧 740）。
      expect(BeatPromptBubbleContent.contentWidth, 708);
      // 两条分隔线位置只由前两列宽决定，不动（166 / 387）。
      expect(BeatPromptBubbleContent.columnSeparatorXs(), [166.0, 387.0]);
    });

    testWidgets('四行文案在 textScale 1.3 下均单行不换行（列宽钉值口径）', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openBeatBubble(tester);

      // 列说明与三行使用提示均单行完整可读（不被省略号截断、不换行）。
      for (final key in const [
        'beat_correction_column_hint',
        'beat_correction_align_hint',
        'beat_correction_eight_beat_hint',
        'beat_correction_density_hint',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(Key(key)),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$key 不截断');
        expect(tester.getSize(find.byKey(Key(key))).height,
            lessThan(30), reason: '$key 单行');
      }
    });
  });

  group('节拍对齐独立气泡（原第三列控件迁出）', () {
    /// 就绪网格文档（拍点 0.5/1.0/1.5/2.0s，第 1 拍 downbeat）。
    void seedReadyGrid(ProviderContainer container) {
      container.read(beatTrackStateProvider.notifier).replace(
            BeatTrackState.ready(
              BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 6),
                beats: const [
                  BeatPoint(t: 0.5, down: true),
                  BeatPoint(t: 1.0, down: false),
                  BeatPoint(t: 1.5, down: false),
                  BeatPoint(t: 2.0, down: false),
                ],
              ),
            ),
          );
    }

    /// 打开节拍提示气泡 → 点第三列「节拍对齐」进入独立气泡。
    Future<ProviderContainer> openAlignBubble(
      WidgetTester tester, {
      double entryLeft = 200,
    }) async {
      final container = await openBeatBubble(tester, entryLeft: entryLeft);
      await tapPanel(
        tester,
        find.byKey(const Key('beat_correction_align_button')),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('点「节拍对齐」→ 节拍提示气泡消失、独立对齐气泡出现', (tester) async {
      tester.view.physicalSize = const Size(1600, 800); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await pumpHost(tester, entryLeft: 600);
      addTearDown(container.dispose);
      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();

      await tapPanel(
        tester,
        find.byKey(const Key('beat_correction_align_button')),
      );
      await tester.pumpAndSettle();

      // 会话单值：切到对齐气泡即离开节拍提示气泡（互斥单开）。
      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beatAlign,
      );
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(find.byKey(const Key('beat_correction_column')), findsNothing);
      expect(find.byKey(const Key('beat_align_bubble')), findsOneWidget);
      expect(find.byKey(const Key('beat_align_group')), findsOneWidget);

      // 锚在**同一个入口链接**上：气泡在入口下方、水平中心对齐入口，
      // 且气泡宽 = 原列宽 + 壳边距（控件排版原样搬迁）。
      final entry = tester.getRect(find.byKey(const Key('beat_entry')));
      final bubble = tester.getRect(find.byKey(const Key('beat_align_bubble')));
      expect(bubble.top, greaterThanOrEqualTo(entry.bottom));
      expect(
        (bubble.center.dx - entry.center.dx).abs(),
        lessThan(2.5),
        reason: '对齐气泡锚同一入口链接、水平中心对齐',
      );
      expect(bubble.width, closeTo(344, 1.0));
    });

    testWidgets('对齐气泡内控件逐项在场：步长三档/± 读数/重置/应用/状态小字', (tester) async {
      await openAlignBubble(tester);

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
      // 就绪网格未注入（占位态）：读数占位、步长/±/重置/应用置灰。
      expect(find.text('— 拍'), findsOneWidget);
      expect(find.text('— ms'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('beat_align_plus')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('beat_align_apply')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('经入口打开的对齐气泡仍是原控件：就绪网格下 ± 可用、预览生效', (tester) async {
      // 行为逐项断言（步长三档/读数/重置/应用/状态小字端到端）归
      // beat_alignment_panel_test（同一 [BeatAlignmentBubbleContent] 组件），
      // 此处只钉「从节拍矫正菜单列入口打开的那一个气泡」确实拿到同一套活控件
      // （就绪网格前不可用 → 就绪后可用、预览生效）。
      final container = await openAlignBubble(tester);
      seedReadyGrid(container);
      await tester.pumpAndSettle();

      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.5);
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+1 拍'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('关闭对齐气泡即丢弃未应用预览偏移（不自动应用）', (tester) async {
      final container = await openAlignBubble(tester);
      seedReadyGrid(container);
      await tester.pumpAndSettle();

      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.5);

      // 点气泡外区域收起。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_align_bubble')), findsNothing);
      expect(container.read(speedBubbleSessionProvider).open, isNull);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.0,
          reason: '未应用的预览不写盘');
    });

    testWidgets('切到其它气泡即丢弃预览；再点入口切回节拍提示气泡', (tester) async {
      final container = await openAlignBubble(tester);
      seedReadyGrid(container);
      await tester.pumpAndSettle();
      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      expect(container.read(beatAlignPreviewOffsetProvider), 0.5);

      // 切倍速气泡（异模式直接替换，会话单值）：对齐气泡消失 + 预览丢弃。
      container
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_align_bubble')), findsNothing);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);

      // 点「节拍提示」工具入口：切回节拍提示气泡（第三列一致）。气泡遮罩
      // 在先——首次点击由遮罩承接（收起倍速气泡），再点即打开节拍提示气泡
      // （与既有「工具→遮罩→工具」路径同构）。
      await tester.tap(find.byKey(const Key('beat_entry')), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('beat_entry')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beat,
      );
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(find.byKey(const Key('beat_align_bubble')), findsNothing);
    });

    testWidgets('对齐气泡宽度恒定：读数变化只变读数内容，气泡宽不动', (tester) async {
      tester.view.physicalSize = const Size(1600, 800); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await pumpHost(tester, entryLeft: 600);
      addTearDown(container.dispose);
      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();
      seedReadyGrid(container);
      await tester.pumpAndSettle();
      await tapPanel(
        tester,
        find.byKey(const Key('beat_correction_align_button')),
      );
      await tester.pumpAndSettle();

      final width0 = tester.getSize(find.byKey(const Key('beat_align_bubble')));
      await tapPanel(tester, find.byKey(const Key('beat_align_plus')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_align_readout')),
          matching: find.text('+1 拍'),
        ),
        findsOneWidget,
        reason: '前置：读数确实变化',
      );
      expect(tester.getSize(find.byKey(const Key('beat_align_bubble'))), width0);
    });
  });
}
