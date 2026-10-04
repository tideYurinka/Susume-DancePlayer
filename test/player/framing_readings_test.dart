/// 落位与读数按选区：取景生效后全仓的
/// 「画面矩形／画面宽高比」读数换成**选区内容**——竖屏编辑态落位、备注贴纸、
/// 局部镜像标识、取消区、循环提示卡都落到取景后的画面上；数拍浮层与视频区
/// 正中大数字按播放页视口、不受影响；未调过时各读数与改动前逐像素一致。
///
/// 缝 3（播放页）：只断言外部可得的面——画面件的落位盒、贴纸渲染矩形、
/// 标识矩形、取消标记落点、提示卡落点与数拍浮层矩形。
library;

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        localMirrorFragmentsProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/compare_framing_view.dart'
    show compareFramingPictureRect;
import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowId, TrackRowTable;
import 'package:dance_learning_app/player/framing_selection_view.dart'
    show FramingSelectionView;
import 'package:dance_learning_app/player/framing_session_state.dart'
    show framingStateProvider;
import 'package:dance_learning_app/player/framing_stage.dart'
    show singlePictureFramedPictureRectOnScreen;
import 'package:dance_learning_app/player/local_mirror_picture_mark.dart'
    show kLocalMirrorPictureMarkKey;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show MetronomeOverlay;
import 'package:dance_learning_app/player/note_sticker_overlay.dart'
    show NoteStickerText;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart'
    show hangingBeatPipeline, turnBeatAnimationOn;
import '../helpers/device_viewport.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';

void main() {
  /// 真机竖屏基准（compact 档 1264×2736 @3.5 = 361.1×781.7dp）。
  const screen = Size(361.1, 781.7);

  /// 紧凑档真机基准下两轨皆空：空备注轨与空局部镜像轨不占行，整带高 =
  /// 剪裁后逐行行高之和 + 行间间隙（全行集见 [TrackRowTable.normal]）；
  /// 画面区因此比常驻空轨时更高。
  final trackBandHeight = TrackRowTable.normal.withoutRows(const {
    TrackRowId.note,
    TrackRowId.localMirror,
  }).totalHeight;

  /// 真机竖屏编辑态骨架（源 16:9）未取景的落位：画面区 351.7、带 203.12。
  final unframedSkeleton = editorSkeletonFor(
    screen: screen,
    trackBandHeight: trackBandHeight,
    videoAspectRatio: 16 / 9,
  );

  /// 选区更「高」（宽 0.5、高 0.6 → 内容比 ≈ 1.4815）。
  const tallSelection = FramingSelection(
    left: 0.25,
    top: 0.2,
    right: 0.75,
    bottom: 0.8,
  );

  /// 选区更「宽」（宽 0.8、高 0.4 → 内容比 ≈ 3.556）。
  const wideSelection = FramingSelection(
    left: 0.1,
    top: 0.3,
    right: 0.9,
    bottom: 0.7,
  );

  /// 选区放不进画面区（宽 0.5、高 1 → 内容比 ≈ 0.889、满宽 contain ≈ 406）。
  const tooTallSelection = FramingSelection(
    left: 0.25,
    top: 0,
    right: 0.75,
    bottom: 1,
  );

  /// 左半区（内容比 = 源比 ÷ 2、观看看态下高充满、左右留黑）。
  const leftHalfSelection = FramingSelection(
    left: 0,
    top: 0,
    right: 0.5,
    bottom: 1,
  );

  late FakePlaybackEngine engine;

  Future<ProviderContainer> pumpPlayer(WidgetTester tester) async {
    engine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 16 / 9,
    );
    final source = Uri.file('/videos/a.mp4');
    final docStorage = InMemoryVideoDocumentStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
  }

  Future<void> applyFraming(
    WidgetTester tester,
    ProviderContainer container,
    FramingSelection selection,
  ) async {
    container.read(framingStateProvider.notifier).applySource(selection);
    await tester.pumpAndSettle();
  }

  /// 进编辑态（展开控制层）。
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
  }

  setUp(() {});

  group('竖屏编辑态落位按选区', () {
    testWidgets('更「高」的选区：盒高封顶在未取景画面矩形高、顶边不上移', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      await openEditor(tester);

      final unframed = tester.getRect(find.byType(FramingSelectionView));
      expect(
        unframed.top,
        closeTo(52 + unframedSkeleton.pictureBandTop, 0.05),
        reason: '未取景：贴底画面带',
      );
      expect(
        unframed.height,
        closeTo(unframedSkeleton.pictureBandHeight, 0.05),
      );

      await applyFraming(tester, container, tallSelection);
      final framed = tester.getRect(find.byType(FramingSelectionView));
      expect(
        framed.height,
        closeTo(unframed.height, 0.05),
        reason: '盒高封顶在未取景时的画面矩形高',
      );
      expect(framed.top, closeTo(unframed.top, 0.05), reason: '画面顶边不上移');
      expect(
        framed.bottom,
        closeTo(52 + unframedSkeleton.pictureAreaHeight, 0.05),
        reason: '底边仍贴画面区下缘',
      );
    });

    testWidgets('更「宽」的选区：带更矮、底边仍贴画面区下缘', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      await openEditor(tester);

      await applyFraming(tester, container, wideSelection);
      final framed = tester.getRect(find.byType(FramingSelectionView));
      final expectedHeight =
          screen.width / wideSelection.contentAspectRatio(16 / 9);
      expect(framed.height, closeTo(expectedHeight, 0.05));
      expect(framed.height, lessThan(unframedSkeleton.pictureBandHeight));
      expect(
        framed.bottom,
        closeTo(52 + unframedSkeleton.pictureAreaHeight, 0.05),
      );
    });

    testWidgets('放不进的选区：走观看态背景位（画面件铺满整屏、不再落带）', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      await openEditor(tester);

      await applyFraming(tester, container, tooTallSelection);
      final framed = tester.getRect(find.byType(FramingSelectionView));
      expect(framed.height, closeTo(screen.height, 0.05));
      expect(framed.width, closeTo(screen.width, 0.05));
    });
  });

  group('备注贴纸按选区窗口落位', () {
    const noteText = '注意手';

    Future<ProviderContainer> pumpWithNote(
      WidgetTester tester, {
      required NoteGeometry geometry,
    }) async {
      final container = await pumpPlayer(tester);
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            AnnotationRestoreDocument(
              notes: [
                NoteSticker(
                  startMs: 0,
                  endMs: 30000,
                  text: noteText,
                  geometry: geometry,
                ),
              ],
            ),
          );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('钉住内容：源点按选区窗口换算后落在取景后的画面上', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpWithNote(
        tester,
        // 左半区选区的正中心。
        geometry: const NoteGeometry(centerX: 0.25, centerY: 0.5),
      );

      final before = tester.getRect(find.byType(NoteStickerText));
      await applyFraming(tester, container, leftHalfSelection);

      final contentRect = singlePictureFramedPictureRectOnScreen(
        screen: screen,
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: leftHalfSelection,
      )!;
      final after = tester.getRect(find.byType(NoteStickerText));
      expect(after.center.dx, closeTo(contentRect.center.dx, 0.5));
      expect(after.center.dy, closeTo(contentRect.center.dy, 0.5));
      expect(
        after.width,
        closeTo(before.width, 0.5),
        reason: '屏幕尺寸（基准字号 × 系数）不随取景缩放',
      );
      expect(after.height, closeTo(before.height, 0.5));
    });

    testWidgets('标的源点被取景裁掉：钳在取景后的画面边缘、不隐藏', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpWithNote(
        tester,
        geometry: const NoteGeometry(centerX: 0.9, centerY: 0.5),
      );
      await applyFraming(tester, container, leftHalfSelection);

      final contentRect = singlePictureFramedPictureRectOnScreen(
        screen: screen,
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: leftHalfSelection,
      )!;
      final sticker = tester.getRect(find.byType(NoteStickerText));
      expect(find.byType(NoteStickerText), findsOneWidget, reason: '不隐藏');
      expect(sticker.right, lessThanOrEqualTo(contentRect.right + 0.5));
      expect(sticker.left, greaterThanOrEqualTo(contentRect.left - 0.5));
    });

    testWidgets('未调过：贴纸读数与改动前一致（对照回归）', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      await pumpWithNote(
        tester,
        geometry: const NoteGeometry(centerX: 0.3, centerY: 0.4),
      );
      final unframed = tester.getRect(find.byType(NoteStickerText));
      // 观看看态整屏 contain 画面矩形里按源点映射（无窗口换算）。
      final picture = singlePictureFramedPictureRectOnScreen(
        screen: screen,
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: null,
      )!;
      expect(
        unframed.center.dx,
        closeTo(picture.left + 0.3 * picture.width, 0.5),
      );
      expect(
        unframed.center.dy,
        closeTo(picture.top + 0.4 * picture.height, 0.5),
      );
    });
  });

  group('画面几何读数按取景后的画面矩形', () {
    testWidgets('取消区标记落在取景后的画面左上角', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      await applyFraming(tester, container, leftHalfSelection);

      // 横向拖动 = 进度拖动；取消标记常显于画面矩形左上角。
      final gesture = await tester.startGesture(const Offset(180, 400));
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(18, 0));
        await tester.pump();
      }
      await tester.pump();

      final contentRect = singlePictureFramedPictureRectOnScreen(
        screen: screen,
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: leftHalfSelection,
      )!;
      final mark = find.byKey(const Key('scrub_cancel_mark'));
      expect(mark, findsOneWidget);
      expect(
        tester.getTopLeft(mark),
        offsetMoreOrLessEquals(contentRect.topLeft, epsilon: 0.5),
      );
      final radius = contentRect.width < contentRect.height
          ? contentRect.width
          : contentRect.height;
      final markSize = tester.getSize(mark);
      final capped = radius < kScrubCancelZoneSize
          ? radius
          : kScrubCancelZoneSize;
      expect(markSize.width, closeTo(capped, 0.5));
      expect(markSize.height, closeTo(capped, 0.5));
      await gesture.up();
    });

    testWidgets('局部镜像标识贴取景后的画面矩形', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      final outcome = container
          .read(annotationEditorProvider)
          .submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;
      await engine.pause();
      await engine.seek(Duration(milliseconds: fragment.startMs + 10));
      await tester.pumpAndSettle();

      await applyFraming(tester, container, leftHalfSelection);

      final contentRect = singlePictureFramedPictureRectOnScreen(
        screen: screen,
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: leftHalfSelection,
      )!;
      final mark = tester.getRect(find.byKey(kLocalMirrorPictureMarkKey));
      expect(mark.left, closeTo(contentRect.left, 0.5));
      expect(mark.top, closeTo(contentRect.top, 0.5));
      expect(mark.width, closeTo(contentRect.width, 0.5));
      expect(mark.height, closeTo(contentRect.height, 0.5));
    });

    testWidgets('对比源侧同口径：标识贴源半区取景后的画面矩形', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      final outcome = container
          .read(annotationEditorProvider)
          .submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)));
      expect(outcome.applied, isTrue);
      final fragment = container.read(localMirrorFragmentsProvider).single;

      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      await engine.pause();
      await engine.seek(Duration(milliseconds: fragment.startMs + 10));
      await tester.pumpAndSettle();

      await applyFraming(tester, container, leftHalfSelection);

      final paneRect = compareFramingPictureRect(
        screen: screen,
        landscape: false,
        aspectRatio: 16 / 9,
        selection: leftHalfSelection,
      );
      final mark = tester.getRect(find.byKey(kLocalMirrorPictureMarkKey));
      expect(mark.left, closeTo(paneRect.left, 0.5));
      expect(mark.top, closeTo(paneRect.top, 0.5));
      expect(mark.width, closeTo(paneRect.width, 0.5));
      expect(mark.height, closeTo(paneRect.height, 0.5));
    });

    testWidgets('循环提示卡锚在取景后的画面左下角', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      await applyFraming(tester, container, leftHalfSelection);

      // 播放到尾 → 左下角循环提示卡。
      await tester.pump(const Duration(seconds: 31));
      final card = find.byKey(const Key('loop_prompt'));
      expect(card, findsOneWidget);

      final contentRect = singlePictureFramedPictureRectOnScreen(
        screen: screen,
        systemTopInset: 0,
        skeleton: null,
        aspectRatio: 16 / 9,
        selection: leftHalfSelection,
      )!;
      final rect = tester.getRect(card);
      // 未调过时卡贴画面左下角内缩 24dp；让路带（底 44）可能把底边推出。
      expect(rect.left, greaterThanOrEqualTo(contentRect.left));
      expect(
        rect.left,
        closeTo(contentRect.left + 24, 0.5),
        reason: '卡横向贴取景后的画面左缘',
      );
    });
  });

  group('对比源侧半区同口径', () {
    Future<ProviderContainer> pumpCompareWithNote(WidgetTester tester) async {
      final container = await pumpPlayer(tester);
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            AnnotationRestoreDocument(
              notes: const [
                NoteSticker(
                  startMs: 0,
                  endMs: 30000,
                  text: '注意手',
                  geometry: NoteGeometry(centerX: 0.5, centerY: 0.5),
                ),
              ],
            ),
          );
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareWatching);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      return container;
    }

    Rect sourcePanePicture(FramingSelection? selection) =>
        compareFramingPictureRect(
          screen: screen,
          landscape: false,
          aspectRatio: 16 / 9,
          selection: selection,
        );

    testWidgets('未调过：贴纸贴在源半区的画面矩形里（不落到整屏 contain）', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      await pumpCompareWithNote(tester);

      final panePicture = sourcePanePicture(null);
      final sticker = tester.getRect(find.byType(NoteStickerText));
      expect(sticker.center.dx, closeTo(panePicture.center.dx, 0.5));
      expect(sticker.center.dy, closeTo(panePicture.center.dy, 0.5));
      // 整屏 contain 的中心在屏幕正中；源半区画面的中心远在其上。
      expect(
        panePicture.center.dy,
        lessThan(screen.height / 2 - 100),
        reason: '源半区画面矩形不是整屏 contain',
      );
    });

    testWidgets('未调过与「选区恰好覆盖整帧」在显示上不可区分', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpCompareWithNote(tester);

      final unframed = tester.getRect(find.byType(NoteStickerText));
      await applyFraming(tester, container, const FramingSelection.fullFrame());
      final fullFrame = tester.getRect(find.byType(NoteStickerText));
      expect(fullFrame, unframed, reason: '整帧选区与未调过同一份显示');
    });
  });

  group('不随取景变（对照断言）', () {
    testWidgets('数拍浮层几何按播放页视口、取景前后不变', (tester) async {
      useNamedViewport(tester, ViewportTier.compact);
      final container = await pumpPlayer(tester);
      turnBeatAnimationOn(tester);
      await tester.pumpAndSettle();
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      final before = tester.getRect(find.byType(MetronomeOverlay));

      await applyFraming(tester, container, leftHalfSelection);
      expect(find.byType(MetronomeOverlay), findsOneWidget);
      final after = tester.getRect(find.byType(MetronomeOverlay));
      expect(after, before, reason: '数拍浮层按播放页视口，不随取景变');
    });
  });
}
