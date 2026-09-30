import 'package:file_picker/file_picker.dart';

import 'picked_video.dart';

/// 系统文件选择器抽象（测试注入 fake，不触碰真实选择器）。
abstract interface class VideoPicker {
  /// 让用户选择一个视频文件；取消返回 null。
  Future<PickedVideo?> pickVideo();

  /// 清理选择器缓存（复制到应用私有目录后调用）。
  Future<void> clearCache();
}

/// 真实实现：file_picker v12（破坏性 API 按 v12 使用——`pickFile`
/// 返回 `PlatformFile?`，取消为 null）。
///
/// file_picker 会把所选文件物化到其缓存目录并返回本地 `file://` URI，
/// 复制完成后调用 [FilePicker.clearTemporaryFiles] 清理该缓存。
class SystemVideoPicker implements VideoPicker {
  @override
  Future<PickedVideo?> pickVideo() async {
    final file = await FilePicker.pickFile(
      type: FileType.video,
      dialogTitle: '选择舞蹈视频',
    );
    if (file == null) return null;

    int? size;
    try {
      size = await file.length();
    } on Object {
      // 个别平台取不到大小时以 null 表示未知，不阻断导入。
      size = null;
    }
    return PickedVideo(name: file.name, sourceUri: file.uri, sizeBytes: size);
  }

  @override
  Future<void> clearCache() => FilePicker.clearTemporaryFiles();
}
