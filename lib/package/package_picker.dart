import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../import/picked_video.dart';

/// 分享包文件选择器抽象（测试注入 fake，不触碰真实选择器）。
abstract interface class PackagePicker {
  /// 让用户选择一个 `.susume` 文件；取消返回 null。
  Future<PickedVideo?> pickPackage();
}

/// 真实实现：file_picker 按扩展名过滤（物化到缓存并给出 `file://` URI，
/// 与视频选择同款）。
class SystemPackagePicker implements PackagePicker {
  @override
  Future<PickedVideo?> pickPackage() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['susume'],
      dialogTitle: '选择分享文件',
    );
    if (file == null) return null;
    int? size;
    try {
      size = await file.length();
    } on Object {
      size = null;
    }
    return PickedVideo(name: file.name, sourceUri: file.uri, sizeBytes: size);
  }
}

final packagePickerProvider = Provider<PackagePicker>(
  (ref) => SystemPackagePicker(),
);
