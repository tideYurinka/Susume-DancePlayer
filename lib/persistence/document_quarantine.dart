/// 留档：读到只读文档时把**原文**按内容寻址另存
/// 一份旁路文件。
///
/// 三条纪律：
/// - **内容寻址**：旁路文件名含只读原因与原文内容哈希，同一份内容重复留档
///   只留一份——幂等不靠「已留档」状态位，也不靠事后清理。
/// - **逐字节原文**：留档写的是盘上原始文本，不重编码（键序/空白一变即
///   不再是原件）。
/// - **不占写链**：旁路文件独立写（tmp + 原子重命名），不进文档的串行写链，
///   既有串行写语义不受影响；**留档失败异常向上**，调用方据此让整次写回
///   失败、盘上原文一字未动。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/video_identity.dart' show XxHash64;
import 'document_read_outcome.dart' show DocumentReadOnlyReason;

/// 单份文档的留档落点：与文档同目录、名字含原因与内容哈希。
class DocumentQuarantine {
  DocumentQuarantine(this.documentFile);

  /// 被留档的文档文件（旁路文件与它同目录）。
  final File documentFile;

  /// 旁路文件名：`<原文件名去扩展>.quarantine-<原因>-<内容哈希>.json`。
  static String sidecarName(
    String documentPath,
    String raw,
    DocumentReadOnlyReason reason,
  ) {
    final hash = XxHash64()..update(utf8.encode(raw));
    return '${p.basenameWithoutExtension(documentPath)}'
        '.quarantine-${reason.name}-${hash.digest()}.json';
  }

  /// 把 [raw] 原文留档，返回旁路文件；同一份内容已留档时直接复用。
  Future<File> save(String raw, DocumentReadOnlyReason reason) async {
    final sidecar = File(
      p.join(
        documentFile.parent.path,
        sidecarName(documentFile.path, raw, reason),
      ),
    );
    if (await FileSystemEntity.isFile(sidecar.path)) return sidecar;
    // 临时名带自增序号：并发留档同一份内容时互不覆盖临时文件；两边内容
    // 相同，重命名互相覆盖也无妨（内容寻址的幂等）。
    final tmp = File('${sidecar.path}.${_tmpSequence++}.tmp');
    await tmp.writeAsString(raw, flush: true);
    try {
      await tmp.rename(sidecar.path);
    } on Object {
      // 留档失败不留残件：失败后盘上只有原文，没有半个旁路文件。
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    return sidecar;
  }

  /// 临时文件名的进程内自增序号（仅避免并发写同一临时路径）。
  static int _tmpSequence = 0;
}
