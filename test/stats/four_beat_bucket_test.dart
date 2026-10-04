import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    show BeatPoint;
import 'package:dance_learning_app/persistence/four_beat_bucket_key.dart';
import 'package:dance_learning_app/stats/four_beat_bucket.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/document_grid_of.dart';
import '../helpers/uniform_test_grid.dart';

/// 四拍桶分摊纯件：桶键几何、墙钟分摊、扫过判据、断点与
/// 两类缺数据。零 Flutter 直测——输入采样序列，输出桶账。
void main() {
  // 每拍 500ms、每 4 拍一桶（2 秒一桶）；首拍即首个强拍。
  final grid = UniformTestGrid();

  final base = DateTime.parse('2026-09-05T20:00:00');
  late DateTime wall;
  late Duration media;
  late FourBeatBucketLedger ledger;
  late List<FourBeatBucketCredit> credits;

  setUp(() {
    wall = base;
    media = Duration.zero;
    ledger = FourBeatBucketLedger();
    credits = [];
  });

  /// 推进一个采样区间：[step] 媒介前进（默认 100ms ≈ 引擎采样步长），
  /// [wallStep] 墙钟前进（默认同媒介步长）。返回本次采样产出的桶账。
  List<FourBeatBucketCredit> tick({
    Duration step = const Duration(milliseconds: 100),
    Duration? wallStep,
    BeatGrid? useGrid,
  }) {
    media += step;
    wall = wall.add(wallStep ?? step);
    final out = ledger.addSample(
      wall: wall,
      mediaPosition: media,
      grid: useGrid ?? grid,
    );
    credits.addAll(out);
    return out;
  }

  /// 以 [step] 为步长把媒介位置推进到 [target]（不含已到位的情形）。
  void playTo(Duration target, {BeatGrid? useGrid}) {
    const step = Duration(milliseconds: 100);
    while (media < target) {
      final remaining = target - media;
      tick(step: remaining < step ? remaining : step, useGrid: useGrid);
    }
  }

  double wallOf(List<FourBeatBucketCredit> list, int bucket) => list
      .where((c) => c.bucket == bucket && c.sweeps == 0)
      .fold<double>(0.0, (sum, c) => sum + c.wallSeconds);

  int sweepsOf(List<FourBeatBucketCredit> list, int bucket) => list
      .where((c) => c.bucket == bucket)
      .fold<int>(0, (sum, c) => sum + c.sweeps);

  group('桶键几何', () {
    test('每 4 拍一桶，键随位置递增；首个强拍不落在拍 0 时对齐它', () {
      // 首个强拍 = 拍 2 → 桶 0 = 拍 2..5，桶 1 = 拍 6..9。
      final shifted = UniformTestGrid(firstDownbeatIndex: 2);
      expect(fourBeatBucketIndex(shifted, Duration.zero), 0); // 弱起归桶 0
      expect(fourBeatBucketIndex(shifted, const Duration(seconds: 1)), 0);
      expect(fourBeatBucketIndex(shifted, const Duration(seconds: 3)), 1);
      expect(fourBeatBucketIndex(shifted, const Duration(seconds: 4)), 1);
      expect(fourBeatBucketIndex(shifted, const Duration(seconds: 5)), 2);
    });

    test('桶右边界上的位置属于下一桶', () {
      // 拍 0 起每拍 0.5s：桶 0 = [0, 2s)，桶 1 = [2s, 4s)。
      expect(
        fourBeatBucketIndex(
          grid,
          const Duration(seconds: 1, milliseconds: 999),
        ),
        0,
      );
      expect(fourBeatBucketIndex(grid, const Duration(seconds: 2)), 1);
    });
  });

  group('连续推进记账', () {
    test('同一桶内推进只累加墙钟，不增扫过', () {
      tick(); // 首个采样只立基准
      final out = tick();
      expect(wallOf(out, 0), closeTo(0.1, 1e-9));
      expect(sweepsOf(credits, 0), 0);
    });

    test('越过右边界：该桶扫过 +1，dt 记在新桶', () {
      playTo(const Duration(seconds: 2)); // 到桶 1 的左边界
      expect(sweepsOf(credits, 0), 1);
      expect(wallOf(credits, 1), closeTo(0.1, 1e-9));
      expect(sweepsOf(credits, 1), 0);
      // 桶 0 的墙钟 = 1.8s（首个采样只立基准不计，末个采样已进桶 1）。
      expect(wallOf(credits, 0), closeTo(1.8, 1e-9));
    });

    test('倍速不折算：dt 一律墙钟', () {
      tick(step: const Duration(milliseconds: 100));
      final out = tick(
        step: const Duration(milliseconds: 100),
        wallStep: const Duration(milliseconds: 200),
      );
      expect(wallOf(out, 0), closeTo(0.2, 1e-9));
    });
  });

  group('断点', () {
    test('向前跳变：中间桶不补账、不增扫过；dt 仍记在新桶', () {
      playTo(const Duration(seconds: 1)); // 桶 0
      media = const Duration(seconds: 20); // 拖动到桶 10
      wall = wall.add(const Duration(milliseconds: 100));
      final out = ledger.addSample(
        wall: wall,
        mediaPosition: media,
        grid: grid,
      );
      expect(out, hasLength(1));
      expect(out.single.bucket, 10);
      expect(out.single.wallSeconds, closeTo(0.1, 1e-9));
      expect(out.single.sweeps, 0);
      expect(sweepsOf(out, 0), 0);
    });

    test('位置回退不补账；回退后重新推进照常累加', () {
      playTo(const Duration(seconds: 3)); // 桶 0、桶 1
      final before = sweepsOf(credits, 0);
      media = const Duration(seconds: 1); // 回退到桶 0
      wall = wall.add(const Duration(milliseconds: 100));
      final rewind = ledger.addSample(
        wall: wall,
        mediaPosition: media,
        grid: grid,
      );
      expect(rewind, isEmpty);
      playTo(const Duration(seconds: 2)); // 重新越过桶 0 右边界
      expect(sweepsOf(credits, 0), before + 1);
    });

    test('循环每圈重复累加：同一桶再次越过再 +1', () {
      playTo(const Duration(seconds: 2));
      expect(sweepsOf(credits, 0), 1);
      // 循环回跳（回退）→ 断点，第二圈再走一遍。
      media = const Duration(milliseconds: 100);
      wall = wall.add(const Duration(milliseconds: 100));
      ledger.addSample(wall: wall, mediaPosition: media, grid: grid);
      playTo(const Duration(seconds: 2));
      expect(sweepsOf(credits, 0), 2);
    });
  });

  group('两类缺数据', () {
    test('网格未就绪不产桶', () {
      playTo(const Duration(seconds: 3), useGrid: placeholderBeatGrid);
      expect(credits, isEmpty);
    });

    test('播放头没推进（位置事件缺口）不产桶', () {
      tick();
      final out = tick(
        step: Duration.zero,
        wallStep: const Duration(seconds: 3),
      );
      expect(out, isEmpty);
    });

    test('网格中途就绪：从当下开始产桶', () {
      playTo(const Duration(seconds: 1), useGrid: placeholderBeatGrid);
      expect(credits, isEmpty);
      tick(); // 就绪后首个采样立基准
      final out = tick();
      expect(out, isNotEmpty);
    });
  });

  group('跨零点', () {
    test('dt 按本地日拆开、桶序号不变', () {
      wall = DateTime.parse('2026-09-05T23:59:59');
      media = Duration.zero;
      ledger = FourBeatBucketLedger();
      ledger.addSample(wall: wall, mediaPosition: media, grid: grid);
      media = const Duration(milliseconds: 500);
      wall = DateTime.parse('2026-09-06T00:00:01');
      final out = ledger.addSample(
        wall: wall,
        mediaPosition: media,
        grid: grid,
      );
      expect(out, hasLength(2));
      expect(out[0].day, DateTime.parse('2026-09-05'));
      expect(out[0].wallSeconds, closeTo(1.0, 1e-9));
      expect(out[1].day, DateTime.parse('2026-09-06'));
      expect(out[1].wallSeconds, closeTo(1.0, 1e-9));
      expect(out.every((c) => c.bucket == 0), isTrue);
    });
  });

  group('桶键的倍频身份', () {
    test('原样键 = 裸整数十进制串；其余 = 倍频值 + 冒号 + 桶序号', () {
      expect(encodeFourBeatBucketKey(const FourBeatBucketKey(1, 5)), '5');
      expect(encodeFourBeatBucketKey(const FourBeatBucketKey(2, 17)), '2:17');
      expect(
        encodeFourBeatBucketKey(const FourBeatBucketKey(0.25, 0)),
        '0.25:0',
      );
    });

    test('解析与编码互逆；非桶键返回 null', () {
      expect(parseFourBeatBucketKey('5'), const FourBeatBucketKey(1, 5));
      expect(parseFourBeatBucketKey('2:17'), const FourBeatBucketKey(2, 17));
      expect(parseFourBeatBucketKey('0.5:3'), const FourBeatBucketKey(0.5, 3));
      expect(parseFourBeatBucketKey('abc'), isNull);
      expect(parseFourBeatBucketKey('3:x'), isNull);
      // 不在五档内的倍频值不是桶键（含历史裸负数）。
      expect(parseFourBeatBucketKey('9:1'), isNull);
      expect(parseFourBeatBucketKey('-3'), isNull);
    });
  });

  group('读取时投影', () {
    // 每拍 500ms、64 拍、首拍即首个强拍——与上方账本用例同一支曲子。
    final beats = [
      for (var i = 0; i < 64; i++) BeatPoint(t: 0.5 * i, down: i % 4 == 0),
    ];
    FourBeatBucketLines lines(double density) =>
        FourBeatBucketLines.of(beats: beats, shiftMs: 0, density: density);

    RecordedBucket rec(
      double density,
      int index, {
      double wallSeconds = 0,
      int sweeps = 0,
    }) => RecordedBucket(
      key: FourBeatBucketKey(density, index),
      wallSeconds: wallSeconds,
      sweeps: sweeps,
    );

    Map<int, ProjectedBucketValue> project(
      List<RecordedBucket> records, {
      double current = 1,
    }) {
      final days = projectFourBeatBuckets(
        days: {'2026-09-05': records},
        recordGridOf: lines,
        currentGrid: lines(current),
      );
      return days['2026-09-05']!;
    }

    test('原样记录投影到原样网格：桶与数值逐位不变', () {
      final out = project([
        rec(1, 5, wallSeconds: 10, sweeps: 3),
        rec(1, 2, wallSeconds: 4),
      ]);
      expect(out[5]!.wallSeconds, 10);
      expect(out[5]!.sweeps, 3);
      expect(out[2]!.wallSeconds, 4);
      expect(out[2]!.sweeps, 0);
    });

    test('细分（记录粗、当前细 ×2）：墙钟均分、扫过复制', () {
      final out = project([rec(1, 5, wallSeconds: 10, sweeps: 3)], current: 2);
      expect(out, hasLength(2));
      // 原桶 5 = [10s, 12s)，×2 网格四拍线每 1s 一根 → 子桶 10、11。
      expect(out[10]!.wallSeconds, 5);
      expect(out[10]!.sweeps, 3);
      expect(out[11]!.wallSeconds, 5);
      expect(out[11]!.sweeps, 3);
    });

    test('合并（记录细 ×2、当前原样）：墙钟求和、扫过取最小', () {
      final out = project([
        rec(2, 10, wallSeconds: 4, sweeps: 2),
        rec(2, 11, wallSeconds: 6, sweeps: 5),
      ]);
      expect(out, hasLength(1));
      expect(out[5]!.wallSeconds, 10);
      expect(out[5]!.sweeps, 2);
    });

    test('细分 ×¼ 档：秒守恒（子桶之和 = 原值）', () {
      final out = project([
        rec(0.25, 1, wallSeconds: 32, sweeps: 2),
      ], current: 1);
      // ×¼ 桶宽 = 8s：原桶 1 = [8s, 16s) → 当前桶 4..7，共 4 个子桶各 8s。
      expect(out, hasLength(4));
      final total = out.values.fold<double>(0, (sum, v) => sum + v.wallSeconds);
      expect(total, closeTo(32, 1e-9));
      expect(out.keys, [4, 5, 6, 7]);
      expect(out.values.every((v) => v.sweeps == 2), isTrue);
    });

    test('同一天混格不串：两种身份各自投影、落进当前桶格后合并', () {
      final out = project([
        rec(1, 5, wallSeconds: 10, sweeps: 3),
        rec(2, 10, wallSeconds: 4, sweeps: 2),
        rec(2, 11, wallSeconds: 6, sweeps: 5),
      ]);
      expect(out, hasLength(1));
      // 密度 1 与密度 2 的历史都指向同一段音乐（当前桶 5）。
      expect(out[5]!.wallSeconds, 20);
      // 扫过合并取最小，不因合并虚增。
      expect(out[5]!.sweeps, 2);
    });

    test('纯墙钟记录（扫过 0）合并不把次数记成 0', () {
      final out = project([
        rec(2, 10, wallSeconds: 4),
        rec(2, 11, wallSeconds: 6, sweeps: 5),
      ]);
      expect(out[5]!.sweeps, 5);
    });

    test('任意档位切换后仍落在同一段音乐上（×2 ↔ ×½ 往返）', () {
      // 同一段音乐（绝对时间 [10s, 12s)）记在 ×2 档两个细桶，投影到 ×½ 档。
      final out = project([
        rec(2, 10, wallSeconds: 4, sweeps: 2),
        rec(2, 11, wallSeconds: 4, sweeps: 2),
      ], current: 0.5);
      // ×½ 网格四拍线每 4s 一根：[10s,12s) 整段落在 ×½ 桶 2（[8s,12s)），
      // 秒求和守恒、次数合并不虚增。
      expect(out, hasLength(1));
      expect(out[2]!.wallSeconds, closeTo(8, 1e-9));
      expect(out[2]!.sweeps, 2);
    });
  });

  group('统计面不回归：段内档', () {
    // 与上方账本用例同一支曲子（500ms/拍、64 拍、首拍即强拍）。生产的
    // 统计网格源 = 整曲构造 `documentGridOf(doc)`（桶格恒取整曲档）
    // ——本组钉住它的字面桶账，并以「段内档显式进构造
    // 即偏移」的敏感性配对证明该字面口径是承重墙、不是恒真式。
    final doc = uniformDownbeatGridDoc(seconds: 32);
    final wholeSong = documentGridOf(doc);
    // 段序 0 = [2s, 4s) 带段内档 ×2 的网格（统计面**不得**收到它）。
    final segmentCarrying = documentGridOf(
      doc,
      segmentDensities: const {0: 2.0},
      segments: const [(startMs: 2000, endMs: 4000)],
    );

    test('桶键不变：整曲 ×2 档与段内档并存时桶格仍按整曲档算', () {
      // 整曲 ×2（文档档）+ 文档带段内档：桶格只由文档整曲档派生，
      // 桶键 = 既有整曲口径的字面值（×2 桶宽 1s）。
      final doubled = documentGridOf(doc.withDensity(2));
      expect(fourBeatBucketIndex(doubled, const Duration(seconds: 3)), 3);
      expect(fourBeatBucketIndex(doubled, const Duration(seconds: 9)), 9);
      expect(doubled.firstDownbeatIndex, 0);
    });

    test('桶明细不变：整曲构造的网格记账与既有口径逐位一致；逐段档混入即偏移', () {
      List<FourBeatBucketCredit> run(BeatGrid grid) {
        final ledger = FourBeatBucketLedger();
        var wall = DateTime.parse('2026-09-05T20:00:00');
        var media = Duration.zero;
        final credits = <FourBeatBucketCredit>[];
        while (media < const Duration(seconds: 5)) {
          media += const Duration(milliseconds: 100);
          wall = wall.add(const Duration(milliseconds: 100));
          credits.addAll(
            ledger.addSample(wall: wall, mediaPosition: media, grid: grid),
          );
        }
        return credits;
      }

      // 生产形状（整曲构造）的桶账 = 既有口径字面值：
      // 桶 0 = [0,2s) 1.8s + 1 次扫过，桶 1 = [2s,4s) 2.0s + 1 次，
      // 桶 2 = [4s,5s] 1.1s。
      final credits = run(wholeSong);
      expect(wallOf(credits, 0), closeTo(1.8, 1e-9));
      expect(sweepsOf(credits, 0), 1);
      expect(wallOf(credits, 1), closeTo(2.0, 1e-9));
      expect(sweepsOf(credits, 1), 1);
      expect(wallOf(credits, 2), closeTo(1.1, 1e-9));
      expect(sweepsOf(credits, 2), 0);

      // 敏感性配对：段内档一旦混进统计网格，段内桶键即偏移（桶键按整曲
      // 档应为 1，按段内 ×2 派生是 2）——本组上方的字面断言因此承重。
      expect(fourBeatBucketIndex(wholeSong, const Duration(seconds: 3)), 1);
      expect(
        fourBeatBucketIndex(segmentCarrying, const Duration(seconds: 3)),
        2,
      );
    });
  });
}
