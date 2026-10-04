import 'dart:async';
import 'dart:convert';

import 'package:dance_learning_app/core/private_json.dart';

/// 内存版设备级私密 JSON 存储（widget/model 测试用）。
///
/// 与 `InMemoryVideoIndexStorage` 同一先例：真实文件 IO 在 flutter_test 的
/// fake async 时钟下不可完成；本实现以微任务完成 read/write。
class InMemoryPrivateJsonStorage implements PrivateJsonStorage {
  InMemoryPrivateJsonStorage({Map<String, dynamic> initial = const {}})
    : _json = Map.of(initial);

  Map<String, dynamic> _json;

  /// 丢掉存储内容（模拟文件被删后首次启动）。
  void reset() => _json = {};

  /// 当前存储内容深拷贝（测试断言/「重启等价」重建 store 用）。
  Map<String, dynamic> get snapshot =>
      jsonDecode(jsonEncode(_json)) as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> read() async => snapshot;

  @override
  Future<void> write(Map<String, dynamic> json) async {
    _json = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
  }

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    mutate,
  ) async {
    final copy = Map<String, dynamic>.of(_json);
    // 内存替身只表达「有一份内容」，没有文件不在态，故恒 present。
    await mutate(copy, present: true);
    await write(copy);
  }
}
