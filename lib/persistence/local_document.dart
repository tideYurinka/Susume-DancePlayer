import '../annotation/compare_materials.dart'
    show
        MaterialAutoDeleteSettings,
        MaterialAutoDeleteStrategy,
        kDefaultMaterialAutoDeleteKeepCount,
        kDefaultMaterialAutoDeleteKeepDays,
        PracticeClip;
import '../annotation/learning_segment_attributes.dart';
import 'annotation_sections.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';

/// `prefs.overlay` 子对象的原始数值投影：四格各一对偏移分量 + 两个共用
/// 尺寸系数。
///
/// **纯值层载体**：不依赖 `dart:ui`（舞库依赖闭包只经按视频文档读面到达
/// 本类型），故持原始数值
/// 而非 `Offset`；四格 → 坐标容器的组装与反向拆解落在 player 层
/// `VideoSettingsPersistence`。一格的两个键**同时存在**才算该格已自定义
/// （缺任一个键即整格视为未自定义，由 codec 读取时归一）。
class OverlayPlacementFields {
  const OverlayPlacementFields({
    this.dx,
    this.dy,
    this.landscapeDx,
    this.landscapeDy,
    this.compareDx,
    this.compareDy,
    this.landscapeCompareDx,
    this.landscapeCompareDy,
    this.rectWidthFactor,
    this.pendulumScale,
  });

  /// 竖屏 · 普通（沿用既有键名 `dx` / `dy`）。
  final double? dx;
  final double? dy;

  final double? landscapeDx;
  final double? landscapeDy;

  final double? compareDx;
  final double? compareDy;

  final double? landscapeCompareDx;
  final double? landscapeCompareDy;

  /// 四格共用尺寸系数（矩形宽系数 / 摆锤等比系数）。
  final double? rectWidthFactor;
  final double? pendulumScale;

  /// 全部未设（文件无任何浮层位字段）。
  bool get isUnset =>
      dx == null &&
      dy == null &&
      landscapeDx == null &&
      landscapeDy == null &&
      compareDx == null &&
      compareDy == null &&
      landscapeCompareDx == null &&
      landscapeCompareDy == null &&
      rectWidthFactor == null &&
      pendulumScale == null;

  @override
  bool operator ==(Object other) =>
      other is OverlayPlacementFields &&
      other.dx == dx &&
      other.dy == dy &&
      other.landscapeDx == landscapeDx &&
      other.landscapeDy == landscapeDy &&
      other.compareDx == compareDx &&
      other.compareDy == compareDy &&
      other.landscapeCompareDx == landscapeCompareDx &&
      other.landscapeCompareDy == landscapeCompareDy &&
      other.rectWidthFactor == rectWidthFactor &&
      other.pendulumScale == pendulumScale;

  @override
  int get hashCode => Object.hash(
    dx,
    dy,
    landscapeDx,
    landscapeDy,
    compareDx,
    compareDy,
    landscapeCompareDx,
    landscapeCompareDy,
    rectWidthFactor,
    pendulumScale,
  );
}

/// `prefs.beatPrompt` 子对象的原始值投影：
/// 一支舞的**节拍提示记忆**，五个值逐字段可缺席（null = 这支舞对这项
/// 没有意见）。音量不入本单元（留设备级 `metronomeSettings.metronomeVolume`）。
///
/// **纯值层载体**：与 [OverlayPlacementFields] 同款，持原始数值/枚举名
/// 而非播放器层枚举类型（舞库依赖闭包零 Flutter）。
class BeatPromptMemoryFields {
  const BeatPromptMemoryFields({
    this.animation,
    this.animationStyle,
    this.sound,
    this.soundType,
    this.halfBeat,
  });

  final bool? animation;

  /// 动画形态；词表 `bar` / `pendulum`（与播放器层 BeatAnimationStyle
  /// 枚举名一致）。词表外的名字读入按缺席兜底。
  final String? animationStyle;

  final bool? sound;

  /// 音源；词表 `normal` / `vocal` / `geigi`（与播放器层
  /// MetronomeSoundType 枚举名一致）。词表外的名字读入按缺席兜底。
  final String? soundType;

  final bool? halfBeat;

  /// 逐字段拷贝（null 参数 = 保持现值；本词表无「清除单字段」的路径，
  /// 缺席 = 记录里就没有该键）。
  BeatPromptMemoryFields copyWith({
    bool? animation,
    String? animationStyle,
    bool? sound,
    String? soundType,
    bool? halfBeat,
  }) => BeatPromptMemoryFields(
    animation: animation ?? this.animation,
    animationStyle: animationStyle ?? this.animationStyle,
    sound: sound ?? this.sound,
    soundType: soundType ?? this.soundType,
    halfBeat: halfBeat ?? this.halfBeat,
  );

  @override
  bool operator ==(Object other) =>
      other is BeatPromptMemoryFields &&
      other.animation == animation &&
      other.animationStyle == animationStyle &&
      other.sound == sound &&
      other.soundType == soundType &&
      other.halfBeat == halfBeat;

  @override
  int get hashCode =>
      Object.hash(animation, animationStyle, sound, soundType, halfBeat);
}

/// `prefs.castPrep` 子对象的原始值投影：一支舞的**投屏准备记忆**——准备面板
/// 那两个渲染勾选档（画面类 / 声音类）与**投屏倍速档**记号表；三个字段逐字段
/// 可缺席（picture / sound 的 null = 这支舞对这项没有意见；`tiers` 的空表 =
/// 对档位没有意见，与缺键同义，见下）。
///
/// **纯值层载体**：与 [BeatPromptMemoryFields] 同款，持原始类型而非投屏域的
/// `CastRenderChoices` / `CastSpeedTier`（舞库依赖闭包零 Flutter，文档层也不
/// 认投屏域）。档位记号是**投屏域的 `CastSpeedTier.token`**，它的词表因此只有
/// 候选档那一处声明：文档层只认「记号是字符串」（`_parseCastTiers`），认不得的
/// 记号原样带回写回，**认不认得由投屏域的值边界回答**
/// （`player/cast_prep_memory.dart` 的降级规则）。
class CastPrepMemoryFields {
  const CastPrepMemoryFields({
    this.picture,
    this.sound,
    this.tiers = const [],
  });

  /// 画面类勾选（含呈现类）。
  final bool? picture;

  /// 声音类勾选（拍声混进音轨）。
  final bool? sound;

  /// 投屏倍速档的记号表（**空表 = 对档位没有意见**，与缺键同义、不落盘；次序
  /// 不入语义，写侧按候选次序归一）。表里每一项都是字符串；认不认得由投屏域
  /// 按候选档判定（文档层不裁词表）。
  final List<String> tiers;

  @override
  bool operator ==(Object other) =>
      other is CastPrepMemoryFields &&
      other.picture == picture &&
      other.sound == sound &&
      jsonDeepEquals(other.tiers, tiers);

  @override
  int get hashCode => Object.hash(picture, sound, jsonDeepHash(tiers));
}

/// 本地文档 `local_<hash>.json` 的 schema v4 文档模型。
///
/// 文件形状 = 两段 + 版本号，段与写入者一一对应：
/// - `session`（保存编排写）：熟练度（按段序）、激活学习段；
/// - `prefs`（编辑偏好持久化会话写）：预览吸附开关、锁定分段、数拍
///   浮层位置（左上角 x/y）与分形态系数（矩形宽系数、摆锤等比系数）、
///   节拍提示记忆（`prefs.beatPrompt`，五个值逐字段可缺席）、
///   **投屏准备记忆**（`prefs.castPrep`，两个渲染勾选档与投屏倍速档记号表
///   逐字段可缺席；#40）。后两份都是**存在性包裹的子对象**——共用
///   [_MemoryDecl] 那一套声明（一个键 + 一张字段表，见该类的库注释）与
///   `prefs` 段的**记忆片**（登记表 [_memoryBindings] 派生读写判等），新增
///   一份按舞记住的取值因此只是「一个键 + 一张字段表 + 登记表一行」，段里
///   不必再挂一处（`#47`：本类上那两个类型化字段是编译器强制的残留）。
///
/// 字段归属清单与双文件文档模型（修订 2026-09-10）一致。仅存本地、永不随
/// 分享导出；删除视频条目时随视频文件删除。
///
/// 本类是两段的**读取面投影**（字段级 API 保持不变，widget/provider/
/// 编辑链零改动）；段化读写、逐层陌生键保底与版本门禁由
/// `document_codec.dart` 的声明派生。
///
/// 契约（不变量）：
/// - **段与写入者一一对应**：`session` 的写入经保存编排的**同一条**
///   `session` 写回臂（标注编辑提交链与激活集合模型两个入口，各自
///   组装完整段值、写入前读现值，路径互不覆盖）；`prefs` 只由编辑
///   偏好持久化会话写——整段写入永不覆盖另一写入者的字段；
/// - **段级提交**：编排写回以 `session` 段值为单位（绝对终值，见
///   `annotation_sections.dart`），无字段级 diff；
/// - **版本演进**：版本事实只此一处声明（[versionPolicy]：
///   地板 3 + 一条 v3 → v4 迁移步骤——丢弃旧取景两键 `prefs.framingSource`／
///   `prefs.framingPractice`、不换算，其余字段与逐层陌生键逐字不变；升级后
///   旧舞取景回未调过的起手构图）；v1／v2 低于地板、整份丢弃；
///   高于本版与版本头读不出都按「认识多少读多少」打开、本机不写回。源画面
///   取景住公开标记文件 `meta` 段，本地文档只承载
///   `session`／`prefs` 两段；
/// - **新增可选字段不抬版本号**：「键缺席即没有意见」这类**纯增量**字段
///   （`prefs.beatPrompt`、`prefs.castPrep` 与 `speedRate` 一族）不改形状，
///   旧读者把它当陌生键原样带回、新读者按缺席兜底，故只在**形状不兼容**
///   （丢键、换算、改词表语义）时才追加一条迁移步骤。
class LocalDocument {
  const LocalDocument({
    this.mastery = const {},
    this.activatedSegments = const [],
    this.previewSnapEnabled = true,
    this.layoutLocked = false,
    this.overlay,
    this.beatPrompt,
    this.castPrep,
    this.speedRate,
    this.practiceMirror,
    this.practiceClips = const [],
    this.activePracticeClipId,
    this.autoDelete = const MaterialAutoDeleteSettings(),
    this.extra = const {},
    this.sessionExtra = const {},
    this.prefsExtra = const {},
    this.overlayExtra = const {},
    this.memoryExtras = const {},
  });

  /// 空态文档（文件缺失/损坏/版本头缺失或不符合时按此兜底，不崩溃）。
  const LocalDocument.empty() : this();

  /// 本地文档的版本链：地板 3 + v3 → v4 一级迁移。本版版本号
  /// = [DocumentVersionPolicy.currentVersion]（链尾派生量）。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 3,
    steps: [MigrationStep(3, _migrateLocalV3ToV4)],
  );

  /// 学习段熟练度（按段序稀疏存储；未显式设置的段为「未练」）——
  /// `session` 段。
  final Map<int, LearningMastery> mastery;

  /// 激活学习段段序集合（恢复时不自动跳转、不自动播放）——`session` 段。
  final List<int> activatedSegments;

  /// 预览线吸附开关——`prefs` 段。
  final bool previewSnapEnabled;

  /// 锁定分段——`prefs` 段。
  final bool layoutLocked;

  /// 数拍浮层位（四格自定义偏移 + 两个共用尺寸系数；null = 文件无任何
  /// 浮层位字段，四格全未自定义）——`prefs.overlay`。
  final OverlayPlacementFields? overlay;

  /// 节拍提示记忆（null = 整份记录不存在，
  /// 即文件无 `beatPrompt` 键；记录在但字段全缺席 = 这支舞对所有项都
  /// 没有意见，两种状态可区分）——`prefs.beatPrompt`。
  final BeatPromptMemoryFields? beatPrompt;

  /// **投屏准备记忆**（#40；null = 整份记录不存在，即文件无 `castPrep` 键；
  /// 记录在但字段全缺席 = 这支舞对投屏准备没有意见，两种状态可区分）
  /// ——`prefs.castPrep`。
  ///
  /// 它**随这支舞**（不是设备级设置）：换一支舞就换一份——票 #40 的显式裁决；
  /// 可见性等级为**完全私密**（ADR-0002）：不进 susume 包、随整机备份走。
  final CastPrepMemoryFields? castPrep;

  /// 这支舞的手动倍率记忆（null = 这支舞没有
  /// 意见，生效值用出厂原速 1.0×，不新增设备级键）——`prefs` 段扁平单键。
  final double? speedRate;

  /// 练习侧镜像随舞覆盖（null = 未覆盖，生效值用
  /// 设备级默认）——`prefs` 段。
  final bool? practiceMirror;

  /// 练习视频轨的在轨片段列表——`prefs` 段。
  ///
  /// 口径：本字段是该舞练习视频轨的**真源**（每条 = 素材引用 + 截取范围），
  /// 与素材清单（私有素材目录的 `manifest.json`）是两份记录：片段引用清单里
  /// 的素材（每条片段都能在清单里追到 `materialId`），而清单是**超集**——
  /// 删除轨道引用不动素材、素材因此可以没有片段。故两处条数不必相等；打开
  /// 装载读回本字段后，写回即会话的完整视图（写入规则见
  /// `VideoSettingsPersistence._persistPreferences`）。
  final List<PracticeClip> practiceClips;

  /// 激活练习片段 id（恢复不自动跳转、不自动播放；null = 无片段激活）
  /// ——`session` 段。
  final String? activePracticeClipId;

  /// 每舞「自动删除」预留设置（默认关、保留最近
  /// 30 条 / 90 天；UI 与执行归首页舞详情）——`prefs` 段。
  final MaterialAutoDeleteSettings autoDelete;

  /// 未知文档级扩展字段（原样保留）。
  final Map<String, dynamic> extra;

  /// `session` 段未知键保底区（原样带回、写回原样）。
  final Map<String, dynamic> sessionExtra;

  /// `prefs` 段未知键保底区。
  final Map<String, dynamic> prefsExtra;

  /// `prefs.overlay` 子对象未知键保底区。
  final Map<String, dynamic> overlayExtra;

  /// **按舞记忆**子对象的未知键保底区（记忆键 → 该子对象的陌生键；原样带回、
  /// 写回原样）。整片读登记表（`_memoryBindings`）：加一份按舞记忆不再多一个
  /// 保底区字段。
  final Map<String, Map<String, dynamic>> memoryExtras;

  /// 全字段拷贝底座：withXxx 族与保底区装配（codec 的 withExtra）都经本
  /// 方法——新增字段只改本方法、值类与段声明处，不再逐处手抄。
  LocalDocument _copy({
    Map<int, LearningMastery>? mastery,
    List<int>? activatedSegments,
    bool? previewSnapEnabled,
    bool? layoutLocked,
    Object? overlay = _keepOverlay,
    Object? beatPrompt = _keepMemory,
    Object? castPrep = _keepMemory,
    double? speedRate,
    bool? practiceMirror,
    List<PracticeClip>? practiceClips,
    Object? activePracticeClipId = _keepActivePracticeClipId,
    MaterialAutoDeleteSettings? autoDelete,
    Map<String, dynamic>? extra,
  }) => LocalDocument(
    mastery: mastery ?? this.mastery,
    activatedSegments: activatedSegments ?? this.activatedSegments,
    previewSnapEnabled: previewSnapEnabled ?? this.previewSnapEnabled,
    layoutLocked: layoutLocked ?? this.layoutLocked,
    overlay: overlay == _keepOverlay
        ? this.overlay
        : overlay as OverlayPlacementFields?,
    beatPrompt: beatPrompt == _keepMemory
        ? this.beatPrompt
        : beatPrompt as BeatPromptMemoryFields?,
    castPrep: castPrep == _keepMemory
        ? this.castPrep
        : castPrep as CastPrepMemoryFields?,
    speedRate: speedRate ?? this.speedRate,
    practiceMirror: practiceMirror ?? this.practiceMirror,
    practiceClips: practiceClips ?? this.practiceClips,
    activePracticeClipId: activePracticeClipId == _keepActivePracticeClipId
        ? this.activePracticeClipId
        : activePracticeClipId as String?,
    autoDelete: autoDelete ?? this.autoDelete,
    extra: extra ?? this.extra,
    sessionExtra: sessionExtra,
    prefsExtra: prefsExtra,
    overlayExtra: overlayExtra,
    memoryExtras: memoryExtras,
  );

  LocalDocument withMastery(int order, LearningMastery mastery) {
    final next = Map<int, LearningMastery>.of(this.mastery);
    next[order] = mastery;
    return _copy(mastery: Map.unmodifiable(next));
  }

  /// 熟练度全表替换（保存编排按编辑快照绝对值落盘用）。
  LocalDocument withMasteryMap(Map<int, LearningMastery> mastery) =>
      _copy(mastery: Map.unmodifiable(Map<int, LearningMastery>.of(mastery)));

  /// `session` 段整段写回（保存编排的段级写回臂）：
  /// 段值为绝对终值（熟练度 + 激活学习段一起落定）；只触碰 `session`
  /// 段，不碰 `prefs` 段。
  LocalDocument withSession(LocalSessionValue session) => _copy(
    mastery: session.mastery,
    activatedSegments: session.activatedSegments,
    activePracticeClipId: session.activePracticeClipId,
  );

  LocalDocument withActivatedSegments(List<int> activatedSegments) =>
      _copy(activatedSegments: activatedSegments);

  LocalDocument withSnap({bool? previewSnapEnabled}) =>
      _copy(previewSnapEnabled: previewSnapEnabled);

  LocalDocument withLayoutLocked(bool layoutLocked) =>
      _copy(layoutLocked: layoutLocked);

  /// 数拍浮层位整组写入（四格偏移与两个共用系数的绝对终值；清除一格 =
  /// 该格缺席，文件里该格的两个键都消失）。
  LocalDocument withOverlayPlacements(OverlayPlacementFields? overlay) =>
      _copy(overlay: overlay != null && overlay.isUnset ? null : overlay);

  /// 节拍提示记忆整份写入：绝对终值——
  /// 传入的记录整体落定（含全字段缺席的空记录），null = 清除整份记录
  /// （文件不再有 `beatPrompt` 键）。
  LocalDocument withBeatPrompt(BeatPromptMemoryFields? beatPrompt) =>
      _copy(beatPrompt: beatPrompt);

  /// **投屏准备记忆**整份写入（#40）：绝对终值——传入的记录整体落定（含全
  /// 字段缺席的空记录），null = 清除整份记录（文件不再有 `castPrep` 键）。
  LocalDocument withCastPrep(CastPrepMemoryFields? castPrep) =>
      _copy(castPrep: castPrep);

  /// 这支舞的手动倍率记忆写入（无清除路径——文件缺该键即「没有意见」，
  /// 故参数为非空 double）。
  LocalDocument withSpeedRate(double speedRate) => _copy(speedRate: speedRate);

  /// 练习侧镜像随舞覆盖写入（与浮层位等可空字段同约定：null 参数 = 保持
  /// 现值；无清除覆盖的路径——文件缺该键即未覆盖）。
  LocalDocument withPracticeMirror(bool? practiceMirror) =>
      _copy(practiceMirror: practiceMirror);

  /// 练习片段列表整组写入（录制入轨/恢复写缝）；
  /// 源侧取景不在此写——它住公开标记文件的取景选区。
  LocalDocument withPracticeClips(List<PracticeClip> practiceClips) =>
      _copy(practiceClips: List.unmodifiable(practiceClips));

  Map<String, dynamic> toJson() => _localCodec.encode(this);

  /// 结构读取（版本政策）：政策把盘上 JSON 升到本版再读——v3 沿
  /// 链升到 v4（旧取景两键直接丢弃、不换算，见 [_migrateLocalV3ToV4]）；
  /// v1／v2 低于地板、整份丢弃；高于本版与版本头读不出都按「认识多少读
  /// 多少」打开（陌生键进保底区原样往返、本机不写回）。
  /// 非法值（未知熟练度名、越界系数）按对应缺省值/钳制兜底；未知键在
  /// 文档/段/overlay 层都原样保留进各保底区。
  factory LocalDocument.fromJson(Map<String, dynamic> json) =>
      _localCodec.decode(json);

  /// 相等与哈希经 [_localCodec]（逐段、只比已登记字段）。
  ///
  /// 各保底区（[extra]/[sessionExtra]/[prefsExtra]/[overlayExtra]/
  /// [memoryExtras]）刻意
  /// 不参与：扩展字段由 [fromJson] 每次读入带回、写回原样透传，不作为
  /// 变更判定依据——patch 不改本版本字段时按无变化跳写，文件里的扩展
  /// 字段也不会因此丢失。
  @override
  bool operator ==(Object other) =>
      other is LocalDocument && _localCodec.equals(this, other);

  @override
  int get hashCode => _localCodec.hash(this);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
  if (a.length != b.length) return false;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// 段声明（字段 id 枚举 + 穷尽 switch，机制派生读写/相等/保底）
// ---------------------------------------------------------------------------

enum _LocalSection { session, prefs }

/// `_copy` 可空字段的「保持现值」哨兵：片段激活写回需要能显式落 null，
/// 区别于不传参。
const Object _keepActivePracticeClipId = Object();

/// `_copy` **按舞记忆**字段的「保持现值」哨兵（两份记忆共用）：记忆写入以
/// 绝对终值落定，null = 清除整份记录，区别于不传参。
const Object _keepMemory = Object();

/// `_copy` 浮层位字段的「保持现值」哨兵：整组写入需要能显式落 null =
/// 无任何浮层位字段，区别于不传参。
const Object _keepOverlay = Object();

final DocumentCodec<LocalDocument, _LocalSection> _localCodec =
    DocumentCodec<LocalDocument, _LocalSection>(
      policy: LocalDocument.versionPolicy,
      ids: _LocalSection.values,
      decl: _localSectionDecl,
      empty: LocalDocument.empty,
      build: _buildLocalDocument,
      extraOf: (doc) => doc.extra,
      withExtra: (doc, extra) => doc._copy(extra: extra),
    );

/// v3 → v4 迁移步骤（纯函数侧）：丢掉旧取景两键
/// `prefs.framingSource`／`prefs.framingPractice`，**不换算**——升级后旧舞
/// 取景回未调过的起手构图；其余全部字段、段、逐层陌生键**逐字不变**。
/// **不写版本号**（政策在每级之后自己写）。
Map<String, Object?> _migrateLocalV3ToV4(Map<String, Object?> json) {
  final next = Map<String, Object?>.of(json);
  final prefs = json['prefs'];
  if (prefs is Map<String, Object?> &&
      (prefs.containsKey('framingSource') ||
          prefs.containsKey('framingPractice'))) {
    next['prefs'] = Map<String, Object?>.of(prefs)
      ..remove('framingSource')
      ..remove('framingPractice');
  }
  return next;
}

SectionDecl<LocalDocument> _localSectionDecl(_LocalSection id) => switch (id) {
  _LocalSection.session => SectionDecl(
    key: 'session',
    codec: _sessionCodec,
    sectionOf: (doc) => _SessionValue(
      mastery: doc.mastery,
      activatedSegments: doc.activatedSegments,
      activePracticeClipId: doc.activePracticeClipId,
      extra: doc.sessionExtra,
    ),
  ),
  _LocalSection.prefs => SectionDecl(
    key: 'prefs',
    codec: _prefsCodec,
    sectionOf: (doc) => _PrefsValue(
      previewSnapEnabled: doc.previewSnapEnabled,
      layoutLocked: doc.layoutLocked,
      overlay: _OverlayValue(
        fields: doc.overlay ?? const OverlayPlacementFields(),
        extra: doc.overlayExtra,
      ),
      memories: _memoryCellsOf(doc),
      speedRate: doc.speedRate,
      practiceMirror: doc.practiceMirror,
      practiceClips: doc.practiceClips,
      autoDelete: doc.autoDelete,
      extra: doc.prefsExtra,
    ),
  ),
};

LocalDocument _buildLocalDocument(Map<_LocalSection, Object?> sections) {
  final session = sections[_LocalSection.session] as _SessionValue;
  final prefs = sections[_LocalSection.prefs] as _PrefsValue;
  return LocalDocument(
    mastery: session.mastery,
    activatedSegments: session.activatedSegments,
    activePracticeClipId: session.activePracticeClipId,
    previewSnapEnabled: prefs.previewSnapEnabled,
    layoutLocked: prefs.layoutLocked,
    overlay: prefs.overlay.isUnset ? null : prefs.overlay.fields,
    // 按舞记忆：段里那一格 → 文档字段（`present` 假即 null）。这两行与
    // `_memoryBindings` 上那两行成对——`LocalDocument` 的字段是**类型化**的，
    // 由编译器逐处强制，故这里绕不开（`#47` 验收第 1 条剩下的那一半）。
    beatPrompt:
        _beatPromptBinding.fieldIn(prefs.memories) as BeatPromptMemoryFields?,
    castPrep: _castPrepBinding.fieldIn(prefs.memories) as CastPrepMemoryFields?,
    speedRate: prefs.speedRate,
    practiceMirror: prefs.practiceMirror,
    practiceClips: prefs.practiceClips,
    autoDelete: prefs.autoDelete,
    sessionExtra: session.extra,
    prefsExtra: prefs.extra,
    overlayExtra: prefs.overlay.extra,
    memoryExtras: _memoryExtrasOf(prefs.memories),
  );
}

// --- session 段（保存编排写：熟练度 + 激活段） --------------------------------

class _SessionValue {
  const _SessionValue({
    this.mastery = const {},
    this.activatedSegments = const [],
    this.activePracticeClipId,
    this.extra = const {},
  });

  final Map<int, LearningMastery> mastery;
  final List<int> activatedSegments;

  /// 激活练习片段 id（null = 无片段激活）。
  final String? activePracticeClipId;
  final Map<String, Object?> extra;
}

enum _SessionField { mastery, activatedSegments, activePracticeClipId }

final RecordCodec<_SessionValue, _SessionField> _sessionCodec =
    RecordCodec<_SessionValue, _SessionField>(
      ids: _SessionField.values,
      decl: _sessionDecl,
      build: _buildSession,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _SessionValue(
        mastery: v.mastery,
        activatedSegments: v.activatedSegments,
        activePracticeClipId: v.activePracticeClipId,
        extra: extra,
      ),
    );

FieldDecl<_SessionValue> _sessionDecl(_SessionField id) => switch (id) {
  _SessionField.mastery => FieldDecl(
    key: 'mastery',
    read: (json) {
      final raw = json['mastery'];
      if (raw is! Map<String, dynamic>) return const <int, LearningMastery>{};
      final mastery = <int, LearningMastery>{};
      for (final entry in raw.entries) {
        final order = int.tryParse(entry.key);
        if (order == null || order < 0) continue;
        // 旧三态名在读取时映射为五档；未知/非法名按缺省「未练」兜底
        // （不落 Map，稀疏存储不变）。
        final value = learningMasteryFromName(entry.value);
        if (value != null) mastery[order] = value;
      }
      return Map<int, LearningMastery>.unmodifiable(mastery);
    },
    write: (v) => {
      for (final entry in v.mastery.entries) '${entry.key}': entry.value.name,
    },
    equal: (a, b) => _mapEquals(a.mastery, b.mastery),
  ),
  _SessionField.activatedSegments => FieldDecl(
    key: 'activatedSegments',
    read: (json) => json['activatedSegments'] is List
        ? List<int>.unmodifiable([
            for (final item in json['activatedSegments'] as List)
              if (item is int) item,
          ])
        : const <int>[],
    write: (v) => [...v.activatedSegments],
    equal: (a, b) => _listEquals(a.activatedSegments, b.activatedSegments),
  ),
  _SessionField.activePracticeClipId => FieldDecl(
    key: 'activePracticeClipId',
    read: (json) => json['activePracticeClipId'] is String
        ? json['activePracticeClipId'] as String
        : null,
    // 承诺：无片段激活（null）不写该键——缺键即无激活。
    write: (v) => v.activePracticeClipId ?? omitField,
    equal: (a, b) => a.activePracticeClipId == b.activePracticeClipId,
  ),
};

_SessionValue _buildSession(Map<_SessionField, Object?> values) =>
    _SessionValue(
      mastery: values[_SessionField.mastery] as Map<int, LearningMastery>,
      activatedSegments: values[_SessionField.activatedSegments] as List<int>,
      activePracticeClipId:
          values[_SessionField.activePracticeClipId] as String?,
    );

// --- prefs 段（编辑偏好持久化写：吸附/锁定分段 + 浮层） ------------------

class _PrefsValue {
  _PrefsValue({
    this.previewSnapEnabled = true,
    this.layoutLocked = false,
    this.overlay = const _OverlayValue(),
    Map<String, Object?>? memories,
    this.speedRate,
    this.practiceMirror,
    this.practiceClips = const [],
    this.autoDelete = const MaterialAutoDeleteSettings(),
    this.extra = const {},
  }) : memories = memories ?? _absentMemories();

  final bool previewSnapEnabled;
  final bool layoutLocked;

  final _OverlayValue overlay;

  /// **按舞记忆那一片**（`#47`）：键 → 段里那一格（[_Memory]；`present` 假 =
  /// 文件无那个键）。每份记忆仍是「一个键一格」，但整片由登记表
  /// （[_memoryBindings]）派生——加一份按舞记忆不再动 `prefs` 段的编解码。
  final Map<String, Object?> memories;

  /// 手动倍率记忆（null = 文件无该键）。
  final double? speedRate;
  final bool? practiceMirror;

  final List<PracticeClip> practiceClips;

  final MaterialAutoDeleteSettings autoDelete;

  final Map<String, Object?> extra;
}

enum _PrefsField {
  previewSnapEnabled,
  layoutLocked,
  overlay,
  // **按舞记忆**那几格：取值名就是它在 `prefs` 段里的键名（`_memoryByKey`
  // 据此认出它们，见 `_prefsDecl`）——加一份按舞记忆 = 这里加一个同名取值 +
  // 登记表加一行，声明分支与装配都不逐份写（`#47`）。
  beatPrompt,
  castPrep,
  speedRate,
  practiceMirror,
  practiceClips,
  autoDelete,
}

final RecordCodec<_PrefsValue, _PrefsField> _prefsCodec =
    RecordCodec<_PrefsValue, _PrefsField>(
      ids: _PrefsField.values,
      decl: _prefsDecl,
      build: _buildPrefs,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _PrefsValue(
        previewSnapEnabled: v.previewSnapEnabled,
        layoutLocked: v.layoutLocked,
        overlay: v.overlay,
        memories: v.memories,
        speedRate: v.speedRate,
        practiceMirror: v.practiceMirror,
        practiceClips: v.practiceClips,
        autoDelete: v.autoDelete,
        extra: extra,
      ),
    );

FieldDecl<_PrefsValue> _prefsDecl(_PrefsField id) {
  // **按舞记忆那几格读登记表**（`#47`）：取值名 = 键名（`beatPrompt` /
  // `castPrep`），故读 / 写 / 判等只需查一次登记——加一份按舞记忆不必在这里
  // 加一条声明分支（剩下的非记忆字段各占一格）。
  final memory = _memoryByKey[id.name];
  if (memory != null) {
    return FieldDecl<_PrefsValue>(
      key: memory.key,
      read: (json) => memory.read(json),
      // 承诺：整份记录不存在（记录缺席）不写该键——缺键即无记录；记录在但字段
      // 全缺席仍写空对象（与无记录是两种状态）。
      write: (v) => memory.write(v.memories[memory.key]),
      equal: (a, b) =>
          memory.equals(a.memories[memory.key], b.memories[memory.key]),
    );
  }
  return switch (id) {
    _PrefsField.previewSnapEnabled => FieldDecl(
      key: 'previewSnapEnabled',
      read: (json) => json['previewSnapEnabled'] as bool? ?? true,
      write: (v) => v.previewSnapEnabled,
      equal: (a, b) => a.previewSnapEnabled == b.previewSnapEnabled,
    ),
    _PrefsField.layoutLocked => FieldDecl(
      key: 'layoutLocked',
      read: (json) => json['layoutLocked'] as bool? ?? false,
      write: (v) => v.layoutLocked,
      equal: (a, b) => a.layoutLocked == b.layoutLocked,
    ),
    _PrefsField.overlay => FieldDecl(
      key: 'overlay',
      read: (json) => json['overlay'] is Map<String, Object?>
          ? _overlayCodec.decode(json['overlay'] as Map<String, Object?>)
          : const _OverlayValue(),
      // 承诺：无自定义浮层（四个字段全未设）不写该键。
      write: (v) =>
          v.overlay.isUnset ? omitField : _overlayCodec.encode(v.overlay),
      equal: (a, b) => _overlayCodec.equals(a.overlay, b.overlay),
    ),
    _PrefsField.speedRate => FieldDecl(
      key: 'speedRate',
      read: (json) => _readSpeedRate(json['speedRate']),
      // 承诺：没有意见（null）不写该键——缺键即无记忆。
      write: (v) => v.speedRate ?? omitField,
      equal: (a, b) => a.speedRate == b.speedRate,
    ),
    _PrefsField.practiceMirror => FieldDecl(
      key: 'practiceMirror',
      read: (json) => json['practiceMirror'] is bool
          ? json['practiceMirror'] as bool
          : null,
      // 承诺：未覆盖（null）不写该键——覆盖值缺省即用设备级值。
      write: (v) => v.practiceMirror ?? omitField,
      equal: (a, b) => a.practiceMirror == b.practiceMirror,
    ),
    _PrefsField.practiceClips => FieldDecl(
      key: 'practiceClips',
      read: (json) => json['practiceClips'] is List
          ? List<PracticeClip>.unmodifiable([
              for (final item in json['practiceClips'] as List)
                ?PracticeClip.fromJson(item),
            ])
          : const <PracticeClip>[],
      write: (v) => v.practiceClips.isEmpty
          ? omitField
          : [for (final clip in v.practiceClips) clip.toJson()],
      equal: (a, b) => _listEquals(a.practiceClips, b.practiceClips),
    ),
    _PrefsField.autoDelete => FieldDecl(
      key: 'autoDelete',
      read: (json) => _readAutoDelete(json['autoDelete']),
      // 承诺：默认设置（关 + 30 条 / 90 天）不写该键——缺键即默认值。
      write: (v) => v.autoDelete == const MaterialAutoDeleteSettings()
          ? omitField
          : {
              'enabled': v.autoDelete.enabled,
              'strategy': switch (v.autoDelete.strategy) {
                MaterialAutoDeleteStrategy.keepRecentCount => 'count',
                MaterialAutoDeleteStrategy.keepRecentDays => 'days',
              },
              'keepCount': v.autoDelete.keepCount,
              'keepDays': v.autoDelete.keepDays,
            },
      equal: (a, b) => a.autoDelete == b.autoDelete,
    ),
    // 记忆那几格在上面查登记表时已经返回（取值名 = 键名）；这里只是让 switch
    // 对枚举穷尽——走到这里说明登记表少了一行。
    _PrefsField.beatPrompt || _PrefsField.castPrep => throw StateError(
      '按舞记忆 ${id.name} 不在登记表（_memoryBindings）里',
    ),
  };
}

_PrefsValue _buildPrefs(Map<_PrefsField, Object?> values) => _PrefsValue(
  previewSnapEnabled: values[_PrefsField.previewSnapEnabled] as bool,
  layoutLocked: values[_PrefsField.layoutLocked] as bool,
  overlay: values[_PrefsField.overlay] as _OverlayValue,
  // 记忆那一片按登记表装配（键名 → 字段 id 同名），不逐份手抄。
  memories: {
    for (final binding in _memoryBindings)
      binding.key: values[_PrefsField.values.byName(binding.key)],
  },
  speedRate: values[_PrefsField.speedRate] as double?,
  practiceMirror: values[_PrefsField.practiceMirror] as bool?,
  practiceClips: values[_PrefsField.practiceClips] as List<PracticeClip>,
  autoDelete: values[_PrefsField.autoDelete] as MaterialAutoDeleteSettings,
);

/// 手动倍率记忆读取兜底：数值经两位小数
/// 取整并钳进 0.1–2.0 的检查——越界或形状不对一律按缺席兜底，不抛错。
double? _readSpeedRate(Object? raw) {
  if (raw is! num) return null;
  final value = raw.toDouble();
  if (value < 0.1 || value > 2.0) return null;
  return double.parse(value.toStringAsFixed(2));
}

/// 自动删除预留设置读取兜底：键缺失/形状不对/字段畸形逐项回默认
/// 值（关 + 保留最近条数 + 30 条 / 90 天）。
MaterialAutoDeleteSettings _readAutoDelete(Object? raw) {
  if (raw is! Map<String, dynamic>) return const MaterialAutoDeleteSettings();
  return MaterialAutoDeleteSettings(
    enabled: raw['enabled'] is bool ? raw['enabled'] as bool : false,
    strategy: switch (raw['strategy']) {
      'days' => MaterialAutoDeleteStrategy.keepRecentDays,
      _ => MaterialAutoDeleteStrategy.keepRecentCount,
    },
    keepCount: raw['keepCount'] is int
        ? raw['keepCount'] as int
        : kDefaultMaterialAutoDeleteKeepCount,
    keepDays: raw['keepDays'] is int
        ? raw['keepDays'] as int
        : kDefaultMaterialAutoDeleteKeepDays,
  );
}

// --- 按舞记忆：存在性包裹的子对象（一个键 + 一张字段表） -----------------------

/// **一份按舞记住的取值**在段里的存在性包裹：`present` 区分「文件里没有这个
/// 键」与「键在、字段全缺席」两种状态（后者仍写空对象）。
class _Memory<T> {
  const _Memory(this.fields, {this.extra = const {}, this.present = true});

  /// 文件里没有这个键（整份记录不存在）。
  const _Memory.absent(this.fields) : extra = const {}, present = false;

  final T fields;
  final Map<String, Object?> extra;
  final bool present;
}

/// **存在性包裹的子对象声明**：一个键 + 一张字段表（字段 id 枚举 + 穷尽 switch
/// + 装配）即得该子对象在 `prefs` 段的编解码、陌生键保底与那一格的读 / 写 /
/// 相等。新增一份按舞记住的取值 = 加一条这样的声明 + 登记表
/// （`_memoryBindings`）里一行 + `LocalDocument` 上那两个类型化字段（编译器
/// 逐处强制，见 `_buildLocalDocument`）。
class _MemoryDecl<T, F extends Enum> {
  _MemoryDecl({
    required this.key,
    required this.ids,
    required this.decl,
    required this.build,
    required this.empty,
  }) : codec = RecordCodec<_Memory<T>, F>(
          ids: ids,
          decl: (id) => _wrappedField(decl(id)),
          build: (values) => _Memory(build(values)),
          extraOf: (v) => v.extra,
          withExtra: (v, extra) =>
              _Memory(v.fields, extra: extra, present: v.present),
        );

  /// 这份记忆在 `prefs` 段里的键名。
  final String key;

  /// 字段表：id 枚举 + 逐格声明（键名 / 读 / 写）。
  final List<F> ids;
  final FieldDecl<T> Function(F id) decl;

  /// 字段表的装配。
  final T Function(Map<F, Object?> values) build;

  /// 空值构造（整份记录缺席时段值的占位；缺席的记录不会被写出去）。
  final T Function() empty;

  final RecordCodec<_Memory<T>, F> codec;

  /// 文件里没有这个键。
  _Memory<T> absent() => _Memory.absent(empty());

  /// 文档字段（null = 无记录）+ 它的陌生键保底区 → 段值。
  _Memory<T> of(T? fields, Map<String, Object?> extra) =>
      fields == null ? absent() : _Memory(fields, extra: extra);

  /// 读这一格：键不在、或形状不是对象，都按整份记录不存在。
  _Memory<T> read(Map<String, Object?> prefs) {
    final raw = prefs[key];
    if (raw is! Map<String, Object?>) return absent();
    return codec.decode(raw);
  }

  /// 写这一格：整份记录不存在（null）不写该键——缺键即无记录；记录在但字段全
  /// 缺席仍写空对象（与无记录是两种状态）。
  Object? write(_Memory<T> value) =>
      value.present ? codec.encode(value) : omitField;

  /// 这一格的相等：存在性 + 已登记字段逐格（保底区不参与）。
  bool equals(_Memory<T> a, _Memory<T> b) =>
      a.present == b.present && (!a.present || codec.equals(a, b));
}

/// **一份按舞记忆的登记项**（`#47`）：一份 [_MemoryDecl]（键 + 字段表，那一格的
/// 读写判等都在里面）+ 它在**文档模型**上那两处的换算，类型擦除成 `Object?`
/// ——`prefs` 段因此只留**一片** `键 → 段值` 的表（`_PrefsValue.memories`），
/// 不逐份记忆各占一个字段 id 与一条声明分支。
///
/// 新增一份按舞记忆 = 一条 [_MemoryDecl]（一个键 + 一张字段表）+ 登记表
/// （`_memoryBindings`）里一行 + `LocalDocument` 上那两个类型化字段（由编译器
/// 逐处强制，见 `_buildLocalDocument`）。
class _MemoryBinding {
  _MemoryBinding({
    required this.key,
    required this.absent,
    required this.read,
    required this.write,
    required this.equals,
    required this.documentOf,
    required this.documentExtraOf,
    required this.ofDocument,
    required this.documentField,
    required this.documentFieldExtra,
  });

  /// 这份记忆在 `prefs` 段里的键名（与它那份 `_MemoryDecl.key` 同一个）。
  final String key;

  /// 文件里没有这个键时的段值（缺席的记录不会被写出去）。
  final Object? Function() absent;

  /// 读这一格（键不在、或形状不是对象，都按整份记录不存在）。
  final Object? Function(Map<String, Object?> prefs) read;

  /// 写这一格（记录缺席给 [omitField]；记录在但字段全缺席仍写空对象）。
  final Object? Function(Object? cell) write;

  /// 这一格的相等（存在性 + 已登记字段逐格，保底区不参与）。
  final bool Function(Object? a, Object? b) equals;

  /// 段值 → 文档字段（`present` 假即 null = 没有记录）。
  final Object? Function(Object? cell) documentOf;

  /// 段值 → 它的陌生键保底区。
  final Map<String, Object?> Function(Object? cell) documentExtraOf;

  /// 文档字段 + 它的陌生键保底区 → 段值。
  final Object? Function(Object? document, Map<String, Object?> extra)
      ofDocument;

  /// 文档模型上的那个**类型化字段**。
  final Object? Function(LocalDocument document) documentField;

  /// 文档模型上那个字段的陌生键保底区。
  final Map<String, Object?> Function(LocalDocument document)
      documentFieldExtra;

  /// 这一份记忆在**段值片**里的文档字段（`present` 假即 null = 没有记录）。
  Object? fieldIn(Map<String, Object?> memories) {
    final cell = memories[key];
    return cell == null ? null : documentOf(cell);
  }

  /// 这一份记忆在**段值片**里的陌生键保底区。
  Map<String, dynamic> extraIn(Map<String, Object?> memories) {
    final cell = memories[key];
    return cell == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.of(documentExtraOf(cell));
  }
}

/// 把一份 [decl]（键 + 字段表）与它在文档模型上的那个**类型化字段**绑成一行
/// 登记。陌生键保底区不必另给：它按同一个键住在 `LocalDocument.memoryExtras`
/// 里（键就是 [decl] 的键）。
_MemoryBinding _memoryBinding<T, F extends Enum>({
  required _MemoryDecl<T, F> decl,
  required T? Function(LocalDocument document) documentField,
}) => _MemoryBinding(
  key: decl.key,
  absent: () => decl.absent(),
  read: decl.read,
  write: (cell) => decl.write(cell as _Memory<T>),
  equals: (a, b) => decl.equals(a as _Memory<T>, b as _Memory<T>),
  documentOf: (cell) {
    final memory = cell as _Memory<T>;
    return memory.present ? memory.fields : null;
  },
  documentExtraOf: (cell) => (cell as _Memory<T>).extra,
  ofDocument: (document, extra) => decl.of(document as T?, extra),
  documentField: (document) => documentField(document),
  documentFieldExtra: (document) => document.memoryExtras[decl.key] ?? const {},
);

/// 键 → 登记项：`_PrefsField` 那几格（**取值名即键名**）与派生的装配都查它。
final Map<String, _MemoryBinding> _memoryByKey = {
  for (final binding in _memoryBindings) binding.key: binding,
};

/// 全部按舞记忆的**缺席格**（文件里一个键都没有）：`prefs` 段值的起手形状。
Map<String, Object?> _absentMemories() => {
  for (final binding in _memoryBindings) binding.key: binding.absent(),
};

/// 文档模型 → 按舞记忆那一片（每份记忆：文档字段 + 它的陌生键保底区）。
Map<String, Object?> _memoryCellsOf(LocalDocument document) => {
  for (final binding in _memoryBindings)
    binding.key: binding.ofDocument(
      binding.documentField(document),
      binding.documentFieldExtra(document),
    ),
};

/// 段值 → 文档模型上按舞记忆的陌生键保底区（记忆键 → 保底区；空的不入表）。
Map<String, Map<String, dynamic>> _memoryExtrasOf(
  Map<String, Object?> memories,
) {
  final extras = <String, Map<String, dynamic>>{};
  for (final binding in _memoryBindings) {
    final extra = binding.extraIn(memories);
    if (extra.isNotEmpty) extras[binding.key] = extra;
  }
  return extras;
}

/// 把字段表里的一格抬到存在性包裹上：读、写、判等仍走那一格。
FieldDecl<_Memory<T>> _wrappedField<T>(FieldDecl<T> field) =>
    FieldDecl<_Memory<T>>(
      key: field.key,
      read: (json) => field.read(json),
      write: (m) => field.write(m.fields),
      equal: (a, b) => field.equal(a.fields, b.fields),
    );

/// 记忆单元的一格：从字段值读出它、按词表读入、写出——没有意见（null）即
/// [omitField]（键不落盘）；[write] 可给出更细的省略口径（例如空表）。
/// **相等由写出的 JSON 值派生**（与 `RecordCodec.hash` 同一份口径）：列表与
/// 嵌套值一视同仁，加一格不必再手写判等。
FieldDecl<T> _memoryField<T, V>({
  required String key,
  required V? Function(T fields) read,
  required V? Function(Object? raw) parse,
  Object? Function(V value)? write,
}) {
  Object? written(T fields) {
    final value = read(fields);
    if (value == null) return omitField;
    return write == null ? value : write(value);
  }

  return FieldDecl<T>(
    key: key,
    read: (json) => parse(json[key]),
    write: written,
    equal: (a, b) => jsonDeepEquals(written(a), written(b)),
  );
}

bool? _parseBool(Object? raw) => raw is bool ? raw : null;

String? _parseName(Object? raw, Set<String> vocabulary) =>
    raw is String && vocabulary.contains(raw) ? raw : null;

// --- beatPrompt（节拍提示记忆：五个值逐字段可缺席） --------------------------

enum _BeatPromptField { animation, animationStyle, sound, soundType, halfBeat }

final _MemoryDecl<BeatPromptMemoryFields, _BeatPromptField> _beatPromptMemory =
    _MemoryDecl(
      key: 'beatPrompt',
      ids: _BeatPromptField.values,
      decl: _beatPromptDecl,
      build: _buildBeatPrompt,
      empty: () => const BeatPromptMemoryFields(),
    );

FieldDecl<BeatPromptMemoryFields> _beatPromptDecl(_BeatPromptField id) =>
    switch (id) {
      _BeatPromptField.animation => _memoryField(
        key: 'animation',
        read: (f) => f.animation,
        parse: _parseBool,
      ),
      _BeatPromptField.animationStyle => _memoryField(
        key: 'animationStyle',
        read: (f) => f.animationStyle,
        parse: (raw) => _parseName(raw, const {'bar', 'pendulum'}),
      ),
      _BeatPromptField.sound => _memoryField(
        key: 'sound',
        read: (f) => f.sound,
        parse: _parseBool,
      ),
      _BeatPromptField.soundType => _memoryField(
        key: 'soundType',
        read: (f) => f.soundType,
        parse: (raw) => _parseName(raw, const {'normal', 'vocal', 'geigi'}),
      ),
      _BeatPromptField.halfBeat => _memoryField(
        key: 'halfBeat',
        read: (f) => f.halfBeat,
        parse: _parseBool,
      ),
    };

BeatPromptMemoryFields _buildBeatPrompt(
  Map<_BeatPromptField, Object?> values,
) => BeatPromptMemoryFields(
  animation: values[_BeatPromptField.animation] as bool?,
  animationStyle: values[_BeatPromptField.animationStyle] as String?,
  sound: values[_BeatPromptField.sound] as bool?,
  soundType: values[_BeatPromptField.soundType] as String?,
  halfBeat: values[_BeatPromptField.halfBeat] as bool?,
);

// --- castPrep（投屏准备记忆#40：两个勾选档 + 档表，逐字段可缺席） -------------

enum _CastPrepField { picture, sound, tiers }

final _MemoryDecl<CastPrepMemoryFields, _CastPrepField> _castPrepMemory =
    _MemoryDecl(
      key: 'castPrep',
      ids: _CastPrepField.values,
      decl: _castPrepDecl,
      build: _buildCastPrep,
      empty: () => const CastPrepMemoryFields(),
    );

FieldDecl<CastPrepMemoryFields> _castPrepDecl(_CastPrepField id) => switch (id) {
  _CastPrepField.picture => _memoryField(
    key: 'picture',
    read: (f) => f.picture,
    parse: _parseBool,
  ),
  _CastPrepField.sound => _memoryField(
    key: 'sound',
    read: (f) => f.sound,
    parse: _parseBool,
  ),
  _CastPrepField.tiers => _memoryField(
    key: 'tiers',
    // 空表 = 没有意见：不写该键（与 practiceClips 同款）——「档位一档都不要」
    // 这条到不了的状态因此不存在。
    read: (f) => f.tiers,
    parse: _parseCastTiers,
    write: (tiers) => tiers.isEmpty ? omitField : [...tiers],
  ),
};

CastPrepMemoryFields _buildCastPrep(Map<_CastPrepField, Object?> values) =>
    CastPrepMemoryFields(
      picture: values[_CastPrepField.picture] as bool?,
      sound: values[_CastPrepField.sound] as bool?,
      tiers: values[_CastPrepField.tiers] as List<String>,
    );

/// 档位记号表读取：非表按空表；逐项只认**字符串**。
///
/// 记号本身的**词表是投屏域的事实**（候选档的 `token`，见
/// `cast_speed_tier.dart`）：文档层不抄第二遍，认不得的记号也照原样带回与写回
/// （本版不认得的记号多半是未来版本写下的档），**认不认得由投屏域的值边界
/// 回答**（`player/cast_prep_memory.dart` 的降级规则）。
List<String> _parseCastTiers(Object? raw) {
  if (raw is! List) return const [];
  return List<String>.unmodifiable([
    for (final item in raw)
      if (item is String) item,
  ]);
}

// --- 按舞记忆的登记表（每份记忆一行；`prefs` 段的读写判等与文档字段两端换算
//     都读它，不逐份记忆另写一遍） ------------------------------------------

/// 节拍提示记忆的登记（键 + 字段表在 `_beatPromptMemory`）。
final _beatPromptBinding = _memoryBinding(
  decl: _beatPromptMemory,
  documentField: (document) => document.beatPrompt,
);

/// 投屏准备记忆的登记（键 + 字段表在 `_castPrepMemory`）。
final _castPrepBinding = _memoryBinding(
  decl: _castPrepMemory,
  documentField: (document) => document.castPrep,
);

/// **全部按舞记忆的登记表**（次序即它们写进 `prefs` 段的次序）。
final List<_MemoryBinding> _memoryBindings = [
  _beatPromptBinding,
  _castPrepBinding,
];

// --- overlay 子对象（浮层位四格 + 分形态系数） --------------------------------

class _OverlayValue {
  const _OverlayValue({
    this.fields = const OverlayPlacementFields(),
    this.extra = const {},
  });

  final OverlayPlacementFields fields;
  final Map<String, Object?> extra;

  bool get isUnset => fields.isUnset;
}

enum _OverlayField {
  dx,
  dy,
  landscapeDx,
  landscapeDy,
  compareDx,
  compareDy,
  landscapeCompareDx,
  landscapeCompareDy,
  rectWidthFactor,
  pendulumScale,
}

final RecordCodec<_OverlayValue, _OverlayField> _overlayCodec =
    RecordCodec<_OverlayValue, _OverlayField>(
      ids: _OverlayField.values,
      decl: _overlayDecl,
      build: _buildOverlay,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _OverlayValue(fields: v.fields, extra: extra),
    );

FieldDecl<_OverlayValue> _overlayDecl(_OverlayField id) => switch (id) {
  _OverlayField.dx => _overlayCellDecl(key: 'dx', read: (f) => f.dx),
  _OverlayField.dy => _overlayCellDecl(key: 'dy', read: (f) => f.dy),
  _OverlayField.landscapeDx => _overlayCellDecl(
    key: 'landscapeDx',
    read: (f) => f.landscapeDx,
  ),
  _OverlayField.landscapeDy => _overlayCellDecl(
    key: 'landscapeDy',
    read: (f) => f.landscapeDy,
  ),
  _OverlayField.compareDx => _overlayCellDecl(
    key: 'compareDx',
    read: (f) => f.compareDx,
  ),
  _OverlayField.compareDy => _overlayCellDecl(
    key: 'compareDy',
    read: (f) => f.compareDy,
  ),
  _OverlayField.landscapeCompareDx => _overlayCellDecl(
    key: 'landscapeCompareDx',
    read: (f) => f.landscapeCompareDx,
  ),
  _OverlayField.landscapeCompareDy => _overlayCellDecl(
    key: 'landscapeCompareDy',
    read: (f) => f.landscapeCompareDy,
  ),
  _OverlayField.rectWidthFactor => FieldDecl(
    key: 'rectWidthFactor',
    // 系数读取兜底：非法值钳制进 0.5–3.0（缺键保持未设）。
    read: (json) => _clampOverlayFactor(
      json['rectWidthFactor'] is num
          ? (json['rectWidthFactor'] as num).toDouble()
          : null,
    ),
    write: (v) => v.fields.rectWidthFactor ?? omitField,
    equal: (a, b) => a.fields.rectWidthFactor == b.fields.rectWidthFactor,
  ),
  _OverlayField.pendulumScale => FieldDecl(
    key: 'pendulumScale',
    read: (json) => _clampOverlayFactor(
      json['pendulumScale'] is num
          ? (json['pendulumScale'] as num).toDouble()
          : null,
    ),
    write: (v) => v.fields.pendulumScale ?? omitField,
    equal: (a, b) => a.fields.pendulumScale == b.fields.pendulumScale,
  ),
};

/// 一格的单轴键声明：缺席（该格未自定义）时写 [omitField]。
FieldDecl<_OverlayValue> _overlayCellDecl({
  required String key,
  required double? Function(OverlayPlacementFields fields) read,
}) => FieldDecl<_OverlayValue>(
  key: key,
  read: (json) => json[key] is num ? (json[key] as num).toDouble() : null,
  write: (v) => read(v.fields) ?? omitField,
  equal: (a, b) => read(a.fields) == read(b.fields),
);

_OverlayValue _buildOverlay(Map<_OverlayField, Object?> values) {
  // 一格的两个键**同时存在**才算该格已自定义；缺任一个键即整格置空。
  ({double? dx, double? dy}) pair(
    _OverlayField horizontal,
    _OverlayField vertical,
  ) {
    final dx = values[horizontal];
    final dy = values[vertical];
    if (dx is! double || dy is! double) {
      return (dx: null, dy: null);
    }
    return (dx: dx, dy: dy);
  }

  final portraitNormal = pair(_OverlayField.dx, _OverlayField.dy);
  final landscapeNormal = pair(
    _OverlayField.landscapeDx,
    _OverlayField.landscapeDy,
  );
  final portraitCompare = pair(
    _OverlayField.compareDx,
    _OverlayField.compareDy,
  );
  final landscapeCompare = pair(
    _OverlayField.landscapeCompareDx,
    _OverlayField.landscapeCompareDy,
  );
  return _OverlayValue(
    fields: OverlayPlacementFields(
      dx: portraitNormal.dx,
      dy: portraitNormal.dy,
      landscapeDx: landscapeNormal.dx,
      landscapeDy: landscapeNormal.dy,
      compareDx: portraitCompare.dx,
      compareDy: portraitCompare.dy,
      landscapeCompareDx: landscapeCompare.dx,
      landscapeCompareDy: landscapeCompare.dy,
      rectWidthFactor: values[_OverlayField.rectWidthFactor] as double?,
      pendulumScale: values[_OverlayField.pendulumScale] as double?,
    ),
  );
}

/// 浮层系数读取兜底：非法值钳制进 0.5–3.0（null 保持未设）。
double? _clampOverlayFactor(double? value) {
  if (value == null) return null;
  return value.clamp(0.5, 3.0).toDouble();
}
