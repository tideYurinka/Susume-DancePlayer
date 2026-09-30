import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/annotation/segment_hit.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/player/track_geometry.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// 轨道带几何值对象直测——可映射谓词、
/// 生效窗口归一、时间↔像素原语与带内钳制、每像素微秒单式子、命中入参
/// 装配（三命中宽 + 收窄触发窗覆盖）、零宽安静降级、行归属委派轨道行表。
/// 不启动 widget 环境、不 pump 容器。

const threeMin = Duration(minutes: 3);

TrackBandGeometry geo({
  Duration? total = threeMin,
  TimelineWindow? window,
  double width = 300,
  double prefixWidth = 0,
}) =>
    TrackBandGeometry.eval(
      total: total,
      window: window,
      width: width,
      prefixWidth: prefixWidth,
    );

TimelineWindow win(int startMs, int endMs) => TimelineWindow(
      total: threeMin,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    );

/// [TimelineWindow] 未声明结构相等，按字段比较。
void expectWindow(TimelineWindow actual, TimelineWindow expected) {
  expect(actual.total, expected.total);
  expect(actual.start, expected.start);
  expect(actual.end, expected.end);
}

void main() {
  group('触控宽度（一处声明）', () {
    // 40dp 是触控目标的约定值。值钉在声明所在的文件里，改常量的人在这里
    // 看到这条约定；命中的行为后果由轨道带套件的既有用例覆盖。
    test('分段线与首/尾线的触控宽度为 40dp', () {
      expect(kSegmentLineHitWidth, 40);
      expect(kVideoRangeHitWidth, 40);
    });
  });

  group('可映射吗（唯一空态谓词）', () {
    test('总时长未知（null）→ 不可映射', () {
      expect(geo(total: null).isMappable, isFalse);
    });
    test('总时长非正（0 / 负）→ 不可映射', () {
      expect(geo(total: Duration.zero).isMappable, isFalse);
      expect(geo(total: const Duration(seconds: -1)).isMappable, isFalse);
    });
    test('带宽非正（0 / 负）→ 不可映射', () {
      expect(geo(width: 0).isMappable, isFalse);
      expect(geo(width: -10).isMappable, isFalse);
    });
    test('合法入参 → 可映射；谓词是唯一判据（恒非空值对象）', () {
      expect(geo().isMappable, isTrue);
      expect(geo(window: win(60_000, 120_000)).isMappable, isTrue);
    });
    test('窗口退化不进入空态：不合法窗口已归一为全宽', () {
      final g = geo(window: win(120_000, 60_000));
      expect(g.isMappable, isTrue);
      expectWindow(g.effectiveWindow, TimelineWindow.full(threeMin));
    });
  });

  group('生效窗口归一', () {
    test('合法窗口原样透出', () {
      final w = win(60_000, 120_000);
      final g = geo(window: w);
      expect(g.effectiveWindow.total, threeMin);
      expect(g.effectiveWindow.start, w.start);
      expect(g.effectiveWindow.end, w.end);
    });
    test('null 窗口 = 全宽 0..total', () {
      expectWindow(geo().effectiveWindow, TimelineWindow.full(threeMin));
    });
    test('倒序窗口 → 归一为全宽', () {
      expectWindow(geo(window: win(120_000, 60_000)).effectiveWindow,
          TimelineWindow.full(threeMin));
    });
    test('零长窗口（start == end）→ 归一为全宽', () {
      expectWindow(geo(window: win(60_000, 60_000)).effectiveWindow,
          TimelineWindow.full(threeMin));
    });
    test('越界窗口（end 超出总时长）→ 归一为全宽', () {
      final w = TimelineWindow(
        total: threeMin,
        start: Duration(minutes: 2),
        end: const Duration(minutes: 4),
      );
      expectWindow(geo(window: w).effectiveWindow, TimelineWindow.full(threeMin));
    });
    test('与总时长不匹配（换片后旧窗口）→ 归一为全宽', () {
      final stale = TimelineWindow(
        total: const Duration(minutes: 5),
        start: Duration(minutes: 1),
        end: Duration(minutes: 2),
      );
      expectWindow(geo(window: stale).effectiveWindow, TimelineWindow.full(threeMin));
    });
  });

  group('读取层真缺失（可空读取）', () {
    test('总时长未知（null）→ 无窗口（null）', () {
      expect(geo(total: null).effectiveWindowOrNull, isNull);
    });
    test('总时长非正（0 / 负）→ 无窗口（null）', () {
      expect(geo(total: Duration.zero).effectiveWindowOrNull, isNull);
      expect(
        geo(total: const Duration(seconds: -1)).effectiveWindowOrNull,
        isNull,
      );
    });
    test('合法窗口原样透出（同一实例）', () {
      final w = win(60_000, 120_000);
      expect(identical(geo(window: w).effectiveWindowOrNull, w), isTrue);
    });
    test('null 窗口 + 总时长已知 → 全宽 0..total', () {
      expectWindow(geo().effectiveWindowOrNull!, TimelineWindow.full(threeMin));
    });
    test('不合法窗口 → 归一为全宽（非 null）', () {
      expectWindow(geo(window: win(120_000, 60_000)).effectiveWindowOrNull!,
          TimelineWindow.full(threeMin));
    });
    test('真缺失判据只看总时长，与带宽无关（带宽 0 不吞窗口）', () {
      final w = win(60_000, 120_000);
      expect(identical(geo(window: w, width: 0).effectiveWindowOrNull, w),
          isTrue);
    });
  });

  group('原语', () {
    final g = geo(window: win(60_000, 120_000));
    // 可视窗口 60s..120s = 60s 满宽映射到 300px。
    final axis = TimelineAxis(
      total: threeMin,
      width: 300,
      contentLeft: 0,
      window: g.effectiveWindow,
    );

    test('时间 → 像素：窗口内按比例、窗口两端钳到 0 / width', () {
      expect(g.timeToPixel(win(60_000, 120_000).start), 0);
      expect(g.timeToPixel(win(60_000, 120_000).end), 300);
      expect(g.timeToPixel(const Duration(seconds: 90)), closeTo(150, 1e-9));
      expect(g.timeToPixel(Duration.zero), 0);
      expect(g.timeToPixel(threeMin), 300);
    });

    test('像素 → 时间与时间 → 像素互为逆（带内采样往返逐位一致）', () {
      for (var x = 0.0; x <= 300; x += 37.5) {
        expect(g.timeToPixel(g.pixelToTime(x)), closeTo(x, 1e-6));
      }
    });

    test('像素 → 时间越界钳到窗口两端', () {
      expect(g.pixelToTime(-5), win(60_000, 120_000).start);
      expect(g.pixelToTime(305), win(60_000, 120_000).end);
    });

    test('时间 → 像素与时间轴换算逐位一致（同一式子）', () {
      for (var ms = 0; ms <= 180_000; ms += 7_317) {
        final t = Duration(milliseconds: ms);
        expect(g.timeToPixel(t), axis.timeToX(t));
        expect(g.pixelToTime(g.timeToPixel(t)), axis.xToTime(g.timeToPixel(t)));
      }
    });

    test('每像素微秒只有一种取值口径：可见微秒 ÷ 带宽（窗口式子）', () {
      // 60_000_000 µs / 300 px = 200_000 µs/px。
      expect(g.microsecondsPerPixel, 200_000);
    });

    test('每像素微秒与像素 → 时间换算自洽：跨 1px 的时间差 = 每像素微秒', () {
      final perPx = g.microsecondsPerPixel;
      final span = g.pixelToTime(101) - g.pixelToTime(100);
      expect(span.inMicroseconds, perPx.round());
    });

    test('像素 → 时长按统一取整口径（(px × 每像素微秒).round()）', () {
      // 非整除样本：0.5px × 200_000 = 100_000µs；1.5px → 300_000µs（round）。
      expect(g.pixelToDuration(0.5), const Duration(microseconds: 100_000));
      expect(g.pixelToDuration(1.5), const Duration(microseconds: 300_000));
      expect(g.pixelToDuration(2.5), const Duration(microseconds: 500_000));
    });

    test('带内像素钳制在模块内完成', () {
      expect(g.clampPixel(-3), 0);
      expect(g.clampPixel(150), 150);
      expect(g.clampPixel(999), 300);
    });
  });

  group('便捷答案：学习段轨命中', () {
    final lines = [
      SegmentLine(position: const Duration(seconds: 70)),
      SegmentLine(position: const Duration(seconds: 90)),
    ];
    final segments = [
      LearningSegment(
        order: 0,
        start: const Duration(seconds: 75),
        end: const Duration(seconds: 85),
      ),
    ];
    LearningTrackHitTarget? hitAt(
      double dx, {
      Duration? narrowedLineHalfWidth,
    }) =>
        geo(window: win(60_000, 120_000)).learningHitAt(
          dx: dx,
          segmentLines: lines,
          rangeStart: win(60_000, 120_000).start,
          rangeEnd: win(60_000, 120_000).end,
          segments: segments,
          narrowedLineHalfWidth: narrowedLineHalfWidth,
        );

    test('命中分段线（命中宽常量经像素→时长装配）', () {
      // 200_000 µs/px：线命中半宽 20px → 4_000_000µs = 4s；点在 90s 线左侧
      // 1px（= 89.8s，距线 0.2s ≤ 4s）→ 命中线 1。
      final hit = hitAt(149);
      expect(hit, SegmentLineHitTarget(1));
    });

    test('装配结果与纯函数直算逐位一致（同一取整口径）', () {
      const perPx = 200_000.0;
      Duration pxToDuration(double px) =>
          Duration(microseconds: (px * perPx).round());
      final expected = resolveLearningTrackHit(
        segmentLines: lines,
        rangeStart: win(60_000, 120_000).start,
        rangeEnd: win(60_000, 120_000).end,
        segments: segments,
        time: win(60_000, 120_000).start +
            Duration(microseconds: (149 * perPx).round()),
        lineHalfWidth: pxToDuration(kSegmentLineHitWidth / 2),
        edgeHalfWidth: pxToDuration(kVideoRangeHitWidth / 2),
        minSegmentHitWidth:
            pxToDuration(kTrackGeometryLearningSegmentMinHitWidth),
      );
      expect(hitAt(149), expected);
    });

    test('命中段体：点按落在段区间内（段宽 10s 已宽于最小命中宽）', () {
      // 段 75s..85s；x=100 → 60s + 100×0.2s = 80s，落在段内。
      final hit = hitAt(100);
      expect(hit, const SegmentHitTarget(0));    });

    test('命中视频尾线（边界命中带）', () {
      // 尾线 = 120s = x 300；距 1px（0.2s ≤ 边缘半宽 20px = 4s）。
      expect(hitAt(299), const RangeEdgeHitTarget(isStart: false));
    });

    test('窗外空白 → 空命中', () {
      // 60s + 25px×0.2s = 65s：距线/边界/扩展段体皆 > 半宽。
      expect(hitAt(25), isNull);
    });

    test('收窄触发窗覆盖参数生效：半宽收窄后同一点不再命中线', () {
      // x=151 → 90.2s，距 90s 线 0.2s：默认半宽 20px（4s）命中；
      // 覆盖为 0.1s 后不命中（线/边界/段体皆不可达）。
      expect(hitAt(151), SegmentLineHitTarget(1));
      expect(
        hitAt(151, narrowedLineHalfWidth: const Duration(milliseconds: 100)),
        isNull,
      );
    });

    test('段体专用答案不认线窗：线窗内的点按段体解析（长按圈选走这条）', () {
      // x=151 → 90.2s，落在 90s 线的线窗内：单击答案命中线 1，段体答案
      // 按最近段中心解析到段 1（[85s,100s) 中心 92.5s，距 2.3s）。
      final b = geo(window: win(60_000, 120_000));
      final twoSegments = [
        LearningSegment(
          order: 0,
          start: const Duration(seconds: 75),
          end: const Duration(seconds: 85),
        ),
        LearningSegment(
          order: 1,
          start: const Duration(seconds: 85),
          end: const Duration(seconds: 100),
        ),
      ];
      expect(hitAt(151), SegmentLineHitTarget(1));
      expect(
        b.learningSegmentHitAt(dx: 151, segments: twoSegments),
        const SegmentHitTarget(1),
      );
    });
  });

  group('零宽：安静降级', () {
    for (final width in [0.0, -10.0]) {
      group('带宽 $width', () {
        final g = geo(width: width);
        test('不可映射', () => expect(g.isMappable, isFalse));
        test('每像素微秒安静返回 0（非无穷）', () {
          expect(g.microsecondsPerPixel, 0);
          expect(g.microsecondsPerPixel.isFinite, isTrue);
        });
        test('像素 → 时间安静返回零时长', () {
          expect(g.pixelToTime(10), Duration.zero);
        });
        test('像素 → 时长安静返回零时长', () {
          expect(g.pixelToDuration(10), Duration.zero);
        });
        test('时间 → 像素安静返回 0', () {
          expect(g.timeToPixel(threeMin), 0);
        });
        test('便捷答案安静返回空命中（有内容的带同样安静返回空）', () {
          expect(
            g.learningHitAt(
              dx: 10,
              segmentLines: const [],
              rangeStart: Duration.zero,
              rangeEnd: threeMin,
              segments: const [],
            ),
            isNull,
          );
          // 传入零宽几何（带真实线/段）→ 不抛、返回空。
          final w = win(60_000, 120_000);
          expect(
            g.learningHitAt(
              dx: 150,
              segmentLines: [
                SegmentLine(position: const Duration(seconds: 90)),
              ],
              rangeStart: w.start,
              rangeEnd: w.end,
              segments: [
                LearningSegment(
                  order: 0,
                  start: const Duration(seconds: 75),
                  end: const Duration(seconds: 85),
                ),
              ],
            ),
            isNull,
          );
        });
        test('行归属安静返回空', () {
          expect(g.rowAt(20), isNull);
        });
        test('时间轴安静返回零值（不发生对无穷取整）', () {
          final axis = g.axis;
          expect(axis.isEmpty, isTrue);
          expect(axis.timeToX(threeMin), 0);
          expect(axis.xToTime(10), Duration.zero);
        });
      });
    }
    test('总时长未知同样安静降级', () {
      final g = geo(total: null);
      expect(g.microsecondsPerPixel, 0);
      expect(g.pixelToTime(10), Duration.zero);
      expect(g.timeToPixel(threeMin), 0);
      expect(g.rowAt(20), isNull);
    });
  });

  group('时间轴构造（模块唯一入口）', () {
    test('合法窗口：时间↔像素按窗口两端满宽映射（独立工作例）', () {
      final axis = geo(window: win(60_000, 120_000)).axis;
      // 窗口 60s..120s 宽 300px：窗口中点 90s → 150px；越界钳到两端。
      expect(axis.timeToX(const Duration(seconds: 90)), 150.0);
      expect(axis.timeToX(Duration.zero), 0.0);
      expect(axis.timeToX(threeMin), 300.0);
      expect(axis.xToTime(150), const Duration(seconds: 90));
      expect(axis.xToTime(-5), const Duration(seconds: 60));
      expect(axis.xToTime(999), const Duration(seconds: 120));
    });
    test('null 窗口：按全宽 0..total 映射', () {
      final axis = geo(window: null).axis;
      expect(axis.timeToX(threeMin ~/ 2), 150.0);
      expect(axis.xToTime(150), threeMin ~/ 2);
    });
    test('不合法窗口：归一为全宽后再构造（轴上无退化窗口）', () {
      final axis = geo(window: win(120_000, 60_000)).axis;
      expect(axis.timeToX(threeMin ~/ 2), 150.0);
      expect(axis.xToTime(300), threeMin);
    });
    test('轴恒非空：总时长未知/非正 → 空轴安静返回零值（空态只有一种表示）', () {
      for (final g in [geo(total: null), geo(total: Duration.zero)]) {
        expect(g.axis.isEmpty, isTrue);
        expect(g.axis.timeToX(threeMin), 0);
        expect(g.axis.xToTime(0), Duration.zero);
      }
    });
    test('轴恒非空：总时长已知 → 与生效窗口同源换算', () {
      final g = geo(window: win(60_000, 120_000));
      expect(g.axis.isEmpty, isFalse);
      expect(g.axis.timeToX(const Duration(seconds: 90)), 150.0);
    });
    test('每像素微秒：任何入参下与窗口式子同值（回退式对照断言）', () {
      // 全宽（window = null）、合法窗口、不合法窗口（归一全宽）三种入参，
      // 模块给出的每像素微秒恒等于「窗口可视微秒 ÷ 带宽」——不存在第二
      // 种取值口径（死支回退式收口后不再可构造）。
      expect(geo(window: null).microsecondsPerPixel,
          threeMin.inMicroseconds / 300);
      expect(geo(window: win(60_000, 120_000)).microsecondsPerPixel,
          const Duration(seconds: 60).inMicroseconds / 300);
      expect(geo(window: win(120_000, 60_000)).microsecondsPerPixel,
          threeMin.inMicroseconds / 300);
    });
    test('轴与每像素微秒同源：轴两端换算与原语逐位一致', () {
      final w = win(60_000, 120_000);
      final g = geo(window: w);
      expect(g.axis.timeToX(w.start), g.timeToPixel(w.start));
      expect(g.axis.timeToX(w.end), g.timeToPixel(w.end));
    });
  });

  group('行归属委派轨道行表', () {
    test('逐点扫描与轨道行表自身直测口径逐位一致（含端点与间隙）', () {
      final g = geo();
      const table = TrackRowTable.normal;
      final total = table.totalHeight;
      for (var dy = -2.0; dy <= total + 2; dy += 0.5) {
        expect(g.rowAt(dy), table.rowAt(dy), reason: 'dy=$dy');
      }
    });
    test('委派具名行集 normal：间隙坐标 → 空、行端点 → 该行', () {
      final g = geo();
      expect(g.rowAt(0), TrackRowId.note);
      // 备注轨 0..36，间隙 36..46，局部镜像轨 46..76。
      expect(g.rowAt(36), TrackRowId.note);
      expect(g.rowAt(41), isNull);
      expect(g.rowAt(46), TrackRowId.localMirror);
    });
    test('可指定行集', () {
      final g = geo();
      const custom = TrackRowTable(
        rows: [
          TrackRow(
            id: TrackRowId.beat,
            height: 20,
            key: 'track_beat_custom',
            prefixLabel: '节拍',
          ),
        ],
        gap: 0,
      );
      expect(g.rowAt(10, rows: custom), TrackRowId.beat);
      expect(g.rowAt(25, rows: custom), isNull);
    });
  });

  group('轨道片头口径', () {
    // 带宽 300、片头 40 → 内容区 [40, 300]（时间轴零点钉在 40）。
    const prefix = 40.0;

    test('内容区左缘让出片头宽：零点在内容区左缘、片尾在带右缘', () {
      final g = geo(prefixWidth: prefix);
      expect(g.contentLeft, prefix);
      expect(g.contentWidth, 300 - prefix);
      expect(g.axis.timeToX(Duration.zero), prefix);
      expect(g.axis.timeToX(threeMin), 300);
      expect(g.timeToPixel(threeMin), 300);
    });

    test('像素↔时间换算按内容区：零点之左的像素钳到窗口起点', () {
      final g = geo(prefixWidth: prefix);
      expect(g.axis.xToTime(prefix), Duration.zero);
      expect(g.axis.xToTime(300), threeMin);
      // 内容区中点 = 片中点。
      expect(g.axis.xToTime((prefix + 300) / 2), const Duration(seconds: 90));
      expect(g.timeToPixel(const Duration(seconds: 90)), (prefix + 300) / 2);
      // 片头区（零点之左）不是内容：像素钳到窗口起点。
      expect(g.axis.xToTime(0), Duration.zero);
      expect(g.pixelToTime(0), Duration.zero);
    });

    test('每像素微秒按内容区宽（片头不吃速度口径）', () {
      final g = geo(prefixWidth: prefix);
      expect(g.microsecondsPerPixel, threeMin.inMicroseconds / (300 - prefix));
    });

    test('无片头（prefixWidth 0）：时间映射占满带宽', () {
      final g = geo();
      expect(g.contentLeft, 0);
      expect(g.contentWidth, 300);
      expect(g.axis.timeToX(Duration.zero), 0);
      expect(g.axis.timeToX(threeMin), 300);
      expect(g.axis.xToTime(150), const Duration(seconds: 90));
      expect(g.microsecondsPerPixel, threeMin.inMicroseconds / 300);
    });

    test('默认全片视图：片头占满零点之左那一段（左缘 0、右缘 = 零点）', () {
      final g = geo(prefixWidth: prefix);
      expect(g.prefixRight, g.axis.timeToX(Duration.zero));
      expect(g.prefixLeft, 0);
      expect(g.prefixVisible, isTrue);
    });

    test('平移到轨道右侧（窗口起点在零点之后）：片头随内容左移出可视带', () {
      final g = geo(prefixWidth: prefix, window: win(60_000, 90_000));
      // 零点屏上 x = 40 − (60/30) × 260 = −480。
      expect(g.prefixRight, closeTo(prefix - 60 / 30 * (300 - prefix), 0.001));
      expect(g.prefixVisible, isFalse);
    });

    test('轻微平移：片头部分仍在带内（跟着内容走，不钉在屏幕左边）', () {
      // 窗口 [1s, 91s]：零点屏上 x = 40 − (1/90) × 260 ≈ 37.11。
      final g = geo(prefixWidth: prefix, window: win(1_000, 91_000));
      expect(g.prefixRight, closeTo(37.111, 0.001));
      expect(g.prefixLeft, closeTo(-2.889, 0.001));
      expect(g.prefixVisible, isTrue);
    });

    test('缩放不改变片头右缘 = 零点屏上 x（与内容同坐标）', () {
      final g = geo(prefixWidth: prefix, window: win(30_000, 60_000));
      // 零点屏上 x = 40 − 1 × 260 = −220（窗口起点即 30s，零点在窗外左侧）。
      expect(g.prefixRight, closeTo(-220, 0.001));
      expect(g.prefixVisible, isFalse);
    });

    test('退化：片头宽 ≥ 带宽 → 无内容可映射、片头不画', () {
      final g = geo(width: 30, prefixWidth: prefix);
      expect(g.contentWidth, 0);
      expect(g.isMappable, isFalse);
      expect(g.prefixVisible, isFalse);
    });

    test('总时长未知（不可映射）时片头仍贴内容区左缘、不抛错', () {
      final g = geo(total: null, prefixWidth: prefix);
      expect(g.contentLeft, prefix);
      expect(g.prefixRight, prefix);
      expect(g.prefixVisible, isTrue);
    });
  });

  group('轨道片头让位宽随窗口收回', () {
    // 带宽 300、片头 40：不让位参考尺度下，零点屏上 x
    //   = 40 − start/可视秒数 × (300 − 40)。
    const prefix = 40.0;

    /// 与实现无关的独立参考式：不让位（常量让位 40、内容区 [40, 300]）
    /// 尺度下的零点屏上 x。
    double refPrefixRight(TimelineWindow w) {
      const refLeft = prefix;
      const refWidth = 300 - prefix;
      return refLeft -
          w.start.inMicroseconds / w.visible.inMicroseconds * refWidth;
    }

    test('默认全片视图：让位宽 = 片头带宽、内容区左缘 = 零点屏上 x（逐位不变）', () {
      for (final g in [geo(prefixWidth: prefix), geo(prefixWidth: prefix, window: win(0, 180_000))]) {
        expect(g.contentLeft, prefix);
        expect(g.contentWidth, 300 - prefix);
        expect(g.prefixRight, prefix);
        expect(g.timeToPixel(Duration.zero), prefix);
        expect(g.microsecondsPerPixel, threeMin.inMicroseconds / (300 - prefix));
      }
    });

    test('窗口起点离开 0：让位宽 = 片头可见右缘，片头右缘与内容区左缘齐平', () {
      final g = geo(prefixWidth: prefix, window: win(1_000, 91_000));
      // 独立参考式：40 − (1s/90s) × 260 ≈ 37.111。
      expect(g.prefixRight, closeTo(refPrefixRight(win(1_000, 91_000)), 1e-9));
      expect(g.contentLeft, closeTo(37.111, 0.001));
      // 齐平 = 空隙恒 0：内容区左缘就是片头右缘（同一份参考映射）。
      expect(g.contentLeft - g.prefixRight, closeTo(0, 1e-9));
      expect(g.contentWidth, closeTo(300 - 37.111, 0.001));
      // 内容映射起于片头右缘：窗口起点贴着内容区左缘。
      expect(g.timeToPixel(win(1_000, 91_000).start), closeTo(g.contentLeft, 1e-9));
    });

    test('零点完全滑出视线：让位宽 = 0、内容区宽 = 带宽（片段左缘贴带左缘）', () {
      final g = geo(prefixWidth: prefix, window: win(60_000, 90_000));
      expect(g.contentLeft, 0);
      expect(g.contentWidth, 300);
      expect(g.prefixVisible, isFalse);
      expect(g.timeToPixel(win(60_000, 90_000).start), 0);
      expect(g.microsecondsPerPixel, const Duration(seconds: 30).inMicroseconds / 300);
    });

    test('平移回开头：片头重新完整出现、让位恢复 40（与默认视图逐位一致）', () {
      final panned = geo(prefixWidth: prefix, window: win(60_000, 90_000));
      expect(panned.contentLeft, 0);
      final back = geo(prefixWidth: prefix, window: win(0, 180_000));
      final fresh = geo(prefixWidth: prefix);
      expect(back.contentLeft, fresh.contentLeft);
      expect(back.contentWidth, fresh.contentWidth);
      expect(back.prefixRight, fresh.prefixRight);
      expect(back.prefixLeft, fresh.prefixLeft);
      expect(back.prefixVisible, fresh.prefixVisible);
      expect(back.prefixVisible, isTrue);
      expect(back.prefixLeft, 0);
      expect(back.microsecondsPerPixel, fresh.microsecondsPerPixel);
      // 对照：起点 > 0 的几何确实收回了让位（非平凡断言）。
      expect(panned.contentLeft, isNot(fresh.contentLeft));
    });

    test('让位变化连续：起点从 0 扫到零点滑出，让位宽单调不增、无跳变', () {
      var previous = prefix;
      for (var startMs = 0; startMs <= 20_000; startMs += 100) {
        final g = geo(prefixWidth: prefix, window: win(startMs, startMs + 90_000));
        final reserve = g.contentLeft;
        expect(reserve, inInclusiveRange(0, prefix), reason: 'startMs=$startMs');
        expect(reserve, lessThanOrEqualTo(previous + 1e-9),
            reason: 'startMs=$startMs 不应回升');
        expect(reserve, closeTo(refPrefixRight(win(startMs, startMs + 90_000)).clamp(0, prefix), 1e-9),
            reason: 'startMs=$startMs 与参考映射逐位一致');
        previous = reserve;
      }
    });

    test('窗口与缩放状态不因让位变化被改写：生效窗口原样透出', () {
      const w = TimelineWindow(
        total: threeMin,
        start: Duration(seconds: 5),
        end: Duration(seconds: 95),
      );
      final g = geo(prefixWidth: prefix, window: w);
      expect(identical(g.effectiveWindow, w), isTrue);
      expect(identical(g.effectiveWindowOrNull, w), isTrue);
    });

    test('片头位置与让位宽同取一份参考映射，不自指迭代', () {
      // 部分滑出的窗口：让位宽不改变片头的绘制位置——两者都等于「不让位
      // 参考尺度」下的零点屏上 x（若自指，contentWidth 反喂位置会偏离此式）。
      for (final startMs in [1_000, 5_000, 10_000, 15_317]) {
        final w = win(startMs, startMs + 90_000);
        final g = geo(prefixWidth: prefix, window: w);
        expect(g.prefixRight, closeTo(refPrefixRight(w), 1e-9),
            reason: 'startMs=$startMs');
        expect(g.contentLeft, closeTo(refPrefixRight(w).clamp(0.0, prefix), 1e-9),
            reason: 'startMs=$startMs');
      }
    });

    test('边界：片头带宽 ≥ 带宽 → 内容区无宽、退化口径与既有一致', () {
      final g = geo(width: 30, prefixWidth: prefix);
      expect(g.contentLeft, 30);
      expect(g.contentWidth, 0);
      expect(g.isMappable, isFalse);
    });

    test('像素↔时间与每像素微秒仍同一份几何派生（平移窗口下互逆）', () {
      final g = geo(prefixWidth: prefix, window: win(1_000, 91_000));
      expect(g.microsecondsPerPixel,
          g.effectiveWindow.visible.inMicroseconds / g.contentWidth);
      for (var x = g.contentLeft; x <= 300; x += 25) {
        expect(g.timeToPixel(g.pixelToTime(x)), closeTo(x, 1e-4), reason: 'x=$x');
      }
    });
  });
}
