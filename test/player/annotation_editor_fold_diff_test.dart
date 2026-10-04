import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/persistence/annotation_sections.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 段级折叠等价护栏：折叠纯函数直测——
/// 「折叠为空 ⇔ 快照相等」。快照按段持有，`videoDuration` 不属于任何
/// 段、不在快照内，等价关系无例外条款。起含备注 lane。
void main() {
  AnnotationEditSnapshot snapshot({
    Duration videoDuration = const Duration(minutes: 1),
    Duration rangeStart = Duration.zero,
    Duration rangeEnd = const Duration(minutes: 1),
    List<SegmentLine> segmentLines = const [],
    List<HalfBeatLine> halfBeatLines = const [],
    Map<int, LearningMastery> mastery = const {},
    Set<int> emphasis = const {},
    double beatShiftSeconds = 0,
    List<int> eightBeatAnchors = const [],
    List<LocalMirrorFragment> localMirrorFragments = const [],
    List<NoteSticker> notes = const [],
    List<PracticeClip> practiceClips = const [],
  }) {
    final timeline = AnnotationTimeline.normalized(
      videoDuration: videoDuration,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      segmentLines: segmentLines,
      halfBeatLines: halfBeatLines,
    );
    return AnnotationEditSnapshot(
      corrections: MarkerCorrectionsValue(
        shiftSeconds: beatShiftSeconds,
        eightBeatAnchors: eightBeatAnchors,
      ),
      annotations: MarkerAnnotationsValue(
        rangeStart: timeline.rangeStart,
        rangeEnd: timeline.rangeEnd,
        segmentLines: timeline.segmentLines,
        halfBeatLines: timeline.halfBeatLines,
        emphasizedSegments: emphasis,
        localMirrorFragments: localMirrorFragments,
      ),
      session: LocalSessionValue(mastery: mastery),
      notes: notes,
      practiceClips: practiceClips,
    );
  }

  test('全同快照对：折叠为空且快照相等', () {
    final before = snapshot(
      segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
      halfBeatLines: const [HalfBeatLine(position: Duration(seconds: 5))],
      mastery: {0: LearningMastery.learning},
      emphasis: {1},
      beatShiftSeconds: 0.5,
      eightBeatAnchors: const [28],
      localMirrorFragments: const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
      ],
    );
    final after = snapshot(
      segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
      halfBeatLines: const [HalfBeatLine(position: Duration(seconds: 5))],
      mastery: {0: LearningMastery.learning},
      emphasis: {1},
      beatShiftSeconds: 0.5,
      eightBeatAnchors: const [28],
      localMirrorFragments: const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
      ],
    );
    expect(before, after);
    expect(foldSectionDiff(before, after).isEmpty, isTrue);
  });

  test('逐段变化：该段为绝对终值、其余段为 null', () {
    // corrections 段（平移量）。
    var before = snapshot(beatShiftSeconds: 0);
    var after = snapshot(beatShiftSeconds: 1.5);
    var diff = foldSectionDiff(before, after);
    expect(diff.isEmpty, isFalse);
    expect(diff.corrections?.shiftSeconds, 1.5);
    expect(diff.annotations, isNull);
    expect(diff.session, isNull);

    // corrections 段（锚点）。
    before = snapshot(eightBeatAnchors: const [28]);
    after = snapshot(eightBeatAnchors: const [28, 40]);
    diff = foldSectionDiff(before, after);
    expect(diff.corrections?.eightBeatAnchors, [28, 40]);
    expect(diff.annotations, isNull);

    // annotations 段（分段线）。
    before = snapshot(
      segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
    );
    after = snapshot(
      segmentLines: const [SegmentLine(position: Duration(seconds: 20))],
    );
    diff = foldSectionDiff(before, after);
    expect(diff.annotations?.segmentLines, [
      const SegmentLine(position: Duration(seconds: 20)),
    ]);
    expect(diff.corrections, isNull);
    expect(diff.session, isNull);

    // annotations 段（首尾 + 半拍线 + 重点 + 局部镜像片段同段一体）。
    before = snapshot();
    after = snapshot(
      rangeStart: const Duration(seconds: 1),
      rangeEnd: const Duration(seconds: 59),
      halfBeatLines: const [HalfBeatLine(position: Duration(seconds: 5))],
      emphasis: {0, 2},
      localMirrorFragments: const [
        LocalMirrorFragment(startMs: 1000, endMs: 3000),
        LocalMirrorFragment(startMs: 5000, endMs: 7000),
      ],
    );
    diff = foldSectionDiff(before, after);
    expect(diff.annotations?.rangeStart, const Duration(seconds: 1));
    expect(diff.annotations?.rangeEnd, const Duration(seconds: 59));
    expect(diff.annotations?.halfBeatLines, [
      const HalfBeatLine(position: Duration(seconds: 5)),
    ]);
    expect(diff.annotations?.emphasizedSegments, {0, 2});
    expect(diff.annotations?.localMirrorFragments, const [
      LocalMirrorFragment(startMs: 1000, endMs: 3000),
      LocalMirrorFragment(startMs: 5000, endMs: 7000),
    ]);
    expect(diff.corrections, isNull);

    // session 段（熟练度）。
    before = snapshot(mastery: {0: LearningMastery.unlearned});
    after = snapshot(mastery: {0: LearningMastery.mastered});
    diff = foldSectionDiff(before, after);
    expect(diff.session?.mastery, {0: LearningMastery.mastered});
    expect(diff.annotations, isNull);
    expect(diff.corrections, isNull);

    // notes 段（备注贴纸，独立 lane）。
    before = snapshot();
    after = snapshot(
      notes: const [NoteSticker(startMs: 1000, endMs: 9000, text: '这里注意手')],
    );
    diff = foldSectionDiff(before, after);
    expect(diff.notes, const [
      NoteSticker(startMs: 1000, endMs: 9000, text: '这里注意手'),
    ]);
    expect(diff.annotations, isNull);
    expect(diff.corrections, isNull);
    expect(diff.session, isNull);
  });

  test('护栏不变量：抽样各段变化对均满足「折叠非空 ⇔ 快照不等」', () {
    final pairs = <(AnnotationEditSnapshot, AnnotationEditSnapshot)>[
      (
        snapshot(
          segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
        ),
        snapshot(
          segmentLines: [
            const SegmentLine(position: Duration(seconds: 10), flagged: true),
          ],
        ),
      ),
      (
        snapshot(
          halfBeatLines: const [HalfBeatLine(position: Duration(seconds: 5))],
        ),
        snapshot(),
      ),
      (
        snapshot(rangeStart: Duration.zero),
        snapshot(rangeStart: const Duration(seconds: 2)),
      ),
      (
        snapshot(mastery: {1: LearningMastery.unlearned}),
        snapshot(mastery: {1: LearningMastery.learning}),
      ),
      (snapshot(emphasis: {3}), snapshot(emphasis: {})),
      (snapshot(beatShiftSeconds: 0.25), snapshot(beatShiftSeconds: -0.75)),
      (snapshot(eightBeatAnchors: const [28]), snapshot()),
      (
        snapshot(
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 3000),
          ],
        ),
        snapshot(
          localMirrorFragments: const [
            LocalMirrorFragment(startMs: 5000, endMs: 7000),
          ],
        ),
      ),
      (
        snapshot(notes: const [NoteSticker(startMs: 1000, endMs: 9000)]),
        snapshot(
          notes: const [NoteSticker(startMs: 1000, endMs: 9000, locked: true)],
        ),
      ),
    ];
    for (final (b, a) in pairs) {
      expect(b, isNot(a));
      expect(
        foldSectionDiff(b, a).isEmpty,
        isFalse,
        reason: '快照不等时折叠必须非空（段级等价护栏）',
      );
    }
  });

  test('videoDuration 结构性缺席：快照不携带、折叠无从感知', () {
    // videoDuration 只活在时间线内存态，不属于任何段——用不同时长构造
    // 出的两份同值快照逐位相等（结构上不存在「仅 videoDuration 不同」
    // 的快照对）。
    final a = snapshot(
      videoDuration: const Duration(minutes: 1),
      segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
    );
    final b = snapshot(
      videoDuration: const Duration(minutes: 2),
      segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
    );
    expect(a, b);
    expect(foldSectionDiff(a, b).isEmpty, isTrue);
  });
}
