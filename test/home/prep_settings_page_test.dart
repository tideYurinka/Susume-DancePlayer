import 'dart:io';

import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/home/prep_settings_page.dart';
import 'package:dance_learning_app/persistence/prep_beats_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_private_json_storage.dart';

/// 详细设置页：三项读值/改值/写回、重启后仍在、
/// 循环前导档位含「不前导」；以及「投屏缓存」那一行——真实占用、清空要确认、
/// 清空后归零。
void main() {
  late InMemoryPrivateJsonStorage storage;
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('prep_settings_page_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<ProviderContainer> pumpPage(
    WidgetTester tester, {
    Directory? cacheDirectory,
  }) async {
    final container = ProviderContainer(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        if (cacheDirectory != null)
          castRenderCacheDirectoryProvider.overrideWithValue(
            () async => cacheDirectory,
          ),
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

    expect(
      container.read(prepBeatsProvider),
      const PrepBeats(delayedPlay: 2, recording: 4, loopLead: 8),
    );
    container.listen(delayedLoopProvider, (_, _) {});
    await container.read(prepBeatsProvider.notifier).restoreDone;
    expect(container.read(delayedLoopProvider), DelayedLoopBeats.eight);
  });

  testWidgets('投屏缓存一行：显示真实占用；清空要确认，确认后占用归零', (tester) async {
    storage = InMemoryPrivateJsonStorage();
    final cacheDirectory = Directory(p.join(root.path, 'cast_render'));
    final product =
        File(p.join(cacheDirectory.path, 'deadbeefdeadbeef', '客厅练习.mp4'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(2048, 1));
    // 半成品与孤儿文件也算真实占用（它是「这块盘上占了多少」）。
    File(p.join(cacheDirectory.path, 'orphan.tmp'))
        .writeAsBytesSync(List.filled(1024, 2));

    await pumpPage(tester, cacheDirectory: cacheDirectory);

    expect(find.text('投屏缓存'), findsOneWidget);
    expect(find.text('当前占用 3.0 KB'), findsOneWidget);

    // 按清空：先要确认；取消则盘上一件不动。
    await tester.tap(find.byKey(const Key('cast_cache_clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cast_cache_clear_dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cast_cache_clear_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cast_cache_clear_dialog')), findsNothing);
    expect(product.existsSync(), isTrue);
    expect(find.text('当前占用 3.0 KB'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cast_cache_clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_cache_clear_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('当前占用 0 B'), findsOneWidget);
    expect(cacheDirectory.listSync(), isEmpty, reason: '清空后缓存区一件不剩');
  });
}
