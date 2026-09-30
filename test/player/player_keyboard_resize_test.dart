import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/level_control.dart'
    show screenBrightnessControllerProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/pump_past_marquee.dart';

/// 播放页键盘行为：播放页 Scaffold
/// 不随软件键盘收缩；横屏 + 大 bottom inset 下底层控制层不溢出。
/// 键盘 inset 用 FakeViewPadding（物理像素，测试面 dpr = 3.0），与
/// 命名弹窗键盘用例先例一致。
void main() {
  const filePath = '/priv/videos/dance.mp4';

  VideoIndexEntry unsignedEntry() {
    return VideoIndexEntry(
      videoId: 'hash-1',
      displayName: 'dance.mp4',
      filePath: filePath,
      sizeBytes: 3,
      fastKey: '3-dance.mp4',
      mirrored: false,
      mirrorAsked: true,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
    );
  }

  Future<void> pumpPlayerLandscape(WidgetTester tester) async {
    addTearDown(tester.view.reset);
    // 底排槽位统一「外 6 + 内 4/4」内边距与 24 图标，整排加宽
    // 约 48dp：横屏小窗物理宽同步放宽（640→673dp 逻辑宽），避免底部工具组
    // RenderFlex 溢出（见 control_layer_test 的 setNarrowView 同类先例）。
    tester.view.physicalSize = const Size(2020, 1080); // 合成档 673.3×360.0dp（dpr 3），非设备基准。
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [unsignedEntry()]),
    );
    final docs = InMemoryVideoDocumentStorage(
      markers: const {},
      markersPresent: false,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          screenBrightnessControllerProvider.overrideWithValue(
            FakeScreenBrightnessController(),
          ),
          videoIndexStoreProvider.overrideWithValue(index),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) => VideoDocumentCoordinator(docs),
          ),
        ],
        child: MaterialApp(
          home: PlayerPage(source: Uri.file(filePath), askNaming: false),
        ),
      ),
    );
    // 显示底层控制层（单拍）后等待布局稳定。
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await pumpPastMarquee(tester); // 标题滚动不停歇，pumpAndSettle 不收敛
  }

  testWidgets('播放页 Scaffold 不随键盘收缩（resizeToAvoidBottomInset = false）', (
    tester,
  ) async {
    await pumpPlayerLandscape(tester);

    // 播放页根 Scaffold（含播放面的最近祖先）不随键盘收缩。
    final playerScaffold = tester.widget<Scaffold>(
      find
          .ancestor(
            of: find.byKey(const Key('player_surface')),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(playerScaffold.resizeToAvoidBottomInset, isFalse);
  });

  testWidgets('横屏 + 键盘大 bottom inset：底层控制层无 BOTTOM OVERFLOWED', (
    tester,
  ) async {
    await pumpPlayerLandscape(tester);

    // 控制层在屏（横屏形态的关键行都在），且整个布局无溢出异常。
    expect(find.byKey(const Key('control_layer_back')), findsOneWidget);
    expect(find.byKey(const Key('control_layer_title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
