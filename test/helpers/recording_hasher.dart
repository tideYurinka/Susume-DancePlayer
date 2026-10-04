import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';

/// 记录算过哪些文件的假内容摘要件：固定返回值，按调用次序记下文件路径。
///
/// 用于断言「复制一遍 + 摘要读一遍」的读取次数与摘要对象（复制后的副本），
/// 以及导入返回时索引条目已落盘。
class RecordingHasher implements ContentHasher {
  RecordingHasher(this.value);

  /// 每次 [hashFile] 的返回值。
  final String value;

  /// [hashFile] 收到的文件路径（按调用次序）。
  final List<String> hashedPaths = [];

  @override
  Future<String> hashFile(File file) async {
    hashedPaths.add(file.path);
    return value;
  }
}
