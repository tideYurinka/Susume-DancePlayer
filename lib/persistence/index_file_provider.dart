import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 视频索引文件：应用文档目录下的 `index.json`（与 `videos/` 平级）。
///
/// 索引是「视频标识 → 各域数据」的键枢纽，它的落点也是本层其余文件
/// （按视频的两份文档、组员方案库）派生路径的参照；写入方在 `lib/import`。
/// 测试用 `overrideWith` 覆盖为临时文件，见
/// `test/import/import_flow_test.dart`。
final importIndexFileProvider = Provider<Future<File>>((ref) async {
  final base = await getApplicationDocumentsDirectory();
  return File(p.join(base.path, 'index.json'));
});
