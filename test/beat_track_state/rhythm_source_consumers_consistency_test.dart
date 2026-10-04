import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/annotation/transition_segment.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatGridProvider, beatTrackStateProvider;
import 'package:dance_learning_app/player/beat_correction.dart'
    show beatCorrectionAvailableProvider;
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show delayedLoopWaitProvider, prepBeatsProvider;
import 'package:dance_learning_app/player/delayed_play.dart';
import 'package:dance_learning_app/player/loop_prompt.dart';
import 'package:dance_learning_app/player/metronome_overlay.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:fake_async/fake_async.dart';

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';

void main() {
  // 跨消费方一致性（主判据）：同一状态集合（就绪非空 /
  // 就绪空拍点 / 占位 / 异常）下，各消费方对「等多久 / 能不能用」的回答
  // 互不矛盾。期望值全部为手算字面量（独立事实源），不重算实现公式。
  //
  // 就绪非空网格：拍点 0.5s / 1.5s（1.0s 拍距）→ 名义一拍 1s、八拍标称 8s。
  BeatTrackState readyNonEmpty() => BeatTrackState.ready(
    marker_doc.BeatGrid(
      model: 'madmom_downbeat_rnn_full.onnx',
      fps: 100,
      generatedAt: DateTime.utc(2026, 9, 14),
      beats: const [
        marker_doc.BeatPoint(t: 0.5, down: true),
        marker_doc.BeatPoint(t: 1.5, down: true),
      ],
    ),
  );

  // 就绪空拍点：映射点落占位网格（120 bpm → 一拍 0.5s、八拍 4s）。
  BeatTrackState readyEmptyBeats() => BeatTrackState.ready(
    marker_doc.BeatGrid(
      model: 'madmom_downbeat_rnn_full.onnx',
      fps: 100,
      generatedAt: DateTime.utc(2026, 9, 14),
    ),
  );

  group('跨消费方一致性：同一状态集合各问法互不矛盾', () {
    // 消费方问题 → 在该状态下的期望答案。倒计时 = 两支（循环提示 / 延迟
    // 播放）共同读取的八拍标称；循环前导 = 前导档位（档 8）；默认宽 =
    // 备注插入/局部镜像创建的八拍宽（毫秒）；拒录阈值 = 名下单拍；
    // 录制准备 = 三支之一（起点 10500、区间 0、准备 8 拍）。
    final rows =
        <
          ({
            String name,
            BeatTrackState state,
            Duration loopLeadTier8,
            Duration loopLeadTier0,
            Duration countdown,
            int defaultWidthMs,
            Duration rejectThreshold,
            bool prepBeatLed,
            int prepLeadDurationMs,
            Duration transitionSideWidth,
            bool overlayVisible,
            bool toolGate,
          })
        >[
          (
            name: '就绪非空',
            state: readyNonEmpty(),
            loopLeadTier8: const Duration(seconds: 8),
            loopLeadTier0: Duration.zero,
            countdown: const Duration(seconds: 8),
            defaultWidthMs: 8000,
            rejectThreshold: const Duration(seconds: 1),
            prepBeatLed: true,
            // 起录点 10500 前只有 2 个真实拍点（500/1500）→「有几拍数几拍」，
            // 前导 = 起录点 − 首个可用拍点 = 10000。
            prepLeadDurationMs: 10000,
            transitionSideWidth: const Duration(seconds: 8),
            overlayVisible: true,
            toolGate: true,
          ),
          (
            name: '就绪空拍点（占位网格）',
            state: readyEmptyBeats(),
            loopLeadTier8: const Duration(seconds: 4),
            loopLeadTier0: Duration.zero,
            countdown: const Duration(seconds: 4),
            defaultWidthMs: 4000,
            rejectThreshold: const Duration(milliseconds: 500),
            prepBeatLed: true,
            prepLeadDurationMs: 4000,
            transitionSideWidth: const Duration(seconds: 4),
            overlayVisible: true,
            toolGate: false,
          ),
          (
            name: '占位',
            state: const BeatTrackState.placeholder(),
            loopLeadTier8: const Duration(seconds: 4),
            loopLeadTier0: Duration.zero,
            countdown: const Duration(seconds: 4),
            defaultWidthMs: 4000,
            rejectThreshold: const Duration(milliseconds: 500),
            prepBeatLed: true,
            prepLeadDurationMs: 4000,
            transitionSideWidth: const Duration(seconds: 4),
            overlayVisible: true,
            toolGate: false,
          ),
          (
            name: '异常（秒制兜底）',
            state: const BeatTrackState.error(),
            // 前导档位 = 档位数字即秒；两支倒计时 = 八拍标称 4s——同档位
            // 时长不等是登记不改的刻意不对称。
            loopLeadTier8: const Duration(seconds: 8),
            loopLeadTier0: Duration.zero,
            countdown: const Duration(seconds: 4),
            defaultWidthMs: 4000,
            rejectThreshold: const Duration(milliseconds: 500),
            prepBeatLed: false,
            prepLeadDurationMs: 4000,
            transitionSideWidth: const Duration(seconds: 4),
            overlayVisible: false,
            toolGate: false,
          ),
        ];

    for (final row in rows) {
      test('状态「${row.name}」：各消费方读数一致', () {
        fakeAsync((async) {
          final container = ProviderContainer(
            overrides: [
              privateJsonStorageProvider.overrideWithValue(
                InMemoryPrivateJsonStorage(),
              ),
            ],
          );
          addTearDown(container.dispose);
          container.read(beatTrackStateProvider.notifier).replace(row.state);
          final grid = container.read(beatGridProvider);

          // 循环前导（前导档位基准）。
          container.read(prepBeatsProvider.notifier).setLoopLead(8);
          expect(
            container.read(delayedLoopWaitProvider),
            row.loopLeadTier8,
            reason: '循环前导档 8',
          );
          container.read(prepBeatsProvider.notifier).setLoopLead(0);
          expect(
            container.read(delayedLoopWaitProvider),
            row.loopLeadTier0,
            reason: '循环前导档 0 = 不前导',
          );
          container.read(prepBeatsProvider.notifier).setLoopLead(4);

          // 两支倒计时 = 八拍标称：差 1ms 不到不结束、到点即结束。
          expect(grid.eightBeatNominal, row.countdown);
          final engine = FakePlaybackEngine(
            duration: const Duration(seconds: 1),
          );
          final loop = LoopPromptController(engine, gridOf: () => grid);
          engine.open(Uri.file('/videos/a.mp4'), play: true);
          async.elapse(const Duration(seconds: 1));
          expect(loop.phase, LoopPromptPhase.countdown);
          async.elapse(row.countdown - const Duration(milliseconds: 1));
          expect(loop.phase, LoopPromptPhase.countdown);
          async.elapse(const Duration(milliseconds: 1));
          expect(loop.phase, LoopPromptPhase.idle);
          loop.dispose();

          // 延迟播放兜底（占位/异常网格不产生八拍点 →
          // 墙钟一个八拍标称后从当前位置起播；主路径由
          // delayed_play_test.dart 直测）。
          final delayed = DelayedPlayController(
            FakePlaybackEngine(),
            phaseOf: () => null,
            prepBeatsOf: () => 4,
            validRangeOf: () => null,
            gridOf: () => grid,
          );
          unawaited(delayed.trigger());
          async.flushMicrotasks();
          expect(delayed.phase, DelayedPlayPhase.preparing);
          async.elapse(row.countdown - const Duration(milliseconds: 1));
          expect(delayed.phase, DelayedPlayPhase.preparing);
          async.elapse(const Duration(milliseconds: 1));
          expect(delayed.phase, DelayedPlayPhase.idle);
          delayed.dispose();

          // 默认宽 = 真实消费方「临时衔接段」的每侧窗宽（起点取整不越
          // 八拍点：分段线放在八拍点上，前/后各恰一个八拍标称）。
          final timeline = AnnotationTimeline.normalized(
            videoDuration: const Duration(seconds: 120),
            rangeStart: Duration.zero,
            rangeEnd: const Duration(seconds: 120),
            segmentLines: const [SegmentLine(position: Duration(seconds: 20))],
          );
          final transition = resolveTransitionSegment(
            timeline: timeline,
            lineIndex: 0,
            phase: BeatPhase(grid: grid),
          );
          expect(transition, isNotNull);
          // 后侧窗 = 线位置 + 八拍标称（区间内不截断）——该消费方读的
          // 正是八拍标称这条基准（前侧另经相位源取整，不在本表断言）。
          expect(
            transition!.end - const Duration(seconds: 20),
            row.transitionSideWidth,
            reason: '临时衔接段后侧窗宽',
          );
          // 备注插入/局部镜像创建的默认宽同读八拍标称，退化守卫不触发。
          expect(grid.eightBeatNominal.inMilliseconds, row.defaultWidthMs);

          // 拒录阈值 = 名下单拍。
          expect(grid.nominalBeat, row.rejectThreshold);

          // 录制准备三支之一。
          final plan = computeRecordingPrep(
            startPointMs: 10500,
            rangeStartMs: 0,
            prepBeats: 8,
            grid: grid,
          );
          expect(plan.beatLed, row.prepBeatLed);
          expect(plan.leadDurationMs, row.prepLeadDurationMs);

          // 浮层可见性（异常态整段不可见）。
          expect(
            isBeatOverlayContentVisible(
              displayEnabled: true,
              hasContent: true,
              positionReady: true,
              beatTrackError: grid.isSecondsFallback,
            ),
            row.overlayVisible,
          );

          // 工具槽门（八拍矫正可用 = 真实拍点可用且有强拍）。
          expect(container.read(beatCorrectionAvailableProvider), row.toolGate);
        });
      });
    }
  });
}
