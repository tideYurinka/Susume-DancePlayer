/// 通用文档编解码机制＋文档版本政策。
///
/// 调用方在**一处**声明字段：字段 id 枚举 + 穷尽 switch（每个 case 给出
/// JSON 键名、读、写、相等语义）；机制由此派生序列化、反序列化、相等与
/// 哈希、逐层陌生键保底、版本演进。新增字段 = 枚举加一项 → 穷尽 switch
/// **编译报错** → 键名/读/写/相等四处不可能漏。
///
/// 三级容器同一套机制：
/// - 元素（[RecordCodec] 直接用于元素模型）；
/// - 段（[RecordCodec] + 值类型自带 extra）；
/// - 文档（[DocumentCodec]：各段键 + 文档级 extra；[ListDocumentCodec]：
///   版本号 + 一个元素列表）。
///
/// 写盘顺序契约：保底区（extra）先展开，已登记字段（含 `version`）后写
/// ——保底区永不可能覆盖已登记字段。保底区不参与相等比较。
///
/// 契约（不变量，违反即 bug）：
/// - **声明式**：字段只在穷尽 switch 一处声明，漏一个 case = 编译错，
///   键名/读/写/相等四处不可能漏；
/// - **逐层保底**：文档、段、元素任意深度，未知键原样带回、写回原样，
///   且永不可能覆盖已登记字段（写盘顺序保证）；
/// - **版本判据**：两个 codec 形状都收**同一份**文档版本政策
///   （地板 + 按序迁移链），版本号、迁移表、「更高版本只读」旗标不再各带
///   一份。读面沿政策把盘上 JSON 升到本版再读；「高于本版」与「版本头读
///   不出」都按「认识多少读多少」打开（不整份丢弃也不读空），只由写侧
///   [DocumentVersionPolicy.isWritable] 判定不可写；空态只剩两个来源——
///   文件不在、本体解析不出对象（后者由调用方的顶层判据承接）；
/// - **可空字段的未设哨兵**：`null` 是合法值（清空）；「未变更/未设置」
///   由 [FieldDecl.write] 返回 [omitField] 表达（键不落盘），二者是不同
///   状态。
library;

import 'document_version_policy.dart';

/// 写盘省略标记：字段声明中 [FieldDecl.write] 返回 [omitField] 表示
/// 「本次不写该键」（未设哨兵字段的常规用法）。
class JsonOmit {
  const JsonOmit._();
}

const JsonOmit omitField = JsonOmit._();

/// 单个字段在同一处声明的四件事：JSON 键名、读（JSON → 值）、写
/// （值 → JSON）、相等语义。
class FieldDecl<V> {
  const FieldDecl({
    required this.key,
    required this.read,
    required this.write,
    required this.equal,
    this.shareable = false,
  });

  /// 该字段的 JSON 键名。
  final String key;

  /// 从所在容器 JSON 对象读出字段值（缺失/类型不符时自行给默认）。
  final Object? Function(Map<String, Object?> json) read;

  /// 从值对象写出 JSON 值；返回 [omitField] 表示本次不写该键。
  final Object? Function(V value) write;

  /// 两值在该字段上的相等语义。
  final bool Function(V a, V b) equal;

  /// 该字段是否进入可分享投影（[RecordCodec.projectJson]）：**缺省不进包**，
  /// 新增字段必须显式标注才会随包流出。嵌套值对象随其父字段整体进出。
  final bool shareable;
}

/// 段/元素的编解码器：由字段 id 枚举 + 穷尽 switch 声明派生读写、相等、
/// 哈希与陌生键保底。
class RecordCodec<V, F extends Enum> {
  const RecordCodec({
    required this.ids,
    required this.decl,
    required this.build,
    required this.extraOf,
    required this.withExtra,
    this.required = const {},
  });

  /// 全部字段 id（穷尽 switch 的论域）。必须传**全量**枚举值（通常
  /// `X.values`）；传子集会让编解码/相等/哈希静默丢字段。
  final List<F> ids;

  /// 字段声明（穷尽 switch；漏一个 case = 编译错）。
  final FieldDecl<V> Function(F id) decl;

  /// 必填字段集合（元素层语义）：这些字段的 [FieldDecl.read] 读出 null
  /// 视为损坏条目，[tryDecode]/[decodeList] 整条丢弃。键名与判空只在
  /// 声明一处：必填字段的 `read` 对缺失/类型不符返回 null，[decode]
  /// 的 `build` 自行给默认值兜底。
  final Set<F> required;

  /// 由各字段值装配值对象。
  final V Function(Map<F, Object?> values) build;

  /// 读出值对象的陌生键保底区。
  final Map<String, Object?> Function(V value) extraOf;

  /// 把保底区装回值对象。
  final V Function(V value, Map<String, Object?> extra) withExtra;

  /// 序列化：保底区先展开，已登记字段后写（保底区不覆盖已登记字段）；
  /// [omitField] 的键不写。
  Map<String, Object?> encode(V value) {
    final out = {...extraOf(value)};
    for (final id in ids) {
      final d = decl(id);
      final written = d.write(value);
      if (written is! JsonOmit) {
        out[d.key] = written;
      }
    }
    return out;
  }

  /// 反序列化：已登记字段逐个读出，未知键收进保底区原样带回。
  V decode(Map<String, Object?> json) {
    final known = {for (final id in ids) decl(id).key};
    final extra = _collectExtra(json, known);
    final values = {for (final id in ids) id: decl(id).read(json)};
    return withExtra(build(values), extra);
  }

  /// 可分享投影：只保留标记 [FieldDecl.shareable] 的已登记字段，值逐字
  /// 保留（不做编解码往返）；非可分享字段与未登记键（保底区）一律剔除
  /// ——新字段默认不进包。
  Map<String, Object?> projectJson(Map<String, Object?> json) => {
    for (final id in ids)
      if (decl(id).shareable && json.containsKey(decl(id).key))
        decl(id).key: json[decl(id).key],
  };

  /// 严格读取单条元素：非 JSON 对象、或任一 [required] 字段缺失/类型
  /// 不符（read 为 null）→ 返回 null（调用方按损坏条目丢弃）。
  V? tryDecode(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    for (final id in required) {
      if (decl(id).read(json) == null) return null;
    }
    return decode(json);
  }

  /// 元素表 ↔ JSON 数组：跳过损坏条目（见 [tryDecode]）、保留合法项；
  /// 非列表整体按空表兜底。
  List<V> decodeList(Object? raw) {
    if (raw is! List) return const [];
    return [for (final item in raw) ?tryDecode(item)];
  }

  /// 相等：只比较已登记字段，保底区不参与；段值可缺席（null = 双双
  /// 缺席相等，缺席 vs 在席不等，见 [SectionDecl.absentOf]）。
  bool equals(V a, V b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return ids.every((id) => decl(id).equal(a, b));
  }

  /// 哈希：由各字段的写出 JSON 值深哈希派生（保底区不参与；缺席段值
  /// 哈希为 0）。
  ///
  /// 声明契约：字段声明的 `equal` 判相等 ⇒ 该字段的 `write` 必须产出
  /// 相同 JSON 值（含 [omitField] 对齐），否则 [hash] 与 [equals] 失配。
  int hash(V value) => value == null
      ? 0
      : jsonDeepHash([
          for (final id in ids) decl(id).write(value),
        ]);
}

/// 把 JSON 对象中不属于已知键的项收进保底区（原样带回）。
Map<String, Object?> _collectExtra(
  Map<String, Object?> json,
  Set<String> known,
) => {
  for (final entry in json.entries)
    if (!known.contains(entry.key)) entry.key: entry.value,
};

/// 文档级单个段的声明：段键名 + 段值编解码器 + 从文档取出段值。
class SectionDecl<D> {
  const SectionDecl({
    required this.key,
    required this.codec,
    required this.sectionOf,
    this.absentOf,
  });

  /// 段的 JSON 键名。
  final String key;

  /// 可缺席段：返回 true 表示文档中该段缺席——写侧省略该段键，读侧
  /// 段键缺失得到 **null 段值**（`sectionOf` 的返回类型因此可为可空）。
  /// 未设 = 段恒在，读侧段键缺失按空对象读默认值。
  final bool Function(D doc)? absentOf;

  /// 段值的编解码器（段值类型在此擦除为 dynamic；键名/读/写/相等的
  /// 编译期保证由文档级穷尽 switch 的声明侧承担）。
  final RecordCodec<dynamic, dynamic> codec;

  /// 从文档读出该段值。
  final Object? Function(D doc) sectionOf;
}

/// 文档级编解码器：版本政策 + 各段 + 文档级陌生键保底。
class DocumentCodec<D, S extends Enum> {
  const DocumentCodec({
    required this.policy,
    required this.ids,
    required this.decl,
    required this.empty,
    required this.build,
    required this.extraOf,
    required this.withExtra,
  });

  /// 该文档的版本链（地板 + 按序迁移步骤）：本版版本号是链尾派生量，
  /// 版本事实只此一处声明，两个 codec 形状共用同一份政策的形状。
  final DocumentVersionPolicy policy;

  final List<S> ids;

  /// 段声明（穷尽 switch；漏一个 case = 编译错）。
  final SectionDecl<D> Function(S id) decl;

  /// 空态兜底（文件不在或低于地板时按此返回）。
  final D Function() empty;

  /// 由各段值装配文档。
  final D Function(Map<S, Object?> sections) build;

  /// 读出文档级陌生键保底区。
  final Map<String, Object?> Function(D doc) extraOf;

  /// 把保底区装回文档。
  final D Function(D doc, Map<String, Object?> extra) withExtra;

  /// 序列化：保底区先展开，`version`（本版链尾）与各段后写（保底区不
  /// 覆盖它们）；可缺席段缺席时省略该段键（见 [SectionDecl.absentOf]）。
  Map<String, Object?> encode(D doc) {
    final out = {...extraOf(doc)};
    out['version'] = policy.currentVersion;
    for (final id in ids) {
      final d = decl(id);
      if (d.absentOf?.call(doc) == true) continue;
      out[d.key] = d.codec.encode(d.sectionOf(doc));
    }
    return out;
  }

  /// 反序列化（版本政策）：政策 [DocumentVersionPolicy.upgrade]
  /// 把盘上 JSON 升到本版再读——低于地板 → 空态兜底；在链上（含中间版本）
  /// → 逐级升位后各段照读；**高于本版**与**版本头读不出** → 按「认识多少
  /// 读多少」打开，只由写侧 [DocumentVersionPolicy.isWritable] 判不可写。
  D decode(Map<String, Object?> json) {
    final upgrade = policy.upgrade(json);
    if (upgrade.json.isEmpty) return empty();
    final effective = upgrade.json;
    final known = {
      'version',
      for (final id in ids) decl(id).key,
    };
    final extra = _collectExtra(effective, known);
    final sections = <S, Object?>{
      for (final id in ids)
        id: () {
          final d = decl(id);
          final rawSection = effective[d.key];
          if (rawSection == null && d.absentOf != null) return null;
          return d.codec.decode(_sectionJson(rawSection));
        }(),
    };
    return withExtra(build(sections), extra);
  }

  static Map<String, Object?> _sectionJson(Object? raw) =>
      raw is Map<String, Object?> ? raw : const {};

  /// 可分享投影：保留 `version` 与各段经 [RecordCodec.projectJson] 的结果
  /// （段投影为空则不写该段键）；文档级未登记键（保底区）一律剔除。
  Map<String, Object?> projectJson(Map<String, Object?> json) {
    final out = <String, Object?>{};
    if (json.containsKey('version')) out['version'] = json['version'];
    for (final id in ids) {
      final d = decl(id);
      final raw = json[d.key];
      if (raw is! Map<String, Object?>) continue;
      final section = d.codec.projectJson(raw);
      if (section.isNotEmpty) out[d.key] = section;
    }
    return out;
  }

  /// 相等：逐段比较（缺席段双双缺席相等、缺席 vs 在席不等），文档级
  /// 保底区不参与。
  bool equals(D a, D b) => ids.every((id) {
    final d = decl(id);
    final va = d.sectionOf(a);
    final vb = d.sectionOf(b);
    if (va == null || vb == null) return identical(va, vb);
    return d.codec.equals(va, vb);
  });

  /// 哈希：由各段哈希派生（保底区不参与；缺席段贡献 0）。
  int hash(D doc) {
    final sectionHashes = <int>[];
    for (final id in ids) {
      final value = decl(id).sectionOf(doc);
      sectionHashes.add(value == null ? 0 : decl(id).codec.hash(value));
    }
    return Object.hashAll(sectionHashes);
  }
}

/// 单列表文档编解码器：`version` + 一个元素列表。
///
/// 顶层只有「版本号 + 一个列表」的文档（视频索引、练习统计）没有多个
/// 写入者，无需分段；文档级陌生键保底与 [DocumentCodec] 同款，元素列表
/// 的读、写、相等、保底由 [elementCodec] 的字段声明派生。版本演进收
/// **同一份** [DocumentVersionPolicy]（与 [DocumentCodec] 共用政策形状），
/// 列表形状因此第一次获得沿链升位的能力，不再「版本不等即丢弃」。
class ListDocumentCodec<D, E, F extends Enum> {
  const ListDocumentCodec({
    required this.policy,
    required this.listKey,
    required this.elementCodec,
    required this.empty,
    required this.build,
    required this.listOf,
    required this.extraOf,
    required this.withExtra,
  });

  /// 该文档的版本链（地板 + 按序迁移步骤）：版本事实只此一处声明。
  final DocumentVersionPolicy policy;

  /// 元素列表的 JSON 键名。
  final String listKey;

  /// 元素编解码器（字段 id 枚举 + 穷尽 switch 声明）。
  final RecordCodec<E, F> elementCodec;

  /// 空态兜底（文件不在/低于地板/列表非 List 时按此返回）。
  final D Function() empty;

  /// 由元素列表装配文档。
  final D Function(List<E> elements) build;

  /// 读出文档的元素列表。
  final List<E> Function(D doc) listOf;

  /// 读出文档级陌生键保底区。
  final Map<String, Object?> Function(D doc) extraOf;

  /// 把保底区装回文档。
  final D Function(D doc, Map<String, Object?> extra) withExtra;

  /// 序列化：保底区先展开，`version`（本版链尾）与元素列表后写（保底区
  /// 不覆盖它们）。
  Map<String, Object?> encode(D doc) => {
    ...extraOf(doc),
    'version': policy.currentVersion,
    listKey: [for (final e in listOf(doc)) elementCodec.encode(e)],
  };

  /// 相等：元素逐个经 [elementCodec] 比较（长度不等先判不等），保底区
  /// 不参与。文档模型是否暴露 `==` 由接入方决定（store 以 identical 判
  /// 「未变更跳写」时保持恒等比较更直观）。
  bool equals(D a, D b) {
    final la = listOf(a);
    final lb = listOf(b);
    if (la.length != lb.length) return false;
    for (var i = 0; i < la.length; i++) {
      if (!elementCodec.equals(la[i], lb[i])) return false;
    }
    return true;
  }

  /// 哈希：由各元素哈希派生（保底区不参与）。
  int hash(D doc) => Object.hashAll([
    for (final e in listOf(doc)) elementCodec.hash(e),
  ]);

  /// 反序列化（版本政策）：政策 [DocumentVersionPolicy.upgrade]
  /// 把盘上 JSON 升到本版再读——低于地板 → 空态兜底；在链上（含中间版本）
  /// → 逐级升位后元素逐个经 [elementCodec] 读；**高于本版**与**版本头读
  /// 不出** → 按「认识多少读多少」打开（列表照读、未知键收进保底区），只
  /// 由写侧 [DocumentVersionPolicy.isWritable] 判不可写；列表非 List →
  /// 空态兜底；非对象成员与必填字段缺失的损坏条目整条丢弃。
  D decode(Map<String, Object?> json) {
    final effective = policy.upgrade(json).json;
    final raw = effective[listKey];
    if (raw is! List) return empty();
    final elements = <E>[
      for (final item in raw)
        if (item is Map<String, Object?>) ?elementCodec.tryDecode(item),
    ];
    return withExtra(
      build(elements),
      _collectExtra(effective, {'version', listKey}),
    );
  }
}

/// JSON 值的深相等（List/Map 递归；数值按数值相等，`1 == 1.0`）。供字段
/// 声明中的列表/嵌套值相等语义使用。
bool jsonDeepEquals(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(
          a.length,
          (i) => jsonDeepEquals(a[i], b[i]),
        ).every((ok) => ok);
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    return a.entries.every(
      (e) => b.containsKey(e.key) && jsonDeepEquals(e.value, b[e.key]),
    );
  }
  return a == b;
}

/// JSON 值的深哈希（与 [jsonDeepEquals] 一致：数值哈希经 double 归一，
/// `1` 与 `1.0` 相等且同哈希）。
int jsonDeepHash(Object? value) {
  if (value is num) return value.toDouble().hashCode;
  if (value is List) {
    return Object.hashAll([for (final v in value) jsonDeepHash(v)]);
  }
  if (value is Map) {
    var hash = 0;
    for (final entry in value.entries) {
      hash = Object.hash(hash, entry.key, jsonDeepHash(entry.value));
    }
    return hash;
  }
  return value.hashCode;
}
