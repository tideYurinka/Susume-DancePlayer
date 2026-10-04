import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/core/playback/playback_engine.dart';
import 'package:dance_learning_app/player/track_hit_resolution.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 命中解析适配层直测：不 pump widget、不注
/// provider——同一组（局部坐标、行表、窗口、几何）给出的目标族、行归属与学习
/// 段命中次序，由本套件逐位钉住；期望值全部由「带宽 200、片头 40、总时长 60s」
/// 这一份手算尺度独立给出（内容区 [40, 200]、每秒 160/60 px），不复算实现里的
/// 公式。
///
/// 命中宽度的手算口径：分段线/首尾线半宽 20px → 7.5s，学习段最小命中全宽
/// 24px → 9s，备注/镜像最小命中全宽 40px → 15s。
const Duration total = Duration(seconds: 60);
const double bandWidth = 200;

/// 带内屏上 x：内容区左缘 40、内容区宽 160、总时长 60s。
double xAt(int ms) => 40 + ms * 160 / 60000;

/// `normal` 行集的行中心（行表：备注 0–36、镜像 46–76、学习 86–134、
/// 节拍 144–168、手柄带 178–208，间隙 10）。
const double noteRowY = 18;
const double mirrorRowY = 61;
const double learningRowY = 110;
const double beatRowY = 156;

/// `compare` 行集（备注 0–36、练习视频 46–94、学习 104–152、节拍 162–186）。
const double practiceRowY = 70;
const double compareLearningRowY = 128;

/// 无总时长的内核（几何不可用的另一端）。
class _DurationlessEngine extends FakePlaybackEngine {
  @override
  Duration? get duration => null;
}

TrackHitResolution hitsOf({
  Duration? totalDuration = total,
  double width = bandWidth,
  TimelineWindow? window,
  TrackRowTable rowTable = TrackRowTable.normal,
  AnnotationTimeline? timeline,
  List<PracticeClip> clips = const [],
  List<NoteSticker> notes = const [],
  List<LocalMirrorFragment> mirrorFragments = const [],
  Duration playhead = Duration.zero,
}) {
  final PlaybackEngine engine = totalDuration == null
      ? _DurationlessEngine()
      : FakePlaybackEngine(duration: totalDuration);
  return TrackHitResolution(
    engine: engine,
    window: window,
    width: width,
    rowTable: rowTable,
    timeline: timeline ?? AnnotationTimeline.wholeVideo(totalDuration ?? Duration.zero),
    clips: clips,
    notes: notes,
    mirrorFragments: mirrorFragments,
    playhead: playhead,
  );
}

AnnotationTimeline timelineWithLines(List<int> lineMs) =>
    AnnotationTimeline.normalized(
      videoDuration: total,
      segmentLines: [
        for (final ms in lineMs) SegmentLine(position: Duration(milliseconds: ms)),
      ],
    );

void main() {
  group('编辑目标：某个局部点落在哪个编辑目标', () {
    test('预览条先于分段线：命中列内是预览条，列外回落分段线', () {
      final hits = hitsOf(
        timeline: timelineWithLines([30000]),
        playhead: const Duration(seconds: 30),
      );
      // 预览条半宽 1dp：120 与 121 都在列内，122 出列。
      expect(hits.editTargetAt(Offset(xAt(30000), learningRowY)),
          TrackEditTarget.previewLine);
      expect(hits.editTargetAt(Offset(xAt(30000) + 1, learningRowY)),
          TrackEditTarget.previewLine);
      expect(hits.editTargetAt(Offset(xAt(30000) + 2, learningRowY)),
          TrackEditTarget.segmentLine);
    });

    test('练习片段块先于学习段命中：块上即练习片段', () {
      final hits = hitsOf(
        rowTable: TrackRowTable.compare,
        clips: [
          PracticeClip(
            id: 'c1',
            materialId: 'm1',
            materialSourceStartMs: 0,
            inMs: 0,
            outMs: 10000,
          ),
        ],
      );
      expect(hits.editTargetAt(Offset(xAt(3750), practiceRowY)),
          TrackEditTarget.practiceClip);
      // 同一列落在学习行上：块体不在该行，落回首尾线命中。
      expect(hits.editTargetAt(Offset(xAt(3750), compareLearningRowY)),
          TrackEditTarget.segmentLine);
      // 练习片段命中入口（压在块上的预览线落位那一问同用）：局部点 → 片段。
      expect(hits.practiceClipAt(Offset(xAt(3750), practiceRowY))?.id, 'c1');
      expect(hits.practiceClipAt(Offset(xAt(3750), compareLearningRowY)), isNull);
      expect(hits.practiceClipAt(Offset(xAt(45000), practiceRowY)), isNull);
    });

    test('段线命中带贯穿全带高：非学习行也是编辑内容', () {
      final normal = hitsOf(timeline: timelineWithLines([30000]));
      final compare =
          hitsOf(rowTable: TrackRowTable.compare, timeline: timelineWithLines([30000]));
      expect(normal.editTargetAt(Offset(xAt(30000), beatRowY)),
          TrackEditTarget.segmentLine);
      expect(compare.editTargetAt(Offset(xAt(30000), beatRowY)),
          TrackEditTarget.segmentLine);
    });

    test('段体只在学习行内是编辑内容', () {
      // 线在 30s → 段 = [0, 30s) 与 [30s, 60s)；10s 落在首段体内。
      final hits = hitsOf(timeline: timelineWithLines([30000]));
      expect(hits.editTargetAt(Offset(xAt(10000), learningRowY)),
          TrackEditTarget.learningSegment);
      expect(hits.editTargetAt(Offset(xAt(10000), beatRowY)), isNull);
    });

    test('备注片段只在学习段命中为空时、且仅在备注行内算编辑内容', () {
      final notes = const [NoteSticker(startMs: 20000, endMs: 25000, text: 'x')];
      final hits = hitsOf(notes: notes);
      // 备注 [20s, 25s) 按 15s 最小命中宽对称扩到 [15s, 30s)：
      // 10s 在两窗之外、且学习段轨命中为空（首尾线窗 7.5s 之外）→ 空白。
      expect(hits.editTargetAt(Offset(xAt(10000), noteRowY)), isNull);
      // 22.5s 落在备注命中窗内、备注行内。
      expect(hits.editTargetAt(Offset(xAt(22500), noteRowY)),
          TrackEditTarget.noteFragment);
      // 同一列不在备注行 → 不是编辑内容。
      expect(hits.editTargetAt(Offset(xAt(22500), mirrorRowY)), isNull);
      // 备注行的行底那一条线（y=36）不是本行内容 → 不算编辑内容。
      expect(hits.editTargetAt(Offset(xAt(22500), 36)), isNull);
      // 行底之内仍是备注片段。
      expect(hits.editTargetAt(Offset(xAt(22500), 35.999)),
          TrackEditTarget.noteFragment);
      // 学习段轨命中非空时它先答（分段线优先于备注片段）。
      final withLine = hitsOf(timeline: timelineWithLines([22500]), notes: notes);
      expect(withLine.editTargetAt(Offset(xAt(22500), noteRowY)),
          TrackEditTarget.segmentLine);
    });

    test('轨道片头带与带外不是编辑内容', () {
      final hits = hitsOf(notes: const [NoteSticker(startMs: 0, endMs: 60000)]);
      expect(hits.editTargetAt(const Offset(20, noteRowY)), isNull);
      expect(hits.editTargetAt(const Offset(220, noteRowY)), isNull);
    });

    test('几何不可用时安静返回空', () {
      final zeroWidth = hitsOf(width: 0);
      final noDuration = hitsOf(totalDuration: null);
      final zeroDuration = hitsOf(totalDuration: Duration.zero);
      for (final hits in [zeroWidth, noDuration, zeroDuration]) {
        expect(hits.editTargetAt(Offset(xAt(30000), learningRowY)), isNull);
        expect(hits.editTargetAt(Offset(xAt(10000), noteRowY)), isNull);
      }
    });
  });

  group('行归属委派轨道行表', () {
    test('行归属与行表逐位一致（含两端口径），几何不可用时为空', () {
      final hits = hitsOf();
      for (final dy in const <double>[
        -1, 0, 1, 35, 36, 37, 40, 45, 46, 60, 76, 77, 80, 86,
        110, 134, 135, 140, 144, 156, 168, 169, 178, 190, 208, 209, 300,
      ]) {
        expect(
          hits.rowAt(dy),
          TrackRowTable.normal.rowAt(dy),
          reason: 'dy=$dy 的行归属须与行表逐位一致',
        );
      }
      expect(hits.rowAt(0), TrackRowId.note);
      expect(hits.rowAt(36), TrackRowId.note);
      expect(hits.rowAt(46), TrackRowId.localMirror);
      expect(hits.rowAt(86), TrackRowId.learning);
      expect(hits.rowAt(144), TrackRowId.beat);
      expect(hits.rowAt(208), TrackRowId.handleStrip);
      expect(hits.rowAt(209), isNull);
      expect(hits.rowAt(40), isNull);

      final noGeometry = hitsOf(width: 0);
      expect(noGeometry.rowAt(110), isNull);
    });

    test('三个行谓词由行归属派生', () {
      final hits = hitsOf();
      expect(hits.isLearningRow(learningRowY), isTrue);
      expect(hits.isLearningRow(noteRowY), isFalse);
      expect(hits.isNoteRow(noteRowY), isTrue);
      expect(hits.isNoteRow(mirrorRowY), isFalse);
      expect(hits.isMirrorRow(mirrorRowY), isTrue);
      expect(hits.isMirrorRow(learningRowY), isFalse);
      // 行间隙（40）不属于任何行。
      expect(hits.isLearningRow(40), isFalse);
      expect(hits.isNoteRow(40), isFalse);
      expect(hits.isMirrorRow(40), isFalse);
      // 备注轨行的内容口径是半开盒：行底（36）那一条线不算本行内容——
      // 行归属仍按行表判为备注轨（含两端），两者各管一层。
      expect(hits.rowAt(36), TrackRowId.note);
      expect(hits.isNoteRow(36), isFalse);
      expect(hits.isNoteRow(35.999), isTrue);
    });

    test('剪掉空轨后的行表：被剪掉的行不再是命中行，其原位归给下一行', () {
      // 紧凑档剪掉空备注轨与空局部镜像轨后的行序：学习段 0–48、
      // 节拍 58–82、手柄带 92–122。
      final hits = hitsOf(
        rowTable: TrackRowTable.normal.withoutRows(const {
          TrackRowId.note,
          TrackRowId.localMirror,
        }),
      );
      expect(hits.isNoteRow(noteRowY), isFalse);
      expect(hits.isMirrorRow(noteRowY), isFalse);
      expect(hits.rowAt(noteRowY), TrackRowId.learning);
      expect(hits.isLearningRow(noteRowY), isTrue);
      expect(hits.isMirrorRow(mirrorRowY), isFalse);
      expect(hits.rowAt(mirrorRowY), TrackRowId.beat);
      expect(hits.rowAt(0), TrackRowId.learning);
      expect(hits.rowAt(48), TrackRowId.learning);
      expect(hits.rowAt(58), TrackRowId.beat);
      expect(hits.rowAt(122), TrackRowId.handleStrip);
      expect(hits.rowAt(122.5), isNull);
    });

    test('行缺席即内容不在命中对象里：同一落点剪裁前是备注片段、剪裁后为空', () {
      const fragment = NoteSticker(startMs: 20000, endMs: 25000, text: '注意手');
      final local = Offset(xAt(20000), noteRowY);
      expect(
        hitsOf(notes: const [fragment]).editTargetAt(local),
        TrackEditTarget.noteFragment,
      );
      expect(
        hitsOf(
          notes: const [fragment],
          rowTable: TrackRowTable.normal.withoutRows(const {
            TrackRowId.note,
            TrackRowId.localMirror,
          }),
        ).editTargetAt(local),
        isNull,
      );
    });
  });

  group('学习段命中次序解析', () {
    // 线在 20s/40s → 段 = [0,20s) 0 序、[20s,40s) 1 序、[40s,60s) 2 序。
    final threeSegments = timelineWithLines([20000, 40000]);

    test('单击解析：段体命中给出段序，段线命中不给出段序（线 > 段体）', () {
      final hits = hitsOf(timeline: threeSegments);
      expect(hits.learningHitOrderAt(Offset(xAt(10000), learningRowY)),
          (order: 0, spanClamped: false));
      expect(hits.learningHitOrderAt(Offset(xAt(30000), learningRowY)),
          (order: 1, spanClamped: false));
      // 段线上：单击那一份认线不认段体（该解析只答段序）。
      expect(hits.learningHitOrderAt(Offset(xAt(20000), learningRowY)),
          (order: null, spanClamped: false));
    });

    test('段体那一份跨过分段线不停顿', () {
      final hits = hitsOf(timeline: threeSegments);
      expect(
        hits.learningHitOrderAt(
          Offset(xAt(20000), learningRowY),
          segmentBodyOnly: true,
        ),
        (order: 1, spanClamped: false),
      );
      expect(
        hits.learningHitOrderAt(
          Offset(xAt(25000), learningRowY),
          segmentBodyOnly: true,
        ),
        (order: 1, spanClamped: false),
      );
    });

    test('落点钳在首/末段时给出 spanClamped', () {
      final hits = hitsOf(timeline: threeSegments);
      expect(
        hits.learningHitOrderAt(
          Offset(xAt(0), learningRowY),
          segmentBodyOnly: true,
        ),
        (order: 0, spanClamped: true),
      );
      expect(
        hits.learningHitOrderAt(
          Offset(xAt(40000), learningRowY),
          segmentBodyOnly: true,
        ),
        (order: 2, spanClamped: true),
      );
      expect(
        hits.learningHitOrderAt(
          Offset(xAt(10000), learningRowY),
          segmentBodyOnly: true,
        ),
        (order: 0, spanClamped: false),
      );
    });

    test('学习行外与区间外都是空命中', () {
      final hits = hitsOf(timeline: threeSegments);
      expect(hits.learningHitOrderAt(Offset(xAt(10000), beatRowY)),
          (order: null, spanClamped: false));
      // 右缘 = 区间右端（开判定）。
      expect(hits.learningHitOrderAt(Offset(bandWidth, learningRowY)),
          (order: null, spanClamped: false));
    });

    test('带内局部落点解析：横向钳回带内后按段体解析', () {
      final hits = hitsOf(timeline: threeSegments);
      // 带左之外钳到 0 → 首段段首。
      expect(hits.learningHitResolve(const Offset(-50, learningRowY)),
          (order: 0, atSpanEdge: true));
      expect(hits.learningHitResolve(Offset(xAt(30000), learningRowY)),
          (order: 1, atSpanEdge: false));
      // 学习行外为空。
      expect(hits.learningHitResolve(Offset(xAt(30000), beatRowY)),
          (order: null, atSpanEdge: false));
      // 远超右缘钳到带内右缘（收进 0.01px：区间右端开判定仍可达）→ 末段。
      expect(hits.learningHitResolve(const Offset(1000, learningRowY)),
          (order: 2, atSpanEdge: true));
    });

    test('几何不可用时安静返回空', () {
      final hits = hitsOf(timeline: threeSegments, width: 0);
      expect(hits.learningHitOrderAt(Offset(xAt(10000), learningRowY)),
          (order: null, spanClamped: false));
      expect(hits.learningHitResolve(Offset(xAt(10000), learningRowY)),
          (order: null, atSpanEdge: false));
    });
  });

  group('最近段线解析', () {
    test('密集线取最近一条；未命中回落兜底下标', () {
      // 线在 20s/25s：7.5s 命中窗内两条同时候选，取横向更近的那条。
      final hits = hitsOf(timeline: timelineWithLines([20000, 25000]));
      expect(hits.nearestSegmentLineIndex(xAt(22000)), 0);
      expect(hits.nearestSegmentLineIndex(xAt(24000)), 1);
      // 35s 距两条线都超过 7.5s → 未命中。
      expect(hits.nearestSegmentLineIndex(xAt(35000)), isNull);
      expect(hits.nearestSegmentLineOrFallback(7, xAt(35000)), 7);
      expect(hits.nearestSegmentLineOrFallback(7, xAt(24000)), 1);
    });

    test('几何不可用时安静回落到兜底下标', () {
      final hits = hitsOf(timeline: timelineWithLines([20000, 25000]), width: 0);
      expect(hits.nearestSegmentLineIndex(xAt(22000)), isNull);
      expect(hits.nearestSegmentLineOrFallback(3, xAt(22000)), 3);
    });
  });

  group('局部镜像轨内容命中经域公开入口', () {
    test('镜像行内片段命中为真；非镜像行与片段外为假', () {
      final hits = hitsOf(
        mirrorFragments: const [LocalMirrorFragment(startMs: 30000, endMs: 40000)],
      );
      expect(hits.mirrorContentAt(Offset(xAt(30000), mirrorRowY)), isTrue);
      expect(hits.mirrorContentAt(Offset(xAt(30000), learningRowY)), isFalse);
      expect(hits.mirrorContentAt(Offset(xAt(22500), mirrorRowY)), isFalse);
      expect(hits.mirrorContentAt(Offset(xAt(30000), noteRowY)), isFalse);
    });

    test('几何不可用时安静返回假', () {
      final hits = hitsOf(
        mirrorFragments: const [LocalMirrorFragment(startMs: 30000, endMs: 40000)],
        width: 0,
      );
      expect(hits.mirrorContentAt(Offset(xAt(30000), mirrorRowY)), isFalse);
    });
  });
}
