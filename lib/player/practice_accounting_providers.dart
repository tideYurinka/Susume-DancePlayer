/// 练习记账事实流与练舞统计记录器的注入点：记账事实由播放侧的在飞态
/// （片段回看在飞、录制准备期、延迟预备期）与引擎播放态组装，记录器消费
/// 事实流把判定为「计」的采样摊到四拍桶。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../beat_track_state/beat_track_state.dart'
    show appliedBeatDensity, committedBeatGridProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import '../persistence/practice_accounting.dart';
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import '../persistence/practice_stats_recorder.dart';
import 'annotation_editor.dart'
    show
        practiceClipActivationProvider,
        practiceClipById,
        practiceClipsProvider;
import 'compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'delayed_play.dart' show delayedPlayPreparingProvider;

/// 练习片段回看在飞：激活非空 ∧ 片段可解析
/// （即今天的在飞语义；悬空激活不构成在飞 ⇒ 保持「计入」的今天口径）。
final practiceAccountingFactsProvider =
    Provider<Stream<PracticeAccountingFacts>>((ref) {
      // 引擎更换时本 provider 随记录器一起重建：新引擎的 isPlaying 边沿要重新
      // 订阅，事实流保持单订阅（建流时的 emitCurrent 先入缓冲、订阅者一到即
      // 送达，不丢事件）。（若本 provider 不随引擎重建，记录器重建时会换一个
      // 订阅者去监听同一条已订阅的单订阅流，报「已被监听」。）
      final engine = ref.watch(playbackEngineProvider);
      // 回看在飞 = 激活非空 ∧ 片段可解析——激活面与片段清单两个既有 owner，
      // 这里只做派生读（不落中间 provider：派生值须随事实写入即时重算）。
      bool reviewInFlight() {
        final active = ref.read(practiceClipActivationProvider);
        if (active == null) return false;
        return practiceClipById(
              ref.read(practiceClipsProvider),
              active.clipId,
            ) !=
            null;
      }

      var clipReviewInFlight = reviewInFlight();
      var recordingPreparing =
          ref.read(compareRecordingPhaseProvider) ==
          CompareRecordingPhase.preparing;
      var delayedPlayPreparing = ref.read(delayedPlayPreparingProvider);
      // 引擎播放态（原 `enginePlayingProvider`；零外部消费者，内联进唯一读
      // 处）：播放态的 owner 仍是引擎，这里只做「现值 + 边沿」的搬运。订阅与
      // 上面三条 `ref.listen` 同为同步送达——引擎边沿在流回调里直接发出事实，
      // 不经中间 provider 的二次通知，事实事件的先后仍等于状态写入的先后（记录
      // 器结算点不受交错时序影响）；同值边沿按原 Notifier 的
      // `updateShouldNotify` 同一口径抑制，不产生重复事实事件。
      var enginePlaying = engine.isPlaying;
      final controller = StreamController<PracticeAccountingFacts>();
      void emit(bool playing) => controller.add(
        PracticeAccountingFacts(
          enginePlaying: playing,
          clipReviewInFlight: clipReviewInFlight,
          recordingPreparing: recordingPreparing,
          delayedPlayPreparing: delayedPlayPreparing,
        ),
      );
      void emitCurrent() => emit(enginePlaying);
      void syncReviewInFlight() {
        clipReviewInFlight = reviewInFlight();
        emitCurrent();
      }

      ref.listen(
        practiceClipActivationProvider,
        (_, _) => syncReviewInFlight(),
      );
      ref.listen(practiceClipsProvider, (_, _) => syncReviewInFlight());
      ref.listen(compareRecordingPhaseProvider, (
        _,
        CompareRecordingPhase phase,
      ) {
        recordingPreparing = phase == CompareRecordingPhase.preparing;
        emitCurrent();
      });
      ref.listen(delayedPlayPreparingProvider, (_, bool preparing) {
        delayedPlayPreparing = preparing;
        emitCurrent();
      });
      // 内联前的 Notifier 只在取值真的翻转时通知（updateShouldNotify 抑制同值
      // 写入），这里同一口径：同值边沿不产生重复事实事件。
      final playingSubscription = engine.isPlayingStream.listen((playing) {
        if (playing == enginePlaying) return;
        enginePlaying = playing;
        emit(playing);
      });
      ref.onDispose(playingSubscription.cancel);
      emitCurrent();
      ref.onDispose(controller.close);
      return controller.stream;
    });

/// 练舞统计记录器注入点（见词条「四拍桶」接入
/// 四拍桶）：消费事实流，判定翻转即结算/重开区间；同时订阅引擎位置流，
/// 把判定为「计」的采样点摊到四拍桶（网格源 = **落盘网格** provider——
/// 不含预览偏移与预览档；未就绪不产桶）。桶键带
/// 记录时的倍频身份（读已落盘档）。测试可注入自管实例（假时钟）。生命
/// 周期随 ProviderScope（dispose 收口）；记录器没有计数器，离开播放页
/// 不需要任何配平调用。
final practiceStatsRecorderProvider = Provider<PracticeStatsRecorder?>((ref) {
  final recorder = PracticeStatsRecorder(
    facts: ref.watch(practiceAccountingFactsProvider),
    store: ref.watch(practiceStatsStoreProvider),
    positions: ref.watch(playbackEngineProvider).positionStream,
    buckets: ref.watch(fourBeatBucketStoreProvider),
    grid: () => ref.read(committedBeatGridProvider),
    density: () => appliedBeatDensity(ref),
  );
  ref.onDispose(recorder.dispose);
  return recorder;
});
