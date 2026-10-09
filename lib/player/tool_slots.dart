/// 工具槽库：标注工具区的单一来源。
///
/// **两个概念面**：
/// ① 身份与次序——[ToolSlotId] + [ToolSlot] + [ToolSlotTable]（槽标识、
/// 槽键与两份具名槽集 [ToolSlotTable.normal] / [ToolSlotTable.standby]，
/// 次序即声明次序）；② 可用性判定——[ToolGateKind] → [ToolSlotVerdict]
/// （命中的门 / 是否可点），由 [evaluateToolSlot] 与种类映射
/// [toolSlotTappable] 一处给出；消费面用求值入口 [evaluateToolEntry]
/// （声明 + 事实 [ToolFacts] → verdict），无对象的按槽解析收在
/// [toolEntryHasSubject] 的穷尽 switch。
///
/// 「`ToolAvailability` 及判定表」这一概念面在库内由命中的 [ToolGateKind]
/// + [ToolSlotVerdict] 承载：前者归类「为什么不可用」（枚举、不是颜色），
/// 后者是判定表对某一次询问给出的完整答案（正常与否、种类、可点性）。
/// 点击语义不另立符号——它由 [ToolSlotVerdict.available] 与
/// [ToolSlotVerdict.tappable] 派生：正常 → 执行动作，置灰可点 → 解释原因，
/// 不可点 → 静默（映射见控制层的点击座架）。`ToolAvailability` 不作为库内
/// 符号出现，读者按本段对应关系理解。
///
/// **槽只报门**：每个槽声明「我这个动作有哪些门」（[ToolSlot.gates]）；
/// 无门写成显式空清单，不靠缺席表达——读者能区分「故意不管」与「忘了管」。
/// 表现与点击语义一律由判定表给出，槽自身不携带。
///
/// **判定规则五行**（按序取第一个命中的门，无例外从句）：
///
/// | 序 | 门 | 表现 | 点击后 |
/// | --- | --- | --- | --- |
/// | ① | 装载未完成 | 置灰、可点 | 弹原因（正在装载） |
/// | ② | 无对象 | 置灰、可点 | 弹原因（该怎么做） |
/// | ③ | 锁定分段 | 置灰、可点 | 弹原因（已锁定分段） |
/// | ④ | 网格未就绪 | 置灰、可点 | 弹原因 |
/// | ⑤ | 预览线越界 | 置灰、不可点 | 无（静默） |
/// | — | 都不命中 | 正常 | 正常 |
///
/// **投屏入口的五条门复用同一张判定表**（票 #35：副本丢失 / 音画同步
/// 校准中 / 录制中或录制准备中 / 对比态或取景调节态 / 渲染进行中）：它们
/// 与「无对象 / 锁定 / 未就绪」同行——**置灰、可点、按下去只解释原因**。
/// 门种 → 可点性只由 [toolSlotTappable] 一处给（今天唯「预览线越界」静默），
/// 消费面（顶栏投屏槽）不另判一套。
///
/// 三句话优先级：装载未完成压倒一切（对象集本身来自尚未装载的文档，
/// 此刻「有没有对象」无从判定）；无对象压倒锁定；锁定压倒未就绪与越界
/// （就近写明，不靠优先级表的书写顺序）。
///
/// **第②行的「弹原因」是一句做法**：没有
/// 作用对象时按下去静默无反应，用户最容易的结论是「软件坏了」——本行改为
/// 说出「该怎么做」（文案的两态取辞见 `no_subject_hint.dart`），动作照样
/// 不发生。**做法随入口声明**（[ToolSlot.noSubjectHint] /
/// [AddEntry.noSubjectHint]）：没有一句做法可给的入口（待命态锚点三槽的
/// 置灰是互斥的，此刻无话可说）声明为空，这一门对它们回到旧口径——置灰、
/// 按不动、静默。
///
/// **锁定的门由「有没有作用对象」之外的第二个事实决定**：锁定门声明的
/// 仍是「我这个动作属于本锁覆盖的族」，而此刻这一下是否真的落在锁内由
/// 按槽标识的穷尽 switch（[toolEntryLayoutLockApplies]）回答——「删除」的
/// 作用对象是分段线时在锁内、是半拍线/局部镜像片段/练习片段时不在锁内。
///
/// **会写文档的入口声明**：每个会写盘的工具槽 / 添加条目显式声明
/// [ToolSlot.writesDocument] / [AddEntry.writesDocument]，并必须在门清单里
/// 声明 [ToolGateKind.loading]——两者双向一致由结构断言兜住，漏声明即
/// 测试红。装载期不存在需要逐字段判定的冲突：写盘入口已被这道门挡在
/// 建立之前。
///
/// **刻意不含**（出现第二个取值时再加，字段在库内构造、后加不破调用方）：
/// - 槽的文案与图标（渲染问题，留在各槽件）；
/// - 槽的自定义尺寸与权重（今天恒为「内容宽度」）；
/// - 槽的分组与分隔线（待命态不需要；出现第二个取值再加）。
///
/// 本模块零框架依赖（不引 Flutter、不引 dart:ui）、不读状态、不依赖任何
/// 外部对象——取值只由入参决定，可在不启动 widget 环境的情况下直测。
library;

/// 工具槽的标识：创建类两项（「插入半拍」「局部镜像」）与 flag 切换收在
/// 「添加」槽的条目表（[AddEntryId] / [AddEntryId.segmentFlag]）；对比槽集
/// 另含一枚 [practiceMirror] 开关槽。
enum ToolSlotId {
  mastery,
  emphasis,
  segment,
  add,
  delete,
  autoRange,
  beatAnchorAdd,
  beatAnchorRemove,
  beatAnchorsClear,
  beatCorrectionExit,

  /// 段内倍频待命态：三枚赋值钮 + 退出。
  segmentDensityFaster,
  segmentDensitySlower,
  segmentDensityReset,
  segmentDensityExit,

  /// 底排对比槽集的练习侧镜像开关槽：取景入口统一为顶栏「取景调整」
  /// （`play_tool_table.dart` 的 `tool_framing_adjust`），对比专用工具区
  /// 只剩本槽。
  practiceMirror,
}

/// 添加条目标识：「添加」槽弹出菜单里往时间线上落标注的动作
/// （创建三条 + 标记一条）。
///
/// 条目不是槽——不进槽集、不参与工具排的宽度分配；条目键沿用原两槽的
/// 槽键字符串（同一件事换了个落点，键不换）。[segmentFlag] 的键沿用
/// `control_segment_flag`。
enum AddEntryId { halfBeat, localMirror, noteSticker, segmentFlag }

/// 自动分段条目标识：「自动分段」槽弹出菜单里的三档动作。
///
/// 条目不是槽——不进槽集、不参与工具排的宽度分配；条目键是渲染层与
/// 测试共同的定位手段。
enum AutoSegmentEntryId { clearSegments, fourBeats, eightBeats }

/// 工具槽的门种类：槽声明「我这个动作有哪些门」。
///
/// 两块取值：**标注工具区**那五种（判定表就按它们写）与**投屏入口**那五条
/// （票 #35；同属顶栏看片工具，判定表与点击语义完全复用同一条——都是
/// 「置灰、可点、按下去只解释原因」）。两块取值的可点性今天恰好同向，故
/// [toolSlotTappable] 只按「越界＝静默」一条判。
enum ToolGateKind {
  /// 装载未完成（打开恢复落定之前）：对象集本身来自尚未装载的文档，
  /// 此刻「有没有对象」无从判定，故本门排在判定表最前。落定点是**标注
  /// 对象集就位**，不是文档读完，也不是建立序列走完。
  loading,

  /// 无对象：这个动作没有作用对象 / 没有合法落点（表现与点击语义见
  /// library 级判定表第②行）。
  noSubject,

  /// 锁定分段（只护分段结构）。
  locked,

  /// 网格未就绪（占位 / 异常）。
  gridNotReady,

  /// 预览线越界（在有效练习区间外）。
  previewOutOfBounds,

  // ---- 投屏入口的五条门（第二块：今天只由顶栏「投屏」槽声明）----

  /// 副本丢失：这支舞的**视频副本**不在本机——推一份不在盘上的文件没有
  /// 意义，先把副本找回来。
  castCopyMissing,

  /// 音画同步校准中：校准在**本机内核**上量音画偏移，投屏把播放挪到电视
  /// 上，两条播放接管互斥。
  castAvSyncCalibrating,

  /// 录制中或录制准备中：录制与投屏是两条互相冲突的播放接管（含准备期，
  /// 与 `RecordingPlaybackTakeover.active` 同一口径）。
  castRecording,

  /// 对比态或取景调节态：这两个态各有自己的画面主张与手势面，投屏态不从
  /// 它们里进去——先退出来再投。
  castCompareOrFraming,

  /// 渲染进行中：另一次投屏渲染还在跑（含后台渲其余倍速档）——起投会与它
  /// 抢同一条渲染链，等它跑完。
  castRendering,
}

/// 「无对象」门命中时该入口给的做法：说先选中哪一种**作用
/// 对象**。门只报「没有作用对象」，做法是这条门在该入口上的落法——它随
/// 槽 / 条目一起**声明**（见 [ToolSlot.noSubjectHint] /
/// [AddEntry.noSubjectHint]），可点性与点击语义仍由判定表按声明给出。
enum NoSubjectHint {
  /// 先选中一个学习段（熟练度 / 重点）。
  learningSegment,

  /// 先选中一条分段线（「标记分段线」）。
  segmentLine,

  /// 先选中一条分段线或练习片段（删除）。
  segmentLineOrClip,
}

/// 单个工具槽：标识、槽键、门清单、「无对象」做法与引导锚点。
///
/// 槽键字符串与渲染层 Key 逐位一致，是渲染层与测试共同的定位手段。
class ToolSlot {
  const ToolSlot({
    required this.id,
    required this.key,
    required this.gates,
    required this.writesDocument,
    this.noSubjectHint,
    this.carriesGuideAnchor = false,
  });

  final ToolSlotId id;

  /// 槽键（与渲染层的 Key 逐位一致）。
  final String key;

  /// 本动作有哪些门（显式声明；无门即空清单）。次序不承载语义——门之间
  /// 的优先级由判定表全局唯一决定。
  final List<ToolGateKind> gates;

  /// 本槽是否会写按视频文档（显式声明；装载期写盘保护的结构事实）。
  /// 与 [gates] 是否含 [ToolGateKind.loading] 双向一致，由结构断言兜住。
  final bool writesDocument;

  /// 「无对象」门命中时该槽给的做法；**null = 刻意不给做法**
  /// （这个入口的置灰是互斥的、此刻没有一句「该怎么做」可说——待命态
  /// 锚点三槽）。不给做法的入口在命中该门时回到旧口径：置灰、按不动、
  /// 静默（判定表第②行的这一支见 [evaluateDeclaredGates]）。
  final NoSubjectHint? noSubjectHint;

  /// 本槽是否承载引导锚点（锚点 key 就是 [key]——与顶栏工具槽同一口径）。
  /// **逐槽声明**而不是按槽键判：同一枚槽键在不同槽集里是两枚不同的槽
  ///（「删除」在编辑态与对比态各一枚），锚点只在声明的那一枚上接线——读者
  /// 从声明就能区分「故意不接」与「忘了接」。
  final bool carriesGuideAnchor;
}

/// 共享槽声明：熟练度与重点在正常态与对比态两份
/// 槽集里逐字同行，自动分段亦然——各提成一条 `const`，两张槽集引用它。
const ToolSlot _masterySlot = ToolSlot(
  id: ToolSlotId.mastery,
  key: 'control_mastery',
  gates: [ToolGateKind.loading, ToolGateKind.noSubject],
  writesDocument: true,
  noSubjectHint: NoSubjectHint.learningSegment,
);

const ToolSlot _emphasisSlot = ToolSlot(
  id: ToolSlotId.emphasis,
  key: 'control_emphasis',
  gates: [ToolGateKind.loading, ToolGateKind.noSubject],
  writesDocument: true,
  noSubjectHint: NoSubjectHint.learningSegment,
);

const ToolSlot _autoRangeSlot = ToolSlot(
  id: ToolSlotId.autoRange,
  key: 'control_auto_range',
  gates: [ToolGateKind.loading, ToolGateKind.locked, ToolGateKind.gridNotReady],
  writesDocument: true,
);

/// 一份有序槽集：某态下有哪些槽、什么次序，即声明次序。
///
/// 槽集对「当前模式」保持无知——「模式 → 槽集」的映射收在
/// `session_mode_surfaces.dart` 的声明表里逐值一行。
///
/// 同一条槽同时进多份槽集时只声明一次：下面的
/// [_masterySlot] / [_emphasisSlot] / [_autoRangeSlot] 各是一条共享
/// `const`，各槽集引用同一份——同一槽的字段不再有两份可能分家的编码。
class ToolSlotTable {
  const ToolSlotTable(List<ToolSlot> slots) : _slots = slots;

  /// 正常态 6 槽：熟练度 → 重点 → 分段 → 添加 → 删除 → 自动分段。
  /// 「插入半拍」「局部镜像」与「标记」收在「添加」槽的条目表
  /// （[AddEntryTable]）。
  static const ToolSlotTable normal = ToolSlotTable([
    _masterySlot,
    _emphasisSlot,
    ToolSlot(
      id: ToolSlotId.segment,
      key: 'control_segment',
      gates: [
        ToolGateKind.loading,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
        ToolGateKind.previewOutOfBounds,
      ],
      writesDocument: true,
    ),
    ToolSlot(
      // 「添加」钮不再受锁（范围收窄）：锁定期间不再命中锁定门，
      // 点开就是正常菜单；菜单里只有「标记分段线」条目仍命中锁定门，动作
      // 由标注编辑模块拒绝（见 [AddEntryTable]）。它是写盘入口（菜单里的
      // 落标注动作都写盘），故声明装载未完成门——装载期整个菜单被挡下，
      // 条目各自的门只在装载落定后可命中。
      id: ToolSlotId.add,
      key: 'control_add',
      gates: [ToolGateKind.loading],
      writesDocument: true,
    ),
    ToolSlot(
      id: ToolSlotId.delete,
      key: 'control_segment_delete',
      gates: [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
        ToolGateKind.locked,
      ],
      writesDocument: true,
      // 无对象：删除的作用对象是分段线 / 半拍线 / 局部镜像
      // 片段，对比态是练习片段——做法按「分段线或片段」取辞。
      noSubjectHint: NoSubjectHint.segmentLineOrClip,
      // 引导锚点：分段第 ② 步指住这枚槽讲一句
      // 「点这里撤掉」（锚点 key = 上面的槽键 `control_segment_delete`）。
      // 对比态那枚同名槽（下面的 `compare` 行）不声明，那里不接锚点。
      carriesGuideAnchor: true,
    ),
    _autoRangeSlot,
  ]);

  /// 对比态 5 槽：熟练度 → 重点 → 删除 → 练习侧镜像 → 自动分段。
  /// 门逐条声明：熟练度/重点 = 无对象（作用对象 = 选中的学习段）；删除 =
  /// 无对象（作用对象 = 选中的练习片段，对比态下分段线与半拍线不可删）；
  /// 练习侧镜像 = **无门**（开关不改标注几何，也不存在「无对象」前提——
  /// 对比-控制层内恒可点）。
  static const ToolSlotTable compare = ToolSlotTable([
    _masterySlot,
    _emphasisSlot,
    ToolSlot(
      id: ToolSlotId.delete,
      key: 'control_segment_delete',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
      // 对比态删除的作用对象 = 选中的练习片段（同一句做法取辞）。
      noSubjectHint: NoSubjectHint.segmentLineOrClip,
    ),
    ToolSlot(
      id: ToolSlotId.practiceMirror,
      key: 'control_practice_mirror',
      gates: [ToolGateKind.loading],
      writesDocument: true,
    ),
    // 自动分段：对比态与编辑态同一菜单形态；门逐条沿用
    // 正常态那行声明（装载 / 锁定 / 网格未就绪），条目各自的门见
    // [AutoSegmentEntryTable]。
    _autoRangeSlot,
  ]);

  /// 待命态 4 槽：设为八拍线 → 取消八拍线 → 清除所有八拍线 → 退出八拍矫正。
  static const ToolSlotTable standby = ToolSlotTable([
    ToolSlot(
      id: ToolSlotId.beatAnchorAdd,
      key: 'control_beat_anchor_add',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
    ),
    ToolSlot(
      id: ToolSlotId.beatAnchorRemove,
      key: 'control_beat_anchor_remove',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
    ),
    ToolSlot(
      id: ToolSlotId.beatAnchorsClear,
      key: 'control_beat_anchors_clear',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
    ),
    ToolSlot(
      // 退出八拍矫正：不改文档（只切模式），无门，也不声明装载未完成门。
      id: ToolSlotId.beatCorrectionExit,
      key: 'control_beat_correction_exit',
      gates: [],
      writesDocument: false,
    ),
  ]);

  /// 段内倍频待命态 4 槽：快一倍（设为 ×2）
  /// → 慢一半（设为 ×½）→ 回到原样（设为 1，删键）→ 退出。三枚赋值钮的
  /// 门 = 装载 + 无对象（作用对象 = 选中的学习段，与熟练度/重点同一作用
  /// 对象与同一句做法取辞）；**回到原样**不设「本来就是原样」的置灰门
  /// （赋值语义，按下无变化仍可点）。退出槽与八拍矫正退出同款：不改文档、
  /// 无门、恒可点。赋值动作的提交接线归。
  static const ToolSlotTable segmentDensityStandby = ToolSlotTable([
    ToolSlot(
      id: ToolSlotId.segmentDensityFaster,
      key: 'control_segment_density_faster',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
      noSubjectHint: NoSubjectHint.learningSegment,
    ),
    ToolSlot(
      id: ToolSlotId.segmentDensitySlower,
      key: 'control_segment_density_slower',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
      noSubjectHint: NoSubjectHint.learningSegment,
    ),
    ToolSlot(
      id: ToolSlotId.segmentDensityReset,
      key: 'control_segment_density_reset',
      gates: [ToolGateKind.loading, ToolGateKind.noSubject],
      writesDocument: true,
      noSubjectHint: NoSubjectHint.learningSegment,
    ),
    ToolSlot(
      // 退出段内倍频待命态：不改文档（只切模式），无门，恒可点。
      id: ToolSlotId.segmentDensityExit,
      key: 'control_segment_density_exit',
      gates: [],
      writesDocument: false,
    ),
  ]);

  /// 投屏态槽集 = **空集**：底排槽位整排不出现——投屏期分段只读是**结构性**
  /// 的（无槽可选、无动作可发），不靠额外的只读门挡。它与「哪些模式取哪份
  /// 槽集」的映射同处一张声明表（`session_mode_surfaces.dart`）。
  static const ToolSlotTable cast = ToolSlotTable([]);

  final List<ToolSlot> _slots;

  /// 本槽集的槽位与次序（声明次序即呈现次序）。
  List<ToolSlot> get slots => List.unmodifiable(_slots);

  /// 按标识取槽；槽不在本槽集内（未知 / 未收录）时显式报错，不静默返回空。
  ToolSlot slotOf(ToolSlotId id) {
    for (final slot in _slots) {
      if (slot.id == id) return slot;
    }
    throw StateError('工具槽库：槽标识 $id 不在本槽集内');
  }
}

/// 单个添加条目：条目标识、条目键、菜单文案与条目自己的门清单。
///
/// 条目键沿用原两槽的槽键字符串，是渲染层与测试共同的定位手段；菜单文案
/// 由条目自己声明（菜单是可声明的数据，渲染层不另排一份文案表）；门清单
/// 与槽同款纪律——显式声明，无门写成空清单。
class AddEntry {
  const AddEntry({
    required this.id,
    required this.key,
    required this.label,
    required this.gates,
    required this.writesDocument,
    this.noSubjectHint,
  });

  final AddEntryId id;

  /// 条目键（逐位沿用原槽键）。
  final String key;

  /// 菜单文案（条目自己声明的标签；与库内概念名不是同一层）。
  final String label;

  /// 本条目有哪些门（显式声明；无门即空清单）。
  final List<ToolGateKind> gates;

  /// 本条目是否会写按视频文档；与 [gates] 是否含 [ToolGateKind.loading]
  /// 双向一致，由结构断言兜住。
  final bool writesDocument;

  /// 「无对象」门命中时该条目给的做法；**null = 刻意不给做法**。
  /// 与 [ToolSlot.noSubjectHint] 同款纪律。
  final NoSubjectHint? noSubjectHint;
}

/// 添加条目表（工具槽库第三张声明表）：「添加」槽弹出菜单里
/// 有哪些条目、什么次序，即声明次序。与槽表同库、零框架依赖、复用同一张
/// 判定表（[evaluateToolSlot]）。
class AddEntryTable {
  const AddEntryTable(List<AddEntry> entries) : _entries = entries;

  /// 正常态条目：备注贴纸 → 局部镜像 → 标记分段线 → 半拍标记（次序即
  /// 菜单次序，[AddEntryId.segmentFlag] 插在「半拍标记」之前）。菜单
  /// 文案 = 条目自己声明的标签（[segmentFlag]
  /// 的文案随选中线的 flag 现态二选一：未标记「标记分段线」、已标记
  /// 「取消标记」——基础标签声明在表内，渲染层按事实取辞）；条目门：
  /// 半拍线 = 预览线越界，局部镜像片段与备注贴纸 = **无门**（只剩装载
  /// 未完成的结构声明），标记分段线 = 装载未完成 / 无选中分段线 / 锁定
  /// （分段结构族，锁定期点它弹「已锁定分段」、不切换 flag——见
  /// 判定表第③行；第三条是本条目独有——原「标记」槽的「无对象」门随
  /// 条目搬进来）。
  static const AddEntryTable normal = AddEntryTable([
    AddEntry(
      id: AddEntryId.noteSticker,
      key: 'control_note_sticker',
      label: '备注贴纸',
      gates: [ToolGateKind.loading],
      writesDocument: true,
    ),
    AddEntry(
      id: AddEntryId.localMirror,
      key: 'control_local_mirror',
      label: '局部镜像',
      gates: [ToolGateKind.loading],
      writesDocument: true,
    ),
    AddEntry(
      // 原「标记」槽的 flag 切换：键逐位沿用
      // 原槽键；门 = 装载 / 无选中分段线 / 锁定——锁定期命中锁定门、
      // 点一下弹「已锁定分段」、不切换 flag；无选中分段线时命中无对象门、
      // 点一下弹一句「该怎么做」、不切换 flag。
      id: AddEntryId.segmentFlag,
      key: 'control_segment_flag',
      label: '标记分段线',
      gates: [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
        ToolGateKind.locked,
      ],
      writesDocument: true,
      // 无对象：做法 = 先选中一条分段线。
      noSubjectHint: NoSubjectHint.segmentLine,
    ),
    AddEntry(
      id: AddEntryId.halfBeat,
      key: 'control_half_beat',
      label: '半拍标记',
      gates: [ToolGateKind.loading, ToolGateKind.previewOutOfBounds],
      writesDocument: true,
    ),
  ]);

  final List<AddEntry> _entries;

  /// 本条目表的条目与次序（声明次序即菜单次序）。
  List<AddEntry> get entries => List.unmodifiable(_entries);

  /// 按标识取条目；条目不在本表内（未知 / 未收录）时显式报错，不静默返回空。
  AddEntry entryOf(AddEntryId id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    throw StateError('添加条目表：条目标识 $id 不在本条目表内');
  }
}

/// 自动分段条目：条目标识、条目键与条目自己的门清单。
/// 与 [AddEntry] 同款纪律——显式声明，无门写成空清单。
class AutoSegmentEntry {
  const AutoSegmentEntry({
    required this.id,
    required this.key,
    required this.gates,
    required this.writesDocument,
  });

  final AutoSegmentEntryId id;

  /// 条目键（渲染层 Key 与测试共同的定位手段）。
  final String key;

  /// 本条目有哪些门（显式声明；无门即空清单）。
  final List<ToolGateKind> gates;

  /// 本条目是否会写按视频文档；与 [gates] 是否含 [ToolGateKind.loading]
  /// 双向一致，由结构断言兜住。
  final bool writesDocument;
}

/// 自动分段条目表：「自动分段」槽弹出菜单里有哪些条目、什么
/// 次序，即声明次序。与添加条目表同库、零框架依赖、复用同一张判定表。
class AutoSegmentEntryTable {
  const AutoSegmentEntryTable(List<AutoSegmentEntry> entries)
    : _entries = entries;

  /// 三档：清空分段 → 4 个八拍/段 → 8 个八拍/段（次序即菜单次序）。
  /// 三项都立即执行、不二次确认，各自是一次可撤销的标注编辑；条目门 =
  /// 装载 / 锁定 / 网格未就绪（网格未就绪时槽本身已被同门挡下弹原因，
  /// 条目门按声明补全，表现与点击语义仍由唯一判定表回答）。
  static const AutoSegmentEntryTable normal = AutoSegmentEntryTable([
    AutoSegmentEntry(
      id: AutoSegmentEntryId.clearSegments,
      key: 'control_auto_clear',
      gates: [
        ToolGateKind.loading,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
      ],
      writesDocument: true,
    ),
    AutoSegmentEntry(
      id: AutoSegmentEntryId.fourBeats,
      key: 'control_auto_seg_4',
      gates: [
        ToolGateKind.loading,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
      ],
      writesDocument: true,
    ),
    AutoSegmentEntry(
      id: AutoSegmentEntryId.eightBeats,
      key: 'control_auto_seg_8',
      gates: [
        ToolGateKind.loading,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
      ],
      writesDocument: true,
    ),
  ]);

  final List<AutoSegmentEntry> _entries;

  /// 本条目表的条目与次序（声明次序即菜单次序）。
  List<AutoSegmentEntry> get entries => List.unmodifiable(_entries);

  /// 按标识取条目；条目不在本表内（未知 / 未收录）时显式报错，不静默返回空。
  AutoSegmentEntry entryOf(AutoSegmentEntryId id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    throw StateError('自动分段条目表：条目标识 $id 不在本条目表内');
  }
}

/// 判定表的门优先级（全局唯一一条）：按序取第一个命中的门。
///
/// 这份次序里的第一条是**装载未完成**：对象集本身来自尚未装载的文档，
/// 此刻「有没有对象」无从判定——先报「正在装载」，别答错问题。紧接着的
/// 第二条同样是刻意的、反直觉的：**无对象压倒锁定**——没东西可作用时先
/// 告诉他该怎么做，而不是告诉他「已锁定分段」，那时说锁也是
/// 答错问题。不要按直觉把本表简化成「锁定一律优先」（那会答错问题、且
/// 推翻待命态已钉住的「谓词不成立不进模块、锁也不弹提示」语义）。
/// 就近写明，防止后来人「顺手简化」。
///
/// 第二块是**投屏入口的五条门**（票 #35）：两块取值不会同时挂在一个入口
/// 上，故只有块内次序有意义——块内次序即「能说什么就先说什么」：副本丢失
/// 是一切的前提；音画同步与录制是两条播放接管互斥（音画同步先，与验收
/// 清单的列举同序）；对比态或取景调节态是模式冲突；渲染进行中是最短命的
/// 那些事实，放最后。
///
/// **本表必须覆盖全部 [ToolGateKind] 取值**（缺一行即那个门永远不判、静默
/// 失效，`cast_entry_gate_test.dart` 有结构断言钉住）；加取值只改本表一处。
const List<ToolGateKind> kToolGatePriority = [
  // 标注工具区（前五行：判定表原文）。
  ToolGateKind.loading,
  ToolGateKind.noSubject,
  ToolGateKind.locked,
  ToolGateKind.gridNotReady,
  ToolGateKind.previewOutOfBounds,
  // 投屏入口（第二块：只由顶栏「投屏」槽声明）。
  ToolGateKind.castCopyMissing,
  ToolGateKind.castAvSyncCalibrating,
  ToolGateKind.castRecording,
  ToolGateKind.castCompareOrFraming,
  ToolGateKind.castRendering,
];

/// 判定结果：是否正常、命中的门、是否可点。
class ToolSlotVerdict {
  const ToolSlotVerdict({
    required this.available,
    required this.tappable,
    this.kind,
  });

  /// 正常（无门命中）为 true；置灰不可用为 false。
  final bool available;

  /// 命中的门（按 [kToolGatePriority] 取第一个）；正常时为 null。
  final ToolGateKind? kind;

  final bool tappable;
}

/// 判定表：按 [kToolGatePriority] 取第一个命中的门，给出表现。
///
/// 入参是**当前命中的门**（调用方只传该槽已声明且此刻成立的门）；空清单
/// 等同正常。
ToolSlotVerdict evaluateToolSlot(Iterable<ToolGateKind> hitGates) {
  final hit = hitGates.toSet();
  for (final gate in kToolGatePriority) {
    if (hit.contains(gate)) {
      return ToolSlotVerdict(
        available: false,
        kind: gate,
        tappable: toolSlotTappable(gate),
      );
    }
  }
  return const ToolSlotVerdict(available: true, tappable: true);
}

/// 事实值：一次求值时刻的全局门事实与具名
/// 作用对象事实。纯值——不读状态、不引框架，由消费面按自己有哪些对象
/// 填，不填的即不适用（缺省全 false）。
///
/// **全局门事实**（四类）：[loading]（装载未完成）、[locked]（锁定分段）、
/// [gridNotReady]（网格未就绪）、[previewOutOfBounds]（预览线越界）。
///
/// **投屏入口门事实**（五条，票 #35；只有顶栏「投屏」槽声明它们）：
/// [castCopyMissing]、[castAvSyncCalibrating]、[castRecording]、
/// [castCompareOrFraming]、[castRendering]。
///
/// **具名作用对象事实**：[selectedLearningSegmentInInterval]（选中段在
/// 区间内）、[selectedSegmentLine]（选中分段线）、[anyLineSelected]（任一线
/// 被选中——分段线 / 半拍线 / 局部镜像片段）、[selectedPracticeClip]（选中的练习片段）、
/// [anchorAddable] / [anchorRemovable] / [hasAnchors]（锚点可加 / 可删 /
/// 有锚点）、[hasAnchors]（锚点可加 / 可删 / 有锚点）。
class ToolFacts {
  const ToolFacts({
    this.loading = false,
    this.locked = false,
    this.gridNotReady = false,
    this.previewOutOfBounds = false,
    this.castCopyMissing = false,
    this.castAvSyncCalibrating = false,
    this.castRecording = false,
    this.castCompareOrFraming = false,
    this.castRendering = false,
    this.selectedLearningSegmentInInterval = false,
    this.selectedSegmentLine = false,
    this.anyLineSelected = false,
    this.selectedPracticeClip = false,
    this.anchorAddable = false,
    this.anchorRemovable = false,
    this.hasAnchors = false,
  });

  /// 装载未完成（打开会话建立之前）。
  final bool loading;

  /// 锁定分段。
  final bool locked;

  /// 网格未就绪（占位 / 异常）。
  final bool gridNotReady;

  /// 预览线越界（在有效练习区间外）。
  final bool previewOutOfBounds;

  /// 投屏入口：这支舞的视频副本不在本机。
  final bool castCopyMissing;

  /// 投屏入口：音画同步校准会话进行中。
  final bool castAvSyncCalibrating;

  /// 投屏入口：录制中或录制准备中。
  final bool castRecording;

  /// 投屏入口：处于对比态或取景调节态。
  final bool castCompareOrFraming;

  /// 投屏入口：投屏渲染进行中。
  final bool castRendering;

  /// 选中段在区间内（熟练度 / 重点槽的作用对象）。
  final bool selectedLearningSegmentInInterval;

  /// 选中分段线（「标记分段线」添加条目的作用对象事实；由「添加」菜单
  /// 装配处消费）。
  final bool selectedSegmentLine;

  /// 任一线被选中（分段线 / 半拍线 / 局部镜像片段——编辑态装配点把局部
  /// 镜像片段折进同一谓词；删除槽的作用对象）。
  final bool anyLineSelected;

  /// 选中的练习片段（对比态删除槽的作用对象）。
  final bool selectedPracticeClip;

  /// 锚点可加（设为八拍线槽的作用对象）。
  final bool anchorAddable;

  /// 锚点可删（取消八拍线槽的作用对象）。
  final bool anchorRemovable;

  /// 有锚点（清除所有八拍线槽的作用对象）。
  final bool hasAnchors;
}

/// 求值入口：「声明 + 事实 → verdict」。
///
/// 入参 = 该入口声明的槽行（[ToolSlot]，门清单仍是槽集里那一行）+ 事实值
/// （[ToolFacts]）；出参 = 既有 verdict（[ToolSlotVerdict]）。命中集 =
/// 声明的门 ∩ 事实成立的门——事实不越过声明（未声明的门不被事实点亮），
/// 门序、可点性、点击语义全由既有判定表（[evaluateToolSlot]）给出，取值
/// 逐位不变。
///
/// **命中集的算法只有一处**（票 #44）：按门优先级逐条走声明表，**按门取
/// 事实**（[_gateHolds] 的穷尽 `switch`）——门种多少条都只这一遍迭代，
/// 不再逐门抄一行 `if (declared.contains(X) && facts.X)`。
///
/// **无对象的按槽解析**：`noSubject` 是否命中由 [ToolSlot.id] 的穷尽
/// switch（[toolEntryHasSubject]）在库内解析；加槽漏补事实即编译报错。
/// [hasSubject] = 该入口「此刻有没有作用对象」（没有 `noSubject` 前提的
/// 入口恒传 true）；[lockApplies] = 该入口「此刻是否被本锁覆盖」（缺省
/// true——直接消费条目表的调用点不带按对象判的锁定前提；槽面由
/// [evaluateToolEntry] 传 [toolEntryLayoutLockApplies] 的解析值）；
/// [noSubjectExplained] = 该入口有没有一句「该怎么做」（缺省 true
/// ——顶栏那枚软门的解释走它自己的动作），由入口的
/// [ToolSlot.noSubjectHint] / [AddEntry.noSubjectHint] 声明回答。
ToolSlotVerdict evaluateDeclaredGates(
  Set<ToolGateKind> declared,
  ToolFacts facts, {
  bool hasSubject = true,
  bool lockApplies = true,
  bool noSubjectExplained = true,
}) {
  final verdict = evaluateToolSlot([
    for (final gate in kToolGatePriority)
      if (declared.contains(gate) &&
          _gateHolds(
            gate,
            facts,
            hasSubject: hasSubject,
            lockApplies: lockApplies,
          ))
        gate,
  ]);
  // 第②行的一支：入口**没有一句做法可给**时，这一门仍按旧口径
  // 收场——置灰、按不动、静默。「可点」要有可点的东西：没话说就别空报一个
  // 按得动却毫无反应的钮。本支只由声明回答（[ToolSlot.noSubjectHint] /
  // [AddEntry.noSubjectHint]），不由渲染路径回答。
  if (verdict.kind == ToolGateKind.noSubject && !noSubjectExplained) {
    return const ToolSlotVerdict(
      available: false,
      kind: ToolGateKind.noSubject,
      tappable: false,
    );
  }
  return verdict;
}

/// 一条门此刻成不成立：**按门取事实**（唯一一处）。十种门各对一位事实，
/// 两处例外带自己的前提——「无对象」的事实是入参 [hasSubject]，「锁定」还要
/// [lockApplies] 说这一下真落在锁内。
///
/// 穷尽 `switch`：加 [ToolGateKind] 取值即编译报错（不会静默不判），
/// 这是命中集算法「只有一份」的护栏。
bool _gateHolds(
  ToolGateKind gate,
  ToolFacts facts, {
  required bool hasSubject,
  required bool lockApplies,
}) => switch (gate) {
  ToolGateKind.loading => facts.loading,
  ToolGateKind.noSubject => !hasSubject,
  ToolGateKind.locked => facts.locked && lockApplies,
  ToolGateKind.gridNotReady => facts.gridNotReady,
  ToolGateKind.previewOutOfBounds => facts.previewOutOfBounds,
  ToolGateKind.castCopyMissing => facts.castCopyMissing,
  ToolGateKind.castAvSyncCalibrating => facts.castAvSyncCalibrating,
  ToolGateKind.castRecording => facts.castRecording,
  ToolGateKind.castCompareOrFraming => facts.castCompareOrFraming,
  ToolGateKind.castRendering => facts.castRendering,
};

/// 按条目解析「此刻有没有作用对象」（穷尽 switch，
/// 与槽面 [toolEntryHasSubject] 同构）：加一个 [AddEntryId] 取值而漏补事实
/// 即编译报错。
///
/// 不声明无对象门的条目恒返回 true——它们没有「无对象」前提，本 switch 的
/// 取值不会被消费。
bool addEntryHasSubject(AddEntryId id, ToolFacts facts) => switch (id) {
  AddEntryId.segmentFlag => facts.selectedSegmentLine,
  AddEntryId.halfBeat ||
  AddEntryId.localMirror ||
  AddEntryId.noteSticker => true,
};

/// 求值入口：「声明 + 事实 → verdict」。
///
/// 入参 = 该入口声明的槽行（[ToolSlot]，门清单仍是槽集里那一行）+ 事实值
/// （[ToolFacts]）；出参 = 既有 verdict（[ToolSlotVerdict]）。
///
/// **无对象的按槽解析**：`noSubject` 是否命中由 [ToolSlot.id] 的穷尽
/// switch（[toolEntryHasSubject]）在库内解析；**锁定是否覆盖本入口**由
/// 第二个穷尽 switch（[toolEntryLayoutLockApplies]）解析；**这一门有没有
/// 一句做法**由槽自己的 [ToolSlot.noSubjectHint] 声明回答；加槽漏补事实
/// 即编译报错。
ToolSlotVerdict evaluateToolEntry(ToolSlot slot, ToolFacts facts) =>
    evaluateDeclaredGates(
      slot.gates.toSet(),
      facts,
      hasSubject: toolEntryHasSubject(slot.id, facts),
      lockApplies: toolEntryLayoutLockApplies(slot.id, facts),
      noSubjectExplained: slot.noSubjectHint != null,
    );

/// 按槽解析「此刻这一下是否被锁定分段覆盖」（穷尽 switch，与
/// [toolEntryHasSubject] 同处同纪律）：**随作用对象变的是事实，不是声明**
/// ——槽的门清单仍然只报「我这个动作属于被锁的族」，「删除」是否落在锁内
/// 由选中对象回答（选中的是分段线 = 锁内；是半拍线 / 局部镜像片段 /
/// 练习片段 = 锁外）。加一个 [ToolSlotId] 取值而漏补即编译报错。
///
/// 门清单里**没有**声明 [ToolGateKind.locked] 的入口恒返回 false——它们
/// 的动作不属于本锁覆盖的族，本 switch 的取值不会被消费。
bool toolEntryLayoutLockApplies(ToolSlotId id, ToolFacts facts) => switch (id) {
  // 删除：锁只覆盖「选中的是分段线」这一种作用对象。`selectedSegmentLine`
  // 由事实面按选中槽填、不区分播放态；对比态的删除对象是练习片段，故
  // 显式排除 `selectedPracticeClip`——对比态里残留的分段线选中不得把
  // 练习片段删除误判进锁内。
  ToolSlotId.delete => facts.selectedSegmentLine && !facts.selectedPracticeClip,
  // 分段槽（落分段线）与自动分段槽在锁内。
  ToolSlotId.segment || ToolSlotId.autoRange => true,
  // 其余入口的动作不属于分段结构族。
  ToolSlotId.mastery ||
  ToolSlotId.emphasis ||
  ToolSlotId.add ||
  ToolSlotId.beatAnchorAdd ||
  ToolSlotId.beatAnchorRemove ||
  ToolSlotId.beatAnchorsClear ||
  ToolSlotId.beatCorrectionExit ||
  ToolSlotId.segmentDensityFaster ||
  ToolSlotId.segmentDensitySlower ||
  ToolSlotId.segmentDensityReset ||
  ToolSlotId.segmentDensityExit => false,

  // 取景入口统一到顶栏「取景调整」；练习侧镜像的动作不属于分段结构族。
  ToolSlotId.practiceMirror => false,
};

/// 按槽解析「此刻有没有作用对象」（穷尽 switch）：
/// 加一个 [ToolSlotId] 取值而漏补事实即编译报错。
///
/// 不声明无对象门的槽恒返回 true——它们的作用对象不存在与否由各自的门
/// 承载（分段槽 = 网格未就绪 / 预览线越界；添加与两个对比开关槽没有
/// 「无对象」前提），本 switch 的取值不会被消费。
bool toolEntryHasSubject(ToolSlotId id, ToolFacts facts) => switch (id) {
  ToolSlotId.mastery => facts.selectedLearningSegmentInInterval,
  ToolSlotId.emphasis => facts.selectedLearningSegmentInInterval,
  ToolSlotId.segment => true,
  ToolSlotId.add => true,
  // 删除：选中任一线（分段线 / 半拍线 / 局部镜像片段——编辑态装配点
  // 折进同一谓词），或选中的练习片段（对比态）。
  ToolSlotId.delete => facts.anyLineSelected || facts.selectedPracticeClip,
  ToolSlotId.autoRange => true,
  ToolSlotId.beatAnchorAdd => facts.anchorAddable,
  ToolSlotId.beatAnchorRemove => facts.anchorRemovable,
  ToolSlotId.beatAnchorsClear => facts.hasAnchors,
  ToolSlotId.beatCorrectionExit => true,
  // 段内倍频三钮的作用对象 = 选中的学习段（与熟练度/重点同一事实）。
  ToolSlotId.segmentDensityFaster ||
  ToolSlotId.segmentDensitySlower ||
  ToolSlotId.segmentDensityReset => facts.selectedLearningSegmentInInterval,
  ToolSlotId.segmentDensityExit => true,
  ToolSlotId.practiceMirror => true,
};

/// 命中的门 → 可点性：预览线越界不可点（静默），其余四种门置灰仍可点
/// （按下去只解释原因）。
bool toolSlotTappable(ToolGateKind kind) =>
    kind != ToolGateKind.previewOutOfBounds;

/// 页面级会写文档入口的标识（不落在槽集里的写盘入口；槽与添加条目各有
/// 自己的标识表）。
enum PageWriteEntryId {
  /// 编辑器进入（单击画面 / 编辑面入口）：进入编辑面本身不写盘，但它是
  /// 所有标注写入的入口，装载期必须挡下并说明原因。
  editorEntry,

  /// 镜像开关（顶栏全局镜像 / 局部镜像）：写 markers / local。
  mirrorSwitch,

  /// 署名编辑（顶栏改名入口）：写 markers 署名。
  signatureEdit,

  /// 设置开关（预览吸附 / 延迟循环 / 锁定分段）：写 local prefs。
  settingsToggle,

  /// 录制入轨：录成的素材与片段轨写盘。
  recording,

  /// 截取（练习片段端点拖）：拖动会话写片段轨。
  capture,

  /// 取景调整：顶栏入口的直写（手势/复位经
  /// 「变更即存」写公开标记文件 `meta` 的取景选区）。
  framingAdjust,
}

/// 单个页面级会写文档入口：标识与门的可见形态。
class PageWriteEntry {
  const PageWriteEntry({required this.id, this.silent = false});

  final PageWriteEntryId id;

  /// 手势类入口：起手前只读判定、**静默不参与**（不弹原因）。false = 点按类
  /// 入口，被装载未完成门挡下时弹「正在装载」。门相同、表现由本字段一处
  /// 声明，生产入口读本表而不各自判断。
  final bool silent;
}

/// 页面级会写文档入口表（工具槽库的第四张声明表）：工具区之外的写盘入口
/// ——编辑器进入 / 镜像开关 / 署名编辑 / 设置开关 / 录制入轨 / 截取 /
/// 取景调整。它们的可用性沿同一张判定表（[evaluateToolSlot]）；生产入口经
/// `load_gate.dart` 的 `loadGateBlocksWrite` 读本表，门只声明一处。
class PageWriteEntryTable {
  const PageWriteEntryTable(List<PageWriteEntry> entries) : _entries = entries;

  /// 主表：七个页面级写盘入口。
  static const PageWriteEntryTable main = PageWriteEntryTable([
    PageWriteEntry(id: PageWriteEntryId.editorEntry),
    PageWriteEntry(id: PageWriteEntryId.mirrorSwitch),
    PageWriteEntry(id: PageWriteEntryId.signatureEdit),
    PageWriteEntry(id: PageWriteEntryId.settingsToggle),
    PageWriteEntry(id: PageWriteEntryId.recording),
    // 截取是手势类入口：静默不参与。
    PageWriteEntry(id: PageWriteEntryId.capture, silent: true),
    PageWriteEntry(id: PageWriteEntryId.framingAdjust),
  ]);

  final List<PageWriteEntry> _entries;

  /// 本入口表的入口与次序。
  List<PageWriteEntry> get entries => List.unmodifiable(_entries);

  /// 按标识取入口；不在本表内时显式报错，不静默返回空。
  PageWriteEntry entryOf(PageWriteEntryId id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    throw StateError('页面写盘入口表：入口标识 $id 不在本入口表内');
  }
}
