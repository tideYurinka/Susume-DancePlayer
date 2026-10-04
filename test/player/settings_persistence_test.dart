import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatGridProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show layoutLockedProvider, practiceClipsProvider;
import 'package:dance_learning_app/player/beat_prompt_memory.dart'
    show beatPromptMemoryProvider;
import 'package:dance_learning_app/player/beat_prompt_panel.dart'
    show beatPromptEnabledProvider;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show overlayPlacementProvider;
import 'package:dance_learning_app/player/metronome_sound.dart'
    show metronomeSoundEnabledProvider;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player/open_session.dart';
import 'package:dance_learning_app/player/overlay.dart'
    show OverlayPlacementCell, OverlayPlacements;
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show prepBeatsProvider;
import 'package:dance_learning_app/player/preview_snap.dart'
    show previewSnapEnabledProvider;
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/speed_control.dart'
    show speedControlProvider;
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryAutoRestoreProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/memory_manifest_storage.dart';
import '../helpers/uniform_test_grid.dart';
import '../helpers/video_index_fixtures.dart';

void main() {
  const pathA = '/videos/a.mp4';
  const pathB = '/videos/b.mp4';
  const idA = 'vid-a';
  const idB = 'vid-b';

  late Map<String, InMemoryVideoDocumentStorage> storages;
  late ProviderContainer container;
  late FakePlaybackEngine engine;

  ProviderContainer makeContainer({
    Map<String, Map<String, dynamic>> localFiles = const {},
    bool realGrid = false,
    FakePlaybackEngine? playbackEngine,
  }) {
    engine = playbackEngine ?? FakePlaybackEngine();
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
    return ProviderContainer(
      overrides: [
        if (realGrid)
          beatGridProvider.overrideWithValue(UniformTestGrid(beatCount: 8)),
        playbackEngineProvider.overrideWithValue(engine),
        // 倍速历史是设备级、启动自动恢复会读真实私密 JSON：测试隔离关闭。
        speedHistoryAutoRestoreProvider.overrideWithValue(false),
        videoIndexStoreProvider.overrideWithValue(index),
        for (final entry in storages.entries)
          videoDocumentStorageProvider(entry.key)
              .overrideWithValue(entry.value),
      ],
    );
  }

  VideoSettingsPersistence persistence() => VideoSettingsPersistence(container);

  VideoSettingsPersistence persistenceOf(ProviderContainer target) =>
      VideoSettingsPersistence(target);

  /// 直接用 `ProviderContainer(...)` 装配的既有用例也须补的两条底座
  /// 偏好域装载倍速记忆会读倍速模型，模型连着播放内核与
  /// 设备级历史自动恢复——不注入 fake 引擎就会去建真实 media_kit 内核。
  /// 返回 `List<dynamic>`：riverpod 3.4.2 未公开导出 Override 类型。
  List<dynamic> baseOverrides() => [
    playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
    speedHistoryAutoRestoreProvider.overrideWithValue(false),
  ];

  group('按视频编辑偏好落盘（吸附/锁定分段；循环前导已改设备级）', () {
    test('变更即存：改锁定分段写 local，不写 markers', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(layoutLockedProvider.notifier).toggle();
      await session.flush;

      expect(storages[idA]!.localSnapshot['prefs']['layoutLocked'], true);
      expect(storages[idA]!.markersSnapshot, isEmpty);
    });

    test('变更即存：预览吸附开关写入 local prefs 段；循环前导不再随舞', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(previewSnapEnabledProvider.notifier).toggle();
      container.read(prepBeatsProvider.notifier).setLoopLead(8);
      await session.flush;

      final prefs =
          storages[idA]!.localSnapshot['prefs'] as Map<String, dynamic>;
      expect(prefs['previewSnapEnabled'], false);
      expect(
        prefs.containsKey('delayedLoopBeats'),
        isFalse,
        reason: '循环前导档位改为设备级，本地文档不再携带',
      );
    });

    test('无 UI 变更不写盘：值未变化的设置操作不产生写入', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      await session.flush;

      expect(storages[idA]!.localSnapshot, isEmpty);
    });

    test('重开恢复：local 中的偏好回到各 provider', () async {
      container = makeContainer(
        localFiles: {
          idA: {
            'version': 3,
            'prefs': {'previewSnapEnabled': false, 'layoutLocked': true},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(container.read(previewSnapEnabledProvider), false);
      expect(container.read(layoutLockedProvider), true);
    });

    test('锁定分段重开仍锁定，可手动解锁并落盘', () async {
      container = makeContainer(
        localFiles: {
          idA: {
            'version': 3,
            'prefs': {'layoutLocked': true},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(layoutLockedProvider), true);

      container.read(layoutLockedProvider.notifier).toggle();
      await session.flush;
      expect(storages[idA]!.localSnapshot['prefs']['layoutLocked'], false);
    });

    test('退出会话前已排队的即时写仍落盘（即时写不经去抖窗口）', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(layoutLockedProvider.notifier).toggle();
      // 未等 flush 直接结束会话：已排队写入仍完成。
      session.dispose();
      await session.flush;
      expect(storages[idA]!.localSnapshot['prefs']['layoutLocked'], true);
    });

    test('收尾落盘：去抖窗口内的变更不随离页丢弃', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      const trimmed = PracticeClip(
        id: 'c1',
        materialId: 'm1',
        materialSourceStartMs: 8000,
        inMs: 0,
        outMs: 16000,
        materialDurationMs: 20000,
      );
      // 三个去抖域各改一次，都落在同一个窗口内（取景只活在会话里，不落盘——
      // 不改盘上任何取景键）。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {OverlayPlacementCell.portraitNormal: Offset(30, 40)},
            ),
          );
      container.read(practiceClipsProvider.notifier).restore(const [trimmed]);

      // 窗口未收口就离页：收尾自己把这几个域的变更落盘。
      session.dispose();
      await session.flush;

      final prefs =
          storages[idA]!.localSnapshot['prefs'] as Map<String, dynamic>;
      expect((prefs['overlay'] as Map)['dx'], 30.0);
      expect((prefs['overlay'] as Map)['dy'], 40.0);
      expect(storages[idA]!.markersSnapshot, isEmpty, reason: '取景不落盘');
      final doc = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      expect(doc.practiceClips, [trimmed]);
    });

    test('换会话收尾：窗口内的变更写进上一支舞，不带入下一支舞的会话态', () async {
      container = makeContainer(
        localFiles: {
          idB: const {
            'version': 3,
            'prefs': {
              'overlay': {'dx': 700.0, 'dy': 800.0},
            },
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      const trimmed = PracticeClip(
        id: 'c1',
        materialId: 'm1',
        materialSourceStartMs: 8000,
        inMs: 0,
        outMs: 16000,
        materialDurationMs: 20000,
      );
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {OverlayPlacementCell.portraitNormal: Offset(30, 40)},
            ),
          );
      container.read(practiceClipsProvider.notifier).restore(const [trimmed]);

      // 窗口未收口就换会话：收尾把 A 的变更落进 A 的文件；换会话随即清空
      // 应用级片段表、并按 B 的文档恢复浮层位，两者都不许改写 A 的落盘内容。
      await session.startForVideo(idB);
      await session.flush;

      final aDoc = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      expect(aDoc.practiceClips, [trimmed]);
      final aPrefs =
          storages[idA]!.localSnapshot['prefs'] as Map<String, dynamic>;
      expect((aPrefs['overlay'] as Map)['dx'], 30.0);
      expect((aPrefs['overlay'] as Map)['dy'], 40.0);
      final bPrefs =
          storages[idB]!.localSnapshot['prefs'] as Map<String, dynamic>;
      expect((bPrefs['overlay'] as Map)['dx'], 700.0);
      expect((bPrefs['overlay'] as Map)['dy'], 800.0);
    });

    test('收尾不白写：无待落盘变更时离页不触发「写不进去」提示', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 99,
            'prefs': {'layoutLocked': true},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      final shownBefore = container.read(
        noticeTriggerProvider(NoticeId.documentReadOnly),
      );

      // 没有任何窗口内变更：收尾不该白写一次，也就不该惊动只读提示。
      session.dispose();
      await session.flush;

      expect(
        container.read(noticeTriggerProvider(NoticeId.documentReadOnly)),
        shownBefore,
      );
      expect(storages[idA]!.localSnapshot['version'], 99, reason: '只读原文一字未动');
    });

    test('各视频相互独立：A 的偏好写 A 文件，B 重开取 B 自己的', () async {
      container = makeContainer(
        localFiles: {
          idB: {
            'version': 3,
            'session': {
              'mastery': {'0': 'mastered'},
            },
            'prefs': {'layoutLocked': true},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(previewSnapEnabledProvider.notifier).toggle();
      await session.flush;

      expect(
        storages[idA]!.localSnapshot['prefs']['previewSnapEnabled'],
        false,
      );
      // B 文件保持原状（会话锚定 A）：session 段原样、prefs 未被触碰。
      expect(storages[idB]!.localSnapshot, {
        'version': 3,
        'session': {
          'mastery': {'0': 'mastered'},
        },
        'prefs': {'layoutLocked': true},
      });

      // 换视频：结束 A 会话、打开 B，恢复 B 自己的偏好。
      session.dispose();
      unawaited(session.startForVideo(idB));
      await session.started;
      expect(container.read(previewSnapEnabledProvider), true);
      expect(container.read(layoutLockedProvider), true);
    });

    test('local 版本不符按空态恢复默认偏好', () async {
      container = makeContainer(
        localFiles: {
          idA: {'version': 99, 'layoutLocked': true},
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(container.read(layoutLockedProvider), false);
    });

    test('会话未识别身份（摘要失败）：维持默认会话态、不写盘', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(null));
      await session.started;
      container.read(layoutLockedProvider.notifier).toggle();
      await session.flush;

      expect(container.read(layoutLockedProvider), true);
      expect(storages[idA]!.localSnapshot, isEmpty);
    });

    test('哈希不符（同名同大小不同内容）：按新身份读写，不套用旧条目', () async {
      const newId = 'changed-hash';
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      final oldStorage = InMemoryVideoDocumentStorage(
        local: {
          'version': 3,
          'prefs': {'layoutLocked': false, 'previewSnapEnabled': false},
        },
      );
      final newStorage = InMemoryVideoDocumentStorage(
        local: {
          'version': 3,
          'prefs': {'layoutLocked': true},
        },
      );
      container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          videoIndexStoreProvider.overrideWithValue(index),
          videoDocumentStorageProvider(idA).overrideWithValue(oldStorage),
          videoDocumentStorageProvider(newId).overrideWithValue(newStorage),
        ],
      );
      addTearDown(container.dispose);
      final session = persistence();
      // 打开会话：条目命中但摘要不符 → 身份取摘要（newId）、旧条目保留。
      unawaited(session.startForVideo(newId));
      await session.started;

      expect(
        container.read(layoutLockedProvider),
        true,
        reason: '读新身份文档的偏好，不套用旧条目文档的 false',
      );

      container.read(layoutLockedProvider.notifier).toggle();
      await session.flush;

      final written = newStorage.localSnapshot['prefs'] as Map<String, dynamic>;
      expect(written['layoutLocked'], false);
      expect(written['previewSnapEnabled'], true, reason: '写新身份文档');
      final oldPrefs =
          oldStorage.localSnapshot['prefs'] as Map<String, dynamic>;
      expect(oldPrefs['previewSnapEnabled'], false, reason: '旧条目文档不被写');
    });

    test('按会话给出的身份恢复对应文档', () async {
      container = makeContainer(
        localFiles: {
          idA: {
            'version': 3,
            'prefs': {'layoutLocked': true},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(container.read(layoutLockedProvider), true);
    });
  });

  group('练习片段落盘（一次拖动 = 一次保存）', () {
    test('去抖窗口内的连续片段变更合并为一次 local 写，终值 = 末次变更', () async {
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      final storage = _CountingLocalStorage();
      final container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          videoIndexStoreProvider.overrideWithValue(index),
          videoDocumentStorageProvider(idA).overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);
      final session = persistenceOf(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      const trimmed = PracticeClip(
        id: 'c1',
        materialId: 'm1',
        materialSourceStartMs: 8000,
        inMs: 0,
        outMs: 16000,
        materialDurationMs: 20000,
      );
      final clips = container.read(practiceClipsProvider.notifier);
      // 模拟截取拖动的逐帧变更：连续多次写，均落去抖窗口内。
      clips.restore(const [
        PracticeClip(
          id: 'c1',
          materialId: 'm1',
          materialSourceStartMs: 8000,
          inMs: 0,
          outMs: 12000,
          materialDurationMs: 20000,
        ),
      ]);
      clips.restore(const [trimmed]);
      // 窗口未收口：还没有 local 写。
      expect(storage.localWrites, 0);

      await session.flush;
      expect(storage.localWrites, 1, reason: '窗口内变更合并为一次落盘');
      final doc = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      expect(doc.practiceClips, [trimmed]);
    });
  });

  // 数据完整性：`prefs.practiceClips` 是
  // 普通整表字段——打开装载把该文档的既有片段恢复进会话，写回即会话的完整
  // 视图。以下用例断言的是**外部行为**：写盘内容（文档条数 / 片段集合）与
  // 恢复后的片段集合。
  group('练习片段表整表写回即会话完整视图', () {
    const existingCount = 9;

    /// 既有片段（形状取自真机快照：素材内 2500..12000、素材全长 12000）。
    List<PracticeClip> existingClips() => [
      for (var i = 1; i <= existingCount; i++)
        PracticeClip(
          id: 'clip_mat_$i',
          materialId: 'mat_$i',
          materialSourceStartMs: 10000 * i,
          inMs: 2500,
          outMs: 12000,
          materialDurationMs: 12000,
        ),
    ];

    MaterialRecord material(int index, {int sourceStartMs = 200000}) =>
        MaterialRecord(
          id: 'mat_$index',
          videoId: idA,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000 * index),
          durationMs: 9500,
          sourceStartMs: sourceStartMs,
          fileName: 'rec_$index.mp4',
          sizeBytes: 100,
        );

    late InMemoryVideoDocumentStorage docStorage;
    late MemoryManifestStorage manifestStorage;

    ProviderContainer buildContainer() {
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      docStorage = InMemoryVideoDocumentStorage(
        local: {
          'version': 3,
          'prefs': {
            'practiceClips': [
              for (final clip in existingClips()) clip.toJson(),
            ],
          },
        },
      );
      manifestStorage = MemoryManifestStorage();
      return ProviderContainer(
        overrides: [
          ...baseOverrides(),
          videoIndexStoreProvider.overrideWithValue(index),
          videoDocumentStorageProvider(idA).overrideWithValue(docStorage),
          materialManifestStorageProvider.overrideWithValue(manifestStorage),
        ],
      );
    }

    /// 录制入库（与对比录制与练习片段域 `CompareRecordingClips` 的入库顺序
    /// 同一：先入轨片段、再追加素材清单）。
    Future<void> ingest(ProviderContainer target, MaterialRecord record) async {
      target.read(practiceClipsProvider.notifier).addFromMaterial(record);
      await target.read(materialManifestStoreProvider).append(record);
    }

    Future<List<String>> docClipIds() async {
      final doc = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      return [for (final clip in doc.practiceClips) clip.id];
    }

    test('既有 9 条 + 一次入库 → 文档 10 条（既有条目一条不少）', () async {
      container = buildContainer();
      addTearDown(container.dispose);
      final manifest = container.read(materialManifestStoreProvider);
      for (var i = 1; i <= existingCount; i++) {
        await manifest.append(material(i));
      }
      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;
      // 装载总是发生：恢复后会话态即文档既有片段（无需写回前并集兜底）。
      expect(container.read(practiceClipsProvider), hasLength(existingCount));

      await ingest(container, material(10));
      await session.flush;

      expect(await docClipIds(), [
        for (var i = 1; i <= existingCount; i++) 'clip_mat_$i',
        'clip_mat_10',
      ]);
      // 清单侧一致：既有素材仍在，新素材也在。
      final doc = await manifest.read();
      expect(doc.materials, hasLength(existingCount + 1));
    });

    test('既有 9 条 + 连续三次入库 → 文档 12 条（不累计丢失）', () async {
      container = buildContainer();
      addTearDown(container.dispose);
      final manifest = container.read(materialManifestStoreProvider);
      for (var i = 1; i <= existingCount; i++) {
        await manifest.append(material(i));
      }
      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;

      for (var k = 0; k < 3; k++) {
        await ingest(
          container,
          material(10 + k, sourceStartMs: 200000 + k * 60000),
        );
      }
      await session.flush;

      expect(
        await docClipIds(),
        hasLength(existingCount + 3),
        reason: '三次入库后既有条目仍在、新增三条齐备',
      );
      expect((await manifest.read()).materials, hasLength(existingCount + 3));
    });

    test('入库后片段表与素材清单指向同一集合（每条片段都追得到素材）', () async {
      container = buildContainer();
      addTearDown(container.dispose);
      final manifest = container.read(materialManifestStoreProvider);
      for (var i = 1; i <= existingCount; i++) {
        await manifest.append(material(i));
      }
      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;

      await ingest(container, material(10));
      await session.flush;

      final materialIds = {
        for (final entry in (await manifest.read()).materials) entry.id,
      };
      final clips = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      for (final clip in clips.practiceClips) {
        expect(
          materialIds,
          contains(clip.materialId),
          reason: '片段 ${clip.id} 引用的素材必须仍在清单里',
        );
      }
      expect(materialIds, contains('mat_10'), reason: '新录素材已入清单');
      expect(
        clips.practiceClips,
        hasLength(existingCount + 1),
        reason: '既有 9 条一条不少（两处指向同一集合的方向：片段引用清单）',
      );
      expect(
        clips.practiceClips.length,
        lessThanOrEqualTo(materialIds.length),
        reason: '清单是超集：删轨道引用不动素材，故两处条数不必相等',
      );
    });

    test('删除不回弹：连带删素材 → 文档不再有该素材的引用', () async {
      container = buildContainer();
      addTearDown(container.dispose);
      final manifest = container.read(materialManifestStoreProvider);
      for (var i = 1; i <= existingCount; i++) {
        await manifest.append(material(i));
      }
      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(practiceClipsProvider), hasLength(existingCount));

      // 素材库删除：文件 + 清单条目 + 全部轨道引用一起消失。
      container.read(practiceClipsProvider.notifier).removeByMaterial('mat_3');
      await manifest.remove('mat_3');
      await session.flush;

      final ids = await docClipIds();
      expect(ids, isNot(contains('clip_mat_3')), reason: '连带删除的引用不得被放回');
      expect(ids, [
        'clip_mat_1',
        'clip_mat_2',
        'clip_mat_4',
        'clip_mat_5',
        'clip_mat_6',
        'clip_mat_7',
        'clip_mat_8',
        'clip_mat_9',
      ]);
    });

    test('装载即恢复：轨道看得见既有片段，此后删除不被文档旧表放回', () async {
      container = buildContainer();
      addTearDown(container.dispose);
      final manifest = container.read(materialManifestStoreProvider);
      for (var i = 1; i <= existingCount; i++) {
        await manifest.append(material(i));
      }
      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;

      await ingest(container, material(10));
      await session.flush;
      // 装载总是发生：轨道上看得见既有片段（与文档一致），而不是只剩本次入库那条。
      expect(
        container.read(practiceClipsProvider).map((clip) => clip.id).toList(),
        [for (var i = 1; i <= existingCount; i++) 'clip_mat_$i', 'clip_mat_10'],
      );

      container.read(practiceClipsProvider.notifier).removeByMaterial('mat_1');
      await manifest.remove('mat_1');
      await session.flush;

      final ids = await docClipIds();
      expect(ids, isNot(contains('clip_mat_1')), reason: '删除照常生效');
      expect(ids, hasLength(existingCount), reason: '9 条 − 删掉的 1 条 + 新入轨 1 条');
    });

    test('跨舞不串：换舞即装载新舞片段，写回不混入上一支舞的片段', () async {
      final clipsA = existingClips();
      final clipsB = [
        for (var i = 1; i <= 2; i++)
          PracticeClip(
            id: 'clip_b$i',
            materialId: 'mat_b$i',
            materialSourceStartMs: 30000 * i,
            inMs: 0,
            outMs: 5000,
            materialDurationMs: 5000,
          ),
      ];
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
            historyEntry(filePath: pathB, mirrored: false, videoId: idB),
          ],
        ),
      );
      final docA = InMemoryVideoDocumentStorage(
        local: {
          'version': 3,
          'prefs': {
            'practiceClips': [for (final clip in clipsA) clip.toJson()],
          },
        },
      );
      final docB = InMemoryVideoDocumentStorage(
        local: {
          'version': 3,
          'prefs': {
            'practiceClips': [for (final clip in clipsB) clip.toJson()],
          },
        },
      );
      manifestStorage = MemoryManifestStorage();
      container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          videoIndexStoreProvider.overrideWithValue(index),
          videoDocumentStorageProvider(idA).overrideWithValue(docA),
          videoDocumentStorageProvider(idB).overrideWithValue(docB),
          materialManifestStorageProvider.overrideWithValue(manifestStorage),
        ],
      );
      addTearDown(container.dispose);
      final manifest = container.read(materialManifestStoreProvider);
      for (final clip in clipsA) {
        await manifest.append(
          material(int.parse(clip.materialId.split('_').last)),
        );
      }

      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(practiceClipsProvider), hasLength(existingCount));

      // 换到 B：装载总是发生，会话态换成 B 自己的片段（A 的不串入）。
      unawaited(session.startForVideo(idB));
      await session.started;
      expect(
        container.read(practiceClipsProvider).map((clip) => clip.id).toList(),
        ['clip_b1', 'clip_b2'],
        reason: '换会话即装载新舞片段：旧舞片段不得留在表里',
      );

      await ingest(
        container,
        MaterialRecord(
          id: 'mat_b9',
          videoId: idB,
          createdAt: DateTime.fromMillisecondsSinceEpoch(9000),
          durationMs: 5000,
          sourceStartMs: 400000,
          fileName: 'rec_b9.mp4',
          sizeBytes: 100,
        ),
      );
      await session.flush;

      final doc = await container
          .read(videoDocumentCoordinatorProvider(idB))
          .readLocal();
      expect(doc.practiceClips.map((clip) => clip.id).toList(), [
        'clip_b1',
        'clip_b2',
        'clip_mat_b9',
      ], reason: 'B 文档 = B 既有 + 新入轨；不得混入 A 的片段');
    });

    test('整表写回以会话终值为准：截取终值不被文档旧表复活', () async {
      container = buildContainer();
      addTearDown(container.dispose);
      final session = persistenceOf(container);
      addTearDown(session.dispose);
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(practiceClipsProvider), hasLength(existingCount));

      final trimmed = existingClips().first.trim(inMs: 3000, outMs: 5000);
      container.read(practiceClipsProvider.notifier).restore([trimmed]);
      await session.flush;

      final ids = await docClipIds();
      expect(ids, ['clip_mat_1'], reason: '写回即会话完整视图（删除/截取必须生效）');
      final doc = await container
          .read(videoDocumentCoordinatorProvider(idA))
          .readLocal();
      expect(doc.practiceClips.single.inMs, 3000);
      expect(doc.practiceClips.single.outMs, 5000);
    });
  });

  group('openFor：消费打开会话身份', () {
    /// 建容器与会话共用同一份索引与文档存储：会话建立读到的身份/文档
    /// 与偏好域写入的是同一条写链。
    ProviderContainer containerFor(
      InMemoryVideoIndexStorage index,
      Map<String, InMemoryVideoDocumentStorage> docs,
    ) => ProviderContainer(
      overrides: [
        ...baseOverrides(),
        videoIndexStoreProvider.overrideWithValue(index),
        for (final entry in docs.entries)
          videoDocumentStorageProvider(entry.key)
              .overrideWithValue(entry.value),
      ],
    );

    OpenSession sessionFor(
      InMemoryVideoIndexStorage index,
      Map<String, InMemoryVideoDocumentStorage> docs, {
      required ContentHasher hasher,
    }) => OpenSession(
      filePath: pathA,
      indexStore: index,
      hasher: hasher,
      coordinatorFor: (videoId) => VideoDocumentCoordinator(docs[videoId]!),
    );

    test('按会话给出的身份恢复该文档偏好', () async {
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      final docs = {
        idA: InMemoryVideoDocumentStorage(
          local: {
            'version': 3,
            'prefs': {'layoutLocked': true},
          },
        ),
      };
      container = containerFor(index, docs);
      addTearDown(container.dispose);
      final open = sessionFor(index, docs, hasher: const FixedHasher(idA));
      await open.establish();

      final session = persistence();
      unawaited(session.openFor(open));
      await session.started;

      expect(container.read(layoutLockedProvider), true);
    });

    test('会话未识别身份（摘要失败）→ 维持默认、不写盘', () async {
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      final docs = {idA: InMemoryVideoDocumentStorage()};
      container = containerFor(index, docs);
      addTearDown(container.dispose);
      final open = sessionFor(index, docs, hasher: const _ThrowingHasher());
      await open.establish();

      final session = persistence();
      unawaited(session.openFor(open));
      await session.started;
      container.read(layoutLockedProvider.notifier).toggle();
      await session.flush;

      expect(container.read(layoutLockedProvider), true);
      expect(docs[idA]!.localSnapshot, isEmpty);
    });
  });

  group('节拍提示随舞记忆：落盘与恢复', () {
    test('变更即存：改动画总开关写进该舞 prefs.beatPrompt，公开标记文件不动', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(beatPromptMemoryProvider.notifier).setAnimation(true);
      await session.flush;

      expect(storages[idA]!.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
      });
      expect(storages[idA]!.markersSnapshot, isEmpty);
    });

    test('重开恢复：生效值按记忆恢复，恢复本身不产生任何写盘', () async {
      const seed = {
        'version': 3,
        'prefs': {
          'beatPrompt': {'animation': false, 'soundType': 'vocal'},
        },
      };
      container = makeContainer(localFiles: {idA: seed});
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(container.read(beatPromptEnabledProvider), isFalse);
      expect(container.read(beatPromptMemoryProvider)?.soundType, 'vocal');
      await session.flush;
      expect(storages[idA]!.localSnapshot, seed);
    });

    test('各视频相互独立：改 A 不碰 B 文件，重开 B 取 B 自己的记忆', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      final memory = container.read(beatPromptMemoryProvider.notifier);
      memory
        ..setAnimation(true)
        ..setAnimationStyle('pendulum')
        ..setSound(true)
        ..setSoundType('vocal')
        ..setHalfBeat(false);
      await session.flush;

      expect(storages[idB]!.localSnapshot, isEmpty);

      final sessionB = session;
      unawaited(sessionB.startForVideo(idB));
      await sessionB.started;
      container.read(beatPromptMemoryProvider.notifier).setHalfBeat(true);
      await sessionB.flush;

      expect(storages[idB]!.localSnapshot['prefs']['beatPrompt'], {
        'halfBeat': true,
      });
      expect(storages[idA]!.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'animationStyle': 'pendulum',
        'sound': true,
        'soundType': 'vocal',
        'halfBeat': false,
      });

      // 重开 A：A 的五值原样读回。
      unawaited(sessionB.startForVideo(idA));
      await sessionB.started;
      final restored = container.read(beatPromptMemoryProvider);
      expect(restored?.animation, isTrue);
      expect(restored?.animationStyle, 'pendulum');
      expect(restored?.sound, isTrue);
      expect(restored?.soundType, 'vocal');
      expect(restored?.halfBeat, isFalse);
    });

    test('换视频不串：B 无记忆时上一支舞的记忆不留在生效值里', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(beatPromptMemoryProvider.notifier).setSound(true);
      await session.flush;
      expect(container.read(metronomeSoundEnabledProvider), isTrue);
      unawaited(session.startForVideo(idB));
      await session.started;
      expect(container.read(metronomeSoundEnabledProvider), isFalse);
      expect(container.read(beatPromptMemoryProvider), isNull);
    });

    test('会话未识别身份：维持默认、改动不落盘、不抛错', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(null));
      await session.started;
      container.read(beatPromptMemoryProvider.notifier).setSound(true);
      await session.flush;

      expect(storages[idA]!.localSnapshot, isEmpty);
      expect(storages[idB]!.localSnapshot, isEmpty);
    });

    test('值未变化不产生新写入：同值重选落盘内容不变', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final storage = _CountingLocalStorage();
      final index = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            historyEntry(filePath: pathA, mirrored: false, videoId: idA),
          ],
        ),
      );
      container = ProviderContainer(
        overrides: [
          ...baseOverrides(),
          videoIndexStoreProvider.overrideWithValue(index),
          videoDocumentStorageProvider(idA).overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      container.read(beatPromptMemoryProvider.notifier).setAnimation(false);
      container.read(beatPromptMemoryProvider.notifier).setAnimation(false);
      await session.flush;

      expect(storage.localWrites, 1, reason: '同值重选不重复写盘');
      expect(storage.localSnapshot['prefs']['beatPrompt'], {
        'animation': false,
      });
    });
  });

  group('倍速记忆随舞：落盘与恢复', () {
    test('变更即存：改档写进该舞 prefs.speedRate，公开标记文件不动', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      await container.read(speedControlProvider.notifier).setRate(0.5);
      await session.flush;

      expect(storages[idA]!.localSnapshot['prefs']['speedRate'], 0.5);
      expect(storages[idA]!.markersSnapshot, isEmpty);
    });

    test('重开恢复：读回记忆并立即写穿引擎；恢复本身不产生写盘', () async {
      const seed = {
        'version': 3,
        'prefs': {'speedRate': 0.75},
      };
      container = makeContainer(localFiles: {idA: seed});
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(container.read(speedControlProvider).manualRate, 0.75);
      expect(engine.rate, 0.75, reason: '第一遍就是这支舞的倍率');
      await session.flush;
      expect(storages[idA]!.localSnapshot, seed, reason: '恢复是只读装载');
    });

    test('各视频相互独立：A 改档不碰 B 文件，重开 B 无记忆取原速、重开 A 取 0.5', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      await container.read(speedControlProvider.notifier).setRate(0.5);
      await session.flush;

      expect(storages[idB]!.localSnapshot, isEmpty);

      // 换到 B（无记忆）：不继承 A 的 0.5×，第一遍是出厂原速。
      unawaited(session.startForVideo(idB));
      await session.started;
      expect(container.read(speedControlProvider).manualRate, 1.0);
      expect(container.read(speedControlProvider).memoryRate, isNull);
      expect(engine.rate, 1.0, reason: 'B 的第一遍不带 A 的速率');

      await container.read(speedControlProvider.notifier).setRate(1.25);
      await session.flush;
      expect(storages[idB]!.localSnapshot['prefs']['speedRate'], 1.25);
      expect(storages[idA]!.localSnapshot['prefs']['speedRate'], 0.5);

      // 重开 A：读回 A 自己的 0.5×（B 的 1.25× 不带回来）。
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(speedControlProvider).manualRate, 0.5);
      expect(engine.rate, 0.5);
    });

    test('步进不写记忆：无记忆的舞启用/停用步进不产生 speedRate 键', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      await session.flush;
      expect(storages[idA]!.localSnapshot, isEmpty, reason: '步进的启用不是这支舞的倍率决定');

      await container.read(speedControlProvider.notifier).setStepEnabled(false);
      await session.flush;
      expect(storages[idA]!.localSnapshot, isEmpty);
    });

    test('停用步进回落这支舞的记忆值（不是步进中间档）', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 3,
            'prefs': {'speedRate': 0.75},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      final control = container.read(speedControlProvider.notifier);
      await control.setStepEnabled(true);
      await control.onSegmentLoopLap();
      await control.onSegmentLoopLap();
      await control.onSegmentLoopLap();
      expect(engine.rate, isNot(0.75));

      await control.setStepEnabled(false);
      expect(engine.rate, 0.75);
    });

    test('换舞归零步进：A 启用步进后打开 B，B 步进未启用、遍数清零且第一遍速率正确', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 3,
            'prefs': {'speedRate': 0.5},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      final control = container.read(speedControlProvider.notifier);
      await control.setStepEnabled(true);
      await control.onSegmentLoopLap();
      await control.onSegmentLoopLap();
      expect(container.read(speedControlProvider).stepEnabled, isTrue);
      expect(container.read(speedControlProvider).stepCycle, 2);

      // 换到 B（无记忆）：A 的步进与递进参数不接管 B 的第一遍。
      unawaited(session.startForVideo(idB));
      await session.started;
      expect(container.read(speedControlProvider).stepEnabled, isFalse);
      expect(container.read(speedControlProvider).stepCycle, 0);
      expect(engine.rate, 1.0, reason: 'B 无记忆：第一遍是出厂原速');
    });

    test('会话未识别身份：按无记忆处理、播放不受影响、改动不落盘', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(null));
      await session.started;

      expect(container.read(speedControlProvider).memoryRate, isNull);
      expect(engine.rate, 1.0);

      await container.read(speedControlProvider.notifier).setRate(1.5);
      await session.flush;
      expect(storages[idA]!.localSnapshot, isEmpty);
      expect(storages[idB]!.localSnapshot, isEmpty);

      // 下一次识别打开按换舞复位：未识别会话的 1.5× 不带入 A。
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(speedControlProvider).manualRate, 1.0);
      expect(engine.rate, 1.0);
    });

    test('换舞清空记忆槽：上一支舞的记忆不留在下一支舞的模型里', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 3,
            'prefs': {'speedRate': 0.5},
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(speedControlProvider).memoryRate, 0.5);

      unawaited(session.startForVideo(idB));
      await session.started;
      expect(container.read(speedControlProvider).memoryRate, isNull);
    });
  });

  group('记忆与「已读到」标记随换舞一起复位', () {
    test('换舞复位：记忆与「已读到」标记一起复位，B 独立置开且 A/B 记忆互不带出', () async {
      container = makeContainer(realGrid: true);
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(idA));
      await session.started;

      // A 无记录 + 网格就绪：自动置开一次并落 A 的文件；随后用户把声音
      // 关掉（记进 A 的记忆）。
      await session.flush;
      expect(storages[idA]!.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'sound': true,
      });
      container.read(beatPromptMemoryProvider.notifier).setSound(false);
      await session.flush;
      expect(storages[idA]!.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'sound': false,
      });

      // 换 B：记忆与「已读到」标记一起复位——B 是「读到且无记录」的新舞，
      // 自动置开闸随复位重新武装，B 再被置开一次且只写 B 的文件。若 A 的
      // 记忆（声音关）未清，B 的生效值会停在关、置开判据也不成立。
      unawaited(session.startForVideo(idB));
      await session.started;
      await session.flush;
      expect(container.read(beatPromptMemoryProvider)?.animation, isTrue);
      expect(container.read(beatPromptMemoryProvider)?.sound, isTrue);
      expect(storages[idB]!.localSnapshot['prefs']['beatPrompt'], {
        'animation': true,
        'sound': true,
      });

      // 回 A：A 按自己的记忆恢复（声音仍是用户关掉的关），B 的开不带回来。
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(beatPromptMemoryProvider)?.sound, isFalse);
      expect(container.read(metronomeSoundEnabledProvider), isFalse);
      expect(container.read(beatPromptEnabledProvider), isTrue);
    });

    test('未识别身份：网格就绪也不自动置开，改动不落盘、不带入下一支舞', () async {
      container = makeContainer(
        realGrid: true,
        localFiles: {
          idA: {
            'version': 3,
            'prefs': {
              'beatPrompt': {'sound': false, 'soundType': 'vocal'},
            },
          },
        },
      );
      addTearDown(container.dispose);
      final session = persistence();
      unawaited(session.startForVideo(null));
      await session.started;

      expect(container.read(beatPromptMemoryProvider), isNull);
      container.read(beatPromptMemoryProvider.notifier).setSound(true);
      await session.flush;
      expect(storages[idA]!.localSnapshot, {
        'version': 3,
        'prefs': {
          'beatPrompt': {'sound': false, 'soundType': 'vocal'},
        },
      }, reason: '未识别会话的改动不落盘');
      expect(storages[idB]!.localSnapshot, isEmpty);

      // 未识别会话的改动只在会话槽；下一次识别打开按换舞复位丢弃，
      // A 生效值按 A 自己的记忆（关），未识别会话的「开」不带入。
      unawaited(session.startForVideo(idA));
      await session.started;
      expect(container.read(beatPromptMemoryProvider)?.sound, isFalse);
      expect(container.read(metronomeSoundEnabledProvider), isFalse);
    });
  });
}

/// 摘要失败（打开会话无身份）的哈希桩。
class _ThrowingHasher implements ContentHasher {
  const _ThrowingHasher();

  @override
  Future<String> hashFile(File file) async => throw StateError('摘要失败');
}

/// 计数版按视频存储：统计 local 写次数（一次保存对拍用）。
class _CountingLocalStorage extends InMemoryVideoDocumentStorage {
  int localWrites = 0;

  @override
  Future<void> saveLocal(Map<String, dynamic> json) async {
    localWrites++;
    await super.saveLocal(json);
  }
}
