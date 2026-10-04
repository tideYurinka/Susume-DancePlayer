import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/player/beat_track_tiers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';

void main() {
  group('节拍轨三级刻度分级', () {
    test('占位均匀网格：八拍大线 / 四拍中线 / 一拍小线 按八拍相位分级', () {
      const grid = UniformBeatGrid();
      final ticks = beatTrackTicks(
        grid,
        Duration.zero,
        const Duration(seconds: 8),
        phase: BeatPhase(grid: grid),
      );

      Duration at(int beat) => Duration(milliseconds: beat * 500);
      tierOf(Duration t) => ticks.firstWhere((tick) => tick.time == t).tier;

      // 八拍区间（8 拍 = 4s）的第 1 条 downbeat = 大线、第 2 条 = 中线。
      expect(tierOf(at(0)), BeatTickTier.eightBar);
      expect(tierOf(at(8)), BeatTickTier.eightBar);
      expect(tierOf(at(16)), BeatTickTier.eightBar);
      expect(tierOf(at(4)), BeatTickTier.fourBar);
      expect(tierOf(at(12)), BeatTickTier.fourBar);
      // 其余每拍 = 一拍小线。
      expect(tierOf(at(2)), BeatTickTier.beat);
      expect(tierOf(at(7)), BeatTickTier.beat);
      expect(tierOf(at(15)), BeatTickTier.beat);
    });

    test('窗口切断不改变八拍相位：t=4s 起窗首仍判大线', () {
      const grid = UniformBeatGrid();
      final ticks = beatTrackTicks(
        grid,
        const Duration(seconds: 4),
        const Duration(seconds: 12),
        phase: BeatPhase(grid: grid),
      );
      expect(ticks.first.time, const Duration(seconds: 4));
      expect(ticks.first.tier, BeatTickTier.eightBar);
    });

    test('真实网格弱起：首强拍前只有一拍小线，不派生大线/中线', () {
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: [
            marker_doc.BeatPoint(t: 0.1, down: false), // 弱起拍
            marker_doc.BeatPoint(t: 0.25, down: true), // 首强拍
            marker_doc.BeatPoint(t: 1.25, down: true),
            marker_doc.BeatPoint(t: 2.25, down: true),
            marker_doc.BeatPoint(t: 3.25, down: true),
            marker_doc.BeatPoint(t: 4.25, down: true),
          ],
        ),
      );
      final ticks = beatTrackTicks(
        grid,
        Duration.zero,
        const Duration(seconds: 5),
        phase: BeatPhase(grid: grid),
      );

      tierOf(int ms) =>
          ticks.firstWhere((tick) => tick.time.inMilliseconds == ms).tier;
      expect(tierOf(100), BeatTickTier.beat, reason: '弱起拍只按拍点呈现');
      expect(tierOf(250), BeatTickTier.eightBar);
      expect(tierOf(1250), BeatTickTier.fourBar);
      expect(tierOf(2250), BeatTickTier.eightBar);
      expect(tierOf(3250), BeatTickTier.fourBar);
      expect(tierOf(4250), BeatTickTier.eightBar);
    });

    test('真实网格无 downbeat（识别退化）：全部一拍小线', () {
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: [
            marker_doc.BeatPoint(t: 0.0, down: false),
            marker_doc.BeatPoint(t: 0.5, down: false),
            marker_doc.BeatPoint(t: 1.0, down: false),
          ],
        ),
      );
      final ticks = beatTrackTicks(
        grid,
        Duration.zero,
        const Duration(seconds: 2),
        phase: BeatPhase(grid: grid),
      );
      expect(ticks.every((tick) => tick.tier == BeatTickTier.beat), isTrue);
      expect(ticks, hasLength(3));
    });

    test('分级与 core 相位源同源：任意窗口切断下大线集合', () {
      // 变速（非均匀拍距）真实网格：八拍大线判定自首个强拍起按 downbeat
      // 全局序数奇偶派生（序数法，core/eight_beat_phase.dart）。轨道刻度
      // 的大线时刻集合必须与相位源的窗口八拍点序列逐位一致（含任意窗口
      // 切断——窗口首 downbeat 不重置相位），四拍中线 = 其余 downbeat。
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: [
            marker_doc.BeatPoint(t: 0.1, down: false), // 弱起拍
            for (var i = 0; i < 9; i++)
              marker_doc.BeatPoint(t: 0.25 + i * 1.3, down: i % 2 == 0),
          ],
        ),
      );
      for (final cutMs in const [0, 300, 1600, 2900, 4200]) {
        final start = Duration(milliseconds: cutMs);
        const end = Duration(seconds: 20);
        final tierEightBars = [
          for (final tick in beatTrackTicks(
            grid,
            start,
            end,
            phase: BeatPhase(grid: grid),
          ))
            if (tick.tier == BeatTickTier.eightBar) tick.time,
        ];
        expect(
          tierEightBars,
          BeatPhase(grid: grid).pointsInWindow(start, end),
          reason: '窗口切断于 ${cutMs}ms 时大线集合须与相位源一致',
        );
        final ticksByTime = {
          for (final tick in beatTrackTicks(
            grid,
            start,
            end,
            phase: BeatPhase(grid: grid),
          ))
            tick.time: tick,
        };
        // 其余 downbeat（含相位原点后的偶数序）= 四拍中线；弱起/非 downbeat
        // = 一拍小线。逐刻度核对层级与相位源判定同源。
        for (final tick in ticksByTime.values) {
          final index = grid.beatIndexAt(tick.time);
          if (index < grid.firstDownbeatIndex || !grid.isDownbeat(index)) {
            expect(tick.tier, BeatTickTier.beat, reason: '窗口切断于 ${cutMs}ms');
          } else {
            expect(
              tick.tier,
              BeatPhase(grid: grid)
                      .pointsInWindow(tick.time, tick.time)
                      .contains(tick.time)
                  ? BeatTickTier.eightBar
                  : BeatTickTier.fourBar,
              reason: '窗口切断于 ${cutMs}ms',
            );
          }
        }
      }
    });
  });

  group('刻度宽按层级取值', () {
    test('八拍大线 1.5px、四拍中线 1px、一拍小线 1px', () {
      expect(beatTickWidthOf(BeatTickTier.eightBar), 1.5);
      expect(beatTickWidthOf(BeatTickTier.fourBar), 1.0);
      expect(beatTickWidthOf(BeatTickTier.beat), 1.0);
    });
  });

  group('节拍轨八拍数标注派生（段内相对编号）', () {
    // 就绪真实网格：0.5s 均匀拍点、每 4 拍一个 downbeat（与占位同几何），
    // 覆盖 0..40s → 八拍大线在 t = 0、4、8…s。
    DocumentBeatGrid uniformReadyGrid({
      double seconds = 40,
      List<int> anchors = const [],
    }) {
      final count = (seconds / 0.5).round() + 1;
      return documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: [
            for (var i = 0; i < count; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
          ],
        ),
      );
    }

    // 默认单学习段 [rangeStart, rangeEnd]（无分段线的隐式整段）。
    List<BeatEightCountLabel> labels({
      BeatGrid? grid,
      Duration rangeStart = Duration.zero,
      Duration rangeEnd = const Duration(seconds: 40),
      List<LearningSegment>? segments,
      Duration windowStart = Duration.zero,
      Duration windowEnd = const Duration(seconds: 40),
      double microsecondsPerPixel = 10,
      double minSpacingPx = 32,
      Set<Duration> hiddenAtTimes = const {},
    }) {
      final resolvedGrid = grid ?? uniformReadyGrid();
      return beatEightCountLabels(
        grid: resolvedGrid,
        segments:
            segments ??
            [LearningSegment(order: 0, start: rangeStart, end: rangeEnd)],
        windowStart: windowStart,
        windowEnd: windowEnd,
        microsecondsPerPixel: microsecondsPerPixel,
        minSpacingPx: minSpacingPx,
        phase: BeatPhase(grid: resolvedGrid),
        hiddenAtTimes: hiddenAtTimes,
      );
    }

    // 变速真实网格：各小节（首拍 = downbeat）时长不匀（节拍识别变速）。
    // 八拍大线 = 序号为奇数的 downbeat → 大线候选间距不匀，用于「窗口内
    // 既有 ≥32px 宽间距、又有 <32px 窄间距 → 整窗不得混杂」的判定用例。
    DocumentBeatGrid tempoChangedGrid() {
      // 小节首拍（downbeat）时刻毫秒；每小节 4 拍（3 弱拍填在 downbeat 间）。
      const barMs = <int>[1000, 2000, 6500, 6700, 7200, 7300, 9000, 9100];
      final beats = <marker_doc.BeatPoint>[];
      for (var b = 0; b < barMs.length; b++) {
        final start = barMs[b];
        final next = b + 1 < barMs.length ? barMs[b + 1] : start + 400;
        beats.add(marker_doc.BeatPoint(t: start / 1000, down: true));
        for (var k = 1; k < 4; k++) {
          beats.add(
            marker_doc.BeatPoint(
              t: (start + k * (next - start) / 4) / 1000,
              down: false,
            ),
          );
        }
      }
      return documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: beats,
        ),
      );
    }

    List<LearningSegment> segmentsBetween(List<Duration> bounds) => [
      for (var i = 0; i < bounds.length - 1; i++)
        LearningSegment(order: i, start: bounds[i], end: bounds[i + 1]),
    ];

    test('非就绪网格（占位/异常）不标注', () {
      // 可用性由网格自陈——占位均匀网格真实拍点不可用。
      expect(labels(grid: const UniformBeatGrid()), isEmpty);
    });

    test('无学习段（未创建分段线）不标注', () {
      expect(labels(segments: const []), isEmpty);
    });

    test('段内相对编号：段首同位大线占 1，其后大线 2、3…顺数', () {
      // 首线 t=0 与段首八拍同位 → 跳过但占序号 1；其后 t=4、8、12 → 2、3、4。
      expect(labels(rangeEnd: const Duration(seconds: 16)), const [
        BeatEightCountLabel(time: Duration(seconds: 4), count: 2),
        BeatEightCountLabel(time: Duration(seconds: 8), count: 3),
        BeatEightCountLabel(time: Duration(seconds: 12), count: 4),
      ]);
    });

    test('跨段重数：两段各自从 1 重新计数', () {
      // 分段线 t=16 → 段 [0,16] 与 [16,40]；t=16 大线与段二段首同位
      // → 不标但占段二序号 1；t=20 重新从 2 起数。
      final result = labels(
        segments: segmentsBetween(const [
          Duration.zero,
          Duration(seconds: 16),
          Duration(seconds: 40),
        ]),
      );
      expect(result, const [
        BeatEightCountLabel(time: Duration(seconds: 4), count: 2),
        BeatEightCountLabel(time: Duration(seconds: 8), count: 3),
        BeatEightCountLabel(time: Duration(seconds: 12), count: 4),
        BeatEightCountLabel(time: Duration(seconds: 20), count: 2),
        BeatEightCountLabel(time: Duration(seconds: 24), count: 3),
        BeatEightCountLabel(time: Duration(seconds: 28), count: 4),
        BeatEightCountLabel(time: Duration(seconds: 32), count: 5),
        BeatEightCountLabel(time: Duration(seconds: 36), count: 6),
      ]);
    });

    test('段中与分段线同位的大线不标、但仍占所在段序号', () {
      // 分段线 t=8 → 段 [0,8] 与 [8,40]；t=8 大线 = 段二段首占 1 不标。
      final result = labels(
        segments: segmentsBetween(const [
          Duration.zero,
          Duration(seconds: 8),
          Duration(seconds: 40),
        ]),
      );
      expect(
        result.where((l) => l.time == const Duration(seconds: 8)),
        isEmpty,
      );
      expect(
        result.where((l) => l.time == const Duration(seconds: 12)).single,
        const BeatEightCountLabel(time: Duration(seconds: 12), count: 2),
      );
    });

    test('让位隐藏：hiddenAtTimes 处不标、但占序号（相邻序号连续）', () {
      // 单段 [0,40]：大线 t=4…36 顺数 2…10；隐藏 t=8（序号 3）与 t=20
      //（序号 6）→ 不标但占号，其余序号连续不前移。
      final result = labels(
        hiddenAtTimes: {
          const Duration(seconds: 8),
          const Duration(seconds: 20),
        },
      );
      expect(result, const [
        BeatEightCountLabel(time: Duration(seconds: 4), count: 2),
        BeatEightCountLabel(time: Duration(seconds: 12), count: 4),
        BeatEightCountLabel(time: Duration(seconds: 16), count: 5),
        BeatEightCountLabel(time: Duration(seconds: 24), count: 7),
        BeatEightCountLabel(time: Duration(seconds: 28), count: 8),
        BeatEightCountLabel(time: Duration(seconds: 32), count: 9),
        BeatEightCountLabel(time: Duration(seconds: 36), count: 10),
      ]);
    });

    test('尾线同位大线不标、但占末段序号', () {
      // 尾线 t=36 非八拍整段末（段 [0,36] 末大线恰在尾线）→ 不标但占
      // 序号 10；t=32 仍 = 9。
      final result = labels(rangeEnd: const Duration(seconds: 36));
      expect(
        result.where((l) => l.time == const Duration(seconds: 36)),
        isEmpty,
      );
      expect(
        result.where((l) => l.time == const Duration(seconds: 32)).single,
        const BeatEightCountLabel(time: Duration(seconds: 32), count: 9),
      );
    });

    test('段首非八拍整点（旧数据）：段内第一个大线 = 1', () {
      final result = labels(
        segments: [
          LearningSegment(
            order: 0,
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 40),
          ),
        ],
      );
      expect(
        result.first,
        const BeatEightCountLabel(time: Duration(seconds: 12), count: 1),
      );
      expect(
        result.where(
          (l) =>
              l.time == const Duration(seconds: 4) ||
              l.time == const Duration(seconds: 8),
        ),
        isEmpty,
      );
    });

    test('相邻候选最小屏距不足 32px：整窗全部不标（严格两档）', () {
      // 大线间距 4s / 200000µs/px = 20px < 32 → 整窗一次判定全隐，
      // 不再隔一个大线放一个标的抽稀。
      expect(labels(microsecondsPerPixel: 200000), isEmpty);
    });

    test('间距阈值 ≤ 最小屏距时整窗全部候选放标', () {
      // 大线间距 20px ≥ 放宽阈值 10px → 窗口内 9 个候选全部放标（不抽稀）。
      final result = labels(microsecondsPerPixel: 200000, minSpacingPx: 10);
      expect(result, hasLength(9));
    });

    test('只标注可视窗口内的大线；段内序号不随窗口起点漂移', () {
      // 窗口 5–15s：t=4 在窗外不标但仍占序号 → t=8 = #3、t=12 = #4。
      final result = labels(
        rangeEnd: const Duration(seconds: 16),
        windowStart: const Duration(seconds: 5),
        windowEnd: const Duration(seconds: 15),
      );
      expect(result, const [
        BeatEightCountLabel(time: Duration(seconds: 8), count: 3),
        BeatEightCountLabel(time: Duration(seconds: 12), count: 4),
      ]);
    });

    test('整窗一次判定翻转点：相邻候选屏距恰 32.0px 全显、31.9px 全隐', () {
      // 单段 [0,12]：八拍大线候选 = t=4、8（段首 0 / 段尾 12 同位不标，
      // 占序号 1、4），相邻候选屏距由 4s 间距与 µsPerPx 决定。
      final seg = [
        LearningSegment(
          order: 0,
          start: Duration.zero,
          end: const Duration(seconds: 12),
        ),
      ];
      // 恰 32.0px：µsPerPx = 4e6µs / 32px → minGap == 32 全显。
      expect(
        labels(
          grid: uniformReadyGrid(),
          segments: seg,
          microsecondsPerPixel: 125000,
        ),
        const [
          BeatEightCountLabel(time: Duration(seconds: 4), count: 2),
          BeatEightCountLabel(time: Duration(seconds: 8), count: 3),
        ],
      );
      // 31.9px：µsPerPx 略大于 125000 → minGap < 32 全隐（无中间抽稀）。
      expect(
        labels(
          grid: uniformReadyGrid(),
          segments: seg,
          microsecondsPerPixel: 4000000 / 31.9,
        ),
        isEmpty,
      );
    });

    test('变速（非均匀拍距）窗口不混杂：存在 ≥32px 宽间距也整窗全隐', () {
      // tempoChangedGrid 的窗口内八拍大线候选间距 = 5500/700/1800ms，
      // µsPerPx=25000 → 屏距 220/28/72px：既有 ≥32px 也有 <32px。
      // 整窗一次判定取最小屏距 28px < 32 → 全部不标，杜绝「有的有、没有」。
      final result = labels(
        grid: tempoChangedGrid(),
        segments: [
          LearningSegment(
            order: 0,
            start: Duration.zero,
            end: const Duration(milliseconds: 9500),
          ),
        ],
        microsecondsPerPixel: 25000,
      );
      expect(result, isEmpty);
    });

    test('平移窗口不改变选中子集：同一候选内容下结果与窗口原点无关', () {
      // 不足 32px 的整窗全隐：两窗（起点 0 与右移 6s）均为 20px 间距
      // （minGap < 32）→ 结果都是全隐、彼此相等（无「窗口首候选恒放」）。
      final a = labels(microsecondsPerPixel: 200000);
      final b = labels(
        windowStart: const Duration(seconds: 6),
        windowEnd: const Duration(seconds: 44),
        microsecondsPerPixel: 200000,
      );
      expect(a, isEmpty);
      expect(b, isEmpty);
      expect(a, b);
      // 全显分支同样验证：宽间距（µsPerPx=10）窗口含同一候选集 {4,8,12}
      // 时，起点左移 1s（0→1）不改变全显的选中子集。
      final wideA = labels(
        rangeEnd: const Duration(seconds: 16),
        windowStart: Duration.zero,
        windowEnd: const Duration(seconds: 16),
      );
      final wideB = labels(
        rangeEnd: const Duration(seconds: 16),
        windowStart: const Duration(seconds: 1),
        windowEnd: const Duration(seconds: 16),
      );
      const expected = [
        BeatEightCountLabel(time: Duration(seconds: 4), count: 2),
        BeatEightCountLabel(time: Duration(seconds: 8), count: 3),
        BeatEightCountLabel(time: Duration(seconds: 12), count: 4),
      ];
      expect(wideA, expected);
      expect(wideB, expected);
    });
  });

  group('段内八拍数', () {
    // 与八拍数标注同一几何：0.5s 均匀拍点、每 4 拍一个 downbeat，
    // 八拍大线在 t = 0、4、8…s。
    DocumentBeatGrid uniformReadyGrid({
      double seconds = 40,
      List<int> anchors = const [],
    }) {
      final count = (seconds / 0.5).round() + 1;
      return documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          anchors: anchors,
          beats: [
            for (var i = 0; i < count; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
          ],
        ),
      );
    }

    /// 段内八拍数（0.5 分度加权值）；相位按生产路径由
    /// 「网格 + 锚点」求值（缺省锚点 = 空 = 今日相位）。
    double? countOf({
      BeatGrid? grid,
      required Duration start,
      required Duration end,
      List<int> anchors = const [],
    }) {
      final resolved = grid ?? uniformReadyGrid(anchors: anchors);
      return segmentEightBeatCount(
        grid: resolved,
        start: start,
        end: end,
        phase: BeatPhase(grid: resolved, anchors: anchors),
      );
    }

    test('就绪网格且段长整八拍：N = 段内完整八拍数', () {
      // t=0..16s = 32 拍 = 4 个八拍。
      expect(
        countOf(start: Duration.zero, end: const Duration(seconds: 16)),
        4,
      );
      // 相位不从首线起也对：t=4..16s = 3 个八拍。
      expect(
        countOf(
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 16),
        ),
        3,
      );
    });

    test('段首非八拍整点不显示', () {
      expect(
        countOf(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 16),
        ),
        isNull,
      );
    });

    test('段尾非八拍整点不显示', () {
      expect(
        countOf(start: Duration.zero, end: const Duration(seconds: 18)),
        isNull,
      );
    });

    test('段尾落在四拍中线（非八拍整点）不显示', () {
      // t=2s = 八拍区间内第 2 条 downbeat = 四拍中线，非八拍整点。
      expect(
        countOf(start: Duration.zero, end: const Duration(seconds: 2)),
        isNull,
      );
    });

    test('半八拍区间按 0.5 加权：段长 4 + 0.5 × 段内半八拍数', () {
      // 锚点第 12 拍（6s）：八拍点 = 0 / 8 / 12 / 20…s，故 [0, 10s] 内
      // 区间权重 = 1 + 0.5 + 1 = 2.5（半八拍不显示为整数）。
      expect(
        countOf(
          start: Duration.zero,
          end: const Duration(seconds: 10),
          anchors: const [12],
        ),
        2.5,
      );
      // 无锚点相位下 6s 非八拍点（4s/8s 才是）→ 不显示（门槛不放松）。
      expect(
        countOf(start: Duration.zero, end: const Duration(seconds: 6)),
        isNull,
      );
    });

    test('段内两个半八拍：权重 = 0.5 + 0.5 + 整八拍区间', () {
      // 锚点第 4、8 拍（2s、4s）：八拍点 = 0/2/4/8/12s，[0, 12s] 权重
      // = 0.5 + 0.5 + 1 + 1 = 3。
      expect(
        countOf(
          start: Duration.zero,
          end: const Duration(seconds: 12),
          anchors: const [4, 8],
        ),
        3,
      );
    });

    test('手动段同一加权口径：不要求凑够 4 个整八拍', () {
      // 长度 1.5 个八拍的手动段 [8s, 14s]（锚点 28：八拍点 8/14s）仍出值。
      expect(
        countOf(
          start: const Duration(seconds: 8),
          end: const Duration(seconds: 14),
          anchors: const [28],
        ),
        1.5,
      );
    });

    test('不等距强拍下权重仍量化到 0.5：不出现 1.125 式伪小数', () {
      // 强拍间隔 4/5 拍混排（down 在第 0/4/9/13/18/22/27 拍）：八拍点区间
      // 相隔 9 拍 → 权重量化到 1（未量化则是 1.125，会渲染成「3.4」）。
      final irregular = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 6),
          beats: [
            for (var i = 0; i < 40; i++)
              marker_doc.BeatPoint(
                t: i * 0.5,
                down: const {0, 4, 9, 13, 18, 22, 27, 31, 36}.contains(i),
              ),
          ],
        ),
      );
      final count = segmentEightBeatCount(
        grid: irregular,
        start: Duration.zero,
        end: const Duration(milliseconds: 13500), // 第 27 拍
        phase: BeatPhase(grid: irregular),
      );
      expect(count, 3, reason: '0 + 9×3 = 27：三个区间各量化到 1');
      expect(count! % 0.5, 0, reason: '权重恒为 0.5 的整数倍');
    });

    test('0.5 分度文案：整数不带小数位、半八拍保留一位', () {
      expect(formatEightBeatCount(4), '4');
      expect(formatEightBeatCount(2.5), '2.5');
      expect(formatEightBeatCount(0.5), '0.5');
    });

    test('网格非就绪（占位/异常）不显示', () {
      // 可用性由网格自陈——占位均匀网格真实拍点不可用。
      expect(
        countOf(
          grid: const UniformBeatGrid(),
          start: Duration.zero,
          end: const Duration(seconds: 16),
        ),
        isNull,
      );
    });

    test('无界网格（占位均匀实现）不显示', () {
      // 防御：真实拍点可用谓词不认无界实现（占位均匀网格），
      // 不得按占位网格派生出假 N。
      expect(
        countOf(
          grid: const UniformBeatGrid(),
          start: Duration.zero,
          end: const Duration(seconds: 16),
        ),
        isNull,
      );
    });
  });
  group('八拍锚点重定相', _anchorRephasingTierTests);
}

/// 八拍锚点重定相后的刻度分级：轨道三级刻度
/// 分级按锚点重定相——八拍大线随 [BeatPhase] 走，四拍中线 = 其余强拍。
void _anchorRephasingTierTests() {
  marker_doc.BeatGrid grid({int beats = 72}) => marker_doc.BeatGrid(
    model: 'm',
    fps: 100,
    generatedAt: DateTime.utc(2026, 9, 10),
    beats: [
      for (var i = 0; i < beats; i++)
        marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
    ],
  );

  Duration at(int beat) => Duration(milliseconds: beat * 500);

  test('锚点重定相：大线按锚点相位、四拍中线为其余强拍', () {
    final doc = grid();
    final derived = documentGridOf(doc);
    final phase = BeatPhase(grid: derived, anchors: const [28]);
    final ticks = beatTrackTicks(
      derived,
      Duration.zero,
      const Duration(seconds: 36),
      phase: phase,
    );

    BeatTickTier tierOf(int beat) =>
        ticks.firstWhere((tick) => tick.time == at(beat)).tier;

    // 自动相位下 0/8/16/24 是大线、28 是中线；落锚后 28 升级为大线，
    // 其后按新相位续：36/44 大线、32/40 中线。
    expect(tierOf(0), BeatTickTier.eightBar);
    expect(tierOf(8), BeatTickTier.eightBar);
    expect(tierOf(24), BeatTickTier.eightBar);
    expect(tierOf(28), BeatTickTier.eightBar, reason: '锚点自身即八拍点');
    expect(tierOf(36), BeatTickTier.eightBar);
    expect(tierOf(32), BeatTickTier.fourBar);
    expect(tierOf(40), BeatTickTier.fourBar);
  });

  test('段内八拍数与轨上大线同相位', () {
    final derived = documentGridOf(grid());
    // 锚点 14s（拍序号 28）：其后大线 = 14/18/22…s（半八拍起新相位）。
    final phase = BeatPhase(grid: derived, anchors: const [28]);
    // 段 [14s, 22s] 在锚点相位下首尾均为大线 → 计 2 个整八拍区间。
    expect(
      segmentEightBeatCount(
        grid: derived,
        start: const Duration(seconds: 14),
        end: const Duration(seconds: 22),
        phase: phase,
      ),
      2,
    );
    // 无锚点相位下该段首 14s 非大线（16s 才是）→ 不显示（null，与今日一致）。
    expect(
      segmentEightBeatCount(
        grid: derived,
        start: const Duration(seconds: 14),
        end: const Duration(seconds: 22),
        phase: BeatPhase(grid: derived),
      ),
      isNull,
    );
  });

  test('无锚点相位与大线集合回归基线逐位一致', () {
    final derived = documentGridOf(grid());
    final withPhase = beatTrackTicks(
      derived,
      Duration.zero,
      const Duration(seconds: 36),
      phase: BeatPhase(grid: derived),
    );
    final without = beatTrackTicks(
      derived,
      Duration.zero,
      const Duration(seconds: 36),
      // 此处按无锚点求值：显式构造无锚点相位（无锚点回归基线）。
      phase: BeatPhase(grid: derived),
    );

    expect(
      [for (final t in withPhase) (t.time, t.tier)],
      [for (final t in without) (t.time, t.tier)],
    );
    expect(
      [
        for (final t in without)
          if (t.tier == BeatTickTier.eightBar) t.time,
      ],
      BeatPhase(grid: derived)
          .pointsInWindow(Duration.zero, const Duration(seconds: 36)),
    );
  });
}
