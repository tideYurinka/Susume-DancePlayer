import '../annotation/half_beat_line.dart';
import '../annotation/learning_segment_attributes.dart';
import '../annotation/local_mirror.dart';
import '../annotation/segment_line.dart';

/// 标注编辑提交链的三个段值（提交粒度 = 段）。
///
/// 段值是**绝对终值**（不是增量），与文件的段一一对应：
/// - [MarkerCorrectionsValue] → markers `corrections` 段（人工修正）；
/// - [MarkerAnnotationsValue] → markers `annotations` 段（标注产物）；
/// - [LocalSessionValue] → local `session` 段（保存编排唯一写入者）。
///
/// 编辑快照、净变化判定与保存编排的排队/写回都以段值为单位；
/// `videoDuration` 不属于任何段，因此结构性不参与净变化判定。

/// markers `corrections` 段值：节拍对齐平移量 + 节拍倍频 + 八拍锚点集合。
class MarkerCorrectionsValue {
  const MarkerCorrectionsValue({
    this.shiftSeconds = 0,
    this.density = 1,
    this.eightBeatAnchors = const [],
  });

  /// 节拍对齐平移量（秒，绝对终值）。
  final double shiftSeconds;

  /// 节拍倍频（派生拍数 ÷ 落盘拍数，五档 2 的幂；缺省 1 = 原样）。
  final double density;

  /// 八拍锚点集合（强拍拍序号，升序去重，绝对终值）。
  final List<int> eightBeatAnchors;

  @override
  bool operator ==(Object other) =>
      other is MarkerCorrectionsValue &&
      other.shiftSeconds == shiftSeconds &&
      other.density == density &&
      _listEquals(other.eightBeatAnchors, eightBeatAnchors);

  @override
  int get hashCode =>
      Object.hash(shiftSeconds, density, Object.hashAll(eightBeatAnchors));
}

/// markers `annotations` 段值：视频首尾 + 分段线 + 半拍线 + 重点 + 逐段
/// 档 + 局部镜像片段——一次编辑产生的公开标记侧段级变更整体。
///
/// 首尾持 `Duration`（微秒精度）：快照判等与 undo/redo 回放沿用内存态
/// 精度；毫秒量化只发生在落盘边界（文件 JSON 键为整数毫秒）。
class MarkerAnnotationsValue {
  const MarkerAnnotationsValue({
    this.rangeStart = Duration.zero,
    this.rangeEnd = Duration.zero,
    this.segmentLines = const [],
    this.halfBeatLines = const [],
    this.emphasizedSegments = const {},
    this.segmentDensities = const {},
    this.localMirrorFragments = const [],
  });

  final Duration rangeStart;

  final Duration rangeEnd;

  /// 全部分段线（时间点 + flag）。
  final List<SegmentLine> segmentLines;

  final List<HalfBeatLine> halfBeatLines;

  /// 置为「重点」的学习段段序集合。
  final Set<int> emphasizedSegments;

  /// 逐段档表（见词条「段内倍频」）：键为段
  /// 序、值为档位数值（0.5 / 2；原样不落键，绝对终值）。
  final Map<int, double> segmentDensities;

  /// 局部镜像片段列表（同表按 startMs 升序且两两不重叠）。
  final List<LocalMirrorFragment> localMirrorFragments;

  @override
  bool operator ==(Object other) =>
      other is MarkerAnnotationsValue &&
      other.rangeStart == rangeStart &&
      other.rangeEnd == rangeEnd &&
      _listEquals(other.segmentLines, segmentLines) &&
      _listEquals(other.halfBeatLines, halfBeatLines) &&
      other.emphasizedSegments.length == emphasizedSegments.length &&
      emphasizedSegments.containsAll(other.emphasizedSegments) &&
      _densitiesEquals(other.segmentDensities, segmentDensities) &&
      _listEquals(other.localMirrorFragments, localMirrorFragments);

  @override
  int get hashCode => Object.hash(
    rangeStart,
    rangeEnd,
    Object.hashAll(segmentLines),
    Object.hashAll(halfBeatLines),
    Object.hashAll(emphasizedSegments),
    Object.hashAll([
      for (final entry in segmentDensities.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)))
        Object.hash(entry.key, entry.value),
    ]),
    Object.hashAll(localMirrorFragments),
  );
}

/// local `session` 段值（绝对终值）：学习段熟练度全表 + 激活学习段集
/// 合（按段序）+ 激活练习片段 id（与学习段激
/// 活同段同口径）。写入路径有二（标注编辑提交链 / 激活集合模型），各自
/// 组装完整段值——路径互不覆盖靠「写入前读现值」保证。
class LocalSessionValue {
  const LocalSessionValue({
    this.mastery = const {},
    this.activatedSegments = const [],
    this.activePracticeClipId,
  });

  /// 学习段熟练度全表（按段序）。
  final Map<int, LearningMastery> mastery;

  /// 激活学习段段序集合（升序）。
  final List<int> activatedSegments;

  /// 激活练习片段 id（null = 无片段激活）。
  final String? activePracticeClipId;

  @override
  bool operator ==(Object other) {
    if (other is! LocalSessionValue) return false;
    if (other.mastery.length != mastery.length) return false;
    for (final entry in mastery.entries) {
      if (other.mastery[entry.key] != entry.value) return false;
    }
    return _listEquals(other.activatedSegments, activatedSegments) &&
        other.activePracticeClipId == activePracticeClipId;
  }

  @override
  int get hashCode => Object.hashAll([
    for (final entry in mastery.entries) Object.hash(entry.key, entry.value),
    Object.hashAll(activatedSegments),
    activePracticeClipId,
  ]);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 逐段档表的结构相等（键集与值逐项一致）。
bool _densitiesEquals(Map<int, double> a, Map<int, double> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
