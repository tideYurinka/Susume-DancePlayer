/// 标注时间线的纯操作函数。
///
/// 约定：模型不可变、UI 不直接改模型，**所有变更一律经本文件的纯函数**——
/// 每个操作接收 [AnnotationTimeline] 并返回一个新实例，原实例不变。
///
/// 覆盖：分段线新建/删除/拖动（区间钳制）、flag 置位/清除、视频首/尾设置
/// （首 ≤ 尾钳制）。学习段几何由派生函数计算（见 `learning_segments.dart`）。
///
/// 对外契约（UI 需遵守）：
///
///   - **非法 vs no-op**：`addSegmentLine` 对区间外位置抛 [ArgumentError]
///     （新建是被**拒**，不是钳制）；`moveSegmentLine` 越邻/触边界时返回原模型
///     （no-op，拖动被**丢弃**而非吸附到最近合法位）。预览线可位于有效区间外，
///     UI 在区间外点「分段」时应吞掉该异常、拖出边界时应
///     丢弃本次拖动，勿把两者的抛/op 当成 bug。
///   - **段序重排**：新建/删除分段线或缩小首尾区间都会改变学习段的数量与段序
///     （order 键）。以段序存储的属性（熟练度/激活/重点）
///     必须在这些操作发生时同步重排/级联（如删除融合取熟练度较高者），本文件
///     只负责时间线几何，属性存储的级联在属性存储侧落实。
library;

import 'annotation_timeline.dart';
import 'half_beat_line.dart';
import 'segment_line.dart';

/// 新建一条分段线：在时间轴 [at] 处创建（默认细线）。
///
/// 区间外被**拒**：[at] 必须严格位于 `(rangeStart, rangeEnd)` 开区间内，
/// 否则抛 [ArgumentError]（在有效区间边界上无法产生非零学习段）。若 [at] 已有
/// 一条分段线则视为 no-op、返回原模型（不产生重复线）。位置自动升序排列。
AnnotationTimeline addSegmentLine(
  AnnotationTimeline t,
  Duration at, {
  bool flagged = false,
}) {
  if (at <= t.rangeStart || at >= t.rangeEnd) {
    throw ArgumentError.value(at, 'at', '分段线位置必须在首/尾开区间 ${_rangeLabel(t)} 内');
  }
  if (t.segmentLines.any((line) => line.position == at)) return t;
  return _rebuild(
    t,
    lines: [
      ...t.segmentLines,
      SegmentLine(position: at, flagged: flagged),
    ],
  );
}

/// 删除索引 [index] 处的分段线（index 越界抛 [RangeError]）。
///
/// 删除即「融合相邻学习段」：派生几何随之合并（见 learning_segments.dart）；
/// 熟练度/重点的融合规则在属性存储上落实。
AnnotationTimeline removeSegmentLine(AnnotationTimeline t, int index) {
  _checkLineIndex(t, index);
  final lines = [...t.segmentLines]..removeAt(index);
  return _rebuild(t, lines: lines);
}

/// 拖动分段线 [index] 到 [to]（钳制语义）。
///
/// 钳制到首/尾区间内**且不越过相邻分段线**（保持升序与几何完整）：当 [to] 落到
/// 其左/右邻居位置上或越过之（含到达首/尾边界）时，本次拖动为 no-op、返回原模型
/// （不产生相邻重叠或零长段的非法状态）。其余任意落在开区间内的目标位置均生效。
AnnotationTimeline moveSegmentLine(
  AnnotationTimeline t,
  int index,
  Duration to,
) {
  _checkLineIndex(t, index);
  final lo = index == 0 ? t.rangeStart : t.segmentLines[index - 1].position;
  final hi = index == t.segmentLines.length - 1
      ? t.rangeEnd
      : t.segmentLines[index + 1].position;
  if (to <= lo || to >= hi) return t;
  final lines = [...t.segmentLines];
  lines[index] = lines[index].copyWith(position: to);
  return _rebuild(t, lines: lines);
}

/// 置位/清除分段线 [index] 的 flag（已是目标值则 no-op）。
AnnotationTimeline setSegmentLineFlag(
  AnnotationTimeline t,
  int index,
  bool value,
) {
  _checkLineIndex(t, index);
  if (t.segmentLines[index].flagged == value) return t;
  final lines = [...t.segmentLines];
  lines[index] = lines[index].copyWith(flagged: value);
  return _rebuild(t, lines: lines);
}

/// 切换分段线 [index] 的 flag（置位 ↔ 清除）。
AnnotationTimeline toggleSegmentLineFlag(AnnotationTimeline t, int index) {
  return setSegmentLineFlag(t, index, !t.segmentLines[index].flagged);
}

/// 设置视频首/尾（一次一个或同时）。首 ≤ 尾始终成立（归一化钳制）。
///
/// 区间被缩小后，落在新区间外的分段线被剔除（标注只能在区间内）；剔除后若
/// 剩余分段线仍满足不变式，学习段几何由派生函数保持一致。
AnnotationTimeline setVideoRange(
  AnnotationTimeline t, {
  Duration? start,
  Duration? end,
}) {
  return AnnotationTimeline.normalized(
    videoDuration: t.videoDuration,
    rangeStart: start ?? t.rangeStart,
    rangeEnd: end ?? t.rangeEnd,
    segmentLines: t.segmentLines,
    halfBeatLines: t.halfBeatLines,
  );
}

/// 仅调整视频首，保证 `rangeStart <= rangeEnd`（钳制）。
AnnotationTimeline setVideoRangeStart(AnnotationTimeline t, Duration start) {
  return setVideoRange(t, start: start);
}

/// 仅调整视频尾，保证 `rangeStart <= rangeEnd`（钳制）。
AnnotationTimeline setVideoRangeEnd(AnnotationTimeline t, Duration end) {
  return setVideoRange(t, end: end);
}

/// 自动分段整体替换：一次设置首/尾到
/// 网格首末拍，并以 [cuts] 整体替换全部分段线（32 拍下刀派生由
/// `auto_segment.dart` 纯函数完成，本函数只管时间线几何）。落在新区间
/// 外的切点由归一化构造剔除，首尾钳制与 [setVideoRange] 同源。
///
/// **flag 迁移**（见词条「自动分段」）：旧分段线上置位的 flag 迁到
/// **时刻最近**的新切割线——无距离阈值；距离并列取更早那条；多条旧 flag
/// 命中同一条新刀只置位一次（新线 flag 是布尔）；只有落在新首/尾开区间内
/// 的旧 flag 参与迁移，区间外的丢弃。切割线为空时新线列表为空、一条都不迁。
AnnotationTimeline applyAutoSegment(
  AnnotationTimeline t, {
  required Duration start,
  required Duration end,
  required List<Duration> cuts,
}) {
  final replaced = AnnotationTimeline.normalized(
    videoDuration: t.videoDuration,
    rangeStart: start,
    rangeEnd: end,
    segmentLines: [
      for (final cut in cuts) SegmentLine(position: cut),
    ],
    halfBeatLines: t.halfBeatLines,
  );
  final landed = _migratedFlagCuts(t.segmentLines, replaced);
  if (landed.isEmpty) return replaced;
  return AnnotationTimeline.normalized(
    videoDuration: replaced.videoDuration,
    rangeStart: replaced.rangeStart,
    rangeEnd: replaced.rangeEnd,
    segmentLines: [
      for (final line in replaced.segmentLines)
        line.copyWith(flagged: landed.contains(line.position)),
    ],
    halfBeatLines: replaced.halfBeatLines,
  );
}

/// [oldLines] 中置位的 flag → 在新时间线 [replaced] 的切割线上的落位集合。
///
/// 每条旧 flag 取 [replaced] 的切割线中时刻最近者，距离并列取更早那条：
/// 切割线升序（归一化保证）且比较用严格「小于」，故并列时先到（更早）者胜。
/// 只有落在 [replaced] 首/尾开区间内的旧 flag 参与迁移，区间内外的丢弃；
/// 新旧刀同刻时距离为 0、原样命中；返回值即新刀置位集合（去重）。
///
/// 不复用 `snap.nearestCandidate`：该收口的并列语义是**取时间靠后者**，
/// 与见词条「自动分段」要求的「取更早」相反，复用会把并列规则反转。
Set<Duration> _migratedFlagCuts(
  List<SegmentLine> oldLines,
  AnnotationTimeline replaced,
) {
  final cuts = [for (final line in replaced.segmentLines) line.position];
  if (cuts.isEmpty) return const {};
  final landed = <Duration>{};
  for (final line in oldLines) {
    if (!line.flagged) continue;
    final at = line.position;
    if (at <= replaced.rangeStart || at >= replaced.rangeEnd) continue;
    Duration? nearest;
    Duration? nearestDistance;
    for (final cut in cuts) {
      final distance = (cut - at).abs();
      if (nearestDistance == null || distance < nearestDistance) {
        nearest = cut;
        nearestDistance = distance;
      }
    }
    if (nearest != null) landed.add(nearest);
  }
  return landed;
}

/// 清空全部分段线：学习段几何
/// 归零（整片范围练习），首/尾线与半拍线保留。
AnnotationTimeline clearSegmentLines(AnnotationTimeline t) {
  if (t.segmentLines.isEmpty) return t;
  return _rebuild(t, lines: const []);
}

/// 节拍对齐应用：把首/尾线与全部分段线/
/// 半拍线的绝对时间整体平移 [delta]，不变式（升序/开区间/首尾钳制）由
/// 既有归一化构造保证——越界线剔除、首尾钳在 `0..videoDuration`。
/// [delta] 为零时返回原模型（no-op）。
AnnotationTimeline shiftBeatAlignment(AnnotationTimeline t, Duration delta) {
  if (delta == Duration.zero) return t;
  return AnnotationTimeline.normalized(
    videoDuration: t.videoDuration,
    rangeStart: t.rangeStart + delta,
    rangeEnd: t.rangeEnd + delta,
    segmentLines: [
      for (final line in t.segmentLines)
        line.copyWith(position: line.position + delta),
    ],
    halfBeatLines: [
      for (final line in t.halfBeatLines)
        line.copyWith(position: line.position + delta),
    ],
  );
}

AnnotationTimeline _rebuild(
  AnnotationTimeline t, {
  required List<SegmentLine> lines,
  List<HalfBeatLine>? halfBeats,
}) {
  return AnnotationTimeline.normalized(
    videoDuration: t.videoDuration,
    rangeStart: t.rangeStart,
    rangeEnd: t.rangeEnd,
    segmentLines: lines,
    halfBeatLines: halfBeats ?? t.halfBeatLines,
  );
}

/// 新建一条半拍线：在时间轴 [at] 处创建。
///
/// 区间外被**拒**：[at] 必须严格位于 `(rangeStart, rangeEnd)` 开区间内，
/// 否则抛 [ArgumentError]。若 [at] 已有一条半拍线则视为 no-op、返回原模型
/// （不产生重复线）。位置自动升序排列。半拍线与分段线可同位、互不排斥；
/// 不参与学习段几何派生（学习段只由分段线决定）。
AnnotationTimeline addHalfBeatLine(AnnotationTimeline t, Duration at) {
  if (at <= t.rangeStart || at >= t.rangeEnd) {
    throw ArgumentError.value(at, 'at', '半拍线位置必须在首/尾开区间 ${_rangeLabel(t)} 内');
  }
  if (t.halfBeatLines.any((line) => line.position == at)) return t;
  return _rebuild(
    t,
    lines: t.segmentLines,
    halfBeats: [...t.halfBeatLines, HalfBeatLine(position: at)],
  );
}

/// 删除索引 [index] 处的半拍线（index 越界抛 [RangeError]）。
///
/// 半拍线不参与学习段几何派生：删除不改变分段线与学习段。
AnnotationTimeline removeHalfBeatLine(AnnotationTimeline t, int index) {
  _checkHalfBeatIndex(t, index);
  final halfBeats = [...t.halfBeatLines]..removeAt(index);
  return _rebuild(t, lines: t.segmentLines, halfBeats: halfBeats);
}

/// 拖动半拍线 [index] 到 [to]（钳制语义）。
///
/// 钳制到首/尾区间内**且不越过相邻半拍线**（保持升序互异）：当 [to] 落到
/// 其左/右邻居位置上或越过之（含到达首/尾边界）时 no-op、返回原模型。
/// 与分段线互不钳制（可自由跨越分段线——两类标记互不约束）。
AnnotationTimeline moveHalfBeatLine(
  AnnotationTimeline t,
  int index,
  Duration to,
) {
  _checkHalfBeatIndex(t, index);
  final lines = t.halfBeatLines;
  final lo = index == 0 ? t.rangeStart : lines[index - 1].position;
  final hi = index == lines.length - 1 ? t.rangeEnd : lines[index + 1].position;
  if (to <= lo || to >= hi) return t;
  final next = [...lines];
  next[index] = next[index].copyWith(position: to);
  return _rebuild(t, lines: t.segmentLines, halfBeats: next);
}

void _checkHalfBeatIndex(AnnotationTimeline t, int index) {
  if (index < 0 || index >= t.halfBeatLines.length) {
    throw RangeError.range(
      index,
      0,
      t.halfBeatLines.length - 1,
      'index',
      '半拍线索引越界',
    );
  }
}

void _checkLineIndex(AnnotationTimeline t, int index) {
  if (index < 0 || index >= t.segmentLines.length) {
    throw RangeError.range(
      index,
      0,
      t.segmentLines.length - 1,
      'index',
      '分段线索引越界',
    );
  }
}

String _rangeLabel(AnnotationTimeline t) => '[${t.rangeStart}, ${t.rangeEnd}]';
