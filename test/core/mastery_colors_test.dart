import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/core/mastery_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 熟练度五档取色的 core 层锚点。
///
/// 断言值来自既有播放侧 token 锚点（`test/player/visual_tokens_test.dart`），
/// 不是从实现推导：未练灰 = `Colors.grey.shade600`、学习中 `#E6B13C`、
/// 能跟上 `#CDDC39`、较熟 `#8BC34A`、掌握 = `Colors.green`。
void main() {
  test('五档色逐位不变：未练灰 / 学习中琥珀 / 能跟上黄绿 / 较熟浅绿 / 掌握绿', () {
    expect(
      learningMasteryColor(LearningMastery.unlearned),
      Colors.grey.shade600,
    );
    expect(
      learningMasteryColor(LearningMastery.learning),
      const Color(0xFFE6B13C),
    );
    expect(
      learningMasteryColor(LearningMastery.keepingUp),
      const Color(0xFFCDDC39),
    );
    expect(
      learningMasteryColor(LearningMastery.familiar),
      const Color(0xFF8BC34A),
    );
    expect(learningMasteryColor(LearningMastery.mastered), Colors.green);
  });

  test('五档取色覆盖全部枚举值且两两不同（颜色是档位的唯一分辨信号）', () {
    final colors = {
      for (final mastery in LearningMastery.values)
        learningMasteryColor(mastery),
    };
    expect(colors, hasLength(LearningMastery.values.length));
  });
}
