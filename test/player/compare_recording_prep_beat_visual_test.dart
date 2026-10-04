/// 录制准备的可视数拍（时钟来源与锚口径）：
/// 按下录制之后、起录之前的那几拍准备期，数拍浮层要显示**「第 0 个八拍顺数」**
/// （八拍号固定 0 + 拍号顺数）；越过起录点转正式数拍。
///
/// - 准备期数字由**准备拍序列**（起录点前可用的真实拍点，源自派生网格）与
///   媒介位置派生——与拍声同一刻推进（不再有控制器侧自由计时器）；
/// - 无激活段录制的锚 = **起录点对齐到其后最近的八拍大线**：起录点到该大线
///   之间按「第 0 个八拍顺数」呈现、过大线起 1｜1；
/// - 起录点前可用真实拍点少于设定拍数时**有几拍数几拍**（缩短）；
///   异常网格仍走秒制兜底：无数字、无声。
///
/// 断言的是**屏幕上渲染出来的两数**（`beat_count_leading` / `beat_count_practice`
/// 那套既有渲染），不是内部状态。
library;

import 'dart:io';

import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackState,
        beatGridProvider,
        beatPhaseProvider,
        beatTrackStateProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    show BeatPoint;
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationSelectionDomainProvider, annotationEditorProvider;
import 'package:dance_learning_app/player/beat_animation.dart'
    show deriveBeatPhase;
import 'package:dance_learning_app/player/beat_presentation_providers.dart'
    show beatCountPositionProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/device_viewport.dart';

void main() {
  group('录制准备的可视数拍', () {
    late FakePlaybackEngine engine;
    late FakeCameraCaptureService camera;
    late File materialOutputFile;

    /// 设备等效视口（`2736×1264 @3.5` = 781.7×361.1dp，与开发真机横屏一致；
    ///  ≠ 存在性」）：录制钮也在本视口下按下，
    /// 免得宽视口把对比态顶栏/录制钮的溢出路径整条遮掉。
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
            materialManifestStorageProvider.overrideWithValue(
              MemoryManifestStorage(),
            ),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => materialOutputFile,
            ),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
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
      // 节拍动画总开关默认关——本组用例针对数拍浮层机制，先置开。
      turnBeatAnimationOn(tester);
      await tester.pump();
    }

    ProviderContainer containerOf(WidgetTester tester) =>
        ProviderScope.containerOf(
          tester.element(find.byType(PlayerPage)),
          listen: false,
        );

    /// 就绪节拍网格：拍点每 [stepSec] 一个自 [fromSec] 起、每 4 拍一个强拍
    /// （4/4）。八拍大线 = 强拍序数奇数者 = 自首个强拍起每 8 拍一条
    /// （stepSec = 0.5 时 t = 0 / 4 / 8 / 12 / 16 …）。
    ///
    /// [stepSec] 取 0.1 的整数倍：假引擎每 100ms 推进一格（[FakePlaybackEngine.tick]），
    /// 拍距不是整数倍时逐拍累积漂移会让末拍数字错过。
    void givenGrid(
      WidgetTester tester, {
      int beats = 60,
      double fromSec = 0,
      double stepSec = 0.5,
    }) {
      // 节拍动画总开关默认关——本组用例钉准备期数字内容，先置开。
      turnBeatAnimationOn(tester);
      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(
            BeatTrackState.ready(
              marker_doc.BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 14),
                shift: 0,
                beats: [
                  for (var i = 0; i < beats; i++)
                    BeatPoint(t: fromSec + i * stepSec, down: i % 4 == 0),
                ],
              ),
            ),
          );
    }

    /// 建学习段 [startMs]–20s 并激活第 1 段。
    void givenActiveSegment(WidgetTester tester, int startMs) {
      final editor = containerOf(tester).read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: Duration(milliseconds: startMs)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      containerOf(tester)
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(1);
    }

    Future<void> enterCompare(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
    }

    Future<void> pressRecordAt(WidgetTester tester, Duration at) async {
      await engine.seek(at);
      await tester.pump(const Duration(milliseconds: 1));
      engine.seekCalls.clear();
      await tester.tap(find.byKey(const Key('compare_record_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
    }

    /// 矩形动画「当前格」的格序（1–8）——与动画同一份相位纯件派生
    /// （`deriveBeatPhase` 的 `beatInCycle + 1` 就是动画高亮的格序）。
    int animationCell(WidgetTester tester) {
      final container = containerOf(tester);
      return deriveBeatPhase(
            grid: container.read(beatGridProvider),
            position: container.read(beatCountPositionProvider)!,
            phase: container.read(beatPhaseProvider),
          ).beatInCycle +
          1;
    }

    /// 屏幕上数拍数字的两数（前导区 `L 八拍号|拍号` / 练习区 `P …` /
    /// 无数字 `-`）。
    String beatCountOnScreen(WidgetTester tester) {
      final leading = find.byKey(const Key('beat_count_leading'));
      final practice = find.byKey(const Key('beat_count_practice'));
      final String tag;
      if (leading.evaluate().isNotEmpty) {
        tag = 'L';
      } else if (practice.evaluate().isNotEmpty) {
        tag = 'P';
      } else {
        return '-';
      }
      final eight = tester.widget<Text>(
        find.byKey(const Key('beat_count_eight')),
      );
      final beat = tester.widget<Text>(
        find.byKey(const Key('beat_count_beat')),
      );
      return '$tag ${eight.data}|${beat.data}';
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      camera = FakeCameraCaptureService();
      materialOutputFile = File('/tmp/unused_prep_visual.mp4');
    });

    testWidgets('有激活段：准备期第 0 个八拍顺数（0|1…0|8），越过起录点转 1|1（行为不变）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      givenActiveSegment(tester, 8000);
      await enterCompare(tester);

      // 起录点 = 段首 8s（本身即八拍大线）；准备拍数默认 8 → 从第 8 个真实
      // 拍点 4.0s 起播。
      await pressRecordAt(tester, const Duration(seconds: 12));
      expect(engine.seekCalls.last, const Duration(seconds: 4));
      // 设备等效视口下这一按真的按到了（红点亮 = 已进准备态）。
      expect(
        find.byKey(const Key('compare_recording_indicator')),
        findsOneWidget,
      );

      for (var beat = 1; beat <= 8; beat++) {
        expect(
          beatCountOnScreen(tester),
          'L 0|$beat',
          reason: '准备期第 $beat 拍（位置 ${engine.position}）',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      // 越过起录点（8s）→ 正式数拍：段首在大线上 → 恒等对齐 → 1｜1 起。
      expect(camera.startRecordingCalls, hasLength(1));
      expect(beatCountOnScreen(tester), 'P 1|1');
    });

    testWidgets('无激活段：起录点吸附到相位最近八拍点，预备 0|x 顺数、越起点起 1|1', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await enterCompare(tester);

      // 无激活段：按下 13.0s 吸附到最近八拍点 12.0s→ 准备期
      // 8 拍 = 8.0s–11.5s，起播点 8.0s。
      await pressRecordAt(tester, const Duration(seconds: 13));
      expect(engine.seekCalls.last, const Duration(seconds: 8));

      for (var beat = 1; beat <= 8; beat++) {
        expect(
          beatCountOnScreen(tester),
          'L 0|$beat',
          reason: '准备期第 $beat 拍（位置 ${engine.position}）',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      // 越过起录点（12.0s）→ 起录点即八拍点：正式数拍 1｜1 起，数字与
      // 矩形动画同落在八拍首格（三方同源相位）。
      expect(camera.startRecordingCalls, hasLength(1));
      expect(beatCountOnScreen(tester), 'P 1|1');
      expect(animationCell(tester), 1, reason: '起录点即八拍点：数字与动画同落八拍首');
    });

    testWidgets('起录点吸附后前导回退照常：吸附点前 N 个真实拍点起播（不整块静默）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await enterCompare(tester);

      // 无激活段：按下 3.0s 吸附到八拍点 4.0s→ 前导 8 拍回退到
      // 0.0s（4.0s 前第 8 个真实拍点）。
      await pressRecordAt(tester, const Duration(seconds: 3));
      expect(engine.seekCalls.last, Duration.zero);

      for (var beat = 1; beat <= 8; beat++) {
        expect(
          beatCountOnScreen(tester),
          'L 0|$beat',
          reason: '第 $beat 个准备拍（吸附点 4.0s 前第 $beat 拍）',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }
      expect(camera.startRecordingCalls, hasLength(1), reason: '越过起录点即起录');
    });

    testWidgets('异常网格：无数字、无声（秒制兜底）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await enterCompare(tester);

      await pressRecordAt(tester, const Duration(seconds: 12));

      for (var i = 0; i < 3; i++) {
        expect(beatCountOnScreen(tester), '-', reason: '异常网格无数字');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }
    });

    testWidgets('真机同款按下位置（无激活段、92.292s，拍距取整 0.3s）：准备期数字 0|1…0|8（取证支）', (
      tester,
    ) async {
      // 2026-09-14 真机取证（开发素材 mmexport1788144136634.mp4）：无激活段按下
      // 92.292s → 真机日志 `press=92292 rangeStart=1070 beatLed=true times=8
      // [89850…92030]`、`gridPhase=ready`、`overlayVisible=true`、`leadingDisplayAt`
      // 逐拍交 0|1…0|8（真机截图同款）。**同款的是按下位置**：真机网格非均匀
      // （首拍 1.07s、拍距 305–330ms），此处用合成均匀网格（首拍 1.4s、拍距
      // 0.3s——取 0.1 的整数倍以贴合假引擎 100ms tick，避免逐拍累积漂移）。
      // 无激活段按下位置大（> 8 拍）时两种网格都落在**节拍前导支**，故本用例
      // 钉的是「按下位置在区间头之后 → 准备期有数字」这一支。
      setDeviceView(tester);
      engine = FakePlaybackEngine(duration: const Duration(minutes: 4));
      await pumpPlayer(tester);
      givenGrid(tester, beats: 600, fromSec: 1.4, stepSec: 0.3);
      await enterCompare(tester);

      await pressRecordAt(tester, const Duration(milliseconds: 92292));
      // 按下 92.292s 吸附到最近八拍点 92.6s（八拍点 = 1.4s + 2.4s·k）；
      // 8 拍回退：起播点 = 92.6s 前第 8 个真实拍点（92.6 − 8×0.3 = 90.2s）。
      expect(engine.seekCalls.last, const Duration(milliseconds: 90200));

      // 逐格推进收集屏幕上的两数（每格 100ms），去重后必须是 0|1…0|8 顺数。
      // 上限 = 准备期 2.392s + 余量（每格 100ms），够走到越过起录点转录制。
      final seen = <String>[];
      for (var i = 0; i < 30; i++) {
        final onScreen = beatCountOnScreen(tester);
        if (onScreen == '-' || onScreen.startsWith('P ')) break;
        if (seen.isEmpty || seen.last != onScreen) seen.add(onScreen);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(seen, [
        for (var beat = 1; beat <= 8; beat++) 'L 0|$beat',
      ], reason: '真机取证支：准备期数字按准备拍序列顺数（与拍声同一刻推进）');
      expect(camera.startRecordingCalls, hasLength(1), reason: '越过起录点即起录');
    });

    testWidgets('按下位置即有效区间头（起录点 = 区间头，room = 0）：无数字、无浮层、无声、到点即起录（口径支）', (
      tester,
    ) async {
      // 真机「屏幕上没有数字」判定支之一（2026-09-14 取证：`press=33
      // rangeStart=1070 start=1070 leadDur=0 beatLed=false times=0` →
      // `visual=RecordingPrepSilentBeat()` → `overlayVisible=false`）：按下位置
      // 早于/等于有效区间头 → 起录点被钳到区间头 → `computeRecordingPrep` 在
      // `room <= 0`（起点即区间头）这一支返回**无前导** → 准备期整段无数字、
      // 无声、按下即起录。
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await enterCompare(tester);
      expect(
        beatCountOnScreen(tester),
        startsWith('P '),
        reason: '按下之前练习态本来有数字（网格就绪）',
      );

      // 无前导支的准备期长度为 0（按下即武装 → 越点即起录），故给起录一个
      // 落定延迟，把那一瞬拉长到可断言（真机取证日志：`startRequested`
      // 08:02:42.270 → `phase=recording` 08:02:42.359，约 89ms）。
      camera.startRecordingLatency = const Duration(milliseconds: 300);
      await pressRecordAt(tester, Duration.zero);
      await tester.pump(const Duration(milliseconds: 100));
      // 无前导：准备期长度为 0 → 浮层整段不挂载（无数字，也不落回锚点链的数）。
      expect(beatCountOnScreen(tester), '-', reason: '无前导支：准备期无数字（浮层不挂载）');

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(camera.startRecordingCalls, hasLength(1), reason: '到点即起录（无准备拍）');
    });

    testWidgets('起录点即网格首拍（其前无可用拍点）：无数字无声，且**不是**秒制兜底（口径支）', (tester) async {
      // 另一支「无数字」：`room > 0` 但起录点前**一个真实拍点都没有**
      // （`computeRecordingPrep` 的 `times.isEmpty` 支）。它与秒制兜底必须可分辨
      // ——秒制兜底会退回 ≈4s 那一档（`kRecordingPrepFallbackMs`），无前导支不
      // 回退、按下点即起播点，故用 seek 目标把两支分开。
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester, fromSec: 20);
      await enterCompare(tester);

      // 同上一例：无前导的准备期长度为 0，给武装一个落定延迟才看得见那一瞬。
      camera.startRecordingLatency = const Duration(milliseconds: 300);
      // 按下 13s 吸附到网格首个八拍点 20s（网格自 20s 起）→ 起录点
      // 即网格首拍，其前无可用拍点 → 无前导支。
      await pressRecordAt(tester, const Duration(seconds: 13));
      await tester.pump(const Duration(milliseconds: 100));
      expect(beatCountOnScreen(tester), '-', reason: '无可用拍点：准备期无数字（浮层不挂载）');

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        engine.seekCalls.last,
        const Duration(seconds: 20),
        reason: '无前导：起播点 = 起录点（不落回秒制兜底的 起录点−4s = 16s）',
      );
      expect(camera.startRecordingCalls, hasLength(1), reason: '到点即起录（无准备拍）');
    });

    testWidgets('准备期中离开播放页：下次打开不残留上一会话的前导数字', (tester) async {
      setDeviceView(tester);
      final source = Uri.file('/videos/a.mp4');
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(camera),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            materialManifestStorageProvider.overrideWithValue(
              MemoryManifestStorage(),
            ),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            materialRecordingFileResolverProvider.overrideWithValue(
              (videoId) async => materialOutputFile,
            ),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
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
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerPage(source: source),
                    ),
                  ),
                  child: const Text('打开播放器'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开播放器'));
      await tester.pumpAndSettle();
      givenGrid(tester);
      await enterCompare(tester);
      await pressRecordAt(tester, const Duration(seconds: 12));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(beatCountOnScreen(tester), 'L 0|2', reason: '准备期确实在顺数');

      // 准备期未走完就离开播放页：dispose 时监听已摘，值道不再回写——留着
      // 上一会话的前导基准会让下次打开时浮层显示一个假数字。
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开播放器'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(
        beatCountOnScreen(tester),
        isNot(startsWith('L ')),
        reason: '新会话未在准备期，不得残留上一会话的第 0 个八拍顺数',
      );
    });
  });
}
