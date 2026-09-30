/// 用户从系统文件选择器选中的视频源文件（尚未复制到应用私有目录）。
///
/// 值类型：把 file_picker 的 [PlatformFile] 归一化为与插件无关的领域值，
/// 供导入管道（[VideoImporter]）使用；测试可自行构造。
class PickedVideo {
  const PickedVideo({
    required this.name,
    required this.sourceUri,
    this.sizeBytes,
  });

  /// 显示名（含扩展名）。
  final String name;

  /// 源文件位置：file_picker 会把所选文件物化到其缓存目录并给出
  /// `file://` URI（Android SAF 同样如此）；非本地源暂不支持。
  final Uri sourceUri;

  /// 源文件大小（字节）；未知时为 null。
  final int? sizeBytes;
}
