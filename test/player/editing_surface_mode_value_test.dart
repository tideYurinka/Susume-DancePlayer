import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 编辑面进出改由模式值承载：控制层展开位改读派生谓词后，
/// 「收起控制层即收起已展开的气泡」由气泡侧听模式值自收尾、「方向锁由
/// 宿主听模式值一处执行」取代两个调用点上的手写调用——本套件在播放页
/// widget 边界钉住这两条行为（收起关气泡今天无测试）。
void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    FakeSystemUi? systemUi,
  }) async {
    final resolved = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(
            systemUi ?? FakeSystemUi(),
          ),
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
  }

  /// 单击唤出控制层：等双击判定窗口过（识别器回调孤立单指单击）后渲染。
  Future<void> singleTapShow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PlayerPage)));

  testWidgets('收起控制层会收起已展开的气泡', (tester) async {
    final engine = FakePlaybackEngine();
    await pumpPlayer(tester, engine: engine);

    await singleTapShow(tester);
    // 编辑态展开倍速气泡（顶栏工具入口）。
    await tester.tap(find.byKey(const Key('tool_speed_settings')));
    await tester.pump();
    expect(find.byKey(const Key('speed_bubble')), findsOneWidget);

    // 收起控制层（模式值经唯一写路径回观看态）：气泡随之收起。
    containerOf(tester).read(playerSessionProvider.notifier).collapse();
    await tester.pump();
    expect(find.byKey(const Key('control_layer')), findsNothing);
    expect(find.byKey(const Key('speed_bubble')), findsNothing);
    expect(containerOf(tester).read(speedBubbleSessionProvider).open, isNull);
    expect(
      containerOf(tester).read(playerSessionProvider).controlOpen,
      isFalse,
    );
  });

  testWidgets('进编辑面零方向锁；收起控制层不再发出任何方向请求', (tester) async {
    final engine = FakePlaybackEngine();
    final systemUi = FakeSystemUi();
    await pumpPlayer(tester, engine: engine, systemUi: systemUi);

    // 进编辑面不再改变设备方向：零方向锁。
    await singleTapShow(tester);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(systemUi.lockLandscapeCount, 0, reason: '进入编辑面不锁方向');

    // 收起控制层：不再有任何方向副作用（粘性锁定由转屏钮一次请求表达）。
    containerOf(tester).read(playerSessionProvider.notifier).collapse();
    await tester.pump();
    expect(find.byKey(const Key('control_layer')), findsNothing);
    expect(systemUi.lockLandscapeCount, 0, reason: '全程无自动方向锁');
    expect(
      containerOf(tester).read(playerSessionProvider).controlOpen,
      isFalse,
    );
  });
}
