import 'dart:async';

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationMemberSchemeReadonlyProvider, layoutLockedProvider;
import 'package:dance_learning_app/player/framing_session_state.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
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

/// 取景选区随舞记忆：**直写公开标记文件
/// `meta` 段**（去抖合并成一次落盘），不入撤销／重做史、不受锁定分段门禁；
/// 组员方案装载期间调整只改会话值、不落盘；本地文档不承载取景。
void main() {
  const pathA = '/videos/a.mp4';
  const idA = 'vid-a';

  late Map<String, InMemoryVideoDocumentStorage> storages;
  late ProviderContainer container;

  ProviderContainer makeContainer({
    Map<String, Map<String, dynamic>> markersFiles = const {},
    Map<String, Map<String, dynamic>> localFiles = const {},
  }) {
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [historyEntry(filePath: pathA, mirrored: false, videoId: idA)],
      ),
    );
    storages = {
      idA: InMemoryVideoDocumentStorage(
        markers: markersFiles[idA] ?? const {},
        local: localFiles[idA] ?? const {},
      ),
    };
    return ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        speedHistoryAutoRestoreProvider.overrideWithValue(false),
        videoIndexStoreProvider.overrideWithValue(index),
        privateJsonStorageProvider.overrideWithValue(
          InMemoryPrivateJsonStorage(),
        ),
        for (final entry in storages.entries)
          videoDocumentStorageProvider(entry.key)
              .overrideWithValue(entry.value),
      ],
    );
  }

  VideoSettingsPersistence persistence() => VideoSettingsPersistence(container);

  test('会话态默认：源画面未调过（无选区）', () {
    container = makeContainer();
    addTearDown(container.dispose);
    final state = container.read(framingStateProvider);
    expect(state.source, isNull);
  });

  test('手势提交直写公开标记文件 meta.framingSelection（去抖合并成一次落盘）',
      () async {
    container = makeContainer();
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    const selection = FramingSelection(
      left: 0.1,
      top: 0.2,
      right: 0.6,
      bottom: 0.8,
    );
    // 逐帧变更：去抖窗口内的多次提交只落一次盘、留下的终值是最后一次。
    for (final left in [0.1, 0.11, 0.12]) {
      container.read(framingStateProvider.notifier).applySource(
            FramingSelection(
              left: left,
              top: 0.2,
              right: 0.6,
              bottom: 0.8,
            ),
          );
    }
    container.read(framingStateProvider.notifier).applySource(selection);
    await session.flush;

    final markers = storages[idA]!.markersSnapshot;
    expect(markers['version'], 9);
    expect((markers['meta'] as Map)['framingSelection'], {
      'left': 0.1,
      'top': 0.2,
      'right': 0.6,
      'bottom': 0.8,
    });
    // 本地文档不承载取景。
    final prefs = storages[idA]!.localSnapshot['prefs'] as Map? ?? const {};
    expect(prefs.containsKey('framingSource'), isFalse);
    expect(prefs.containsKey('framingPractice'), isFalse);
  });

  test('复位 = 清除取值：写 null 后公开标记文件的取景键消失', () async {
    container = makeContainer();
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;
    final model = container.read(framingStateProvider.notifier);

    model.applySource(
      const FramingSelection(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8),
    );
    await session.flush;
    expect(
      (storages[idA]!.markersSnapshot['meta'] as Map)
          .containsKey('framingSelection'),
      isTrue,
    );

    model.reset();
    await session.flush;

    expect(container.read(framingStateProvider).source, isNull);
    expect(
      (storages[idA]!.markersSnapshot['meta'] as Map)
          .containsKey('framingSelection'),
      isFalse,
    );
  });

  test('组员方案装载期间：调整只改会话值，公开标记文件不落盘', () async {
    container = makeContainer();
    addTearDown(container.dispose);
    container
        .read(annotationMemberSchemeReadonlyProvider.notifier)
        .setLoaded(true);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    const selection = FramingSelection(
      left: 0.15,
      top: 0.15,
      right: 0.65,
      bottom: 0.65,
    );
    container.read(framingStateProvider.notifier).applySource(selection);
    await session.flush;

    expect(container.read(framingStateProvider).source, selection);
    expect(storages[idA]!.markersSnapshot, isEmpty);
  });

  test('更高版本的公开标记文件：认识多少读多少、本机不写回', () async {
    const forward = <String, dynamic>{
      'version': 10,
      'meta': {
        'framingSelection': {
          'left': 0.1,
          'top': 0.1,
          'right': 0.5,
          'bottom': 0.5,
        },
        'futureMetaKey': 'keep',
      },
      'futureDocKey': 1,
    };
    container = makeContainer(markersFiles: {idA: forward});
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    container
        .read(framingStateProvider.notifier)
        .applySource(
          const FramingSelection(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8),
        );
    await session.flush;

    expect(storages[idA]!.markersSnapshot, forward, reason: '高版本文件保持原样');
    expect(
      container.read(noticeTriggerProvider(NoticeId.documentReadOnly)),
      1,
      reason: '真实改动撞上只读文件：弹一次提示，改动不静默丢失',
    );
  });

  test('打开恢复的装载与盘上现值相同：不落盘、不对只读文件弹提示', () async {
    const restored = FramingSelection(
      left: 0.1,
      top: 0.1,
      right: 0.5,
      bottom: 0.5,
    );
    const forward = <String, dynamic>{
      'version': 10,
      'meta': {
        'framingSelection': {
          'left': 0.1,
          'top': 0.1,
          'right': 0.5,
          'bottom': 0.5,
        },
      },
    };
    container = makeContainer(markersFiles: {idA: forward});
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    // 打开恢复是后台进行、订阅可能先挂上：装载盘上的同一值不得被当成用户
    // 改动——否则只读文件会在打开后凭空弹一次提示。
    container.read(framingStateProvider.notifier).restoreSource(restored);
    await session.flush;

    expect(container.read(framingStateProvider).source, restored);
    expect(
      container.read(noticeTriggerProvider(NoticeId.documentReadOnly)),
      0,
      reason: '装载与现值相同即无事发生',
    );
    expect(storages[idA]!.markersSnapshot, forward);
  });

  test('盘上旧 v3 取景键不被读：会话态照常打开为未调过', () async {
    container = makeContainer(
      localFiles: {
        idA: {
          'version': 3,
          'prefs': {
            'framingSource': {'scale': 2.0, 'offsetX': 0.0, 'offsetY': 0.0},
            'framingPractice': {'scale': 'x'},
          },
        },
      },
    );
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    expect(container.read(framingStateProvider).source, isNull);
    expect(container.read(framingStateProvider).sourceTouched, isFalse);
  });

  test('更高版本的 local 文件按认识多少读多少打开、本机不写回',
      () async {
    const forward = <String, dynamic>{
      'version': 5,
      'prefs': {
        'framingSource': {'scale': 2.0, 'offsetX': 0.0, 'offsetY': 0.0},
        'futurePrefsKey': 'keep',
      },
    };
    container = makeContainer(localFiles: {idA: forward});
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    // 变更不落盘：文件保持高版本原样。
    container
        .read(framingStateProvider.notifier)
        .applySource(
          const FramingSelection(left: 0.2, top: 0.2, right: 0.8, bottom: 0.8),
        );
    await session.flush;
    expect(storages[idA]!.localSnapshot, forward);
  });

  test('v3 → v4 迁移在写链上生效：写盘后旧取景键整条消失、版本升 4', () async {
    container = makeContainer(
      localFiles: {
        idA: {
          'version': 3,
          'prefs': {
            'framingSource': {'scale': 3.0, 'offsetX': 0.1, 'offsetY': -0.05},
            'framingPractice': {'scale': 1.5, 'offsetX': 0.0, 'offsetY': 0.0},
          },
        },
      },
    );
    addTearDown(container.dispose);
    final session = persistence();
    unawaited(session.startForVideo(idA));
    await session.started;

    // 触发一次偏好写盘：锁定分段开/关是一次真实变更。
    container.read(layoutLockedProvider.notifier).toggle();
    await session.flush;

    final local = storages[idA]!.localSnapshot;
    expect(local['version'], 4);
    final prefs = local['prefs'] as Map? ?? const {};
    expect(prefs['layoutLocked'], isTrue);
    expect(prefs.containsKey('framingSource'), isFalse);
    expect(prefs.containsKey('framingPractice'), isFalse);
  });

  group('源画面「已调过」口径（取值非空即真，随舞记忆）', () {
    test('默认会话态：未调过', () {
      container = makeContainer();
      addTearDown(container.dispose);
      expect(container.read(framingStateProvider).sourceTouched, isFalse);
    });

    test('手势提交（applySource）即已调过', () {
      container = makeContainer();
      addTearDown(container.dispose);
      final model = container.read(framingStateProvider.notifier);

      model.applySource(
        const FramingSelection(left: 0.3, top: 0.3, right: 0.8, bottom: 0.8),
      );
      expect(container.read(framingStateProvider).sourceTouched, isTrue);
    });

    test('复位 = 清值：回未调过（此后按整帧渲染）', () {
      container = makeContainer();
      addTearDown(container.dispose);
      final model = container.read(framingStateProvider.notifier);

      model.applySource(
        const FramingSelection(left: 0.3, top: 0.3, right: 0.8, bottom: 0.8),
      );
      model.reset();
      expect(container.read(framingStateProvider).sourceTouched, isFalse);
    });
  });
}
