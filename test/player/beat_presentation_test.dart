import 'package:dance_learning_app/core/current_beat.dart' show PracticeBeatCount;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/core/playback/media_clock.dart'
    show MediaClockSync;
import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/beat_presentation.dart';
import 'package:dance_learning_app/player/beat_schedule.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_beat_executor.dart';
import '../helpers/uniform_test_grid.dart';

/// 节拍呈现对象装配缝用例：注入 fake 执行器（[BeatScheduleConsumer] +
/// [BeatStreamControl] 同一 fake）与不可变上下文，驱动 onFrame 断言发布值
/// ——期望字面独立书写，不断言内部（水位/时钟/记账）。
void main() {
  final testGrid = UniformTestGrid(beatCount: 32);

  BeatPresentationContext context({
    BeatGrid? grid,
    List<Duration> halfBeatLines = const [],
    bool halfBeatEnabled = true,
    bool gridError = false,
    Duration? delayAnchor,
    Duration? activeAnchor,
    Duration firstLine = Duration.zero,
    bool playing = true,
    bool soundEnabled = true,
    MetronomeSourceEntry? source,
    Duration? sessionBeatInterval,
    bool sessionActive = false,
    double rate = 1,
    int avSyncDelayMs = 0,
  }) {
    return BeatPresentationContext(
      grid: grid ?? testGrid,
      phase: BeatPhase(grid: grid ?? testGrid),
      recordingAnchor: null,
      delayAnchor: delayAnchor,
      activeAnchor: activeAnchor,
      segmentLines: const [],
      firstLine: firstLine,
      source: source ?? metronomeSourceEntryOfId(kNormalSourceId),
      slotVolumeOf: (slot) => 1.0,
      halfBeatLines: halfBeatLines,
      halfBeatEnabled: halfBeatEnabled,
      avSyncDelayMs: avSyncDelayMs,
      rate: rate,
      playing: playing,
      soundEnabled: soundEnabled,
      gridError: gridError,
      sessionActive: sessionActive,
      sessionBeatInterval: sessionBeatInterval,
    );
  }

  late FakeBeatExecutor executor;
  late BeatPresentation presentation;

  setUp(() {
    executor = FakeBeatExecutor();
    presentation = BeatPresentation(
      streamControl: () => executor,
      consumer: () => executor,
    );
  });

  group('流生命周期与执行器 seam', () {
    test('attach 与 detach 各一次：开流、收流各恰一次，不产生重复产出', () async {
      await presentation.attach();
      await presentation.detach();
      expect(executor.openCount, 1);
      expect(executor.stopCount, 1);
      expect(executor.flushCount, 1);
      // 不产声：对象不向执行器排任何指令（声音仍由旧节拍声模块产出）。
      expect(executor.commands, isEmpty);
    });

    test('重复 attach 幂等：不重复开流', () async {
      await presentation.attach();
      await presentation.attach();
      expect(executor.openCount, 1);
    });

    test('未 attach 时 onFrame 不发布；detach 后不再发布', () async {
      final updates = <BeatPresentationValue?>[];
      presentation.currentBeat.addListener(
        () => updates.add(presentation.currentBeat.value),
      );
      presentation.onFrame(context(), Duration.zero);
      expect(presentation.currentBeat.value, isNull);
      await presentation.attach();
      presentation.onFrame(context(), Duration.zero);
      expect(presentation.currentBeat.value, isNotNull);
      await presentation.detach();
      presentation.onFrame(context(), const Duration(milliseconds: 500));
      // 值停在 detach 前的最后一次发布。
      expect(presentation.currentBeat.value!.beat.beatStart, Duration.zero);
      expect(updates.length, 1);
    });
  });

  group('发布值随位置与上下文变化', () {
    test('练习区顺数：0.5s 拍间隔下 0/0.5/1.5s 逐拍 1｜1、1｜2、1｜4', () async {
      await presentation.attach();
      BeatPresentationValue? valueAt(Duration position) {
        presentation.onFrame(context(), position);
        return presentation.currentBeat.value;
      }

      expect(valueAt(Duration.zero)!.beat.eightCount, 1);
      expect(valueAt(Duration.zero)!.beat.beatCount, 1);
      expect(valueAt(const Duration(milliseconds: 500))!.beat.beatCount, 2);
      expect(valueAt(const Duration(milliseconds: 1500))!.beat.beatCount, 4);
    });

    test('前导区：延迟锚前的位置发布 0｜x', () async {
      await presentation.attach();
      // 延迟锚 4s = 拍 8（八拍点）；位置 3.5s 距锚 1 拍 → 0｜8。
      presentation.onFrame(
        context(delayAnchor: const Duration(seconds: 4)),
        const Duration(milliseconds: 3500),
      );
      final value = presentation.currentBeat.value!;
      expect(value.beat.eightCount, 0);
      expect(value.beat.beatCount, 8);
    });

    test('无锚可数：位置早于首线发布空值，浮层不显示', () async {
      await presentation.attach();
      presentation.onFrame(
        context(firstLine: const Duration(seconds: 2)),
        const Duration(milliseconds: 500),
      );
      expect(presentation.currentBeat.value, isNull);
    });

    test('无锚可数：位置超出网格末拍发布空值', () async {
      await presentation.attach();
      // 末拍 = 31 × 0.5s = 15.5s；16s 超出网格末拍。
      presentation.onFrame(context(), const Duration(seconds: 16));
      expect(presentation.currentBeat.value, isNull);
    });

    test('暂停时发布值仍随位置更新（播放态为假不冻结发布）', () async {
      await presentation.attach();
      presentation.onFrame(context(playing: false), Duration.zero);
      expect(presentation.currentBeat.value!.beat.beatCount, 1);
      presentation.onFrame(context(playing: false), const Duration(seconds: 2));
      expect(presentation.currentBeat.value!.beat.beatCount, 5);
    });

    test('上下文变化自下一次 onFrame 生效：半拍开关改变发布值', () async {
      await presentation.attach();
      const halfLine = Duration(milliseconds: 250);
      presentation.onFrame(context(halfBeatLines: [halfLine]), Duration.zero);
      expect(presentation.currentBeat.value!.beat.halfBeatLines, [halfLine]);
      presentation.onFrame(
        context(halfBeatLines: [halfLine], halfBeatEnabled: false),
        Duration.zero,
      );
      expect(presentation.currentBeat.value!.beat.halfBeatLines, isEmpty);
    });

    test('网格异常标志：发布空值（秒制兜底不画假拍序）', () async {
      await presentation.attach();
      presentation.onFrame(context(gridError: true), Duration.zero);
      expect(presentation.currentBeat.value, isNull);
    });

    test('同一位置重复 onFrame 不重复通知（值不变不重发）', () async {
      await presentation.attach();
      var notifications = 0;
      presentation.currentBeat.addListener(() => notifications++);
      presentation.onFrame(context(), const Duration(milliseconds: 100));
      final afterFirst = notifications;
      presentation.onFrame(context(), const Duration(milliseconds: 100));
      expect(notifications, afterFirst);
    });

    test('发布值携带动画状态：窗口相位、强拍边界与半拍线投影', () async {
      await presentation.attach();
      const halfLine = Duration(milliseconds: 250);
      presentation.onFrame(context(halfBeatLines: [halfLine]), Duration.zero);
      final value = presentation.currentBeat.value!;
      // 0s = 拍 0（4/4 网格首个强拍）：窗口首拍 = 拍 0、当前格 0、拍内相位 0。
      expect(value.animation.beatInCycle, 0);
      expect(value.animation.beatFraction, 0);
      // 4/4：窗口内强拍边界竖线在第 4 格左边界。
      expect(value.strongBoundaryOffsets, [4]);
      // 半拍线 250ms 落在第 0 拍拍中。
      expect(value.halfBeatProjections.single.beatOffset, 0);
      expect(value.halfBeatProjections.single.beatFraction, closeTo(0.5, 1e-6));
      // 数拍数字显示 = 练习区两数（八拍号 1 起非前导）。
      expect(value.display, isA<PracticeBeatCount>());
    });
  });

  schedulingTests();
}


/// 发声排程装配缝用例：fake 执行器 + 可控单调钟，驱动位置流与周期 tick，
/// 断言「什么媒介位置产出了哪些（时刻 / 段 / 音量）」——期望字面独立
/// 书写（段 id 按注册表资产自算：「普通」去重段表重音=0、整拍=1、半拍=2），
/// 不断言水位 / 时钟 / 记账内部。
void schedulingTests() {
  final testGrid = UniformTestGrid(beatCount: 32);

  BeatPresentationContext context({
    BeatGrid? grid,
    List<Duration> halfBeatLines = const [],
    Duration? delayAnchor,
    bool gridError = false,
    bool playing = true,
    bool soundEnabled = true,
    MetronomeSourceEntry? source,
    bool sessionActive = false,
    Duration? sessionBeatInterval,
    double rate = 1,
    int avSyncDelayMs = 0,
  }) {
    return BeatPresentationContext(
      grid: grid ?? testGrid,
      phase: BeatPhase(grid: grid ?? testGrid),
      recordingAnchor: null,
      delayAnchor: delayAnchor,
      activeAnchor: null,
      segmentLines: const [],
      firstLine: Duration.zero,
      source: source ?? metronomeSourceEntryOfId(kNormalSourceId),
      slotVolumeOf: (slot) => 1.0,
      halfBeatLines: halfBeatLines,
      halfBeatEnabled: true,
      avSyncDelayMs: avSyncDelayMs,
      rate: rate,
      playing: playing,
      soundEnabled: soundEnabled,
      gridError: gridError,
      sessionActive: sessionActive,
      sessionBeatInterval: sessionBeatInterval,
    );
  }

  late FakeBeatExecutor executor;
  late BeatPresentation presentation;

  /// 一帧驱动：置钟 → onFrame（位置事件与周期 tick 同一条入口）→ 等推进
  /// 链排空。
  Future<void> frame(
    Duration position, {
    required int atMs,
    BeatPresentationContext? ctx,
  }) async {
    executor.nowMs = atMs;
    presentation.onFrame(ctx ?? context(), position);
    await presentation.settled;
  }

  /// 周期 tick 重放：同一位置按 30ms 步进推进钟（生产起表后的稳态驱动
  /// 形态）。
  Future<void> runTo(
    int atMs,
    Duration position, {
    BeatPresentationContext? ctx,
  }) async {
    while (executor.nowMs < atMs) {
      executor.nowMs += 30;
      presentation.onFrame(ctx ?? context(), position);
      await presentation.settled;
    }
  }

  List<int> commandMs() =>
      executor.commands.map((c) => c.beatMediaTime.inMilliseconds).toList();

  setUp(() {
    executor = FakeBeatExecutor();
    presentation = BeatPresentation(
      streamControl: () => executor,
      consumer: () => executor,
    );
  });

  test('位置前进：逐拍产出、一拍一声、无产出早于当时估计位置', () async {
    await presentation.attach();
    await frame(Duration.zero, atMs: 0);
    // 窗口 [0,150)：拍 0 产出（重音段 id 0）。
    expect(executor.commands, [
      const BeatScheduleCommand(
        beatMediaTime: Duration.zero,
        segmentId: 0,
        volume: 1.0,
      ),
    ]);
    await runTo(480, Duration.zero);
    // 稳态推进按外推预排：钟到 480 时窗 [480,630) 覆盖拍 500，产出一次。
    expect(commandMs(), [0, 500]);
    await frame(const Duration(milliseconds: 500), atMs: 500);
    // 位置事件落地：拍 500 已排，不重复产出（一拍一声）。
    expect(commandMs(), [0, 500]);
    expect(
      executor.commands.last.segmentId,
      1,
    ); // 1|2 → 整拍段（注册表资产自算）。
  });

  test('前跳越过已排区：被跳过的拍不补发', () async {
    await presentation.attach();
    await frame(Duration.zero, atMs: 0);
    await frame(const Duration(seconds: 3), atMs: 3000);
    // 0 与 3000 之间的拍（500..2500）不补发。
    expect(commandMs(), [0, 3000]);
  });

  test('段循环回跳（后跳越过前瞻窗）：清未消费、按新位置续排', () async {
    await presentation.attach();
    await frame(const Duration(seconds: 5), atMs: 5000);
    final flushBefore = executor.flushCount;
    await frame(const Duration(seconds: 2), atMs: 5000);
    expect(executor.flushCount, greaterThan(flushBefore));
    // 回跳清掉旧位置的未消费（首拍 5000 不重出），按新位置续排。
    expect(commandMs(), [5000, 2000]);
    await runTo(5500, const Duration(seconds: 2));
    // 回跳后拍声持续：2500 照常产出。
    expect(commandMs(), [5000, 2000, 2500]);
  });

  test('整片循环回跳后到达携带回跳前位置的陈旧报位：拍声仍持续产出', () async {
    await presentation.attach();
    await frame(const Duration(seconds: 5), atMs: 5000);
    await frame(const Duration(seconds: 2), atMs: 5000);
    // 陈旧报位（回跳前的 5s 位置）直接覆盖时钟：拍声不静默。
    await frame(const Duration(seconds: 5), atMs: 5050);
    expect(commandMs(), contains(5000));
    await runTo(5500, const Duration(seconds: 5));
    expect(commandMs(), contains(5500));
  });

  test('暂停即静音、恢复从停下的位置续排', () async {
    await presentation.attach();
    await frame(const Duration(milliseconds: 500), atMs: 500);
    expect(executor.commands.map((c) => c.beatMediaTime.inMilliseconds), [500]);
    await frame(
      const Duration(milliseconds: 500),
      atMs: 600,
      ctx: context(playing: false),
    );
    // 停沿：清未消费 + 停流；暂停期间周期 tick 无产出。
    expect(executor.stopCount, 1);
    final afterPause = commandMs().length;
    await runTo(
      1500,
      const Duration(milliseconds: 500),
      ctx: context(playing: false),
    );
    expect(executor.nowMs, greaterThanOrEqualTo(1500));
    expect(commandMs().length, afterPause);
    await frame(const Duration(milliseconds: 500), atMs: 2000);
    // 恢复：从停下的位置续排，500 上的拍重排一次（此前被清）。
    expect(commandMs(), [500, 500]);
    expect(executor.openCount, 2); // 停沿关流，恢复边沿重开。
  });

  test('暂停冻结外推：暂停期间钟走过位置不动', () async {
    await presentation.attach();
    await frame(
      const Duration(seconds: 1),
      atMs: 1000,
      ctx: context(playing: false),
    );
    await runTo(
      3000,
      const Duration(seconds: 1),
      ctx: context(playing: false),
    );
    // 位置冻结在 1s：1500..3000 的拍不因墙钟推进而产出。
    expect(commandMs(), isEmpty);
  });

  test('闸门矩阵：开声关、网格异常、音源不可用各只静默发声', () async {
    await presentation.attach();
    // 开声关：不应活 → 停流、无产出。
    await frame(
      Duration.zero,
      atMs: 0,
      ctx: context(soundEnabled: false),
    );
    expect(executor.stopCount, 1);
    expect(commandMs(), isEmpty);
    // 网格异常（秒制兜底）：不产指令；发布值已另行判空。
    await frame(Duration.zero, atMs: 0, ctx: context(gridError: true));
    expect(commandMs(), isEmpty);
    // 待支持音源：静默（流不因此停——应活判定不含音源可用性）。
    await frame(
      Duration.zero,
      atMs: 0,
      ctx: context(source: metronomeSourceEntryOfId('vocal')),
    );
    expect(commandMs(), isEmpty);
    expect(executor.stopCount, 1);
  });

  test('占位网格照响', () async {
    await presentation.attach();
    await frame(
      Duration.zero,
      atMs: 0,
      ctx: context(grid: placeholderBeatGrid),
    );
    expect(commandMs(), [0]);
  });

  test('换网格 / 换音源：旧上下文的未消费拍声被清掉、新上下文继续', () async {
    await presentation.attach();
    await frame(Duration.zero, atMs: 0);
    final flushBefore = executor.flushCount;
    // 网格换代（对象实例身份变化，含节拍对齐 / 倍频应用）。
    await frame(
      const Duration(milliseconds: 500),
      atMs: 500,
      ctx: context(grid: UniformTestGrid(beatCount: 32)),
    );
    expect(executor.flushCount, greaterThan(flushBefore));
    // 音源换代（含会话回落）：再清一次。
    final beforeSource = executor.flushCount;
    await frame(
      const Duration(seconds: 1),
      atMs: 1000,
      ctx: context(source: metronomeSourceEntryOfId('vocal')),
    );
    expect(executor.flushCount, greaterThan(beforeSource));
  });

  test('半拍：正式区窗内出半拍声，前导区不出', () async {
    await presentation.attach();
    const half = Duration(milliseconds: 250);
    final formalCtx = context(halfBeatLines: [half]);
    await frame(Duration.zero, atMs: 0, ctx: formalCtx);
    expect(commandMs(), [0]);
    await runTo(300, Duration.zero, ctx: formalCtx);
    // 拍 0 拍中的半拍 250ms 产出半拍段（id 2）。
    expect(commandMs(), [0, 250]);
    expect(executor.commands.last.segmentId, 2);
    // 前导区（延迟锚 4s 前）：3.5s 与其半拍 3.75s 无半拍产出。
    final leadingCtx = context(
      delayAnchor: const Duration(seconds: 4),
      halfBeatLines: [const Duration(milliseconds: 3750)],
    );
    await frame(const Duration(milliseconds: 3500), atMs: 3500, ctx: leadingCtx);
    expect(commandMs(), contains(3500)); // 前导整拍 0|8 照排。
    await runTo(3800, const Duration(milliseconds: 3500), ctx: leadingCtx);
    expect(commandMs(), isNot(contains(3750)));
  });

  test('倍速与音画同步 Δ：指令时刻 = 拍点 − Δ·rate', () async {
    await presentation.attach();
    final ctx = context(rate: 2, avSyncDelayMs: 50);
    await frame(Duration.zero, atMs: 0, ctx: ctx);
    // 拍 0 的指令时刻 0 − 100 < 0：早于估计位置，不响过去。
    expect(commandMs(), isEmpty);
    // 外推（rate 2）：est 越过 350 后窗覆盖拍 500 → 指令时刻 500 − 50×2 = 400。
    await runTo(200, Duration.zero, ctx: ctx);
    expect(commandMs(), [400]);
    expect(executor.commands.single.segmentId, 1);
  });

  test('流生命周期：失效探测后重开并按水位重排', () async {
    await presentation.attach();
    await frame(const Duration(milliseconds: 500), atMs: 500);
    expect(executor.openCount, 1);
    executor.lost = true;
    await frame(
      const Duration(milliseconds: 500),
      atMs: 530,
      ctx: context(),
    );
    // 失效探测到即重开。
    expect(executor.openCount, 2);
    // 重开后按水位重排：当下之后的拍照常产出。
    await runTo(1100, const Duration(milliseconds: 500));
    expect(commandMs(), contains(1000));
  });

  test('流生命周期：开流失败冷却重试，成功即恢复', () async {
    executor.failOpens = true;
    await presentation.attach();
    expect(executor.openCount, 0); // attach 开流失败。
    await frame(
      const Duration(milliseconds: 500),
      atMs: 500,
      ctx: context(playing: false, soundEnabled: false),
    );
    executor.failOpens = false;
    executor.nowMs = 500 + 1000; // 冷却已过。
    await frame(
      const Duration(milliseconds: 500),
      atMs: 1500,
      ctx: context(playing: true),
    );
    expect(executor.openCount, 1);
  });

  test('校准会话：滴答每 4 拍重音、无半拍、不受开声与播放态约束', () async {
    var pulses = 0;
    presentation = BeatPresentation(
      streamControl: () => executor,
      consumer: () => executor,
      onSessionBeat: () => pulses++,
    );
    await presentation.attach();
    final ctx = context(
      sessionActive: true,
      sessionBeatInterval: const Duration(milliseconds: 600),
      playing: false,
      soundEnabled: false,
    );
    await frame(Duration.zero, atMs: 0, ctx: ctx);
    // 会话拍 0：重音（k=0 → 拍号 1）。
    expect(commandMs(), [0]);
    expect(executor.commands.first.segmentId, 0);
    expect(pulses, 1);
    await runTo(2400, Duration.zero, ctx: ctx);
    // k=1..4 → 拍点 600/1200/1800/2400，k=4 为下一记重音。
    expect(commandMs(), [0, 600, 1200, 1800, 2400]);
    expect(
      executor.commands.map((c) => c.segmentId).toList(),
      [0, 1, 1, 1, 0],
    );
    expect(pulses, 5);
  });

  test('校准会话：档位变更自下一拍生效', () async {
    await presentation.attach();
    final sessionCtx = context(
      sessionActive: true,
      sessionBeatInterval: const Duration(milliseconds: 600),
    );
    await frame(Duration.zero, atMs: 0, ctx: sessionCtx);
    await runTo(600, Duration.zero, ctx: sessionCtx);
    expect(commandMs(), [0, 600]);
    // 换 300ms 档：已排拍之后下一拍按新档取点（900 = 300 的整倍数）。
    final fastCtx = context(
      sessionActive: true,
      sessionBeatInterval: const Duration(milliseconds: 300),
    );
    await runTo(900, Duration.zero, ctx: fastCtx);
    expect(commandMs(), contains(900));
    expect(commandMs(), isNot(contains(1200)));
  });

  test('观测：产出行携带四元组——媒体时刻、号、该拍求值用的锚、当时位置', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    await presentation.attach();
    const half = Duration(milliseconds: 250);
    await frame(Duration.zero, atMs: 0, ctx: context(halfBeatLines: [half]));
    await runTo(300, Duration.zero, ctx: context(halfBeatLines: [half]));
    final production = logs.where((l) => l.contains('产出')).toList();
    // 整拍 0ms：号 1｜1、锚 0ms、当时位置 0ms。
    expect(
      production.any(
        (l) =>
            l.contains('0ms') &&
            l.contains('号1｜1') &&
            l.contains('锚0ms') &&
            l.contains('位置0ms'),
      ),
      isTrue,
      reason: '$production',
    );
    // 半拍 250ms：号沿用所在拍的 1｜1，行内携带当时的估计位置（相邻产出
    // 间隔与网格拍距由此可读，排程错与输出延迟可分辨）。
    expect(
      production.any(
        (l) => l.contains('250ms') && l.contains('号1｜1') && l.contains('位置'),
      ),
      isTrue,
      reason: '$production',
    );
  });

  test('观测：正常播放全程不产生报警行', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    await presentation.attach();
    var position = Duration.zero;
    for (var step = 0; step < 8; step++) {
      await frame(position, atMs: position.inMilliseconds);
      position += const Duration(milliseconds: 500);
    }
    expect(logs.where((l) => l.contains('产出')), isNotEmpty);
    expect(logs.where((l) => l.contains('报警')), isEmpty, reason: '$logs');
  });

  test('观测：排程不变量断言——指令时刻早于当时估计位置即报警', () {
    expect(
      scheduleInvariantWarning(commandMs: 400, estMs: 500),
      contains('排程报警'),
    );
    expect(scheduleInvariantWarning(commandMs: 500, estMs: 500), isNull);
    expect(scheduleInvariantWarning(commandMs: 600, estMs: 500), isNull);
    // 负 Δ：拍点媒体时刻可以早于位置，但指令时刻（拍点 − Δ）不早——
    // 不变量比它真正要守的量，负 Δ 下不误报。
    expect(scheduleInvariantWarning(commandMs: 550, estMs: 500), isNull);
  });

  test('负 Δ：拍点早于估计位置照排，不产生排程报警行', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    await presentation.attach();
    // Δ = −500（嗒声推后 500ms）：拍点 0ms 的指令时刻 500 ≥ est 0，照排。
    final ctx = context(avSyncDelayMs: -500);
    await frame(Duration.zero, atMs: 0, ctx: ctx);
    await runTo(300, Duration.zero, ctx: ctx);
    expect(commandMs(), [500]);
    expect(logs.where((l) => l.contains('排程报警')), isEmpty, reason: '$logs');
  });

  test('正 Δ ≥ 前瞻窗：指令时刻前移不吃窗，媒体轴 / 半拍 / 会话轴逐拍照出', () async {
    /// 位置随单调钟同步推进走完 [toMs]，返回产出指令时刻。
    Future<List<int>> run({
      required int delta,
      double rate = 1,
      bool session = false,
      List<Duration> halfBeatLines = const [],
      int toMs = 3000,
    }) async {
      executor = FakeBeatExecutor();
      presentation = BeatPresentation(
        streamControl: () => executor,
        consumer: () => executor,
      );
      await presentation.attach();
      for (var now = 0; now <= toMs; now += 30) {
        await frame(
          Duration(milliseconds: now),
          atMs: now,
          ctx: context(
            avSyncDelayMs: delta,
            rate: rate,
            sessionActive: session,
            sessionBeatInterval: session
                ? const Duration(milliseconds: 600)
                : null,
            halfBeatLines: halfBeatLines,
          ),
        );
      }
      return commandMs();
    }

    /// 指令时刻落在运行区间 `[0, toMs]` 的拍点序列（指令时刻 = 拍点 − Δ·rate；
    /// 拍点因此可以比运行终点晚 Δ·rate）。
    List<int> expected({
      required int delta,
      double rate = 1,
      int step = 500,
      int toMs = 3000,
    }) {
      final shift = (delta * rate).round();
      return [
        for (var beat = 0; beat <= toMs + shift; beat += step)
          if (beat - shift >= 0) beat - shift,
      ];
    }

    // 整拍：Δ = 130 / 140（掉拍区）、150（与窗同宽）、600 / 1000（超窗）下，
    // 指令时刻落在运行区间内的网格拍全数各响一次。
    for (final delta in [130, 140, 150, 600, 1000]) {
      expect(
        await run(delta: delta),
        expected(delta: delta),
        reason: '媒体轴 Δ=$delta',
      );
    }
    // 倍速：Δ·rate = 300 ≥ 窗宽，拍点窗按同一条换算前移。
    expect(
      await run(delta: 150, rate: 2),
      expected(delta: 150, rate: 2),
      reason: '媒体轴 Δ=150 rate=2',
    );
    // 半拍与整拍按指令时间合并、单调输出：Δ = 150 时 250ms / 750ms 半拍线的
    // 指令 100ms / 600ms 与整拍指令交错成一条升序序列。
    expect(
      await run(
        delta: 150,
        halfBeatLines: const [
          Duration(milliseconds: 250),
          Duration(milliseconds: 750),
        ],
      ),
      [...expected(delta: 150), 100, 600]..sort(),
      reason: '半拍 Δ=150',
    );
    // 会话轴（校准滴答）同一条窗：Δ = 600 时 600ms 档逐拍照出。
    expect(
      await run(delta: 600, session: true),
      expected(delta: 600, step: 600),
      reason: '会话轴 Δ=600',
    );
  });

  test('播放中 Δ 变更：同一拍点不因新指令时刻重发（拍光标只进不退）', () async {
    /// 前 2000ms 用 [before]，其后用 [after]；返回产出行里的拍点媒介时刻。
    Future<List<int>> run({
      required int before,
      required int after,
      List<Duration> halfBeatLines = const [],
    }) async {
      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          logs.add(message ?? '');
      addTearDown(() => debugPrint = previous);
      executor = FakeBeatExecutor();
      presentation = BeatPresentation(
        streamControl: () => executor,
        consumer: () => executor,
      );
      await presentation.attach();
      for (var now = 0; now <= 3500; now += 30) {
        await frame(
          Duration(milliseconds: now),
          atMs: now,
          ctx: context(
            avSyncDelayMs: now < 2000 ? before : after,
            halfBeatLines: halfBeatLines,
          ),
        );
      }
      debugPrint = previous;
      return [
        for (final line in logs)
          if (RegExp(r'产出 (\d+)ms').firstMatch(line) case final match?)
            int.parse(match.group(1)!),
      ];
    }

    void expectSingleFire(List<int> beats, String label) {
      expect(beats, isNotEmpty, reason: '$label 无产出');
      expect(
        beats.toSet().length,
        beats.length,
        reason: '$label 出现重发：$beats',
      );
      expect(
        beats,
        orderedEquals([...beats]..sort()),
        reason: '$label 产出未按拍点单调：$beats',
      );
    }

    for (final (before, after) in [(600, 0), (0, 600), (1000, 0), (0, 1000)]) {
      expectSingleFire(
        await run(before: before, after: after),
        'Δ $before → $after',
      );
    }
    // 半拍线走同一条只进不退纪律（半拍线在切点附近，Δ 下降后其新指令时刻
    // 会把同一根线再扫进窗一次）。
    expectSingleFire(
      await run(
        before: 600,
        after: 0,
        halfBeatLines: const [
          Duration(milliseconds: 2250),
          Duration(milliseconds: 2750),
        ],
      ),
      '半拍 Δ 600 → 0',
    );
  });

  test('排程不变量：相邻产出间隔等于网格相邻拍点间隔', () async {
    await presentation.attach();
    var position = Duration.zero;
    for (var step = 0; step < 10; step++) {
      await frame(position, atMs: position.inMilliseconds);
      position += const Duration(milliseconds: 500);
    }
    final times = commandMs();
    expect(times.length, greaterThan(2));
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], 500);
    }
  });

  test('观测：会话轴产出行同带四元组（号与锚走同一条求值）', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    await presentation.attach();
    await frame(
      Duration.zero,
      atMs: 0,
      ctx: context(
        sessionActive: true,
        sessionBeatInterval: const Duration(milliseconds: 600),
      ),
    );
    expect(
      logs.any(
        (l) =>
            l.contains('产出 0ms') &&
            l.contains('号1｜1') &&
            l.contains('锚0ms') &&
            l.contains('位置0ms'),
      ),
      isTrue,
      reason: '$logs',
    );
  });

  test('校准会话与正式数拍同一条求值：八拍号顺数、重音落小节首（600ms 档）', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = previous);
    var pulses = 0;
    presentation = BeatPresentation(
      streamControl: () => executor,
      consumer: () => executor,
      onSessionBeat: () => pulses++,
    );
    await presentation.attach();
    final ctx = context(
      sessionActive: true,
      sessionBeatInterval: const Duration(milliseconds: 600),
      playing: false,
      soundEnabled: false,
    );
    await frame(Duration.zero, atMs: 0, ctx: ctx);
    await runTo(9600, Duration.zero, ctx: ctx);
    // 拍点 = 档间隔整倍数；第 8 拍（4800ms，k=8）起八拍号进 2——号与锚
    // 由与正式播放同一条 evaluateCurrentBeat 求出，不再有 1｜x 退化轴。
    expect(commandMs(), [for (var t = 0; t <= 9600; t += 600) t]);
    for (final l in logs.where((l) => l.contains('产出'))) {
      final ms = int.parse(RegExp(r'产出 (\d+)ms').firstMatch(l)!.group(1)!);
      final eight = ms ~/ 4800 + 1;
      final beat = (ms ~/ 600) % 8 + 1;
      expect(l, contains('号$eight｜$beat'), reason: l);
      expect(l, contains('锚0ms'), reason: l);
    }
    // 重音 = 小节首拍（k % 4 == 0），选段与正式播放同一套（「普通」音源
    // 重音段 0、整拍段 1）。
    expect(
      executor.commands.map((c) => c.segmentId).toList(),
      [for (var k = 0; k <= 16; k++) k % 4 == 0 ? 0 : 1],
    );
    expect(pulses, 17);
  });

  test('同源对表：产出段 id 与纯求值在同拍给出的选段逐拍一致', () async {
    await presentation.attach();
    var position = Duration.zero;
    for (var step = 0; step < 12; step++) {
      await frame(position, atMs: position.inMilliseconds);
      position += const Duration(milliseconds: 500);
    }
    // 产出时刻即拍点（Δ=0、rate=1）：每条整拍指令的段 id = 该拍位置独立
    // 求出的拍号选段（「普通」音源：号 1/5 重音段 0，其余整拍段 1）。
    for (final command in executor.commands) {
      final t = command.beatMediaTime;
      expect(t.inMilliseconds % 500, 0, reason: '$t 非拍点');
      final beatCount = (t.inMilliseconds ~/ 500) % 8 + 1;
      final strong = beatCount == 1 || beatCount == 5;
      expect(command.segmentId, strong ? 0 : 1, reason: '$t');
    }
    // 排程不变量：相邻产出间隔 = 网格拍距。
    final times = commandMs();
    for (var i = 1; i < times.length; i++) {
      expect(times[i] - times[i - 1], 500);
    }
  });

  // 单一时基：呈现的外推是全仓唯一的「现在」，它
  // 同时回答「排哪一拍」与「告诉原生锚在哪」——下推原生的是取自同一份
  // 外推的配对（媒介时刻 + 倍速 + 播放态）。
  group('单一时基：配对下推取自呈现的唯一外推', () {
    late _RecordingTimebase timebase;
    late BeatPresentation withTimebase;

    setUp(() {
      timebase = _RecordingTimebase();
      withTimebase = BeatPresentation(
        streamControl: () => executor,
        consumer: () => executor,
        timebase: () => timebase,
      );
    });

    test('下推的媒介时刻 = 报位锚 + 单调钟 × 倍速的外推；倍速随同一份上下文', () async {
      await withTimebase.attach();
      executor.nowMs = 1000;
      withTimebase.onFrame(context(rate: 2), const Duration(seconds: 5));
      await withTimebase.settled;

      // 锚 (5s @ 1000ms)、2× 外推 500ms 墙钟 → 6000ms。同位置重放不重立锚，
      // 外推进度保留——配对值就是呈现热路径排程用的那个 est。
      executor.nowMs = 1500;
      withTimebase.onFrame(context(rate: 2), const Duration(seconds: 5));
      await withTimebase.settled;

      expect(timebase.syncs.last.mediaTimeMs, 6000);
      expect(timebase.syncs.last.rate, 2.0);
      expect(timebase.syncs.last.playing, isTrue);
    });

    test('向后报位后配对跟随呈现外推（无条件采纳），不是第二份拒绝向后的估计', () async {
      await withTimebase.attach();
      executor.nowMs = 1000;
      withTimebase.onFrame(context(), const Duration(seconds: 5));
      await withTimebase.settled;

      executor.nowMs = 1500;
      withTimebase.onFrame(context(), const Duration(seconds: 3));
      await withTimebase.settled;

      // 呈现时钟已把锚采纳到 3s：此后唯一的外推答 3000ms（拒绝向后的
      // 第二份时钟会答 ≥5000ms——配对值证明它已不在同步路径上）。
      expect(timebase.syncs.last.mediaTimeMs, 3000);
      expect(executor.flushCount, greaterThan(0),
          reason: '向后跳变由水位判定清账，纪律不再由第二份时钟承担');
    });

    test('暂停：外推冻结在最近报位（不把暂停时长外推进位置）', () async {
      await withTimebase.attach();
      executor.nowMs = 1000;
      withTimebase.onFrame(context(playing: false), const Duration(seconds: 5));
      await withTimebase.settled;

      executor.nowMs = 3000;
      withTimebase.onFrame(context(playing: false), const Duration(seconds: 5));
      await withTimebase.settled;

      expect(timebase.syncs.last.mediaTimeMs, 5000);
      expect(timebase.syncs.last.playing, isFalse);
    });

    test('校准会话期间不下推媒体轴（会话锚由渲染器经会话边沿自理）', () async {
      await withTimebase.attach();
      executor.nowMs = 1000;
      withTimebase.onFrame(
        context(sessionActive: true, sessionBeatInterval: const Duration(milliseconds: 500)),
        Duration.zero,
      );
      await withTimebase.settled;

      expect(timebase.sessionEdges, [true]);
      expect(timebase.syncs, isEmpty);
    });
  });
}

/// 时基 seam fake：记录呈现下推的媒介时刻配对与会话
/// 边沿，断言「排哪一拍」与「告诉原生锚在哪」读同一个「现在」。
class _RecordingTimebase implements BeatAudioRendererLifecycle {
  final syncs = <MediaClockSync>[];
  final sessionEdges = <bool>[];

  @override
  void onMediaNow(MediaClockSync sync) => syncs.add(sync);

  @override
  Future<void> onCalibrationSession(bool active) async {
    sessionEdges.add(active);
  }
}
