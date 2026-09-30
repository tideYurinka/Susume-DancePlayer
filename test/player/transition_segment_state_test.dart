import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        activeLoopRangeProvider,
        annotationEditorProvider,
        annotationTimelineProvider,
        transitionSegmentProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 临时衔接段独立会话态（状态 seam）：
/// 激活/再点取消/异线替换、与真实学习段激活互斥、几何变化清除、
/// seek 越出清除、单一循环范围派生。占位 120bpm：1 八拍 = 4s、四拍格 2s。
/// 带锚用例注入与占位网格逐位一致的就绪态样例（`uniformReadyBeatState`，
/// 60s 覆盖）以便锚点落盘。
///
/// 时间线播种改走标注编辑模块命令（store
/// 写缝已同 library 私有）；几何清除改由模块显式几何 diff 触发——
/// 行为修正点：flag 切换与纯属性编辑不再清激活/临时段，只有
/// 几何变化（加/删/移线、区间调整、撤销回放）才清（清除语义用例见
/// `annotation_editor_test.dart`，此处保留状态面回归）。
void main() {
  late ProviderContainer container;
  late FakePlaybackEngine engine;

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 60));
    container = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
    // 经模块命令播种三条分段线：10s / 20s / 30s。
    final editor = container.read(annotationEditorProvider);
    for (final position in const [
      Duration(seconds: 10),
      Duration(seconds: 20),
      Duration(seconds: 30),
    ]) {
      editor.submit(AddSegmentLine(at: position));
    }
  });

  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

  TransitionSegment? activate(int lineIndex) {
    container.read(annotationEditorProvider).toggleTransitionSegment(lineIndex);
    return container.read(transitionSegmentProvider);
  }

  group('临时衔接段状态', () {
    test('点击线激活 ±1 八拍范围（网格取整）；再点同线取消', () {
      expect(activate(1), isNotNull);
      var segment = container.read(transitionSegmentProvider)!;
      // 线 20s → [16, 24]。
      expect(segment.start, const Duration(seconds: 16));
      expect(segment.end, const Duration(seconds: 24));

      // 再点同线 → 取消（null）。
      activate(1);
      expect(container.read(transitionSegmentProvider), isNull);
    });

    test('点其它线替换（不叠加）', () {
      activate(0);
      activate(2);
      final segment = container.read(transitionSegmentProvider)!;
      expect(segment.lineIndex, 2);
      // 线 30s → 理论起点 26s 取整到八拍点（24/28 等距取靠后）= 28s →
      // [28, 34]。
      expect(segment.start, const Duration(seconds: 28));
      expect(segment.end, const Duration(seconds: 34));
    });

    test('落八拍锚点后激活：起点落重定相后的八拍点', () {
      // 注入就绪网格（与占位逐位一致）并落锚：请求位置 2s → 最近强拍
      // 拍序号 4（2s）。
      container
          .read(beatTrackStateProvider.notifier)
          .replace(uniformReadyBeatState(seconds: 60));
      final outcome = container
          .read(annotationEditorProvider)
          .submit(const AddEightBeatAnchor(at: Duration(seconds: 2)));
      expect(outcome.applied, isTrue);

      activate(1);
      final segment = container.read(transitionSegmentProvider)!;
      // 锚点 4（2s）后八拍点 = 2/6/10/14/18s…；线 20s → 理论起点 16s →
      // 14s 与 18s 等距取靠后 = 18s（无锚为 16s）；终点不取整 = 24s。
      expect(segment.start, const Duration(seconds: 18));
      expect(segment.end, const Duration(seconds: 24));
    });

    test('线索引无效时不激活（保持原状）', () {
      expect(activate(9), isNull);
    });

    test('与真实学习段激活互斥：激活临时段清除真实段、激活真实段清除临时段', () {
      // 先激活真实段 0。
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), const {0});

      // 激活临时段 → 真实段激活被清除。
      activate(1);
      expect(container.read(selectedLearningSegmentsProvider), isEmpty);
      expect(container.read(transitionSegmentProvider), isNotNull);

      // 再激活真实段 → 临时段被清除。
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(2);
      expect(container.read(transitionSegmentProvider), isNull);
      expect(container.read(selectedLearningSegmentsProvider), const {2});
    });

    test('几何变化（移线经模块命令）清除临时段', () {
      activate(1);
      expect(container.read(transitionSegmentProvider), isNotNull);

      // 模块提交几何变化（拖线 20s → 21s）→ 显式几何 diff 命中 → 清除。
      // 行为修正口径：几何变化才清；flag/属性编辑不清，不再「任何时间线
      // 替换=几何」。
      final outcome = container
          .read(annotationEditorProvider)
          .submit(MoveSegmentLine(index: 1, to: const Duration(seconds: 21)));
      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isTrue);
      expect(container.read(transitionSegmentProvider), isNull);
    });

    test('seek 越出临时段范围时清除；段内 seek 不清除', () {
      activate(1); // [16, 24]
      container
          .read(transitionSegmentProvider.notifier)
          .clearIfOutside(timeline(), const Duration(seconds: 25));
      expect(container.read(transitionSegmentProvider), isNull);

      activate(1);
      container
          .read(transitionSegmentProvider.notifier)
          .clearIfOutside(timeline(), const Duration(seconds: 16));
      expect(container.read(transitionSegmentProvider), isNotNull);
    });
  });

  group('单一循环范围（activeLoopRangeProvider）', () {
    test('临时段激活时优先于真实段合并范围；双双无激活为 null', () {
      expect(container.read(activeLoopRangeProvider), isNull);

      activate(1); // [16, 24]
      final range = container.read(activeLoopRangeProvider)!;
      expect(range.start, const Duration(seconds: 16));
      expect(range.end, const Duration(seconds: 24));

      // 取消临时段 → 回落为 null（真实段已被互斥清除）。
      activate(1);
      expect(container.read(activeLoopRangeProvider), isNull);

      // 真实段激活路径仍走合并范围。
      container
          .read(annotationSelectionDomainProvider)
          .toggleLearningSegment(0);
      final real = container.read(activeLoopRangeProvider)!;
      expect(real.start, Duration.zero);
      expect(real.end, const Duration(seconds: 10));
    });
  });
}
