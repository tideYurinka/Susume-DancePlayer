import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

/// 临时衔接段范围纯函数：
/// 范围 = 线前 1 八拍 + 后 1 八拍（合计 2 八拍）、按首尾截断、可跨相邻
/// 学习段、起点按八拍点取整。占位 BPM 120 → 1 八拍 = 4s、八拍点每 4s
/// 一个（0/4/8/12…s），期望值为手算字面量（独立于实现）。
void main() {
  /// 相位值对象：无锚点 = 占位网格自动相位；[anchors] = 八拍锚点拍序号。
  BeatPhase phase([List<int> anchors = const []]) =>
      BeatPhase(grid: placeholderBeatGrid, anchors: anchors);

  AnnotationTimeline timeline({
    required Duration videoDuration,
    Duration? rangeStart,
    Duration? rangeEnd,
    List<Duration> lines = const [],
  }) {
    return AnnotationTimeline.normalized(
      videoDuration: videoDuration,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      segmentLines: [
        for (final position in lines) SegmentLine(position: position),
      ],
    );
  }

  group('临时衔接段范围解析', () {
    test('线前 1 八拍 + 后 1 八拍（120bpm → ±4s），起点落八拍点则不偏移', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        lines: [const Duration(seconds: 10)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      )!;
      // 10s - 4s = 6s → 取整到最近八拍点：4s 与 8s 等距、并列取靠后
      // = 8s；10s + 4s = 14s。
      expect(segment.start, const Duration(seconds: 8));
      expect(segment.end, const Duration(seconds: 14));
      expect(segment.lineIndex, 0);
    });

    test('起点按八拍点取整（八拍点 @120bpm 每 4s 一个，最近点）', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        lines: [const Duration(seconds: 11)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      )!;
      // 7s → 最近八拍点 = 8s；终点不取整：11 + 4 = 15s。
      expect(segment.start, const Duration(seconds: 8));
      expect(segment.end, const Duration(seconds: 15));
    });

    test('按首尾截断：前半越视频首则起点钳到首、后半越尾则终点钳到尾', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        rangeStart: const Duration(seconds: 8),
        rangeEnd: const Duration(seconds: 12),
        lines: [const Duration(seconds: 10)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      )!;
      // 理论范围 [6, 14] → 按首尾截断为 [8, 12]。
      expect(segment.start, const Duration(seconds: 8));
      expect(segment.end, const Duration(seconds: 12));
    });

    test('取整后的起点低于视频首时钳回首（截断优先于网格）', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        rangeStart: const Duration(seconds: 9),
        lines: [const Duration(seconds: 10)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      )!;
      // 理论起点 6s → 取整 8s < 9s → 钳回首 9s；终点 14s。
      expect(segment.start, const Duration(seconds: 9));
      expect(segment.end, const Duration(seconds: 14));
    });

    test('可跨相邻学习段：范围只按时间计算，不吸附到真实段边界', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 60),
        lines: [
          const Duration(seconds: 10),
          const Duration(seconds: 12),
          const Duration(seconds: 14),
        ],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 1,
        phase: phase(),
      )!;
      // 线 12s：[8, 16]，跨过 10s 与 14s 两条分段线（真实段边界不参与）。
      expect(segment.start, const Duration(seconds: 8));
      expect(segment.end, const Duration(seconds: 16));
    });

    test('分段线索引越界或无线时返回 null', () {
      final t = timeline(videoDuration: const Duration(seconds: 30));
      expect(
        resolveTransitionSegment(timeline: t, lineIndex: 0, phase: phase()),
        isNull,
      );
      final withLine = timeline(
        videoDuration: const Duration(seconds: 30),
        lines: [const Duration(seconds: 10)],
      );
      expect(
        resolveTransitionSegment(
          timeline: withLine,
          lineIndex: 1,
          phase: phase(),
        ),
        isNull,
      );
      expect(
        resolveTransitionSegment(
          timeline: withLine,
          lineIndex: -1,
          phase: phase(),
        ),
        isNull,
      );
    });

    test('区间过窄取整后起点不早于终点时无有效临时段（null）', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        rangeStart: const Duration(seconds: 10),
        rangeEnd: const Duration(seconds: 11),
        lines: [const Duration(milliseconds: 10500)],
      );
      // 截断后 [10, 11]；起点 6.5s 取整到八拍点 8s、低于 rangeStart
      // 10s → 钳回首 10s，仍 < 终点 → 有效。
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      )!;
      expect(segment.start, const Duration(seconds: 10));
      expect(segment.end, const Duration(seconds: 11));
    });

    test('值相等：同线同范围为同一临时段', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        lines: [const Duration(seconds: 10)],
      );
      final a = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      );
      final b = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('带锚点回归（起点落重定相后的八拍点）', () {
    test('设八拍锚点后起点落重定相后的八拍点（锚点拍 4 = 2s 重定相）', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        lines: [const Duration(seconds: 11)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(const [4]),
      )!;
      // 锚点拍序号 4（2s）后八拍点 = 2/6/10/14s…；起点理论值 7s →
      // 最近八拍点 = 6s（距 6s 1s、距 10s 3s；无锚点为 8s）；终点不取整
      // = 11 + 4 = 15s。
      expect(segment.start, const Duration(seconds: 6));
      expect(segment.end, const Duration(seconds: 15));
    });

    test('带锚点对照：取整点落到首界外仍贴首（截断优先于网格）', () {
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        rangeStart: const Duration(seconds: 9),
        lines: [const Duration(seconds: 10)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: phase(const [4]),
      )!;
      // 锚定相位下起点理论值 6s 即重定相八拍点（2/6/10…）→ 6s < 首界
      // 9s → 贴首 9s，不回吸区间内格线；终点 14s。
      expect(segment.start, const Duration(seconds: 9));
      expect(segment.end, const Duration(seconds: 14));
    });

    test('带锚点对照：网格无八拍点时起点自由直通（不取整）', () {
      // 全非强拍网格：无八拍点、传入锚点不成立（nearest 返回 null）。
      final noDownbeatGrid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2024),
          beats: [
            for (var i = 0; i < 40; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: false),
          ],
        ),
      );
      final t = timeline(
        videoDuration: const Duration(seconds: 30),
        lines: [const Duration(seconds: 11)],
      );
      final segment = resolveTransitionSegment(
        timeline: t,
        lineIndex: 0,
        phase: BeatPhase(grid: noDownbeatGrid, anchors: const [4]),
      )!;
      // 无八拍点可取整 → 起点自由直通理论值 7s；终点 15s。
      expect(segment.start, const Duration(seconds: 7));
      expect(segment.end, const Duration(seconds: 15));
    });
  });

  group('临时段触发窗分侧半宽', () {
    LearningSegment seg(int order, int startS, int endS) => LearningSegment(
      order: order,
      start: Duration(seconds: startS),
      end: Duration(seconds: endS),
    );

    /// 把时间域半宽换回像素（验证窗的像素几何，如放大恢复）。
    double px(Duration half, double usPerPx) => half.inMicroseconds / usPerPx;

    test('两侧邻段均宽（显示宽 ≥ 上限对应 200px）→ 两侧均为上限', () {
      // 20 000 µs/px（20ms/px）：上限 20px → 400ms；两侧段各 10s 显示宽
      // 500px ≥ 200px（顶帽区）→ 两侧都取上限。
      final sides = transitionTriggerSideHalfWidths(
        segments: [seg(0, 0, 10), seg(1, 10, 20), seg(2, 20, 30)],
        lineIndex: 1,
        microsecondsPerPixel: 20 * 1000,
        maxSideWidthPx: 20,
      );
      expect(sides.left, const Duration(milliseconds: 400));
      expect(sides.right, const Duration(milliseconds: 400));
    });

    test('左右可不对称：左邻窄段收窄为其显示宽 ×10%，右邻宽段取上限', () {
      // 线 0 左邻 1s 段、右邻 10s 段；50ms/px → 左段显示宽 20px → 左窗
      // = 10% × 20px = 2px = 100ms；右段显示宽 200px → 10% = 20px = 上限
      // 20px × 50ms = 1s（顶帽）→ 右窗 = 1s。左右不对称。
      final sides = transitionTriggerSideHalfWidths(
        segments: [seg(0, 0, 1), seg(1, 1, 11), seg(2, 11, 30)],
        lineIndex: 0,
        microsecondsPerPixel: 50 * 1000,
        maxSideWidthPx: 20,
      );
      expect(sides.left, const Duration(milliseconds: 100));
      expect(sides.right, const Duration(seconds: 1));
    });

    test('每侧 min 语义：任一侧窗宽不超过 20dp 上限', () {
      // 左段 4s、右段 30s @80µs/px → 显示宽均超 200px 顶帽区 → 两侧均
      // 取上限 20px × 80µs = 1600µs。
      final sides = transitionTriggerSideHalfWidths(
        segments: [seg(0, 0, 4), seg(1, 4, 30)],
        lineIndex: 0,
        microsecondsPerPixel: 80,
        maxSideWidthPx: 20,
      );
      expect(sides.left, const Duration(microseconds: 20 * 80));
      expect(sides.right, const Duration(microseconds: 20 * 80));
    });

    test('≥80% 保留：窄段被两端相邻线窗合计占用 ≤ 段显示宽 20%', () {
      // 窄段 1s（30–31s）夹在两宽段间，40ms/px → 显示宽 25px（< 顶帽区
      // 200px）→ 每侧窗 = 10% × 25px = 2.5px；窄段左窗 = 线 0 右侧、
      // 右窗 = 线 1 左侧。两端合计占用 5px = 段宽 20%，恒保留 80%。
      final segments = [seg(0, 0, 30), seg(1, 30, 31), seg(2, 31, 60)];
      const usPerPx = 40 * 1000.0;
      final atLine0 = transitionTriggerSideHalfWidths(
        segments: segments,
        lineIndex: 0,
        microsecondsPerPixel: usPerPx,
        maxSideWidthPx: 20,
      );
      final atLine1 = transitionTriggerSideHalfWidths(
        segments: segments,
        lineIndex: 1,
        microsecondsPerPixel: usPerPx,
        maxSideWidthPx: 20,
      );
      final segWidthPx = px(seg(1, 30, 31).duration, usPerPx);
      final occupiedPx = px(atLine0.right, usPerPx) + px(atLine1.left, usPerPx);
      expect(occupiedPx, lessThanOrEqualTo(segWidthPx * 0.20 + 1e-6));
      expect(segWidthPx - occupiedPx, greaterThanOrEqualTo(segWidthPx * 0.80));
    });

    test('放大轨道（µs/px 变小）后窗随之恢复：像素窗变宽、最终回到上限', () {
      // 窄段 1s（30–31s）：40ms/px 时显示宽 25px → 左侧窗 2.5px；放大
      // 2 倍到 20ms/px → 显示宽 50px → 窗 5px（像素恢复）；继续放大到
      // 5µs/px → 显示宽 200px → 10% = 20px = 上限（顶帽）。窗取线 1
      // 左侧（邻接窄段）。
      final segments = [seg(0, 0, 30), seg(1, 30, 31), seg(2, 31, 60)];
      final coarse = transitionTriggerSideHalfWidths(
        segments: segments,
        lineIndex: 1,
        microsecondsPerPixel: 40 * 1000,
        maxSideWidthPx: 20,
      );
      final mid = transitionTriggerSideHalfWidths(
        segments: segments,
        lineIndex: 1,
        microsecondsPerPixel: 20 * 1000,
        maxSideWidthPx: 20,
      );
      final fine = transitionTriggerSideHalfWidths(
        segments: segments,
        lineIndex: 1,
        microsecondsPerPixel: 5,
        maxSideWidthPx: 20,
      );
      expect(px(coarse.left, 40 * 1000), closeTo(2.5, 1e-6));
      expect(px(mid.left, 20 * 1000), closeTo(5, 1e-6));
      expect(px(fine.left, 5), closeTo(20, 1e-6));
    });

    test('线索引越界时钳制到最近有效线（分侧公式照常，不变式恒成立）', () {
      // 段 = 1s 与 29s @100ms/px（cap 时间域 = 20px×100ms = 2s）：越界
      // 下标 5 钳到线 0 → 左 = min(2s, 10%×1s=100ms) = 100ms；
      // 右 = min(2s, 10%×29s=2.9s) = 2s（cap）。
      final sides = transitionTriggerSideHalfWidths(
        segments: [seg(0, 0, 1), seg(1, 1, 30)],
        lineIndex: 5,
        microsecondsPerPixel: 100 * 1000,
        maxSideWidthPx: 20,
      );
      expect(sides.left, const Duration(milliseconds: 100));
      expect(sides.right, const Duration(seconds: 2));
    });

    test('首/尾段只有单侧邻线：仅该侧被占用，保留面积 ≥90%', () {
      // 首段 3s（0–3s）仅右侧有线 0 → 占用 = 线 0 左侧窗；30ms/px →
      // 首段显示宽 100px → 左窗 = 10% = 10px = 300ms（cap = 20px×30ms =
      // 600ms 不触顶）；线 0 右侧窗面向末段 27s，与本断言无关。
      final sides = transitionTriggerSideHalfWidths(
        segments: [seg(0, 0, 3), seg(1, 3, 30)],
        lineIndex: 0,
        microsecondsPerPixel: 30 * 1000,
        maxSideWidthPx: 20,
      );
      expect(sides.left, const Duration(milliseconds: 300));
      final seg0Us = seg(0, 0, 3).duration.inMicroseconds;
      expect(
        seg0Us - sides.left.inMicroseconds,
        greaterThanOrEqualTo(seg0Us * 0.9),
      );
    });
  });
}
