import 'dart:async';
import 'dart:io';

import '../core/atomic_json_file.dart';
import 'document_quarantine.dart';
import 'document_read_outcome.dart';
import '../core/document_version_policy.dart';
import 'local_document.dart';
import 'marker_document.dart';

/// 按视频双文件（`markers_<hash>.json` + `local_<hash>.json`）的原始
/// JSON 读写 seam。
///
/// 协调器（[VideoDocumentCoordinator]）只经本接口触达磁盘；测试可注入
/// 内存 fake（`test/helpers/in_memory_video_document_storage.dart`）与
/// 真实实现双跑。读取失败（文件缺失/损坏）由实现兜底为空 Map，不抛错。
///
/// 本缝也是**留档**的落点：只读文档的原文在读出时、以及
/// 被本缝的破坏性动词（[saveMarkers]/[saveLocal] 整份替换、[delete]）销毁
/// 前，按内容寻址另存一份旁路文件（见 [DocumentQuarantine]）。放在这一层
/// 才盖得住「删除这支舞」与「恢复整机备份的全量替换」这两条绕过版本政策
/// 的路径；留档失败异常向上，破坏性动作随之不发生。这份「何时留档」的
/// 纪律由 [QuarantiningVideoDocumentStorage] 统一实现一次。
abstract interface class VideoDocumentStorage {
  /// 读取公开标记文件整份 JSON；缺失/损坏兜底空 Map。
  Future<Map<String, dynamic>> loadMarkers();

  /// 读取公开标记文件；缺失/损坏返回 null，存在且可解析返回内容
  /// （可能为空 Map）。markers 首建判定（「文件不存在/损坏」才立
  /// 首建初值）依赖该区分。
  Future<Map<String, dynamic>?> loadMarkersOrNull();

  /// 整份覆盖写入公开标记文件（原子写，读侧不见半截 JSON）。
  Future<void> saveMarkers(Map<String, dynamic> json);

  /// 读取本地文档整份 JSON；缺失/损坏兜底空 Map。
  Future<Map<String, dynamic>> loadLocal();

  /// 读取本地文档；缺失/损坏返回 null，存在且可解析返回内容（可能为空
  /// Map）。读结局的「文件不在 vs 本体解析不出对象」由此区分。
  Future<Map<String, dynamic>?> loadLocalOrNull();

  /// 整份覆盖写入本地文档（原子写）。
  Future<void> saveLocal(Map<String, dynamic> json);

  /// 删除该视频的两份文档文件（缺失视作已删）；所属舞被删除时 best-effort
  /// 调用一次，此后该 videoId 读回空态。删除前会先留档只读原文，**留档
  /// 失败异常向上**（best-effort 调用方据此只留孤儿文件、不回滚）。
  Future<void> delete();

  /// 原子读改写公开标记文件：读最新 → [apply] → 写，三步串行在本实例的
  /// 写链上执行。写者的数量因此不再是丢更新的风险来源——「一份文档一个
  /// 写入者」由「每次写入都是一次原子读改写」承接；
  /// [apply] 未改动内容时跳过写盘。[apply] 另收链内「文件是否存在且可
  /// 解析」的存在位（`false` 不塌缩成空对象）。
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  );

  /// 原子读改写本地文档（语义同 [mutateMarkers]）。
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  );
}

/// 只投影可分享键读取公开标记文件（见 [MarkersDocument.shareableJson]）：
/// 字段声明处未标记 `shareable` 的字段与逐层未登记键一律不流出——新字段
/// 默认不进包。缺失/损坏返回 null，与 [VideoDocumentStorage.loadMarkersOrNull]
/// 同口径；投影纯由原文派生，各实现无需各自复刻。
extension ShareableMarkersRead on VideoDocumentStorage {
  Future<Map<String, dynamic>?> loadShareableMarkersOrNull() async {
    final json = await loadMarkersOrNull();
    return json == null ? null : MarkersDocument.shareableJson(json);
  }
}

/// 单份文档的读写内核：只懂读、写、删与原子读改写，**不含留档**。
///
/// [QuarantiningVideoDocumentStorage] 包住一对内核（markers / local），把
/// 「何时留档」收在一处；真实文件实现与内存 fake 只需各自回答「原文从哪
/// 来、原文往哪放」，不必各自复刻留档时机。
abstract interface class VideoDocumentStorageKernel {
  /// 读取整份 JSON；文件缺失/损坏/顶层非对象返回 null。
  Future<Map<String, dynamic>?> readOrNull();

  /// 读取文件原始文本（不解析）；文件缺失/读失败返回 null。留档据此保住
  /// **逐字节原文**。
  Future<String?> readRawOrNull();

  /// 整份覆盖写入（原子写）。
  Future<void> write(Map<String, dynamic> json);

  /// 删除底层文件（缺失视作已删）。
  Future<void> delete();

  /// 原子读改写：读 → [apply] → 写，串行在本内核的写链上执行。
  /// [apply] 另收链内「文件是否存在且可解析」的存在位。
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  );

  /// 把只读原文 [raw] 按 [reason] 按内容寻址留档；失败异常向上。
  Future<void> quarantine(String raw, DocumentReadOnlyReason reason);
}

/// 留档纪律装饰器：包住一对只懂读写的 [VideoDocumentStorageKernel]，统一
/// 实现「何时留档」——读出只读原文时，以及 [saveMarkers]/[saveLocal]、
/// [delete]、[mutateMarkers]/[mutateLocal] 销毁原文前。留档名与原因判定
/// 仍走公开纯件（[DocumentQuarantine.sidecarName]、
/// [documentReadOnlyReasonOf]、两份文档的 `versionPolicy`）。
///
/// 真实文件实现（[AtomicVideoDocumentStorage]）与内存 fake 共用本类，
/// 「何时留档」因此只有一份拷贝。
class QuarantiningVideoDocumentStorage implements VideoDocumentStorage {
  QuarantiningVideoDocumentStorage({
    required VideoDocumentStorageKernel markers,
    required VideoDocumentStorageKernel local,
  }) : _markers = markers, // ignore: prefer_initializing_formals
       _local = local; // ignore: prefer_initializing_formals

  final VideoDocumentStorageKernel _markers;
  final VideoDocumentStorageKernel _local;

  @override
  Future<Map<String, dynamic>> loadMarkers() async =>
      await loadMarkersOrNull() ?? const {};

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() async {
    final json = await _markers.readOrNull();
    await _quarantine(_markers, MarkersDocument.versionPolicy, json);
    return json;
  }

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) async {
    await _quarantine(
      _markers,
      MarkersDocument.versionPolicy,
      await _markers.readOrNull(),
    );
    await _markers.write(json);
  }

  @override
  Future<Map<String, dynamic>> loadLocal() async =>
      await loadLocalOrNull() ?? const {};

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() async {
    final json = await _local.readOrNull();
    await _quarantine(_local, LocalDocument.versionPolicy, json);
    return json;
  }

  @override
  Future<void> saveLocal(Map<String, dynamic> json) async {
    await _quarantine(
      _local,
      LocalDocument.versionPolicy,
      await _local.readOrNull(),
    );
    await _local.write(json);
  }

  @override
  Future<void> delete() async {
    // 破坏性动词：删除只读原文前先留档；留档失败则不删。
    await _quarantine(
      _markers,
      MarkersDocument.versionPolicy,
      await _markers.readOrNull(),
    );
    await _quarantine(
      _local,
      LocalDocument.versionPolicy,
      await _local.readOrNull(),
    );
    await _markers.delete();
    await _local.delete();
  }

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    // 原子读改写的链内读不经本类的读面，故在入链前先留档只读原文——留档
    // 在链外完成（不占写链），随后才交链执行读改写。
    await _quarantine(
      _markers,
      MarkersDocument.versionPolicy,
      await _markers.readOrNull(),
    );
    await _markers.mutate(apply);
  }

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) async {
    await _quarantine(
      _local,
      LocalDocument.versionPolicy,
      await _local.readOrNull(),
    );
    await _local.mutate(apply);
  }

  /// 只读则把 [json] 对应的原文留档；文件不在（`null`）与可写都不落旁路
  /// 文件。原文由内核自己的读面给出，本类只决定**何时**调用。
  Future<void> _quarantine(
    VideoDocumentStorageKernel kernel,
    DocumentVersionPolicy policy,
    Map<String, dynamic>? json,
  ) async {
    if (json == null) return;
    final reason = documentReadOnlyReasonOf(policy.verdict(json));
    if (reason == null) return;
    final raw = await kernel.readRawOrNull();
    if (raw == null) return;
    await kernel.quarantine(raw, reason);
  }
}

/// [VideoDocumentStorage] 的真实文件实现：每文件一个 [AtomicJsonFile]
/// 内核（原子写/损坏兜底/单文件串行链全部委托既有深模块），留档纪律由
/// [QuarantiningVideoDocumentStorage] 统一实现。
class AtomicVideoDocumentStorage extends QuarantiningVideoDocumentStorage {
  AtomicVideoDocumentStorage({
    required FutureOr<File> markersFile,
    required FutureOr<File> localFile,
  }) : super(
         markers: _AtomicDocumentKernel(AtomicJsonFile(markersFile)),
         local: _AtomicDocumentKernel(AtomicJsonFile(localFile)),
       );
}

/// 真实文件内核：[AtomicJsonFile] 的读写 + 同目录旁路留档。
class _AtomicDocumentKernel implements VideoDocumentStorageKernel {
  _AtomicDocumentKernel(this._file);

  final AtomicJsonFile _file;

  @override
  Future<Map<String, dynamic>?> readOrNull() => _file.readOrNull();

  @override
  Future<String?> readRawOrNull() => _file.readRawOrNull();

  @override
  Future<void> write(Map<String, dynamic> json) => _file.write(json);

  @override
  Future<void> delete() => _file.delete();

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    apply,
  ) => _file.mutate(apply);

  @override
  Future<void> quarantine(String raw, DocumentReadOnlyReason reason) async =>
      DocumentQuarantine(await _file.resolveFile()).save(raw, reason);
}

/// 按视频文档协调器：以**一等读结局**读写两份文档。
///
/// 读面给出三态结局——[DocumentAbsent]（文件不在/本体解析不出对象，
/// 可写、可创建）、[DocumentUnderstood]（听懂了，可写、整份替换）、
/// [DocumentReadOnly]（高于本版 / 低于地板 / 版本头读不出，原因具名）。
/// **写回入口只挂在可写结局上**，只读结局没有写回成员，「覆盖一份没读懂的
/// 文件」在类型上不可达；协调器不再有通用的字段级更新入口。
///
/// 写回在**文件存取实例**的串行链内做原子读改写（同一份文件被
/// 多个协调器持有时交错写仍不丢字段）：链内重读最新原文 → 再判可写（读与
/// 写之间盘上换成只读文件即被拒、盘上原文一字未动）→ 交调用方改自己那段
/// → 内容有变化才整份替换。未知扩展字段（P1 预留位）随读取带回、写回原样
/// 保留。**破坏性写法（清空整份 JSON 再写）只出现在可写结局的写回实现
/// 里**，不出现在任何产品可见的签名上。
class VideoDocumentCoordinator {
  VideoDocumentCoordinator(this._storage);

  final VideoDocumentStorage _storage;

  /// 读当前 markers 文档的一等读结局（不经写链）。
  Future<DocumentReadOutcome<MarkersDocument>> readMarkersOutcome() async =>
      _markersOutcome(await _storage.loadMarkersOrNull());

  /// 读当前 markers 文档（只读投影：只读结局也「认识多少读多少」。
  /// 低于地板与文件不在按空态）。读调用点签名不变。
  Future<MarkersDocument> readMarkers() async =>
      (await readMarkersOutcome()).document;

  /// 读当前 local 文档的一等读结局。
  Future<DocumentReadOutcome<LocalDocument>> readLocalOutcome() async =>
      _localOutcome(await _storage.loadLocalOrNull());

  /// 读当前 local 文档（只读投影）。
  Future<LocalDocument> readLocal() async =>
      (await readLocalOutcome()).document;

  /// 读当前 markers 文档；文件缺失/损坏返回 null（markers 首建判定
  /// 「文件不存在/损坏」的依据）。只读投影：版本头读不懂但文件在盘上时
  /// 仍返回文档（首建判定据 [DocumentWriteContext.present] 区分）。
  Future<MarkersDocument?> readMarkersOrNull() async {
    final json = await _storage.loadMarkersOrNull();
    return json == null ? null : MarkersDocument.fromJson(json);
  }

  DocumentReadOutcome<MarkersDocument> _markersOutcome(
    Map<String, dynamic>? json,
  ) => _outcome(
    json,
    policy: MarkersDocument.versionPolicy,
    decode: MarkersDocument.fromJson,
    write: _writeMarkers,
  );

  DocumentReadOutcome<LocalDocument> _localOutcome(
    Map<String, dynamic>? json,
  ) => _outcome(
    json,
    policy: LocalDocument.versionPolicy,
    decode: LocalDocument.fromJson,
    write: _writeLocal,
  );

  /// 文件层结局：`null`（`AtomicJsonFile.readOrNull` 对「文件不在/损坏/顶层
  /// 非对象」的兜底）落 [DocumentAbsent]；**存在但内容为空对象**不在这里
  /// 折叠成「文件不在」——它没有版本头，按 [DocumentVersionVerdict
  /// .unreadableHeader] 只读，首建路径拿到的 `null` 不受
  /// 影响。其余分支交给政策的具名裁决。
  static DocumentReadOutcome<D> _outcome<D>(
    Map<String, dynamic>? json, {
    required DocumentVersionPolicy policy,
    required D Function(Map<String, dynamic>) decode,
    required DocumentWriteExecutor<D> write,
  }) {
    final verdict = _verdictOf(json, policy);
    final document = decode(json ?? const {});
    return switch (verdict) {
      DocumentVersionVerdict.absent => DocumentAbsent(document, write),
      DocumentVersionVerdict.onChain => DocumentUnderstood(document, write),
      DocumentVersionVerdict.aboveCurrent ||
      DocumentVersionVerdict.belowFloor ||
      DocumentVersionVerdict.unreadableHeader ||
      DocumentVersionVerdict.notAnObject => DocumentReadOnly(
        document,
        _reasonOf(verdict),
      ),
    };
  }

  /// 文件层裁决：`null`（`AtomicJsonFile.readOrNull` 对「文件不在/损坏/顶层
  /// 非对象」的兜底）→ [DocumentVersionVerdict.absent]；**存在但内容为空
  /// 对象**有版本头缺失，按 [DocumentVersionVerdict.unreadableHeader] 只读
  /// ——不做「空 Map = 文件不在」的折叠（`readOrNull` 已把两者分开）。
  static DocumentVersionVerdict _verdictOf(
    Map<String, dynamic>? json,
    DocumentVersionPolicy policy,
  ) => json == null ? DocumentVersionVerdict.absent : policy.verdict(json);

  /// 只读分支 → 具名原因（与文件层共用 [documentReadOnlyReasonOf]，不重抄
  /// 判据）；可写分支没有原因，落到这里即调用方用错了。
  static DocumentReadOnlyReason _reasonOf(DocumentVersionVerdict verdict) =>
      documentReadOnlyReasonOf(verdict) ??
      (throw StateError('可写分支没有只读原因：$verdict'));

  Future<DocumentWriteOutcome<MarkersDocument>> _writeMarkers(
    FutureOr<MarkersDocument> Function(DocumentWriteContext<MarkersDocument>)
    mutate,
  ) async {
    DocumentWriteOutcome<MarkersDocument>? outcome;
    await _storage.mutateMarkers((json, {required bool present}) async {
      // 链内读的存在位即版本裁决的输入：文件不在（present = false）走
      // absent 分支，存在则交给政策的具名裁决；不再链内二次读盘。
      final verdict = present
          ? MarkersDocument.versionPolicy.verdict(json)
          : DocumentVersionVerdict.absent;
      final current = MarkersDocument.fromJson(json);
      if (!verdict.isWritable) {
        outcome = DocumentWriteRejected(current, _reasonOf(verdict));
        return;
      }
      final next = await mutate(
        DocumentWriteContext(document: current, present: present),
      );
      if (next == current) {
        // 未变更：内容不变即跳写（不产生新 mtime）。
        outcome = DocumentWriteCommitted(current);
        return;
      }
      json
        ..clear()
        ..addAll(next.toJson());
      outcome = DocumentWriteCommitted(next);
    });
    // 文件层保证 apply 一定被调用（否则上面的 await 抛错），因此必有结局。
    return outcome!;
  }

  Future<DocumentWriteOutcome<LocalDocument>> _writeLocal(
    FutureOr<LocalDocument> Function(DocumentWriteContext<LocalDocument>)
    mutate,
  ) async {
    DocumentWriteOutcome<LocalDocument>? outcome;
    await _storage.mutateLocal((json, {required bool present}) async {
      // 链内读的存在位即版本裁决的输入（语义同 [_writeMarkers]）。
      final verdict = present
          ? LocalDocument.versionPolicy.verdict(json)
          : DocumentVersionVerdict.absent;
      final current = LocalDocument.fromJson(json);
      if (!verdict.isWritable) {
        outcome = DocumentWriteRejected(current, _reasonOf(verdict));
        return;
      }
      final next = await mutate(
        DocumentWriteContext(document: current, present: present),
      );
      if (next == current) {
        outcome = DocumentWriteCommitted(current);
        return;
      }
      json
        ..clear()
        ..addAll(next.toJson());
      outcome = DocumentWriteCommitted(next);
    });
    // 文件层保证 apply 一定被调用（否则上面的 await 抛错），因此必有结局。
    return outcome!;
  }
}
