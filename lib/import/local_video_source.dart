/// 源文件边界：无论走导入管道还是找回动作，源都必须物化成本地文件。
///
/// 两条路径都从系统选择器拿 [PickedVideo]：file_picker 会先把所选文件物化到
/// 其缓存目录并给出 `file://` URI（Android SAF 同样如此），非 `file://` 源
/// 没有可复制的文件。这条判据与文案只此一处——两条路径不各写一份，边界改了
/// 一起变。
library;

import 'dart:io';

import 'picked_video.dart';

/// [picked] 的本地源文件；非 `file://` 时抛出明确错误。
///
/// [what] = 这条路径的名字（「导入源」/「找回源」），只为把错误指向出问题的
/// 那一步——判据与兜底解释两条路径共用。
File localSourceFileOf(PickedVideo picked, {required String what}) {
  if (picked.sourceUri.scheme != 'file') {
    throw StateError(
      '暂不支持非本地文件的$what（${picked.sourceUri.scheme}）；'
      'file_picker 会先把所选文件物化到缓存，正常应为 file://。',
    );
  }
  return File(picked.sourceUri.toFilePath());
}
