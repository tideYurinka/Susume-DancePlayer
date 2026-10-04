import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/video_index_fixtures.dart';

/// 观看态「八拍矫正」进入的宿主编排（改口径：编辑面三值
/// 进入前置为无）。拍平后待命态蕴含控制层展开，竖屏观看态口径必须**落待办**、
/// 由宿主完成编排后经唯一提交入口提交——竖屏与横屏同一路径直接进入，不再有
/// 方向弹窗与拒绝分支；进编辑面零方向锁，收起控制层一次解锁。
///
/// 竖屏视口（刻意收窄的**合成档** 632×1368dp，非设备基准）与横屏默认视口走
/// 同一条路径。
/// 气泡按钮经回调直调（与既有套件同款：回调本身即生产接线；观看态视口下
/// 按钮命中点被浮层遮挡）。
void main() {
  late FakeSystemUi systemUi;

  /// 泵起播放页（竖屏 [landscape] 为假时按刻意收窄的合成档 632×1368dp 设
  /// 视口，非设备基准；横屏用默认测试视口）。
  Future<void> pumpPlayer(WidgetTester tester, {bool landscape = false}) async {
    if (!landscape) {
      // 刻意收窄的合成档：1264×2736 @2.0 = 632×1368dp（非设备基准）。
      tester.view.physicalSize = const Size(1264, 2736);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    final resolved = Uri.file('/videos/a.mp4');
    systemUi = FakeSystemUi();
    final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(systemUi),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(
                    filePath: resolved.toFilePath(),
                    mirrored: false,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: resolved)),
      ),
    );
    await tester.pumpAndSettle();
    await injectBeatState(
      tester,
      uniformDownbeatBeatState(
        seconds:
            (engine.duration ?? const Duration(seconds: 60)).inMilliseconds /
            1000,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPlayerPortrait(WidgetTester tester) =>
      pumpPlayer(tester, landscape: false);

  /// 打开观看态节拍提示气泡并按下「八拍矫正」（回调直调，见库头说明）。
  /// 控制层展开后标题跑幕动画常驻（溢出时持续产帧）——进入编排的
  /// 帧推进用 [pumpPastMarquee]，不可 `pumpAndSettle`。
  Future<void> pressEightBeatButton(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.beat);
    await tester.pumpAndSettle();
    tester
        .widget<OutlinedButton>(
          find.byKey(const Key('beat_correction_eight_beat_button')),
        )
        .onPressed!();
    await pumpPastMarquee(tester);
  }

  PlayerSession sessionOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(PlayerPage)),
    listen: false,
  ).read(playerSessionProvider);

  testWidgets('竖屏观看态：直接进待命态——零方向锁、待办清空', (tester) async {
    await pumpPlayerPortrait(tester);
    expect(find.byKey(const Key('control_layer')), findsNothing);

    await pressEightBeatButton(tester);

    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(
      sessionOf(tester).mode,
      PlayerSessionMode.beatCorrectionStandby,
      reason: '竖屏直接进入并提交至待命态（进入前置为无）',
    );
    expect(sessionOf(tester).pendingEntry, isNull, reason: '提交后待办清空');
    expect(
      find.byKey(const Key('control_beat_anchor_add')),
      findsOneWidget,
      reason: '待命态工具槽换装',
    );
    expect(systemUi.lockLandscapeCount, 0, reason: '进入编辑面不锁方向');
  });

  testWidgets('竖屏观看态：收起控制层零方向请求并回观看态', (tester) async {
    await pumpPlayerPortrait(tester);
    await pressEightBeatButton(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
    container.read(playerSessionProvider.notifier).collapse();
    await tester.pump();

    expect(find.byKey(const Key('control_layer')), findsNothing);
    expect(sessionOf(tester).mode, PlayerSessionMode.watching);
    expect(systemUi.lockLandscapeCount, 0, reason: '全程无自动方向锁');
  });

  testWidgets('无待办不编排——宿主监听注册（页面初始）不触发进入', (tester) async {
    await pumpPlayerPortrait(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('control_layer')), findsNothing);
    expect(sessionOf(tester).mode, PlayerSessionMode.watching);
    expect(sessionOf(tester).pendingEntry, isNull);
    expect(systemUi.lockLandscapeCount, 0, reason: '未编排，方向锁不被调用');
  });

  testWidgets('重复落待办不叠加——两次请求仍一次进入、零方向锁', (tester) async {
    // 横屏默认视口：同一路径直接提交（前置为无）。
    await pumpPlayer(tester, landscape: true);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
    // 观看态打开气泡并同步连按两次：槽是单槽，重复落待办不叠加。
    container
        .read(speedBubbleSessionProvider.notifier)
        .open(SpeedBubbleMode.beat);
    await tester.pumpAndSettle();
    final onPressed = tester
        .widget<OutlinedButton>(
          find.byKey(const Key('beat_correction_eight_beat_button')),
        )
        .onPressed;
    expect(onPressed, isNotNull);
    onPressed!();
    onPressed();
    await pumpPastMarquee(tester); // 控制层展开后标题跑幕常驻，不可 pumpAndSettle

    expect(
      sessionOf(tester).mode,
      PlayerSessionMode.beatCorrectionStandby,
      reason: '两次请求一次进入（第二次为幂等 no-op）',
    );
    expect(sessionOf(tester).pendingEntry, isNull, reason: '提交后待办清空');
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(systemUi.lockLandscapeCount, 0, reason: '进入编辑面零方向锁');
  });
}
