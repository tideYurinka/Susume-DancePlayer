import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/annotation_selection_domain_harness.dart';

/// 选中域——单值槽半边直测。
///
/// 缝 = 域对象公开接口 + 域状态 provider：裸容器只挂域的状态 provider，不
/// pump widget、不经 `AnnotationEditor`。只钉域交出的外部可观察事实：
/// 三动词的置位与互斥、两类越界拒绝形状、`clear` 幂等、同位重映射四走向。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late AnnotationSelectionDomain domain;

  void buildDomain({
    int Function()? localMirrorFragmentCount,
    int Function()? noteCount,
  }) {
    domain = buildAnnotationSelectionDomain(
      container: container,
      localMirrorFragmentCount: localMirrorFragmentCount,
      noteCount: noteCount,
    );
  }

  setUp(() {
    container = ProviderContainer();
    buildDomain();
  });

  tearDown(() => container.dispose());

  AnnotationSelection? selection() =>
      container.read(annotationSelectionProvider);

  AnnotationTimeline timeline({
    List<SegmentLine> segmentLines = const [],
    List<HalfBeatLine> halfBeatLines = const [],
  }) => AnnotationTimeline.normalized(
    videoDuration: total,
    segmentLines: segmentLines,
    halfBeatLines: halfBeatLines,
  );

  SegmentLine line(int seconds) =>
      SegmentLine(position: Duration(seconds: seconds));

  HalfBeatLine half(int seconds) =>
      HalfBeatLine(position: Duration(seconds: seconds));

  group('单值槽三动词', () {
    test('默认无选中；select 置位且五类共用单选槽互斥', () {
      expect(selection(), isNull);

      domain.select(const SegmentLineSelection(2));
      expect(selection(), isA<SegmentLineSelection>());
      expect(selection()!.asSegmentLineIndex, 2);

      domain.select(const VideoRangeBoundarySelection(VideoRangeBoundary.end));
      expect(selection()!.asSegmentLineIndex, isNull);
      expect(selection()!.asVideoRangeBoundary, VideoRangeBoundary.end);

      domain.select(const HalfBeatLineSelection(1));
      expect(selection()!.asVideoRangeBoundary, isNull);
      expect(selection()!.asHalfBeatLineIndex, 1);

      buildDomain(localMirrorFragmentCount: () => 3, noteCount: () => 2);
      domain.select(const LocalMirrorFragmentSelection(2));
      expect(selection()!.asLocalMirrorFragmentIndex, 2);

      domain.select(const NoteFragmentSelection(1));
      expect(selection()!.asLocalMirrorFragmentIndex, isNull);
      expect(selection()!.asNoteFragmentIndex, 1);
    });

    test('toggle：同目标再点取消、异目标替换（分段线/半拍线/端标）', () {
      domain.toggle(const SegmentLineSelection(0));
      expect(selection()!.asSegmentLineIndex, 0);
      domain.toggle(const SegmentLineSelection(0));
      expect(selection(), isNull);

      domain.toggle(const SegmentLineSelection(0));
      domain.toggle(const SegmentLineSelection(1));
      expect(selection()!.asSegmentLineIndex, 1);

      domain.toggle(const HalfBeatLineSelection(0));
      domain.toggle(const HalfBeatLineSelection(0));
      expect(selection(), isNull);

      domain.toggle(
        const VideoRangeBoundarySelection(VideoRangeBoundary.start),
      );
      domain.toggle(
        const VideoRangeBoundarySelection(VideoRangeBoundary.start),
      );
      expect(selection(), isNull);
      domain.toggle(
        const VideoRangeBoundarySelection(VideoRangeBoundary.start),
      );
      domain.toggle(const VideoRangeBoundarySelection(VideoRangeBoundary.end));
      expect(selection()!.asVideoRangeBoundary, VideoRangeBoundary.end);

      // 片段/备注今天只有「只选中」一条路径：toggle 不引入第二次点击取消。
      buildDomain(localMirrorFragmentCount: () => 1, noteCount: () => 1);
      domain.toggle(const LocalMirrorFragmentSelection(0));
      domain.toggle(const LocalMirrorFragmentSelection(0));
      expect(
        selection()!.asLocalMirrorFragmentIndex,
        0,
        reason: '片段再写仍是「只选中」，不取消',
      );
    });

    test('clear 清除任意目标且幂等（无选中时再次 clear 零行为）', () {
      buildDomain(localMirrorFragmentCount: () => 1, noteCount: () => 1);
      domain.select(const NoteFragmentSelection(0));
      domain.clear();
      expect(selection(), isNull);

      domain.clear();
      expect(selection(), isNull);

      domain.select(
        const VideoRangeBoundarySelection(VideoRangeBoundary.start),
      );
      domain.clear();
      expect(selection(), isNull);
    });
  });

  group('越界拒绝形状', () {
    test('分段线负索引抛 RangeError（0..null、索引不能为负）', () {
      expect(
        () => domain.select(const SegmentLineSelection(-1)),
        throwsA(
          isA<RangeError>()
              .having((e) => e.invalidValue, 'invalidValue', -1)
              .having((e) => e.start, 'start', 0)
              .having((e) => e.end, 'end', isNull)
              .having((e) => e.message, 'message', '分段线索引不能为负'),
        ),
      );
      expect(
        () => domain.toggle(const SegmentLineSelection(-1)),
        throwsA(isA<RangeError>()),
      );
      expect(selection(), isNull);
    });

    test('半拍线负索引抛 RangeError（0..null、索引不能为负）', () {
      expect(
        () => domain.toggle(const HalfBeatLineSelection(-1)),
        throwsA(
          isA<RangeError>().having((e) => e.message, 'message', '半拍线索引不能为负'),
        ),
      );
    });

    test('局部镜像片段索引越界抛 RangeError（0..count-1、片段索引越界）', () {
      buildDomain(localMirrorFragmentCount: () => 2, noteCount: () => 0);
      expect(
        () => domain.select(const LocalMirrorFragmentSelection(2)),
        throwsA(
          isA<RangeError>()
              .having((e) => e.invalidValue, 'invalidValue', 2)
              .having((e) => e.start, 'start', 0)
              .having((e) => e.end, 'end', 1)
              .having((e) => e.message, 'message', '局部镜像片段索引越界'),
        ),
      );
      expect(
        () => domain.select(const LocalMirrorFragmentSelection(-1)),
        throwsA(
          isA<RangeError>().having((e) => e.message, 'message', '局部镜像片段索引越界'),
        ),
      );
      expect(selection(), isNull);
    });

    test('备注片段索引越界抛 RangeError（0..count-1、备注索引越界）', () {
      buildDomain(localMirrorFragmentCount: () => 0, noteCount: () => 1);
      expect(
        () => domain.select(const NoteFragmentSelection(1)),
        throwsA(
          isA<RangeError>()
              .having((e) => e.invalidValue, 'invalidValue', 1)
              .having((e) => e.start, 'start', 0)
              .having((e) => e.end, 'end', 0)
              .having((e) => e.message, 'message', '备注索引越界'),
        ),
      );
      expect(selection(), isNull);
    });
  });

  group('同位重映射四走向', () {
    test('线数不变不动选中', () {
      domain.select(const SegmentLineSelection(0));
      domain.remapLineSelection(
        timeline(segmentLines: [line(10)]),
        timeline(
          segmentLines: [SegmentLine(position: const Duration(seconds: 12))],
        ),
      );
      expect(selection()!.asSegmentLineIndex, 0);
    });

    test('按位置匹配重指向（插线右侧 +1、删线左移）', () {
      domain.select(const SegmentLineSelection(1));
      domain.remapLineSelection(
        timeline(segmentLines: [line(10), line(20)]),
        timeline(segmentLines: [line(5), line(10), line(20)]),
      );
      expect(selection()!.asSegmentLineIndex, 2);

      domain.remapLineSelection(
        timeline(segmentLines: [line(5), line(10), line(20)]),
        timeline(segmentLines: [line(10), line(20)]),
      );
      expect(selection()!.asSegmentLineIndex, 1);
    });

    test('越界无效化（选中索引已不在变化前线表内）', () {
      domain.select(const SegmentLineSelection(3));
      domain.remapLineSelection(
        timeline(segmentLines: [line(10), line(20)]),
        timeline(segmentLines: [line(10)]),
      );
      expect(selection(), isNull);
    });

    test('匹配不到则清（选中线被删）', () {
      domain.select(const SegmentLineSelection(1));
      domain.remapLineSelection(
        timeline(segmentLines: [line(10), line(20)]),
        timeline(segmentLines: [line(10)]),
      );
      expect(selection(), isNull);
    });

    test('半拍线同一语义；非线选中不受重映射影响', () {
      domain.toggle(const HalfBeatLineSelection(1));
      domain.remapLineSelection(
        timeline(halfBeatLines: [half(5), half(15)]),
        timeline(halfBeatLines: [half(5), half(8), half(15)]),
      );
      expect(selection()!.asHalfBeatLineIndex, 2);

      domain.select(
        const VideoRangeBoundarySelection(VideoRangeBoundary.start),
      );
      domain.remapLineSelection(
        timeline(segmentLines: [line(10)]),
        timeline(segmentLines: [line(10), line(20)]),
      );
      expect(selection()!.asVideoRangeBoundary, VideoRangeBoundary.start);
    });
  });
}
