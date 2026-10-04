import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/plan/system_push_provider.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 播放页顶栏改名 → 推送同步：`SongSignatureController` 的提交
/// 信号在播放页装配处接到推送同步，改名落盘后补一次同步，已排通知按新名差分
/// 重排。这里以替换同步闭包为计数桩，只钉「改名提交触发同步、取消不触发」。
void main() {
  VideoIndexEntry entry() => VideoIndexEntry(
    videoId: 'hash-1',
    displayName: 'dance.mp4',
    filePath: '/priv/videos/dance.mp4',
    sizeBytes: 3,
    fastKey: '3-dance.mp4',
    mirrored: false,
    mirrorAsked: true,
    lastOpenedAt: DateTime(2026, 9, 1, 12),
  );

  Future<void> pumpPlayer(
    WidgetTester tester, {
    required void Function() onSync,
  }) async {
    tester.view.physicalSize = const Size(
      1336,
      720,
    ); // 合成档 668.0×360.0dp（dpr 2），非设备基准。
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: VideoIndex(entries: [entry()])),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (_) => InMemoryVideoDocumentStorage(),
          ),
          planPushSyncProvider.overrideWithValue(() async => onSync()),
        ],
        child: MaterialApp(
          home: PlayerPage(
            source: Uri.file('/priv/videos/dance.mp4'),
            askNaming: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openControlLayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pump();
  }

  testWidgets('顶栏改名保存：补一次推送同步', (tester) async {
    var syncCalls = 0;
    await pumpPlayer(tester, onSync: () => syncCalls++);
    await openControlLayer(tester);

    await tester.tap(find.byKey(const Key('control_layer_title_slot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('naming_song_field')), '新名');
    await tester.pump();
    await tester.tap(find.byKey(const Key('naming_save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(syncCalls, 1);
  });

  testWidgets('顶栏改名取消：不补同步', (tester) async {
    var syncCalls = 0;
    await pumpPlayer(tester, onSync: () => syncCalls++);
    await openControlLayer(tester);

    await tester.tap(find.byKey(const Key('control_layer_title_slot')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byKey(const Key('naming_song_field')), '改一半');
    await tester.pump();
    await tester.tap(find.byKey(const Key('naming_skip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(syncCalls, 0);
  });
}
