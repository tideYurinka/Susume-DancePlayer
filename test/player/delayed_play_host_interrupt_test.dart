/// 延迟播放的宿主接线：打断表逐行。
///
/// 断言的是**外部可观察状态**：引擎调用序列（seek/play/pause）、延迟锚
/// 值道（`delayAnchorProvider`，数拍锚点链消费）、提示声起收——不测私有
/// 字段、不测渲染细节。音量 / 亮度 / 倍速与收起控制层**不**打断也在此
/// 钉住（打断判据收敛为「播放态 / 媒介位置 / 所在层任一被改动」）。
library;

import 'dart:io' show File;

import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/persistence/marker_document.dart'
    show BeatPoint;
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/delayed_play.dart' show delayedPlayPreparingProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/beat_presentation_providers.dart'
    show delayAnchorProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
  group('延迟播放宿主接线：打断表逐行', () {
    late FakePlaybackEngine engine;
    late FakeSystemMediaVolumeController volume;
    late File materialOutputFile;

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      volume = FakeSystemMediaVolumeController();
      materialOutputFile = File('/tmp/unused_delayed_host.mp4');
    });

    void setDeviceView(WidgetTester tester) {
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
    }

    Future<void> pumpPlayer(WidgetTester tester) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            cameraCaptureProvider.overrideWithValue(
              FakeCameraCaptureService(),
            ),
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

    /// 就绪真实网格：500ms 一拍、60 拍；八拍点在 0、4s、8s、12s、16s…。
    void givenGrid(WidgetTester tester) {
      containerOf(tester).read(beatTrackStateProvider.notifier).replace(
            BeatTrackState.ready(
              marker_doc.BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 14),
                beats: [
                  for (var i = 0; i < 60; i++)
                    BeatPoint(t: i * 0.5, down: i % 4 == 0),
                ],
              ),
            ),
          );
    }

    /// 触发延迟（位置 [at]）：编辑态点工具条「延迟播放」钮（先收起后触发）
    /// ——起点 = 位置后最近八拍点，触发后引擎在播。
    Future<void> triggerAt(WidgetTester tester, Duration at) async {
      await engine.seek(at);
      await tester.pump();
      // 单击画面左下空白（避开中央浮层）= 唤出控制层。
      final tap = await tester.startGesture(const Offset(120, 320));
      await tap.up();
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar_delayed_play')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();
    }

    Future<void> triggerAt15s(WidgetTester tester) =>
        triggerAt(tester, const Duration(seconds: 15));

    Duration? anchorOf(WidgetTester tester) =>
        containerOf(tester).read(delayAnchorProvider);

    bool preparingFactOf(WidgetTester tester) =>
        containerOf(tester).read(delayedPlayPreparingProvider);

    testWidgets('触发即倒回预备起点连续播，延迟锚就位（基线）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);

      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      expect(engine.isPlaying, isTrue);

      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));
      expect(engine.seekCalls.last, const Duration(seconds: 14));
      expect(engine.isPlaying, isTrue);
      expect(preparingFactOf(tester), isTrue,
          reason: '预备期 = preparing，记账事实道置真（预备期不计）');
    });

    testWidgets('预备期事实道：越过起点即翻回（照常计入）；打断也翻回', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await triggerAt15s(tester);
      expect(preparingFactOf(tester), isTrue);

      // 位置越过起点（16s）：转 active，预备期事实撤销——播放照常计入。
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(preparingFactOf(tester), isFalse,
          reason: '越过起点后按观看态照常计入');

      // 再触发回 preparing，随后暂停（停沿打断）也翻回。
      await triggerAt15s(tester);
      expect(preparingFactOf(tester), isTrue);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump();
      expect(preparingFactOf(tester), isFalse, reason: '打断即预备作废');
    });

    testWidgets('引擎转停沿（用户暂停）打断：撤锚、作废预备、不改播放态语义', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 单指双击 = 暂停：引擎停沿即打断。
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump();
      expect(engine.isPlaying, isFalse);
      expect(anchorOf(tester), isNull, reason: '停沿即撤锚');

      // 打断后不再有「到点自己起播」。
      await tester.pump(const Duration(seconds: 5));
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('任何 seek（三指跳转，经 seek 唯一提交口）打断', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 三指左滑 = 跳转视频首（经 SeekSubmitter 的 seek）。
      final g1 = await tester.startGesture(const Offset(400, 300));
      final g2 = await tester.startGesture(const Offset(440, 300));
      final g3 = await tester.startGesture(const Offset(480, 300));
      await tester.pump();
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(-60, 0));
      await g3.moveBy(const Offset(-60, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pumpAndSettle();

      expect(anchorOf(tester), isNull, reason: 'seek 即撤锚');
    });

    testWidgets('唤出控制层（进编辑态）打断；编辑态点延迟钮 = 先收起后触发（不撤锚）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 单击（画面空白处，避开中央浮层）= 唤出控制层（进编辑态）→ 打断。
      await tester.tap(find.byKey(const Key('player_surface')), warnIfMissed: false);
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
      expect(anchorOf(tester), isNull, reason: '唤出控制层即撤锚');

      // 编辑态点延迟钮 = 先收起后触发：收起（控制层 → 播放态）不在此列，
      // 触发本身重新设锚。
      await engine.seek(const Duration(seconds: 15));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar_delayed_play')));
      await tester.pump();
      await tester.pump();
      expect(anchorOf(tester), const Duration(seconds: 16));
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('再次触发 = 重设（锚随新位置重算），不是 no-op 也不是两次叠加', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 摆到 9s 再触发：起点 = 8s。
      await triggerAt(tester, const Duration(seconds: 9));
      expect(anchorOf(tester), const Duration(seconds: 8));
      expect(engine.seekCalls.last, const Duration(seconds: 6));
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('退后台打断（didChangeAppLifecycleState paused 显式收口）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 退后台：不依赖内核的退后台停播行为，宿主显式打断。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(anchorOf(tester), isNull, reason: '退后台即撤锚');
    });

    testWidgets('音量变化（应用外侧键经系统音量流）不打断；倍速调整不打断', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await triggerAt15s(tester);
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 应用外音量变化（侧键）：经系统音量流推进基线，不打断延迟。
      volume.emitExternal(0.2);
      await tester.pump();
      await tester.pump();
      expect(anchorOf(tester), const Duration(seconds: 16));

      // 倍速调整（含长按瞬态 2× 的引擎落点 setRate）：媒介位置与所在层都
      // 没被改动，不打断。
      await engine.setRate(2.0);
      await tester.pump();
      await tester.pump();
      expect(anchorOf(tester), const Duration(seconds: 16));
    });
  });
}
