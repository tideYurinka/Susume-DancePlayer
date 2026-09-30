import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';

/// 门控假哈希：结果由测试用 [Completer] 控制，用于证明导入/打开
/// 不等待哈希完成（后台计算），以及让镜像「首次打开询问」
/// 的 app 级测试保持确定性（条目在测试放行前不会落盘）。
class GatedHasher implements ContentHasher {
  GatedHasher(this.gate);

  final Completer<String> gate;

  @override
  Future<String> hashFile(File file) => gate.future;
}
