import '../annotation/dancer_roster.dart';
import '../annotation/framing_selection.dart'
    show FramingSelection, framingSelectionFromJson, framingSelectionToJson;
import '../annotation/half_beat_line.dart';
import '../annotation/local_mirror.dart';
import '../annotation/note_sticker.dart';
import '../annotation/segment_line.dart';
import '../core/beat_point.dart';
import 'annotation_sections.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';
import 'song_signature.dart';

export '../core/beat_point.dart' show BeatPoint;

/// 公开标记文件 `markers_<hash>.json` 的 schema v9 文档模型。
///
/// 文件形状 = 六段 + 版本号：
/// - `meta`：镜像值、歌曲署名、封面位置、源画面取景选区；
/// - `beat`：节拍网格纯生成物与溯源（分析写一次、永不改）；未分析时
///   该段缺席（不写段键）；
/// - `corrections`：节拍对齐平移量、八拍锚点——对生成物的人工修正，
///   与 `beat` 分段正交；
/// - `annotations`：视频首/尾、分段线、半拍线、重点、局部镜像片段；
/// - `notes`：备注贴纸（时间窗 / 文本（含点名语法）/ 内容锁 /
///   贴纸几何；顶层段）；
/// - `roster`：舞者名册（名字 + 代表色；顶层段。独立成段是因为写入者
///   不同：名册直写、与备注的编辑模块写入者互异，段与写入者一一对应
///   是段级写入安全的前提）。
///
/// 本类是六段的**读取面投影**（字段级 API 保持不变，widget/provider/
/// 编辑链零改动）；段化读写、逐层陌生键保底与版本门禁由
/// `document_codec.dart` 的声明派生。熟练度/激活/偏好等私密字段不在
/// 本文件（见 `local_document.dart`）。
///
/// 契约（不变量）：
/// - **段与写入者一一对应**：`meta`（镜像控制器 / 署名会话，封面位置同经
///   按视频文档的原子读改写落入本段）、`beat`（节拍分析写一次）、
///   `corrections` + `annotations`（标注编辑经保存编排）——一段一个写入者，
///   整段写入永不覆盖另一写入者的字段；
/// - **段级提交**：编辑快照/净变化判定/保存编排的排队与写回都以
///   `corrections` / `annotations` 段值为单位（见
///   `annotation_sections.dart`），无字段级 diff；
/// - **版本演进**：版本事实只此一处声明（[versionPolicy]：
///   地板 7 + v7 → v8 → v9 两级迁移步骤）；v7 / v8 沿链升到 v9 再读，
///   v1–v6 低于地板、从未分发、整份丢弃；高于本版与版本头读不出都按
///   「认识多少读多少」打开、本机不写回。
class MarkersDocument {
  const MarkersDocument({
    this.mirrored = false,
    this.localMirrorEnabled = true,
    this.signature,
    this.coverPositionMs,
    this.framingSelection,
    this.rangeStartMs = 0,
    this.rangeEndMs = 0,
    this.segmentLines = const [],
    this.halfBeatLines = const [],
    this.emphasizedSegments = const [],
    this.segmentDensities = const {},
    this.beat,
    this.localMirrorFragments = const [],
    this.notes = const [],
    this.roster = const [],
    this.extra = const {},
    this.metaExtra = const {},
    this.rangeExtra = const {},
    this.correctionsExtra = const {},
    this.annotationsExtra = const {},
    this.notesExtra = const {},
    this.rosterExtra = const {},
  });

  /// 空态文档（文件缺失/损坏/版本头缺失或不符合时按此兜底，不崩溃）。
  const MarkersDocument.empty() : this();

  /// 公开标记文件的版本链：地板 7 + v7 → v8、v8 → v9 两级迁移。
  /// 本版版本号 = [DocumentVersionPolicy.currentVersion]（链尾派生量）。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 7,
    steps: [
      MigrationStep(7, Map<String, Object?>.of),
      MigrationStep(8, _migrateMarkerV8ToV9),
    ],
  );

  /// 镜像值（可分享；接收方直接获得镜像画面）——`meta` 段。
  final bool mirrored;

  /// 局部镜像总开关（视频级视图开关，可分享；回答"要不要按片段集合把
  /// 部分区间反相"）——`meta` 段。缺键/类型不符兜底 `true`。注意：加字段
  /// 不动版本的安全路径只对**顶层**键成立（段内未知键老 reader
  /// 回写即丢），本字段在 `meta` 段内——升 v3 前的同版本旧代码一旦回写
  /// markers 会丢此键、读回兜底 `true`；升 v3 后新 reader 才是唯一读面。
  final bool localMirrorEnabled;

  /// 歌曲署名；未署名时为 null（标题栏回退文件名）——`meta` 段。
  final SongSignature? signature;

  /// 源画面取景选区（四边按源画面原相归一化）——`meta` 段，
  /// 完全公开（随分享包与组员方案走）。
  /// null = 未调过（显示整帧）；写侧省键。整帧选区与未调过在显示上不可
  /// 区分，但前者是已存值、在取景态里画框，故照常写键。
  final FramingSelection? framingSelection;

  /// 封面位置（毫秒，绝对时间点）——`meta` 段，完全公开（ADR-0002）。
  /// 缺省或不存在 = **跟随首线**（读面按有效区间起点求值，
  /// 见 `dance_library.dart`）；用户换过封面后写入该字段，恢复为默认时
  /// 写回 null。封面图片本身是设备本地缓存，不在此文件。
  final int? coverPositionMs;

  /// 视频首（毫秒）——`annotations` 段。
  final int rangeStartMs;

  /// 视频尾（毫秒）——`annotations` 段。
  final int rangeEndMs;

  /// 分段线（时间点 + flag，均可分享）——`annotations` 段。
  final List<SegmentLine> segmentLines;

  /// 半拍线（视频属性公共标记，可分享）——`annotations` 段。
  final List<HalfBeatLine> halfBeatLines;

  /// 置为「重点」的学习段段序（按段序升序）——`annotations` 段。
  final List<int> emphasizedSegments;

  /// 逐段档（见词条「段内倍频」）：键为段序、
  /// 值为档位数值——只收两档 ×½（0.5）/ ×2（2），**只写非原样档**（设回
  /// 原样即删键，缺省空表 = 全部段原样，整曲档与八拍锚点同一条稀疏纪律）
  /// ——`annotations` 段（分段几何归 `annotations`，不经 `beat` 段）。
  final Map<int, double> segmentDensities;

  /// 节拍网格（自动识别结果）；未分析时为 null（`beat` 段缺席）。
  ///
  /// [BeatGrid.shift]/[BeatGrid.anchors] 在文件里存 `corrections` 段
  /// （人工修正），读取时装配回网格（读取面不变）。
  final BeatGrid? beat;

  /// 局部镜像片段（局部镜像轨，可分享）：半开区间 [startMs,endMs) +
  /// 启用开关，同表按 startMs 升序且两两不重叠（编辑侧维持）。
  final List<LocalMirrorFragment> localMirrorFragments;

  /// 备注贴纸（备注轨 + 画面贴纸，可分享）：时间窗半开区间
  /// [startMs,endMs) + 文本 + 内容锁 + 贴纸几何（**没有 `refs`**：点名信息
  /// 就在 `text` 里；**没有 `style`**：颜色与描边都是派生的）。同表按
  /// startMs 升序且两两不重叠（编辑侧维持）。
  final List<NoteSticker> notes;

  /// 舞者名册（名字 + 代表色，可分享）：按视频关联、不跨视频。同表按
  /// 名字唯一（写入侧 [normalizeRoster] 维持，历史重复项在整表补写时
  /// 合并修复）。与 `notes` 独立成段——名册直写、与备注的写入者不同。
  final List<DancerRosterEntry> roster;

  /// 未知文档级扩展字段（原样保留）。
  final Map<String, dynamic> extra;

  /// `meta` 段未知键保底区（原样带回、写回原样）。
  final Map<String, dynamic> metaExtra;

  /// `annotations.range` 子对象未知键保底区。
  final Map<String, dynamic> rangeExtra;

  /// `corrections` 段未知键保底区。
  final Map<String, dynamic> correctionsExtra;

  /// `annotations` 段未知键保底区。
  final Map<String, dynamic> annotationsExtra;

  /// `notes` 段未知键保底区（原样带回、写回原样）。
  final Map<String, dynamic> notesExtra;

  /// `roster` 段未知键保底区（原样带回、写回原样）。
  final Map<String, dynamic> rosterExtra;

  static const Object _same = Object();

  MarkersDocument _rebuild({
    bool? mirrored,
    bool? localMirrorEnabled,
    Object? signature = _same,
    Object? coverPositionMs = _same,
    Object? framingSelection = _same,
    int? rangeStartMs,
    int? rangeEndMs,
    List<SegmentLine>? segmentLines,
    List<HalfBeatLine>? halfBeatLines,
    List<int>? emphasizedSegments,
    Map<int, double>? segmentDensities,
    BeatGrid? beat,
    bool clearBeat = false,
    List<LocalMirrorFragment>? localMirrorFragments,
    List<NoteSticker>? notes,
    List<DancerRosterEntry>? roster,
    Object? extra = _same,
  }) => MarkersDocument(
    mirrored: mirrored ?? this.mirrored,
    localMirrorEnabled: localMirrorEnabled ?? this.localMirrorEnabled,
    signature: identical(signature, _same)
        ? this.signature
        : signature as SongSignature?,
    coverPositionMs: identical(coverPositionMs, _same)
        ? this.coverPositionMs
        : coverPositionMs as int?,
    framingSelection: identical(framingSelection, _same)
        ? this.framingSelection
        : framingSelection as FramingSelection?,
    rangeStartMs: rangeStartMs ?? this.rangeStartMs,
    rangeEndMs: rangeEndMs ?? this.rangeEndMs,
    segmentLines: segmentLines ?? this.segmentLines,
    halfBeatLines: halfBeatLines ?? this.halfBeatLines,
    emphasizedSegments: emphasizedSegments ?? this.emphasizedSegments,
    segmentDensities: segmentDensities ?? this.segmentDensities,
    beat: clearBeat ? null : (beat ?? this.beat),
    localMirrorFragments: localMirrorFragments ?? this.localMirrorFragments,
    notes: notes ?? this.notes,
    roster: roster ?? this.roster,
    extra: identical(extra, _same) ? this.extra : extra as Map<String, dynamic>,
    metaExtra: metaExtra,
    rangeExtra: rangeExtra,
    correctionsExtra: correctionsExtra,
    annotationsExtra: annotationsExtra,
    notesExtra: notesExtra,
    rosterExtra: rosterExtra,
  );

  MarkersDocument withMirrored(bool mirrored) => _rebuild(mirrored: mirrored);

  /// 局部镜像总开关：与全局 [withMirrored] 同住 `meta` 段、
  /// 同一条落盘管线（首建初值 / 切换双写 / 打开读取）。
  MarkersDocument withLocalMirrorEnabled(bool localMirrorEnabled) =>
      _rebuild(localMirrorEnabled: localMirrorEnabled);

  MarkersDocument withSignature(SongSignature? signature) =>
      _rebuild(signature: signature);

  /// 写定封面位置（毫秒）；传 null = 清除、恢复「跟随首线」。
  MarkersDocument withCoverPosition(int? positionMs) =>
      _rebuild(coverPositionMs: positionMs);

  /// 写定源画面取景选区（直写：与封面位置同
  /// 一条 `meta` 段落盘管线）；传 null = 清除（回未调过、显示整帧）。
  MarkersDocument withFramingSelection(FramingSelection? selection) =>
      _rebuild(framingSelection: selection);

  MarkersDocument withRange({required int startMs, required int endMs}) =>
      _rebuild(rangeStartMs: startMs, rangeEndMs: endMs);

  MarkersDocument withSegmentLines(List<SegmentLine> segmentLines) =>
      _rebuild(segmentLines: segmentLines);

  MarkersDocument withHalfBeatLines(List<HalfBeatLine> halfBeatLines) =>
      _rebuild(halfBeatLines: halfBeatLines);

  MarkersDocument withEmphasizedSegments(List<int> emphasizedSegments) =>
      _rebuild(emphasizedSegments: emphasizedSegments);

  MarkersDocument withBeat(BeatGrid? beat) =>
      beat == null ? _rebuild(clearBeat: true) : _rebuild(beat: beat);

  MarkersDocument withLocalMirrorFragments(
    List<LocalMirrorFragment> localMirrorFragments,
  ) => _rebuild(localMirrorFragments: localMirrorFragments);

  /// `notes` 段整段写回（段级写回臂的备注侧）：全部备注一次就位。
  /// 不触碰 `beat` / `corrections` 段（备注编辑不属于生成物、不触发节拍
  /// 重算）。
  MarkersDocument withNotes(List<NoteSticker> notes) => _rebuild(notes: notes);

  /// `roster` 段整段写回（名册直写臂）：整表补写、绝对终值、最新优先。
  /// 不经编辑模块、不入撤销史、不受锁定分段与内容锁影响；只触碰名册段，
  /// 不碰 `notes` / `beat` / `corrections` /
  /// `annotations`。同表去重收在这一处（段写回即规范形）：名册没有
  /// 编辑侧不变量维护者，直写控制器是唯一写入者，历史重复项经任何
  /// 一次整表补写即合并修复。
  MarkersDocument withRoster(List<DancerRosterEntry> roster) =>
      _rebuild(roster: normalizeRoster(roster));

  /// `annotations` 段整段写回（保存编排的段级写回臂）：
  /// 段值为绝对终值，七面（首、尾、分段线、半拍线、重点、逐段档、局部
  /// 镜像片段）一次就位。首尾毫秒量化在此边界发生（文件 JSON 键为整数毫秒）。
  MarkersDocument withAnnotations(MarkerAnnotationsValue annotations) =>
      _rebuild(
        rangeStartMs: annotations.rangeStart.inMilliseconds,
        rangeEndMs: annotations.rangeEnd.inMilliseconds,
        segmentLines: annotations.segmentLines,
        halfBeatLines: annotations.halfBeatLines,
        emphasizedSegments: annotations.emphasizedSegments.toList()..sort(),
        segmentDensities: annotations.segmentDensities,
        localMirrorFragments: annotations.localMirrorFragments,
      );

  /// `corrections` 段整段写回（保存编排的段级写回臂）：平移量与锚点一次
  /// 就位；无 `beat` 段（未分析）时修正值无处装配，返回原文档（与读取
  /// 面的已登记边缘态一致——corrections 只在网格就绪后经编辑链产生）。
  MarkersDocument withCorrections(MarkerCorrectionsValue corrections) {
    final beat = this.beat;
    if (beat == null) return this;
    return _rebuild(
      beat: beat
          .withShift(corrections.shiftSeconds)
          .withDensity(corrections.density)
          .withAnchors(corrections.eightBeatAnchors),
    );
  }

  Map<String, dynamic> toJson() => _markersCodec.encode(this);

  /// 可分享投影：只保留声明为 `shareable` 的字段
  /// （见 [FieldDecl.shareable]）与各段结构，未登记键与非可分享字段一律
  /// 剔除——新字段默认不进包。分享面板与问题日志包读此投影。
  static Map<String, dynamic> shareableJson(Map<String, dynamic> json) =>
      _markersCodec.projectJson(json);

  /// 结构读取（版本政策）：政策把盘上 JSON 沿迁移链升到本版再读——
  /// v7 / v8 逐级升到 v9；v1–v6 低于地板、整份丢弃；高于本版与版本头读
  /// 不出都按「认识多少读多少」打开（陌生键进保底区原样往返、本机不写
  /// 回）。字段类型不符时按该字段缺省值兜底；未知键在文档/段/元素层都原样
  /// 保留进各保底区。
  factory MarkersDocument.fromJson(Map<String, dynamic> json) =>
      _markersCodec.decode(json);

  /// 相等与哈希经 [_markersCodec]（逐段、只比已登记字段）。
  ///
  /// 各保底区（[extra]/[metaExtra]/[correctionsExtra]/[annotationsExtra]/
  /// 元素 extra）刻意不参与：扩展字段由读入带回、写回原样透传，不作为
  /// 变更判定依据——patch 不改本版本字段时按无变化跳写，文件里的扩展
  /// 字段也不会因此丢失。
  @override
  bool operator ==(Object other) =>
      other is MarkersDocument && _markersCodec.equals(this, other);

  @override
  int get hashCode => _markersCodec.hash(this);
}

/// 节拍倍频档位：五档 2 的幂，值 = 派生拍数 ÷
/// 落盘拍数（「数拍速度倍数」）。缺省 [normal] = 原样。
enum BeatDensity {
  quarter(0.25),
  half(0.5),
  normal(1),
  two(2),
  quadruple(4);

  const BeatDensity(this.value);

  /// 档位值（派生拍数 ÷ 落盘拍数）。
  final double value;

  /// 从数值读档位；不在五档内（含损坏值）回落 [normal]。
  static BeatDensity fromValue(double value) => values.firstWhere(
    (d) => d.value == value,
    orElse: () => BeatDensity.normal,
  );
}

/// 节拍网格（markers `beat` 段 + `corrections` 段的读取面装配）。
///
/// 纯生成物与溯源（[model]/[fps]/[generatedAt]/[beats]）属 `beat` 段，
/// 分析一次后永不改；人工修正（[shift]/[density]/[anchors]）在文件里属
/// `corrections` 段，经 [MarkersDocument] 装配回网格（读取面不变）。
class BeatGrid {
  const BeatGrid({
    required this.model,
    required this.fps,
    required this.generatedAt,
    this.shift = 0,
    this.density = 1,
    this.anchors = const [],
    this.beats = const [],
    this.extra = const {},
  });

  /// 识别模型文件名（如 `madmom_downbeat_rnn_full.onnx`）。
  final String model;

  /// 解码帧率（fps=100）。
  final int fps;

  /// 识别完成时间（UTC）。
  final DateTime generatedAt;

  /// 节拍对齐平移量（秒，`lib/beat/CONTEXT.md`「节拍对齐」）：派生网格时刻 = 网格拍点 +
  /// 平移量；非破坏——[beats] 始终为节拍网格拍点（规整产物）。默认 0
  /// （未对齐）；占位/异常态无 beat 段、不适用。文件里存 `corrections` 段。
  final double shift;

  /// 节拍倍频：派生拍数 ÷ 网格拍数，五档 2 的幂
  /// （[BeatDensity]）；派生拍点 = 网格拍点（[beats]，不因倍频改写）按
  /// 档位重采样。缺省 1（原样，文件里不写该键）；占位/异常态无 beat 段、
  /// 不适用。文件里存 `corrections` 段。
  final double density;

  /// 节拍网格拍点序列（t 秒、down 强拍）——节拍规整产物，只此一份；
  /// 识别拍点在分析管线内即被替换、产品内不可读。
  final List<BeatPoint> beats;

  /// 八拍锚点：**强拍拍序号**数组，升序、去重（缺省 =
  /// 空 = 自动相位）。语义 = 分段奇偶重定相——锚点自身即八拍点、其后每隔
  /// 一个强拍一个八拍点、管到下一个锚点之前（求值见 [BeatPhase]）。
  /// 文件里存 `corrections` 段；拍序号对平移量 Δ 免疫，两者正交。
  final List<int> anchors;

  /// `beat` 段未知键保底区（原样带回、写回原样；不参与相等比较）。
  final Map<String, Object?> extra;

  /// 写定平移量（纯函数：返回新实例，原实例不变）。
  BeatGrid withShift(double shift) => BeatGrid(
    model: model,
    fps: fps,
    generatedAt: generatedAt,
    shift: shift,
    density: density,
    anchors: anchors,
    beats: beats,
    extra: extra,
  );

  /// 写定节拍倍频（纯函数：返回新实例，原实例不变）。
  BeatGrid withDensity(double density) => BeatGrid(
    model: model,
    fps: fps,
    generatedAt: generatedAt,
    shift: shift,
    density: density,
    anchors: anchors,
    beats: beats,
    extra: extra,
  );

  /// 写定锚点集合（纯函数：返回新实例，原实例不变）。
  BeatGrid withAnchors(List<int> anchors) => BeatGrid(
    model: model,
    fps: fps,
    generatedAt: generatedAt,
    shift: shift,
    density: density,
    anchors: List.unmodifiable(anchors),
    beats: beats,
    extra: extra,
  );

  /// `beat` 段写出（纯生成物与溯源；平移量/锚点在 `corrections` 段，
  /// 见 [MarkersDocument.toJson]）。
  Map<String, Object?> toJson() => _beatCodec.encode(_beatValue);

  /// 网格到 `beat` 段值的投影（一处装配，段声明与 toJson 共用）。
  _BeatValue get _beatValue => _BeatValue(
    model: model,
    fps: fps,
    generatedAt: generatedAt,
    beats: beats,
    extra: extra,
  );

  /// `beat` 段读取（shift/anchors 缺省 0/空；人工修正经文档层
  /// `corrections` 段装配）。
  factory BeatGrid.fromJson(Map<String, dynamic> json) {
    final v = _beatCodec.decode(json);
    return BeatGrid(
      model: v.model,
      fps: v.fps,
      generatedAt: v.generatedAtOrEpoch,
      beats: v.beats,
      extra: v.extra,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BeatGrid &&
        other.model == model &&
        other.fps == fps &&
        other.generatedAt == generatedAt &&
        other.shift == shift &&
        other.density == density &&
        _listEquals(other.anchors, anchors) &&
        _listEquals(other.beats, beats);
  }

  @override
  int get hashCode => Object.hash(
    model,
    fps,
    generatedAt,
    shift,
    density,
    Object.hashAll(anchors),
    Object.hashAll(beats),
  );
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

/// 逐段档的合法档位（词条「段内倍频」档位表）：两档 + 原样（原样不落键）。
/// 档位变化只改本集合与读侧收值，不散落到消费点。
final Set<double> _segmentDensityTiers = {0.5, 2.0};

// ---------------------------------------------------------------------------
// 段声明（字段 id 枚举 + 穷尽 switch，机制派生读写/相等/保底）
// ---------------------------------------------------------------------------

enum _MarkersSection { meta, beat, corrections, annotations, notes, roster }

final DocumentCodec<MarkersDocument, _MarkersSection> _markersCodec =
    DocumentCodec<MarkersDocument, _MarkersSection>(
      policy: MarkersDocument.versionPolicy,
      ids: _MarkersSection.values,
      decl: _markersSectionDecl,
      empty: MarkersDocument.empty,
      build: _buildMarkersDocument,
      extraOf: (doc) => doc.extra,
      withExtra: (doc, extra) => doc._rebuild(extra: extra),
    );

/// v8 → v9 迁移步骤：只丢掉 `meta` 段的旧取景字段 `framingBand`（旧形状
/// 一律**复位**，不换算、不预写新字段 `framingSelection`），其余键（含文档
/// 级、段级、元素级的陌生键保底区）逐字带过——**不写版本号**，由政策在每级
/// 之后自己写。已发布的 v8 文件（v0.1.3 及更早）本就没有旧取景字段，迁移
/// 对它们是**恒等**。
Map<String, Object?> _migrateMarkerV8ToV9(Map<String, Object?> json) {
  final meta = json['meta'];
  if (meta is! Map) return Map<String, Object?>.of(json);
  final nextMeta = <String, Object?>{
    for (final entry in meta.entries)
      if (entry.key is String) entry.key as String: entry.value,
  }..remove('framingBand');
  return Map<String, Object?>.of(json)..['meta'] = nextMeta;
}

SectionDecl<MarkersDocument> _markersSectionDecl(_MarkersSection id) =>
    switch (id) {
      _MarkersSection.meta => SectionDecl(
        key: 'meta',
        codec: _metaCodec,
        sectionOf: (doc) => _MetaValue(
          mirrored: doc.mirrored,
          localMirrorEnabled: doc.localMirrorEnabled,
          signature: doc.signature,
          coverPositionMs: doc.coverPositionMs,
          framingSelection: doc.framingSelection,
          extra: doc.metaExtra,
        ),
      ),
      _MarkersSection.beat => SectionDecl(
        key: 'beat',
        codec: _beatCodec,
        absentOf: (doc) => doc.beat == null,
        sectionOf: (doc) => doc.beat?._beatValue,
      ),
      _MarkersSection.corrections => SectionDecl(
        key: 'corrections',
        codec: _correctionsCodec,
        sectionOf: (doc) => _CorrectionsValue(
          shift: doc.beat?.shift ?? 0,
          density: doc.beat?.density ?? 1,
          anchors: doc.beat?.anchors ?? const [],
          extra: doc.correctionsExtra,
        ),
      ),
      _MarkersSection.annotations => SectionDecl(
        key: 'annotations',
        codec: _annotationsCodec,
        sectionOf: (doc) => _AnnotationsValue(
          range: _RangeValue(
            startMs: doc.rangeStartMs,
            endMs: doc.rangeEndMs,
            extra: doc.rangeExtra,
          ),
          segmentLines: doc.segmentLines,
          halfBeatLines: doc.halfBeatLines,
          emphasizedSegments: doc.emphasizedSegments,
          segmentDensities: doc.segmentDensities,
          localMirrorFragments: doc.localMirrorFragments,
          extra: doc.annotationsExtra,
        ),
      ),
      _MarkersSection.notes => SectionDecl(
        key: 'notes',
        codec: _notesCodec,
        // 空表不写段键（与 `beat` 缺席同款）：缺段读侧按空兜底。
        absentOf: (doc) => doc.notes.isEmpty,
        sectionOf: (doc) =>
            _ListSectionValue<NoteSticker>(doc.notes, doc.notesExtra),
      ),
      _MarkersSection.roster => SectionDecl(
        key: 'roster',
        codec: _rosterCodec,
        // 空名册不写段键（与 `notes` 缺席同款）：缺段读侧按空兜底。
        absentOf: (doc) => doc.roster.isEmpty,
        sectionOf: (doc) =>
            _ListSectionValue<DancerRosterEntry>(doc.roster, doc.rosterExtra),
      ),
    };

MarkersDocument _buildMarkersDocument(Map<_MarkersSection, Object?> sections) {
  final meta = sections[_MarkersSection.meta] as _MetaValue;
  final beatValue = sections[_MarkersSection.beat] as _BeatValue?;
  final corrections =
      sections[_MarkersSection.corrections] as _CorrectionsValue;
  final annotations =
      sections[_MarkersSection.annotations] as _AnnotationsValue;
  final notesValue =
      sections[_MarkersSection.notes] as _ListSectionValue<NoteSticker>? ??
      const _ListSectionValue<NoteSticker>();
  final rosterValue =
      sections[_MarkersSection.roster] as _ListSectionValue<DancerRosterEntry>? ??
      const _ListSectionValue<DancerRosterEntry>();
  return MarkersDocument(
    mirrored: meta.mirrored,
    localMirrorEnabled: meta.localMirrorEnabled,
    signature: meta.signature,
    coverPositionMs: meta.coverPositionMs,
    framingSelection: meta.framingSelection,
    rangeStartMs: annotations.range.startMs,
    rangeEndMs: annotations.range.endMs,
    segmentLines: annotations.segmentLines,
    halfBeatLines: annotations.halfBeatLines,
    emphasizedSegments: annotations.emphasizedSegments,
    segmentDensities: annotations.segmentDensities,
    // 已登记边缘态：`beat` 缺席而 `corrections` 带 shift/anchors 的文件，
    // 修正值无处装配（读取面网格为 null）即被丢弃——与 v1「无 beat 段则
    // shift/anchors 不存在」等价；corrections 只在网格就绪后经编辑链产生，
    // 正常文件不会出现该形态。
    beat: beatValue == null
        ? null
        : BeatGrid(
            model: beatValue.model,
            fps: beatValue.fps,
            generatedAt: beatValue.generatedAtOrEpoch,
            shift: corrections.shift,
            density: corrections.density,
            anchors: corrections.anchors,
            beats: beatValue.beats,
            extra: beatValue.extra,
          ),
    localMirrorFragments: annotations.localMirrorFragments,
    notes: notesValue.elements,
    roster: rosterValue.elements,
    metaExtra: meta.extra,
    rangeExtra: annotations.range.extra,
    correctionsExtra: corrections.extra,
    annotationsExtra: annotations.extra,
    notesExtra: notesValue.extra,
    rosterExtra: rosterValue.extra,
  );
}

// --- meta 段 ----------------------------------------------------------------

class _MetaValue {
  const _MetaValue({
    this.mirrored = false,
    this.localMirrorEnabled = true,
    this.signature,
    this.coverPositionMs,
    this.framingSelection,
    this.extra = const {},
  });

  final bool mirrored;
  final bool localMirrorEnabled;
  final SongSignature? signature;
  final int? coverPositionMs;
  final FramingSelection? framingSelection;
  final Map<String, Object?> extra;
}

enum _MetaField {
  mirrored,
  localMirrorEnabled,
  signature,
  coverPositionMs,
  framingSelection,
}

final RecordCodec<_MetaValue, _MetaField> _metaCodec =
    RecordCodec<_MetaValue, _MetaField>(
      ids: _MetaField.values,
      decl: _metaDecl,
      build: _buildMeta,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _MetaValue(
        mirrored: v.mirrored,
        localMirrorEnabled: v.localMirrorEnabled,
        signature: v.signature,
        coverPositionMs: v.coverPositionMs,
        framingSelection: v.framingSelection,
        extra: extra,
      ),
    );

FieldDecl<_MetaValue> _metaDecl(_MetaField id) => switch (id) {
  _MetaField.mirrored => FieldDecl(
    key: 'mirrored',
    shareable: true,
    read: (json) => json['mirrored'] is bool ? json['mirrored'] as bool : false,
    write: (v) => v.mirrored,
    equal: (a, b) => a.mirrored == b.mirrored,
  ),
  _MetaField.localMirrorEnabled => FieldDecl(
    key: 'localMirrorEnabled',
    shareable: true,
    read: (json) => json['localMirrorEnabled'] is bool
        ? json['localMirrorEnabled'] as bool
        : true,
    write: (v) => v.localMirrorEnabled,
    equal: (a, b) => a.localMirrorEnabled == b.localMirrorEnabled,
  ),
  _MetaField.signature => FieldDecl(
    key: 'signature',
    shareable: true,
    read: (json) => json['signature'] is Map<String, dynamic>
        ? SongSignature.fromJson(json['signature'] as Map<String, dynamic>)
        : null,
    // 承诺：未署名不写该键。
    write: (v) => v.signature?.toJson() ?? omitField,
    equal: (a, b) => a.signature == b.signature,
  ),
  _MetaField.coverPositionMs => FieldDecl(
    key: 'coverPositionMs',
    shareable: true,
    // 只收整数毫秒；类型不符按「未设置」兜底（不把坏值当位置）。
    read: (json) {
      final raw = json['coverPositionMs'];
      return raw is int ? raw : null;
    },
    // 承诺：未换过封面（跟随首线）不写该键。
    write: (v) => v.coverPositionMs ?? omitField,
    equal: (a, b) => a.coverPositionMs == b.coverPositionMs,
  ),
  _MetaField.framingSelection => FieldDecl(
    key: 'framingSelection',
    shareable: true,
    read: (json) => framingSelectionFromJson(json['framingSelection']),
    // 承诺：未调过（null）省键；整帧选区是已存值，照常写。
    write: (v) => v.framingSelection == null
        ? omitField
        : framingSelectionToJson(v.framingSelection!),
    equal: (a, b) => a.framingSelection == b.framingSelection,
  ),
};

_MetaValue _buildMeta(Map<_MetaField, Object?> values) => _MetaValue(
  mirrored: values[_MetaField.mirrored] as bool,
  localMirrorEnabled: values[_MetaField.localMirrorEnabled] as bool,
  signature: values[_MetaField.signature] as SongSignature?,
  coverPositionMs: values[_MetaField.coverPositionMs] as int?,
  framingSelection: values[_MetaField.framingSelection] as FramingSelection?,
);

// --- beat 段（纯生成物 + 溯源） ----------------------------------------------

class _BeatValue {
  const _BeatValue({
    this.model = '',
    this.fps = 0,
    this.generatedAt,
    this.beats = const [],
    this.extra = const {},
  });

  final String model;
  final int fps;

  /// null 视为 epoch（const 构造默认值用不了 DateTime）。
  final DateTime? generatedAt;
  final List<BeatPoint> beats;
  final Map<String, Object?> extra;

  DateTime get generatedAtOrEpoch =>
      generatedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

enum _BeatField { model, fps, generatedAt, beats }

final RecordCodec<_BeatValue, _BeatField> _beatCodec =
    RecordCodec<_BeatValue, _BeatField>(
      ids: _BeatField.values,
      decl: _beatDecl,
      build: _buildBeat,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _BeatValue(
        model: v.model,
        fps: v.fps,
        generatedAt: v.generatedAtOrEpoch,
        beats: v.beats,
        extra: extra,
      ),
    );

FieldDecl<_BeatValue> _beatDecl(_BeatField id) => switch (id) {
  _BeatField.model => FieldDecl(
    key: 'model',
    shareable: true,
    read: (json) => json['model'] as String? ?? '',
    write: (v) => v.model,
    equal: (a, b) => a.model == b.model,
  ),
  _BeatField.fps => FieldDecl(
    key: 'fps',
    shareable: true,
    read: (json) => (json['fps'] as num?)?.toInt() ?? 0,
    write: (v) => v.fps,
    equal: (a, b) => a.fps == b.fps,
  ),
  _BeatField.generatedAt => FieldDecl(
    key: 'generatedAt',
    shareable: true,
    read: (json) => json['generatedAt'] is String
        ? DateTime.tryParse(json['generatedAt'] as String)?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    write: (v) => v.generatedAtOrEpoch.toUtc().toIso8601String(),
    equal: (a, b) => a.generatedAtOrEpoch == b.generatedAtOrEpoch,
  ),
  _BeatField.beats => FieldDecl(
    key: 'beats',
    shareable: true,
    read: (json) => [
      if (json['beats'] is List)
        for (final item in json['beats'] as List)
          if (item is Map && item['t'] is num)
            BeatPoint(
              t: (item['t'] as num).toDouble(),
              down: item['down'] as bool? ?? false,
            ),
    ],
    write: (v) => [
      for (final b in v.beats) {'t': b.t, 'down': b.down},
    ],
    equal: (a, b) => _listEquals(a.beats, b.beats),
  ),
};

_BeatValue _buildBeat(Map<_BeatField, Object?> values) => _BeatValue(
  model: values[_BeatField.model] as String,
  fps: values[_BeatField.fps] as int,
  generatedAt: values[_BeatField.generatedAt] as DateTime?,
  beats: values[_BeatField.beats] as List<BeatPoint>,
);

// --- corrections 段（人工修正：平移量 + 八拍锚点） ---------------------------

class _CorrectionsValue {
  const _CorrectionsValue({
    this.shift = 0,
    this.density = 1,
    this.anchors = const [],
    this.extra = const {},
  });

  final double shift;
  final double density;
  final List<int> anchors;
  final Map<String, Object?> extra;
}

enum _CorrectionsField { shift, density, anchors }

final RecordCodec<_CorrectionsValue, _CorrectionsField> _correctionsCodec =
    RecordCodec<_CorrectionsValue, _CorrectionsField>(
      ids: _CorrectionsField.values,
      decl: _correctionsDecl,
      build: _buildCorrections,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _CorrectionsValue(
        shift: v.shift,
        density: v.density,
        anchors: v.anchors,
        extra: extra,
      ),
    );

FieldDecl<_CorrectionsValue> _correctionsDecl(_CorrectionsField id) =>
    switch (id) {
      _CorrectionsField.shift => FieldDecl(
        key: 'shift',
        shareable: true,
        read: (json) => (json['shift'] as num?)?.toDouble() ?? 0.0,
        write: (v) => v.shift,
        equal: (a, b) => a.shift == b.shift,
      ),
      _CorrectionsField.density => FieldDecl(
        key: 'density',
        shareable: true,
        // 只收五档 2 的幂（损坏值按原样兜底，不当档位）。
        read: (json) =>
            BeatDensity.fromValue((json['density'] as num?)?.toDouble() ?? 1)
                .value,
        // 承诺：原样不写该键。
        write: (v) => v.density != 1 ? v.density : omitField,
        equal: (a, b) => a.density == b.density,
      ),
      _CorrectionsField.anchors => FieldDecl(
        key: 'anchors',
        shareable: true,
        // 读入规范化：升序去重、只收整数。
        read: (json) {
          final raw = json['anchors'];
          if (raw is! List) return const <int>[];
          final anchors = <int>[
            for (final item in raw)
              if (item is int) item,
          ]..sort();
          return List<int>.unmodifiable([
            for (var i = 0; i < anchors.length; i++)
              if (i == 0 || anchors[i] != anchors[i - 1]) anchors[i],
          ]);
        },
        // 承诺：无锚点不写该键。
        write: (v) => v.anchors.isNotEmpty ? List.of(v.anchors) : omitField,
        equal: (a, b) => _listEquals(a.anchors, b.anchors),
      ),
    };

_CorrectionsValue _buildCorrections(Map<_CorrectionsField, Object?> values) =>
    _CorrectionsValue(
      shift: values[_CorrectionsField.shift] as double,
      density: values[_CorrectionsField.density] as double,
      anchors: values[_CorrectionsField.anchors] as List<int>,
    );

// --- annotations 段 ----------------------------------------------------------

class _AnnotationsValue {
  const _AnnotationsValue({
    this.range = const _RangeValue(),
    this.segmentLines = const [],
    this.halfBeatLines = const [],
    this.emphasizedSegments = const [],
    this.segmentDensities = const {},
    this.localMirrorFragments = const [],
    this.extra = const {},
  });

  final _RangeValue range;
  final List<SegmentLine> segmentLines;
  final List<HalfBeatLine> halfBeatLines;
  final List<int> emphasizedSegments;
  final Map<int, double> segmentDensities;
  final List<LocalMirrorFragment> localMirrorFragments;
  final Map<String, Object?> extra;
}

enum _AnnotationsField {
  range,
  segmentLines,
  halfBeatLines,
  emphasizedSegments,
  segmentDensities,
  localMirrorFragments,
}

final RecordCodec<_AnnotationsValue, _AnnotationsField> _annotationsCodec =
    RecordCodec<_AnnotationsValue, _AnnotationsField>(
      ids: _AnnotationsField.values,
      decl: _annotationsDecl,
      build: _buildAnnotations,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _AnnotationsValue(
        range: v.range,
        segmentLines: v.segmentLines,
        halfBeatLines: v.halfBeatLines,
        emphasizedSegments: v.emphasizedSegments,
        segmentDensities: v.segmentDensities,
        localMirrorFragments: v.localMirrorFragments,
        extra: extra,
      ),
    );

class _RangeValue {
  const _RangeValue({this.startMs = 0, this.endMs = 0, this.extra = const {}});

  final int startMs;
  final int endMs;
  final Map<String, Object?> extra;
}

enum _RangeField { startMs, endMs }

final RecordCodec<_RangeValue, _RangeField> _rangeCodec =
    RecordCodec<_RangeValue, _RangeField>(
      ids: _RangeField.values,
      decl: _rangeDecl,
      build: _buildRange,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) =>
          _RangeValue(startMs: v.startMs, endMs: v.endMs, extra: extra),
    );

FieldDecl<_RangeValue> _rangeDecl(_RangeField id) => switch (id) {
  _RangeField.startMs => FieldDecl(
    key: 'startMs',
    read: (json) => (json['startMs'] as num?)?.toInt() ?? 0,
    write: (v) => v.startMs,
    equal: (a, b) => a.startMs == b.startMs,
  ),
  _RangeField.endMs => FieldDecl(
    key: 'endMs',
    read: (json) => (json['endMs'] as num?)?.toInt() ?? 0,
    write: (v) => v.endMs,
    equal: (a, b) => a.endMs == b.endMs,
  ),
};

_RangeValue _buildRange(Map<_RangeField, Object?> values) => _RangeValue(
  startMs: values[_RangeField.startMs] as int,
  endMs: values[_RangeField.endMs] as int,
);

FieldDecl<_AnnotationsValue> _annotationsDecl(_AnnotationsField id) =>
    switch (id) {
      _AnnotationsField.range => FieldDecl(
        key: 'range',
        shareable: true,
        read: (json) => _rangeCodec.decode(
          json['range'] is Map<String, Object?>
              ? json['range'] as Map<String, Object?>
              : const {},
        ),
        write: (v) => _rangeCodec.encode(v.range),
        equal: (a, b) => _rangeCodec.equals(a.range, b.range),
      ),
      _AnnotationsField.segmentLines => FieldDecl(
        key: 'segmentLines',
        shareable: true,
        read: (json) => SegmentLine.fromJsonList(json['segmentLines']),
        write: (v) => [for (final line in v.segmentLines) line.toJson()],
        equal: (a, b) => _listEquals(a.segmentLines, b.segmentLines),
      ),
      _AnnotationsField.halfBeatLines => FieldDecl(
        key: 'halfBeatLines',
        shareable: true,
        read: (json) => HalfBeatLine.fromJsonList(json['halfBeatLines']),
        write: (v) => [for (final line in v.halfBeatLines) line.toJson()],
        equal: (a, b) => _listEquals(a.halfBeatLines, b.halfBeatLines),
      ),
      _AnnotationsField.emphasizedSegments => FieldDecl(
        key: 'emphasizedSegments',
        shareable: true,
        read: (json) {
          final raw = json['emphasizedSegments'];
          if (raw is! List) return const <int>[];
          return <int>[
            for (final item in raw)
              if (item is int) item,
          ]..sort();
        },
        write: (v) => [...v.emphasizedSegments]..sort(),
        equal: (a, b) =>
            _listEquals(a.emphasizedSegments, b.emphasizedSegments),
      ),
      _AnnotationsField.segmentDensities => FieldDecl(
        key: 'segmentDensities',
        shareable: true,
        // 读入规范化：键为段序（整数字符串），值只收两档（0.5 / 2）；
        // 类型不符/负段序/未知档位（含原样 1）按该键不存在兜底，不当档位。
        read: (json) {
          final raw = json['segmentDensities'];
          if (raw is! Map) return const <int, double>{};
          final parsed = <int, double>{};
          raw.forEach((key, value) {
            final order = key is int ? key : int.tryParse('$key');
            final density = value is num ? value.toDouble() : null;
            if (order != null &&
                order >= 0 &&
                density != null &&
                _segmentDensityTiers.contains(density)) {
              parsed[order] = density;
            }
          });
          return Map<int, double>.unmodifiable(parsed);
        },
        // 承诺：只写非原样档；全部原样不写该键（缺省不写、稀疏）。
        write: (v) => v.segmentDensities.isEmpty
            ? omitField
            : {
                for (final entry in v.segmentDensities.entries)
                  if (_segmentDensityTiers.contains(entry.value))
                    '${entry.key}': entry.value,
              },
        equal: (a, b) => _densitiesEquals(a.segmentDensities, b.segmentDensities),
      ),
      _AnnotationsField.localMirrorFragments => FieldDecl(
        key: 'localMirrorFragments',
        shareable: true,
        read: (json) =>
            LocalMirrorFragment.fromJsonList(json['localMirrorFragments']),
        write: (v) => [
          for (final fragment in v.localMirrorFragments) fragment.toJson(),
        ],
        equal: (a, b) =>
            _listEquals(a.localMirrorFragments, b.localMirrorFragments),
      ),
    };

_AnnotationsValue _buildAnnotations(
  Map<_AnnotationsField, Object?> values,
) => _AnnotationsValue(
  range: values[_AnnotationsField.range] as _RangeValue,
  segmentLines: values[_AnnotationsField.segmentLines] as List<SegmentLine>,
  halfBeatLines: values[_AnnotationsField.halfBeatLines] as List<HalfBeatLine>,
  emphasizedSegments: values[_AnnotationsField.emphasizedSegments] as List<int>,
  segmentDensities:
      values[_AnnotationsField.segmentDensities] as Map<int, double>,
  localMirrorFragments:
      values[_AnnotationsField.localMirrorFragments]
          as List<LocalMirrorFragment>,
);

// --- 单列表段（备注、名册共用） ----------------------------------------------

/// 单列表段的值：段对象只装一个元素列表与段级陌生键保底区。
class _ListSectionValue<E> {
  const _ListSectionValue([this.elements = const [], this.extra = const {}]);

  final List<E> elements;
  final Map<String, Object?> extra;
}

enum _ListField { items }

/// 单列表段的编解码器：元素列表在 [key] 键下，段级陌生键进保底区。
RecordCodec<_ListSectionValue<E>, _ListField> _listSectionCodec<E>({
  required String key,
  required List<E> Function(Object? raw) read,
  required Object? Function(E element) write,
}) => RecordCodec<_ListSectionValue<E>, _ListField>(
  ids: _ListField.values,
  decl: (id) => FieldDecl(
    key: key,
    shareable: true,
    read: (json) => read(json[key]),
    write: (v) => [for (final element in v.elements) write(element)],
    equal: (a, b) => _listEquals(a.elements, b.elements),
  ),
  build: (values) => _ListSectionValue<E>(values[_ListField.items] as List<E>),
  extraOf: (v) => v.extra,
  withExtra: (v, extra) => _ListSectionValue<E>(v.elements, extra),
);

final _notesCodec = _listSectionCodec<NoteSticker>(
  key: 'notes',
  read: NoteSticker.fromJsonList,
  write: (note) => note.toJson(),
);

final _rosterCodec = _listSectionCodec<DancerRosterEntry>(
  key: 'dancers',
  read: DancerRosterEntry.fromJsonList,
  write: (entry) => entry.toJson(),
);
