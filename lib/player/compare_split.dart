import 'package:flutter/material.dart';

/// 对比态分屏：视频层按设备方向等分两块——
/// 横屏左右、竖屏上下，随旋转即时应变；两块之间留细缝。
///
/// 源侧 = 既有的源视频画面子树（沿用唯一翻转闸门，全局镜像与局部镜像
/// 照常）；练习侧 = 相机服务 seam 的实时预览件。每半区 contain
/// 语义由画面内核自供（media_kit 内部 contain / 测试内核 AspectRatio）。

/// 两块之间细缝宽度。
const double kCompareSplitGap = 2.0;

/// 对比态分屏件：横屏左右等分、竖屏上下等分。
class CompareVideoSplit extends StatelessWidget {
  const CompareVideoSplit({
    super.key,
    required this.source,
    required this.practice,
  });

  /// 源侧画面子树（既有源视频画面，含镜像翻转闸门）。
  final Widget source;

  /// 练习侧子树（相机实时预览件）。
  final Widget practice;

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape) {
      return Row(
        children: [
          Expanded(child: source),
          const _CompareSplitGap(),
          Expanded(child: practice),
        ],
      );
    }
    return Column(
      children: [
        Expanded(child: source),
        const _CompareSplitGap(),
        Expanded(child: practice),
      ],
    );
  }
}

/// 分屏细缝：纯黑分隔条，横屏为竖缝、竖屏为横缝。
class _CompareSplitGap extends StatelessWidget {
  const _CompareSplitGap();

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Container(
      color: Colors.black,
      width: landscape ? kCompareSplitGap : double.infinity,
      height: landscape ? double.infinity : kCompareSplitGap,
    );
  }
}
