/// 装载表：打开一支舞时
/// 「谁恢复哪个字段、什么顺序、默认值多少」的**一处声明**。
///
/// **行 = 恢复入口**，[LoadTable.rows] 的声明次序即会话 seam
/// （`VideoOpenRestorer.resolve`）的执行次序。**列 = 文档与段、默认值**；
/// 行的内部（怎么解析、写哪个取值道、缺段怎么补）仍归各自模块，本表不
/// 描述字段细节。
///
/// **执行者两分**：编辑器两行、名册与续播由打开会话按表执行；偏好 / 署名 /
/// 镜像三行的执行归宿主调用点（`player_page._open` 的 `VideoSettingsPersistence`
/// / `SongSignatureController` / `MirrorController`），本表只登记它们的
/// 标识、次序、来源与默认值。宿主三行的实际先后与声明次序一致：
/// 偏好 → 署名解析（含首次导入的命名框） → 镜像 resolve。
///
/// **顺序依赖由声明次序承载**：
/// - 时间线（[LoadRowId.editorPublicMarkers]）先于熟练度与激活段的段序过滤
///   （[LoadRowId.editorLocalPrivate]）——段属性按恢复后的时间线段序挂靠；
/// - 时间线先于续播 seek（[LoadRowId.resume]）——续播位置读恢复后的尾线钳制。
///
/// **加一个每视频字段 = 加一行**（或改该行声明的默认值），不再往打开恢复的
/// 复位函数与模块里各写一次。
///
/// 本模块零框架依赖（不引 Flutter、不引 Riverpod）：只声明取值，可在不启动
/// widget 环境的情况下直测。
library;

/// 恢复入口标识（表的行）。次序即 [LoadTable.rows] 的声明次序；新增一行
/// 会让会话 seam 的穷尽 switch 编译报错（漏执行即红）。
enum LoadRowId {
  /// 编辑器装载：公开标记文件。
  editorPublicMarkers,

  /// 编辑器装载：本地文档。
  editorLocalPrivate,

  /// 偏好装载。
  preferences,

  /// 名册装载。
  roster,

  /// 署名解析（含首次导入的命名框）。
  signature,

  /// 镜像 resolve。
  mirror,

  /// 续播。
  resume,
}

/// 一行取值的文档来源（列：文档与段）。
enum LoadSource {
  /// 公开标记文件（`markers_<hash>.json`）。
  publicMarkers,

  /// 本地文档（`local_<hash>.json`）。
  localPrivate,

  /// 索引条目（`index.json` 的按视频条目）。
  indexEntry,
}

/// 一行落空（缺段 / 空文档 / 无条目）时的字段默认值。
///
/// 只放**打开恢复路径的字段默认值**：打开恢复的复位函数与偏好编排的拍数
/// 回落读它，同一字段在打开恢复路径上的默认值因此只声明一次。取值道的
/// 类型级初始值（各模型 `build()`）与文档解析层的缺键回落是另一层契约
/// （类型初值 / 文件格式），不在此列。
class LoadDefaults {
  const LoadDefaults({
    required this.previewSnapEnabled,
    required this.delayedLoopBeats,
    required this.layoutLocked,
  });

  /// 预览吸附开关默认。
  final bool previewSnapEnabled;

  /// 循环前导拍数默认（拍数而非 player 侧枚举：本表是纯值库，不认识
  /// 取值道类型）。
  final int delayedLoopBeats;

  /// 锁定分段默认。
  final bool layoutLocked;

  /// 偏好行的出厂默认：吸附开 / 前导 4 拍 / 不锁。
  static const LoadDefaults preferences = LoadDefaults(
    previewSnapEnabled: true,
    delayedLoopBeats: 4,
    layoutLocked: false,
  );

  @override
  bool operator ==(Object other) =>
      other is LoadDefaults &&
      other.previewSnapEnabled == previewSnapEnabled &&
      other.delayedLoopBeats == delayedLoopBeats &&
      other.layoutLocked == layoutLocked;

  @override
  int get hashCode =>
      Object.hash(previewSnapEnabled, delayedLoopBeats, layoutLocked);
}

/// 打开恢复的偏好字段默认值：唯一来源 = 装载表。
/// 打开恢复的复位函数与偏好编排的拍数回落都读它，同一字段在打开恢复路径
/// 上的默认值因此只声明一次。
LoadDefaults get loadPreferenceDefaults => LoadDefaults.preferences;

/// 表的一行：标识、文档与段、默认值。
class LoadRow {
  const LoadRow({
    required this.id,
    required this.source,
    required this.segment,
    this.defaults,
  });

  final LoadRowId id;

  final LoadSource source;

  /// 本行读的段（列：文档与段）。
  final String segment;

  /// 本行落空时的字段默认值；null = 本行无字段默认（空文档回落空态，
  /// 字段值归本行模块）。
  final LoadDefaults? defaults;
}

/// 装载表：`rows` 的次序即恢复次序。
class LoadTable {
  const LoadTable(this.rows);

  /// 行序 = 声明次序：会话 seam 按此执行它承接的行；宿主三行的执行归属
  /// 与当前先后见行注与库头。
  final List<LoadRow> rows;

  /// 取某一行。
  LoadRow rowFor(LoadRowId id) => rows.firstWhere((row) => row.id == id);

  /// 打开一支舞的装载表。
  static const LoadTable standard = LoadTable([
    LoadRow(
      id: LoadRowId.editorPublicMarkers,
      source: LoadSource.publicMarkers,
      segment:
          '时间线 / 分段线 / 半拍线 / 首尾 / 重点 / 局部镜像片段 / 备注 / 取景选区',
    ),
    LoadRow(
      id: LoadRowId.editorLocalPrivate,
      source: LoadSource.localPrivate,
      segment: '熟练度 / 激活段',
    ),
    // 执行归宿主调用点（`player_page._open`）；宿主行的实际先后与声明次序
    // 一致（偏好 → 署名 → 镜像）。本表登记它们的标识、次序、来源与默认值。
    LoadRow(
      id: LoadRowId.preferences,
      source: LoadSource.localPrivate,
      segment: '吸附 / 延迟循环 / 锁定分段 / 浮层位 / 练习侧镜像 / 练习片段 / 片段激活',
      defaults: LoadDefaults.preferences,
    ),
    LoadRow(
      id: LoadRowId.roster,
      source: LoadSource.publicMarkers,
      segment: '名册',
    ),
    // 执行归宿主调用点（同上）。含首次导入的命名框：命名框关闭即镜像
    // resolve 开始（先命名、后镜像），两个模态不叠置。
    LoadRow(
      id: LoadRowId.signature,
      source: LoadSource.indexEntry,
      segment: '署名缓存',
    ),
    // 执行归宿主调用点（同上）。
    LoadRow(
      id: LoadRowId.mirror,
      source: LoadSource.indexEntry,
      segment: '镜像过渡值',
    ),
    LoadRow(
      id: LoadRowId.resume,
      source: LoadSource.indexEntry,
      segment: '续播位置',
    ),
  ]);
}
