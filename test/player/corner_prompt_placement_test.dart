import 'dart:io';

import 'package:dance_learning_app/annotation/annotation_timeline.dart'
    show AnnotationTimeline;
import 'package:dance_learning_app/annotation/note_sticker.dart'
    show NoteSticker;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/beat_grid.dart' show placeholderBeatGrid;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/video_identity.dart' show ContentHasher;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationRestoreDocument, annotationEditorProvider;
import 'package:dance_learning_app/player/compare_framing_view.dart'
    show compareFramingPictureRect;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/control_layer.dart' show ControlLayer;
import 'package:dance_learning_app/player/level_control.dart'
    show screenBrightnessControllerProvider;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player/note_editor.dart'
    show NoteTextEditorPanel, noteTextEditorTargetProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart'
    show practiceClipEngineProvider;
import 'package:dance_learning_app/player/resume_position.dart'
    show resumePromptProvider;
import 'package:dance_learning_app/player/resume_prompt.dart'
    show ResumePromptOverlay;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/fake_brightness.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/stack_paint_order.dart';
import '../helpers/video_index_fixtures.dart';

/// 「提示卡贴画面左下角」：整页接缝（卡落在画面矩形的
/// 哪一角、放不下时不画、编辑态卡不压 chrome、点卡不收起控制层、四层命中
/// 顺序、对比-播放态锚源半区）与卡 widget 缝（传什么锚落什么位置、锚为
/// null 不渲染）。
///
/// 几何纯件（落位三步的数值）在 `editor_skeleton_test.dart` 直测；本文件只
/// 钉外部行为，期望值取号机基准（361.1 × 781.7dp，dpr 1.0 即逻辑尺寸）。
class _FixedHasher implements ContentHasher {
  const _FixedHasher(this.value);

  final String value;

  @override
  Future<String> hashFile(File file) async => value;
}

void main() {
  /// 号机竖屏基准屏与横屏基准屏（padding 为 0，逻辑尺寸即实数）。
  const portrait = Size(361.1, 781.7);
  const landscape = Size(781.7, 361.1);

  /// 单击唤出控制层（等自定义双击识别器判定孤立单击）。
  Future<void> singleTapShow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 收起控制层（对比编辑态 → 对比-播放态）：画面上的孤立单击被控制层空白
  /// 手势面接管，故不要求命中原件。
  Future<void> collapseControlLayer(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('player_surface')),
      warnIfMissed: false,
    );
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  /// 设系统手势内缩（按当前测试面 dpr 换算成物理像素）。
  void setGestureInsets(
    WidgetTester tester, {
    double bottom = 0,
    double left = 0,
  }) {
    addTearDown(tester.view.reset);
    final dpr = tester.view.devicePixelRatio;
    tester.view.systemGestureInsets = FakeViewPadding(
      bottom: bottom * dpr,
      left: left * dpr,
    );
  }

  /// 竖屏编辑态各段 chrome 的具名落点（看片工具行 / 设置条 / 轨道带 / 底栏
  /// 两行）：卡与它们逐段不相交 = 没压住任何编辑入口。
  const editingChrome = <String, Key>{
    '看片工具行': Key('control_layer_video_toolbar'),
    '设置条': Key('settings_cluster'),
    '轨道带': Key('track_band'),
    '底栏标注工具行': Key('control_layer_annotation_row'),
    '底栏播放控制工具行': Key('control_layer_toolbar'),
  };

  /// 卡矩形不压编辑态 chrome 的任何一段，且与控制层 chrome 最上缘留出占用区
  /// 间隙（每段都须在场、非零尺寸，防断言空转）。
  void expectCardClearOfEditingChrome(WidgetTester tester, Rect card) {
    var chromeTop = double.infinity;
    for (final chrome in editingChrome.entries) {
      final rect = tester.getRect(find.byKey(chrome.value));
      expect(rect.width, greaterThan(0), reason: '${chrome.key} 在场且非零宽');
      expect(rect.height, greaterThan(0), reason: '${chrome.key} 在场且非零高');
      expect(
        card.overlaps(rect),
        isFalse,
        reason: '卡 $card 不压${chrome.key} $rect',
      );
      chromeTop = chromeTop < rect.top ? chromeTop : rect.top;
    }
    expect(
      chromeTop - card.bottom,
      greaterThanOrEqualTo(24 - 0.05),
      reason: '卡底抬到控制层 chrome 上缘之上 24dp（占用区间隙）',
    );
  }

  /// 竖屏编辑态的卡角基准（号机 361.1 × 781.7dp）：贴画面左缘 +24、底边抬到
  /// 占用区上缘（画面区下缘 317.7 = 顶栏 52 + 画面区 265.7）之上 24dp——
  /// 横向源与竖向源同一条落位。
  Rect expectPortraitEditingCorner(WidgetTester tester, Finder card) {
    final rect = tester.getRect(card);
    expect(rect.left, closeTo(24, 0.01), reason: '左 = 画面左缘 + 24');
    expect(rect.bottom, closeTo(317.7 - 24, 0.05), reason: '底 = 占用区上缘 − 24');
    return rect;
  }

  /// 点一处屏幕坐标，等过自定义双击识别器判定孤立单击。
  Future<void> tapAtAndSettle(WidgetTester tester, Offset point) async {
    await tester.tapAt(point);
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  group('播放页整页接缝（真实打开路径）', () {
    Future<ProviderContainer> pumpPlayer(
      WidgetTester tester, {
      required Size logical,
      required FakePlaybackEngine engine,
      int lastPositionMs = 0,
    }) async {
      tester.view.physicalSize = logical;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // 收尾暂停引擎：倒计时/自动循环会让它转起来，不留悬挂计时器。
      addTearDown(engine.pause);
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
            screenBrightnessControllerProvider.overrideWithValue(
              FakeScreenBrightnessController(),
            ),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: source.toFilePath(),
                      mirrored: false,
                    ).copyWith(lastPositionMs: lastPositionMs),
                  ],
                ),
              ),
            ),
            contentHasherProvider.overrideWithValue(const _FixedHasher('seeded')),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
            // 对比态布景（练习半区会出场）：相机通路平台与两个引擎按真机注入。
            androidCameraPlatform(),
            cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
            practiceClipEngineProvider.overrideWithValue(
              FakePlaybackEngine(duration: const Duration(seconds: 20)),
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

    testWidgets('竖屏观看态 16:9：卡贴画面左下角，离屏幕底 300dp 以上', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 3),
        videoAspectRatio: 16 / 9,
      );
      await pumpPlayer(tester, logical: portrait, engine: engine);

      // 播放到尾 → 倒计时；控制层收起（观看态）。
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      // 画面矩形 = 满宽 contain 居中：(0, 289.3)–(361.1, 492.4)。
      final rect = tester.getRect(find.byKey(const Key('loop_prompt')));
      expect(rect.left, closeTo(24, 0.01), reason: '左 = 画面左缘 + 24');
      expect(
        rect.bottom,
        closeTo(492.4 - 24, 0.05),
        reason: '底 = 画面底边 − 24（基准不再是屏幕左下角）',
      );
      expect(
        781.7 - rect.bottom,
        greaterThan(300),
        reason: '卡离屏幕底 300dp 以上',
      );
      // 收窄后卡只占画面窄窄一条：画面 361.1 × 203.1dp。
      expect(
        rect.width / 361.1,
        lessThanOrEqualTo(0.52),
        reason: '卡占画面宽 ≤ 52%',
      );
      expect(
        rect.height / 203.1,
        lessThanOrEqualTo(0.26),
        reason: '卡占画面高 ≤ 26%',
      );
    });

    testWidgets('竖屏编辑态（横向源）：卡落在画面带左下角，点卡不收起控制层', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 3),
        videoAspectRatio: 16 / 9,
      );
      await pumpPlayer(tester, logical: portrait, engine: engine);
      await singleTapShow(tester);
      expect(
        find.byKey(const Key('control_layer')),
        findsOneWidget,
        reason: '前置：控制层已展开',
      );

      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      // 画面带底 317.7 = 画面区下缘：卡底抬到占用区上缘之上 24dp。
      final rect = expectPortraitEditingCorner(
        tester,
        find.byKey(const Key('loop_prompt')),
      );
      // 卡落在控制层 chrome 之外：不压看片工具行、设置条、轨道带与底栏。
      expectCardClearOfEditingChrome(tester, rect);

      // 反证：卡矩形之外的空白处单击 → 控制层照常被收起（落点取卡顶之上
      // 100dp：仍在顶栏之下的画面区空白里，不被顶栏或卡接管）。
      await tapAtAndSettle(tester, Offset(rect.left + 8, rect.top - 100));
      expect(
        find.byKey(const Key('control_layer')),
        findsNothing,
        reason: '空白处单击照常收起控制层',
      );

      // 重开控制层：点卡自身矩形内的两处空白（左内边距上下各一处）只算对卡
      // 的操作——卡不穿透到控制层空白手势面。
      await singleTapShow(tester);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      for (final point in [
        Offset(rect.left + 8, rect.top + 4),
        Offset(rect.left + 8, rect.center.dy),
      ]) {
        await tapAtAndSettle(tester, point);
        expect(
          find.byKey(const Key('control_layer')),
          findsOneWidget,
          reason: '点卡（$point）不穿透到控制层空白手势面',
        );
        expect(find.byKey(const Key('loop_prompt')), findsOneWidget);
      }

      // 点卡上的「不循环」：动作照旧发生，控制层留在原地。
      await tester.tap(find.byKey(const Key('loop_dismiss_button')));
      await tester.pump();
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      expect(engine.isPlaying, isFalse, reason: '停留于结尾，不自动循环');
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('竖屏编辑态（竖向源）：卡上抬到画面区下缘之上、不压 chrome', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 3),
        videoAspectRatio: 9 / 16,
      );
      await pumpPlayer(tester, logical: portrait, engine: engine);
      await singleTapShow(tester);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      // 竖向源的画面矩形是整屏 contain（下缘 711.8，卡原位会落进底栏工具行
      // 里）：占用区上抬那条规则把它抬到画面区下缘之上 24dp——反证它不是按
      // 画面矩形下缘落位。
      final rect = expectPortraitEditingCorner(
        tester,
        find.byKey(const Key('loop_prompt')),
      );
      expect(
        rect.bottom,
        lessThan(711.8 - 24 - 300),
        reason: '卡不是按整屏画面矩形的下缘落位（占用区上抬生效）',
      );
      expectCardClearOfEditingChrome(tester, rect);

      // 卡仍可点：点「不循环」后控制层不因此收起。
      await tester.tap(find.byKey(const Key('loop_dismiss_button')));
      await tester.pump();
      expect(find.byKey(const Key('loop_prompt')), findsNothing);
      expect(engine.isPlaying, isFalse, reason: '停留于结尾，不自动循环');
      expect(find.byKey(const Key('control_layer')), findsOneWidget);
    });

    testWidgets('编辑态层序与命中顺序：控制层 → 两张提示卡 → 备注文本编辑器 → 屏幕中央提示',
        (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 30),
        videoAspectRatio: 16 / 9,
      );
      final container = await pumpPlayer(
        tester,
        logical: portrait,
        engine: engine,
      );

      // 先展开控制层（编辑器面铺满后点画面只会收起编辑器），再让备注文本
      // 编辑器面进入编辑态（有目标备注 + 打开编辑目标）：层序钉的是有内容的
      // 槽，不是空占位。
      await singleTapShow(tester);
      expect(find.byKey(const Key('control_layer')), findsOneWidget);

      container.read(annotationEditorProvider).restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(const Duration(seconds: 30)),
          notes: [const NoteSticker(startMs: 10000, endMs: 14000, text: '')],
        ),
      );
      container.read(noteTextEditorTargetProvider.notifier).open(10000);
      await tester.pump();
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);

      // 驱动到尾点 → 循环提示出场；再弹一次续播小卡：两张卡同框。
      await engine.seek(const Duration(seconds: 29));
      await tester.pump();
      engine.play();
      await tester.pump(const Duration(seconds: 2));
      container.read(resumePromptProvider.notifier).show();
      await tester.pump();
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);
      expect(find.byKey(const Key('resume_prompt_card')), findsOneWidget);

      // 屏幕中央短暂提示在场（整页最后绘制的那条）。
      container.read(noticeTriggerProvider(NoticeId.layoutLock).notifier).show();
      await tester.pump();
      expect(find.text('已锁定分段'), findsOneWidget);

      // 层序 = 共享 Stack 的直系子序：命中按子序逆序发生，故子序在后 = 命中
      // 在先。卡与编辑器之间的先后另由下方点按结果佐证。
      final stack = sharedStackOf(
        tester,
        find.byType(ControlLayer),
        find.byKey(const Key('loop_prompt')),
      );
      int layerIndex(Finder layer) => paintIndexOf(stack, tester.element(layer));

      final controlIndex = layerIndex(find.byType(ControlLayer));
      final loopIndex = layerIndex(find.byKey(const Key('loop_prompt')));
      final resumeIndex = layerIndex(find.byKey(const Key('resume_prompt_card')));
      final editorIndex = layerIndex(find.byType(NoteTextEditorPanel));
      final noticeIndex = layerIndex(find.text('已锁定分段'));
      expect(loopIndex, greaterThan(controlIndex), reason: '循环提示卡在控制层之上');
      expect(resumeIndex, greaterThan(controlIndex), reason: '续播小卡在控制层之上');
      expect(editorIndex, greaterThan(loopIndex), reason: '备注文本编辑器面在两张卡之上');
      expect(editorIndex, greaterThan(resumeIndex), reason: '备注文本编辑器面在两张卡之上');
      expect(noticeIndex, greaterThan(editorIndex), reason: '屏幕中央提示在备注文本编辑器面之上');

      final card = tester.getRect(find.byKey(const Key('loop_prompt')));

      // 命中顺序之一：编辑器面开着时，它那层铺满的不透明点按面吃掉卡矩形内
      // 的点按——编辑器收起、卡与倒计时一位不动（编辑器画在卡之上）。
      await tapAtAndSettle(tester, Offset(card.left + 8, card.center.dy));
      expect(
        find.byKey(const Key('note_text_editor')),
        findsNothing,
        reason: '编辑器面接管了这笔点按',
      );
      expect(
        find.byKey(const Key('loop_prompt')),
        findsOneWidget,
        reason: '卡没吃到这笔点按',
      );
      expect(engine.isPlaying, isFalse, reason: '「不循环」没被误触');

      // 命中顺序之二：第二张卡（续播小卡）在编辑态同样可点——点它的
      // 「从头播放？」跳回片头，控制层留在原地。
      await tester.tap(find.byKey(const Key('resume_prompt_restart')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('resume_prompt_card')), findsNothing);
      expect(engine.position, Duration.zero, reason: '「从头播放？」动作发生');
      expect(find.byKey(const Key('control_layer')), findsOneWidget);

      // 命中顺序之三：编辑器收起后卡自身矩形接管点按（卡矩形内的一处空白点按
      // 只算对卡的操作），卡外的空白落点照常由控制层空白手势面接管。
      await tapAtAndSettle(tester, Offset(card.left + 8, card.center.dy));
      expect(
        find.byKey(const Key('control_layer')),
        findsOneWidget,
        reason: '卡矩形内的点按命中的是卡',
      );
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      await tapAtAndSettle(tester, Offset(card.left + 8, card.top - 40));
      expect(
        find.byKey(const Key('control_layer')),
        findsNothing,
        reason: '卡外的空白落点照常由控制层空白手势面接管',
      );
    });

    testWidgets('横屏编辑态：本次不画卡，尾点倒计时照常（八拍后自动循环）', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 3),
        videoAspectRatio: 16 / 9,
      );
      await pumpPlayer(tester, logical: landscape, engine: engine);
      await singleTapShow(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(engine.isPlaying, isFalse, reason: '前置：播放到尾停在尾点');
      expect(
        find.byKey(const Key('loop_prompt')),
        findsNothing,
        reason: '中带只剩 49.1dp：放不下就不画',
      );

      await tester.pump(placeholderBeatGrid.beatsDuration(8));
      expect(engine.isPlaying, isTrue, reason: '倒计时照常：八拍后自动循环');
      expect(
        engine.position,
        lessThan(const Duration(seconds: 3)),
        reason: '回到片头起播（不是停在尾点）',
      );
    });

    testWidgets('横屏观看态竖向源：卡跟着居中的画面横向移到位，底边抬出底部让路带', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 3),
        videoAspectRatio: 9 / 16,
      );
      await pumpPlayer(tester, logical: landscape, engine: engine);
      setGestureInsets(tester, bottom: 44, left: 16);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      // 画面矩形 (289.3, 0)–(492.4, 361.1)：贴画面左缘 + 24，底边推出 44dp 让路带。
      final rect = tester.getRect(find.byKey(const Key('loop_prompt')));
      expect(rect.left, closeTo(289.3 + 24, 0.1));
      expect(rect.bottom, closeTo(361.1 - 44, 0.1));
    });

    testWidgets('对比-播放态（非录制）：卡锚在源半区画面的左下角', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 3),
        videoAspectRatio: 16 / 9,
      );
      // 先暂停：进对比态的 pumpAndSettle 不该把播放推到尾点。
      final container = await pumpPlayer(
        tester,
        logical: landscape,
        engine: engine,
      );
      engine.pause();
      await tester.pump();
      await singleTapShow(tester);
      await tester.tap(find.byKey(const Key('tool_compare')));
      await tester.pumpAndSettle();
      // 退到对比-播放态（与 safe_area_avoidance_test 的进/退对比态同款：
      // 两下孤立单击，第二下才真的把控制层收起）。
      await collapseControlLayer(tester);
      await collapseControlLayer(tester);
      expect(
        container.read(playerSessionProvider).mode,
        PlayerSessionMode.compareWatching,
        reason: '前置：对比-播放态',
      );
      expect(
        container.read(compareRecordingPhaseProvider),
        CompareRecordingPhase.idle,
        reason: '前置：非录制',
      );

      // 驱动到尾点 → 倒计时。
      await engine.seek(const Duration(seconds: 2, milliseconds: 900));
      await tester.pump();
      engine.play();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.byKey(const Key('loop_prompt')),
        findsOneWidget,
        reason: '非录制态：尾点提示照常出现',
      );

      // 画面矩形 = 组合根那座读面的源半区；卡贴它的左下角内缩 24dp（横屏
      // 16:9 源下源半区画面矩形 (0, 70.9)–(389.85, 290.2)，非整屏 contain 的
      // (69.9, 0)–(711.8, 361.1)）。
      final picture = compareFramingPictureRect(
        screen: landscape,
        landscape: true,
        aspectRatio: 16 / 9,
      );
      final rect = tester.getRect(find.byKey(const Key('loop_prompt')));
      expect(rect.left, closeTo(picture.left + 24, 0.05));
      expect(rect.bottom, closeTo(picture.bottom - 24, 0.05));
    });

    testWidgets('续播小卡与循环提示同锚（落位规则只有一条）', (tester) async {
      final engine = FakePlaybackEngine(
        duration: const Duration(seconds: 30),
        videoAspectRatio: 16 / 9,
      );
      final container = await pumpPlayer(
        tester,
        logical: portrait,
        engine: engine,
        lastPositionMs: 10000,
      );
      expect(
        find.byKey(const Key('resume_prompt_card')),
        findsOneWidget,
        reason: '前置：打开续播即弹小卡',
      );

      // 驱动到尾点：循环提示出场；续播小卡再弹一次，两张卡同框。
      await engine.seek(const Duration(seconds: 29));
      await tester.pump();
      engine.play();
      await tester.pump(const Duration(seconds: 2));
      container.read(resumePromptProvider.notifier).show();
      await tester.pump();
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);
      expect(find.byKey(const Key('resume_prompt_card')), findsOneWidget);

      final loop = tester.getRect(find.byKey(const Key('loop_prompt')));
      final resume = tester.getRect(find.byKey(const Key('resume_prompt_card')));
      expect(resume.left, loop.left);
      expect(resume.bottom, loop.bottom);
      expect(loop.left, closeTo(24, 0.01));
      expect(loop.bottom, closeTo(492.4 - 24, 0.05));
    });
  });

  group('「从头播放？」小卡（widget 缝：锚入参）', () {
    Future<ProviderContainer> pumpCard(
      WidgetTester tester, {
      required ({double left, double bottom})? anchor,
    }) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [ResumePromptOverlay(anchor: anchor)],
              ),
            ),
          ),
        ),
      );
      container.read(resumePromptProvider.notifier).show();
      await tester.pump();
      return container;
    }

    testWidgets('传什么锚落什么位置（卡不再自读系统手势内缩）', (tester) async {
      final container = await pumpCard(tester, anchor: (left: 40, bottom: 100));
      expect(find.byKey(const Key('resume_prompt_card')), findsOneWidget);

      final rect = tester.getRect(find.byKey(const Key('resume_prompt_card')));
      expect(rect.left, 40);
      expect(rect.bottom, 600 - 100);

      // 收尾：撤掉自动消失计时。
      container.read(resumePromptProvider.notifier).dismiss();
    });

    testWidgets('锚为 null（本次放不下）：不渲染', (tester) async {
      final container = await pumpCard(tester, anchor: null);
      expect(find.byKey(const Key('resume_prompt_card')), findsNothing);

      container.read(resumePromptProvider.notifier).dismiss();
    });
  });
}
