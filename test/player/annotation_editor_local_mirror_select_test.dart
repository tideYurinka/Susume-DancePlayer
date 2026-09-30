import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        layoutLockedProvider,
        localMirrorFragmentsProvider,
        selectedLocalMirrorFragmentIndexProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/notice.dart' show NoticeId, noticeTriggerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（净变化/撤销入队断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「局部镜像片段选中 / 单击点选 / 拖动会话」模块 seam 直测：
/// 片段点选（单选槽选中态）走模块、派生 selected 索引越界失效、
/// 删除清选中、tap = 只选中（锁定期照常选中）、整体移/端点拖
/// 会话单步入史。fake 网格三态驱动。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);
  List<LocalMirrorFragment> fragments() =>
      container.read(localMirrorFragmentsProvider);
  AnnotationSelection? selection() =>
      container.read(annotationSelectionProvider);
  int? selectedFragmentIndex() =>
      container.read(selectedLocalMirrorFragmentIndexProvider);

  void injectReadyGrid({double seconds = 60}) {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: seconds));
  }

  void seedOne({bool ready = true}) {
    if (ready) injectReadyGrid();
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        localMirrorFragments: const [
          LocalMirrorFragment(startMs: 8000, endMs: 12000),
        ],
      ),
    );
  }

  void seedTwo() {
    injectReadyGrid();
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        localMirrorFragments: const [
          LocalMirrorFragment(startMs: 8000, endMs: 12000),
          LocalMirrorFragment(startMs: 20000, endMs: 24000),
        ],
      ),
    );
  }

  group('选中：点选/拖动会话 begin 置入单选槽 + 派生 selected 越界失效', () {
    test('拖动会话 begin 选中目标片段；派生返回有效索引', () {
      seedTwo();
      final session = editor().beginLocalMirrorMoveDrag(1);
      final sel = selection();
      expect(sel, isA<LocalMirrorFragmentSelection>());
      expect((sel! as LocalMirrorFragmentSelection).index, 1);
      expect(selectedFragmentIndex(), 1);
      session.end();
    });

    test('选中异类（如分段线）后片段派生 selected 为 null（共用单选槽）', () {
      seedOne();
      editor().submit(AddSegmentLine(at: const Duration(seconds: 4)));
      domain().select(SegmentLineSelection(0));
      expect(selectedFragmentIndex(), isNull);
      expect(selection(), isA<SegmentLineSelection>());
    });

    test('删除后选中失效：RemoveLocalMirrorFragment 清选中、派生 null', () {
      seedOne();
      // 经模块点选路径（tap = 只选中）置选。
      domain().select(LocalMirrorFragmentSelection(0));
      expect(selectedFragmentIndex(), 0);
      editor().submit(const RemoveLocalMirrorFragment(index: 0));
      expect(fragments(), isEmpty);
      expect(selection(), isNull);
      expect(selectedFragmentIndex(), isNull);
    });

    test('选中片段被 undo 回退删除后（片段消失）派生 selected 越界失效', () {
      injectReadyGrid();
      // 经 verb 创建（入史）→ tap 选中（不产生编辑步）→ undo 回退到创建
      // 前 → 片段消失、派生 selected 失效。
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 6, milliseconds: 300)),
      );
      domain().select(LocalMirrorFragmentSelection(0));
      expect(selectedFragmentIndex(), 0);
      expect(fragments(), isNotEmpty);
      editor().undo(); // 回退创建 → 片段消失
      expect(fragments(), isEmpty);
      expect(selectedFragmentIndex(), isNull);
    });
  });

  group('tapLocalMirrorFragment：单击 = 只选中', () {
    test('就绪：只改选中，不改片段表、不产生编辑/撤销步、不入队保存', () {
      seedOne();
      final beforeHist = container.read(annotationEditHistoryProvider).length;
      domain().select(LocalMirrorFragmentSelection(0));
      expect(selectedFragmentIndex(), 0);
      expect(container.read(annotationEditHistoryProvider).length, beforeHist);
      expect(sink.saved, isEmpty);
    });

    test('锁定分段：照常选中（选中不改几何，锁提示不因点选出现）', () {
      seedOne();
      container.read(layoutLockedProvider.notifier).toggle();
      domain().select(LocalMirrorFragmentSelection(0));
      expect(selectedFragmentIndex(), 0);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });
  });

  group('拖动会话：整体移/端点拖各单步入史', () {
    test('整体移会话：begin 选中 + moveTo 钳制 + end 单步入史', () {
      seedTwo();
      final beforeHist = container.read(annotationEditHistoryProvider).length;
      final session = editor().beginLocalMirrorMoveDrag(0);
      expect(selectedFragmentIndex(), 0);
      // 拖到 18s（0 号宽 4s，会与 1 号起点 20s 互斥钳到 16s）。
      final landed = session.moveTo(const Duration(seconds: 18));
      expect(landed, const Duration(seconds: 16));
      session.end();
      expect(fragments().first.startMs, 16000);
      expect(container.read(annotationEditHistoryProvider).length, beforeHist + 1);
    });

    test('端点拖会话：begin 选中 + 钳制到邻段起点 + end 单步入史', () {
      seedTwo();
      final beforeHist = container.read(annotationEditHistoryProvider).length;
      final session = editor().beginLocalMirrorEdgeDrag(
        0,
        IntervalEdge.end,
      );
      expect(selectedFragmentIndex(), 0);
      final landed = session.moveTo(const Duration(seconds: 25));
      // 拖 0 号右端越过 1 号起点 20s → 钳到 20000。
      expect(landed, const Duration(seconds: 20));
      session.end();
      expect(fragments().first.endMs, 20000);
      expect(container.read(annotationEditHistoryProvider).length, beforeHist + 1);
    });

    test('会话内 moveTo no-op（钳空）不写不误记历史', () {
      injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            // 0 号紧贴 rangeStart 且 1 号紧贴其后：0 号宽 4s、1 号起 4s，
            // 无可平移区间（hi = 4-4 = 0 ≤ lo = 0）→ 整体移钳空 = no-op。
            LocalMirrorFragment(startMs: 0, endMs: 4000),
            LocalMirrorFragment(startMs: 4000, endMs: 8000),
          ],
        ),
      );
      final beforeHist = container.read(annotationEditHistoryProvider).length;
      final session = editor().beginLocalMirrorMoveDrag(0);
      final landed = session.moveTo(const Duration(seconds: 10));
      expect(landed, isNull);
      session.end();
      expect(fragments(), const [
        LocalMirrorFragment(startMs: 0, endMs: 4000),
        LocalMirrorFragment(startMs: 4000, endMs: 8000),
      ]);
      // 全程无净变化 → 会话收口折叠空 → 不入史。
      expect(container.read(annotationEditHistoryProvider).length, beforeHist);
    });
  });
}
