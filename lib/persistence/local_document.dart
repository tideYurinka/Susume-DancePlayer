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

/// 本地文档 `local_<hash>.json` 的 schema v4 文档模型。
///
/// 文件形状 = 两段 + 版本号，段与写入者一一对应：
/// - `session`（保存编排写）：熟练度（按段序）、激活学习段；
/// - `prefs`（编辑偏好持久化会话写）：预览吸附开关、锁定分段、数拍
///   浮层位置（左上角 x/y）与分形态系数（矩形宽系数、摆锤等比系数）、
///   节拍提示记忆（`prefs.beatPrompt`，五个值逐字段可缺席）。
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
///   `session`／`prefs` 两段。
class LocalDocument {
  const LocalDocument({
    this.mastery = const {},
    this.activatedSegments = const [],
    this.previewSnapEnabled = true,
    this.layoutLocked = false,
    this.overlay,
    this.beatPrompt,
    this.speedRate,
    this.practiceMirror,
    this.practiceClips = const [],
    this.activePracticeClipId,
    this.autoDelete = const MaterialAutoDeleteSettings(),
    this.extra = const {},
    this.sessionExtra = const {},
    this.prefsExtra = const {},
    this.overlayExtra = const {},
    this.beatPromptExtra = const {},
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

  /// `prefs.beatPrompt` 子对象未知键保底区（原样带回、写回原样）。
  final Map<String, dynamic> beatPromptExtra;

  /// 全字段拷贝底座：withXxx 族与保底区装配（codec 的 withExtra）都经本
  /// 方法——新增字段只改本方法、值类与段声明处，不再逐处手抄。
  LocalDocument _copy({
    Map<int, LearningMastery>? mastery,
    List<int>? activatedSegments,
    bool? previewSnapEnabled,
    bool? layoutLocked,
    Object? overlay = _keepOverlay,
    Object? beatPrompt = _keepBeatPrompt,
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
    beatPrompt: beatPrompt == _keepBeatPrompt
        ? this.beatPrompt
        : beatPrompt as BeatPromptMemoryFields?,
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
    beatPromptExtra: beatPromptExtra,
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
  /// [beatPromptExtra]）刻意
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

/// `_copy` 节拍提示记忆字段的「保持现值」哨兵：记忆写入以绝对终值落定，
/// null = 清除整份记录，区别于不传参。
const Object _keepBeatPrompt = Object();

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
      beatPrompt: doc.beatPrompt == null
          ? _beatPromptAbsent
          : _BeatPromptValue(
              fields: doc.beatPrompt!,
              extra: doc.beatPromptExtra,
            ),
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
    beatPrompt: prefs.beatPrompt.present ? prefs.beatPrompt.fields : null,
    speedRate: prefs.speedRate,
    practiceMirror: prefs.practiceMirror,
    practiceClips: prefs.practiceClips,
    autoDelete: prefs.autoDelete,
    sessionExtra: session.extra,
    prefsExtra: prefs.extra,
    overlayExtra: prefs.overlay.extra,
    beatPromptExtra: prefs.beatPrompt.extra,
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
  const _PrefsValue({
    this.previewSnapEnabled = true,
    this.layoutLocked = false,
    this.overlay = const _OverlayValue(),
    this.beatPrompt = const _BeatPromptValue(present: false),
    this.speedRate,
    this.practiceMirror,
    this.practiceClips = const [],
    this.autoDelete = const MaterialAutoDeleteSettings(),
    this.extra = const {},
  });

  final bool previewSnapEnabled;
  final bool layoutLocked;

  final _OverlayValue overlay;

  /// 节拍提示记忆（[beatPromptAbsent] = 文件无 `beatPrompt` 键）。
  final _BeatPromptValue beatPrompt;

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
  beatPrompt,
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
        beatPrompt: v.beatPrompt,
        speedRate: v.speedRate,
        practiceMirror: v.practiceMirror,
        practiceClips: v.practiceClips,
        autoDelete: v.autoDelete,
        extra: extra,
      ),
    );

FieldDecl<_PrefsValue> _prefsDecl(_PrefsField id) => switch (id) {
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
  _PrefsField.beatPrompt => FieldDecl(
    key: 'beatPrompt',
    read: (json) {
      final raw = json['beatPrompt'];
      if (raw is! Map<String, Object?>) return _beatPromptAbsent;
      return _beatPromptCodec.decode(raw);
    },
    // 承诺：整份记录不存在（null）不写该键——缺键即无记录；记录在但
    // 五个字段全缺席仍写空对象（与无记录是两种状态）。
    write: (v) => v.beatPrompt.present
        ? _beatPromptCodec.encode(v.beatPrompt)
        : omitField,
    equal: (a, b) =>
        a.beatPrompt.present == b.beatPrompt.present &&
        (!a.beatPrompt.present || a.beatPrompt.fields == b.beatPrompt.fields),
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
    read: (json) =>
        json['practiceMirror'] is bool ? json['practiceMirror'] as bool : null,
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
};

_PrefsValue _buildPrefs(Map<_PrefsField, Object?> values) => _PrefsValue(
  previewSnapEnabled: values[_PrefsField.previewSnapEnabled] as bool,
  layoutLocked: values[_PrefsField.layoutLocked] as bool,
  overlay: values[_PrefsField.overlay] as _OverlayValue,
  beatPrompt: values[_PrefsField.beatPrompt] as _BeatPromptValue,
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

// --- beatPrompt 子对象（节拍提示记忆：五个值逐字段可缺席） ----------

/// 「文件无 `beatPrompt` 键」的哨兵值（整份记录不存在）。
const _BeatPromptValue _beatPromptAbsent = _BeatPromptValue(present: false);

class _BeatPromptValue {
  const _BeatPromptValue({
    this.fields = const BeatPromptMemoryFields(),
    this.extra = const {},
    this.present = true,
  });

  final BeatPromptMemoryFields fields;
  final Map<String, Object?> extra;

  /// prefs 段里是否存在 `beatPrompt` 键（false = 整份记录不存在）。
  final bool present;
}

enum _BeatPromptField { animation, animationStyle, sound, soundType, halfBeat }

final RecordCodec<_BeatPromptValue, _BeatPromptField> _beatPromptCodec =
    RecordCodec<_BeatPromptValue, _BeatPromptField>(
      ids: _BeatPromptField.values,
      decl: _beatPromptDecl,
      build: _buildBeatPrompt,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) =>
          _BeatPromptValue(fields: v.fields, extra: extra, present: v.present),
    );

FieldDecl<_BeatPromptValue> _beatPromptDecl(_BeatPromptField id) =>
    switch (id) {
      _BeatPromptField.animation => _beatPromptFieldDecl(
        key: 'animation',
        read: (f) => f.animation,
        parse: _parseBool,
      ),
      _BeatPromptField.animationStyle => _beatPromptFieldDecl(
        key: 'animationStyle',
        read: (f) => f.animationStyle,
        parse: (raw) => _parseName(raw, const {'bar', 'pendulum'}),
      ),
      _BeatPromptField.sound => _beatPromptFieldDecl(
        key: 'sound',
        read: (f) => f.sound,
        parse: _parseBool,
      ),
      _BeatPromptField.soundType => _beatPromptFieldDecl(
        key: 'soundType',
        read: (f) => f.soundType,
        parse: (raw) => _parseName(raw, const {'normal', 'vocal', 'geigi'}),
      ),
      _BeatPromptField.halfBeat => _beatPromptFieldDecl(
        key: 'halfBeat',
        read: (f) => f.halfBeat,
        parse: _parseBool,
      ),
    };

/// 记忆单元的单字段声明：缺席（null）时写 [omitField]，词表外的值读入
/// 归缺席。
FieldDecl<_BeatPromptValue> _beatPromptFieldDecl<T>({
  required String key,
  required T? Function(BeatPromptMemoryFields fields) read,
  required T? Function(Object? raw) parse,
}) => FieldDecl<_BeatPromptValue>(
  key: key,
  read: (json) => parse(json[key]),
  write: (v) => read(v.fields) ?? omitField,
  equal: (a, b) => read(a.fields) == read(b.fields),
);

_BeatPromptValue _buildBeatPrompt(Map<_BeatPromptField, Object?> values) =>
    _BeatPromptValue(
      fields: BeatPromptMemoryFields(
        animation: values[_BeatPromptField.animation] as bool?,
        animationStyle: values[_BeatPromptField.animationStyle] as String?,
        sound: values[_BeatPromptField.sound] as bool?,
        soundType: values[_BeatPromptField.soundType] as String?,
        halfBeat: values[_BeatPromptField.halfBeat] as bool?,
      ),
    );

bool? _parseBool(Object? raw) => raw is bool ? raw : null;

String? _parseName(Object? raw, Set<String> vocabulary) =>
    raw is String && vocabulary.contains(raw) ? raw : null;

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
