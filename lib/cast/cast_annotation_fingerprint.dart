/// **标注内容**的指纹（纯件）：把影响**投屏渲染**的那几件标注事实折成一条
/// 16 位十六进制串，进缓存键的最后一个分量。
///
/// ## 收哪些、不收哪些
///
/// 收：分段线与半拍线、首尾区间、备注（文本 / 时间窗 / 几何）、局部镜像片段、
/// 舞者名册（贴纸着色），以及节拍的**内容**——拍点序列、平移、倍频、八拍锚点。
/// 这一堆正好是「改一次产物就得重做」的那些。
///
/// 不收：节拍识别的**时间**与**模型名**（换了识别时间但拍点逐位相同，产物
/// 不变，不该因此重渲），以及视频时长之外的任何文件元数据。
///
/// 判据取「**宁多收一项，不少收一项**」：多收只会多渲一次，少收会把一份过时
/// 的副本当成新的投出去。
///
/// ## 边界
///
/// 指纹是**内容**的函数，与盘上文件、会话身份、渲染设置无关；同一份标注内容
/// 无论何时算都是同一个指纹。
library;

import 'dart:convert';

import '../annotation/annotation_timeline.dart';
import '../annotation/dancer_roster.dart';
import '../core/local_mirror_fragment.dart';
import '../annotation/note_sticker.dart';
import '../core/video_identity.dart' show XxHash64;
import '../persistence/marker_document.dart' as marker_doc;

/// 影响投屏渲染的标注事实（各域读面装配成这一份）。
class CastAnnotationFacts {
  const CastAnnotationFacts({
    required this.timeline,
    this.notes = const [],
    this.mirrorFragments = const [],
    this.roster = const [],
    this.beatGrid,
  });

  /// 标注时间线（首尾区间 + 分段线 + 半拍线）。
  final AnnotationTimeline timeline;

  /// 备注贴纸。
  final List<NoteSticker> notes;

  /// 局部镜像片段。
  final List<LocalMirrorFragment> mirrorFragments;

  /// 舞者名册（贴纸着色）。
  final List<DancerRosterEntry> roster;

  /// 节拍网格文档（含平移、倍频与八拍锚点）；无节拍段时为 null。
  final marker_doc.BeatGrid? beatGrid;
}

/// 算一份标注内容指纹（16 位小写十六进制）。
String castAnnotationFingerprint(CastAnnotationFacts facts) {
  final canonical = jsonEncode(<String, Object?>{
    'duration': facts.timeline.videoDuration.inMilliseconds,
    'range': [
      facts.timeline.rangeStart.inMilliseconds,
      facts.timeline.rangeEnd.inMilliseconds,
    ],
    'segments': [
      for (final line in facts.timeline.segmentLines)
        [line.position.inMilliseconds, line.flagged],
    ],
    'halfBeats': [
      for (final line in facts.timeline.halfBeatLines)
        line.position.inMilliseconds,
    ],
    'notes': [for (final note in facts.notes) note.toJson()],
    'mirror': [for (final fragment in facts.mirrorFragments) fragment.toJson()],
    'roster': [for (final entry in facts.roster) entry.toJson()],
    'beat': _beatContent(facts.beatGrid),
  });
  return (XxHash64()..update(utf8.encode(canonical))).digest();
}

/// 节拍的**内容**投影：拍点、平移、倍频、八拍锚点（识别时间与模型名不收，
/// 它们不改产物）。
Object? _beatContent(marker_doc.BeatGrid? grid) {
  if (grid == null) return null;
  return <String, Object?>{
    'shift': grid.shift,
    'density': grid.density,
    'anchors': grid.anchors,
    'beats': [
      for (final beat in grid.beats) [beat.t, beat.down],
    ],
  };
}
