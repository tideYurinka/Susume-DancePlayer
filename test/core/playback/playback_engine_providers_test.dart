import 'package:dance_learning_app/core/playback/playback_engine_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_playback_engine.dart';

/// 播放内核注入点（`lib/core/playback/playback_engine_providers.dart`）的
/// 接线测试：position 流驱动 UI、completed 事件流可订阅，注入 FakeEngine。
void main() {
  group('Riverpod 接线（FakeEngine 注入）', () {
    testWidgets('position 流驱动 UI 更新', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackEngineProvider.overrideWithValue(engine)],
          child: const MaterialApp(home: _PositionProbe()),
        ),
      );
      expect(find.text('0'), findsOneWidget);

      await engine.open(Uri.file('/videos/a.mp4'), play: true);
      // fake 时钟下推进 1s：10 拍 × 100ms。
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1000'), findsOneWidget);

      // 暂停后 position 冻结。
      await engine.pause();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('completed 事件流可订阅（循环层接缝）', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
      final container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);

      var completedCount = 0;
      final subscription = container
          .read(playbackCompletedStreamProvider)
          .listen((_) => completedCount++);
      addTearDown(subscription.cancel);

      await engine.open(Uri.file('/videos/a.mp4'), play: true);
      await tester.pump(const Duration(seconds: 2));

      expect(completedCount, 1);
    });
  });
}

/// 通过 Riverpod 读 position 流的探针 widget。
class _PositionProbe extends ConsumerWidget {
  const _PositionProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    return Scaffold(body: Center(child: Text('${position.inMilliseconds}')));
  }
}
