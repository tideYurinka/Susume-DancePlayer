/// annotation 域（标注编辑数据基座，纯模型 + 纯操作函数，无 UI）。
///
/// 模块职责：
///
///   - [annotation_timeline]：时间线模型与不变式；
///   - [timeline_ops]：分段线/首尾/flag 的纯操作函数（唯一变更入口）；
///   - [learning_segments]：由首尾 + 分段线派生的学习段几何；
///   - [learning_segment_attributes]：学习段熟练度（私密）与重点（可分享）
///     的会话态值/融合规则与纯操作；
///   - [segment_selection]：选中段集合与合并循环范围（私密字段）；
///   - [segment_hit]：学习段轨触控命中解析（段/线/首尾，最近段扩展）；
///   - [snap]：吸附对齐（占位节拍四拍格，密度/开关可调）；
///   - [transition_segment]：临时衔接段范围解析（±1 八拍、首尾截断、
///     跨段、网格取整）；
///   - [half_beat_snap]：插入半拍线的吸附位置解析；
///   - [local_mirror]：局部镜像片段值类型/升序不重叠不变量/落点与端点钳制
///     （局部镜像轨数据基座）。
library;

export 'annotation_timeline.dart';
export 'half_beat_line.dart';
export 'half_beat_snap.dart';
export 'local_mirror.dart';
export 'learning_segment_attributes.dart';
export 'learning_segments.dart';
export 'segment_selection.dart';
export 'segment_hit.dart';
export 'segment_line.dart';
export 'snap.dart';
export 'timeline_ops.dart';
export 'transition_segment.dart';
