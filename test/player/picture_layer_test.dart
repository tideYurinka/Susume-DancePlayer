/// 画面层模块套件：**直接挂载** [PictureLayer]——不经过播放页、
/// 不注容器、不需要十二个 provider 替换。断言的是这一层按「画面层输入」
/// 渲染出的画面结果（画面方向、宽高比、骨架分配、对比取景、练习面内容、
/// 反馈层形态）与输入变化时的重建纪律。
library;

import 'package:dance_learning_app/player/advanced_gestures.dart'
    show PlayerDoubleTapGestureRecognizer;
import 'package:dance_learning_app/player/framing_selection_view.dart'
    show FramingSelectionView;
import 'package:dance_learning_app/player/compare_split.dart'
    show CompareVideoSplit;
import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/picture_layer.dart';
import 'package:dance_learning_app/player/scrub_indicator.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHighlightAmber;

import '../helpers/video_surface.dart';

import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/gestures.dart'
    show
        LongPressGestureRecognizer,
        PointerCancelEvent,
        PointerDownEvent,
        PointerUpEvent,
        ScaleEndDetails,
        ScaleStartDetails,
        ScaleUpdateDetails;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/semantics_assertions.dart';

/// 贴底骨架（骨架分配用例）：画面带宽 100，贴画面区下缘（顶 100 = 画面区
/// 200 − 带高 100，与 `editorSkeletonFor` 的实际分配一致）。
const EditorSkeleton stickSkeleton = EditorSkeleton(
  compact: false,
  portrait: true,
  pictureAreaHeight: 200,
  picturePlacement: PicturePlacement.stickToBottom,
  pictureBandHeight: 100,
  pictureBandTop: 100,
);

/// 观看态背景位骨架：不落带（走整屏 contain）。
const EditorSkeleton backgroundSkeleton = EditorSkeleton(
  compact: false,
  portrait: true,
  pictureAreaHeight: 200,
  picturePlacement: PicturePlacement.background,
  pictureBandHeight: 0,
  pictureBandTop: 0,
);

Duration? tenSeconds() => const Duration(seconds: 10);
void main() {
  late LongPressGestureRecognizer longPress;
  late PlayerDoubleTapGestureRecognizer doubleTap;
  late GestureFeedbackController defaultFeedback;
  late ValueNotifier<Duration> defaultScrubTarget;

  setUp(() {
    longPress = LongPressGestureRecognizer();
    doubleTap = PlayerDoubleTapGestureRecognizer();
    defaultFeedback = GestureFeedbackController();
    defaultScrubTarget = ValueNotifier(Duration.zero);
  });

  tearDown(() {
    longPress.dispose();
    doubleTap.dispose();
    defaultFeedback.dispose();
    defaultScrubTarget.dispose();
  });

  void noopScaleStart(ScaleStartDetails _) {}
  void noopScaleUpdate(ScaleUpdateDetails _) {}
  void noopScaleEnd(ScaleEndDetails _) {}
  void noopPointerDown(PointerDownEvent _) {}
  void noopPointerUp(PointerUpEvent _) {}
  void noopPointerCancel(PointerCancelEvent _) {}
  void noopTogglePlay() {}

  Duration? noDuration() => null;
  double defaultFrameRate() => 30;

  /// 默认画面矩形（观看态整屏 800×600）：稳定 tear-off，参与输入判等。
  Rect defaultPictureRect() => const Rect.fromLTWH(0, 0, 800, 600);

  Widget mount(PictureLayerInput input) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: PictureLayer(input: input)),
    ),
  );

  /// 构造画面层输入；只覆盖本用例关心的事实，其余取观看态默认。
  PictureLayerInput buildInput({
    FaceDirection direction = FaceDirection.original,
    double? aspectRatio = 16 / 9,
    Widget Function()? surfaceBuilder,
    EditorSkeleton? skeleton,
    double systemTopInset = 0,
    bool compareActive = false,
    bool framingActive = false,
    Widget? practiceSurface,
    GestureFeedbackController? feedback,
    ValueNotifier<Duration>? scrubTarget,
    Duration? Function()? durationOf,
    double Function()? frameRateOf,
    Rect Function()? pictureRectOf,
    bool isPlaying = false,
    bool opened = true,
    bool openFailed = false,
    VoidCallback? onTogglePlay,
    Widget prepCenterNumber = const SizedBox.shrink(),
    Widget doubleSpeedBadge = const SizedBox.shrink(),
    Widget? pictureOverride,
    GestureScaleStartCallback? onScaleStart,
  }) => PictureLayerInput(
    face: PictureFaceInput(source: direction),
    video: PictureVideoInput(
      aspectRatio: aspectRatio,
      surfaceBuilder:
          surfaceBuilder ??
          () => VideoSurfacePlaceholder(videoAspectRatio: aspectRatio),
    ),
    frame: PictureFrameInput(
      skeleton: skeleton,
      systemTopInset: systemTopInset,
      compareActive: compareActive,
      framingActive: framingActive,
    ),
    practice: PicturePracticeInput(surface: practiceSurface),
    feedback: PictureFeedbackInput(
      controller: feedback ?? defaultFeedback,
      scrubTarget: scrubTarget ?? defaultScrubTarget,
      durationOf: durationOf ?? noDuration,
      frameRateOf: frameRateOf ?? defaultFrameRate,
      pictureRectOf: pictureRectOf ?? defaultPictureRect,
    ),
    playback: PicturePlaybackInput(
      isPlaying: isPlaying,
      opened: opened,
      openFailed: openFailed,
      onTogglePlay: onTogglePlay ?? noopTogglePlay,
    ),
    gesture: PictureGestureInput(
      doubleTapRecognizer: doubleTap,
      longPressRecognizer: longPress,
      onScaleStart: onScaleStart ?? noopScaleStart,
      onScaleUpdate: noopScaleUpdate,
      onScaleEnd: noopScaleEnd,
      onPointerDown: noopPointerDown,
      onPointerUp: noopPointerUp,
      onPointerCancel: noopPointerCancel,
    ),
    prepCenterNumber: prepCenterNumber,
    doubleSpeedBadge: doubleSpeedBadge,
    pictureOverride: pictureOverride,
  );

  group('画面件方向（源视频面）', () {
    testWidgets('原相：画面件不做水平翻转', (tester) async {
      await tester.pumpWidget(mount(buildInput()));
      expect(find.byKey(const Key('mirrored_surface')), findsNothing);
      expect(find.byKey(videoSurfacePlaceholderKey), findsOneWidget);
    });

    testWidgets('镜像：画面件套水平 Transform（scaleX = -1）', (tester) async {
      await tester.pumpWidget(
        mount(buildInput(direction: FaceDirection.mirrored)),
      );
      final transform = find.byKey(const Key('mirrored_surface'));
      expect(transform, findsOneWidget);
      expect(tester.widget<Transform>(transform).transform.storage[0], -1);
    });
  });

  group('画面区覆盖件', () {
    testWidgets('覆盖件取代源画面：源画面件不构造、播放大图标不出现', (tester) async {
      var surfaceCalls = 0;
      await tester.pumpWidget(
        mount(
          buildInput(
            // 暂停态（默认）：无覆盖件时这一档本该画出播放大图标。
            surfaceBuilder: () {
              surfaceCalls++;
              return const SizedBox.shrink();
            },
            pictureOverride: const ColoredBox(
              key: Key('picture_override'),
              color: Colors.black,
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('picture_override')), findsOneWidget);
      expect(surfaceCalls, 0, reason: '覆盖件在场时源画面件不构造（源片不上屏）');
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });

    testWidgets('无覆盖件：源画面件照旧、暂停时播放大图标在场', (tester) async {
      await tester.pumpWidget(mount(buildInput()));
      expect(find.byKey(videoSurfacePlaceholderKey), findsOneWidget);
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('覆盖件不吃触摸：点按仍落到底层手势层', (tester) async {
      var scaleStarts = 0;
      await tester.pumpWidget(
        mount(
          buildInput(
            onScaleStart: (_) => scaleStarts++,
            pictureOverride: const ColoredBox(color: Colors.black),
          ),
        ),
      );

      await tester.drag(
        find.byKey(const Key('player_surface')),
        const Offset(40, 0),
      );
      await tester.pump();
      expect(scaleStarts, greaterThan(0), reason: '覆盖件不拦截其下那条手势面');
    });
  });

  group('宽高比与退化', () {
    testWidgets('宽高比已知：画面按 contain 收窄（横屏 9:16 左右留黑）', (tester) async {
      tester.view.physicalSize = const Size(
        800,
        400,
      ); // 合成档 800.0×400.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(mount(buildInput(aspectRatio: 9 / 16)));
      final size = tester.getSize(find.byKey(videoSurfacePlaceholderKey));
      expect(size.height, 400);
      expect(size.width, closeTo(225, 0.5));
    });

    testWidgets('竖屏屏幕下竖屏视频按宽铺满、上下留黑', (tester) async {
      tester.view.physicalSize = const Size(
        400,
        800,
      ); // 合成档 400.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(mount(buildInput(aspectRatio: 9 / 16)));
      final size = tester.getSize(find.byKey(videoSurfacePlaceholderKey));
      expect(size.width, 400);
      expect(size.height, closeTo(400 / (9 / 16), 0.5));
    });

    testWidgets('宽高比未知：画面填满可用区域（内核自行 contain）', (tester) async {
      tester.view.physicalSize = const Size(
        800,
        400,
      ); // 合成档 800.0×400.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(mount(buildInput(aspectRatio: null)));
      final size = tester.getSize(find.byKey(videoSurfacePlaceholderKey));
      expect(size, const Size(800, 400));
    });
  });

  group('骨架分配（画面落位）', () {
    testWidgets('贴底：画面带宽 = 骨架给高，顶 = 系统栏 + 顶栏 + 骨架带顶（未调过取景 = 贴底画面带）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(
        800,
        400,
      ); // 合成档 800.0×400.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        mount(
          buildInput(
            // 8:1 源与骨架自洽：满宽 contain 高 100 = 画面带（800 ÷ 8）。
            aspectRatio: 8.0,
            skeleton: stickSkeleton,
            systemTopInset: 24,
          ),
        ),
      );
      final surface = find.byKey(videoSurfacePlaceholderKey);
      expect(tester.getSize(surface).height, 100);
      expect(
        tester.getTopLeft(surface).dy,
        stickSkeleton.bandTopIn(systemTopInset: 24),
      );
    });

    testWidgets('背景位骨架：画面走整屏 contain，不落带', (tester) async {
      tester.view.physicalSize = const Size(
        800,
        400,
      ); // 合成档 800.0×400.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        mount(buildInput(aspectRatio: 1.0, skeleton: backgroundSkeleton)),
      );
      final size = tester.getSize(find.byKey(videoSurfacePlaceholderKey));
      expect(size, const Size(400, 400));
    });
  });

  group('对比态取景（分屏）', () {
    testWidgets('对比态：上下分屏、两侧半区；练习面内容件摆进练习半区', (tester) async {
      tester.view.physicalSize = const Size(
        400,
        800,
      ); // 合成档 400.0×800.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        mount(
          buildInput(
            compareActive: true,
            framingActive: true,
            practiceSurface: const ColoredBox(
              key: Key('practice_surface_probe'),
              color: Color(0xFF112233),
            ),
          ),
        ),
      );
      expect(find.byType(CompareVideoSplit), findsOneWidget);
      // 取景只有源画面一份——源半区挂取景应用件，练习半区直接摆
      // 练习面内容件（恒 contain），不挂任何取景件。
      expect(find.byType(FramingSelectionView), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(const Key('practice_surface_probe')),
          matching: find.byType(FramingSelectionView),
        ),
        findsNothing,
      );
    });

    testWidgets('无练习面：对比态练习半区为空件，不崩溃', (tester) async {
      await tester.pumpWidget(
        mount(buildInput(compareActive: true, practiceSurface: null)),
      );
      expect(find.byType(CompareVideoSplit), findsOneWidget);
      expect(find.byKey(const Key('practice_surface_probe')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('非对比态:不分屏、不挂练习面', (tester) async {
      await tester.pumpWidget(
        mount(
          buildInput(
            practiceSurface: const SizedBox(key: Key('practice_surface_probe')),
          ),
        ),
      );
      expect(find.byType(CompareVideoSplit), findsNothing);
      expect(find.byKey(const Key('practice_surface_probe')), findsNothing);
    });
  });

  group('反馈浮层气泡底', () {
    Future<Size> mountScrubbing(
      WidgetTester tester, {
      Size screenSize = const Size(800, 600),
      double textScale = 1.0,
      Duration? Function()? durationOf = tenSeconds,
    }) async {
      tester.view.physicalSize = screenSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final feedback = GestureFeedbackController();
      final target = ValueNotifier<Duration>(const Duration(seconds: 5));
      addTearDown(feedback.dispose);
      addTearDown(target.dispose);
      feedback.beginScrubbing();
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: screenSize,
            textScaler: TextScaler.linear(textScale),
          ),
          child: mount(
            buildInput(
              feedback: feedback,
              scrubTarget: target,
              durationOf: durationOf,
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('scrub_indicator_bubble')));
    }

    Container bubbleContainer(WidgetTester tester) => tester.widget(
      find
          .ancestor(
            of: find.byKey(const Key('scrub_indicator_bar')),
            matching: find.byKey(const Key('scrub_indicator_bubble')),
          )
          .first,
    );

    testWidgets('三行内容同住一个半透明深色胶囊：底/圆角/内边距按定稿', (tester) async {
      await mountScrubbing(tester);

      final container = bubbleContainer(tester);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0x99000000));
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(
        container.padding,
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );
      // 时间文本与提示文案都在同一个气泡内。
      final bubbleRect = tester.getRect(
        find.byKey(const Key('scrub_indicator_bubble')),
      );
      expect(
        bubbleRect.top,
        lessThanOrEqualTo(tester.getCenter(find.textContaining('/')).dy),
      );
      expect(
        bubbleRect.bottom,
        greaterThanOrEqualTo(tester.getCenter(find.textContaining('/')).dy),
      );
      final hintCenter = tester.getCenter(find.text(kScrubCancelHintText));
      expect(bubbleRect.top, lessThanOrEqualTo(hintCenter.dy));
      expect(bubbleRect.bottom, greaterThanOrEqualTo(hintCenter.dy));
    });

    testWidgets('气泡宽度由内容撑开；条仍占屏宽 60%', (tester) async {
      await mountScrubbing(tester);

      final bar = tester.getSize(find.byKey(const Key('scrub_indicator_bar')));
      expect(bar.width, closeTo(800 * 0.6, 0.5));
      final bubble = tester.getSize(
        find.byKey(const Key('scrub_indicator_bubble')),
      );
      // 24 = 气泡水平内边距 12 × 2（与胶囊内边距断言同源）。
      expect(bubble.width, closeTo(bar.width + 12 * 2, 0.5));
    });

    testWidgets('窄屏大字号：提示文案单行、无省略号，气泡不超屏', (tester) async {
      await mountScrubbing(
        tester,
        textScale: 1.6,
        screenSize: const Size(360, 640),
      );

      final hint = tester.getSize(find.text(kScrubCancelHintText));
      // 单行：行高 = 字号 × scale × 行高倍数（1.4，Material 默认），两行会翻倍。
      expect(hint.height, lessThan(12 * 1.6 * 1.4 * 2));
      final bubble = tester.getSize(
        find.byKey(const Key('scrub_indicator_bubble')),
      );
      expect(bubble.width, lessThanOrEqualTo(360));
      // 提示文案完整渲染在气泡内（不截断、不省略）。
      final hintRect = tester.getRect(find.text(kScrubCancelHintText));
      final bubbleRect = tester.getRect(
        find.byKey(const Key('scrub_indicator_bubble')),
      );
      expect(hintRect.right, lessThanOrEqualTo(bubbleRect.right - 12 + 0.5));
      expect(hintRect.left, greaterThanOrEqualTo(bubbleRect.left + 12 - 0.5));
    });

    testWidgets('时长未知：气泡仍在，只显示目标时间、无条', (tester) async {
      final bubble = await mountScrubbing(tester, durationOf: noDuration);

      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      expect(find.byKey(const Key('scrub_indicator_bar')), findsNothing);
      expect(find.textContaining('/'), findsNothing);
      expect(bubble.height, greaterThan(0));
    });
  });

  group('反馈层形态（反馈会话空/非空）', () {
    testWidgets('会话空（idle）：不挂任何反馈内容', (tester) async {
      await tester.pumpWidget(mount(buildInput()));
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      expect(find.byKey(const Key('level_adjust_slider')), findsNothing);
    });

    testWidgets('scrubbing：出现迷你条与「目标/总长」，比例按目标/总长', (tester) async {
      final feedback = GestureFeedbackController();
      final target = ValueNotifier<Duration>(const Duration(seconds: 5));
      addTearDown(feedback.dispose);
      addTearDown(target.dispose);
      feedback.beginScrubbing();

      await tester.pumpWidget(
        mount(
          buildInput(
            feedback: feedback,
            scrubTarget: target,
            durationOf: () => const Duration(seconds: 10),
          ),
        ),
      );
      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      expect(find.byKey(const Key('scrub_indicator_bar')), findsOneWidget);
      final fill = tester.getSize(
        find.byKey(const Key('scrub_indicator_fill')),
      );
      final bar = tester.getSize(find.byKey(const Key('scrub_indicator_bar')));
      expect(fill.width, closeTo(bar.width / 2, 0.5));
    });

    testWidgets('时长未知：只显示目标时间，无比例条，不崩溃', (tester) async {
      final feedback = GestureFeedbackController();
      final target = ValueNotifier<Duration>(const Duration(seconds: 5));
      addTearDown(feedback.dispose);
      addTearDown(target.dispose);
      feedback.beginScrubbing();

      await tester.pumpWidget(
        mount(buildInput(feedback: feedback, scrubTarget: target)),
      );
      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      expect(find.byKey(const Key('scrub_indicator_bar')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('levelAdjust：出现音量/亮度滑条', (tester) async {
      final feedback = GestureFeedbackController();
      addTearDown(feedback.dispose);
      feedback.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.5);

      await tester.pumpWidget(mount(buildInput(feedback: feedback)));
      expect(find.byKey(const Key('level_adjust_slider')), findsOneWidget);
      expect(find.byKey(const Key('level_track')), findsOneWidget);
    });
  });

  group('播放指示', () {
    testWidgets('已打开、暂停、无反馈：显示中央播放指示', (tester) async {
      await tester.pumpWidget(mount(buildInput(opened: true)));
      expect(find.byKey(const Key('play_indicator')), findsOneWidget);
    });

    testWidgets('播放中 / 打开失败 / 未打开：不显示播放指示', (tester) async {
      await tester.pumpWidget(mount(buildInput(isPlaying: true)));
      expect(find.byKey(const Key('play_indicator')), findsNothing);

      await tester.pumpWidget(mount(buildInput(openFailed: true)));
      expect(find.byKey(const Key('play_indicator')), findsNothing);

      await tester.pumpWidget(mount(buildInput(opened: false)));
      expect(find.byKey(const Key('play_indicator')), findsNothing);
    });
  });

  group('输入值等值重建纪律', () {
    testWidgets('输入值不变：不重建画面件（surfaceBuilder 不再被调用）', (tester) async {
      var calls = 0;
      Widget surface() {
        calls++;
        return const VideoSurfacePlaceholder(videoAspectRatio: 1);
      }

      await tester.pumpWidget(mount(buildInput(surfaceBuilder: surface)));
      expect(calls, 1);
      await tester.pumpWidget(mount(buildInput(surfaceBuilder: surface)));
      expect(calls, 1, reason: '输入值相等 → 该层不重建子树');
    });

    testWidgets('输入值变化：该层重建（surfaceBuilder 再次被调用）', (tester) async {
      var calls = 0;
      Widget surface() {
        calls++;
        return const VideoSurfacePlaceholder(videoAspectRatio: 1);
      }

      await tester.pumpWidget(mount(buildInput(surfaceBuilder: surface)));
      expect(calls, 1);
      await tester.pumpWidget(
        mount(
          buildInput(
            surfaceBuilder: surface,
            direction: FaceDirection.mirrored,
          ),
        ),
      );
      expect(calls, 2, reason: '画面方向变化 → 该层重建');
    });

    test('输入值对象按内容判等：每个字段都参与判等', () {
      Widget surface() => const VideoSurfacePlaceholder(videoAspectRatio: 1);
      PictureLayerInput base() => buildInput(surfaceBuilder: surface);
      const probe = SizedBox(key: Key('overlay_probe'), width: 1);
      final otherFeedback = GestureFeedbackController();
      final otherTarget = ValueNotifier(Duration.zero);
      final otherDoubleTap = PlayerDoubleTapGestureRecognizer();
      addTearDown(otherFeedback.dispose);
      addTearDown(otherTarget.dispose);
      addTearDown(otherDoubleTap.dispose);
      Duration? otherDuration() => const Duration(seconds: 9);

      expect(base(), base());
      for (final (label, changed) in <(String, PictureLayerInput)>[
        (
          'face.source',
          buildInput(
            surfaceBuilder: surface,
            direction: FaceDirection.mirrored,
          ),
        ),
        (
          'video.aspectRatio',
          buildInput(surfaceBuilder: surface, aspectRatio: 4 / 3),
        ),
        (
          'frame.skeleton',
          buildInput(surfaceBuilder: surface, skeleton: stickSkeleton),
        ),
        (
          'frame.systemTopInset',
          buildInput(surfaceBuilder: surface, systemTopInset: 24),
        ),
        (
          'frame.compareActive',
          buildInput(surfaceBuilder: surface, compareActive: true),
        ),
        (
          'frame.framingActive',
          buildInput(surfaceBuilder: surface, framingActive: true),
        ),
        (
          'practice.surface',
          buildInput(surfaceBuilder: surface, practiceSurface: probe),
        ),
        (
          'feedback.controller',
          buildInput(surfaceBuilder: surface, feedback: otherFeedback),
        ),
        (
          'feedback.scrubTarget',
          buildInput(surfaceBuilder: surface, scrubTarget: otherTarget),
        ),
        (
          'feedback.pictureRectOf',
          buildInput(
            surfaceBuilder: surface,
            pictureRectOf: () => const Rect.fromLTWH(10, 10, 100, 50),
          ),
        ),
        (
          'feedback.durationOf',
          buildInput(surfaceBuilder: surface, durationOf: otherDuration),
        ),
        (
          'playback.isPlaying',
          buildInput(surfaceBuilder: surface, isPlaying: true),
        ),
        ('playback.opened', buildInput(surfaceBuilder: surface, opened: false)),
        (
          'playback.openFailed',
          buildInput(surfaceBuilder: surface, openFailed: true),
        ),
        (
          'playback.onTogglePlay',
          buildInput(surfaceBuilder: surface, onTogglePlay: () {}),
        ),
        (
          'prepCenterNumber',
          buildInput(surfaceBuilder: surface, prepCenterNumber: probe),
        ),
        (
          'doubleSpeedBadge',
          buildInput(surfaceBuilder: surface, doubleSpeedBadge: probe),
        ),
        (
          'pictureOverride',
          buildInput(surfaceBuilder: surface, pictureOverride: probe),
        ),
      ]) {
        expect(changed, isNot(base()), reason: '$label 变化必须让输入值对象判不等');
      }

      // 手势层件也参与判等：换一个识别器实例即判不等。
      final swapped = PictureGestureInput(
        doubleTapRecognizer: otherDoubleTap,
        longPressRecognizer: longPress,
        onScaleStart: noopScaleStart,
        onScaleUpdate: noopScaleUpdate,
        onScaleEnd: noopScaleEnd,
        onPointerDown: noopPointerDown,
        onPointerUp: noopPointerUp,
        onPointerCancel: noopPointerCancel,
      );
      expect(
        buildInput(surfaceBuilder: surface).gesture,
        isNot(swapped),
        reason: 'gesture.doubleTapRecognizer 变化必须让输入值对象判不等',
      );
    });
  });

  group('取消区标记', () {
    testWidgets('scrubbing 期间画面左上角画出四分之一圆弧标记与「取消」', (tester) async {
      final feedback = GestureFeedbackController();
      feedback.beginScrubbing();
      await tester.pumpWidget(
        mount(
          buildInput(
            feedback: feedback,
            pictureRectOf: () => const Rect.fromLTWH(20, 40, 300, 200),
          ),
        ),
      );
      expect(find.byKey(const Key('scrub_cancel_mark')), findsOneWidget);
      // 标记落点 = 画面矩形左上角，尺寸 = 半径（min(88, 300, 200) = 88）。
      expect(
        tester.getTopLeft(find.byKey(const Key('scrub_cancel_mark'))),
        const Offset(20, 40),
      );
      expect(
        tester.getSize(find.byKey(const Key('scrub_cancel_mark'))),
        const Size(88, 88),
      );
      expect(find.text('取消'), findsOneWidget);
      // 常态提示文案指向画面。
      expect(find.text(kScrubCancelHintText), findsOneWidget);
      expect(kScrubCancelHintText, '拖到画面左上角松开可取消');
    });

    testWidgets('armed：文案换「松开取消」、标记转琥珀（含低透琥珀底）', (tester) async {
      final feedback = GestureFeedbackController();
      feedback.beginScrubbing();
      feedback.setCancelArmed(true);
      await tester.pumpWidget(mount(buildInput(feedback: feedback)));
      expect(find.text(kScrubCancelArmedText), findsOneWidget);
      final mark = find.byKey(const Key('scrub_cancel_mark'));
      expect(mark, findsOneWidget);
      final text = tester.widget<Text>(
        find.descendant(of: mark, matching: find.text('取消')),
      );
      expect(text.style!.color, kHighlightAmber);
    });

    testWidgets('取消标记是纯装饰：弧与「取消」小字不进无障碍树', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      final feedback = GestureFeedbackController();
      feedback.beginScrubbing();
      await tester.pumpWidget(
        mount(
          buildInput(
            feedback: feedback,
            pictureRectOf: () => const Rect.fromLTWH(20, 40, 300, 200),
          ),
        ),
      );
      // 视觉仍在，但读屏不会把这个「取消」当作独立语义读出。
      expect(find.text('取消'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^取消$', multiLine: true)),
        findsNothing,
        reason: '弧内小字是纯装饰，不单独进无障碍树',
      );
      semanticsHandle.dispose();
    });

    testWidgets('画面矩形变化：标记落点跟随重算', (tester) async {
      final feedback = GestureFeedbackController();
      feedback.beginScrubbing();
      await tester.pumpWidget(
        mount(
          buildInput(
            feedback: feedback,
            pictureRectOf: () => const Rect.fromLTWH(20, 40, 300, 200),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('scrub_cancel_mark'))),
        const Offset(20, 40),
      );
      await tester.pumpWidget(
        mount(
          buildInput(
            feedback: feedback,
            pictureRectOf: () => const Rect.fromLTWH(0, 120, 200, 100),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('scrub_cancel_mark'))),
        const Offset(0, 120),
        reason: '矩形变化（旋转屏幕 / 开合控制层）时标记按同一条规则重算落点',
      );
    });

    testWidgets('扁画面：标记尺寸随半径收缩', (tester) async {
      final feedback = GestureFeedbackController();
      feedback.beginScrubbing();
      await tester.pumpWidget(
        mount(
          buildInput(
            feedback: feedback,
            pictureRectOf: () => const Rect.fromLTWH(0, 0, 400, 50),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('scrub_cancel_mark'))),
        const Size(50, 50),
      );
    });
  });

  group('画面播放开关：语义与键盘', () {
    const switchKey = Key('picture_play_switch');

    testWidgets('暂停态：报「播放画面」按钮，激活后状态翻转', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        mount(buildInput(isPlaying: false, onTogglePlay: () => toggles++)),
      );

      expectButtonSemantics(tester, switchKey, label: '播放画面', enabled: true);
      semanticsOfKey(tester, switchKey).properties.onTap!();
      expect(toggles, 1, reason: '语义激活走同一条播放/暂停写入口');
    });

    testWidgets('播放态：报「暂停画面」按钮', (tester) async {
      await tester.pumpWidget(mount(buildInput(isPlaying: true)));
      expectButtonSemantics(tester, switchKey, label: '暂停画面', enabled: true);
    });

    testWidgets('未打开 / 打开失败：按钮不可点、不产生激活动作', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        mount(buildInput(opened: false, onTogglePlay: () => toggles++)),
      );
      expectButtonSemantics(tester, switchKey, enabled: false);
      expect(semanticsOfKey(tester, switchKey).properties.onTap, isNull);

      await tester.pumpWidget(
        mount(buildInput(openFailed: true, onTogglePlay: () => toggles++)),
      );
      expectButtonSemantics(tester, switchKey, enabled: false);
      expect(semanticsOfKey(tester, switchKey).properties.onTap, isNull);
      expect(toggles, 0);
    });

    testWidgets('键盘：Tab 走到播放开关，空格与回车都能翻转播放态', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(mount(buildInput(onTogglePlay: () => toggles++)));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(toggles, 1, reason: '空格激活播放开关');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(toggles, 2, reason: '回车激活播放开关');
    });

    testWidgets('键盘：未打开时按键不产生动作', (tester) async {
      var toggles = 0;
      await tester.pumpWidget(
        mount(buildInput(opened: false, onTogglePlay: () => toggles++)),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(toggles, 0);
    });

    testWidgets('焦点可见：落焦时画出焦点描边、失焦后撤下', (tester) async {
      await tester.pumpWidget(mount(buildInput()));
      expect(find.byKey(const Key('picture_focus_ring')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(find.byKey(const Key('picture_focus_ring')), findsOneWidget);

      tester.binding.focusManager.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('picture_focus_ring')), findsNothing);
    });
  });
}
