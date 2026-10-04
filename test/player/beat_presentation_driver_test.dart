import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/half_beat_line.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/player/beat_presentation.dart';
import 'package:dance_learning_app/player/calibration_session_grid.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';
import '../helpers/fake_beat_executor.dart';
import '../helpers/uniform_test_grid.dart';

/// 节拍呈现宿主交权后的装配缝用例：驱动只收
/// 显式读取闭包——素材（[BeatPresentationFacts]）、引擎活输入（倍速/播放
/// 态）与位置原始报位；上下文装配规则与重驱编排都在模块内。断言只读驱动
/// 的可观察后果（发布值、产出槽位、流生命周期），不读内部记账。
void main() {
  final testGrid = UniformTestGrid(beatCount: 32);

  BeatPresentationFacts facts({
    BeatGrid? grid,
    BeatPhase? phase,
    AnnotationTimeline? timeline,
    Duration? recordingAnchor,
    Duration? delayAnchor,
    Duration? activeLoopStart,
    String sourceId = kNormalSourceId,
    double Function(MetronomeSegmentSlot slot)? slotVolumeOf,
    bool halfBeatEnabled = true,
    bool soundEnabled = true,
    int avSyncDelayMs = 0,
    bool sessionActive = false,
    CalibrationSessionBpmTier sessionTier = CalibrationSessionBpmTier.song,
    int sessionTrialMs = 0,
  }) {
    final resolvedGrid = grid ?? testGrid;
    return BeatPresentationFacts(
      grid: resolvedGrid,
      phase: phase ?? BeatPhase(grid: resolvedGrid),
      timeline:
          timeline ??
          AnnotationTimeline.normalized(
            videoDuration: const Duration(minutes: 1),
          ),
      recordingAnchor: recordingAnchor,
      delayAnchor: delayAnchor,
      activeLoopStart: activeLoopStart,
      sourceId: sourceId,
      slotVolumeOf: slotVolumeOf ?? (slot) => 1.0,
      halfBeatEnabled: halfBeatEnabled,
      soundEnabled: soundEnabled,
      avSyncDelayMs: avSyncDelayMs,
      sessionActive: sessionActive,
      sessionTier: sessionTier,
      sessionTrialMs: sessionTrialMs,
    );
  }

  group('上下文装配（宿主交权：解析规则归模块）', () {
    test('分段线、首线与半拍线由时间线投影而来', () {
      final timeline = AnnotationTimeline.normalized(
        videoDuration: const Duration(seconds: 30),
        rangeStart: const Duration(seconds: 2),
        rangeEnd: const Duration(seconds: 28),
        segmentLines: const [
          SegmentLine(position: Duration(seconds: 10)),
          SegmentLine(position: Duration(seconds: 20)),
        ],
        halfBeatLines: const [
          HalfBeatLine(position: Duration(milliseconds: 2500)),
        ],
      );

      final context = assembleBeatPresentationContext(
        facts(timeline: timeline),
        rate: 1,
        playing: true,
      );

      expect(context.firstLine, const Duration(seconds: 2));
      expect(context.segmentLines, const [
        Duration(seconds: 10),
        Duration(seconds: 20),
      ]);
      expect(context.halfBeatLines, const [Duration(milliseconds: 2500)]);
      expect(context.halfBeatEnabled, isTrue);
    });

    test('校准会话活跃取会话试听 Δ，非会话取设置 Δ', () {
      final active = assembleBeatPresentationContext(
        facts(avSyncDelayMs: 40, sessionActive: true, sessionTrialMs: 120),
        rate: 1,
        playing: true,
      );
      expect(active.avSyncDelayMs, 120);

      final idle = assembleBeatPresentationContext(
        facts(avSyncDelayMs: 40, sessionTrialMs: 120),
        rate: 1,
        playing: true,
      );
      expect(idle.avSyncDelayMs, 40);
    });

    test('会话拍间隔按档派生：歌曲档取网格拍距，120/160 按固定 BPM', () {
      Duration? intervalOf(CalibrationSessionBpmTier tier) =>
          assembleBeatPresentationContext(
            facts(sessionActive: true, sessionTier: tier),
            rate: 1,
            playing: true,
          ).sessionBeatInterval;

      expect(intervalOf(CalibrationSessionBpmTier.song), testGrid.beatTime(1));
      expect(
        intervalOf(CalibrationSessionBpmTier.bpm120),
        const Duration(milliseconds: 500),
      );
      expect(
        intervalOf(CalibrationSessionBpmTier.bpm160),
        const Duration(milliseconds: 375),
      );
    });

    test('网格异常标志 = 秒制兜底（不画假拍序）', () {
      final fallback = assembleBeatPresentationContext(
        facts(grid: const UnavailableBeatGrid()),
        rate: 1,
        playing: true,
      );
      expect(fallback.gridError, isTrue);
      expect(
        assembleBeatPresentationContext(
          facts(),
          rate: 1,
          playing: true,
        ).gridError,
        isFalse,
      );
    });

    test('播放态与倍速取调用方给出的引擎事实', () {
      final paused = assembleBeatPresentationContext(
        facts(),
        rate: 1.5,
        playing: false,
      );
      expect(paused.rate, 1.5);
      expect(paused.playing, isFalse);
    });

    test('生效音源项与按槽音量取自素材', () {
      final context = assembleBeatPresentationContext(
        facts(sourceId: 'vocal', slotVolumeOf: (slot) => slot.index + 0.5),
        rate: 1,
        playing: true,
      );
      expect(context.source.id, 'vocal');
      expect(context.slotVolumeOf(MetronomeSegmentSlot.count1), 0.5);
    });
  });

  group('驱动（素材/位置/前后台 → 重驱）', () {
    late FakeBeatExecutor executor;
    late BeatPresentation presentation;
    late BeatPresentationDriver driver;

    setUp(() {
      executor = FakeBeatExecutor();
      presentation = BeatPresentation(
        streamControl: () => executor,
        consumer: () => executor,
      );
    });

    BeatPresentationDriver connect({
      required BeatPresentationFacts Function() readFacts,
      Duration? Function()? readPosition,
      double rate = 1,
      bool enginePlaying = true,
    }) {
      return BeatPresentationDriver(
        presentation: presentation,
        readFacts: readFacts,
        readTransport: () => (rate: rate, playing: enginePlaying),
        readPosition: readPosition ?? () => Duration.zero,
      );
    }

    /// 一次重驱并等推进链排空（位置事件与周期 tick 同走 onFrame）。
    Future<void> drive() async {
      driver.resync();
      await Future<void>.delayed(Duration.zero);
      await presentation.settled;
    }

    test('素材装配的上下文经位置报位驱动 onFrame：位置未就绪不驱动', () async {
      await presentation.attach();
      Duration? position;
      driver = connect(readFacts: facts, readPosition: () => position);
      await drive();
      expect(presentation.currentBeat.value, isNull, reason: '位置未就绪不驱动');

      position = Duration.zero;
      await drive();
      expect(presentation.currentBeat.value!.beat.eightCount, 1);
      expect(presentation.currentBeat.value!.beat.beatCount, 1);
    });

    test('素材变化自下一次重驱生效（驱动每帧现读素材）', () async {
      await presentation.attach();
      const half = Duration(milliseconds: 250);
      var halfBeatEnabled = true;
      driver = connect(
        readFacts: () => facts(
          timeline: AnnotationTimeline.normalized(
            videoDuration: const Duration(seconds: 30),
            halfBeatLines: const [HalfBeatLine(position: half)],
          ),
          halfBeatEnabled: halfBeatEnabled,
        ),
      );
      await drive();
      expect(presentation.currentBeat.value!.beat.halfBeatLines, [half]);

      halfBeatEnabled = false;
      await drive();
      expect(presentation.currentBeat.value!.beat.halfBeatLines, isEmpty);
    });

    test('退后台：播放态合成为假、节拍声不应活停流；回前台按引擎真实播放态恢复', () async {
      executor.nowMs = 0;
      await presentation.attach();
      driver = connect(readFacts: facts);
      await drive();
      expect(executor.commands, isNotEmpty, reason: '前台播放中应产出');

      driver.setAppPaused(true);
      await drive();
      expect(executor.stopCount, 1, reason: '退后台 = 不应活停流');

      final before = executor.commands.length;
      executor.nowMs = 1000;
      await drive();
      expect(executor.commands.length, before, reason: '退后台期间不产出');

      driver.setAppPaused(false);
      await drive();
      expect(executor.commands.length, greaterThan(before), reason: '回前台恢复产出');
    });

    test('收尾后不再驱动（微任务在途也丢弃）', () async {
      await presentation.attach();
      driver = connect(readFacts: facts);
      driver.resync();
      driver.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(presentation.currentBeat.value, isNull);
    });
  });

  group('素材换代驱动产出（相位锚／数拍锚／生效音源进模块装配）', () {
    // 不规则强拍网格：拍点每 0.5s 一拍（30s，61 拍），强拍间隔 4、3 交替
    // （强拍序号 0,4,7,11,14,…）——八拍点 = 每隔一个强拍（0,7,14,…）。
    marker_doc.BeatGrid irregularGrid() => marker_doc.BeatGrid(
      model: 'fake.onnx',
      fps: 100,
      generatedAt: DateTime.utc(2024),
      beats: [
        for (var i = 0; i <= 60; i++)
          marker_doc.BeatPoint(
            t: i * 0.5,
            down: i == 0 || i % 7 == 4 || (i % 7 == 0 && i >= 7),
          ),
      ],
    );

    late FakeBeatExecutor executor;
    late BeatPresentation presentation;

    setUp(() {
      executor = FakeBeatExecutor();
      presentation = BeatPresentation(
        streamControl: () => executor,
        consumer: () => executor,
      );
    });

    /// 给定素材与位置，从当下按周期 tick 推进 [span]，返回 [from, to] 闭窗
    /// 内的产出槽位（稳态驱动形态：位置报位 + 30ms 周期 tick 同走一条入口）。
    Future<List<String>> slotsAt(
      BeatPresentationFacts Function() readFacts,
      Duration position, {
      required Duration from,
      required Duration to,
      Duration span = const Duration(milliseconds: 1200),
    }) async {
      await presentation.attach();
      executor.commands.clear();
      final driver = BeatPresentationDriver(
        presentation: presentation,
        readFacts: readFacts,
        readTransport: () => (rate: 1, playing: true),
        readPosition: () => position,
      );
      final until = position.inMilliseconds + span.inMilliseconds;
      executor.nowMs = position.inMilliseconds;
      while (executor.nowMs <= until) {
        driver.resync();
        await Future<void>.delayed(Duration.zero);
        await presentation.settled;
        executor.nowMs += 30;
      }
      driver.dispose();
      await presentation.detach();
      return [
        for (final command in executor.commands)
          if (!command.beatMediaTime.isNegative &&
              command.beatMediaTime >= from &&
              command.beatMediaTime <= to)
            '${command.beatMediaTime.inMilliseconds}:${command.segmentId}',
      ];
    }

    test('落八拍锚点：产出槽位按新相位重建（屏幕与声音同一条派生）', () async {
      final grid = documentGridOf(irregularGrid());
      // 基线（无锚点）：拍 3（1.5s）非重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
          ),
          const Duration(milliseconds: 1200),
          from: const Duration(seconds: 1),
          to: const Duration(seconds: 2),
          // 原整页用例只推 600ms：窗口止于拍 4 之前（拍 4 属下一窗）。
          span: const Duration(milliseconds: 600),
        ),
        ['1500:1'],
      );

      // 落锚点（强拍 4 = 2.0s）：大线重定相，拍 8（4.0s）变重音、拍 9 非重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid, anchors: const [4]),
          ),
          const Duration(milliseconds: 3200),
          from: const Duration(seconds: 4),
          to: const Duration(milliseconds: 4500),
        ),
        ['4000:0', '4500:1'],
      );

      // 删锚还原基线口径：拍 14（7.0s）回重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
          ),
          const Duration(milliseconds: 6200),
          from: const Duration(seconds: 7),
          to: const Duration(seconds: 7),
        ),
        ['7000:0'],
      );
    });

    test('数拍锚（延迟锚 / 起录锚）变化：预备区按 0|x 取样', () async {
      final grid = documentGridOf(irregularGrid());

      // 基线：拍 4（2.0s）重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
          ),
          const Duration(milliseconds: 1200),
          from: const Duration(seconds: 2),
          to: const Duration(seconds: 2),
        ),
        ['2000:0'],
      );

      // 延迟锚 6.0s（对齐大线 7.0s）：位置在锚前 = 预备区，拍 6（3.0s）
      // 由非重音变 0|1 重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
            delayAnchor: const Duration(seconds: 6),
          ),
          const Duration(milliseconds: 2200),
          from: const Duration(seconds: 3),
          to: const Duration(seconds: 3),
        ),
        ['3000:0'],
      );

      // 起录锚 8.0s（对齐大线 10.5s）：拍 8（4.0s）同样落预备区重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
            recordingAnchor: const Duration(seconds: 8),
          ),
          const Duration(milliseconds: 3200),
          from: const Duration(seconds: 4),
          to: const Duration(seconds: 4),
        ),
        ['4000:0'],
      );

      // 锚复位：拍 12（6.0s）回基线非重音。
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
          ),
          const Duration(milliseconds: 5200),
          from: const Duration(seconds: 6),
          to: const Duration(seconds: 6),
        ),
        ['6000:1'],
      );
    });

    test('生效音源切换：待支持音源静默、普通音源照响', () async {
      final grid = documentGridOf(irregularGrid());
      const from = Duration(seconds: 1);
      const to = Duration(seconds: 2);
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
            sourceId: 'vocal',
          ),
          const Duration(milliseconds: 1200),
          from: from,
          to: to,
          span: const Duration(milliseconds: 600),
        ),
        isEmpty,
      );
      expect(
        await slotsAt(
          () => facts(
            grid: grid,
            phase: BeatPhase(grid: grid),
          ),
          const Duration(milliseconds: 1200),
          from: from,
          to: to,
          span: const Duration(milliseconds: 600),
        ),
        ['1500:1'],
      );
    });
  });
}
