import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/dancer_roster.dart';
import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/cast/cast_annotation_fingerprint.dart';
import 'package:dance_learning_app/core/beat_point.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter_test/flutter_test.dart';

/// 标注内容指纹直测（纯件）：**任一件标注改了，指纹就换**——缓存键里那一分量
/// 的算术面。
void main() {
  AnnotationTimeline timeline({
    Duration rangeStart = Duration.zero,
    Duration rangeEnd = const Duration(seconds: 30),
    List<SegmentLine> segments = const [],
    List<HalfBeatLine> halfBeats = const [],
  }) => AnnotationTimeline.normalized(
    videoDuration: const Duration(seconds: 30),
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    segmentLines: segments,
    halfBeatLines: halfBeats,
  );

  marker_doc.BeatGrid grid({
    List<BeatPoint> beats = const [BeatPoint(t: 0.5, down: true)],
    double shift = 0,
    double density = 1,
    List<int> anchors = const [],
  }) => marker_doc.BeatGrid(
    model: 'madmom_downbeat_rnn_full.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2026, 1, 1),
    beats: beats,
    shift: shift,
    density: density,
    anchors: anchors,
  );

  CastAnnotationFacts facts({
    AnnotationTimeline? timelineValue,
    List<NoteSticker> notes = const [],
    List<LocalMirrorFragment> mirrorFragments = const [],
    List<DancerRosterEntry> roster = const [],
    marker_doc.BeatGrid? beatGrid,
  }) => CastAnnotationFacts(
    timeline: timelineValue ?? timeline(),
    notes: notes,
    mirrorFragments: mirrorFragments,
    roster: roster,
    beatGrid: beatGrid,
  );

  test('指纹是 16 位小写十六进制；同一份事实给同一个指纹', () {
    final value = castAnnotationFingerprint(facts());

    expect(value, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(castAnnotationFingerprint(facts()), value);
  });

  test('一模一样的取值（不同实例）指纹相同', () {
    final a = facts(
      timelineValue: timeline(
        segments: [const SegmentLine(position: Duration(seconds: 10))],
      ),
      notes: [const NoteSticker(startMs: 0, endMs: 1000, text: '注意手')],
      mirrorFragments: const [LocalMirrorFragment(startMs: 0, endMs: 1000)],
      roster: const [DancerRosterEntry(name: '小满', color: 0xFF00FF00)],
      beatGrid: grid(),
    );
    final b = facts(
      timelineValue: timeline(
        segments: [const SegmentLine(position: Duration(seconds: 10))],
      ),
      notes: [const NoteSticker(startMs: 0, endMs: 1000, text: '注意手')],
      mirrorFragments: const [LocalMirrorFragment(startMs: 0, endMs: 1000)],
      roster: const [DancerRosterEntry(name: '小满', color: 0xFF00FF00)],
      beatGrid: grid(),
    );

    expect(castAnnotationFingerprint(a), castAnnotationFingerprint(b));
  });

  group('任一件标注改了，指纹就换', () {
    test('分段线', () {
      expect(
        castAnnotationFingerprint(
          facts(
            timelineValue: timeline(
              segments: [const SegmentLine(position: Duration(seconds: 10))],
            ),
          ),
        ),
        isNot(castAnnotationFingerprint(facts())),
      );
    });

    test('首尾线区间', () {
      expect(
        castAnnotationFingerprint(
          facts(
            timelineValue: timeline(rangeStart: const Duration(seconds: 2)),
          ),
        ),
        isNot(castAnnotationFingerprint(facts())),
      );
    });

    test('半拍线', () {
      expect(
        castAnnotationFingerprint(
          facts(
            timelineValue: timeline(
              halfBeats: [const HalfBeatLine(position: Duration(seconds: 3))],
            ),
          ),
        ),
        isNot(castAnnotationFingerprint(facts())),
      );
    });

    test('备注（文本 / 时间窗 / 几何）', () {
      final base = facts(
        notes: [const NoteSticker(startMs: 0, endMs: 1000, text: '注意手')],
      );
      expect(
        castAnnotationFingerprint(
          facts(
            notes: [const NoteSticker(startMs: 0, endMs: 1000, text: '注意脚')],
          ),
        ),
        isNot(castAnnotationFingerprint(base)),
      );
      expect(
        castAnnotationFingerprint(
          facts(
            notes: [const NoteSticker(startMs: 0, endMs: 2000, text: '注意手')],
          ),
        ),
        isNot(castAnnotationFingerprint(base)),
      );
    });

    test('局部镜像片段', () {
      expect(
        castAnnotationFingerprint(
          facts(
            mirrorFragments: const [
              LocalMirrorFragment(startMs: 1000, endMs: 2000),
            ],
          ),
        ),
        isNot(castAnnotationFingerprint(facts())),
      );
    });

    test('舞者名册', () {
      expect(
        castAnnotationFingerprint(
          facts(
            roster: const [DancerRosterEntry(name: '小满', color: 0xFF00FF00)],
          ),
        ),
        isNot(castAnnotationFingerprint(facts())),
      );
    });

    test('节拍内容（拍点 / 平移 / 倍频 / 八拍锚点）', () {
      final base = castAnnotationFingerprint(facts(beatGrid: grid()));
      expect(base, isNot(castAnnotationFingerprint(facts())));

      expect(
        castAnnotationFingerprint(
          facts(beatGrid: grid(beats: const [BeatPoint(t: 0.6, down: true)])),
        ),
        isNot(base),
        reason: '拍点变了，数拍与拍声都要重渲',
      );
      expect(
        castAnnotationFingerprint(facts(beatGrid: grid(shift: 0.05))),
        isNot(base),
      );
      expect(
        castAnnotationFingerprint(facts(beatGrid: grid(density: 2))),
        isNot(base),
      );
      expect(
        castAnnotationFingerprint(facts(beatGrid: grid(anchors: const [1]))),
        isNot(base),
      );
    });

    test('识别时间与模型名不进指纹（它们不改产物）', () {
      final a = marker_doc.BeatGrid(
        model: 'model-a.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 1, 1),
        beats: const [BeatPoint(t: 0.5, down: true)],
      );
      final b = marker_doc.BeatGrid(
        model: 'model-b.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 6, 6),
        beats: const [BeatPoint(t: 0.5, down: true)],
      );

      expect(
        castAnnotationFingerprint(facts(beatGrid: a)),
        castAnnotationFingerprint(facts(beatGrid: b)),
      );
    });
  });
}
