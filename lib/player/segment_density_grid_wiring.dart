/// 逐段档读面装配：把播放器标注侧的逐段档与
/// 分段几何注入节拍轨读面端口（`beatGridSegmentContextProvider`）——
/// beat_track_state 不反向依赖播放器标注库，由装配处（main.dart）注册本
/// override，与 main.dart 既有观察者装配同一条依赖倒置先例。
library;

import '../annotation/learning_segments.dart' show deriveLearningSegments;
import '../beat_track_state/beat_track_state.dart'
    show beatGridSegmentContextProvider;
import 'annotation_editor.dart'
    show annotationTimelineProvider, segmentDensitiesProvider;

/// 逐段档 + 分段几何 → 读面端口（实时跟随：档集合变化使 [beatGridProvider]
/// 重算）。学习段几何（首/尾 + 分段线）按段序换算为毫秒半开区间。
final beatGridSegmentContextWiring = beatGridSegmentContextProvider
    .overrideWith((ref) {
      final timeline = ref.watch(annotationTimelineProvider);
      return (
        segmentDensities: ref.watch(segmentDensitiesProvider),
        segments: [
          for (final segment in deriveLearningSegments(timeline))
            (
              startMs: segment.start.inMilliseconds,
              endMs: segment.end.inMilliseconds,
            ),
        ],
      );
    });
