import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/annotation.dart';

Duration s(int v) => Duration(seconds: v);

void main() {
  const video = Duration(minutes: 3); // 180s
  AnnotationTimeline whole() => AnnotationTimeline.wholeVideo(video);

  group('默认模型（整片）', () {
    test('视频首 = 0:00、视频尾 = 视频时长、无分段线', () {
      final t = whole();
      expect(t.rangeStart, Duration.zero);
      expect(t.rangeEnd, video);
      expect(t.segmentLines, isEmpty);
      expect(t.practiceRangeDuration, video);
    });

    test('负视频时长被拒', () {
      expect(
        () => AnnotationTimeline.wholeVideo(const Duration(seconds: -1)),
        throwsArgumentError,
      );
    });
  });

  group('新建分段线 addSegmentLine', () {
    test('区间内新建 → 产生一条线，位置正确', () {
      final t = addSegmentLine(whole(), s(60));
      expect(t.segmentLines, hasLength(1));
      expect(t.segmentLines.single.position, s(60));
      expect(t.segmentLines.single.flagged, isFalse);
    });

    test('多线自动升序排列', () {
      final t = addSegmentLine(addSegmentLine(whole(), s(120)), s(60));
      expect(t.segmentLines.map((l) => l.position), [s(60), s(120)]);
    });

    test('不改变原模型（纯函数）', () {
      final original = whole();
      addSegmentLine(original, s(60));
      expect(original.segmentLines, isEmpty);
    });

    test('同位置重复新建 = no-op', () {
      final t = addSegmentLine(whole(), s(60));
      final again = addSegmentLine(t, s(60));
      expect(again, t); // 无变更，等值
      expect(again.segmentLines, hasLength(1));
      expect(again.segmentLines.single.position, s(60));
    });

    test('区间外（首边界、尾边界、区间外）被拒', () {
      expect(() => addSegmentLine(whole(), s(0)), throwsArgumentError); // == 首
      expect(
        () => addSegmentLine(whole(), s(180)),
        throwsArgumentError,
      ); // == 尾
      expect(() => addSegmentLine(whole(), s(200)), throwsArgumentError); // 越尾
      expect(() => addSegmentLine(whole(), s(-10)), throwsArgumentError); // 越首
    });

    test('区间退化为单点时无法新建（无内部）', () {
      final t = setVideoRange(whole(), start: s(50), end: s(50));
      expect(t.rangeStart, s(50));
      expect(t.rangeEnd, s(50));
      expect(() => addSegmentLine(t, s(50)), throwsArgumentError);
    });
  });

  group('删除分段线 removeSegmentLine', () {
    test('删除中间线 → 融合相邻（几何见 learning_segments）', () {
      var t = whole();
      t = addSegmentLine(t, s(60));
      t = addSegmentLine(t, s(120));
      final removed = removeSegmentLine(t, 1);
      expect(removed.segmentLines.map((l) => l.position), [s(60)]);
    });

    test('越界索引被拒', () {
      expect(() => removeSegmentLine(whole(), 0), throwsRangeError); // 空
      final t = addSegmentLine(whole(), s(60));
      expect(() => removeSegmentLine(t, -1), throwsRangeError);
      expect(() => removeSegmentLine(t, 1), throwsRangeError);
    });
  });

  group('拖动分段线 moveSegmentLine（钳制）', () {
    test('单线：区间内移动生效，触首/尾边界 no-op', () {
      final t = addSegmentLine(whole(), s(60));
      expect(moveSegmentLine(t, 0, s(70)).segmentLines.single.position, s(70));

      // 拖到 == 首/尾边界或越界 → 不动（避免零长段）
      expect(moveSegmentLine(t, 0, s(0)).segmentLines.single.position, s(60));
      expect(moveSegmentLine(t, 0, s(180)).segmentLines.single.position, s(60));
      expect(moveSegmentLine(t, 0, s(200)).segmentLines.single.position, s(60));
    });

    test('多线：不越过相邻线（保持升序与几何完整）', () {
      var t = whole();
      t = addSegmentLine(t, s(60));
      t = addSegmentLine(t, s(120));

      // 线 0 向左：不越过首，仍升序
      var m = moveSegmentLine(t, 0, s(30));
      expect(m.segmentLines.map((l) => l.position), [s(30), s(120)]);

      // 线 0 试图拖过线 1（120）→ no-op
      m = moveSegmentLine(t, 0, s(150));
      expect(m.segmentLines.map((l) => l.position), [s(60), s(120)]);

      // 线 1 右移到区间内 → 生效；右移触尾/越邻 → no-op
      m = moveSegmentLine(t, 1, s(150));
      expect(m.segmentLines.map((l) => l.position), [s(60), s(150)]);
      m = moveSegmentLine(t, 1, s(180));
      expect(m.segmentLines.map((l) => l.position), [s(60), s(120)]);
    });

    test('越界索引被拒', () {
      expect(() => moveSegmentLine(whole(), 0, s(10)), throwsRangeError);
    });
  });

  group('flag 置位/清除', () {
    test('置位/清除/切换', () {
      var t = addSegmentLine(whole(), s(60));
      t = setSegmentLineFlag(t, 0, true);
      expect(t.segmentLines.single.flagged, isTrue);
      expect(setSegmentLineFlag(t, 0, true), t); // 已为目标值 → no-op

      t = setSegmentLineFlag(t, 0, false);
      expect(t.segmentLines.single.flagged, isFalse);

      t = toggleSegmentLineFlag(t, 0);
      expect(t.segmentLines.single.flagged, isTrue);
    });

    test('越界索引被拒', () {
      expect(() => setSegmentLineFlag(whole(), 0, true), throwsRangeError);
      expect(() => toggleSegmentLineFlag(whole(), 0), throwsRangeError);
    });
  });

  group('视频首/尾设置与钳制', () {
    test('首被钳制在 [0, videoDuration] 且 ≤ 尾', () {
      final t = whole(); // [0, 180]
      // 首试图超过尾 → 钳到尾
      final c = setVideoRangeStart(t, s(200));
      expect(c.rangeStart, s(180));
      expect(c.rangeEnd, s(180));
      expect(c.rangeStart, lessThanOrEqualTo(c.rangeEnd));
    });

    test('尾被钳制 ≥ 首 且 ≤ videoDuration', () {
      final t = setVideoRangeStart(whole(), s(40)); // [40, 180]
      final c = setVideoRangeEnd(t, s(10)); // 尾试图早于首 → 钳到首
      expect(c.rangeStart, s(40));
      expect(c.rangeEnd, s(40));
    });

    test('缩小尾 → 区间外的分段线被剔除', () {
      var t = whole();
      for (final p in [s(60), s(120), s(150)]) {
        t = addSegmentLine(t, p);
      }
      final c = setVideoRangeEnd(t, s(100)); // 新区间 (0, 100]
      // 严格位于 (0,100) 内仅剩 60
      expect(c.segmentLines.map((l) => l.position), [s(60)]);
    });

    test('首右移（前移）→ 位于新首左侧的分段线被剔除', () {
      var t = whole();
      for (final p in [s(60), s(120), s(150)]) {
        t = addSegmentLine(t, p);
      }
      final c = setVideoRangeStart(t, s(130)); // 首 0→130，新区间 [130, 180]
      expect(c.segmentLines.map((l) => l.position), [s(150)]);
    });

    test('同时设置首/尾被归一化（首 ≤ 尾）', () {
      final t = whole();
      final c = setVideoRange(t, start: s(150), end: s(100));
      expect(c.rangeStart, lessThanOrEqualTo(c.rangeEnd));
      // 两条都被钳在 [0, videoDuration] 内
      expect(c.rangeStart, greaterThanOrEqualTo(Duration.zero));
      expect(c.rangeEnd, lessThanOrEqualTo(video));
    });
  });

  group('删除半拍线 removeHalfBeatLine', () {
    test('删除指定半拍线：半拍线减少，分段线/首尾不变', () {
      var t = whole();
      t = addSegmentLine(t, s(60));
      t = addHalfBeatLine(t, s(30));
      t = addHalfBeatLine(t, s(90));
      final removed = removeHalfBeatLine(t, 0);
      expect(removed.halfBeatLines.map((l) => l.position), [s(90)]);
      expect(removed.segmentLines.map((l) => l.position), [s(60)]);
      expect(removed.rangeStart, t.rangeStart);
      expect(removed.rangeEnd, t.rangeEnd);
      // 原模型不变（不可变约定）。
      expect(t.halfBeatLines.map((l) => l.position), [s(30), s(90)]);
    });

    test('越界索引被拒', () {
      expect(() => removeHalfBeatLine(whole(), 0), throwsRangeError); // 空
      final t = addHalfBeatLine(whole(), s(30));
      expect(() => removeHalfBeatLine(t, -1), throwsRangeError);
      expect(() => removeHalfBeatLine(t, 1), throwsRangeError);
    });
  });

  group('节拍对齐整体平移 shiftBeatAlignment', () {
    AnnotationTimeline seeded() {
      var t = whole();
      t = addSegmentLine(t, s(60));
      t = addSegmentLine(t, s(120));
      t = addHalfBeatLine(t, s(30));
      return t;
    }

    test('整体平移：首尾线与全部分段线/半拍线同量移动', () {
      final d = const Duration(milliseconds: 250);
      final c = shiftBeatAlignment(seeded(), d);
      expect(c.rangeStart, d);
      expect(c.rangeEnd, video);
      expect(c.segmentLines.map((l) => l.position), [s(60) + d, s(120) + d]);
      expect(c.halfBeatLines.map((l) => l.position), [s(30) + d]);
    });

    test('负平移：首尾线钳在 0..total，界外线由归一化剔除', () {
      var t = seeded();
      t = setVideoRange(t, start: s(10));
      final c = shiftBeatAlignment(t, const Duration(seconds: -20));
      expect(c.rangeStart, Duration.zero); // −10s 钳 0
      expect(c.rangeEnd, s(160)); // 区间随平移到 [−10, 160]，首线钳 0
      // 30s 半拍线平移到 10s 仍在开区间内；60/120s 分段线平移到 40/100s。
      expect(c.segmentLines.map((l) => l.position), [s(40), s(100)]);
      expect(c.halfBeatLines.map((l) => l.position), [s(10)]);
    });

    test('正平移越界：尾线钳到视频总时长，落入尾线上的线被剔除', () {
      final c = shiftBeatAlignment(seeded(), const Duration(seconds: 50));
      expect(c.rangeStart, s(50));
      expect(c.rangeEnd, video); // 170+50 钳到 180
      expect(c.segmentLines.map((l) => l.position), [s(110), s(170)]);
      // 再平移 20s：170+20=190 越出钳后区间，剔除。
      final c2 = shiftBeatAlignment(seeded(), const Duration(seconds: 70));
      expect(c2.rangeEnd, video); // 170+70 钳到 180
      expect(c2.segmentLines.map((l) => l.position), [s(130)]);
    });

    test('零平移恒等（返回等值模型，不产生净变化）', () {
      final t = seeded();
      expect(shiftBeatAlignment(t, Duration.zero), t);
    });
  });

  group('自动分段 applyAutoSegment 的 flag 迁移', () {
    /// 播种 [flaggedSeconds] 各一条置位 flag 的分段线（整片区间内）。
    AnnotationTimeline seeded(List<int> flaggedSeconds) {
      var t = whole();
      for (final sec in flaggedSeconds) {
        t = addSegmentLine(t, s(sec), flagged: true);
      }
      return t;
    }

    List<Duration> flagged(AnnotationTimeline t) => [
      for (final line in t.segmentLines)
        if (line.flagged) line.position,
    ];

    test('唯一旧 flag 迁到时刻最近的新刀（无距离阈值）', () {
      final migrated = applyAutoSegment(
        seeded([10]),
        start: Duration.zero,
        end: video,
        cuts: [s(3), s(12)],
      );
      expect(flagged(migrated), [s(12)]);

      // 唯一新刀即便很远也照迁（无距离阈值）。
      final far = applyAutoSegment(
        seeded([10]),
        start: Duration.zero,
        end: video,
        cuts: [s(50)],
      );
      expect(flagged(far), [s(50)]);
    });

    test('新旧刀同刻时 flag 落在该刀上（距离 0）', () {
      final migrated = applyAutoSegment(
        seeded([10]),
        start: Duration.zero,
        end: video,
        cuts: [s(10), s(40)],
      );
      expect(flagged(migrated), [s(10)]);
    });

    test('距离并列时取更早那条新刀', () {
      final migrated = applyAutoSegment(
        seeded([10]),
        start: Duration.zero,
        end: video,
        cuts: [s(5), s(15)],
      );
      expect(flagged(migrated), [s(5)]);
    });

    test('多条旧 flag 命中同一条新刀时只置位一次', () {
      final migrated = applyAutoSegment(
        seeded([9, 11]),
        start: Duration.zero,
        end: video,
        cuts: [s(10)],
      );
      expect(migrated.segmentLines, hasLength(1));
      expect(migrated.segmentLines.single.flagged, isTrue);
    });

    test('落在新首/尾区间之外的旧 flag 丢弃', () {
      final beforeRange = applyAutoSegment(
        seeded([5]),
        start: s(20),
        end: s(40),
        cuts: [s(30)],
      );
      expect(flagged(beforeRange), isEmpty, reason: '5s 落在新首之外');
      expect(beforeRange.segmentLines.map((l) => l.position), [s(30)]);

      final afterRange = applyAutoSegment(
        seeded([60]),
        start: s(20),
        end: s(40),
        cuts: [s(30)],
      );
      expect(flagged(afterRange), isEmpty, reason: '60s 落在新尾之外');

      // 落在新首/尾**线上**（开区间边界）的旧 flag 同样不参与迁移。
      final onBoundary = applyAutoSegment(
        seeded([20, 40]),
        start: s(20),
        end: s(40),
        cuts: [s(30)],
      );
      expect(flagged(onBoundary), isEmpty, reason: '触新首/尾线的 flag 不在开区间内');
    });

    test('多条旧 flag 各自迁到时刻最近的不同新刀', () {
      final migrated = applyAutoSegment(
        seeded([9, 23]),
        start: Duration.zero,
        end: video,
        cuts: [s(10), s(20), s(30)],
      );
      expect(flagged(migrated), [s(10), s(20)]);
    });

    test('旧分区没有 flag 时新线一条都不带 flag', () {
      var t = whole();
      t = addSegmentLine(t, s(10));
      t = addSegmentLine(t, s(20));
      final migrated = applyAutoSegment(
        t,
        start: Duration.zero,
        end: video,
        cuts: [s(15), s(25)],
      );
      expect(migrated.segmentLines.map((l) => l.position), [s(15), s(25)]);
      expect(flagged(migrated), isEmpty);
    });

    test('切割线为空时新线列表为空且不抛异常', () {
      final migrated = applyAutoSegment(
        seeded([10]),
        start: s(5),
        end: s(40),
        cuts: const [],
      );
      expect(migrated.segmentLines, isEmpty);
      expect(migrated.rangeStart, s(5));
      expect(migrated.rangeEnd, s(40));
    });

    test('首/尾钳制、升序与开区间不变式与替换前一致', () {
      final migrated = applyAutoSegment(
        seeded([10]),
        start: const Duration(seconds: -5),
        end: s(200),
        cuts: [s(15), s(5)],
      );
      expect(migrated.rangeStart, Duration.zero);
      expect(migrated.rangeEnd, video);
      expect(migrated.segmentLines.map((l) => l.position), [s(5), s(15)]);
      // 并列取更早（未排序输入经归一化后仍按时刻最近且并列取更早）。
      expect(flagged(migrated), [s(5)]);

      // 与首/尾同刻的刀由归一化剔除（开区间）。
      final boundary = applyAutoSegment(
        whole(),
        start: s(10),
        end: s(20),
        cuts: [s(10), s(15), s(20)],
      );
      expect(boundary.segmentLines.map((l) => l.position), [s(15)]);
    });
  });
}
