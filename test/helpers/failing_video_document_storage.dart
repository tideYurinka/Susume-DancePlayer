import 'dart:async';

import 'package:dance_learning_app/persistence/video_document_store.dart';

import 'in_memory_video_document_storage.dart';

/// 可指定哪一份文档写失败的按视频文档存储替身：读走内层（读面照常呈现旧
/// 值），被指定的那份原子读改写抛错。
///
/// 管理写的「写失败零副作用」用例用它——改名写 markers、改档写 local；
/// 与 [InMemoryVideoDocumentStorage] 同一注入点，不新增 seam。
class FailingVideoDocumentStorage implements VideoDocumentStorage {
  FailingVideoDocumentStorage(
    this._inner, {
    this.failMarkers = false,
    this.failLocal = false,
  });

  final InMemoryVideoDocumentStorage _inner;

  /// markers 的原子读改写抛错。
  final bool failMarkers;

  /// local 的原子读改写抛错。
  final bool failLocal;

  @override
  Future<Map<String, dynamic>> loadMarkers() => _inner.loadMarkers();

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() =>
      _inner.loadMarkersOrNull();

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) =>
      _inner.saveMarkers(json);

  @override
  Future<Map<String, dynamic>> loadLocal() => _inner.loadLocal();

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() =>
      _inner.loadLocalOrNull();

  @override
  Future<void> saveLocal(Map<String, dynamic> json) =>
      _inner.saveLocal(json);

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present}) apply,
  ) async {
    if (failMarkers) throw StateError('markers 不可写');
    await _inner.mutateMarkers(apply);
  }

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present}) apply,
  ) async {
    if (failLocal) throw StateError('local 不可写');
    await _inner.mutateLocal(apply);
  }

  @override
  Future<void> delete() => _inner.delete();
}
