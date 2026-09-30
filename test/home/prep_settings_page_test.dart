import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/home/prep_settings_page.dart';
import 'package:dance_learning_app/persistence/prep_beats_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_private_json_storage.dart';

/// 详细设置页：三项读值/改值/写回、重启后仍在、
/// 循环前导档位含「不前导」。
void main() {
  late InMemoryPrivateJsonStorage storage;

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PrepSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('三项默认 4 / 8 / 4 渲染；循环前导含「不前导」档', (tester) async {
    storage = InMemoryPrivateJsonStorage();
    await pumpPage(tester);

    expect(find.text('预备拍数'), findsOneWidget);
    expect(find.text('延迟播放'), findsOneWidget);
    expect(find.text('录制准备'), findsOneWidget);
    expect(find.text('循环前导'), findsOneWidget);
    expect(find.text('不前导'), findsOneWidget);
  });

  testWidgets('改值即落盘：点选档位写入 prepBeats 键、会话值同步', (tester) async {
    storage = InMemoryPrivateJsonStorage();
    final container = await pumpPage(tester);

    await tester.tap(find.byKey(const Key('prep_segment_prep_delayed_play_8')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prep_segment_prep_recording_2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('prep_segment_prep_loop_lead_0')));
    await tester.pump();
    await container.read(prepBeatsProvider.notifier).flushDone;

    expect(storage.snapshot['prepBeats'], {
      'delayedPlay': 8,
      'recording': 2,
      'loopLead': 0,
    });
    // 循环前导会话值同步（消费方 delayedLoopProvider 读到新档位）。
    expect(container.read(delayedLoopProvider), DelayedLoopBeats.none);
  });

  testWidgets('重启等价：重新装载从存储恢复三项', (tester) async {
    storage = InMemoryPrivateJsonStorage(
      initial: {
        'prepBeats': {'delayedPlay': 2, 'recording': 4, 'loopLead': 8},
      },
    );
    final container = await pumpPage(tester);

    expect(container.read(prepBeatsProvider),
        const PrepBeats(delayedPlay: 2, recording: 4, loopLead: 8));
    container.listen(delayedLoopProvider, (_, _) {});
    await container.read(prepBeatsProvider.notifier).restoreDone;
    expect(container.read(delayedLoopProvider), DelayedLoopBeats.eight);
  });
}
