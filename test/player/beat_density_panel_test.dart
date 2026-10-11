import 'package:dance_learning_app/player/beat_density_panel.dart';
import 'package:dance_learning_app/player/beat_prompt_panel.dart';
import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackState,
        beatDensityPreviewProvider,
        beatGridProvider,
        beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationEditorProvider;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_bubble_text.dart';
import '../helpers/fake_playback_engine.dart';

/// 「节拍倍频」入口与独立锚定气泡：
///
/// - 第三列第三个条目「节拍倍频」：置灰门 = 真实拍点可用（占位/异常置灰）；
/// - 独立锚定气泡：档位读数 + 「快一倍」「慢一半」+「重置」+「确认/取消」，
///   与节拍提示气泡互斥单开、锚同一入口；
/// - 按一下只改预览（派生网格实时跟随、不落盘）；「确认」才落盘 = 一次
///   可撤销的标注编辑，落盘后气泡退出；关气泡/切走即弃未应用预览；
/// - 到端点（×4 / ×¼）两枚按钮各自置灰；「重置」回到原样（×1）。
///
/// 断言只钉外部可见语义（键、文案、置灰、预览/落盘/撤销、气泡互斥），
/// 不断言内部实现与像素级排版。
void main() {
  group('纯函数：档位读数', () {
    test('档位表钉值：恰好五档 2 的幂（加一档只改这张表）', () {
      expect(beatDensityLevels, [0.25, 0.5, 1, 2, 4]);
    });

    test('五档 2 的幂各自有读数：×¼/×½/原样/×2/×4', () {
      expect(beatDensityLabel(0.25), '×¼');
      expect(beatDensityLabel(0.5), '×½');
      expect(beatDensityLabel(1), '原样');
      expect(beatDensityLabel(2), '×2');
      expect(beatDensityLabel(4), '×4');
    });
  });

  group('「节拍倍频」独立气泡（widget seam）', () {
    late ProviderContainer container;
    late FakePlaybackEngine engine;

    /// 就绪网格文档：拍点 0.5/1.0/1.5/2.0s，第 1 拍 downbeat（4 拍）。
    void seedReadyGrid() {
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
                  BeatPoint(t: 1.5, down: false),
                  BeatPoint(t: 2.0, down: false),
                ],
              ),
            ),
          );
    }

    Future<void> pumpHost(WidgetTester tester) async {
      engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      tester.view.physicalSize = const Size(
        1600,
        800,
      ); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
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
                // 生产同路径：气泡内容经 [SpeedBubble] 消费。
                return const Scaffold(body: SpeedBubble());
              },
            ),
          ),
        ),
      );
    }

    Future<void> openBubble(WidgetTester tester) async {
      await pumpHost(tester);
      container
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.beatDensity);
      await tester.pumpAndSettle();
    }

    Future<void> tapBubble(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
    }

    tearDown(() => container.dispose());

    testWidgets('占位态：控件在场但全部置灰、读数不误导读', (tester) async {
      await openBubble(tester);

      expect(find.byKey(const Key('beat_density_bubble')), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_density_faster')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_density_slower')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_density_reset')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_density_apply')),
            )
            .onPressed,
        isNull,
      );
      expect(container.read(beatDensityPreviewProvider), isNull);
    });

    testWidgets('异常态：控件置灰', (tester) async {
      await openBubble(tester);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pump();

      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_density_faster')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const Key('beat_density_apply')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('就绪态：读数「原样」；快一倍预览 ×2、读数随预览变化', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('beat_density_readout')),
          matching: find.text('原样'),
        ),
        findsOneWidget,
      );

      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      expect(container.read(beatDensityPreviewProvider), 2.0);
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_density_readout')),
          matching: find.text('×2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('端点置灰：×4 时「快一倍」置灰、×¼ 时「慢一半」置灰', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      bool fasterEnabled() =>
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const Key('beat_density_faster')),
              )
              .onPressed !=
          null;
      bool slowerEnabled() =>
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const Key('beat_density_slower')),
              )
              .onPressed !=
          null;

      // ×1：两枚都可用。
      expect(fasterEnabled(), isTrue);
      expect(slowerEnabled(), isTrue);

      // 快到 ×4：快一倍置灰、慢一半仍可用。
      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_density_readout')),
          matching: find.text('×4'),
        ),
        findsOneWidget,
      );
      expect(fasterEnabled(), isFalse);
      expect(slowerEnabled(), isTrue);

      // 重置回原样后慢到 ×¼：慢一半置灰、快一倍仍可用。
      await tapBubble(tester, find.byKey(const Key('beat_density_reset')));
      await tapBubble(tester, find.byKey(const Key('beat_density_slower')));
      await tapBubble(tester, find.byKey(const Key('beat_density_slower')));
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_density_readout')),
          matching: find.text('×¼'),
        ),
        findsOneWidget,
      );
      expect(fasterEnabled(), isTrue);
      expect(slowerEnabled(), isFalse);
    });

    testWidgets('重置回到原样（预览 ×1）', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapBubble(tester, find.byKey(const Key('beat_density_slower')));
      expect(container.read(beatDensityPreviewProvider), 0.5);
      await tapBubble(tester, find.byKey(const Key('beat_density_reset')));
      expect(container.read(beatDensityPreviewProvider), 1.0);
      expect(
        find.descendant(
          of: find.byKey(const Key('beat_density_readout')),
          matching: find.text('原样'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('预览只改派生网格（节拍轨刻度实时跟随）、不落盘', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      // 前置：原样 4 拍。
      expect(container.read(beatGridProvider).lastBeatIndex, 3);
      expect(container.read(beatTrackStateProvider).grid!.density, 1.0);

      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      await tester.pumpAndSettle();

      // 派生网格实时跟随（快方向 (N−1)×d+1 = 7 拍），落盘文档不动。
      expect(container.read(beatGridProvider).lastBeatIndex, 6);
      expect(container.read(beatTrackStateProvider).grid!.density, 1.0);
    });

    testWidgets('确认：倍频写定落盘、预览清空、气泡退出；一步撤销连倍频一起回退', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      await tapBubble(tester, find.byKey(const Key('beat_density_apply')));
      await tester.pumpAndSettle();

      expect(container.read(beatTrackStateProvider).grid!.density, 2.0);
      expect(container.read(beatDensityPreviewProvider), isNull);
      expect(
        container.read(speedBubbleSessionProvider).open,
        isNull,
        reason: '确认后应用并退出气泡',
      );

      // 一步撤销：倍频与连带改动一起还原。
      container.read(annotationEditorProvider).undo();
      await tester.pump();
      expect(container.read(beatTrackStateProvider).grid!.density, 1.0);
    });

    testWidgets('按钮放大：五个控件同档行高 ≥40（旧紧凑档 32），大字号 1.3 下不溢出', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      final heights = {
        for (final key in const [
          'beat_density_reset',
          'beat_density_faster',
          'beat_density_slower',
          'beat_density_cancel',
          'beat_density_apply',
        ])
          key: tester.getSize(find.byKey(Key(key))).height,
      };
      for (final entry in heights.entries) {
        expect(
          entry.value,
          greaterThanOrEqualTo(40),
          reason: '${entry.key} 的触控目标已放大（旧紧凑档 32）',
        );
      }
      expect(heights.values.toSet(), hasLength(1), reason: '五个控件同挂一档样式，行高一致');
      expect(tester.takeException(), isNull);
    });

    testWidgets('大字号 1.6：第二行不横向溢出、五钮全在场', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      for (final key in const [
        'beat_density_faster',
        'beat_density_slower',
        'beat_density_cancel',
        'beat_density_apply',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 在场');
      }
      expect(tester.takeException(), isNull, reason: '1.6× 下第二行不横向溢出');
    });

    testWidgets('确认（无净变化）：同样退出气泡、不留预览', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      // 未调整档位（原样）即确认 → 提交为 no-op，但操作已结束。
      await tapBubble(tester, find.byKey(const Key('beat_density_apply')));
      await tester.pumpAndSettle();

      expect(container.read(speedBubbleSessionProvider).open, isNull);
      expect(container.read(beatDensityPreviewProvider), isNull);
      expect(container.read(beatTrackStateProvider).grid!.density, 1.0);
    });

    testWidgets('取消：丢弃预览并关气泡（不自动应用）', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      expect(container.read(beatDensityPreviewProvider), 2.0);

      await tapBubble(tester, find.byKey(const Key('beat_density_cancel')));
      await tester.pumpAndSettle();

      expect(container.read(speedBubbleSessionProvider).open, isNull);
      expect(container.read(beatDensityPreviewProvider), isNull);
      expect(container.read(beatTrackStateProvider).grid!.density, 1.0);
    });

    testWidgets('切其它气泡即丢弃未应用预览；切回不自动应用', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();
      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      expect(container.read(beatDensityPreviewProvider), 2.0);

      container
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.beat);
      await tester.pumpAndSettle();

      expect(container.read(beatDensityPreviewProvider), isNull);
      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beat,
        reason: '与节拍提示气泡互斥单开',
      );
      expect(container.read(beatTrackStateProvider).grid!.density, 1.0);
    });

    testWidgets('气泡宽度恒定：读数变化不改气泡宽', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      final width0 = tester.getSize(
        find.byKey(const Key('beat_density_bubble')),
      );
      await tapBubble(tester, find.byKey(const Key('beat_density_faster')));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('beat_density_bubble'))),
        width0,
      );
    });

    testWidgets('气泡内文字是亮字（近黑底上不读成置灰）', (tester) async {
      await openBubble(tester);
      seedReadyGrid();
      await tester.pumpAndSettle();

      expectLightText(tester, find.text('节拍倍频'));
      expectLightText(
        tester,
        find.descendant(
          of: find.byKey(const Key('beat_density_readout')),
          matching: find.text('原样'),
        ),
      );
    });
  });

  group('第三列「节拍倍频」入口（菜单列 seam）', () {
    final LayerLink link = LayerLink();

    Future<ProviderContainer> pumpHost(
      WidgetTester tester, {
      double entryLeft = 200,
    }) async {
      final engine = FakePlaybackEngine();
      late ProviderContainer container;
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

    testWidgets('第三列第三个条目「节拍倍频」在场、带一行使用提示', (tester) async {
      await openBeatBubble(tester);

      expect(
        find.byKey(const Key('beat_correction_density_button')),
        findsOneWidget,
      );
      expect(find.text('节拍倍频'), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_density_hint')),
        findsOneWidget,
      );
      // 竖排序：倍频条目在八拍矫正之下。
      final eight = tester.getRect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
      );
      final density = tester.getRect(
        find.byKey(const Key('beat_correction_density_button')),
      );
      expect(density.top, greaterThanOrEqualTo(eight.bottom));
    });

    testWidgets('置灰门 = 真实拍点可用：占位/异常置灰、就绪可点', (tester) async {
      final container = await openBeatBubble(tester);

      bool enabled() =>
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const Key('beat_correction_density_button')),
              )
              .onPressed !=
          null;
      expect(enabled(), isFalse, reason: '占位网格置灰');

      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await tester.pumpAndSettle();
      expect(enabled(), isFalse, reason: '异常网格置灰');
      // 异常态：使用提示说明原因。
      expect(find.text('节拍识别失败，暂不可用'), findsOneWidget);

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
      expect(enabled(), isTrue, reason: '真实拍点就绪可点');
      // 就绪态：使用提示切回词条句式（`lib/beat/GLOSSARY.md`「节拍提示面板」）。
      expect(find.text('识别快/慢一倍时用'), findsOneWidget);
    });

    testWidgets('点「节拍倍频」→ 节拍提示气泡消失、倍频气泡出现且锚同一入口', (tester) async {
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

      await tester.tap(find.byKey(const Key('beat_correction_density_button')));
      await tester.pumpAndSettle();

      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beatDensity,
      );
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(find.byKey(const Key('beat_density_bubble')), findsOneWidget);

      final entry = tester.getRect(find.byKey(const Key('beat_entry')));
      final bubble = tester.getRect(
        find.byKey(const Key('beat_density_bubble')),
      );
      expect(bubble.top, greaterThanOrEqualTo(entry.bottom));
      expect(
        (bubble.center.dx - entry.center.dx).abs(),
        lessThan(2.5),
        reason: '倍频气泡锚同一入口链接、水平中心对齐',
      );
    });

    testWidgets('三条使用提示默认字号下均单行不截断；列宽与气泡总宽不变', (tester) async {
      tester.view.physicalSize = const Size(
        1600,
        800,
      ); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openBeatBubble(tester, entryLeft: 600);

      for (final key in const [
        'beat_correction_column_hint',
        'beat_correction_align_hint',
        'beat_correction_eight_beat_hint',
        'beat_correction_density_hint',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(Key(key)),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$key 应单行完整显示');
      }
      // 列宽与气泡总宽不变（既有钉值：312 / 708）。
      expect(BeatPromptBubbleContent.correctionColWidth, 312);
      expect(BeatPromptBubbleContent.contentWidth, 708);
    });
  });
}
