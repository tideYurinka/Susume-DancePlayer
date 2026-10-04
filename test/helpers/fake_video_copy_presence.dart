import 'package:dance_learning_app/dance/video_copy_presence.dart';

/// 视频副本存在性替身：喂假路径，不碰真实文件系统。
///
/// 缺省按「副本都在场」——既有页面测试的条目路径都是假的（`/videos/...`），
/// 只有显式列进 [missingPaths] 的路径判为丢失。问过哪些路径按序记在
/// [consulted]，供「一次装入里逐舞只问一次」这类断言读。
class FakeVideoCopyPresence implements VideoCopyPresence {
  FakeVideoCopyPresence({this.missingPaths = const {}});

  /// 判为「副本不在」的副本路径（**副本丢失**）。
  final Set<String> missingPaths;

  /// 问过的路径（按问序）。
  final List<String> consulted = [];

  @override
  bool exists(String path) {
    consulted.add(path);
    return !missingPaths.contains(path);
  }
}
