import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 可编程调度器（fake 时钟）：入队后的合并写由测试显式 [tick] 驱动，
/// 「到期未写即挂起、flush 强制写」据此断言。
class ManualSaveScheduler implements AnnotationSaveScheduler {
  void Function()? _task;

  /// 当前挂起的到期回调（null = 无挂起）。
  void Function()? get pendingTask => _task;

  @override
  void schedule(Duration delay, void Function() task) => _task = task;

  @override
  void cancel() => _task = null;

  /// 时间到达：执行挂起的合并写。
  void tick() {
    final task = _task;
    _task = null;
    task?.call();
  }
}

/// 记录写次数的假 store（burst 合并「只写一次」断言用）。
class CountingVideoDocumentStorage implements VideoDocumentStorage {
  CountingVideoDocumentStorage(this._inner);

  final InMemoryVideoDocumentStorage _inner;
  int markersWrites = 0;
  int localWrites = 0;

  @override
  Future<Map<String, dynamic>> loadMarkers() => _inner.loadMarkers();

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() =>
      _inner.loadMarkersOrNull();

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) async {
    markersWrites++;
    await _inner.saveMarkers(json);
  }

  @override
  Future<Map<String, dynamic>> loadLocal() => _inner.loadLocal();

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() => _inner.loadLocalOrNull();

  @override
  Future<void> saveLocal(Map<String, dynamic> json) async {
    localWrites++;
    await _inner.saveLocal(json);
  }

  @override
  Future<void> delete() => _inner.delete();

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    var wrote = false;
    await _inner.mutateMarkers((json, {required bool present}) async {
      final before = jsonEncode(json);
      await apply(json, present: present);
      wrote = jsonEncode(json) != before;
    });
    if (wrote) markersWrites++;
  }

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    var wrote = false;
    await _inner.mutateLocal((json, {required bool present}) async {
      final before = jsonEncode(json);
      await apply(json, present: present);
      wrote = jsonEncode(json) != before;
    });
    if (wrote) localWrites++;
  }
}

/// 段级 diff 助手：默认构造一份非空 `annotations` 段（分段线 + 首尾 +
/// 半拍线 + 重点一体），`corrections` / `mastery` 按需覆盖。
AnnotationSectionDiff diff({
  MarkerCorrectionsValue? corrections,
  List<SegmentLine>? segmentLines,
  int? rangeStartMs,
  int? rangeEndMs,
  List<HalfBeatLine>? halfBeatLines,
  Map<int, LearningMastery>? mastery,
  List<int>? emphasizedSegments,
  double? beatShiftSeconds,
  List<int>? eightBeatAnchors,
  List<int>? activatedSegments,
  bool withAnnotations = true,
}) => AnnotationSectionDiff(
  corrections:
      corrections ??
      (beatShiftSeconds == null && eightBeatAnchors == null
          ? null
          : MarkerCorrectionsValue(
              shiftSeconds: beatShiftSeconds ?? 0,
              eightBeatAnchors: eightBeatAnchors ?? const [],
            )),
  annotations: !withAnnotations
      ? null
      : MarkerAnnotationsValue(
          rangeStart: Duration(milliseconds: rangeStartMs ?? 0),
          rangeEnd: Duration(milliseconds: rangeEndMs ?? 0),
          segmentLines: segmentLines ?? const [],
          halfBeatLines: halfBeatLines ?? const [],
          emphasizedSegments: (emphasizedSegments ?? const []).toSet(),
        ),
  session: mastery == null && activatedSegments == null
      ? null
      : LocalSessionValue(
          mastery: mastery ?? const {},
          activatedSegments: activatedSegments ?? const [],
        ),
);

void main() {
  late InMemoryVideoDocumentStorage inner;
  late CountingVideoDocumentStorage storage;
  late ManualSaveScheduler scheduler;
  late VideoDocumentCoordinator coordinator;
  late AnnotationSaveOrchestrator orchestrator;

  setUp(() {
    inner = InMemoryVideoDocumentStorage();
    storage = CountingVideoDocumentStorage(inner);
    scheduler = ManualSaveScheduler();
    coordinator = VideoDocumentCoordinator(storage);
    orchestrator = AnnotationSaveOrchestrator(
      coordinator: coordinator,
      scheduler: scheduler,
    );
  });

  group('入队与落盘（三条段臂）', () {
    test('单次编辑到期后段级落盘（markers 两条臂 + local 一条臂）', () async {
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 4200), flagged: true),
          ],
          rangeStartMs: 1000,
          rangeEndMs: 50000,
          emphasizedSegments: const [0, 2],
          mastery: const {1: LearningMastery.mastered},
        ),
      );

      scheduler.tick();
      await pumpEventQueue();

      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.segmentLines, const [
        SegmentLine(position: Duration(milliseconds: 4200), flagged: true),
      ]);
      expect(markers.rangeStartMs, 1000);
      expect(markers.rangeEndMs, 50000);
      expect(markers.emphasizedSegments, const [0, 2]);
      expect(LocalDocument.fromJson(inner.localSnapshot).mastery, const {
        1: LearningMastery.mastered,
      });
    });

    test('只变更的文件写、未变更的文件不写（段级 diff）', () async {
      orchestrator.save(
        diff(
          withAnnotations: false,
          mastery: const {0: LearningMastery.learning},
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      expect(storage.markersWrites, 0);
      expect(storage.localWrites, 1);
    });

    test('空 diff 不调度、不落盘', () async {
      orchestrator.save(const AnnotationSectionDiff());
      expect(scheduler.pendingTask, isNull);
    });

    test('corrections 段写定平移量：原始拍点不动、只改 shift', () async {
      final beat = BeatGrid(
        model: 'madmom_downbeat_rnn_full.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 9, 6),
        beats: const [
          BeatPoint(t: 0.5, down: true),
          BeatPoint(t: 1.0, down: false),
        ],
      );
      await inner.saveMarkers(MarkersDocument(beat: beat).toJson());
      storage.markersWrites = 0;

      orchestrator.save(diff(withAnnotations: false, beatShiftSeconds: 0.25));
      scheduler.tick();
      await pumpEventQueue();

      expect(storage.markersWrites, 1);
      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.beat!.shift, 0.25);
      expect(markers.beat!.beats, beat.beats);
      expect(markers.beat!.model, beat.model);
    });

    test('corrections 段写定锚点：拍点/平移量不受影响', () async {
      final beat = BeatGrid(
        model: 'madmom_downbeat_rnn_full.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 9, 6),
        shift: 0.25,
        beats: const [
          BeatPoint(t: 0.5, down: true),
          BeatPoint(t: 1.0, down: false),
        ],
      );
      await inner.saveMarkers(MarkersDocument(beat: beat).toJson());
      storage.markersWrites = 0;

      orchestrator.save(
        diff(
          withAnnotations: false,
          beatShiftSeconds: 0.25,
          eightBeatAnchors: const [28, 40],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      expect(storage.markersWrites, 1);
      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.beat!.anchors, [28, 40]);
      expect(markers.beat!.shift, 0.25);
      expect(markers.beat!.beats, beat.beats);
    });

    test('无 beat 段（未分析）时 corrections 段静默跳过、锚点不落盘', () async {
      orchestrator.save(
        diff(withAnnotations: false, eightBeatAnchors: const [28]),
      );
      scheduler.tick();
      await pumpEventQueue();

      expect(MarkersDocument.fromJson(inner.markersSnapshot).beat, isNull);
    });
  });

  group('burst 合并（latest-wins）', () {
    test('同段快速连续编辑合并为一次写，落盘为最后状态', () async {
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 2000)),
          ],
        ),
      );
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 3000), flagged: true),
          ],
        ),
      );

      scheduler.tick();
      await pumpEventQueue();

      expect(storage.markersWrites, 1);
      expect(
        MarkersDocument.fromJson(inner.markersSnapshot).segmentLines,
        const [
          SegmentLine(position: Duration(milliseconds: 3000), flagged: true),
        ],
      );
    });

    test('同段 latest-wins、异段并集：跨段各取最新共写一次', () async {
      // annotations + session 异段并集。
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
          mastery: const {0: LearningMastery.learning},
        ),
      );
      // corrections + annotations 异段并集（annotations latest-wins）。
      orchestrator.save(
        diff(
          beatShiftSeconds: 0.5,
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1500)),
          ],
        ),
      );

      scheduler.tick();
      await pumpEventQueue();

      expect(storage.markersWrites, 1);
      expect(storage.localWrites, 1);
      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.segmentLines, const [
        SegmentLine(position: Duration(milliseconds: 1500)),
      ]);
      expect(LocalDocument.fromJson(inner.localSnapshot).mastery, const {
        0: LearningMastery.learning,
      });
    });

    test('session 段绝对终值整段落盘：激活学习段随段值写入', () async {
      orchestrator.save(
        diff(
          withAnnotations: false,
          mastery: const {0: LearningMastery.mastered},
          activatedSegments: const [1, 0],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      final local = LocalDocument.fromJson(inner.localSnapshot);
      expect(local.mastery, const {0: LearningMastery.mastered});
      expect(local.activatedSegments, const [1, 0]);
    });

    test('同 burst 内两次 session 保存 latest-wins：全量终值覆盖', () async {
      orchestrator.save(
        diff(
          withAnnotations: false,
          mastery: const {0: LearningMastery.mastered},
          activatedSegments: const [0],
        ),
      );
      // 第二次保存的全量终值：熟练度更新、激活清空（用户取消了激活）。
      orchestrator.save(
        diff(
          withAnnotations: false,
          mastery: const {0: LearningMastery.learning},
          activatedSegments: const [],
        ),
      );

      scheduler.tick();
      await pumpEventQueue();

      expect(storage.localWrites, 1);
      final local = LocalDocument.fromJson(inner.localSnapshot);
      expect(local.mastery, const {0: LearningMastery.learning});
      expect(local.activatedSegments, isEmpty);
    });

    test('burst 期间文件保持旧内容（到期前不落盘）', () async {
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      expect(inner.markersSnapshot, isEmpty);

      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 2000)),
          ],
        ),
      );
      expect(inner.markersSnapshot, isEmpty);
    });
  });

  group('强制 flush', () {
    test('到期前 flush 立即落盘并取消挂起回调', () async {
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );

      await orchestrator.flush();
      expect(inner.markersSnapshot['annotations']['segmentLines'], isNotEmpty);
      expect(scheduler.pendingTask, isNull);
    });

    test('无挂起 flush 幂等不写', () async {
      await orchestrator.flush();
      expect(storage.markersWrites, 0);
      expect(storage.localWrites, 0);
    });
  });

  group('写失败兜底', () {
    test('flush 遇写失败静默不抛，后续保存照常', () async {
      orchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );

      final failing = _FailingStorage(inner, failMarkersWrites: 1);
      final failingOrchestrator = AnnotationSaveOrchestrator(
        coordinator: VideoDocumentCoordinator(failing),
        scheduler: scheduler,
      );
      failingOrchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );

      await expectLater(failingOrchestrator.flush(), completes);
      expect(inner.markersSnapshot, isEmpty);
      // 同一编排器后续保存不受失败影响（异常耗尽后落盘成功）。
      failingOrchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 2000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();
      expect(
        MarkersDocument.fromJson(inner.markersSnapshot).segmentLines,
        const [SegmentLine(position: Duration(milliseconds: 2000))],
      );
    });

    test('markers 写失败不拖累同批 session 段落盘', () async {
      final failing = _FailingStorage(inner, failMarkersWrites: 99);
      final failingOrchestrator = AnnotationSaveOrchestrator(
        coordinator: VideoDocumentCoordinator(failing),
        scheduler: scheduler,
      );
      failingOrchestrator.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
          mastery: const {0: LearningMastery.mastered},
        ),
      );

      await expectLater(failingOrchestrator.flush(), completes);
      expect(inner.markersSnapshot, isEmpty);
      expect(LocalDocument.fromJson(inner.localSnapshot).mastery, const {
        0: LearningMastery.mastered,
      });
    });
  });

  group('markers 首建初值（index 署名缓存 + 镜像过渡值）', () {
    test('markers 不存在时首次写带署名 + 镜像初值', () async {
      final orchestratorWithSeed = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async => const AnnotationSaveSeed(
          signature: SongSignature(song: 'My Love', remark: '9人版'),
          mirrored: true,
        ),
      );

      orchestratorWithSeed.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.signature?.song, 'My Love');
      expect(markers.signature?.remark, '9人版');
      expect(markers.mirrored, true);
      expect(markers.segmentLines, const [
        SegmentLine(position: Duration(milliseconds: 1000)),
      ]);
    });

    test('markers 已存在（有真实内容）时首建初值不覆盖现值', () async {
      await coordinator.patchMarkers(
        (doc) => doc
            .withMirrored(false)
            .withSignature(const SongSignature(song: 'Old'))
            .withSegmentLines(const [
              SegmentLine(position: Duration(milliseconds: 500)),
            ]),
      );

      final orchestratorWithSeed = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async => const AnnotationSaveSeed(
          signature: SongSignature(song: 'New'),
          mirrored: true,
        ),
      );
      orchestratorWithSeed.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.mirrored, false);
      expect(markers.signature?.song, 'Old');
    });

    test('标注保存不改变局部镜像总开关取值（首建初值带过渡值 / 已存在则原样）', () async {
      // ① markers 不存在：首建初值取 index 过渡值 false，随后标注落盘不得冲成 true。
      final seeded = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async => const AnnotationSaveSeed(localMirrorEnabled: false),
      );
      seeded.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();
      expect(
        MarkersDocument.fromJson(inner.markersSnapshot).localMirrorEnabled,
        isFalse,
        reason: '标注保存的首建初值带总开关过渡值',
      );

      // ② markers 已存在：后续标注保存（含撤销回放的绝对终值写）不触碰 meta。
      final orchestrator2 = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async => const AnnotationSaveSeed(localMirrorEnabled: true),
      );
      orchestrator2.save(diff(segmentLines: const []));
      scheduler.tick();
      await pumpEventQueue();
      expect(
        MarkersDocument.fromJson(inner.markersSnapshot).localMirrorEnabled,
        isFalse,
        reason: '既有文件的总开关现值不被标注保存/撤销写覆盖',
      );
    });

    test('首建初值只取一次（首个 markers 写时取，后续写不重复取）', () async {
      var seedCalls = 0;
      final orchestratorWithSeed = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async {
          seedCalls++;
          return const AnnotationSaveSeed(mirrored: true);
        },
      );

      orchestratorWithSeed.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();
      expect(seedCalls, 1);

      orchestratorWithSeed.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 2000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();
      expect(seedCalls, 1);
      expect(MarkersDocument.fromJson(inner.markersSnapshot).mirrored, true);
    });

    test('markers 文件存在但全字段为 v1 缺省值时按「存在」对待，不补种初值', () async {
      await coordinator.patchMarkers((doc) => doc);
      expect(inner.markersSnapshot, isEmpty); // patch 无变化跳写，文件仍不存在

      // 显式落一份全缺省 v1 文件（存在但无现值信息）。
      await inner.saveMarkers(const MarkersDocument.empty().toJson());
      final orchestratorWithSeed = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async => const AnnotationSaveSeed(
          signature: SongSignature(song: 'New'),
          mirrored: true,
        ),
      );

      orchestratorWithSeed.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.mirrored, false);
      expect(markers.signature, isNull);
    });

    test('markers 文件损坏（不存在判定）时首写仍带首建初值', () async {
      inner.corruptMarkers();
      final orchestratorWithSeed = AnnotationSaveOrchestrator(
        coordinator: coordinator,
        scheduler: scheduler,
        seed: () async => const AnnotationSaveSeed(
          signature: SongSignature(song: 'My Love'),
          mirrored: true,
        ),
      );

      orchestratorWithSeed.save(
        diff(
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 1000)),
          ],
        ),
      );
      scheduler.tick();
      await pumpEventQueue();

      final markers = MarkersDocument.fromJson(inner.markersSnapshot);
      expect(markers.mirrored, true);
      expect(markers.signature?.song, 'My Love');
    });
  });

  group('notes 臂', () {
    const note = NoteSticker(
      startMs: 8000,
      endMs: 16000,
      text: '这里注意手',
      locked: true,
      geometry: NoteGeometry(centerX: 0.4, centerY: 0.2, scale: 1.5),
    );

    /// 预置一份带 beat / corrections 的 markers 文件。
    Future<void> seedMarkersWithBeatAndCorrections() async {
      await coordinator.patchMarkers((doc) => doc.withMirrored(true));
      await inner.saveMarkers(
        MarkersDocument.fromJson(inner.markersSnapshot)
            .withBeat(
              BeatGrid(
                model: 'madmom_downbeat_rnn_full.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2026, 9, 1),
                beats: const [BeatPoint(t: 0.5, down: true)],
              ),
            )
            .withCorrections(
              const MarkerCorrectionsValue(
                shiftSeconds: 0,
                eightBeatAnchors: [7],
              ),
            )
            .toJson(),
      );
    }

    test('notes 臂到期落盘：只写 notes 段，beat / corrections / meta 原样', () async {
      await seedMarkersWithBeatAndCorrections();
      final before = inner.markersSnapshot;

      orchestrator.save(AnnotationSectionDiff(notes: const [note]));
      scheduler.tick();
      await pumpEventQueue();

      final after = inner.markersSnapshot;
      expect(MarkersDocument.fromJson(after).notes, const [note]);
      expect(after['beat'], before['beat']);
      expect(after['corrections'], before['corrections']);
      expect(after['meta'], before['meta']);
    });

    test('flush 落挂起 notes 臂（切后台 / 退出播放器）', () async {
      orchestrator.save(AnnotationSectionDiff(notes: const [note]));
      // 未到期（不 tick）：flush 强制落盘。
      await orchestrator.flush();
      await pumpEventQueue();

      expect(MarkersDocument.fromJson(inner.markersSnapshot).notes, const [
        note,
      ]);
    });

    test('同类 burst 合并：连续两次 notes 编辑只落盘一次、latest-wins', () async {
      const first = NoteSticker(startMs: 0, endMs: 4000, text: 'a');
      const second = NoteSticker(startMs: 8000, endMs: 16000, text: 'b');
      orchestrator.save(AnnotationSectionDiff(notes: const [first]));
      orchestrator.save(AnnotationSectionDiff(notes: const [second]));
      scheduler.tick();
      await pumpEventQueue();

      expect(storage.markersWrites, 1);
      expect(MarkersDocument.fromJson(inner.markersSnapshot).notes, const [
        second,
      ]);
    });
  });
}

/// 前 [failMarkersWrites] 次 markers 写抛异常的假 store（写失败兜底用）。
class _FailingStorage implements VideoDocumentStorage {
  _FailingStorage(this._inner, {required int failMarkersWrites})
    : _remainingFailures = failMarkersWrites;

  final InMemoryVideoDocumentStorage _inner;
  int _remainingFailures;

  @override
  Future<Map<String, dynamic>> loadMarkers() => _inner.loadMarkers();

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() =>
      _inner.loadMarkersOrNull();

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) async {
    if (_remainingFailures > 0) {
      _remainingFailures--;
      throw FileSystemException('disk full');
    }
    await _inner.saveMarkers(json);
  }

  @override
  Future<Map<String, dynamic>> loadLocal() => _inner.loadLocal();

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() => _inner.loadLocalOrNull();

  @override
  Future<void> saveLocal(Map<String, dynamic> json) => _inner.saveLocal(json);

  @override
  Future<void> delete() => _inner.delete();

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) => _inner.mutateMarkers((json, {required bool present}) async {
    if (_remainingFailures > 0) {
      _remainingFailures--;
      throw FileSystemException('disk full');
    }
    await apply(json, present: present);
  });

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) => _inner.mutateLocal(apply);
}
