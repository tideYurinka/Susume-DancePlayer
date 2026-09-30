import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryAutoRestoreProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 练习侧镜像记忆：设备级默认开（设备级全局私密
/// 文件 `global_private.json` 并列扩键）+ 随该支舞覆盖（local 私密文件
/// `prefs` 段扩键）；生效值 = 覆盖 ?? 设备级默认。
void main() {
  const pathA = '/videos/a.mp4';
  const pathB = '/videos/b.mp4';
  const idA = 'vid-a';
  const idB = 'vid-b';

  late Map<String, InMemoryVideoDocumentStorage> storages;
  late InMemoryPrivateJsonStorage privateJson;
  late ProviderContainer container;

  ProviderContainer makeContainer({
    Map<String, Map<String, dynamic>> localFiles = const {},
    Map<String, dynamic> privateInitial = const {},
  }) {
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [
          historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          historyEntry(filePath: pathB, mirrored: false, videoId: idB),
        ],
      ),
    );
    storages = {
      idA: InMemoryVideoDocumentStorage(local: localFiles[idA] ?? const {}),
      idB: InMemoryVideoDocumentStorage(local: localFiles[idB] ?? const {}),
    };
    privateJson = InMemoryPrivateJsonStorage(initial: privateInitial);
    return ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        speedHistoryAutoRestoreProvider.overrideWithValue(false),
        videoIndexStoreProvider.overrideWithValue(index),
        privateJsonStorageProvider.overrideWithValue(privateJson),
        for (final entry in storages.entries)
          videoDocumentStorageProvider(entry.key)
              .overrideWithValue(entry.value),
      ],
    );
  }

  VideoSettingsPersistence persistence() => VideoSettingsPersistence(container);

  test('设备级默认开：无任何存储值时生效值为 true（照镜子）', () async {
    container = makeContainer();
    addTearDown(container.dispose);

    expect(container.read(effectivePracticeMirrorProvider), true);
    await container.read(practiceMirrorDeviceDefaultProvider.notifier)
        .restoreDone;
    expect(container.read(effectivePracticeMirrorProvider), true);
  });

  test('设备级值可关：设备级文件存 false 且无覆盖时生效值为 false', () async {
    container = makeContainer(
      privateInitial: {'practiceMirrorDefault': false},
    );
    addTearDown(container.dispose);

    await container.read(practiceMirrorDeviceDefaultProvider.notifier)
        .restoreDone;
    expect(container.read(effectivePracticeMirrorProvider), false);
  });

  test('随舞覆盖落盘：切镜像写 local prefs 段 practiceMirror，不写 markers', () async {
    container = makeContainer();
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    container.read(practiceMirrorOverrideProvider.notifier).set(false);
    await session.flush;

    expect(
      storages[idA]!.localSnapshot['prefs']['practiceMirror'],
      false,
    );
    expect(storages[idA]!.markersSnapshot, isEmpty);
  });

  test('重开恢复：local 的覆盖值回到会话并决定生效值（关掉重开仍生效）', () async {
    container = makeContainer(
      localFiles: {
        idA: {
          'version': 3,
          'prefs': {'practiceMirror': false},
        },
      },
    );
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    expect(container.read(practiceMirrorOverrideProvider), false);
    expect(container.read(effectivePracticeMirrorProvider), false);
  });

  test('覆盖缺省用设备级值：另一支舞无覆盖 → 生效值回落设备级默认', () async {
    container = makeContainer(
      localFiles: {
        idA: {
          'version': 3,
          'prefs': {'practiceMirror': false},
        },
      },
      privateInitial: {'practiceMirrorDefault': false},
    );
    addTearDown(container.dispose);
    await container
        .read(practiceMirrorDeviceDefaultProvider.notifier)
        .restoreDone;
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;
    expect(container.read(effectivePracticeMirrorProvider), false);

    // 换到无覆盖的 b 舞：回落设备级默认（同为 false）。
    session.dispose();
    unawaited(session.startForVideo(idB));
    await session.started;
    expect(container.read(practiceMirrorOverrideProvider), isNull);
    expect(container.read(effectivePracticeMirrorProvider), false);
  });
}
