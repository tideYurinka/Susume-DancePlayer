import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/player/segment_jump.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const start = Duration.zero;
  const end = Duration(minutes: 3);

  group('threeFingerJumpTarget（纯函数）', () {
    test('无分段线：左滑跳视频首、右滑跳视频尾', () {
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.left,
          currentPosition: const Duration(minutes: 1),
          segmentLines: const [],
          videoStart: start,
          videoEnd: end,
        ),
        start,
      );
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 1),
          segmentLines: const [],
          videoStart: start,
          videoEnd: end,
        ),
        end,
      );
    });

    test('左滑跳到当前位置左侧最近的分段线', () {
      const lines = [
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 5),
      ];
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.left,
          currentPosition: const Duration(minutes: 4),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 2),
      );
    });

    test('右滑跳到当前位置右侧最近的分段线', () {
      const lines = [
        Duration(minutes: 1),
        Duration(minutes: 2),
        Duration(minutes: 5),
      ];
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 4),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 5),
      );
    });

    test('当前位置恰好在分段线上：左滑取严格更左、右滑取严格更右', () {
      const lines = [Duration(minutes: 1), Duration(minutes: 3)];
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.left,
          currentPosition: const Duration(minutes: 3),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 1),
      );
      // 3 右侧无分段线 → 回退视频尾。
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 3),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        end,
      );
    });

    test('滑动方向无分段线时回退视频首/尾', () {
      const lines = [Duration(minutes: 1), Duration(minutes: 2)];
      // 当前位置在第一条线左侧：左滑无更左的线 → 视频首。
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.left,
          currentPosition: const Duration(seconds: 30),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        start,
      );
      // 当前位置在最后一条线右侧：右滑无更右的线 → 视频尾。
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 5),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        end,
      );
    });

    test('分段线输入乱序时按升序处理', () {
      const lines = [
        Duration(minutes: 5),
        Duration(minutes: 1),
        Duration(minutes: 3),
      ];
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 2),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 3),
      );
    });

    test('接缝：segmentLinePositions 从标注时间线取分段线位置', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: end,
        rangeStart: const Duration(seconds: 10),
        rangeEnd: const Duration(minutes: 2, seconds: 50),
        segmentLines: const [
          SegmentLine(position: Duration(minutes: 2)),
          SegmentLine(position: Duration(seconds: 30)),
          SegmentLine(position: Duration(minutes: 1)),
        ],
      );
      // 升序返回时间线内全部分段线位置（首/尾边界不是分段线，不出现）。
      expect(segmentLinePositions(timeline), const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
      ]);
      expect(segmentLinePositions(AnnotationTimeline.wholeVideo(end)), isEmpty);
    });

    test('接缝：flaggedSegmentLinePositions 只取标记过的分段线，无标记返回空表', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: end,
        segmentLines: const [
          SegmentLine(position: Duration(seconds: 30)),
          SegmentLine(position: Duration(minutes: 1), flagged: true),
          SegmentLine(position: Duration(minutes: 2)),
          SegmentLine(
            position: Duration(minutes: 2, seconds: 30),
            flagged: true,
          ),
        ],
      );
      expect(flaggedSegmentLinePositions(timeline), const [
        Duration(minutes: 1),
        Duration(minutes: 2, seconds: 30),
      ]);
      expect(
        flaggedSegmentLinePositions(
          AnnotationTimeline.normalized(
            videoDuration: end,
            segmentLines: const [SegmentLine(position: Duration(seconds: 30))],
          ),
        ),
        isEmpty,
      );
    });

    test('混合集合只跳标记线：未标记线对跳转隐形', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: end,
        segmentLines: const [
          SegmentLine(position: Duration(minutes: 1), flagged: true),
          SegmentLine(position: Duration(minutes: 2)),
          SegmentLine(
            position: Duration(minutes: 2, seconds: 50),
            flagged: true,
          ),
        ],
      );
      final lines = flaggedSegmentLinePositions(timeline);
      // 右滑：右侧最近的线是未标记的 2:00 → 跳过，落到标记线 2:50。
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 1, seconds: 30),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 2, seconds: 50),
        reason: '右侧未标记线（2:00）不成为目标',
      );
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.left,
          currentPosition: const Duration(minutes: 2, seconds: 30),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 1),
        reason: '左侧未标记线（2:00）不成为目标',
      );
    });

    test('恰好站在标记线上：经标记线投影左滑取严格更左、右滑取严格更右', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: end,
        segmentLines: const [
          SegmentLine(position: Duration(minutes: 1), flagged: true),
          SegmentLine(position: Duration(minutes: 2), flagged: true),
        ],
      );
      final lines = flaggedSegmentLinePositions(timeline);
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.left,
          currentPosition: const Duration(minutes: 2),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        const Duration(minutes: 1),
      );
      // 2:00 右侧无标记线 → 回退视频尾。
      expect(
        threeFingerJumpTarget(
          direction: ThreeFingerSwipeDirection.right,
          currentPosition: const Duration(minutes: 2),
          segmentLines: lines,
          videoStart: start,
          videoEnd: end,
        ),
        end,
      );
    });
  });
}
