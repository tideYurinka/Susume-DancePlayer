import 'dart:async';

import 'package:dance_learning_app/core/private_json.dart';

/// 每次读写都抛错的设备级私密 JSON 替身（模拟无平台通道）。
///
/// 与 [InMemoryPrivateJsonStorage] 同一注入点，不新增 seam：读面兜底与
/// 「写失败静默」两类用例共用它。
class FailingPrivateJsonStorage implements PrivateJsonStorage {
  @override
  Future<Map<String, dynamic>> read() async => throw StateError('无平台通道');

  @override
  Future<void> write(Map<String, dynamic> json) async =>
      throw StateError('无平台通道');

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present}) mutate,
  ) async => throw StateError('无平台通道');
}
