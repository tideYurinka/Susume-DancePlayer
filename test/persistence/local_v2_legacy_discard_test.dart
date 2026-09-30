import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 低于地板的旧本地文档验收：地板 3 之下的 v1／v2 文件读到
/// 空态（唯一合法的读空），且只读——随后任何一次写入都不改盘、原文一字
/// 不动。段与写入者对齐验收用当前版本文件另跑。真实文件 +
/// 内存 fake 双跑。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('local_v2_discard');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  VideoDocumentStorage makeReal() => AtomicVideoDocumentStorage(
    markersFile: File(p.join(tempDir.path, 'markers_abc.json')),
    localFile: File(p.join(tempDir.path, 'local_abc.json')),
  );

  Future<Map<String, dynamic>> readRaw(VideoDocumentStorage storage) async {
    if (storage is AtomicVideoDocumentStorage) {
      return jsonDecode(
        await File(p.join(tempDir.path, 'local_abc.json')).readAsString(),
      ) as Map<String, dynamic>;
    }
    return (storage as InMemoryVideoDocumentStorage).localSnapshot;
  }

  /// v1 老文件：扁平顶层字段（含 snap 包装与 overlay）。
  const v1File = {
    'version': 1,
    'mastery': {'0': 'practicing', '2': 'mastered'},
    'activatedSegments': [1, 2],
    'snap': {'enabled': false, 'previewSnapEnabled': false},
    'delayedLoopBeats': 8,
    'layoutLocked': true,
    'overlay': {'dx': 24.0, 'dy': 96.0, 'rectWidthFactor': 1.5, 'scale': 2.0},
  };

  /// v2 老文件：已是两段 + 版本号形状，但低于地板 3、按空态读出
  /// （含一份旧版节拍提示记忆——记忆同样不读出）。
  const v2File = {
    'version': 2,
    'session': {
      'mastery': {'0': 'mastered'},
      'activatedSegments': [1],
    },
    'prefs': {
      'previewSnapEnabled': false,
      'layoutLocked': true,
      'beatPrompt': {'animation': true, 'sound': true},
    },
  };

  const legacyFiles = {'v1': v1File, 'v2': v2File};

  for (final entry in legacyFiles.entries) {
    for (final (label, make) in [
      ('真实文件', makeReal),
      ('内存 fake', () => InMemoryVideoDocumentStorage(local: entry.value)),
    ]) {
      group('${entry.key} · $label', () {
        test('低于地板：读到空态、只读——三种写入口都不改盘', () async {
          final storage = make();
          if (storage is AtomicVideoDocumentStorage) {
            await storage.saveLocal(entry.value);
          }
          final coordinator = VideoDocumentCoordinator(storage);

          // 打开：读到空态——熟练度/激活/偏好/浮层/记忆全无。
          final opened = await coordinator.readLocal();
          expect(opened, const LocalDocument.empty());
          expect(opened.mastery, isEmpty);
          expect(opened.activatedSegments, isEmpty);
          expect(opened.layoutLocked, isFalse);
          expect(opened.beatPrompt, isNull);
          expect(
            LocalDocument.versionPolicy.isWritable(entry.value),
            isFalse,
          );

          // 三种写入口都试一遍：session / prefs / 记忆。
          await coordinator.patchLocal(
            (doc) => doc.withMasteryMap(const {1: LearningMastery.mastered}),
          );
          await coordinator.patchLocal(
            (doc) =>
                doc.withSnap(previewSnapEnabled: false).withLayoutLocked(true),
          );
          await coordinator.patchLocal(
            (doc) => doc.withBeatPrompt(
              const BeatPromptMemoryFields(animation: true, halfBeat: true),
            ),
          );

          expect(await readRaw(storage), entry.value, reason: '盘上原文一字未动');
        });
      });
    }
  }

  group('两个写入者各写各段（当前版本）', () {
    for (final (label, make) in [
      ('真实文件', makeReal),
      ('内存 fake', () => InMemoryVideoDocumentStorage()),
    ]) {
      test('$label：session 写不覆盖 prefs、反之亦然', () async {
        final storage = make();
        final coordinator = VideoDocumentCoordinator(storage);

        // 偏好写入者先落 prefs。
        await coordinator.patchLocal(
          (doc) =>
              doc.withSnap(previewSnapEnabled: false).withLayoutLocked(true),
        );
        // 保存编排再落 session（保存编排只写 session 段）。
        final sink = AnnotationSaveOrchestrator(coordinator: coordinator);
        sink.save(
          const AnnotationSectionDiff(
            session: LocalSessionValue(
              mastery: {
                0: LearningMastery.learning,
                2: LearningMastery.mastered,
              },
            ),
          ),
        );
        await sink.flush();

        var json = await readRaw(storage);
        expect(json['version'], 4);
        expect(json['session']['mastery'], {
          '0': 'learning',
          '2': 'mastered',
        });
        expect(json['prefs']['previewSnapEnabled'], false);
        expect(json['prefs']['layoutLocked'], true);

        // 偏好写入者再改 prefs：session 熟练度原样保留。
        await coordinator.patchLocal(
          (doc) => doc.withSnap(previewSnapEnabled: true),
        );
        json = await readRaw(storage);
        expect(json['session']['mastery'], {
          '0': 'learning',
          '2': 'mastered',
        });
        expect(json['prefs']['previewSnapEnabled'], true);
      });
    }
  });

  group('低于地板的记忆不被读出、写入不改盘', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('beat_prompt_mem');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('种 v2 文件后写入记忆：读到空态、本地与公开标记文件都一个字节不动', () async {
      final markersFile = File(p.join(dir.path, 'markers_abc.json'));
      const markersBytes = '{"version": 7}';
      await markersFile.writeAsString(markersBytes);
      final localFile = File(p.join(dir.path, 'local_abc.json'));
      await localFile.writeAsString(jsonEncode(v2File));
      final localBytes = await localFile.readAsString();

      final storage = AtomicVideoDocumentStorage(
        markersFile: markersFile,
        localFile: localFile,
      );
      expect(
        await VideoDocumentCoordinator(storage).readLocal(),
        const LocalDocument.empty(),
      );

      await VideoDocumentCoordinator(storage).patchLocal(
        (doc) => doc.withBeatPrompt(
          const BeatPromptMemoryFields(
            animation: true,
            animationStyle: 'pendulum',
            halfBeat: true,
          ),
        ),
      );

      expect(await localFile.readAsString(), localBytes);
      // 公开标记文件一个字节不动。
      expect(await markersFile.readAsString(), markersBytes);
    });
  });
}
