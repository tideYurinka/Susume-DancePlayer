import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/control_layer.dart'
    show kPortraitRotateButtonHitKey, kPortraitRotateButtonKey;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetMinSize;
import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/player/speed_bubble.dart'
    show SpeedBubble, SpeedBubbleMode, speedBubbleSessionProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart' show hangingBeatPipeline;
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/semantics_assertions.dart';

/// 竖屏编辑面转屏钮：动作「转为横屏」的无字图标，长在**画面区**右下角
/// （字形 24dp、视觉圆底 36dp、内缩 8dp；命中盒外扩到下限——），位置只看画面区、与画面显示朝向无关。
/// 点一次锁横屏并粘住：此后收起控制层不再发出任何方向请求（粘性来自「此后不
/// 再请求跟随」）。
///
/// 本文件钉**用户可见面**：存在性与显隐门禁（控制层展开、非录制、竖屏屏、
/// 对比态共用）、落位（视觉圆底 36dp、相对画面区右下角内缩 8dp、四角都在画面区
/// 内）、位置与显示朝向无关、点击一次锁横屏、粘性（收起零方向请求）。
void main() {
  /// 测试视口：刻意放宽的**合成档**（非设备基准），实际逻辑尺寸 668 × 1368dp。
  const screen = Size(668.0, 1368.0);

  /// 字形 24dp、视觉圆底 36dp、内缩 8dp。
  const glyphSize = 24.0;
  const touchSize = 36.0;
  const inset = 8.0;

  void setPortraitView(WidgetTester tester, {double topInset = 0}) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = screen * 2.0;
    if (topInset != 0) {
      tester.view.padding = FakeViewPadding(top: topInset * 2.0);
    }
    addTearDown(tester.view.reset);
  }

  Future<FakeSystemUi> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    FakeSystemUi? systemUi,
  }) async {
    final fake = systemUi ?? FakeSystemUi();
    final source = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(fake),
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) =>
                VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  /// 竖屏单击画面唤出控制层（等双击判定窗口过）。
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await pumpPastMarquee(tester);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  Finder rotateButton() => find.byKey(kPortraitRotateButtonKey);

  /// 画面区矩形（屏幕坐标）——与实现同一式子（[portraitPictureAreaRect] +
  /// 组合根口径的骨架分配），不手写坐标。
  Rect pictureAreaFor({
    required double aspectRatio,
    required double trackBandHeight,
    double topInset = 0,
  }) => portraitPictureAreaRect(
    screen: screen,
    systemTopInset: topInset,
    skeleton: editorSkeletonFor(
      // 骨架分配吃的可用高已扣系统栏内缩（组合根口径）。
      screen: Size(screen.width, screen.height - topInset),
      trackBandHeight: trackBandHeight,
      videoAspectRatio: aspectRatio,
    ),
  );

  /// 画面区右下角内缩、视觉圆底 36dp 的期望矩形。
  Rect expectedButtonRect({
    required double aspectRatio,
    required double trackBandHeight,
    double topInset = 0,
  }) => portraitRotateButtonRect(
    pictureArea: pictureAreaFor(
      aspectRatio: aspectRatio,
      trackBandHeight: trackBandHeight,
      topInset: topInset,
    ),
  );

  group('存在性与落位', () {
    testWidgets('竖屏 + 横画面（16:9）：转屏钮在画面区右下角，内缩 8dp、视觉圆底 36dp、字形 24dp', (
      tester,
    ) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      expect(rotateButton(), findsOneWidget);
      final rect = tester.getRect(rotateButton());
      expect(rect.width, touchSize);
      expect(rect.height, touchSize);
      final icon = tester.widget<Icon>(find.byIcon(Icons.screen_rotation));
      expect(icon.size, glyphSize, reason: '字形收小到 24dp');
      final area = pictureAreaFor(
        aspectRatio: 16 / 9,
        trackBandHeight: TrackRowTable.normal.totalHeight,
      );
      expect(
        rect,
        expectedButtonRect(
          aspectRatio: 16 / 9,
          trackBandHeight: TrackRowTable.normal.totalHeight,
        ),
        reason: '锚是画面区右下角、内缩 8dp——与画面显示朝向无关',
      );
      expect(
        rect.center,
        area.bottomRight -
            const Offset(inset + touchSize / 2, inset + touchSize / 2),
        reason: '圆心落在画面区右下角内 26dp 处（外缘内缩 8dp + 视觉圆底 36/2）',
      );
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        expect(area.contains(corner), isTrue, reason: '四角都在画面区内：$corner');
      }
    });

    testWidgets('位置与显示朝向无关：9:16 竖画面落在同一处', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 9 / 16),
      );
      await openEditor(tester);

      expect(rotateButton(), findsOneWidget);
      final rect = tester.getRect(rotateButton());
      expect(
        rect,
        expectedButtonRect(
          aspectRatio: 16 / 9,
          trackBandHeight: TrackRowTable.normal.totalHeight,
        ),
        reason: '横画面算出的角也是竖画面的角：同一枚钮永远在同一个地方',
      );
    });

    testWidgets('四角都在画面区内：不越出画面区下缘（视频播放工具栏两行上缘）', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final rect = tester.getRect(rotateButton());
      final videoToolbar = tester.getRect(
        find.byKey(const Key('control_layer_video_toolbar')),
      );
      expect(rect.bottom, lessThanOrEqualTo(videoToolbar.top));
      expect(rect.right, lessThanOrEqualTo(screen.width));
    });

    testWidgets('顶系统栏内缩非零（号机 39.4dp）：四角仍落在画面区内、视觉圆底 36dp', (tester) async {
      setPortraitView(tester, topInset: 39.4);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final rect = tester.getRect(rotateButton());
      expect(rect.width, touchSize);
      expect(rect.height, touchSize);
      expect(
        rect,
        expectedButtonRect(
          aspectRatio: 16 / 9,
          trackBandHeight: TrackRowTable.normal.totalHeight,
          topInset: 39.4,
        ),
        reason: '锚随系统栏内缩下移，仍在画面区右下角内缩 8dp',
      );
      final area = pictureAreaFor(
        aspectRatio: 16 / 9,
        trackBandHeight: TrackRowTable.normal.totalHeight,
        topInset: 39.4,
      );
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ]) {
        expect(area.contains(corner), isTrue, reason: '四角都在画面区内：$corner');
      }
    });

    testWidgets('命中矩形外扩到通行下限 48：视觉圆底 36 与字形 24 逐位不变、命中盒四角仍在画面区内', (
      tester,
    ) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final hit = tester.getRect(find.byKey(kPortraitRotateButtonHitKey));
      expect(hit.width, kHitTargetMinSize, reason: '命中宽 = 通行下限');
      expect(hit.height, kHitTargetMinSize, reason: '命中高 = 通行下限');
      final rect = tester.getRect(rotateButton());
      expect(
        rect.size,
        const Size(touchSize, touchSize),
        reason: '视觉圆底 36dp 逐位不变',
      );
      expect(hit.center, rect.center, reason: '视觉件在命中盒内居中（透明外扩）');
      final icon = tester.widget<Icon>(find.byIcon(Icons.screen_rotation));
      expect(icon.size, glyphSize, reason: '字形仍 24dp');
      final area = pictureAreaFor(
        aspectRatio: 16 / 9,
        trackBandHeight: TrackRowTable.normal.totalHeight,
      );
      for (final corner in [
        hit.topLeft,
        hit.topRight,
        hit.bottomLeft,
        hit.bottomRight,
      ]) {
        expect(area.contains(corner), isTrue, reason: '命中盒四角仍在画面区内：$corner');
      }
    });

    testWidgets('不占用视频播放工具栏槽位：六枚工具仍在、钮不在该行内', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final toolbar = find.byKey(const Key('control_layer_video_toolbar'));
      expect(toolbar, findsOneWidget);
      expect(
        find.descendant(of: toolbar, matching: rotateButton()),
        findsNothing,
        reason: '钮不占任何工具栏槽位',
      );
    });
  });

  group('显隐门禁', () {
    testWidgets('控制层收起时不出现（观看态画面干净）', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      expect(rotateButton(), findsNothing, reason: '观看态不出现');

      await openEditor(tester);
      expect(rotateButton(), findsOneWidget);

      containerOf(tester).read(playerSessionProvider.notifier).collapse();
      await tester.pump();
      expect(find.byKey(const Key('control_layer')), findsNothing);
      expect(rotateButton(), findsNothing, reason: '收起后不出现');
    });

    testWidgets('录制中（含准备期）不出现', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);
      expect(rotateButton(), findsOneWidget);

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.recording);
      await tester.pump();
      expect(rotateButton(), findsNothing, reason: '录制中不出现');

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.preparing);
      await tester.pump();
      expect(rotateButton(), findsNothing, reason: '准备期同样不出现');

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.idle);
      await tester.pump();
      expect(rotateButton(), findsOneWidget, reason: '回待录态恢复');
    });

    testWidgets('对比练习态共用同一枚', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await pumpPastMarquee(tester);

      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      expect(rotateButton(), findsOneWidget);
    });
  });

  group('锁横屏与粘性', () {
    testWidgets('点一次锁横屏；收起控制层零方向请求；再展开仍粘着', (tester) async {
      setPortraitView(tester);
      final systemUi = await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);
      expect(systemUi.lockLandscapeCount, 0, reason: '进编辑面零方向锁');

      await tester.tap(rotateButton());
      await tester.pump();
      expect(systemUi.lockLandscapeCount, 1, reason: '点一次锁横屏');

      // 收起控制层：不再解锁、不再发任何方向请求（粘性）。
      containerOf(tester).read(playerSessionProvider.notifier).collapse();
      await tester.pump();
      expect(systemUi.lockLandscapeCount, 1);
      expect(rotateButton(), findsNothing);

      // 再展开：朝向仍锁着，不重新请求跟随。
      await openEditor(tester);
      expect(rotateButton(), findsOneWidget);
      expect(systemUi.lockLandscapeCount, 1, reason: '没有第二次请求');
    });

    testWidgets('转屏钮：报按钮角色与名字；读屏激活确实锁横屏', (tester) async {
      final semantics = tester.ensureSemantics();
      setPortraitView(tester);
      final systemUi = await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      expectButtonSemantics(tester, kPortraitRotateButtonKey, label: '转为横屏');
      activateBySemantics(tester, kPortraitRotateButtonKey);
      await tester.pump();
      expect(systemUi.lockLandscapeCount, 1, reason: '读屏双击转屏钮应真的锁横屏');
      semantics.dispose();
    });
  });

  group('气泡覆盖层与钮的层序', () {
    /// 打开竖屏编辑面的「倍速设置」气泡（气泡域的公开状态源）。
    Future<void> openSpeedBubble(WidgetTester tester) async {
      containerOf(tester)
          .read(speedBubbleSessionProvider.notifier)
          .open(SpeedBubbleMode.speed);
      await tester.pump();
      expect(find.byType(SpeedBubble), findsOneWidget);
    }

    testWidgets('气泡打开时点钮矩形任一处：走「点泡外收起」且零方向请求；关泡后同一处一次锁横屏', (tester) async {
      setPortraitView(tester);
      final systemUi = await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final buttonRect = tester.getRect(rotateButton());
      for (final probe in [
        buttonRect.center,
        buttonRect.bottomRight - const Offset(1, 1),
      ]) {
        await openSpeedBubble(tester);
        expect(
          tester
              .getRect(find.byKey(const Key('speed_bubble_scrim')))
              .contains(probe),
          isTrue,
          reason: '本用例的前提：$probe 落在遮罩管辖范围内（不是空转）',
        );
        await tester.tapAt(probe);
        await tester.pump();
        expect(systemUi.lockLandscapeCount, 0, reason: '气泡打开时钮不抢这块点击：$probe');
        expect(
          find.byType(SpeedBubble),
          findsNothing,
          reason: '按遮罩语义收起气泡：$probe',
        );
      }

      await tester.tapAt(buttonRect.center);
      await tester.pump();
      expect(systemUi.lockLandscapeCount, 1, reason: '关泡后同一坐标一次点按即锁横屏');
    });
  });
}
