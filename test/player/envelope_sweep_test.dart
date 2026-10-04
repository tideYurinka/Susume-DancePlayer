import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart'
    show contentHasherProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/editor_skeleton.dart'
    show editorIsCompact;
import 'package:dance_learning_app/player/play_tool_table.dart'
    show
        kPlayToolRowLandscapeTopBar,
        kPlayToolRowLandscapeTopBarCompact,
        playToolLandscapeTopBarRow;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetDenseMinSize;
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart' show hangingBeatPipeline;
import '../helpers/device_viewport.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/pump_past_marquee.dart';

/// 包线遍历：宽度参与几何计算的面在包线两档
/// （small 320×640 / large 480×1000）× 竖横两姿态 × 字号 1.0×/1.6× 下
/// 不溢出，关键矩形（控制层、轨道带）落在视口内。只断言外部行为。
void main() {
  final source = Uri.file('/videos/a.mp4');

  Future<ProviderContainer> pumpPlayer(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
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
    return ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
  }

  /// 单击画面唤出控制层（等双击判定窗口过）。
  Future<void> showControlLayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await pumpPastMarquee(tester);
  }

  /// 观看态：控制层在场且整体收在视口内；轨道带水平不越界。
  Future<void> expectWatchSurface(WidgetTester tester) async {
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expectNoOverflow(tester, '观看态');
    final viewport = logicalViewport(tester);
    expectRectInside(tester, viewport, const Key('control_layer'), '控制层');
    // 控制层展开即常驻轨道带（观看/对比态与编辑态同一装配）。
    expectRectInside(tester, viewport, const Key('track_band'), '轨道带');
  }

  /// 编辑态：控制层展开即编辑面，轨道带与控制层都收在视口内。
  Future<void> expectEditSurface(WidgetTester tester) async {
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expectNoOverflow(tester, '编辑态');
    final viewport = logicalViewport(tester);
    expectRectInside(tester, viewport, const Key('control_layer'), '控制层');
    expectRectInside(tester, viewport, const Key('track_band'), '轨道带');
  }

  /// 对比态：进入对比-控制层，控制层收在视口内。
  Future<void> expectCompareSurface(WidgetTester tester) async {
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expectNoOverflow(tester, '对比态');
    final viewport = logicalViewport(tester);
    expectRectInside(tester, viewport, const Key('control_layer'), '控制层');
    expectRectInside(tester, viewport, const Key('track_band'), '轨道带');
  }

  for (final tier in [ViewportTier.small, ViewportTier.large]) {
    for (final landscape in [false, true]) {
      for (final textScale in [1.0, 1.6]) {
        final label = '${tier.name}${landscape ? ' 横屏' : ' 竖屏'} $textScale×';
        testWidgets('播放页观看态 $label：不溢出，控制层落在视口内', (tester) async {
          useNamedViewport(
            tester,
            tier,
            landscape: landscape,
            textScale: textScale,
          );
          await pumpPlayer(tester);
          await showControlLayer(tester);
          await expectWatchSurface(tester);
        });

        testWidgets('播放页编辑态 $label：不溢出，控制层与轨道带落在视口内', (tester) async {
          useNamedViewport(
            tester,
            tier,
            landscape: landscape,
            textScale: textScale,
          );
          final container = await pumpPlayer(tester);
          container
              .read(playerSessionProvider.notifier)
              .enter(PlayerSessionMode.editing);
          await tester.pump();
          await pumpPastMarquee(tester);
          await expectEditSurface(tester);
        });

        testWidgets('播放页对比态 $label：不溢出，控制层落在视口内', (tester) async {
          useNamedViewport(
            tester,
            tier,
            landscape: landscape,
            textScale: textScale,
          );
          final container = await pumpPlayer(tester);
          await showControlLayer(tester);
          container
              .read(playerSessionProvider.notifier)
              .enter(PlayerSessionMode.compareEditing);
          await tester.pump();
          await pumpPastMarquee(tester);
          await expectCompareSurface(tester);
        });
      }
    }
  }

  // small 横屏 1.6× 下顶栏可用宽放不下带标签的生效行集，标签收起为
  // 纯图标（布局修复，非缩放）——该档的全部入口仍须在场且收在视口内。
  // 判据遍历**当前视口生效的那份行集**（不是写死某一份）。
  testWidgets('播放页 small 横屏 1.6×：生效行集全部入口在场且收在视口内', (tester) async {
    useNamedViewport(
      tester,
      ViewportTier.small,
      landscape: true,
      textScale: 1.6,
    );
    await pumpPlayer(tester);
    await showControlLayer(tester);
    expect(tester.takeException(), isNull);
    final viewport = logicalViewport(tester);
    final rowSet = playToolLandscapeTopBarRow(
      compact: editorIsCompact(viewport.size),
    );
    expect(
      rowSet,
      same(kPlayToolRowLandscapeTopBarCompact),
      reason: 'small 横屏（最短边 320 < 600）落紧凑档',
    );
    for (final slot in rowSet.slots) {
      expect(
        find.byKey(Key(slot.key)),
        findsOneWidget,
        reason: '${slot.label} 在场',
      );
      expectRectInside(tester, viewport, Key(slot.key), slot.label);
      // 标签收起不连带收命中盒：逐槽不小于邻接密集区兜底下限（44）。
      expect(
        tester.getRect(find.byKey(Key(slot.key))).width,
        greaterThanOrEqualTo(kHitTargetDenseMinSize),
        reason: '${slot.label} 命中盒不小于兜底下限',
      );
    }
    // 搬进「更多」的三枚不常驻紧凑档横屏顶栏。
    for (final key in ['tool_av_sync', 'tool_framing_adjust', 'tool_beat_prompt']) {
      expect(find.byKey(Key(key)), findsNothing, reason: '$key 由「更多」承载');
    }
  });

  // 常规档横屏代表用例（平板横置 1180×820dp，最短边 820 ≥ 600）：三枚
  // 仍内联常驻、不出现「更多」，生效行集逐槽收在视口内。
  testWidgets('播放页 tablet 横屏 1.6×：常规档行集全部入口在场、无「更多」', (tester) async {
    useNamedViewport(
      tester,
      ViewportTier.tablet,
      landscape: true,
      textScale: 1.6,
    );
    await pumpPlayer(tester);
    await showControlLayer(tester);
    expect(tester.takeException(), isNull);
    final viewport = logicalViewport(tester);
    final rowSet = playToolLandscapeTopBarRow(
      compact: editorIsCompact(viewport.size),
    );
    expect(
      rowSet,
      same(kPlayToolRowLandscapeTopBar),
      reason: '平板横置（最短边 820 ≥ 600）落常规档',
    );
    expect(find.byKey(const Key('tool_more')), findsNothing);
    for (final slot in rowSet.slots) {
      expect(
        find.byKey(Key(slot.key)),
        findsOneWidget,
        reason: '${slot.label} 仍内联在常规档横屏顶栏',
      );
      expectRectInside(tester, viewport, Key(slot.key), slot.label);
      expect(
        tester.getRect(find.byKey(Key(slot.key))).width,
        greaterThanOrEqualTo(kHitTargetDenseMinSize),
        reason: '${slot.label} 命中盒不小于兜底下限',
      );
    }
  });
}

Rect logicalViewport(WidgetTester tester) {
  final view = tester.view;
  return Offset.zero &
      Size(
        view.physicalSize.width / view.devicePixelRatio,
        view.physicalSize.height / view.devicePixelRatio,
      );
}

void expectNoOverflow(WidgetTester tester, String label) {
  expect(tester.takeException(), isNull, reason: '$label 不溢出');
}

void expectRectInside(
  WidgetTester tester,
  Rect viewport,
  Key key,
  String label,
) {
  final rect = tester.getRect(find.byKey(key));
  expect(rect.left, greaterThanOrEqualTo(viewport.left), reason: '$label 不越左缘');
  expect(rect.right, lessThanOrEqualTo(viewport.right), reason: '$label 不越右缘');
  expect(rect.top, greaterThanOrEqualTo(viewport.top), reason: '$label 不越顶缘');
  expect(
    rect.bottom,
    lessThanOrEqualTo(viewport.bottom),
    reason: '$label 不越底缘',
  );
}
