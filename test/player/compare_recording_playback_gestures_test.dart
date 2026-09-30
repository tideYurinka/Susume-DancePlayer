/// 录制期的播放语义：录制期间（**含准备期**）源侧
/// 恒 1.0× 在播，播放类手势整体失效——双击暂停、进度拖动与定格预览、双指
/// 双击延迟播放、三指跳转都不生效；**双击画面 = 停录**（与录制钮同一个
/// 动作：准备期 = 取消并丢弃已武装的那段、录制中 = 停录入库）；整片循环
/// （尾点循环提示的倒计时与自动回拨）一并抑制；音量/亮度照常（它们不动
/// 播放态也不动位置）。
///
/// 手势一律用**真手势序列**（双击要在双击窗口内两次落下抬起），断言**可观察
/// 状态**：引擎播放态与位置、相机是否还在录、素材与片段是否入库、屏幕上
/// 出现了哪个浮层。否定式与正向成对——「没崩」不算过。
library;

import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/gestures.dart'
    show kLongPressDoubleSpeedTimeout, kLongPressDoubleSpeedRate;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show practiceClipsProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show
        screenBrightnessControllerProvider,
        systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/device_viewport.dart';

void main() {
  group('录制期的播放手势语义', () {
    late FakePlaybackEngine engine;
    late FakeCameraCaptureService camera;
    late MemoryManifestStorage manifestStorage;
    late FakeSystemMediaVolumeController volume;
    late FakeScreenBrightnessController brightness;
    late File materialOutputFile;

    /// 设备等效视口（`2736×1264 @3.5` = 781.7×361.1dp，与开发真机横屏一致）：
    /// 「手感」类判据必须在真机等效视口下断言能真的按到/滑到
    /// （可达性 ≠ 存在性）。
    void setDeviceView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
    }

    Future<void> pumpPlayer(WidgetTester tester) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            materialManifestStorageProvider.overrideWithValue(manifestStorage),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => materialOutputFile,
            ),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
            screenBrightnessControllerProvider.overrideWithValue(brightness),
            systemMediaVolumeControllerProvider.overrideWithValue(volume),
            contentHasherProvider.overrideWithValue(
              const FixedHasher('seeded'),
            ),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: source.toFilePath(),
                      mirrored: false,
                    ),
                  ],
                ),
              ),
            ),
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

    /// 设备等效视口下的手势落点（右半屏 x ≥ 390.9dp）：中央；右半屏 = 音量、
    /// 左半屏 = 亮度（轴向锁定后按起点所在半屏分流）。
    const Offset center = Offset(390, 180);
    const Offset rightHalf = Offset(600, 180);
    const Offset leftHalf = Offset(150, 180);

    Future<void> enterCompare(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    /// 按下录制并走到**准备期**：无激活段、起点 = 按下位置 12s、前导 8 拍
    /// （占位网格 500ms/拍）从 8s 起播。返回时仍在准备期（引擎在播、未起录）。
    Future<void> pressRecordIntoPrep(
      WidgetTester tester, {
      Duration at = const Duration(seconds: 12),
    }) async {
      await engine.seek(at);
      await tester.pump(const Duration(milliseconds: 1));
      engine.seekCalls.clear();
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsOneWidget,
        reason: '布景自身必须真的离开待录态（记录钮在设备等效视口下可达）',
      );
    }

    /// 按下录制并走到**录制中**（前导 8 拍播完、位置越过起录点 12s）。
    Future<void> beginRecording(
      WidgetTester tester, {
      Duration at = const Duration(seconds: 12),
    }) async {
      await pressRecordIntoPrep(tester, at: at);
      await tester.pump(const Duration(seconds: 4)); // 前导 8 拍。
      await tester.pump(const Duration(milliseconds: 200)); // 越过起录点。
      expect(camera.startRecordingCalls, hasLength(1), reason: '布景须真的在录');
      expect(engine.isPlaying, isTrue);
    }

    /// 单指双击（两次 tap 间隔 < 双击窗口 300ms）。
    Future<void> doubleTap(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
    }

    /// 一次双指 tap：两指按下 → 50ms → 两指抬起。
    Future<void> twoFingerTap(WidgetTester tester, Offset at) async {
      final g1 = await tester.startGesture(at);
      final g2 = await tester.startGesture(at + const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 50));
      await g1.up();
      await g2.up();
      await tester.pump(const Duration(milliseconds: 50));
    }

    /// 双指双击（两次双指 tap，间隔 < 300ms 窗口）。
    Future<void> twoFingerDoubleTap(WidgetTester tester, Offset at) async {
      await twoFingerTap(tester, at);
      await tester.pump(const Duration(milliseconds: 50));
      await twoFingerTap(tester, at);
      await tester.pump();
    }

    /// 三指水平滑动（按 [delta] 步进一次后抬起）。
    Future<void> threeFingerSwipe(
      WidgetTester tester, {
      required Offset start,
      required Offset delta,
    }) async {
      final g1 = await tester.startGesture(start);
      final g2 = await tester.startGesture(start + const Offset(40, 0));
      final g3 = await tester.startGesture(start + const Offset(80, 0));
      await tester.pump();
      await g1.moveBy(delta);
      await g2.moveBy(delta);
      await g3.moveBy(delta);
      await tester.pump();
      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump();
      await tester.pump();
    }

    /// 单指拖动 [frames] 帧（水平 = 进度拖动、垂直 = 音量/亮度）。
    Future<TestGesture> dragFrames(
      WidgetTester tester,
      Offset start,
      int frames, {
      required Offset delta,
    }) async {
      final gesture = await tester.startGesture(start);
      for (var i = 0; i < frames; i++) {
        await gesture.moveBy(delta);
        await tester.pump();
      }
      return gesture;
    }

    PlayerSessionMode modeOf(WidgetTester tester) =>
        containerOf(tester).read(playerSessionProvider).mode;

    Future<MaterialManifestDocument> readManifest() =>
        MaterialManifestStore(manifestStorage).read();

    List<dynamic> clipsOf(WidgetTester tester) =>
        containerOf(tester).read(practiceClipsProvider);

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      camera = FakeCameraCaptureService();
      manifestStorage = MemoryManifestStorage();
      volume = FakeSystemMediaVolumeController(currentVolume: 0.5);
      brightness = FakeScreenBrightnessController(initialBrightness: 0.5);
      final dir = Directory.systemTemp.createTempSync('cmp_rec_gesture');
      addTearDown(() => dir.delete(recursive: true));
      materialOutputFile = File('${dir.path}/rec.mp4');
    });

    testWidgets('准备期：播放类手势同样不生效（水平拖 / 三指跳转 / 双指双击）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await pressRecordIntoPrep(tester);
      await tester.pump(const Duration(milliseconds: 300)); // 前导已起播。
      expect(engine.isPlaying, isTrue);
      engine.seekCalls.clear();

      // 水平拖：不起 scrub、不暂停、不 seek。
      final drag = await dragFrames(
        tester,
        center,
        10,
        delta: const Offset(20, 0),
      );
      expect(engine.seekCalls, isEmpty, reason: '准备期进度拖动不生效');
      expect(engine.isPlaying, isTrue, reason: '准备期源侧恒在播');
      expect(find.byKey(const Key('scrub_indicator')), findsNothing);
      await drag.up();
      await tester.pump();

      // 三指跳转：不 seek、无跳转提示。
      await threeFingerSwipe(
        tester,
        start: center,
        delta: const Offset(-80, 0),
      );
      expect(engine.seekCalls, isEmpty, reason: '准备期三指跳转不生效');
      expect(find.byKey(const Key('three_finger_toast')), findsNothing);

      // 双指双击：不触发延迟播放。
      await twoFingerDoubleTap(tester, center);
      await tester.pump();
      expect(find.byKey(const Key('delayed_play_indicator')), findsNothing);
      expect(engine.isPlaying, isTrue);

      // 全程仍在准备期：没起录、没进控制层/取景态。
      expect(camera.startRecordingCalls, isEmpty, reason: '还没越过起录点');
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsOneWidget,
      );
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
    });

    testWidgets('起录接线：录制钮收掉在途的定格预览并进入接管（次序不变量在模块级）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);

      // 拖动起 scrub：定格预览出现、源侧被暂停（多点触控下「拖着进度条按
      // 录制」是唯一能带着 scrub 会话起录的路径）。
      final drag = await dragFrames(
        tester,
        center,
        10,
        delta: const Offset(20, 0),
      );
      expect(find.byKey(const Key('scrub_indicator')), findsOneWidget);
      expect(engine.isPlaying, isFalse, reason: 'scrub 起手先暂停定格');
      engine.seekCalls.clear();

      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '起录即收掉在途定格预览：录制期不残留 scrub 相位',
      );
      expect(engine.isPlaying, isTrue, reason: '前导起播（源侧恒 1.0× 在播）');
      expect(
        engine.seekCalls,
        hasLength(1),
        reason: '留在序列里的只有起播定位那一次（scrub 的逐帧 seek 已随会话收口）',
      );
      expect(
        engine.seekCalls.single,
        lessThan(const Duration(seconds: 10)),
        reason: '起录点取按下位置（含 scrub 落点），前导回拨到它之前',
      );
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsOneWidget,
      );
      expect(modeOf(tester), PlayerSessionMode.compareWatching);

      // 松手：scrub 已在起录那一刻收口，不再回写播放态、不再补任何 seek。
      await drag.up();
      await tester.pump();
      expect(engine.seekCalls, hasLength(1), reason: '松手不再补 seek（含取消回退）');
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('录制期瞬态倍速收尾（真路径：长按 2× → 起录 → 松手）不把速率写回非 1.0×', (
      tester,
    ) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      // 手动倍速 1.5：松手若写回「瞬态前基准」就会把录制强制的 1.0× 顶成 1.5。
      await containerOf(tester).read(speedControlProvider.notifier).setRate(1.5);
      expect(engine.rate, 1.5);

      // 一根手指长按满阈值 → 瞬态 2× 生效。
      final hold = await tester.startGesture(center);
      await tester.pump(
        kLongPressDoubleSpeedTimeout + const Duration(milliseconds: 30),
      );
      await tester.pump();
      expect(engine.rate, kLongPressDoubleSpeedRate, reason: '长按瞬态 2× 生效');
      expect(find.byKey(const Key('double_speed_badge')), findsOneWidget);

      // 另一根手指按下录制（多指同时操作 = 带着 2× 起录的唯一路径）。
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(engine.rate, 1.0, reason: '录制强制 1.0×');

      await hold.up();
      await tester.pump();
      expect(
        engine.rate,
        1.0,
        reason: '录制期收尾上锁：松手不得把速率写回瞬态前的 1.5',
      );
      expect(find.byKey(const Key('double_speed_badge')), findsNothing);

      // 停录：恢复的「原倍速」是用户的手动倍速 1.5，不是瞬态 2×。
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(engine.rate, 1.5, reason: '停后恢复录制前的手动倍速');
    });

    testWidgets('录制中双击 = 停录并入库（不是把源侧暂停、让录制继续跑）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await beginRecording(tester);

      await doubleTap(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        camera.isRecording,
        isFalse,
        reason: '双击必须与录制钮同一个动作：停录。'
            '旧行为是「只把源侧暂停、录制照跑」——素材照录满而声明的源区间比实际内容多',
      );
      expect(camera.stopRecordingCount, 1);
      expect(find.byKey(const Key('compare_recording_indicator')), findsNothing);
      expect(engine.isPlaying, isFalse, reason: '停录后暂停在停止点');
      expect(await readManifest().then((d) => d.materials), hasLength(1));
      expect(clipsOf(tester), hasLength(1), reason: '停录即入库、片段随即入轨');
    });

    testWidgets('准备期双击 = 取消并丢弃已武装的那段（不落素材、不落片段）', (tester) async {
      setDeviceView(tester);
      // 起录重配耗时：非零才让「武装了但还没到起录点」这段窗口
      // 真实存在——准备期双击取消的正是这段。
      camera.startRecordingLatency = const Duration(milliseconds: 200);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await pressRecordIntoPrep(tester);

      // 前导 3.6s：越过武装点（11.4s）但还没到起录点（12s）。
      await tester.pump(const Duration(milliseconds: 3600));
      expect(camera.startRecordingCalls, hasLength(1), reason: '武装窗口内');
      expect(camera.isRecording, isTrue);
      expect(engine.position, lessThan(const Duration(seconds: 12)));

      await doubleTap(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsNothing,
        reason: '准备期双击 = 取消：回到待录态（不是继续准备、更不是起录）',
      );
      expect(
        camera.isRecording,
        isFalse,
        reason: '已武装的那段要被停掉并丢弃（不留下半截素材）',
      );
      expect(camera.stopRecordingCount, 1);
      expect(engine.isPlaying, isFalse, reason: '取消后暂停在取消点，不自动回拨');
      expect(
        engine.position,
        lessThan(const Duration(seconds: 12)),
        reason: '不得越过起录点起录',
      );
      expect(
        await readManifest().then((d) => d.materials),
        isEmpty,
        reason: '准备期取消不落素材',
      );
      expect(clipsOf(tester), isEmpty, reason: '准备期取消不落片段');
    });

    testWidgets('录制中水平拖不生效：不暂停、不 seek、不起 scrub 指示', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await beginRecording(tester);

      engine.seekCalls.clear();
      final gesture = await dragFrames(
        tester,
        center,
        10,
        delta: const Offset(20, 0),
      );
      await tester.pump();

      expect(
        engine.isPlaying,
        isTrue,
        reason: '源侧恒 1.0× 在播：scrub 起手不得把引擎暂停（定格预览不生效）',
      );
      expect(engine.seekCalls, isEmpty, reason: '进度拖动不生效：位置不跳');
      expect(
        find.byKey(const Key('scrub_indicator')),
        findsNothing,
        reason: '定格预览不生效',
      );

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(engine.seekCalls, isEmpty);
      expect(engine.isPlaying, isTrue);
      expect(camera.isRecording, isTrue, reason: '手势不得把录制搅停');
      expect(find.byKey(const Key('compare_recording_indicator')), findsOneWidget);
      expect(
        modeOf(tester),
        PlayerSessionMode.compareWatching,
        reason: '不进入对比-控制层或取景调节态',
      );
    });

    testWidgets('录制中双指双击不触发延迟播放', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await beginRecording(tester);
      // 布景自身的前导定位 seek（8s）不计入本用例的 seek 序列。
      engine.seekCalls.clear();

      await twoFingerDoubleTap(tester, center);
      await tester.pump();

      expect(
        find.byKey(const Key('delayed_play_indicator')),
        findsNothing,
        reason: '延迟播放不生效',
      );
      expect(engine.isPlaying, isTrue);

      // 一个八拍（占位网格 4s）也不会有任何「到点起播」的后账。
      final before = engine.position;
      await tester.pump(const Duration(seconds: 4));
      expect(engine.seekCalls, isEmpty, reason: '延迟播放不产生任何定位');
      expect(engine.position, greaterThan(before), reason: '只是在顺播');
      expect(camera.isRecording, isTrue);
      expect(find.byKey(const Key('compare_recording_indicator')), findsOneWidget);
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
    });

    testWidgets('录制中三指跳转不生效（不 seek、无跳转提示）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await beginRecording(tester);

      engine.seekCalls.clear();
      await threeFingerSwipe(
        tester,
        start: center,
        delta: const Offset(-80, 0),
      );

      expect(engine.seekCalls, isEmpty, reason: '三指跳转不生效：位置不跳');
      expect(
        find.byKey(const Key('three_finger_toast')),
        findsNothing,
        reason: '不生效的手势不留「已跳转」提示',
      );
      expect(engine.isPlaying, isTrue);
      expect(camera.isRecording, isTrue);
      expect(modeOf(tester), PlayerSessionMode.compareWatching);
    });

    testWidgets('录制中垂直滑音量/亮度照常生效（它们不动播放态也不动位置）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);
      await beginRecording(tester);

      engine.seekCalls.clear();
      final volumeBefore = volume.currentVolume;
      final volumeGesture = await dragFrames(
        tester,
        rightHalf,
        8,
        delta: const Offset(0, -20),
      );
      expect(
        volume.currentVolume,
        greaterThan(volumeBefore),
        reason: '右半屏上滑 = 调大音量（录制期照常）',
      );
      expect(find.byKey(const Key('level_adjust_slider')), findsOneWidget);
      await volumeGesture.up();
      await tester.pump();

      final brightnessBefore = brightness.initialBrightness;
      final brightnessGesture = await dragFrames(
        tester,
        leftHalf,
        8,
        delta: const Offset(0, -20),
      );
      expect(
        brightness.initialBrightness,
        greaterThan(brightnessBefore),
        reason: '左半屏上滑 = 调大亮度（录制期照常）',
      );
      await brightnessGesture.up();
      await tester.pump();

      expect(engine.seekCalls, isEmpty, reason: '音量/亮度不动位置');
      expect(engine.isPlaying, isTrue, reason: '音量/亮度不动播放态');
      expect(camera.isRecording, isTrue);
    });

    testWidgets('录制期越过视频尾：不出现尾点循环提示、不发生一个八拍后回片头起播', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      await enterCompare(tester);

      // 无激活段：起点 = 按下位置 27s、有效区间尾 = 视频尾 30s（一拍 = 500ms，
      // 距尾 3s > 一拍，可起录）。
      await beginRecording(tester, at: const Duration(seconds: 27));

      // 越过视频尾（+自停）之后再过一整个八拍：尾点提示的倒计时若生效，这
      // 一刻就会「回片头起播」。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 5));

      expect(
        engine.position,
        const Duration(seconds: 30),
        reason: '录制期不发生整片循环：位置不回到片头',
      );
      expect(engine.isPlaying, isFalse, reason: '不得自动回片头起播');
      expect(camera.isRecording, isFalse, reason: '尾点即停录入库');
      expect(
        find.byKey(const Key('loop_prompt')),
        findsNothing,
        reason: '录制期尾点循环提示（与它的倒计时）一并抑制',
      );
      expect(await readManifest().then((d) => d.materials), hasLength(1));
    });
  });
}
