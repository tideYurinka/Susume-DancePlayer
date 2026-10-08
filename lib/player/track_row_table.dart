/// 轨道行表：轨道带行几何的单一来源。
///
/// **范围（只装几何与身份）**：行标识（[TrackRowId]）、逐行行高、行键
/// （与渲染层 Key 逐位一致）、行间间隙，以及**轨道片头短标签**
/// （[TrackRow.prefixLabel]——显示文案，不进标识与行键）。接口
/// 三个成员：整带高（[totalHeight]）；某行的矩形（[rectOf]，以「顶」「高」
/// 两个标量表达，不用框架矩形类型）；某纵向坐标落在哪一行（[rowAt]，无则
/// 空）。片头标签集由 [TrackRowTable.prefixLabels] / [TrackRowTable.prefixLabelOf]
/// 给出，与行集同序、行缺席即无标签。
///
/// **片头不是行**：轨道片头是行集**之外**的一列（见 track_band.dart 的
/// `_TrackPrefix`），不带行高、不参与行矩形与行命中；本表只回答「这一行
/// 叫什么短标签」。
///
/// **行集语义**：某态下有哪些行、什么次序，由传入的有序行列表表达
/// （[TrackRowTable.rows] 顺序即带内自上而下的行序）；具名行集
/// [TrackRowTable.normal] 与 [TrackRowTable.compare]（对比
/// 练习）为当前两份行集。轨道带对「模式」无知——换一份
/// 行集即换掉整条带的行数与行序；「模式 → 行集」的映射收在
/// `session_mode_surfaces.dart` 的声明表里逐值一行。
///
/// **坐标 → 行的边界口径**：行区间含两端（行顶与行底都判为命中该行）、
/// 行优先于间隙；落在间隙、带外或负坐标返回空。口径由直测钉住。
///
/// **刻意不含**（出现第二个取值时再加，字段都在模块内部构造、后加不破
/// 调用方）：
/// - 行种类（块状行 / 刻度行 / 交互行）——今天四个取值各只出现一次，
///   立字段只是猜；
/// - 行级可编辑性——今天恒为真；「分段线全带只读、首尾线不渲染、半拍线
///   仅节拍轨行内只读」这类表现是**带级**的，硬塞进行级会给跨行表现安错
///   家；
/// - 带级标记层表现——今天恒为「全渲染且全可交互」。
///
/// 行内装饰（节拍刻度列内缩、控制柄条底偏移、镜像片段块内边距、学习段
/// 体填充）不进表——表只回答「行在哪、多高」，不承担行内画法；变的只是
/// 「本行高从哪来」，不是「内缩规则归谁」。
///
/// 本模块零框架依赖（不引 Flutter、不引 dart:ui）、不读状态、不依赖任何
/// 外部对象——取值只由入参决定，可在不启动 widget 环境的情况下直测。
library;

/// 练习视频轨 / 备注轨 / 局部镜像轨 / 学习段轨 / 节拍轨 / 轨道手柄带行
/// 六行的标识。
enum TrackRowId {
  practiceVideo,
  note,
  localMirror,
  learning,
  beat,
  handleStrip,
}

/// 行间间隙（dp）：具名常量，normal 行集与其余行集共用同一取值。
const double kTrackRowGap = 10;

/// 局部镜像轨行高（dp）。
const double kLocalMirrorTrackRowHeight = 30;

/// 备注轨行高（dp）。
const double kNoteTrackRowHeight = 36;

/// 学习段轨行高（dp）。
const double kLearningTrackRowHeight = 48;

/// 节拍轨行高（dp）。
const double kBeatTrackRowHeight = 24;

/// 轨道手柄带行行高（dp）。
const double kHandleStripTrackRowHeight = 30;

/// 单条轨道行：标识、行高、行键（行键为渲染层与测试共同的定位手段）与
/// 轨道片头短标签。
class TrackRow {
  const TrackRow({
    required this.id,
    required this.height,
    required this.key,
    required this.prefixLabel,
  });

  final TrackRowId id;

  /// 行高（dp），恒为正。
  final double height;

  /// 行键字符串（与渲染层的 Key 逐位一致）。
  final String key;

  /// 本行在**轨道片头**列里的短标签：片头标签集 = 行 → 短标签
  /// 的有序映射，行序即本行的声明次序；行不在某态行集内时就没有它的标签。
  /// 标签只是显示文案——不进入 [id]、不进 [key]，也不参与任何定位。
  final String prefixLabel;
}

/// 行矩形：带内纵向「顶」与「高」两个标量。
class TrackRowRect {
  const TrackRowRect({required this.top, required this.height});

  /// 行顶相对带内纵向原点的偏移（dp）。
  final double top;

  /// 行高（dp）。
  final double height;

  /// 行底（含端点口径下属于本行的最大坐标）。
  double get bottom => top + height;

  @override
  bool operator ==(Object other) =>
      other is TrackRowRect && other.top == top && other.height == height;

  @override
  int get hashCode => Object.hash(top, height);

  @override
  String toString() => 'TrackRowRect(top: $top, height: $height)';
}

/// 轨道行表：有序行列表 + 行间间隙，回答行几何三问。
class TrackRowTable {
  const TrackRowTable({required this.rows, required this.gap});

  /// 具名行集 `normal`：备注轨 → 局部镜像轨 → 学习段轨 → 节拍轨 →
  /// 轨道手柄带行（备注轨 36dp 常驻、叠在局部镜像轨之上——
  /// 自下而上 = 手柄带行 → 节拍 → 学习段 → 局部镜像 → 备注）。
  static const TrackRowTable normal = TrackRowTable(
    rows: [
      TrackRow(
        id: TrackRowId.note,
        height: kNoteTrackRowHeight,
        key: 'track_notes',
        prefixLabel: '备注',
      ),
      TrackRow(
        id: TrackRowId.localMirror,
        height: kLocalMirrorTrackRowHeight,
        key: 'track_mirror',
        prefixLabel: '镜像',
      ),
      TrackRow(
        id: TrackRowId.learning,
        height: kLearningTrackRowHeight,
        key: 'track_learning',
        prefixLabel: '分段',
      ),
      TrackRow(
        id: TrackRowId.beat,
        height: kBeatTrackRowHeight,
        key: 'track_beat',
        prefixLabel: '节拍',
      ),
      TrackRow(
        id: TrackRowId.handleStrip,
        height: kHandleStripTrackRowHeight,
        key: 'track_handle_strip_row',
        prefixLabel: '控制',
      ),
    ],
    gap: kTrackRowGap,
  );

  /// 具名行集 `compare`（对比练习）：备注轨（最顶）→ 练习视频轨
  /// → 学习段轨 → 节拍轨（自下而上 = 节拍 → 学习段 → 练习视频 → 备注，
  /// 与编辑态读起来是同一条带）。不含局部镜像轨与轨道手柄带行（首尾线与
  /// 控制柄属于该行承载的编辑面，行缺席即不渲染；有效练习区间约束不受
  /// 影响）。练习视频轨行高与学习段轨同高（48dp），不新增视觉常量。
  /// 练习视频轨的片头标签为「练习」（对比态没有「镜像」这一条——该行不在
  /// 本行集内）。
  static const TrackRowTable compare = TrackRowTable(
    rows: [
      TrackRow(
        id: TrackRowId.note,
        height: kNoteTrackRowHeight,
        key: 'track_notes',
        prefixLabel: '备注',
      ),
      TrackRow(
        id: TrackRowId.practiceVideo,
        height: kLearningTrackRowHeight,
        key: 'track_practice',
        prefixLabel: '练习',
      ),
      TrackRow(
        id: TrackRowId.learning,
        height: kLearningTrackRowHeight,
        key: 'track_learning',
        prefixLabel: '分段',
      ),
      TrackRow(
        id: TrackRowId.beat,
        height: kBeatTrackRowHeight,
        key: 'track_beat',
        prefixLabel: '节拍',
      ),
    ],
    gap: kTrackRowGap,
  );

  /// 有序行列表：顺序即带内自上而下的行序。
  final List<TrackRow> rows;

  /// 行间间隙（dp）；行数 ≤ 1 时不参与整带高。
  final double gap;

  /// 整带高 = Σ行高 + 间隙 × (行数 − 1)；空行集为 0。
  double get totalHeight {
    if (rows.isEmpty) {
      return 0;
    }
    var sum = 0.0;
    for (final row in rows) {
      sum += row.height;
    }
    return sum + gap * (rows.length - 1);
  }

  /// 行集是否声明了某行（行缺席是行集参数的合法状态；渲染与命中层以
  /// 本谓词表达「行集含该行」，不各自用行矩形存在性迂回表达）。
  bool hasRow(TrackRowId id) => rows.any((row) => row.id == id);

  /// 去掉若干行（吃一组行身份、返回新表）：留下的行保持原次序、原行高与
  /// 原行间间隙，其余查询（[totalHeight] / [hasRow] / [rectOf] / [rowAt] /
  /// [prefixLabels]）按新表派生；行集里没有的身份是空操作，全部去掉即空表。
  ///
  /// **本表对档位与空否保持无知**：哪一档去掉哪些行由构造点回答，表只回答
  /// 「去掉这些行之后长什么样」。具名行集 [normal] / [compare] 不受影响——
  /// 它们仍是该态的全行集。
  TrackRowTable withoutRows(Set<TrackRowId> ids) => TrackRowTable(
    rows: [
      for (final row in rows)
        if (!ids.contains(row.id)) row,
    ],
    gap: gap,
  );

  /// 轨道片头标签集：**行 → 短标签**的有序映射，与 [rows] 同序
  /// （自上而下）。条数恒等于该态行集的条数——片头标签列与行集只有这一处
  /// 对应关系，渲染层不另立第二份清单。
  List<String> get prefixLabels => [for (final row in rows) row.prefixLabel];

  /// 某行的片头短标签；**行不在本行集内时为空**（该态下它没有标签，如
  /// 对比态没有「镜像」、编辑态没有「练习」）。
  String? prefixLabelOf(TrackRowId id) {
    for (final row in rows) {
      if (row.id == id) return row.prefixLabel;
    }
    return null;
  }

  /// 某行的矩形（带内顶与高）。行不在本行集内时显式报错（ArgumentError），
  /// 不静默返回空矩形——调用错误在开发期暴露。
  TrackRowRect rectOf(TrackRowId id) {
    var top = 0.0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.id == id) {
        return TrackRowRect(top: top, height: row.height);
      }
      top += row.height + gap;
    }
    throw ArgumentError.value(id, 'id', '行不在本行集内');
  }

  /// 某纵向坐标落在哪一行；无则空。行区间**含两端**且**行优先于间隙**：
  /// 先扫行，只有落在间隙或带外（含负坐标）才返回空。
  TrackRowId? rowAt(double dy) {
    var top = 0.0;
    for (final row in rows) {
      if (dy >= top && dy <= top + row.height) {
        return row.id;
      }
      top += row.height + gap;
    }
    return null;
  }
}
