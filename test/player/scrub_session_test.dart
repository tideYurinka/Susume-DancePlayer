import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/scrub_session.dart';
import 'package:dance_learning_app/core/playback/seek_submitter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// ScrubSession 模块面测试：FakeEngine callLog 直接驱动
/// begin/moveBy/end，断言核心不变量——pause 先于首次 seek、begin/end 幂等、
/// begin 无效场景（时长未知）返回 false 且静默、moveBy 在基准未定时丢弃、
/// 累计 + 钳制、end 恢复守卫（wasPlaying && 界内才 play）、cancel 回退单发
/// 再续播、cancelZoneEnabled=false 时 cancel 无害、player/blank 差分经参数
/// 化（cancelZoneEnabled / resumeRange / feedback / indicator 组合）覆盖。
void main() {
  late FakePlaybackEngine engine;
  late List<Duration> seeks;
  late ValueNotifier<Duration> indicator;
  late GestureFeedbackController feedback;

  ScrubSession build({
    Duration? Function()? total,
    bool Function()? isPlayingOverride,
    bool Function(Duration target)? resumeRange,
    bool cancelZoneEnabled = false,
    bool requireKnownDuration = true,
    GestureFeedbackController? feedbackOverride,
    ValueNotifier<Duration>? indicatorOverride,
    SeekSubmitter? seekOverride,
  }) {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 10));
    seeks = <Duration>[];
    indicator = indicatorOverride ?? ValueNotifier(Duration.zero);
    feedback = feedbackOverride ?? GestureFeedbackController();
    final seek = seekOverride ??
        SeekSubmitter(
          engineSeek: (t) {
            seeks.add(t);
            return engine.seek(t);
          },
          total: total ?? () => engine.duration,
          timeline: () => AnnotationTimeline.wholeVideo(
            engine.duration ?? Duration.zero,
          ),
          clearLoops: (_, _) {},
        );
    return ScrubSession(
      seek: seek,
      pause: engine.pause,
      play: engine.play,
      isPlaying: isPlayingOverride ?? () => engine.isPlaying,
      position: () => engine.position,
      resumeRange: resumeRange,
      feedback: feedback,
      indicator: indicator,
      cancelZoneEnabled: cancelZoneEnabled,
      requireKnownDuration: requireKnownDuration,
    );
  }

  group('begin（幂等；pause 先于任何 seek）', () {
    test('在播 begin：先 pause 再可 seek（callLog 序），基准 = 定格点快照',
        () async {
      final s = build();
      await engine.play();
      await engine.seek(const Duration(seconds: 5));
      engine.callLog.clear();
      engine.seekCalls.clear();

      expect(await s.begin(), isTrue);
      expect(s.isActive, isTrue);
      expect(engine.isPlaying, isFalse, reason: '在播起手即暂停定格');
      expect(indicator.value, const Duration(seconds: 5),
          reason: 'indicator = 基准快照');

      s.moveBy(const Duration(seconds: 1));
      await pumpEventQueue();
      final pauseIdx = engine.callLog.indexOf('pause');
      final firstSeek = engine.callLog.indexOf('seek');
      expect(pauseIdx, greaterThanOrEqualTo(0));
      expect(firstSeek, greaterThan(pauseIdx), reason: 'pause 须先于首次 seek');
      expect(seeks.single, const Duration(seconds: 6));
    });

    test('暂停态 begin：不 pause、基准 = 当前位置', () async {
      final s = build();
      await engine.seek(const Duration(seconds: 2));
      engine.callLog.clear();

      expect(await s.begin(), isTrue);
      expect(engine.callLog, isNot(contains('pause')));
      expect(indicator.value, const Duration(seconds: 2));
      expect(feedback.isScrubbing, isTrue);
    });

    test('begin 幂等：active 期间重复 begin 不重复暂停、不重置基准', () async {
      final s = build();
      await engine.play();
      await engine.seek(const Duration(seconds: 5));
      engine.callLog.clear();

      expect(await s.begin(), isTrue);
      s.moveBy(const Duration(seconds: 1));
      expect(await s.begin(), isTrue, reason: '幂等返回 true');
      expect(engine.callLog.where((c) => c == 'pause'), hasLength(1));
      s.moveBy(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(seeks.last, const Duration(seconds: 7),
          reason: '基准未被重置：累计仍基于同一快照');
    });

    test('时长未知：begin 返回 false 且静默（无相位、无暂停、无 seek）', () async {
      final s = build(total: () => null);
      await engine.play();

      expect(await s.begin(), isFalse);
      expect(s.isActive, isFalse);
      expect(feedback.isScrubbing, isFalse, reason: '不进入反馈相位');
      expect(engine.callLog, isNot(contains('pause')));
      expect(engine.isPlaying, isTrue, reason: '同现状静默：不打断播放');
      s.moveBy(const Duration(seconds: 1));
      expect(seeks, isEmpty, reason: '基准未定，本帧丢弃');
    });

    test('时长 ≤0 视同未知', () async {
      final s = build(total: () => Duration.zero);
      expect(await s.begin(), isFalse);
    });

    test('requireKnownDuration=false（player 差分）：时长未知照常起会话',
        () async {
      final s = build(total: () => null, requireKnownDuration: false);
      await engine.play();
      engine.callLog.clear();

      expect(await s.begin(), isTrue);
      expect(engine.callLog, contains('pause'), reason: '在播照常暂停定格');
      s.moveBy(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(seeks, [const Duration(seconds: 1)],
          reason: '时长未知：只钳 ≥0、照常入队（submitter 兜底）');
    });
  });

  group('moveBy（累计 + 钳制；未 begin 丢弃）', () {
    test('累计增量与钳制到 [0, total]', () async {
      final s = build();
      await engine.seek(const Duration(seconds: 8));
      await s.begin();

      s.moveBy(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(seeks.single, const Duration(seconds: 10), reason: '钳上界');
      s.moveBy(const Duration(seconds: -30));
      await pumpEventQueue();
      expect(seeks.last, Duration.zero, reason: '钳下界');
      expect(indicator.value, Duration.zero, reason: 'indicator 与入队值同源');
    });

    test('未 begin 直接 moveBy：丢弃（无 seek、无相位）', () async {
      final s = build();
      s.moveBy(const Duration(seconds: 1));
      expect(seeks, isEmpty);
      expect(s.isActive, isFalse);
    });
  });

  group('end（恢复守卫；cancel 回退）', () {
    test('wasPlaying && 界内：play 续播 + 相位结束', () async {
      final s = build(
        resumeRange: (t) =>
            t >= Duration.zero && t <= const Duration(seconds: 10),
      );
      await engine.play();
      await engine.seek(const Duration(seconds: 5));
      engine.callLog.clear();
      await s.begin();
      s.moveBy(const Duration(seconds: 1));

      await s.end();
      expect(engine.callLog.last, 'play');
      expect(engine.isPlaying, isTrue);
      expect(feedback.isScrubbing, isFalse);
      expect(s.isActive, isFalse);
    });

    test('wasPlaying && 界外：不 play（区间外暂停查看态）', () async {
      final s = build(
        resumeRange: (t) => t >= Duration.zero && t <= const Duration(seconds: 4),
      );
      await engine.play();
      await engine.seek(const Duration(seconds: 3));
      await s.begin();
      s.moveBy(const Duration(seconds: 4)); // 目标 7s，越出 [0, 4s]

      engine.callLog.clear();
      await s.end();
      expect(engine.callLog, isNot(contains('play')));
      expect(feedback.isScrubbing, isFalse, reason: '相位照常结束');
    });

    test('未在播 end：不 play、不回调（保持暂停）', () async {
      final s = build(
        resumeRange: (t) =>
            t >= Duration.zero && t <= const Duration(seconds: 10),
      );
      await s.begin();
      s.moveBy(const Duration(seconds: 1));
      await s.end();
      expect(engine.callLog, isNot(contains('play')));
    });

    test('resumeRange 为 null：不守卫，wasPlaying 即续播', () async {
      final s = build();
      await engine.play();
      await engine.seek(const Duration(seconds: 9));
      await s.begin();
      s.moveBy(const Duration(seconds: 5)); // 目标钳到 10s 尾

      engine.callLog.clear();
      await s.end();
      expect(engine.callLog.last, 'play', reason: 'null 守卫 = 不拦截');
    });

    test('end 幂等：!isActive 时 no-op（无 play、无 seek）', () async {
      final s = build();
      await s.begin();
      await s.end();
      engine.callLog.clear();
      await s.end();
      expect(engine.callLog, isEmpty);
      expect(feedback.isScrubbing, isFalse);
    });

    test('cancel：单发基准回退（latest-wins）再续播，indicator 不写回退值',
        () async {
      final s = build(cancelZoneEnabled: true);
      await engine.play();
      await engine.seek(const Duration(seconds: 5));
      engine.callLog.clear();
      await s.begin();
      s.moveBy(const Duration(seconds: 2)); // 目标 7s

      engine.callLog.clear();
      await s.end(cancel: true);
      await pumpEventQueue();
      expect(seeks, [const Duration(seconds: 7), const Duration(seconds: 5)],
          reason: '回退单发：拖动 seek 后只追加一次基准回退（latest-wins 收敛）');
      expect(engine.callLog.contains('play'), isTrue, reason: '按守卫续播');
      expect(engine.position, const Duration(seconds: 5),
          reason: '最终落点收敛到回退基准');
      expect(indicator.value, const Duration(seconds: 7),
          reason: '回退经 submit 单发，不写 indicator（player 现状同源）');
    });

    test('cancelZoneEnabled=false：cancel 无害（不回退）', () async {
      final s = build(cancelZoneEnabled: false);
      await engine.play();
      await engine.seek(const Duration(seconds: 5));
      engine.callLog.clear();
      await s.begin();
      s.moveBy(const Duration(seconds: 2));
      await pumpEventQueue();
      engine.callLog.clear();

      await s.end(cancel: true);
      await pumpEventQueue();
      expect(seeks, [const Duration(seconds: 7)], reason: '无回退 seek');
      expect(engine.callLog.last, 'play', reason: '按守卫正常续播');
    });

    test('begin 失败（时长未知）后 end：no-op', () async {
      final s = build(total: () => null);
      await s.begin();
      await s.end();
      expect(engine.callLog, isEmpty);
    });
  });


/// player/blank 整配置差分参数化：同一生命周期序列分别以 player
/// 完整配置（cancelZoneEnabled + 守卫 + 无时长门）与 blank 配置（无取消角、
/// 时长门、effective 界内守卫）驱动，断言同序列下两配置的可观察差异仅在
/// 注入轴上。
group('player/blank 整配置差分参数化', () {
  // 同一驱动序列：在播起手 → 拖两帧 → end（可选 cancel）。
  Future<void> drive(
    ScrubSession s,
    FakePlaybackEngine engine, {
    bool cancel = false,
  }) async {
    await engine.play();
    await engine.seek(const Duration(seconds: 5));
    engine.callLog.clear();
    await s.begin();
    s.moveBy(const Duration(seconds: 1));
    s.moveBy(const Duration(seconds: -3));
    await pumpEventQueue();
    await s.end(cancel: cancel);
    await pumpEventQueue();
  }

  test('player 配置：cancel 回退到定格基准再续播', () async {
    final s = build(
      cancelZoneEnabled: true,
      requireKnownDuration: false,
      resumeRange: (t) => t >= Duration.zero && t <= const Duration(seconds: 10),
    );
    await drive(s, engine, cancel: true);
    expect(
      seeks,
      [
        const Duration(seconds: 6),
        const Duration(seconds: 3),
        const Duration(seconds: 5),
      ],
      reason: '逐帧累计（6s、3s）后 cancel 单发定格点回退（基准 5s）',
    );
    expect(engine.position, const Duration(seconds: 5));
    expect(engine.callLog.contains('play'), isTrue, reason: '界内续播');
    expect(feedback.isScrubbing, isFalse);
  });

  test('blank 配置：cancel 无害、守卫界外不续播', () async {
    final s = build(
      cancelZoneEnabled: false,
      requireKnownDuration: true,
      resumeRange: (t) => t >= Duration.zero && t <= const Duration(seconds: 2),
    );
    await drive(s, engine); // 拖到 6s-3s=3s，越出 [0, 2s]
    expect(seeks, [const Duration(seconds: 6), const Duration(seconds: 3)],
        reason: '无取消角：cancel 分支不发回退，落点 3s');
    expect(engine.callLog.contains('play'), isFalse, reason: '越出有效区间不续播');
    expect(feedback.isScrubbing, isFalse);
  });

  test('两配置同序列（不 cancel、界内）：生命周期轨迹一致', () async {
    final player = build(
      cancelZoneEnabled: true,
      requireKnownDuration: false,
      resumeRange: (t) => t >= Duration.zero && t <= const Duration(seconds: 10),
    );
    final playerSeeks = seeks;
    final playerCallLog = engine.callLog;
    await drive(player, engine);

    final blank = build(
      cancelZoneEnabled: false,
      requireKnownDuration: true,
      resumeRange: (t) => t >= Duration.zero && t <= const Duration(seconds: 10),
    );
    await drive(blank, engine);

    expect(seeks, playerSeeks, reason: '同序列下落点轨迹一致');
    expect(
      engine.callLog.where((c) => c != 'seek'),
      playerCallLog.where((c) => c != 'seek'),
      reason: 'play/pause 序一致（守卫差异仅由 resumeRange 注入轴决定）',
    );
  });
});

}
