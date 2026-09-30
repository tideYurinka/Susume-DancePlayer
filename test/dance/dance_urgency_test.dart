import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页紧急层与单枚角标纯件直测：紧急度求值、
/// 组合排序的逾期置顶与稳定次序、角标取值优先级。零 IO，时钟经 now 注入。
void main() {
  final now = DateTime(2026, 9, 20, 15);

  group('紧急度求值', () {
    test('无 DDL（未设或已清除）不带紧急度', () {
      expect(
        danceUrgencyOf(
          dueDay: null,
          settledOnTime: false,
          fullyMastered: false,
          now: now,
        ),
        isNull,
      );
    });

    test('未过未达成：到期日带出，未逾期', () {
      final urgency = danceUrgencyOf(
        dueDay: DateTime(2026, 10, 1),
        settledOnTime: false,
        fullyMastered: false,
        now: now,
      );
      expect(
        urgency,
        DanceUrgency(
          dueDay: DateTime(2026, 10, 1),
          overdue: false,
          achieved: false,
        ),
      );
    });

    test('今天到期整天不算逾期（剩余 0）', () {
      final urgency = danceUrgencyOf(
        dueDay: DateTime(2026, 9, 20),
        settledOnTime: false,
        fullyMastered: false,
        now: now,
      );
      expect(urgency!.overdue, isFalse);
    });

    test('昨天到期 = 逾期', () {
      final urgency = danceUrgencyOf(
        dueDay: DateTime(2026, 9, 19),
        settledOnTime: false,
        fullyMastered: false,
        now: now,
      );
      expect(urgency!.overdue, isTrue);
    });

    test('落档按时 = 已达成，不再带紧急度', () {
      expect(
        danceUrgencyOf(
          dueDay: DateTime(2026, 9, 1),
          settledOnTime: true,
          fullyMastered: false,
          now: now,
        ),
        isNull,
      );
    });

    test('落档逾期：历史仍显示逾期（带紧急度、逾期为真）', () {
      final urgency = danceUrgencyOf(
        dueDay: DateTime(2026, 9, 1),
        settledOnTime: false,
        fullyMastered: false,
        now: now,
      );
      expect(urgency!.overdue, isTrue);
    });

    test('完全掌握 = 目标已达成，不再带紧急度', () {
      expect(
        danceUrgencyOf(
          dueDay: DateTime(2026, 10, 1),
          settledOnTime: false,
          fullyMastered: true,
          now: now,
        ),
        isNull,
      );
    });
  });

  group('组合排序', () {
    DanceLibrarySnapshot snapshot(
      List<String> ids,
      Map<String, (DateTime, bool)> goals,
    ) {
      return composeDanceLibrarySnapshot(
        index: VideoIndex(entries: [for (final id in ids) _entry(videoId: id)]),
        markersByVideoId: const {},
        localByVideoId: const {},
        practiceByVideoId: const {},
        planGoalByVideoId: goals,
        now: now,
      );
    }

    test('逾期置顶（目标日升序）→ 未过按剩余自然日升序 → 无目标落回既有次序', () {
      final result = snapshot(
        ['plain-a', 'future-5', 'overdue-long', 'future-2', 'overdue-recent'],
        {
          // 目标日（即剩余自然日的序）：逾期组内久的在前；未过组近的在前。
          'overdue-long': (DateTime(2026, 9, 10), false),
          'overdue-recent': (DateTime(2026, 9, 19), false),
          'future-2': (DateTime(2026, 9, 22), false),
          'future-5': (DateTime(2026, 9, 25), false),
        },
      );

      expect(
        [for (final dance in result.dances) dance.videoId],
        ['overdue-long', 'overdue-recent', 'future-2', 'future-5', 'plain-a'],
      );
    });

    test('同目标日并列：落回既有次序（最近练习倒序，未练按导入序）', () {
      final result = snapshot(
        ['u-early-import', 'u-late-import', 'plain'],
        {
          'u-late-import': (DateTime(2026, 9, 25), false),
          'u-early-import': (DateTime(2026, 9, 25), false),
        },
      );

      // 两支未练的紧急舞同日：导入序倒序（后导入在前）；无目标者垫底。
      expect(
        [for (final dance in result.dances) dance.videoId],
        ['u-late-import', 'u-early-import', 'plain'],
      );
    });

    test('已按时达成与已清除 DDL 的舞不带紧急度、不参与置顶', () {
      final result = snapshot(
        ['settled', 'plain'],
        {
          // 已按时落档：紧急度求值为 null，不参与置顶。
          'settled': (DateTime(2026, 9, 1), true),
        },
      );

      // 两支都无紧急度：落回既有次序。
      expect(
        [for (final dance in result.dances) dance.videoId],
        ['plain', 'settled'],
      );
      expect(result.dances.last.urgency, isNull);
    });
  });

  group('单枚角标取值', () {
    DanceSnapshot danceOf({
      DateTime? dueDay,
      bool settledOnTime = false,
      bool fullyMastered = false,
    }) {
      return composeDanceSnapshot(
        entry: _entry(),
        importOrder: 0,
        markers: fullyMastered
            ? MarkersDocument(
                rangeStartMs: 10000,
                rangeEndMs: 120000,
                segmentLines: const [
                  SegmentLine(position: Duration(seconds: 60)),
                ],
              )
            : const MarkersDocument.empty(),
        local: fullyMastered
            ? const LocalDocument(
                mastery: {
                  0: LearningMastery.mastered,
                  1: LearningMastery.mastered,
                },
              )
            : const LocalDocument.empty(),
        practice: const DancePracticeTotals(),
        planDueDay: dueDay,
        planSettledOnTime: settledOnTime,
        now: now,
      );
    }

    test('逾期 > 临期：昨天到期出逾期标', () {
      final badge = danceCardBadgeOf(
        danceOf(dueDay: DateTime(2026, 9, 19)),
        now: now,
      );
      expect(badge, DanceCardBadge.overdue);
    });

    test('剩余 0–3 天出临期标', () {
      for (final offset in const [0, 3]) {
        expect(
          danceCardBadgeOf(
            danceOf(dueDay: DateTime(2026, 9, 20 + offset)),
            now: now,
          ),
          DanceCardBadge.nearDeadline,
          reason: '剩余 $offset 天',
        );
      }
    });

    test('无目标且未完全掌握不出角标', () {
      expect(danceCardBadgeOf(danceOf(), now: now), isNull);
    });

    test('无目标但完全掌握出完成勾', () {
      expect(
        danceCardBadgeOf(danceOf(fullyMastered: true), now: now),
        DanceCardBadge.mastered,
      );
    });

    test('完全掌握的舞不带 DDL 紧急度，角标为完成勾而非临期/逾期', () {
      final badge = danceCardBadgeOf(
        danceOf(dueDay: DateTime(2026, 9, 19), fullyMastered: true),
        now: now,
      );
      expect(badge, DanceCardBadge.mastered);
    });
  });
}

VideoIndexEntry _entry({String videoId = 'v1'}) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
