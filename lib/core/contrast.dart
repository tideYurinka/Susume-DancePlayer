/// WCAG 对比度判定的共用纯函数接缝。只认 ARGB 整数、不 import Flutter：
/// 系统页 token 与控制层 token 用同一份判定，期望值一律来自 4.5:1 下限与
/// 「文字实际压着的底色」，不从实现推导。
library;

import 'dart:math' as math;

/// 对比度下限（「四个下限」：4.5:1）。
const kContrastFloor = 4.5;

/// sRGB 非线性通道 → 线性光（WCAG 2.x 相对亮度定义）。
double _linearChannel(int value) {
  final x = value / 255;
  return x <= 0.03928
      ? x / 12.92
      : math.pow((x + 0.055) / 1.055, 2.4).toDouble();
}

/// ARGB 颜色的 WCAG 相对亮度（0 黑 → 1 白）。
double relativeLuminance(int argb) => 0.2126 * _linearChannel((argb >> 16) & 255) +
    0.7152 * _linearChannel((argb >> 8) & 255) +
    0.0722 * _linearChannel(argb & 255);

/// 两色对比度（亮者作分子，与参数顺序无关）。
double contrastRatio(int a, int b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 达标判定：下限固定 4.5:1（[kContrastFloor]）。半透明前景先把 alpha 合
/// 成到底色再判（合成是调用方的口径，本函数只对不透明取值负责）。
bool meetsContrastFloor(int foreground, int background) =>
    contrastRatio(foreground, background) >= kContrastFloor;
