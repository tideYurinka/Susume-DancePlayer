/// 备注贴纸（markers 顶层 `notes` 段的元素值对象）。
///
/// 一条备注 = 轨道上的**时间窗**片段 + 画面贴纸，一一对应；全部字段
/// 随公开标记文件分享还原。字段：时间窗起止（毫秒，
/// 半开 `[startMs, endMs)`）、`text`
/// （可空串，含点名语法——点名不另存字段、文本是唯一真源）、
/// `locked`（内容锁：只护几何）、`geometry{centerX, centerY, scale}`
/// （视频内容矩形归一化）。**没有 `style`**：正文恒白、点名段取代表色、
/// 描边按底色自动对比——样式是派生的，没有字段可存。
///
/// 列表不变量：按 [NoteSticker.startMs] 升序且两两不重叠，由编辑侧逐
/// verb 维持；消费侧对违规输入优雅降级，不做 reader 校验。
library;

import '../core/document_codec.dart';
import 'interval_fragment_row.dart';
import 'snap.dart' show nearestCandidate;

/// 备注贴纸字段 id（元素类型自带字段单一声明；没有 `refs`、
/// 没有 `style`——样式是派生值，见 [noteSegmentStrokeColor]）。
enum NoteStickerField { startMs, endMs, text, locked, geometry }

/// 贴纸几何字段 id。
enum NoteGeometryField { centerX, centerY, scale }

/// 备注文本单行化：换行（`\r\n` / `\r` / `\n`）归一为空格，
/// 逐个换行各归一为一个空格、不合并不裁剪。贴纸是单行标签——这条口径
/// 在进标注编辑模块之前收口，存盘文本不含换行。
String normalizeNoteText(String text) =>
    text.replaceAll(RegExp('\r\n|\r|\n'), ' ');

/// 贴纸默认落点（观感值，真机看版项）：水平居中、
/// 纵向自内容矩形顶边下移约 12%、等比系数 1.0。
const double noteDefaultCenterX = 0.5;
const double noteDefaultCenterY = 0.12;
const double noteDefaultScale = 1.0;

/// 贴纸等比系数钳制界（观感值，真机看版项；「缩放不越界」）。
const double noteMinScale = 0.5;
const double noteMaxScale = 4.0;

/// 备注正文填充色（正文恒为白——样式没有可调项）。
const int kNoteBodyColor = 0xFFFFFFFF;

/// 描边取色判据阈值（感知亮度
/// `(0.299R + 0.587G + 0.114B) / 255` 严格大于该值描黑边。观感值，
/// 真机看版项）。
const double kNoteStrokeLuminanceThreshold = 0.40;

/// 描边黑色支（真机看版项）。
const int kNoteStrokeBlackColor = 0xFF000000;

/// 描边白色支（真机看版项）。
const int kNoteStrokeWhiteColor = 0xFFFFFFFF;

/// 一个段的描边取色（纯函数；判据按**段**、不按字）：
/// 正文段（[mention] = false）固定黑边、不走亮度判据；点名段底色为
/// 纯白时固定白边（好与白色正文分得开），其余按感知亮度
/// `(0.299R + 0.587G + 0.114B) / 255 > [kNoteStrokeLuminanceThreshold]`
/// 描黑边、否则描白边。
int noteSegmentStrokeColor(int fillColor, {required bool mention}) {
  if (!mention) return kNoteStrokeBlackColor;
  if (fillColor == kNoteBodyColor) return kNoteStrokeWhiteColor;
  final r = (fillColor >> 16) & 0xFF;
  final g = (fillColor >> 8) & 0xFF;
  final b = fillColor & 0xFF;
  final luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  return luminance > kNoteStrokeLuminanceThreshold
      ? kNoteStrokeBlackColor
      : kNoteStrokeWhiteColor;
}

/// 纯白点名段**外层黑边**的取色（纯函数）：点名段底色为纯白时
/// 返回黑——白描边之外再包的一层更细黑边；其余一律 null（不挂外层）。
int? noteSegmentOuterStrokeColor(int fillColor, {required bool mention}) =>
    mention && fillColor == kNoteBodyColor ? kNoteStrokeBlackColor : null;

/// 贴纸几何钳制（模块内单点）：中心钳进内容矩形归一化域 [0,1]、
/// 系数钳进 [noteMinScale, noteMaxScale]——像素矩形完整留在画面内由渲染
/// 侧按钳制框收敛（noteStickerRect），角工具恒可达。
NoteGeometry clampNoteGeometry(NoteGeometry geometry) => NoteGeometry(
  centerX: geometry.centerX.clamp(0.0, 1.0),
  centerY: geometry.centerY.clamp(0.0, 1.0),
  scale: geometry.scale.clamp(noteMinScale, noteMaxScale),
);

/// 贴纸几何（值对象）：中心点与等比系数，按视频内容矩形归一化
/// （位置取中心归一化，大小取等比系数；跨分辨率可还原）。
class NoteGeometry {
  const NoteGeometry({
    this.centerX = noteDefaultCenterX,
    this.centerY = noteDefaultCenterY,
    this.scale = noteDefaultScale,
  });

  /// 中心点横坐标（内容矩形归一化，0–1）。
  final double centerX;

  /// 中心点纵坐标（内容矩形归一化，0–1）。
  final double centerY;

  /// 等比缩放系数。
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is NoteGeometry && _noteGeometryCodec.equals(this, other);

  @override
  int get hashCode => _noteGeometryCodec.hash(this);
}

/// 一条备注贴纸（不可变值对象）。
///
/// 时间窗为半开 `[startMs, endMs)`（毫秒），钳在视频首尾区间内；同表
/// 按 [startMs] 升序且两两不重叠（不变量由编辑侧维持）。
class NoteSticker {
  const NoteSticker({
    required this.startMs,
    required this.endMs,
    this.text = '',
    this.locked = false,
    this.geometry = const NoteGeometry(),
    this.extra = const {},
  });

  /// 时间窗起点（毫秒，含）。
  final int startMs;

  /// 时间窗终点（毫秒，不含——半开区间）。
  final int endMs;

  /// 备注文本。空串不是可保存状态——编辑器收起时归一国空即删除这条备注
  /// （见 `note_editor.dart` 的收起路径），因此本应用不产生空文本备注；
  /// 既有文件里已存在的空文本不主动清理。
  final String text;

  /// 内容锁（公开、随分享）：只保护几何（贴纸位置/大小 + 时间窗的
  /// 整体移与端点拖）；文本 / 本开关豁免。
  final bool locked;

  /// 贴纸几何（内容矩形归一化）。
  final NoteGeometry geometry;

  /// 未知键保底区（原样带回、写回原样；不参与相等比较）。
  final Map<String, Object?> extra;

  /// 写定字段（纯函数：返回新实例，原实例不变；未给字段与保底区原样
  /// 携带——新字段落于此处即自动进入保底区透传路径）。
  NoteSticker copyWith({
    int? startMs,
    int? endMs,
    String? text,
    bool? locked,
    NoteGeometry? geometry,
    Map<String, Object?>? extra,
  }) => NoteSticker(
    startMs: startMs ?? this.startMs,
    endMs: endMs ?? this.endMs,
    text: text ?? this.text,
    locked: locked ?? this.locked,
    geometry: geometry ?? this.geometry,
    extra: extra ?? this.extra,
  );

  /// 相等/哈希由字段声明派生（保底区不参与）。
  @override
  bool operator ==(Object other) =>
      other is NoteSticker && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);

  @override
  String toString() =>
      'NoteSticker(startMs: $startMs, endMs: $endMs, text: $text)';

  /// 自带编解码（键名/读/写/相等在同一处声明）。
  static const RecordCodec<NoteSticker, NoteStickerField> codec =
      RecordCodec<NoteSticker, NoteStickerField>(
        ids: NoteStickerField.values,
        decl: _decl,
        build: _build,
        extraOf: _extraOf,
        withExtra: _withExtra,
        required: {NoteStickerField.startMs, NoteStickerField.endMs},
      );

  /// 写出（元素层保底区先展开，已登记字段后写）。
  Map<String, Object?> toJson() => codec.encode(this);

  /// 读取；`startMs`/`endMs` 任一缺失或类型不符（必填）视为损坏条目，
  /// 返回 null（调用方丢弃）。
  static NoteSticker? fromJson(Object? raw) => codec.tryDecode(raw);

  /// 元素表 ↔ JSON 数组：跳过损坏条目、保留合法项。
  static List<NoteSticker> fromJsonList(Object? raw) => codec.decodeList(raw);
}

FieldDecl<NoteSticker> _decl(NoteStickerField id) => switch (id) {
  NoteStickerField.startMs => FieldDecl(
    key: 'startMs',
    read: (json) => switch (json['startMs']) {
      int v => v,
      _ => null,
    },
    write: (note) => note.startMs,
    equal: (a, b) => a.startMs == b.startMs,
  ),
  NoteStickerField.endMs => FieldDecl(
    key: 'endMs',
    read: (json) => switch (json['endMs']) {
      int v => v,
      _ => null,
    },
    write: (note) => note.endMs,
    equal: (a, b) => a.endMs == b.endMs,
  ),
  NoteStickerField.text => FieldDecl(
    key: 'text',
    read: (json) => json['text'] is String ? json['text'] as String : '',
    write: (note) => note.text,
    equal: (a, b) => a.text == b.text,
  ),
  NoteStickerField.locked => FieldDecl(
    key: 'locked',
    read: (json) => json['locked'] is bool ? json['locked'] as bool : false,
    write: (note) => note.locked,
    equal: (a, b) => a.locked == b.locked,
  ),
  NoteStickerField.geometry => FieldDecl(
    key: 'geometry',
    read: (json) => _noteGeometryCodec.decode(
      json['geometry'] is Map<String, Object?>
          ? json['geometry'] as Map<String, Object?>
          : const {},
    ),
    write: (note) => _noteGeometryCodec.encode(note.geometry),
    equal: (a, b) => a.geometry == b.geometry,
  ),
};

NoteSticker _build(Map<NoteStickerField, Object?> values) => NoteSticker(
  startMs: values[NoteStickerField.startMs] as int? ?? 0,
  endMs: values[NoteStickerField.endMs] as int? ?? 0,
  text: values[NoteStickerField.text] as String,
  locked: values[NoteStickerField.locked] as bool,
  geometry: values[NoteStickerField.geometry] as NoteGeometry,
);

Map<String, Object?> _extraOf(NoteSticker note) => note.extra;

NoteSticker _withExtra(NoteSticker note, Map<String, Object?> extra) =>
    note.copyWith(extra: extra);

const _noteGeometryCodec = RecordCodec<NoteGeometry, NoteGeometryField>(
  ids: NoteGeometryField.values,
  decl: _noteGeometryDecl,
  build: _buildNoteGeometry,
  extraOf: _extraOfNone,
  withExtra: _withExtraNone,
);

FieldDecl<NoteGeometry> _noteGeometryDecl(NoteGeometryField id) => switch (id) {
  NoteGeometryField.centerX => FieldDecl(
    key: 'centerX',
    read: (json) => (json['centerX'] as num?)?.toDouble() ?? noteDefaultCenterX,
    write: (geometry) => geometry.centerX,
    equal: (a, b) => a.centerX == b.centerX,
  ),
  NoteGeometryField.centerY => FieldDecl(
    key: 'centerY',
    read: (json) => (json['centerY'] as num?)?.toDouble() ?? noteDefaultCenterY,
    write: (geometry) => geometry.centerY,
    equal: (a, b) => a.centerY == b.centerY,
  ),
  NoteGeometryField.scale => FieldDecl(
    key: 'scale',
    read: (json) => (json['scale'] as num?)?.toDouble() ?? noteDefaultScale,
    write: (geometry) => geometry.scale,
    equal: (a, b) => a.scale == b.scale,
  ),
};

NoteGeometry _buildNoteGeometry(Map<NoteGeometryField, Object?> values) =>
    NoteGeometry(
      centerX: values[NoteGeometryField.centerX] as double,
      centerY: values[NoteGeometryField.centerY] as double,
      scale: values[NoteGeometryField.scale] as double,
    );

Map<String, Object?> _extraOfNone<T>(T value) => const {};

/// 已登记边界（评审登记）：透传止步于元素级（口径：段内与文档级）。
/// `geometry` 子对象内的未知键读取即丢——子对象是本版本封闭 schema，
/// 扩展时在此加 extra 车道，不可静默依赖透传。旧文件里的 `style` 键
/// 落元素保底区、原样透传（v5 起不再被解释）。
T _withExtraNone<T>(T value, Map<String, Object?> extra) => value;

/// 占用谓词（半开窗）：预览线 [at] 落在某条既有备注的
/// 时间窗 `[startMs, endMs)` 内。
bool noteLandingOccupied(List<NoteSticker> notes, Duration at) {
  final atMs = at.inMilliseconds;
  return notes.any((note) => note.startMs <= atMs && atMs < note.endMs);
}

/// 备注表 → 区间表（共用件换算的统一入口）。
List<IntervalSpan> _noteSpans(List<NoteSticker> notes) => [
  for (final note in notes)
    IntervalSpan(startMs: note.startMs, endMs: note.endMs),
];

/// 新建备注落点解析（模块内唯一一处；纯函数）：
///
///   ① 请求位置 [requestMs] 钳入视频首尾区间；
///   ② 钳后位置落在既有备注窗内 ⇒ **不建**（返回 null）；
///   ③ 起点吸「**自由区间内的最近拍点**」：从 [beatPoints] 中取不落在既有
///      备注窗内的最近者（每个拍点都是合法起点，不按八拍点分级；等距并列
///      取时间靠后者）。无自由拍点 ⇒ 落点退化为请求位置（照常创建，不静默
///      no-op；调用方以空拍点表表达「网格未就绪、不吸附」）；
///   ④ 终点 = 起点 + [widthMs]，向视频尾与**右邻备注起点**截断
///      （截断数学收口于共用件 [truncatedNewSpan]）；零宽不成立（返回
///      null）。
///
/// 几何初值 = 落点左侧紧邻的那一条备注的几何（值拷贝，取初值不改任何既有
/// 备注）；左侧没有任何备注（首条 / 落在所有既有备注之前）→ 具名默认落点
/// （[NoteGeometry] 的三个常量）。
NoteSticker? resolveNoteInsertion({
  required List<NoteSticker> notes,
  required int requestMs,
  required int rangeStartMs,
  required int rangeEndMs,
  required Iterable<Duration> beatPoints,
  required int widthMs,
}) {
  if (rangeEndMs <= rangeStartMs) return null;
  var point = requestMs;
  if (point < rangeStartMs) point = rangeStartMs;
  if (point > rangeEndMs) point = rangeEndMs;
  if (noteLandingOccupied(notes, Duration(milliseconds: point))) return null;
  final snapped = nearestCandidate(
    beatPoints.where((beat) => !noteLandingOccupied(notes, beat)),
    Duration(milliseconds: point),
  );
  final startMs = snapped?.inMilliseconds ?? point;
  final span = truncatedNewSpan(
    spans: _noteSpans(notes),
    startMs: startMs,
    widthMs: widthMs,
    rangeEndMs: rangeEndMs,
  );
  if (span == null) return null;
  final index = spanInsertionIndex(_noteSpans(notes), span.startMs);
  return NoteSticker(
    startMs: span.startMs,
    endMs: span.endMs,
    geometry: index == 0 ? const NoteGeometry() : notes[index - 1].geometry,
  );
}

/// 整体移：把 [index] 处备注的时间窗平移为新起点 [newStartMs]
///（宽度不变，其余字段原样携带），并与相邻备注 + 视频首尾互斥钳制。
/// 钳空（无可放置区间）= 返回 null = no-op（拖动静默停住）。钳制数学
/// 收口于共用件 [moveSpanClamped]（区间片段行共用纪律，不自带第三份）。
NoteSticker? moveNoteClamped({
  required List<NoteSticker> notes,
  required int index,
  required int rangeStartMs,
  required int rangeEndMs,
  required int newStartMs,
}) {
  final moved = moveSpanClamped(
    spans: _noteSpans(notes),
    index: index,
    rangeStartMs: rangeStartMs,
    rangeEndMs: rangeEndMs,
    newStartMs: newStartMs,
  );
  if (moved == null) return null;
  return notes[index].copyWith(startMs: moved.startMs, endMs: moved.endMs);
}

/// 端点拖：把 [index] 处备注的 [edge] 端拖到 [edgeMs]（另一端
/// 不动，其余字段原样携带），并与相邻备注 + 视频首尾互斥钳制；端点不得
/// 倒置（拖过对端 = 返回 null = no-op）。钳制数学收口于共用件
/// [dragSpanEdgeClamped]。
NoteSticker? dragNoteEdgeClamped({
  required List<NoteSticker> notes,
  required int index,
  required IntervalEdge edge,
  required int rangeStartMs,
  required int rangeEndMs,
  required int edgeMs,
}) {
  final dragged = dragSpanEdgeClamped(
    spans: _noteSpans(notes),
    index: index,
    edge: edge,
    rangeStartMs: rangeStartMs,
    rangeEndMs: rangeEndMs,
    edgeMs: edgeMs,
  );
  if (dragged == null) return null;
  return notes[index].copyWith(startMs: dragged.startMs, endMs: dragged.endMs);
}
