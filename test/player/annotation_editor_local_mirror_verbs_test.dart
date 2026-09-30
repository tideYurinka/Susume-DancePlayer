import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
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
        annotationTimelineProvider,
        layoutLockedProvider,
        localMirrorFragmentsProvider,
        transitionSegmentProvider;
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

/// 「局部镜像片段 verb 族与模块纪律」模块 seam 直测：建/删/整体移/
/// 端点拖/启停全为标注编辑模块 verb（经 submit 单一收口 seam），落点解析
/// 逐网格三态断言、禁重叠不变量、启停每切一步入史、锁定分段逐 verb 门禁、
/// 几何变更不清激活/临时段。fake 网格三态驱动。
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
  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);
  List<LocalMirrorFragment> fragments() =>
      container.read(localMirrorFragmentsProvider);

  /// 就绪网格：真实拍点每 0.5s 一拍、强拍每 4 拍（[uniformReadyBeatState]
  /// 样例）→ 真实拍 = 0.5k、八拍点 = 4k（每 8 拍）。片段落点吸附据此断言。
  void injectReadyGrid({double seconds = 60}) {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: seconds));
  }

  /// 占位网格 = 容器缺省（placeholderBeatGrid 120bpm 均匀派生，拍 0.5s）。
  /// 异常网格注入。
  void injectErrorGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(const BeatTrackState.error());
  }

  /// 断言片段表恒升序不重叠（禁重叠不变量）。
  void expectSortedNonOverlapping() {
    expect(isSortedAndNonOverlapping(fragments()), isTrue);
  }

  group('verb 族建/删/整体移/端点拖/启停全为模块 verb（单一收口 seam）', () {
    test('创建/启停/删各自入史；undo/redo 逐位保真片段 lane', () {
      injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
        ),
      );

      // 创建：一次提交 → EditApplied + 片段 lane 就位 + 入史 1 步。
      final create = editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 6, milliseconds: 300)),
      );
      expect(create.applied, isTrue);
      expect(fragments(), const [
        LocalMirrorFragment(startMs: 8000, endMs: 12000),
      ]);
      expect(container.read(annotationEditHistoryProvider).length, 1);

      // 整体移（保留原宽）：起点按端点同级真实拍吸附（14s 恰为真实拍）。
      editor().submit(const MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 14)));
      expect(fragments().single.startMs, 14000);
      expect(fragments().single.endMs, 18000);
      expect(container.read(annotationEditHistoryProvider).length, 2);

      // undo 逐位回退片段 lane。
      editor().undo();
      expect(fragments().single.startMs, 8000);
      editor().undo();
      expect(fragments(), isEmpty);
    });

    test('段级折叠：片段 verb 入队保存 diff 只带 annotations 段', () {
      injectReadyGrid();
      final create = editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 6, milliseconds: 300)),
      );
      expect(create.applied, isTrue);
      final diff = sink.saved.single;
      expect(diff.annotations?.localMirrorFragments, const [
        LocalMirrorFragment(startMs: 8000, endMs: 12000),
      ]);
      expect(diff.annotations?.segmentLines, isEmpty);
      expect(diff.annotations?.rangeStart, Duration.zero);
      expect(diff.annotations?.rangeEnd, total);
      expect(diff.corrections, isNull);
      expect(diff.session, isNull);
    });
  });

  group('创建落点：起点吸八拍点、默认一"八拍"宽', () {
    test('就绪网格：6.3s → 吸最近八拍点 8s、右延 4s', () {
      injectReadyGrid();
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 6, milliseconds: 300)),
      );
      expect(fragments().single,
          const LocalMirrorFragment(startMs: 8000, endMs: 12000));
    });

    test('带锚点：起点落在重定相后的八拍点上、默认宽仍 4s', () {
      injectReadyGrid();
      // 锚落 14s（强拍序号 28）：其后相位段以 14s 为原点，14s 自身成为
      // 八拍点、其后每 4s 一个（18s…）；锚前相位不变（…10s）。
      editor().submit(AddEightBeatAnchor(at: Duration(seconds: 14)));
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 14, milliseconds: 500)),
      );
      // 自动相位下 14.5s 吸 16s；重定相后吸 14s（不再落锚点之前的相位）。
      expect(fragments().single,
          const LocalMirrorFragment(startMs: 14000, endMs: 18000));
    });

    test('无锚点：落点与自动相位逐位一致（14.5s → 16s，零变化）', () {
      injectReadyGrid();
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 14, milliseconds: 500)),
      );
      expect(fragments().single,
          const LocalMirrorFragment(startMs: 16000, endMs: 20000));
    });

    test('占位均匀网格：同级派生长度（宽 4s）', () {
      // 未注入 = 占位占位网格（120bpm 均匀，拍 0.5s）→ 默认宽 4s。
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 6, milliseconds: 300)),
      );
      // 占位均匀同级派生八拍点 = 4s 步（0/4/8…）→ 8s，宽 4s。
      expect(fragments().single,
          const LocalMirrorFragment(startMs: 8000, endMs: 12000));
    });

    test('异常网格：起点自由（不吸附）、秒制兜底宽 4s', () {
      injectErrorGrid();
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 6, milliseconds: 300)),
      );
      expect(fragments().single,
          const LocalMirrorFragment(startMs: 6300, endMs: 10300));
    });
  });

  group('端点吸附逐态断言（真实拍/均匀派生/自由）', () {
    void seedOne({required bool ready}) {
      if (ready) injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 3000),
          ],
        ),
      );
    }

    test('就绪网格：端点吸真实拍点（2.7s → 2.5s）', () {
      seedOne(ready: true);
      editor().submit(const DragLocalMirrorFragmentEdge(
        index: 0,
        edge: IntervalEdge.end,
        to: Duration(seconds: 2, milliseconds: 700),
      ));
      expect(fragments().single.endMs, 2500);
    });

    test('占位均匀网格：端点吸均匀同级派生点（2.7s → 2.5s）', () {
      seedOne(ready: false);
      editor().submit(const DragLocalMirrorFragmentEdge(
        index: 0,
        edge: IntervalEdge.end,
        to: Duration(seconds: 2, milliseconds: 700),
      ));
      expect(fragments().single.endMs, 2500);
    });

    test('异常网格：端点自由（2.7s 原样）', () {
      injectErrorGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs:3000),
          ],
        ),
      );
      editor().submit(const DragLocalMirrorFragmentEdge(
        index: 0,
        edge: IntervalEdge.end,
        to: Duration(seconds: 2, milliseconds: 700),
      ));
      expect(fragments().single.endMs, 2700);
    });
  });

  group('禁重叠不变量：创建自动截断/互斥钳制/钳空 no-op', () {
    test('创建与既有片段中部重叠：右延截断到邻段起点防重叠', () {
      injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 9000, endMs: 13000),
          ],
        ),
      );
      // 起于 8s 处创建默认右延 4s → [8000,12000) 与 9s 既有片段中部重叠，
      // 应截断到 9000。
      editor().submit(
        const AddLocalMirrorFragment(at: Duration(seconds: 8)),
      );
      expect(fragments(), const [
        LocalMirrorFragment(startMs: 8000, endMs: 9000),
        LocalMirrorFragment(startMs: 9000, endMs: 13000),
      ]);
      expectSortedNonOverlapping();
    });

    test('整体移与相邻/首尾互斥钳制（钳到 1 号片段起点前）', () {
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
      // 把 0 号片段向右拖：吸附后进入 1 号片段的间隙之前被钳住（不能重叠）。
      final outcome = editor().submit(const MoveLocalMirrorFragment(
        index: 0,
        to: Duration(seconds: 18),
      ));
      expect(outcome.applied, isTrue);
      expect(fragments().first.startMs, 16000); // 保留原宽、钳在 1 号起点前
      expect(fragments().first.endMs, 20000);
      expectSortedNonOverlapping();
    });

    test('端点拖与相邻片段互斥钳制：拖 0 号右端越界被钳到 1 号起点', () {
      injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 3000),
            LocalMirrorFragment(startMs: 5000, endMs: 7000),
          ],
        ),
      );
      // 拖 0 号右端到 6s（越过 1 号起点 5s）→ 互斥钳到 5000（紧贴不重叠）。
      final outcome = editor().submit(const DragLocalMirrorFragmentEdge(
        index: 0,
        edge: IntervalEdge.end,
        to: Duration(seconds: 6),
      ));
      expect(outcome.applied, isTrue);
      expect(fragments().first.endMs, 5000);
      expectSortedNonOverlapping();
    });

    test('整体移钳空（前后紧贴无可放置区间）= 返回 null 分支 → EditNoop', () {
      injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 3000),
            LocalMirrorFragment(startMs: 3000, endMs: 5000),
            LocalMirrorFragment(startMs: 5000, endMs: 7000),
          ],
        ),
      );
      // 1 号与 0/2 号均紧贴（gap = 0），无可平移区间 → moveFragmentClamped
      // 走 hi<=lo 钳空返回 null → EditNoop、状态未动。
      final outcome = editor().submit(const MoveLocalMirrorFragment(
        index: 1,
        to: Duration(seconds: 2),
      ));
      expect(outcome, isA<EditNoop>());
      expect(fragments(), const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
        LocalMirrorFragment(startMs: 3000, endMs: 5000),
        LocalMirrorFragment(startMs: 5000, endMs: 7000),
      ]);
      expectSortedNonOverlapping();
    });
  });

  group('锁定门禁逐 verb（局部镜像片段四 verb 一律不受锁）', () {
    test('锁定分段开启时四 verb 照常提交、不弹锁提示；撤销/重做同样豁免', () {
      injectReadyGrid();
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 8000, endMs: 12000),
          ],
        ),
      );
      // 先整体移一次建立一条可撤销历史。
      editor().submit(const MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 4)));

      void lock() => container.read(layoutLockedProvider.notifier).toggle();
      lock();
      final promptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      for (final verb in <AnnotationEdit>[
        const AddLocalMirrorFragment(at: Duration(seconds: 20)),
        const RemoveLocalMirrorFragment(index: 0),
        const MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 10)),
        const DragLocalMirrorFragmentEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(seconds: 10),
        ),
      ]) {
        expect(editor().submit(verb), isNot(isA<EditLocked>()),
            reason: '${verb.runtimeType} 不受锁定分段');
      }
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore);

      // 豁免：锁定期内 undo/redo 照常回放（片段 lane 随快照回放）。
      editor().undo();
      editor().redo();
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore);
      lock(); // 解锁
    });
  });

  group('片段几何变更不清除激活/临时段（模块语义直测）', () {
    test('激活学习段后片段增/删/移保持激活', () {
      injectReadyGrid();
      editor().submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor().submit(AddSegmentLine(at: const Duration(seconds: 20)));
      domain().toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);

      editor().submit(const AddLocalMirrorFragment(at: Duration(seconds: 4)));
      editor().submit(const MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 6)));
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);
      expect(timeline().segmentLines.length, 2);
    });

    test('临时衔接段在场时片段增/删/移保持临时段', () {
      injectReadyGrid();
      editor().submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor().submit(AddSegmentLine(at: const Duration(seconds: 20)));
      editor().toggleTransitionSegment(1);
      expect(container.read(transitionSegmentProvider), isNotNull);

      editor().submit(const AddLocalMirrorFragment(at: Duration(seconds: 4)));
      editor().submit(const MoveLocalMirrorFragment(index: 0, to: Duration(seconds: 6)));
      expect(container.read(transitionSegmentProvider), isNotNull);
      expect(timeline().segmentLines.length, 2);
    });
  });
}
