import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';

Duration s(int v) => Duration(seconds: v);

void main() {
  const video = Duration(minutes: 3); // 180s

  test('未分段 → 无学习段片段', () {
    final t = AnnotationTimeline.wholeVideo(video);
    expect(deriveLearningSegments(t), isEmpty);
  });

  test('新建 1 条分段线 → 前后两段、首尾相接', () {
    final t = addSegmentLine(AnnotationTimeline.wholeVideo(video), s(60));
    final segs = deriveLearningSegments(t);
    expect(segs, hasLength(2));
    expect(segs[0].order, 0);
    expect(segs[0].start, s(0));
    expect(segs[0].end, s(60));
    expect(segs[1].order, 1);
    expect(segs[1].start, s(60));
    expect(segs[1].end, s(180));
    // 首尾相接、总长 = 有效练习区间时长
    expect(segs[0].end, segs[1].start);
    expect(
      segs.fold<Duration>(Duration.zero, (sum, seg) => sum + seg.duration),
      video,
    );
  });

  test('n 条分段线 → n+1 段，首段左端 = 首、末段右端 = 尾', () {
    var t = AnnotationTimeline.wholeVideo(video);
    t = addSegmentLine(t, s(60));
    t = addSegmentLine(t, s(120));
    final segs = deriveLearningSegments(t);
    expect(segs, hasLength(3));
    expect(segs.map((seg) => seg.start), [s(0), s(60), s(120)]);
    expect(segs.map((seg) => seg.end), [s(60), s(120), s(180)]);
    expect(segs.first.start, s(0)); // 首段左端 = 视频首
    expect(segs.last.end, s(180)); // 末段右端 = 视频尾
    // 任意相邻相接
    for (var i = 0; i < segs.length - 1; i++) {
      expect(segs[i].end, segs[i + 1].start);
    }
  });

  test('首/尾边界变化时几何随之更新（隐式边界）', () {
    var t = AnnotationTimeline.wholeVideo(video);
    t = addSegmentLine(t, s(60));
    t = addSegmentLine(t, s(120));

    // 收紧区间到 [20, 160]（分段线 60、120 仍在内部被保留）
    t = setVideoRange(t, start: s(20), end: s(160));
    final segs = deriveLearningSegments(t);
    expect(segs.map((seg) => seg.start), [s(20), s(60), s(120)]);
    expect(segs.map((seg) => seg.end), [s(60), s(120), s(160)]);
    expect(
      segs.fold<Duration>(Duration.zero, (sum, seg) => sum + seg.duration),
      s(160) - s(20),
    );
  });

  test('删除分段线 → 相邻学习段融合（几何实时派生）', () {
    var t = AnnotationTimeline.wholeVideo(video);
    t = addSegmentLine(t, s(60));
    t = addSegmentLine(t, s(120));
    expect(deriveLearningSegments(t), hasLength(3));

    final merged = removeSegmentLine(t, 1); // 删 120 → 融合
    final segs = deriveLearningSegments(merged);
    expect(segs, hasLength(2));
    expect(segs.map((seg) => seg.start), [s(0), s(60)]);
    expect(segs.map((seg) => seg.end), [s(60), s(180)]);
  });
}
