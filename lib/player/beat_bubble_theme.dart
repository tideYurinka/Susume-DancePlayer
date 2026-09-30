/// 节拍气泡内容暗色主题：节拍提示气泡与**节拍对齐独立气泡**共用的内容级
/// 主题。
///
/// 气泡底为深色浮层，亮色默认主题下 Switch/文本/按钮不可读。
///
/// 在内容级深色主题上叠紧凑项——紧凑视觉密度 +
/// Switch 收缩触控目标（shrinkWrap）+ 紧凑轨道——把 Switch/滑条行高从
/// Material 默认 48 收到 ~36（只包节拍侧气泡内容，速/步/avSync 不受影响）。
library;

import 'package:flutter/material.dart';

/// 节拍侧气泡内容主题（模块级缓存，避免每次 build 重建整套主题）。
final ThemeData beatBubbleContentTheme = _buildBeatBubbleTheme();

ThemeData _buildBeatBubbleTheme() {
  final base = ThemeData.dark();
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    switchTheme: const SwitchThemeData(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    sliderTheme: base.sliderTheme.copyWith(trackHeight: 3),
  );
}
