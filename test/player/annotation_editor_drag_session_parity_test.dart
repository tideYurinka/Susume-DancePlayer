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
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        localMirrorFragmentsProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/notice.dart' show NoticeId, noticeTriggerProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（历史 × 保存 1:1 parity 对拍用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 拖动会话统一操作面：五个具名工厂返回的会话类型不同，但外部行为同构
/// （逐帧 moveTo 返回写后真实落点或空；end 幂等收口）。参数表只钉这层
/// 外部行为，不窥会话内部。
class _DragSessionHandle {
  _DragSessionHandle({required this.moveTo, required this.end});

  final Duration? Function(Duration target) moveTo;
  final void Function() end;
}

/// 一族拖动的参数表条目：如何开始会话、三个逐帧序列（净变化 / 无净变化
/// / 被钳空）、落点与状态的读取面、收口保存 diff 载荷的终值读取器。
class _DragFamily {
  _DragFamily({
    required this.name,
    required this.seed,
    required this.seedClamped,
    required this.open,
    required this.netFrames,
    required this.expectedLanding,
    required this.noNetFrame,
    required this.clampedFrames,
    required this.landing,
    required this.snapshot,
    required this.diffLanding,
    this.layoutLocked = false,
  });

  final String name;
  final void Function(ProviderContainer container) seed;
  final void Function(ProviderContainer container) seedClamped;
  final _DragSessionHandle Function(AnnotationEditor editor) open;
  final List<Duration> netFrames;
  final Duration expectedLanding;
  final Duration noNetFrame;
  final List<Duration> clampedFrames;
  final Object Function(ProviderContainer container) landing;
  final Object Function(ProviderContainer container) snapshot;

  /// 本族是否受锁定分段（只剩分段线与首尾端标两族）。
  final bool layoutLocked;

  /// 从收口保存 diff 载荷读回本族终值落点（null = 载荷未携带本族所在段）。
  final Duration? Function(AnnotationSectionDiff diff) diffLanding;
}

/// 跨族参数表：「一次拖动会话 = 一条
/// 历史 = 一次保存」这条不变量对五族（分段线 / 半拍线 / 视频首尾端标 /
/// 局部镜像片段整体移 / 端点拖）只在此一处断言——收口后历史恰加一条、
/// 保存恰入队一条；无净变化双双为零；收口幂等不产生第二条；会话被撤销
/// 防御性收口后逐帧返回空；逐帧中间态不入队；锁门禁逐帧返回空、状态
/// 不变、触发一次提示。表内每族只带一个代表落点（驱动净变化序列）；
/// 各族吸附来源的**落点全表**（八拍点 / 半拍格点 / 真实拍点 / 同级派生
/// 点 / 自由落点）是规格，留在各族 landing 测试文件原处。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const ten25 = Duration(seconds: 10, milliseconds: 250);
  const ten30 = Duration(seconds: 10, milliseconds: 300);
  const ten60 = Duration(seconds: 10, milliseconds: 600);
  const ten75 = Duration(seconds: 10, milliseconds: 750);
  const sixteen = Duration(seconds: 16);
  const eighteen = Duration(seconds: 18);
  const twenty = Duration(seconds: 20);
  const twentyFive = Duration(seconds: 25);
  const thirty = Duration(seconds: 30);

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

  final families = <_DragFamily>[
    // 分段线：占位网格（无锚点直通合法域）；钳空 = 触界 / 越邻丢弃。
    _DragFamily(
      name: '分段线',
      seed: (c) =>
          c.read(annotationEditorProvider).submit(AddSegmentLine(at: ten)),
      seedClamped: (c) =>
          c.read(annotationEditorProvider).submit(AddSegmentLine(at: ten)),
      open: (editor) {
        final session = editor.beginLineDrag(0);
        return _DragSessionHandle(moveTo: session.moveTo, end: session.end);
      },
      netFrames: const [twenty, thirty],
      expectedLanding: thirty,
      noNetFrame: ten,
      clampedFrames: const [total, Duration.zero],
      landing: (c) =>
          c.read(annotationTimelineProvider).segmentLines.first.position,
      snapshot: (c) => c.read(annotationTimelineProvider),
      diffLanding: (diff) => diff.annotations?.segmentLines.first.position,
      layoutLocked: true,
    ),
    // 半拍线：半拍格点吸附（0.25s + 0.5k，等距取靠后）；钳空 = 越邻
    // （吸附落点撞右邻位置被钳制丢弃）。
    _DragFamily(
      name: '半拍线',
      seed: (c) =>
          c.read(annotationEditorProvider).submit(AddHalfBeatLine(at: ten25)),
      seedClamped: (c) {
        final editor = c.read(annotationEditorProvider);
        editor.submit(AddHalfBeatLine(at: ten25));
        editor.submit(AddHalfBeatLine(at: ten75));
      },
      open: (editor) {
        final session = editor.beginHalfBeatDrag(0);
        return _DragSessionHandle(moveTo: session.moveTo, end: session.end);
      },
      netFrames: const [twenty],
      expectedLanding: const Duration(seconds: 20, milliseconds: 250),
      noNetFrame: ten30,
      clampedFrames: const [ten60],
      landing: (c) =>
          c.read(annotationTimelineProvider).halfBeatLines.first.position,
      snapshot: (c) => c.read(annotationTimelineProvider),
      diffLanding: (diff) => diff.annotations?.halfBeatLines.first.position,
    ),
    // 首尾端标（尾边界）：无索引校验；归一化只把尾钳到 [首, 时长]——
    // 钳空 = 请求越片尾被钳回时长上限（恰为缺省尾，落回原值）。
    _DragFamily(
      name: '视频首尾端标',
      seed: (c) {},
      seedClamped: (c) {},
      open: (editor) {
        final session = editor.beginRangeDrag(VideoRangeBoundary.end);
        return _DragSessionHandle(moveTo: session.moveTo, end: session.end);
      },
      netFrames: const [thirty],
      expectedLanding: thirty,
      noNetFrame: total,
      clampedFrames: const [Duration(seconds: 70)],
      landing: (c) => c.read(annotationTimelineProvider).rangeEnd,
      snapshot: (c) => c.read(annotationTimelineProvider),
      diffLanding: (diff) => diff.annotations?.rangeEnd,
      layoutLocked: true,
    ),
    // 局部镜像片段整体移：端点同级吸附 + 互斥钳制；钳空 = 前后紧贴
    // 无可放置区间。
    _DragFamily(
      name: '局部镜像片段整体移',
      seed: (c) {
        c
            .read(beatTrackStateProvider.notifier)
            .replace(uniformReadyBeatState(seconds: 60));
        c
            .read(annotationEditorProvider)
            .restoreDocument(
              AnnotationRestoreDocument(
                timeline: AnnotationTimeline.wholeVideo(total),
                localMirrorFragments: const [
                  LocalMirrorFragment(startMs: 8000, endMs: 12000),
                  LocalMirrorFragment(startMs: 20000, endMs: 24000),
                ],
              ),
            );
      },
      seedClamped: (c) {
        c
            .read(beatTrackStateProvider.notifier)
            .replace(uniformReadyBeatState(seconds: 60));
        c
            .read(annotationEditorProvider)
            .restoreDocument(
              AnnotationRestoreDocument(
                timeline: AnnotationTimeline.wholeVideo(total),
                localMirrorFragments: const [
                  LocalMirrorFragment(startMs: 0, endMs: 4000),
                  LocalMirrorFragment(startMs: 4000, endMs: 8000),
                ],
              ),
            );
      },
      open: (editor) {
        final session = editor.beginLocalMirrorMoveDrag(0);
        return _DragSessionHandle(moveTo: session.moveTo, end: session.end);
      },
      netFrames: const [eighteen],
      expectedLanding: sixteen,
      noNetFrame: const Duration(seconds: 8),
      clampedFrames: const [ten],
      landing: (c) => Duration(
        milliseconds: c.read(localMirrorFragmentsProvider).first.startMs,
      ),
      snapshot: (c) => c.read(localMirrorFragmentsProvider),
      diffLanding: (diff) => diff.annotations == null
          ? null
          : Duration(
              milliseconds: diff.annotations!.localMirrorFragments.first.startMs,
            ),
    ),
    // 局部镜像片段端点拖：端点吸附 + 互斥钳制；钳空 = 钳到相邻片段
    // 起点恰为当前端点（写入同值）。
    _DragFamily(
      name: '局部镜像片段端点拖',
      seed: (c) {
        c
            .read(beatTrackStateProvider.notifier)
            .replace(uniformReadyBeatState(seconds: 60));
        c
            .read(annotationEditorProvider)
            .restoreDocument(
              AnnotationRestoreDocument(
                timeline: AnnotationTimeline.wholeVideo(total),
                localMirrorFragments: const [
                  LocalMirrorFragment(startMs: 8000, endMs: 12000),
                  LocalMirrorFragment(startMs: 20000, endMs: 24000),
                ],
              ),
            );
      },
      seedClamped: (c) {
        c
            .read(beatTrackStateProvider.notifier)
            .replace(uniformReadyBeatState(seconds: 60));
        c
            .read(annotationEditorProvider)
            .restoreDocument(
              AnnotationRestoreDocument(
                timeline: AnnotationTimeline.wholeVideo(total),
                localMirrorFragments: const [
                  LocalMirrorFragment(startMs: 1000, endMs: 3000),
                  LocalMirrorFragment(startMs: 3000, endMs: 5000),
                ],
              ),
            );
      },
      open: (editor) {
        final session = editor.beginLocalMirrorEdgeDrag(0, IntervalEdge.end);
        return _DragSessionHandle(moveTo: session.moveTo, end: session.end);
      },
      netFrames: const [twentyFive],
      expectedLanding: twenty,
      noNetFrame: const Duration(seconds: 12),
      clampedFrames: const [Duration(seconds: 6)],
      landing: (c) => Duration(
        milliseconds: c.read(localMirrorFragmentsProvider).first.endMs,
      ),
      snapshot: (c) => c.read(localMirrorFragmentsProvider),
      diffLanding: (diff) => diff.annotations == null
          ? null
          : Duration(
              milliseconds: diff.annotations!.localMirrorFragments.first.endMs,
            ),
    ),
  ];

  for (final family in families) {
    group('跨族参数表：${family.name}', () {
      test('净变化：收口后历史恰 +1 ∧ 保存恰入队 1；中间态不入队；end 幂等', () {
        family.seed(container);
        final historyBefore = container
            .read(annotationEditHistoryProvider)
            .length;
        sink.saved.clear();

        final session = family.open(editor());
        for (final frame in family.netFrames) {
          expect(session.moveTo(frame), isNotNull, reason: '净变化帧 $frame');
        }
        expect(family.landing(container), family.expectedLanding);
        // 逐帧中间态不入队：收口前保存队列为空。
        expect(sink.saved, isEmpty);

        session.end();
        session.end(); // 收口幂等：不产生第二条。
        expect(
          container.read(annotationEditHistoryProvider).length,
          historyBefore + 1,
        );
        expect(sink.saved.length, 1);
        // 保存 diff 载荷终值与模型终态一致（payload 携带本族字段组）。
        expect(family.diffLanding(sink.saved.single), family.expectedLanding);
      });

      test('无净变化：逐帧返回空、状态不变、历史与保存双双为零', () {
        family.seed(container);
        final historyBefore = container
            .read(annotationEditHistoryProvider)
            .length;
        final stateBefore = family.snapshot(container);
        sink.saved.clear();

        final session = family.open(editor());
        expect(session.moveTo(family.noNetFrame), isNull);
        expect(family.snapshot(container), stateBefore);
        session.end();

        expect(
          container.read(annotationEditHistoryProvider).length,
          historyBefore,
        );
        expect(sink.saved, isEmpty);
      });

      test('被钳空：逐帧返回空、状态不变、历史与保存双双为零', () {
        family.seedClamped(container);
        final historyBefore = container
            .read(annotationEditHistoryProvider)
            .length;
        final stateBefore = family.snapshot(container);
        sink.saved.clear();

        final session = family.open(editor());
        for (final frame in family.clampedFrames) {
          expect(session.moveTo(frame), isNull, reason: '钳空帧 $frame');
        }
        expect(family.snapshot(container), stateBefore);
        session.end();

        expect(
          container.read(annotationEditHistoryProvider).length,
          historyBefore,
        );
        expect(sink.saved, isEmpty);
      });

      test('会话被撤销防御性收口后逐帧返回空', () {
        family.seed(container);

        final session = family.open(editor());
        expect(session.moveTo(family.netFrames.first), isNotNull);
        editor().undo();
        expect(session.moveTo(family.noNetFrame), isNull);
      });

      test(family.layoutLocked
          ? '锁门禁：逐帧返回空、状态不变、触发一次提示'
          : '不受锁定分段：锁下逐帧照常写入、不弹提示', () {
        family.seed(container);
        container.read(layoutLockedProvider.notifier).toggle();
        final promptBefore = container.read(noticeTriggerProvider(NoticeId.layoutLock));
        sink.saved.clear();

        final session = family.open(editor());
        if (family.layoutLocked) {
          final historyBefore = container
              .read(annotationEditHistoryProvider)
              .length;
          final stateBefore = family.snapshot(container);
          expect(session.moveTo(family.netFrames.first), isNull);
          expect(family.snapshot(container), stateBefore);
          expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore + 1);
          session.end();

          expect(
            container.read(annotationEditHistoryProvider).length,
            historyBefore,
          );
          expect(sink.saved, isEmpty);
        } else {
          expect(session.moveTo(family.netFrames.first), isNotNull);
          expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), promptBefore);
          session.end();
          expect(sink.saved, hasLength(1));
        }
      });
    });
  }

  group('索引越界错误契约（按族）', () {
    test('分段线：越界开始会话抛 RangeError', () {
      editor().submit(AddSegmentLine(at: ten));
      expect(() => editor().beginLineDrag(1), throwsRangeError);
      expect(() => editor().beginLineDrag(-1), throwsRangeError);
    });

    test('局部镜像片段整体移：越界开始会话抛 RangeError', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 8000, endMs: 12000),
          ],
        ),
      );
      expect(() => editor().beginLocalMirrorMoveDrag(1), throwsRangeError);
      expect(() => editor().beginLocalMirrorMoveDrag(-1), throwsRangeError);
    });

    test('局部镜像片段端点拖：越界开始会话抛 RangeError', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 8000, endMs: 12000),
          ],
        ),
      );
      expect(
        () => editor().beginLocalMirrorEdgeDrag(1, IntervalEdge.end),
        throwsRangeError,
      );
      expect(
        () => editor().beginLocalMirrorEdgeDrag(-1, IntervalEdge.start),
        throwsRangeError,
      );
    });

    test('首尾端标族无索引校验：两个边界均能直接开始会话', () {
      expect(editor().beginRangeDrag(VideoRangeBoundary.start), isNotNull);
      expect(editor().beginRangeDrag(VideoRangeBoundary.end), isNotNull);
    });
  });
}
