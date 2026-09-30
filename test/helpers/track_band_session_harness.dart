import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/core/playback/playback_engine.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show clearLoopActivationsIfOutside;
import 'package:dance_learning_app/player/track_band_session.dart';

/// 轨道带会话域的**测试侧唯一共享构造**。
///
/// 二十八处轨道带构造点与各套引导函数共用这一份装配：会话域的五件（窗口、
/// 预览线显示值、拖动标记、编辑态微调、跨面捏合）由本函数一次给全——各处
/// 不再各搭一份同构接线。
///
/// [container] 非空时，`TrackBandSession.clearLoops` 转调生产的
/// `clearLoopActivationsIfOutside`（读口闭包由 `ProviderContainer.read` 提供）。
/// 为 null 时不驱动越界清循环——只有不消费该事实的用例才省略。
TrackBandSession buildTrackBandSession({
  required PlaybackEngine engine,
  AnnotationTimeline? timeline,
  ProviderContainer? container,
  ValueChanged<Duration>? onScrubCommitted,
  double layerWidth = 800,
}) {
  return TrackBandSession(
    engine: engine,
    // 未显式给时间线的用例与生产同口径：时间线未按视频时长初始化即整片兜底
    // （effectiveAnnotationTimelineProvider 的唯一兜底）。
    timeline: () =>
        timeline ??
        AnnotationTimeline.wholeVideo(engine.duration ?? Duration.zero),
    clearLoops: container == null
        ? (_, _) {}
        : (tl, position) =>
              clearLoopActivationsIfOutside(container.read, tl, position),
    layerWidth: () => layerWidth,
    onScrubCommitted: onScrubCommitted,
  );
}
