import 'dart:async';

import 'package:dance_learning_app/persistence/document_read_outcome.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';

/// 测试专用写回便捷面。
///
/// 产品面已无通用更新入口：写回只从**可写读结局**发生。护栏 / 装配类用例
/// 只想「把一份文档写到盘上」，不为写回本身断言时用这两个扩展走同一条
/// 可写读结局路径；只读文件上静默不写（与产品的「没有写回成员」一致）。
extension VideoDocumentWriteTestHelpers on VideoDocumentCoordinator {
  /// 经可写读结局整份写回 markers；只读文件上不写。
  Future<MarkersDocument> patchMarkers(
    FutureOr<MarkersDocument> Function(MarkersDocument document) mutate,
  ) async {
    final outcome = await readMarkersOutcome();
    if (outcome is! WritableDocumentReadOutcome<MarkersDocument>) {
      return outcome.document;
    }
    return (await outcome.write((context) => mutate(context.document)))
        .document;
  }

  /// 经可写读结局整份写回 local；只读文件上不写。
  Future<LocalDocument> patchLocal(
    FutureOr<LocalDocument> Function(LocalDocument document) mutate,
  ) async {
    final outcome = await readLocalOutcome();
    if (outcome is! WritableDocumentReadOutcome<LocalDocument>) {
      return outcome.document;
    }
    return (await outcome.write((context) => mutate(context.document)))
        .document;
  }
}
