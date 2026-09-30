/// 标注编辑命令代数与 outcome。
///
/// 命令族是模块**唯一可入史**的编辑意图描述：新增一种编辑操作 = 新增一个
/// sealed 子类 + executor（见 `annotation_editor.dart`）一个 case，编译期
/// switch 兜漏，调用方零改动。错误契约：交互命令提交时**落点解析在模块内**
/// 完成（widget 不预吸附），越界/触界/无合法落点 = [EditNoop] 静默（不入史
/// 不入盘）；`ArgumentError` 只对不经落点解析的路径（`timeline_ops.dart`
/// 纯函数）保留，非法索引 [RangeError] 照旧。不吞错、不转错、失败不半写。
library;

import '../annotation/learning_segment_attributes.dart' show LearningMastery;
import '../annotation/interval_fragment_row.dart' show IntervalEdge;
import '../annotation/note_sticker.dart' show NoteGeometry;

/// 端点截取：把片段 id [clipId] 对应练习片段的 [edge] 端拖到 [to]（另一端
/// 不动）。
///
/// 寻址按**片段 id**：渲染内部的下标不进 verb；
/// 提交时按 id 回查当前表，查无该 id = [EditNoop] 静默（不入史不入盘）。
/// [to] 为请求位置（**源时间轴**，任意时间点，非最终落点）：提交时模块内
/// 落点解析（就绪网格吸就近八拍点、异常网格自由直通；钳在素材内
/// `[0, materialDurationMs]` 与有效练习区间内；端点拖过对端 = no-op）。
/// 截取只改片段的引用范围（素材内 in/out 偏移），素材文件与库内条目不动。
final class TrimPracticeClip extends AnnotationEdit {
  const TrimPracticeClip({
    required this.clipId,
    required this.edge,
    required this.to,
  });

  /// 目标片段 id（形如 `clip_<素材 id>`）。
  final String clipId;

  /// 被拖动的端点（起点或终点）。
  final IntervalEdge edge;

  /// 请求的端点位置（源时间轴，任意时间点，非最终落点）。
  final Duration to;
}

/// 删除练习片段：只把该片段移出练习视频轨——素材文件与素材库
/// 条目保留，一次撤销可回退；删除后清选中（与
/// [RemoveLocalMirrorFragment] 同一语义）。
final class RemovePracticeClip extends AnnotationEdit {
  const RemovePracticeClip({required this.clipId});

  /// 目标片段 id（形如 `clip_<素材 id>`）；提交时按 id 回查当前表，查无 =
  /// [EditNoop] 静默。
  final String clipId;
}

/// 一次标注编辑命令（sealed：唯一可入史族）。
sealed class AnnotationEdit {
  const AnnotationEdit();
}

/// 在 [at] 处新建一条分段线。
///
/// [at] 为请求位置（任意时间点）：提交时模块内解析落点（就近**八拍点**
/// （经 core 单一相位源、锚点重定相；仅就绪网格派生，占位/异常直通）+
/// 合法域开区间检查）；解析不成立（越界/触界/无合法落点）= [EditNoop]
/// 静默。同位加线 no-op。
final class AddSegmentLine extends AnnotationEdit {
  const AddSegmentLine({required this.at});

  /// 请求位置（任意时间点，非最终落点）。
  final Duration at;
}

/// 删除索引 [index] 处的分段线（融合相邻学习段属性 + 整体清选中）。
///
/// 越界抛 [RangeError]。
final class RemoveSegmentLine extends AnnotationEdit {
  const RemoveSegmentLine({required this.index});

  /// 升序分段线列表中的索引。
  final int index;
}

/// 拖动/步进分段线 [index] 到 [to]。
///
/// [to] 为请求位置：提交时模块内解析落点（同 [AddSegmentLine]）；解析
/// 不成立或越邻/触界为 no-op（钳制丢弃而非吸附到最近合法位）。
final class MoveSegmentLine extends AnnotationEdit {
  const MoveSegmentLine({required this.index, required this.to});

  /// 升序分段线列表中的索引。
  final int index;

  /// 请求位置（任意时间点，非最终落点）。
  final Duration to;
}

/// 在 [at] 处新建一条半拍线。
///
/// [at] 为请求位置（任意时间点）：提交时模块内解析落点（就近**半拍格点**；
/// 就绪/占位均匀网格照常派生，异常态吸附停用、请求位置直通）。越界/触界
/// （合法域 = 时间线开区间）或无合法落点 = [EditNoop] 静默（不入史不入盘，
/// 不抛 `ArgumentError`）；同位加线 no-op。半拍线不参与学习段几何派生，
/// 无段序键属性级联、不清激活/临时段。
final class AddHalfBeatLine extends AnnotationEdit {
  const AddHalfBeatLine({required this.at});

  /// 请求位置（任意时间点，非最终落点）。
  final Duration at;
}

/// 拖动半拍线 [index] 到 [to]。
///
/// [to] 为请求位置：提交时模块内解析落点（同 [AddHalfBeatLine]）；解析
/// 不成立（越界/触界/无合法落点）或越邻 = [EditNoop] 静默（钳制丢弃而非
/// 吸附到最近合法位）；与分段线互不钳制。
final class MoveHalfBeatLine extends AnnotationEdit {
  const MoveHalfBeatLine({required this.index, required this.to});

  /// 升序半拍线列表中的索引。
  final int index;

  /// 请求位置（任意时间点，非最终落点）。
  final Duration to;
}

/// 删除索引 [index] 处的半拍线（同分段线删除语义）。
///
/// 越界抛 [RangeError]；半拍线不参与学习段几何派生，无段序键属性级联。
final class RemoveHalfBeatLine extends AnnotationEdit {
  const RemoveHalfBeatLine({required this.index});

  /// 升序半拍线列表中的索引。
  final int index;
}

/// 设置视频首/尾（一次一个或同时）。
///
/// [start]/[end] 为请求位置：提交时模块内解析落点——就绪网格覆盖区
/// （首拍..末拍）内吸最近**真实拍点**，覆盖外**自由落点**（不回拉，
/// 首尾线可拖出网格生成区直到片尾）；非就绪网格请求位置直通。首尾线是
/// 三族线中唯一「区间外不拒绝」的一族：端标本体即区间边界，不适用开区间
/// 触界检查，合法域由可拖范围与归一化钳制（保证首 ≤ 尾）收口，不抛
/// `ArgumentError`、不以越界为由拒绝（[EditNoop] 仅在无净变化时发生）。
/// 区间收缩剔除界外线，段序键属性按映射重排。
final class SetVideoRange extends AnnotationEdit {
  const SetVideoRange({this.start, this.end});

  /// 新的视频首（null = 不改）。
  final Duration? start;

  /// 新的视频尾（null = 不改）。
  final Duration? end;
}

/// 自动分段：一次编辑内设置首/尾到网格
/// 首末拍，并以派生切点整体替换全部分段线（32 拍下刀、尾部并入、首线
/// 相位）。首尾与切点均为派生**终值**，不经落点解析（豁免路径，同撤销
/// 回放/恢复装载）。逐段熟练度与重点按旧新分区的**时间重叠**就地重写
/// （规则见 [rebakeLearningSegmentAttributes]）；一步可撤销，
/// 撤销同时回退线与属性。
final class AutoSegment extends AnnotationEdit {
  const AutoSegment({
    required this.start,
    required this.end,
    required this.cuts,
  });

  /// 新的视频首（网格首拍）。
  final Duration start;

  /// 新的视频尾（网格末拍）。
  final Duration end;

  /// 升序分段线切点（`deriveAutoSegmentCuts` 派生）。
  final List<Duration> cuts;
}

/// 节拍对齐应用：把分段线/半拍线/首尾线的绝对时间整体平移
/// [delta]（= 预览偏移 − 上次已应用偏移，越界按 0..total 钳制、
/// 归一化不变式保持；整体平移不经落点解析，属豁免路径），
/// 同时把公开 beat 段平移量写定为 [shiftSeconds]。整次应用 = 一次标注编辑
/// （一步撤销，撤销同时回退线位置与平移量字段）。
final class ApplyBeatShift extends AnnotationEdit {
  const ApplyBeatShift({required this.delta, required this.shiftSeconds});

  /// 线整体平移量（预览偏移 − 已应用偏移）。
  final Duration delta;

  /// 写定到公开 beat 段的平移量（秒，绝对终值）。
  final double shiftSeconds;
}

/// 节拍倍频应用：把公开 beat 段倍频写定为
/// [density]（绝对终值，五档 2 的幂），同时把八拍锚点序号按新档就地
/// 烘焙；整次应用 = 一次标注编辑。烘焙规则与两方向语义见
/// `document_beat_grid.dart` 的 [rebakeEightBeatAnchors]（单一事实源）。
final class ApplyBeatDensity extends AnnotationEdit {
  const ApplyBeatDensity({required this.density});

  /// 写定到公开 beat 段的倍频（派生拍数 ÷ 落盘拍数，绝对终值）。
  final double density;
}

/// 清空分段：删除全部分段线
/// （学习段几何归零 → 整片范围练习），首/尾线与半拍线保留。熟练度/重点
/// 重置为缺省；一步可撤销。
final class ClearSegmentLines extends AnnotationEdit {
  const ClearSegmentLines();
}

/// 落一个八拍锚点：在 [at] 处落锚
/// ——模块内落点解析把 [at]（请求位置，通常预览线）解析为最近**强拍**，
/// 该强拍的拍序号即锚点（锚点自身即八拍点、其后每隔一个强拍一个八拍点、
/// 管到下一个锚点之前）。
///
/// [at] 为请求位置（任意时间点，非最终落点）：非就绪网格、网格无强拍或
/// 解析不成立 = EditNoop 静默（不入史不入盘）；已存在的锚点重复落锚 =
/// no-op（集合未变）。**不改任何线的几何**（[EditApplied.geometryChanged]
/// 恒 false，不触发学习段激活/临时段清除）；一次提交 = 一次标注编辑
/// （单步可撤销）。**不受锁定分段门禁**（锁只护分段结构）。
final class AddEightBeatAnchor extends AnnotationEdit {
  const AddEightBeatAnchor({required this.at});

  /// 请求位置（任意时间点，非最终落点）。
  final Duration at;
}

/// 删除预览位置 [at] 处的八拍锚点：与
/// [AddEightBeatAnchor] 同一谓词——模块内落点解析把 [at] 解析为最近**强拍**
/// 的拍序号，该拍序号在锚点集合内即删除，否则 no-op（预览位置无锚点 =
/// EditNoop 静默）。
///
/// **不改任何线的几何**（[EditApplied.geometryChanged] 恒 false，不触发学习段
/// 激活/临时段清除）；一次提交 = 一次标注编辑（单步可撤销）。**不受锁定
/// 分段门禁**（锁只护分段结构）。
/// 删中间一个锚点时，仅该锚点其后一段的相位回落到前一锚点，其余段逐位不变。
final class RemoveEightBeatAnchor extends AnnotationEdit {
  const RemoveEightBeatAnchor({required this.at});

  /// 请求位置（任意时间点，非最终落点）。
  final Duration at;
}

/// 清空全部八拍锚点：一次点击 = 一次标注编辑
/// （单步可撤销）、当帧刷新全部派生面；集合已为空 = EditNoop 静默（UI 侧
/// 表现为按钮置灰）。不改任何线的几何。
final class ClearEightBeatAnchors extends AnnotationEdit {
  const ClearEightBeatAnchors();
}

/// 切换分段线 [index] 的 flag（已是目标值 no-op）。
///
/// 几何未变 → 不清除激活学习段/临时衔接段（全库唯一）。
final class ToggleSegmentFlag extends AnnotationEdit {
  const ToggleSegmentFlag({required this.index});

  /// 升序分段线列表中的索引。
  final int index;
}

/// 设置段序 [order] 的学习段熟练度（同值 no-op）。
final class SetSegmentMastery extends AnnotationEdit {
  const SetSegmentMastery({required this.order, required this.mastery});

  /// 学习段段序（自左向右，0 起）。
  final int order;

  final LearningMastery mastery;
}

/// 切换段序 [order] 的学习段「重点」。
final class ToggleSegmentEmphasis extends AnnotationEdit {
  const ToggleSegmentEmphasis({required this.order});

  /// 学习段段序（自左向右，0 起）。
  final int order;
}

/// 设置**全部选中学习段**的熟练度为同一档：一次标注编辑——
/// 一个 diff、一步撤销、一次落盘。提交时模块内读选中集合：空选中 =
/// 空 plan → EditNoop 静默。
final class SetSelectedSegmentsMastery extends AnnotationEdit {
  const SetSelectedSegmentsMastery({required this.mastery});

  final LearningMastery mastery;
}

/// 切换**全部选中学习段**的「重点」：全有星则全部取消、否则
/// 全部点亮；一次标注编辑、一步撤销。提交时模块内读选中集合：空选中 =
/// 空 plan → EditNoop 静默。
final class ToggleSelectedSegmentsEmphasis extends AnnotationEdit {
  const ToggleSelectedSegmentsEmphasis();
}

/// 把**全部选中学习段**的段内档**赋值**为同一档：一次标注编辑——
/// diff、一步撤销、一次落盘。提交时模块内读选中集合：空选中 = 空 plan
/// → EditNoop 静默（无对象时按钮置灰但按得动、弹「无对象」做法）。
/// 赋值不是步进：连按不叠乘；多段档位不一时按一下即整片统一；
/// [density] == 1（回到原样）即删键。
final class SetSelectedSegmentsDensity extends AnnotationEdit {
  const SetSelectedSegmentsDensity({required this.density});

  /// 赋值档值（快一倍 = 2、慢一半 = 0.5、回到原样 = 1）。
  final double density;
}

/// 在 [at]（请求起点，通常播放头）处创建一条局部镜像片段。
///
/// [at] 为请求位置：提交时模块内落点解析（创建起点吸最近八拍点/占位同级
/// 派生点；异常自由），默认宽一个八拍（占位均匀派生长度 / 异常秒制兜底）；
/// 结果与 range 与既有片段重叠则自动截断/钳制（不重叠
/// 不变量成立）。钳空无可放置 = no-op drop（EditNoop）。
final class AddLocalMirrorFragment extends AnnotationEdit {
  const AddLocalMirrorFragment({required this.at});

  /// 请求起点（任意时间点，非最终落点）。
  final Duration at;
}

/// 在 [at]（请求位置，通常预览线）处插入一条备注贴纸。
///
/// [at] 为请求位置：提交时模块内落点解析四步收在一处——① 钳入视频首尾
/// 区间 → ② 请求位置落在既有备注窗内即**不建**（占用谓词，正常路径由
/// 入口按原始请求位置转编辑，模块保留本步作兜底）→ ③ 起点吸「自由区间
/// 内的」最近八拍点（不吸被占窗内的拍点；网格非就绪不吸附、落点 = 请求
/// 位置，照常创建）→ ④ 终点 = 起点 + 派生格一个八拍，向视频尾与右邻
/// 备注起点截断；零宽不成立 = [EditNoop] 静默。结果按起点升序插入且与
/// 既有两两不重叠（不变量由本命令维持）。一次提交 = 一次标注编辑（单步
/// 可撤销）。**不受锁定分段门禁**（锁只护分段结构）；**不改学习段几何**
/// （[EditApplied.geometryChanged] 恒 false）。
final class InsertNote extends AnnotationEdit {
  const InsertNote({required this.at});

  /// 请求位置（任意时间点，非最终落点）。
  final Duration at;
}

/// 把索引 [index] 处备注的文本写定为 [text]（载荷 = 纯文本
/// 本身）。
///
/// **模块契约**：本模块**不解析点名、不读名册、不存引用**——点名只
/// 存在于文本里（`@名字`），渲染时按当前名册解析并着色。一次提交 =
/// 一次标注编辑（单步可撤销）。**不受锁定
/// 分段门禁**（锁只护分段结构）；不改学习段几何
/// （[EditApplied.geometryChanged] 恒 false）。
final class SetNoteText extends AnnotationEdit {
  const SetNoteText({required this.index, required this.text});

  /// 升序备注列表中的索引（越界抛 [RangeError]）。
  final int index;

  /// 新文本（可含点名语法；模块按不透明字符串写定）。
  final String text;
}

/// 整体移：把 [index] 处备注的时间窗平移为新起点 [to]（宽度不变）。
///
/// [to] 为请求位置：提交时模块内落点解析（就绪网格吸最近八拍点、非就绪
/// 自由直通），再与相邻备注 + 视频首尾区间互斥钳制；钳空（无可放置区间）
/// = no-op（拖动静默停住）。备注的文本/样式/锁/几何等其余字段原样携带。
final class MoveNote extends AnnotationEdit {
  const MoveNote({required this.index, required this.to});

  /// 升序备注列表中的索引。
  final int index;

  /// 请求的新起点（任意时间点，非最终落点）。
  final Duration to;
}

/// 端点拖：把 [index] 处备注时间窗的 [edge] 端拖到 [to]（另一端不动）。
///
/// [to] 为请求位置：提交时模块内落点解析（同 [MoveNote]），再与相邻备注
/// + 首尾区间互斥钳制；端点不得倒置（拖过对端）= no-op。
final class DragNoteEdge extends AnnotationEdit {
  const DragNoteEdge({
    required this.index,
    required this.edge,
    required this.to,
  });

  /// 升序备注列表中的索引。
  final int index;

  /// 被拖动的端点（起点或终点）。
  final IntervalEdge edge;

  /// 请求的端点位置（任意时间点，非最终落点）。
  final Duration to;
}

/// 贴纸几何：把索引 [index] 处备注的贴纸几何写定为
/// [geometry]（单指平移与双指等比缩放共用一条命令）。
///
/// [geometry] 为**请求值**（内容矩形归一化）：提交时模块内单点钳制
///（[clampNoteGeometry]——中心钳进 [0,1]、系数钳进具名界）；像素 → 归一化
/// 换算在拖动会话内单点完成，不在本命令重复。同几何 = EditNoop 静默。
/// 一次提交 = 一次标注编辑（单步可撤销）。**不受锁定分段门禁**；不改
/// 学习段几何（[EditApplied.geometryChanged] 恒 false）。备注自身的
/// 内容锁（`locked` 字段）对本命令的门禁见：已锁时被模块拒绝并弹
/// 「备注已锁定」提示。
final class SetNoteGeometry extends AnnotationEdit {
  const SetNoteGeometry({required this.index, required this.geometry});

  /// 升序备注列表中的索引（越界抛 [RangeError]）。
  final int index;

  /// 请求的贴纸几何（归一化，非最终落点）。
  final NoteGeometry geometry;
}

/// 锁定开关：把索引 [index] 处备注的内容锁取反。一次提交 =
/// 一次标注编辑（单步可撤销、随备注臂保存）；**不受锁定分段门禁、也
/// 不受内容锁**——两把锁都不挡自己的开关（锁是保护而不是锁死）。不改
/// 学习段几何（[EditApplied.geometryChanged] 恒 false）。
final class ToggleNoteLock extends AnnotationEdit {
  const ToggleNoteLock({required this.index});

  /// 升序备注列表中的索引（越界抛 [RangeError]）。
  final int index;
}

/// 删除索引 [index] 处的备注贴纸（编辑器与贴纸左上角的删除入口
/// 共用；一次提交 = 一次标注编辑，撤销即恢复整条备注）。**不受锁定
/// 分段门禁**；不改学习段几何
/// （[EditApplied.geometryChanged] 恒 false）。
final class RemoveNote extends AnnotationEdit {
  const RemoveNote({required this.index});

  /// 升序备注列表中的索引（越界抛 [RangeError]）。
  final int index;
}

/// 删除索引 [index] 处的局部镜像片段（越界抛 [RangeError]）。
final class RemoveLocalMirrorFragment extends AnnotationEdit {
  const RemoveLocalMirrorFragment({required this.index});

  /// 升序片段列表中的索引。
  final int index;
}

/// 整体移：把 [index] 处局部镜像片段平移为新起点 [to]（保持原宽）。
///
/// [to] 为请求位置：提交时模块内落点解析（端点同级吸附：就绪真实拍/占位
/// 均匀派生/异常自由），再与相邻片段 + 首尾区间互斥钳制；钳空 = no-op。
final class MoveLocalMirrorFragment extends AnnotationEdit {
  const MoveLocalMirrorFragment({required this.index, required this.to});

  /// 升序片段列表中的索引。
  final int index;

  /// 请求的新起点（任意时间点，非最终落点）。
  final Duration to;
}

/// 端点拖：把 [index] 处局部镜像片段的 [edge] 端拖到 [to]（另一端不动）。
///
/// [to] 为请求位置：提交时模块内落点解析（端点同级吸附），再与相邻片段 +
/// 首尾区间互斥钳制；端点越位/钳空 = no-op。
final class DragLocalMirrorFragmentEdge extends AnnotationEdit {
  const DragLocalMirrorFragmentEdge({
    required this.index,
    required this.edge,
    required this.to,
  });

  /// 升序片段列表中的索引。
  final int index;

  /// 被拖动的端点（起点或终点）。
  final IntervalEdge edge;

  /// 请求的端点位置（任意时间点，非最终落点）。
  final Duration to;
}

/// submit 的返回结果：调用方据此决定后续副作用（如帧步进只在 applied 时
/// 同步播放头、geometryChanged 时处理清除之外的 UI），模块不吞错不转错。
sealed class EditOutcome {
  const EditOutcome();

  /// 本次提交是否实际生效（false = no-op，状态未动）。
  bool get applied => false;

  /// 生效的提交是否改变了标注几何（rangeStart/rangeEnd 或分段线位置）。
  bool get geometryChanged => false;
}

final class EditApplied extends EditOutcome {
  const EditApplied({required this.geometryChanged});

  @override
  final bool geometryChanged;

  @override
  bool get applied => true;
}

/// no-op：无净变化，状态、清除、历史均未动。
final class EditNoop extends EditOutcome {
  const EditNoop();
}

/// 锁门禁拒绝：锁定分段开启时受锁 verb 的提交被拒——状态、
/// 清除、历史、保存均未动；模块已统一触发一次「已锁定分段」提示，调用方
/// 只按结果判定后续副作用（无动作），不自行预查锁策略。
final class EditLocked extends EditOutcome {
  const EditLocked();
}

/// 门禁原因：一枚门禁、N 个原因——逐 verb
/// 声明自己受哪些原因门禁（同一份声明，不建第二张平行动词表）；新增原因
/// = 加一个枚举值 + 逐 verb 补声明，漏声明由编辑器内的穷尽 switch 兜住。
enum AnnotationEditGateReason {
  /// 用户锁（锁定分段）：拒绝弹「已锁定分段」提示。
  userLayoutLock,

  /// 对比态只读：对比态里标注几何改不动。
  /// 拒绝**静默**——对比态不是「锁」，是「这里不能改」，不弹提示；
  /// 拖动手势起手前的静默不参与归 widget（只读判定读
  /// `annotationCompareReadonlyProvider`），verb 级拒绝归模块。
  compareReadonly,

  /// 组员方案只读：装载组员方案时，一切几何与
  /// 文本改动（含熟练度/重点/flag/备注锁开关）被拒——组员方案不能被我改。
  /// 拒绝**静默**（与对比态只读同款，不弹提示）；装载判定读
  /// `annotationMemberSchemeReadonlyProvider`，verb 级拒绝归模块。
  /// 我的落盘学习段激活同受此门禁（写入口静默拒绝）：它按我的标注方案的
  /// 段序索引，装载组员方案时不读也不写。
  memberSchemeReadonly,
}
