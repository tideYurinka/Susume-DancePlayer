/// 对比练习纯域模块 · 概念面①素材与片段：素材记录值对象、练习片段
/// （素材引用 + 截取范围）与三条纯函数纪律——重叠清理（只作用于轨道
/// 引用）、截取吸附（经相位求值、异常自由）、激活互斥决策（激活源保持单值）。
///
/// 零框架依赖（不引 Flutter、不持有 IO、不读 provider），可在不启动
/// widget 环境的情况下直测。时间一律毫秒整数；源时间轴 = 被跟练视频的
/// 时间轴，素材内偏移经 [PracticeClip.materialSourceStartMs]
/// 与源时间轴换算（换算只在此处声明，消费方不各自重算）。
library;

import '../core/beat_grid.dart';
import '../core/eight_beat_phase.dart';
import 'interval_fragment_row.dart';

/// 一条练习素材（原始录像 + 元数据，不可变值对象；`lib/capture/CONTEXT.md`「练习素材」）。
/// 本模块只持有其内存值；文件落位与清单持久化归接线层。
class MaterialRecord {
  const MaterialRecord({
    required this.id,
    required this.videoId,
    required this.createdAt,
    required this.durationMs,
    required this.sourceStartMs,
    required this.fileName,
    required this.sizeBytes,
    this.extra = const {},
  });

  /// 素材 id（清单主键）。
  final String id;

  /// 所属舞的视频标识。
  final String videoId;

  /// 录制时刻。
  final DateTime createdAt;

  /// 素材时长（毫秒）。
  final int durationMs;

  /// 录制起始的源时间（毫秒；素材内偏移 0 对应的源时间轴位置）。
  final int sourceStartMs;

  final String fileName;

  /// 素材文件字节数。
  final int sizeBytes;

  /// 条目级陌生键保底区（原样带回、写回原样，不参与
  /// 相等比较）。内存构造恒空，仅清单编解码使用。
  final Map<String, Object?> extra;

  @override
  bool operator ==(Object other) =>
      other is MaterialRecord &&
      other.id == id &&
      other.videoId == videoId &&
      other.createdAt == createdAt &&
      other.durationMs == durationMs &&
      other.sourceStartMs == sourceStartMs &&
      other.fileName == fileName &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(
    id,
    videoId,
    createdAt,
    durationMs,
    sourceStartMs,
    fileName,
    sizeBytes,
  );
}

/// 练习视频轨上的一条练习片段 = 素材引用 + 截取范围（素材内 in/out 偏移）。
/// 位置固定不可拖动换位：源时间区间由 [materialSourceStartMs] + 偏移派生。
class PracticeClip {
  const PracticeClip({
    required this.id,
    required this.materialId,
    required this.materialSourceStartMs,
    required this.inMs,
    required this.outMs,
    this.materialDurationMs,
  });

  /// 片段 id（轨道引用主键，与素材 id 分立）。
  final String id;

  final String materialId;

  /// 片段读取的素材内容原点（素材内偏移 0 对应的源时间轴位置）：承接素材
  /// 记录的 [MaterialRecord.sourceStartMs]（= **起录点**，唯一对齐锚点）再
  /// **减去前言长度**——素材文件头部那一段是录制武装到起录点之间
  /// 录下的前言，故片段入点 = 前言长度时，[sourceStartMs] 正好回到起录点。
  final int materialSourceStartMs;

  /// 截取范围起点（素材内偏移，含）。
  final int inMs;

  /// 截取范围终点（素材内偏移，不含）。
  final int outMs;

  /// 引用素材的全长（毫秒；端点截取钳制域 `[0, materialDurationMs]` 的
  /// 依据——截取只改引用范围，放宽回去的合法上界是素材全长）。null =
  /// 早期引用未记录（回落 [outMs]，对应「未截取 = 全长」的既有条目）。
  final int? materialDurationMs;

  /// 端点截取的素材内偏移上界（[materialDurationMs] 缺失时回落 [outMs]）。
  int get materialDurationBoundMs => materialDurationMs ?? outMs;

  /// 显示/循环的源时间区间起点。
  int get sourceStartMs => materialSourceStartMs + inMs;

  /// 显示/循环的源时间区间终点。
  int get sourceEndMs => materialSourceStartMs + outMs;

  /// 录制完成即建 1:1 在轨片段（截取范围 = 素材全长 − 前言）。
  ///
  /// [preambleMs] = 起录武装录下的**前言**长度：它留在素材文件里
  /// 作对齐余量，但**不进片段定义**——入点 = 前言长度、出点 = 素材全长，
  /// 于是片段的源时间区间正好从**起录点**开始（素材记录的原点即起录点，
  /// 故片段侧的素材内容原点 = 起录点 − 前言长度）。
  factory PracticeClip.fullLength({
    required String id,
    required MaterialRecord material,
    int preambleMs = 0,
  }) {
    final inMs = practiceClipInMs(
      preambleMs: preambleMs,
      materialDurationMs: material.durationMs,
    );
    return PracticeClip(
      id: id,
      materialId: material.id,
      materialSourceStartMs: _contentOriginMs(material.sourceStartMs, inMs),
      inMs: inMs,
      outMs: material.durationMs,
      materialDurationMs: material.durationMs,
    );
  }

  /// 端点截取后的新引用（只改截取范围，素材不动）。
  PracticeClip trim({required int inMs, required int outMs}) => PracticeClip(
    id: id,
    materialId: materialId,
    materialSourceStartMs: materialSourceStartMs,
    inMs: inMs,
    outMs: outMs,
    materialDurationMs: materialDurationMs,
  );

  /// 元素自身的 JSON 读写（「元素类型自带读写」；随舞
  /// 私密 `prefs.practiceClips` 段字段的元素编解码收口在此）。
  Map<String, Object?> toJson() => {
    'id': id,
    'materialId': materialId,
    'materialSourceStartMs': materialSourceStartMs,
    'inMs': inMs,
    'outMs': outMs,
    if (materialDurationMs != null) 'materialDurationMs': materialDurationMs,
  };

  /// 结构读取：字段缺失或类型不符返回 null（调用方整条跳过）。
  static PracticeClip? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    final materialId = raw['materialId'];
    final materialSourceStartMs = raw['materialSourceStartMs'];
    final inMs = raw['inMs'];
    final outMs = raw['outMs'];
    final materialDurationMs = raw['materialDurationMs'];
    if (id is! String ||
        materialId is! String ||
        materialSourceStartMs is! int ||
        inMs is! int ||
        outMs is! int) {
      return null;
    }
    if (materialDurationMs != null && materialDurationMs is! int) {
      return null;
    }
    return PracticeClip(
      id: id,
      materialId: materialId,
      materialSourceStartMs: materialSourceStartMs,
      inMs: inMs,
      outMs: outMs,
      materialDurationMs: materialDurationMs as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeClip &&
      other.id == id &&
      other.materialId == materialId &&
      other.materialSourceStartMs == materialSourceStartMs &&
      other.inMs == inMs &&
      other.outMs == outMs &&
      other.materialDurationMs == materialDurationMs;

  @override
  int get hashCode => Object.hash(
    id,
    materialId,
    materialSourceStartMs,
    inMs,
    outMs,
    materialDurationMs,
  );

  @override
  String toString() => 'PracticeClip($id, $materialId, $inMs..$outMs)';
}

/// 每舞「自动删除」预留设置：默认关；策略 = 保留最近
/// N 条或 N 天；UI 与执行归首页舞详情，本库只落字段与默认值。
enum MaterialAutoDeleteStrategy { keepRecentCount, keepRecentDays }

/// 默认保留条数（30 条）与保留天数（90 天）。
const int kDefaultMaterialAutoDeleteKeepCount = 30;
const int kDefaultMaterialAutoDeleteKeepDays = 90;

class MaterialAutoDeleteSettings {
  const MaterialAutoDeleteSettings({
    this.enabled = false,
    this.strategy = MaterialAutoDeleteStrategy.keepRecentCount,
    this.keepCount = kDefaultMaterialAutoDeleteKeepCount,
    this.keepDays = kDefaultMaterialAutoDeleteKeepDays,
  });

  final bool enabled;

  final MaterialAutoDeleteStrategy strategy;

  /// 保留最近条数。
  final int keepCount;

  /// 保留最近天数。
  final int keepDays;

  @override
  bool operator ==(Object other) =>
      other is MaterialAutoDeleteSettings &&
      other.enabled == enabled &&
      other.strategy == strategy &&
      other.keepCount == keepCount &&
      other.keepDays == keepDays;

  @override
  int get hashCode => Object.hash(enabled, strategy, keepCount, keepDays);
}

/// 重叠清理：新录制片段的源时间区间 [newSourceSpan]
/// 入轨后，清理已有轨道引用——被完全覆盖的旧引用删除、部分重叠的裁到
/// 不重叠（裁后无单一不重叠区间的照删）；素材与库内条目不参与、不动。
/// 输入表原样保留顺序，返回新表（不改传入对象）。
List<PracticeClip> pruneClipsOverlappedBy(
  List<PracticeClip> clips,
  IntervalSpan newSourceSpan,
) {
  return [
    for (final clip in clips) ?pruneClipOverlappedBy(clip, newSourceSpan),
  ];
}

/// 单条引用对 [newSpan] 的重叠清理（表规范化经它逐条复用入轨的
/// 同一套口径，不另造判据）。
PracticeClip? pruneClipOverlappedBy(PracticeClip clip, IntervalSpan newSpan) {
  final cs = clip.sourceStartMs;
  final ce = clip.sourceEndMs;
  if (ce <= newSpan.startMs || cs >= newSpan.endMs) return clip; // 无重叠
  final coveredInside = cs >= newSpan.startMs && ce <= newSpan.endMs;
  // 完全覆盖，或新旧互罩（裁不出单一不重叠区间）→ 删除引用。
  if (coveredInside || (cs < newSpan.startMs && ce > newSpan.endMs)) {
    return null;
  }
  if (cs < newSpan.startMs) {
    // 左悬：右端裁到新片段起点。
    return clip.trim(
      inMs: clip.inMs,
      outMs: clip.outMs - (ce - newSpan.startMs),
    );
  }
  // 右悬：左端裁到新片段终点。
  return clip.trim(inMs: clip.inMs + (newSpan.endMs - cs), outMs: clip.outMs);
}

/// 截取端点吸附：素材内偏移换算到源时间轴后经**相位值
/// 对象**求就近八拍点（相位入参必填——锚点重定相与无锚自动相位同源求值，
/// 不出现按裸网格求八拍点的第二口径）；无八拍点（异常网格）自由、原样
/// 返回；结果换算回素材内偏移并钳在 `[0, materialDurationMs]` 内。
/// 单位与本文件其余时间值一致为毫秒整数。
int snapTrimOffsetMs({
  required int offsetInMaterialMs,
  required int materialSourceStartMs,
  required int materialDurationMs,
  required BeatPhase phase,
}) {
  final snapped =
      phase.nearest(
        Duration(milliseconds: materialSourceStartMs + offsetInMaterialMs),
      ) ??
      Duration(milliseconds: materialSourceStartMs + offsetInMaterialMs);
  final offset = snapped.inMilliseconds - materialSourceStartMs;
  if (offset < 0) return 0;
  if (offset > materialDurationMs) return materialDurationMs;
  return offset;
}

/// 对比态循环激活源（片段 ↔ 学习段 ↔ 临时衔接段三
/// 者互斥，激活源保持单值）。
sealed class CompareLoopSource {
  const CompareLoopSource();
}

/// 学习段激活（连续合并循环，沿用既有段激活语义）。
class LearningSegmentLoop extends CompareLoopSource {
  const LearningSegmentLoop({required this.orders});

  /// 激活的学习段序集合。
  final Set<int> orders;
}

/// 临时衔接段激活。
class TransitionSegmentLoop extends CompareLoopSource {
  const TransitionSegmentLoop();
}

/// 练习片段激活（片段区间 AB 循环回看）。
class PracticeClipLoop extends CompareLoopSource {
  const PracticeClipLoop({required this.clipId});

  final String clipId;
}

/// 对比态激活源单值快照（任一时刻三个面至多一个成立）。
class CompareActivationState {
  const CompareActivationState({
    this.learningOrders = const {},
    this.transitionActive = false,
    this.practiceClipId,
  });

  final Set<int> learningOrders;

  final bool transitionActive;

  final String? practiceClipId;

  bool get isEmpty =>
      learningOrders.isEmpty && !transitionActive && practiceClipId == null;
}

/// 激活互斥决策：在现值上应用一次激活请求，返回新单值——激活任一面
/// 自动清除另两面；请求为 null = 显式清除（清激活路径）。纯决策，写点
/// 归接线层。
CompareActivationState applyCompareActivation({
  required CompareActivationState current,
  required CompareLoopSource? requested,
}) {
  if (requested == null) return const CompareActivationState();
  return switch (requested) {
    LearningSegmentLoop(:final orders) => CompareActivationState(
      learningOrders: Set.unmodifiable(orders),
    ),
    TransitionSegmentLoop() => const CompareActivationState(
      transitionActive: true,
    ),
    PracticeClipLoop(:final clipId) => CompareActivationState(
      practiceClipId: clipId,
    ),
  };
}

/// 进度拖出片段范围清激活（与学习段同规则：端点仍属范围）。未激活片段
/// 或仍在范围内返回现值，拖出返回 null。
PracticeClipLoop? clipActivationAfterSeek({
  required PracticeClipLoop? active,
  required int positionMs,
  required IntervalSpan clipRange,
}) {
  final inside =
      positionMs >= clipRange.startMs && positionMs <= clipRange.endMs;
  return active != null && inside ? active : null;
}

/// 录制准备前导计划：从 [leadStartMs] 起播
/// [leadDurationMs] 后到 [startPointMs] 起录；[beatLed] = 节拍前导
/// （复用循环前导的机制与视觉），false = 无节拍前导（秒制兜底或无可用拍点：
/// 无节拍器/数字/声）。
class RecordingPrepPlan {
  const RecordingPrepPlan({
    required this.startPointMs,
    required this.leadStartMs,
    required this.leadDurationMs,
    required this.beatLed,
    this.beatTimesMs = const [],
  });

  /// 起录点（激活段 = 段首；无激活段 = 按下位置）。
  final int startPointMs;

  /// 前导起播点（回退截断后不早于有效区间头）。
  final int leadStartMs;

  /// 前导时长（毫秒；0 = 到点即起录）。
  final int leadDurationMs;

  /// 是否节拍前导（网格就绪且起录点前有可用真实拍点）。
  final bool beatLed;

  /// 准备拍点（毫秒、升序）：起录点前**可用的真实拍点**（派生网格）里最后
  /// 至多 N 拍——不足 N 拍时就是全部可用拍点（**有几拍数几拍**）。
  /// [beatLed] 为真时非空；秒制兜底/无可用拍点/无前导时为空。
  ///
  /// 这是准备期**数字与拍声共同的唯一来源**（数字由它 + 媒介位置派生，
  /// 拍声由决策层按同一派生网格排程）。
  final List<int> beatTimesMs;
}

/// 无激活段起录判定（延迟准备改起点）：给定按下位置、有效区间头尾与
/// 拒录阈值（一拍时长），交出
/// **起录点**与**是否可录**。有激活段的另一支不走这里（起点 = 段首，见
/// `CompareRecordingController`）。
class RecordingStartDecision {
  const RecordingStartDecision({
    required this.startPointMs,
    required this.recordable,
  });

  /// 起录点：当前相位下最近的八拍点（可能落在按下位置之前半个八拍内）；
  /// 相位不可用时按下位置原样；早于有效区间头时取区间头（起点前没有可播
  /// 的余量）。
  final int startPointMs;

  /// 可录 = false 即**拒录**：距有效区间尾不足一拍、或已在尾线（含恰在
  /// 尾线）——按下即会落一条近 0 长的素材与片段，故不起录、不落素材、
  /// 不落片段。
  final bool recordable;
}

/// 无激活段起录点与拒录判定（改
/// 起点）：起点 = 当前相位下最近的八拍点（[BeatPhase.nearest]，等距并列取
/// 靠后——可能落在按下位置之前半个八拍内），相位不可用（占位/异常网格不
/// 产生八拍点）时按下位置原样；早于有效区间头时钳到区间头。起录点距有效
/// 区间尾不足 [minTailMs]、或起录点已在尾线之上（含恰在尾线）即拒录——
/// **不足**一拍才拒，恰好一拍仍可录；判定随**新起录点**（吸附后）落定。
///
/// [minTailMs] 是**一拍时长**（阈值由调用侧传入的入参，不写死在会话里）；
/// 有效区间尾读不到（`<= 0`）时不拒录——那一支的终点交**物理尾**兜底。
RecordingStartDecision computeRecordingStart({
  required int pressPositionMs,
  required int rangeStartMs,
  required int rangeEndMs,
  required int minTailMs,
  // 显式必填（可空）：调用方必须表态「传不传相位」，漏传不得静默落进
  // 退化口径（见词条「八拍点」的同款防呆；null 本身 = 占位/异常网格）。
  required BeatPhase? phase,
}) {
  final snapped = phase
      ?.nearest(Duration(milliseconds: pressPositionMs))
      ?.inMilliseconds;
  var startPointMs = snapped ?? pressPositionMs;
  if (startPointMs < rangeStartMs) startPointMs = rangeStartMs;
  // 恰在尾线与尾线之后一律拒录（`<` 那一半管住阈值为 0 的退化入参）。
  final recordable =
      rangeEndMs <= 0 ||
      (startPointMs < rangeEndMs && startPointMs + minTailMs <= rangeEndMs);
  return RecordingStartDecision(
    startPointMs: startPointMs,
    recordable: recordable,
  );
}

/// 秒制兜底前导时长。
const int kRecordingPrepFallbackMs = 4000;

/// 录制武装余量：
/// 起录点前约 600ms 武装编码器，保证越过起录点时编码器早在写、起录点那
/// 一帧必然入素材。**可调常量、不是规格真理**——真机实测重配更慢就改这里
/// （判据「素材第一帧 = 起录点画面」不改）。
const int kRecordingArmMarginMs = 600;

/// 素材内容原点（素材内偏移 0 对应的源时间轴位置）：素材记录的原点是
/// **起录点**，而文件头那一段是武装到起录点之间录下的前言，故内容原点 =
/// 起录点 − 前言长度。
///
/// 钳 0 的那一支是**武装比余量还慢**的病态路径：编码器在越过起录点之后才
/// 开始写，素材头本身就晚于起录点（该改的是武装余量常量，不是判据）——
/// 那时能给的只有文件里最早的画面，即原点 0。
int _contentOriginMs(int startPointMs, int preambleMs) {
  final origin = startPointMs - preambleMs;
  return origin < 0 ? 0 : origin;
}

/// 起录武装点换算：武装点 = 起录点 − [armMarginMs]，**钳到
/// 有效区间头**——起点前余量不足时不越过区间头（余量随之缩短到实有余量，
/// 无余量可退时武装点即起录点，走无前导路径）。
///
/// 只交武装点：**前言长度不进这里**——它是「武装到起录点之间**录下的**那段」
/// 与计划余量差着一个「武装落定耗时」，
/// 故由会话在起录点那一刻实测（见 `CompareRecordingController`），计划的余量
/// 不是前言。
int computeRecordingArmPoint({
  required int startPointMs,
  required int rangeStartMs,
  int armMarginMs = kRecordingArmMarginMs,
}) {
  final room = startPointMs - rangeStartMs;
  if (room <= 0 || armMarginMs <= 0) return startPointMs;
  return startPointMs - (armMarginMs < room ? armMarginMs : room);
}

/// 片段入点换算：入点 = **前言长度**（素材内偏移），钳到素材真实
/// 编码时长（前言不会长到越过素材尾）。
int practiceClipInMs({
  required int preambleMs,
  required int materialDurationMs,
}) {
  if (preambleMs <= 0) return 0;
  return preambleMs > materialDurationMs ? materialDurationMs : preambleMs;
}

/// 起录点前可用的真实拍点（毫秒、升序、至多 [prepBeats] 拍）：自起录点向前
/// **逐拍回溯**，越出有效区间头即止（「锚点前 N 拍回退」）。
///
/// - 拍点严格早于起录点：起录点那一拍属正式数拍（1｜1），不算准备拍。
/// - 拍长取自**网格自身**：变拍长网格上回退的仍是 N 个真实拍点，不按名义
///   拍长折算（不取「整曲第 0→1 拍间隔」这类常量——变拍长即错）。
/// - 起录点前可用真实拍点少于 [prepBeats] 时返回这些拍点本身——调用侧
///   「有几拍数几拍」，不整块静默。
List<int> recordingPrepBeatTimes({
  required BeatGrid grid,
  required int startPointMs,
  required int rangeStartMs,
  required int prepBeats,
}) {
  if (prepBeats <= 0 || startPointMs <= rangeStartMs) return const [];
  var index = grid.beatIndexAt(Duration(milliseconds: startPointMs - 1));
  final times = <int>[];
  while (index >= 0 && times.length < prepBeats) {
    final ms = grid.beatTime(index).inMilliseconds;
    if (ms < rangeStartMs) break;
    if (ms < startPointMs) times.add(ms);
    index--;
  }
  return times.reversed.toList(growable: false);
}

/// 录制准备前导计算：起点前 N 拍回退（N = 录制准备
/// 拍数，独立设置项、默认 8，与循环前导拍档无关）；回退点 = 起录点前第 N 个
/// **真实拍点**（有几个用几个），回退在有效区间内截断。
///
/// 三支可分辨的状态：
/// - 秒制兜底网格（异常态）→ 秒制兜底（≈4s 并在有效区间内截断、无节拍、
///   无数字、无声）；
/// - 起录点前有可用拍点（哪怕少于 N 拍；占位均匀网格照常给出拍点）→
///   **节拍前导**：拍点序列交给准备期，数字与拍声同源同步；
/// - 起点即区间头，或起录点前**一个真实拍点都没有**（含 `prepBeats = 0`，
///   语义同「循环前导：不前导」）→ 无前导：无数字、无声、到点即起录。
///
/// 判据上移进纯件：[grid] 收**非空**网格，先判
/// [BeatGridReads.isSecondsFallback] 再算真实拍点——「无网格」不用空值
/// 编码。秒制兜底常量 [kRecordingPrepFallbackMs] 是「录制准备」自己的
/// ≈4 秒，语义与八拍标称不是同一规则，原地不动。
RecordingPrepPlan computeRecordingPrep({
  required int startPointMs,
  required int rangeStartMs,
  required int prepBeats,
  required BeatGrid grid,
}) {
  final room = startPointMs - rangeStartMs;
  if (room <= 0) {
    return RecordingPrepPlan(
      startPointMs: startPointMs,
      leadStartMs: startPointMs,
      leadDurationMs: 0,
      beatLed: false,
    );
  }
  if (grid.isSecondsFallback) {
    // 秒制兜底：≈4s 并在有效区间内截断、无节拍、无数字、无声。
    final fallbackMs = kRecordingPrepFallbackMs < room
        ? kRecordingPrepFallbackMs
        : room;
    return RecordingPrepPlan(
      startPointMs: startPointMs,
      leadStartMs: startPointMs - fallbackMs,
      leadDurationMs: fallbackMs,
      beatLed: false,
    );
  }
  final times = recordingPrepBeatTimes(
    grid: grid,
    startPointMs: startPointMs,
    rangeStartMs: rangeStartMs,
    prepBeats: prepBeats,
  );
  if (times.isEmpty) {
    // 有网格但起录点前无可数拍点（含 prepBeats = 0 → 本就不该有准备拍）：
    // 无前导——无数字、无声、到点即起录，不退化成秒制兜底的「整块静默」。
    return RecordingPrepPlan(
      startPointMs: startPointMs,
      leadStartMs: startPointMs,
      leadDurationMs: 0,
      beatLed: false,
    );
  }
  return RecordingPrepPlan(
    startPointMs: startPointMs,
    leadStartMs: times.first,
    leadDurationMs: startPointMs - times.first,
    beatLed: true,
    beatTimesMs: times,
  );
}
