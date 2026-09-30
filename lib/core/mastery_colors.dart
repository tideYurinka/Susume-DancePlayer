/// 熟练度五档色常量与取色入口。
///
/// 跨域共享：`lib/home` / `lib/stats` 的图表与播放器段体取同一套五档色，
/// 取色入口放在跨域可读的 core 层——与 `lib/core/contrast.dart`、
/// `lib/core/hit_target.dart` 的跨域落点做法相同。「唯一写者」不变：色值
/// 只在此声明，播放域经 `lib/player/visual_tokens.dart` 原样转出读取。
library;

import 'package:flutter/material.dart';

import 'learning_mastery.dart';

/// 熟练度五档颜色（片段填充与工具区图例共用同一 token），按档位线性递进：
/// 未练灰（= `Colors.grey.shade600`）→ 学习中琥珀（取值 `#E6B13C`，
/// 柔和不刺眼）→ 能跟上黄绿 → 较熟浅绿 → 掌握绿（`Colors.green`）。
const Color kMasteryUnlearnedColor = Color(0xFF757575);
const Color kMasteryLearningColor = Color(0xFFE6B13C);
const Color kMasteryKeepingUpColor = Color(0xFFCDDC39);
const Color kMasteryFamiliarColor = Color(0xFF8BC34A);
const Color kMasteryMasteredColor = Colors.green;

/// 学习段/图例的熟练度取色入口（图例与轨道同值，修正项）。
Color learningMasteryColor(LearningMastery mastery) => switch (mastery) {
  LearningMastery.unlearned => kMasteryUnlearnedColor,
  LearningMastery.learning => kMasteryLearningColor,
  LearningMastery.keepingUp => kMasteryKeepingUpColor,
  LearningMastery.familiar => kMasteryFamiliarColor,
  LearningMastery.mastered => kMasteryMasteredColor,
};
