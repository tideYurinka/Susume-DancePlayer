part of 'annotation_editor.dart';

// 标注写读面 store 区：保存缝状态胶水、
// 时间线 store、选中带外派生读面、熟练度/重点 store、激活/临时段 store、
// 选中循环范围派生、clearLoopActivationsIfOutside helper、历史模型与快照。
// 选中状态本体（单值槽 + 学习段选中 store/provider）住在选中域库
//（`annotation_selection.dart`），本文件只留按现势几何做越界校验的派生视图
// 与跨域写点（经域对象）。符号名、语义、provider 身份全保留；变更方法保持
// library 私有——唯一写入口是同库的 [AnnotationEditor] 与域对象。

/// 标注保存编排器接缝：标注编辑模块每次**完成**的编辑提交
/// 经此把段级 diff 交给保存编排（burst 合并 latest-wins、切后台/退出
/// flush、写失败静默由编排器承担）。默认 null；打开恢复接线在按路径取到
/// 身份（条目命中，或兜底定身份并补建条目）后注入 per-video 实例
/// （[VideoOpenRestorer]），会话无身份时保持 null（无落盘目标）。
class AnnotationSaveSinkModel extends Notifier<AnnotationSaveSink?> {
  @override
  AnnotationSaveSink? build() {
    // 注入态跨打开保持（Riverpod 3 默认无监听即销毁）：恢复接线注入后由
    // 播放页消费，播放页收尾显式清空。
    ref.keepAlive();
    return null;
  }

  /// 打开恢复接线注入 / 播放页收尾清空（容器先于收尾微任务销毁时跳过）。
  void set(AnnotationSaveSink? value) {
    if (!ref.mounted) return;
    state = value;
  }
}

final annotationSaveSinkStateProvider =
    NotifierProvider<AnnotationSaveSinkModel, AnnotationSaveSink?>(
      AnnotationSaveSinkModel.new,
    );

/// 保存编排器读取 seam：保持 Provider 形态，既有测试的
/// `overrideWithValue` 注入与各读取方用法不变。
final annotationSaveSinkProvider = Provider<AnnotationSaveSink?>((ref) {
  return ref.watch(annotationSaveSinkStateProvider);
});

/// 标注时间线模型（内存态）：默认整片有效区间、无分段线。
///
/// store 私有化：本模型是纯**读取源**，唯一写入口
/// 在标注编辑模块（[AnnotationEditor]）——变更方法全部 library 私有，
/// 选中维护（插线平移/删线整体清/重映射）由模块执行管线内的 selectionOp
/// 完成，模型写序不再附带任何簿记。
class AnnotationTimelineModel extends Notifier<AnnotationTimeline> {
  @override
  AnnotationTimeline build() {
    return AnnotationTimeline.wholeVideo(
      ref.watch(playbackEngineProvider).duration ?? Duration.zero,
    );
  }

  /// 写入 `timeline_ops.dart` 纯函数返回的新实例（同 library 私有写缝）。
  ///
  /// 几何 diff、选中维护、激活/临时段清除、历史记录全部由模块执行管线
  /// 负责：模块每次提交前从当前 state 读取旧几何做 diff，本入口只落盘
  /// 新实例，不再持有「最近已知线表」类簿记。
  void _replace(AnnotationTimeline value) {
    state = value;
  }
}

/// 标注时间线注入点；UI 不直接构造模型，所有变更经标注编辑模块。
final annotationTimelineProvider =
    NotifierProvider<AnnotationTimelineModel, AnnotationTimeline>(
      AnnotationTimelineModel.new,
    );

/// 有效标注时间线（单一派生读取）：时间线尚未按视频
/// 时长初始化（[AnnotationTimeline.videoDuration]≤0，state 仍为零时长占位）
/// 时，以引擎整片时长兜底为全片区间——全库唯一兜底实现，控制层 / 轨道带 /
/// 播放页的读取点一律读此处，杜绝兜底口径漂移。时间线已初始化时原样透出。
///
/// 唯一依赖引擎时长的派生，归标注编辑模块库（读本库
/// [annotationTimelineProvider] + 播放内核时长）。
final effectiveAnnotationTimelineProvider = Provider<AnnotationTimeline>((ref) {
  final timeline = ref.watch(annotationTimelineProvider);
  if (timeline.videoDuration > Duration.zero) return timeline;
  return AnnotationTimeline.wholeVideo(
    ref.watch(playbackEngineProvider).duration ?? Duration.zero,
  );
});

/// 当前选中的分段线索引（null = 未选中或索引已越界）：[annotationSelectionProvider]
/// 的派生视图，对 [annotationTimelineProvider] 现势线数做有效性校验——
/// 撤销/重做回放、区间收缩删线后越界/错位选中带外读取为 null。
final selectedSegmentLineIndexProvider = Provider<int?>((ref) {
  final selection = ref.watch(annotationSelectionProvider);
  if (selection is! SegmentLineSelection) return null;
  final lines = ref.watch(annotationTimelineProvider).segmentLines;
  final index = selection.index;
  return index >= 0 && index < lines.length ? index : null;
});

/// 当前选中的首/尾线端标（null = 未选中）：选中上提的带外可读派生
/// 视图，供帧步进与「其它操作即清除」统一消费。
final selectedVideoRangeBoundaryProvider = Provider<VideoRangeBoundary?>((ref) {
  return ref.watch(annotationSelectionProvider).asVideoRangeBoundary;
});

/// 当前选中的半拍线索引（null = 未选中或索引已越界）：带外
/// 可读派生视图，对 [annotationTimelineProvider] 现势线数做有效性校验
///（与 [selectedSegmentLineIndexProvider] 同一口径）。
final selectedHalfBeatLineIndexProvider = Provider<int?>((ref) {
  final selection = ref.watch(annotationSelectionProvider);
  if (selection is! HalfBeatLineSelection) return null;
  final lines = ref.watch(annotationTimelineProvider).halfBeatLines;
  final index = selection.index;
  return index >= 0 && index < lines.length ? index : null;
});

/// 当前选中的局部镜像片段索引（null = 未选中或索引已越界）：带外
/// 可读派生视图，对 [localMirrorFragmentsProvider] 现势片段数做有效性校验
///（删除/撤销后越界读 null，与 [selectedHalfBeatLineIndexProvider] 同一口径）。
final selectedLocalMirrorFragmentIndexProvider = Provider<int?>((ref) {
  final selection = ref.watch(annotationSelectionProvider);
  if (selection is! LocalMirrorFragmentSelection) return null;
  final fragments = ref.watch(localMirrorFragmentsProvider);
  final index = selection.index;
  return index >= 0 && index < fragments.length ? index : null;
});

/// 当前选中的备注片段索引（null = 未选中或索引已越界）：带外可读
/// 派生视图，对 [noteStickersProvider] 现势备注数做有效性校验（删除/撤销
/// 后越界读 null，与 [selectedLocalMirrorFragmentIndexProvider] 同一口径）。
final selectedNoteFragmentIndexProvider = Provider<int?>((ref) {
  final selection = ref.watch(annotationSelectionProvider);
  if (selection is! NoteFragmentSelection) return null;
  final notes = ref.watch(noteStickersProvider);
  final index = selection.index;
  return index >= 0 && index < notes.length ? index : null;
});

/// 学习段熟练度（私密侧；只保会话内存态）。
///
/// store 私有化：熟练度写入统一经标注编辑模块
/// （SetSegmentMastery 命令 / 删线融合 / 区间重排 / 回放），写缝同
/// library 私有；模块级联计算后整体落盘，无逐段 set/插线/重排旁路。
class LearningMasteryModel extends Notifier<Map<int, LearningMastery>> {
  @override
  Map<int, LearningMastery> build() => const {};

  void _reset() => state = const {};

  /// 整体替换（模块级联/回放写入融合或重排后的全量属性）。
  void _replace(Map<int, LearningMastery> value) {
    state = value;
  }
}

/// 学习段熟练度注入点。
final learningMasteryProvider =
    NotifierProvider<LearningMasteryModel, Map<int, LearningMastery>>(
      LearningMasteryModel.new,
    );

/// 学习段「重点」（公开标记侧；随公开文件落盘）。
///
/// store 私有化：重点写入统一经标注编辑模块
/// （ToggleSegmentEmphasis 命令 / 删线融合 / 区间重排 / 回放），写缝同
/// library 私有；模块级联计算后整体落盘，无逐段 toggle/插线/重排旁路。
class LearningEmphasisModel extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void _reset() => state = const {};

  /// 整体替换（模块级联/回放写入融合或重排后的全量属性）。
  void _replace(Set<int> value) {
    state = value;
  }
}

/// 学习段重点注入点。
final learningEmphasisProvider =
    NotifierProvider<LearningEmphasisModel, Set<int>>(
      LearningEmphasisModel.new,
    );

/// 学习段逐段档（公开标记侧 `annotations` 段）。
///
/// store 私有化：写入统一经标注编辑模块（几何变动级联 / 回放 /
/// 恢复装载），写缝同 library 私有；赋值命令落在本写缝上。
class SegmentDensitiesModel extends Notifier<Map<int, double>> {
  @override
  Map<int, double> build() => const {};

  void _reset() => state = const {};

  /// 整体替换（模块级联/回放/恢复装载写入重烘焙后的全表）。
  void _replace(Map<int, double> value) {
    state = value;
  }
}

/// 逐段档注入点（读面；写缝 library 私有）。
final segmentDensitiesProvider =
    NotifierProvider<SegmentDensitiesModel, Map<int, double>>(
      SegmentDensitiesModel.new,
    );

/// 当前选中的学习段代表段序（null = 无选中）：从选中集合派生
///（单一事实源 = [selectedLearningSegmentsProvider]）。
/// 越界段序不参与代表选举（几何变化整体清空，界内性由写路径维持，此处
/// 只兜快照回放窗口）；需要单个代表值的地方（熟练度档位显示与作用对象、
/// 重点写点）取**最低档**所属段——多段档位不一时显示还有一段没跟上的那
/// 一档；并列取最小段序。
final selectedLearningSegmentRepresentativeProvider = Provider<int?>((ref) {
  final count = deriveLearningSegments(ref.watch(annotationTimelineProvider))
      .length;
  final selected =
      ref
          .watch(selectedLearningSegmentsProvider)
          .where((order) => order >= 0 && order < count)
          .toList()
        ..sort();
  if (selected.isEmpty) return null;
  final mastery = ref.watch(learningMasteryProvider);
  var representative = selected.first;
  var representativeRank = learningSegmentMastery(
    mastery,
    representative,
  ).index;
  for (final order in selected.skip(1)) {
    final rank = learningSegmentMastery(mastery, order).index;
    if (rank < representativeRank) {
      representative = order;
      representativeRank = rank;
    }
  }
  return representative;
});

/// 局部镜像片段列表（独立值道）：整视频的区间列表、按 startMs 升序
/// 且两两不重叠（[isSortedAndNonOverlapping]），**独立值道**——不参与学习
/// 段派生、无段序键、与分段线/半拍线/首尾线几何无关，绝不随无关几何操作被
/// 丢/改。承载形态 = 独立 store 值道：自身 store/Notifier +
/// 快照随 markers `annotations` 段携带（[AnnotationEditSnapshot.annotations]）
/// + 段级 diff 整段入队（foldSectionDiff/AnnotationSectionDiff）+ 独立恢复
/// 水合（restore 装载）。
///
/// store 私有化同纪律：本模型是**读取源**，唯一写入口
/// 是同库的 [AnnotationEditor]（写缝同 library 私有——打开恢复装载经
/// `_replace`/全复位 `_reset` 写，几何 verb 族从 `_plan` 写）。
class LocalMirrorFragmentsModel extends Notifier<List<LocalMirrorFragment>> {
  @override
  List<LocalMirrorFragment> build() => const [];

  /// 整体复位（换视频兜底）。
  void _reset() => state = const [];

  /// 整体替换（打开恢复装载 / 几何 verb 提交写全量终值）。
  void _replace(List<LocalMirrorFragment> value) {
    state = List.unmodifiable(value);
  }
}

/// 局部镜像片段注入点（读取源；模块内 _capture 读作快照 lane）。
final localMirrorFragmentsProvider =
    NotifierProvider<LocalMirrorFragmentsModel, List<LocalMirrorFragment>>(
      LocalMirrorFragmentsModel.new,
    );

/// 备注贴纸列表（独立值道）：markers 顶层 `notes` 段的会话内现值、
/// 按时间窗起点升序且两两不重叠（不变量由编辑侧逐 verb 维持）。承载形态
/// 照既有片段 store（写法照 [LocalMirrorFragmentsModel]）：自身
/// store/Notifier + 快照随备注 lane 携带（[AnnotationEditSnapshot.notes]）
/// + 段级 diff 备注臂整段入队 + 恢复装载就位。
///
/// store 私有化同纪律：本模型是**读取源**，唯一写入口是同库的
/// [AnnotationEditor]——替换 / 复位 / 恢复三个私有入口，模块外无法写入
///（备注 verb 族经 `_replace` 从模块管线写）。
class NoteStickersModel extends Notifier<List<NoteSticker>> {
  @override
  List<NoteSticker> build() => const [];

  /// 整体复位（换视频兜底，随 [AnnotationEditor.resetForVideo]）。
  void _reset() => state = const [];

  /// 整体替换（备注 verb 提交写全量终值）。
  void _replace(List<NoteSticker> value) {
    state = List.unmodifiable(value);
  }

  /// 打开恢复整组写回（装载语义：非撤销、非保存；盘上现值即来源）。
  void _restore(List<NoteSticker> value) => _replace(value);
}

/// 备注贴纸注入点（读取源；模块内 _capture 读作快照 lane）。
final noteStickersProvider =
    NotifierProvider<NoteStickersModel, List<NoteSticker>>(
      NoteStickersModel.new,
    );

/// 局部镜像总开关（视频级视图开关值道）：markers `meta` 段
/// `localMirrorEnabled` 的会话内现值（未写入/缺键兜底 `true`——合成输入
/// 取 `true` 时有效镜像与既有行为逐位一致）。它是**镜像控制器的投影**：
/// 读取与落盘都归镜像控制器（打开时按 markers 真值 / index 过渡值 /
/// 首建初值三条路径读出、切换即双写 markers + index），每次取值经写缝
/// [replace] 推入本值道供合成与顶栏槽位视觉消费；不入撤销/重做史、不受
/// 锁定分段门禁（视图开关，与全局镜像同类）。
class LocalMirrorEnabledModel extends Notifier<bool> {
  @override
  bool build() => true;

  /// 打开时的复位 / 控制器写缝。
  void replace(bool value) => state = value;
}

/// 局部镜像总开关注入点（渲染翻转门与轨道块视觉的合成输入）。
final localMirrorEnabledProvider =
    NotifierProvider<LocalMirrorEnabledModel, bool>(
      LocalMirrorEnabledModel.new,
    );

/// 当前选中学习段的合并循环范围；null = 无选中。
final selectedLearningSegmentRangeProvider = Provider<LearningSegmentRange?>((
  ref,
) {
  return selectedLearningSegmentRange(
    ref.watch(annotationTimelineProvider),
    ref.watch(selectedLearningSegmentsProvider),
  );
});

/// 临时衔接段：点击分段线激活的会话态临时学习段。
///
/// 不落盘（重启等价为空——本 provider 无任何持久化写入）、不进熟练度/
/// 重点、不参与步进「选中段」候选（[AnnotationSelectionDomain] 不含
/// 它）；与真实学习段选中互斥（单一循环范围事实，见
/// [activeLoopRangeProvider]）。时间线几何变化时**不** build-watch 隐式
/// 重建为空——清除仅由标注编辑模块在几何 diff 命中时显式触发（触发线的
/// 索引在新几何下无意义，不做重映射；幂等、会话内只清首次），换视频兜底
/// 走 [AnnotationEditor.resetForVideo]。
class TransitionSegmentModel extends Notifier<TransitionSegment?> {
  @override
  TransitionSegment? build() => null;

  /// 触发区内点击分段线：同线取消、异线替换（范围解析见
  /// [resolveTransitionSegment]，无效线索引/过窄区间不激活）。
  ///
  /// 互斥：激活临时段先清空真实学习段激活。
  void _toggle(AnnotationTimeline timeline, int lineIndex) {
    final current = state;
    if (current != null && current.lineIndex == lineIndex) {
      state = null;
      return;
    }
    final segment = resolveTransitionSegment(
      timeline: timeline,
      lineIndex: lineIndex,
      // 起点取整经相位源求值（网格 + 锚点
      // 同源），设锚后起点落重定相后的八拍点。
      phase: ref.read(beatPhaseProvider),
    );
    if (segment == null) return;
    ref.read(annotationSelectionDomainProvider).clearLearningSegments();
    // 互斥：激活临时段同时清除片段激活（激活源保持单值）。
    ref.read(practiceClipActivationProvider.notifier)._clear();
    state = segment;
  }

  /// 取消临时段（再点同线路径在 [_toggle] 内；此入口供宿主显式清除）。
  void _clear() {
    state = null;
  }

  /// 任意 seek 目标越出临时段范围时清除（与真实段激活的
  /// [AnnotationSelectionDomain.clearLearningSegmentsIfOutside] 同一规则：避免区间
  /// 循环层把进度拽回段首）。
  void clearIfOutside(AnnotationTimeline timeline, Duration position) {
    if (timeline.videoDuration <= Duration.zero) return;
    final segment = state;
    if (segment != null &&
        (position < segment.start || position > segment.end)) {
      state = null;
    }
  }
}

/// 临时衔接段注入点；轨道带触发区与播放联动共同消费。
final transitionSegmentProvider =
    NotifierProvider<TransitionSegmentModel, TransitionSegment?>(
      TransitionSegmentModel.new,
    );

/// 激活练习片段：点选练习片段即
/// 激活 = 片段源区间 AB 循环回看；与学习段/临时衔接段激活互斥（激活源
/// 保持单值，纯件 [applyCompareActivation] 的接线——互斥各写在
/// 双方写点、写点复用既有清激活路径）。循环区间输出经
/// [activeLoopRangeProvider] 保持既有单值 seam 形状不变。
///
/// 跨会话恢复走 `session` 段扩键 `activePracticeClipId`（与学习段选中同
/// 段同口径）：恢复只就位激活与循环作用域、不自动跳转、不自动播放
/// （[lastWriteFromRestore] 驱动播放页循环接线的 seek 抑制，同
/// 款）；恢复 id 不在片段列表时不激活。
class PracticeClipActivationModel extends Notifier<PracticeClipLoop?> {
  @override
  PracticeClipLoop? build() => null;

  /// 当前激活是否来自打开恢复写回（与学习段同款语义）：播放页的循环接线
  /// 据此抑制「跳片段首」seek；任何用户/会话路径的写回置回 false。
  bool get lastWriteFromRestore => _lastWriteFromRestore;
  bool _lastWriteFromRestore = false;

  /// 点选练习片段：激活（清除学习段/临时衔接段激活）；再点同片段取消。
  void toggle(PracticeClip clip) {
    if (state?.clipId == clip.id) {
      _clear();
      return;
    }
    _lastWriteFromRestore = false;
    ref.read(annotationSelectionDomainProvider).clearLearningSegments();
    ref.read(transitionSegmentProvider.notifier)._clear();
    state = PracticeClipLoop(clipId: clip.id);
    _persist();
  }

  /// 进度拖出片段范围清激活（与学习段同规则：端点仍属范围；判定收口
  /// 在纯件 [clipActivationAfterSeek]）。片段引用失效（列表已无
  /// 此 id）视同越界清除。
  void clearIfOutside(Duration position) {
    final active = state;
    if (active == null) return;
    final clip = practiceClipById(
      ref.read(practiceClipsProvider),
      active.clipId,
    );
    final kept = clip == null
        ? null
        : clipActivationAfterSeek(
            active: active,
            positionMs: position.inMilliseconds,
            clipRange: IntervalSpan(
              startMs: clip.sourceStartMs,
              endMs: clip.sourceEndMs,
            ),
          );
    if (kept == null) _clear();
  }

  /// 打开恢复整组写回：就位激活与循环作用域，不触发跳转/播放、不入队
  /// （盘上现值即来源）。id 不在片段列表（片段已删）时不激活。
  ///
  /// 恢复静默标志只在**真的写回激活**时置真——写回为空
  /// （`clipId == null` 或 id 不在列表）不置，否则空写回会污染本源标志，
  /// 连坐另一激活源的 seek 抑制。
  void restore(String? clipId, {required List<PracticeClip> clips}) {
    final writes = clipId != null && clips.any((c) => c.id == clipId);
    _lastWriteFromRestore = writes;
    state = writes ? PracticeClipLoop(clipId: clipId) : null;
  }

  /// 非保存清（换视频复位）：保存缝可能已指向另一支视频，不入队。
  void reset() {
    _lastWriteFromRestore = false;
    state = null;
  }

  /// 退出回看：清激活并落盘（无回看时幂等 no-op）。画面常驻出口件与编辑
  /// 态回看浮条共用的退出写入口对本方法的调用点。
  void exitReview() => _clear();

  void _clear() {
    if (state == null) return;
    _lastWriteFromRestore = false;
    state = null;
    _persist();
  }

  /// `session` 段落盘写入点：绝对终值（熟练度现值 + 激活段现值 + 片段
  /// 激活现值——片段激活取自身 state，不经本 provider 的 ref 自读），
  /// 与学习段激活写入点同段同口径互不覆盖；未接编排器零行为。
  ///
  /// 装载组员方案时不落盘：`session` 段的熟练度与
  /// 激活学习段此刻的现值都来自组员方案，写进去会把队友那份档位写成我的
  /// 进度、并清掉我的激活学习段。片段回看本身照常，只是这次查看不动我的盘。
  void _persist() {
    if (ref.read(annotationMemberSchemeReadonlyProvider)) return;
    ref
        .read(annotationSaveSinkProvider)
        ?.save(
          AnnotationSectionDiff(
            session: _currentSessionValue(
              ref,
              activePracticeClipId: state?.clipId,
            ),
          ),
        );
  }
}

/// `session` 段的绝对终值：熟练度现值 + 升序激活段现值 + 片段激活现值。
///
/// **必须在同步上下文内调用**：值取自各 provider 的当前态，异步间隙之后可能
/// 已变。片段激活由调用方给绝对终值（激活模型自身传 `state?.clipId`，免得
/// 自读自身 provider）；落盘值是激活的绝对终值，片段引用悬空时也照原样保留。
LocalSessionValue _currentSessionValue(
  Ref ref, {
  required String? activePracticeClipId,
}) => LocalSessionValue(
  mastery: ref.read(learningMasteryProvider),
  activatedSegments: [...ref.read(selectedLearningSegmentsProvider)]..sort(),
  activePracticeClipId: activePracticeClipId,
);

/// 激活练习片段注入点；轨道带片段块点选与播放页循环/相机/回放接线共同消费。
final practiceClipActivationProvider =
    NotifierProvider<PracticeClipActivationModel, PracticeClipLoop?>(
      PracticeClipActivationModel.new,
    );

/// 「练习半区此刻显示的是相机实时预览还是练习片段回放」这一判断的**唯一
/// 派生读**：播放页渲染点与切路接线、轨道带激活
/// 描边、标注编辑的几何清除守卫等消费方全部读本 provider，不各自读一次
/// [practiceClipActivationProvider] 谓词。
///
/// 取值按**解析出的播放源（含引用有效性）**判定：
/// 激活为空，或激活片段按 id 解析不到（已不在轨道上）⇒ 相机实时预览（解析
/// 不到即停播、练习半区回落实时预览）；激活片段在轨 ⇒ 回放件在屏。写后无
/// 悬空激活（写缝不变量清激活），本判定兜的是恢复窗口等过渡态。
///
/// 值类型取画面方向库的 [SurfaceFace]（在屏哪一路 = 该表里的面，同一事实只有
/// 一处声明）。练习半区只会答两枚练习面。
final practiceOnscreenFaceProvider = Provider<SurfaceFace>((ref) {
  final loop = ref.watch(practiceClipActivationProvider);
  if (loop == null) return SurfaceFace.cameraPreview;
  final clip = practiceClipById(ref.watch(practiceClipsProvider), loop.clipId);
  return clip != null ? SurfaceFace.clipPlayback : SurfaceFace.cameraPreview;
});

/// clipId → 片段引用的查找（唯一形状；循环范围派生、越界清除与播放页
/// 接线共用，找不到 = 引用失效）。
PracticeClip? practiceClipById(List<PracticeClip> clips, String clipId) {
  for (final clip in clips) {
    if (clip.id == clipId) return clip;
  }
  return null;
}

/// 当前生效的「激活源」判别：片段 > 临时衔接段 > 学习段——
/// 与 [activeLoopRangeProvider] 同一优先级的**唯一手写点**；消费方（循环
/// 范围派生、播放页恢复静默标志按源选读）都经本 provider，优先级变更
/// 只改此处。三者互斥（激活任一清除其余），不会同时非空。
enum ActiveLoopSource {
  practiceClip,

  transitionSegment,

  /// 真实学习段激活（合并范围）。
  learningSegments,
}

final activeLoopSourceProvider = Provider<ActiveLoopSource>((ref) {
  if (ref.watch(practiceClipActivationProvider) != null) {
    return ActiveLoopSource.practiceClip;
  }
  if (ref.watch(transitionSegmentProvider) != null) {
    return ActiveLoopSource.transitionSegment;
  }
  return ActiveLoopSource.learningSegments;
});

/// 当前激活写是否「静默就位」：**当前生效的激活源**的最近一次写不触发
/// 跳段首/片段首 seek——打开恢复写回与长按拖动圈选的拖动帧写
/// 都属静默写。静默标志是每个激活源自己的写回属性，不是会话级
/// 开关：先经 [activeLoopSourceProvider] 问此刻生效的激活源是谁（同一
/// 优先级判别），再读它的标志；一个源的标志不得连坐另一个源的 seek，
/// 无激活源（learningSegments 集为空）时标志本就为假，不产生可观察差异。
bool restoreQuietLoopWrite(WidgetRef ref) {
  switch (ref.read(activeLoopSourceProvider)) {
    case ActiveLoopSource.practiceClip:
      return ref
          .read(practiceClipActivationProvider.notifier)
          .lastWriteFromRestore;
    case ActiveLoopSource.transitionSegment:
      // 临时衔接段不落盘、无恢复写回：激活必来自会话内点击。
      return false;
    case ActiveLoopSource.learningSegments:
      return ref
          .read(selectedLearningSegmentsProvider.notifier)
          .lastWriteSilent;
  }
}

/// 当前生效的「单一循环范围」（含片段激活）：片段激活优先，
/// 否则临时衔接段，否则真实学习段合并范围；三者互斥（激活任一清除其余），
/// 不会同时非空。播放页的区间循环接线（enableLoop + 队首 seek）只消费本
/// provider——片段循环的区间输出保持既有单值 seam 的形状不变；片段引用
/// 失效（列表已无此 id）时无循环范围。
final activeLoopRangeProvider = Provider<LearningSegmentRange?>((ref) {
  switch (ref.watch(activeLoopSourceProvider)) {
    case ActiveLoopSource.practiceClip:
      final clipLoop = ref.watch(practiceClipActivationProvider)!;
      final clip = practiceClipById(
        ref.watch(practiceClipsProvider),
        clipLoop.clipId,
      );
      if (clip == null) return null;
      return LearningSegmentRange(
        start: Duration(milliseconds: clip.sourceStartMs),
        end: Duration(milliseconds: clip.sourceEndMs),
      );
    case ActiveLoopSource.transitionSegment:
      final transition = ref.watch(transitionSegmentProvider)!;
      return LearningSegmentRange(start: transition.start, end: transition.end);
    case ActiveLoopSource.learningSegments:
      return ref.watch(selectedLearningSegmentRangeProvider);
  }
});

/// 任意 seek 入口共用的「越出即取消激活」判定（真实段 + 临时段
/// + 片段激活，单一事实源）：目标越出 [activeLoopRangeProvider] 生效
/// 范围时取消对应激活，避免区间循环层把进度拽回段首。player_page 的手势
/// seek 与 track_band 的预览条拖动共用本入口。播放侧例外（模块外规则）：
/// 保持公开。
void clearLoopActivationsIfOutside(
  T Function<T>(ProviderListenable<T>) read,
  AnnotationTimeline timeline,
  Duration position,
) {
  read(annotationSelectionDomainProvider)
      .clearLearningSegmentsIfOutside(position);
  read(transitionSegmentProvider.notifier).clearIfOutside(timeline, position);
  read(practiceClipActivationProvider.notifier).clearIfOutside(position);
}

/// 一次标注编辑命令前后的可撤销状态快照（按段持有）：公开标记
/// `corrections` / `annotations` / `notes`
/// 三段 + 本地 `session` 一段，段值为绝对终值。`videoDuration` 不属于任何段、不在
/// 快照内——它结构性不参与净变化判定。选中/激活/临时段等派生或会话
/// UI 态不入快照——撤销重放几何后，激活/临时段由标注编辑模块按几何
/// diff 规则显式清除。
class AnnotationEditSnapshot {
  const AnnotationEditSnapshot({
    required this.corrections,
    required this.annotations,
    required this.session,
    this.notes = const [],
    required this.practiceClips,
  });

  /// markers `corrections` 段（平移量 + 八拍锚点；撤销/重做与线位置同一
  /// 步回退）。
  final MarkerCorrectionsValue corrections;

  /// markers `annotations` 段（首尾 + 分段线 + 半拍线 + 重点 + 局部镜像
  /// 片段）。
  final MarkerAnnotationsValue annotations;

  /// local `session` 段（熟练度）。
  final LocalSessionValue session;

  /// markers `notes` 段（备注贴纸列表，独立 lane）。
  final List<NoteSticker> notes;

  /// 练习片段列表（独立 lane；编辑快照内的绝对终值，撤销/重做
  /// 回放恢复引用范围；持久化仍归随舞 prefs 编排，不经标注保存臂）。
  final List<PracticeClip> practiceClips;

  @override
  bool operator ==(Object other) =>
      other is AnnotationEditSnapshot &&
      other.corrections == corrections &&
      other.annotations == annotations &&
      other.session == session &&
      _listEquals(other.notes, notes) &&
      _listEquals(other.practiceClips, practiceClips);

  @override
  int get hashCode => Object.hash(
    corrections,
    annotations,
    session,
    Object.hashAll(notes),
    Object.hashAll(practiceClips),
  );
}

/// 值对象列表相等（逐位；模块库依赖约束禁 flutter/foundation，
/// 与集合相等手写判定同一口径）。
bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 标注编辑撤销/重做：会话内命令历史 ≤50 步，覆盖时间线几何与
/// 属性操作（分段线新建/拖动/flag/删除、首尾设置与拖动、熟练度/重点）。
///
/// 命令以 [AnnotationEditSnapshot] 前后快照对记录（纯历史见
/// `annotation/edit_history.dart`）；撤销/重做**经既有模型操作重放**——
/// 快照写回 [AnnotationTimelineModel._replace]、
/// [LearningMasteryModel._replace]、[LearningEmphasisModel._replace]，激活/
/// 临时段的清除由标注编辑模块按同一几何 diff 规则在回放后显式触发
/// （不入史）。播放位置/倍速/镜像/吸附开关不触碰上述三个模型，天然
/// 不入史。
///
/// 拖动类编辑（分段线/首尾线）每帧写入模型：整次手势由标注编辑模块
/// 以事务起点/收口快照对合并为单步命令（begin 单捕事务起点、end 经模块
/// 收口 seam 提交）；单发编辑（按钮）经模块收口 seam 显式记录。
/// 换视频/重新打开调 clear。
/// store 私有化：本模型是历史的**读取源 + 模块
/// 内部写缝**，变更方法全部 library 私有，调用方 undo/redo 一律走模块。
/// 历史只存取/回放模块传入的显式快照对（入史唯一入口 = [_record]，由模块
/// 收口 seam 下发），无自我捕获、无 pending 簿记；悬挂态由模块唯一会话态
/// 表达，undo/redo 前由模块收口。
class AnnotationEditHistoryModel
    extends Notifier<EditHistory<AnnotationEditSnapshot>> {
  @override
  EditHistory<AnnotationEditSnapshot> build() => const EditHistory.empty();

  /// 模块内显式记录入口：接收标注编辑模块收口 seam 下发的
  /// 显式 (before, after) 快照对。收口 seam 已按段判空，no-op 不到达本
  /// 入口（`EditHistory.record` 不重复防御 before==after）。
  void _record(AnnotationEditSnapshot before, AnnotationEditSnapshot after) {
    state = state.record(before, after);
  }

  /// 撤销一步：回放命令的 before 快照；练习片段 lane 按 id 作用域回放
  /// （历史缝交出快照对，见 [EditHistory.undoEntry]；无历史时 no-op）。
  void _undo() {
    final (next, entry) = state.undoEntry();
    state = next;
    if (entry != null) {
      _replay(entry.before);
      _replayClipLane(
        before: entry.before.practiceClips,
        after: entry.after.practiceClips,
      );
    }
  }

  /// 重做一步：语义同撤销（快照对方向对调——逐 id 合并以当前表为目标、
  /// 按条目另一侧回写）。
  void _redo() {
    final (next, entry) = state.redoEntry();
    state = next;
    if (entry != null) {
      _replay(entry.after);
      // 方向对调：合并以当前表为目标，`before` 侧 = 回放目标侧（after）。
      _replayClipLane(
        before: entry.after.practiceClips,
        after: entry.before.practiceClips,
      );
    }
  }

  /// 清空历史（换视频/重新打开）。
  void _clear() {
    state = const EditHistory.empty();
  }

  void _replay(AnnotationEditSnapshot snapshot) {
    // annotations 段值重建时间线（`videoDuration` 不属于任何段，取当前
    // 时间线的现值——同视频会话内恒定，换视频前历史已被清空）。
    final a = snapshot.annotations;
    ref
        .read(annotationTimelineProvider.notifier)
        ._replace(
          AnnotationTimeline.normalized(
            videoDuration: ref.read(annotationTimelineProvider).videoDuration,
            rangeStart: a.rangeStart,
            rangeEnd: a.rangeEnd,
            segmentLines: a.segmentLines,
            halfBeatLines: a.halfBeatLines,
          ),
        );
    ref
        .read(learningMasteryProvider.notifier)
        ._replace(snapshot.session.mastery);
    ref.read(learningEmphasisProvider.notifier)._replace(a.emphasizedSegments);
    // 逐段档随 annotations 段回放（撤销/重做
    // 与几何级联同一步回退/重放）。
    ref.read(segmentDensitiesProvider.notifier)._replace(a.segmentDensities);
    // corrections 段（平移量 + 倍频 + 锚点）与线位置同一步回退/重放（与
    // 节拍对齐/倍频/落锚命令共用同一写缝）。
    writeAppliedBeatShift(ref, snapshot.corrections.shiftSeconds);
    writeAppliedBeatDensity(ref, snapshot.corrections.density);
    writeEightBeatAnchors(ref, snapshot.corrections.eightBeatAnchors);
    // 局部镜像片段随 annotations 段回放（撤销/重做恢复片段态）。
    ref
        .read(localMirrorFragmentsProvider.notifier)
        ._replace(a.localMirrorFragments);
    // 备注随备注 lane 回放（撤销/重做恢复备注态）。
    ref.read(noteStickersProvider.notifier)._replace(snapshot.notes);
  }

  /// 练习片段 lane 的按 id 作用域回放：以
  /// 历史条目快照对为变更、当前表为目标做逐 id 三方合并（纯件）——
  /// 仅回写这次编辑碰过的 id，被外部写过的 id 跳过（录制入轨 / 素材连带
  /// 删除既不进史、也不被撤销/重做影响），未碰过的 id 原样保留。全表无
  /// 净变化时不写 lane（不触发落盘编排）。
  void _replayClipLane({
    required List<PracticeClip> before,
    required List<PracticeClip> after,
  }) {
    final current = ref.read(practiceClipsProvider);
    // 复活分支把复活的片段追加在表尾：写前恢复表恒升序（确定性并列
    // 次序按 end、id；不裁剪——重叠裁剪归库内写缝）。
    final merged =
        replayClipTableBySnapshotPair(
          before: before,
          after: after,
          current: current,
        ).clips..sort((a, b) {
          final byStart = a.sourceStartMs.compareTo(b.sourceStartMs);
          if (byStart != 0) return byStart;
          final byEnd = a.sourceEndMs.compareTo(b.sourceEndMs);
          return byEnd != 0 ? byEnd : a.id.compareTo(b.id);
        });
    var changed = merged.length != current.length;
    for (var i = 0; i < merged.length && !changed; i++) {
      changed = merged[i] != current[i];
    }
    if (changed) ref.read(practiceClipsProvider.notifier)._replace(merged);
  }
}

/// 标注编辑历史注入点；顶栏撤销/重做按钮与各编辑入口共用。
final annotationEditHistoryProvider =
    NotifierProvider<
      AnnotationEditHistoryModel,
      EditHistory<AnnotationEditSnapshot>
    >(AnnotationEditHistoryModel.new);
