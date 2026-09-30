import 'dart:convert';

import 'package:dance_learning_app/persistence/material_manifest.dart';

/// 素材清单内存存储（对比练习播放页级测试共用）：真实文件 IO 在
/// fake async 时钟下不可完成，与 `InMemoryPrivateJsonStorage` 同款以微
/// 任务完成 load/save。
class MemoryManifestStorage implements MaterialManifestStorage {
  final _json = <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> load() async => jsonDeepCopy(_json);

  @override
  Future<void> save(Map<String, dynamic> json) async =>
      _json..clear()..addAll(jsonDeepCopy(json));
}

Map<String, dynamic> jsonDeepCopy(Map<String, dynamic> json) =>
    Map<String, dynamic>.of(json);

/// 深拷贝（测试断言用）。
Map<String, dynamic> jsonDecodeCopy(Map<String, dynamic> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
