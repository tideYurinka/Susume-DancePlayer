/// 测试专用画面占位：非真实内核的 [VideoSurfacePlaceholder] 与占位 key。
///
/// 只为 [FakePlaybackEngine.buildVideoSurface] 与 widget 级画面几何断言
/// 提供可控的占位渲染，不被 lib/ 生产代码引用。
library;

import 'package:flutter/material.dart';

/// 视频画面控件的占位 key（测试内核画面几何断言用）。
const Key videoSurfacePlaceholderKey = Key('video_surface_placeholder');

/// 非真实内核的画面占位（测试接缝）。
///
/// 按 [VideoSurfacePlaceholder.videoAspectRatio] 用 Center + AspectRatio
/// 约束占位尺寸（contain 语义）；宽高比未知时填满可用
/// 区域（由内核自行 contain）。
class VideoSurfacePlaceholder extends StatelessWidget {
  const VideoSurfacePlaceholder({super.key, required this.videoAspectRatio});

  /// 视频画面宽高比（宽 / 高）；null 或非正数视为未知 → 填满可用区域。
  final double? videoAspectRatio;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      key: videoSurfacePlaceholderKey,
      color: Color(0xFF141414),
    );
    final ratio = videoAspectRatio;
    if (ratio == null || ratio <= 0) {
      return placeholder;
    }
    return Center(
      child: AspectRatio(aspectRatio: ratio, child: placeholder),
    );
  }
}
