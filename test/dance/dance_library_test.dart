import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';

/// 舞库纯值层直测：断言合成后的卡片量、派生口径与排序结果，不断言内部
/// 结构、缓存或调用次序。
void main() {
  group('卡片量合成', () {
    test('四处输入齐备：卡片量字段齐全', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(signatureCache: const SongSignature(song: '缓存名')),
        importOrder: 0,
        markers: _markers(
          signature: const SongSignature(dancer: '如', song: '真值名'),
          rangeStartMs: 10000,
          rangeEndMs: 120000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        local: const LocalDocument(
          mastery: {0: LearningMastery.mastered, 1: LearningMastery.keepingUp},
        ),
        practice: DancePracticeTotals(
          total: const Duration(minutes: 3),
          lastPracticedAt: DateTime(2026, 9, 10),
        ),
      );

      expect(snapshot.title, '「如」真值名');
      expect(snapshot.masteryPercent, 75.0);
      expect(snapshot.fullyMastered, isFalse);
      expect(snapshot.practiceTotal, const Duration(minutes: 3));
      expect(snapshot.lastPracticedAt, DateTime(2026, 9, 10));
      expect(snapshot.coverPosition, const Duration(seconds: 10));
      expect(snapshot.urgency, isNull);
    });

    test('缺文档的舞按未标注处理：无百分比、无完成勾、标题回退索引署名缓存', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(signatureCache: const SongSignature(song: '缓存名')),
        importOrder: 0,
        markers: const MarkersDocument.empty(),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.masteryPercent, isNull);
      expect(snapshot.fullyMastered, isFalse);
      expect(snapshot.title, '缓存名');
      expect(snapshot.coverPosition, Duration.zero);
      // 无缓存图片 = 未就绪（渲染占位图）。
      expect(snapshot.coverReady, isFalse);
    });

    test('缺统计的舞按零时长、无最近练习兜底', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeEndMs: 60000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.practiceTotal, Duration.zero);
      expect(snapshot.lastPracticedAt, isNull);
    });

    test('既无署名真值也无缓存：标题回退「文件名回落名」（去扩展名）', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(displayName: 'a.b.mp4'),
        importOrder: 0,
        markers: const MarkersDocument.empty(),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      // 只验这一处确实过纯件（去最后一个点及其之后），规则本身在
      // `song_signature_test.dart` 验过。
      expect(snapshot.title, 'a.b');
    });
  });

  group('封面引用（位置 + 是否就绪）', () {
    test('位置缺省：跟随首线（有效区间起点）', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeStartMs: 10000, rangeEndMs: 120000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.coverPosition, const Duration(seconds: 10));
    });

    test('位置已落盘：读面取该位置，不跟随首线', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeStartMs: 10000,
          rangeEndMs: 120000,
          coverPositionMs: 42000,
        ),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.coverPosition, const Duration(seconds: 42));
    });

    test('无有效区间的舞：缺省位置落在视频第 0 帧', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.coverPosition, Duration.zero);
    });

    test('已就绪：卡片量带就绪标记（真图）；未就绪为占位图', () {
      final ready = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeEndMs: 120000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
        readyAspectRatio: 4 / 3,
      );
      final placeheld = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeEndMs: 120000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(ready.coverReady, isTrue);
      expect(ready.coverAspectRatio, 4 / 3);
      expect(placeheld.coverReady, isFalse);
      expect(placeheld.coverAspectRatio, 3 / 4);
      // 就绪标记参与读面相等性：页面据此从占位图换成真图。
      expect(ready, isNot(placeheld));
    });

    test('整库入口按就绪比例逐舞标记：就绪给图片比例，未就绪 3:4', () {
      final snapshot = composeDanceLibrarySnapshot(
        index: VideoIndex(
          entries: [
            _entry(videoId: 'v1'),
            _entry(videoId: 'v2'),
          ],
        ),
        markersByVideoId: const {},
        localByVideoId: const {},
        practiceByVideoId: const {},
        coverAspectRatios: const {'v2': 4 / 3},
      );

      final byId = {for (final dance in snapshot.dances) dance.videoId: dance};
      expect(byId['v1']!.coverReady, isFalse);
      expect(byId['v1']!.coverAspectRatio, 3 / 4);
      expect(byId['v2']!.coverReady, isTrue);
      expect(byId['v2']!.coverAspectRatio, 4 / 3);
    });
  });

  group('熟练度百分比', () {
    test('有段：学习段档位值均值 × 25（不取整）', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 120000,
          segmentLines: const [
            SegmentLine(position: Duration(seconds: 40)),
            SegmentLine(position: Duration(seconds: 80)),
          ],
        ),
        local: const LocalDocument(
          mastery: {
            0: LearningMastery.mastered,
            1: LearningMastery.familiar,
            2: LearningMastery.unlearned,
          },
        ),
        practice: const DancePracticeTotals(),
      );

      // (4 + 3 + 0) / 3 × 25 = 58.333…
      expect(snapshot.masteryPercent, closeTo(58.3333, 0.001));
    });

    test('无段：不显示百分比', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeEndMs: 120000),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.masteryPercent, isNull);
    });

    test('部分段缺项：缺项按未练计入均值', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 120000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        practice: const DancePracticeTotals(),
      );

      // (4 + 0) / 2 × 25 = 50
      expect(snapshot.masteryPercent, 50.0);
    });

    test('有段但无本地私密文件：全段按未练，百分比为 0', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 120000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.masteryPercent, 0.0);
    });
  });

  group('完全掌握', () {
    test('全段最高档成立', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 120000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        local: const LocalDocument(
          mastery: {0: LearningMastery.mastered, 1: LearningMastery.mastered},
        ),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.fullyMastered, isTrue);
      expect(snapshot.masteryPercent, 100.0);
    });

    test('空段集不成立（熟练度表有值也不算）', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeEndMs: 120000),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.fullyMastered, isFalse);
    });

    test('缺项按未练：任一段未置最高档不成立', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 120000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 60))],
        ),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.fullyMastered, isFalse);
    });
  });

  group('详情量：平均练习遍数', () {
    test('有有效区间：累计墙钟练习时长 ÷ 有效区间时长', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeStartMs: 10000, rangeEndMs: 130000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(total: Duration(minutes: 3)),
      );

      // 180s ÷ 120s = 1.5 遍。
      expect(snapshot.averagePracticeCount, 1.5);
    });

    test('无有效区间（未落盘）：显示 —（null）', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(total: Duration(hours: 2)),
      );

      expect(snapshot.averagePracticeCount, isNull);
    });

    test('零长有效区间：显示 —（null），不用零凑假数', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeStartMs: 5000, rangeEndMs: 5000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(total: Duration(minutes: 3)),
      );

      expect(snapshot.averagePracticeCount, isNull);
    });
  });

  group('平均练习遍数文案（卡片与详情共用）', () {
    test('无值显示 —；整数不带小数位；非整数一位小数', () {
      expect(averagePracticeCountText(null), '—');
      expect(averagePracticeCountText(2), '2 遍');
      expect(averagePracticeCountText(1.5), '1.5 遍');
      expect(averagePracticeCountText(1.25), '1.3 遍');
    });
  });

  group('详情量：逐段列表', () {
    test('段号 / 时长 / 档位按段序对齐；缺项按未练，网格未落盘不出八拍区间', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeStartMs: 10000,
          rangeEndMs: 130000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 70))],
        ),
        local: const LocalDocument(mastery: {0: LearningMastery.mastered}),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.segments, hasLength(2));
      final first = snapshot.segments[0];
      expect(first.order, 0);
      expect(first.start, const Duration(seconds: 10));
      expect(first.end, const Duration(seconds: 70));
      expect(first.mastery, LearningMastery.mastered);
      expect(first.eightBeatRange, isNull);

      final second = snapshot.segments[1];
      expect(second.order, 1);
      expect(second.mastery, LearningMastery.unlearned);
      expect(second.eightBeatRange, isNull);
    });

    test('无分段线：逐段列表为空', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(rangeEndMs: 120000),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect(snapshot.segments, isEmpty);
    });
  });

  group('详情量：八拍区间', () {
    test('网格就绪：该段覆盖的八拍点闭区间（全曲时间序，1 起）', () {
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 24000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
          beat: uniformDownbeatGridDoc(seconds: 24),
        ),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      // 八拍点 = 0/4/8/12/16/20/24s（每 8 拍一个）：段 0 覆盖八拍 1–2、
      // 段 1 覆盖八拍 3–6。
      expect(
        snapshot.segments[0].eightBeatRange,
        const DanceEightBeatRange(first: 1, last: 2),
      );
      expect(
        snapshot.segments[1].eightBeatRange,
        const DanceEightBeatRange(first: 3, last: 6),
      );
    });

    test('网格未就绪：八拍区间为 null（不显示编出来的八拍号）', () {
      for (final markers in [
        // 未分析（无 beat 段）。
        _markers(
          rangeEndMs: 24000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
        ),
        // beat 段落盘但拍点为空（退化网格）。
        _markers(
          rangeEndMs: 24000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 8))],
          beat: BeatGrid(model: 'm', fps: 100, generatedAt: DateTime.utc(2024)),
        ),
      ]) {
        final snapshot = composeDanceSnapshot(
          entry: _entry(),
          importOrder: 0,
          markers: markers,
          local: const LocalDocument.empty(),
          practice: const DancePracticeTotals(),
        );

        expect([
          for (final segment in snapshot.segments) segment.eightBeatRange,
        ], everyElement(isNull));
      }
    });

    test('弱起段：与段相交的八拍计入区间；整段早于首个八拍点才不显示', () {
      // 弱起网格：首个强拍在拍序号 4（2s），八拍点 = 2/6/10s——八拍 #1 =
      // [2s,6s)、#2 = [6s,10s)。
      final pickup = BeatGrid(
        model: 'm',
        fps: 100,
        generatedAt: DateTime.utc(2024),
        beats: [
          for (var i = 0; i <= 28; i++)
            BeatPoint(t: i * 0.5, down: i >= 4 && (i - 4) % 4 == 0),
        ],
      );
      final covered = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 10000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 6))],
          beat: pickup,
        ),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      // 段首落在首个八拍点之前，但八拍 #1 整体落在段 [0,6s] 内 → 照样计入。
      expect(
        covered.segments[0].eightBeatRange,
        const DanceEightBeatRange(first: 1, last: 1),
      );
      expect(
        covered.segments[1].eightBeatRange,
        const DanceEightBeatRange(first: 2, last: 2),
      );

      // 整段落在首个八拍点（2s）之前：与任何八拍都不相交 → 不显示。
      final before = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 1000,
          segmentLines: const [
            SegmentLine(position: Duration(milliseconds: 500)),
          ],
          beat: pickup,
        ),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      expect([
        for (final segment in before.segments) segment.eightBeatRange,
      ], everyElement(isNull));
    });

    test('八拍锚点重定相：区间经相位源重算（不自行实现相位）', () {
      // 锚点 = 拍序号 12（6s）：其后八拍点改为 6/10/14s。
      final snapshot = composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: _markers(
          rangeEndMs: 14000,
          segmentLines: const [SegmentLine(position: Duration(seconds: 10))],
          beat: uniformDownbeatGridDoc(seconds: 14, anchors: const [12]),
        ),
        local: const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
      );

      // 相位点 = 0/4/6/10/14s：段 0 覆盖 1–3、段 1 覆盖 4–4；无锚点时
      // 第二段会算成 3–4（回归对照见上一用例的均匀网格）。
      expect(
        snapshot.segments[0].eightBeatRange,
        const DanceEightBeatRange(first: 1, last: 3),
      );
      expect(
        snapshot.segments[1].eightBeatRange,
        const DanceEightBeatRange(first: 4, last: 4),
      );
    });
  });

  group('逐段熟练度取值（改档的作用对象）', () {
    test('of：捕获当前档位、未练不入表，段序表与段集对齐', () {
      final values = DanceMasteryValues.of(const [
        DanceSegmentDetail(
          order: 0,
          start: Duration.zero,
          end: Duration(seconds: 8),
          mastery: LearningMastery.familiar,
          eightBeatRange: null,
        ),
        DanceSegmentDetail(
          order: 1,
          start: Duration(seconds: 8),
          end: Duration(seconds: 16),
          mastery: LearningMastery.unlearned,
          eightBeatRange: null,
        ),
      ]);

      expect(values.orders, const [0, 1]);
      expect(values.mastery, const {0: LearningMastery.familiar});
    });

    test('allMastered：同一段序表全部最高档', () {
      const values = DanceMasteryValues(orders: [0, 1, 2]);

      expect(
        values.allMastered,
        const DanceMasteryValues(
          orders: [0, 1, 2],
          mastery: {
            0: LearningMastery.mastered,
            1: LearningMastery.mastered,
            2: LearningMastery.mastered,
          },
        ),
      );
    });
  });

  group('整库快照与排序', () {
    test('最近练习倒序；从未练过者按导入时间倒序尾排', () {
      // 索引列表位置即导入次序（0 = 最早导入）。
      final snapshot = composeDanceLibrarySnapshot(
        index: VideoIndex(
          entries: [
            _entry(videoId: 'practiced-early'),
            _entry(videoId: 'never-old', lastOpenedAt: DateTime(2026, 9, 9)),
            _entry(videoId: 'never-new', lastOpenedAt: DateTime(2026, 9, 1)),
            _entry(videoId: 'practiced-late'),
          ],
        ),
        markersByVideoId: const {},
        localByVideoId: const {},
        practiceByVideoId: {
          'practiced-early': DancePracticeTotals(
            total: const Duration(minutes: 10),
            lastPracticedAt: DateTime(2026, 9, 10),
          ),
          'practiced-late': DancePracticeTotals(
            total: const Duration(minutes: 20),
            lastPracticedAt: DateTime(2026, 9, 12),
          ),
        },
      );

      // 未练组按导入次序倒序（后导入在前），不受打开刷新的最近打开时间影响。
      expect(
        [for (final dance in snapshot.dances) dance.videoId],
        ['practiced-late', 'practiced-early', 'never-new', 'never-old'],
      );
    });

    test('舞附件列表次序：最近打开倒序，并列保持传入原序', () {
      DanceSnapshot dance(String videoId, DateTime opened) =>
          composeDanceSnapshot(
            entry: _entry(videoId: videoId, lastOpenedAt: opened),
            importOrder: 0,
            markers: const MarkersDocument.empty(),
            local: const LocalDocument.empty(),
            practice: const DancePracticeTotals(),
          );

      final tied = DateTime(2026, 9, 15);
      final ordered = dancesByRecentOpen([
        dance('old', DateTime(2026, 9, 1)),
        dance('new', DateTime(2026, 9, 20)),
        dance('tie-a', tied),
        dance('tie-b', tied),
      ]);

      expect(
        [for (final item in ordered) item.videoId],
        ['new', 'tie-a', 'tie-b', 'old'],
      );
    });

    test('列表口径 = 索引条目：未落条目的舞不出现，已删视频的历史统计不进列表', () {
      final snapshot = composeDanceLibrarySnapshot(
        index: VideoIndex(entries: [_entry(videoId: 'kept')]),
        markersByVideoId: const {'kept': MarkersDocument.empty()},
        localByVideoId: const {'kept': LocalDocument.empty()},
        practiceByVideoId: {
          'kept': DancePracticeTotals(
            total: const Duration(minutes: 5),
            lastPracticedAt: DateTime(2026, 9, 10),
          ),
          'deleted': DancePracticeTotals(
            total: const Duration(minutes: 99),
            lastPracticedAt: DateTime(2026, 9, 11),
          ),
        },
      );

      expect(snapshot.dances, hasLength(1));
      expect(snapshot.dances.single.videoId, 'kept');
    });

    test('紧急度留位：无 DDL 即无紧急度', () {
      final snapshot = composeDanceLibrarySnapshot(
        index: VideoIndex(entries: [_entry(videoId: 'v1')]),
        markersByVideoId: const {},
        localByVideoId: const {},
        practiceByVideoId: const {},
      );

      expect(snapshot.dances.single.urgency, isNull);
    });

    test('紧急度输入：计划目标在合成快照处接线', () {
      final now = DateTime(2026, 9, 20, 15);
      final snapshot = composeDanceLibrarySnapshot(
        index: VideoIndex(entries: [_entry(videoId: 'v1')]),
        markersByVideoId: const {},
        localByVideoId: const {},
        practiceByVideoId: const {},
        planGoalByVideoId: {'v1': (DateTime(2026, 10, 1), false)},
        now: now,
      );

      expect(
        snapshot.dances.single.urgency,
        DanceUrgency(
          dueDay: DateTime(2026, 10, 1),
          overdue: false,
          achieved: false,
        ),
      );
    });
  });
}

VideoIndexEntry _entry({
  String videoId = 'v1',
  String displayName = 'a.mp4',
  SongSignature? signatureCache,
  DateTime? lastOpenedAt,
}) => VideoIndexEntry(
  videoId: videoId,
  displayName: displayName,
  filePath: '/videos/$displayName',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: lastOpenedAt ?? DateTime(2026, 9, 1),
  signatureCache: signatureCache,
);

MarkersDocument _markers({
  SongSignature? signature,
  int? coverPositionMs,
  int rangeStartMs = 0,
  int rangeEndMs = 0,
  List<SegmentLine> segmentLines = const [],
  BeatGrid? beat,
}) => MarkersDocument(
  signature: signature,
  coverPositionMs: coverPositionMs,
  rangeStartMs: rangeStartMs,
  rangeEndMs: rangeEndMs,
  segmentLines: segmentLines,
  beat: beat,
);
