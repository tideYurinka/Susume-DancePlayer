import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentStorageProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentStorage;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import '../helpers/video_surface.dart'
    show videoSurfacePlaceholderKey;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/compare_framing_harness.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 取景调节态（收口）：面板
/// 「取景」进入、画面手势归取景、其余交互停用、取景条两路命令（复位／
/// 完成）、退出三路同路、取值随舞记忆、钳制接线。断言一律落屏上判据：选区走
/// 屏上框几何（`framingBoxOnScreen`）、模式与撤销史可用性走在场件与置灰 token。
/// 取景条自身的落位/形制/命中在 `compare_framing_bar_test.dart`。
void main() {
  late FakePlaybackEngine engine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;

  /// 横屏逻辑尺寸 960 × 540：源侧左半（0–479）、练习侧右半（481–959）。
  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080); // 合成档 960.0×540.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    Map<String, Map<String, dynamic>> localFiles = const {},
    VideoDocumentStorage? documentStorage,
  }) async {
    final source = Uri.file('/videos/a.mp4');
    final docStorage =
        documentStorage ??
        InMemoryVideoDocumentStorage(
          local: localFiles['vid-test'] ?? const {},
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
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-test')),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => docStorage,
          ),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(
                    filePath: source.toFilePath(),
                    mirrored: false,
                    videoId: 'vid-test',
                  ),
                ],
              ),
            ),
          ),
          videoDocumentStorageProvider(
            'vid-test',
          ).overrideWithValue(docStorage),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 共用夹具（提取到 test/helpers/compare_framing_harness.dart）：屏上框几何、
  // 真入口进入取景态、真手势序列——本文件与取景条测试同源。
  Future<void> enterFraming(WidgetTester tester) =>
      enterFramingMode(tester);

  Future<void> singleTapShow(WidgetTester tester) async {
    // 点源侧画面内（水平 0–479、垂直 contain 画面 135–404），避开半区分界。
    await tester.tapAt(const Offset(240, 270));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 单指从 [from] 拖到 [to]：按对角圈出一个取景选区（真手势序列）。
  Future<void> buildBox(
    WidgetTester tester, {
    required Offset from,
    required Offset to,
  }) async {
    final touch = await tester.startGesture(from);
    await tester.pump();
    // 首帧位移只用于越过识别 slop：识别器的 start 落在这一帧的位置上，
    // 之后才跟手到 [to]。
    await touch.moveTo(Offset.lerp(from, to, 0.15)!);
    await tester.pump();
    await touch.moveTo(to);
    await tester.pump();
    await touch.up();
    await tester.pumpAndSettle();
  }

  setUp(() {
    engine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 16 / 9,
    );
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
  });

  testWidgets('进入取景态：控制层收起、取景条出现、倍速胶囊停用', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    // 模式判据 = 屏上在场者：取景条在、控制层与倍速入口不在。
    expect(find.byKey(const Key('framing_bar')), findsOneWidget);
    expect(find.byKey(const Key('control_layer')), findsNothing);
    expect(find.byKey(const Key('speed_entry_button')), findsNothing);
    // 源侧未调过 = 屏上不画选区框（整帧 contain 起手）。取景只剩源画面
    // 一份，没有练习侧取值（倍数数字的缺席断言见
    // `compare_framing_bar_test.dart`）。
    expect(framingBoxOnScreen(tester), isNull, reason: '未调过时屏上无框');
    expect(
      find.byKey(const Key('framing_selection_overlay')),
      findsNothing,
      reason: '未调过时不画任何覆盖层',
    );
  });

  // 本文件覆盖取景的端到端接线：进入/退出三路、取景条两路命令、随舞记忆与
  // 钳制接线。取景手势编排（进入取基准、调节、重设基准、侧别不变）的直测在
  // `test/player/framing_session_test.dart`（FramingSessionHost，不 pump 整页）。

  testWidgets('取景态在 burst 中途退出：本 burst 余帧既不再改取景、也不回落播放语义',
      (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    // 先圈一个选区，再起一次单指手势并保持按下（本次会圈出新框）。
    await buildBox(tester, from: const Offset(150, 180), to: const Offset(300, 320));
    final pinned = framingBoxOnScreen(tester)!;
    final touch = await tester.startGesture(const Offset(180, 180));
    await tester.pump();
    await touch.moveTo(const Offset(260, 230));
    await tester.pump();
    await touch.moveTo(const Offset(420, 380));
    await tester.pump();
    final moved = framingBoxOnScreen(tester)!;
    expect(moved, isNot(pinned), reason: '新的一次拖动在屏上圈出新框');
    expect(moved.right, greaterThan(pinned.right), reason: '新框跟手到更右侧');

    // 手指仍按着时用另一根手指点取景条「完成」退出取景态。
    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    final callsBefore = List<String>.of(engine.callLog);

    // 余下几帧：取景取值不再变、也没有回落成 seek/音量/亮度。
    await touch.moveBy(const Offset(-40, 0));
    await tester.pump();
    await touch.moveBy(const Offset(30, 120));
    await tester.pump();
    await touch.up();
    await tester.pumpAndSettle();

    expect(
      engine.callLog.skip(callsBefore.length).where(
            (c) => c.startsWith('seek') || c.startsWith('setVolume'),
          ),
      isEmpty,
    );
    // 再进一次取景态：屏上框仍是退出前定格的那一个（余帧没有改建框）。
    await enterFraming(tester);
    expect(framingBoxOnScreen(tester), moved);
  });

  testWidgets('取景态内播放手势无响应：双击不暂停、横滑不 seek、单击不唤控制层', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);
    expect(engine.isPlaying, isTrue);
    final callsBefore = List<String>.of(engine.callLog);

    // 双击：不暂停。
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(engine.isPlaying, isTrue);

    // 单指横滑（源侧 1.0×）：不产生 seek/进度手势。
    await tester.drag(
      find.byKey(const Key('player_surface')),
      const Offset(-120, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(
      engine.callLog
          .skip(callsBefore.length)
          .where((c) => c.startsWith('seek') || c.startsWith('pause')),
      isEmpty,
    );

    // 单击画面：不唤出控制层（取景态内一切交互停用）。
    await singleTapShow(tester);
    expect(find.byKey(const Key('framing_bar')), findsOneWidget);
    expect(find.byKey(const Key('control_layer')), findsNothing);
  });

  testWidgets('圈好后对比源侧也按选区 contain 显示', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);
    final unframed = tester.getRect(
      find.byKey(videoSurfacePlaceholderKey),
    );

    await buildBox(tester, from: const Offset(120, 160), to: const Offset(360, 360));
    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();

    final framed = tester.getRect(find.byKey(videoSurfacePlaceholderKey));
    expect(
      framed.height,
      greaterThan(unframed.height),
      reason: '对比源侧按选区内容 contain 放大',
    );
  });

  testWidgets('取景条：复位清取值回基线；完成退出回对比-控制层', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    await buildBox(tester, from: const Offset(150, 180), to: const Offset(300, 320));
    expect(framingBoxOnScreen(tester), isNotNull, reason: '圈好后屏上出现选区框');
    expect(
      find.byKey(const Key('framing_selection_overlay')),
      findsOneWidget,
      reason: '圈好后选区外压暗、边界出白框',
    );

    await tester.tap(find.byKey(const Key('framing_reset')));
    await tester.pumpAndSettle();
    // 复位生效 = 屏上框消失（回整帧）。
    expect(framingBoxOnScreen(tester), isNull);
    expect(
      find.byKey(const Key('framing_selection_overlay')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(find.byKey(const Key('framing_bar')), findsNothing);
  });

  testWidgets('系统返回键退出取景态 = 回对比-控制层（三路同路之二）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(find.byKey(const Key('framing_bar')), findsNothing);
  });

  testWidgets('点画面外退出取景态（contain 黑边落点，三路同路之三）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    // 源侧半区（0–479 宽）contain 16:9 画面：高 269、垂直居中（135–404），
    // 顶部黑边 (240, 30) 在画面之外。
    await tester.tapAt(const Offset(240, 30));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(find.byKey(const Key('framing_bar')), findsNothing);
  });

  testWidgets('打开含旧 v3 取景键的舞：取景未调过（直接复位）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester, localFiles: {
      'vid-test': {
        'version': 3,
        'prefs': {
          'framingSource': {'scale': 2.5, 'offsetX': 0.0, 'offsetY': 0.0},
        },
      },
    });
    await enterFraming(tester);

    expect(
      framingBoxOnScreen(tester),
      isNull,
      reason: '旧值不换算、不提升：屏上无框，回未调过的起手构图',
    );
    expect(
      find.byKey(const Key('framing_selection_overlay')),
      findsNothing,
    );
  });


  testWidgets('直写不受锁定分段门禁：「锁定分段」开启时取景仍可调', (tester) async {
    setWideView(tester);
    await pumpPlayer(
      tester,
      localFiles: {
        'vid-test': {
          'version': 4,
          'prefs': {'layoutLocked': true},
        },
      },
    );
    await enterCompareEditing(tester);
    expect(
      find.text('锁定分段·开'),
      findsOneWidget,
      reason: '布景的「锁定分段」真的开着（屏上开关读数）',
    );
    await enterFraming(tester);

    await buildBox(tester, from: const Offset(150, 180), to: const Offset(300, 320));

    expect(
      framingBoxOnScreen(tester),
      isNotNull,
      reason: '锁定分段开启时屏上仍圈得出取景框',
    );
  });

  testWidgets('取景调整不入撤销／重做史', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await enterCompareEditing(tester);

    // 取景调整前：撤销/重做按钮置灰（无历史）。
    expect(toolSlotDisabled(tester, 'tool_undo'), isTrue);
    expect(toolSlotDisabled(tester, 'tool_redo'), isTrue);

    await enterFraming(tester);
    await buildBox(tester, from: const Offset(150, 180), to: const Offset(300, 320));
    expect(framingBoxOnScreen(tester), isNotNull);

    await tester.tap(find.byKey(const Key('framing_done')));
    await tester.pumpAndSettle();

    // 回控制层：两枚按钮仍置灰 = 取景调整没进撤销/重做史。
    expect(toolSlotDisabled(tester, 'tool_undo'), isTrue, reason: '取景不入撤销史');
    expect(toolSlotDisabled(tester, 'tool_redo'), isTrue, reason: '取景不入重做史');
  });

}
