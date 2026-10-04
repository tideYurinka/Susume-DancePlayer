import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/dance/cover_frame_providers.dart'
    show coverCacheProvider, coverGenerationQueueProvider;
import 'package:dance_learning_app/dance/cover_generation_queue.dart'
    show CoverGenerationQueue;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_share_channel.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 一次性图文引导卡：内容超高时可滚动，出口
/// 按钮始终在屏内——大字号 + 小视口下不溢出、不把出口推出屏幕。
Finder _oneShotActions() => find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('guide_one_shot_action_');
});

void main() {
  testWidgets('大字号 + 矮视口：引导卡不溢出，出口按钮完整落在屏内', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(361, 320); // 合成档 361×320dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(initial: VideoIndex.empty),
          ),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(InMemoryPracticeStatsStorage()),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          coverCacheProvider.overrideWith((ref) => InMemoryCoverCache()),
          coverGenerationQueueProvider.overrideWith(
            (ref) => CoverGenerationQueue(run: (_) async => false),
          ),
          shareChannelProvider.overrideWithValue(FakeShareChannel()),
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '大字号矮视口下无溢出');

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    for (final Element button in _oneShotActions().evaluate()) {
      final rect = tester.getRect(find.byWidget(button.widget));
      expect(rect.top, greaterThanOrEqualTo(0), reason: '出口按钮不越上缘');
      expect(
        rect.bottom,
        lessThanOrEqualTo(screen.height),
        reason: '出口按钮不越下缘（不被推出屏幕）',
      );
      expect(rect.left, greaterThanOrEqualTo(0), reason: '出口按钮不越左缘');
      expect(rect.right, lessThanOrEqualTo(screen.width), reason: '出口按钮不越右缘');
    }
    expect(_oneShotActions(), findsWidgets, reason: '出口按钮在场');

    // 内容超高时正文可滚：在正文区上滑，标题随滚动移出原位。
    final titleBefore = tester.getTopLeft(
      find.byKey(const Key('guide_one_shot_title')),
    );
    await tester.drag(
      find.byKey(const Key('guide_one_shot_title')),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final titleAfter = tester.getTopLeft(
      find.byKey(const Key('guide_one_shot_title')),
    );
    expect(
      titleAfter.dy,
      lessThan(titleBefore.dy),
      reason: '正文区内部滚动（出口按钮不参与滚动）',
    );
  });
}
