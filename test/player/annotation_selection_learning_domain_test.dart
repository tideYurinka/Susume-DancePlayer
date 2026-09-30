import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/annotation/segment_selection.dart';
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/annotation_selection_domain_harness.dart';

/// 选中域——学习段会话半边直测。
///
/// 缝 = 域对象公开接口 + 域状态 provider：裸容器只挂域的状态 provider，注入
/// 假时间线、假只读门与记录器写入端口，不 pump widget、不经 `AnnotationEditor`。
/// 只钉域交出的外部可观察事实：两条会话的逐帧语义、四条非用户路径口的落盘
/// 口径、写入端口两个钩子的触发面、只读门五入口。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late AnnotationSelectionDomain domain;

  late List<String> hooks;
  late List<Set<int>> persisted;
  late AnnotationTimeline currentTimeline;
  var readonly = false;

  /// 两条分段线 → 三个学习段：[0,10s]／[10,20s]／[20,60s]。
  AnnotationTimeline timelineWithLines(List<int> seconds) =>
      AnnotationTimeline.normalized(
        videoDuration: total,
        segmentLines: [
          for (final second in seconds)
            SegmentLine(position: Duration(seconds: second)),
        ],
      );

  void buildDomain({AnnotationTimeline? timeline}) {
    currentTimeline = timeline ?? timelineWithLines(const [10, 20]);
    domain = buildAnnotationSelectionDomain(
      container: container,
      timeline: () => currentTimeline,
      memberSchemeReadonly: () => readonly,
      beforeUserWrite: () => hooks.add('before'),
      persistSelection: (selection) => persisted.add(Set.of(selection)),
    );
  }

  Set<int> selected() => container.read(selectedLearningSegmentsProvider);

  LearningSegmentRange? loopRange() =>
      selectedLearningSegmentRange(currentTimeline, selected());

  setUp(() {
    container = ProviderContainer();
    hooks = [];
    persisted = [];
    readonly = false;
    buildDomain();
  });

  tearDown(() => container.dispose());

  group('用户路径：点击 toggle 与只选中', () {
    test('toggle：点中未选中段 = 单元素集合；再点 = 清空；异段 = 替换', () {
      domain.toggleLearningSegment(0);
      expect(selected(), const {0});
      expect(loopRange()!.start, Duration.zero);
      expect(loopRange()!.end, const Duration(seconds: 10));

      domain.toggleLearningSegment(0);
      expect(selected(), isEmpty);
      expect(loopRange(), isNull);

      domain.toggleLearningSegment(0);
      domain.toggleLearningSegment(2);
      expect(selected(), const {2});
      expect(loopRange()!.start, const Duration(seconds: 20));
      expect(loopRange()!.end, total);
    });

    test('selectOnly 替换既有选中；越界段序忽略（零行为）', () {
      domain.toggleLearningSegment(0);
      domain.selectOnly(2);
      expect(selected(), const {2});

      hooks.clear();
      persisted.clear();
      domain.selectOnly(9);
      expect(selected(), const {2});
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
      domain.selectOnly(-1);
      expect(selected(), const {2});
    });
  });

  group('用户路径：按下四步', () {
    test('按下落在未选中段 = 静默只选中这一段，循环范围随之就位', () {
      expect(domain.press(1), isTrue);
      expect(selected(), const {1});
      expect(domain.lastWriteSilent, isTrue);
      expect(loopRange()!.start, const Duration(seconds: 10));
      expect(loopRange()!.end, const Duration(seconds: 20));
    });

    test('按下落在已选中段 = 按兵不动；抬手才清空（toggle）', () {
      domain.toggleLearningSegment(1);
      hooks.clear();
      persisted.clear();

      expect(domain.press(1), isTrue);
      expect(selected(), const {1}, reason: '按下对已选中段零写');
      expect(hooks, isEmpty, reason: '按兵不动不触发钩子');
      expect(persisted, isEmpty);

      domain.liftPress(1);
      expect(selected(), isEmpty, reason: '抬手 toggle 清空');
      expect(domain.lastWriteSilent, isFalse);
    });

    test('按下写过 → 抬手维持选中、静默标志复位、不落盘', () {
      domain.press(1);
      hooks.clear();
      persisted.clear();

      domain.liftPress(1);

      expect(selected(), const {1});
      expect(domain.lastWriteSilent, isFalse);
      expect(hooks, isEmpty, reason: '只重发选中事实，两个钩子都不触发');
      expect(persisted, isEmpty);
    });

    test('按下越界段序：未落地、不建会话、零写', () {
      expect(domain.press(9), isFalse);
      expect(domain.press(-1), isFalse);
      expect(selected(), isEmpty);
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
    });

    test('被接管回滚：pressCancel 回到按下前选中与循环', () {
      domain.toggleLearningSegment(0);
      expect(selected(), const {0});

      domain.press(1);
      expect(selected(), const {1}, reason: '按下落在未选中段即刻静默只选中它');
      domain.cancelPress();

      expect(selected(), const {0}, reason: '整片回滚到按下前');
      expect(domain.lastWriteSilent, isTrue, reason: '回滚是静默写');
      expect(loopRange()!.start, Duration.zero);
      expect(loopRange()!.end, const Duration(seconds: 10));
    });

    test('无回滚了结：pressConsume 后抬手按普通 toggle 兜底，不回滚', () {
      domain.beginDragSelect(0);
      domain.spanTo(2);
      domain.commitDragSelect();

      domain.press(1);
      domain.consumePress();
      domain.liftPress(1);

      expect(selected(), isEmpty, reason: '会话已了结，抬手 toggle 掉当前选中');
    });

    test('抬手命中的段不是按下段：按下会话了结并按普通 toggle 兜底', () {
      domain.press(1);
      domain.liftPress(2);
      expect(selected(), const {2});
    });
  });

  group('用户路径：圈选四步', () {
    test('起手：越界段序不成立；成立即清空并以落点段为起点（静默）', () {
      expect(domain.beginDragSelect(9), isFalse);
      expect(domain.beginDragSelect(-1), isFalse);

      expect(domain.beginDragSelect(2), isTrue);
      expect(selected(), const {2});
      expect(domain.lastWriteSilent, isTrue);
    });

    test('横拖区间连续：首末段钳住、越界段序保持上一帧', () {
      domain.beginDragSelect(2);
      domain.spanTo(0);
      expect(selected(), const {0, 1, 2}, reason: '起点 2 与手指 0 之间的全部段');
      expect(domain.lastWriteSilent, isTrue, reason: '拖动帧是静默写');

      domain.spanTo(1);
      expect(selected(), const {1, 2});

      // 手指未落进任何段（线窗/轨外）保持上一帧区间。
      domain.spanTo(9);
      expect(selected(), const {1, 2});
      domain.spanTo(-1);
      expect(selected(), const {1, 2});
    });

    test('松手提交：静默标志复位、选中维持；无会话时零行为', () {
      domain.beginDragSelect(0);
      domain.spanTo(1);
      domain.commitDragSelect();

      expect(selected(), const {0, 1});
      expect(domain.lastWriteSilent, isFalse);

      hooks.clear();
      persisted.clear();
      domain.commitDragSelect();
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
    });

    test('取消回滚到拖动前选中与循环（静默）', () {
      domain.toggleLearningSegment(0);
      domain.beginDragSelect(2);
      expect(selected(), const {2});

      domain.cancelDragSelect();
      expect(selected(), const {0});
      expect(domain.lastWriteSilent, isTrue);
    });
  });

  group('非用户路径四口', () {
    test('清（保存清）：落盘一次、清空、不走写前钩子', () {
      domain.toggleLearningSegment(0);
      hooks.clear();
      persisted.clear();

      domain.clearLearningSegments();

      expect(selected(), isEmpty);
      expect(hooks, isEmpty, reason: '整体清不触发写前钩子');
      expect(persisted, [<int>{}]);
    });

    test('复位（非保存清）：清空且两个钩子都不触发', () {
      domain.toggleLearningSegment(0);
      hooks.clear();
      persisted.clear();

      domain.resetLearningSegments();

      expect(selected(), isEmpty);
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
      expect(domain.lastWriteSilent, isFalse);
    });

    test('恢复装载：两钩子都不触发；静默标志只在写回非空集合时置真', () {
      domain.restoreLearningSegments(const {1, 2});
      expect(selected(), const {1, 2});
      expect(domain.lastWriteSilent, isTrue);
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);

      domain.restoreLearningSegments(const {});
      expect(selected(), isEmpty);
      expect(domain.lastWriteSilent, isFalse, reason: '空写回不置静默标志');
    });

    test('seek 越出清除：越出才清并落盘；界内与时长未知零行为', () {
      domain.toggleLearningSegment(0);
      hooks.clear();
      persisted.clear();

      domain.clearLearningSegmentsIfOutside(const Duration(seconds: 5));
      expect(selected(), const {0}, reason: '界内不清');
      expect(persisted, isEmpty);

      domain.clearLearningSegmentsIfOutside(const Duration(seconds: 30));
      expect(selected(), isEmpty);
      expect(persisted, [<int>{}], reason: '越出即清并落盘');

      // 时长未知（占位时间线）不判越出。
      buildDomain(timeline: AnnotationTimeline.wholeVideo(Duration.zero));
      domain.restoreLearningSegments(const {0});
      hooks.clear();
      persisted.clear();
      domain.clearLearningSegmentsIfOutside(const Duration(seconds: 30));
      expect(selected(), const {0});
      expect(persisted, isEmpty);
    });
  });

  group('只读门：写点入口判、回滚了结不判', () {
    test('只读时五个写点入口静默拒绝：状态不变、钩子不触发、按下/起手返回未落地', () {
      readonly = true;

      domain.toggleLearningSegment(0);
      domain.selectOnly(1);
      expect(domain.press(0), isFalse);
      domain.liftPress(0);
      expect(domain.beginDragSelect(0), isFalse);

      expect(selected(), isEmpty);
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
    });

    test('回滚／了结类入口不经只读门（与写点门刻意不对称）', () {
      domain.toggleLearningSegment(2);
      domain.press(0);
      expect(selected(), const {0});
      readonly = true;

      domain.cancelPress();
      expect(selected(), const {2}, reason: '回滚不被只读门拦');
      expect(domain.lastWriteSilent, isTrue);

      readonly = false;
      domain.beginDragSelect(0);
      domain.spanTo(1);
      readonly = true;
      domain.spanTo(2);
      expect(selected(), const {0, 1, 2}, reason: '逐帧不被只读门拦');

      domain.cancelDragSelect();
      expect(selected(), const {2}, reason: '取消回滚到起手前选中，不被只读门拦');
    });
  });

  group('写入端口两个钩子的触发面', () {
    test('用户路径写 = 写前一次 + 写后一次（带绝对终值）', () {
      domain.toggleLearningSegment(1);
      expect(hooks, ['before']);
      expect(persisted, [
        {1},
      ]);
    });

    test('用户路径写无净变化 = 写前一次、写后零次', () {
      domain.selectOnly(1);
      hooks.clear();
      persisted.clear();

      domain.selectOnly(1);

      expect(hooks, ['before']);
      expect(persisted, isEmpty, reason: '无净变化不落盘');
    });

    test('圈选逐帧与回滚写只走写后、无净变化不触发', () {
      domain.beginDragSelect(0);
      hooks.clear();
      persisted.clear();

      domain.spanTo(1);
      expect(hooks, isEmpty);
      expect(persisted, [
        {0, 1},
      ]);

      domain.spanTo(1); // 同区间：净变化判定拦下
      expect(persisted.length, 1);

      domain.cancelDragSelect();
      expect(hooks, isEmpty);
      expect(persisted.last, isEmpty);
    });

    test('圈选提交与按下抬手（已写过那条）两个钩子都不触发', () {
      domain.beginDragSelect(0);
      domain.spanTo(1);
      hooks.clear();
      persisted.clear();
      domain.commitDragSelect();
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);

      domain.press(2);
      hooks.clear();
      persisted.clear();
      domain.liftPress(2);
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
    });

    test('复位与恢复装载两个钩子都不触发', () {
      domain.toggleLearningSegment(0);
      hooks.clear();
      persisted.clear();

      domain.resetLearningSegments();
      domain.restoreLearningSegments(const {1});
      expect(hooks, isEmpty);
      expect(persisted, isEmpty);
    });
  });
}
