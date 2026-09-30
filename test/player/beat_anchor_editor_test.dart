import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackState,
        appliedEightBeatAnchors,
        beatPhaseProvider,
        beatTrackStateProvider,
        writeAppliedBeatShift,
        writeEightBeatAnchors;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        layoutLockedProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/notice.dart' show NoticeId, noticeTriggerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';

import '../helpers/fake_playback_engine.dart';

/// 八拍锚点落锚 verb：
/// 落锚 = 一次标注编辑（单步可撤销、净变化折叠、锁定分段门禁、落点解析在
/// 模块内），且写定后相位源当帧重定相。

/// 记录型保存 sink（收口 seam 两消费者对拍用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

Duration ms(int v) => Duration(milliseconds: v);

/// 就绪真实网格：72 拍、每 0.5s 一拍、强拍每 4 拍（强拍序号 0/4/8…）。
marker_doc.BeatGrid readyGrid({int beats = 72}) => marker_doc.BeatGrid(
  model: 'fake.onnx',
  fps: 100,
  generatedAt: DateTime.utc(2024),
  beats: [
    for (var i = 0; i < beats; i++)
      marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
  ],
);

void main() {
  late ProviderContainer container;
  late RecordingSaveSink sink;

  setUp(() {
    sink = RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: const Duration(minutes: 2)),
        ),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() => container.dispose());

  final refOf = Provider<Ref>((ref) => ref);
  AnnotationEditor editor() => container.read(annotationEditorProvider);
  AnnotationSelectionDomain domain() =>
      container.read(annotationSelectionDomainProvider);
  Ref ref() => container.read(refOf);
  List<int> anchors() => appliedEightBeatAnchors(ref());
  void useReadyGrid({marker_doc.BeatGrid? grid}) => container
      .read(beatTrackStateProvider.notifier)
      .replace(BeatTrackState.ready(grid ?? readyGrid()));

  group('落锚 verb（AddEightBeatAnchor）', () {
    test('落锚 = 一次标注编辑：写定锚点 + 单步入史 + 保存 diff + 不动几何', () {
      useReadyGrid();

      final outcome = editor().submit(AddEightBeatAnchor(at: ms(13500)));

      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse, reason: '锚点不改任何线的几何');
      expect(anchors(), [28], reason: '13.5s 就近强拍 = 14s（第 8 个强拍）');
      expect(container.read(annotationEditHistoryProvider).length, 1);
      expect(sink.saved.single.corrections?.eightBeatAnchors, [28]);
      expect(sink.saved.single.annotations, isNull, reason: '仅 corrections 段变化');
    });

    test('落点解析在模块内：裸时间（非强拍）也被解析到最近强拍', () {
      useReadyGrid();

      editor().submit(AddEightBeatAnchor(at: ms(12500)));

      expect(anchors(), [24], reason: '12.5s 就近强拍 = 12s');
      expect(container.read(beatPhaseProvider).isEightBeatPoint(24), isTrue);
    });

    test('多锚点并存：升序去重、各自管其后一段', () {
      useReadyGrid();

      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(AddEightBeatAnchor(at: ms(20000)));
      editor().submit(AddEightBeatAnchor(at: ms(14000)));

      expect(anchors(), [28, 40], reason: '重复提交同一锚点不产生新项');
      final phase = container.read(beatPhaseProvider);
      expect(phase.isEightBeatPoint(28), isTrue);
      expect(phase.isEightBeatPoint(36), isTrue, reason: '第一段自锚点 28 重定相');
      expect(phase.isEightBeatPoint(40), isTrue, reason: '锚点自身即八拍点');
      expect(phase.isEightBeatPoint(44), isFalse, reason: '第二段自锚点 40 重定相');
      expect(phase.isEightBeatPoint(48), isTrue);
    });

    test('净变化折叠正确：重复提交同一集合不产生历史与写盘', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      final lengthBefore = container.read(annotationEditHistoryProvider).length;
      sink.saved.clear();

      final outcome = editor().submit(AddEightBeatAnchor(at: ms(14100)));

      expect(outcome, isA<EditNoop>());
      expect(anchors(), [28]);
      expect(container.read(annotationEditHistoryProvider).length, lengthBefore);
      expect(sink.saved, isEmpty);
    });

    test('单步撤销：回退该次落锚（锚点与相位一起回退）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      sink.saved.clear();

      editor().undo();

      expect(anchors(), isEmpty);
      expect(container.read(annotationEditHistoryProvider).canUndo, isFalse);
      expect(sink.saved.single.corrections?.eightBeatAnchors, isEmpty);
      expect(container.read(beatPhaseProvider).isEightBeatPoint(28), isFalse);

      editor().redo();
      expect(anchors(), [28]);
    });

    test('锚点变更不改几何、不清激活段与临时段', () {
      useReadyGrid();
      final timeline = container.read(annotationTimelineProvider);
      editor().submit(AddSegmentLine(at: ms(20000)));
      domain().toggleLearningSegment(0);
      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);

      editor().submit(AddEightBeatAnchor(at: ms(14000)));

      expect(container.read(selectedLearningSegmentsProvider), isNotEmpty);
      expect(
        container.read(annotationTimelineProvider).segmentLines.length,
        timeline.segmentLines.length + 1,
      );
    });

    test('锁定分段：落锚照常（锁只护分段结构，不弹提示）', () {
      useReadyGrid();
      final promptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      container.read(layoutLockedProvider.notifier).replace(true);

      final outcome = editor().submit(AddEightBeatAnchor(at: ms(14000)));

      expect(outcome.applied, isTrue);
      expect(anchors(), [28]);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore);
    });

    test('非就绪网格（占位/异常）无落点：静默 EditNoop 不写不入史', () {
      // 默认占位态。
      expect(editor().submit(AddEightBeatAnchor(at: ms(14000))), isA<EditNoop>());
      expect(anchors(), isEmpty);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(sink.saved, isEmpty);

      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      expect(editor().submit(AddEightBeatAnchor(at: ms(14000))), isA<EditNoop>());
      expect(anchors(), isEmpty);
    });

    test('网格无强拍（识别退化）：无落点、EditNoop', () {
      useReadyGrid(
        grid: marker_doc.BeatGrid(
          model: 'fake.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2024),
          beats: [
            for (var i = 0; i < 16; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: false),
          ],
        ),
      );

      expect(editor().submit(AddEightBeatAnchor(at: ms(2000))), isA<EditNoop>());
      expect(anchors(), isEmpty);
    });
  });

  group('删除锚点 verb（RemoveEightBeatAnchor）', () {
    test('删除 = 一次标注编辑：写定集合 + 单步入史 + 保存 diff + 不动几何', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(AddEightBeatAnchor(at: ms(20000)));
      sink.saved.clear();
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;

      final outcome = editor().submit(RemoveEightBeatAnchor(at: ms(14100)));

      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse, reason: '锚点不改任何线的几何');
      expect(anchors(), [40], reason: '14.1s 就近强拍 = 14s（锚点 28）');
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore + 1,
      );
      expect(sink.saved.single.corrections?.eightBeatAnchors, [40]);
      expect(sink.saved.single.annotations, isNull, reason: '仅 corrections 段变化');
    });

    test('落点解析在模块内：裸时间（非强拍）也删到最近强拍那个锚点', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(12000)));

      final outcome = editor().submit(RemoveEightBeatAnchor(at: ms(12500)));

      expect(outcome.applied, isTrue, reason: '12.5s 就近强拍 = 12s = 锚点 24');
      expect(anchors(), isEmpty);
    });

    test('预览位置无锚点：删除为 EditNoop（不入史不写盘）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      sink.saved.clear();
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;

      final outcome = editor().submit(RemoveEightBeatAnchor(at: ms(20000)));

      expect(outcome, isA<EditNoop>());
      expect(anchors(), [28], reason: '20s 处无锚点，集合不变');
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore,
      );
      expect(sink.saved, isEmpty);
    });

    test('单步撤销：回退该次删除（锚点与相位一起回退）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(RemoveEightBeatAnchor(at: ms(14000)));
      expect(anchors(), isEmpty);
      sink.saved.clear();

      editor().undo();

      expect(anchors(), [28], reason: '一步撤销回到删除前');
      expect(container.read(beatPhaseProvider).isEightBeatPoint(28), isTrue);
      expect(sink.saved.single.corrections?.eightBeatAnchors, [28]);

      editor().redo();
      expect(anchors(), isEmpty);
    });

    test('锁定分段：删除照常（锁只护分段结构，不弹提示）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      final promptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      container.read(layoutLockedProvider.notifier).replace(true);

      final outcome = editor().submit(RemoveEightBeatAnchor(at: ms(14000)));

      expect(outcome.applied, isTrue);
      expect(anchors(), isEmpty);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore);
    });

    test('删锚当帧刷新落点派生面：其后新插分段线按新相位落点', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      // 有锚点时 14s 是新相位的八拍点：14.5s 的分段线落点吸到 14s。
      editor().submit(AddSegmentLine(at: ms(14500)));
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        ms(14000),
      );

      editor().submit(RemoveEightBeatAnchor(at: ms(14000)));

      // 删锚后相位回到自动口径（14s 不再是八拍点）：同一请求位置改吸 16s
      // ——落点消费方读的是重算后的相位源（既有分段线本身不动）。
      editor().submit(AddSegmentLine(at: ms(20500)));
      expect(
        [
          for (final line
              in container.read(annotationTimelineProvider).segmentLines)
            line.position.inMilliseconds,
        ],
        [14000, 20000],
        reason: '20.5s 在自动相位下吸 20s；既有 14s 线保持不变',
      );
    });

    test('非就绪网格（异常）：无落点解析，EditNoop 不入史不写盘', () {
      useReadyGrid();
      final withAnchor = readyGrid().withAnchors(const [28]);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(BeatTrackState.ready(withAnchor));
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;
      // 异常态（本次分析失败/无节拍数据）：无强拍解析依据。
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());

      final outcome = editor().submit(RemoveEightBeatAnchor(at: ms(14000)));

      expect(outcome, isA<EditNoop>());
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore,
      );
      expect(sink.saved, isEmpty);
    });
  });

  group('清空锚点 verb（ClearEightBeatAnchors）', () {
    test('一次点击清空全部锚点：写定空集合 + 单步入史 + 保存 diff', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(AddEightBeatAnchor(at: ms(20000)));
      sink.saved.clear();
      final historyBefore = container
          .read(annotationEditHistoryProvider)
          .length;

      final outcome = editor().submit(const ClearEightBeatAnchors());

      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse);
      expect(anchors(), isEmpty);
      expect(
        container.read(annotationEditHistoryProvider).length,
        historyBefore + 1,
        reason: '整次清空 = 一次标注编辑',
      );
      expect(sink.saved.single.corrections?.eightBeatAnchors, isEmpty);
    });

    test('无锚点时置灰语义：EditNoop（不入史不写盘）', () {
      useReadyGrid();
      final outcome = editor().submit(const ClearEightBeatAnchors());

      expect(outcome, isA<EditNoop>());
      expect(anchors(), isEmpty);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(sink.saved, isEmpty);
    });

    test('单步撤销：一次撤销恢复全部锚点', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(AddEightBeatAnchor(at: ms(20000)));
      editor().submit(const ClearEightBeatAnchors());
      sink.saved.clear();

      editor().undo();

      expect(anchors(), [28, 40], reason: '一次撤销恢复清空前全部锚点');
      expect(sink.saved.single.corrections?.eightBeatAnchors, [28, 40]);
    });

    test('清空后派生面逐位回到无锚点口径（回归基线）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(const ClearEightBeatAnchors());

      final phase = container.read(beatPhaseProvider);
      expect(phase.anchors, isEmpty);
      expect(
        [
          for (final t in phase.pointsInWindow(ms(0), ms(20000)))
            t.inMilliseconds,
        ],
        [0, 4000, 8000, 12000, 16000, 20000],
        reason: '无锚点 = 自动相位（偶数强拍为八拍点）',
      );
    });

    test('锁定分段：清空照常（锁只护分段结构，不弹提示）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      final promptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
      container.read(layoutLockedProvider.notifier).replace(true);

      final outcome = editor().submit(const ClearEightBeatAnchors());

      expect(outcome.applied, isTrue);
      expect(anchors(), isEmpty);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore);
    });
  });

  group('多锚点共存的删除（验收）', () {
    test('删中间一个锚点只影响其后一段的相位，其余段不变', () {
      useReadyGrid();
      // 三锚点：28（14s）、40（20s）、52（26s）。
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      editor().submit(AddEightBeatAnchor(at: ms(20000)));
      editor().submit(AddEightBeatAnchor(at: ms(26000)));
      final before = container.read(beatPhaseProvider);
      expect(
        [
          for (final t in before.pointsInWindow(ms(0), ms(30000)))
            t.inMilliseconds,
        ],
        [0, 4000, 8000, 12000, 14000, 18000, 20000, 24000, 26000, 30000],
      );

      editor().submit(RemoveEightBeatAnchor(at: ms(20000)));

      final after = container.read(beatPhaseProvider);
      expect(
        [
          for (final t in after.pointsInWindow(ms(0), ms(30000)))
            t.inMilliseconds,
        ],
        [0, 4000, 8000, 12000, 14000, 18000, 22000, 26000, 30000],
        reason: '锚点 28 段（14/18s）不变；28→52 之间回到锚点 28 的相位；52 起不变',
      );
    });
  });

  group('分段线落点吸附跟锚点重定相（消费方）', () {
    test('无锚点：14.5s 落 16s（自动相位）；落锚后落 14s（重定相后的相位）', () {
      useReadyGrid();
      expect(
        container.read(beatPhaseProvider).nearest(ms(14500)),
        ms(16000),
        reason: '自动相位下 14s 不是八拍点，同一请求位置落 16s',
      );

      editor().submit(AddEightBeatAnchor(at: ms(14000)));

      expect(
        container.read(beatPhaseProvider).nearest(ms(14500)),
        ms(14000),
        reason: '落锚后同一请求位置落到重定相后的八拍点 14s',
      );
      editor().submit(AddSegmentLine(at: ms(14500)));

      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        ms(14000),
        reason: '落锚后 14s 成为八拍点，分段线落点随之重定相',
      );
    });

    test('锚点之前的落点不受影响（锚只向后延续）', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(20000)));
      editor().submit(AddSegmentLine(at: ms(8500)));

      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        ms(8000),
      );
    });
  });

  group('自动分段按锚点相位重算（消费方）', () {
    List<Duration> cutPositions() => container
        .read(annotationTimelineProvider)
        .segmentLines
        .map((line) => line.position)
        .toList();

    /// 生产调用路径：自动分段消费 track 的 beat 文档（含已落锚点）。
    List<Duration> submitAutoSegment() {
      final outcome = editor().submitAutoSegment(
        container.read(beatTrackStateProvider).grid!,
        fullIntervalsPerSegment: 4,
      );
      expect(outcome.applied, isTrue);
      return cutPositions();
    }

    /// 档位入参直通：指定每段整八拍区间配额提交。
    List<Duration> submitAutoSegmentWithQuota(int quota) {
      final outcome = editor().submitAutoSegment(
        container.read(beatTrackStateProvider).grid!,
        fullIntervalsPerSegment: quota,
      );
      expect(outcome.applied, isTrue);
      return cutPositions();
    }

    test('每段 8 个整八拍档：72 拍网格只在第 64 拍（32s）下刀', () {
      useReadyGrid(); // 72 拍、每 0.5s 一拍。
      expect(submitAutoSegmentWithQuota(8), [ms(32000)]);
    });

    test('无锚点：切割线 = 旧「每 32 拍」口径（回归基线）', () {
      useReadyGrid(); // 72 拍、每 0.5s 一拍 → 第 32、64 拍 = 16s、32s。
      expect(submitAutoSegment(), [ms(16000), ms(32000)]);
    });

    test('落锚后再按一次「自动首尾」按新口径重算；锚点本身不动已有线', () {
      useReadyGrid();
      expect(submitAutoSegment(), [ms(16000), ms(32000)]);

      // 落锚 14s（第 28 拍）：锚点刀——再次生成时锚点处强制下刀
      // 并清空配额（首段 3.5 个八拍：3 整 + 半八拍 24→28），其后自锚点重
      // 新数 4 个整八拍在 60 拍（30s）下刀。
      final anchored = editor().submit(AddEightBeatAnchor(at: ms(13500)));
      expect(anchored.applied, isTrue);
      expect(anchored.geometryChanged, isFalse);
      expect(cutPositions(), [ms(16000), ms(32000)], reason: '锚点变化不影响已有线');

      // 再次生成：按新相位 + 锚点刀重算，单步可撤销。
      expect(submitAutoSegment(), [ms(14000), ms(30000)]);
      expect(container.read(annotationEditHistoryProvider).length, 3);
    });

    test('末段不足 4 个整八拍并入最后一段：不产生贴着尾线的碎段', () {
      // 55 拍：尾拍 = 第 54 拍（27s）；锚点 28（14s）锚点刀一刀，其后只有
      // 3 个整八拍区间（36/44/52 拍）、不足 4 个 → 整段并入，无第二刀。
      useReadyGrid(grid: readyGrid(beats: 55));
      editor().submit(AddEightBeatAnchor(at: ms(13500)));
      expect(submitAutoSegment(), [ms(14000)]);
    });
  });

  group('相位源接线（beatPhaseProvider）', () {
    test('无锚点时相位与今日一致（网格首个强拍为原点）', () {
      useReadyGrid();
      final phase = container.read(beatPhaseProvider);
      expect(phase.anchors, isEmpty);
      expect(phase.isEightBeatPoint(0), isTrue);
      expect(phase.isEightBeatPoint(4), isFalse);
      expect(phase.isEightBeatPoint(8), isTrue);
    });

    test('占位/异常网格：相位源仍可读（无锚点 = 自动相位口径）', () {
      expect(container.read(beatPhaseProvider).nearest(ms(1500)), ms(0));
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      expect(container.read(beatPhaseProvider).nearest(ms(1500)), ms(0));
    });

    test('换视频复位（回占位态）后锚点清零', () {
      useReadyGrid();
      editor().submit(AddEightBeatAnchor(at: ms(14000)));
      expect(anchors(), [28]);

      editor().resetForVideo(const Duration(minutes: 2));
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.placeholder());

      expect(anchors(), isEmpty);
      expect(container.read(beatPhaseProvider).anchors, isEmpty);
    });

    test('重开（读回 markers 文件 JSON）后锚点与派生结构完整恢复', () {
      // 落盘侧「写进 beat 段」由 annotation_save_orchestrator_test 钉死；
      // 本用例钉恢复链：文件 JSON → beat 段文档 → 就绪态 → 相位重定相
      // （杀进程重开、换设备打开走同一条链）。
      final file = marker_doc.MarkersDocument(
        beat: readyGrid().withAnchors(const [28]),
      );
      final reopened = marker_doc.MarkersDocument.fromJson(file.toJson());
      container
          .read(beatTrackStateProvider.notifier)
          .replace(BeatTrackState.ready(reopened.beat!));

      final phase = container.read(beatPhaseProvider);
      expect(appliedEightBeatAnchors(ref()), [28]);
      expect(phase.isEightBeatPoint(28), isTrue);
      expect(
        [
          for (final t in phase.pointsInWindow(ms(0), ms(20000)))
            t.inMilliseconds,
        ],
        [0, 4000, 8000, 12000, 14000, 18000],
        reason: '锚点后 14s 起续八拍点（7→8 只隔 4 拍）',
      );
    });

    test('网格文档带锚点即水合相位（打开恢复路径）', () {
      useReadyGrid(grid: readyGrid().withAnchors(const [28]));

      expect(container.read(beatPhaseProvider).isEightBeatPoint(28), isTrue);
      expect(appliedEightBeatAnchors(ref()), [28]);
    });
  });

  group('锚点写缝', () {
    test('writeEightBeatAnchors：写定进 beat 段；同值 no-op；无网格 no-op', () {
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.placeholder());
      writeEightBeatAnchors(ref(), const [28]);
      expect(anchors(), isEmpty, reason: '无 beat 段（未分析）不适用');

      useReadyGrid();
      final before = container.read(beatTrackStateProvider).grid;
      writeEightBeatAnchors(ref(), const [28, 40]);
      expect(anchors(), [28, 40]);
      final after = container.read(beatTrackStateProvider).grid;
      expect(identical(before, after), isFalse);

      writeEightBeatAnchors(ref(), const [28, 40]);
      expect(
        identical(container.read(beatTrackStateProvider).grid, after),
        isTrue,
        reason: '同值不重写',
      );
    });

    test('节拍对齐平移保留锚点（两者正交）', () {
      useReadyGrid();
      writeEightBeatAnchors(ref(), const [28]);
      writeAppliedBeatShift(ref(), 0.5);

      expect(appliedEightBeatAnchors(ref()), [28]);
      expect(container.read(beatTrackStateProvider).grid?.shift, 0.5);
      expect(container.read(beatPhaseProvider).isEightBeatPoint(28), isTrue);
    });
  });
}
