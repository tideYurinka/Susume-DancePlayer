part of 'control_layer.dart';

/// 底部标注工具行：槽集声明遍历成条目、底排事实装配、判定表门控管道
/// （可点性派生与置灰原因提示）与熟练度内联档位件。

/// 标注工具区整排：由槽集声明遍历生成——有哪些槽、什么次序全
/// 由 [ToolSlotTable] 决定，本行不写死任何子序；加槽、换序只改声明。
///
/// 槽件按 [ToolSlotId] 装配（各自保留自己的动作与外观），渲染次序即声明
/// 次序；测试侧的跨面一致性断言把「槽集声明的槽位」与「实际渲染出的槽键」
/// 钉成逐位相等。
///
/// 一行渲染的槽位集就是该行的全部槽位：无溢出判定、无「更多」入口、无
/// 横向滚动兜底。横竖屏同一行同一装配，行的可用宽由分行取得。
class _ToolSlotRow extends ConsumerWidget {
  const _ToolSlotRow({
    required this.table,
    required this.mirror,
    required this.session,
  });

  final ToolSlotTable table;

  /// 镜像控制器（创建片段即打开局部镜像总开关的落点）。
  final MirrorController mirror;

  /// 轨道带会话域（落半拍线后收视野的写口）。
  final TrackBandSession session;

  /// 本面事实：底排这一个求值面只在这里组装一次
  /// ——各槽件消费传进来的声明行与事实，不自报门集合、不自算命中。
  ToolFacts _facts(WidgetRef ref) {
    final timeline = ref.watch(annotationTimelineProvider);
    final segmentCount = deriveLearningSegments(timeline).length;
    final selectedSegment = ref.watch(
      selectedLearningSegmentRepresentativeProvider,
    );
    final segmentLine = ref.watch(selectedSegmentLineIndexProvider);
    final halfBeatLine = ref.watch(selectedHalfBeatLineIndexProvider);
    final mirrorFragment = ref.watch(selectedLocalMirrorFragmentIndexProvider);
    final clipId = ref.watch(selectedPracticeClipIdProvider);
    final ready = ref.watch(beatGridProvider).hasRealBeats;
    final engine = ref.watch(playbackEngineProvider);
    final position =
        ref.watch(playbackPositionProvider).value ?? engine.position;
    final inBounds = previewLineInBounds(position, timeline);
    final anchorAvailable = ref.watch(beatCorrectionAvailableProvider);
    final anchorOccupied = ref.watch(previewAnchorOccupiedProvider);
    // 对象事实按面填（各面按自己有哪些对象填；分支收在
    // 本面唯一的装配点，槽件零分支）：对比面的删除对象 = 选中的练习
    // 片段（两类线在对比态删不掉，line/halfBeat 选中残留不跨面点亮）；
    // 编辑/待命面的删除对象 = 线与局部镜像片段（片段选中残留不点亮）。
    final isCompare = ref.watch(playerSessionProvider).isCompare;
    return ToolFacts(
      loading: ref.watch(loadGateActiveProvider),
      locked: ref.watch(layoutLockedProvider),
      gridNotReady: !ready,
      previewOutOfBounds: ready && !inBounds,
      selectedLearningSegmentInInterval:
          selectedSegment != null && selectedSegment < segmentCount,
      selectedSegmentLine: segmentLine != null,
      anyLineSelected:
          !isCompare &&
          (segmentLine != null ||
              halfBeatLine != null ||
              mirrorFragment != null),
      selectedPracticeClip: isCompare && clipId != null,
      anchorAddable: anchorAvailable && !anchorOccupied,
      anchorRemovable: anchorAvailable && anchorOccupied,
      hasAnchors: ref.watch(hasEightBeatAnchorsProvider),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = _facts(ref);
    final entries = [
      for (final slot in table.slots)
        _bottomToolEntry(slot, facts, ref, mirror: mirror, session: session),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries)
          // Builder：槽位拿到自身锚点上下文（自带弹出菜单的槽锚自己）。
          Builder(
            builder: (anchor) =>
                entry.inlineOverride?.call(anchor, ref) ??
                _gatedInline(entry, anchor),
          ),
      ],
    );
  }
}

/// 判定 → 按下动作（槽位装配唯一消费的映射）：不可点不挂动作；正常态走
/// [onInvoke]；置灰可点走 [_explainReasonTap]（装载未完成 → 「正在装载」
/// 压倒一切、锁定分段 → 「已锁定分段」、无对象 → [onNoSubject] 的
/// 「该怎么做」、其余 → [onExplain] 的「节拍分析中…」/「无节拍数据」）。
VoidCallback? _gatedTap(
  WidgetRef ref,
  ToolSlotVerdict verdict, {
  VoidCallback? onInvoke,
  VoidCallback? onExplain,
  VoidCallback? onNoSubject,
}) {
  if (!verdict.tappable) return null;
  if (verdict.available) return onInvoke;
  return _explainReasonTap(ref, verdict, onExplain, onNoSubject);
}

/// 「灰着、按得动、点一下说原因」的唯一映射：原因是哪一种由
/// 判定表给出的 [ToolSlotVerdict.kind] 决定——装载未完成压倒该槽自己的
/// 原因（判定表最前一行）；锁定分段弹「已锁定分段」；无对象弹该入口的
/// 「该怎么做」；其余（网格未就绪）走调用侧的 [onExplain]。
VoidCallback? _explainReasonTap(
  WidgetRef ref,
  ToolSlotVerdict verdict,
  VoidCallback? onExplain,
  VoidCallback? onNoSubject,
) {
  return switch (verdict.kind) {
    ToolGateKind.loading =>
      () => ref.read(noticeTriggerProvider(NoticeId.loadGate).notifier).show(),
    ToolGateKind.locked =>
      () =>
          ref.read(noticeTriggerProvider(NoticeId.layoutLock).notifier).show(),
    ToolGateKind.gridNotReady => onExplain,
    // 无对象：该入口的做法文案；没接线的入口（没有一句做法
    // 可给的，如待命态锚点三槽）保持既有的「按不动、静默」。
    ToolGateKind.noSubject => onNoSubject,
    ToolGateKind.previewOutOfBounds || null => null,
    // 投屏入口那五条门（票 #35）只挂在顶栏投屏槽上，底排标注工具区
    // 不声明它们——走到这里是不可能的组合；显式列出而不是吞进兜底，
    // 读的人知道它们被想过。
    ToolGateKind.castCopyMissing ||
    ToolGateKind.castAvSyncCalibrating ||
    ToolGateKind.castRecording ||
    ToolGateKind.castCompareOrFraming ||
    ToolGateKind.castRendering => null,
  };
}

/// 「无对象」门的做法提示：按**这支舞有没有分段**两态取辞
/// （事实 = 派生学习段是否为空——「分段」切出来的段），短暂提示每次按都弹。
/// 文案表与提示声明在 `no_subject_hint.dart`，本处只供事实。
void _showNoSubjectHint(WidgetRef ref, NoSubjectHint hint) {
  showNoSubjectHint(
    ref,
    hint,
    hasSegments: deriveLearningSegments(ref.read(annotationTimelineProvider))
        .isNotEmpty,
  );
}

/// 入口声明的做法 → 无对象态按下去的动作：**声明是唯一来源**（null = 这个
/// 入口没有一句做法可给，此刻判定表也不会报可点）。渲染层不各排一份口径。
VoidCallback? _noSubjectHintTap(WidgetRef ref, NoSubjectHint? hint) =>
    hint == null ? null : () => _showNoSubjectHint(ref, hint);

/// 底栏标注工具槽条目：标注工具区那一排槽元数据的唯一来源——加槽 / 换文案 /
/// 换动作只改这里。
///
/// [inlineOverride] 仅熟练度槽使用（其形态是自带档位菜单、几何比其余槽少一
/// 层外内边距的 [PopupMenuButton]）；[onInvoke] 收锚点上下文——锚槽位自身。
class _BottomToolEntry {
  _BottomToolEntry({
    required this.slot,
    required this.label,
    required this.icon,
    required this.verdict,
    this.active = false,
    this.activeColor,
    this.iconKey,
    this.onInvoke,
    this.onExplain,
    this.inlineOverride,
  });

  final ToolSlot slot;
  final String label;
  final IconData icon;
  final ToolSlotVerdict verdict;

  final bool active;
  final Color? activeColor;
  final Key? iconKey;
  final void Function(BuildContext anchor)? onInvoke;
  final VoidCallback? onExplain;
  final Widget Function(BuildContext anchor, WidgetRef ref)? inlineOverride;
}

/// 条目 → 槽座架（唯一消费条目字段的渲染点）。无对象做法与引导锚点都取
/// **槽声明**里的字段（[ToolSlot.noSubjectHint] / [ToolSlot.carriesGuideAnchor]），
/// 本处不另排一份口径：哪些槽承载引导锚点是槽集数据的一部分（同一枚槽 key
/// 在编辑态与对比态是两枚不同的槽），锚点 key 即槽键。
Widget _gatedInline(_BottomToolEntry entry, BuildContext anchor) {
  final slot = _GatedToolSlot(
    keyName: entry.slot.key,
    label: entry.label,
    icon: entry.icon,
    verdict: entry.verdict,
    active: entry.active,
    activeColor: entry.activeColor,
    iconKey: entry.iconKey,
    onInvoke: entry.onInvoke == null ? null : () => entry.onInvoke!(anchor),
    onExplain: entry.onExplain,
    noSubjectHint: entry.slot.noSubjectHint,
  );
  if (!entry.slot.carriesGuideAnchor) return slot;
  return GuideAnchor(anchorKey: entry.slot.key, child: slot);
}

/// 落锚提交（待命态「设为八拍线」）：在预览位置（最近强拍）提交
/// 一次 [AddEightBeatAnchor]——请求位置取落点 seam 解析出的强拍时刻（模块
/// 内落点解析幂等，传裸时间同结果；两处共用同一纯函数）。
void _addAnchor(WidgetRef ref) {
  final downbeat = ref.read(previewDownbeatProvider);
  if (downbeat == null) return;
  ref
      .read(annotationEditorProvider)
      .submit(AddEightBeatAnchor(at: downbeat.time));
}

/// 删锚提交（待命态「取消八拍线」）：删掉预览位置（最近强拍）那个
/// 锚点——与 [_addAnchor] 同一落点 seam、同一提交语义（点击即原子写、
/// 一次标注编辑单步可撤销，删后派生面当帧刷新）。
void _removeAnchor(WidgetRef ref) {
  final downbeat = ref.read(previewDownbeatProvider);
  if (downbeat == null) return;
  ref
      .read(annotationEditorProvider)
      .submit(RemoveEightBeatAnchor(at: downbeat.time));
}

/// 底栏槽声明行 + 事实 → 槽条目（底栏槽身份到渲染的唯一映射）：
/// 有哪些槽由 [ToolSlotTable] 决定，本函数只按 [ToolSlotId]
/// 装配各自保留的文案、图标、激活态与动作；加槽只改声明，漏补即编译报错
/// （穷尽 switch）。
///
/// 门与可点性一律经 [evaluateToolEntry]（声明 ∩ 事实 → verdict），本处不
/// 自算命中；[ToolSlotId.mastery] 的内联形态自带档位菜单，见
/// [_BottomToolEntry.inlineOverride]。
///
/// 待命态（八拍矫正）四槽：锚点三槽由 [previewAnchorOccupiedProvider] 与
/// [hasEightBeatAnchorsProvider] 驱动互斥置灰，退出槽无门恒可点。刻意的
/// 不对称（第②门的做法随入口声明）：自动分段缺网格走「网格
/// 未就绪」门（可点、弹原因），锚点三槽缺网格走「无对象」门——槽声明的
/// 做法刻意为空，故仍置灰、按不动、静默（见下段）。锚点槽的「对象」就是
/// 落点本身，没有网格就没有对象。
///
/// 锚点三槽不给做法（不同款）：判定表第②行起「无对象」可点并
/// 弹「该怎么做」，四个灰钮入口各自在表里声明了一句做法
/// （[ToolSlot.noSubjectHint]）；锚点三槽的置灰是**互斥**的（设/取消同一
/// 谓词驱动，清除槽无锚点才灰），此刻没有一句「该怎么做」可给，故声明为
/// 空——判定表据此把这一门对它们退回旧口径（置灰、按不动、静默），槽集
/// 声明与渲染逐位不变。
_BottomToolEntry _bottomToolEntry(
  ToolSlot slot,
  ToolFacts facts,
  WidgetRef ref, {
  required MirrorController mirror,
  required TrackBandSession session,
}) {
  switch (slot.id) {
    case ToolSlotId.mastery:
      // 熟练度作用在全部选中段上。代表段序即「最低档所属段」，故
      // 档位显示天然取多段中的最低档；选一档经批量写点改完全部选中段。
      final selected = ref.watch(selectedLearningSegmentRepresentativeProvider);
      final mastery = ref.watch(learningMasteryProvider);
      final enabled = facts.selectedLearningSegmentInInterval;
      final current = enabled
          ? learningSegmentMastery(mastery, selected!)
          : LearningMastery.unlearned;
      final label = learningMasteryLabel(current);
      // 判定表接线：门 = 无选中学习段（无对象）；装载未完成门
      // 排最前：装载期挡下写盘入口并弹原因。
      final verdict = evaluateToolEntry(slot, facts);
      return _BottomToolEntry(
        slot: slot,
        label: label,
        icon: _masteryIcon(current),
        verdict: verdict,
        active: verdict.available,
        activeColor: learningMasteryColor(current),
        inlineOverride: (anchor, ref) =>
            _masteryButton(ref, verdict, current, slot.noSubjectHint),
      );
    case ToolSlotId.emphasis:
      // 重点作用在全部选中段上——灯「全部选中段都有星才点亮」，
      // 按下经批量写点全开才关、否则全开（一次标注编辑、一步撤销）。
      final selected = ref.watch(selectedLearningSegmentsProvider);
      final emphasizedSegments = ref.watch(learningEmphasisProvider);
      // 判定表接线：门 = 无选中学习段（无对象）；锁定豁免。
      // 无对象：置灰可点、弹「该怎么做」、动作不发生。
      final verdict = evaluateToolEntry(slot, facts);
      return _BottomToolEntry(
        slot: slot,
        label: '重点',
        icon: Icons.star,
        verdict: verdict,
        active:
            verdict.available &&
            selected.isNotEmpty &&
            emphasizedSegments.containsAll(selected),
        activeColor: kHighlightAmber,
        iconKey: const Key('control_emphasis_icon'),
        // 重点写点改走标注编辑模块（批量写点）。
        onInvoke: selected.isEmpty
            ? null
            : (_) => ref
                  .read(annotationEditorProvider)
                  .submit(const ToggleSelectedSegmentsEmphasis()),
      );
    case ToolSlotId.segment:
      final track = ref.watch(beatTrackStateProvider);
      final engine = ref.watch(playbackEngineProvider);
      final position =
          ref.watch(playbackPositionProvider).value ?? engine.position;
      // 判定表接线：门按序 = 锁定 / 网格未就绪 / 预览线越界；
      // 表现与点击语义（含「越界 → 置灰不可点、无提示」）全由判定表给出。
      return _BottomToolEntry(
        slot: slot,
        label: '分段',
        icon: Icons.content_cut,
        verdict: evaluateToolEntry(slot, facts),
        // 正常态走动作；锁定态由判定表改走弹原因（「已锁定
        // 分段」），动作不发生、不落线。
        // 角标触发（改锚）：**落线成功**才记触达——节拍未
        // 就绪 / 锁定走 explain、落点越界或同位既有线（EditNoop）不落成，
        // 都不触达、不消耗；成功时把本次新线序号记进会话（与「添加」菜单
        // 条目同一套「触发与新产物是谁同处取得」，见「添加」装配处的
        // recordArtifact），轨道带按同一序号把锚点包在刚落的那条线上。
        // 连着落两条时序号更新为第二条，角标改指第二条。
        onInvoke: (_) {
          final before = ref.read(annotationTimelineProvider).segmentLines;
          final outcome = ref
              .read(annotationEditorProvider)
              .submit(AddSegmentLine(at: position));
          if (!outcome.applied) return;
          final index = indexOfNewItem(
            before,
            ref.read(annotationTimelineProvider).segmentLines,
            (a, b) => a.position == b.position,
          );
          if (index == null) return;
          // 落线即重开这一单元的判据：刚落这条线还没被选中过——
          // 即使它恰好顶掉了上一条刚被选中的线的序号，也不该一上来就打勾。
          ref
              .read(guideSessionProvider.notifier)
              .clearCriterion(HandsOnCriterion.badgeSegmentLineSelected);
          recordGuideArtifact(ref, badgeSegmentUnitId, index);
        },
        onExplain: () => showBeatReadinessPrompt(ref, track),
      );
    case ToolSlotId.add:
      // 「添加」钮不受锁：只声明装载未完成门，锁定期间正常色、菜单照常
      // 打开；菜单里只有「标记分段线」一条灰着（条目各自的门见
      // [AddEntryTable]）。
      return _BottomToolEntry(
        slot: slot,
        label: '添加',
        icon: Icons.add,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (anchor) => _showAddMenu(anchor, ref, mirror, session),
      );
    case ToolSlotId.delete:
      // 选中索引带外校验（越界/错位即 null），本处私有守卫移除。
      final selectedLine = ref.watch(selectedSegmentLineIndexProvider);
      final selectedHalfBeat = ref.watch(selectedHalfBeatLineIndexProvider);
      // 局部镜像片段选中（经片段单击只选中/拖动会话 begin 置入
      // 单选槽），删除可用并分派 [RemoveLocalMirrorFragment]。
      final selectedMirrorFragment = ref.watch(
        selectedLocalMirrorFragmentIndexProvider,
      );
      // 对比态下删除只认选中的练习片段——两类线在对比态删不掉；
      // 删除动作接线归（片段入轨后才有可删对象）。
      final selectedClipId = ref.watch(selectedPracticeClipIdProvider);
      // 删除写点改走标注编辑模块（级联/清选中在模块内收口）。
      // 半拍线删除走同管线 RemoveHalfBeatLine（无确认框即删）。
      // 门与事实消费声明行：无对象压倒锁定——
      // 无选中 → 置灰但按得动、弹「该怎么做」（动作不发生）；
      // 锁门随作用对象（[toolEntryLayoutLockApplies]）
      // ——选中的是分段线时置灰仍可点、弹锁提示，选中的是半拍线 /
      // 局部镜像片段 / 练习片段时照常可删。
      final VoidCallback? deleteOnTap;
      if (selectedClipId != null) {
        // 删除动作：只把选中的片段移出练习视频轨（素材文件与库内
        // 条目保留），一次撤销可回退——走标注编辑模块唯一写缝。
        deleteOnTap = () => ref
            .read(annotationEditorProvider)
            .submit(RemovePracticeClip(clipId: selectedClipId));
      } else if (selectedLine != null) {
        deleteOnTap = () => ref
            .read(annotationEditorProvider)
            .submit(RemoveSegmentLine(index: selectedLine));
      } else if (selectedHalfBeat != null) {
        // 局部拷贝为把非空提升带进闭包（闭包内不再提升外层局部变量）。
        final index = selectedHalfBeat;
        deleteOnTap = () => ref
            .read(annotationEditorProvider)
            .submit(RemoveHalfBeatLine(index: index));
      } else if (selectedMirrorFragment != null) {
        final index = selectedMirrorFragment;
        deleteOnTap = () => ref
            .read(annotationEditorProvider)
            .submit(RemoveLocalMirrorFragment(index: index));
      } else {
        deleteOnTap = null;
      }
      return _BottomToolEntry(
        slot: slot,
        label: '删除',
        icon: Icons.delete,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: deleteOnTap == null ? null : (_) => deleteOnTap!(),
      );
    case ToolSlotId.autoRange:
      // 就绪门 explain 原因（既有语义）：弹「节拍分析中…」/「无节拍数据」。
      final track = ref.watch(beatTrackStateProvider);
      return _BottomToolEntry(
        slot: slot,
        label: '自动分段',
        // 四根等高竖条：音符字形只归「节拍提示」。
        icon: Icons.view_week,
        verdict: evaluateToolEntry(slot, facts),
        // 角标触发：菜单打开 = 功能被真正使用（就绪门已过）。
        // 角标锚在**刚弹出的三档菜单本体**上（不回指工具槽）——菜单
        // 路由用带引导锚点的容器，打开即向引导宿主上报菜单矩形。
        onInvoke: (anchor) {
          ref
              .read(guideSessionProvider.notifier)
              .trigger(badgeAutoSegmentUnitId);
          _showAutoSegmentMenu(anchor, ref);
        },
        onExplain: () => showBeatReadinessPrompt(ref, track),
      );
    case ToolSlotId.practiceMirror:
      // 练习侧镜像槽：开关语义用「激活态琥珀 +
      // 点按取反」表达；激活态读生效值（覆盖 ?? 设备级默认）。**无门**
      // （对比-控制层内恒可点）；点按即写随舞覆盖会话值。
      final effective = ref.watch(effectivePracticeMirrorProvider);
      return _BottomToolEntry(
        slot: slot,
        label: '练习侧镜像',
        icon: Icons.flip,
        verdict: evaluateToolEntry(slot, facts),
        active: effective,
        activeColor: kHighlightAmber,
        onInvoke: (_) =>
            ref.read(practiceMirrorOverrideProvider.notifier).set(!effective),
      );
    case ToolSlotId.beatAnchorAdd:
      // 待命态「设为八拍线」：在预览位置落一个锚点（点击即原子写、无
      // 「应用」、一次标注编辑单步可撤销）。
      return _BottomToolEntry(
        slot: slot,
        label: '设为八拍线',
        icon: Icons.playlist_add,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (_) => _addAnchor(ref),
      );
    case ToolSlotId.beatAnchorRemove:
      // 待命态「取消八拍线」：删掉预览位置那个锚点；与「设为八拍线」互斥
      // 置灰（同一谓词驱动）。
      return _BottomToolEntry(
        slot: slot,
        label: '取消八拍线',
        icon: Icons.playlist_remove,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (_) => _removeAnchor(ref),
      );
    case ToolSlotId.beatAnchorsClear:
      // 待命态「清除所有八拍线」：一次点击清空全部锚点。
      return _BottomToolEntry(
        slot: slot,
        label: '清除所有八拍线',
        icon: Icons.layers_clear,
        verdict: evaluateToolEntry(slot, facts),
        // 一次点击 = 一次标注编辑（单步可撤销）。
        onInvoke: (_) => ref
            .read(annotationEditorProvider)
            .submit(const ClearEightBeatAnchors()),
      );
    case ToolSlotId.beatCorrectionExit:
      // 待命态「退出八拍矫正」：无门（显式空门清单），恒可点。
      return _BottomToolEntry(
        slot: slot,
        label: '退出八拍矫正',
        icon: Icons.exit_to_app,
        verdict: evaluateToolEntry(slot, facts),
        // 底排退出（改走模式值）：回编辑面（控制层仍展开）——待命态是模式取值
        // 之一，退待命 = 进入编辑取值。
        onInvoke: (_) => ref
            .read(playerSessionProvider.notifier)
            .enter(PlayerSessionMode.editing),
      );
    case ToolSlotId.segmentDensityFaster:
      // 段内倍频待命态「快一倍」：赋值钮——
      // 把选中的每一段**设为** ×2（不是相对步进，连按不叠乘）。作用对象 =
      // 选中的学习段；门 = 装载 + 无对象（同一句做法取辞）；经既有标注
      // 编辑提交路径落盘，一次改多段 = 一步撤销。
      return _BottomToolEntry(
        slot: slot,
        label: '快一倍',
        icon: Icons.speed,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (_) => ref
            .read(annotationEditorProvider)
            .submit(const SetSelectedSegmentsDensity(density: 2)),
      );
    case ToolSlotId.segmentDensitySlower:
      return _BottomToolEntry(
        slot: slot,
        label: '慢一半',
        icon: Icons.shutter_speed,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (_) => ref
            .read(annotationEditorProvider)
            .submit(const SetSelectedSegmentsDensity(density: 0.5)),
      );
    case ToolSlotId.segmentDensityReset:
      // 「回到原样」是赋值（设为 1，删键），不设「本来就是原样」的置灰门
      // ——选中段全为原样时仍可点（按下无变化，钉语义）。
      return _BottomToolEntry(
        slot: slot,
        label: '回到原样',
        icon: Icons.restart_alt,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (_) => ref
            .read(annotationEditorProvider)
            .submit(const SetSelectedSegmentsDensity(density: 1)),
      );
    case ToolSlotId.segmentDensityExit:
      // 待命态「退出」：无门（显式空门清单），恒可点；回编辑面（控制层
      // 仍展开），与八拍矫正退出同一口径。
      return _BottomToolEntry(
        slot: slot,
        label: '退出段内倍频',
        icon: Icons.exit_to_app,
        verdict: evaluateToolEntry(slot, facts),
        onInvoke: (_) => ref
            .read(playerSessionProvider.notifier)
            .enter(PlayerSessionMode.editing),
      );
  }
}

/// 熟练度五档图标（熟练度槽用）。
IconData _masteryIcon(LearningMastery value) => switch (value) {
  LearningMastery.unlearned => Icons.circle_outlined,
  LearningMastery.learning => Icons.timelapse,
  LearningMastery.keepingUp => Icons.directions_run,
  LearningMastery.familiar => Icons.thumb_up,
  LearningMastery.mastered => Icons.check_circle,
};

/// 熟练度槽内联形态：自带五档菜单的 [PopupMenuButton]，槽键
/// `control_mastery` 挂在本控件上（测试与无障碍助手据此定位）。内联几何比
/// 其余槽少一层外内边距（不经 [_GatedToolSlot] 座架）。
///
/// 「无对象」门：置灰、按得动、点一下弹**本槽声明的做法**
/// （[ToolSlot.noSubjectHint]），**不打开档位菜单、不写盘**——档位菜单是
/// 「动作」，此刻没有作用对象。档位菜单的几何逐位沿用（同一条
/// [PopupMenuButton]，只是置为 `enabled: false`）。
Widget _masteryButton(
  WidgetRef ref,
  ToolSlotVerdict verdict,
  LearningMastery current,
  NoSubjectHint? noSubjectHint,
) {
  final visual = Semantics(
    button: true,
    selected: verdict.available,
    enabled: verdict.tappable,
    child: _ToolSlotVisual(
      label: learningMasteryLabel(current),
      icon: _masteryIcon(current),
      activeColor: learningMasteryColor(current),
      active: verdict.available,
      available: verdict.available,
    ),
  );
  final noSubjectTap = _noSubjectHintTap(ref, noSubjectHint);
  if (verdict.kind == ToolGateKind.noSubject && noSubjectTap != null) {
    return KeyedSubtree(
      key: const Key('control_mastery'),
      child: InkWell(
        onTap: noSubjectTap,
        child: PopupMenuButton<LearningMastery>(
          enabled: false,
          itemBuilder: (context) => _masteryMenuItems(null),
          child: visual,
        ),
      ),
    );
  }
  return PopupMenuButton<LearningMastery>(
    key: const Key('control_mastery'),
    enabled: verdict.tappable,
    onSelected: verdict.tappable
        ? (value) => _applyMasteryChoice(ref, verdict, value)
        : null,
    // 当前档位高亮走条目自身（[CheckedPopupMenuItem]）而非
    // PopupMenuButton.initialValue——向上菜单与槽位共用同一份条目，
    // 两条路径的高亮口径因此一致。
    itemBuilder: (context) =>
        _masteryMenuItems(verdict.available ? current : null),
    child: visual,
  );
}

/// 熟练度菜单项（五档、条目键与当前档位高亮口径；[current] 为 null 时
/// 无高亮）。
List<PopupMenuEntry<LearningMastery>> _masteryMenuItems(
  LearningMastery? current,
) => [
  for (final candidate in LearningMastery.values)
    CheckedPopupMenuItem<LearningMastery>(
      key: Key('control_mastery_${candidate.name}'),
      value: candidate,
      checked: candidate == current,
      child: Text(learningMasteryLabel(candidate)),
    ),
];

/// 熟练度写点（唯一入口）：装载未完成可点、弹原因、不写盘（唯一
/// 写盘保护）；其余走标注编辑模块——现为批量写点（一次改完全部
/// 选中段，一个 diff、一步撤销）。
void _applyMasteryChoice(
  WidgetRef ref,
  ToolSlotVerdict verdict,
  LearningMastery value,
) {
  if (verdict.kind == ToolGateKind.loading) {
    ref.read(noticeTriggerProvider(NoticeId.loadGate).notifier).show();
    return;
  }
  ref
      .read(annotationEditorProvider)
      .submit(SetSelectedSegmentsMastery(mastery: value));
}

/// 工具槽视觉（取值一律引用集中视觉 token）：供门控槽座架与
/// 熟练度弹出菜单共用；槽自身不自算颜色。
class _ToolSlotVisual extends StatelessWidget {
  const _ToolSlotVisual({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.available,
    this.iconKey,
  });

  final String label;
  final IconData icon;

  /// 激活态（有激活态的槽才可能为 true：熟练度 / 重点）。
  final bool active;

  /// 激活配色（可选输入：熟练度用熟练度色、重点用琥珀，其余不传）。
  final Color? activeColor;

  /// 正常（无门命中）；false = 置灰。
  final bool available;
  final Key? iconKey;

  @override
  Widget build(BuildContext context) {
    final iconColor = active && activeColor != null
        ? activeColor!
        : available
        ? kToolSlotEnabledIconColor
        : kToolSlotDisabledIconColor;
    final textColor = active && activeColor != null
        ? kToolSlotActiveTextColor
        : available
        ? kToolSlotEnabledTextColor
        : kToolSlotDisabledTextColor;
    // 透明命中盒：把可点层撑到密集区兜底
    // 下限、视觉件在加宽方向居中其内——图标 24 档、标签 10 档、槽件自然
    // 高 48 与行名义高 52 一个像素都不动（纵向自然高已过 44，外扩实际
    // 只发生在宽度向）。标注工具区是邻接密集区：六/七槽同排、槽间只隔
    // 「外 6」内边距，为什么这里达不到 48——按 48 外扩相邻命中域会互吞，
    // 故取 [kHitTargetDenseMinSize] 兜底；
    // 通行下限读 [kHitTargetMinSize]（非密集区消费面用）。
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: kHitTargetDenseMinSize,
        minHeight: kHitTargetDenseMinSize,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kToolSlotInnerPaddingH,
          vertical: kToolSlotInnerPaddingV,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, key: iconKey, color: iconColor, size: kToolSlotIconSize),
            const SizedBox(height: 2),
            Text(label, style: _kToolSlotLabelStyle.copyWith(color: textColor)),
          ],
        ),
      ),
    );
  }
}

/// 标注工具槽统一座架：表现与点击语义一律取自判定表
/// （[ToolSlotVerdict]），槽内不自算颜色、不自算可点性、不自拼点击阶梯。
///
/// - 点击映射（[_gatedTap]）：可点才挂 onTap；正常态走 [onInvoke]；置灰可点
///   走原因提示——装载未完成弹「正在装载」、锁定分段弹「已锁定分段」、无对象
///   弹该入口声明的做法（[noSubjectHint]）（一处门：门原因由本座架统一
///   给出，槽件不各写一份），其余走 [onExplain]（弹「节拍分析中…」/
///   「无节拍数据」）；不可点不挂 onTap（按不动、静默）。
/// - 无障碍语义：每槽都是一个按钮并报出可点与否（[ToolSlotVerdict.tappable]
///   ——判定表是唯一来源）；有激活态的槽另报「已选中」（[active]）。
class _GatedToolSlot extends ConsumerWidget {
  const _GatedToolSlot({
    required this.keyName,
    required this.label,
    required this.icon,
    required this.verdict,
    this.onInvoke,
    this.onExplain,
    this.noSubjectHint,
    this.active = false,
    this.activeColor,
    this.iconKey,
  });

  final String keyName;
  final String label;
  final IconData icon;
  final ToolSlotVerdict verdict;

  /// 正常态按下去的动作。
  final VoidCallback? onInvoke;

  /// 网格未就绪态按下去的原因提示（按节拍轨状态区分文案）。
  final VoidCallback? onExplain;

  /// 本槽声明的「无对象」做法（null = 没话说，判定表也就不会报
  /// 可点）。
  final NoSubjectHint? noSubjectHint;

  /// 激活态（另报「已选中」；激活配色为可选输入）。
  final bool active;
  final Color? activeColor;

  final Key? iconKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final column = _ToolSlotVisual(
      label: label,
      icon: icon,
      active: active,
      activeColor: activeColor,
      available: verdict.available,
      iconKey: iconKey,
    );
    // 判定 → 动作的唯一映射（[_gatedTap]）。
    final onTap = _gatedTap(
      ref,
      verdict,
      onInvoke: onInvoke,
      onExplain: onExplain,
      onNoSubject: _noSubjectHintTap(ref, noSubjectHint),
    );
    return Semantics(
      key: Key(keyName),
      button: true,
      selected: active,
      enabled: verdict.tappable,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kToolSlotOuterPaddingH),
        child: InkWell(
          borderRadius: BorderRadius.circular(kToolSlotRadius),
          onTap: onTap,
          child: column,
        ),
      ),
    );
  }
}

/// 竖屏标注工具行的 key（溢出断言按行取矩形）。
const Key kAnnotationToolRowKey = Key('control_layer_annotation_row');

/// 标注工具槽标签样式（渲染 [_ToolSlotVisual] 的唯一来源：字距不写死，
/// 随环境继承）。语义档（随系统字号）：槽标签承载语义、随系统字号缩放，
/// 量宽与渲染同源。
const TextStyle _kToolSlotLabelStyle = TextStyle(
  fontSize: kToolSlotLabelFontSize,
);
