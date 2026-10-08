/// 节拍呈现域的容器接线面：六个节拍
/// provider、两个值道模型与数拍内容件的家。依赖方向：本文件读容器并 import
/// 各素材域，单向向下；不适用 `beat_presentation.dart` 的域护栏（该文件自持
/// 上下文装配与驱动、不碰容器，接线天生读容器，故分居两文件）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatPhaseProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackPositionProvider;
import 'annotation_editor.dart'
    show activeLoopRangeProvider, effectiveAnnotationTimelineProvider;
import 'av_sync.dart' show avSyncProvider;
import 'av_sync_session.dart' show avSyncCalibrationSessionProvider;
import 'beat_animation.dart'
    show
        BeatPresentationValue,
        MetronomeBeatAnimation,
        beatAnimationStyleProvider;
import 'beat_count_layout.dart'
    show kBeatNumbersGap, kBeatPillPaddingH, kBeatPillPaddingV;
import 'beat_presentation.dart'
    show BeatPresentation, BeatPresentationFacts, kBeatPresentationTopUpPeriod;
import 'beat_prompt_panel.dart' show beatPromptEnabledProvider;
import 'beat_schedule.dart' show beatScheduleConsumerProvider;
import 'compare_recording.dart'
    show compareRecordingStartProvider, recordingPrepBeatProvider;
import 'metronome_overlay.dart'
    show BeatCountNumbers, isBeatOverlayContentVisible;
import 'metronome_sound.dart'
    show metronomeHalfBeatEnabledProvider, metronomeSoundEnabledProvider;
import 'song_loudness.dart' show metronomePlayVolumeProvider;
import 'metronome_source_registry.dart' show effectiveMetronomeSourceIdProvider;
import 'native_scheduled_audio.dart' show beatAudioRendererProvider;

/// 数拍派生位置：原样位置，null = 位置未就绪。锚点解析与数拍数字/动画
/// 统一消费本 provider。
///
/// 不叠加音画同步 Δ 平移：数拍数字/节拍动画/摆锤与节拍轨刻度
/// 同读视频时间轴，调 Δ 只改声音、屏幕不动。
final beatCountPositionProvider = Provider<Duration?>((ref) {
  return ref.watch(playbackPositionProvider).value;
});

/// 延迟锚：延迟播放控制器交出的会话值（=
/// 延迟起点，八拍点），不落盘、打断即撤。宿主随控制器通知写入；null =
/// 无在途延迟。供数拍锚点链消费（优先级：录制锚 → 延迟锚 → 激活锚）。
class DelayAnchorModel extends Notifier<Duration?> {
  @override
  Duration? build() => null;

  void set(Duration? anchor) {
    if (state != anchor) state = anchor;
  }
}

final delayAnchorProvider = NotifierProvider<DelayAnchorModel, Duration?>(
  DelayAnchorModel.new,
);

/// 节拍呈现对象注入点：这一簇唯一的对外对象，
/// 页面只保留 attach / detach / onFrame 与对发布值的订阅。发声排程
/// 在对象内：生产 seam 经容器直读现读（渲染器随生效音源重建后新实例即被
/// 拾取，推进不断声）；会话拍脉冲与发声同一拍点。ProviderScope 销毁时收流。
final beatPresentationProvider = Provider<BeatPresentation>((ref) {
  final presentation = BeatPresentation(
    streamControl: () => ref.read(beatAudioRendererProvider),
    consumer: () => ref.read(beatScheduleConsumerProvider),
    timebase: () => ref.read(beatAudioRendererProvider),
    onSessionBeat: () =>
        ref.read(avSyncCalibrationSessionProvider.notifier).fireBeatPulse(),
    topUpPeriod: kBeatPresentationTopUpPeriod,
  );
  unawaited(presentation.attach());
  ref.onDispose(() => unawaited(presentation.detach()));
  return presentation;
});

/// 节拍呈现素材聚合：模块声明的**原始事实**
/// 面在此按 provider 接线读齐——素材 provider 的变化合成一条重驱信号
/// （[BeatPresentationDriver.resync]）；「素材 → 每帧上下文」的解析规则归
/// 节拍呈现模块。引擎活输入（倍速/播放态）仍逐帧现读，不进本值。
final beatPresentationFactsProvider = Provider<BeatPresentationFacts>((ref) {
  final session = ref.watch(avSyncCalibrationSessionProvider);
  return BeatPresentationFacts(
    grid: ref.watch(beatGridProvider),
    phase: ref.watch(beatPhaseProvider),
    timeline: ref.watch(effectiveAnnotationTimelineProvider),
    recordingAnchor: ref.watch(compareRecordingStartProvider),
    delayAnchor: ref.watch(delayAnchorProvider),
    activeLoopStart: ref.watch(activeLoopRangeProvider)?.start,
    sourceId: ref.watch(effectiveMetronomeSourceIdProvider),
    slotVolumeOf: ref.watch(metronomePlayVolumeProvider),
    halfBeatEnabled: ref.watch(metronomeHalfBeatEnabledProvider),
    soundEnabled: ref.watch(metronomeSoundEnabledProvider),
    avSyncDelayMs: ref.watch(avSyncProvider).delayMs,
    sessionActive: session.active,
    sessionTier: session.tier,
    sessionTrialMs: session.trialMs,
  );
});

/// 发布值镜像：对象的当前拍 ValueListenable →
/// Riverpod 值道，浮层存在性与浮层内容读同一个值（同步转发，不产生第二
/// 份真相）。
final publishedBeatProvider =
    NotifierProvider<PublishedBeatModel, BeatPresentationValue?>(
      PublishedBeatModel.new,
    );

class PublishedBeatModel extends Notifier<BeatPresentationValue?> {
  @override
  BeatPresentationValue? build() {
    final presentation = ref.watch(beatPresentationProvider);
    void onChange() => state = presentation.currentBeat.value;
    presentation.currentBeat.addListener(onChange);
    ref.onDispose(() => presentation.currentBeat.removeListener(onChange));
    return presentation.currentBeat.value;
  }
}

/// 浮层内容可见性（放宽显隐条件）：[isBeatOverlayContentVisible]
/// 的 provider 面。位置就绪与异常两道门已被「发布空值」吸收（空值即无内容），
/// 四条件谓词只余两条件生效（另两个实参固定为真）。浮层底座（绘制 + 命中）
/// 只在内容真正显示时存在——内容为空即幽灵浮层修复：不挂载、不参与命中、
/// 不可进选中态。
final beatOverlayContentVisibleProvider = Provider<bool>((ref) {
  // 录制准备期的显隐口径：
  // 秒制兜底（异常网格 / 起录点前无可用拍点）整段不显示，其余全由发布值
  // 给出——数字与居中大数字同一次求值，无第二套计数。
  final hasContent =
      ref.watch(recordingPrepBeatProvider)?.showsContent ??
      // 发布值非空即有内容：位置未就绪、无锚
      // 可数与网格异常都已被「发布空值」吸收。
      ref.watch(publishedBeatProvider) != null;
  return isBeatOverlayContentVisible(
    displayEnabled: ref.watch(beatPromptEnabledProvider),
    hasContent: hasContent,
    positionReady: true,
    beatTrackError: false,
  );
});

/// 数拍跟练内容（读发布值）：数拍数字 + 节拍动画只读节拍呈现对象的
/// 发布值；无锚可数（发布空值）不显示。
class BeatCountContent extends ConsumerWidget {
  const BeatCountContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 节拍动画总开关：数拍数字 + 节拍动画同显同隐。
    if (!ref.watch(beatPromptEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final value = ref.watch(publishedBeatProvider);
    if (value == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kBeatPillPaddingH,
          vertical: kBeatPillPaddingV,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BeatCountNumbers(display: value.display),
            const SizedBox(height: kBeatNumbersGap),
            MetronomeBeatAnimation(
              style: ref.watch(beatAnimationStyleProvider),
              value: value,
            ),
          ],
        ),
      ),
    );
  }
}
