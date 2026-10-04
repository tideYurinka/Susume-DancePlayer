/// 选中域模块库：**不入史的选中态**的唯一写面。
///
/// 本库收两族同性质的状态——单值标注点选槽（分段线／半拍线／首尾端标／
/// 局部镜像片段／备注片段互斥选一）与学习段选中会话；两族只共享一条性质：
/// **都不入史**（不参与标注编辑的撤销/重做、不落公开标记文件；学习段选中
/// 落本地文档 `session` 段）。单值槽零外部依赖、不落盘、零门禁。
///
/// 写面 = [AnnotationSelectionDomain]：状态住 provider（消费方与派生读面
/// 继续 `ref.watch`），写口私有、编辑库访问选中一律经域对象。带外派生读面
/// （按现势几何做越界校验的五个视图）留编辑库——它们要读时间线或另两个
/// store，域不反向 import。
///
/// 依赖方向（单向、无环）：本库只依赖 annotation 纯域与 riverpod；**不
/// import 标注编辑库**、不碰容器句柄、不读构建上下文、不带 widget——
/// 可在裸 `ProviderContainer` 下直测。
///
/// 接口形状：单值槽三动词 `select`／`toggle`／`clear` 与几何同位重映射
/// `remapLineSelection`；学习段十条逐帧动词、四条非用户路径写口与 seek 越出
/// 清除、`lastWriteSilent` 读口。跨域后果（清临时衔接段与片段激活、组装
/// `session` 段落盘）经注入的 [AnnotationSelectionWritePort] 两个钩子回到
/// 编辑侧。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/annotation_timeline.dart';
import '../annotation/learning_segments.dart';
import '../annotation/segment_selection.dart';

/// 标注轨道中的点选对象（分段线/半拍线/首尾端标/局部镜像片段/备注片段
/// 互斥；编辑标记的单选槽）。
///
/// 学习段选中是独立值道
///（[selectedLearningSegmentsProvider]），点选这些标记不波及学习段选中
/// 与循环。
sealed class AnnotationSelection {}

/// 视频首/尾边界：首尾线端标选中的目标端。
enum VideoRangeBoundary { start, end }

class VideoRangeBoundarySelection implements AnnotationSelection {
  const VideoRangeBoundarySelection(this.boundary);

  /// 选中的端标（首线或尾线）。
  final VideoRangeBoundary boundary;
}

class SegmentLineSelection implements AnnotationSelection {
  const SegmentLineSelection(this.index);

  /// 升序分段线列表中的索引。
  final int index;
}

/// 点选中的半拍线：与分段线/首尾端标共用「当前选中标记」
/// 单选槽（同一密封点选状态互斥）。
class HalfBeatLineSelection implements AnnotationSelection {
  const HalfBeatLineSelection(this.index);

  /// 升序半拍线列表中的索引。
  final int index;
}

/// 点选中的局部镜像片段：与分段线/半拍线共用「当前选中标记」
/// 单选槽——单击片段 = 只选中（见
/// [AnnotationEditor.tapLocalMirrorFragment]）；选中态驱动底部「删除」
/// 可用。
class LocalMirrorFragmentSelection implements AnnotationSelection {
  const LocalMirrorFragmentSelection(this.index);

  /// 升序片段列表中的索引。
  final int index;
}

/// 点选中的备注片段：与局部镜像片段 / 分段线等共用同一个标注
/// 选中单选槽（同一密封类型互斥免费）——单击 = 选中并在片段上方展开内
/// 容浮条、再单击 = 打开编辑器。选中是编辑期界面态，不持久化。
class NoteFragmentSelection implements AnnotationSelection {
  const NoteFragmentSelection(this.index);

  /// 备注列表中的索引。
  final int index;
}

/// 点选解包辅助：调用侧不再各自写一遍 switch。
extension AnnotationSelectionX on AnnotationSelection? {
  /// 若点选的是分段线，返回其索引，否则 null。
  int? get asSegmentLineIndex => switch (this) {
    SegmentLineSelection(:final index) => index,
    _ => null,
  };

  /// 若点选的是首/尾线端标，返回其端，否则 null。
  VideoRangeBoundary? get asVideoRangeBoundary => switch (this) {
    VideoRangeBoundarySelection(:final boundary) => boundary,
    _ => null,
  };

  /// 若点选的是半拍线，返回其索引，否则 null。
  int? get asHalfBeatLineIndex => switch (this) {
    HalfBeatLineSelection(:final index) => index,
    _ => null,
  };

  /// 若点选的是局部镜像片段，返回其索引，否则 null。
  int? get asLocalMirrorFragmentIndex => switch (this) {
    LocalMirrorFragmentSelection(:final index) => index,
    _ => null,
  };

  /// 若点选的是备注片段，返回其索引，否则 null。
  int? get asNoteFragmentIndex => switch (this) {
    NoteFragmentSelection(:final index) => index,
    _ => null,
  };
}

/// 当前标注点选状态（null = 未选中；纯编辑 UI 态，不落盘）。
///
/// 变更方法 library 私有——唯一写面是同库的 [AnnotationSelectionDomain]，
/// 编辑库只能经域对象动词写入。
class AnnotationSelectionModel extends Notifier<AnnotationSelection?> {
  @override
  AnnotationSelection? build() => null;

  /// 现势点选（域内读取缝；写入面 [_set] 私有）。
  AnnotationSelection? get _current => state;

  /// 写入落点（唯一直写缝；动词的校验与分派在 [AnnotationSelectionDomain]）。
  void _set(AnnotationSelection? value) => state = value;
}

/// 标注点选注入点；轨道与标注工具区共用同一互斥状态。
final annotationSelectionProvider =
    NotifierProvider<AnnotationSelectionModel, AnnotationSelection?>(
      AnnotationSelectionModel.new,
    );

/// 选中域写入端口：跨域后果的唯一
/// 通道，两个钩子。域不持有编辑域的 store、不反向 import 编辑库。
///
/// 次序契约：[beforeUserWrite] 先于状态写入、[persistSelection] 后于状态
/// 写入；净变化判定住域里。
class AnnotationSelectionWritePort {
  const AnnotationSelectionWritePort({
    required this.beforeUserWrite,
    required this.persistSelection,
  });

  /// **写前**钩子：只在用户路径写上触发一次（点击 toggle／只选中／按下即选／
  /// 圈选起手），编辑侧据此清临时衔接段与片段激活。
  final void Function() beforeUserWrite;

  /// **写后**钩子：只在「有净变化才落盘」那一句上触发，带绝对终值（新的选中
  /// 集合），编辑侧据此读熟练度与片段激活现值、组装 `session` 段入队。非保存
  /// 写（复位、恢复装载）与只重发事实的收口（抬起已写过那条、圈选提交）都不
  /// 触发。
  final void Function(Set<int> activatedSegments) persistSelection;
}

/// 选中学习段集合（私密；写入本地文档 `session` 段的
/// `activatedSegments` 字段，跨会话保留）。
///
/// 状态按段序存储。时间线几何变化时**不** build-watch 隐式自清；清除仅由
/// 编辑模块在几何 diff 命中时经域显式触发（幂等、会话内只清首次），换视频
/// 兜底走域对象的 [AnnotationSelectionDomain.resetLearningSegments]。
///
/// 跨域后果（清临时衔接段与片段激活、`session` 段落盘）经域装配时注入的
/// [AnnotationSelectionWritePort] 两个钩子回到编辑侧——本模型自身不读任何
/// 编辑域 provider，也不 import 编辑库。
///
/// 落盘：用户路径的选中变更（点选/步进选中/越出取消/几何清除/临时衔接段
/// 互斥清）经写后钩子入队 `session` 段绝对终值（熟练度取现值组全段，与熟练
/// 度写入路径互不覆盖）；**恢复装载与换视频复位路径不入队**——恢复写入的
/// 就是盘上现值，换视频/恢复前清时保存缝可能已指向另一支视频，写入会把空
/// 选中落进错视频的文件。
class SelectedLearningSegmentsModel extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  /// 选中写公共序列：可选写前钩子（用户路径写触发，清跨域另两源）→ 可选静默
  /// 标志 → 写集合 → 净变化才走写后钩子。所有写点共用同形；[silent] 为 null
  /// 表示本写不动静默标志。
  void _write(
    Set<int> next, {
    required AnnotationSelectionWritePort? port,
    bool? silent,
    bool userWrite = false,
  }) {
    if (silent != null) _lastWriteSilent = silent;
    if (userWrite) port?.beforeUserWrite();
    final previous = state;
    state = next;
    _persistIfChanged(previous, port);
  }

  /// 点击学习段：选中集合的两条改写规则见
  /// [toggleLearningSegmentSelection]。
  ///
  /// 互斥：与临时衔接段共用「单一循环范围」事实——选中任一清除另一
  /// （清跨域另两源收在写前钩子里）。
  void _toggle(
    AnnotationTimeline timeline,
    int order,
    AnnotationSelectionWritePort? port,
  ) {
    final next = toggleLearningSegmentSelection(state, timeline, order);
    _write(next, port: port, silent: false, userWrite: true);
  }

  /// 只选中指定学习段（替换现有选中集合；段序无效时忽略）。
  ///
  /// 步进倍速范围弹窗「只选中当前学习段并启用步进倍速」使用——
  /// 语义是「只选中这一段」而非「切换」：替换既有选中集合。
  void _selectOnly(
    AnnotationTimeline timeline,
    int order,
    AnnotationSelectionWritePort? port,
  ) {
    if (!_inRange(timeline, order)) return;
    _write({order}, port: port, silent: false, userWrite: true);
  }

  /// 取消全部选中并落盘（进度拖出选中范围、模块几何清除、临时段互斥
  /// 等会话内清除）。
  void _clear(AnnotationSelectionWritePort? port) =>
      _write(const {}, port: port, silent: false);

  /// 非保存清（换视频兜底与恢复前清）：保存缝可能已指向另一支视频，
  /// 此处入队会把空选中落进错视频的文件。
  void _reset() {
    _lastWriteSilent = false;
    state = const {};
  }

  /// 打开恢复整组写回：恢复的选中段集合就位（越界段序由恢复方
  /// 过滤）；不触发跳转、不自动播放，循环作用域由派生 provider 就位。
  /// 非保存写入（盘上现值即来源，不入队）。
  ///
  /// 恢复静默标志只在**真的写回选中**（集合非空）时置真——空
  /// 选中集的恢复写回不置，否则点学习段的跳段首 seek 被陈旧标志抑制。
  void _restore(Set<int> orders) {
    _lastWriteSilent = orders.isNotEmpty;
    state = Set.of(orders);
  }

  // ── 按下即选──

  /// 按下会话在场的段序；null = 无按下会话。
  int? _pressOrder;

  /// 按下前的选中快照；null = 本按下未写过（落在已选中的段上，按兵不动）。
  Set<int>? _prePressSelection;

  /// 按下会话是否落地（段序有效且未遭只读拒绝）；无效序不建会话。
  bool get _pressLanded => _pressOrder != null;

  /// 按下即选：按下落在未选中的段上即刻**静默**清空原选中、只选中这一段
  ///（循环范围随之就位；不 seek、不打断播放），快照按下前选中供被接管时
  /// 整片回滚。按下落在已选中的段上按兵不动——抬手（[_pressLift]）才清空。
  void _pressDown(
    AnnotationTimeline timeline,
    int order,
    AnnotationSelectionWritePort? port,
  ) {
    if (!_inRange(timeline, order)) return;
    _pressOrder = order;
    if (state.contains(order)) return;
    _prePressSelection = Set.of(state);
    _write({order}, port: port, silent: true, userWrite: true);
  }

  /// 按下段上抬手：按下写过（原未选中）→ 选中维持、清除按下会话，静默
  /// 标志复位后强制重发选中事实——派生链以激活语义重跑循环接线（跳选中
  /// 首段段首并起播）；按下落在已选中的段（未写过）→ toggle 清空（多段
  /// 选中整片清）。会话不在场（被其它路径了结）按普通点选 toggle 兜底。
  void _pressLift(
    AnnotationTimeline timeline,
    int order,
    AnnotationSelectionWritePort? port,
  ) {
    if (_pressOrder != order) {
      // 抬手命中的段不是按下段（越段界/经线层窗口路径等）：按下会话一并
      // 了结，不留陈旧快照供后续 tapCancel 误回滚。
      _pressConsume();
      _toggle(timeline, order, port);
      return;
    }
    _pressOrder = null;
    if (_prePressSelection == null) {
      _toggle(timeline, order, port);
      return;
    }
    _prePressSelection = null;
    _lastWriteSilent = false;
    ref.notifyListeners();
  }

  /// 按下落的选中被其它手势接管（压在段上的缩放起手、系统打断、点选被
  /// 更上层命中层抢判）：**静默回滚**到按下前的选中与循环——不 seek、
  /// 不新增跳转、不打断播放。未写过或会话已了结时零行为。
  void _pressCancel(AnnotationSelectionWritePort? port) {
    if (_pressOrder == null) return;
    _pressOrder = null;
    final snapshot = _prePressSelection;
    _prePressSelection = null;
    if (snapshot == null) return;
    _write(snapshot, port: port, silent: true);
  }

  /// 按下会话无回滚了结（横向快滑起手接管：横滑自己的「只选中这一段」
  /// 照常落地，不整片回滚、不落两次写）。
  void _pressConsume() {
    _pressOrder = null;
    _prePressSelection = null;
  }

  // ── 长按拖动圈选──

  /// 拖动进行中的起点段序；null = 无拖动会话。
  int? _dragAnchor;
  Set<int>? _preDragSelection;

  /// 长按成立：清空原选中、落点段立为起点。拖动帧的写是**静默写**
  ///（静默标志沿用恢复写回那一形态）——循环接线只就位作用域，不跳段首、
  /// 不起播、不打断播放；松手提交（[_dragCommit]）才恢复激活语义。
  /// 返回会话是否真的成立（越界段序 = false，会话未开）。
  /// 按下即选会话在场时回滚基线继承**按下前**的选中——圈选取消
  /// 回滚到按下前；已选中的段起手不被提前清空后再回滚。
  bool _dragBegin(
    AnnotationTimeline timeline,
    int order,
    AnnotationSelectionWritePort? port,
  ) {
    if (!_inRange(timeline, order)) return false;
    _dragAnchor = order;
    _preDragSelection = _prePressSelection ?? Set.of(state);
    _pressConsume();
    _write({order}, port: port, silent: true, userWrite: true);
    return true;
  }

  /// 横拖实时更新区间：起点与手指段序之间的全部连续段（区间代数钳住
  /// 首/末段）。手指未落进任何段（线窗/轨外）时保持上一帧区间。
  void _dragSpanTo(
    AnnotationTimeline timeline,
    int order,
    AnnotationSelectionWritePort? port,
  ) {
    final anchor = _dragAnchor;
    if (anchor == null) return;
    final count = deriveLearningSegments(timeline).length;
    if (order < 0 || order >= count) return;
    _write(contiguousSelectionBetween(anchor, order, count), port: port);
  }

  /// 松手提交：静默标志复位后强制重发选中事实——派生链以激活语义重跑
  /// 循环接线（跳选中首段段首并起播；集合在拖动帧已就位，常规写不再
  /// 触发派生链）。
  void _dragCommit() {
    if (_dragAnchor == null) return;
    _dragAnchor = null;
    _preDragSelection = null;
    _lastWriteSilent = false;
    ref.notifyListeners();
  }

  /// 手势取消：回到按下前的选中与循环——回滚写是静默写（不跳段首、
  /// 不起播）。静默标志置真后保持：派生链监听异步派发，写后即清会落在
  /// 监听之前、令回滚误触发激活；而所有激活语义的写点（点选/步进选中/
  /// 拖动提交）各自在写前清标志，陈旧真值不会抑制下一次激活。
  void _dragCancel(AnnotationSelectionWritePort? port) {
    if (_dragAnchor == null) return;
    _dragAnchor = null;
    final snapshot = _preDragSelection ?? const <int>{};
    _preDragSelection = null;
    _write(snapshot, port: port, silent: true);
  }

  /// 最近一次选中写是否「静默就位」（只就位循环作用域，不触发跳段首
  /// seek / 起播）。两个来源共用同一形态：打开恢复写回（恢复就位
  /// 不自动跳转）与长按拖动圈选的拖动帧写（拖动期间不打断播放）；
  /// 任何激活语义的用户/会话写（点选、步进选中、拖动提交）置回 false。
  bool get lastWriteSilent => _lastWriteSilent;
  bool _lastWriteSilent = false;

  /// 任意 seek（拖动预览条、单击粗线跳转等）目标越出选中合并范围时取消
  /// 选中；区间循环随派生范围一起停用。各 seek 入口共用同一判定，避免
  /// 进度被 PlaybackLoopLayer 拽回段首（「进度拖出选中范围即取消选中并
  /// 停用循环」对非拖动 seek 同样适用）。
  void _clearIfOutside(
    AnnotationTimeline timeline,
    Duration position,
    AnnotationSelectionWritePort? port,
  ) {
    if (timeline.videoDuration <= Duration.zero) return;
    final range = selectedLearningSegmentRange(timeline, state);
    if (range != null && !range.contains(position)) {
      _write(const {}, port: port);
    }
  }

  /// 选中集合落盘写入点：有净变化才经写后钩子把绝对终值（熟练度取现值 +
  /// 升序选中段序由编辑侧组装）入队；未接端口时零行为。
  void _persistIfChanged(
    Set<int> previous,
    AnnotationSelectionWritePort? port,
  ) {
    final next = state;
    // 集合相等手写判定：模块库依赖约束禁 flutter/foundation（setEquals
    // 不可用）；Set 无重复元素，长度一致 + 单向包含即相等。
    if (next.length == previous.length && previous.containsAll(next)) return;
    port?.persistSelection(next);
  }

  /// 段序是否落在现势学习段范围内。
  bool _inRange(AnnotationTimeline timeline, int order) {
    final count = deriveLearningSegments(timeline).length;
    return order >= 0 && order < count;
  }
}

/// 选中学习段注入点；播放联动与轨道样式共同消费。
final selectedLearningSegmentsProvider =
    NotifierProvider<SelectedLearningSegmentsModel, Set<int>>(
      SelectedLearningSegmentsModel.new,
    );

/// 选中域写面。
///
/// 构造收显式依赖、不碰容器句柄：两个 store、时间线读取闭包、组员方案只读
/// 读取闭包、写入端口、两个现势计数读口（局部镜像片段数／备注数——片段类
/// 目标的越界拒绝形状要与今天逐位一致，而这两个 store 留在编辑库）。装配
/// provider 住编辑库。
///
/// 单值槽三动词 [select]／[toggle]／[clear] 按目标类型分派，`clear` 是
/// 「点空白／其它操作即清除」的唯一入口；[remapLineSelection] 承接结构性
/// 线表变化后的同位重映射。学习段十条逐帧动词（[toggleLearningSegment]／
/// [selectOnly]／[press]／[liftPress]／[cancelPress]／[consumePress]／
/// [beginDragSelect]／[spanTo]／[commitDragSelect]／[cancelDragSelect]）与
/// 四条非用户路径口（[clearLearningSegments]／[resetLearningSegments]／
/// [restoreLearningSegments]／[clearLearningSegmentsIfOutside]）是学习段
/// store 的唯一公开写面；组员方案只读由注入读口在五个写点入口判。
class AnnotationSelectionDomain {
  AnnotationSelectionDomain({
    required this._store,
    required this._learningStore,
    required this.timeline,
    required this._memberSchemeReadonly,
    required this._writePort,
    required this._localMirrorFragmentCount,
    required this._noteCount,
  });

  final AnnotationSelectionModel _store;
  final SelectedLearningSegmentsModel _learningStore;

  /// 时间线读取闭包：学习段半边的逐帧动词与 seek 越出清除经它取现势时间线，
  /// 调用点不必各自取。
  final AnnotationTimeline Function() timeline;

  /// 组员方案只读读取闭包（单一事实源仍是编辑库的 provider）：五个写点入口
  /// 判它，回滚／了结类入口不判；对比态只读不进域。
  final bool Function() _memberSchemeReadonly;

  final AnnotationSelectionWritePort _writePort;

  final int Function() _localMirrorFragmentCount;
  final int Function() _noteCount;

  /// 点选目标（替换既有任意选中；同一密封类型互斥免费）。
  ///
  /// 越界目标在域内被拒：分段线／半拍线负索引、片段／备注索引越界抛
  /// [RangeError]，取值域与报错口径与既有写口逐位一致。
  void select(AnnotationSelection target) => _store._set(_validated(target));

  /// 目标 toggle：同目标再点取消、异目标替换选中。
  ///
  /// 只有今天存在 toggle 路径的三类目标按「再点取消」分派；片段／备注今天
  /// 只有「只选中」一条路径，按替换写入、不引入第二次点击取消。
  void toggle(AnnotationSelection target) {
    final validated = _validated(target);
    final current = _store._current;
    final sameTarget = switch (validated) {
      SegmentLineSelection(:final index) =>
        current?.asSegmentLineIndex == index,
      HalfBeatLineSelection(:final index) =>
        current?.asHalfBeatLineIndex == index,
      VideoRangeBoundarySelection(:final boundary) =>
        current?.asVideoRangeBoundary == boundary,
      LocalMirrorFragmentSelection() || NoteFragmentSelection() => false,
    };
    _store._set(sameTarget ? null : validated);
  }

  /// 清除选中（语义统一入口）：覆盖整体复位（换视频/重开/初始化兜底）、
  /// 删除命令后清与「其它操作即清除」。
  ///
  /// 「其它操作即清除」：任何不针对当前选中线的操作（段体/空白
  /// 含收起/其它工具/播放控制/无选中时帧步进/拖预览或换目标/缩放等）统一
  /// 经本入口清除；帧步进/标记/删除视为针对选中线，调用侧**不得**经本
  /// 入口清除（删除后自然清）。幂等：无选中时再清为零行为。
  void clear() => _store._set(null);

  /// 结构性线表变化（插线/删线/区间收缩删线）后的线选中同位重映射
  /// （分段线与半拍线共用）。线数不变（拖线/flag 等）不动
  /// 选中；线数变化时以选中线的位置在新线表中同位匹配（升序互异、不随
  /// 插入/删除变化）——匹配到则指向同一条线（插入点右侧自然 +1、撤销插入
  /// −1），匹配不到（该线已被删）则无效化；索引越界同效。非线段选中
  /// （端标/片段）不受影响。
  void remapLineSelection(AnnotationTimeline before, AnnotationTimeline after) {
    final selection = _store._current;
    if (selection is SegmentLineSelection) {
      _remapIndex(
        before: before.segmentLines,
        after: after.segmentLines,
        index: selection.index,
        positionOf: (line) => line.position,
        reselect: (index) => _store._set(SegmentLineSelection(index)),
      );
      return;
    }
    if (selection is HalfBeatLineSelection) {
      _remapIndex(
        before: before.halfBeatLines,
        after: after.halfBeatLines,
        index: selection.index,
        positionOf: (line) => line.position,
        reselect: (index) => _store._set(HalfBeatLineSelection(index)),
      );
    }
  }

  // ── 学习段用户路径 10 动词──

  /// 点击学习段选中：toggle 语义（规则见 [toggleLearningSegmentSelection]）。
  /// 组员方案只读时静默拒绝。
  void toggleLearningSegment(int order) {
    if (_memberSchemeReadonly()) return;
    _learningStore._toggle(timeline(), order, _writePort);
  }

  /// 只选中指定学习段（替换既有选中集合；段序无效时忽略）。组员方案只读时
  /// 静默拒绝。
  void selectOnly(int order) {
    if (_memberSchemeReadonly()) return;
    _learningStore._selectOnly(timeline(), order, _writePort);
  }

  /// 按下即选：返回按下会话是否落地（只读拒绝或段序越界为假）。
  bool press(int order) {
    if (_memberSchemeReadonly()) return false;
    _learningStore._pressDown(timeline(), order, _writePort);
    return _learningStore._pressLanded;
  }

  /// 按下段上抬手（已写过那条 = 只重发选中事实；落在已选中段 = toggle
  /// 清空）。组员方案只读时静默拒绝。
  void liftPress(int order) {
    if (_memberSchemeReadonly()) return;
    _learningStore._pressLift(timeline(), order, _writePort);
  }

  /// 按下落的选中被其它手势接管：静默回滚到按下前（回滚不被只读门拦）。
  void cancelPress() => _learningStore._pressCancel(_writePort);

  /// 按下会话无回滚了结（横向快滑起手接管）。
  void consumePress() => _learningStore._pressConsume();

  /// 长按起手圈选：返回会话是否真的成立（只读拒绝或落点越界 = false）。
  bool beginDragSelect(int order) {
    if (_memberSchemeReadonly()) return false;
    return _learningStore._dragBegin(timeline(), order, _writePort);
  }

  /// 横拖实时更新区间（首/末段钳住；手指未落进任何段保持上一帧）。
  void spanTo(int order) =>
      _learningStore._dragSpanTo(timeline(), order, _writePort);

  /// 松手提交圈选区间为最终选中。
  void commitDragSelect() => _learningStore._dragCommit();

  /// 手势取消：回滚选中与循环。
  void cancelDragSelect() => _learningStore._dragCancel(_writePort);

  /// 最近一次选中写是否静默就位（只就位循环作用域，不触发跳段首 seek）。
  bool get lastWriteSilent => _learningStore.lastWriteSilent;

  // ── 学习段非用户路径 4 口 + seek 越出清除──

  /// 整体清（几何清除／临时段互斥／模块内显式清）：保存清、不清另两源。
  void clearLearningSegments() => _learningStore._clear(_writePort);

  /// 非保存清（换视频复位与恢复前清）：不入队。
  void resetLearningSegments() => _learningStore._reset();

  /// 打开恢复装载写回：非保存写入；静默标志只在写回非空集合时置真。
  void restoreLearningSegments(Set<int> orders) =>
      _learningStore._restore(orders);

  /// 任意 seek 目标越出选中合并范围时取消选中（判定与今天同一处）；时间线
  /// 由域经注入的读取闭包取。
  void clearLearningSegmentsIfOutside(Duration position) =>
      _learningStore._clearIfOutside(timeline(), position, _writePort);

  /// 准入校验：越界目标抛 [RangeError]（形状与既有写口逐位一致），合法
  /// 目标原样返回。
  AnnotationSelection _validated(AnnotationSelection target) {
    switch (target) {
      case SegmentLineSelection(:final index):
        if (index < 0) {
          throw RangeError.range(index, 0, null, 'index', '分段线索引不能为负');
        }
      case HalfBeatLineSelection(:final index):
        if (index < 0) {
          throw RangeError.range(index, 0, null, 'index', '半拍线索引不能为负');
        }
      case LocalMirrorFragmentSelection(:final index):
        final count = _localMirrorFragmentCount();
        if (index < 0 || index >= count) {
          throw RangeError.range(index, 0, count - 1, 'index', '局部镜像片段索引越界');
        }
      case NoteFragmentSelection(:final index):
        final count = _noteCount();
        if (index < 0 || index >= count) {
          throw RangeError.range(index, 0, count - 1, 'index', '备注索引越界');
        }
      case VideoRangeBoundarySelection():
        break;
    }
    return target;
  }

  /// 同位重映射通用形状（分段线/半拍线共用）：线数不变不动；越界无效化；
  /// 以位置在新线表中匹配，匹配到则重指向、匹配不到则清选中。
  void _remapIndex<T>({
    required List<T> before,
    required List<T> after,
    required int index,
    required Duration Function(T) positionOf,
    required void Function(int) reselect,
  }) {
    if (before.length == after.length) return;
    if (index < 0 || index >= before.length) {
      _store._set(null);
      return;
    }
    final position = positionOf(before[index]);
    final newIndex = after.indexWhere((line) => positionOf(line) == position);
    if (newIndex < 0) {
      _store._set(null);
      return;
    }
    reselect(newIndex);
  }
}
