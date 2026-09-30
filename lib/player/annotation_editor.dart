/// 标注编辑模块库（领域词「标注编辑」，见 `lib/annotation/CONTEXT.md`）：标注（分段线/
/// 首尾边界/flag/熟练度/重点）的**唯一写入口**深模块。
///
/// widget 只做意图陈述（调用本模块方法），一致性收尾（段序键属性级联、
/// 激活/临时段几何清除、撤销/重做记录）全部在模块内完成；现有
/// 粒状 Notifier 保留为读取源，其变更方法与本模块同 library 私有
/// （store 私有化；写读面整体收进本独立
/// 库，写缝私有由 library 边界保证而非 hub 内纪律）——本模块是唯一写路径。
///
/// 写路径与例外归属：唯一可入史写路径 = submit 命令族；非史非存恢复装载
/// = restoreDocument；恢复前清 = clearForVideoRestore；播放侧例外 =
/// clearLoopActivationsIfOutside（seek 越出清除，模块外的规则，
/// 归手势会话 + seek 提交器簇；保持公开、不封口）。
///
/// 提交点归属：模块收口 seam `_commit` 是**单一提交
/// 点**，仅两个消费者——历史模型（显式快照对入史）与保存编排（段级
/// diff 入队），净变化判定共用折叠纯函数 `foldSectionDiff`（全库唯一权威
/// 谓词）；undo/redo 回放也经同一 seam（`recordHistory: false` 不记史）。
/// before 快照唯一 owner = 本模块：单发 submit 在提交入口捕获一次、拖动
/// 会话 begin 捕获一次事务起点（`_transactionStart`）；历史模型不自捕、
/// 无 pending 簿记。快照按段持有（corrections / annotations / notes /
/// session），`videoDuration` 不属于任何段、结构性不参与净变化
/// 判定。
///
/// 已登记漂移窗口（本模块只登记不实施）：① 异步恢复窗口——
/// `VideoOpenRestorer` 异步恢复写回与进行中拖动会话无守卫；② sink null
/// 窗口——videoId 未定期间的编辑提交不入盘、历史照记（保存编排既有语义）。
///
/// 依赖方向（单向、无环）：本库只依赖 annotation 纯域、persistence 类型、
/// beat_track_state 小库与共享内核，零 import hub。
///
/// 行为契约（不变量）：
///
///   - **编辑一致性**：一次 submit 要么全部生效（几何 + 属性级联 + 域侧
///     选中重映射与清除 + 历史），要么全部不生效；失败以异常报出，不吞错、
///     不转错、不半写。
///   - **清除规则**：仅几何变化（rangeStart/rangeEnd 或分段线位置集合
///     变化，忽略 flag/属性）才清除激活学习段与临时衔接段；flag 切换与
///     纯属性编辑不清（全库唯一）。清除幂等、不入史。
///   - **历史语义**：复用 EditHistory 纯值（≤50 淘汰、no-op 不入史、新
///     记录清重做分支）；一次拖动会话以首尾快照比较单步入史；undo/redo
///     内部先清选中，回放按同一几何 diff 规则清除激活/临时段，回放效果
///     经同一收口 seam 入队保存（不入史）；无历史/无可重做 no-op。
///   - **错误契约**：经落点解析的交互命令（分段线/
///     半拍线的加线/移动、首尾线调整）提交 = 模块内吸附 + 合法域检查——
///     分段线/半拍线触界或无合法落点 = EditNoop（静默、不入史不入盘），
///     首尾线覆盖外/异常态自由落点，均不再抛 ArgumentError；ArgumentError
///     只对不经落点解析的路径保留（timeline_ops 纯函数契约不变）。非法
///     索引 RangeError、越邻/触界/同值/同位 no-op、首尾归一化钳制照旧
///     （与 timeline_ops 纯函数同源）。
///   - **落点解析纪律**：交互命令提交 = 模块内落点
///     解析 + 合法域检查，widget 不预吸附。逐 verb 吸附策略（对齐落点
///     词条）：分段线加线/移动恒吸**八拍点**（经 core 单一相位源，仅就绪
///     网格派生；占位/异常无吸附依据、请求位置直通——生产入口由就绪置灰
///     门挡住）；半拍线加线/移动/步进恒吸**半拍格点**（占位均匀网格照常
///     派生、异常态吸附停用直通）；首尾线调整覆盖区内吸**真实拍点**、
///     覆盖外/异常态自由。合法域 = 时间线开区间（首尾线例外：端标本体即
///     边界，合法域由可拖范围与归一化钳制收口）——触界或无合法落点 =
///     EditNoop 静默（见错误契约）。**不经落点解析的豁免路径** = 撤销/
///     重做回放、恢复装载、节拍对齐整体平移、自动分段切割线、恢复前清
///     （历史与装载语义不被吸附改写；步进/方向换算等读取侧纯函数留在
///     纯域，模块对到达的请求做落点解析，幂等）。
///   - **八拍锚点**：锚点 verb = [AddEightBeatAnchor]
///     / [RemoveEightBeatAnchor] / [ClearEightBeatAnchors] ——加/删提交时模块内
///     落点解析（[resolveDownbeatSnap] 最近**强拍**，非强拍不落点；非就绪网格/
///     无强拍 = EditNoop），集合升序去重写定公开 beat 段锚点字段；一次提交 =
///     一次标注编辑（单步可撤销、净变化折叠、受锁门禁、**不改任何线的几何**
///     故不触发激活/临时段清除）。相位唯一事实源 = core 相位模块的
///     [BeatPhase]（网格 + 锚点求值，无锚点 = 自动相位口径）；
///     本模块内落点消费它（分段线吸附跟锚点重定相）。
///   - **锁门禁**：锁定分段开启时**分段结构族** verb（分段线
///     的创建/移动/删除、首尾边界调整、自动分段、清空分段、flag 切换）在
///     交互写入口被拒——返回 `EditLocked`、编辑不成立、统一触发一次
///     「已锁定分段」提示。节拍域（半拍线、节拍对齐、节拍倍频、八拍锚点）、
///     画面/各片段轨（备注贴纸与备注片段、局部镜像片段）与练习片段截取/
///     删除都不受本锁（锁只护分段结构）；豁免 = 重点/熟练度
///     切换、激活/临时段会话组、撤销/重做、恢复装载、
///     恢复前清、复位。门禁次序 = 锁 →（分段等入口的）就绪网格 → 落点。
///   - **门禁第二原因：对比态只读**：
///     逐 verb 受哪些原因门禁收成 `verbGateReasons`（一个门禁 N 个原因，
///     不建第二张平行动词表）；对比态（[annotationCompareReadonlyProvider]）
///     下同一批几何 verb 静默被拒——不弹提示（对比态不是「锁」）、不写、
///     不入史、不入盘；拖动手势起手前的静默不参与归 widget（读同一
///     provider）。豁免与本库既有豁免一致（熟练度/重点/备注文本与
///     备注锁开关照常；flag 切换受锁）。
///   - **内容锁门禁**：备注自己的内容锁只护几何——几何类备注
///     命令（整体移 / 端点拖 / 贴纸几何）在目标备注已锁时被拒，同样返回
///     `EditLocked` 但触发独立的「备注已锁定」提示（两套门禁并存、各弹
///     各的提示）；文本 / 样式 / 锁定开关豁免。不新增第 5 个门（可用性
///     判定表不动）。
///   - **互斥**：激活学习段与临时衔接段严格互斥，跨库承载：域上报、本
///     模块清另两源（不入史）。
///   - **拖动会话协议**（三不变量的唯一权威处；各具名工厂与会话类
///     [AnnotationDragSession] 的文档都指向这里）：
///     一次拖动 = 一个事务 = 一条历史 = 一次保存。① **会话唯一性（令牌）**：
///     同一时刻只有一个进行中会话，会话对象持有生成时的令牌，逐帧与收口
///     先比对——被顶替或已收口的陈旧会话对象结构性失效（逐帧返回空、
///     收口为空操作）；② **逐帧并入事务**：会话中的提交不各自入史、不
///     各自入队（收口 seam 的会话分支早退）；③ **收口一次净变化**：收口
///     幂等，把事务起点与终态折成一次净变化判定，非空才记一条历史、入队
///     一次保存。**写后真实落点的返回形态逐族保留**：三族直接读模型的
///     位置值（微秒精度），镜像两族把整数毫秒重新包成时长——口径差异收
///     在各自落点适配器的一行里，刻意不统一。**与文档段化 effort 的
///     边界**：不碰提交链的粒度与净变化判定的实现；唯一接触点 = 收口
///     函数第一句读的「会话进行中」谓词（[_sessionOpen]）。
///   - **文本命令载荷契约**：[SetNoteText] 的载荷 = **纯文本
///     本身**。本模块**不解析点名、不读名册、不存引用**——点名只存在于
///     文本里（`@名字`），渲染时按当前名册解析并着色（点名语法解析归
///     `note_mention.dart` 纯件 + 渲染侧）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;

import '../annotation/annotation_timeline.dart';
import '../annotation/auto_segment.dart';
import '../annotation/compare_materials.dart'
    show PracticeClip, snapTrimOffsetMs;
import '../annotation/edit_history.dart';
import '../annotation/downbeat_snap.dart' show resolveDownbeatLanding;
import '../annotation/half_beat_snap.dart' show resolveHalfBeatSnap;
import '../annotation/learning_segment_attributes.dart';
import '../annotation/interval_fragment_row.dart'
    show IntervalEdge, IntervalSpan, spanInsertionIndex;
import '../annotation/practice_clip_table_algebra.dart'
    show normalizePracticeClipTable;
import '../annotation/learning_segments.dart';
import '../annotation/local_mirror.dart';
import '../annotation/practice_clip_table_algebra.dart'
    show replayClipTableBySnapshotPair;
import '../annotation/compare_materials.dart'
    show
        MaterialRecord,
        PracticeClip,
        PracticeClipLoop,
        clipActivationAfterSeek,
        pruneClipsOverlappedBy;
import '../annotation/note_sticker.dart';
import '../annotation/segment_selection.dart';
import '../annotation/snap.dart'
    show nearestCandidate, snapRangeBoundary;
import '../annotation/timeline_ops.dart' as timeline_ops;
import '../annotation/transition_segment.dart';
import '../beat_track_state/beat_track_state.dart';
import '../core/beat_grid.dart'
    show BeatGrid, BeatGridReads, secondsFallbackEightBeat;
import '../core/document_beat_grid.dart';
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../persistence/annotation_save_orchestrator.dart';
import '../persistence/annotation_sections.dart';
// BeatGrid 文档类与 core/beat_grid.dart 的网格 seam 接口同名，别名引入。
import '../persistence/marker_document.dart' as marker_doc show BeatGrid;
import '../player_session/player_session.dart' show playerSessionProvider;
import '../surface_direction/surface_direction.dart' show SurfaceFace;
import 'annotation_edit.dart';
// 锁定分段/内容锁两把锁的提示触发只报身份：
// 提示的寿命归提示模块，本库不持有任何触发机制。
import 'notice.dart' show NoticeId, noticeTriggerProvider;
// 选中域库：不入史的选中态本体与其
// 写面。本库 import 它以便经域对象读写选中 provider；消费方直连域对象，
// 两族符号不从本库出口。
import 'annotation_selection.dart';

part 'annotation_stores.dart';
part 'annotation_lock_state.dart';
part 'practice_clips.dart';

/// 标注编辑模块注入点；所有编辑入口经 [AnnotationEditor] 提交意图。
final annotationEditorProvider = Provider<AnnotationEditor>((ref) {
  return AnnotationEditor(ref);
});

/// 选中域装配 provider：编辑库是唯一
/// 同时握有域端口与片段／备注现值的地方，域对象在此一次装配。域直测经
/// `test/helpers/` 的 `buildAnnotationSelectionDomain(...)` 自建，不经本
/// provider。
final annotationSelectionDomainProvider = Provider<AnnotationSelectionDomain>((
  ref,
) {
  return AnnotationSelectionDomain(
    store: ref.watch(annotationSelectionProvider.notifier),
    learningStore: ref.watch(selectedLearningSegmentsProvider.notifier),
    timeline: () => ref.read(annotationTimelineProvider),
    memberSchemeReadonly: () =>
        ref.read(annotationMemberSchemeReadonlyProvider),
    writePort: _selectionWritePort(ref),
    localMirrorFragmentCount: () =>
        ref.read(localMirrorFragmentsProvider).length,
    noteCount: () => ref.read(noteStickersProvider).length,
  );
});

/// 选中域写入端口：跨域后果回到编辑
/// 侧。**写前**只在用户路径写上触发——清临时衔接段与片段激活，保住「清另两
/// 源 → 写状态 → 落盘」的次序；**写后**只在域判定有净变化时触发并带绝对终
/// 值——读熟练度与片段激活现值、组装 `session` 段入队。
AnnotationSelectionWritePort _selectionWritePort(Ref ref) {
  return AnnotationSelectionWritePort(
    beforeUserWrite: () {
      ref.read(transitionSegmentProvider.notifier)._clear();
      ref.read(practiceClipActivationProvider.notifier)._clear();
    },
    persistSelection: (_) {
      ref.read(annotationSaveSinkProvider)?.save(
        AnnotationSectionDiff(
          session: _currentSessionValue(
            ref,
            activePracticeClipId: ref
                .read(practiceClipActivationProvider)
                ?.clipId,
          ),
        ),
      );
    },
  );
}

/// 对比态只读：播放会话 ∈ 对比态（对比-播放/
/// 对比-控制/对比取景）时标注几何只读。widget「手势是否参与」与模块
/// verb 级门禁共读此单一事实源；依赖方向单向（本库 import 播放会话模式
/// 库，结构前提）。
final annotationCompareReadonlyProvider = Provider<bool>((ref) {
  return ref.watch(playerSessionProvider).isCompare;
});

/// 组员方案只读：装载组员方案时标注只读。真值由
/// 打开恢复接线就位（以组员方案打开置真、恢复起点复位），
/// 门禁与对比态只读同一份逐 verb 声明、同款静默拒绝。
final annotationMemberSchemeReadonlyProvider =
    NotifierProvider<MemberSchemeReadonlyModel, bool>(
      MemberSchemeReadonlyModel.new,
    );

class MemberSchemeReadonlyModel extends Notifier<bool> {
  @override
  bool build() => false;

  /// 打开恢复就位（true = 装载的是组员方案）。
  void setLoaded(bool value) => state = value;
}

/// 拖动会话协议本体（各族共用一份）：只承担逐帧那一段——拿一个请求
/// 目标，按本族声明的编辑命令提交一次；提交未生效（钳空、越邻、同位、
/// 同值、锁门禁拒绝）返回空，否则从模型读回**写后真实落点**并返回。每族
/// 的差异只有构造时注入的两条**必填**适配器（[_command] 与 [_readLanding]）
/// 与请求/落点的类型参数（时间族 = [Duration]，贴纸几何族 = [NoteGeometry]）。
///
/// 协议契约（三条不变量）与文档段化 effort 的边界见库头「拖动会话
/// 协议」——各具名工厂的开始期差异（校验形状、是否顺带选中）留在
/// 工厂里，不是协议不变量。onDragEnd 与 onDragCancel 都走 [end]。
///
/// 时长族拖动会话（请求与落点均为时间点的各族共同形态）。
typedef DurationDragSession = AnnotationDragSession<Duration, Duration>;

class AnnotationDragSession<Target extends Object, Landing extends Object> {
  AnnotationDragSession._(
    this._editor,
    this._token,
    this._command,
    this._readLanding,
  );

  final AnnotationEditor _editor;

  /// 生成时的会话令牌（模块侧「进行中会话令牌」当时的值）：逐帧与收口
  /// 先比对，不匹配即空操作。
  final Object _token;

  /// 适配器一（必填）：本族提交哪条编辑命令。
  final AnnotationEdit Function(Target target) _command;

  /// 适配器二（必填）：写后真实落点从模型哪一处读回。
  final Landing Function() _readLanding;

  /// 拖动到 [target]（原始请求，模块内落点解析/钳制）：本会话仍是当前
  /// 会话时按 [_command] 提交一次，生效则返回 [_readLanding] 读回的写后
  /// 真实落点；无净变化（触界/越邻/同位/同值/钳空/锁门禁拒绝）或本会话
  /// 已失效返回 null 且不写状态。
  Landing? moveTo(Target target) {
    if (!_editor._isCurrentDragSession(_token)) return null;
    final outcome = _editor.submit(_command(target));
    if (!outcome.applied) return null;
    return _readLanding();
  }

  /// 结束会话（幂等）：本会话仍是当前会话时一次收口（净变化才记一条
  /// 历史）；已失效的会话为空操作。
  void end() {
    if (!_editor._isCurrentDragSession(_token)) return;
    _editor._endSession();
  }
}

/// 标注编辑唯一写入口（模块本体），行为契约见库头注释。
/// 手势目标：轨道带上每族手势的起手目标。起手门禁的唯一
/// 知识 = [gestureTargetGateReasons]；widget 起手判定由它派生
/// （[AnnotationEditor.gestureStartRejected]）。
enum AnnotationGestureTarget {
  /// 分段线移动（verb 支撑）。
  segmentLineMove,

  /// 分段线点选（选中 toggle；锁只护几何，点选不受锁）。
  segmentLineTap,

  /// 控制柄点选（与分段线点选同一语义）。
  controlKnobTap,

  /// 半拍线移动（verb 支撑）。
  halfBeatLineMove,

  /// 半拍线点选（选中 toggle；对比态只读静默不参与）。
  halfBeatLineTap,

  /// 首尾端标拖动（verb 支撑）。
  rangeBoundaryDrag,

  /// 首尾端标点选（选中 toggle；不受锁）。
  rangeBoundaryTap,

  /// 局部镜像片段整体移（verb 支撑）。
  localMirrorMove,

  /// 局部镜像片段端点拖（verb 支撑）。
  localMirrorEdgeDrag,

  /// 局部镜像轨行点选（只选中；锁定期照常选中、不弹提示）。
  localMirrorRowTap,

  /// 备注片段整体移（verb 支撑；目标备注的内容锁是逐条事实，不在本表）。
  noteMove,

  /// 备注片段端点拖（verb 支撑；内容锁同上）。
  noteEdgeDrag,

  /// 备注轨行点选（选中 / 再点开编辑器；对比态只读静默不参与）。
  noteRowTap,

  /// 备注长按切内容锁（两把锁都不挡锁定开关；对比态只读静默不参与）。
  noteLockLongPress,

  /// 练习片段端点截取（verb 支撑：刻意豁免对比态只读——截取是对比态
  /// 自己的写点，**只报锁定**）。
  practiceClipTrim,

  /// 练习片段块点按（激活 / 选中切换；无门）。
  practiceClipBlockTap,

  /// 学习段轨点选与激活（无门）。
  learningTrackTap,

  /// 预览线拖动接管（seek 语义；无门）。
  previewLineDrag,

  /// 空白面捏合与翻看（无门）。
  blankSurfacePinchPan,
}

/// 手势目标起手门禁声明表：每个手势目标
/// 声明它受哪些文档级原因（[AnnotationEditGateReason]）——verb 支撑的
/// 目标从逐 verb 声明（[AnnotationEditor.verbGateReasons]）取值（同一份
/// 声明，不抄第二份）；无 verb 的目标就地声明，**无门 = 显式空清单**。
/// 用户锁只落在「拖分段线」与「拖首尾边界」两个目标上（锁只护分段结构）；
/// 捏合、突发、行存在、几何可用属拖动协议，装载未完成属可用性事实，
/// 均不进本表。
Set<AnnotationEditGateReason> gestureTargetGateReasons(
  AnnotationGestureTarget target,
) => switch (target) {
  // verb 支撑：代表 verb 只取类型（声明 switch 按类型分组，字段不参与）。
  AnnotationGestureTarget.segmentLineMove => AnnotationEditor.verbGateReasons(
    const MoveSegmentLine(index: 0, to: Duration.zero),
  ),
  AnnotationGestureTarget.halfBeatLineMove =>
    AnnotationEditor.verbGateReasons(
      const MoveHalfBeatLine(index: 0, to: Duration.zero),
    ),
  AnnotationGestureTarget.rangeBoundaryDrag =>
    AnnotationEditor.verbGateReasons(const SetVideoRange()),
  AnnotationGestureTarget.localMirrorMove => AnnotationEditor.verbGateReasons(
    const MoveLocalMirrorFragment(index: 0, to: Duration.zero),
  ),
  AnnotationGestureTarget.localMirrorEdgeDrag =>
    AnnotationEditor.verbGateReasons(
      const DragLocalMirrorFragmentEdge(
        index: 0,
        edge: IntervalEdge.start,
        to: Duration.zero,
      ),
    ),
  AnnotationGestureTarget.noteMove => AnnotationEditor.verbGateReasons(
    const MoveNote(index: 0, to: Duration.zero),
  ),
  AnnotationGestureTarget.noteEdgeDrag => AnnotationEditor.verbGateReasons(
    const DragNoteEdge(index: 0, edge: IntervalEdge.start, to: Duration.zero),
  ),
  AnnotationGestureTarget.practiceClipTrim => AnnotationEditor.verbGateReasons(
    // 声明求值只看 verb 族，clipId 占位（提交按 id 回查）；
    // 练习片段截取不声明任何门禁原因（显式空清单）。
    const TrimPracticeClip(
      clipId: '',
      edge: IntervalEdge.start,
      to: Duration.zero,
    ),
  ),
  // 无 verb 的目标：就地声明；无门 = 显式空清单。
  AnnotationGestureTarget.segmentLineTap => const {},
  AnnotationGestureTarget.controlKnobTap => const {},
  AnnotationGestureTarget.halfBeatLineTap => const {
    AnnotationEditGateReason.compareReadonly,
  },
  AnnotationGestureTarget.rangeBoundaryTap => const {},
  AnnotationGestureTarget.localMirrorRowTap => const {},
  AnnotationGestureTarget.noteRowTap => const {
    AnnotationEditGateReason.compareReadonly,
  },
  AnnotationGestureTarget.noteLockLongPress => const {
    AnnotationEditGateReason.compareReadonly,
  },
  AnnotationGestureTarget.practiceClipBlockTap => const {},
  AnnotationGestureTarget.learningTrackTap => const {},
  AnnotationGestureTarget.previewLineDrag => const {},
  AnnotationGestureTarget.blankSurfacePinchPan => const {},
};

class AnnotationEditor {
  AnnotationEditor(this._ref);

  final Ref _ref;

  /// 进行中拖动会话的令牌：非空 = 会话中
  /// （submit 并入会话、不单独入史），同时是会话唯一性的结构性保证——
  /// 会话对象持有生成时的令牌，逐帧与收口先比对。会话收口以首尾快照比较
  /// 记一条历史。
  Object? _sessionToken;

  /// 「会话进行中」谓词（全库唯一定义；收口 seam [_commit] 第一句读它）。
  bool get _sessionOpen => _sessionToken != null;

  /// [token] 是否仍是当前进行中会话的令牌（会话对象逐帧/收口的守卫）。
  bool _isCurrentDragSession(Object token) => _sessionToken == token;

  /// 进行中拖动会话的事务起点快照（历史与保存共用的唯一
  /// before 捕获；null = 无会话）。
  AnnotationEditSnapshot? _transactionStart;

  // ── 读取侧内部缝 ──

  AnnotationTimeline get _timeline => _ref.read(annotationTimelineProvider);

  AnnotationEditHistoryModel get _history =>
      _ref.read(annotationEditHistoryProvider.notifier);

  AnnotationSelectionDomain get _selectionDomain =>
      _ref.read(annotationSelectionDomainProvider);

  Map<int, LearningMastery> get _mastery => _ref.read(learningMasteryProvider);

  Set<int> get _emphasis => _ref.read(learningEmphasisProvider);

  /// 逐段档读面：几何变动级联与快照捕获
  /// 共用。
  Map<int, double> get _segmentDensities =>
      _ref.read(segmentDensitiesProvider);

  /// 当前选中的学习段段序（升序）——批量熟练度/重点写点的作用对象
  /// 无选中为空列表。
  List<int> _selectedSegmentOrders() =>
      _ref.read(selectedLearningSegmentsProvider).toList()..sort();

  List<LocalMirrorFragment> get _localMirrorFragments =>
      _ref.read(localMirrorFragmentsProvider);

  /// 备注贴纸读面（独立值道，快照 lane 同源）。
  List<NoteSticker> get _notes => _ref.read(noteStickersProvider);

  /// 练习片段读面（独立 lane，快照 lane 同源）。
  List<PracticeClip> get _practiceClips =>
      _ref.read(practiceClipsProvider);

  /// 公开 beat 段八拍锚点读面：锚点存 beat 段，
  /// 会话内的现值即写读源；占位/异常无 beat 段恒空。
  List<int> get _eightBeatAnchors => appliedEightBeatAnchors(_ref);

  AnnotationEditSnapshot _capture() => AnnotationEditSnapshot(
    corrections: MarkerCorrectionsValue(
      shiftSeconds: appliedBeatShiftSeconds(_ref),
      density: appliedBeatDensity(_ref),
      eightBeatAnchors: _eightBeatAnchors,
    ),
    annotations: _annotationsSection(
      _timeline,
      emphasis: _emphasis,
      segmentDensities: _segmentDensities,
      localMirrorFragments: _localMirrorFragments,
    ),
    session: LocalSessionValue(mastery: _mastery),
    notes: _notes,
    practiceClips: _practiceClips,
  );

  /// 从时间线 + 属性面组装 markers `annotations` 段值（一处装配，
  /// 快照捕获与提交判等共用）。
  MarkerAnnotationsValue _annotationsSection(
    AnnotationTimeline timeline, {
    required Set<int> emphasis,
    required Map<int, double> segmentDensities,
    required List<LocalMirrorFragment> localMirrorFragments,
  }) =>
      MarkerAnnotationsValue(
        rangeStart: timeline.rangeStart,
        rangeEnd: timeline.rangeEnd,
        segmentLines: timeline.segmentLines,
        halfBeatLines: timeline.halfBeatLines,
        emphasizedSegments: emphasis,
        segmentDensities: segmentDensities,
        localMirrorFragments: localMirrorFragments,
      );

  // ── 落点解析基础设施（半拍线/首尾线复用）──

  /// 真实拍点可用读面（各线型落点解析共用的可用性谓词，收口：
  /// 只读共享内核两个可用性谓词之一 [BeatGridReads.hasRealBeats]）。
  /// 就绪性按 [beatGridProvider] 派生格自陈的性质判定——派生格在非就绪态
  /// 回落占位/兜底格并在值上表态，占位/异常（含「就绪但拍点为空」潜伏态
  /// 的占位回落）一律不可用；落点也按同一派生格求值，单一来源。
  bool get _hasRealBeats => _ref.read(beatGridProvider).hasRealBeats;

  /// 分段线落点解析：把「请求位置」解析为合法落点，供交互命令提交时
  /// 调用——widget 不再预吸附。
  ///
  /// 规则（对齐落点词条，经 core 单一相位源）：
  ///
  ///   - **就绪网格在场** → 解析就近八拍点（[BeatPhase.nearest]，消费
  ///     [beatPhaseProvider]——派生网格（已应用/预览平移随行）+ 八拍锚点
  ///     （分段线落点跟锚点重定相））；网格无八拍点（downbeat
  ///     缺失等）= 无合法落点。就绪性按 [_hasRealBeats]。
  ///   - **非就绪网格**（占位/异常）→ 无吸附依据，请求位置原样直通
  ///     （生产入口由就绪置灰门挡住；模块对到达的请求做落点解析，幂等）。
  ///   - **合法域** = 时间线开区间（[_inOpenRange]，两落点解析共用）：
  ///     解析结果触界或在区间外 = 编辑不成立（null → [EditNoop] 静默，
  ///     不入史不入盘）。
  bool _inOpenRange(Duration t) {
    final timeline = _timeline;
    return t > timeline.rangeStart && t < timeline.rangeEnd;
  }

  Duration? _resolveSegmentLineLanding(Duration requested) {
    var landing = requested;
    if (_hasRealBeats) {
      // 分段线落点按**锚点重定相**的八拍点解析（单一相位源；
      // 无锚点时退化为网格首个强拍起的默认八拍相位）。
      final snapped = _ref.read(beatPhaseProvider).nearest(requested);
      if (snapped == null) return null;
      landing = snapped;
    }
    return _inOpenRange(landing) ? landing : null;
  }

  /// 半拍线落点解析：合法域与分段线同一检查
  /// （[_inOpenRange]），吸附目标 = 就近**半拍格点**（相邻拍点中点，
  /// [resolveHalfBeatSnap]）。
  ///
  ///   - **就绪网格 / 占位均匀网格** → 消费 [beatGridProvider] 派生网格
  ///     解析（占位 120bpm 均匀网格照常派生半拍位，「对齐落点」占位语义
  ///     不变）；网格无候选 = 无合法落点。
  ///   - **异常态** → 吸附停用（既有语义），请求位置原样直通。
  ///   - **合法域** = 时间线开区间：触界或区间外 = null → [EditNoop]。
  Duration? _resolveHalfBeatLineLanding(Duration requested) {
    final grid = _ref.read(beatGridProvider);
    var landing = requested;
    // 异常态吸附停用（[isSecondsFallback]，收口）；占位均匀网格
    // 照常派生半拍位。
    if (!grid.isSecondsFallback) {
      final snapped = resolveHalfBeatSnap(requested, grid: grid);
      if (snapped == null) return null;
      landing = snapped;
    }
    return _inOpenRange(landing) ? landing : null;
  }

  /// 首尾线落点解析（复用 [_hasRealBeats] 就绪读面）：把
  /// 「请求位置」解析为首尾线合法落点，供 [SetVideoRange] 交互命令提交
  /// 时调用——widget 不再预吸附。
  ///
  /// 规则（对齐落点词条，沿用纯域吸附函数 [snapRangeBoundary] 语义）：
  ///
  ///   - **就绪网格在场**（与分段线同一就绪读面）→ 按派生网格（已应用/
  ///     预览平移随行）解析：网格覆盖区（首拍..末拍）内吸最近**真实拍点**
  ///     （含弱起拍，等距取靠后）；覆盖区外自由落点（首尾线可拖出网格
  ///     生成区直到片尾，不回拉）。
  ///   - **非就绪网格**（无界占位/异常均匀实现）→ 无网格语义，请求位置
  ///     自由直通（生产入口由就绪置灰门挡住；模块对到达的请求做落点
  ///     解析，幂等）。
  ///   - **合法域**：端标本体即区间边界，不适用分段线的开区间触界检查；
  ///     合法域 = 首尾可拖范围与 start<end 归一化钳制，由
  ///     `timeline_ops.setVideoRange` 纯函数收口（不经落点解析的路径
  ///     契约不变）。
  Duration _resolveRangeBoundaryLanding(Duration requested) {
    if (_hasRealBeats) {
      return snapRangeBoundary(requested, grid: _ref.read(beatGridProvider));
    }
    return requested;
  }

  /// 八拍锚点落点解析：把「请求位置」解析为最近**强拍**的
  /// **拍序号**（返回的是网格上的强拍序号，不保证它在锚点集合内——加/删两个
  /// verb 各自再判集合成员）。仅就绪真实网格可解析（[_hasRealBeats]）——
  /// 占位/异常无节拍数据、解析不成立 = null（落锚/删锚不成立，EditNoop
  /// 静默）；网格无强拍（识别退化）同样 null。合法域不在时间线开区间内检查：
  /// 锚点是**网格上的拍**，落域由网格本体收口（早于首拍/晚于末拍贴首/末
  /// 强拍，不越界）。
  int? _resolveDownbeatBeatIndex(Duration requested) {
    if (!_hasRealBeats) return null;
    return resolveDownbeatLanding(
      requested,
      grid: _ref.read(beatGridProvider),
    )?.beatIndex;
  }

  // ── 唯一可入史写路径 ──

  /// 锁定分段是否开启（本库的锁状态只读缝）。
  bool get _layoutLocked => _ref.read(layoutLockedProvider);

  /// 对比态只读：播放会话 ∈ 对比态即只读（单一事实源 =
  /// [annotationCompareReadonlyProvider]）。
  bool get _compareReadonly => _ref.read(annotationCompareReadonlyProvider);

  /// 组员方案只读：装载组员方案时标注只读
  /// （单一事实源 = [annotationMemberSchemeReadonlyProvider]）。
  bool get _memberSchemeReadonly =>
      _ref.read(annotationMemberSchemeReadonlyProvider);

  /// 起手前纯读（widget 缝）：这个手势目标起手会不会被文档级
  /// 门禁拒。按目标声明表（[gestureTargetGateReasons]）对当前三个门禁
  /// 事实（锁定分段、对比态只读、组员方案只读）求值；**静默**——不弹提示、
  /// 不写状态、不建会话，widget 起手判定由此派生（不再手拼子集）。逐帧
  /// 提交时的门禁次序与提示归属不变（拒绝的最终裁决仍在模块）。
  bool gestureStartRejected(AnnotationGestureTarget target) {
    if (gestureStartRejectedBySegmentLock(target)) return true;
    final reasons = gestureTargetGateReasons(target);
    if (reasons.contains(
          AnnotationEditGateReason.compareReadonly,
        ) &&
        _compareReadonly) {
      return true;
    }
    // 组员方案只读：受本原因门禁的目标（逐 verb
    // 声明的几何族）在装载组员方案时静默不参与，与对比态只读同款；
    // 点选类目标不声明本原因——选中与激活不是编辑。
    return reasons.contains(
          AnnotationEditGateReason.memberSchemeReadonly,
        ) &&
        _memberSchemeReadonly;
  }

  /// 起手是否被**分段锁**拒：本手势目标此刻被用户锁覆盖且锁
  /// 开着——两个受锁目标（拖分段线 / 拖首尾边界）共用这一处起手判定，
  /// widget 据此在首次位移成立那刻弹一次「已锁定分段」并放弃手势。对比态
  /// 只读与组员方案只读仍静默，故不计入本判定（[gestureStartRejected] 才是
  /// 合并三者的「会不会被拒」）。
  bool gestureStartRejectedBySegmentLock(AnnotationGestureTarget target) =>
      _layoutLocked &&
      gestureTargetGateReasons(target).contains(
        AnnotationEditGateReason.userLayoutLock,
      );

  /// 触发一次「已锁定分段」短暂提示并返回锁门禁拒绝结果（编辑不成立）。
  EditLocked _lockedReject() {
    _ref.read(noticeTriggerProvider(NoticeId.layoutLock).notifier).show();
    return const EditLocked();
  }

  /// 触发一次「备注已锁定」短暂提示并返回内容锁拒绝结果（编辑
  /// 不成立）。
  EditLocked _contentLockReject() {
    _ref.read(noticeTriggerProvider(NoticeId.noteContentLock).notifier).show();
    return const EditLocked();
  }

  /// 逐 verb 门禁原因声明（锁门禁 + 对比态只读 + 组员方案只读，一个门禁
  /// N 个原因）：**用户锁只覆盖分段结构族**——分段线的创建/删除/移动、
  /// 首尾边界调整、自动分段、清空分段、flag 切换；它们同时受对比态只读
  /// （flag 除外）与组员方案只读门禁。节拍域（半拍线、节拍对齐、节拍
  /// 倍频、八拍锚点）与画面/各片段轨（备注片段、局部镜像片段）不受用户
  /// 锁，只受对比态只读与组员方案只读；练习片段截取/删除是对比态自己的
  /// 写点、不声明任何门禁原因。文本与熟练度/重点/备注锁开关豁免用户锁与
  /// 对比态，但受组员方案只读——装载组员方案时一切几何与文本改动被拒。
  /// 选中/清除选中、临时衔接段会话组、撤销/重做、恢复装载、恢复前清、
  /// 复位不进 submit，天然不受本表约束；激活学习段写我的落盘状态，装载
  /// 组员方案时由域写入口静默拒绝
  /// （[AnnotationSelectionDomain.toggleLearningSegment]）。新增原因 =
  /// 枚举加值 + 各 verb 集合补声明，漏声明由本穷尽 switch 兜住。
  /// 纯声明（不读实例状态）：手势目标声明表
  /// （[gestureTargetGateReasons]）逐 target 从这里取值。
  static Set<AnnotationEditGateReason> verbGateReasons(AnnotationEdit edit) =>
      switch (edit) {
        // 分段结构族（用户锁 + 对比态只读 + 组员方案只读）。
        AddSegmentLine() ||
        RemoveSegmentLine() ||
        MoveSegmentLine() ||
        SetVideoRange() ||
        AutoSegment() ||
        ClearSegmentLines() => const {
          AnnotationEditGateReason.userLayoutLock,
          AnnotationEditGateReason.compareReadonly,
          AnnotationEditGateReason.memberSchemeReadonly,
        },
        // flag 切换同属分段结构（标记入口进「添加」
        // 菜单）：受用户锁与组员方案只读，豁免对比态只读（对比态不改 flag
        // 链路）。
        ToggleSegmentFlag() => const {
          AnnotationEditGateReason.userLayoutLock,
          AnnotationEditGateReason.memberSchemeReadonly,
        },
        // 节拍域（半拍线 / 节拍对齐 / 节拍倍频 / 八拍锚点）：不受用户锁，
        // 受对比态只读与组员方案只读。
        AddHalfBeatLine() ||
        MoveHalfBeatLine() ||
        RemoveHalfBeatLine() ||
        ApplyBeatShift() ||
        ApplyBeatDensity() ||
        AddEightBeatAnchor() ||
        RemoveEightBeatAnchor() ||
        ClearEightBeatAnchors() => const {
          AnnotationEditGateReason.compareReadonly,
          AnnotationEditGateReason.memberSchemeReadonly,
        },
        // 备注轨（片段几何）：不受用户锁（几何另受备注自己的内容锁管，
        // 见 `_noteContentLocked`），受对比态只读与组员方案只读。
        InsertNote() ||
        MoveNote() ||
        DragNoteEdge() ||
        SetNoteGeometry() ||
        RemoveNote() => const {
          AnnotationEditGateReason.compareReadonly,
          AnnotationEditGateReason.memberSchemeReadonly,
        },
        // 局部镜像片段轨：不受用户锁，受对比态只读与组员方案只读。
        AddLocalMirrorFragment() ||
        RemoveLocalMirrorFragment() ||
        MoveLocalMirrorFragment() ||
        DragLocalMirrorFragmentEdge() => const {
          AnnotationEditGateReason.compareReadonly,
          AnnotationEditGateReason.memberSchemeReadonly,
        },
        // 练习片段截取/删除：对比态自己的写点（练习视频轨
        // 是对比行集里唯一可编辑行），**不声明任何门禁原因**。
        TrimPracticeClip() || RemovePracticeClip() => const {},
        // 文本与锁定开关豁免锁定分段（锁只护几何，不挡
        // 写字与开关）；对比态同样豁免（备注文本编辑链路不改）。
        SetNoteText() ||
        ToggleNoteLock() ||
        SetSegmentMastery() ||
        ToggleSegmentEmphasis() ||
        SetSelectedSegmentsMastery() ||
        SetSelectedSegmentsDensity() ||
        ToggleSelectedSegmentsEmphasis() => const {
          AnnotationEditGateReason.memberSchemeReadonly,
        },
      };

  /// 内容锁门禁：几何类备注命令（整体移 / 端点拖 / 贴纸几何）
  /// 在**目标备注已锁**时被拒——内容锁语义收成一句话：保护这条备注的
  /// 几何；文本 / 样式 / 锁定开关豁免。不新增第 5 个门（可用性判定表
  /// 不动），走模块拒绝 + 同族提示。
  bool _noteContentLocked(AnnotationEdit edit) => switch (edit) {
    MoveNote(:final index) ||
    DragNoteEdge(:final index) ||
    SetNoteGeometry(:final index) => _lockedAt(index),
    _ => false,
  };

  /// [index] 处备注是否已锁（越界抛 [RangeError]，与按索引 verb 一致）。
  bool _lockedAt(int index) {
    _checkNoteIndex(index);
    return _notes[index].locked;
  }

  /// 提交一条编辑命令：前快照捕获（提交点起点，与 no-op 判据同源）→ 纯函数
  /// 分发 → no-op 判定 → 几何 diff → slice 级联 → 选中维护 → 显式几何清
  /// 除 → 分写粒状 Notifier → 经收口 seam [_commit] 折叠分发历史与保存。
  /// 会话中提交自动并入会话（只 apply，不各自入史/入队）。
  /// 锁门禁先于一切（门禁次序 = 锁 → 就绪网格 → 落点）：锁定态受锁 verb
  /// 返回 [EditLocked]，不写、不入史、不入盘、不抛。内容锁门禁
  /// 次于锁定分段：几何类备注命令在目标备注已锁时同样返回 [EditLocked]
  /// 并触发「备注已锁定」提示——两套门禁并存、各弹各的提示。
  EditOutcome submit(AnnotationEdit edit) {
    final gateReasons = verbGateReasons(edit);
    if (_layoutLocked &&
        gateReasons.contains(AnnotationEditGateReason.userLayoutLock)) {
      return _lockedReject();
    }
    if (_noteContentLocked(edit)) return _contentLockReject();
    if (gateReasons.contains(
          AnnotationEditGateReason.compareReadonly,
        ) &&
        _compareReadonly) {
      // 对比态只读：静默拒绝——不弹提示（对比态不是「锁」），
      // 不写、不入史、不入盘、不抛。
      return const EditLocked();
    }
    if (gateReasons.contains(
          AnnotationEditGateReason.memberSchemeReadonly,
        ) &&
        _memberSchemeReadonly) {
      // 组员方案只读：同款静默拒绝——组员
      // 方案不能被我改，也不弹提示。
      return const EditLocked();
    }
    final before = _capture();
    final plan = _plan(edit);
    final nextTimeline = plan.timeline ?? _timeline;

    // no-op 判定：前后快照（按段）相等 → 不写、不清、不入史。平移量
    // 写定值参与比较：时间线被钳回原值而平移量变化的纯字段写定
    // 是 applied；平移量也不变的整体 no-op 才是 EditNoop。
    final after = AnnotationEditSnapshot(
      corrections: MarkerCorrectionsValue(
        shiftSeconds: plan.beatShift ?? before.corrections.shiftSeconds,
        density: plan.beatDensity ?? before.corrections.density,
        eightBeatAnchors:
            plan.eightBeatAnchors ?? before.corrections.eightBeatAnchors,
      ),
      annotations: _annotationsSection(
        nextTimeline,
        // 锚点集合写终值参与判等：重复落锚同一强拍 = 集合
        // 未变 = EditNoop 静默（不入史不入盘）。片段 verb 携写终值参与
        // 判等，几何/属性 verb（无片段写）沿用 before 片段值判等。
        emphasis: plan.emphasis ?? before.annotations.emphasizedSegments,
        segmentDensities:
            plan.segmentDensities ?? before.annotations.segmentDensities,
        localMirrorFragments:
            plan.localMirrorFragments ??
            before.annotations.localMirrorFragments,
      ),
      session: LocalSessionValue(
        mastery: plan.mastery ?? before.session.mastery,
      ),
      // 备注 lane：快照独立 lane；verb 写终值 = 备注命令
      // 携带（plan 无备注写时沿用 before 快照值判等）。
      notes: plan.notes ?? before.notes,
      // 练习片段 lane：快照独立 lane；plan 无片段写时沿用
      // before 快照值判等。
      practiceClips: plan.practiceClips ?? before.practiceClips,
    );
    if (before == after) {
      return const EditNoop();
    }

    // 几何 diff 全 submit 只算一次，清除与 outcome 共用。
    final geometryChanged = _geometryChanged(
      before.annotations,
      after.annotations,
    );

    void apply() {
      if (plan.timeline != null) {
        _selectionDomain.remapLineSelection(_timeline, plan.timeline!);
      }
      plan.selectionOp?.call();
      // 几何清除先于属性/时间线分写与历史写入（快照
      // 不含激活/临时段，写序收敛终态等价）。
      if (geometryChanged) {
        _clearLoopActivationsOnGeometryChange();
      }
      if (plan.mastery != null) {
        _ref.read(learningMasteryProvider.notifier)._replace(plan.mastery!);
      }
      if (plan.emphasis != null) {
        _ref.read(learningEmphasisProvider.notifier)._replace(plan.emphasis!);
      }
      // 逐段档：几何级联/清空的重烘焙全表
      // 经同一写缝落库；无级联的 verb（含节拍倍频/节拍对齐）plan 字段为
      // null 不动 lane。
      if (plan.segmentDensities != null) {
        _ref
            .read(segmentDensitiesProvider.notifier)
            ._replace(plan.segmentDensities!);
      }
      if (plan.timeline != null) {
        _ref.read(annotationTimelineProvider.notifier)._replace(plan.timeline!);
      }
      if (plan.beatShift != null) {
        writeAppliedBeatShift(_ref, plan.beatShift!);
      }
      // 节拍倍频：倍频命令写定 beat 段 density（与平移量同一
      // 「节拍侧字段」承载模式）；锚点集合由 plan.eightBeatAnchors 携带
      // 烘焙终值、经下一行同一写缝落库。
      if (plan.beatDensity != null) {
        writeAppliedBeatDensity(_ref, plan.beatDensity!);
      }
      // 八拍锚点：落锚提交写定 beat 段锚点集合（与平移量同一
      // 「节拍侧字段」承载模式）；派生网格/相位源随 state 变更当帧刷新。
      if (plan.eightBeatAnchors != null) {
        writeEightBeatAnchors(_ref, plan.eightBeatAnchors!);
      }
      // 局部镜像片段独立 lane：片段 verb 写终值经 store 写缝落库；
      // 几何/属性 verb 无写（plan 字段 null）不动片段。
      if (plan.localMirrorFragments != null) {
        _ref
            .read(localMirrorFragmentsProvider.notifier)
            ._replace(plan.localMirrorFragments!);
      }
      // 备注插入：备注 lane 写终值经 store 写缝落库。
      if (plan.notes != null) {
        _ref.read(noteStickersProvider.notifier)._replace(plan.notes!);
      }
      // 练习片段截取：片段 lane 写终值经库内私有写缝落 provider
      // （随舞 prefs 持久化编排监听本 lane 落盘）。
      if (plan.practiceClips != null) {
        _ref.read(practiceClipsProvider.notifier)._replace(plan.practiceClips!);
      }
    }

    apply();

    _commit(before, _capture());
    return EditApplied(geometryChanged: geometryChanged);
  }

  /// 收口 seam（收敛为全库唯一折叠分发点）：单发提交
  /// （非会话分支）、拖动态收口（[_endSession]）与 undo/redo 回放
  /// 支路（`recordHistory: false` 不记史）的共同提交点——会话中逐
  /// 帧提交也经此入口但在会话分支上早退（只 apply、不入史不入队）。
  /// before 在提交入口捕获一次（与帧级 no-op 判据同源快照），apply/回放
  /// 落库后捕获一次 after；折叠一次段级 diff——为空则历史与保存一起跳
  /// 过，非空才同时喂两消费者（历史记录 = 显式快照对；保存编排 = 段级
  /// diff 入队）。
  void _commit(
    AnnotationEditSnapshot before,
    AnnotationEditSnapshot after, {
    bool recordHistory = true,
  }) {
    if (_sessionOpen) return;
    var diff = foldSectionDiff(before, after);
    // 练习片段 lane不在 [AnnotationSectionDiff] 内：片段持久化
    // 归随舞 prefs 编排（practiceClipsProvider 的唯一写听者，
    // 段/写入者一一对应），不经 markers/标注保存臂。本 lane 只参与净变
    // 化判定（快照相等含片段逐位相等）与历史折叠。
    final clipsChanged = !_listEquals(
      before.practiceClips,
      after.practiceClips,
    );
    if (diff.isEmpty && !clipsChanged) return;
    // session 段值是绝对终值，落盘前补上当前激活现值——激活不属于编辑
    // 快照（不入史、不参与回放），但它是 session 段的字段，缺省会以空
    // 集覆盖盘上值。激活自身的写入点在激活集合模型，两条路径都读现值
    // 组段值，latest-wins 下互不覆盖。
    final session = diff.session;
    if (session != null) {
      diff = AnnotationSectionDiff(
        corrections: diff.corrections,
        annotations: diff.annotations,
        notes: diff.notes,
        session: _currentSessionValue(
          _ref,
          activePracticeClipId: _ref
              .read(practiceClipActivationProvider)
              ?.clipId,
        ),
      );
    }
    if (recordHistory) _history._record(before, after);
    // 仅标注段净变化入队标注保存臂；片段-only 变更的落盘归随舞 prefs
    // 编排（practiceClipsProvider 写听者），不入本 diff。
    if (!diff.isEmpty) _saveDiff(diff);
  }

  /// 段级 diff 入队保存（未注入编排器时零行为）。
  void _saveDiff(AnnotationSectionDiff diff) {
    _ref.read(annotationSaveSinkProvider)?.save(diff);
  }

  // ── 备注插入落点解析──

  /// 备注索引越界守卫（越界抛 [RangeError]，与其它按索引 verb 一致）。
  void _checkNoteIndex(int index) {
    final count = _notes.length;
    if (index < 0 || index >= count) {
      throw RangeError.range(index, 0, count - 1, 'index', '备注索引越界');
    }
  }

  /// 占用谓词（入口路由消费）：预览线 [at]（**原始请求位置**，不
  /// 钳制、不吸附）落在某条既有备注的半开
  /// 时间窗 `[startMs, endMs)` 内。
  bool isNoteLandingOccupied(Duration at) => noteLandingOccupied(_notes, at);

  /// 备注表 → 区间表（共用件换算的统一入口）。
  List<IntervalSpan> get _noteSpans => [
    for (final note in _notes)
      IntervalSpan(startMs: note.startMs, endMs: note.endMs),
  ];

  /// 新建备注落点解析：读落点所需的域事实（时间线、自由区间内的拍点、
  /// 默认窗宽）后交由纯件 [resolveNoteInsertion]——钳制 → 占用不建 →
  /// 自由区间内拍点吸附 → 向尾与右邻截断 + 左邻几何初值都在那一处；
  /// 不建（null）= 空 plan → 快照相等 → EditNoop 静默。
  NoteSticker? _resolveNoteInsert(Duration requested) {
    final timeline = _timeline;
    return resolveNoteInsertion(
      notes: _notes,
      requestMs: requested.inMilliseconds,
      rangeStartMs: timeline.rangeStart.inMilliseconds,
      rangeEndMs: timeline.rangeEnd.inMilliseconds,
      beatPoints: _hasRealBeats
          ? _ref
                .read(beatGridProvider)
                .beatsInWindow(timeline.rangeStart, timeline.rangeEnd)
          : const [],
      widthMs: _eightBeatWidthMs(),
    );
  }

  // ── 备注轨片段拖动──

  /// 备注片段落点解析（**拍点级**）：就绪网格 → 吸最近**真实拍点**（与
  /// 局部镜像片段端点同一支 [_resolveFragmentEdgeLanding]，含弱起拍、覆盖
  /// 区外自由）；**网格未就绪 / 异常 → 不吸附**，请求位置直通（吸附需要
  /// 就绪网格，未就绪时不吸附但照常创建）。
  ///
  /// 整体移起点与端点拖共用本规则；**不做占用跳过**——拖动与相邻备注的
  /// 互斥由钳制收口，不同于创建落点的「自由区间内吸附」。
  Duration _resolveNoteFragmentLanding(Duration requested) =>
      _hasRealBeats ? _resolveFragmentEdgeLanding(requested) : requested;

  /// 以可变副本返回备注列表并对 [index] 做越界守卫（越界抛 [RangeError]，
  /// 与其它按索引 verb 一致）。
  List<NoteSticker> _checkedNoteList(int index) {
    final notes = List.of(_notes);
    if (index < 0 || index >= notes.length) {
      throw RangeError.range(index, 0, notes.length - 1, 'index', '备注索引越界');
    }
    return notes;
  }

  /// 整体移 plan：宽度不变平移 + 互斥钳制；钳空返回空 plan
  ///（EditNoop，静默停住）。起点落点 = 拍点级（[_resolveFragmentEdgeLanding]，
  /// 与端点拖同一网格）。
  _EditPlan _planNoteMove(int index, Duration to) {
    final notes = _checkedNoteList(index);
    final timeline = _timeline;
    final moved = moveNoteClamped(
      notes: notes,
      index: index,
      rangeStartMs: timeline.rangeStart.inMilliseconds,
      rangeEndMs: timeline.rangeEnd.inMilliseconds,
      newStartMs: _resolveNoteFragmentLanding(to).inMilliseconds,
    );
    if (moved == null) return _EditPlan(); // 钳空 drop
    notes[index] = moved;
    return _EditPlan()..notes = notes;
  }

  /// 端点拖 plan：改起止不得倒置 + 互斥钳制；越位/钳空返回空
  /// plan。端点落点 = 拍点级（[_resolveFragmentEdgeLanding]：每个拍点都能
  /// 落，不按八拍分级）。
  _EditPlan _planNoteDragEdge(int index, IntervalEdge edge, Duration to) {
    final notes = _checkedNoteList(index);
    final timeline = _timeline;
    final dragged = dragNoteEdgeClamped(
      notes: notes,
      index: index,
      edge: edge,
      rangeStartMs: timeline.rangeStart.inMilliseconds,
      rangeEndMs: timeline.rangeEnd.inMilliseconds,
      edgeMs: _resolveNoteFragmentLanding(to).inMilliseconds,
    );
    if (dragged == null) return _EditPlan(); // 越位/钳空 drop
    notes[index] = dragged;
    return _EditPlan()..notes = notes;
  }

  /// 贴纸几何 plan：请求几何在模块内单点钳制（[clampNoteGeometry]
  /// ——中心进 [0,1]、系数进具名界）；钳后同值 = 空 plan（EditNoop 静默）。
  _EditPlan _planNoteGeometry(int index, NoteGeometry requested) {
    final notes = _checkedNoteList(index);
    final clamped = clampNoteGeometry(requested);
    if (clamped == notes[index].geometry) return _EditPlan();
    notes[index] = notes[index].copyWith(geometry: clamped);
    return _EditPlan()..notes = notes;
  }

  // ── 局部镜像片段落点解析──

  /// 片段落点解析（**拍点级**，逐态；两轨共用一处）：备注片段的端点拖 /
  /// 整体移与局部镜像片段的端点拖都走本规则——片段落点吸**每个拍点**，
  /// 不按八拍点分级。
  ///
  ///   - **就绪网格**（真实拍点）→ 网格覆盖区内吸最近**真实拍点**（复用
  ///     [snapRangeBoundary]：含弱起拍，与首尾线同一真实拍吸附 seam）、
  ///     覆盖区外自由；
  ///   - **占位均匀网格** → 吸最近**均匀同级派生点**（占位均匀网格等分点，
  ///     [beatGridProvider] 占位网格的拍点）；
  ///   - **异常态** → 自由（不吸附，请求原样直通）。
  ///
  /// 固定吸附、不随缩放分级。与相邻片段的互斥由钳制收口，不做占用跳过
  /// （不同于创建落点的「自由区间内吸附」）。返回解析后的绝对时刻。
  Duration _resolveFragmentEdgeLanding(Duration requested) {
    final grid = _ref.read(beatGridProvider);
    // 异常态自由（[isSecondsFallback]，收口）。
    if (grid.isSecondsFallback) return requested;
    if (grid.hasRealBeats) {
      return snapRangeBoundary(requested, grid: grid);
    }
    // 占位均匀网格：吸附最近派生（等分）拍点。
    final uniform = _nearestUniformDerivedPointMs(grid, requested.inMilliseconds);
    return uniform == null ? requested : Duration(milliseconds: uniform);
  }

  /// 创建起点落点（局部镜像片段新建吸八拍点）：就绪网格吸最近真实八拍点、
  /// 占位均匀网格同级派生八拍点；异常自由。无八拍点则自由直通。
  ///
  /// 起点经相位源（[beatPhaseProvider]，派生网格 + 八拍锚点）求值，
  /// 与分段线落点同款——设过锚点后落点跟锚点重定相（无锚点时退化为网格
  /// 首个强拍起的默认八拍相位）。
  int _resolveFragmentStart(Duration requested) {
    // 异常态自由（[isSecondsFallback]，收口）。
    if (_ref.read(beatGridProvider).isSecondsFallback) {
      return requested.inMilliseconds;
    }
    final eight = _ref.read(beatPhaseProvider).nearest(requested);
    return (eight ?? requested).inMilliseconds;
  }

  /// 在 [grid]（占位均匀网格）的派生拍点中取 [requestedMs] 最近者；无候选
  /// 返回 null（调用方自由直通）。
  int? _nearestUniformDerivedPointMs(BeatGrid grid, int requestedMs) {
    final index = grid.beatIndexAt(Duration(milliseconds: requestedMs));
    final candidates = <Duration>[];
    for (var i = index - 1; i <= index + 1; i++) {
      if (i < 0) continue;
      candidates.add(grid.beatTime(i));
    }
    final nearest =
        nearestCandidate(candidates, Duration(milliseconds: requestedMs));
    return nearest?.inMilliseconds;
  }

  /// 创建默认宽：右延一个八拍宽。就绪/占位网格取网格时长（8 拍）；异常
  /// 网格按秒制兜底长度（8 拍 × 0.5s = 4s）。返回毫秒。
  int _resolveFragmentCreateWidth() => _eightBeatWidthMs();

  /// 「一个八拍默认宽」（共享 helper，随备注插入收口一处）：读
  /// **八拍标称**——异常态由哨兵算术自然得 4s，无特例支。退化守卫
  /// 留在调用点：实算宽 ≤ 0 时回落秒制兜底八拍
  ///（[secondsFallbackEightBeat] = 4s，哨兵算术唯一出处）。返回毫秒。
  /// 局部镜像创建与备注插入共用。
  int _eightBeatWidthMs() {
    final grid = _ref.read(beatGridProvider);
    final width = grid.eightBeatNominal.inMilliseconds;
    return width <= 0 ? secondsFallbackEightBeat.inMilliseconds : width;
  }

  /// 纯函数分发（switch over sealed）：只计算不写入；新增编辑操作 = 新
  /// 子类 + 此处一个 case。
  _EditPlan _plan(AnnotationEdit edit) {
    switch (edit) {
      case AddSegmentLine(:final at):
        // 提交时模块内落点解析（就近八拍点 + 合法域）；解析
        // 不成立 = 空 plan → 快照相等 → EditNoop 静默。
        final landing = _resolveSegmentLineLanding(at);
        if (landing == null) return _EditPlan();
        final next = timeline_ops.addSegmentLine(_timeline, landing);
        final insertedLineIndex = next.segmentLines.indexWhere(
          (line) => line.position == landing,
        );
        final plan = _EditPlan()..timeline = next;
        plan.mastery = splitLearningMasteryOnSegmentLineAdded(
          _mastery,
          insertedLineIndex,
        );
        plan.emphasis = splitLearningEmphasisOnSegmentLineAdded(
          _emphasis,
          insertedLineIndex,
        );
        // 被切段的前后两新段均继承原段逐段档，后续段序后移。
        plan.segmentDensities = splitSegmentDensitiesOnSegmentLineAdded(
          _segmentDensities,
          insertedLineIndex,
        );
        return plan;
      case RemoveSegmentLine(:final index):
        final next = timeline_ops.removeSegmentLine(_timeline, index);
        return _EditPlan()
          ..timeline = next
          ..selectionOp = _selectionDomain.clear
          ..mastery = mergeLearningMasteryOnSegmentLineRemoved(_mastery, index)
          ..emphasis = mergeLearningEmphasisOnSegmentLineRemoved(
            _emphasis,
            index,
          )
          // 融合段取相邻两段绝对值最大的逐段档，后续段序前移。
          ..segmentDensities = mergeSegmentDensitiesOnSegmentLineRemoved(
            _segmentDensities,
            index,
          );
      case MoveSegmentLine(:final index, :final to):
        // 同加线族，提交时落点解析；解析不成立 = EditNoop。
        final moveLanding = _resolveSegmentLineLanding(to);
        if (moveLanding == null) return _EditPlan();
        return _EditPlan()
          ..timeline = timeline_ops.moveSegmentLine(
            _timeline,
            index,
            moveLanding,
          );
      case AddHalfBeatLine(:final at):
        // 提交时模块内落点解析（就近半拍格点 + 合法域）；解析
        // 不成立 = 空 plan → 快照相等 → EditNoop 静默。半拍线不参与学习段
        // 几何派生：无段序键属性级联、不清激活/临时段（geometryChanged 只
        // 看分段线位置集合，半拍线变化天然不计入）。
        final halfBeatLanding = _resolveHalfBeatLineLanding(at);
        if (halfBeatLanding == null) return _EditPlan();
        return _EditPlan()
          ..timeline = timeline_ops.addHalfBeatLine(_timeline, halfBeatLanding);
      case MoveHalfBeatLine(:final index, :final to):
        // 同加线族，提交时落点解析（步进原始目标解析幂等）；
        // 解析不成立或触邻线钳制丢弃 = EditNoop。
        final halfBeatMoveLanding = _resolveHalfBeatLineLanding(to);
        if (halfBeatMoveLanding == null) return _EditPlan();
        return _EditPlan()
          ..timeline = timeline_ops.moveHalfBeatLine(
            _timeline,
            index,
            halfBeatMoveLanding,
          );
      case RemoveHalfBeatLine(:final index):
        // 半拍线删除：一次标注编辑、删后整体清选中；无段序键
        // 属性级联（同 Add/Move 半拍线族）。
        return _EditPlan()
          ..timeline = timeline_ops.removeHalfBeatLine(_timeline, index)
          ..selectionOp = _selectionDomain.clear;
      case SetVideoRange(:final start, :final end):
        // 提交时模块内落点解析（覆盖区内吸最近真实拍点、覆盖
        // 外/异常态自由）；合法域 = 可拖范围与归一化钳制，由 setVideoRange
        // 纯函数收口（端标即区间边界，不适用分段线开区间触界检查）。
        final next = timeline_ops.setVideoRange(
          _timeline,
          start: start == null ? null : _resolveRangeBoundaryLanding(start),
          end: end == null ? null : _resolveRangeBoundaryLanding(end),
        );
        if (next == _timeline) return _EditPlan();
        final orderMapping = rangeChangedLearningSegmentOrderMapping(
          _timeline,
          next,
        );
        final plan = _EditPlan()..timeline = next;
        plan.mastery = remapLearningSegmentOrders(_mastery, orderMapping);
        plan.emphasis = remapLearningSegmentEmphasis(_emphasis, orderMapping);
        // 段内档沿用同一段序映射（映射外的旧值 = 被裁掉的段丢弃）。
        plan.segmentDensities = remapLearningSegmentOrders(
          _segmentDensities,
          orderMapping,
        );
        return plan;
      case ToggleSegmentFlag(:final index):
        return _EditPlan()
          ..timeline = timeline_ops.toggleSegmentLineFlag(_timeline, index);
      case SetSegmentMastery(:final order, :final mastery):
        return _EditPlan()
          ..mastery = withLearningSegmentMastery(_mastery, order, mastery);
      case AutoSegment(:final start, :final end, :final cuts):
        // 分段被整体替换，段序键属性（熟练度/重点）按旧新
        // 分区的**时间重叠**就地重写（规则在纯件 [rebakeLearningSegment
        // Attributes] 里钉一次）；撤销按快照一步还原线与属性。
        final next = timeline_ops.applyAutoSegment(
          _timeline,
          start: start,
          end: end,
          cuts: cuts,
        );
        final rebaked = rebakeLearningSegmentAttributes(
          oldTimeline: _timeline,
          newTimeline: next,
          mastery: _mastery,
          emphasis: _emphasis,
        );
        return _EditPlan()
          ..timeline = next
          ..selectionOp = _selectionDomain.clear
          ..mastery = rebaked.mastery
          ..emphasis = rebaked.emphasis
          // 段内档按同一旧新分区的时间重叠重烘焙（相交旧段取绝对
          // 值最大档、方向并列取更快；不相交丢弃；切碎各继承）。
          ..segmentDensities = rebakeSegmentDensities(
            oldTimeline: _timeline,
            newTimeline: next,
            densities: _segmentDensities,
          );
      case ApplyBeatShift(:final delta, :final shiftSeconds):
        // 线整体平移差值 + beat 段平移量写定，同一次提交（快照
        // 携带平移量，一步撤销同时回退）。
        return _EditPlan()
          ..timeline = timeline_ops.shiftBeatAlignment(_timeline, delta)
          ..beatShift = shiftSeconds;
      case ApplyBeatDensity(:final density):
        // 倍频写定 + 八拍锚点就地烘焙，同一次提交（快照携带
        // 两者，一步撤销同时回退）；烘焙规则见 core 的
        // [rebakeEightBeatAnchors]。不改平移量、不动任何线的时刻；同档
        // 应用 = 快照相等 → EditNoop 静默。
        final doc = _ref.read(beatTrackStateProvider).grid;
        if (doc == null) return _EditPlan();
        return _EditPlan()
          ..beatDensity = density
          ..eightBeatAnchors = rebakeEightBeatAnchors(
            beats: doc.beats,
            fromDensity: doc.density,
            toDensity: density,
            anchors: _eightBeatAnchors,
          );
      case AddEightBeatAnchor(:final at):
        // 提交时模块内落点解析（最近强拍，非就绪/无强拍 = 空
        // plan → EditNoop）；锚点集合升序去重后写定。不改任何线的几何。
        final anchorIndex = _resolveDownbeatBeatIndex(at);
        if (anchorIndex == null) return _EditPlan();
        return _EditPlan()
          ..eightBeatAnchors = ({..._eightBeatAnchors, anchorIndex}.toList()
            ..sort());
      case RemoveEightBeatAnchor(:final at):
        // 与落锚同一谓词——落点解析出的强拍序号不在集合内 = 空
        // plan → EditNoop（预览位置无锚点）；在集合内则删该项、其余保持。
        final downbeatIndex = _resolveDownbeatBeatIndex(at);
        if (downbeatIndex == null) return _EditPlan();
        if (!_eightBeatAnchors.contains(downbeatIndex)) return _EditPlan();
        return _EditPlan()
          ..eightBeatAnchors = [
            for (final anchor in _eightBeatAnchors)
              if (anchor != downbeatIndex) anchor,
          ];
      case ClearEightBeatAnchors():
        // 清空全部锚点（空集合 = 空 plan → EditNoop，UI 侧置灰）。
        if (_eightBeatAnchors.isEmpty) return _EditPlan();
        return _EditPlan()..eightBeatAnchors = const [];
      case ClearSegmentLines():
        // 清空分段是显式丢弃分段的动作，熟练度/重点照旧重置为缺省
        // （与自动分段的按几何重写区分）。
        return _EditPlan()
          ..timeline = timeline_ops.clearSegmentLines(_timeline)
          ..selectionOp = _selectionDomain.clear
          ..mastery = const {}
          ..emphasis = const {}
          // 清空分段是显式丢弃分段的动作，段内档一并清空。
          ..segmentDensities = const {};
      case ToggleSegmentEmphasis(:final order):
        return _EditPlan()
          ..emphasis = toggleLearningSegmentEmphasis(_emphasis, order);
      case SetSelectedSegmentsMastery(:final mastery):
        // 熟练度一次作用在全部选中段上——提交时读选中集合，空选中
        // = 空 plan → EditNoop；一个 diff、一步撤销。
        final selected = _selectedSegmentOrders();
        if (selected.isEmpty) return _EditPlan();
        return _EditPlan()
          ..mastery = withLearningSegmentsMastery(_mastery, selected, mastery);
      case ToggleSelectedSegmentsEmphasis():
        // 重点一次作用在全部选中段上——全有星则全部取消、否则全部
        // 点亮；一个 diff、一步撤销；空选中 = 空 plan → EditNoop。
        final selected = _selectedSegmentOrders();
        if (selected.isEmpty) return _EditPlan();
        return _EditPlan()
          ..emphasis = toggleLearningSegmentsEmphasis(_emphasis, selected);
      case SetSelectedSegmentsDensity(:final density):
        // 段内档一次赋值在全部选中段上（与
        // 熟练度、重点同一作用对象与同一提交路径）——空选中 = 空 plan →
        // EditNoop；选中的段全是该档 = 空 plan（按下无变化仍可点）；
        // 一个 diff、一步撤销。
        final selected = _selectedSegmentOrders();
        if (selected.isEmpty) return _EditPlan();
        return _EditPlan()
          ..segmentDensities = withLearningSegmentsDensity(
            _segmentDensities,
            selected,
            density,
          );
      case InsertNote(:final at):
        // 插入落点解析收在纯件 [resolveNoteInsertion]（钳制 → 占用不建 →
        // 自由区间内拍点吸附 → 向尾与右邻截断 + 左邻几何初值）；不建 =
        // 空 plan → 快照相等 → EditNoop 静默。
        final created = _resolveNoteInsert(at);
        if (created == null) return _EditPlan();
        final notes = _notes;
        final index = spanInsertionIndex(_noteSpans, created.startMs);
        return _EditPlan()
          ..notes = [...notes.sublist(0, index), created, ...notes.sublist(index)];
      case SetNoteText(:final index, :final text):
        // 载荷 = 纯文本本身，写定即完成（不解析点名、
        // 不读名册、不存引用）；索引越界抛 RangeError（与其它按索引
        // verb 一致）；同文本 = 空 plan → 快照相等 → EditNoop 静默。
        _checkNoteIndex(index);
        final updated = List.of(_notes);
        updated[index] = updated[index].copyWith(text: text);
        return _EditPlan()..notes = updated;
      case MoveNote(:final index, :final to):
        // 整体移：宽度不变平移；落点解析（拍点级，见
        // [_resolveFragmentEdgeLanding]）后与相邻备注 + 首尾互斥钳制，钳空
        // = 空 plan → EditNoop（拖动静默停住）。
        return _planNoteMove(index, to);
      case DragNoteEdge(:final index, :final edge, :final to):
        // 端点拖：改起止、不得倒置；落点解析同整体移，互斥钳制后
        // 越位/钳空 = 空 plan → EditNoop。
        return _planNoteDragEdge(index, edge, to);
      case SetNoteGeometry(:final index, :final geometry):
        // 贴纸几何：请求几何模块内单点钳制（[clampNoteGeometry]）；
        // 钳后同值 = 空 plan → 快照相等 → EditNoop 静默。
        return _planNoteGeometry(index, geometry);
      case ToggleNoteLock(:final index):
        // 内容锁开关取反；越界抛 RangeError；豁免两把锁，其余
        // 字段原样携带。
        _checkNoteIndex(index);
        final toggled = List.of(_notes);
        toggled[index] = toggled[index].copyWith(locked: !toggled[index].locked);
        return _EditPlan()..notes = toggled;
      case RemoveNote(:final index):
        // 删除整条备注；越界抛 RangeError；撤销即恢复。
        _checkNoteIndex(index);
        final remaining = List.of(_notes)..removeAt(index);
        return _EditPlan()
          ..notes = remaining
          // 删除后清选中（与 [RemoveLocalMirrorFragment] 同一语义）：原选中
          // 索引已无意义，只按索引越界判定的话它会在删掉中间那条时"顺手"
          // 指到下一条上——选中框 / 内容浮条 / 端点柄跟着搬到没被选过的
          // 备注上。删末位恰好越界变 null，不能靠这点巧合。
          ..selectionOp = _selectionDomain.clear;
      case AddLocalMirrorFragment(:final at):
        // 创建：模块内落点解析（起点吸八拍点/占位同级派生、异常自由）
        // + 默认宽一个八拍；自动钳入首尾并截断防重叠；创建即启用。
        return _planFragmentCreate(at);
      case RemoveLocalMirrorFragment(:final index):
        final fragments = _checkedFragmentList(index);
        fragments.removeAt(index);
        return _EditPlan()
          ..localMirrorFragments = fragments
          // 删除命令后清选中（同分段线/半拍线删除的整清语义，删除后
          // 原选中索引已无意义——派生视图越界亦失效，此处显式整清兜一致）。
          ..selectionOp = _selectionDomain.clear;
      case MoveLocalMirrorFragment(:final index, :final to):
        // 整体移：保留原宽平移；起点落点解析后与相邻片段 + 首尾互斥
        // 钳制，钳空 = 空 plan → EditNoop。
        return _planFragmentMove(index, to);
      case DragLocalMirrorFragmentEdge(:final index, :final edge, :final to):
        // 端点拖：端点吸附（就绪真实拍/占位派生/异常自由）后与相邻
        // 片段 + 首尾互斥钳制；越位/钳空 = EditNoop。
        return _planFragmentDragEdge(index, edge, to);
      case TrimPracticeClip(:final clipId, :final edge, :final to):
        // 端点截取；按片段 id 寻址：先按 id 回查当前表（查无
        // = 空 plan → EditNoop 静默，不入史不入盘），再吸附 + 素材内钳制 +
        // 有效练习区间约束；倒置/无净变化 = EditNoop。只改引用范围（素材
        // 内 in/out），素材不动。
        final trimIndex = _clipIndexById(clipId);
        if (trimIndex == null) return _EditPlan();
        final offset = _resolveClipTrimOffsetMs(trimIndex, edge, to);
        if (offset == null) return _EditPlan();
        final clip = _practiceClips[trimIndex];
        final nextClips = [
          for (var i = 0; i < _practiceClips.length; i++)
            i == trimIndex
                ? clip.trim(
                    inMs: edge == IntervalEdge.start ? offset : clip.inMs,
                    outMs: edge == IntervalEdge.start ? clip.outMs : offset,
                  )
                : _practiceClips[i],
        ];
        return _EditPlan()..practiceClips = nextClips;
      case RemovePracticeClip(:final clipId):
        // 只把片段移出练习视频轨（素材文件与库内条目不动），一次
        // 撤销可回退；按片段 id 寻址（查无 = 空 plan → EditNoop
        // 静默）；删除后清标注选中（与局部镜像片段删除同语义）。
        final removeIndex = _clipIndexById(clipId);
        if (removeIndex == null) return _EditPlan();
        final remaining = [..._practiceClips]..removeAt(removeIndex);
        return _EditPlan()
          ..practiceClips = remaining
          ..selectionOp = _selectionDomain.clear;
    }
  }

  /// 创建 plan：起点落点 + 默认宽，钳入首尾并截断防重叠。
  _EditPlan _planFragmentCreate(Duration at) {
    final current = _localMirrorFragments;
    final timeline = _timeline;
    final rangeStartMs = timeline.rangeStart.inMilliseconds;
    final rangeEndMs = timeline.rangeEnd.inMilliseconds;
    final startMs = _resolveFragmentStart(at);
    final widthMs = _resolveFragmentCreateWidth();
    final created = placeFragmentCreation(
      fragments: current,
      rangeStartMs: rangeStartMs,
      rangeEndMs: rangeEndMs,
      startMs: startMs,
      widthMs: widthMs,
    );
    if (created == null) return _EditPlan();
    return _EditPlan()
      ..localMirrorFragments =
          insertFragmentKeepingInvariant(current, created);
  }

  /// 整体移 plan：保留原宽平移 + 互斥钳制；钳空返回空 plan（EditNoop）。
  ///
  /// 起点落点 = 端点同级吸附（[_resolveFragmentEdgeLanding]：就绪真实拍/占位均匀
  /// 派生/异常自由），与端点拖同一 boundary 网格——片段经端点编辑后其边界是
  /// 真实拍点，整体移若复用创建八拍点会把它静默拉回八拍相位、改变片段偏移；
  /// 故平移起点按真实拍 boundary 落点（只钉创建/端点，
  /// 整体移取与端点一致的网格是内部一致的取舍）。
  _EditPlan _planFragmentMove(int index, Duration to) {
    _checkedFragmentList(index);
    final timeline = _timeline;
    final rangeStartMs = timeline.rangeStart.inMilliseconds;
    final rangeEndMs = timeline.rangeEnd.inMilliseconds;
    final startMs = _resolveFragmentEdgeLanding(to).inMilliseconds;
    final moved = moveFragmentClamped(
      fragments: _localMirrorFragments,
      index: index,
      rangeStartMs: rangeStartMs,
      rangeEndMs: rangeEndMs,
      newStartMs: startMs,
    );
    if (moved == null) return _EditPlan(); // 钳空 drop
    final fragments = List.of(_localMirrorFragments);
    fragments[index] = moved;
    return _EditPlan()..localMirrorFragments = fragments;
  }

  /// 端点拖 plan：端点吸附 + 互斥钳制；越位/钳空返回空 plan。
  _EditPlan _planFragmentDragEdge(
    int index,
    IntervalEdge edge,
    Duration to,
  ) {
    _checkedFragmentList(index);
    final timeline = _timeline;
    final rangeStartMs = timeline.rangeStart.inMilliseconds;
    final rangeEndMs = timeline.rangeEnd.inMilliseconds;
    final edgeMs = _resolveFragmentEdgeLanding(to).inMilliseconds;
    final dragged = dragFragmentEdgeClamped(
      fragments: _localMirrorFragments,
      index: index,
      edge: edge,
      rangeStartMs: rangeStartMs,
      rangeEndMs: rangeEndMs,
      edgeMs: edgeMs,
    );
    if (dragged == null) return _EditPlan(); // 越位/钳空 drop
    final fragments = List.of(_localMirrorFragments);
    fragments[index] = dragged;
    return _EditPlan()..localMirrorFragments = fragments;
  }

  /// 以可变副本返回局部镜像片段列表并对 [index] 做越界守卫（越界抛
  /// [RangeError]，与其它按索引 verb 一致）。
  List<LocalMirrorFragment> _checkedFragmentList(int index) {
    final fragments = List.of(_localMirrorFragments);
    if (index < 0 || index >= fragments.length) {
      throw RangeError.range(
        index,
        0,
        fragments.length - 1,
        'index',
        '局部镜像片段索引越界',
      );
    }
    return fragments;
  }

  /// 自动分段：由就绪节拍网格派生首末拍与**每段
  /// [fullIntervalsPerSegment] 个整八拍区间**的切割线，作为一次标注编辑
  /// 提交（自动首尾 + 顺延下刀、半八拍并入本段、尾部并入、收在尾线）。
  /// 网格无拍点抛 [StateError]（调用方须先判就绪）。
  EditOutcome submitAutoSegment(
    marker_doc.BeatGrid grid, {
    required int fullIntervalsPerSegment,
  }) {
    // 锁门禁先于就绪判定（门禁次序 = 锁 → 就绪网格 → 落点）。
    if (_layoutLocked) return _lockedReject();
    if (grid.beats.isEmpty) {
      throw StateError('自动分段要求网格含拍点');
    }
    // 消费平移后网格（单一来源 = [DocumentBeatGrid] 派生，网格拍点 +
    // 平移量）——应用平移后再自动分段，按平移后相位落线（首线 = 平移后
    // 网格首拍、末拍同理）。末拍序号取**派生网格**自己的末拍：倍频后派生
    // 拍数 ≠ 文档拍数（×2 时约两倍），按文档拍数索引会落在曲中。
    final derived = DocumentBeatGrid(
      beats: grid.beats,
      shift: grid.shift,
      density: grid.density,
    );
    final lastIndex = derived.lastBeatIndex;
    // 切割线口径 = 每段 4 个整八拍区间，派生输入是相位对象（按拍序号
    // 等距切片无法表达半八拍）。相位就地从
    // **传入文档的派生网格**求值、不读 beatPhaseProvider：后者按读取侧语义
    // 叠加「节拍对齐预览偏移」，而本入口的首/尾线与切割线都落在传入文档的
    // 时刻上——两处必须同源（同一份平移 + 同一份锚点），否则对齐气泡预览中
    // 一键自动分段会按预览相位落出与首尾线不同源的刀位。
    final cuts = deriveAutoSegmentCuts(
      phase: BeatPhase(grid: derived, anchors: grid.anchors),
      startLine: derived.beatTime(0),
      endLine: derived.beatTime(lastIndex),
      fullIntervalsPerSegment: fullIntervalsPerSegment,
    );
    return submit(
      AutoSegment(
        start: derived.beatTime(0),
        end: derived.beatTime(lastIndex),
        cuts: cuts,
      ),
    );
  }

  /// 节拍对齐应用：把分段线/半拍线/首尾线的绝对时间整体平移
  /// 「[previewOffsetSeconds] − 上次已应用偏移」的差值，同时把公开 beat
  /// 段平移量写定为预览值；整次应用 = 一次标注
  /// 编辑（一步撤销同时回退两者）。越界按 0..total 钳制、归一化不变式
  /// 由既有归一化保证。网格非就绪抛 [StateError]（占位/异常不适用，
  /// 调用方须先判就绪置灰）。
  EditOutcome submitBeatShift(double previewOffsetSeconds) {
    // 节拍对齐不受锁定分段（锁只护分段结构）；就绪门仍先判。
    // 就绪门读可用性谓词：派生格真实拍点可用才适用；
    // 写定仍按原始文档（shift 落盘语义不动）。
    if (!_ref.read(beatGridProvider).hasRealBeats) {
      throw StateError('节拍对齐应用要求真实网格就绪');
    }
    final grid = _ref.read(beatTrackStateProvider).grid!;
    final delta = durationFromSeconds(previewOffsetSeconds - grid.shift);
    final outcome = submit(
      ApplyBeatShift(delta: delta, shiftSeconds: previewOffsetSeconds),
    );
    if (outcome.applied) {
      // 应用即提交：预览值已写定进 beat 段，预览态随之清空（派生网格改
      // 消费已应用平移量，值不变）。本入口只在使用者点「应用」时被调用，
      // 「退出面板/切视频不自动应用、预览即弃」语义不变。
      _ref.read(beatAlignPreviewOffsetProvider.notifier).set(null);
    }
    return outcome;
  }

  /// 节拍倍频应用：把公开 beat 段倍频写定为
  /// [density]，同时把八拍锚点序号按新档就地烘焙；整次应用 = 一次标注
  /// 编辑。门禁次序与 [submitBeatShift] 同族（锁 → 就绪网格，非就绪抛
  /// [StateError]）。
  EditOutcome submitBeatDensity(double density) {
    // 节拍倍频不受锁定分段；就绪门仍先判。
    if (!_ref.read(beatGridProvider).hasRealBeats) {
      throw StateError('节拍倍频应用要求真实网格就绪');
    }
    return submit(ApplyBeatDensity(density: density));
  }

  // ── 拖动会话 ──

  /// 分段线拖动会话：校验（索引越界 RangeError）→ 选中该线 → 开事务；
  /// 契约见库头「拖动会话协议」。
  DurationDragSession beginLineDrag(int index) {
    final lineCount = _timeline.segmentLines.length;
    if (index < 0 || index >= lineCount) {
      throw RangeError.range(index, 0, lineCount - 1, 'index', '分段线索引越界');
    }
    _endSession();
    _selectionDomain.select(SegmentLineSelection(index));
    return _openDragSession(
      (target) => MoveSegmentLine(index: index, to: target),
      () => _timeline.segmentLines[index].position,
    );
  }

  /// 半拍线拖动会话：校验（索引越界 RangeError）→ 开事务（不选中——
  /// 半拍线不参与分段线/学习段选中体系）；契约见库头「拖动会话协议」。
  DurationDragSession beginHalfBeatDrag(int index) {
    final lineCount = _timeline.halfBeatLines.length;
    if (index < 0 || index >= lineCount) {
      throw RangeError.range(index, 0, lineCount - 1, 'index', '半拍线索引越界');
    }
    _endSession();
    return _openDragSession(
      (target) => MoveHalfBeatLine(index: index, to: target),
      () => _timeline.halfBeatLines[index].position,
    );
  }

  /// 首/尾线端标拖动会话：选中该端标（无索引可校验）→ 开事务；契约见
  /// 库头「拖动会话协议」。
  DurationDragSession beginRangeDrag(VideoRangeBoundary boundary) {
    _endSession();
    _selectionDomain.select(VideoRangeBoundarySelection(boundary));
    return _openDragSession(
      (target) => boundary == VideoRangeBoundary.start
          ? SetVideoRange(start: target)
          : SetVideoRange(end: target),
      () => boundary == VideoRangeBoundary.start
          ? _timeline.rangeStart
          : _timeline.rangeEnd,
    );
  }

  /// 局部镜像片段**整体移**拖动会话：校验（共享片段列表检查）→ 选中该
  /// 片段 → 开事务；契约见库头「拖动会话协议」。
  DurationDragSession beginLocalMirrorMoveDrag(int index) {
    _checkedFragmentList(index);
    _endSession();
    _selectionDomain.select(LocalMirrorFragmentSelection(index));
    return _openDragSession(
      (target) => MoveLocalMirrorFragment(index: index, to: target),
      () => Duration(milliseconds: _localMirrorFragments[index].startMs),
    );
  }

  /// 局部镜像片段**端点拖**拖动会话：校验（共享片段列表检查）→ 选中该
  /// 片段 → 开事务；契约见库头「拖动会话协议」。
  DurationDragSession beginLocalMirrorEdgeDrag(
    int index,
    IntervalEdge edge,
  ) {
    _checkedFragmentList(index);
    _endSession();
    _selectionDomain.select(LocalMirrorFragmentSelection(index));
    return _openDragSession(
      (target) =>
          DragLocalMirrorFragmentEdge(index: index, edge: edge, to: target),
      () => Duration(
        milliseconds: edge == IntervalEdge.start
            ? _localMirrorFragments[index].startMs
            : _localMirrorFragments[index].endMs,
      ),
    );
  }

  /// 备注片段**整体移**拖动会话（第 6 个拖动会话族）：校验（备注
  /// 列表检查）→ 开事务（备注无选中槽，不选中）；契约见库头「拖动会话
  /// 协议」。
  DurationDragSession beginNoteMoveDrag(int index) {
    _checkedNoteList(index);
    _endSession();
    return _openDragSession(
      (target) => MoveNote(index: index, to: target),
      () => Duration(milliseconds: _notes[index].startMs),
    );
  }

  /// 备注片段**端点拖**拖动会话（第 7 个拖动会话族）：校验（备注
  /// 列表检查）→ 开事务；契约见库头「拖动会话协议」。
  DurationDragSession beginNoteEdgeDrag(
    int index,
    IntervalEdge edge,
  ) {
    _checkedNoteList(index);
    _endSession();
    return _openDragSession(
      (target) => DragNoteEdge(index: index, edge: edge, to: target),
      () => Duration(
        milliseconds: edge == IntervalEdge.start
            ? _notes[index].startMs
            : _notes[index].endMs,
      ),
    );
  }

  /// 贴纸几何拖动会话（第 8 个拖动会话族）：校验（备注列表检查）
  /// → 开事务（贴纸几何手势只在选中态起手，选中由浮层注册表持有，此处
  /// 不选中）；请求 = 像素 → 归一化换算后的请求几何（换算单点在会话消费
  /// 方），模块内单点钳制；契约见库头「拖动会话协议」。
  AnnotationDragSession<NoteGeometry, NoteGeometry> beginNoteGeometryDrag(
    int index,
  ) {
    _checkedNoteList(index);
    _endSession();
    return _openDragSession(
      (target) => SetNoteGeometry(index: index, geometry: target),
      () => _notes[index].geometry,
    );
  }

  /// 练习片段**端点截取**拖动会话（第 9 个拖动会话族）：校验（片段
  /// 列表检查）→ 开事务（不选中——截取不改选中语义）；契约见库头「拖动
  /// 会话协议」。落点读回 = 被拖端点的写后源时间位置。
  ///
  /// 起手按渲染下标定位（下标只留在渲染内部），会话记**片段 id**——逐帧
  /// 提交与落点读回都按 id 回查当前表：起手之后外部写移动了下标，
  /// 作用对象仍是起手的那条；该 id 被外部删除后逐帧静默、收口不入史。
  DurationDragSession beginPracticeClipTrimDrag(int index, IntervalEdge edge) {
    _checkedClipList(index);
    final clipId = _practiceClips[index].id;
    _endSession();
    return _openDragSession(
      (target) => TrimPracticeClip(clipId: clipId, edge: edge, to: target),
      () {
        // 仅在 verb applied 后被读（拖动会话协议：无净变化不读落点），
        // applied 蕴含该 id 仍在当前表——查无不必达成协议，故不设 orElse。
        final clip = _practiceClips.firstWhere(
          (candidate) => candidate.id == clipId,
        );
        return Duration(
          milliseconds: edge == IntervalEdge.start
              ? clip.sourceStartMs
              : clip.sourceEndMs,
        );
      },
    );
  }

  /// 练习片段索引越界守卫（越界抛 [RangeError]，与其它按索引 verb 一致）。
  void _checkedClipList(int index) {
    final count = _practiceClips.length;
    if (index < 0 || index >= count) {
      throw RangeError.range(index, 0, count - 1, 'index', '练习片段索引越界');
    }
  }

  /// 按片段 id 回查当前表下标：截取 / 删除 executor 与拖动读回
  /// 共用的唯一查表缝；查无返回 null，由调用方落各自的「查无 = 静默」口径。
  int? _clipIndexById(String clipId) {
    final index = _practiceClips.indexWhere((clip) => clip.id == clipId);
    return index < 0 ? null : index;
  }

  /// 练习片段端点截取落点解析：请求位置（源时间轴）→ 素材内偏移
  /// → 吸附纯件 [snapTrimOffsetMs]（就绪网格吸就近八拍点、异常网格自由；
  /// 经相位对象求值，钳在素材内 `[0, materialDurationBoundMs]`）→ 有效
  /// 练习区间约束（源时间钳在 `[rangeStart, rangeEnd]`）→ 端点不倒置与
  /// 同值检查。不成立（倒置/无净变化/越界）返回 null = EditNoop 静默。
  int? _resolveClipTrimOffsetMs(int index, IntervalEdge edge, Duration to) {
    _checkedClipList(index);
    final clip = _practiceClips[index];
    final rawOffset = to.inMilliseconds - clip.materialSourceStartMs;
    // 异常态吸附停用（与半拍线落点同口径，[isSecondsFallback] 
    // 收口）：请求位置原样直通；其余经吸附纯件（就绪网格吸就近八拍点、
    // 占位派生同级、异常不达此处）。
    final offset = _ref.read(beatGridProvider).isSecondsFallback
        ? rawOffset
        : snapTrimOffsetMs(
            offsetInMaterialMs: rawOffset,
            materialSourceStartMs: clip.materialSourceStartMs,
            materialDurationMs: clip.materialDurationBoundMs,
            phase: _ref.read(beatPhaseProvider),
          );
    // 有效练习区间约束（首尾线在对比态不渲染但照常生效）：源时间钳进
    // `[rangeStart, rangeEnd]` 后换算回素材内偏移。
    final timeline = _timeline;
    final rangeStartOffset =
        timeline.rangeStart.inMilliseconds - clip.materialSourceStartMs;
    final rangeEndOffset =
        timeline.rangeEnd.inMilliseconds - clip.materialSourceStartMs;
    final lo = rangeStartOffset < 0 ? 0 : rangeStartOffset;
    var hi = clip.materialDurationBoundMs;
    if (rangeEndOffset < hi) hi = rangeEndOffset;
    if (hi < lo) return null; // 有效区间与素材无交：无可放置端点。
    final clamped = offset.clamp(lo, hi).toInt();
    final current = edge == IntervalEdge.start ? clip.inMs : clip.outMs;
    final other = edge == IntervalEdge.start ? clip.outMs : clip.inMs;
    // 端点不倒置（拖过对端 = no-op）；同值无净变化。
    final isInverted = edge == IntervalEdge.start ? clamped >= other : clamped <= other;
    if (isInverted || clamped == current) return null;
    return clamped;
  }

  /// 开拖动事务并返回会话（各具名工厂的共用尾巴）：生成会话令牌（唯一
  /// 性结构保证）→ 捕获事务起点 → 注入本族两条必填适配器（命令 + 落点
  /// 读回，漏声明即编译错）。
  AnnotationDragSession<Target, Landing> _openDragSession<Target extends Object,
      Landing extends Object>(
    AnnotationEdit Function(Target target) command,
    Landing Function() readLanding,
  ) {
    final token = Object();
    _sessionToken = token;
    _transactionStart = _capture();
    return AnnotationDragSession._(this, token, command, readLanding);
  }

  /// 收口进行中的会话（幂等）：经收口 seam [_commit] 一次收口——折叠
  /// 事务起点与终态的段级 diff，净变化才记一条历史 + 入队一次保存
  /// （拖动中间态不入史不入队，begin/收口各捕获一次快照）。
  void _endSession() {
    if (!_sessionOpen) return;
    _sessionToken = null;
    final start = _transactionStart;
    _transactionStart = null;
    if (start != null) _commit(start, _capture());
  }

  // ── 撤销/重做/复位 ──

  /// 撤销一步：内部先清选中；回放按同一几何 diff 规则清除激活/临时段
  /// （清除不入史）；无历史 no-op；undo 前先收口悬挂会话（会话态由模块
  /// 唯一表达，不防御历史模型侧 pending）。回放后经收口
  /// seam [_commit] 同一折叠与保存入口入队（不记史、after 单次捕获）。
  void undo() => _replayHistory(undo: true);

  /// 重做一步：语义同 [undo]。
  void redo() => _replayHistory(undo: false);

  void _replayHistory({required bool undo}) {
    _endSession();
    // 无历史/无可重做 no-op：不清当前状态（含选中）。
    final history = _ref.read(annotationEditHistoryProvider);
    if (undo ? !history.canUndo : !history.canRedo) return;
    _selectionDomain.clear();
    final before = _capture();
    if (undo) {
      _history._undo();
    } else {
      _history._redo();
    }
    final after = _capture();
    if (_geometryChanged(before.annotations, after.annotations)) {
      _clearLoopActivationsOnGeometryChange();
    }
    // 撤销/重做各算一次编辑，效果即时入队落盘（撤销栈本身不落、不入史）。
    _commit(before, after, recordHistory: false);
  }

  /// 换视频/重开视频/初始化兜底共用的全复位：时间线 + 全部属性 + 选中 +
  /// 激活 + 临时段 + 历史清空。
  void resetForVideo(Duration videoDuration) {
    _endSession();
    _selectionDomain.clear();
    _ref.read(beatAlignPreviewOffsetProvider.notifier).set(null);
    // 非保存清：换视频时保存缝可能已指向另一支视频。
    _selectionDomain.resetLearningSegments();
    _ref.read(transitionSegmentProvider.notifier)._clear();
    _ref.read(practiceClipActivationProvider.notifier).reset();
    _ref.read(learningMasteryProvider.notifier)._reset();
    _ref.read(learningEmphasisProvider.notifier)._reset();
    _ref.read(segmentDensitiesProvider.notifier)._reset();
    _ref.read(localMirrorFragmentsProvider.notifier)._reset();
    // 备注 lane：换视频兜底随全复位清空。
    _ref.read(noteStickersProvider.notifier)._reset();
    _ref
        .read(annotationTimelineProvider.notifier)
        ._replace(AnnotationTimeline.wholeVideo(videoDuration));
    _history._clear();
  }

  // ── 非史非存恢复入口──

  /// 打开恢复装载：以预解析载荷一次就位时间线/重点/
  /// 熟练度/激活。非撤销（不入历史）、非保存（不触发保存 diff）、非入史
  /// 装载，不动选中（全复位已清）；激活走恢复语义（「自恢复写入」旗标
  /// 置位，恢复就位不触发跳段首 seek）。
  ///
  /// 三段越界过滤在模块内完成：重点/熟练度/激活按段序挂靠，段数依**入参
  /// 时间线**派生（载荷未带时间线时读当前时间线），语义与恢复编排的
  /// `_orderInRange` 过滤逐项等价（越界段序丢弃、宁丢不挂错段）。markers
  /// 空态/时长未知守卫留在恢复编排——无有效几何不调用本入口。
  void restoreDocument(AnnotationRestoreDocument document) {
    final timeline = document.timeline;
    if (timeline != null) {
      _ref.read(annotationTimelineProvider.notifier)._replace(timeline);
    }
    final segmentCount = deriveLearningSegments(
      timeline ?? _ref.read(annotationTimelineProvider),
    ).length;
    if (document.emphasizedSegments != null) {
      _ref.read(learningEmphasisProvider.notifier)._replace({
        for (final order in document.emphasizedSegments!)
          if (_orderInRange(order, segmentCount)) order,
      });
    }
    if (document.mastery != null) {
      _ref.read(learningMasteryProvider.notifier)._replace({
        for (final entry in document.mastery!.entries)
          if (_orderInRange(entry.key, segmentCount)) entry.key: entry.value,
      });
    }
    if (document.segmentDensities != null) {
      _ref.read(segmentDensitiesProvider.notifier)._replace({
        for (final entry in document.segmentDensities!.entries)
          if (_orderInRange(entry.key, segmentCount)) entry.key: entry.value,
      });
    }
    if (document.activatedSegments != null) {
      // 越界过滤后收紧连续性——只保留含最小段序的那一段连续块
      //（空则视为无选中）；恢复装载为非保存写入，盘上现值即来源。
      _selectionDomain.restoreLearningSegments(
        contiguousBlockFromMin({
          for (final order in document.activatedSegments!)
            if (_orderInRange(order, segmentCount)) order,
        }),
      );
    }
    if (document.localMirrorFragments != null) {
      _ref
          .read(localMirrorFragmentsProvider.notifier)
          ._replace(document.localMirrorFragments!);
    }
    if (document.notes != null) {
      _ref.read(noteStickersProvider.notifier)._restore(document.notes!);
    }
  }

  /// 恢复前清：清激活学习段与临时衔接段，非史
  /// 非存、幂等——替换打开恢复在 async 等待前的私有清（时长未知未走
  /// [resetForVideo] 的兜底路径保留）。
  void clearForVideoRestore() {
    // 非保存清：打开新视频时保存缝尚指向上一支视频，此处入队会把空
    // 激活落进错视频的文件。
    _selectionDomain.resetLearningSegments();
    _ref.read(transitionSegmentProvider.notifier)._clear();
    _ref.read(practiceClipActivationProvider.notifier).reset();
  }

  /// 段序是否落在有效学习段范围内（恢复属性挂靠的越界过滤）。
  static bool _orderInRange(int order, int segmentCount) =>
      order >= 0 && order < segmentCount;

  // ── 封闭会话/点选组（不入史；互斥与清除同属一条写纪律）──

  /// 触发临时衔接段（学习轨行内点击线身）：同线取消、异线/新线激活替换
  /// （±1 八拍、起点八拍点取整、按首尾截断在解析纯函数内）；先清真实激活。
  /// 选中联动一并收口：激活成功选中该线，无效线不激活也不改选中，同线
  /// 取消时若正选中该线则连带清除——widget 只陈述触发意图，互斥与选中
  /// 耦合决策留在模块内。
  void toggleTransitionSegment(int lineIndex) {
    _ref.read(transitionSegmentProvider.notifier)._toggle(_timeline, lineIndex);
    if (_ref.read(transitionSegmentProvider) != null) {
      _selectionDomain.select(SegmentLineSelection(lineIndex));
      return;
    }
    final selection = _ref.read(annotationSelectionProvider);
    if (selection is SegmentLineSelection && selection.index == lineIndex) {
      _selectionDomain.clear();
    }
  }

  // ── 内部：几何 diff 与显式清除 ──

  /// 显式几何 diff：rangeStart/rangeEnd + 分段线位置集合前后相等（忽略
  /// flag/属性/半拍线——半拍线不参与学习段几何派生）。
  bool _geometryChanged(
    MarkerAnnotationsValue before,
    MarkerAnnotationsValue after,
  ) {
    if (before.rangeStart != after.rangeStart) return true;
    if (before.rangeEnd != after.rangeEnd) return true;
    final beforeLines = before.segmentLines;
    final afterLines = after.segmentLines;
    if (beforeLines.length != afterLines.length) return true;
    for (var i = 0; i < beforeLines.length; i++) {
      if (beforeLines[i].position != afterLines[i].position) return true;
    }
    return false;
  }

  /// geometryChanged 时的显式幂等清除：激活学习段/临时衔接段非空才清
  /// （「非空才清」即幂等守卫——会话中每帧几何写入重复到达时为空操作，
  /// 等效于会话内只清首次）。
  void _clearLoopActivationsOnGeometryChange() {
    if (_ref.read(selectedLearningSegmentsProvider).isNotEmpty) {
      _selectionDomain.clearLearningSegments();
    }
    if (_ref.read(transitionSegmentProvider) != null) {
      _ref.read(transitionSegmentProvider.notifier)._clear();
    }
    // 片段激活随几何变化一并清除（激活源单值纪律的清除侧）。读
    // **激活源现值**而非在屏派生（[practiceOnscreenFaceProvider]）——
    // 片段引用悬空时也照清。
    if (_ref.read(practiceClipActivationProvider) != null) {
      _ref.read(practiceClipActivationProvider.notifier)._clear();
    }
  }
}

/// 一次编辑的计算结果（纯数据，未写入）：各字段 null = 该面无变化。
class _EditPlan {
  AnnotationTimeline? timeline;
  Map<int, LearningMastery>? mastery;
  Set<int>? emphasis;

  /// 逐段档全表写终值（仅几何变动级联/清空
  /// verb 设置，其余 verb 保持 null——沿用 before 快照值，节拍倍频/节拍
  /// 对齐因此天然不动段内档）。
  Map<int, double>? segmentDensities;
  void Function()? selectionOp;

  /// 公开 beat 段平移量写定值（秒；节拍对齐应用专用）。
  double? beatShift;

  /// 公开 beat 段节拍倍频写定值（倍频应用专用；null = 本次提交
  /// 不改倍频 lane）。
  double? beatDensity;

  /// 公开 beat 段八拍锚点集合写终值（升序去重；落锚提交专用；
  /// null = 本次提交不改锚点 lane）。
  List<int>? eightBeatAnchors;

  /// 局部镜像片段列表写终值（独立 lane；非 null = 本次提交改片段
  /// lane，经 submit 单一收口 seam 分写 + 折叠入史/入队）。仅片段几何
  /// verb（建/删/整体移/端点拖）设置；属性 verb 保持 null（沿用 before
  /// 快照值）。
  List<LocalMirrorFragment>? localMirrorFragments;

  /// 备注列表写终值（独立 lane；备注插入命令携带）。
  /// 仅备注 verb 设置；其余 verb 保持 null（沿用 before 快照值）。
  List<NoteSticker>? notes;

  /// 练习片段列表写终值（独立 lane；仅端点截取 verb 设置；其余
  /// verb 保持 null（沿用 before 快照值））。
  List<PracticeClip>? practiceClips;
}

/// 打开恢复装载载荷：时间线 +
/// 熟练度 + 重点 + 激活段序；各字段 null = 该面不由本次装载触碰。载荷为
/// 未过滤原值——三段越界过滤由模块内按时间线派生段数完成。
class AnnotationRestoreDocument {
  const AnnotationRestoreDocument({
    this.timeline,
    this.mastery,
    this.emphasizedSegments,
    this.segmentDensities,
    this.activatedSegments,
    this.localMirrorFragments,
    this.notes,
  });

  /// 装载的时间线（null = 沿用当前时间线派生段数，仅就位属性）。
  final AnnotationTimeline? timeline;

  /// 熟练度（段序 → 熟练度，未过滤）。
  final Map<int, LearningMastery>? mastery;

  /// 重点段序集合（未过滤）。
  final Set<int>? emphasizedSegments;

  /// 逐段档表（未过滤；null = 本次装载不触碰
  /// 逐段档 lane）。
  final Map<int, double>? segmentDensities;

  /// 激活段序集合（未过滤；走恢复语义旗标）。
  final Set<int>? activatedSegments;

  /// 局部镜像片段列表（独立 lane；null = 本次装载不触碰片段 lane，
  /// 空列表 = 装载为空——旧文件缺省键读为空）。
  final List<LocalMirrorFragment>? localMirrorFragments;

  /// 备注贴纸列表（独立 lane；null = 本次装载不触碰备注 lane，
  /// 空列表 = 装载为空——旧文件缺省段读为空）。
  final List<NoteSticker>? notes;
}

/// 段级 diff 折叠（模块库唯一权威纯函数）：
/// 把快照前后差异折叠为 [AnnotationSectionDiff]——各段均为**绝对终值**，
/// 未变更的段为 null（`isEmpty` 可判整体无净变化）。保存编排、历史与
/// 撤销/重做支路的净变化判定一律经本函数收口。
///
/// 等价关系：折叠为空 ⇔ 快照相等，无例外条款——
/// 快照按四段持有，不属于任何段的字段（如 `videoDuration`）结构性不
/// 参与判定；等价护栏测试 `annotation_editor_fold_diff_test` 钉死。
AnnotationSectionDiff foldSectionDiff(
  AnnotationEditSnapshot before,
  AnnotationEditSnapshot after,
) =>
    AnnotationSectionDiff(
      corrections: before.corrections == after.corrections
          ? null
          : after.corrections,
      annotations: before.annotations == after.annotations
          ? null
          : after.annotations,
      session: before.session == after.session ? null : after.session,
      notes: _listEquals(before.notes, after.notes) ? null : after.notes,
    );

