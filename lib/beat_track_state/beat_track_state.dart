/// beat_track_state 小库（标注编辑模块依赖的 beat 侧跨接，自足、无环）：
/// 节拍轨三态、已应用移位读写、对齐试听预览，以及 ** 起的八拍锚点
/// 写读面与八拍相位派生读取点**（[appliedEightBeatAnchors] /
/// [writeEightBeatAnchors] / [beatPhaseProvider]——锚点与相位同属 beat 侧
/// 网格事实，与移位同档承载，不新建库）。前段为自 beat 分析域纯搬移（符号
/// 名、语义、provider 身份全保留），后段为本 feature 新增。只依赖共享内核
/// 与节拍文档类型（含 core 相位求值），不依赖标注模块与 hub。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/beat_grid.dart';
import '../core/document_beat_grid.dart';
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../persistence/marker_document.dart' as marker_doc show BeatGrid;

/// 节拍轨三态（`lib/beat/CONTEXT.md` 词条）：
///
/// - [BeatTrackPhase.placeholder] 占位：分析中/未开始——节拍轨整行
///   不定态进度条（不画均匀占位刻度）；网格 seam 沿用均匀
///   占位实现（既有 demoBpm 语义）供吸附/拍制计时消费；
/// - [BeatTrackPhase.ready] 就绪：真实网格已落盘——拍时刻刻度 +
///   downbeat 强调；
/// - [BeatTrackPhase.error] 异常：本次分析失败——节拍轨整行暖色底
///   「节拍识别失败」（不画刻度）、吸附停用（用户偏好保留）、
///   拍制计时走秒制兜底。
enum BeatTrackPhase { placeholder, ready, error }

/// 节拍轨状态：阶段 + 就绪时的 markers `beat` 段文档。
class BeatTrackState {
  const BeatTrackState._(this.phase, this.grid);

  const BeatTrackState.placeholder() : this._(BeatTrackPhase.placeholder, null);
  const BeatTrackState.ready(marker_doc.BeatGrid grid)
    : this._(BeatTrackPhase.ready, grid);
  const BeatTrackState.error() : this._(BeatTrackPhase.error, null);

  final BeatTrackPhase phase;

  /// 就绪态的真实网格文档（其余态为 null）。
  final marker_doc.BeatGrid? grid;
}

/// 节拍轨状态模型：默认占位态；打开恢复按 markers 是否已有 beat 置
/// 就绪/占位，分析完成置就绪、失败置异常（新视频打开复位占位）。
class BeatTrackStateModel extends Notifier<BeatTrackState> {
  @override
  BeatTrackState build() => const BeatTrackState.placeholder();

  void _ready(marker_doc.BeatGrid grid) => replace(BeatTrackState.ready(grid));

  /// 整体替换节拍轨状态：本库全部写缝的唯一收口——打开恢复（占位/
  /// 就绪）、分析完成（就绪）/失败（异常）、新视频打开复位占位、写定
  /// 移位（经 [_ready]）与 widget 测试注入三态，均最终经本方法赋值。
  void replace(BeatTrackState value) => state = value;
}

final beatTrackStateProvider =
    NotifierProvider<BeatTrackStateModel, BeatTrackState>(
      BeatTrackStateModel.new,
    );

/// 公开 beat 段已应用平移量（秒）：就绪网格文档携带；占位/异常
/// 无 beat 段，恒 0（不适用）。
double appliedBeatShiftSeconds(Ref ref) {
  return ref.read(beatTrackStateProvider).grid?.shift ?? 0;
}

/// 三写缝共用收口：读就绪网格 → 无 beat 段即 no-op → 求新值 → 未变即
/// no-op（BeatGrid 的 == 已含 anchors 深比较，不另写比较形状）→ 写定会话
/// 内存态（[BeatTrackStateModel._ready]）。
void _updateBeatGrid(
  Ref ref,
  marker_doc.BeatGrid Function(marker_doc.BeatGrid grid) update,
) {
  final grid = ref.read(beatTrackStateProvider).grid;
  if (grid == null) return;
  final next = update(grid);
  if (next == grid) return;
  ref.read(beatTrackStateProvider.notifier)._ready(next);
}

/// 写定公开 beat 段平移量（秒）：会话内存态（就绪文档）即时生效；
/// 落盘经保存编排的字段级 diff 由标注编辑模块提交点钩子完成。无 beat 段
/// 或值未变时 no-op（应用命令与撤销/重做回放共用同一写缝）。
void writeAppliedBeatShift(Ref ref, double shiftSeconds) {
  _updateBeatGrid(ref, (grid) => grid.withShift(shiftSeconds));
}

/// 公开 beat 段八拍锚点（拍序号数组，升序去重）：就绪
/// 网格文档携带；占位/异常无 beat 段，恒空（不适用）。语义见
/// [marker_doc.BeatGrid.anchors] 与 [BeatPhase]。
List<int> appliedEightBeatAnchors(Ref ref) {
  return ref.read(beatTrackStateProvider).grid?.anchors ?? const [];
}

/// 写定公开 beat 段八拍锚点：会话内存态（就绪文档）即时生效；
/// 落盘经保存编排的字段级 diff 由标注编辑模块提交点钩子完成。无 beat 段
/// 或集合未变时 no-op（落锚命令与撤销/重做回放共用同一写缝，与
/// [writeAppliedBeatShift] 同一纪律）。
void writeEightBeatAnchors(Ref ref, List<int> anchors) {
  _updateBeatGrid(ref, (grid) => grid.withAnchors(anchors));
}

/// 公开 beat 段节拍倍频：就绪网格文档携带；占位/
/// 异常无 beat 段，恒 1（原样，不适用）。
double appliedBeatDensity(Ref ref) {
  return ref.read(beatTrackStateProvider).grid?.density ?? 1;
}

/// 写定公开 beat 段节拍倍频：会话内存态（就绪文档）即时生效；
/// 落盘经保存编排的字段级 diff 由标注编辑模块提交点钩子完成。无 beat 段
/// 或值未变时 no-op（倍频命令与撤销/重做回放共用同一写缝，与
/// [writeAppliedBeatShift] 同一纪律）。
void writeAppliedBeatDensity(Ref ref, double density) {
  _updateBeatGrid(ref, (grid) => grid.withDensity(density));
}

/// 八拍相位派生读取点：由「派生网格 + 公开 beat 段锚点」求值的**单一相位
/// 事实源**——消费方只读本 provider，不各自实现相位。网格随派生面（就绪/
/// 占位/异常三态 + 节拍对齐预览偏移）实时跟随；占位/异常态无锚点（beat 段
/// 不存在），相位即默认口径。
///
/// **跟锚点的消费方（显式清单）**——新增消费者必须显式接线、
/// 不得自行实现相位：
///
///   - 轨道三级刻度分级（[beatTrackTicks] 的 `phase` 入参）；
///   - 轨上八拍数小数字（[beatEightCountLabels] 的 `phase` 入参；与大线同
///     相位）；
///   - 分段线插入/拖动落点吸附（[AnnotationEditor] 内 `BeatPhase.nearest`）；
///   - 局部镜像片段创建起点取整（[AnnotationEditor] 创建 verb 的起点，经
///     [beatPhaseProvider] 求值；默认宽仍固定 8 拍，端点另吸真实拍点）；
///   - 待命态预览线强拍吸附（`annotation/downbeat_snap.dart`，与相位无关的
///     强拍解析——锚点只决定"哪根强拍是八拍点"）；
///   - 数拍八拍号（`metronome_overlay.dart` 的 `deriveBeatCount` 的 `phase`
///     入参，观看态经 `player_page.dart` 注入）；
///   - 节拍动画八拍首与游标格（`beat_animation.dart` 的 `deriveBeatPhase` /
///     [MetronomeBeatAnimation] 的 `phase` 入参；强拍走
///     [BeatPhase.isStrongBeat] 一条判定）；
///   - 学习段段内八拍数（[segmentEightBeatCount] 的 `phase` 入参；与大线同
///     相位，按八拍点区间加权求 0.5 分度值）；
///   - 自动分段切割线（`deriveAutoSegmentCuts` 的 `phase` 入参；切割线按
///     「每段 4 个整八拍区间」顺延）；
///   - 临时衔接段起点取整（`annotation/transition_segment.dart` 的 `phase`
///     入参；起点截断优先于网格，其余语义不变）。
///
/// **不跟锚点的消费方**（明确不接相位）：循环前导（按 N 拍换算）、
/// 局部镜像片段端点（吸真实拍点）、音画同步会话网格 BPM（读单拍拍距）。
/// 练舞统计不在此清单——其记账单位是**四拍桶**：桶键 = 绝对四拍序号（自整曲
/// 首个强拍起数，**不消费八拍点**），见 `lib/stats/CONTEXT.md`「四拍桶」词条
///（记账契约；与相位口径正交），不属任何一侧。
///
/// **延迟播放接相位**：控制器注入相位来源，起点 = 当前相位下最近的八拍点。
final beatPhaseProvider = Provider<BeatPhase>((ref) {
  final grid = ref.watch(beatGridProvider);
  final anchors =
      ref.watch(beatTrackStateProvider).grid?.anchors ?? const <int>[];
  return BeatPhase(grid: grid, anchors: anchors);
});

/// 节拍预览值的会话态（对齐偏移秒 / 倍频档共用一个持有形状）：null =
/// 无预览。
class BeatPreviewModel extends Notifier<double?> {
  @override
  double? build() => null;

  void set(double? value) => state = value;
}

/// 节拍对齐预览偏移（秒，面板 ±/重置写入的会话态）：null =
/// 无预览。预览只改派生网格（实时跟随），不改已落盘线、不写盘；应用
/// 后写定进 beat 段、预览值清空（退出面板/切视频即弃）。
final beatAlignPreviewOffsetProvider =
    NotifierProvider<BeatPreviewModel, double?>(BeatPreviewModel.new);

/// 节拍倍频预览档（见词条「节拍倍频」）：倍频气泡「快一倍/慢一半/重置」
/// 写入的会话态，null = 无预览（读面用已落盘档）。预览只改派生网格（节拍
/// 轨刻度等消费方实时跟随），不改文档 beat 段、不写盘；应用后写定、预览
/// 清空；关气泡/切走即弃（气泡会话侧统一丢弃，与节拍对齐预览同语义）。
final beatDensityPreviewProvider =
    NotifierProvider<BeatPreviewModel, double?>(
      BeatPreviewModel.new,
    );

/// 节拍 seam 注入点（自 hub beat 分析域迁入本
/// 小库：标注编辑模块库的临时衔接段 store 依赖它，小库是模块库允许的
/// 唯一 beat 依赖）：拍数等待/延迟播放/吸附/节拍轨渲染的节奏来源。按
/// 节拍轨三态派生——就绪态注入真实网格（markers `beat` 段，派生时刻 =
/// 网格拍点 + 平移量；预览偏移非空时以预览值实时派生），占位态维持
/// 均匀占位网格（120 bpm 既有语义），异常态注入秒制兜底网格（每拍
/// 0.5s，固定八拍等待 = 4s）。测试仍可整体覆盖本 provider 注入 fake
/// 真实网格。
///
/// 【白名单】这里是三态 → 性质的**唯一映射点**：三态枚举的
/// 裸判只许出现在 [_gridForTrack] 这一个 switch；其余可用性判读一律读两个
/// 谓词（[BeatGridReads.hasRealBeats] / [BeatGridReads.isSecondsFallback]），
/// 两支许可 UI 文案见 `control_layer.dart` `_showBeatReadinessPrompt` 与
/// `track_band.dart` 异常态小标识。
BeatGrid _gridForTrack(
  Ref ref,
  BeatTrackState track, {
  required bool withPreviews,
  required BeatGridSegmentContext segmentContext,
}) {
  switch (track.phase) {
    case BeatTrackPhase.ready:
      final grid = track.grid;
      if (grid != null && grid.beats.isNotEmpty) {
        if (!withPreviews) {
          return DocumentBeatGrid(
            beats: grid.beats,
            shift: grid.shift,
            density: grid.density,
          );
        }
        final preview = ref.watch(beatAlignPreviewOffsetProvider);
        final previewDensity = ref.watch(beatDensityPreviewProvider);
        // 倍频预览与平移预览同层：只改派生网格构造（「派生点唯一」），不落盘。
        final shift = preview ?? grid.shift;
        final density = previewDensity ?? grid.density;
        // 逐段档：档集合与分段几何变化都会
        // 使本 provider 重算。
        return DocumentBeatGrid(
          beats: grid.beats,
          shift: shift,
          density: density,
          segmentDensities: segmentContext.segmentDensities,
          segments: segmentContext.segments,
        );
      }
      return placeholderBeatGrid;
    case BeatTrackPhase.error:
      return const UnavailableBeatGrid();
    case BeatTrackPhase.placeholder:
      return placeholderBeatGrid;
  }
}

final beatGridProvider = Provider<BeatGrid>((ref) {
  return _gridForTrack(
    ref,
    ref.watch(beatTrackStateProvider),
    withPreviews: true,
    segmentContext: ref.watch(beatGridSegmentContextProvider),
  );
});

/// 逐段档读面端口：展示读面（[beatGridProvider]）
/// 的逐段档与分段几何由装配处注入——beat_track_state 不反向依赖播放器标注
/// 库（先例：main.dart 的观察者装配 override）。缺省空 = 全部段原样、无
/// 分段几何，派生与逐段档缺席时逐位一致。
typedef BeatGridSegmentContext =
    ({Map<int, double> segmentDensities, List<({int startMs, int endMs})> segments});

final beatGridSegmentContextProvider = Provider<BeatGridSegmentContext>(
  (ref) => (segmentDensities: const {}, segments: const []),
);

/// 落盘网格（见词条「节拍网格」）：与 [beatGridProvider] 同一三态
/// 映射，但**不含**会话期的节拍对齐预览偏移与倍频预览档——预览只改派生
/// 网格的展示面；练舞统计的桶记账读本 provider，预览期间不把桶记到预览
/// 偏移/预览档上。**不接**逐段档端口——四拍桶恒取整曲档（负面契约，
/// 本注释是该契约的唯一落点）。
final committedBeatGridProvider = Provider<BeatGrid>((ref) {
  return _gridForTrack(
    ref,
    ref.watch(beatTrackStateProvider),
    withPreviews: false,
    // 落盘网格不接逐段档端口——四拍桶恒取整曲档（负面契约）。
    segmentContext: (segmentDensities: const {}, segments: const []),
  );
});
