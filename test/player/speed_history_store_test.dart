import 'dart:io';

import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/speed_control.dart'
    show speedControlProvider;
import 'package:dance_learning_app/player/speed_history_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

void main() {
  group('sanitizeSpeedHistory（纯函数 seam）', () {
    test('非法整体（非 List）按出厂态处理', () {
      expect(sanitizeSpeedHistory('oops'), isEmpty);
      expect(sanitizeSpeedHistory(null), isEmpty);
    });

    test('过滤非数值元素并转换为 double', () {
      expect(sanitizeSpeedHistory([1.25, 'x', 0, null, 2]), [1.25, 0.0, 2.0]);
    });

    test('去重、保留最近在前、截断到上限 8', () {
      final raw = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
      expect(sanitizeSpeedHistory(raw), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(sanitizeSpeedHistory([1.5, 0.75, 1.5]), [1.5, 0.75]);
    });
  });

  group('SpeedHistoryStore（设备级私密 JSON speedHistory 键）', () {
    late InMemoryPrivateJsonStorage storage;

    setUp(() {
      storage = InMemoryPrivateJsonStorage();
    });

    test('缺失键读出厂空态', () async {
      final store = SpeedHistoryStore(storage);
      expect(await store.load(), isEmpty);
    });

    test('save 落 speedHistory 键且不覆盖其它键', () async {
      storage.reset();
      await storage.write({
        'speedStepPresets': {'selectedId': 'builtin_first'},
      });
      final store = SpeedHistoryStore(storage);
      await store.save([1.5, 0.75]);

      expect(storage.snapshot['speedHistory'], [1.5, 0.75]);
      expect(
        (storage.snapshot['speedStepPresets']
            as Map<String, dynamic>)['selectedId'],
        'builtin_first',
      );
      expect(await store.load(), [1.5, 0.75]);
    });

    test('损坏值读回出厂空态', () async {
      storage.reset();
      await storage.write({
        'speedHistory': <String, dynamic>{'bad': true},
      });
      final store = SpeedHistoryStore(storage);
      expect(await store.load(), isEmpty);
    });

    test('归属固定：设备级私密 JSON 不携带按舞倍速记忆键', () async {
      storage.reset();
      final store = SpeedHistoryStore(storage);
      await store.save([1.25, 0.5]);
      expect(storage.snapshot['speedHistory'], [1.25, 0.5]);
      expect(storage.snapshot.containsKey('speedRate'), isFalse);
    });

    test('真实文件损坏（非法 JSON）读回出厂空态，不崩溃', () async {
      final tempDir = await Directory.systemTemp.createTemp('speed_history');
      addTearDown(() => tempDir.delete(recursive: true));
      final file = File(p.join(tempDir.path, 'global_private.json'));
      await file.writeAsString('{not json');

      final store = SpeedHistoryStore(AtomicJsonFile(file));
      expect(await store.load(), isEmpty);
      await store.save([1.25]);
      expect(await store.load(), [1.25]);
    });
  });

  group('倍速历史设备级持久化（SpeedControlModel 接线）', () {
    late InMemoryPrivateJsonStorage storage;
    late ProviderContainer container;

    ProviderContainer makeContainer(Map<String, dynamic> initial) {
      storage = InMemoryPrivateJsonStorage(initial: initial);
      return ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          speedHistoryStorageProvider.overrideWithValue(
            SpeedHistoryStore(storage),
          ),
        ],
      );
    }

    test('启动恢复：历史随设备私密 JSON 回来（去重、最近在前）', () async {
      container = makeContainer({
        'speedHistory': [0.75, 1.5, 0.75],
      });
      addTearDown(container.dispose);

      await container.read(speedControlProvider.notifier).restoreDone;
      expect(container.read(speedControlProvider).history, [0.75, 1.5]);
    });

    test('记录即落盘：去重、最近在前、上限 8', () async {
      container = makeContainer(const {});
      addTearDown(container.dispose);
      final model = container.read(speedControlProvider.notifier);
      await model.restoreDone;

      model.recordHistory(1.25);
      model.recordHistory(0.5);
      model.recordHistory(1.25);
      await model.flushDone;

      expect(storage.snapshot['speedHistory'], [1.25, 0.5]);
      expect(container.read(speedControlProvider).history, [1.25, 0.5]);

      for (var i = 0; i < 10; i++) {
        model.recordHistory(0.1 * (i + 1));
      }
      await model.flushDone;
      expect(container.read(speedControlProvider).history.length, 8);
    });

    test('损坏值恢复出厂空态，不崩溃', () async {
      container = makeContainer({'speedHistory': 'broken'});
      addTearDown(container.dispose);

      await container.read(speedControlProvider.notifier).restoreDone;
      expect(container.read(speedControlProvider).history, isEmpty);
    });

    test('恢复完成前的用户记录不被恢复结果覆盖', () async {
      storage = InMemoryPrivateJsonStorage(
        initial: {
          'speedHistory': [1.5],
        },
      );
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          speedHistoryStorageProvider.overrideWithValue(
            SpeedHistoryStore(storage),
          ),
        ],
      );
      addTearDown(container.dispose);
      final model = container.read(speedControlProvider.notifier);
      model.recordHistory(0.25);
      await model.restoreDone;

      expect(container.read(speedControlProvider).history, [0.25]);
      await model.flushDone;
      expect(storage.snapshot['speedHistory'], [0.25]);
    });

    test('存储不可用（真实路径不可达等）：默认会话态，不抛错', () async {
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
      );
      addTearDown(container.dispose);
      final model = container.read(speedControlProvider.notifier);

      await model.restoreDone;
      model.recordHistory(1.5);
      await model.flushDone;
      expect(container.read(speedControlProvider).history, [1.5]);
    });
  });
}
