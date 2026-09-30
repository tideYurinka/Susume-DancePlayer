import 'dart:math' as math;

import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/beat_track_tiers.dart';

import '../helpers/beat_presentation_value.dart' show presentationValueFor;

import 'package:dance_learning_app/player/metronome_sound.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc
    show BeatGrid, BeatPoint, MarkersDocument;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实网格文档（4 拍：0.5s 起，每 0.5s 一拍，第 1 拍 downbeat）。
marker_doc.MarkersDocument docWithBeats() => marker_doc.MarkersDocument(
  beat: marker_doc.BeatGrid(
    model: 'madmom_downbeat_rnn_full.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2026, 9, 6),
    beats: [
      marker_doc.BeatPoint(t: 0.5, down: true),
      marker_doc.BeatPoint(t: 1.0, down: false),
      marker_doc.BeatPoint(t: 1.5, down: false),
      marker_doc.BeatPoint(t: 2.0, down: false),
    ],
  ),
);

/// 读大方块格第 i 格的装饰（key 挂在 Positioned 上，取其 Container 子代）。
BoxDecoration _blockDecoration(WidgetTester tester, int i) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byKey(Key('beat_anim_block_$i')),
      matching: find.byType(Container),
    ),
  );
  return container.decoration! as BoxDecoration;
}

/// 按发布值泵入动画组件（widget seam：widget 只
/// 读发布值）。
Future<void> pumpValue(
  WidgetTester tester,
  BeatAnimationStyle style,
  BeatPresentationValue value, {
  double hostWidth = 160,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: hostWidth,
            child: MetronomeBeatAnimation(style: style, value: value),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // 占位均匀网格 120 bpm：一拍 500ms。
  const grid = UniformBeatGrid();

  group('连续游标相位 deriveBeatPhase（纯函数 seam）', () {
    test('拍内推进给出拍序号与拍内连续相位', () {
      final phase = deriveBeatPhase(
        grid: grid,
        position: const Duration(milliseconds: 1250),
        phase: BeatPhase(grid: grid),
      );
      expect(phase.beatInCycle, 2);
      expect(phase.beatFraction, closeTo(0.5, 1e-6));
      expect(phase.cyclePhase, closeTo(2.5 / 8, 1e-6));
    });

    test('八拍大周期：cyclePhase 在 [0, 1) 内随位置单调连续', () {
      for (var ms = 0; ms <= 3900; ms += 10) {
        final a = deriveBeatPhase(
          grid: grid,
          position: Duration(milliseconds: ms),
          phase: BeatPhase(grid: grid),
        );
        final b = deriveBeatPhase(
          grid: grid,
          position: Duration(milliseconds: ms + 10),
          phase: BeatPhase(grid: grid),
        );
        expect(a.cyclePhase, lessThan(1.0));
        expect(b.cyclePhase, greaterThanOrEqualTo(a.cyclePhase));
        // 相邻采样步进连续（无跳断）。
        expect(b.cyclePhase - a.cyclePhase, lessThan(0.01));
      }
    });

    test('换拍/换八拍不跳断：跨拍边界相位连续推进', () {
      final before = deriveBeatPhase(
        grid: grid,
        position: const Duration(milliseconds: 1499),
        phase: BeatPhase(grid: grid),
      );
      final after = deriveBeatPhase(
        grid: grid,
        position: const Duration(milliseconds: 1501),
        phase: BeatPhase(grid: grid),
      );
      expect(after.cyclePhase - before.cyclePhase, closeTo(0.002 / 4.0, 0.01));
      expect(after.beatInCycle, 3);
    });

    test('八拍首（第 1 拍）与小节首（第 5 拍）为强拍标记', () {
      final eightStart = deriveBeatPhase(
        grid: grid,
        position: Duration.zero,
        phase: BeatPhase(grid: grid),
      );
      expect(eightStart.beatInCycle, 0);
      expect(eightStart.isEightStart, isTrue);
      expect(eightStart.isBarStart, isFalse);

      final barStart = deriveBeatPhase(
        grid: grid,
        position: const Duration(seconds: 2),
        phase: BeatPhase(grid: grid),
      );
      expect(barStart.beatInCycle, 4);
      expect(barStart.isBarStart, isTrue);
      expect(barStart.isEightStart, isFalse);

      final plain = deriveBeatPhase(
        grid: grid,
        position: const Duration(milliseconds: 500),
        phase: BeatPhase(grid: grid),
      );
      expect(plain.isEightStart, isFalse);
      expect(plain.isBarStart, isFalse);
    });

    test('非均匀 downbeat 网格：动画八拍首与轨道大线/相位源同判（登记修正）', () {
      // downbeat 序列不按 beatsPerBar 周期铺（0、8、12：真实网格漏检一
      // 条 downbeat 的形态），拍距均匀但 downbeat 间距非均匀：索引算术
      //（rel ~/ beatsPerBar 奇偶）与序数法在拍 8、12 处分歧；序数法为
      // 唯一语义，动画须与轨道大线同判。
      const grid = _NonUniformDownbeatGrid();
      final ticks = beatTrackTicks(
        grid,
        Duration.zero,
        const Duration(seconds: 20),
        phase: BeatPhase(grid: grid),
      );
      final bigLines = [
        for (final tick in ticks)
          if (tick.tier == BeatTickTier.eightBar) tick.time,
      ];
      final noAnchor = BeatPhase(grid: grid);
      for (var index = 0; index <= 15; index++) {
        if (!grid.isDownbeat(index)) continue;
        final phase = deriveBeatPhase(
          grid: grid,
          position: grid.beatTime(index),
          phase: noAnchor,
        );
        expect(
          phase.isEightStart,
          noAnchor.isEightBeatPoint(index),
          reason: '拍 $index：动画与相位源应同判',
        );
        expect(
          bigLines.contains(grid.beatTime(index)),
          phase.isEightStart,
          reason: '拍 $index：动画八拍首应与轨道大线同判',
        );
      }
      // 钉死分歧点：拍 8 序数为 2（四拍中线，旧索引算术误判八拍首）、
      // 拍 12 序数为 3（八拍首，旧索引算术误判小节首）。
      expect(
        deriveBeatPhase(
          grid: grid,
          position: grid.beatTime(8),
          phase: noAnchor,
        ).isEightStart,
        isFalse,
      );
      expect(
        deriveBeatPhase(
          grid: grid,
          position: grid.beatTime(12),
          phase: noAnchor,
        ).isEightStart,
        isTrue,
      );
    });

    test('真实网格（有界）：早于首拍的时间钳制到首拍相位 0', () {
      const bounded = _BoundedGrid();
      final phase = deriveBeatPhase(
        grid: bounded,
        position: Duration.zero,
        phase: BeatPhase(grid: bounded),
      );
      expect(phase.beatInCycle, 0);
      expect(phase.beatFraction, 0);
      expect(phase.cyclePhase, 0);
    });

    test('时钟纪律：长播 40 拍逐帧推进，每个拍点相位精确归位（无累积漂移）', () {
      // 100ms 步进推进 20s（40 拍，覆盖 5 个八拍大周期）：相位只由位置
      // 派生，拍序号全程精确；每个拍点边界 beatFraction 恒为 0（无独立
      // 时钟状态累积偏移）。
      for (var ms = 0; ms <= 20000; ms += 100) {
        final phase = deriveBeatPhase(
          grid: grid,
          position: Duration(milliseconds: ms),
          phase: BeatPhase(grid: grid),
        );
        expect(phase.beatInCycle, (ms ~/ 500) % 8, reason: '位置 $ms 处拍序号应精确归位');
        if (ms % 500 == 0) {
          expect(phase.beatFraction, 0, reason: '拍点边界拍内相位应为 0');
        }
      }
    });

    test('时钟纪律：变速与 seek 到同一位置相位一致（无独立时钟状态泄漏）', () {
      // 位置是唯一时钟：1×（每帧 100ms 位置步进）与 2×（同样墙钟时间下
      // 每帧位置步进翻倍）推进 12s 后，以及直接 seek 到 12s，相位完全
      // 一致（纯函数无内部时钟状态，倍速差异被位置输入吸收）。
      const target = Duration(seconds: 12);
      final step1x = Duration(milliseconds: 100);
      final step2x = Duration(milliseconds: 200);
      for (final step in [step1x, step2x]) {
        var position = Duration.zero;
        while (position < target) {
          position += step;
        }
        final phase = deriveBeatPhase(
          grid: grid,
          position: position,
          phase: BeatPhase(grid: grid),
        );
        final direct = deriveBeatPhase(
          grid: grid,
          position: target,
          phase: BeatPhase(grid: grid),
        );
        expect(phase.cyclePhase, direct.cyclePhase);
        expect(phase.beatInCycle, direct.beatInCycle);
      }
      // 12s = 第 24 拍 = 八拍相位 0：相位与位置推导一致（精确归位）。
      final atBeat = deriveBeatPhase(
        grid: grid,
        position: target,
        phase: BeatPhase(grid: grid),
      );
      expect(atBeat.beatInCycle, 0);
      expect(atBeat.beatFraction, 0);
      expect(atBeat.isEightStart, isTrue);
    });
  });

  group('矩形/摆锤形态切换（widget seam，读发布值）', () {
    Future<void> pumpStyle(
      WidgetTester tester,
      BeatAnimationStyle style, {
      List<Duration> halfBeatLines = const [],
      Duration position = const Duration(milliseconds: 1000),
      double hostWidth = 160,
      BeatGrid beatGrid = const UniformBeatGrid(),
      BeatPhase? phase,
    }) async {
      await pumpValue(
        tester,
        style,
        presentationValueFor(
          grid: beatGrid,
          position: position,
          phase: phase,
          halfBeatLines: halfBeatLines,
        ),
        hostWidth: hostWidth,
      );
    }

    testWidgets('矩形形态渲染大方块格（格 + 游标 + 拖尾）', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      expect(find.byKey(const Key('beat_anim_bar')), findsOneWidget);
      expect(find.byKey(const Key('beat_anim_cursor')), findsOneWidget);
      expect(find.byKey(const Key('beat_anim_fill')), findsOneWidget);
    });

    testWidgets('摆锤形态渲染摆锤，不再渲染进度条', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.pendulum);
      expect(find.byKey(const Key('beat_anim_pendulum')), findsOneWidget);
      expect(find.byKey(const Key('beat_anim_bar')), findsNothing);
    });

    testWidgets('摆锤在真实宿主（无固定高 Column）下高度 > 0 且中轴全高可见', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 160,
                    child: MetronomeBeatAnimation(
                      style: BeatAnimationStyle.pendulum,
                      value: presentationValueFor(
                        grid: grid,
                        position: const Duration(milliseconds: 1000),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final pendulumRect = tester.getRect(
        find.byKey(const Key('beat_anim_pendulum')),
      );
      expect(pendulumRect.height, greaterThan(0));
      final axisRect = tester.getRect(
        find.byKey(const Key('beat_anim_pendulum_axis')),
      );
      expect(axisRect.height, closeTo(pendulumRect.height, 0.5));
      expect(axisRect.width, closeTo(1, 0.5));
    });

    testWidgets('形态切换：同参数换形态渲染目标形态', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      expect(find.byKey(const Key('beat_anim_bar')), findsOneWidget);
      await pumpStyle(tester, BeatAnimationStyle.pendulum);
      expect(find.byKey(const Key('beat_anim_pendulum')), findsOneWidget);
      expect(find.byKey(const Key('beat_anim_bar')), findsNothing);
    });

    testWidgets('矩形游标按全域相位连续推进（2 拍位置 → 游标在 25%）', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      final cursor = tester.getRect(find.byKey(const Key('beat_anim_cursor')));
      final fraction = (cursor.left - barRect.left) / barRect.width;
      expect(fraction, closeTo(0.25, 0.02));
    });

    // 强拍边界竖线：色 = 原强拍格描边色（#4A5A6B）。
    const strongLineColor = Color(0xFF4A5A6B);
    const strongLineWidth = 2.0;

    testWidgets('8 格描边逐格一致：四边同宽同色，无某格三粗一细', (tester) async {
      // 4/4 网格：窗口 [0,8) 的强拍格 = 0、4。验收要求任何一格的四边粗细
      // 与颜色逐位相同——强拍不再改变格描边。
      await pumpStyle(tester, BeatAnimationStyle.bar);
      for (var i = 0; i < 8; i++) {
        final border = _blockDecoration(tester, i).border! as Border;
        final edges = [
          border.top,
          border.bottom,
          border.right,
          if (i == 0) border.left,
        ];
        for (final edge in edges) {
          expect(edge.width, 1.0, reason: '格 $i 描边宽');
          expect(edge.color, const Color(0xFF2A313D), reason: '格 $i 描边色');
        }
      }
    });

    testWidgets('4/4：第 4、5 格之间画 2px 强拍竖线，中心压在边界上', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      // 窗口内强拍边界 = 第 4 格左缘（八拍首 offset 0 与 4 之间只画后者）。
      final line = tester.getRect(
        find.byKey(const Key('beat_anim_strong_line_4')),
      );
      final slot = barRect.width / 8;
      expect(line.center.dx - barRect.left, closeTo(4 * slot, 0.5));
      expect(line.width, strongLineWidth);
      expect(line.top, barRect.top);
      expect(line.bottom, barRect.bottom);
      final color = tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byKey(const Key('beat_anim_strong_line_4')),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      expect(color, strongLineColor);
      // 其余格边界（含第 0 格 = 窗口左端）不画。
      for (final i in [0, 1, 2, 3, 5, 6, 7]) {
        expect(
          find.byKey(Key('beat_anim_strong_line_$i')),
          findsNothing,
          reason: '边界 $i 不应有强拍竖线',
        );
      }
    });

    testWidgets('强拍边界竖线由网格派生驱动（非 4/4 网格下同样正确）', (tester) async {
      // 3/4 网格：八拍点 = 拍 0/6/12…（周期 = beatsPerBar × 2 = 6），
      // 八拍窗口首拍 = 相位源给出的最近八拍点——窗口内强拍格 = 该窗口的
      // downbeat（偏移随窗口首拍走，不再由 `(index − firstDownbeat) % 8`
      // 的索引算术决定；归并）。
      Future<void> pump3_4(int offset) => pumpStyle(
        tester,
        BeatAnimationStyle.bar,
        beatGrid: const _ThreeFourGrid(),
        position: Duration(milliseconds: offset * 500 + 100),
      );

      double lineCenter(int i, Rect barRect) =>
          tester
              .getRect(find.byKey(Key('beat_anim_strong_line_$i')))
              .center
              .dx -
          barRect.left;

      await pump3_4(0);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      final slot = barRect.width / 8;
      // 窗口 [0,8)：全局拍 0/3/6 为强拍（0、6 = 八拍首，3 = 小节首）；
      // 窗口左端（offset 0）不画，故只画 3、6 两条边界线。
      expect(lineCenter(3, barRect), closeTo(3 * slot, 0.5));
      expect(lineCenter(6, barRect), closeTo(6 * slot, 0.5));
      for (final i in [0, 1, 2, 4, 5, 7]) {
        expect(find.byKey(Key('beat_anim_strong_line_$i')), findsNothing);
      }
      // 格描边一律普通取值。
      double strokeWidth(int i) =>
          _blockDecoration(tester, i).border!.top.width;
      for (var i = 0; i < 8; i++) {
        expect(strokeWidth(i), 1, reason: '格 $i');
      }

      // 换窗口：位置 = 拍 9 → 相位窗口首拍 = 最近的八拍点 6，窗口 [6,14)；
      // 全局拍 6/9/12 为强拍（6、12 = 八拍首，9 = 小节首）。
      await pump3_4(9);
      final window = deriveBeatPhase(
        grid: const _ThreeFourGrid(),
        position: const Duration(milliseconds: 4600),
        phase: BeatPhase(grid: const _ThreeFourGrid()),
      );
      expect(window.windowFirstBeatIndex, 6, reason: '窗口首拍 = 最近八拍点');
      final nextBarRect = tester.getRect(
        find.byKey(const Key('beat_anim_bar')),
      );
      final nextSlot = nextBarRect.width / 8;
      // 窗口左端（全局拍 6，offset 0）不画；画 9、12 两条边界线。
      expect(lineCenter(3, nextBarRect), closeTo(3 * nextSlot, 0.5));
      expect(lineCenter(6, nextBarRect), closeTo(6 * nextSlot, 0.5));
      for (final i in [0, 1, 2, 4, 5, 7]) {
        expect(find.byKey(Key('beat_anim_strong_line_$i')), findsNothing);
      }
    });

    testWidgets('有界网格：窗口末格恰为末拍时强拍竖线按拍派生（衔接）', (tester) async {
      // _BoundedGrid 末拍序号 15；位置 8500ms → 窗口 [8,16)，8 格恰为全局
      // 拍 8–15，末格即末拍。
      await pumpStyle(
        tester,
        BeatAnimationStyle.bar,
        beatGrid: const _BoundedGrid(),
        position: const Duration(milliseconds: 8500),
      );
      expect(tester.takeException(), isNull);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      final slot = barRect.width / 8;
      // 窗口 [8,16)：全局拍 12 为小节首 → 边界线在 offset 4；offset 0 为
      // 窗口左端不画；offset 7 的边界拍 15 非强拍，无线。
      expect(
        tester
                .getRect(find.byKey(const Key('beat_anim_strong_line_4')))
                .center
                .dx -
            barRect.left,
        closeTo(4 * slot, 0.5),
      );
      for (final i in [0, 1, 2, 3, 5, 6, 7]) {
        expect(find.byKey(Key('beat_anim_strong_line_$i')), findsNothing);
      }
      // 描边一律普通取值。
      for (var i = 0; i < 8; i++) {
        expect(
          _blockDecoration(tester, i).border!.top.width,
          1,
          reason: '格 $i',
        );
      }
    });

    testWidgets('有界网格：窗口越过末拍时强拍竖线不派生、不越界抛错（衔接）', (tester) async {
      // 末拍序号 14（8s）；位置 7500ms 落在末拍上 → 窗口 [8,16) 越过末拍，
      // 全局拍 15 起无拍可派生。强拍边界守卫（边界越过末拍不派生）在发布值
      // 求值侧（beat_presentation）触发。
      await pumpStyle(
        tester,
        BeatAnimationStyle.bar,
        beatGrid: const _BoundedGrid(lastBeatIndex: 14),
        position: const Duration(milliseconds: 7500),
      );
      expect(tester.takeException(), isNull);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      final slot = barRect.width / 8;
      // 全局拍 8 为八拍首（offset 0，窗口左端不画）、拍 12 为小节首 →
      // offset 4 有线；offset 5–7 越过末拍，无派生、不抛错。
      expect(
        tester
                .getRect(find.byKey(const Key('beat_anim_strong_line_4')))
                .center
                .dx -
            barRect.left,
        closeTo(4 * slot, 0.5),
      );
      for (final i in [0, 1, 2, 3, 5, 6, 7]) {
        expect(find.byKey(Key('beat_anim_strong_line_$i')), findsNothing);
      }
      // 越界边界若无限定本会是强拍（拍 16 原为小节首）——线上无竖线是守卫
      // 生效的证据，而非碰巧不强。
      expect(
        BeatPhase(grid: const _BoundedGrid(lastBeatIndex: 14)).isStrongBeat(16),
        isTrue,
      );
      for (var i = 0; i < 8; i++) {
        expect(
          _blockDecoration(tester, i).border!.top.width,
          1,
          reason: '格 $i',
        );
      }
    });

    testWidgets('用户半拍线 x == 所在格几何正中（无缝布局下格中心）', (tester) async {
      await pumpStyle(
        tester,
        BeatAnimationStyle.bar,
        // 1250ms = 第 3 拍（偏移 2）拍中。
        halfBeatLines: const [Duration(milliseconds: 1250)],
      );
      final line = tester.getRect(
        find.byKey(const Key('beat_anim_user_half_0')),
      );
      final cell = tester.getRect(find.byKey(const Key('beat_anim_block_2')));
      expect(line.center.dx, closeTo(cell.center.dx, 0.5));
    });

    testWidgets('8 格 + 块内弱显拍号 1–8（16px w800，白 35%，当前格深色）', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      for (var i = 0; i < 8; i++) {
        expect(find.byKey(Key('beat_anim_block_$i')), findsOneWidget);
      }
      for (var i = 0; i < 8; i++) {
        final text = tester.widget<Text>(
          find.byKey(Key('beat_anim_beat_number_$i')),
        );
        expect(text.data, '${i + 1}');
        expect(text.style!.fontSize, 16);
        expect(text.style!.fontWeight, FontWeight.w800);
        // 当前格（position 1000ms → beatInCycle 2）深色，其余白 35%。
        if (i == 2) {
          expect(text.style!.color, kBeatHalfLineDeepenedColor);
        } else {
          expect(text.style!.color, Colors.white.withValues(alpha: 0.35));
        }
      }
    });

    testWidgets('8 格无缝等分整条：格宽 = 内容宽/8、无 gap、无行尾悬空', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      const cells = 8;
      Rect? previous;
      for (var i = 0; i < cells; i++) {
        final rect = tester.getRect(find.byKey(Key('beat_anim_block_$i')));
        expect(rect.width, closeTo(barRect.width / cells, 0.5));
        expect(rect.top, barRect.top);
        expect(rect.bottom, barRect.bottom);
        if (previous != null) {
          expect(rect.left, closeTo(previous.right, 0.5), reason: '格 $i 无缝');
        }
        previous = rect;
      }
      // 行尾不悬空：末格右缘 == 整条右缘。
      expect(previous!.right, closeTo(barRect.right, 0.5));
    });

    testWidgets('栏宽随宿主宽铺满（不再固定 160）', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar, hostWidth: 240);
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      expect(barRect.width, closeTo(240, 0.5));
      final block0 = tester.getRect(find.byKey(const Key('beat_anim_block_0')));
      expect(block0.width, closeTo(240 / 8, 0.5));
    });

    testWidgets('当前格整块亮青（其余格暗底）', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      Color bgColor(int i) => _blockDecoration(tester, i).color!;
      // position 1000ms → 第 3 拍（beatInCycle 2）。
      expect(
        deriveBeatPhase(
          grid: grid,
          position: const Duration(milliseconds: 1000),
          phase: BeatPhase(grid: grid),
        ).beatInCycle,
        2,
      );
      expect(bgColor(2), kCyanAccentColor);
      expect(bgColor(0), isNot(kCyanAccentColor));
      expect(bgColor(7), isNot(kCyanAccentColor));
    });

    testWidgets('无强拍网格（占位/异常回退）：不画强拍竖线，既有回退行为不变', (tester) async {
      // 无 downbeat 的有界网格 = 强拍判定取不到任何拍，回退到索引算术窗口；
      // 强拍竖线此态一条都派生不出来，格描边仍一律普通取值。
      await pumpStyle(
        tester,
        BeatAnimationStyle.bar,
        beatGrid: const _NoStrongBeatGrid(),
        position: const Duration(milliseconds: 1000),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is Key &&
              (w.key as Key).toString().contains('beat_anim_strong_line'),
        ),
        findsNothing,
      );
      for (var i = 0; i < 8; i++) {
        expect(
          _blockDecoration(tester, i).border!.top.width,
          1,
          reason: '格 $i',
        );
        // 格内数字与当前格亮青照旧。
        expect(find.byKey(Key('beat_anim_beat_number_$i')), findsOneWidget);
      }
      expect(_blockDecoration(tester, 2).color, kCyanAccentColor);
    });

    testWidgets('强拍竖线与拖尾、游标线、用户半拍线同层且不打架（绘制次序正确）', (tester) async {
      // 游标停在八拍首（position 0 → cursorX 0）、拖尾宽 0；强拍边界线在
      // 第 4 格左缘。竖线画在格层之上、拖尾/格内数字/半拍线/游标之下。
      await pumpStyle(
        tester,
        BeatAnimationStyle.bar,
        position: Duration.zero,
        halfBeatLines: const [Duration(milliseconds: 2250)], // 第 5 拍拍中
      );
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      final slot = barRect.width / 8;
      final line = tester.getRect(
        find.byKey(const Key('beat_anim_strong_line_4')),
      );
      final cursor = tester.getRect(find.byKey(const Key('beat_anim_cursor')));
      final halfLine = tester.getRect(
        find.byKey(const Key('beat_anim_user_half_0')),
      );
      // 三条竖线各有其位，互不重合（强拍线在第 4 格左缘、游标在窗口左端、
      // 用户半拍线在第 5 格拍中）。
      expect(line.center.dx - barRect.left, closeTo(4 * slot, 0.5));
      expect(cursor.center.dx - barRect.left, closeTo(0, 0.5));
      expect(halfLine.center.dx - barRect.left, closeTo(4.5 * slot, 0.5));
      // Stack 直系子级次序：强拍线在所有格之后、拖尾与游标之前。
      final stack = tester.widget<Stack>(
        find.descendant(
          of: find.byKey(const Key('beat_anim_bar')),
          matching: find.byType(Stack),
        ),
      );
      int indexOf(Key key) => stack.children.indexWhere((w) => w.key == key);
      final strongLineIndex = indexOf(const Key('beat_anim_strong_line_4'));
      expect(
        strongLineIndex,
        greaterThan(indexOf(const Key('beat_anim_block_7'))),
      );
      expect(strongLineIndex, lessThan(indexOf(const Key('beat_anim_fill'))));
      expect(
        strongLineIndex,
        lessThan(indexOf(const Key('beat_anim_user_half_0'))),
      );
      expect(strongLineIndex, lessThan(indexOf(const Key('beat_anim_cursor'))));
    });

    testWidgets('无自动半拍刻度（细条观感的半拍细分线不再渲染）', (tester) async {
      await pumpStyle(tester, BeatAnimationStyle.bar);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is Key &&
              (w.key as Key).toString().contains('beat_anim_half_line'),
        ),
        findsNothing,
      );
    });

    group('格内用户半拍线', () {
      testWidgets('窗口内标记按相对所属拍相位投影到格内 x', (tester) async {
        await pumpStyle(
          tester,
          BeatAnimationStyle.bar,
          halfBeatLines: const [Duration(milliseconds: 1250)],
        );
        expect(find.byKey(const Key('beat_anim_user_half_0')), findsOneWidget);
        final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
        final line = tester.getRect(
          find.byKey(const Key('beat_anim_user_half_0')),
        );
        // 1250ms = 第 3 拍（偏移 2）拍中 → x = (2.5/8) × 160 = 50。
        expect(line.center.dx - barRect.left, closeTo(50, 1));
      });

      testWidgets('当前八拍窗口外的标记不画', (tester) async {
        await pumpStyle(
          tester,
          BeatAnimationStyle.bar,
          // position 1000ms → 窗口 = 第 0–7 拍；4500ms 属第 9 拍（窗口外）。
          halfBeatLines: const [Duration(milliseconds: 4500)],
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w.key is Key &&
                (w.key as Key).toString().contains('beat_anim_user_half'),
          ),
          findsNothing,
        );
      });

      testWidgets('同格多条都画', (tester) async {
        await pumpStyle(
          tester,
          BeatAnimationStyle.bar,
          halfBeatLines: const [
            Duration(milliseconds: 1000),
            Duration(milliseconds: 1250),
          ],
        );
        expect(find.byKey(const Key('beat_anim_user_half_0')), findsOneWidget);
        expect(find.byKey(const Key('beat_anim_user_half_1')), findsOneWidget);
      });

      testWidgets('当前格亮青时格内半拍线加深，其余格保持冷灰蓝', (tester) async {
        await pumpStyle(
          tester,
          BeatAnimationStyle.bar,
          // 第 3 拍（当前格）拍中 1250ms + 第 1 拍（非当前格）拍中 250ms。
          halfBeatLines: const [
            Duration(milliseconds: 1250),
            Duration(milliseconds: 250),
          ],
        );
        Color colorOf(int j) => tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byKey(Key('beat_anim_user_half_$j')),
                matching: find.byType(ColoredBox),
              ),
            )
            .color;
        // 投影按格序排序：user_half_0 = 第 1 拍（非当前格），user_half_1 =
        // 第 3 拍（当前格亮青）。
        expect(colorOf(0), kBeatHalfSubdivisionColor);
        expect(colorOf(1), kBeatHalfLineDeepenedColor);
        // 加深态略加粗：当前格线 2px、其余格 1px。
        double widthOf(int j) =>
            tester.getRect(find.byKey(Key('beat_anim_user_half_$j'))).width;
        expect(widthOf(0), 1);
        expect(widthOf(1), 2);
      });

      testWidgets('摆锤形态不画半拍线', (tester) async {
        await pumpStyle(
          tester,
          BeatAnimationStyle.pendulum,
          halfBeatLines: const [Duration(milliseconds: 1250)],
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w.key is Key &&
                (w.key as Key).toString().contains('beat_anim_user_half'),
          ),
          findsNothing,
        );
      });
    });

    testWidgets('摆锤一摆一拍：拍首在端点、拍中过中线；强拍摆幅略大', (tester) async {
      Future<void> pumpAt(Duration position) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 160,
                  child: MetronomeBeatAnimation(
                    style: BeatAnimationStyle.pendulum,
                    value: presentationValueFor(grid: grid, position: position),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await pumpAt(Duration.zero);
      expect(find.byKey(const Key('beat_anim_pendulum')), findsOneWidget);

      // 八拍首（强拍）拍首：摆到 -1 端点。
      expect(
        deriveBeatPhase(
          grid: grid,
          position: Duration.zero,
          phase: BeatPhase(grid: grid),
        ).isEightStart,
        isTrue,
      );
      expect(
        pendulumSwing(
          deriveBeatPhase(
            grid: grid,
            position: Duration.zero,
            phase: BeatPhase(grid: grid),
          ),
        ),
        closeTo(-1.0, 1e-6),
      );

      // 一摆一拍：拍中过中线（符号翻转点）。
      expect(
        pendulumSwing(
          deriveBeatPhase(
            grid: grid,
            position: const Duration(milliseconds: 1250),
            phase: BeatPhase(grid: grid),
          ),
        ),
        closeTo(0.0, 1e-6),
      );

      // 强拍摆幅（1.0）大于普通拍摆幅（同相位、非拍中点比较）。
      final strongAmplitude = pendulumSwing(
        deriveBeatPhase(
          grid: grid,
          position: const Duration(milliseconds: 375),
          phase: BeatPhase(grid: grid),
        ),
      ).abs();
      final normalAmplitude = pendulumSwing(
        deriveBeatPhase(
          grid: grid,
          position: const Duration(milliseconds: 3375),
          phase: BeatPhase(grid: grid),
        ),
      ).abs();
      expect(strongAmplitude, closeTo(0.5, 1e-6));
      expect(normalAmplitude, lessThan(strongAmplitude));
    });
  });

  group('节拍动画跟八拍锚点（游标格与强拍格同一相位源）', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required BeatGrid grid,
      required Duration position,
      BeatPhase? phase,
    }) async {
      await pumpValue(
        tester,
        BeatAnimationStyle.bar,
        presentationValueFor(grid: grid, position: position, phase: phase),
      );
    }

    Color cellColor(WidgetTester tester, int i) =>
        _blockDecoration(tester, i).color!;

    double cellStroke(WidgetTester tester, int i) =>
        _blockDecoration(tester, i).border!.top.width;

    test('无锚点：动画相位与今日逐位一致（回归基线：旧公式独立复算）', () {
      // 独立复算今日（main 上）的实现口径——游标格 = `(拍序号 − 首个强拍)
      // % 8` 的索引算术、八拍首 = 相位源（序数法）、小节首 =
      // `rel % beatsPerBar == 0 且非八拍首`；不调用被测实现，故能真正与
      // 旧行为对照（均匀网格下两套口径逐位等价，回归基线）。
      void expectMatchesToday(BeatGrid grid, String label) {
        final source = BeatPhase(grid: grid);
        for (var ms = 0; ms <= 20000; ms += 50) {
          final position = Duration(milliseconds: ms);
          final actual = deriveBeatPhase(
            grid: grid,
            position: position,
            phase: source,
          );
          final index = math.max(grid.beatIndexAt(position), 0);
          final rel = index - grid.firstDownbeatIndex;
          final todayBeatInCycle = ((rel % 8) + 8) % 8;
          final todayEightStart = source.isEightBeatPoint(index);
          final todayBarStart =
              grid.isDownbeat(index) &&
              ((rel % grid.beatsPerBar) + grid.beatsPerBar) %
                      grid.beatsPerBar ==
                  0 &&
              !todayEightStart;
          expect(actual.beatIndex, index, reason: '$label $ms ms 拍序号');
          expect(
            actual.beatInCycle,
            todayBeatInCycle,
            reason: '$label $ms ms 游标格',
          );
          expect(
            actual.isEightStart,
            todayEightStart,
            reason: '$label $ms ms 八拍首',
          );
          expect(actual.isBarStart, todayBarStart, reason: '$label $ms ms 小节首');
        }
      }

      expectMatchesToday(const UniformBeatGrid(), '无界占位网格');
      expectMatchesToday(const _BoundedGrid(), '有界真实网格（首拍 0）');
    });

    test('半八拍（锚点）后：八拍窗口首拍随锚点走，不再由索引算术固定', () {
      const grid = _BoundedGrid(); // 拍 1s 起每 0.5s 一拍、强拍每 4 拍
      final anchored = BeatPhase(grid: grid, anchors: const [4]);
      const position = Duration(milliseconds: 6500); // 第 11 拍

      // 自动相位八拍点 = 0/8；锚点 4 落锚后 = 0/4/12…
      expect(anchored.eightBeatPointIndexAtOrBefore(11), 4);
      final auto = deriveBeatPhase(
        grid: grid,
        position: position,
        phase: BeatPhase(grid: grid),
      );
      final followed = deriveBeatPhase(
        grid: grid,
        position: position,
        phase: anchored,
      );
      expect(auto.windowFirstBeatIndex, 8, reason: '今日：索引算术窗口');
      expect(followed.windowFirstBeatIndex, 4, reason: '窗口首拍 = 相位源八拍点');
      expect(followed.beatInCycle, 7);
      expect(followed.isEightStart, isFalse, reason: '第 11 拍非八拍点');
    });

    testWidgets('半八拍后当前格随窗口首拍移动（游标分组跟锚点）', (tester) async {
      const grid = _BoundedGrid();
      const position = Duration(milliseconds: 6500); // 第 11 拍

      await pumpBar(tester, grid: grid, position: position);
      // 今日（无锚点）：窗口 [8,16) → 当前格 = 偏移 3。
      expect(cellColor(tester, 3), kCyanAccentColor);

      await pumpBar(
        tester,
        grid: grid,
        position: position,
        phase: BeatPhase(grid: grid, anchors: const [4]),
      );
      // 锚点 4 重定相：窗口 [4,12) → 当前格 = 偏移 7。
      expect(cellColor(tester, 7), kCyanAccentColor);
      expect(cellColor(tester, 3), isNot(kCyanAccentColor));
    });

    testWidgets('强拍边界竖线 = 相位源的 downbeat：非均匀 downbeat 网格下不再分歧', (tester) async {
      // downbeat 落在拍 0/4/9/13（漏检一拍的非均匀序列）：八拍点按序数 =
      // 0、9；窗口首拍 = 9。强拍边界判定读相位源 downbeat，而非
      // `(拍序号 − firstDownbeat) % beatsPerBar` 的索引算术——后者的
      // 拍 13 判不出小节首（13 % 4 = 1）。
      const grid = _IrregularDownbeatGrid();
      await pumpBar(
        tester,
        grid: grid,
        position: const Duration(milliseconds: 5000), // 第 10 拍
        phase: BeatPhase(grid: grid),
      );

      final window = deriveBeatPhase(
        grid: grid,
        position: const Duration(milliseconds: 5000),
        phase: BeatPhase(grid: grid),
      );
      expect(window.windowFirstBeatIndex, 9, reason: '窗口首拍 = 最近八拍点');
      final barRect = tester.getRect(find.byKey(const Key('beat_anim_bar')));
      final slot = barRect.width / 8;
      double lineCenter(int i) =>
          tester
              .getRect(find.byKey(Key('beat_anim_strong_line_$i')))
              .center
              .dx -
          barRect.left;
      // 窗口左端（拍 9 = 八拍首，offset 0）不画；拍 13 = 小节首 → offset 4。
      expect(lineCenter(4), closeTo(4 * slot, 0.5));
      for (final i in [0, 1, 2, 3, 5, 6, 7]) {
        expect(find.byKey(Key('beat_anim_strong_line_$i')), findsNothing);
      }
      for (var i = 0; i < 8; i++) {
        expect(cellStroke(tester, i), 1, reason: '格 $i 描边一律普通取值');
      }

      // 与轨道大线同判：相位源八拍点 = 拍 0、9，窗口首拍即最近大线。
      final ticks = beatTrackTicks(
        grid,
        Duration.zero,
        const Duration(seconds: 8),
        phase: BeatPhase(grid: grid),
      );
      final bigLines = [
        for (final tick in ticks)
          if (tick.tier == BeatTickTier.eightBar) tick.time,
      ];
      expect(bigLines, [grid.beatTime(0), grid.beatTime(9)]);
      expect(bigLines.last, grid.beatTime(window.windowFirstBeatIndex));
    });
  });

  group('用户半拍线投影 projectUserHalfBeatLines（纯函数 seam）', () {
    test('窗口内标记按相对所属拍的相位投影', () {
      final projections = projectUserHalfBeatLines(
        grid: grid,
        windowFirstBeatIndex: 0,
        halfBeatLines: const [Duration(milliseconds: 1250)],
      );
      expect(projections.length, 1);
      expect(projections.single.beatOffset, 2);
      expect(projections.single.beatFraction, closeTo(0.5, 1e-6));
    });

    test('当前八拍窗口外的标记不投影', () {
      final projections = projectUserHalfBeatLines(
        grid: grid,
        windowFirstBeatIndex: 8,
        halfBeatLines: const [
          Duration(milliseconds: 1250), // 第 2 拍，在窗口 [8,16) 之外。
          Duration(milliseconds: 4500), // 第 9 拍，窗口内偏移 1。
        ],
      );
      expect(projections.single.beatOffset, 1);
      expect(projections.single.beatFraction, closeTo(0.0, 1e-6));
    });

    test('同拍多条都投影', () {
      final projections = projectUserHalfBeatLines(
        grid: grid,
        windowFirstBeatIndex: 0,
        halfBeatLines: const [
          Duration(milliseconds: 1000),
          Duration(milliseconds: 1250),
        ],
      );
      expect(projections.length, 2);
      expect(projections.every((p) => p.beatOffset == 2), isTrue);
      expect(projections[0].beatFraction, closeTo(0.0, 1e-6));
      expect(projections[1].beatFraction, closeTo(0.5, 1e-6));
    });

    test('早于首拍的标记（网格定位 -1）不投影', () {
      const bounded = _BoundedGrid();
      final projections = projectUserHalfBeatLines(
        grid: bounded,
        windowFirstBeatIndex: 0,
        halfBeatLines: const [Duration.zero],
      );
      expect(projections, isEmpty);
    });

    test('动画相位携带绝对拍序号与八拍窗口首拍', () {
      final phase = deriveBeatPhase(
        grid: grid,
        position: const Duration(milliseconds: 4500),
        phase: BeatPhase(grid: grid),
      );
      expect(phase.beatIndex, 9);
      expect(phase.windowFirstBeatIndex, 8);
      expect(phase.beatIndex - phase.beatInCycle, 8);
    });

    test('有界网格恰在末拍：不外推 index+1 越界，拍内相位钳 0', () {
      const bounded = _BoundedGrid();
      // 末拍 = 序号 15 @ 8.5s（原实现 beatTime(16) 越界抛 RangeError）。
      final atLast = deriveBeatPhase(
        grid: bounded,
        position: const Duration(milliseconds: 8500),
        phase: BeatPhase(grid: bounded),
      );
      expect(atLast.beatIndex, 15);
      expect(atLast.beatFraction, 0.0);
    });
  });

  group('声音类型设置槽（拍型词汇保留）', () {
    test('普通类型可发声；人声/歌姬为待支持占位（不发声）', () {
      expect(MetronomeSoundType.normal.samplePending, isFalse);
      expect(MetronomeSoundType.vocal.samplePending, isTrue);
      expect(MetronomeSoundType.geigi.samplePending, isTrue);
    });
  });
}

/// 有界假网格：首拍 1s、每拍 500ms、4/4 小节，早于首拍定位 -1。
class _BoundedGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _BoundedGrid({this.lastBeatIndex = 15});

  @override
  final int lastBeatIndex;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: 1000 + index * 500);

  @override
  int beatIndexAt(Duration time) {
    final index = ((time.inMilliseconds - 1000) / 500).floor();
    return index < 0 ? -1 : index;
  }

  @override
  bool isDownbeat(int index) => index % 4 == 0;

  @override
  int get firstDownbeatIndex => 0;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}

/// 非均匀 downbeat 有界网格：一拍 500ms、时间轴 0 对齐，downbeat 落在
/// 拍 0、8、12（真实网格漏检一条 downbeat 的形态，间距不按
/// beatsPerBar = 4 周期），用于钉序数法与索引算术的分歧点。
class _NonUniformDownbeatGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _NonUniformDownbeatGrid();

  static const _downbeats = {0, 8, 12};

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: index * 500);

  @override
  int beatIndexAt(Duration time) {
    final index = (time.inMilliseconds / 500).floor();
    return index < 0 ? -1 : (index > 15 ? 16 : index);
  }

  @override
  bool isDownbeat(int index) => _downbeats.contains(index);

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => 15;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) {
    final first = beatIndexAt(start);
    final last = beatIndexAt(end);
    return [
      for (var i = math.max(first, 0); i <= math.min(last, 15); i++)
        beatTime(i),
    ];
  }
}

/// 非均匀 downbeat 有界网格（平局点用）：一拍 500ms、时间轴 0 对齐，
/// downbeat 落在拍 0、4、9、13——**间距不按 beatsPerBar = 4 周期**，故
/// `(拍序号 − firstDownbeat) % beatsPerBar` 的索引算术在拍 13 判不出小节首，
/// 而 downbeat 序列（相位源）判得出。
class _IrregularDownbeatGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _IrregularDownbeatGrid();

  static const _downbeats = {0, 4, 9, 13};

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: index * 500);

  @override
  int beatIndexAt(Duration time) {
    final index = (time.inMilliseconds / 500).floor();
    return index < 0 ? -1 : (index > 15 ? 16 : index);
  }

  @override
  bool isDownbeat(int index) => _downbeats.contains(index);

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => 15;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) {
    final first = beatIndexAt(start);
    final last = beatIndexAt(end);
    return [
      for (var i = math.max(first, 0); i <= math.min(last, 15); i++)
        beatTime(i),
    ];
  }
}

/// 无强拍假网格（占位/异常回退态）：一拍 500ms、无 downbeat、有界 16 拍。
/// 强拍判定取不到任何拍 → 回退到索引算术窗口。
class _NoStrongBeatGrid implements BeatGrid {
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _NoStrongBeatGrid();

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: index * 500);

  @override
  int beatIndexAt(Duration time) {
    final index = (time.inMilliseconds / 500).floor();
    return index < 0 ? -1 : (index > 15 ? 16 : index);
  }

  @override
  bool isDownbeat(int index) => false;

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => 15;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}

/// 3/4 均匀假网格：一拍 500ms、每 3 拍一个 downbeat、时间轴 0 对齐、无界。
class _ThreeFourGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _ThreeFourGrid();

  @override
  int get beatsPerBar => 3;

  @override
  Duration beatTime(int index) => Duration(milliseconds: index * 500);

  @override
  int beatIndexAt(Duration time) => (time.inMilliseconds / 500).floor();

  @override
  bool isDownbeat(int index) => index % 3 == 0;

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => null;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}
