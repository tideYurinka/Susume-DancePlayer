import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/edit_history.dart'
    show EditHistory;
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditSnapshot,
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationTimelineProvider,
        effectiveAnnotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider,
        selectedLearningSegmentRepresentativeProvider,
        selectedLearningSegmentRangeProvider,
        selectedSegmentLineIndexProvider,
        selectedVideoRangeBoundaryProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 标注编辑模块面测试：ProviderContainer 直测模块
/// interface（submit 命令代数 / outcome / 拖动会话 / undo-redo-reset /
/// 封闭会话组），仿 annotation_edit_history_test 模板。
///
/// store 私有化：激活/临时段模型不再 build-watch 自清，本文件
/// 的「几何 diff 才清」行为修正点用例直接对**真实 store** 端到端验证
/// （无替身、无 override）。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);
  const thirty = Duration(seconds: 30);
  const forty = Duration(seconds: 40);

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
  EditHistory<AnnotationEditSnapshot> history() =>
      container.read(annotationEditHistoryProvider);

  /// 经模块命令播种 [positions] 各一条分段线（不走 notifier 直写）。
  void seedLines(List<Duration> positions) {
    for (final position in positions) {
      editor().submit(AddSegmentLine(at: position));
    }
  }

  group('submit：outcome 与错误契约', () {
    test('加线 applied 且 geometryChanged；同位加线 EditNoop 且不入史', () {
      final first = editor().submit(AddSegmentLine(at: ten));
      expect(first.applied, isTrue);
      expect(first.geometryChanged, isTrue);
      expect(history().length, 1);

      final second = editor().submit(AddSegmentLine(at: ten));
      expect(second.applied, isFalse);
      expect(second.geometryChanged, isFalse);
      expect(history().length, 1);
    });

    test('区间外加线 EditNoop 静默且不半写不入史', () {
      // 吸附入模块后：无就绪网格 → 请求直通合法域检查；触界 = 编辑不成立。
      expect(editor().submit(AddSegmentLine(at: Duration.zero)), isA<EditNoop>());
      expect(editor().submit(AddSegmentLine(at: total)), isA<EditNoop>());
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(history().canUndo, isFalse);
    });

    test('非法索引删除/标记 RangeError 且不半写', () {
      seedLines([ten]);
      expect(
        () => editor().submit(RemoveSegmentLine(index: 5)),
        throwsRangeError,
      );
      expect(
        () => editor().submit(ToggleSegmentFlag(index: -1)),
        throwsRangeError,
      );
      expect(
        container.read(annotationTimelineProvider).segmentLines.length,
        1,
      );
      expect(history().length, 1);
    });

    test('越邻/触界移动 no-op', () {
      seedLines([ten, thirty]);
      final before = history().length;

      expect(
        editor()
            .submit(MoveSegmentLine(index: 0, to: thirty))
            .applied,
        isFalse,
      );
      expect(editor().submit(MoveSegmentLine(index: 1, to: total)).applied,
          isFalse,);
      expect(
        editor().submit(MoveSegmentLine(index: 0, to: Duration.zero)).applied,
        isFalse,
      );
      expect(history().length, before);
    });

    test('设首尾归一化钳制（首 ≤ 尾）', () {
      editor().submit(SetVideoRange(start: forty, end: ten));
      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.rangeStart, forty);
      expect(timeline.rangeEnd, forty);
    });

    test('同值熟练度 EditNoop；重点切换 applied 且 geometryChanged 为假', () {
      editor().submit(SetSegmentMastery(order: 0, mastery: LearningMastery.mastered));
      final noop = editor()
          .submit(SetSegmentMastery(order: 0, mastery: LearningMastery.mastered));
      expect(noop.applied, isFalse);
      expect(history().length, 1);

      final toggle = editor().submit(ToggleSegmentEmphasis(order: 0));
      expect(toggle.applied, isTrue);
      expect(toggle.geometryChanged, isFalse);
    });
  });

  group('submit：几何 diff 清除（override 露出新语义）', () {
    void seedActive() {
      seedLines([thirty]);
      domain().toggleLearningSegment(1);
      expect(container.read(selectedLearningSegmentsProvider), {1});
    }

    test('行为修正点：切 flag 不清激活（几何未变）', () {
      seedActive();
      final outcome = editor().submit(ToggleSegmentFlag(index: 0));
      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse);
      expect(container.read(selectedLearningSegmentsProvider), {1});
    });

    test('行为修正点：纯属性编辑（熟练度/重点）不清激活', () {
      seedActive();
      editor().submit(SetSegmentMastery(order: 1, mastery: LearningMastery.mastered));
      expect(container.read(selectedLearningSegmentsProvider), {1});
      editor().submit(ToggleSegmentEmphasis(order: 1));
      expect(container.read(selectedLearningSegmentsProvider), {1});
    });

    test('几何变化（移线/加线/删线/区间收缩）才清激活', () {
      seedActive();
      editor().submit(MoveSegmentLine(index: 0, to: twenty));
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);

      seedActive();
      editor().submit(AddSegmentLine(at: forty));
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);

      seedActive();
      editor().submit(RemoveSegmentLine(index: 0));
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);

      seedActive();
      editor().submit(SetVideoRange(start: twenty));
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });

    test('几何变化才清临时衔接段；flag 切换不清', () {
      seedLines([thirty]);
      editor().toggleTransitionSegment(0);
      expect(container.read(transitionSegmentProvider), isNotNull);

      editor().submit(ToggleSegmentFlag(index: 0));
      expect(container.read(transitionSegmentProvider), isNotNull);

      editor().submit(MoveSegmentLine(index: 0, to: twenty));
      expect(container.read(transitionSegmentProvider), isNull);
    });
  });

  group('submit：选中维护', () {
    test('插线后线选中按位置同位重映射', () {
      seedLines([twenty]);
      domain().select(SegmentLineSelection(0));
      editor().submit(AddSegmentLine(at: ten));
      expect(container.read(selectedSegmentLineIndexProvider), 1);
    });

    test('删除分段线整体清选中', () {
      seedLines([ten]);
      domain().select(SegmentLineSelection(0));
      editor().submit(RemoveSegmentLine(index: 0));
      expect(container.read(annotationSelectionProvider), isNull);
    });
  });

  group('历史语义', () {
    test('新编辑清重做分支', () {
      seedLines([ten]);
      editor().submit(SetSegmentMastery(order: 0, mastery: LearningMastery.mastered));
      editor().undo();
      expect(history().canRedo, isTrue);
      editor().submit(ToggleSegmentEmphasis(order: 0));
      expect(history().canRedo, isFalse);
    });

    test('历史上限 50 条：第 51 条淘汰最旧', () {
      for (var i = 0; i < 51; i++) {
        editor().submit(
          SetSegmentMastery(
            order: 0,
            mastery: i.isEven
                ? LearningMastery.learning
                : LearningMastery.mastered,
          ),
        );
      }
      expect(history().length, 50);
    });

    test('undo/redo 清点选槽；非几何编辑不清学习段选中', () {
      seedLines([ten]);
      editor().submit(SetSegmentMastery(order: 0, mastery: LearningMastery.mastered));
      domain().toggleLearningSegment(0);
      domain().select(SegmentLineSelection(0));
      editor().undo();
      expect(container.read(annotationSelectionProvider), isNull);
      expect(container.read(selectedLearningSegmentRepresentativeProvider), 0);
      expect(container.read(selectedLearningSegmentsProvider), {0});
      editor().redo();
      expect(container.read(selectedLearningSegmentsProvider), {0});
    });

    test('undo/redo 无历史/无可重做 no-op（不清当前状态）', () {
      // 无历史：undo 不动状态也不清选中。
      domain().select(SegmentLineSelection(0));
      editor().undo();
      expect(container.read(annotationSelectionProvider), isNotNull);
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);

      // 撤销种子后 redo 生效一次；已在最新时再 redo = no-op 不清状态。
      seedLines([ten]);
      editor().undo();
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      editor().redo();
      expect(container.read(annotationTimelineProvider).segmentLines.length, 1);
      domain().toggleLearningSegment(0);
      editor().redo();
      expect(container.read(annotationTimelineProvider).segmentLines.length, 1);
      expect(container.read(selectedLearningSegmentRepresentativeProvider), 0);
    });

    test('撤销几何变化按同一规则清激活（回放清除不入史）', () {
      seedLines([thirty]);
      editor().submit(MoveSegmentLine(index: 0, to: twenty));
      domain().toggleLearningSegment(1);
      editor().undo();
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      editor().redo();
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });

    test('撤销纯属性变化不清激活', () {
      seedLines([thirty]);
      editor().submit(SetSegmentMastery(order: 1, mastery: LearningMastery.mastered));
      domain().toggleLearningSegment(1);
      editor().undo();
      expect(container.read(selectedLearningSegmentsProvider), {1});
    });
  });

  group('拖动会话', () {
    test('拖线：begin 选中目标；moveTo 返回钳制后真实落点；no-op 帧返回 null', () {
      seedLines([thirty]);
      final session = editor().beginLineDrag(0);
      expect(container.read(selectedSegmentLineIndexProvider), 0);

      expect(session.moveTo(forty), forty);
      expect(session.moveTo(total), isNull);
      expect(session.moveTo(Duration.zero), isNull);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        forty,
      );
      session.end();
    });

    test('拖线 end 幂等且整会话单步入史；无净变化不入史', () {
      seedLines([thirty]);
      final session = editor().beginLineDrag(0);
      session.moveTo(forty);
      session.end();
      session.end();
      expect(history().length, 2);
      editor().undo();
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        thirty,
      );

      final noopSession = editor().beginLineDrag(0);
      expect(noopSession.moveTo(thirty), isNull);
      noopSession.end();
      expect(history().length, 1);
    });

    test('会话中 submit 并入会话不单独入史', () {
      seedLines([thirty]);
      final session = editor().beginLineDrag(0);
      session.moveTo(forty);
      editor().submit(ToggleSegmentFlag(index: 0));
      session.end();
      expect(history().length, 2);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isTrue,
      );
      editor().undo();
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.flagged,
        isFalse,
      );
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        thirty,
      );
    });

    test('拖首尾：begin 选中端标；moveTo 返回钳制落点；end 单步入史', () {
      seedLines([thirty]);
      final start = editor().beginRangeDrag(VideoRangeBoundary.start);
      expect(container.read(selectedVideoRangeBoundaryProvider),
          VideoRangeBoundary.start,);
      expect(start.moveTo(twenty), twenty);
      start.end();

      final end = editor().beginRangeDrag(VideoRangeBoundary.end);
      expect(end.moveTo(forty), forty);
      end.end();

      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.rangeStart, twenty);
      expect(timeline.rangeEnd, forty);
      expect(history().length, 3);
      editor().undo();
      editor().undo();
      expect(container.read(annotationTimelineProvider).rangeEnd,
          container.read(annotationTimelineProvider).videoDuration,);
    });

    test('undo 遇悬挂会话防御性收口', () {
      seedLines([thirty]);
      final session = editor().beginLineDrag(0);
      session.moveTo(forty);
      editor().undo();
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        thirty,
      );
      // 悬挂会话已收口：后续 moveTo 为空操作。
      expect(session.moveTo(twenty), isNull);
      // 收口产生的会话记录随本次 undo 消费，剩种子记录仍可撤销。
      expect(history().canUndo, isTrue);
      editor().undo();
      expect(
        container.read(annotationTimelineProvider).segmentLines,
        isEmpty,
      );
    });
  });

  group('封闭会话组', () {
    test('激活与临时衔接段互斥经模块收口', () {
      seedLines([thirty]);
      editor().toggleTransitionSegment(0);
      expect(container.read(transitionSegmentProvider), isNotNull);

      domain().toggleLearningSegment(1);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), {1});

      editor().toggleTransitionSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(container.read(transitionSegmentProvider), isNotNull);
    });

    test('selectOnly 替换既有选中；clearSelection 整体清', () {
      seedLines([ten, thirty]);
      domain().toggleLearningSegment(0);
      domain().selectOnly(1);
      expect(container.read(selectedLearningSegmentsProvider), {1});

      domain().select(SegmentLineSelection(0));
      domain().clear();
      expect(container.read(annotationSelectionProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), {1});
    });

    test('toggleTransitionSegment 选中联动：激活选中该线、同线取消连带清选中', () {
      seedLines([ten, thirty]);
      editor().toggleTransitionSegment(0);
      expect(container.read(transitionSegmentProvider), isNotNull);
      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>().having((s) => s.index, 'index', 0),
      );

      // 异线替换：临时段与选中一起切到新线。
      editor().toggleTransitionSegment(1);
      expect(
        container.read(annotationSelectionProvider),
        isA<SegmentLineSelection>().having((s) => s.index, 'index', 1),
      );

      // 同线取消：临时段清，选中该线时连带清除。
      editor().toggleTransitionSegment(1);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(annotationSelectionProvider), isNull);
    });

    test('toggleTransitionSegment 无效线不激活也不改选中', () {
      seedLines([thirty]);
      domain().select(SegmentLineSelection(0));
      // 越界线索引 → 解析无效，不激活、不改选中。
      editor().toggleTransitionSegment(5);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(annotationSelectionProvider), isNotNull);
    });
  });

  group('一个状态：选中集合升格为主状态', () {
    test('选分段线/半拍线/端标不清学习段选中与循环', () {
      seedLines([ten, twenty, thirty]);
      domain().toggleLearningSegment(1);

      domain().toggle(SegmentLineSelection(0));
      expect(container.read(selectedLearningSegmentsProvider), {1});
      domain().toggle(HalfBeatLineSelection(0));
      expect(container.read(selectedLearningSegmentsProvider), {1});
      domain().toggle(VideoRangeBoundarySelection(VideoRangeBoundary.start));
      expect(container.read(selectedLearningSegmentsProvider), {1});

      // 循环范围照旧由选中集合派生。
      final range = container.read(selectedLearningSegmentRangeProvider);
      expect(range, isNotNull);
      expect(range!.start, ten);
      expect(range.end, twenty);
    });

    test('代表段序：多段选中取最低档所属段；并列取最小段序', () {
      seedLines([ten, twenty, thirty]);
      // 点选只产生单元素集合；多段选中由长按圈选产生，此处直接布置。
      container.read(selectedLearningSegmentsProvider.notifier).state = {
        0, 1, 2,
      };
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});
      // 全部未练：并列取最小段序。
      expect(container.read(selectedLearningSegmentRepresentativeProvider), 0);

      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );
      // 段 0 已掌握、其余未练：代表段换成最低档所属段。
      expect(container.read(selectedLearningSegmentRepresentativeProvider), 1);
    });
  });

  group('submit：段序键属性级联', () {
    test('拆线：前后两新段均继承原段熟练度与重点', () {
      seedLines([thirty]);
      editor().submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 1));

      editor().submit(AddSegmentLine(at: forty));

      expect(container.read(learningMasteryProvider), {
        1: LearningMastery.mastered,
        2: LearningMastery.mastered,
      });
      expect(container.read(learningEmphasisProvider), {1, 2});
    });

    test('删线融合：熟练度取较高者、重点取并集、段序前移', () {
      seedLines([twenty, forty]);
      editor().submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.learning),
      );
      editor().submit(
        SetSegmentMastery(order: 2, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 2));

      editor().submit(RemoveSegmentLine(index: 1));

      expect(container.read(learningMasteryProvider), {
        1: LearningMastery.mastered,
      });
      expect(container.read(learningEmphasisProvider), {1});
    });

    test('区间收缩裁线：段序键属性按映射 remap', () {
      seedLines([twenty, forty]);
      editor().submit(
        SetSegmentMastery(order: 1, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 1));

      editor().submit(SetVideoRange(start: thirty));

      expect(container.read(learningMasteryProvider), {
        0: LearningMastery.mastered,
      });
      expect(container.read(learningEmphasisProvider), {0});
    });
  });

  group('resetForVideo', () {
    test('全复位 + 清历史', () {
      seedLines([ten, thirty]);
      editor().submit(SetSegmentMastery(order: 1, mastery: LearningMastery.mastered));
      editor().submit(ToggleSegmentEmphasis(order: 1));
      domain().select(SegmentLineSelection(0));
      domain().toggleLearningSegment(1);
      expect(history().canUndo, isTrue);

      editor().resetForVideo(total);

      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.videoDuration, total);
      expect(timeline.rangeStart, Duration.zero);
      expect(timeline.rangeEnd, total);
      expect(timeline.segmentLines, isEmpty);
      expect(container.read(learningMasteryProvider), isEmpty);
      expect(container.read(learningEmphasisProvider), isEmpty);
      expect(container.read(annotationSelectionProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(history().canUndo, isFalse);
      expect(history().canRedo, isFalse);
    });
  });

  group('自动分段与清空分段', () {
    const gridStart = Duration(milliseconds: 500);
    const gridEnd = Duration(seconds: 20);

    test('AutoSegment：一次编辑内设首尾 + 整体替换分段线，一步撤销', () {
      seedLines([ten, twenty]);
      final historyBefore = history().length;

      final outcome = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));

      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isTrue);
      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.rangeStart, gridStart);
      expect(timeline.rangeEnd, gridEnd);
      expect(
        [for (final line in timeline.segmentLines) line.position],
        const [ten],
      );
      expect(history().length, historyBefore + 1, reason: '整动作一次入史');

      editor().undo();
      final restored = container.read(annotationTimelineProvider);
      expect(restored.rangeStart, Duration.zero);
      expect(restored.rangeEnd, total);
      expect(
        [for (final line in restored.segmentLines) line.position],
        const [ten, twenty],
      );
      editor().redo();
      expect(container.read(annotationTimelineProvider).rangeStart, gridStart);
    });

    test('AutoSegment：熟练度/重点按时间重叠重写，撤销与重做对称', () {
      seedLines([ten, twenty]);
      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 2));
      final masteryBefore = container.read(learningMasteryProvider);
      final emphasisBefore = container.read(learningEmphasisProvider);

      editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));

      // 旧分区 [0,10)/[10,20)/[20,60) → 新分区 [0.5,10)/[10,20)。
      // 新段 0 与旧段 0 相交 → 继承「掌握」；旧段 2 落在新尾之外 → 丢弃。
      expect(container.read(learningMasteryProvider), const {
        0: LearningMastery.mastered,
      });
      expect(container.read(learningEmphasisProvider), isEmpty);

      editor().undo();
      expect(container.read(learningMasteryProvider), masteryBefore);
      expect(container.read(learningEmphasisProvider), emphasisBefore);

      editor().redo();
      expect(container.read(learningMasteryProvider), const {
        0: LearningMastery.mastered,
      });
      expect(container.read(learningEmphasisProvider), isEmpty);
    });

    test('AutoSegment：新分区为空时逐段数据整体清空，撤销还原', () {
      seedLines([ten, twenty]);
      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 1));
      final masteryBefore = container.read(learningMasteryProvider);
      final emphasisBefore = container.read(learningEmphasisProvider);

      final outcome = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [],
      ));

      expect(outcome.applied, isTrue);
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(container.read(learningMasteryProvider), isEmpty);
      expect(container.read(learningEmphasisProvider), isEmpty);

      editor().undo();
      expect(container.read(learningMasteryProvider), masteryBefore);
      expect(container.read(learningEmphasisProvider), emphasisBefore);
    });

    test('AutoSegment：无净变化 EditNoop 不入史', () {
      editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));
      final historyAfterFirst = history().length;

      final outcome = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));
      expect(outcome.applied, isFalse);
      expect(history().length, historyAfterFirst);
    });

    test('AutoSegment：同档位重复应用且属性非空时仍无净变化、不入史', () {
      seedLines([ten, twenty]);
      editor().submit(
        SetSegmentMastery(order: 0, mastery: LearningMastery.mastered),
      );
      editor().submit(ToggleSegmentEmphasis(order: 1));
      editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));
      final masteryAfterFirst = container.read(learningMasteryProvider);
      final emphasisAfterFirst = container.read(learningEmphasisProvider);
      final historyAfterFirst = history().length;

      final outcome = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));

      expect(outcome.applied, isFalse);
      expect(container.read(learningMasteryProvider), masteryAfterFirst);
      expect(container.read(learningEmphasisProvider), emphasisAfterFirst);
      expect(history().length, historyAfterFirst);
    });

    test('清空分段：删全部分段线、保留首尾与半拍线，一步撤销', () {
      seedLines([ten, twenty]);
      editor().submit(AddHalfBeatLine(at: const Duration(seconds: 15)));
      final rangeBefore = container.read(annotationTimelineProvider);

      final outcome = editor().submit(const ClearSegmentLines());

      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isTrue);
      final timeline = container.read(annotationTimelineProvider);
      expect(timeline.segmentLines, isEmpty);
      expect(timeline.rangeStart, rangeBefore.rangeStart);
      expect(timeline.rangeEnd, rangeBefore.rangeEnd);
      expect(timeline.halfBeatLines.length, 1, reason: '半拍线保留');

      editor().undo();
      final restored = container.read(annotationTimelineProvider);
      expect(restored.segmentLines.length, 2);
      expect(restored.halfBeatLines.length, 1);
    });

    test('清空分段：无分段线时 EditNoop 不入史', () {
      final outcome = editor().submit(const ClearSegmentLines());
      expect(outcome.applied, isFalse);
      expect(history().canUndo, isFalse);
    });

    test('AutoSegment：旧线 flag 迁到最近新刀，撤销/重做按快照还原线 flag', () {
      seedLines([const Duration(seconds: 9), const Duration(seconds: 11)]);
      editor().submit(const ToggleSegmentFlag(index: 0));
      final before = container.read(annotationTimelineProvider);
      expect(
        before.segmentLines.map((l) => l.flagged),
        [true, false],
        reason: '播种：9s 置位、11s 未置位',
      );
      final historyBefore = history().length;

      final outcome = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));

      expect(outcome.applied, isTrue);
      expect(history().length, historyBefore + 1, reason: '整动作一次入史');
      var timeline = container.read(annotationTimelineProvider);
      expect(timeline.segmentLines.single.position, ten);
      expect(timeline.segmentLines.single.flagged, isTrue, reason: '9s 的 flag 迁到 10s');

      editor().undo();
      timeline = container.read(annotationTimelineProvider);
      expect(timeline.segmentLines.map((l) => l.position), [
        const Duration(seconds: 9),
        const Duration(seconds: 11),
      ]);
      expect(timeline.segmentLines.map((l) => l.flagged), [true, false]);

      editor().redo();
      timeline = container.read(annotationTimelineProvider);
      expect(timeline.segmentLines.single.position, ten);
      expect(timeline.segmentLines.single.flagged, isTrue);
    });

    test('清空分段不迁移 flag：线上一律无 flag，撤销还原旧线 flag', () {
      seedLines([ten]);
      editor().submit(const ToggleSegmentFlag(index: 0));
      final before = container.read(annotationTimelineProvider);
      expect(before.segmentLines.single.flagged, isTrue);

      final outcome = editor().submit(const ClearSegmentLines());
      expect(outcome.applied, isTrue);
      final cleared = container.read(annotationTimelineProvider);
      expect(cleared.segmentLines, isEmpty, reason: '没有可落的刀，线上一律无 flag');

      editor().undo();
      expect(container.read(annotationTimelineProvider), before, reason: '撤销还原旧线及其 flag');
    });

    test('AutoSegment：迁移出 flag 后同档位重复应用仍 EditNoop 不入史', () {
      seedLines([const Duration(seconds: 9)]);
      editor().submit(const ToggleSegmentFlag(index: 0));

      final first = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));
      expect(first.applied, isTrue);
      final historyAfterFirst = history().length;

      final repeat = editor().submit(AutoSegment(
        start: gridStart,
        end: gridEnd,
        cuts: const [ten],
      ));
      expect(repeat.applied, isFalse);
      expect(history().length, historyAfterFirst);
    });
  });

  group('有效标注时间线派生', () {
    test('时间线已初始化（videoDuration>0）时原样透出，不兜底', () {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);

      container
          .read(annotationEditorProvider)
          .resetForVideo(const Duration(seconds: 30));

      final effective = container.read(effectiveAnnotationTimelineProvider);
      expect(effective.videoDuration, const Duration(seconds: 30));
      expect(effective.rangeEnd, const Duration(seconds: 30));
      expect(effective, container.read(annotationTimelineProvider));
    });

    test('时间线未初始化（videoDuration≤0）时以引擎整片时长兜底', () {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);

      // 模拟宿主尚未按视频时长初始化：时间线仍为零时长占位。
      container.read(annotationEditorProvider).resetForVideo(Duration.zero);

      final effective = container.read(effectiveAnnotationTimelineProvider);
      // 兜底 = 以整片时长构造的全片区间（与其他 seek 路径同一判定基准）。
      expect(
        effective,
        AnnotationTimeline.wholeVideo(const Duration(minutes: 3)),
      );
    });
  });

  group('按下即选与接管回滚', () {
    /// 三段：0=[0,10) 1=[10,20) 2=[20,60)。
    void seedThreeSegments() => seedLines([ten, twenty]);

    /// 选中写是否「静默就位」（按下写/回滚写为真，激活语义写为假）。
    bool lastWriteSilent() => container
        .read(selectedLearningSegmentsProvider.notifier)
        .lastWriteSilent;

    test('按下未选中的段：当帧清空原选中、只选中这一段，循环范围随之就位', () {
      seedThreeSegments();
      domain().toggleLearningSegment(0);
      domain().press(1);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      final range = container.read(selectedLearningSegmentRangeProvider);
      expect(range, isNotNull);
      expect(range!.start, ten);
      expect(range.end, twenty);
      // 静默写：只就位作用域，播放接线不 seek、不起播。
      expect(lastWriteSilent(), isTrue);
      expect(engine.seekCalls, isEmpty);
      expect(engine.callLog, isEmpty);
    });

    test('按下写过抬手：选中维持、激活语义恢复（跳段首起播由派生链接管）', () {
      seedThreeSegments();
      domain().press(1);
      domain().liftPress(1);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      expect(lastWriteSilent(), isFalse);
    });

    test('按下已选中的段：按下期间选中不变；抬手清空、循环关掉', () {
      seedThreeSegments();
      domain().toggleLearningSegment(1);
      domain().press(1);
      expect(container.read(selectedLearningSegmentsProvider), const {1});
      domain().liftPress(1);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(container.read(selectedLearningSegmentRangeProvider), isNull);
    });

    test('按下落在多段选中范围里：按下期间整片不变；抬手整片清空', () {
      seedThreeSegments();
      domain().press(0);
      domain().liftPress(0);
      domain().press(2);
      domain().liftPress(2);
      domain().beginDragSelect(0);
      domain().spanTo(2);
      domain().commitDragSelect();
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});

      domain().press(1);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});
      domain().liftPress(1);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
    });

    test('按下落的选中被接管（系统打断）：静默回滚到按下前的选中与循环', () {
      seedThreeSegments();
      domain().toggleLearningSegment(0);
      domain().press(2);
      expect(container.read(selectedLearningSegmentsProvider), const {2});
      domain().cancelPress();
      expect(container.read(selectedLearningSegmentsProvider), const {0});
      expect(lastWriteSilent(), isTrue);
    });

    test('横向快滑起手接管：会话无回滚了结，快滑自己的只选中照常落地', () {
      seedThreeSegments();
      domain().toggleLearningSegment(0);
      domain().press(2);
      domain().consumePress();
      domain().selectOnly(2);
      expect(container.read(selectedLearningSegmentsProvider), const {2});
      expect(lastWriteSilent(), isFalse);
    });

    test('长按圈选起手接管：回滚基线继承按下前——取消回滚到按下前', () {
      seedThreeSegments();
      domain().toggleLearningSegment(0);
      domain().press(2);
      domain().beginDragSelect(2);
      domain().spanTo(0);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});
      domain().cancelDragSelect();
      expect(container.read(selectedLearningSegmentsProvider), const {0});
    });

    test('已选中段起手长按：不被提前清空，取消同样回滚到按下前', () {
      seedThreeSegments();
      domain().press(0);
      domain().liftPress(0);
      domain().press(2);
      domain().liftPress(2);
      domain().beginDragSelect(0);
      domain().spanTo(2);
      domain().commitDragSelect();
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});

      // 从已选中的段 1 起手长按：按下按兵不动，圈选取消回到整片。
      domain().press(1);
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});
      domain().beginDragSelect(1);
      domain().cancelDragSelect();
      expect(container.read(selectedLearningSegmentsProvider), {0, 1, 2});
    });

    test('抬手命中的段不是按下段：按下会话一并了结，不残留陈旧快照', () {
      seedThreeSegments();
      domain().toggleLearningSegment(0);
      domain().press(1);
      // 抬手命中另一段（越段界/经线层窗口路径）：toggle 兜底 + 会话了结。
      domain().liftPress(2);
      expect(container.read(selectedLearningSegmentsProvider), const {2});
      // 陈旧快照不得在后续 tapCancel 时误回滚。
      domain().cancelPress();
      expect(container.read(selectedLearningSegmentsProvider), const {2});
    });
  });
}
