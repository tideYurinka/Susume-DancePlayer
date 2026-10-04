import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/annotation/note_sticker.dart'
    show NoteGeometry;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatAlignPreviewOffsetProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkStateProvider,
        annotationSelectionDomainProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        learningEmphasisProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录 diff 的假保存编排（编辑器 → sink 链路断言用）。
class RecordingSink implements AnnotationSaveSink {
  final diffs = <AnnotationSectionDiff>[];

  @override
  void save(AnnotationSectionDiff diff) => diffs.add(diff);

  @override
  Future<void> flush() async {}
}

/// 模块锁门禁 seam 测试（范围收窄为分段结构）：ProviderContainer
/// 直测模块 interface（逐 verb 门禁 / 结果类型「锁门禁拒绝」/ 豁免路径照常），
/// 仿 annotation_editor_test 模板。
///
/// 门禁矩阵：受锁 = 分段结构族（分段线的建/删/移、首尾边界调整、自动分段、
/// 清空分段、flag 切换）；不受锁 = 节拍域（半拍线、节拍对齐、节拍倍频、
/// 八拍锚点）、画面/各片段轨（备注贴纸与备注片段、局部镜像片段）、练习片段
/// 截取与删除，以及重点/熟练度切换、选中/清除选中、激活与临时段会话组、
/// 撤销/重做、恢复装载、恢复前清、复位。
/// 门禁次序 = 锁 → 就绪网格 → 落点。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);

  late ProviderContainer container;
  late FakePlaybackEngine engine;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    container = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);
  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

  void lock() => container.read(layoutLockedProvider.notifier).toggle();

  void seedLines() {
    editor().submit(AddSegmentLine(at: ten));
    editor().submit(AddSegmentLine(at: twenty));
    editor().submit(AddHalfBeatLine(at: const Duration(seconds: 5)));
  }

  /// 就绪网格文档：拍点 0.5/1.0/1.5/2.0s，第 1 拍 downbeat。
  void seedReadyGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(
          BeatTrackState.ready(
            BeatGrid(
              model: 'madmom_downbeat_rnn_full.onnx',
              fps: 100,
              generatedAt: DateTime.utc(2026, 9, 6),
              shift: 0,
              beats: const [
                BeatPoint(t: 0.5, down: true),
                BeatPoint(t: 1.0, down: false),
                BeatPoint(t: 1.5, down: false),
                BeatPoint(t: 2.0, down: false),
              ],
            ),
          ),
        );
  }

  /// 逐 verb 声明表就是锁范围的权威：受锁族恰好是这些 verb。
  const lockedVerbs = <AnnotationEdit>[
    AddSegmentLine(at: Duration(seconds: 15)),
    RemoveSegmentLine(index: 0),
    MoveSegmentLine(index: 0, to: Duration(seconds: 15)),
    SetVideoRange(start: Duration(seconds: 5)),
    AutoSegment(start: Duration.zero, end: Duration(minutes: 1), cuts: []),
    ClearSegmentLines(),
    ToggleSegmentFlag(index: 0),
  ];

  const unlockedVerbs = <AnnotationEdit>[
    AddHalfBeatLine(at: Duration(seconds: 15)),
    MoveHalfBeatLine(index: 0, to: Duration(seconds: 15)),
    RemoveHalfBeatLine(index: 0),
    ApplyBeatShift(delta: Duration.zero, shiftSeconds: 0),
    ApplyBeatDensity(density: 2),
    AddEightBeatAnchor(at: Duration(seconds: 15)),
    RemoveEightBeatAnchor(at: Duration(seconds: 15)),
    ClearEightBeatAnchors(),
    InsertNote(at: Duration(seconds: 15)),
    MoveNote(index: 0, to: Duration(seconds: 15)),
    DragNoteEdge(index: 0, edge: IntervalEdge.start, to: Duration(seconds: 15)),
    SetNoteGeometry(index: 0, geometry: NoteGeometry()),
    RemoveNote(index: 0),
    AddLocalMirrorFragment(at: Duration(seconds: 15)),
    RemoveLocalMirrorFragment(index: 0),
    MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 15)),
    DragLocalMirrorFragmentEdge(
      index: 0,
      edge: IntervalEdge.start,
      to: Duration(seconds: 15),
    ),
    TrimPracticeClip(
      clipId: '',
      edge: IntervalEdge.start,
      to: Duration(seconds: 15),
    ),
    RemovePracticeClip(clipId: ''),
    SetNoteText(index: 0, text: ''),
    ToggleNoteLock(index: 0),
    SetSegmentMastery(order: 0, mastery: LearningMastery.unlearned),
    ToggleSegmentEmphasis(order: 0),
  ];

  group('逐 verb 门禁声明表：只剩分段结构族受锁定分段', () {
    test('受锁 verb 恰好 7 个、不受锁 23 个（范围收窄的唯一声明处）', () {
      for (final verb in lockedVerbs) {
        expect(
          AnnotationEditor.verbGateReasons(verb),
          contains(AnnotationEditGateReason.userLayoutLock),
          reason: '${verb.runtimeType} 应受锁定分段',
        );
      }
      for (final verb in unlockedVerbs) {
        expect(
          AnnotationEditor.verbGateReasons(verb),
          isNot(contains(AnnotationEditGateReason.userLayoutLock)),
          reason: '${verb.runtimeType} 不受锁定分段',
        );
      }
    });
  });

  group('受锁分段结构族：锁定时提交被拒（EditLocked）', () {
    for (final (name, command) in <(String, AnnotationEdit)>[
      ('加分段线', AddSegmentLine(at: Duration(seconds: 15))),
      ('移分段线', MoveSegmentLine(index: 0, to: Duration(seconds: 15))),
      ('删分段线', RemoveSegmentLine(index: 0)),
      ('首尾边界调整', SetVideoRange(start: Duration(seconds: 5))),
      ('清空分段', ClearSegmentLines()),
    ]) {
      test('锁定时 $name 被拒：不成立、不入史、提示触发一次', () {
        seedLines();
        final sink = RecordingSink();
        container.read(annotationSaveSinkStateProvider.notifier).set(sink);
        lock();
        final historyBefore = container
            .read(annotationEditHistoryProvider)
            .length;
        sink.diffs.clear();
        final promptBefore = container.read(
          noticeTriggerProvider(NoticeId.layoutLock),
        );

        final outcome = editor().submit(command);

        expect(outcome, isA<EditLocked>());
        expect(outcome.applied, isFalse);
        expect(outcome.geometryChanged, isFalse);
        expect(
          container.read(annotationEditHistoryProvider).length,
          historyBefore,
        );
        expect(sink.diffs, isEmpty);
        expect(
          container.read(noticeTriggerProvider(NoticeId.layoutLock)),
          promptBefore + 1,
        );
      });
    }

    test('flag 切换受锁：不生效、弹「已锁定分段」', () {
      seedLines();
      lock();
      final before = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      expect(
        editor().submit(const ToggleSegmentFlag(index: 1)),
        isA<EditLocked>(),
      );
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        before + 1,
      );
    });

    test('锁定时状态未动：线位置与首尾保持', () {
      seedLines();
      lock();
      editor().submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
      );
      editor().submit(const SetVideoRange(start: Duration(seconds: 5)));
      expect(timeline().segmentLines.map((l) => l.position), [ten, twenty]);
      expect(timeline().rangeStart, Duration.zero);
      expect(timeline().rangeEnd, total);
    });

    test('锁未开时同一命令照常生效（门禁只在锁定态命中）', () {
      seedLines();
      final outcome = editor().submit(
        MoveSegmentLine(index: 0, to: const Duration(seconds: 15)),
      );
      expect(outcome.applied, isTrue);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('自动分段被拒（门禁先于就绪网格：非就绪也不抛 StateError）', () {
      lock();
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
      final outcome = editor().submitAutoSegment(
        BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          shift: 0,
          beats: const [
            BeatPoint(t: 0.5, down: true),
            BeatPoint(t: 1.0, down: false),
            BeatPoint(t: 1.5, down: false),
            BeatPoint(t: 2.0, down: false),
          ],
        ),
        fullIntervalsPerSegment: 4,
      );
      expect(outcome, isA<EditLocked>());
      expect(timeline().segmentLines, isEmpty);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 1);
    });

    test('清空分段入口被拒', () {
      seedLines();
      lock();
      final outcome = editor().submit(const ClearSegmentLines());
      expect(outcome, isA<EditLocked>());
      expect(timeline().segmentLines, hasLength(2));
    });

    test('锁定中的拖分段线会话逐帧提交被拒（moveTo 返回 null、无净变化收口）', () {
      seedLines();
      lock();
      final session = editor().beginLineDrag(0);
      expect(session.moveTo(const Duration(seconds: 15)), isNull);
      session.end();
      expect(timeline().segmentLines[0].position, ten);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 1);
    });
  });

  group('不受锁族：锁定时照常提交（锁门禁不被点亮、不弹提示）', () {
    test('半拍线的加/移/删照常', () {
      seedLines();
      lock();
      final before = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      expect(
        editor().submit(AddHalfBeatLine(at: const Duration(seconds: 15))),
        isNot(isA<EditLocked>()),
      );
      final index = timeline().halfBeatLines.length - 1;
      editor().submit(MoveHalfBeatLine(index: index, to: ten));
      editor().submit(RemoveHalfBeatLine(index: 0));
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        before,
      );
    });

    test('节拍对齐「应用」照常（登记修正：不再纳入锁门禁）', () {
      seedLines();
      seedReadyGrid();
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.25);
      lock();
      final outcome = editor().submitBeatShift(0.25);
      expect(outcome, isNot(isA<EditLocked>()));
      expect(container.read(beatTrackStateProvider).grid!.shift, 0.25);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('节拍倍频照常', () {
      seedReadyGrid();
      lock();
      final outcome = editor().submitBeatDensity(2);
      expect(outcome, isNot(isA<EditLocked>()));
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('八拍锚点的加/删/清照常', () {
      seedReadyGrid();
      lock();
      final before = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      expect(
        editor().submit(AddEightBeatAnchor(at: const Duration(seconds: 1))),
        isNot(isA<EditLocked>()),
      );
      editor().submit(RemoveEightBeatAnchor(at: const Duration(seconds: 1)));
      editor().submit(const ClearEightBeatAnchors());
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        before,
      );
    });

    test('备注贴纸的建/移/删照常', () {
      lock();
      final before = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      expect(
        editor().submit(InsertNote(at: const Duration(seconds: 15))),
        isNot(isA<EditLocked>()),
      );
      expect(container.read(noteStickersProvider), hasLength(1));
      editor().submit(MoveNote(index: 0, to: const Duration(seconds: 25)));
      editor().submit(RemoveNote(index: 0));
      expect(container.read(noteStickersProvider), isEmpty);
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        before,
      );
    });

    test('局部镜像片段的建/移/删照常', () {
      lock();
      final before = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      expect(
        editor().submit(
          AddLocalMirrorFragment(at: const Duration(seconds: 15)),
        ),
        isNot(isA<EditLocked>()),
      );
      expect(container.read(localMirrorFragmentsProvider), hasLength(1));
      editor().submit(
        MoveLocalMirrorFragment(index: 0, to: const Duration(seconds: 25)),
      );
      editor().submit(const RemoveLocalMirrorFragment(index: 0));
      expect(container.read(localMirrorFragmentsProvider), isEmpty);
      expect(
        container.read(noticeTriggerProvider(NoticeId.layoutLock)),
        before,
      );
    });
  });

  group('豁免路径：锁定时照常', () {
    test('熟练度/重点切换照常', () {
      seedLines();
      lock();
      expect(
        editor()
            .submit(
              SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
            )
            .applied,
        isTrue,
      );
      expect(
        editor().submit(const ToggleSegmentEmphasis(order: 0)).applied,
        isTrue,
      );
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('选中/清除选中/激活/临时段会话组照常', () {
      seedLines();
      lock();
      domain().select(SegmentLineSelection(0));
      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>(),
      );
      domain().clear();
      domain().toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);
      domain().selectOnly(0);
      editor().toggleTransitionSegment(0);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('撤销/重做在锁定期照常回放', () {
      seedLines();
      editor().submit(const SetVideoRange(start: Duration(seconds: 5)));
      lock();
      editor().undo();
      expect(timeline().rangeStart, Duration.zero);
      editor().redo();
      expect(timeline().rangeStart, const Duration(seconds: 5));
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });

    test('恢复装载/恢复前清/复位照常', () {
      seedLines();
      lock();
      editor().clearForVideoRestore();
      editor().restoreDocument(
        const AnnotationRestoreDocument(emphasizedSegments: {0}),
      );
      expect(container.read(learningEmphasisProvider), {0});
      editor().resetForVideo(total);
      expect(timeline().segmentLines, isEmpty);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });
  });
}
