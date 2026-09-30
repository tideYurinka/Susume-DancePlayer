/// 文档版本政策纯件：**文档地板 + 按序迁移步骤**。
///
/// 一份文档的版本谱系在此一处声明：地板（该文档在首个发布版 v0.1.0 的
/// 版本号，历史常量、声明一次永不改）加上按序排列的迁移步骤；**本版
/// 版本号是链尾派生量**（[DocumentVersionPolicy.currentVersion]），
/// 不单独声明、不单独可写——「抬了版本号却忘了写迁移」在类型上写不出
/// 来，唯一的抬版本方式是追加一级（且新级别必须紧接链尾，乱序、倒退、
/// 跳级的声明在构造期即失败）。
///
/// 一个行为入口 [DocumentVersionPolicy.upgrade]：给定盘上 JSON，返回
/// 「升到本版后的 JSON」与「是否可写」。分类梯固定六支：
///
/// | 分支 | 返回的 JSON | 可写 |
/// |---|---|---|
/// | 文件不在（`null`） | 空 JSON | ✅ |
/// | 本体解析不出对象 | 空 JSON | ❌ |
/// | 版本头不是整数 | 原样 | ❌ |
/// | 高于本版 | 原样（零拷贝） | ❌ |
/// | 低于地板 | 空 JSON | ❌ |
/// | 在链上（含中间版本） | 升到本版 | ✅ |
///
/// 三条裁决：地板是唯一许可「读空」的凭据；版本判据只决定
/// 可写性、从不决定读空；不给「更高版本时是只读还是重建」留开关——
/// 更高版本一律原样 + 不可写。
library;

/// 一级迁移：`from` 版本的 JSON → 下一版本的 JSON。
///
/// 步骤是纯函数：**只改形状、不写版本号**（政策在每级之后自己写），
/// 且必须浅拷贝原 JSON，使文档级/段级/元素级的逐层陌生键保底区随行。
class MigrationStep {
  const MigrationStep(this.from, this.up);

  /// 该级迁入的源版本号，必须恰为链上它所在位置的版本
  /// （首级 = 地板，其后逐级 +1）。
  final int from;

  /// 「该版本 JSON → 下一版本 JSON」的纯函数。
  final Map<String, Object?> Function(Map<String, Object?> json) up;
}

/// 版本判据的具名分支（六支分类梯的「哪一支」）。
///
/// [upgrade] 只交回载荷与可写性；本枚举让文件层把「只读」的**原因**具名
/// 带给一等读结局。三分支只读（[aboveCurrent] / [belowFloor] /
/// [unreadableHeader]）与两个空态来源（[absent] / [notAnObject]）都由它
/// 区分，文件层不必重抄判据。
enum DocumentVersionVerdict {
  /// 文件不在（`null`）：可写、可创建。
  absent,

  /// 本体解析不出对象：空态、不可写。
  notAnObject,

  /// 版本头不是整数：只读（内容没读懂，不改一字）。
  unreadableHeader,

  /// 高于本版：只读、原样。
  aboveCurrent,

  /// 低于地板：只读、空态（唯一许可读空的凭据）。
  belowFloor,

  /// 在链上（含需要逐级升位的中间版本）：可写。
  onChain;

  /// 该分支是否可写（可覆盖）。
  bool get isWritable => this == absent || this == onChain;
}

/// [DocumentVersionPolicy.upgrade] 的读结局：升位后的 JSON 与可写性。
class PolicyUpgrade {
  const PolicyUpgrade(this.json, this.writable);

  /// 升到本版后的 JSON（分支语义见库注释的分类梯）。
  final Map<String, Object?> json;

  /// 该文件是否可写（可覆盖）。只读结局没有后续写回，覆盖一份没读懂
  /// 的文件从调用面不可达。
  final bool writable;
}

/// 文档版本政策：地板 + 按序迁移链，行为入口 [upgrade]。
class DocumentVersionPolicy {
  /// 声明即校验：步骤必须从地板起逐级紧邻（`steps[i].from == floor + i`），
  /// 乱序、倒退、跳级（=「抬版本号却缺一级」）在构造期即失败。
  DocumentVersionPolicy({
    required this.floor,
    this.steps = const [],
  }) {
    for (var i = 0; i < steps.length; i++) {
      final expected = floor + i;
      if (steps[i].from != expected) {
        throw ArgumentError(
          '迁移链在第 $i 级断开：期望 from=$expected，实为 ${steps[i].from}'
          '（地板 $floor 必须逐级无缝连到链尾，不允许乱序、倒退或跳级）',
        );
      }
    }
  }

  /// 文档地板：该文档在首个发布版 v0.1.0 的版本号。历史常量，声明一次
  /// 永不改变。
  final int floor;

  /// 按序迁移步骤（首级迁入版本 = [floor]）。
  final List<MigrationStep> steps;

  /// 本版版本号 = 链尾（派生量，不单独声明、不单独可写）。
  int get currentVersion => floor + steps.length;

  /// 写侧可写性判定（唯一入口）：盘上
  /// JSON 是否可被本版写回。只决定可写性，从不决定读空。
  ///
  /// 本仓库的原始文件缝以空 Map 表示「文件不在/损坏」
  /// （`AtomicJsonFile.read` 的兜底），空 Map 因此按 [upgrade] 的「文件
  /// 不在」分支判——可写，首建不被版本门挡住；其余分支交给 [upgrade]。
  bool isWritable(Object? onDisk) =>
      upgrade(onDisk is Map && onDisk.isEmpty ? null : onDisk).writable;

  /// 行为入口：给定盘上 JSON（`null` = 文件不在），返回升到本版后的
  /// JSON 与是否可写（六支分类梯见库注释）。
  PolicyUpgrade upgrade(Object? onDisk) {
    final verdict = this.verdict(onDisk);
    switch (verdict) {
      case DocumentVersionVerdict.absent:
        return const PolicyUpgrade({}, true);
      case DocumentVersionVerdict.notAnObject:
      case DocumentVersionVerdict.belowFloor:
        return const PolicyUpgrade({}, false);
      case DocumentVersionVerdict.unreadableHeader:
      case DocumentVersionVerdict.aboveCurrent:
        return PolicyUpgrade(_asStringKeyed(onDisk as Map), false);
      case DocumentVersionVerdict.onChain:
        break;
    }
    final json = _asStringKeyed(onDisk as Map);
    final raw = json['version'] as int;
    final current = currentVersion;
    var effective = json;
    for (var v = raw; v < current; v++) {
      final next = steps[v - floor].up(effective);
      // 政策在每级之后自己写版本号（步骤只改形状）；浅拷贝使步骤的
      // 返回值与本件都不必共享可变状态。
      effective = {...next, 'version': v + 1};
    }
    return PolicyUpgrade(effective, true);
  }

  /// 版本判据的具名分支（六支分类梯的「哪一支」）。文件层据此把「只读」
  /// 的原因具名带给一等读结局，不重抄判据。
  DocumentVersionVerdict verdict(Object? onDisk) {
    if (onDisk == null) return DocumentVersionVerdict.absent;
    if (onDisk is! Map) return DocumentVersionVerdict.notAnObject;
    final raw = _asStringKeyed(onDisk)['version'];
    if (raw is! int) return DocumentVersionVerdict.unreadableHeader;
    if (raw > currentVersion) return DocumentVersionVerdict.aboveCurrent;
    if (raw < floor) return DocumentVersionVerdict.belowFloor;
    return DocumentVersionVerdict.onChain;
  }

  /// 类型参数不符的 Map（如 `Map<String, int>`、非 String 键）不抛
  /// TypeError，收敛进分类梯内；非 String 键被丢弃。
  static Map<String, Object?> _asStringKeyed(Map<dynamic, dynamic> onDisk) =>
      onDisk is Map<String, Object?>
      ? onDisk
      : {
          for (final entry in onDisk.entries)
            if (entry.key is String) entry.key as String: entry.value,
        };
}
