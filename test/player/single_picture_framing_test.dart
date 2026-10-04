/// 单画面取景：普通编辑面点「取景调整」进
/// 单画面取景调节态——控制层收起、画面手势归取景（其余播放手势无响应）、
/// 取景条只有「复位」「完成」、退出三路同路回编辑态、两条路径（单画面 /
/// 对比源侧）共用同一份取值、复位 = 清取值回整帧、构图在整个打开期间常显。
/// 取景条形制与落位的形制断言在 `compare_framing_bar_test.dart`；取景手势
/// 编排直测在 `framing_session_test.dart`。
library;

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/player/framing_overlay.dart'
    show FramingSelectionOverlay;
import 'package:dance_learning_app/player/compare_framing_bar.dart'
    show kCompareFramingBarHint, kCompareFramingBarTitle;
import 'package:dance_learning_app/player/framing_session_state.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentStorageProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;

import '../helpers/video_surface.dart' show videoSurfacePlaceholderKey;

import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentStorage;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_viewport.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';

void main() {
  late FakePlaybackEngine engine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;

  /// 设备等效横屏（compact 档转置 = 781.7 × 361.1dp）：整屏 contain 16:9
  /// 画面 = 642 × 361.1（垂直充满），左右黑边各约 70dp——「点画面外」
  /// 取左黑边落点。
  void setWideView(WidgetTester tester) {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    Map<String, dynamic> local = const {},
  }) async {
    final source = Uri.file('/videos/a.mp4');
    final VideoDocumentStorage docStorage = InMemoryVideoDocumentStorage(
      local: local,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          cameraCaptureProvider.overrideWithValue(camera),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(systemUi),
          contentHasherProvider.overrideWithValue(
            const FixedHasher('vid-test'),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
          ),
          videoDocumentStorageProvider('vid-test')
              .overrideWithValue(docStorage),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  PlayerSessionMode modeOf(WidgetTester tester) =>
      containerOf(tester).read(playerSessionProvider).mode;

  FramingSelection? sourceSelectionOf(WidgetTester tester) =>
      containerOf(tester).read(framingStateProvider).source;

  /// 进编辑态（控制层展开）；已在编辑态则不动（单击会收起控制层）。
  Future<void> openEditor(WidgetTester tester) async {
    if (modeOf(tester) != PlayerSessionMode.editing) {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pumpAndSettle();
    }
  }

  /// 点顶栏「取景调整」进单画面取景。
  Future<void> enterSingleFraming(WidgetTester tester) async {
    await openEditor(tester);
    await tester.tap(find.byKey(const Key('tool_framing_adjust')));
    await tester.pumpAndSettle();
  }

  /// 真手势：单指从 [from] 按下、拖到 [to] 抬手。首帧位移取**固定 20dp**
  /// （沿拖动方向）越过识别 slop——识别器的 start 落在这一帧的位置上，之后
  /// 才跟手到 [to]。
  Future<void> dragOnPicture(
    WidgetTester tester, {
    required Offset from,
    required Offset to,
  }) async {
    final delta = to - from;
    final first = delta.distance <= 20
        ? to
        : from + delta * (20 / delta.distance);
    final touch = await tester.startGesture(from);
    await tester.pump();
    await touch.moveTo(first);
    await tester.pump();
    if (first != to) {
      await touch.moveTo(to);
      await tester.pump();
    }
    await touch.up();
    // 越过双击判定窗口：连续两次拖动不被并成一次双击仲裁。
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  }

  /// 单指从 [from] 拖到 [to]：按对角圈出一个取景选区（真手势序列）。
  Future<void> buildBox(
    WidgetTester tester, {
    required Offset from,
    required Offset to,
  }) => dragOnPicture(tester, from: from, to: to);

  /// 画面矩形（屏幕坐标）：覆盖层的画面矩形 + 覆盖层原点。
  Rect pictureOnScreen(WidgetTester tester) {
    final overlay = tester.widget<FramingSelectionOverlay>(
      find.byType(FramingSelectionOverlay),
    );
    final box = tester.getRect(
      find.byKey(const Key('framing_selection_overlay')),
    );
    return overlay.pictureRect.shift(box.topLeft);
  }

  /// 选区在屏幕上的矩形（与渲染覆盖层共用同一处映射）。
  Rect selectionOnScreen(FramingSelection selection, Rect picture) {
    final rect = framingSelectionRectOnPicture(
      selection: selection,
      pictureLeft: picture.left,
      pictureTop: picture.top,
      pictureWidth: picture.width,
      pictureHeight: picture.height,
    );
    return Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom);
  }

  setUp(() {
    engine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 16 / 9,
    );
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
  });

  testWidgets('单画面取景：拖动圈出一块选区；双击不暂停（除取景手势外手势全停）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterSingleFraming(tester);

    expect(sourceSelectionOf(tester), isNull, reason: '未调过 = 取值不存在');

    await buildBox(
      tester,
      from: const Offset(240, 120),
      to: const Offset(480, 280),
    );
    final selection = sourceSelectionOf(tester);
    expect(selection, isNotNull, reason: '拖动圈出一块选区');
    expect(selection!.width, lessThan(1.0));
    expect(selection.height, lessThan(1.0));

    // 双击暂停停用：引擎播放态不变。
    final playingBefore = engine.isPlaying;
    await tester.tap(
      find.byKey(const Key('player_surface')),
      warnIfMissed: false,
    );
    await tester.pump(kDoubleTapTimeout);
    await tester.tap(
      find.byKey(const Key('player_surface')),
      warnIfMissed: false,
    );
    await tester.pump(kDoubleTapTimeout);
    expect(engine.isPlaying, playingBefore, reason: '双击暂停停用');
    expect(modeOf(tester).name, 'framing', reason: '单击（双击首击）也不唤控制层');
  });

  testWidgets('打开含旧 v3 取景键的舞：单画面路径未调过、按整帧起手构图', (tester) async {
    setWideView(tester);
    await pumpPlayer(
      tester,
      local: {
        'version': 3,
        'prefs': {
          'framingSource': {'scale': 2.5, 'offsetX': 0.0, 'offsetY': 0.0},
        },
      },
    );
    await enterSingleFraming(tester);

    expect(
      sourceSelectionOf(tester),
      isNull,
      reason: '旧值不换算：取值不存在即按整帧基线起手（渲染变换的 null 退化分支）',
    );
  });

  testWidgets('竖屏贴底：覆盖层的画面矩形贴着画面实际显示位置（不偏上）', (tester) async {
    useNamedViewport(tester, ViewportTier.compact, landscape: false);
    await pumpPlayer(tester);
    await enterSingleFraming(tester);

    final frame = tester.getRect(find.byKey(videoSurfacePlaceholderKey));
    await buildBox(
      tester,
      from: frame.topLeft + Offset(frame.width * 0.1, frame.height * 0.1),
      to: frame.topLeft + Offset(frame.width * 0.9, frame.height * 0.9),
    );

    final overlayFinder = find.byKey(const Key('framing_selection_overlay'));
    expect(overlayFinder, findsOneWidget);
    final overlay = tester.widget<FramingSelectionOverlay>(
      find.byType(FramingSelectionOverlay),
    );
    final box = tester.getRect(overlayFinder);
    // 覆盖层的画面矩形（相对控件）+ 控件原点 = 画面实际显示的矩形。
    expect(box.top + overlay.pictureRect.top, closeTo(frame.top, 1.0));
    expect(box.left + overlay.pictureRect.left, closeTo(frame.left, 1.0));
    expect(box.top + overlay.pictureRect.bottom, closeTo(frame.bottom, 1.0));
    expect(box.left + overlay.pictureRect.right, closeTo(frame.right, 1.0));
  });

  testWidgets('退出三路同路回编辑态：完成 / 系统返回 / 点画面外', (tester) async {
    // 整屏 contain 16:9 画面左右留黑边：「点画面外」取左黑边落点。
    setWideView(tester);
    await pumpPlayer(tester);

    // 路① 完成。
    await enterSingleFraming(tester);
    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.editing);

    // 路② 系统返回.
    await enterSingleFraming(tester);
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(modeOf(tester), PlayerSessionMode.editing);

    // 路③ 点画面外（左黑边落点 (30, 180)）。
    await enterSingleFraming(tester);
    await tester.tapAt(const Offset(30, 180));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byKey(const Key('framing_bar')), findsNothing);
  });

  testWidgets('两条路径共用同一份取值：单画面调好的带在对比源侧原样生效', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);

    await enterSingleFraming(tester);
    await buildBox(
      tester,
      from: const Offset(240, 120),
      to: const Offset(480, 280),
    );
    final single = sourceSelectionOf(tester)!;
    expect(single.width, lessThan(1.0));

    // 退回编辑态 → 进对比态到对比取景：取值原样（同一对象、未被换基线改写）。
    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();
    expect(sourceSelectionOf(tester), single, reason: '退出取景子态构图保留');

    containerOf(tester)
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareEditing);
    await tester.pumpAndSettle();
    containerOf(tester)
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareFraming);
    await tester.pumpAndSettle();

    expect(sourceSelectionOf(tester), single, reason: '对比分屏路径读同一份带');
  });

  testWidgets('复位 = 清取值回基线；重开取景子态仍是基线（构图随打开期间常显）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);

    await enterSingleFraming(tester);
    await buildBox(
      tester,
      from: const Offset(240, 120),
      to: const Offset(480, 280),
    );
    expect(sourceSelectionOf(tester), isNotNull);

    await tester.tap(find.byKey(const Key('framing_reset')));
    await tester.pumpAndSettle();
    expect(sourceSelectionOf(tester), isNull, reason: '复位 = 清除取值（回基线）');

    // 清值后继续退出、再进：仍是基线（未调过），取景条仍在。
    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();
    await enterSingleFraming(tester);
    expect(sourceSelectionOf(tester), isNull);
    expect(find.byKey(const Key('framing_bar')), findsOneWidget);
    // 单画面路径与对比路径共用同一条取景条：提示「拖动圈选画面」两路都在
    // （条内容断言在 compare_framing_bar_test）。
    expect(find.text(kCompareFramingBarHint), findsOneWidget);
    expect(find.text(kCompareFramingBarTitle), findsOneWidget);
  });

  testWidgets('框内拖动整体平移、角点改两轴、边中点只改那一条边', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterSingleFraming(tester);

    await buildBox(
      tester,
      from: const Offset(240, 120),
      to: const Offset(480, 280),
    );
    final built = sourceSelectionOf(tester)!;
    final picture = pictureOnScreen(tester);
    final box = selectionOnScreen(built, picture);

    // 框内拖动：整体平移，形状不变。
    await dragOnPicture(
      tester,
      from: box.center,
      to: box.center + const Offset(60, -40),
    );
    final moved = sourceSelectionOf(tester)!;
    expect(moved.width, closeTo(built.width, 1e-9), reason: '整体平移形状不变');
    expect(moved.height, closeTo(built.height, 1e-9));
    expect(moved.centerX, greaterThan(built.centerX));
    expect(moved.centerY, lessThan(built.centerY));

    // 角点拖动：同时改两轴，对侧不动。
    final movedBox = selectionOnScreen(moved, picture);
    await dragOnPicture(
      tester,
      from: movedBox.topLeft,
      to: movedBox.topLeft + const Offset(40, 30),
    );
    final resized = sourceSelectionOf(tester)!;
    expect(resized.left, greaterThan(moved.left));
    expect(resized.top, greaterThan(moved.top));
    expect(resized.right, closeTo(moved.right, 1e-9), reason: '对侧不动');
    expect(resized.bottom, closeTo(moved.bottom, 1e-9));

    // 边中点拖动：只改那一条边（另一轴的位移不生效）。
    final resizedBox = selectionOnScreen(resized, picture);
    final rightMid = Offset(resizedBox.right, resizedBox.center.dy);
    await dragOnPicture(
      tester,
      from: rightMid,
      to: rightMid + const Offset(-50, 40),
    );
    final edged = sourceSelectionOf(tester)!;
    expect(edged.right, lessThan(resized.right));
    expect(edged.left, closeTo(resized.left, 1e-9));
    expect(edged.top, closeTo(resized.top, 1e-9));
    expect(edged.bottom, closeTo(resized.bottom, 1e-9), reason: '边中点只改那一条边');
  });

  testWidgets('框外拖动替换成新框（不是整体平移）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterSingleFraming(tester);

    await buildBox(
      tester,
      from: const Offset(240, 120),
      to: const Offset(480, 280),
    );
    final built = sourceSelectionOf(tester)!;

    // 框左侧的框外区域起手、向右下拖：新框替换掉原框（不与原框重叠）。
    await dragOnPicture(
      tester,
      from: const Offset(100, 150),
      to: const Offset(240, 300),
    );
    final replaced = sourceSelectionOf(tester)!;
    expect(replaced.right, lessThanOrEqualTo(built.left), reason: '替换成新框');
  });

  testWidgets('竖屏贴底：框内拖动按画面实际位置整体平移', (tester) async {
    useNamedViewport(tester, ViewportTier.compact, landscape: false);
    await pumpPlayer(tester);
    await enterSingleFraming(tester);

    final frame = tester.getRect(find.byKey(videoSurfacePlaceholderKey));
    await buildBox(
      tester,
      from: frame.topLeft + Offset(frame.width * 0.1, frame.height * 0.1),
      to: frame.topLeft + Offset(frame.width * 0.9, frame.height * 0.9),
    );
    final built = sourceSelectionOf(tester)!;
    final picture = pictureOnScreen(tester);
    final box = selectionOnScreen(built, picture);

    await dragOnPicture(
      tester,
      from: box.center,
      to: box.center + const Offset(0, -30),
    );
    final moved = sourceSelectionOf(tester)!;
    expect(moved.width, closeTo(built.width, 1e-9), reason: '整体平移形状不变');
    expect(moved.height, closeTo(built.height, 1e-9));
    expect(moved.centerY, lessThan(built.centerY), reason: '框随手指上移');
  });

  testWidgets('选区画八个取景控制点：四角 ∅16dp、四边中点 ∅10dp', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterSingleFraming(tester);

    await buildBox(
      tester,
      from: const Offset(240, 120),
      to: const Offset(480, 280),
    );

    expect(
      find.byKey(const Key('framing_selection_overlay')),
      paints
        ..circle(radius: 8)
        ..circle(radius: 8)
        ..circle(radius: 8)
        ..circle(radius: 8)
        ..circle(radius: 5)
        ..circle(radius: 5)
        ..circle(radius: 5)
        ..circle(radius: 5),
      reason: '四角 ∅16dp、四边中点 ∅10dp（八个控制点）',
    );
  });
}
