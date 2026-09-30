/// 录制准备期 + 延迟播放倒计时的**视频区正中大数字**：让用户一眼
/// 看出「**现在还没有开录**」。
///
/// 与既有数拍浮层的关系 = **同一份发布值**：居中
/// 大数字与浮层数拍取同一份 `八拍号｜拍号`（前导区 `0｜x`），逐拍一致；数据
/// 源 = 节拍呈现对象的发布值（录制锚 / 延迟锚经锚点链派生），无第二套计数。
///
/// 断言的是**屏幕上渲染出来的文本与几何**（`prep_center_big_number` 键），
/// 不是内部状态。
library;

import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
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
import 'package:dance_learning_app/player/beat_presentation_providers.dart'
    show delayAnchorProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationSelectionDomainProvider, annotationEditorProvider;
import '../helpers/video_surface.dart' show videoSurfacePlaceholderKey;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/core/current_beat.dart' show LeadingBeatCount;
import 'package:dance_learning_app/player/prep_center_big_number.dart'
    show prepCenterBigNumberOf;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
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
  group('录制准备期视频中心大数字', () {
    late FakePlaybackEngine engine;
    late FakeCameraCaptureService camera;
    late File materialOutputFile;

    /// 设备等效视口（`2736×1264 @3.5` = 781.7×361.1dp，与开发真机横屏一致）。
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
    /// （与准备期可视数拍同一套夹具，拍距取 0.1 的整数倍贴合假引擎 100ms tick）。
    void givenGrid(
      WidgetTester tester, {
      int beats = 60,
      double fromSec = 0,
      double stepSec = 0.5,
    }) {
      containerOf(tester).read(beatTrackStateProvider.notifier).replace(
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

    /// 屏幕上那枚居中大数字的文本；未挂载 = `-`。
    String bigNumberOnScreen(WidgetTester tester) {
      final finder = find.byKey(const Key('prep_center_big_number'));
      if (finder.evaluate().isEmpty) return '-';
      final texts = find.descendant(of: finder, matching: find.byType(Text));
      expect(texts, findsOneWidget, reason: '大数字件只渲染一个文本');
      return tester.widget<Text>(texts).data!;
    }

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
      camera = FakeCameraCaptureService();
      materialOutputFile = File('/tmp/unused_prep_big_number.mp4');
    });

    testWidgets('普通练习的前导段（激活段首晚于当前位置）：浮层亮 0｜x，居中大数字不亮（范围钉在两支预备期）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      givenActiveSegment(tester, 8000);

      // 在播状态摆到段首之前 4s：锚点链推出前导，浮层显示 0｜x——但这一
      // 刻不属于录制准备 / 延迟预备，居中大数字不跟（显示范围钉在两支
      // 预备期）。
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await engine.seek(const Duration(seconds: 4));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('beat_count_leading')), findsOneWidget,
          reason: '前提：此刻浮层确实在前导口径上');
      expect(bigNumberOnScreen(tester), '-', reason: '非预备期的前导不亮大数字');
    });

    testWidgets('准备期：视频区正中显示大数字 = 前导顺数 0｜1…0｜8（与浮层数拍同一份），逐拍跳动', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      givenActiveSegment(tester, 8000);
      await enterCompare(tester);

      // 按下前（非准备期）没有这枚数字——它是准备期的提示，不是常驻件。
      expect(bigNumberOnScreen(tester), '-', reason: '非准备期不显示');

      await pressRecordAt(tester, const Duration(seconds: 12));

      for (var beat = 1; beat <= 8; beat++) {
        expect(
          bigNumberOnScreen(tester),
          '0｜$beat',
          reason: '准备期第 $beat 拍：大数字 = 浮层数拍同一份 0｜x（位置 ${engine.position}）',
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      // 越过起录点：进正式录制态。
      expect(camera.startRecordingCalls, hasLength(1));
    });

    testWidgets('起录瞬间消失：正式录制态不挂载，且不影响既有数拍浮层（0|3 那件照旧）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      givenActiveSegment(tester, 8000);
      await enterCompare(tester);

      await pressRecordAt(tester, const Duration(seconds: 12));
      expect(bigNumberOnScreen(tester), '0｜1', reason: '准备期在显示');
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      expect(
        containerOf(tester).read(compareRecordingPhaseProvider),
        CompareRecordingPhase.recording,
        reason: '越过起录点即起录',
      );
      expect(bigNumberOnScreen(tester), '-', reason: '起录即消失');
      // 既有数拍浮层照旧：正式录制态是练习区两数（1 起），本用例不动它的
      // 位置与外观。
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byKey(const Key('beat_count_leading')), findsNothing);
    });

    testWidgets('延迟播放预备：倒回起点前 4 拍连续播，大数字 0｜5…0｜8（与浮层同份）、越起点即消失并 1|1 起数', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);

      // 在播状态摆到 15s：起点 = 最近八拍点 16s，预备 = 14s…15.5s（拍号
      // 5、6、7、8——白数即普通状态在该位置的真实拍号）。
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      expect(engine.isPlaying, isTrue, reason: '打开即播：媒介时钟在走');
      await engine.seek(const Duration(seconds: 15));
      await tester.pump();

      await tester.tap(find.byKey(const Key('toolbar_delayed_play')));
      await tester.pump();
      await tester.pump();
      // 触发即倒回预备起点连续播：seek(14s) + play，延迟锚就位。
      expect(engine.seekCalls.last, const Duration(seconds: 14));
      expect(engine.isPlaying, isTrue);
      expect(
        containerOf(tester).read(delayAnchorProvider),
        const Duration(seconds: 16),
        reason: '触发即交出延迟锚（预备区 0|x 与越点 1|1 同一锚派生）',
      );
      // 预备区浮层 = 第 0 个八拍顺数（0|5…0|8）。
      expect(find.byKey(const Key('beat_count_leading')), findsOneWidget);

      // 大数字随媒介位置逐拍推进：0｜5、0｜6、0｜7、0｜8（不靠第二只钟）。
      const beat = Duration(milliseconds: 500);
      for (final number in <int>[5, 6, 7, 8]) {
        final target = const Duration(seconds: 14) + beat * (number - 5) + beat ~/ 2;
        await engine.seek(target);
        await tester.pump();
        await tester.pump();
        expect(
          bigNumberOnScreen(tester),
          '0｜$number',
          reason: '预备第 \${number - 4} 拍：大数字 = 浮层数拍同一份 0｜x',
        );
      }

      // 越过起点：大数字消失、预备区浮层让位练习区（1|1 起数）。
      await engine.seek(const Duration(seconds: 16));
      await tester.pump();
      await tester.pump();
      expect(
        containerOf(tester).read(delayAnchorProvider),
        const Duration(seconds: 16),
      );
      expect(bigNumberOnScreen(tester), '-', reason: '越起点即消失');
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.byKey(const Key('beat_count_leading')), findsNothing);
    });

    testWidgets('暂停中触发：照样起播（画面、拍声、数字照常推进）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);

      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      expect(engine.isPlaying, isFalse, reason: '暂停到确定态');
      await engine.seek(const Duration(seconds: 15));
      await tester.pump();

      await tester.tap(find.byKey(const Key('toolbar_delayed_play')));
      await tester.pump();
      await tester.pump();
      // 暂停中触发 = 倒回预备起点连续播：不再有「数字冻住、无声干等」。
      expect(engine.isPlaying, isTrue, reason: '触发即起播');
      expect(engine.seekCalls.last, const Duration(seconds: 14));
      expect(bigNumberOnScreen(tester), '0｜5', reason: '预备区有数字');
    });

    testWidgets('异常网格（秒制兜底）：无数字、无声，也不显示这枚大数字', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      await enterCompare(tester);

      await pressRecordAt(tester, const Duration(seconds: 12));
      for (var i = 0; i < 3; i++) {
        expect(bigNumberOnScreen(tester), '-', reason: '异常网格无数字（秒制兜底不显示）');
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }

      // 倒计时同样不显示（异常网格这一支的倒计时自检见
      // `delayed_play_test.dart` 的「异常网格：倒计时也无每拍号」——录制期
      // 手势/控制层整体停用，部件面在这一态取不到触发的入口）。
    });

    testWidgets('无前导支（起录点前无可用真实拍点）：无数字、无声，也不显示这枚大数字', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester, fromSec: 20);
      await enterCompare(tester);

      camera.startRecordingLatency = const Duration(milliseconds: 300);
      await pressRecordAt(tester, const Duration(seconds: 13));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        bigNumberOnScreen(tester),
        '-',
        reason: '无前导支不显示（「没有网格」与「有网格但不足」必须可分辨）',
      );
      // 收尾武装落定（到点即起录），免留下在途定时器。
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    });

    testWidgets('准备期中网格转异常：大数字跟着消失（与数拍浮层同一句话）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      givenActiveSegment(tester, 8000);
      await enterCompare(tester);

      await pressRecordAt(tester, const Duration(seconds: 12));
      expect(bigNumberOnScreen(tester), '0｜1', reason: '准备期在显示');

      // 网格转异常：数拍浮层整段不显示，这枚大数字也不该还挂着
      // （两支要可分辨，不是漏出一支）。
      containerOf(tester)
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      // 大数字与浮层同走发布链（上下文变化 → onFrame 重发布 → 消费方重建）：
      // 第二次 pump 让这条异步链在断言前落定。
      await tester.pump();
      await tester.pump();
      expect(bigNumberOnScreen(tester), '-', reason: '异常网格无数字');
    });

    testWidgets('位置：整个视频区几何中心（分屏下跨素材侧/练习侧居中）', (tester) async {
      setDeviceView(tester);
      await pumpPlayer(tester);
      givenGrid(tester);
      await enterCompare(tester);

      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      await pressRecordAt(tester, const Duration(seconds: 12));

      final bigNumber = find.byKey(const Key('prep_center_big_number'));
      expect(bigNumber, findsOneWidget);
      final center = tester.getCenter(bigNumber);
      // 分屏两块：源侧左半、练习侧右半、之间留细缝——两块之间就是**整个
      // 视频区的几何中心**，而不是任一半区的中心。
      final sourceRect = tester.getRect(
        find.byKey(videoSurfacePlaceholderKey),
      );
      final practiceRect = tester.getRect(
        find.byKey(const Key('fake_camera_preview')),
      );
      expect(sourceRect.center.dx, lessThan(view.width / 2));
      expect(practiceRect.center.dx, greaterThan(view.width / 2));
      final seam = (sourceRect.right + practiceRect.left) / 2;
      expect(center.dx, closeTo(seam, 1.0), reason: '大数字水平居中于整个视频区');
      expect(center.dx, closeTo(view.width / 2, 1.0), reason: '分屏下跨两侧居中');
      expect(center.dy, closeTo(view.height / 2, 1.0), reason: '垂直居中');
      // 位置在视频区中心 ⇒ 与既有控件命中区（录制钮在底部居中、取景条在中部、
      // 工具区在上下缘）不重叠。
      expect(
        tester
            .getRect(find.byKey(const Key('compare_record_button')))
            .contains(center),
        isFalse,
        reason: '不落在录制钮命中区上',
      );
    });
  });

  group('视频区正中大数字的取值口径（纯件 seam）', () {
    test('前导区：取与浮层数拍同一份「八拍号｜拍号」（0｜x）', () {
      for (var x = 1; x <= 8; x++) {
        expect(
          prepCenterBigNumberOf(LeadingBeatCount(beatCount: x)),
          '0｜$x',
          reason: '第 $x 拍：大数字与浮层数拍同份（不是只取每拍号）',
        );
      }
    });
  });
}
