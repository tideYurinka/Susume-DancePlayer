import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/package/package_picker.dart';

/// 记录调用并返回固定结果的假包选择器（不触碰系统文件选择器）。
class FakePackagePicker implements PackagePicker {
  FakePackagePicker(this.result);

  /// 每次 pickPackage 返回的结果；null 表示用户取消。
  final PickedVideo? result;

  int pickCalls = 0;

  @override
  Future<PickedVideo?> pickPackage() async {
    pickCalls++;
    return result;
  }
}
