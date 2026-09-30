import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/import/video_picker.dart';

/// 记录调用并返回固定结果的假选择器（不触碰系统文件选择器）。
class FakeVideoPicker implements VideoPicker {
  FakeVideoPicker(this.result);

  /// 每次 pickVideo 返回的结果；null 表示用户取消。
  final PickedVideo? result;

  int pickCalls = 0;
  bool clearCacheCalled = false;

  @override
  Future<PickedVideo?> pickVideo() async {
    pickCalls++;
    return result;
  }

  @override
  Future<void> clearCache() async {
    clearCacheCalled = true;
  }
}
