import 'package:dance_learning_app/player/handle_strip.dart';
import 'package:flutter_test/flutter_test.dart';

/// 手柄槽等分互斥分区122，取代（三）半距
/// min24/max48 可重叠）：槽区间互斥不重叠、相邻线分界=中点；目标宽 ≤48dp；
/// 不足时优先向两侧空余扩展（贴屏边/区间边向外顶满至界内），仅当左右
/// 都无空余（三条密排中间线）才收缩；放大后槽恢复。
///
/// 首线的天然左界（线心 − 目标半宽）落在内容区之左（片头让位出
/// 的那一段）里时，左界顶到带左缘——片头让位后首线站在内容区左缘，那一段
/// 因此也归它可抓；首线被拖进内容区之后不再向带左缘伸手。
/// 整组左右严格对称：每条纹与其镜像纹互补。
void expectSymmetric(HandleBarPlan plan) {
  for (var i = 0; i < plan.grooves.length; i++) {
    final mirror = plan.grooves[plan.grooves.length - 1 - i];
    expect(
      plan.grooves[i].left + plan.grooves[i].width,
      closeTo(plan.contentWidth - mirror.left, 1e-9),
    );
  }
}

void main() {
  group('等分互斥分区', () {
    test('相邻线远距：槽宽封顶 48dp、以线心居中', () {
      final slots = assignHandleSlots(
        positions: const [0, 200, 500, 800],
        bandWidth: 800,
        contentLeft: 0,
      );
      expect(slots.length, 4);
      expect(slots[1].hitWidth, 48);
      expect(slots[1].hitLeft, 200 - 24);
      expect(slots[1].hitRight, 200 + 24);
      expect(slots[2].hitWidth, 48);
    });

    test('相邻线分界=中点：30dp 间距 → 相邻槽在中点相接不重叠', () {
      final slots = assignHandleSlots(
        positions: const [0, 130, 160, 800],
        bandWidth: 800,
        contentLeft: 0,
      );
      // 130 与 160 相距 30 < 48 → 分界 = 145；各自向外侧空余扩展到目标
      // 半宽 → 各 24+15=39dp，中点相接不重叠。
      expect(slots[1].hitRight, 145);
      expect(slots[2].hitLeft, 145);
      expect(slots[1].hitWidth, 39);
      expect(slots[2].hitWidth, 39);
      expect(slots[1].hitLeft, 130 - 24);
      expect(slots[2].hitRight, 160 + 24);
    });

    test('近线向外扩展优先：13.4dp 间距双线各占外侧目标半宽，互斥无重叠', () {
      final slots = assignHandleSlots(
        positions: const [373.3, 386.7],
        bandWidth: 800,
        contentLeft: 0,
      );
      // 分界 = 380：左线向左、右线向右各扩展到目标半宽 24 → 各 24+6.7。
      expect(slots[0].hitLeft, closeTo(373.3 - 24, 0.01));
      expect(slots[0].hitRight, closeTo(380, 0.01));
      expect(slots[1].hitLeft, closeTo(380, 0.01));
      expect(slots[1].hitRight, closeTo(386.7 + 24, 0.01));
      expect(slots[0].hitWidth, closeTo(30.7, 0.01));
      expect(slots[1].hitWidth, closeTo(30.7, 0.01));
      // 互斥：重叠区间内只有一侧 contains。
      expect(slots[0].contains(379), isTrue);
      expect(slots[1].contains(379), isFalse);
    });

    test('三条密排中间线：左右都无空余 → 槽收缩到两侧中点之间', () {
      final slots = assignHandleSlots(
        positions: const [40, 50, 60],
        bandWidth: 800,
        contentLeft: 0,
      );
      // 中间线（50）左右分界 = 45/55 → 槽 [45,55]（收缩）；两侧线向外侧
      // 空余扩展补足目标。
      expect(slots[1].hitLeft, 45);
      expect(slots[1].hitRight, 55);
      expect(slots[1].hitWidth, 10, reason: '两侧都被邻线占 → 只能收缩');
      expect(slots[0].hitWidth, 45 - (40 - 24));
      expect(slots[2].hitWidth, (60 + 24) - 55);
    });

    test('首线天然左界落在片头列里 → 左界顶到带左缘', () {
      // 默认视图：首线站在内容区左缘（内容区左缘 = 片头宽 40），天然左界
      // 16 落在片头列 [0, 40) 里 → 左界顶到带左缘 0，触发区由半个目标宽
      // 变 64dp；尾线槽逐位不变。
      final home = assignHandleSlots(
        positions: const [40, 800],
        bandWidth: 800,
        contentLeft: 40,
      );
      expect(home.first.hitLeft, 0);
      expect(home.first.hitRight, 64);
      expect(home.first.hitWidth, 64);
      expect(home.last.hitLeft, 776);
      expect(home.last.hitRight, 800);

      // 首线被拖进内容区（天然左界已在内容区里）→ 槽就是目标宽，不再向
      // 带左缘伸手（内容区的空白横滑区逐位不变）。
      final dragged = assignHandleSlots(
        positions: const [400, 800],
        bandWidth: 800,
        contentLeft: 40,
      );
      expect(dragged.first.hitLeft, 400 - 24);
      expect(dragged.first.hitRight, 400 + 24);
    });

    test('贴屏边向外顶满至界内：首线 x=0 → [0,24]，尾线 x=800 → [776,800]', () {
      final slots = assignHandleSlots(
        positions: const [0, 400, 800],
        bandWidth: 800,
        contentLeft: 0,
      );
      expect(slots.first.hitLeft, 0);
      expect(slots.first.hitRight, 24);
      expect(slots.last.hitLeft, 776);
      expect(slots.last.hitRight, 800);
    });

    test('边缘线在带缘内侧：外侧顶满到带缘，不越界', () {
      final slots = assignHandleSlots(
        positions: const [6, 400, 794],
        bandWidth: 800,
        contentLeft: 0,
      );
      // 首线 x=6：向左顶满到带缘 0（不越出屏），右侧到目标半宽。
      expect(slots.first.hitLeft, 0);
      expect(slots.first.hitRight, 6 + 24);
      // 尾线 x=794：[770,800]。
      expect(slots.last.hitLeft, 794 - 24);
      expect(slots.last.hitRight, 800);
    });

    test('贴屏边密线：分界中点 + 外侧顶满带缘，仍互斥', () {
      final slots = assignHandleSlots(
        positions: const [0, 10, 800],
        bandWidth: 800,
        contentLeft: 0,
      );
      // 首线 [0,5]（右侧被中点 5 截断、左侧顶满带缘），中间线 [5,34]
      // （向右侧空余扩展到目标）。
      expect(slots[0].hitLeft, 0);
      expect(slots[0].hitRight, 5);
      expect(slots[1].hitLeft, 5);
      expect(slots[1].hitRight, 10 + 24);
    });

    test('放大恢复：间距增大超过 48dp → 各槽恢复目标宽', () {
      // 放大前 30dp 间距（分界中点）；放大后同两线间距 120dp > 48。
      final zoomedOut = assignHandleSlots(
        positions: const [100, 130],
        bandWidth: 800,
        contentLeft: 0,
      );
      expect(zoomedOut[0].hitRight, 115);
      expect(zoomedOut[0].hitWidth, lessThan(48));
      final zoomedIn = assignHandleSlots(
        positions: const [100, 220],
        bandWidth: 800,
        contentLeft: 0,
      );
      expect(zoomedIn[0].hitWidth, 48);
      expect(zoomedIn[1].hitWidth, 48);
      expect(zoomedIn[0].hitRight, 124);
      expect(zoomedIn[1].hitLeft, 196);
    });

    test('密集线整组互斥：任意相邻槽相接不重叠', () {
      final positions = <double>[0, 30, 44, 52, 200, 208, 800];
      final slots = assignHandleSlots(
        positions: positions,
        bandWidth: 800,
        contentLeft: 0,
      );
      for (var i = 0; i + 1 < slots.length; i++) {
        expect(
          slots[i].hitRight,
          lessThanOrEqualTo(slots[i + 1].hitLeft + 1e-9),
          reason: '槽 $i 与 ${i + 1} 互斥不重叠',
        );
      }
      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].hitWidth, greaterThan(0));
        expect(slots[i].hitLeft, greaterThanOrEqualTo(0));
        expect(slots[i].hitRight, lessThanOrEqualTo(800));
      }
    });

    test('空列表与单线：不越界，单线槽居中并贴边顶满', () {
      expect(
        assignHandleSlots(positions: const [], bandWidth: 800, contentLeft: 0),
        isEmpty,
      );
      final solo = assignHandleSlots(
        positions: const [400],
        bandWidth: 800,
        contentLeft: 0,
      );
      expect(solo.single.hitWidth, 48);
      // 首线在最左：左界与线心重合，槽只剩右半——不加最小抓取宽。
      final soloEdge = assignHandleSlots(
        positions: const [0],
        bandWidth: 800,
        contentLeft: 0,
      );
      expect(soloEdge.single.hitLeft, 0);
      expect(soloEdge.single.hitWidth, 24);
    });

    test('槽序与输入一致（center 保持线心）', () {
      final positions = <double>[0, 100, 250, 800];
      final slots = assignHandleSlots(
        positions: positions,
        bandWidth: 800,
        contentLeft: 0,
      );
      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].center, positions[i]);
      }
    });
  });

  // （「缩放链路防御性 clamp」①）：控制柄视觉条几何——
  // 分段线乱序/槽区间退化时先归一（lo=max(0,hitLeft)、
  // hi=max(lo, min(带宽,hitRight)-条宽)）再钳制，不直接 clamp 抛
  // ArgumentError（build 阶段红屏根因）。
  group('handleBarLeft：视觉条几何归一后钳制', () {
    test('正常槽：条以线心居中并钳在槽区间内', () {
      final left = handleBarLeft(
        barCenter: 200,
        barWidth: 24,
        hitLeft: 176,
        hitRight: 224,
        bandWidth: 800,
      );
      expect(left, 188);
    });

    test('乱序槽（hitLeft > hitRight）：不抛错，值域合法', () {
      final left = handleBarLeft(
        barCenter: 200,
        barWidth: 24,
        hitLeft: 224,
        hitRight: 176,
        bandWidth: 800,
      );
      expect(left.isNaN, isFalse);
      expect(left, greaterThanOrEqualTo(224 - 1e-9));
    });

    test('退化槽（右界-条宽 < 下界）：下界兜底，不抛错', () {
      // 槽贴左缘且条宽超出槽宽：hi 原始值 < lo，归一后取 lo。
      final left = handleBarLeft(
        barCenter: 2,
        barWidth: 24,
        hitLeft: 0,
        hitRight: 8,
        bandWidth: 800,
      );
      expect(left, 0);
    });

    test('槽越出带右缘：上界归一为下界（hi ≥ lo），不抛错', () {
      // hitLeft=780 > min(带宽,hitRight)-条宽=776 → hi 取 lo=780。
      final left = handleBarLeft(
        barCenter: 795,
        barWidth: 24,
        hitLeft: 780,
        hitRight: 900,
        bandWidth: 800,
      );
      expect(left, 780);
    });
  });

  // 控制柄视觉几何收进纯函数——输入「槽宽 +
  // 条宽上限 + 条高 + 行高 + 描边开关」，输出一份视觉计划（条矩形、
  // 圆角、描边、每条纹相对内容盒的矩形、行内纵向偏移）。只断言几何
  // 结果，不断言 widget 结构；数值与规则照实测一字不改。
  group('planHandleBar：控制柄视觉几何', () {
    test('定稿 32×18：条 32×18、圆角 9、描边 1dp、内容盒 30×16、行内偏移 6dp', () {
      final plan = planHandleBar(
        slotWidth: 48,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      expect(plan.barWidth, 32);
      expect(plan.barHeight, 18);
      expect(plan.cornerRadius, 9, reason: '圆角 = 条高/2 = 9');
      expect(plan.strokeWidth, 1);
      expect(plan.contentWidth, 30, reason: '描边画在框内 → 内容盒 = 条 − 2×1dp');
      expect(plan.contentHeight, 16);
      expect(plan.rowOffsetY, 6, reason: '行高 30、条高 18 → 条顶偏移 (30−18)/2 = 6');
    });

    test('定稿 32×18：纹 4 条，每条 2×8dp，竖直上下余量各 4dp', () {
      final plan = planHandleBar(
        slotWidth: 48,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      expect(plan.grooves.length, 4);
      for (final g in plan.grooves) {
        expect(g.width, 2);
        expect(g.height, 8, reason: '纹高与内容盒高 16 同奇偶、≈ 16/2 = 8');
        expect(g.top, 4, reason: 'y = (16 − 8) / 2 = 4，上下余量相等且整 dp');
      }
    });

    test('定稿 32×18：等距端距 = 内缝 = 4.4dp，整组左右严格对称', () {
      final plan = planHandleBar(
        slotWidth: 48,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      final gaps = <double>[
        plan.grooves.first.left,
        for (var i = 1; i < plan.grooves.length; i++)
          plan.grooves[i].left -
              (plan.grooves[i - 1].left + plan.grooves[i - 1].width),
        plan.contentWidth - (plan.grooves.last.left + plan.grooves.last.width),
      ];
      for (final gap in gaps) {
        expect(
          gap,
          closeTo(4.4, 1e-9),
          reason: '端距 = 内缝 = 右端距 = 4.4dp，保留小数不取整',
        );
      }
      // 左右严格对称：每条纹与其镜像纹互补。
      expectSymmetric(plan);
    });

    test('描边关闭：内容盒 = 条本身 32×18，两态各自重算落位且都严格对称', () {
      final stroked = planHandleBar(
        slotWidth: 48,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      final plain = planHandleBar(
        slotWidth: 48,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: false,
      );
      expect(plain.strokeWidth, 0);
      expect(plain.contentWidth, 32);
      expect(plain.contentHeight, 18);
      expect(plain.grooves.length, 4);
      // 内容盒高 18 → 纹高同奇偶取 8（不是 9）；竖直余量各 5。
      expect(plain.grooves.first.height, 8);
      expect(plain.grooves.first.top, 5);
      // 端距 = (32 − 4×2)/5 = 4.8dp，与描边开态的 4.4dp 不同（各自重算）。
      expect(plain.grooves.first.left, closeTo(4.8, 1e-9));
      final gaps = <double>[
        plain.grooves.first.left,
        for (var i = 1; i < plain.grooves.length; i++)
          plain.grooves[i].left -
              (plain.grooves[i - 1].left + plain.grooves[i - 1].width),
        plain.contentWidth -
            (plain.grooves.last.left + plain.grooves.last.width),
      ];
      for (final gap in gaps) {
        expect(gap, closeTo(4.8, 1e-9));
      }
      expectSymmetric(plain);
      // 两态互为对照：开态内容盒 30、关态 32，落位不同。
      expect(
        stroked.grooves.first.left,
        isNot(closeTo(plain.grooves.first.left, 1e-6)),
      );
    });

    test('槽压窄：条宽 = min(条宽上限, 槽宽)', () {
      final plan = planHandleBar(
        slotWidth: 20,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      expect(plan.barWidth, 20);
    });

    test('条高 = 行高：行内偏移 0 且不越界', () {
      final plan = planHandleBar(
        slotWidth: 48,
        maxBarWidth: 32,
        barHeight: 30,
        rowHeight: 30,
        stroked: true,
      );
      expect(plan.rowOffsetY, 0);
      expect(plan.rowOffsetY + plan.barHeight, lessThanOrEqualTo(30));
    });

    test('密集退化：条宽 40/32/24/12/8dp → 纹数 5/4/3/2/0', () {
      int grooveCount(double barWidth) => planHandleBar(
        slotWidth: barWidth,
        maxBarWidth: barWidth,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      ).grooves.length;
      expect(grooveCount(40), 5);
      expect(grooveCount(32), 4);
      expect(grooveCount(24), 3);
      expect(grooveCount(12), 2);
      expect(grooveCount(8), 0, reason: '<12dp 无纹');
    });

    test('内容盒放不下：纹数在分档之下继续减，但条矩形与圆角仍在', () {
      // 条高 30、描边开 → 内容盒高 28 → 纹宽 2、纹高 14：条宽 18 分档
      // 给 3 条，3×2+4×1=10 ≤ 16 放得下；用条宽 18、条高 4（描边开 →
      // 内容盒高 2、纹高 0）验证纹高不足时清空为实心胶囊。
      final plan = planHandleBar(
        slotWidth: 18,
        maxBarWidth: 18,
        barHeight: 4,
        rowHeight: 30,
        stroked: true,
      );
      expect(plan.grooves, isEmpty, reason: '纹高不足 1dp → 无纹');
      expect(plan.barWidth, 18);
      expect(plan.cornerRadius, 2);
    });

    test('0 条：仍输出实心胶囊计划（条矩形、圆角齐全），不是空计划', () {
      final plan = planHandleBar(
        slotWidth: 8,
        maxBarWidth: 8,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      expect(plan.grooves, isEmpty);
      expect(plan.barWidth, 8);
      expect(plan.barHeight, 18);
      expect(plan.cornerRadius, 9);
      expect(plan.strokeWidth, 1);
      expect(plan.rowOffsetY, 6);
    });

    test('全组合不越界：条宽 16–48 × 条高 4–30 × 描边开关', () {
      for (var width = 16.0; width <= 48.0; width += 1) {
        for (var height = 4.0; height <= 30.0; height += 1) {
          for (final stroked in [true, false]) {
            final plan = planHandleBar(
              slotWidth: width,
              maxBarWidth: width,
              barHeight: height,
              rowHeight: 30,
              stroked: stroked,
            );
            final label = '条 $width×$height 描边$stroked';
            expect(plan.cornerRadius, height / 2, reason: label);
            expect(plan.rowOffsetY, greaterThanOrEqualTo(0), reason: label);
            expect(
              plan.rowOffsetY + plan.barHeight,
              lessThanOrEqualTo(30),
              reason: label,
            );
            for (final g in plan.grooves) {
              expect(g.left, greaterThanOrEqualTo(0), reason: label);
              expect(g.top, greaterThanOrEqualTo(0), reason: label);
              expect(
                g.left + g.width,
                lessThanOrEqualTo(plan.contentWidth + 1e-9),
                reason: label,
              );
              expect(
                g.top + g.height,
                lessThanOrEqualTo(plan.contentHeight + 1e-9),
                reason: label,
              );
              expect(g.width, greaterThan(0), reason: label);
              expect(g.height, greaterThan(0), reason: label);
            }
            // 缝非负（相邻纹间、端距）。
            for (var i = 1; i < plan.grooves.length; i++) {
              expect(
                plan.grooves[i].left -
                    (plan.grooves[i - 1].left + plan.grooves[i - 1].width),
                greaterThanOrEqualTo(-1e-9),
                reason: label,
              );
            }
            // 端距对称：左端距 = 右端距。
            if (plan.grooves.isNotEmpty) {
              expect(
                plan.grooves.first.left,
                closeTo(
                  plan.contentWidth -
                      (plan.grooves.last.left + plan.grooves.last.width),
                  1e-9,
                ),
                reason: label,
              );
            }
          }
        }
      }
    });
  });

  group('绘制期设备像素对齐', () {
    test('纹矩形左右缘按 dpr 吸附到设备像素栅格（32dp 条 4.4dp 缝不取整到某一侧）', () {
      final plan = planHandleBar(
        slotWidth: 32,
        maxBarWidth: 32,
        barHeight: 18,
        rowHeight: 30,
        stroked: true,
      );
      const dpr = 1.0;
      final snapped = plan.grooves
          .map((g) => snapRectToDevicePixels(g, dpr))
          .toList();
      for (final g in snapped) {
        expect((g.left * dpr) % 1, 0, reason: '左缘在栅格上');
        expect((g.right * dpr) % 1, 0, reason: '右缘在栅格上');
      }
      // 等距保持：相邻缝一致（容差 = 一次取整的半像素）。
      for (var i = 1; i + 1 < snapped.length; i++) {
        final gapA =
            snapped[i].left - (snapped[i - 1].left + snapped[i - 1].width);
        final gapB = snapped[i + 1].left - (snapped[i].left + snapped[i].width);
        expect(gapA, closeTo(gapB, 1 / dpr), reason: '缝均匀');
      }
      // 纹宽不因吸附跑出 plan 的 2dp ± 半像素。
      for (final g in snapped) {
        expect(g.width, closeTo(plan.grooves.first.width, 1 / dpr));
      }
    });

    test('snapToDevicePixel：条左缘 24.3 在 1× 下吸到 24（条缘归栅格）', () {
      expect(snapToDevicePixel(24.3, 1.0), 24.0);
      expect(snapToDevicePixel(24.6, 1.0), 25.0);
      expect(
        snapToDevicePixel(24.5, 3.0),
        closeTo(74 / 3, 1e-9),
        reason: '24.5×3=73.5 → Dart 四舍五入取 74',
      );
    });
  });
}
