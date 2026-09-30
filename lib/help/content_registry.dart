import 'package:flutter/material.dart';

/// 引导步的四种形态：**形态声明在步上**——一个多步单元
/// 里各步可以各自是不同的形态（如编辑态上手的动手步与就地讲解步同属一个
/// 单元）。
enum GuideUnitForm {
  /// 就地讲解：锚定真实控件，整屏压暗 + 锚点挖亮 + 气泡（原「首启步 /
  /// 引导角标 / 逐步讲解」合并后的统一形态）。
  inplaceTour,

  /// 动手演练：停靠安全区顶的待办条 + 跟着锚点走的高亮框，判"做到了"，
  /// 不接管手势。
  handsOnDrill,

  /// 一次性图文：不锚定的模态图文卡片，自带按钮。
  oneShotCard,

  /// 短暂提示：贴锚点左侧、与它同高的小浮层，约 4 秒自散。
  transientHint,
}

/// 新手引导页上的三个分组——单元归哪
/// 一组是单元自己的声明，不由形态推导（编辑态上手是角标形态却属「播放页」）。
enum GuideUnitGroup {
  start('起步'),
  player('播放页'),
  hint('功能提示');

  const GuideUnitGroup(this.label);

  final String label;
}

/// 编辑态上手单元 id（动手两步 + 讲解一步；播放域触发点与状态位字段共用
/// 同一份字面量）。
const String editorIntroUnitId = 'editor_intro';

/// 编辑态上手两个动手步的判据声明（声明在步上，宿主按声明查会话事实；
/// 判据事实的读面归属见 guide_state 的 `GuideSessionState` 判据字段与
/// guide_host 的判据查表）。
enum HandsOnCriterion {
  /// 第一段段体在屏且渲染宽 ≥44 逻辑像素（读面 = 段体锚点矩形）。
  editorIntroZoom,

  /// 第一段学习段被激活过一次（读面 = 会话闩，播放域记入）。
  editorIntroActivate,

  /// 刚落成的那条分段线被选中过一次（读面 = 会话闩，播放域在点选动作处
  /// 记入）：点它的控制柄、或在线身那一行点它都算，落线本身不算。
  badgeSegmentLineSelected,

  /// 三指跳转做到过一次（读面 = 会话闩，播放域在三指跳转发生的动作处
  /// 记入）：不要求滑的是刚标记的那条线——判不了，也不判。
  threeFingerJumpPerformed,
}

/// 学习段序的「第一段」（判据②与播放域记入点共用，不散写字面量 0）。
const int firstLearningSegmentOrder = 0;

/// 六个就地讲解单元的 id（播放域触发点与状态位字段共用同一份字面量）。
const String badgeSegmentUnitId = 'badge_segment';
const String badgeAutoSegmentUnitId = 'badge_auto_segment';
const String badgeBeatPromptUnitId = 'badge_beat_prompt';

/// 倍速单元 id（播放域触发点与状态位字段共用同一份字面量）：这一位讲的是
/// 倍速气泡里的步进栏。
const String badgeSpeedUnitId = 'badge_speed';

const String badgeAvSyncUnitId = 'badge_av_sync';

const String badgeRosterUnitId = 'badge_roster';

const String practiceRangeUnitId = 'practice_range';

/// 首启分支：会话事实、不落盘——欢迎卡两个按钮与
/// 下载卡两个按钮各自记一个取值，指认步的锚点与文案按取值分流。
enum FirstRunChoice {
  /// 欢迎卡的教程主路：进入「下载视频」图文。
  tour,

  /// 欢迎卡的跳过支路：跳过图文，直接指「帮助」；收场后其余 13 个单元
  /// 一次置位。
  skip,

  /// 下载卡「已经存好了」：指「导入视频」。
  saved,

  /// 下载卡「等会儿再下载」：指「帮助」（两个按钮都置位下载图文这一步）。
  later,
}

/// 首启单元 id（指认步收场的分支置位与状态位字段共用同一份字面量）。
const String firstRunUnitId = 'first_run';

/// 跳过支路那次指认的步 id：按下「跳过教程」即把全部单元置位，这一步只是
/// 欠的一次演出——它走完之前不看状态位（见 `currentGuideStepProvider`）。
const String firstRunSkipRecognitionStepId = 'first_run_help';

/// 引导单元：与「已看过」状态位一一对应（字段清单见 guide_state 的
/// `onboardingFlagFields`）；新手引导页按 [group] 三组列出。标题与说明是
/// **文案**，随包存于 `assets/help/onboarding.yaml`（本表只声明结构）。
class GuideUnit {
  const GuideUnit({required this.id, required this.group});

  final String id;

  final GuideUnitGroup group;
}

/// 条目 id = 目录名去掉前面的数字前缀（`01-下载视频` → `下载视频`）；数字前缀
/// 只定显示顺序，不进 id。扫目录建条目时按本函数取 id。
String helpDocumentIdOfDirectory(String directory) =>
    directory.split('/').last.replaceFirst(RegExp(r'^\d+-'), '');

/// 三条菜单类就地讲解单元的 id（触发点在「添加」菜单条目的动作里，锚点
/// 落在刚落成的**实物**上）。
const String badgeLocalMirrorUnitId = 'badge_local_mirror';
const String badgeSegmentFlagUnitId = 'badge_segment_flag';
const String badgeHalfBeatUnitId = 'badge_half_beat';

/// 「三指跳转」单元 id（标记分段线的引导
/// 补第二步；触发点与「标记分段线」同处——标记动作真正做成的那一刻）。
const String badgeThreeFingerJumpUnitId = 'badge_three_finger_jump';

const List<GuideUnit> helpGuideUnits = [
  GuideUnit(
    id: 'first_run',
    group: GuideUnitGroup.start,
  ),
  GuideUnit(
    id: 'player_drill',
    group: GuideUnitGroup.player,
  ),
  GuideUnit(
    id: editorIntroUnitId,
    group: GuideUnitGroup.player,
  ),
  GuideUnit(
    id: practiceRangeUnitId,
    group: GuideUnitGroup.player,
  ),
  GuideUnit(
    id: badgeSegmentUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeAutoSegmentUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeBeatPromptUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeSpeedUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeAvSyncUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeRosterUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeLocalMirrorUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeSegmentFlagUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeThreeFingerJumpUnitId,
    group: GuideUnitGroup.hint,
  ),
  GuideUnit(
    id: badgeHalfBeatUnitId,
    group: GuideUnitGroup.hint,
  ),
];

/// 需「功能被触达」才可能出现的单元全集（功能提示只在用户
/// 真的走到那个功能时才有机会出现）：起步组之外的全部单元——首启两单元随
/// 判定照常出现，其余（编辑态上手与各功能提示）须先经
/// `GuideSessionState.triggered` 记入触达。派生自单元表，不另抄一份清单。
final Set<String> guideTriggerGatedUnitIds = {
  for (final unit in helpGuideUnits)
    if (unit.group != GuideUnitGroup.start) unit.id,
};

/// 导入前「下载视频」图卡引用的教程条目 id（= 目录名去数字前缀）。
/// 条目表本身由 help_documents 扫 `assets/help/tutorials/` 下的目录现算。
const String downloadVideoTutorialId = '下载视频';

/// 引导步：引导表里的一条步。锚定的步（就地讲解 / 短暂提示）必带锚点 key
/// （首页/播放页既有控件的定位 key）；一次性图文不锚定、[anchorKey] 为 null。
/// **结构在这里，文案在随包文件**（`assets/help/onboarding.yaml`，按本表 id
/// 查表）——引导演出层不携带硬编码文案。
class GuideStep {
  const GuideStep({
    required this.id,
    required this.unitId,
    required this.form,
    this.anchorKey,
    this.anchorKeySuffix,
    this.otherAnchorKeys = const [],
    this.asset,
    this.actionIcon,
    this.handsOnCriterion,
    this.stickyAnchor = false,
    this.requestsEnterWatching = false,
    this.firstRunChoice,
    this.cardChoices = const [],
    this.sourceDocumentId,
  });

  final String id;

  /// 所属引导单元（与状态位字段一一对应）。
  final String unitId;
  final GuideUnitForm form;

  /// 锚点控件的全局定位 key（一次性图文为 null）。
  final String? anchorKey;

  /// 锚点 key 的尾缀（null = 无）：锚在**同一件实物**的另一个部位时用它——
  /// 分段第 ① 步与线身两条角标共用基键 [segmentLineAnchorKeyBase] 与新落线
  /// 序号，末尾加 [segmentLineHandleAnchorKeySuffix] 才是控制柄那一枚
  /// （`segment_line_N_handle`）。
  final String? anchorKeySuffix;

  /// 同一个步的**其余锚点**（不含主播点 [anchorKey]）：演出层给每一枚在场
  /// 锚点各圈一圈、同一款式；缺席的不画、不算。首尾线用它同屏圈出头线与
  /// 尾线。
  final List<String> otherAnchorKeys;

  /// 图或动图资产路径（`assets/help/` 下）；首启步一句话为主，可为 null。
  final String? asset;

  /// 动手步待办条上的动作图标（动手演练列）；非动手步为 null。
  final IconData? actionIcon;

  /// 动手步的判据声明；非动手步为 null（声明在步上，宿主按声明分派）。
  final HandsOnCriterion? handsOnCriterion;

  /// 锚点驻留（声明在步上）：true 时本步**已取得过**的锚点矩形在锚点撤下
  /// 后仍供演出使用（步一换即清）——演出要在锚点控件退场后的表面上进行时
  /// 声明（如三指跳转步：控制层收起带走轨道带）。
  final bool stickyAnchor;

  /// 推进到本步的一帧请求播放页进观看态（声明在步上，宿主经组合根给的
  /// 闭包请求；一次演出只请求一次）。
  final bool requestsEnterWatching;

  /// 首启分支门槛：非 null 时本步只在会话分支取同一取值时才可能命中
  /// 其余步恒为 null、不受分支影响。
  final FirstRunChoice? firstRunChoice;

  /// 一次性图文卡的按钮（就地讲解 / 短暂提示为空）：**分支取值在结构里**，
  /// 按钮文案按它在 `onboarding.yaml` 里查（作者调序不改按钮与分支的对应）。
  final List<FirstRunChoice> cardChoices;

  /// 一次性图文卡正文取自哪份帮助文档（单一内容来源：首启的「下载视频」
  /// 图文就是帮助中心「教程」那条）；为 null 时正文用 [message] 分行。
  final String? sourceDocumentId;
}

/// 动手步待办条上的动作图标：图标与文案同为注册表单一口径（动手步自己
/// 声明）；未声明时取中性的「点一下」图标，演出层不再硬编码一份。
IconData guideStepActionIcon(GuideStep step) =>
    step.actionIcon ?? Icons.touch_app;

/// 首启指认步的三分支文案随包于 `assets/help/onboarding.yaml`（按步 id 取：
/// `first_run_import` / `first_run_help_download` / `first_run_help`）。

/// 引导步表：14 个单元各自的步。锚点缺席的步（首尾线、音画同步、名册，
/// 以及节拍提示 / 倍速的逐栏锚点）不出场、也不被消耗——锚点缺席即放行
///（宿主对缺席锚点按无步处理）。
const List<GuideStep> helpGuideSteps = [
  // 首启：一次性图文 ×2 + 就地讲解 ×1，三段按会话分支推进。
  // 欢迎卡两枚按钮的先后由这里的声明次序给出：那排按钮右对齐，声明在后的
  // 在右——「跳过教程」在左、「开始新手教程」在右。
  GuideStep(
    id: 'first_run_welcome',
    unitId: firstRunUnitId,
    form: GuideUnitForm.oneShotCard,
    cardChoices: [FirstRunChoice.skip, FirstRunChoice.tour],
  ),
  GuideStep(
    id: 'first_run_download',
    unitId: firstRunUnitId,
    form: GuideUnitForm.oneShotCard,
    sourceDocumentId: downloadVideoTutorialId,
    firstRunChoice: FirstRunChoice.tour,
    cardChoices: [FirstRunChoice.later, FirstRunChoice.saved],
  ),
  GuideStep(
    id: 'first_run_import',
    unitId: firstRunUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: importVideoAnchorKey,
    firstRunChoice: FirstRunChoice.saved,
  ),
  GuideStep(
    id: 'first_run_help_download',
    unitId: firstRunUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: homeHelpEntryAnchorKey,
    firstRunChoice: FirstRunChoice.later,
  ),
  GuideStep(
    id: 'first_run_help',
    unitId: firstRunUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: homeHelpEntryAnchorKey,
    firstRunChoice: FirstRunChoice.skip,
  ),
  // 编辑态上手（动手两步 + 讲解一步）——①两指张开把第一段放大到
  // 点得着（判据 = 段体在屏且渲染宽 ≥44 逻辑像素，双指捏合或拉缩放滑条都
  // 体现为段体矩形变宽，判据同一）；②点第一段段体把它循环起来（判据 =
  // 第一段被激活过一次）；③就地讲解线上的小把手。触达面 = 第一个学习段体
  // 挂载且可用（无学习段 = 锚点不在场，不弹也不消耗）。
  GuideStep(
    id: 'editor_intro_zoom',
    unitId: editorIntroUnitId,
    form: GuideUnitForm.handsOnDrill,
    handsOnCriterion: HandsOnCriterion.editorIntroZoom,
    anchorKey: learningSegment0AnchorKey,
    actionIcon: Icons.pinch,
  ),
  GuideStep(
    id: 'editor_intro_segment',
    unitId: editorIntroUnitId,
    form: GuideUnitForm.handsOnDrill,
    handsOnCriterion: HandsOnCriterion.editorIntroActivate,
    anchorKey: learningSegment0AnchorKey,
    actionIcon: Icons.touch_app,
  ),
  GuideStep(
    id: 'editor_intro_line_handle',
    unitId: editorIntroUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: segmentLine0HandleAnchorKey,
  ),
  // 首尾线：排在编辑态上手之后，只讲含义、不要求操作；一步声明
  // 两枚锚点——头线是主播点（气泡指它、它在场才出场），尾线同圈一圈。
  GuideStep(
    id: 'practice_range_head',
    unitId: practiceRangeUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: practiceRangeHeadAnchorKey,
    otherAnchorKeys: [practiceRangeTailAnchorKey],
  ),
  // 分段：两步都落在**刚落成的那条线**上——实际锚点 key 由会话
  // 记下的新落线序号拼出（[guideArtifactAnchorKey]），指的一定是刚落的那条。
  // ① 动手演练：高亮框框住那条线的**控制柄**，判据 = 这条线被选中过一次
  //（点控制柄或点线身都算；落线本身不选中）；② 就地讲解：锚「删除」工具槽。
  GuideStep(
    id: 'badge_segment_select',
    unitId: badgeSegmentUnitId,
    form: GuideUnitForm.handsOnDrill,
    handsOnCriterion: HandsOnCriterion.badgeSegmentLineSelected,
    anchorKey: segmentLineAnchorKeyBase,
    anchorKeySuffix: segmentLineHandleAnchorKeySuffix,
    actionIcon: Icons.touch_app,
  ),
  GuideStep(
    id: 'badge_segment_delete',
    unitId: badgeSegmentUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: segmentDeleteSlotAnchorKey,
  ),
  // 自动分段：锚在**刚弹出的三档菜单本体**上，不回指工具槽。
  GuideStep(
    id: 'badge_auto_segment_step',
    unitId: badgeAutoSegmentUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: autoSegmentMenuAnchorKey,
  ),
  // 节拍提示三步逐栏走查（各栏锚点；通篇不提三种状态）。
  GuideStep(
    id: 'badge_beat_prompt_animation',
    unitId: badgeBeatPromptUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: beatAnimationColumnAnchorKey,
  ),
  GuideStep(
    id: 'badge_beat_prompt_sound',
    unitId: badgeBeatPromptUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: beatSoundColumnAnchorKey,
  ),
  GuideStep(
    id: 'badge_beat_prompt_correct',
    unitId: badgeBeatPromptUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: beatCorrectColumnAnchorKey,
  ),
  // 倍速一步走查：锚气泡里的步进栏；文案不含方位词、不要求点控件。
  GuideStep(
    id: 'badge_speed_step',
    unitId: badgeSpeedUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: speedStepColumnAnchorKey,
  ),
  // 音画同步一步走查（锚在含 ＋/－ 的那一行上）。
  GuideStep(
    id: 'badge_av_sync_delay',
    unitId: badgeAvSyncUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: avSyncDelayColumnAnchorKey,
  ),
  // 名册：短暂提示，贴「名册」钮左侧、同高。
  GuideStep(
    id: 'badge_roster_hint',
    unitId: badgeRosterUnitId,
    form: GuideUnitForm.transientHint,
    anchorKey: rosterButtonAnchorKey,
  ),
  // 三条菜单类：锚点落在**刚落成的实物**上——[anchorKey] 是
  // 实物定位 key 的**基键**，实际锚点 key = 基键 + 本会话记下的新产物序号
  // （[guideArtifactAnchorKey]，见 [GuideSessionState.artifactIndexes]）。
  GuideStep(
    id: 'badge_local_mirror_step',
    unitId: badgeLocalMirrorUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: mirrorFragmentAnchorKeyBase,
  ),
  // 局部镜像第二步：锚顶栏 / 竖屏视频工具栏里的
  // 「局部镜像」开关（见 [localMirrorSwitchAnchorKey]）。落成镜像片段那一刻
  // 这枚开关被自动打开，故这一步讲的是「已经开着」，不是「去打开」；锚点随
  // 控制层收起退场——沿用既有「主播点不在场即不出场、回屏上接着演」，不新增
  // 放行规则。
  GuideStep(
    id: 'badge_local_mirror_switch',
    unitId: badgeLocalMirrorUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: localMirrorSwitchAnchorKey,
  ),
  GuideStep(
    id: 'badge_segment_flag_step',
    unitId: badgeSegmentFlagUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: segmentLineAnchorKeyBase,
  ),
  // 三指跳转：与「标记分段线」各是一条独立单元，触发时点相同——
  // 都挂在标记动作真正做成的产物序号上。两步都锚刚标记的那条线（线身基键
  // + 本单元记下的序号）：① 就地讲解沿用「标记分段线」那句话；② 动手演练
  // 三指滑，判据 = 三指跳转做到过（不要求滑的是这条线）。
  GuideStep(
    id: 'badge_three_finger_flag_step',
    unitId: badgeThreeFingerJumpUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: segmentLineAnchorKeyBase,
  ),
  GuideStep(
    id: 'badge_three_finger_jump_step',
    unitId: badgeThreeFingerJumpUnitId,
    form: GuideUnitForm.handsOnDrill,
    handsOnCriterion: HandsOnCriterion.threeFingerJumpPerformed,
    stickyAnchor: true,
    requestsEnterWatching: true,
    anchorKey: segmentLineAnchorKeyBase,
    actionIcon: Icons.swipe,
  ),
  GuideStep(
    id: 'badge_half_beat_step',
    unitId: badgeHalfBeatUnitId,
    form: GuideUnitForm.inplaceTour,
    anchorKey: halfBeatLineAnchorKeyBase,
  ),
];

/// 注册表里某引导单元的全部步（顺序即推进序）：多步单元的步数与推进共用
/// 同一个取值点。
List<GuideStep> guideStepsOfUnit(String unitId) => [
  for (final step in helpGuideSteps)
    if (step.unitId == unitId) step,
];

/// 某步在给定首启分支下是否可能上场（带分支门槛的步只认同一取值；其余步
/// 不受分支影响）。收场判定与演出层的步数指示共用同一谓词，不各抄一份。
bool guideStepRunsUnderChoice(GuideStep step, FirstRunChoice? choice) =>
    step.firstRunChoice == null || step.firstRunChoice == choice;

/// [step] 是否是本单元在给定首启分支下能走到的最后一步（首启的指认步锚点
/// 与文案按分支取，谁上场谁就是收场步；其余单元不受分支影响，行为与
/// 「单元最后一步」一致）。
bool guideIsFinalStepOfUnit(GuideStep step, FirstRunChoice? choice) {
  final candidates = [
    for (final s in guideStepsOfUnit(step.unitId))
      if (guideStepRunsUnderChoice(s, choice)) s,
  ];
  return candidates.isNotEmpty && candidates.last.id == step.id;
}

/// [unitId] 在注册表里的全部步是否都已走完（读面是**本会话已走完的步**）：
/// 多步单元用来判「轮到它后面的那一步了」——注册表序即推进序，本单元全部步
/// 走完才轮到下一个单元。
bool guideUnitStepsDone(String unitId, Set<String> sessionStepsDone) => [
  for (final step in guideStepsOfUnit(unitId)) step.id,
].every(sessionStepsDone.contains);

/// 首启第 1 步的锚点 key：锚点包装器与被包控件共用同一份字面量。
const String importVideoAnchorKey = 'import_video_button';

/// 首启第 2 步的锚点 key：与首页帮助入口是同一个控件。
const String homeHelpEntryAnchorKey = 'home_help_entry';

/// 首尾线步的锚点 key：有效练习区间的头线与尾线。头线是
/// 主播点（气泡指它、它在场才出场），尾线只跟着同圈一圈。
const String practiceRangeHeadAnchorKey = 'practice_range_head_line';
const String practiceRangeTailAnchorKey = 'practice_range_tail_line';

/// 编辑态上手两步的锚点 key：第一段段体与第一条分段线的手柄，分别与播放域
/// 轨道带内的既有控件定位 key（`learning_segment_0` / `segment_line_0_handle`）
/// 逐位一致。
const String learningSegment0AnchorKey = 'learning_segment_0';
const String segmentLine0HandleAnchorKey = 'segment_line_0_handle';

/// 「删除」工具槽的锚点 key：分段第 ② 步指住它讲一句"点这里撤掉"。
/// 它**只在编辑态那一枚槽上接线**——对比态另有一枚同名槽（`ToolSlotTable.compare`
/// 的 key 与本值逐位相同），不接锚点（见 `control_layer` 的槽条目装配）。
const String segmentDeleteSlotAnchorKey = 'control_segment_delete';

/// 自动分段就地讲解的锚点 key：「自动分段」三档菜单的容器——菜单
/// 路由自建容器时用它包 [GuideAnchor]，洞挖在菜单本体上（不回指工具槽）。
const String autoSegmentMenuAnchorKey = 'auto_segment_menu';

/// 节拍提示三步走查的锚点 key：气泡里的动画 / 声音 / 矫正三栏。
const String beatAnimationColumnAnchorKey = 'beat_animation_column';
const String beatSoundColumnAnchorKey = 'beat_sound_column';
const String beatCorrectColumnAnchorKey = 'beat_correct_column';

/// 倍速一步走查的锚点 key：气泡里的步进栏，与播放域既有控件定位 key
/// `speed_step_column` 逐位一致。倍速栏不承载引导锚点。
const String speedStepColumnAnchorKey = 'speed_step_column';

/// 音画同步一步走查的锚点 key：含 ＋/－ 的那一行
/// （`[－][读数][＋] [重置]`）。
const String avSyncDelayColumnAnchorKey = 'av_sync_delay_column';

/// 名册短暂提示的锚点 key：备注编辑里的「名册」钮。
const String rosterButtonAnchorKey = 'roster_button';

/// 三条菜单类的锚点 **基键**：实际锚点 key 由基键与本会话
/// 记下的新产物序号拼出（[guideArtifactAnchorKey]），与轨道带里实物控件的
/// 定位 key 逐位一致（镜像块 `mirror_fragment_N`、被标记的那条分段线
/// `segment_line_N`、新落的半拍线 `half_beat_line_N`）。注册表步声明基键、
/// 播放域按同一序号包锚点：**触发与「新产物是谁」在同一处取得**，指的一
/// 定是刚落的那一条。
const String mirrorFragmentAnchorKeyBase = 'mirror_fragment';
const String segmentLineAnchorKeyBase = 'segment_line';
const String halfBeatLineAnchorKeyBase = 'half_beat_line';

/// 局部镜像**第二步**的锚点 key：顶栏 / 竖屏视频
/// 工具栏里那枚「局部镜像」开关槽的槽键（`PlayToolSlot.key`）——顶栏槽声明
/// `carriesGuideAnchor` 为真，播放域在渲染点按声明包锚点，锚点 key 即槽键。
/// 与 [segmentDeleteSlotAnchorKey] 同形：锚点 key 由帮助域声明，播放域只在自己的
/// 挂载点包装。
const String localMirrorSwitchAnchorKey = 'tool_local_mirror';

/// 分段线**控制柄**的锚点后缀：与 [segmentLineAnchorKeyBase] 同一
/// 个基键、同一个新落线序号，末尾加本后缀——拼出的 key 与轨道手柄带里那根
/// 小把手的定位 key 逐位一致（`segment_line_N_handle`）。分段第 ① 步框住的
/// 就是它，而同一个基键不带后缀的拼法（`segment_line_N`）是通高的线身（分段
/// /「标记分段线」两条角标的锚点），两者互不顶替。
const String segmentLineHandleAnchorKeySuffix = '_handle';

/// 分段线**控制柄**的锚点 key 唯一拼法：线身基键 + 序号 + 后缀。
/// 轨道手柄带里那根小把手的定位 key 由它给出，与
/// [GuideStep.anchorKeySuffix] 的拼法同一结果（[segmentLine0HandleAnchorKey]
/// 即本函数取 0）。
String segmentLineHandleAnchorKey(int index) =>
    '${guideArtifactAnchorKey(segmentLineAnchorKeyBase, index)}'
    '$segmentLineHandleAnchorKeySuffix';

/// 实物锚点 key 的唯一拼法：基键 + 序号（注册表步声明基键、播放域包锚点、
/// 引导宿主取矩形三处共用，不各拼一份）。
String guideArtifactAnchorKey(String baseKey, int index) => '${baseKey}_$index';

/// 三条「锚在刚落成实物上」的角标步的**实物锚点基键**全集（分段第 ② 步锚
/// 「删除」工具槽那样的固定锚点不在内）：只有步声明的是这些基键之一，才按
/// 本会话记下的新产物序号拼出实际 key。同一单元里可以既有实物锚点步、也有
/// 固定锚点步（分段第 ① 步锚控制柄、第 ② 步锚「删除」槽），故本判据按
/// **步声明的基键**取，不按单元 id 推。
const Set<String> guideArtifactAnchorKeyBases = {
  mirrorFragmentAnchorKeyBase,
  segmentLineAnchorKeyBase,
  halfBeatLineAnchorKeyBase,
};

/// 引导步此刻的锚点 key：本会话记着该单元新产物序号、且本步声明的就是**实物
/// 锚点基键**（[guideArtifactAnchorKeyBases]）时，按序号拼出实际锚点 key
/// （[guideArtifactAnchorKey]），再补上步自己声明的尾缀（[GuideStep.anchorKeySuffix]
/// ——同一件实物上的另一个部位）；其余步用注册表声明的 key。序号取不到时用
/// 基键——基键不承载任何实物（锚点缺席），宿主按无锚点放行。
///
/// 本结果即步声明的**主播点**锚点 key = [GuideStep.anchorKey]：演出层只指它、
/// 只有它的在场决定本步出场；同一个步的其余锚点（[GuideStep.otherAnchorKeys]）
/// 只跟着圈圈、不进出场判定。
String? guideAnchorKeyOfStep(GuideStep step, Map<String, int> artifactIndexes) {
  final baseKey = step.anchorKey;
  if (baseKey == null) return null;
  final index = artifactIndexes[step.unitId];
  final key = index != null && guideArtifactAnchorKeyBases.contains(baseKey)
      ? guideArtifactAnchorKey(baseKey, index)
      : baseKey;
  return key + (step.anchorKeySuffix ?? '');
}

/// 步声明的全部锚点 key（主播点在前，其余按声明序）：演出层按本清单给每一
/// 枚**在场**锚点各圈一圈。
List<String> guideAnchorKeysOfStep(
  GuideStep step,
  Map<String, int> artifactIndexes,
) {
  return [
    ?guideAnchorKeyOfStep(step, artifactIndexes),
    ...step.otherAnchorKeys,
  ];
}

/// 序号 [index] 的实物此刻的角标锚点 key：只有它就是本会话刚落成的那一个
/// （[artifactIndexes] 里记着同一序号）才返回 key，否则 null——轨道带据此
/// 决定包不包锚点。
///
/// **按单元 id + 基键两个入参调用**：一条线身 / 一根控制柄 / 一块镜像片段
/// 可以同时承载多枚锚点（分段第 ① 步锚控制柄、第 ② 步锚「删除」槽），各步
/// 的基键不同但序号口径同一，故基键由调用方按自己要包的那一步给出，不按
/// 单元 id 反查步（同一单元里多步用不同基键）。基键取注册表步声明的值，
/// 播放域不另抄一份。
String? liveArtifactAnchorKeyOfBase(
  String unitId,
  String? baseKey,
  Map<String, int> artifactIndexes,
  int index,
) {
  if (baseKey == null || artifactIndexes[unitId] != index) return null;
  return guideArtifactAnchorKey(baseKey, index);
}

/// [unitId] 里声明了判据 [criterion] 的那一步：播放域按注册表声明取步来包
/// 锚点（不另抄一份基键与尾缀）。找不到抛 StateError。
GuideStep guideHandsOnStep(String unitId, HandsOnCriterion criterion) =>
    helpGuideSteps.firstWhere(
      (s) => s.unitId == unitId && s.handsOnCriterion == criterion,
      orElse: () => throw StateError('引导单元 $unitId 没有判据 $criterion 的步'),
    );

/// 手势演练的一个子勾（第 4 步内含的点击类动作）：做对一次记一勾。子勾片的
/// 文字是**文案**，按本 id 去 `assets/help/onboarding.yaml` 查。
class GuideDrillSubCheck {
  const GuideDrillSubCheck({required this.id});

  final String id;
}

/// 手势演练步（`player_drill` 单元，停靠待办条）：条子按本表顺序推进，做对
/// 打勾。**结构在这里，那一句话在随包文件**（按本表 id 查）。
class GuideDrillStep {
  const GuideDrillStep({
    required this.id,
    required this.actionIcon,
    this.subChecks = const [],
  });

  final String id;

  final IconData actionIcon;

  /// 末步的三个子勾（其余步为空）。
  final List<GuideDrillSubCheck> subChecks;
}

/// 手势演练步表：单指滑 / 双指滑 / 末步三个点击类子勾（三步；三指滑不在此教）。
const List<GuideDrillStep> helpDrillSteps = [
  GuideDrillStep(
    id: 'drill_single_finger',
    actionIcon: Icons.swipe,
  ),
  GuideDrillStep(
    id: 'drill_two_finger',
    actionIcon: Icons.fast_forward,
  ),
  GuideDrillStep(
    id: 'drill_taps',
    actionIcon: Icons.touch_app,
    subChecks: [
      GuideDrillSubCheck(id: 'drill_double_tap'),
      GuideDrillSubCheck(id: 'drill_two_finger_double_tap'),
      GuideDrillSubCheck(id: 'drill_long_press'),
    ],
  ),
];

/// 手势演练单元的「已看过」状态位 id（`onboarding.playerDrill`）。
const String playerDrillUnitId = 'player_drill';

/// 注册表条目在帮助中心目录里的定位 key（`help_entry_<id>`），供排序与
/// 集合断言使用；不承载别的语义。
Key helpEntryKey(String id) => Key('help_entry_$id');
