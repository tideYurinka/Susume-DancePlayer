import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';

/// 固定值哈希（打开恢复的内容哈希校验桩：返回值即「视频内容哈希」）。
/// 多个播放页测试文件共用（open_restore / player_page / 片段激活 widget）。
class FixedHasher implements ContentHasher {
  const FixedHasher(this.value);

  final String value;

  @override
  Future<String> hashFile(File file) async => value;
}
