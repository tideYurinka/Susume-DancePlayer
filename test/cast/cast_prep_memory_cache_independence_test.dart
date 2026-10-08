import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart'
    show CastRenderChoices, CastRenderRequest, CastRenderSettings, CastSpeedTier;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/cast_prep_memory.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryAutoRestoreProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// **投屏准备记忆 ↺ 投屏缓存：两本账各归各**（票 #40 的验收点）。
///
/// 记住的取值随这支舞落在**本地文档**（`prefs.castPrep`）里，只是面板的预置
/// ——它不进渲染请求、不进缓存键；投屏缓存是另一处盘上账（ADR-0005），它的
/// **清空**（详细设置那一行走的同一入口）只该删缓存区里的副本：
///
/// - 清空投屏缓存 → 这支舞记住的取值逐字不动（面板重开仍按它预置）；
/// - 改记住的取值 → 缓存区里的那份产物一个字节都不动，也不在缓存区里造文件。
///
/// 两边都用真实临时目录与真实公开面（缓存走它自己的 `partFileFor` /
/// `promote` / `clear`；文档走设置持久化的落盘链），不 mock。
void main() {
  const pathA = '/videos/a.mp4';
  const idA = 'vid-a';

  late Directory support;
  late Directory cacheDir;
  late Map<String, InMemoryVideoDocumentStorage> storages;
  late ProviderContainer container;

  setUp(() {
    support = Directory.systemTemp.createTempSync('cast_prep_memory_cache');
    cacheDir = Directory(p.join(support.path, 'cast_render'));
    storages = {idA: InMemoryVideoDocumentStorage()};
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [historyEntry(filePath: pathA, mirrored: false, videoId: idA)],
      ),
    );
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        // 倍速历史是设备级、启动自动恢复会读真实私密 JSON：测试隔离关闭。
        speedHistoryAutoRestoreProvider.overrideWithValue(false),
        videoIndexStoreProvider.overrideWithValue(index),
        videoDocumentStorageProvider(idA).overrideWithValue(storages[idA]!),
        castRenderCacheDirectoryProvider.overrideWithValue(
          () async => cacheDir,
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  CastRenderRequest cacheRequest() => const CastRenderRequest(
    videoPath: pathA,
    videoId: idA,
    duration: Duration(seconds: 8),
    choices: CastRenderChoices.all(),
    speedTier: CastSpeedTier.full,
    settings: CastRenderSettings(),
    annotationFingerprint: 'fp-1',
  );

  /// 缓存区里真放一份投屏副本（经缓存自己的公开面：半成品 → 落定）。
  Future<File> populateCache() async {
    final cache = container.read(castRenderCacheProvider);
    final part = await cache.partFileFor(cacheRequest());
    part.writeAsBytesSync(List.filled(2048, 7));
    final product = await cache.promote(part, cacheRequest());
    expect(await cache.usageBytes(), 2048, reason: '缓存区里真有一份副本');
    return product;
  }

  /// 打开这支舞并按“面板回写”落一次记忆（走真实落盘链）。
  Future<void> remember(
    VideoSettingsPersistence session,
    CastPrepMemory memory,
  ) async {
    container.read(castPrepMemoryProvider.notifier).remember(memory);
    await session.flush;
  }

  test('清空投屏缓存：这支舞记住的取值逐字不动，面板重开仍按它预置', () async {
    final session = VideoSettingsPersistence(container);
    unawaited(session.startForVideo(idA));
    await session.started;
    const memory = CastPrepMemory(
      choices: CastRenderChoices(picture: false, sound: true),
      tiers: {CastSpeedTier.half, CastSpeedTier.full},
    );
    await remember(session, memory);
    expect(storages[idA]!.localSnapshot['prefs']['castPrep'], {
      'picture': false,
      'sound': true,
      'tiers': ['0.5', '1'],
    });

    final product = await populateCache();

    // 详细设置那一行按的就是这个入口。
    await container.read(castRenderCacheProvider).clear();

    expect(await container.read(castRenderCacheProvider).usageBytes(), 0);
    expect(product.existsSync(), isFalse, reason: '清空确实把副本删了');
    expect(
      storages[idA]!.localSnapshot['prefs']['castPrep'],
      {'picture': false, 'sound': true, 'tiers': ['0.5', '1']},
      reason: '清缓存不动本地文档里的投屏准备记忆',
    );
    // 面板重开那一刻走的就是这条读法：清缓存之后预置仍是记住的取值。
    final preset = castPrepMemoryOf(
      container.read(castPrepMemoryProvider),
      manualRate: 1,
    );
    expect(preset, memory);
  });

  test('改记住的取值：缓存区里的产物一个字节都不动，也不在缓存区造文件', () async {
    final session = VideoSettingsPersistence(container);
    unawaited(session.startForVideo(idA));
    await session.started;

    final product = await populateCache();
    final before = cacheDir.listSync(recursive: true).length;

    await remember(
      session,
      const CastPrepMemory(
        choices: CastRenderChoices.none(),
        tiers: {CastSpeedTier.threeQuarter},
      ),
    );
    expect(storages[idA]!.localSnapshot['prefs']['castPrep'], {
      'picture': false,
      'sound': false,
      'tiers': ['0.75'],
    });

    expect(product.existsSync(), isTrue);
    expect(product.lengthSync(), 2048);
    expect(
      await container.read(castRenderCacheProvider).usageBytes(),
      2048,
      reason: '记住的取值不进缓存账',
    );
    expect(
      cacheDir.listSync(recursive: true).length,
      before,
      reason: '改记忆不在缓存区里造任何文件',
    );
  });
}
