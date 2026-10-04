import 'dart:math' as math;

import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final threeMin = const Duration(minutes: 3); // 180_000 ms

  group('TimelineAxis.timeToX：0..duration 满宽', () {
    const axis = TimelineAxis(
      total: Duration(minutes: 3),
      width: 300,
      contentLeft: 0,
    );

    test('0 → 0、duration → width、中点 → width/2', () {
      expect(axis.timeToX(Duration.zero), 0);
      expect(axis.timeToX(threeMin), 300);
      expect(axis.timeToX(const Duration(minutes: 1, seconds: 30)), 150);
    });

    test('按毫秒连续换算（时间点按比例落在宽度内）', () {
      // 1 分钟 = 全程 1/3 → 100 / 300。
      expect(axis.timeToX(const Duration(minutes: 1)), closeTo(100, 1e-6));
    });

    test('越界钳制：time > duration → width；time < 0 → 0', () {
      expect(axis.timeToX(const Duration(minutes: 4)), 300);
      expect(axis.timeToX(const Duration(seconds: -5)), 0);
    });

    test('total 为 0 / width 为 0 → 0（不除零）', () {
      const emptyTotal = TimelineAxis(
        total: Duration.zero,
        width: 300,
        contentLeft: 0,
      );
      const emptyWidth = TimelineAxis(
        total: Duration(minutes: 3),
        width: 0,
        contentLeft: 0,
      );
      expect(emptyTotal.timeToX(const Duration(seconds: 3)), 0);
      expect(emptyWidth.timeToX(const Duration(seconds: 3)), 0);
      expect(emptyTotal.isEmpty, isTrue);
      expect(emptyWidth.isEmpty, isTrue);
    });
  });

  group('TimelineAxis.xToTime：timeToX 的逆', () {
    const axis = TimelineAxis(
      total: Duration(minutes: 3),
      width: 300,
      contentLeft: 0,
    );

    test('0 → 0、width → duration、width/2 → duration/2', () {
      expect(axis.xToTime(0), Duration.zero);
      expect(axis.xToTime(300), threeMin);
      expect(axis.xToTime(150), const Duration(minutes: 1, seconds: 30));
    });

    test('x 越界钳制到 [0, width]', () {
      expect(axis.xToTime(-40), Duration.zero);
      expect(axis.xToTime(9999), threeMin);
    });

    test('与 timeToX 往返一致（整格时间点无损）', () {
      const roundTrip = TimelineAxis(
        total: Duration(minutes: 3),
        width: 400,
        contentLeft: 0,
      );
      for (final ms in [0, 1, 45_000, 90_000, 180_000]) {
        final d = Duration(milliseconds: ms);
        expect(roundTrip.xToTime(roundTrip.timeToX(d)), d);
      }
    });
  });

  group('TimelineWindow：可视窗口值类型', () {
    const win = TimelineWindow(
      total: Duration(minutes: 3),
      start: Duration(minutes: 1),
      end: Duration(minutes: 2),
    );

    test('full 工厂 = 0..total 全宽；isValid / visible / zoomFactor', () {
      final full = TimelineWindow.full(threeMin);
      expect(full.isValid, isTrue);
      expect(full.start, Duration.zero);
      expect(full.end, threeMin);
      expect(full.visible, threeMin);
      expect(full.zoomFactor, 1);

      expect(win.isValid, isTrue);
      expect(win.start, const Duration(minutes: 1));
      expect(win.end, const Duration(minutes: 2));
      expect(win.visible, const Duration(minutes: 1));
      expect(win.zoomFactor, 3); // 180s / 60s

      expect(win.contains(const Duration(minutes: 1)), isTrue);
      expect(win.contains(const Duration(minutes: 2)), isTrue);
      expect(win.contains(const Duration(minutes: 1, seconds: 30)), isTrue);
      expect(win.contains(const Duration(seconds: 59)), isFalse);
      expect(win.contains(const Duration(minutes: 2, seconds: 1)), isFalse);
    });

    test('退化窗口（end <= start / 越界）isValid=false', () {
      const bad1 = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(minutes: 2),
        end: Duration(minutes: 1),
      );
      const bad2 = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(minutes: 2),
        end: Duration(minutes: 4),
      );
      expect(bad1.isValid, isFalse);
      expect(bad2.isValid, isFalse);
      expect(TimelineWindow.full(Duration.zero).isValid, isFalse);
    });

    test('pannedBy 平移并钳制在 [0, total] 内', () {
      final left = win.pannedBy(const Duration(minutes: -2));
      expect(left.start, Duration.zero);
      expect(left.end, const Duration(minutes: 1));

      final right = win.pannedBy(const Duration(minutes: 3));
      expect(right.start, const Duration(minutes: 2));
      expect(right.end, threeMin);

      final small = win.pannedBy(const Duration(seconds: 10));
      expect(small.start, const Duration(minutes: 1, seconds: 10));
      expect(small.end, const Duration(minutes: 2, seconds: 10));
      expect(small.visible, win.visible);
    });
  });

  group('TimelineWindow.zoomed：锚点保持相对位置', () {
    const win = TimelineWindow(
      total: Duration(minutes: 3),
      start: Duration(minutes: 1),
      end: Duration(minutes: 2),
    );

    test('锚点在中点放大 2 倍：中点时间仍处窗口一半 → 屏上 x 不变', () {
      // 窗口 [60,120]s 可视 60s，锚 90s（相对位置 0.5），×2 → 可视 30s → [75,105]。
      final z = win.zoomed(
        anchor: const Duration(minutes: 1, seconds: 30),
        factor: 2,
      );
      expect(z.start, const Duration(seconds: 75));
      expect(z.end, const Duration(seconds: 105));
      expect(z.visible, const Duration(seconds: 30));
      // 锚时间在缩放后的窗口内仍占一半 → 映射 x 不变（映射正确性）。
      const axis = TimelineAxis(
        total: Duration(minutes: 3),
        width: 300,
        contentLeft: 0,
      );
      const zAxis = TimelineAxis(
        total: Duration(minutes: 3),
        width: 300,
        contentLeft: 0,
        window: TimelineWindow(
          total: Duration(minutes: 3),
          start: Duration(seconds: 75),
          end: Duration(seconds: 105),
        ),
      );
      const anchor = Duration(minutes: 1, seconds: 30);
      expect(axis.timeToX(anchor), closeTo(zAxis.timeToX(anchor), 1e-6));
    });

    test('锚点在窗口左端 / 右端：窗口贴锚点一侧缩放', () {
      final atStart = win.zoomed(anchor: const Duration(minutes: 1), factor: 2);
      expect(atStart.start, const Duration(minutes: 1));
      expect(atStart.end, const Duration(minutes: 1, seconds: 30));

      final atEnd = win.zoomed(anchor: const Duration(minutes: 2), factor: 2);
      expect(atEnd.start, const Duration(minutes: 1, seconds: 30));
      expect(atEnd.end, const Duration(minutes: 2));
    });

    test('缩小（factor<1）可视变长；缩到全宽为止（不越出 total）', () {
      final out = win.zoomed(
        anchor: const Duration(minutes: 1, seconds: 30),
        factor: 0.5,
      );
      // 可视 120s，锚 90s 居中 → [30,150]。
      expect(out.start, const Duration(seconds: 30));
      expect(out.end, const Duration(seconds: 150));

      final wayOut = win.zoomed(
        anchor: const Duration(minutes: 1, seconds: 30),
        factor: 0.1,
      );
      // 缩到可视 = total → 0..total 全宽。
      expect(wayOut.visible, threeMin);
      expect(wayOut.start, Duration.zero);
      expect(wayOut.end, threeMin);
    });

    test('放大钳制到 kMinZoomVisibleDuration（不无限缩）', () {
      final deep = win.zoomed(
        anchor: const Duration(minutes: 1, seconds: 30),
        factor: 1e6,
      );
      expect(deep.visible, kMinZoomVisibleDuration);
      expect(deep.contains(const Duration(minutes: 1, seconds: 30)), isTrue);
    });

    test('非法 factor（<=0）返回自身', () {
      expect(win.zoomed(anchor: Duration.zero, factor: 0), same(win));
      expect(win.zoomed(anchor: Duration.zero, factor: -1), same(win));
    });
  });

  group('TimelineWindow.keepingVisible：播放头越窗跟随', () {
    const win = TimelineWindow(
      total: Duration(minutes: 3),
      start: Duration(minutes: 1),
      end: Duration(minutes: 2),
    );

    test('窗口内不动（返回同一实例）', () {
      expect(
        win.keepingVisible(const Duration(minutes: 1, seconds: 30)),
        same(win),
      );
      expect(win.keepingVisible(const Duration(minutes: 1)), same(win));
    });

    test('越出右端：平移使播放头落回 fraction 处', () {
      final panned = win.keepingVisible(const Duration(seconds: 130));
      // 130 - 0.25×60 = 115 → [115,175]。
      expect(panned.start, const Duration(seconds: 115));
      expect(panned.end, const Duration(seconds: 175));
      expect(panned.visible, win.visible);
    });

    test('越出左端同样跟随；近 total 处钳制窗口右端到 total', () {
      final panned = win.keepingVisible(const Duration(seconds: 30));
      expect(panned.start, const Duration(seconds: 15));
      expect(panned.end, const Duration(seconds: 75));

      final nearEnd = win.keepingVisible(threeMin);
      // 180 - 15 = 165 → 钳到 120（窗口右端贴 total）。
      expect(nearEnd.start, const Duration(seconds: 120));
      expect(nearEnd.end, threeMin);
    });
  });

  group('TimelineWindow.centeredOn：落半拍线后收拢窗口', () {
    test('以锚点为中心、可视宽 = span（±1 拍 → span = 2 拍）', () {
      final win = TimelineWindow.centeredOn(
        total: threeMin,
        anchor: const Duration(minutes: 1, seconds: 30),
        span: const Duration(seconds: 8),
      );
      expect(win.start, const Duration(minutes: 1, seconds: 26));
      expect(win.end, const Duration(minutes: 1, seconds: 34));
      expect(win.total, threeMin);
      expect(win.contains(const Duration(minutes: 1, seconds: 30)), isTrue);
    });

    test('锚点靠近左端：窗口左端钳到 0，锚点仍在窗内', () {
      final win = TimelineWindow.centeredOn(
        total: threeMin,
        anchor: const Duration(seconds: 2),
        span: const Duration(seconds: 8),
      );
      expect(win.start, Duration.zero);
      expect(win.end, const Duration(seconds: 8));
    });

    test('锚点靠近右端：窗口右端钳到 total，锚点仍在窗内', () {
      final win = TimelineWindow.centeredOn(
        total: threeMin,
        anchor: threeMin - const Duration(seconds: 2),
        span: const Duration(seconds: 8),
      );
      expect(win.end, threeMin);
      expect(win.start, threeMin - const Duration(seconds: 8));
      expect(win.contains(threeMin - const Duration(seconds: 2)), isTrue);
    });

    test('span ≥ total：回全宽窗口', () {
      final win = TimelineWindow.centeredOn(
        total: threeMin,
        anchor: const Duration(minutes: 1),
        span: threeMin,
      );
      expect(win.start, Duration.zero);
      expect(win.end, threeMin);
    });
  });

  group('缩放滑条映射（指数插值 1..maxZoomFactor）', () {
    test('maxZoomFactorFor：total/缩放下限；无可缩放空间 = 1', () {
      expect(maxZoomFactorFor(threeMin), 90); // 180s / 2s
      expect(maxZoomFactorFor(const Duration(minutes: 1)), 30);
      expect(maxZoomFactorFor(const Duration(seconds: 1)), 1);
      expect(maxZoomFactorFor(Duration.zero), 1);
    });

    test('zoomFactorForSliderValue：0 → 1、1 → max、中点 = 几何中位', () {
      expect(zoomFactorForSliderValue(threeMin, 0), 1);
      expect(zoomFactorForSliderValue(threeMin, 1), closeTo(90, 1e-9));
      final mid = zoomFactorForSliderValue(threeMin, 0.5);
      expect(mid, closeTo(math.sqrt(90), 1e-9));
    });

    test('zoomSliderValueFor：全宽 = 0；与 zoomFactorForSliderValue 往返一致', () {
      expect(zoomSliderValueFor(TimelineWindow.full(threeMin)), 0);
      // visible 60s → factor 3 → v = ln3/ln90。
      const win = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(minutes: 1),
        end: Duration(minutes: 2),
      );
      final v = zoomSliderValueFor(win);
      expect(v, closeTo(math.log(3) / math.log(90), 1e-9));
      // 往返：v → factor → 相同滑条值。
      final f = zoomFactorForSliderValue(threeMin, v);
      expect(f, closeTo(3, 1e-6));
      expect(win.zoomFactor, closeTo(f, 1e-6));
    });

    test('越界输入钳制；退化窗口滑条值 = 0', () {
      expect(zoomFactorForSliderValue(threeMin, -1), 1);
      expect(zoomFactorForSliderValue(threeMin, 2), closeTo(90, 1e-9));
      const bad = TimelineWindow(
        total: Duration(minutes: 3),
        start: Duration(minutes: 2),
        end: Duration(minutes: 1),
      );
      expect(zoomSliderValueFor(bad), 0);
    });

    test('滑条取值 NaN 过滤：NaN 归 0', () {
      expect(sanitizeZoomSliderValue(double.nan), 0);
      expect(sanitizeZoomSliderValue(0.5), 0.5);
      // NaN 进倍率换算 = 滑条 0 → 倍率 1（全宽），不抛错。
      expect(zoomFactorForSliderValue(threeMin, double.nan), 1);
    });
  });

  group('TimelineAxis 带可视窗口：缩放后映射', () {
    const total = Duration(minutes: 3);
    const win = TimelineWindow(
      total: total,
      start: Duration(minutes: 1),
      end: Duration(minutes: 2),
    );
    const axis = TimelineAxis(
      total: total,
      width: 300,
      window: win,
      contentLeft: 0,
    );

    test('timeToX：窗口左端 → 0、右端 → width、中点 → width/2', () {
      expect(axis.timeToX(const Duration(minutes: 1)), 0);
      expect(axis.timeToX(const Duration(minutes: 2)), 300);
      expect(axis.timeToX(const Duration(minutes: 1, seconds: 30)), 150);
    });

    test('窗口外时间钳制到窗口两端（不全片 0..total 映射）', () {
      expect(axis.timeToX(Duration.zero), 0);
      expect(axis.timeToX(const Duration(minutes: 3)), 300);
    });

    test('xToTime：逆映射落回窗口内', () {
      expect(axis.xToTime(0), const Duration(minutes: 1));
      expect(axis.xToTime(300), const Duration(minutes: 2));
      expect(axis.xToTime(150), const Duration(minutes: 1, seconds: 30));
      expect(axis.xToTime(-50), const Duration(minutes: 1));
      expect(axis.xToTime(9999), const Duration(minutes: 2));
    });

    test('退化窗口 → isEmpty（映射短路）', () {
      const bad = TimelineAxis(
        total: total,
        width: 300,
        contentLeft: 0,
        window: TimelineWindow(
          total: total,
          start: Duration(minutes: 2),
          end: Duration(minutes: 1),
        ),
      );
      expect(bad.isEmpty, isTrue);
      expect(bad.timeToX(const Duration(minutes: 1)), 0);
      expect(bad.xToTime(100), Duration.zero);
    });

    test('往返一致（窗口内整格时间点无损）', () {
      for (final ms in [60_000, 90_000, 119_000, 120_000]) {
        final d = Duration(milliseconds: ms);
        expect(axis.xToTime(axis.timeToX(d)), d);
      }
    });
  });

  group('双指缩放+平移联动换算', () {
    const total = Duration(minutes: 3);
    const width = 600.0;

    test('缩放分量：与 zoomed 同锚同倍率一致（沿用上下限/整片钳制）', () {
      final base = TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 120),
      );
      const anchor = Duration(seconds: 90);
      const factor = 2.0;
      final expected = base.zoomed(anchor: anchor, factor: factor);
      final got = pinchPanZoomed(
        base: base,
        anchor: anchor,
        factor: factor,
        focalDeltaDx: 0,
        width: width,
      );
      expect(got.start, expected.start);
      expect(got.end, expected.end);
    });

    test('平移分量：手指右移（焦点 dx>0）= 内容跟手 = 窗口左移看更早内容', () {
      final base = TimelineWindow(
        total: total,
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 120),
      );
      final got = pinchPanZoomed(
        base: base,
        anchor: base.start,
        factor: 1,
        focalDeltaDx: 60, // 1/10 带宽 → 平移 6s
        width: width,
      );
      expect(got.visible, base.visible, reason: '平移不改窗口时长');
      expect(got.start, const Duration(seconds: 54), reason: '左移 6s');
    });

    test('组合：缩放决定窗口时长、平移在其上叠加且各钳制不越界', () {
      final base = TimelineWindow(
        total: total,
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 30),
      );
      final got = pinchPanZoomed(
        base: base,
        anchor: const Duration(seconds: 20),
        factor: 2,
        focalDeltaDx: 150,
        width: width,
      );
      final zoomed = base.zoomed(
        anchor: const Duration(seconds: 20),
        factor: 2,
      );
      expect(got.visible, zoomed.visible, reason: '时长由缩放决定');
      expect(got.start, lessThan(zoomed.start), reason: '向右拖在此基础上左移窗口');
      expect(got.start, greaterThanOrEqualTo(Duration.zero));
      expect(got.end, lessThanOrEqualTo(total));

      // 反向拖 + 贴缘：平移钳制在 [0, total]。
      final right = pinchPanZoomed(
        base: base,
        anchor: const Duration(seconds: 20),
        factor: 2,
        focalDeltaDx: -100000,
        width: width,
      );
      expect(right.end, total, reason: '左拖钳制贴 total');
      final left = pinchPanZoomed(
        base: base,
        anchor: const Duration(seconds: 20),
        factor: 2,
        focalDeltaDx: 100000,
        width: width,
      );
      expect(left.start, Duration.zero, reason: '右拖钳制贴 0');
    });

    test('缩放下限沿用：放大超过 kMinZoomVisibleDuration 后可视不再变短', () {
      final base = TimelineWindow(
        total: total,
        start: Duration.zero,
        end: const Duration(seconds: 3),
      );
      final got = pinchPanZoomed(
        base: base,
        anchor: const Duration(seconds: 1),
        factor: 100,
        focalDeltaDx: 0,
        width: width,
      );
      expect(
        got.visible,
        kMinZoomVisibleDuration,
        reason: '最细可视下限不变（沿用既有钳制规则）',
      );
    });

    test('无效窗口 / 零宽 → 原样返回', () {
      const bad = TimelineWindow(
        total: total,
        start: Duration(seconds: 30),
        end: Duration(seconds: 10),
      );
      expect(
        pinchPanZoomed(
          base: bad,
          anchor: Duration.zero,
          factor: 2,
          focalDeltaDx: 10,
          width: width,
        ),
        same(bad),
      );
      final base = TimelineWindow.full(total);
      expect(
        pinchPanZoomed(
          base: base,
          anchor: Duration.zero,
          factor: 2,
          focalDeltaDx: 10,
          width: 0,
        ),
        same(base),
      );
    });
  });

  group('pinchAnchorTime：捏合锚点取预览线', () {
    final window = TimelineWindow(
      total: threeMin,
      start: const Duration(seconds: 60),
      end: const Duration(seconds: 120),
    );
    const finger = Duration(seconds: 90);

    test('预览线在窗口内（含端点）→ 锚点 = 预览线时间', () {
      expect(
        pinchAnchorTime(
          window: window,
          previewLineTime: const Duration(seconds: 90),
          fingerFocalTime: finger,
        ),
        const Duration(seconds: 90),
      );
      expect(
        pinchAnchorTime(
          window: window,
          previewLineTime: const Duration(seconds: 60),
          fingerFocalTime: finger,
        ),
        const Duration(seconds: 60),
        reason: '恰在左端点 = 在窗口内',
      );
      expect(
        pinchAnchorTime(
          window: window,
          previewLineTime: const Duration(seconds: 120),
          fingerFocalTime: finger,
        ),
        const Duration(seconds: 120),
        reason: '恰在右端点 = 在窗口内',
      );
    });

    test('预览线在窗口外 → 锚点 = 手指焦点时间', () {
      expect(
        pinchAnchorTime(
          window: window,
          previewLineTime: const Duration(seconds: 30),
          fingerFocalTime: finger,
        ),
        finger,
      );
      expect(
        pinchAnchorTime(
          window: window,
          previewLineTime: const Duration(seconds: 150),
          fingerFocalTime: finger,
        ),
        finger,
      );
    });

    test('退化窗口（零宽 / 零时长 / 无效）→ 手指焦点时间，不炸', () {
      final zeroWidth = TimelineWindow(
        total: threeMin,
        start: Duration(seconds: 60),
        end: Duration(seconds: 60),
      );
      const zeroTotal = TimelineWindow(
        total: Duration.zero,
        start: Duration.zero,
        end: Duration.zero,
      );
      final invalid = TimelineWindow(
        total: threeMin,
        start: const Duration(seconds: 120),
        end: const Duration(seconds: 60),
      );
      for (final w in [zeroWidth, zeroTotal, invalid]) {
        expect(
          pinchAnchorTime(
            window: w,
            previewLineTime: const Duration(seconds: 60),
            fingerFocalTime: finger,
          ),
          finger,
        );
      }
    });
  });
}
