/// 命中解析适配层：带内「某个局部点落在哪个
/// 编辑目标」的唯一一处答案。
///
/// 本层把带内三件事收成一处：
///
///   - **编辑内容判定中枢** [editTargetAt]：优先级 = 预览条 → 练习片段块 →
///     学习段轨命中（分段线/首尾线 → 段体）→ 备注片段；不可映射几何、
///     轨道片头带与带外一律无目标；
///   - **行谓词** [rowAt] / [isLearningRow] / [isNoteRow] / [isMirrorRow]：
///     某纵向局部坐标落在哪一行，委派轨道行表 [TrackRowTable]（行区间含两端、
///     行优先于间隙），横向不可映射时为空；
///   - **学习段命中次序解析与最近段线解析**：[learningHitOrderAt]（单击那一份
///     认线与首尾线的命中窗，段体那一份只认段体）、[learningHitResolve]（带内
///     局部落点钳回带内后按段体解析）、[nearestSegmentLineIndex] /
///     [nearestSegmentLineOrFallback]（密集线取最近、未命中回落兜底下标）。
///
/// **内层算法仍归既有纯件**：学习段/分段线与首尾线的命中算法在横向几何值对象
/// [TrackBandGeometry]（其内委派 [resolveLearningTrackHit] 与段体解析），
/// 练习片段块命中在练习片段轨域公开的 [practiceClipHitAtLocal]，备注片段命中
/// 在备注轨域公开的 [noteRowHitAt]，局部镜像片段命中在局部镜像轨域公开的
/// [mirrorRowHitAt]——本层只装配入参、比较次序与委派，不含第二份判定式子。
///
/// ## 读面与依赖方向（单向）
///
/// 读面来自四处：**引擎接缝**（[PlaybackEngine.duration]，总时长的唯一来源）、
/// **会话域窗口读数** [window] 与**带宽** [width]（与轨道片头让位常量一起在
/// [geometry] 求值）、**轨道行表** [rowTable]，以及**数据快照**（标注时间线、
/// 练习片段、备注片段、镜像片段）。快照由带侧组装时现读给全——本层不持
/// provider 句柄、不碰构建上下文；全局坐标 → 带内局部坐标的换算也住在带侧
/// （它需要带级渲染盒），本层只收局部坐标。
///
/// **依赖方向单向**：适配层 → 三个行域（练习片段轨域 / 备注轨域 / 局部镜像轨
/// 域，只经它们公开的命中入口）+ 轨道行表 + 横向几何与时间纯件 + 引擎接缝 +
/// 标注纯件 + 集中视觉常量；**不 import 带级文件**（track_band.dart）、不
/// import 控制层 / 演出层 / 播放页——反向边只有轨道带一处组装本层。
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../annotation/annotation_timeline.dart';
import '../annotation/compare_materials.dart' show PracticeClip;
import '../annotation/learning_segments.dart';
import '../annotation/local_mirror.dart' show LocalMirrorFragment;
import '../annotation/note_sticker.dart' show NoteSticker;
import '../annotation/segment_hit.dart';
import '../core/playback/playback_engine.dart' show PlaybackEngine;
import 'track_geometry.dart';
import 'track_mirror_row.dart' show mirrorRowHitAt;
import 'track_note_row.dart' show noteRowHitAt;
import 'track_practice_row.dart' show practiceClipHitAtLocal;
import 'track_row_table.dart';
import 'track_time.dart';
import 'visual_tokens.dart' show kPreviewLineWidth;

/// 某个带内局部点落在哪个编辑目标（[TrackHitResolution.editTargetAt] 的答案；
/// 无目标以 `null` 表达）。
enum TrackEditTarget {
  /// 预览条（播放头贯穿全带高的命中列）。
  previewLine,

  /// 练习片段块（练习视频轨行内）。
  practiceClip,

  /// 分段线或视频首/尾线（命中带贯穿全带高）。
  segmentLine,

  /// 学习段体（只在学习段轨行内）。
  learningSegment,

  /// 备注片段（只在备注轨行内、且学习段轨命中为空时）。
  noteFragment,
}

/// 命中解析适配层：一次求值收一份读面（引擎 + 窗口 + 带宽 + 行表 + 数据
/// 快照 + 播放头显示值），其余问题都问它。
class TrackHitResolution {
  TrackHitResolution({
    required this.engine,
    required this.window,
    required this.width,
    required this.rowTable,
    required this.timeline,
    required this.clips,
    required this.notes,
    required this.mirrorFragments,
    required this.playhead,
  });

  /// 播放内核接缝：本层只读它的总时长 [PlaybackEngine.duration]。
  final PlaybackEngine engine;

  /// 生效可视窗口读数（null = 全宽 `0..total`；不合法窗口在 [geometry] 求值
  /// 时归一为全宽）。
  final TimelineWindow? window;

  /// 带内横向带宽（横向几何与全部命中换算的唯一尺度）。
  final double width;

  /// 本态行集（行归属的唯一来源）。
  final TrackRowTable rowTable;

  /// 生效标注时间线（学习段命中次序解析与备注/练习片段命中宽度的入参）。
  final AnnotationTimeline timeline;

  /// 练习视频轨在轨片段（练习片段块命中的候选）。
  final List<PracticeClip> clips;

  /// 备注轨在轨片段（备注片段命中的候选）。
  final List<NoteSticker> notes;

  /// 局部镜像轨在轨片段（镜像片段命中的候选）。
  final List<LocalMirrorFragment> mirrorFragments;

  /// 预览条显示位置（拖动中 = 拖动目标）。
  final Duration playhead;

  /// 本层求出的横向几何：总时长、窗口、带宽与轨道片头让位的唯一合成点——
  /// 「没有可映射几何」只由 [TrackBandGeometry.isMappable] 一种谓词表达。
  late final TrackBandGeometry geometry = TrackBandGeometry.eval(
    total: engine.duration,
    window: window,
    width: width,
    prefixWidth: kTrackPrefixWidth,
  );

  /// 编辑内容判定中枢：局部点 → 目标族（null = 空白/不可映射/轨道片头带/
  /// 带外）。次序 = 预览条 → 练习片段块 → 学习段轨命中 → 备注片段。
  TrackEditTarget? editTargetAt(Offset local) {
    if (local.dx < 0 || local.dx > width) return null;
    if (!geometry.isMappable) return null;
    // 轨道片头带（时间轴零点之左那一段）不是编辑内容。
    if (local.dx < geometry.contentLeft) return null;
    final axis = geometry.axis;
    final effectiveWindow = geometry.effectiveWindow;
    // 预览条（贯穿全带高的命中列）。
    if (effectiveWindow.contains(playhead) &&
        (axis.timeToX(playhead) - local.dx).abs() <= kPreviewLineWidth / 2) {
      return TrackEditTarget.previewLine;
    }
    // 练习片段块：块体命中即编辑内容。**先于**学习段轨命中——块体与学习段体
    // 的横向区间天然重叠，先按段体判会把块体当成空白。
    if (practiceClipAt(local) != null) {
      return TrackEditTarget.practiceClip;
    }
    final hit = geometry.learningHitAt(
      dx: local.dx,
      segmentLines: timeline.segmentLines,
      rangeStart: timeline.rangeStart,
      rangeEnd: timeline.rangeEnd,
      segments: deriveLearningSegments(timeline),
    );
    if (hit == null) {
      // 备注片段：与备注轨域的行级点按同一条命中解析（同一份函数、同一个
      // 窗口换算），只在备注行内算内容。
      if (isNoteRow(local.dy) &&
          noteRowHitAt(
                localX: local.dx,
                notes: notes,
                axis: axis,
                window: effectiveWindow,
              ) !=
              null) {
        return TrackEditTarget.noteFragment;
      }
      return null;
    }
    if (hit is SegmentHitTarget) {
      // 段体命中只在学习段轨行内是内容（命中扩展跨轨不吸收空白手势）。
      return isLearningRow(local.dy) ? TrackEditTarget.learningSegment : null;
    }
    // 分段线 / 视频首/尾线：命中带贯穿全带高。
    return TrackEditTarget.segmentLine;
  }

  /// 局部点是否压在局部镜像轨的片段上（该轨的编辑内容判定）：纵向落在局部
  /// 镜像轨行内、且经该轨公开的命中入口 [mirrorRowHitAt] 命中片段为真。
  bool mirrorContentAt(Offset local) {
    if (!isMirrorRow(local.dy)) return false;
    return mirrorRowHitAt(
          localX: local.dx,
          fragments: mirrorFragments,
          axis: geometry.axis,
          window: geometry.effectiveWindow,
        ) !=
        null;
  }

  /// 练习视频轨行内的片段命中（练习片段轨域公开入口 [practiceClipHitAtLocal]
  /// 的委派）：局部点 → 压在哪个练习片段上（null = 不在任何块上）。压在块上的
  /// 播放头竖线（落位取预览线位置那一问）与编辑内容判定共用本入口。
  PracticeClip? practiceClipAt(Offset local) => practiceClipHitAtLocal(
    local,
    axis: geometry.axis,
    rowTable: rowTable,
    clips: clips,
  );

  /// 某纵向局部坐标落在哪一行；几何不可映射、落在行间隙或带外时为空。行归属
  /// 委派轨道行表 [rows]（表的口径：行区间含两端、行优先于间隙）。
  TrackRowId? rowAt(double dy) => geometry.rowAt(dy, rows: rowTable);

  /// 局部纵坐标是否落在学习段轨行内（分段线/首尾线之外的段体判定用它）。
  bool isLearningRow(double dy) => rowAt(dy) == TrackRowId.learning;

  /// 局部纵坐标是否落在**备注轨行内容**内：行身份问行表，行内口径取该行内容件
  /// 的盒口径——半开区间 `[行顶, 行底)`，行底那一条线归下一段（行间隙或下一
  /// 行）。备注片段的块体、文本与命中层都按半开盒参与命中，本谓词与它们同源。
  bool isNoteRow(double dy) =>
      rowAt(dy) == TrackRowId.note &&
      dy < rowTable.rectOf(TrackRowId.note).bottom;

  /// 局部纵坐标是否落在局部镜像轨行内。
  bool isMirrorRow(double dy) => rowAt(dy) == TrackRowId.localMirror;

  /// 学习段命中次序解析：局部点 → 命中段序（null = 未命中）。未命中 = 学习
  /// 段轨行外、区间外、无可派生学习段、几何不可映射，或命中给了线与首尾线而
  /// 非段体（[segmentBodyOnly] 假时线 > 段体）。
  ///
  /// [segmentBodyOnly] 真 = 按段体解析（长按圈选的起手与逐帧走这条）：跨过分段
  /// 线连续解析到相邻段、不停顿。[spanClamped] = 落点时间已越过首段段首或末段
  /// 段尾起点（本帧钳在首/末段）。
  ({int? order, bool spanClamped}) learningHitOrderAt(
    Offset local, {
    Duration? lineHalfWidth,
    bool segmentBodyOnly = false,
  }) {
    const noHit = (order: null, spanClamped: false);
    if (!geometry.isMappable) return noHit;
    if (!isLearningRow(local.dy)) return noHit;
    final axis = geometry.axis;
    final segments = deriveLearningSegments(timeline);
    if (segments.isEmpty) return noHit;
    final dx = local.dx.clamp(0.0, width).toDouble();
    final time = axis.xToTime(dx);
    if (time < timeline.rangeStart || time >= timeline.rangeEnd) return noHit;
    if (segmentBodyOnly) {
      // 段体解析在区间内恒有候选（段首尾相接，最小命中宽只扩不缩）。
      final segment = geometry.learningSegmentHitAt(dx: dx, segments: segments);
      return (
        order: segment?.segmentOrder,
        // 落点越过首段段首/末段段尾起点 = 本帧已钳在首/末段。
        spanClamped:
            time <= segments.first.start || time >= segments.last.start,
      );
    }
    final hit = geometry.learningHitAt(
      dx: dx,
      segmentLines: timeline.segmentLines,
      rangeStart: timeline.rangeStart,
      rangeEnd: timeline.rangeEnd,
      segments: segments,
      // 窗外回落命中时线带同用收窄后的触发窗（真实段优先）。
      narrowedLineHalfWidth: lineHalfWidth,
    );
    if (hit is SegmentHitTarget) {
      return (order: hit.segmentOrder, spanClamped: false);
    }
    return noHit;
  }

  /// 学习段命中解析（带内局部落点）：横向钳回带内右缘内 0.01px 后按段体解析
  /// ——长按圈选的起手/逐帧/滚屏共用。[atSpanEdge] = 落点已钳在首/末段（继续
  /// 滚屏不可能再圈进新段）。
  ({int? order, bool atSpanEdge}) learningHitResolve(Offset local) {
    final dx = local.dx
        .clamp(0.0, math.max(0.0, width - 0.01))
        .toDouble();
    final hit = learningHitOrderAt(
      Offset(dx, local.dy),
      segmentBodyOnly: true,
    );
    return (order: hit.order, atSpanEdge: hit.spanClamped);
  }

  /// 横向局部像素命中的分段线下标（密集线取最近一条；未命中为空）。内层算法
  /// 仍归横向几何值对象的 [TrackBandGeometry.learningHitAt]。
  int? nearestSegmentLineIndex(double dx) {
    final hit = geometry.learningHitAt(
      dx: dx,
      segmentLines: timeline.segmentLines,
      rangeStart: timeline.rangeStart,
      rangeEnd: timeline.rangeEnd,
      segments: deriveLearningSegments(timeline),
    );
    return hit is SegmentLineHitTarget ? hit.lineIndex : null;
  }

  /// 最近分段线下标，未命中时回落到命中层携带的下标 [fallbackIndex]。
  int nearestSegmentLineOrFallback(int fallbackIndex, double dx) =>
      nearestSegmentLineIndex(dx) ?? fallbackIndex;
}
