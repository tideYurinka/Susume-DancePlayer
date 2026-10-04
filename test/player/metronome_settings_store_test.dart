import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/player/metronome_settings_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_private_json_storage.dart';

void main() {
  group('metronomeSettings 净化（设备级，global_private.json 并列扩键）', () {
    test('整体不是 Map → 出厂空态，不抛错', () {
      expect(sanitizeMetronomeSettings(null), isEmpty);
      expect(sanitizeMetronomeSettings('nope'), isEmpty);
      expect(sanitizeMetronomeSettings(42), isEmpty);
    });

    test('是 Map → 浅拷贝保留字段', () {
      final sanitized = sanitizeMetronomeSettings({
        'animationStyle': 'pendulum',
        'halfBeatEnabled': false,
      });
      expect(sanitized, {
        'animationStyle': 'pendulum',
        'halfBeatEnabled': false,
      });
    });
  });

  group('MetronomeSettingsStore（读改写 seam）', () {
    test('load：缺失兜底空设置；字段值原样透出（解码归消费方）', () async {
      final storage = InMemoryPrivateJsonStorage();
      final store = MetronomeSettingsStore(storage);
      expect(await store.load(), isEmpty);

      await storage.mutate((json, {required bool present}) {
        json['metronomeSettings'] = {
          'animationStyle': 'bar',
          'soundType': 'vocal',
        };
      });
      expect(await store.load(), {
        'animationStyle': 'bar',
        'soundType': 'vocal',
      });
    });

    test('load：metronomeSettings 损坏（非 Map）兜底空设置', () async {
      final storage = InMemoryPrivateJsonStorage();
      await storage.mutate(
        (json, {required bool present}) => json['metronomeSettings'] = 'broken',
      );
      expect(await MetronomeSettingsStore(storage).load(), isEmpty);
    });

    test('update：保留同文件其它键与既有节拍器字段', () async {
      final storage = InMemoryPrivateJsonStorage(
        initial: {
          'speedHistory': [1.5],
          'metronomeSettings': {'animationStyle': 'bar'},
        },
      );
      final store = MetronomeSettingsStore(storage);
      await store.update((settings) => settings['soundType'] = 'geigi');

      expect(storage.snapshot['speedHistory'], [1.5]);
      expect(storage.snapshot['metronomeSettings'], {
        'animationStyle': 'bar',
        'soundType': 'geigi',
      });
    });
  });

  group('MetronomeSettingSync（单字段恢复 + 落盘）', () {
    // 测试专用字段（int 便于断言编解码透明性）。
    final syncProvider = Provider<MetronomeSettingSync<int>>((ref) {
      return MetronomeSettingSync<int>(
        ref,
        field: 'hits',
        decode: (raw) => raw is int ? raw : null,
        encode: (value) => value,
      );
    });

    late InMemoryPrivateJsonStorage storage;

    ProviderContainer makeContainer({
      bool autoRestore = true,
      Map<String, dynamic> initial = const {},
    }) {
      storage = InMemoryPrivateJsonStorage(initial: initial);
      return ProviderContainer(
        overrides: [
          privateJsonStorageProvider.overrideWithValue(storage),
          metronomeSettingsAutoRestoreProvider.overrideWithValue(autoRestore),
        ],
      );
    }

    test('restore：字段缺失不 apply', () async {
      final container = makeContainer();
      addTearDown(container.dispose);
      final sync = container.read(syncProvider);
      var applied = -1;
      sync.restore((value) => applied = value);
      await sync.restoreDone;
      expect(applied, -1);
    });

    test('restore：持久化字段合法 → apply 写回会话态', () async {
      final container = makeContainer(
        initial: {
          'metronomeSettings': {'hits': 7},
        },
      );
      addTearDown(container.dispose);
      final sync = container.read(syncProvider);
      var applied = -1;
      sync.restore((value) => applied = value);
      await sync.restoreDone;
      expect(applied, 7);
    });

    test('restore：字段值非法 → 不 apply（解码兜底 null）', () async {
      final container = makeContainer(
        initial: {
          'metronomeSettings': {'hits': 'bad'},
        },
      );
      addTearDown(container.dispose);
      final sync = container.read(syncProvider);
      var applied = -1;
      sync.restore((value) => applied = value);
      await sync.restoreDone;
      expect(applied, -1);
    });

    test('autoRestore 关闭：不读存储、restoreDone 立即完成', () async {
      final container = makeContainer(
        autoRestore: false,
        initial: {
          'metronomeSettings': {'hits': 7},
        },
      );
      addTearDown(container.dispose);
      final sync = container.read(syncProvider);
      var applied = -1;
      sync.restore((value) => applied = value);
      await sync.restoreDone;
      expect(applied, -1);
    });

    test('persist：字段落盘并保留同文件其它键', () async {
      final container = makeContainer(
        initial: {
          'speedHistory': [1.5],
        },
      );
      addTearDown(container.dispose);
      final sync = container.read(syncProvider);
      sync.persist(3);
      await sync.flushDone;

      expect(storage.snapshot['metronomeSettings'], {'hits': 3});
      expect(storage.snapshot['speedHistory'], [1.5]);
    });
  });
}
