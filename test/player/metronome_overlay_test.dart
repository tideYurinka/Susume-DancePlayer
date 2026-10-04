import 'package:dance_learning_app/core/current_beat.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/player/beat_animation.dart';

import '../helpers/beat_anchor_probe.dart';
import '../helpers/beat_presentation_value.dart' show presentationValueFor;

import 'package:dance_learning_app/player/metronome_overlay.dart';
import 'package:dance_learning_app/player/overlay.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';
import '../helpers/semantics_assertions.dart';

/// 浮层位载荷的测试构造：控制器只读竖屏·普通格，故默认把给定的
/// 偏移写进该格；四格容器的形状由 `overlay_placement_test.dart` 直测。
OverlayPlacements overlayPlacements({
  Offset offset = Offset.zero,
  double rectWidthFactor = 1.0,
  double pendulumScale = 1.0,
}) => OverlayPlacements(
  offsets: {OverlayPlacementCell.portraitNormal: offset},
  rectWidthFactor: rectWidthFactor,
  pendulumScale: pendulumScale,
);

/// 挂了钳制框的控制器（浮层位用例按各自视口语义自选尺寸）。
MetronomeOverlayController controllerAt(Size viewport) =>
    MetronomeOverlayController()..setViewport(viewport);

void main() {
  group('数拍数字锚点派生 deriveBeatCount（纯函数 seam）', () {
    // 占位均匀网格 120 bpm：一拍 500ms。
    const grid = UniformBeatGrid();

    test('锚点位置 = 第 1 八拍第 1 拍', () {
      final display = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 2),
        position: const Duration(seconds: 2),
        phase: BeatPhase(grid: grid),
      );
      expect(display, isA<PracticeBeatCount>());
      final practice = display as PracticeBeatCount;
      expect(practice.eightCount, 1);
      expect(practice.beatCount, 1);
    });

    test('八拍内推进只动拍号', () {
      final practice = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 2),
        position: const Duration(milliseconds: 3500),
        phase: BeatPhase(grid: grid),
      ) as PracticeBeatCount;
      expect(practice.eightCount, 1);
      expect(practice.beatCount, 4);
    });

    test('跨过八拍边界八拍号进位、拍号回 1（段首即八拍点）', () {
      // 段首 = 第 8 拍（4000ms，八拍点）：跨过其后第一个八拍点（8000ms）
      // 进位、拍号回 1。段首落八拍点是应用常态（分段线吸附八拍点）。
      final practice = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 4),
        position: const Duration(seconds: 8),
        phase: BeatPhase(grid: grid),
      ) as PracticeBeatCount;
      expect(practice.eightCount, 2);
      expect(practice.beatCount, 1);
    });

    test('前导区（锚点前 4 拍，N=4）→ 第 0 八拍顺数 0/5、0/6、0/7、0/8', () {
      final expected = const [5, 6, 7, 8];
      for (var i = 0; i < expected.length; i++) {
        final display = deriveBeatCount(
          grid: grid,
          anchor: const Duration(seconds: 2),
          position: Duration(milliseconds: 500 * i),
          phase: BeatPhase(grid: grid),
        );
        expect(display, isA<LeadingBeatCount>(), reason: 'position ${i + 1}');
        final leading = display as LeadingBeatCount;
        expect(leading.eightCount, 0, reason: 'position ${i + 1}');
        expect(leading.beatCount, expected[i], reason: 'position ${i + 1}');
      }
    });

    test('前导 N=2 → 0/7、0/8', () {
      final expected = const [7, 8];
      for (var i = 0; i < expected.length; i++) {
        final leading = deriveBeatCount(
          grid: grid,
          anchor: const Duration(seconds: 2),
          position: Duration(milliseconds: 1000 + 500 * i),
          phase: BeatPhase(grid: grid),
        ) as LeadingBeatCount;
        expect(leading.eightCount, 0);
        expect(leading.beatCount, expected[i]);
      }
    });

    test('前导 N=8 → 0/1…0/8', () {
      final expected = const [1, 2, 3, 4, 5, 6, 7, 8];
      for (var i = 0; i < expected.length; i++) {
        final leading = deriveBeatCount(
          grid: grid,
          anchor: const Duration(seconds: 6),
          position: Duration(milliseconds: 2000 + 500 * i),
          phase: BeatPhase(grid: grid),
        ) as LeadingBeatCount;
        expect(leading.eightCount, 0);
        expect(leading.beatCount, expected[i]);
      }
    });

    test('位置早于首拍（真实网格定位 -1）→ 仍前导两数、不落回练习区', () {
      final grid = _BoundedFakeGrid(firstBeat: const Duration(seconds: 1));
      final display = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 1),
        position: Duration.zero,
        phase: BeatPhase(grid: grid),
      );
      expect(display, isA<LeadingBeatCount>());
      final leading = display as LeadingBeatCount;
      expect(leading.eightCount, 0);
      expect(leading.beatCount, 8);
    });

    test('弱起双 -1（锚点与位置都早于首拍）→ 1｜1，不误入前导 0｜8', () {
      final grid = _BoundedFakeGrid(firstBeat: const Duration(seconds: 2));
      final display = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 1),
        position: Duration.zero,
        phase: BeatPhase(grid: grid),
      );
      expect(display, isA<PracticeBeatCount>());
      final practice = display as PracticeBeatCount;
      expect(practice.eightCount, 1);
      expect(practice.beatCount, 1);
    });

    test('锚点前超过 8 拍 → 拍号钳到 1，不外推 0 或负数', () {
      final grid = _BoundedFakeGrid(firstBeat: const Duration(seconds: 1));
      final leading = deriveBeatCount(
        grid: grid,
        anchor: const Duration(seconds: 6),
        position: Duration.zero,
        phase: BeatPhase(grid: grid),
      ) as LeadingBeatCount;
      expect(leading.eightCount, 0);
      expect(leading.beatCount, 1);
    });
  });

  group('前导区拍号（录制准备借用同一换算）', () {
    // 占位均匀网格 120 bpm：一拍 500ms。
    const grid = UniformBeatGrid();
    const anchor = Duration(seconds: 10);
    const beat = Duration(milliseconds: 500);

    /// 距锚 [before] 拍的「第 0 个八拍顺数」拍号：经公开的 [deriveBeatCount]
    /// 前导分支读（位置取锚点前 [before] 拍）。
    int leadingNumber(int before) {
      final display = deriveBeatCount(
        grid: grid,
        anchor: anchor,
        position: anchor - beat * before,
        phase: BeatPhase(grid: grid),
      );
      return (display as LeadingBeatCount).beatCount;
    }

    test('距锚点 8 拍：自 0|1 顺数到 0|8（第 0 个八拍）', () {
      expect(
        [for (var before = 8; before >= 1; before--) leadingNumber(before)],
        const [1, 2, 3, 4, 5, 6, 7, 8],
      );
    });

    test('距锚点 4 拍：0|5…0|8', () {
      expect(
        [for (var before = 4; before >= 1; before--) leadingNumber(before)],
        const [5, 6, 7, 8],
      );
    });

    test('距锚点超过 8 拍：拍号钳到 1，不外推 0 或负数', () {
      expect(
        [for (var before = 12; before >= 1; before--) leadingNumber(before)],
        const [1, 1, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8],
      );
    });

    test('录制准备那几拍的拍号与位置口径逐拍一致（两支共用同一换算）', () {
      const prepBeats = 8;
      for (var index = 0; index < prepBeats; index++) {
        final display = deriveBeatCount(
          grid: grid,
          anchor: anchor,
          position: anchor - beat * prepBeats + beat * index,
          phase: BeatPhase(grid: grid),
        );
        expect(display, isA<LeadingBeatCount>(), reason: '前导第 ${index + 1} 拍');
        expect(
          (display as LeadingBeatCount).beatCount,
          index + 1,
          reason: '前导第 ${index + 1} 拍：录制准备与段循环前导同一套视觉',
        );
      }
    });
  });

  group('数拍跟八拍锚点（八拍号按八拍点顺数）', () {
    // 有界均匀网格：一拍 500ms、强拍每 4 拍（0/4/8…）、末拍 100。
    // 锚点 28（第 8 个强拍）→ 八拍点 = 0/8/16/24/28/36/44…，其中 24→28
    // 只隔 4 拍 = 半八拍。
    _BoundedFakeGrid uniform() => _BoundedFakeGrid(firstBeat: Duration.zero);

    Duration at(int beat) => Duration(milliseconds: beat * 500);

    ({int eight, int beat}) practice(BeatCountDisplay display) {
      final p = display as PracticeBeatCount;
      return (eight: p.eightCount, beat: p.beatCount);
    }

    /// 两数全等比较键（练习区/前导区各一形态，回归基线逐位比对用）。
    Object displayKey(BeatCountDisplay display) => switch (display) {
      PracticeBeatCount(:final eightCount, :final beatCount) => (
        'P',
        eightCount,
        beatCount,
      ),
      LeadingBeatCount(:final beatCount) => ('L', beatCount),
    };

    test('半八拍后下一个八拍号提前到来（不整段漂移）', () {
      final grid = uniform();
      final phase = BeatPhase(grid: grid, anchors: const [28]);
      // 半八拍前：每 8 拍一号（与今日一致）。
      expect(
        practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(27),
            phase: phase,
          ),
        ),
        (eight: 4, beat: 4),
      );
      // 半八拍处：号 5 在拍 28 到来（旧口径拍 28 = 4｜5，号 5 要到拍 32）。
      expect(
        practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(28),
            phase: phase,
          ),
        ),
        (eight: 5, beat: 1),
      );
      // 半八拍区间（28–35，仅 4 拍）内拍号顺数到 4，其后本段照旧每 8 拍。
      expect(
        practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(31),
            phase: phase,
          ),
        ),
        (eight: 5, beat: 4),
      );
      expect(
        practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(32),
            phase: phase,
          ),
        ),
        (eight: 5, beat: 5),
      );
      expect(
        practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(36),
            phase: phase,
          ),
        ),
        (eight: 6, beat: 1),
      );
      // 不漂移：号恒等于「段内第几个八拍点」，与轨上八拍数小数字同口径。
      final auto = phase.pointsInWindow(at(0), at(60));
      expect(auto.length, 9, reason: '段内八拍点 0/8/16/24/28/36/44/52/60');
      expect(
        practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(60),
            phase: phase,
          ),
        ),
        (eight: 9, beat: 1),
      );
    });

    test('八拍号与拍号仍为整数、拍号恒在 1–8（无 0.5 分度）', () {
      final grid = uniform();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      var previousEight = 1;
      for (var index = 0; index <= 99; index++) {
        final display = practice(
          deriveBeatCount(
            grid: grid,
            anchor: at(0),
            position: at(index),
            phase: phase,
          ),
        );
        expect(display.beat, inInclusiveRange(1, 8), reason: '拍 $index');
        expect(display.eight, greaterThanOrEqualTo(1), reason: '拍 $index');
        // 号只按八拍点 +1，永不跳跃、永不回退。
        expect(
          display.eight - previousEight,
          inInclusiveRange(0, 1),
          reason: '拍 $index',
        );
        previousEight = display.eight;
      }
      expect(
        previousEight,
        13,
        reason: '0..99 内八拍点 = 0/8/16/24/28/36/44/52/60/68/76/84/92',
      );
    });

    test('锚点之前的数拍逐位不变（锚只向后）', () {
      final grid = uniform();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      for (var index = 0; index < 28; index++) {
        expect(
          practice(
            deriveBeatCount(
              grid: grid,
              anchor: at(0),
              position: at(index),
              phase: phase,
            ),
          ),
          practice(
            deriveBeatCount(
              grid: grid,
              anchor: at(0),
              position: at(index),
              phase: BeatPhase(grid: grid),
            ),
          ),
          reason: '锚点之前拍 $index 须与今日逐位一致',
        );
      }
    });

    test('前导第 0 个八拍计数不受锚点影响', () {
      final grid = uniform();
      final phase = BeatPhase(grid: grid, anchors: const [28]);

      for (var index = 0; index < 8; index++) {
        final leading = deriveBeatCount(
          grid: grid,
          anchor: at(8),
          position: at(index),
          phase: phase,
        );
        expect(leading, isA<LeadingBeatCount>(), reason: '拍 $index');
        expect((leading as LeadingBeatCount).eightCount, 0);
        expect(
          leading.beatCount,
          (deriveBeatCount(
            grid: grid,
            anchor: at(8),
            position: at(index),
            phase: BeatPhase(grid: grid),
          ) as LeadingBeatCount).beatCount,
          reason: '拍 $index 前导计数不变',
        );
      }
    });

    test('无锚点且段首落八拍点：与今日逐位一致（回归基线）', () {
      final grid = uniform();
      final auto = BeatPhase(grid: grid);

      for (final anchorBeat in [0, 8, 16, 24]) {
        for (var index = 0; index <= 99; index++) {
          expect(
            displayKey(
              deriveBeatCount(
                grid: grid,
                anchor: at(anchorBeat),
                position: at(index),
                phase: auto,
              ),
            ),
            displayKey(
              deriveBeatCount(
                grid: grid,
                anchor: at(anchorBeat),
                position: at(index),
                phase: BeatPhase(grid: grid),
              ),
            ),
            reason: '段首拍 $anchorBeat、位置拍 $index 须与今日逐位一致',
          );
        }
      }
    });

    test('锚点不改变相位时数拍也不变（无额外噪音）', () {
      final grid = uniform();
      // 拍 8 本就是自动相位的八拍点——落锚不改变任何相位。
      final phase = BeatPhase(grid: grid, anchors: const [8]);

      for (var index = 0; index <= 99; index++) {
        expect(
          practice(
            deriveBeatCount(
              grid: grid,
              anchor: at(0),
              position: at(index),
              phase: phase,
            ),
          ),
          practice(
            deriveBeatCount(
              grid: grid,
              anchor: at(0),
              position: at(index),
              phase: BeatPhase(grid: grid),
            ),
          ),
          reason: '拍 $index：相位未变则数拍不得变',
        );
      }
    });

    test('段首不落八拍点时：段首恒 1｜1、号在下一个八拍点进位', () {
      // 段首 = 拍 4（非八拍点，如占位期插入、未吸附的分段线）：号 1 只含
      // 4 拍，号 2 在八拍点 8 到来（旧口径要到拍 12），拍号自八拍点顺数。
      const placeholder = UniformBeatGrid();
      final phase = BeatPhase(grid: placeholder, anchors: const [28]);

      expect(
        practice(
          deriveBeatCount(
            grid: placeholder,
            anchor: const Duration(seconds: 2),
            position: const Duration(seconds: 4),
            phase: phase,
          ),
        ),
        (eight: 2, beat: 1),
      );
      expect(
        practice(
          deriveBeatCount(
            grid: placeholder,
            anchor: const Duration(seconds: 2),
            position: const Duration(seconds: 6),
            phase: phase,
          ),
        ),
        (eight: 2, beat: 5),
      );
      expect(
        practice(
          deriveBeatCount(
            grid: placeholder,
            anchor: const Duration(seconds: 2),
            position: const Duration(seconds: 2),
            phase: phase,
          ),
        ),
        (eight: 1, beat: 1),
        reason: '段首恒 1｜1',
      );
    });
  });

  group('锚点链解析（经公开求值口）', () {
    // 首线（视频有效区间起点 rangeStart）。
    const firstLine = Duration(seconds: 1);
    final segmentLines = [
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ];

    test('有激活锚（临时段段首/激活段合并起点段首）→ 恒用激活段首', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 12),
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 12),
      );
    });

    test('延迟锚优先于激活锚（录制锚 → 延迟锚 → 激活锚）', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 12),
          delayAnchor: const Duration(seconds: 16),
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 16),
      );
    });

    test('录制锚优先于延迟锚', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          recordingAnchor: const Duration(seconds: 8),
          delayAnchor: const Duration(seconds: 16),
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 8),
      );
    });

    test('延迟锚撤销后回落激活锚（打断即撤，数拍回到普通锚点链）', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 12),
          delayAnchor: null,
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 12),
      );
    });

    test('无激活锚 → 位置之前最近的分段线', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 10),
      );
    });

    test('位置恰在分段线上（≤ 语义）→ 该线为新段段首', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 20),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 20),
      );
    });

    test('位置早于全部分段线 → 首线', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 5),
          gridLastBeatTime: null,
        ),
        firstLine,
      );
    });

    test('无分段线 → 首线', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: const [],
          firstLine: firstLine,
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        firstLine,
      );
    });

    test('无界网格（占位）无网格末拍上限', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 100),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 20),
      );
    });

    test('位置早于首线 → null（有激活锚也不显示）', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 12),
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(milliseconds: 500),
          gridLastBeatTime: null,
        ),
        isNull,
      );
    });

    test('位置超出网格末拍 → null（有激活锚也不显示）', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 12),
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 26),
          gridLastBeatTime: const Duration(seconds: 24),
        ),
        isNull,
      );
    });

    test('位置恰在网格末拍 → 可锚（不显示边界外一拍才隐藏）', () {
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          segmentLines: segmentLines,
          firstLine: firstLine,
          position: const Duration(seconds: 24),
          gridLastBeatTime: const Duration(seconds: 24),
        ),
        const Duration(seconds: 20),
      );
    });
  });

  group('数拍锚点对齐网格八拍大线（经公开求值口）', () {
    // 弱起有界真实网格：每拍 500ms、首拍非强拍、首个强拍在序号 1，其后每
    // 4 拍一个强拍；八拍大线自首个强拍起每 8 拍一条（序号 1 / 9 / … / 65）。
    Duration at(int beatIndex) => Duration(milliseconds: 500 * beatIndex);

    // 相位源与数拍八拍号、矩形动画当前格、轨道大线同一份（八拍点
    // 只有一扇门）；无锚点相位即「网格首个强拍为相位原点」。
    BeatPhase phaseOf(BeatGrid grid) => BeatPhase(grid: grid);

    test('大线锚点恒等（原样返回）', () {
      const grid = _WeakStartFakeGrid();
      final phase = phaseOf(grid);
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(33)),
        at(33),
        reason: '序号 33 本身即八拍大线',
      );
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(1)),
        at(1),
        reason: '首个强拍所在大线',
      );
    });

    test('弱起首线早于首个强拍 → 取首个强拍所在大线', () {
      const grid = _WeakStartFakeGrid();
      expect(
        alignBeatCountAnchorToGridProbe(phase: phaseOf(grid), anchor: at(0)),
        at(1),
      );
    });

    test('锚早于网格首拍（就绪网格）→ 归首个强拍所在八拍点', () {
      // 锚点定位 -1（早于网格首拍）不再原样放行：就绪网格上恒归八拍点
      // ——首个强拍（序号 1，相位原点）所在大线；无论早多少拍。
      const grid = _WeakStartFakeGrid();
      final phase = phaseOf(grid);
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(-1)),
        at(1),
      );
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(-10)),
        at(1),
      );
      // 归位后：网格首拍落在锚点之前 → 前导区 0|8，过大线起 1|1。
      expect(
        deriveBeatCount(
          grid: grid,
          anchor: at(1),
          position: at(0),
          phase: phase,
        ),
        isA<LeadingBeatCount>().having((d) => d.beatCount, 'beatCount', 8),
      );
      expect(
        deriveBeatCount(
          grid: grid,
          anchor: at(1),
          position: at(1),
          phase: phase,
        ),
        isA<PracticeBeatCount>().having((d) => d.beatCount, 'beatCount', 1),
      );
    });

    test('就绪网格无任何八拍点（无强拍）→ 锚原样返回', () {
      // 无强拍即无相位原点，无八拍点可对齐：不新造相位，锚原样（含定位 -1
      // 的早于首拍锚——不再走「归首个强拍」分支，因不存在首个强拍）。
      const grid = _NoDownbeatReadyGrid();
      final phase = phaseOf(grid);
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(5)),
        at(5),
      );
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(-1)),
        at(-1),
      );
    });

    test('错位线（大线前若干拍）→ 取其后最近的大线', () {
      // 序号 30 非大线（其前的大线为 25、其后最近的大线为 33）→ 16.5s。
      const grid = _WeakStartFakeGrid();
      expect(
        alignBeatCountAnchorToGridProbe(phase: phaseOf(grid), anchor: at(30)),
        at(33),
      );
    });

    test('网格尾部无后随大线 → 回退前一条大线', () {
      // 末拍序号 69 非大线，其后无大线（网格最末大线序号 65）→ 回退 65。
      const grid = _WeakStartFakeGrid();
      expect(
        alignBeatCountAnchorToGridProbe(phase: phaseOf(grid), anchor: at(69)),
        at(65),
      );
    });

    test('占位/异常无界网格（无真实大线）→ 原样返回锚点', () {
      const placeholder = UniformBeatGrid();
      const anchor = Duration(seconds: 10);
      expect(
        alignBeatCountAnchorToGridProbe(
          phase: phaseOf(placeholder),
          anchor: anchor,
        ),
        anchor,
      );
    });

    test('非均匀强拍网格：大线取强拍序数，不按拍序号算术', () {
      // 强拍序号 {0,4,8,11,15,19,23,26,30,34}（间距非等距）→ 八拍大线 =
      // 序数奇数者 {0,8,15,23,30}；序号 20 的后随大线是 23，而按「原点 +
      // 8 的整数倍」算出的 24 并非强拍、不成大线。
      final grid = _irregularDownbeatGrid();
      final phase = phaseOf(grid);
      expect(
        alignBeatCountAnchorToGridProbe(phase: phase, anchor: at(20)),
        at(23),
      );
      expect(grid.isDownbeat(23), isTrue, reason: '对齐结果必须落在真实大线上');
      expect(phase.isEightBeatPoint(23), isTrue);
      expect(grid.isDownbeat(24), isFalse);
    });
  });

  group('录制期锚与相位等价（接线后的口径）', () {
    Duration at(int beatIndex) => Duration(milliseconds: 500 * beatIndex);
    BeatPhase phaseOf(BeatGrid grid) => BeatPhase(grid: grid);

    test('录制期锚优先于激活锚/分段线（无激活段录制 = 起录点）', () {
      const anchor = Duration(seconds: 12);
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          recordingAnchor: anchor,
          segmentLines: const [Duration(seconds: 10), Duration(seconds: 20)],
          firstLine: const Duration(seconds: 1),
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        anchor,
        reason: '无激活段录制：锚 = 起录点，不退化到「最近分段线 → 首线」',
      );
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: const Duration(seconds: 12),
          recordingAnchor: const Duration(seconds: 12),
          segmentLines: const [Duration(seconds: 10)],
          firstLine: const Duration(seconds: 1),
          position: const Duration(seconds: 15),
          gridLastBeatTime: null,
        ),
        const Duration(seconds: 12),
        reason: '有激活段时起录点即段首，两支同值',
      );
    });

    test('录制期锚仍受网格边界约束（早于首线/晚于末拍不显示）', () {
      const anchor = Duration(seconds: 12);
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          recordingAnchor: anchor,
          segmentLines: const [],
          firstLine: const Duration(seconds: 1),
          position: const Duration(milliseconds: 500),
          gridLastBeatTime: null,
        ),
        isNull,
      );
      expect(
        resolveBeatAnchorProbe(
          activeAnchor: null,
          recordingAnchor: anchor,
          segmentLines: const [],
          firstLine: const Duration(seconds: 1),
          position: const Duration(seconds: 26),
          gridLastBeatTime: const Duration(seconds: 24),
        ),
        isNull,
      );
    });

    test('错位锚对齐后：数字拍号 == 矩形动画当前格（同源相位）', () {
      const grid = _WeakStartFakeGrid();
      final phase = phaseOf(grid);
      // 序号 30 非大线（其前大线 25、其后最近大线 33）→ 锚归到 33。
      final anchor = alignBeatCountAnchorToGridProbe(
        phase: phase,
        anchor: at(30),
      )!;
      expect(anchor, at(33));
      for (var i = 30; i <= 41; i++) {
        final display = deriveBeatCount(
          grid: grid,
          anchor: anchor,
          position: at(i),
          phase: phase,
        );
        final digit = switch (display) {
          LeadingBeatCount(:final beatCount) => beatCount,
          PracticeBeatCount(:final beatCount) => beatCount,
        };
        final animation = deriveBeatPhase(
          grid: grid,
          position: at(i),
          phase: phase,
        );
        expect(
          digit,
          animation.beatInCycle + 1,
          reason: '第 $i 拍：数拍数字与动画当前格同号（对齐前会差一拍）',
        );
      }
    });

    test('弱起首线对齐到首个强拍所在大线：弱起区 0|8、过大线起 1|1', () {
      const grid = _WeakStartFakeGrid();
      final phase = phaseOf(grid);
      final anchor = alignBeatCountAnchorToGridProbe(
        phase: phase,
        anchor: at(0),
      )!;
      expect(anchor, at(1));
      expect(
        deriveBeatCount(
          grid: grid,
          anchor: anchor,
          position: at(0),
          phase: phase,
        ),
        isA<LeadingBeatCount>().having((d) => d.beatCount, 'beatCount', 8),
      );
      expect(
        deriveBeatCount(
          grid: grid,
          anchor: anchor,
          position: at(1),
          phase: phase,
        ),
        isA<PracticeBeatCount>()
            .having((d) => d.eightCount, 'eightCount', 1)
            .having((d) => d.beatCount, 'beatCount', 1),
      );
    });
  });

  group('混区 burst 跟踪 OverlayMixedBurstTracker', () {
    test('burst 内两类指针并存 → 闩锁混区', () {
      final tracker = OverlayMixedBurstTracker();
      tracker.pointerDown(1, onOverlay: true);
      expect(tracker.burstEverMixed, isFalse);
      tracker.pointerDown(2, onOverlay: false);
      expect(tracker.burstEverMixed, isTrue);
    });

    test('burst 结束复位闩锁，新 burst 不带旧证据', () {
      final tracker = OverlayMixedBurstTracker();
      tracker.pointerDown(1, onOverlay: true);
      tracker.pointerDown(2, onOverlay: false);
      tracker.pointerUp(1);
      tracker.pointerUp(2);
      tracker.endBurst();
      expect(tracker.burstEverMixed, isFalse);
      tracker.pointerDown(3, onOverlay: false);
      expect(tracker.burstEverMixed, isFalse);
    });

    test('落选中态浮层上的指针单独成 burst → 不混区但命中浮层', () {
      final tracker = OverlayMixedBurstTracker();
      tracker.pointerDown(1, onOverlay: true);
      expect(tracker.burstEverMixed, isFalse);
      expect(tracker.burstTouchesSelectedOverlay, isTrue);
    });
  });

  group('数拍八拍号四八拍循环 eightCountCycleDisplay（纯函数 seam）', () {
    test('段内 1–4 循环：第 1–4 个八拍号原样、无组序', () {
      for (final rel in [1, 2, 3, 4]) {
        final display = eightCountCycleDisplay(rel);
        expect(display.number, rel, reason: 'rel=$rel');
        expect(display.group, isNull, reason: 'rel=$rel');
      }
    });
    test('第 5 个八拍回到 1 且组序 2', () {
      final display = eightCountCycleDisplay(5);
      expect(display.number, 1);
      expect(display.group, 2);
    });
    test('第 8 个八拍 = ⁴4；第 9 个八拍 = ²1（组 3）', () {
      expect(eightCountCycleDisplay(8).number, 4);
      expect(eightCountCycleDisplay(8).group, 2);
      final ninth = eightCountCycleDisplay(9);
      expect(ninth.number, 1);
      expect(ninth.group, 3);
    });
    test('组 = ⌈相对八拍 / 4⌉', () {
      expect(eightCountCycleDisplay(17).group, 5);
      expect(eightCountCycleDisplay(32).group, 8);
      expect(eightCountCycleDisplay(32).number, 4);
    });
  });

  group('数拍数字内容 BeatCountNumbers', () {
    testWidgets('练习区渲染 八拍号（青·大）+ 拍号（白·小）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatCountNumbers(
                display: PracticeBeatCount(eightCount: 2, beatCount: 5),
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);

      final eightStyle = tester.widget<Text>(find.text('2')).style!;
      expect(eightStyle.color, kCyanAccentColor);
      expect(eightStyle.fontSize, 56);
      final beatStyle = tester.widget<Text>(find.text('5')).style!;
      expect(beatStyle.color, Colors.white);
      expect(beatStyle.fontSize, 36);
    });

    testWidgets('段内第 4 个八拍不加组上标', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatCountNumbers(
                display: PracticeBeatCount(eightCount: 4, beatCount: 8),
              ),
            ),
          ),
        ),
      );
      expect(find.text('4'), findsOneWidget);
      expect(find.byKey(const Key('beat_count_group')), findsNothing);
    });

    testWidgets('第 5 个八拍显示 ²1：八拍号回 1 + 小上标组序 2', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatCountNumbers(
                display: PracticeBeatCount(eightCount: 5, beatCount: 3),
              ),
            ),
          ),
        ),
      );
      expect(find.text('1'), findsOneWidget);
      final group = tester.widget<Text>(
        find.byKey(const Key('beat_count_group')),
      );
      expect(group.data, '2');
      expect(group.style!.fontSize, lessThan(24));
      expect(group.style!.color, kCyanAccentColor);
    });

    testWidgets('前导区渲染两数：八拍号 0（青·大）+ 拍号（白·小）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatCountNumbers(display: LeadingBeatCount(beatCount: 7)),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('beat_count_leading')), findsOneWidget);
      expect(find.byKey(const Key('beat_count_practice')), findsNothing);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      final eightStyle = tester.widget<Text>(find.text('0')).style!;
      expect(eightStyle.color, kCyanAccentColor);
      expect(eightStyle.fontSize, 56);
      final beatStyle = tester.widget<Text>(find.text('7')).style!;
      expect(beatStyle.color, Colors.white);
      expect(beatStyle.fontSize, 36);
    });

    testWidgets('组序渲染于青色大数左上角上标（字号 14、同色青）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatCountNumbers(
                display: PracticeBeatCount(eightCount: 5, beatCount: 3),
              ),
            ),
          ),
        ),
      );
      final groupRect = tester.getRect(
        find.byKey(const Key('beat_count_group')),
      );
      final eightRect = tester.getRect(
        find.byKey(const Key('beat_count_eight')),
      );
      // 上标：悬于主数字左上角——在主数字左侧、顶部不高出主数字框太多（上标而非上方独立行）。
      expect(groupRect.right, lessThanOrEqualTo(eightRect.left));
      expect(groupRect.top, greaterThanOrEqualTo(eightRect.top - 0.5));
      expect(groupRect.top, lessThan(eightRect.top + eightRect.height / 2));
      final group = tester.widget<Text>(
        find.byKey(const Key('beat_count_group')),
      );
      expect(group.style!.fontSize, 14);
      expect(group.style!.color, kCyanAccentColor);
    });

    testWidgets('前导区与练习区拍号同规则：白拍号 36（两区一致）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: BeatCountNumbers(display: LeadingBeatCount(beatCount: 7)),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Text>(find.text('7')).style!.fontSize,
        tester
            .widget<Text>(find.byKey(const Key('beat_count_beat')))
            .style!
            .fontSize,
      );
      expect(tester.widget<Text>(find.text('7')).style!.fontSize, 36);
    });
  });

  group('数拍数字随系统字号缩放（语义档；取代固定口径）', () {
    final grid = UniformBeatGrid();

    Widget host({
      required double textScale,
      required BeatAnimationStyle style,
    }) {
      // 宿主盒高恒定：放得下 1.6× 的内容盒（120 × 1.6 = 192），但不随
      // 缩放同步放大——「无溢出」必须由实现正确重算容量才成立。
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: SizedBox(
                height: 200,
                child: Stack(
                  children: [
                    MetronomeOverlay(
                      controller: MetronomeOverlayController(),
                      style: style,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BeatCountNumbers(
                            display: PracticeBeatCount(
                              eightCount: 2,
                              beatCount: 5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          MetronomeBeatAnimation(
                            style: style,
                            value: presentationValueFor(
                              grid: grid,
                              position: Duration.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    for (final scale in [1.3, 1.6]) {
      for (final style in BeatAnimationStyle.values) {
        testWidgets('textScaler $scale ${style.name} 无溢出、数字行按缩放长高', (
          tester,
        ) async {
          await tester.pumpWidget(host(textScale: scale, style: style));
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const Key('beat_count_practice'))).height,
            moreOrLessEquals(56 * scale, epsilon: 0.5),
            reason: '语义档：1.3×/1.6× 下数字行真的随系统字号长高',
          );
          // 屏上可见尺寸（含 FittedBox 变换后）同步变大：「真的变大」
          // 断言在渲染接缝上，不在布局中间量。
          expect(
            tester.getRect(find.byKey(const Key('beat_count_eight'))).height,
            moreOrLessEquals(56 * scale, epsilon: 1.0),
            reason: '数字在屏上的墨迹高按系统字号放大，不被压回',
          );
        });
      }
    }
  });

  group('摆锤渲染链单次缩放 + 专属窄基准', () {
    final grid = UniformBeatGrid();

    // 常态挂载真实数拍内容（数字行 + 动画）：s 全域摆锤应一次布局后
    // 单次视觉缩放，无 bottom overflow、内容完整在框内（不再二次位移）。
    Widget host({
      required MetronomeOverlayController controller,
      BeatAnimationStyle style = BeatAnimationStyle.pendulum,
      Size? viewport,
      Widget? content,
    }) {
      final placementContent =
          content ??
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BeatCountNumbers(
                display: PracticeBeatCount(eightCount: 2, beatCount: 5),
              ),
              const SizedBox(height: 6),
              MetronomeBeatAnimation(
                style: style,
                value: presentationValueFor(
                  grid: grid,
                  position: Duration.zero,
                ),
              ),
            ],
          );
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 600,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: Colors.black)),
                  MetronomeOverlay(
                    controller: controller,
                    style: style,
                    child: placementContent,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    for (final scale in [0.5, 0.8, 1.0, 2.0, 3.0]) {
      testWidgets('摆锤 s=$scale：常态渲染无溢出、内容完整在框内', (tester) async {
        final controller = MetronomeOverlayController()
          ..setViewport(const Size(2000, 2000))
          ..applyPlacements(
            overlayPlacements(offset: Offset.zero, pendulumScale: 1.0),
          );
        await tester.pumpWidget(host(controller: controller));
        controller.applyPlacements(
          overlayPlacements(offset: Offset.zero, pendulumScale: scale),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        // 数拍数字与摆锤动画都可见（内容在框内，未被挤出/吞掉）。
        expect(find.byKey(const Key('beat_count_practice')), findsOneWidget);
        expect(find.byKey(const Key('beat_anim_pendulum')), findsOneWidget);
      });
    }

    testWidgets('摆锤 s=0.5 无 bottom overflow（渲染探针断言）', (tester) async {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(2000, 2000))
        ..applyPlacements(
          overlayPlacements(offset: Offset.zero, pendulumScale: 1.0),
        );
      await tester.pumpWidget(host(controller: controller));
      controller.applyPlacements(
        overlayPlacements(offset: Offset.zero, pendulumScale: 0.5),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      // 二次 pump 后仍无溢出（内容在基准一次布局、只做一次视觉缩放）。
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('摆锤小系数（0.5 等比）渲染无溢出', (tester) async {
      // 渲染探针：直接以 0.5 等比系数构造放置。
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(2000, 2000))
        ..applyPlacements(
          overlayPlacements(offset: Offset.zero, pendulumScale: 0.5),
        );
      await tester.pumpWidget(host(controller: controller));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('beat_anim_pendulum')), findsOneWidget);
    });

    testWidgets('摆锤放大到窄视口 cap：无溢出、内容仍在框内', (tester) async {
      // 窄视口（如 2736×1264 真机的高/宽比例下限量级）钳制生效上限。
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(480, 360))
        ..style = BeatAnimationStyle.pendulum;
      controller.applyPlacements(
        overlayPlacements(offset: Offset.zero, pendulumScale: 3.0),
      );
      await tester.pumpWidget(host(controller: controller));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('beat_anim_pendulum')), findsOneWidget);
      expect(controller.hitRect().size.width, lessThanOrEqualTo(480));
      expect(controller.hitRect().size.height, lessThanOrEqualTo(360));
    });

    testWidgets('摆锤拉大到 s=3.0：数字行仍完整渲染、无内容挤出框底', (tester) async {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(2000, 2000))
        ..applyPlacements(
          overlayPlacements(offset: Offset.zero, pendulumScale: 3.0),
        );
      await tester.pumpWidget(host(controller: controller));
      expect(tester.takeException(), isNull);
      // 数字行整体在浮层内容框内（不再二次位移挤出）。
      expect(
        tester.getSize(find.byKey(const Key('beat_count_practice'))).height,
        56,
      );
    });

    testWidgets('矩形形态 s 全域行为不变（共享 320×120 基准）', (tester) async {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(2000, 2000));
      await tester.pumpWidget(
        host(controller: controller, style: BeatAnimationStyle.bar),
      );
      // bar 默认实宽 = 共享基准宽 320。
      expect(controller.hitRect().size.width, kOverlayBaseContentSize.width);
      // bar 缩放走 rectWidthFactor（不影响高度），行为回归。
      controller.applyRectPinch(2.0);
      await tester.pump();
      expect(
        controller.hitRect().size.width,
        kOverlayBaseContentSize.width * 2.0,
      );
      expect(controller.hitRect().size.height, kOverlayBaseContentSize.height);
      expect(tester.takeException(), isNull);
    });
  });

  group('选中态缩放会话 seam（beginPinch/updatePinch/endPinch）', () {
    test('矩形：灵敏度 ×0.5——原始水平分量 2 → 宽系数 1.5', () {
      final controller = MetronomeOverlayController()..beginPinch();
      controller.updatePinch(scale: 2.0, horizontalScale: 2.0);
      expect(controller.placements.rectWidthFactor, 1.5);
      expect(controller.placements.pendulumScale, 1.0);
    });

    test('摆锤：灵敏度 ×0.5——原始 scale 3 → 等比 2.0；矩形系数独立不变', () {
      final controller = MetronomeOverlayController()
        ..style = BeatAnimationStyle.pendulum
        ..applyPlacements(
          overlayPlacements(offset: Offset(10, 10), rectWidthFactor: 1.5),
        )
        ..beginPinch();
      controller.updatePinch(scale: 3.0, horizontalScale: 3.0);
      expect(controller.placements.pendulumScale, 2.0);
      expect(controller.placements.rectWidthFactor, 1.5);
    });

    test('累计倍率口径：重复同值帧不叠加（绝对写回，不随帧数漂移）', () {
      final controller = MetronomeOverlayController()..beginPinch();
      controller
        ..updatePinch(scale: 2.0, horizontalScale: 2.0)
        ..updatePinch(scale: 2.0, horizontalScale: 2.0);
      expect(controller.placements.rectWidthFactor, 1.5);
    });

    test('上限钳制 2.5：原始水平分量 99 → 宽系数 2.5', () {
      final controller = MetronomeOverlayController()..beginPinch();
      controller.updatePinch(scale: 99.0, horizontalScale: 99.0);
      expect(controller.placements.rectWidthFactor, kMaxRectWidthFactor);
    });

    test('下限钳制 0.5：基准 0.8 原始内合到底 → 钳 0.5', () {
      final controller = MetronomeOverlayController()
        ..applyPlacements(
          overlayPlacements(offset: Offset(10, 10), rectWidthFactor: 0.8),
        )
        ..beginPinch();
      controller.updatePinch(scale: 0.0, horizontalScale: 0.0);
      expect(controller.placements.rectWidthFactor, kMinRectWidthFactor);
    });

    test('endPinch 后 updatePinch 忽略（无会话不缩放）', () {
      final controller = MetronomeOverlayController()
        ..beginPinch()
        ..endPinch();
      controller.updatePinch(scale: 4.0, horizontalScale: 4.0);
      expect(controller.placements.rectWidthFactor, 1.0);
    });

    test('缩放放大：生效尺寸超屏后位置随钳制收口保持可达（不变式）', () {
      // 摆锤贴下缘放置，放大到铺满视口高度 → 位置重新钳回屏内。
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(440, 300))
        ..style = BeatAnimationStyle.pendulum
        ..applyPlacements(
          overlayPlacements(offset: Offset(10, 180), pendulumScale: 1.0),
        )
        ..beginPinch();
      // 原始 scale 99 → 减半生效 → 摆锤上限 2.5 → 视口联动高上限
      // 300/120=2.5 → 生效铺满视口高。钳制收口后 dy 不再 >0 越界。
      controller.updatePinch(scale: 99.0, horizontalScale: 99.0);
      expect(controller.placements.pendulumScale, kMaxPendulumScale);
      expect(controller.hitRect().bottom, lessThanOrEqualTo(300));
    });

    test('混区闩锁在缩放会话期间被忽略（选中态缩放不进混区锁）', () {
      final controller = MetronomeOverlayController()..beginPinch();
      controller.setBurstSuppressed(true);
      expect(controller.burstSuppressed, isFalse);
      controller.updatePinch(scale: 2.0, horizontalScale: 2.0);
      expect(controller.placements.rectWidthFactor, 1.5);
    });

    test('beginPinch 起手解除已落混区闩锁；endPinch 后闩锁写入恢复生效', () {
      final controller = MetronomeOverlayController();
      controller.setBurstSuppressed(true);
      expect(controller.burstSuppressed, isTrue);
      controller.beginPinch();
      expect(controller.burstSuppressed, isFalse);
      controller.endPinch();
      controller.setBurstSuppressed(true);
      expect(controller.burstSuppressed, isTrue);
    });

    test('未开会的 setBurstSuppressed 语义不变（未选中态行为不变）', () {
      final controller = MetronomeOverlayController();
      controller.setBurstSuppressed(true);
      expect(controller.burstSuppressed, isTrue);
      controller.setBurstSuppressed(false);
      expect(controller.burstSuppressed, isFalse);
    });
  });

  group('可拖浮层 MetronomeOverlay（widget seam）', () {
    late MetronomeOverlayController controller;
    var behindTaps = 0;
    var closeTaps = 0;

    Future<void> pumpOverlay(
      WidgetTester tester, {
      BeatAnimationStyle style = BeatAnimationStyle.bar,
      Widget? child,
    }) async {
      behindTaps = 0;
      closeTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // 底层播放手势替身：常态穿透时应收到浮层区域的点击。
                Positioned.fill(
                  child: GestureDetector(
                    key: const Key('behind_surface'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => behindTaps++,
                  ),
                ),
                MetronomeOverlay(
                  controller: controller,
                  style: style,
                  onClose: () => closeTaps++,
                  child: child ?? const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    setUp(() {
      controller = MetronomeOverlayController();
    });

    testWidgets('常态穿透：IgnorePointer，点击落到底层播放面、无选中框', (tester) async {
      await pumpOverlay(tester);
      await tester.tap(find.byKey(const Key('behind_surface')));
      await tester.pump();

      expect(behindTaps, 1);
      expect(find.byKey(const Key('metronome_overlay_selected')), findsNothing);
      expect(find.byKey(const Key('metronome_overlay_close')), findsNothing);
    });

    testWidgets('点选进选中态：矩形框 + 4 角工具（右下为锁定钮）', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('metronome_overlay_close')), findsOneWidget);
      expect(find.byKey(const Key('metronome_overlay_reset')), findsOneWidget);
      expect(
        find.byKey(const Key('metronome_overlay_beat_panel')),
        findsOneWidget,
      );
      // 右下没有拖把手，改为锁定钮。
      expect(find.byKey(const Key('metronome_overlay_handle')), findsNothing);
      expect(find.byKey(const Key('metronome_overlay_lock')), findsOneWidget);
    });

    testWidgets('四角工具报出主动语态中文名', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      expectButtonSemantics(
        tester,
        const Key('metronome_overlay_close'),
        label: '关闭数拍浮层',
      );
      expectButtonSemantics(
        tester,
        const Key('metronome_overlay_reset'),
        label: '重置数拍浮层位置',
      );
      expectButtonSemantics(
        tester,
        const Key('metronome_overlay_beat_panel'),
        label: '切换节拍提示面板',
      );
      expectButtonSemantics(
        tester,
        const Key('metronome_overlay_lock'),
        label: '锁定数拍浮层',
      );

      // 锁定后名字改为解锁动作（名字说清当前这一步会做什么）。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expectButtonSemantics(
        tester,
        const Key('metronome_overlay_lock'),
        label: '解锁数拍浮层',
      );
      handle.dispose();
    });

    testWidgets('单指主体拖动 = 宿主仲裁：widget 层 body 穿透不吞命中', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      // 选中态 body 对指针穿透：单指落主体拖动不由浮层自身消费（宿主
      // scale 仲裁处平移），拖动落到底层播放替身也不改变位置。
      final body =
          tester.getTopLeft(
            find.byKey(const Key('metronome_overlay_selected')),
          ) +
          const Offset(80, 48);
      final gesture = await tester.startGesture(body);
      await gesture.moveBy(const Offset(60, 40));
      await gesture.up();
      await tester.pump();

      // 未接线视口（钳制框 null）：生效位仍停屏左上默认位，未被拖动。
      expect(controller.effectiveOffset, Offset.zero);
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        isNull,
      );
    });

    testWidgets('锁定钮切换：锁定外观 + 锁定态；解锁恢复', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      // 初始未锁定：解锁图标。
      expect(controller.locked, isFalse);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);

      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(controller.locked, isTrue);
      expect(find.byIcon(Icons.lock), findsOneWidget);

      // 再点解锁恢复。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(controller.locked, isFalse);
      expect(find.byIcon(Icons.lock_open), findsOneWidget);
    });

    testWidgets('四角工具命中盒 ≥ 48、互不重叠；视觉图标仍 20dp 且居原位', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      const expectedCenters = {
        'metronome_overlay_close': Alignment.topLeft,
        'metronome_overlay_reset': Alignment.topRight,
        'metronome_overlay_beat_panel': Alignment.bottomLeft,
        'metronome_overlay_lock': Alignment.bottomRight,
      };
      final overlay = tester.getRect(
        find.byKey(const Key('metronome_overlay_selected')),
      );
      final rects = <Rect>[];
      for (final entry in expectedCenters.entries) {
        final finder = find.byKey(Key(entry.key));
        final rect = tester.getRect(finder);
        expect(
          rect.width,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '${entry.key} 命中盒宽 ≥ 48',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '${entry.key} 命中盒高 ≥ 48',
        );
        rects.add(rect);
        // 图标视觉 20dp 不变（外扩不放大图标）。
        final icon = tester.getRect(
          find.descendant(of: finder, matching: find.byType(Icon)),
        );
        expect(icon.size, const Size(20, 20), reason: '${entry.key} 图标仍 20dp');
        // 图标仍距浮层对应角 20dp（命中盒外扩不移动图标）。
        final expected = Offset(
          entry.value.x > 0 ? overlay.right - 20 : overlay.left + 20,
          entry.value.y > 0 ? overlay.bottom - 20 : overlay.top + 20,
        );
        expect(icon.center, expected, reason: '${entry.key} 图标在原位');
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse, reason: '四角命中域不互吞');
        }
      }
    });

    testWidgets('锁定不持久化：deselect 后再 select 默认解锁', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();
      controller.setLocked(true);
      await tester.pump();
      expect(controller.locked, isTrue);

      // 退出选中态（如点浮层外 / 控制层展开）后重进 → 默认解锁。
      controller.deselect();
      await tester.pump();
      controller.select();
      await tester.pump();
      expect(controller.locked, isFalse);
    });

    testWidgets('缩放会话：矩形外张只改宽系数、不改位置，钳制上限 2.5', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      controller
        ..beginPinch()
        ..updatePinch(scale: 99.0, horizontalScale: 99.0);
      await tester.pump();

      expect(controller.placements.rectWidthFactor, 2.5);
      expect(controller.placements.pendulumScale, 1.0);
      // 位置不因缩放被改写：容器无自定义位，生效位仍是默认位。
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        isNull,
      );
      expect(controller.effectiveOffset, Offset.zero);
    });

    testWidgets('缩放会话：矩形只取水平分量——纵向倍率不改宽系数', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      controller
        ..beginPinch()
        ..updatePinch(scale: 4.0, horizontalScale: 1.0);
      await tester.pump();

      expect(controller.placements.rectWidthFactor, 1.0);
    });

    testWidgets('缩放会话：矩形内合灵敏度减半（累计 0.33 → 系数 0.667）', (tester) async {
      controller.applyPlacements(overlayPlacements(offset: Offset(20, 20)));
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      controller
        ..beginPinch()
        ..updatePinch(scale: 1 / 3, horizontalScale: 1 / 3);
      await tester.pump();

      expect(controller.placements.rectWidthFactor, closeTo(2 / 3, 0.001));
      expect(controller.placements.pendulumScale, 1.0);
    });

    testWidgets('缩放会话：摆锤整体等比、矩形宽系数独立不变', (tester) async {
      controller.applyPlacements(
        overlayPlacements(offset: Offset(20, 20), rectWidthFactor: 1.5),
      );
      await pumpOverlay(tester, style: BeatAnimationStyle.pendulum);
      controller.select();
      await tester.pump();

      controller
        ..beginPinch()
        ..updatePinch(scale: 3.0, horizontalScale: 3.0);
      await tester.pump();

      // 灵敏度 ×0.5：累计 scale 3 → 生效 2.0。
      expect(controller.placements.pendulumScale, 2.0);
      // 分形态独立：矩形宽系数不被摆锤捏合改写。
      expect(controller.placements.rectWidthFactor, 1.5);
    });

    testWidgets('常态渲染按保存系数：矩形实宽布局、摆锤整体等比', (tester) async {
      // 矩形：默认宽 320；系数 1.5 → 实宽 480，高固定。
      controller.applyPlacements(
        overlayPlacements(offset: Offset(10, 10), rectWidthFactor: 1.5),
      );
      await pumpOverlay(tester);
      expect(_overlayContentSize(tester), const Size(480, 120));

      // 摆锤：等比系数 2 → 440×240（宽沿用摆锤专属窄基准 220，含数字等比）。
      controller.applyPlacements(
        overlayPlacements(offset: Offset(10, 10), pendulumScale: 2.0),
      );
      await pumpOverlay(tester, style: BeatAnimationStyle.pendulum);
      expect(_overlayContentSize(tester), const Size(440, 240));
    });

    testWidgets('常态与选中态同尺寸（保存系数一致渲染）', (tester) async {
      controller.applyPlacements(
        overlayPlacements(offset: Offset(10, 10), rectWidthFactor: 1.25),
      );
      await pumpOverlay(tester);
      final normalSize = _overlayContentSize(tester);
      controller.select();
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const Key('metronome_overlay_selected'))),
        normalSize,
      );
    });

    testWidgets('矩形缩到最小钳制不触发渲染溢出', (tester) async {
      controller.applyPlacements(
        overlayPlacements(offset: Offset(10, 10), rectWidthFactor: 0.9),
      );
      await pumpOverlay(
        tester,
        // 内容 = 8 个 19px 固宽格（152px）：宽度低于 152 即渲染溢出，
        // 钳制下限 0.5（实宽 160）应容纳。
        child: Row(
          children: List.generate(
            8,
            (i) => SizedBox(key: ValueKey('cell_$i'), width: 19),
          ),
        ),
      );
      controller.select();
      await tester.pump();

      // 深度内合：累计水平分量 ≈0.083 → 减半生效 ≈0.542 → 0.9×0.542
      // ≈ 0.488 → 钳 0.5。
      controller
        ..beginPinch()
        ..updatePinch(scale: 1 / 12, horizontalScale: 1 / 12);
      await tester.pump();

      expect(controller.placements.rectWidthFactor, 0.5);
      expect(tester.takeException(), isNull);
    });

    testWidgets('混区闩锁抑制：角工具（含锁定钮）均被抑制', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      controller.setBurstSuppressed(true);
      await tester.pump();

      // 锁定钮被抑制：点按不改锁定态。
      await tester.tap(find.byKey(const Key('metronome_overlay_lock')));
      await tester.pump();
      expect(controller.locked, isFalse);

      await tester.tap(find.byKey(const Key('metronome_overlay_close')));
      await tester.pump();
      expect(closeTaps, 0);
    });

    testWidgets('关闭角工具回调宿主（退出选中态归宿主仲裁）', (tester) async {
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      await tester.tap(find.byKey(const Key('metronome_overlay_close')));
      await tester.pump();
      expect(closeTaps, 1);
      expect(controller.selected, isTrue);
    });

    testWidgets('重置角工具：位置与缩放回到默认位', (tester) async {
      controller.applyPlacements(
        overlayPlacements(
          offset: Offset(120, 80),
          rectWidthFactor: 2.0,
          pendulumScale: 2.0,
        ),
      );
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      await tester.tap(find.byKey(const Key('metronome_overlay_reset')));
      await tester.pump();

      // 重置 = 清自定义位（当前格回未自定义）+ 系数回 1.0；未接线视口下
      // 生效位回落屏左上默认位。
      expect(controller.placements, const OverlayPlacements());
      expect(controller.effectiveOffset, Offset.zero);
    });
  });

  group('浮层越界钳制（视口联动 + 屏内钳制）', () {
    late MetronomeOverlayController controller;

    setUp(() {
      controller = MetronomeOverlayController();
    });

    Future<void> pumpOverlay(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                MetronomeOverlay(
                  controller: controller,
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    test('moveBy 拖出视口右/下边界 → 生效位钳回屏内贴边（存值 = 用户意图）', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(800, 600));
      controller.moveBy(const Offset(2000, 1200));
      // 生效面：右/下贴边（800−320、600−120）。
      expect(controller.effectiveOffset, const Offset(800 - 320, 600 - 120));
      // 钳制结果不写回：容器存的是用户意图（默认位 + 位移）。
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(2000, 600 * 0.12 + 1200),
      );
    });

    test('moveBy 拖出左/上边界 → 生效位钳回 0（存值保留越界意图）', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(800, 600))
        ..applyPlacements(overlayPlacements(offset: Offset(100, 100)));
      controller.moveBy(const Offset(-500, -500));
      expect(controller.effectiveOffset, Offset.zero);
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(-400, -400),
      );
    });

    test('捏合放大：生效上限钳到铺满视口（矩形）', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(800, 600));
      controller.applyRectPinch(99.0);
      expect(controller.placements.rectWidthFactor, 2.5); // 落盘值不被视口改写
      expect(
        controller.hitRect().size,
        Size(800, kOverlayBaseContentSize.height),
      );
    });

    test('捏合放大：生效上限钳到铺满视口（摆锤，宽高取更紧）', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(440, 300))
        ..style = BeatAnimationStyle.pendulum;
      controller.applyPendulumPinch(99.0);
      expect(controller.placements.pendulumScale, 2.5); // 上限 2.5
      // 窄基准 220：宽维上限 440/220=2.0 钳到 2 → 实宽 440、高 240。
      expect(controller.hitRect().size, const Size(440, 240));
    });

    test('恢复（applyPlacements）：越屏存值只在生效面钳；系数钳回上限', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(800, 600));
      controller.applyPlacements(
        overlayPlacements(
          offset: Offset(5000, 5000),
          rectWidthFactor: 3.0, // 界外：写入即钳到上限 2.5。
        ),
      );
      expect(controller.placements.rectWidthFactor, 2.5);
      // 存值原样保留（转回原姿态原样恢复）；生效位：宽铺满视口 → dx 左上
      // 对齐 0；dy 贴下缘。
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(5000, 5000),
      );
      expect(controller.effectiveOffset, const Offset(0, 480));
    });

    // setViewport 是控制器入参（应用内视口），不经测试窗视口接缝；下面的
    // 1368×632 / 632×1368 均为刻意放宽/收窄的**合成档**（非设备基准）。
    test('旋转/方向变化（setViewport）：生效位按新视口现钳；存值一字不改', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(1368, 632))
        ..applyPlacements(overlayPlacements(offset: Offset(450, 300)));
      // 横屏 1368×632 量级：dx 450+320=770 ≤ 1368、dy 300+120=420 ≤ 632 → 不动。
      expect(controller.effectiveOffset, const Offset(450, 300));
      // 转竖屏 632×1368 量级：dx 450+320=770 > 632 → 生效位钳回 312；dy 界内不动。
      controller.setViewport(const Size(632, 1368));
      expect(controller.effectiveOffset, const Offset(312, 300));
      // 钳制不回写：转回原姿态原样恢复。
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(450, 300),
      );
      controller.setViewport(const Size(1368, 632));
      expect(controller.effectiveOffset, const Offset(450, 300));
    });

    test('形态切换（set style）：生效位按新尺寸重钳；存值不改', () {
      final controller = MetronomeOverlayController()
        ..setViewport(const Size(800, 600))
        ..applyPlacements(overlayPlacements(offset: Offset(100, 480)));
      // bar 形态高 120：480+120=600 贴下缘，界内。
      expect(controller.effectiveOffset, const Offset(100, 480));
      // 切摆锤等比 2 → 内容高 240：480+240=720 > 600 → 生效位钳回 360。
      controller
        ..style = BeatAnimationStyle.pendulum
        ..applyPendulumPinch(2.0);
      expect(controller.effectiveOffset, const Offset(100, 360));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(100, 480),
      );
    });

    test('无视口（宿主未接线）→ 维持既有语义不钳（向后兼容 seam 缺省）', () {
      final controller = MetronomeOverlayController();
      controller.moveBy(const Offset(2000, 2000));
      expect(controller.effectiveOffset, const Offset(2000, 2000));
    });

    testWidgets('widget：放大到铺满视口不越界、锁定钮/角工具/选中框可达、双指可缩小', (tester) async {
      controller
        ..setViewport(const Size(400, 300))
        ..applyPlacements(
          overlayPlacements(offset: Offset(300, 200), rectWidthFactor: 3.0),
        );
      await pumpOverlay(tester);
      controller.select();
      await tester.pump();

      // 内容钳到铺满视口宽、位置钳回视口内（宽贴满 → 左对齐；dy 贴下缘 180）。
      expect(
        tester.getTopLeft(find.byKey(const Key('metronome_overlay_selected'))),
        const Offset(0, 180),
      );
      expect(
        tester.getSize(find.byKey(const Key('metronome_overlay_selected'))),
        Size(400, kOverlayBaseContentSize.height),
      );
      // 右下锁定钮 / 角工具在屏内可达。
      final lockRect = tester.getRect(
        find.byKey(const Key('metronome_overlay_lock')),
      );
      expect(lockRect.bottomRight, const Offset(400, 300));
      // 命中盒外扩到 48 后，角工具盒向浮层内
      // 延伸；图标仍居原位（距浮层右缘 30、距下缘 30 起），观感不变。
      expect(
        tester
            .getRect(
              find.descendant(
                of: find.byKey(const Key('metronome_overlay_reset')),
                matching: find.byType(Icon),
              ),
            )
            .topLeft,
        const Offset(370, 190),
      );
      expect(
        tester.getRect(find.byKey(const Key('metronome_overlay_reset'))).size,
        const Size(kHitTargetMinSize, kHitTargetMinSize),
      );

      // 缩小可用：缩放会话深度内合（累计 0.2 → 减半生效 0.6 → 2.5×0.6
      // = 1.5）→ 系数显著下降，且不越下限。
      controller
        ..beginPinch()
        ..updatePinch(scale: 0.2, horizontalScale: 0.2);
      await tester.pump();

      expect(controller.placements.rectWidthFactor, lessThanOrEqualTo(1.5));
      expect(
        controller.placements.rectWidthFactor,
        greaterThanOrEqualTo(kMinRectWidthFactor),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('浮层位切格与默认位', () {
    test('未自定义格 = 贴左、纵向视口高 12%（按当前视口现算）', () {
      final controller = controllerAt(const Size(800, 600));
      expect(controller.cell, OverlayPlacementCell.portraitNormal);
      expect(controller.effectiveOffset, const Offset(0, 72));
      // 视口高变化：默认位随之变化，横向恒贴左（不牵进浮层宽度）。
      controller.setViewport(const Size(800, 1000));
      expect(controller.effectiveOffset, const Offset(0, 120));
    });

    test('四格默认位同款：横屏格未自定义时同样是贴左 12%', () {
      final controller = controllerAt(const Size(800, 600));
      controller.setCell(OverlayPlacementCell.landscapeNormal);
      expect(controller.effectiveOffset, const Offset(0, 72));
      controller.setCell(OverlayPlacementCell.portraitCompare);
      expect(controller.effectiveOffset, const Offset(0, 72));
      controller.setCell(OverlayPlacementCell.landscapeCompare);
      expect(controller.effectiveOffset, const Offset(0, 72));
    });

    test('切格取该格的值；未自定义格取默认位（各格互不串值）', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(
          const OverlayPlacements(
            offsets: {
              OverlayPlacementCell.portraitNormal: Offset(10, 20),
              OverlayPlacementCell.landscapeNormal: Offset(30, 40),
              OverlayPlacementCell.portraitCompare: Offset(50, 60),
            },
          ),
        );
      expect(controller.effectiveOffset, const Offset(10, 20));
      controller.setCell(OverlayPlacementCell.landscapeNormal);
      expect(controller.effectiveOffset, const Offset(30, 40));
      controller.setCell(OverlayPlacementCell.portraitCompare);
      expect(controller.effectiveOffset, const Offset(50, 60));
      // 未自定义格：默认位现算。
      controller.setCell(OverlayPlacementCell.landscapeCompare);
      expect(controller.effectiveOffset, const Offset(0, 72));
    });

    // 1368×632 / 632×1368：刻意放宽/收窄的**合成档**（非设备基准）。
    test('切格后生效位钳回钳制框、容器值不变；切回原格恢复原值', () {
      final controller = controllerAt(const Size(1368, 632))
        ..applyPlacements(
          const OverlayPlacements(
            offsets: {
              OverlayPlacementCell.landscapeNormal: Offset(450, 300),
              OverlayPlacementCell.portraitNormal: Offset(450, 300),
            },
          ),
        );
      // 横屏格 1368×632 量级：界内不动。
      controller.setCell(OverlayPlacementCell.landscapeNormal);
      expect(controller.effectiveOffset, const Offset(450, 300));
      // 转竖屏（视口宽高互换）→ 落竖屏·普通格，生效位钳回屏内。
      controller
        ..setViewport(const Size(632, 1368))
        ..setCell(OverlayPlacementCell.portraitNormal);
      expect(controller.effectiveOffset, const Offset(312, 300));
      // 钳制不回写：容器里两格的值一字未改。
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(450, 300),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        const Offset(450, 300),
      );
      // 转回原姿态 → 原值原样恢复。
      controller
        ..setViewport(const Size(1368, 632))
        ..setCell(OverlayPlacementCell.landscapeNormal);
      expect(controller.effectiveOffset, const Offset(450, 300));
    });

    test('切格不改写容器：转屏/开关对比本身零写入', () {
      const before = OverlayPlacements(
        offsets: {
          OverlayPlacementCell.portraitNormal: Offset(10, 20),
          OverlayPlacementCell.portraitCompare: Offset(500, 400),
        },
      );
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(before);
      controller.setCell(OverlayPlacementCell.portraitCompare);
      controller.setViewport(const Size(600, 800));
      controller.setCell(OverlayPlacementCell.portraitNormal);
      expect(controller.placements, before);
    });

    test('切格不动选中态与锁定态', () {
      final controller = controllerAt(const Size(800, 600))
        ..select()
        ..setLocked(true);
      controller.setCell(OverlayPlacementCell.landscapeCompare);
      expect(controller.selected, isTrue);
      expect(controller.locked, isTrue);
    });

    test('命中区与显示位置同源：切格后 hitRect 立即跟到新格', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(
          const OverlayPlacements(
            offsets: {OverlayPlacementCell.landscapeNormal: Offset(100, 100)},
          ),
        );
      expect(controller.hitTest(const Offset(120, 120)), isTrue);
      controller.setCell(OverlayPlacementCell.landscapeNormal);
      expect(controller.hitRect().topLeft, const Offset(100, 100));
      expect(controller.hitTest(const Offset(120, 120)), isTrue);
      expect(controller.hitTest(const Offset(20, 20)), isFalse);
    });

    test('拖动中切格：位移结算进切格前那一格，手势随即结束且不复燃', () {
      final controller = controllerAt(const Size(800, 600))..beginMove();
      controller.moveBy(const Offset(10, 5));
      controller.setCell(OverlayPlacementCell.landscapeNormal);
      controller.moveBy(const Offset(30, 30));
      // 切格前的位移落竖屏·普通格；切格后的帧不再生效。
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(10, 77),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        isNull,
      );
      // A→B→A：切回原格也不恢复写入（本手势已结束，闩锁到 burst 收尾）。
      controller.setCell(OverlayPlacementCell.portraitNormal);
      controller.moveBy(const Offset(100, 100));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(10, 77),
      );
      // 新手势（beginMove）回到当前格继续生效。
      controller.endMove();
      controller.beginMove();
      controller.moveBy(const Offset(1, 1));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(11, 78),
      );
    });

    test('在一格里拖动：另外三格已存值一字不变', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(
          const OverlayPlacements(
            offsets: {
              OverlayPlacementCell.portraitNormal: Offset(10, 20),
              OverlayPlacementCell.landscapeNormal: Offset(30, 40),
              OverlayPlacementCell.portraitCompare: Offset(50, 60),
              OverlayPlacementCell.landscapeCompare: Offset(70, 80),
            },
          ),
        );
      controller.moveBy(const Offset(5, 5));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(15, 25),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        const Offset(30, 40),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitCompare),
        const Offset(50, 60),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeCompare),
        const Offset(70, 80),
      );
    });

    test('捏合进行中切格：缩放落共用系数、位置切到新格', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(
          const OverlayPlacements(
            offsets: {
              OverlayPlacementCell.portraitNormal: Offset(10, 20),
              OverlayPlacementCell.landscapeNormal: Offset(300, 100),
            },
          ),
        )
        ..beginPinch()
        ..updatePinch(scale: 2.0, horizontalScale: 2.0);
      controller.setCell(OverlayPlacementCell.landscapeNormal);
      controller.updatePinch(scale: 2.0, horizontalScale: 2.0);
      // 尺寸系数四格共用：切格后继续缩放仍写在共用系数上；位置取新格。
      expect(controller.placements.rectWidthFactor, 1.5);
      expect(controller.effectiveOffset, const Offset(300, 100));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(10, 20),
      );
    });
  });

  group('重置只清当前格', () {
    /// 四格各有自定义位 + 两个系数都非默认。
    const fourCells = OverlayPlacements(
      offsets: {
        OverlayPlacementCell.portraitNormal: Offset(10, 20),
        OverlayPlacementCell.landscapeNormal: Offset(30, 40),
        OverlayPlacementCell.portraitCompare: Offset(50, 60),
        OverlayPlacementCell.landscapeCompare: Offset(70, 80),
      },
      rectWidthFactor: 1.5,
      pendulumScale: 0.75,
    );

    test('重置只清当前格：该格回未自定义（生效位 = 默认位），另三格一字不动', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(fourCells)
        // 当前格 = 竖屏 · 对比。
        ..setCell(OverlayPlacementCell.portraitCompare)
        ..resetPlacement();

      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitCompare),
        isNull,
      );
      expect(controller.effectiveOffset, const Offset(0, 72));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(10, 20),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        const Offset(30, 40),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeCompare),
        const Offset(70, 80),
      );
    });

    test('反向同理：在普通格重置，已存的对比格位置一字不动', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(fourCells)
        // 当前格 = 横屏 · 普通。
        ..setCell(OverlayPlacementCell.landscapeNormal)
        ..resetPlacement();

      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeNormal),
        isNull,
      );
      expect(controller.effectiveOffset, const Offset(0, 72));
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitCompare),
        const Offset(50, 60),
      );
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.landscapeCompare),
        const Offset(70, 80),
      );
    });

    test('重置把两个共用尺寸系数回 1.0：两形态生效尺寸都随之回默认', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(fourCells)
        ..setCell(OverlayPlacementCell.landscapeCompare);
      controller.style = BeatAnimationStyle.bar;
      expect(controller.hitRect().size, isNot(kOverlayBaseContentSize));

      controller.resetPlacement();

      expect(controller.placements.rectWidthFactor, 1.0);
      expect(controller.placements.pendulumScale, 1.0);
      expect(controller.hitRect().size, kOverlayBaseContentSize);

      controller.style = BeatAnimationStyle.pendulum;
      expect(controller.hitRect().size, kPendulumBaseContentSize);
    });

    test('重置后切走再切回：该格仍未自定义（不留钳制残值）', () {
      final controller = controllerAt(const Size(800, 600))
        ..applyPlacements(
          const OverlayPlacements(
            offsets: {
              // 越界存值：生效面钳到 (480, 480)，重置不得把它当用户值留下。
              OverlayPlacementCell.portraitNormal: Offset(4000, 5000),
              OverlayPlacementCell.landscapeNormal: Offset(30, 40),
            },
          ),
        )
        ..setCell(OverlayPlacementCell.portraitNormal);
      expect(controller.effectiveOffset, const Offset(480, 480));

      controller.resetPlacement();
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        isNull,
      );

      controller
        ..setCell(OverlayPlacementCell.landscapeNormal)
        ..setCell(OverlayPlacementCell.portraitNormal);
      expect(
        controller.placements.offsetFor(OverlayPlacementCell.portraitNormal),
        isNull,
      );
      expect(controller.effectiveOffset, const Offset(0, 72));
    });
  });
}

/// 浮层常态内容实际尺寸（浮层 subtree 内的 IgnorePointer 即穿透底座）。
Size _overlayContentSize(WidgetTester tester) {
  return tester.getSize(
    find
        .descendant(
          of: find.byType(MetronomeOverlay),
          matching: find.byType(IgnorePointer),
        )
        .first,
  );
}

/// 有界真实网格替身（早于首拍定位 -1，真实网格边界语义）。
class _BoundedFakeGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  _BoundedFakeGrid({required this.firstBeat});

  final Duration firstBeat;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) =>
      firstBeat + Duration(milliseconds: 500 * index);

  @override
  int beatIndexAt(Duration time) {
    if (time < firstBeat) return -1;
    return (time.inMilliseconds - firstBeat.inMilliseconds) ~/ 500;
  }

  @override
  bool isDownbeat(int index) => index % 4 == 0;

  @override
  int get firstDownbeatIndex => 0;

  @override
  int? get lastBeatIndex => 100;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}

/// 非均匀强拍网格（非均匀用例；生产真实网格类型 [DocumentBeatGrid]）：
/// 拍点每 500ms 均匀，强拍序号 [_irregularDownbeats] 间距不等——拍序号算术
/// 与强拍序数在此类网格上分歧（算术会落到非强拍上，不成大线）。
DocumentBeatGrid _irregularDownbeatGrid() => documentGridOf(
  marker_doc.BeatGrid(
    model: 'madmom_downbeat_rnn_full.onnx',
    fps: 100,
    generatedAt: DateTime.utc(2026, 9, 14),
    beats: [
      for (var i = 0; i <= 40; i++)
        marker_doc.BeatPoint(t: i * 0.5, down: _irregularDownbeats.contains(i)),
    ],
  ),
);

/// 非均匀强拍序号：八拍大线 = 序数奇数者 {0, 8, 15, 23, 30}。
const Set<int> _irregularDownbeats = {0, 4, 8, 11, 15, 19, 23, 26, 30, 34};

/// 弱起有界真实网格替身（锚点对齐用例）：每拍 500ms、首拍（序号 0）
/// 非强拍，首个强拍在序号 1，其后每 4 拍一个强拍；早于首拍定位 -1，末拍
/// 序号 69（有界真实网格边界语义；八拍大线自首个强拍起每 8 拍一条，即
/// 序号 1 / 9 / … / 65）。
/// 就绪有界但**无强拍**的网格：八拍相位无原点，无任何八拍点。
class _NoDownbeatReadyGrid implements BeatGrid {
  const _NoDownbeatReadyGrid();

  @override
  BeatGridNature get nature => BeatGridNature.ready;

  @override
  int get lastBeatIndex => 9;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: 500 * index);

  @override
  int beatIndexAt(Duration time) =>
      time.inMilliseconds < 0 ? -1 : time.inMilliseconds ~/ 500;

  @override
  bool isDownbeat(int index) => false;

  @override
  int get firstDownbeatIndex => 0;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}

class _WeakStartFakeGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  const _WeakStartFakeGrid();

  /// 弱起：首个强拍（八拍相位原点）在序号 1，不在首拍。
  static const int _firstStrongBeat = 1;

  @override
  int get lastBeatIndex => 69;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: 500 * index);

  @override
  int beatIndexAt(Duration time) =>
      time.inMilliseconds < 0 ? -1 : time.inMilliseconds ~/ 500;

  @override
  bool isDownbeat(int index) => (index - _firstStrongBeat) % 4 == 0;

  @override
  int get firstDownbeatIndex => _firstStrongBeat;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => const [];
}
