// 学习段轨命中解析纯函数测试（最近段命中扩展）。
//
// seam 入参 = 派生几何 + 时间坐标 + 扩展宽度（时间量，与像素无关——像素→
// 时间换算在 widget 层）；返回命中的段/线/首尾或空。命中优先级：
// 分段线/首尾线 > 段体 > 空。
import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/player/track_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const total = Duration(seconds: 30);

  AnnotationTimeline timelineWith(List<Duration> lines) =>
      AnnotationTimeline.normalized(
        videoDuration: total,
        segmentLines: [for (final p in lines) SegmentLine(position: p)],
      );

  /// 统一调用助手：默认从时间线取派生几何、各扩展宽度缺省为零。
  LearningTrackHitTarget? hitAt(
    AnnotationTimeline t,
    Duration time, {
    List<LearningSegment>? segments,
    (Duration, Duration)? range,
    Duration lineHalfWidth = Duration.zero,
    Duration edgeHalfWidth = Duration.zero,
    Duration minSegmentHitWidth = Duration.zero,
  }) =>
      resolveLearningTrackHit(
        segmentLines: t.segmentLines,
        rangeStart: range == null ? t.rangeStart : range.$1,
        rangeEnd: range == null ? t.rangeEnd : range.$2,
        segments: segments ?? deriveLearningSegments(t),
        time: time,
        lineHalfWidth: lineHalfWidth,
        edgeHalfWidth: edgeHalfWidth,
        minSegmentHitWidth: minSegmentHitWidth,
      );

  group('段体命中（最近段 + 最小命中宽扩展）', () {
    test('点在段内 → 命中该段', () {
      final t = timelineWith([
        const Duration(seconds: 10),
        const Duration(seconds: 20),
      ]);
      const wide = Duration(milliseconds: 200);
      expect(
        hitAt(
          t,
          const Duration(seconds: 5),
          lineHalfWidth: wide,
          edgeHalfWidth: wide,
        ),
        const SegmentHitTarget(0),
      );
      expect(
        hitAt(
          t,
          const Duration(seconds: 15),
          lineHalfWidth: wide,
          edgeHalfWidth: wide,
        ),
        const SegmentHitTarget(1),
      );
    });

    test('短段扩展：点在短段几何外、但落其最小命中宽内且更近其中心 → 命中短段', () {
      // 段 1 = [10s, 11s) 仅 1s 宽；最小命中宽 2s → 左右各扩 0.5s。
      // 点 11.3s 几何上在段 2 内，但距段 1 中心 0.8s、距段 2 中心更远。
      final t = timelineWith([
        const Duration(seconds: 10),
        const Duration(seconds: 11),
      ]);
      expect(
        hitAt(
          t,
          const Duration(milliseconds: 11300),
          minSegmentHitWidth: const Duration(seconds: 2),
        ),
        const SegmentHitTarget(1),
      );
    });

    test('多候选重叠取距点按最近的段中心', () {
      // 对称窄段构造真实重叠：段 0 = [8s,12s)、段 1 = [12s,16s)，最小宽 6s
      // → 各扩 1s，点 11.5s 同时落两段扩展区间，距段 0 中心 1.5s < 距段 1 3s。
      final t = timelineWith([
        const Duration(seconds: 8),
        const Duration(seconds: 12),
      ]);
      // 手工几何（时间线只有一条线）：直接构造段列表。
      final segments = [
        LearningSegment(
          order: 0,
          start: const Duration(seconds: 8),
          end: const Duration(seconds: 12),
        ),
        LearningSegment(
          order: 1,
          start: const Duration(seconds: 12),
          end: const Duration(seconds: 16),
        ),
      ];
      LearningTrackHitTarget? hit(Duration time) => hitAt(
        t,
        time,
        segments: segments,
        range: (Duration.zero, total),
        minSegmentHitWidth: const Duration(seconds: 6),
      );
      expect(hit(const Duration(milliseconds: 11500)), const SegmentHitTarget(0));
      // 镜像：点 12.5s 更近段 1 中心。
      expect(hit(const Duration(milliseconds: 12500)), const SegmentHitTarget(1));
    });

    test('零扩展宽度时点在段间缝（段界）→ 段体不命中，段界恰为分段线则命中线', () {
      final t = timelineWith([const Duration(seconds: 10)]);
      // 段区间左闭右开：10s 恰在段界上、两侧段体皆不含；但段界即分段线 →
      // 线命中兜底（优先级线 > 段体）。
      expect(hitAt(t, const Duration(seconds: 10)), const SegmentLineHitTarget(0));
    });
  });

  group('线与首尾命中（优先级：分段线/首尾线 > 段体）', () {
    test('点靠近分段线（命中半宽内）→ 分段线优先于段体；密集线取最近', () {
      final t = timelineWith([
        const Duration(seconds: 10),
        const Duration(seconds: 10, milliseconds: 100),
      ]);
      const lineHalf = Duration(milliseconds: 200);
      expect(
        hitAt(t, const Duration(seconds: 10), lineHalfWidth: lineHalf),
        const SegmentLineHitTarget(0),
        reason: '距 10s 线 0、距 10.1s 线 100ms → 取更近的线 0',
      );
      expect(
        hitAt(
          t,
          const Duration(seconds: 10, milliseconds: 90),
          lineHalfWidth: lineHalf,
        ),
        const SegmentLineHitTarget(1),
      );
    });

    test('点靠近视频首/尾（首尾半宽内）→ 首尾线命中', () {
      final t = timelineWith([const Duration(seconds: 15)]);
      const edgeHalf = Duration(milliseconds: 300);
      expect(
        hitAt(t, const Duration(milliseconds: 200), edgeHalfWidth: edgeHalf),
        const RangeEdgeHitTarget(isStart: true),
      );
      expect(
        hitAt(
          t,
          total - const Duration(milliseconds: 250),
          edgeHalfWidth: edgeHalf,
        ),
        const RangeEdgeHitTarget(isStart: false),
      );
    });

    test('线与段体同点竞争 → 线胜出（命中优先级）', () {
      final t = timelineWith([const Duration(seconds: 10)]);
      expect(
        hitAt(
          t,
          const Duration(seconds: 10, milliseconds: 50),
          lineHalfWidth: const Duration(milliseconds: 200),
          minSegmentHitWidth: const Duration(seconds: 30),
        ),
        const SegmentLineHitTarget(0),
      );
    });
  });

  group('段体专用解析（长按不认线与首尾线的命中窗）', () {
    // 段 0 = [0,5) 中心 2.5s；段 1 = [5,20) 中心 12.5s；段 2 = [20,30)
    // 中心 25s——线在 5s / 20s 上。
    final segments = [
      LearningSegment(
        order: 0,
        start: Duration.zero,
        end: const Duration(seconds: 5),
      ),
      LearningSegment(
        order: 1,
        start: const Duration(seconds: 5),
        end: const Duration(seconds: 20),
      ),
      LearningSegment(order: 2, start: const Duration(seconds: 20), end: total),
    ];

    SegmentHitTarget? bodyHit(
      Duration time, {
      Duration minSegmentHitWidth = Duration.zero,
    }) => resolveLearningSegmentHit(
      segments: segments,
      time: time,
      minSegmentHitWidth: minSegmentHitWidth,
    );

    test('点落分段线上：不因命中线而落选，按最近段中心解析', () {
      expect(
        bodyHit(const Duration(seconds: 5)),
        const SegmentHitTarget(1),
        reason: '零扩展：段界左闭右开归右段',
      );
      expect(
        bodyHit(const Duration(seconds: 5), minSegmentHitWidth: const Duration(seconds: 6)),
        const SegmentHitTarget(0),
        reason: '两侧段都进候选时取距中心更近的左段',
      );
    });

    test('点落视频首/尾线命中窗内（区间内）：解析到首/末段', () {
      expect(
        bodyHit(const Duration(milliseconds: 300)),
        const SegmentHitTarget(0),
      );
      expect(
        bodyHit(total - const Duration(milliseconds: 300)),
        const SegmentHitTarget(2),
      );
    });

    test('无学习段 → 空', () {
      expect(
        resolveLearningSegmentHit(
          segments: const [],
          time: const Duration(seconds: 5),
          minSegmentHitWidth: Duration.zero,
        ),
        isNull,
      );
    });
  });

  group('空命中', () {
    test('无分段线（无学习段）→ 空', () {
      final t = AnnotationTimeline.wholeVideo(total);
      expect(
        hitAt(
          t,
          const Duration(seconds: 5),
          segments: const [],
          lineHalfWidth: const Duration(seconds: 1),
          edgeHalfWidth: const Duration(seconds: 1),
          minSegmentHitWidth: const Duration(seconds: 5),
        ),
        isNull,
      );
    });

    test('扩展后仍无候选（区间外远处）→ 空', () {
      final t = AnnotationTimeline.normalized(
        videoDuration: const Duration(minutes: 3),
        rangeStart: const Duration(seconds: 30),
        rangeEnd: const Duration(seconds: 60),
        segmentLines: const [SegmentLine(position: Duration(seconds: 45))],
      );
      expect(
        hitAt(
          t,
          const Duration(seconds: 5),
          edgeHalfWidth: const Duration(milliseconds: 300),
          minSegmentHitWidth: const Duration(seconds: 2),
        ),
        isNull,
      );
    });

    test('零宽几何导出的命中入参 → 不抛、不虚命中', () {
      // 就地守卫直测的模块层表达：零宽几何安静返回空命中、各命中宽度与
      // 时间由零宽几何导出（pixelToDuration / pixelToTime 全为零值），命中
      // 解析函数收到即安静返回空——不产生任何命中、不抛。
      const zeroWidth = TrackBandGeometry.eval(
        total: Duration(minutes: 3),
        width: 0,
        prefixWidth: 0,
      );
      final t = AnnotationTimeline.normalized(
        videoDuration: const Duration(minutes: 3),
        rangeStart: const Duration(seconds: 30),
        rangeEnd: const Duration(seconds: 60),
        segmentLines: const [SegmentLine(position: Duration(seconds: 45))],
      );
      expect(
        resolveLearningTrackHit(
          segmentLines: t.segmentLines,
          rangeStart: t.rangeStart,
          rangeEnd: t.rangeEnd,
          segments: const [],
          time: zeroWidth.pixelToTime(44),
          lineHalfWidth: zeroWidth.pixelToDuration(20),
          edgeHalfWidth: zeroWidth.pixelToDuration(20),
          minSegmentHitWidth: zeroWidth.pixelToDuration(24),
        ),
        isNull,
      );
    });
  });
}
