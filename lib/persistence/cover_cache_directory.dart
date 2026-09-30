import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 封面缓存目录：应用**缓存区**下的 `covers/`。
///
/// 文件位置归持久化层（与 `four_beat_bucket_providers.dart` 同处一处来源）；
/// 系统回收缓存不影响正确性——文件缺失即未就绪，卡片回落占位图并按封面位置
/// 重新生成。缓存存取与生成编排在 `lib/dance/`。
final coverCacheDirectoryProvider = FutureProvider<Directory>((ref) async {
  final base = await getApplicationCacheDirectory();
  return Directory(p.join(base.path, 'covers'));
});
