/// 标注时间线模型（内存态，落 JSON 持久化）。
///
/// 核心对象 [AnnotationTimeline]：视频总时长 + 视频首/尾有效区间 + 分段线列表。
/// 学习段几何**不落盘**、由此区间与分段线实时推导（见 `learning_segments.dart`）；
/// 吸附/节拍参数与「熟练度/激活」等私密字段的归属见双文件
/// 分层（公开 `persistence/marker_document.dart` / 私密
/// `persistence/local_document.dart`）。
///
/// 本文件只含模型值类型与其不变式；**一切变更必须经 `timeline_ops.dart` 的纯操作
/// 函数**（UI 不直接改模型）。不变式：
///
///   1. `0 <= rangeStart <= rangeEnd <= videoDuration`；
///   2. 分段线与半拍线各自升序、互异，且严格位于 `(rangeStart, rangeEnd)`
///      开区间内（落在边界上的线无意义——分段线会产生零长学习段，故被
///      剔除）。
library;

import 'half_beat_line.dart';
import 'segment_line.dart';

/// 标注时间线（不可变值对象）。
///
/// 构造统一经工厂 [AnnotationTimeline.normalized] 归一化：视频首/尾被钳制到
/// 合法区间并保证 `rangeStart <= rangeEnd`，落在有效区间外的分段线被剔除，
/// 从而不变式恒成立。
class AnnotationTimeline {
  AnnotationTimeline._({
    required this.videoDuration,
    required this.rangeStart,
    required this.rangeEnd,
    required List<SegmentLine> segmentLines,
    List<HalfBeatLine> halfBeatLines = const [],
  }) : segmentLines = List.unmodifiable(segmentLines),
       halfBeatLines = List.unmodifiable(halfBeatLines);

  /// 归一化构造：钳制首/尾并剔除区间外的分段线（见文件头不变式）。
  ///
  /// [videoDuration] 为负时抛 [ArgumentError]（整片时长不可能为负）。
  factory AnnotationTimeline.normalized({
    required Duration videoDuration,
    Duration? rangeStart,
    Duration? rangeEnd,
    List<SegmentLine> segmentLines = const [],
    List<HalfBeatLine> halfBeatLines = const [],
  }) {
    if (videoDuration.isNegative) {
      throw ArgumentError.value(videoDuration, 'videoDuration', '视频时长不能为负');
    }
    final start = _clamp(
      rangeStart ?? Duration.zero,
      Duration.zero,
      videoDuration,
    );
    final end = _clamp(rangeEnd ?? videoDuration, start, videoDuration);

    final kept = <SegmentLine>[
      for (final line in segmentLines)
        if (line.position > start && line.position < end) line,
    ]..sort((a, b) => a.position.compareTo(b.position));

    final unique = <SegmentLine>[];
    for (final line in kept) {
      if (unique.isEmpty || unique.last.position != line.position) {
        unique.add(line);
      }
    }

    return AnnotationTimeline._(
      videoDuration: videoDuration,
      rangeStart: start,
      rangeEnd: end,
      segmentLines: unique,
      halfBeatLines: _normalizeHalfBeats(halfBeatLines, start, end),
    );
  }

  /// 整片默认：视频首 = 0:00、视频尾 = 视频时长、无分段线。
  factory AnnotationTimeline.wholeVideo(Duration videoDuration) {
    return AnnotationTimeline.normalized(videoDuration: videoDuration);
  }

  /// 视频总时长（恒定，打开视频时确定；也是默认视频尾）。
  final Duration videoDuration;

  /// 视频首（有效练习区间左边界，默认 0:00）。
  final Duration rangeStart;

  /// 视频尾（有效练习区间右边界，默认 = 视频时长）。
  final Duration rangeEnd;

  /// 分段线：升序、互异、严格位于首/尾开区间内。
  final List<SegmentLine> segmentLines;

  /// 半拍线：升序、互异、严格位于首/尾开区间内；不参与
  /// 学习段几何派生。
  final List<HalfBeatLine> halfBeatLines;

  /// 有效练习区间时长（= `rangeEnd - rangeStart`；学习段总长固定为此值）。
  Duration get practiceRangeDuration => rangeEnd - rangeStart;

  @override
  bool operator ==(Object other) {
    if (other is! AnnotationTimeline) return false;
    if (other.videoDuration != videoDuration) return false;
    if (other.rangeStart != rangeStart) return false;
    if (other.rangeEnd != rangeEnd) return false;
    if (other.segmentLines.length != segmentLines.length) return false;
    for (var i = 0; i < segmentLines.length; i++) {
      if (other.segmentLines[i] != segmentLines[i]) return false;
    }
    if (other.halfBeatLines.length != halfBeatLines.length) return false;
    for (var i = 0; i < halfBeatLines.length; i++) {
      if (other.halfBeatLines[i] != halfBeatLines[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    videoDuration,
    rangeStart,
    rangeEnd,
    Object.hashAll(segmentLines),
    Object.hashAll(halfBeatLines),
  );

  @override
  String toString() =>
      'AnnotationTimeline(videoDuration: $videoDuration, range: '
      '[$rangeStart, $rangeEnd], segmentLines: $segmentLines, '
      'halfBeatLines: $halfBeatLines)';
}

/// 半拍线归一化：钳除区间外、升序、去重（与分段线同规则）。
List<HalfBeatLine> _normalizeHalfBeats(
  List<HalfBeatLine> lines,
  Duration start,
  Duration end,
) {
  final kept = <HalfBeatLine>[
    for (final line in lines)
      if (line.position > start && line.position < end) line,
  ]..sort((a, b) => a.position.compareTo(b.position));
  final unique = <HalfBeatLine>[];
  for (final line in kept) {
    if (unique.isEmpty || unique.last.position != line.position) {
      unique.add(line);
    }
  }
  return unique;
}

Duration _clamp(Duration value, Duration lo, Duration hi) {
  if (value < lo) return lo;
  if (value > hi) return hi;
  return value;
}
