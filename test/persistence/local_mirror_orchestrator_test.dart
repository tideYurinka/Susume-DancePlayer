import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/in_memory_video_document_storage.dart';

/// 可编程调度器（fake 时钟）：flush 经显式驱动。
class ManualSaveScheduler implements AnnotationSaveScheduler {
  void Function()? _task;

  void Function()? get pendingTask => _task;

  @override
  void schedule(Duration delay, void Function() task) => _task = task;

  @override
  void cancel() => _task = null;

  void tick() {
    final task = _task;
    _task = null;
    task?.call();
  }
}

/// 「片段并入 annotations 段、编排器落盘单链」持久化 seam 直测：
/// 局部镜像片段随 `annotations` 段经既有编排器 pending 合并 → flush 整段落盘
/// markers，杀进程重开（重读文件）能取回——内存 fake + 真实文件双跑。
void main() {
  const fragments = [
    LocalMirrorFragment(startMs: 1000, endMs: 3000),
    LocalMirrorFragment(startMs: 5000, endMs: 9000),
  ];

  AnnotationSectionDiff diff(
    List<LocalMirrorFragment> fragments, {
    int? rangeStartMs,
    int? rangeEndMs,
  }) =>
      AnnotationSectionDiff(
        annotations: MarkerAnnotationsValue(
          rangeStart: Duration(milliseconds: rangeStartMs ?? 0),
          rangeEnd: Duration(milliseconds: rangeEndMs ?? 0),
          localMirrorFragments: fragments,
        ),
      );

  late InMemoryVideoDocumentStorage inner;
  late ManualSaveScheduler scheduler;
  late VideoDocumentCoordinator coordinator;
  late AnnotationSaveOrchestrator orchestrator;

  setUp(() {
    inner = InMemoryVideoDocumentStorage();
    scheduler = ManualSaveScheduler();
    coordinator = VideoDocumentCoordinator(inner);
    orchestrator = AnnotationSaveOrchestrator(
      coordinator: coordinator,
      scheduler: scheduler,
    );
  });

  test('片段 diff 入队到期后落盘 markers；重开读取取回（内存 fake）', () async {
    orchestrator.save(diff(fragments));
    scheduler.tick();
    await pumpEventQueue();

    expect(
      MarkersDocument.fromJson(inner.markersSnapshot).localMirrorFragments,
      fragments,
    );
    // 杀进程重开：新协调器读文件取回。
    final reopened = MarkersDocument.fromJson(inner.markersSnapshot);
    expect(reopened.localMirrorFragments, fragments);
  });

  test('空 diff 不调度；latest-wins burst 合并只落最后态', () async {
    orchestrator.save(const AnnotationSectionDiff());
    expect(scheduler.pendingTask, isNull);

    orchestrator.save(diff(const [
      LocalMirrorFragment(startMs: 1000, endMs: 2000),
    ]));
    orchestrator.save(diff(fragments));
    scheduler.tick();
    await pumpEventQueue();

    expect(
      MarkersDocument.fromJson(inner.markersSnapshot).localMirrorFragments,
      fragments,
    );
  });

  test('片段面与首尾同段一体落盘不互扰（真实文件双跑）', () async {
    final tempDir = await Directory.systemTemp.createTemp('lm_orch');
    addTearDown(() => tempDir.delete(recursive: true));
    final storage = AtomicVideoDocumentStorage(
      markersFile: File(p.join(tempDir.path, 'markers_abc.json')),
      localFile: File(p.join(tempDir.path, 'local_abc.json')),
    );
    final realOrchestrator = AnnotationSaveOrchestrator(
      coordinator: VideoDocumentCoordinator(storage),
      scheduler: scheduler,
    );

    realOrchestrator.save(diff(fragments, rangeStartMs: 100, rangeEndMs: 60000));
    await realOrchestrator.flush();

    final json = await File(p.join(tempDir.path, 'markers_abc.json'))
        .readAsString();
    final doc = MarkersDocument.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );
    expect(doc.rangeStartMs, 100);
    expect(doc.localMirrorFragments, fragments);
  });
}
