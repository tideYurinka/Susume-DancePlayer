/// 浮层模块：两类内容类（数拍动画浮层与备注贴纸）共用的值与换算——角序、
/// 四格浮层位容器、尺寸换算与几何存取接口。
///
/// 各内容类自己的几何参考系与存取归属由各自控制器承担并声明（数拍动画
/// 浮层 = 播放页视口参考系 + 本地私密存取；备注贴纸 = 视频内容矩形归一化
/// + 公开标记文件），本模块不假设、不分支。
///
/// 依赖一律显式：本模块只 import `dart:math`、`dart:ui` 与节拍动画样式
/// （尺寸换算的形态入参），不 import 中枢、不碰构建上下文。
library;

import 'dart:math' show min;
import 'dart:ui' show Offset, Size;

import 'beat_animation.dart' show BeatAnimationStyle;

part 'overlay_geometry_binding.dart';
part 'overlay_placement.dart';
part 'overlay_sizing.dart';

/// 浮层四角（角工具的渲染次序 = 本枚举序）。
enum OverlayCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}
