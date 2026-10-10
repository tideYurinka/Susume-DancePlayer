import 'dart:ui' show CheckedState;

import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/metronome_sound.dart';
import 'package:dance_learning_app/player/beat_prompt_panel.dart';
import 'package:dance_learning_app/player/beat_prompt_memory.dart';
import 'package:dance_learning_app/persistence/local_document.dart'
    show BeatPromptMemoryFields;
import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatAlignPreviewOffsetProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/song_loudness.dart';
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/speed_step_preset_store.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetMinSize;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_bubble_text.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/device_viewport.dart';

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

  /// [animationOn] = 打开气泡后把节拍动画总开关置开（默认关，
  /// 而本文件多数用例针对「组展开」内容，需先置开再断言；显式传 false 以
  /// 观察默认关态）。
  Future<ProviderContainer> openPanel(
    WidgetTester tester, {
    bool animationOn = true,
  }) async {
    final container = await pumpHost(tester);
    addTearDown(container.dispose);
    await tester.tap(find.byKey(const Key('beat_entry')));
    await tester.pumpAndSettle();
    if (animationOn && !container.read(beatPromptEnabledProvider)) {
      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
    }
    return container;
  }

  group('节拍提示锚定气泡（widget seam）', () {
    testWidgets('入口锚定展开：气泡在入口下方、水平与入口对齐、屏内不溢出', (tester) async {
      await openPanel(tester);

      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      final entry = tester.getRect(find.byKey(const Key('beat_entry')));
      final panel = tester.getRect(find.byKey(const Key('beat_prompt_panel')));
      expect(panel.top, greaterThanOrEqualTo(entry.bottom));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(
        panel.right,
        lessThanOrEqualTo(
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
        ),
      );
    });
    testWidgets('气泡内默认正文色是亮字（黑底上不读成置灰）', (tester) async {
      await openPanel(tester);

      // 本模式内暂无不显式设色的文字，故钉壳交给内容的默认正文色——它与
      // 「节拍对齐」「节拍倍频」走同一条节拍侧气泡壳，回归时同处失败。
      expectLightColor(
        DefaultTextStyle.of(
          tester.element(find.byKey(const Key('beat_prompt_panel'))),
        ).style.color,
      );
    });

    testWidgets('默认态：动画总开关关（会话级）、矩形、声音关（普通）、半拍开', (tester) async {
      final container = await openPanel(tester, animationOn: false);

      expect(container.read(beatPromptEnabledProvider), isFalse);
      expect(
        container.read(beatAnimationStyleProvider),
        BeatAnimationStyle.bar,
      );
      expect(container.read(metronomeSoundEnabledProvider), isFalse);
      expect(
        container.read(metronomeSoundTypeProvider),
        MetronomeSoundType.normal,
      );
      expect(container.read(metronomeHalfBeatEnabledProvider), isTrue);
    });

    testWidgets('行结构：无「节拍显示」行、无「前导」行、无「采样待补」占位', (tester) async {
      await openPanel(tester);

      expect(find.byKey(const Key('beat_panel_prompt_switch')), findsOneWidget);
      expect(find.byKey(const Key('beat_panel_display_switch')), findsNothing);
      expect(find.byKey(const Key('beat_panel_lead_in_switch')), findsNothing);
      expect(find.byKey(const Key('beat_panel_sound_pending')), findsNothing);
      expect(find.text('前导'), findsNothing);
      expect(find.text('节拍显示'), findsNothing);
    });

    testWidgets('动画总开关：单开关切换生效（数拍数字与动画同显同隐，无独立动画开关）', (tester) async {
      final container = await openPanel(tester);

      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      expect(container.read(beatPromptEnabledProvider), isFalse);

      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      expect(container.read(beatPromptEnabledProvider), isTrue);
    });

    testWidgets('声音反馈开关：默认关，打开后半拍声子项可见可调', (tester) async {
      final container = await openPanel(tester);

      // 声音关：半拍声子项不可见。
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsNothing,
      );

      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      expect(container.read(metronomeSoundEnabledProvider), isTrue);
      await tester.pumpAndSettle();

      // 声音开：半拍声可见（默认开）且可调。
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsOneWidget,
      );
      expect(container.read(metronomeHalfBeatEnabledProvider), isTrue);
      await tapPanel(
        tester,
        find.byKey(const Key('beat_panel_half_beat_switch')),
      );
      expect(container.read(metronomeHalfBeatEnabledProvider), isFalse);

      // 关声音：半拍声再次隐藏。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      expect(container.read(metronomeSoundEnabledProvider), isFalse);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsNothing,
      );
    });

    testWidgets('节拍音量滑条：声音关不可见；开可见默认 50%，拖动生效', (tester) async {
      final container = await openPanel(tester);

      // 声音关：滑条不可见。
      expect(find.byKey(const Key('beat_panel_volume_row')), findsNothing);

      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      // 声音开：滑条可见，默认 50%。
      expect(find.byKey(const Key('beat_panel_volume_row')), findsOneWidget);
      expect(container.read(metronomeVolumeProvider), 50);
      expect(find.text('50%'), findsOneWidget);

      // 拖到最右 → 滑条值上升。
      final sliderCenter = tester.getCenter(
        find.byKey(const Key('beat_panel_volume_slider')),
      );
      await tester.dragFrom(sliderCenter, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(container.read(metronomeVolumeProvider), greaterThan(50));
    });

    testWidgets('关闭视频声音：音量行下方的勾选项，勾选只静视频、取消即回来', (tester) async {
      final container = await openPanel(tester);
      final engine =
          container.read(playbackEngineProvider) as FakePlaybackEngine;

      // 声音关：整组收起，本项也不可见。
      expect(find.byKey(const Key('beat_panel_video_mute_row')), findsNothing);

      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      // 位置：音量滑条下方（音频条之下）。
      final volumeRow = tester.getRect(
        find.byKey(const Key('beat_panel_volume_row')),
      );
      final muteRow = tester.getRect(
        find.byKey(const Key('beat_panel_video_mute_row')),
      );
      expect(muteRow.top, greaterThanOrEqualTo(volumeRow.bottom - 0.5));
      expect(find.text('关闭视频声音'), findsOneWidget);

      // 默认不勾、未写过内核。
      expect(container.read(videoMutedProvider), isFalse);
      expect(engine.videoMuteCalls, isEmpty);

      // 点整行（此处点文案）→ 只静视频：值 + 内核同值。
      await tapPanel(tester, find.text('关闭视频声音'));
      expect(container.read(videoMutedProvider), isTrue);
      expect(engine.videoMuteCalls, [true]);

      // 再点一次取消 → 视频声音原样回来。
      await tapPanel(tester, find.text('关闭视频声音'));
      expect(container.read(videoMutedProvider), isFalse);
      expect(engine.videoMuteCalls, [true, false]);
    });

    testWidgets('关掉「声音反馈」总开关：视频静音一并解除', (tester) async {
      final container = await openPanel(tester);
      final engine =
          container.read(playbackEngineProvider) as FakePlaybackEngine;
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      await tapPanel(tester, find.text('关闭视频声音'));
      expect(container.read(videoMutedProvider), isTrue);

      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      expect(container.read(videoMutedProvider), isFalse);
      expect(engine.videoMuteCalls.last, isFalse);
      // 组收起后本行随组隐藏，不留半个勾选态。
      expect(find.byKey(const Key('beat_panel_video_mute_row')), findsNothing);
    });

    testWidgets('关气泡不解除视频静音：同一支舞里一直只听拍子', (tester) async {
      final container = await openPanel(tester);
      final engine =
          container.read(playbackEngineProvider) as FakePlaybackEngine;
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      await tapPanel(tester, find.text('关闭视频声音'));
      expect(container.read(videoMutedProvider), isTrue);

      // 点气泡外收起。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(container.read(videoMutedProvider), isTrue);
      expect(engine.videoMuteCalls, [true]);

      // 再开气泡：勾选态还在（收气泡不改值、不再写内核）。
      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();
      final checkbox = tester.widget<Checkbox>(
        find.descendant(
          of: find.byKey(const Key('beat_panel_video_mute_row')),
          matching: find.byType(Checkbox),
        ),
      );
      expect(checkbox.value, isTrue);
      expect(engine.videoMuteCalls, [true]);
    });

    testWidgets('音源▾列表：人声/歌姬「待支持」置灰不可选，普通可选', (tester) async {
      final container = await openPanel(tester);

      // 声音总开关关 = 整组收起——音源行也不可见（音源/半拍/音量
      // 一并随声音开显隐）。
      expect(
        find.byKey(const Key('beat_panel_sound_source_row')),
        findsNothing,
      );

      // 打开声音反馈后音源行可见。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('beat_panel_sound_source_row')),
        findsOneWidget,
      );
      expect(find.text('音源'), findsOneWidget);

      // 展开音源列表：普通/人声/歌姬三项数组化渲染，人声/歌姬标「待支持」。
      // 注：DropdownButton 收起态按钮会复用被选中项的 DropdownMenuItem，故
      // 「普通」（默认选中）在收起按钮 + 展开菜单各出现一次。
      await tapPanel(
        tester,
        find.byKey(const Key('beat_panel_sound_source_select')),
      );
      await tester.pumpAndSettle();
      // 展开菜单里人声/歌姬两项各带「待支持」小字（节拍矫正菜单列的
      // 「八拍矫正」也带同款小字，故断言限定在下拉项内）。
      expect(
        find.descendant(
          of: find.byWidgetPredicate((w) => w is DropdownMenuItem),
          matching: find.text('待支持'),
        ),
        findsNWidgets(2),
      );

      bool optionEnabled(MetronomeSoundType type) {
        // 只取展开菜单里的项（收起按钮复用的那一份在外层，先 filter 掉）。
        final widgets = tester
            .widgetList<DropdownMenuItem<MetronomeSoundType>>(
              find.byWidgetPredicate((w) {
                return w is DropdownMenuItem<MetronomeSoundType> &&
                    w.value == type;
              }),
            )
            .toList();
        // 菜单展开后，选中项（普通）可能出现两份；都应为 enabled=false 之外
        // 的可选态。vocal/geigi 只出现在菜单、必然 enabled=false。
        return widgets.isNotEmpty && widgets.every((w) => w.enabled);
      }

      // 普通可选；人声/歌姬无采样置灰不可选但仍可见。
      expect(optionEnabled(MetronomeSoundType.normal), isTrue);
      expect(optionEnabled(MetronomeSoundType.vocal), isFalse);
      expect(optionEnabled(MetronomeSoundType.geigi), isFalse);

      // 收起列表（点气泡外）后再重开，选中态仍为普通。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(
        container.read(metronomeSoundTypeProvider),
        MetronomeSoundType.normal,
      );
    });

    testWidgets('用词统一：音源行标「音源」、音量行标「音量」，无「声种/声音种类」', (tester) async {
      final container = await openPanel(tester);

      // 打开声音反馈（声音关时整组收起，音源/音量行不可见）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(container.read(metronomeSoundEnabledProvider), isTrue);

      // 音源行标「音源」、音量行标「音量」；无「声种/声音种类」。
      expect(find.text('音源'), findsOneWidget);
      expect(find.text('声音种类'), findsNothing);
      expect(find.text('声种'), findsNothing);
      expect(find.text('音量'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
    });

    testWidgets('节拍动画形态选择：矩形/摆锤', (tester) async {
      final container = await openPanel(tester);

      await tester.tap(find.text('摆锤'));
      await tester.pump();
      expect(
        container.read(beatAnimationStyleProvider),
        BeatAnimationStyle.pendulum,
      );

      await tester.tap(find.text('矩形'));
      await tester.pump();
      expect(
        container.read(beatAnimationStyleProvider),
        BeatAnimationStyle.bar,
      );
    });

    testWidgets('三组内容键齐：动画组/声音组/节拍矫正菜单列（半拍声随声音开显隐）', (tester) async {
      await openPanel(tester);

      expect(find.byKey(const Key('beat_panel_prompt_switch')), findsOneWidget);
      expect(find.text('矩形'), findsOneWidget);
      expect(find.text('摆锤'), findsOneWidget);
      expect(find.byKey(const Key('beat_panel_sound_switch')), findsOneWidget);
      // 第三列为「节拍矫正」菜单列。
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsNothing,
      );
    });

    testWidgets('三段并排：动画/声音/节拍矫正三列横向排布，内容一次全显', (tester) async {
      final container = await openPanel(tester);

      // 三段列根键齐（列1 动画、列2 声音、列3 节拍矫正菜单列）。
      final anim = find.byKey(const Key('beat_anim_column'));
      final sound = find.byKey(const Key('beat_sound_column'));
      final correction = find.byKey(const Key('beat_correction_column'));
      expect(anim, findsOneWidget);
      expect(sound, findsOneWidget);
      expect(correction, findsOneWidget);

      // 三组内容齐：动画形态（矩形/摆锤）、节拍矫正菜单列两入口、声音总开关。
      expect(find.byKey(const Key('beat_panel_prompt_switch')), findsOneWidget);
      expect(find.text('矩形'), findsOneWidget);
      expect(find.text('摆锤'), findsOneWidget);
      expect(find.byKey(const Key('beat_panel_sound_switch')), findsOneWidget);
      expect(find.text('节拍矫正'), findsOneWidget);

      // 声音开：音源/半拍/音量三个子行齐（随声音开整组展开）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('beat_panel_sound_source_row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beat_panel_volume_row')), findsOneWidget);
      expect(container.read(metronomeSoundEnabledProvider), isTrue);

      // 三段横向排布：列1 左、列2 中、列3 右（x 依序递增，不上下叠）。
      final cx = tester.getCenter;
      expect(cx(anim).dx, lessThan(cx(sound).dx));
      expect(cx(sound).dx, lessThan(cx(correction).dx));
      // 三段顶对齐（同排，非上下叠）：各列 top 相同。
      final top = tester.getTopLeft;
      expect(top(anim).dy, top(sound).dy);
      expect(top(sound).dy, top(correction).dy);
    });

    testWidgets('内容一次全显：打开即完整、无纵向滚动依赖', (tester) async {
      await openPanel(tester);

      double maxScrollExtent() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      // 默认态（动画开、声音关）一次全显，无滚动距离。
      expect(maxScrollExtent(), 0);

      // 两组总开关都展开（最占高）仍一次全显、无滚动。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(maxScrollExtent(), 0);

      // 三段内容全部可见（未被纵向裁剪）：第三列节拍矫正菜单列整列在场（含
      // 两个入口按钮与待支持标记）。
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        findsOneWidget,
      );
      expect(maxScrollExtent(), 0);
    });

    testWidgets('横屏窄高：最占高（两组都开）内容一次全显、无纵向滚动', (tester) async {
      // 真机横屏窄高主场景（如 2736×1264 横屏逻辑高 ≈ 300–400）——短高视口
      // 下最占高态也不依赖纵向滚动兜底（目标内容高 ≤~170）。
      tester.view.physicalSize = const Size(
        2600,
        800,
      ); // 合成档 1300.0×400.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0; // 逻辑 1300×400
      addTearDown(tester.view.reset);
      await openPanel(tester);

      double maxScrollExtent() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;

      // 两组总开关都开（最占高）仍一次全显。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(find.text('音量'), findsOneWidget);
      expect(find.text('矩形'), findsOneWidget);
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(maxScrollExtent(), 0);
    });

    testWidgets('收起宽度恒定：关总开关只变高度，列宽与气泡总宽不变', (tester) async {
      await openPanel(tester);

      Size sizeOf(Key key) => tester.getSize(find.byKey(key));
      double w(Key k) => sizeOf(k).width;
      double h(Key k) => sizeOf(k).height;
      final bubble = const Key('beat_prompt_panel');
      final anim = const Key('beat_anim_column');
      final sound = const Key('beat_sound_column');
      final correction = const Key('beat_correction_column');

      // 默认态声音关：记录气泡/各列宽与气泡高（作为收起基线）。
      final bubbleWOff = w(bubble);
      final animWOff = w(anim);
      final soundWOff = w(sound);
      final correctionWOff = w(correction);
      final correctionHOff = h(correction);
      final soundHOff = h(sound);
      final hOff = h(bubble);

      // 声音开（整组展开）：声音列变高并成为最高列（含「关闭视频
      // 声音」行盒），整泡高随最高列变高。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      final hOn = h(bubble);
      expect(h(sound), greaterThan(soundHOff), reason: '声音开整组展开 → 声音列变高');
      expect(h(sound), greaterThan(h(correction)), reason: '声音列成为最高列');
      expect(hOn, greaterThan(hOff), reason: '整泡高随最高列（声音列）变高');

      // 声音关（收起）：气泡回到收起高，列宽与气泡总宽不变。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(h(bubble), hOff);
      expect(w(bubble), bubbleWOff);
      expect(w(sound), soundWOff);
      expect(w(anim), animWOff);
      expect(w(correction), correctionWOff);

      // 声音开关全程各列宽与气泡总宽恒定（ON 态与 OFF 态一致）。
      expect(w(bubble), bubbleWOff);
      expect(w(anim), animWOff);
      expect(w(sound), soundWOff);
      expect(w(correction), correctionWOff);

      // 动画总开关 ON→OFF→ON：动画组列高收起/还原；列宽与气泡总宽恒定。
      // 第三列为无开关的菜单列——列高在任何开关态都不变（只
      // 承载两个入口）。
      final bubbleH0 = h(bubble);
      final animH0 = h(anim);
      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
      expect(h(anim), lessThan(animH0));
      expect(find.text('矩形'), findsNothing);
      expect(find.text('摆锤'), findsNothing);
      expect(h(correction), correctionHOff, reason: '菜单列无开关、列高恒定');
      expect(w(bubble), bubbleWOff);
      expect(w(anim), animWOff);
      expect(w(sound), soundWOff);
      expect(w(correction), correctionWOff);

      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
      expect(find.text('矩形'), findsOneWidget);
      expect(w(anim), animWOff);
      expect(w(bubble), bubbleWOff);
      expect(h(bubble), bubbleH0);
    });

    testWidgets('中心锚点：屏内放得下时气泡水平中心对齐入口锚点', (tester) async {
      // 宽屏（1600）避开钳位/兜底缩放；入口离左缘足够远（紧凑后
      // 气泡 760 宽居中需左缘 ≥8），验证纯中心对齐语义。
      tester.view.physicalSize = const Size(
        1600,
        800,
      ); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final container = await pumpHost(tester, entryLeft: 600);
      addTearDown(container.dispose);
      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();

      final entry = tester.getRect(find.byKey(const Key('beat_entry')));
      final panel = tester.getRect(find.byKey(const Key('beat_prompt_panel')));
      expect(
        (panel.center.dx - entry.center.dx).abs(),
        lessThan(2.5),
        reason: '气泡水平中心对齐入口锚点（左右对称；容差为文本排版取整）',
      );
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(1600));
    });

    test('列间距口径：分隔线两侧各 8px + 1px 线（列距 17），单源派生', () {
      expect(BeatPromptBubbleContent.colGapWidth, 1);
      expect(BeatPromptBubbleContent.colGapSide, 8);
      expect(BeatPromptBubbleContent.colGap, 17);
      // 三段内容宽 = 158 + 17 + 204 + 17 + 312 = 708（菜单列缩窄，
      // 旧 740；≤746 横屏纪律保持）。
      expect(BeatPromptBubbleContent.contentWidth, 708);
      // 分隔线 x（相对内容左缘，列布局单源累计）：166 与 387，满高分隔。
      expect(BeatPromptBubbleContent.columnSeparatorXs(), [166.0, 387.0]);
    });

    testWidgets('分隔线画笔 shouldRepaint 按内容比较：同内容重建不重绘', (tester) async {
      await openPanel(tester);

      CustomPainter vsep() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere(
            (w) => w.painter?.runtimeType.toString() == '_ColumnVsepPainter',
          )
          .painter!;

      final before = vsep();
      // 同内容重建：总开关切走再切回，列宽与分隔线 x 全程不变。
      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
      final after = vsep();

      expect(
        identical(before, after),
        isFalse,
        reason: '每次重建都是新画笔实例（旧实现比较 List 身份故恒重绘）',
      );
      expect(after.shouldRepaint(before), isFalse, reason: '分隔线内容相同 → 不重绘');
    });

    testWidgets('读数变化列宽恒定：音量读数变化只变读数内容，'
        '列宽与气泡总宽纹丝不动', (tester) async {
      tester.view.physicalSize = const Size(
        1600,
        800,
      ); // 合成档 1600.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // 入口离左缘足够远，避开钳位平移干扰宽度观感。
      final container = await pumpHost(tester, entryLeft: 600);
      addTearDown(container.dispose);
      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();

      double w(Key k) => tester.getSize(find.byKey(k)).width;
      final bubble = const Key('beat_prompt_panel');
      final anim = const Key('beat_anim_column');
      final sound = const Key('beat_sound_column');
      final correction = const Key('beat_correction_column');

      // 基线（声音关）。
      final bubbleW0 = w(bubble);
      final animW0 = w(anim);
      final soundW0 = w(sound);
      final correctionW0 = w(correction);

      // 声音开 → 拖音量滑条改变 % 读数（'50%' ↔ 其它宽度文本）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      final volumeSlider = find.byKey(const Key('beat_panel_volume_slider'));
      await tester.drag(volumeSlider, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(find.text('50%'), findsNothing, reason: '前置：音量读数确实变化');

      expect(w(bubble), bubbleW0, reason: '读数变化不改气泡总宽');
      expect(w(anim), animW0);
      expect(w(sound), soundW0);
      expect(w(correction), correctionW0, reason: '读数变化不改列宽');
    });

    testWidgets('大字号(1.3×)最展开：各列一次全显、无横向溢出', (tester) async {
      // 系统字号放大时文本不被裁切。固定列宽语义下兜底
      // 0.8× 只缩整泡（不重排），故大字号时文本必须在固定列内放得下、不得
      // 行内横向溢出（溢出会抛 RenderFlex overflow，测试即失败）。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(
        2600,
        800,
      ); // 合成档 1300.0×400.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2.0; // 逻辑 1300×400 窄高横屏。
      addTearDown(tester.view.reset);
      await openPanel(tester);

      // 两组总开关都开（最占宽文本全在场）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      // 各列在场、未被裁切/丢弃（第三列为节拍矫正菜单列两入口）。
      expect(find.byKey(const Key('beat_anim_column')), findsOneWidget);
      expect(find.byKey(const Key('beat_sound_column')), findsOneWidget);
      expect(find.byKey(const Key('beat_correction_column')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        findsOneWidget,
      );
      // 声音组子行（最占宽内容）确已展开在场，非空跑。
      expect(
        find.byKey(const Key('beat_panel_sound_source_row')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beat_panel_volume_row')), findsOneWidget);
      expect(find.text('节拍矫正'), findsOneWidget);
      expect(find.text('修正整曲或局部的节拍错位'), findsOneWidget);
      expect(find.text('整首偏移时用'), findsOneWidget);
      expect(find.text('八拍点错位 / 半八拍时用'), findsOneWidget);
    });

    testWidgets('与倍速气泡互斥单开：开倍速后再开节拍提示，只余节拍气泡', (tester) async {
      final container = await pumpHost(tester);
      addTearDown(container.dispose);

      container
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_rate_slider')), findsOneWidget);

      container
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.beat);
      await tester.pumpAndSettle();

      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.beat,
      );
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
      expect(find.byKey(const Key('speed_rate_slider')), findsNothing);
    });

    testWidgets('关闭气泡弃对齐预览：预览偏移清空、不自动应用', (tester) async {
      final container = await openPanel(tester);
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.25);
      await tester.pump();
      expect(container.read(beatAlignPreviewOffsetProvider), 0.25);

      // 点气泡外区域收起。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);
      expect(container.read(beatAlignPreviewOffsetProvider), isNull);
    });

    testWidgets('收起：再点入口可重新打开', (tester) async {
      await openPanel(tester);
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);

      // 点气泡外区域收起。
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsNothing);

      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_prompt_panel')), findsOneWidget);
    });
  });

  group('真机紧凑化', () {
    testWidgets('控件行高：开关/滑条行命中盒 ≥ 下限、分段钮视觉 ≤32', (tester) async {
      await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      // 组名总开关（命中盒撑到下限；视觉开关件仍居中紧凑）。
      expect(
        tester
            .getSize(find.byKey(const Key('beat_panel_prompt_switch')))
            .height,
        greaterThanOrEqualTo(kHitTargetMinSize),
        reason: '组名 Switch 行盒 = 命中盒，≥48（紧凑档 → 命中下限）',
      );
      expect(
        tester
            .getSize(find.byKey(const Key('beat_panel_half_beat_switch')))
            .height,
        greaterThanOrEqualTo(kHitTargetMinSize),
        reason: '半拍声 Switch 命中盒 ≥ 48',
      );
      // 动画形态分段钮：视觉保持 32 档（命中经透明层外扩）。
      final segmented = find.byType(SegmentedButton<BeatAnimationStyle>);
      expect(segmented, findsOneWidget);
      expect(
        tester.getSize(segmented).height,
        lessThanOrEqualTo(32),
        reason: '分段钮视觉 40 → ~32',
      );
      // 音量行：行盒即命中盒 ≥ 48。
      expect(
        tester.getSize(find.byKey(const Key('beat_panel_volume_row'))).height,
        greaterThanOrEqualTo(kHitTargetMinSize),
        reason: '音量滑条行命中盒 ≥ 48',
      );
      // 音源行（Dropdown dense）维持 24 量级、不被撑高。
      expect(
        tester
            .getSize(find.byKey(const Key('beat_panel_sound_source_row')))
            .height,
        lessThanOrEqualTo(28),
      );
    });

    testWidgets('整泡高度：声音组展开后声音列最高、整泡随之变高；列宽与总宽恒定', (tester) async {
      useNamedViewport(
        tester,
        ViewportTier.compact,
        landscape: true,
      ); // compact 横屏逻辑 781.7×361.1dp。
      await openPanel(tester);

      double w(Key k) => tester.getSize(find.byKey(k)).width;
      final panel = const Key('beat_prompt_panel');
      final anim = const Key('beat_anim_column');
      final sound = const Key('beat_sound_column');
      final correction = const Key('beat_correction_column');
      // 收起基线（紧凑档）高与各列宽、总宽。
      final hOff = tester.getSize(find.byKey(panel)).height;
      final wOff = [panel, anim, sound, correction].map(w).toList();

      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      final expanded = tester.getSize(find.byKey(panel)).height;

      // 声音组整组展开（含「关闭视频声音」行）后声音列高于菜单列——
      // 整泡高随最高列变高。
      expect(
        tester.getSize(find.byKey(sound)).height,
        greaterThan(tester.getSize(find.byKey(correction)).height),
        reason: '声音组展开后声音列为最高列',
      );
      expect(expanded, greaterThan(hOff), reason: '整泡高随最高列（声音列）变高');

      // 紧凑横屏：最展开态仍在宿主上限内一次全显（无滚动余量）。
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent,
        0,
        reason: '紧凑横屏最展开态一次全显',
      );

      // 紧凑档回归：收起/展开只变高度，列宽与气泡总宽恒定。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(panel)).height, hOff);
      expect([panel, anim, sound, correction].map(w).toList(), wOff);
    });

    testWidgets('compact 档横屏（782 量级）：气泡一次完整放下零缩放、总宽 ≤766', (tester) async {
      useNamedViewport(
        tester,
        ViewportTier.compact,
        landscape: true,
      ); // compact 横屏逻辑 781.7×361.1dp。
      await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      // 常量口径：内容宽 + 壳边距（左 8 / 右 12）≤ 782 − 16（横屏零缩放上限）。
      final bubbleWidth =
          BeatPromptBubbleContent.contentWidth +
          speedBubblePaddingLeft +
          speedBubblePaddingRight;
      expect(bubbleWidth, lessThanOrEqualTo(766), reason: '824 → ≤766dp');

      // 实测内容宽 = 自然宽（beat_prompt_panel 键在壳 Padding 内侧）；
      // 未被兜底等比缩小（缩放会等比缩实测宽）。
      final panel = tester.getRect(find.byKey(const Key('beat_prompt_panel')));
      expect(
        panel.width,
        closeTo(BeatPromptBubbleContent.contentWidth, 0.5),
        reason: '横屏 782 一次放下、scale = 1（无兜底缩小）',
      );
      expect(panel.right, lessThanOrEqualTo(782));
    });

    testWidgets('系统大字 textScale 1.3：紧凑行高不裁剪、无溢出', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      // 最展开态全内容在场（溢出会抛 RenderFlex overflow 使测试失败）。
      expect(find.byKey(const Key('beat_panel_prompt_switch')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('beat_panel_volume_row')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_panel_video_mute_row')),
        findsOneWidget,
      );
      // 第三列节拍矫正菜单列两入口 + 两行使用提示齐（大字号下不换行
      // 不溢出，超宽以省略号收尾）。
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_align_hint')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_hint')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // 行高下限仍容纳放大文本：13px × 1.3 ≈ 17 ≤ 行高。
      expect(
        tester.getSize(find.byKey(const Key('beat_panel_volume_row'))).height,
        greaterThanOrEqualTo(17),
      );
    });
  });

  group('命中盒 / 大字号 / 语义标签', () {
    testWidgets('面板控件命中盒 ≥ 下限：开关/滑条/分段钮/矫正入口（视觉件不变）', (tester) async {
      await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      double hitHeight(Key key) => tester.getRect(find.byKey(key)).height;
      for (final key in const [
        'beat_panel_prompt_switch',
        'beat_panel_sound_switch',
        'beat_panel_half_beat_switch',
        'beat_panel_volume_slider',
        'beat_panel_video_mute_row',
        'beat_panel_style_seg_hit',
        'beat_correction_align_button',
        'beat_correction_eight_beat_button',
      ]) {
        expect(
          hitHeight(Key(key)),
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中盒高 ≥ $kHitTargetMinSize',
        );
      }

      // 视觉件紧凑不变：分段钮视觉高仍 ≤32（外扩只发生在透明命中层）。
      expect(
        tester.getSize(find.byType(SegmentedButton<BeatAnimationStyle>)).height,
        lessThanOrEqualTo(32),
        reason: '分段钮视觉行高保持紧凑档',
      );
    });

    /// 打开面板、展开声音组并把音量拨到 100（最宽读数场景）。
    Future<void> pumpExpandedAtMaxVolume(WidgetTester tester) async {
      final container = await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      container.read(metronomeVolumeProvider.notifier).set(100);
      await tester.pumpAndSettle();
    }

    /// 断言最宽读数在场且完全落在声音列内（不裁切、不出列）、无溢出。
    Future<void> expectVolumeReadoutIntact(
      WidgetTester tester,
      String scale,
    ) async {
      final column = tester.getRect(find.byKey(const Key('beat_sound_column')));
      final readout = tester.getRect(find.text('100%'));
      expect(find.text('100%'), findsOneWidget);
      expect(
        readout.right,
        lessThanOrEqualTo(column.right + 0.5),
        reason: '$scale× 下音量读数不被裁',
      );
      expect(tester.takeException(), isNull, reason: '$scale× 下无溢出');
    }

    testWidgets('系统字号 1.3×：无溢出、音量读数不被裁', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpExpandedAtMaxVolume(tester);
      await expectVolumeReadoutIntact(tester, '1.3');
    });

    testWidgets('系统字号 1.6×：无溢出、音量读数不被裁', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpExpandedAtMaxVolume(tester);
      await expectVolumeReadoutIntact(tester, '1.6');
    });

    testWidgets('音源下拉与音量滑条报得出所属标签', (tester) async {
      await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(
              find.byKey(const Key('beat_panel_sound_source_select')),
            )
            .getSemanticsData()
            .label,
        contains('音源'),
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('beat_panel_volume_slider')))
            .getSemanticsData()
            .label,
        contains('音量'),
      );
      handle.dispose();
    });

    testWidgets('关闭视频声音：读得出文案与勾选态', (tester) async {
      final container = await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      container.read(videoMutedProvider.notifier).set(true);
      await tester.pumpAndSettle();

      final handle = tester.ensureSemantics();
      final data = tester
          .getSemantics(find.byKey(const Key('beat_panel_video_mute_row')))
          .getSemanticsData();
      expect(data.label, contains('关闭视频声音'));
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
      handle.dispose();
    });
  });

  group('竖屏三段堆叠（气泡族重排共用规则）', () {
    /// 真机竖屏基准视口：361.1 × 781.7dp（1264×2736 @3.5，唯一竖屏基准）。
    void setPortrait(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact);
    }

    /// 真机横屏：782 × 361dp（2736×1264 @3.5）。
    void setLandscape(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
    }

    final animCol = find.byKey(const Key('beat_anim_column'));
    final soundCol = find.byKey(const Key('beat_sound_column'));
    final correctionCol = find.byKey(const Key('beat_correction_column'));
    final panelKey = const Key('beat_prompt_panel');

    // 并排所需外宽：三段内容 708 + 气泡盒边距（左 8 / 右 12）= 728。
    // 取独立字面量而非复算生产算式——生产漂移时此处失配即暴露。
    const double sideBySideBubbleWidth = 728;

    test('布局判定复用共用规则：可用宽够 → 并排 708；不足 → 堆叠 312；边界即并排', () {
      BeatPromptBubbleLayout layoutAt(double availableWidth) =>
          beatPromptBubbleLayout(
            availableWidth: availableWidth,
            sideBySideBubbleWidth: sideBySideBubbleWidth,
          );

      // 横屏 782：可用 766 ≥ 728 → 并排，内容宽 708。
      final wide = layoutAt(782 - 2 * speedBubbleScreenMargin);
      expect(wide.stacked, isFalse);
      expect(wide.contentWidth, BeatPromptBubbleContent.contentWidth);

      // 竖屏 361.1：可用 345.1 < 728 → 堆叠，内容宽收为最宽段。
      final narrow = layoutAt(361.1 - 2 * speedBubbleScreenMargin);
      expect(narrow.stacked, isTrue);
      expect(narrow.contentWidth, BeatPromptBubbleContent.stackedContentWidth);

      // 边界（共用规则 >= 口径）：恰等于并排总宽仍并排，差 1px 堆叠。
      expect(layoutAt(sideBySideBubbleWidth).stacked, isFalse);
      expect(layoutAt(sideBySideBubbleWidth - 1).stacked, isTrue);
    });

    testWidgets('竖屏 361.1dp：三段上下堆叠、完整可见、无横向溢出、最展开态只多出一点滚动', (tester) async {
      setPortrait(tester);
      await openPanel(tester);

      expect(animCol, findsOneWidget);
      expect(soundCol, findsOneWidget);
      expect(correctionCol, findsOneWidget);

      // 堆叠：三段 y 依序递增、左缘对齐（同一纵列）。
      final tl = tester.getTopLeft;
      expect(tl(animCol).dy, lessThan(tl(soundCol).dy));
      expect(tl(soundCol).dy, lessThan(tl(correctionCol).dy));
      expect(tl(animCol).dx, closeTo(tl(soundCol).dx, 0.5));
      expect(tl(soundCol).dx, closeTo(tl(correctionCol).dx, 0.5));

      // 无裁切、无横向溢出：各段与面板右缘都在 361.1dp 屏内。
      const screenWidth = 1264 / 3.5;
      for (final column in [animCol, soundCol, correctionCol]) {
        expect(tester.getRect(column).right, lessThanOrEqualTo(screenWidth));
      }
      final panel = tester.getRect(find.byKey(panelKey));
      expect(panel.left, greaterThanOrEqualTo(0));
      expect(panel.right, lessThanOrEqualTo(screenWidth));

      // 段间两条横分隔线占满内容宽（可见、非零宽）。
      final separators = find.byKey(const Key('beat_stacked_separator'));
      expect(separators, findsNWidgets(2));
      final separatorSize = tester.getSize(separators.first);
      expect(
        separatorSize.width,
        closeTo(BeatPromptBubbleContent.stackedContentWidth, 0.5),
      );
      expect(separatorSize.height, BeatPromptBubbleContent.colGap);

      // 三段内部形态不变：总开关、音源/半拍/音量、菜单列两入口。
      expect(find.text('节拍动画'), findsOneWidget);
      expect(find.text('声音反馈'), findsOneWidget);
      expect(find.text('节拍矫正'), findsOneWidget);
      expect(
        find.byKey(const Key('beat_correction_align_button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('beat_correction_eight_beat_button')),
        findsOneWidget,
      );

      // 竖屏 781.7 高下最占高态：新增「关闭视频声音」行后声音段成为最高
      // 段，气泡壳略超宿主上限——只多出一点滚动（末行仍可达），不出现
      // 大段滚动。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('beat_panel_volume_row')), findsOneWidget);
      expect(
        find.byKey(const Key('beat_panel_video_mute_row')),
        findsOneWidget,
      );
      expect(
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .maxScrollExtent,
        lessThanOrEqualTo(8),
        reason: '最展开态多出的滚动 ≈3px（不足一行）',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('横竖屏切换即重排：竖屏堆叠 ↔ 横屏并排，开合与各组开关状态不丢', (tester) async {
      setPortrait(tester);
      final container = await openPanel(tester);
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(container.read(metronomeSoundEnabledProvider), isTrue);

      final tl = tester.getTopLeft;
      expect(tl(animCol).dy, lessThan(tl(soundCol).dy), reason: '竖屏堆叠');

      // 转横屏 compact 档（782 量级）：三段并排（同排 top、x 递增），面板与组开关状态保持。
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
      await tester.pumpAndSettle();
      expect(find.byKey(panelKey), findsOneWidget);
      expect(tl(animCol).dy, tl(soundCol).dy, reason: '横屏并排同排');
      expect(tl(soundCol).dy, tl(correctionCol).dy);
      expect(tl(animCol).dx, lessThan(tl(soundCol).dx));
      expect(tl(soundCol).dx, lessThan(tl(correctionCol).dx));
      expect(container.read(metronomeSoundEnabledProvider), isTrue);
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsOneWidget,
      );

      // 转回竖屏 compact 档：重新堆叠，声音组仍开、气泡仍开。
      useNamedViewport(tester, ViewportTier.compact);
      await tester.pumpAndSettle();
      expect(find.byKey(panelKey), findsOneWidget);
      expect(tl(animCol).dy, lessThan(tl(soundCol).dy), reason: '转回竖屏重新堆叠');
      expect(container.read(metronomeSoundEnabledProvider), isTrue);
      expect(
        find.byKey(const Key('beat_panel_half_beat_switch')),
        findsOneWidget,
      );
    });

    testWidgets('横屏 782 并排照旧：三段同排、内容宽 708 零缩放', (tester) async {
      setLandscape(tester);
      await openPanel(tester);

      final tl = tester.getTopLeft;
      expect(tl(animCol).dy, tl(soundCol).dy);
      expect(tl(soundCol).dy, tl(correctionCol).dy);
      expect(tl(animCol).dx, lessThan(tl(soundCol).dx));
      expect(tl(soundCol).dx, lessThan(tl(correctionCol).dx));
      expect(
        tester.getRect(find.byKey(panelKey)).width,
        closeTo(BeatPromptBubbleContent.contentWidth, 0.5),
      );
      expect(
        find.byKey(const Key('beat_stacked_separator')),
        findsNothing,
        reason: '并排走既有竖分隔线，不出现堆叠横线',
      );
    });

    testWidgets('竖屏堆叠：组总开关关闭只变高度，气泡总宽与各段宽不变', (tester) async {
      setPortrait(tester);
      await openPanel(tester);

      double w(Key key) => tester.getSize(find.byKey(key)).width;
      double h(Key key) => tester.getSize(find.byKey(key)).height;
      final anim = const Key('beat_anim_column');
      final sound = const Key('beat_sound_column');
      final correction = const Key('beat_correction_column');

      final bubbleW = w(panelKey);
      final hOff = h(panelKey);
      final widths = [anim, sound, correction].map(w).toList();

      // 声音组展开（整组子行）→ 只变高，各段与气泡总宽不变。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(h(panelKey), greaterThan(hOff));
      expect(w(panelKey), bubbleW);
      expect([anim, sound, correction].map(w).toList(), widths);

      // 收起 → 回到基线高，宽仍不变。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(h(panelKey), hOff);
      expect(w(panelKey), bubbleW);
      expect([anim, sound, correction].map(w).toList(), widths);
    });
  });

  group('节拍器设置设备级持久化（metronomeSettings 扩键）', () {
    test('设置槽变更落盘；新容器（等价重启）读回', () async {
      final storage = InMemoryPrivateJsonStorage();
      final container = ProviderContainer(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);

      final style = container.read(beatAnimationStyleProvider.notifier);
      // 设备级「新舞默认」层的落盘/恢复同步点（生效值槽本身不再
      // 直接持有 metronomeSettings 同步）。
      await container
          .read(beatAnimationStyleDefaultProvider.notifier)
          .restoreDone;
      // 内存存储实现按「单次 update」收口（无跨调用写链），这里顺序等每次
      // 落盘完成再改下一字段；真实 AtomicJsonFile.update 本身串行。
      style.set(BeatAnimationStyle.pendulum);
      await container
          .read(beatAnimationStyleDefaultProvider.notifier)
          .flushDone;
      container
          .read(metronomeSoundTypeProvider.notifier)
          .set(MetronomeSoundType.geigi);
      await container
          .read(metronomeSoundTypeDefaultProvider.notifier)
          .flushDone;
      container.read(metronomeHalfBeatEnabledProvider.notifier).set(false);
      await container
          .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
          .flushDone;
      final volume = container.read(metronomeVolumeProvider.notifier);
      volume.set(80);
      await volume.flushDone;

      expect(storage.snapshot['metronomeSettings'], {
        'animationStyle': 'pendulum',
        'soundType': 'geigi',
        'halfBeatEnabled': false,
        'metronomeVolume': 80,
      });

      // 「重启等价」：同一存储的新容器恢复三字段。
      final restored = ProviderContainer(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(restored.dispose);
      await restored
          .read(beatAnimationStyleDefaultProvider.notifier)
          .restoreDone;
      await restored
          .read(metronomeSoundTypeDefaultProvider.notifier)
          .restoreDone;
      await restored
          .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
          .restoreDone;
      await restored.read(metronomeVolumeProvider.notifier).restoreDone;
      expect(
        restored.read(beatAnimationStyleProvider),
        BeatAnimationStyle.pendulum,
      );
      expect(
        restored.read(metronomeSoundTypeProvider),
        // 遗留非「普通」声种读取归一为「普通」。
        MetronomeSoundType.normal,
      );
      expect(restored.read(metronomeHalfBeatEnabledProvider), isFalse);
      expect(restored.read(metronomeVolumeProvider), 80);
    });

    test('遗留非「普通」声种读取归一为 normal', () async {
      for (final legacy in ['vocal', 'geigi']) {
        final storage = InMemoryPrivateJsonStorage(
          initial: {
            'metronomeSettings': {'soundType': legacy},
          },
        );
        final container = ProviderContainer(
          overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
        );
        addTearDown(container.dispose);
        await container
            .read(metronomeSoundTypeDefaultProvider.notifier)
            .restoreDone;
        expect(
          container.read(metronomeSoundTypeProvider),
          MetronomeSoundType.normal,
          reason: '遗留 soundType=$legacy',
        );
        expect(
          container.read(metronomeSoundTypeProvider).samplePending,
          isFalse,
          reason: '遗留 soundType=$legacy 不再抑制节拍声',
        );
      }
    });

    test('损坏设置兜底默认：非法值不起效', () async {
      final storage = InMemoryPrivateJsonStorage(
        initial: {
          'metronomeSettings': {
            'animationStyle': 'cube',
            'soundType': 42,
            'halfBeatEnabled': 'yes',
            'metronomeVolume': 150,
          },
        },
      );
      final container = ProviderContainer(
        overrides: [privateJsonStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      await container
          .read(beatAnimationStyleDefaultProvider.notifier)
          .restoreDone;
      await container
          .read(metronomeSoundTypeDefaultProvider.notifier)
          .restoreDone;
      await container
          .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
          .restoreDone;
      await container.read(metronomeVolumeProvider.notifier).restoreDone;
      expect(
        container.read(beatAnimationStyleProvider),
        BeatAnimationStyle.bar,
      );
      expect(
        container.read(metronomeSoundTypeProvider),
        MetronomeSoundType.normal,
      );
      expect(container.read(metronomeHalfBeatEnabledProvider), isTrue);
      expect(container.read(metronomeVolumeProvider), 50);
    });
  });

  group('面板读写生效值并写进这支舞的记忆', () {
    /// 读面板上某枚 Switch 的当前读数（UI 实显值，即生效值）。键挂在透明
    /// 命中盒上，Switch 是其子件。
    bool switchValue(WidgetTester tester, Key key) => tester
        .widget<Switch>(
          find.descendant(of: find.byKey(key), matching: find.byType(Switch)),
        )
        .value;

    /// 读面板形态分段的选中项（UI 实显值，即生效值）。
    Set<BeatAnimationStyle> selectedStyle(WidgetTester tester) => tester
        .widget<SegmentedButton<BeatAnimationStyle>>(
          find.byType(SegmentedButton<BeatAnimationStyle>),
        )
        .selected;

    /// 读面板音源下拉的当前值（UI 实显值，即生效值）。
    MetronomeSoundType soundSourceValue(WidgetTester tester) => tester
        .widget<DropdownButton<MetronomeSoundType>>(
          find.byKey(const Key('beat_panel_sound_source_select')),
        )
        .value!;

    testWidgets('无记忆舞的面板读数来自生效值：形态/半拍回落设备级「新舞默认」当前值', (tester) async {
      final container = await pumpHost(tester);
      addTearDown(container.dispose);
      // 设备级默认 = 用户上次选择：摆锤 + 半拍关（无记忆舞按它生效）。
      container
          .read(beatAnimationStyleDefaultProvider.notifier)
          .set(BeatAnimationStyle.pendulum);
      container
          .read(metronomeHalfBeatEnabledDefaultProvider.notifier)
          .set(false);

      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();

      // 总开关记忆缺席恒关。
      expect(
        switchValue(tester, const Key('beat_panel_prompt_switch')),
        isFalse,
      );
      // 扳开总开关（记忆落 animation，形态字段仍缺席）→ 分段显示设备级
      // 当前值（摆锤）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
      expect(selectedStyle(tester), {BeatAnimationStyle.pendulum});
      // 声音开（记忆落声音表态）后可见半拍行：读数同样是设备级当前值（关）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(
        switchValue(tester, const Key('beat_panel_half_beat_switch')),
        isFalse,
      );
    });

    testWidgets('有记忆舞的面板读数来自记忆，设备级那一层不再影响这一支舞', (tester) async {
      final container = await pumpHost(tester);
      addTearDown(container.dispose);
      container
          .read(beatAnimationStyleDefaultProvider.notifier)
          .set(BeatAnimationStyle.bar);
      container
          .read(beatPromptMemoryProvider.notifier)
          .restoreFor(
            'panel-test-video',
            const BeatPromptMemoryFields(
              animation: true,
              animationStyle: 'pendulum',
              sound: true,
              soundType: 'normal',
              halfBeat: false,
            ),
          );

      await tester.tap(find.byKey(const Key('beat_entry')));
      await tester.pumpAndSettle();

      expect(
        switchValue(tester, const Key('beat_panel_prompt_switch')),
        isTrue,
      );
      expect(selectedStyle(tester), {BeatAnimationStyle.pendulum});
      expect(switchValue(tester, const Key('beat_panel_sound_switch')), isTrue);
      expect(
        switchValue(tester, const Key('beat_panel_half_beat_switch')),
        isFalse,
      );
      // 音源列表同样显示生效值（记忆 soundType 字段解码值）。
      expect(soundSourceValue(tester), MetronomeSoundType.normal);
    });

    testWidgets('面板扳动即写进这支舞的记忆：形态/音源/半拍同时更新设备级，'
        '总开关只写记忆', (tester) async {
      final container = await openPanel(tester);
      // 打开面板时的总开关扳动已是一次用户表态：记忆记录落 animation。
      expect(container.read(beatPromptMemoryProvider)?.animation, isTrue);

      // 形态选摆锤：记忆落 animationStyle，设备级默认同时更新为摆锤。
      await tapPanel(tester, find.text('摆锤'));
      await tester.pumpAndSettle();
      expect(
        container.read(beatPromptMemoryProvider)?.animationStyle,
        'pendulum',
      );
      expect(
        container.read(beatAnimationStyleDefaultProvider),
        BeatAnimationStyle.pendulum,
      );

      // 声音开：只写记忆（总开关无设备级对应字段）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_sound_switch')));
      await tester.pumpAndSettle();
      expect(container.read(beatPromptMemoryProvider)?.sound, isTrue);

      // 音源下拉选「普通」（唯一可选音源；重选同值也是一次表态）：记忆落
      // soundType，设备级默认同写「普通」。收起按钮复用选中项的菜单项，
      // 点「普通」文本取菜单里那份（展开后唯一一份带文本的项是可点目标，
      // 收起按钮复用份不含独立文本节点）。
      await tester.tap(find.byKey(const Key('beat_panel_sound_source_select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('普通').last);
      await tester.pumpAndSettle();
      expect(container.read(beatPromptMemoryProvider)?.soundType, 'normal');
      expect(
        container.read(metronomeSoundTypeDefaultProvider),
        MetronomeSoundType.normal,
      );

      // 半拍关：记忆落 halfBeat，设备级默认同时更新为关。
      await tapPanel(
        tester,
        find.byKey(const Key('beat_panel_half_beat_switch')),
      );
      await tester.pumpAndSettle();
      expect(container.read(beatPromptMemoryProvider)?.halfBeat, isFalse);
      expect(container.read(metronomeHalfBeatEnabledDefaultProvider), isFalse);

      // 总开关再扳回关：记忆跟着翻回关（下次打开这支舞仍是关）。
      await tapPanel(tester, find.byKey(const Key('beat_panel_prompt_switch')));
      await tester.pumpAndSettle();
      expect(container.read(beatPromptMemoryProvider)?.animation, isFalse);
    });
  });
}
