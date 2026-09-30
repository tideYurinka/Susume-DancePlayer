/// 一等读结局：读一份文档得到
/// **可写读**（文件不在、或沿链升到本版）或**只读读**（原因具名——
/// 高于本版 / 低于地板 / 版本头读不出）。
///
/// 三条不变量：
/// - **只有可写读结局带写回入口**（[WritableDocumentReadOutcome.write]）；
///   只读结局没有写回成员，「覆盖一份没读懂的文件」在类型上不可达。
/// - **写回结局二态**（[DocumentWriteOutcome]：已提交 / 被拒），调用点必须
///   当面处理拒写——写不进去不再可能静默。
/// - **版本判据只决定可写性、从不决定读空**：空态只剩两个来源——文件不在、
///   本体解析不出对象。只读结局仍带「认识多少读多少」的文档投影。
///
/// 只读投影 [DocumentReadOutcome.document] 供纯读调用点使用，读调用点签名
/// 因此不必全部改写；写回入口从协调器的通用更新方法搬进可写结局。
library;

import 'dart:async';

import '../core/document_version_policy.dart';

/// 版本裁决 → 只读读的具名原因；可写分支（文件不在 / 在链上）返回 null。
///
/// 文件层与协调器共用这一处映射，不各自重抄判据；[notAnObject] 在文件缝
/// 不可达（`loadXOrNull` 对非对象已回 null），归到「版本头读不出」一族。
DocumentReadOnlyReason? documentReadOnlyReasonOf(
  DocumentVersionVerdict verdict,
) => switch (verdict) {
  DocumentVersionVerdict.aboveCurrent => DocumentReadOnlyReason.aboveCurrent,
  DocumentVersionVerdict.belowFloor => DocumentReadOnlyReason.belowFloor,
  DocumentVersionVerdict.unreadableHeader ||
  DocumentVersionVerdict.notAnObject =>
    DocumentReadOnlyReason.unreadableVersionHeader,
  DocumentVersionVerdict.absent || DocumentVersionVerdict.onChain => null,
};

/// 只读读的三种具名原因。
enum DocumentReadOnlyReason {
  /// 高于本版：本机认识多少读多少，但不改写回旧形状。
  aboveCurrent,

  /// 低于地板：该格式从未随发布版落过盘，是唯一许可读空的凭据。
  belowFloor,

  /// 版本头不是整数（含键缺失）：内容没读懂。
  unreadableVersionHeader,
}

/// 读一份文档得到的一等结局。
sealed class DocumentReadOutcome<D> {
  const DocumentReadOutcome(this.document);

  /// 只读投影：纯读调用点从这里取文档。
  final D document;
}

/// 可写读结局：文件不在（可创建）或听懂了（可整份替换）。
sealed class WritableDocumentReadOutcome<D> extends DocumentReadOutcome<D> {
  const WritableDocumentReadOutcome(super.document, DocumentWriteExecutor<D> writeBack)
    : _write = writeBack;

  final DocumentWriteExecutor<D> _write;

  /// 写回：链内重读最新原文 → 再判可写 → [mutate] → 整份替换（逐层陌生键
  /// 保底随行）。返回已提交或被拒；被拒时盘上原文一字未动。
  Future<DocumentWriteOutcome<D>> write(
    FutureOr<D> Function(DocumentWriteContext<D> context) mutate,
  ) => _write(mutate);
}

/// 文件不存在（或本体解析不出对象）：可写、可创建。
final class DocumentAbsent<D> extends WritableDocumentReadOutcome<D> {
  const DocumentAbsent(super.document, super.writeBack);
}

/// 听懂了：可写、整份替换。
final class DocumentUnderstood<D> extends WritableDocumentReadOutcome<D> {
  const DocumentUnderstood(super.document, super.writeBack);
}

/// 只读：原因具名。**没有写回成员**。
final class DocumentReadOnly<D> extends DocumentReadOutcome<D> {
  const DocumentReadOnly(super.document, this.reason);

  /// 只读的具名原因。
  final DocumentReadOnlyReason reason;
}

/// 写回执行器：由文件层给出（链内重读最新、再判可写、整份替换）。
typedef DocumentWriteExecutor<D> =
    Future<DocumentWriteOutcome<D>> Function(
      FutureOr<D> Function(DocumentWriteContext<D> context) mutate,
    );

/// 写回上下文：链内读到的最新文档 + 盘上是否真有这份文件。
///
/// [present] 必须在**写链内**取（并发首写竞态下首建判定依赖它，见
/// `firstBuildSeeded`）——它区分「文件不存在/损坏」与「存在但全字段为
/// 缺省值的文件」。
class DocumentWriteContext<D> {
  const DocumentWriteContext({required this.document, required this.present});

  /// 链内最新文档（损坏/不存在按空态）。
  final D document;

  /// 链内最新一次读：盘上是否真有这份文件。
  final bool present;
}

/// 写回的二态结局。
sealed class DocumentWriteOutcome<D> {
  const DocumentWriteOutcome(this.document);

  /// 写后（或拒写时读到）的文档。
  final D document;
}

/// 已提交：整份替换已落盘（内容未变时为无变化跳写，内容即链内现值）。
final class DocumentWriteCommitted<D> extends DocumentWriteOutcome<D> {
  const DocumentWriteCommitted(super.document);
}

/// 被拒：读与写之间盘上换成只读文件，盘上原文一字未动。
final class DocumentWriteRejected<D> extends DocumentWriteOutcome<D> {
  const DocumentWriteRejected(super.document, this.reason);

  /// 拒写的具名原因。
  final DocumentReadOnlyReason reason;
}
