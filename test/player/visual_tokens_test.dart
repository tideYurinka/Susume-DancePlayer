import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 集中视觉 token 的规格锚点。
///
/// 断言值取自规格，不是从实现推导：
/// 激活色默认 `#39C5BB`；图例灰与轨道未练灰同值（`Colors.grey.shade600`）。
void main() {
  test('激活色 token 默认值为 spec 指定的 #39C5BB（替换原蓝）', () {
    expect(kCyanAccentColor, const Color(0xFF39C5BB));
  });

  test('不可用文字按底色分两个落点——深底工具条 white54、浅底菜单 onSurface 38% 档', () {
    // 深底工具条（底排槽 + 顶栏）保持在册取值不动。
    expect(kToolSlotDisabledTextColor, Colors.white54);
    // 浅底弹出菜单 = 低强调 38% 档（浅色主题 onSurface = 不透明黑）。
    expect(kToolMenuDisabledTextColor, const Color(0x61000000));
    expect(kToolMenuDisabledTextColor.a, closeTo(0.38, 0.001));
    expect(
      kToolMenuDisabledTextColor,
      isNot(kToolSlotDisabledTextColor),
      reason: '两个底色各有自己的一个灰，不复用同一条白字灰',
    );
  });

  test('名册色板是集中视觉常量、24 色、互不重复', () {
    expect(kRosterPalette.length, 24);
    expect(kRosterPalette.toSet().length, 24);
    for (final argb in kRosterPalette) {
      expect(
        (argb >> 24) & 0xFF,
        0xFF,
        reason: '色板色全不透明: 0x${argb.toRadixString(16)}',
      );
    }
  });

  test('熟练度五档颜色集中定义：未练灰与轨道灰一致，逐档可取色且互不相同', () {
    expect(
      learningMasteryColor(LearningMastery.unlearned),
      Colors.grey.shade600,
    );
    // 取值：学习中柔和金黄 #E6B13C。
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

    // 五档取色覆盖全部枚举值且两两不同（颜色是一眼分辨档位的唯一信号）。
    final colors = {
      for (final mastery in LearningMastery.values)
        learningMasteryColor(mastery),
    };
    expect(colors, hasLength(LearningMastery.values.length));
  });

  group('对比度下限 4.5:1（纯函数 + token 级断言）', () {
    // 期望值来自 ：对比度下限 4.5:1，按文字实际压着的
    // 底色（含半透明合成后）算。底衬压在播放器黑底上时按叠黑合成——
    // 半透底衬下的视频内容不可断定，可断定的底色取底衬叠黑。
    const black = Colors.black;

    /// 文字色压在底色上、底色再叠黑合成后的实际对比度：前景与判定底都取
    /// 叠黑后的**不透明**合成结果再算比值（半透底衬不能直接进对比度比值
    /// ——`computeLuminance` 忽略 alpha，直接传会碰巧算对、写法脆弱）。
    double actualContrast(Color fg, Color bg) {
      final base = Color.alphaBlend(bg, black);
      return contrastRatio(Color.alphaBlend(fg, base), base);
    }

    test('纯函数锚点：白对黑 = 21:1，同色 = 1:1', () {
      expect(contrastRatio(Colors.white, Colors.black), closeTo(21, 0.01));
      expect(contrastRatio(Colors.black, Colors.black), 1.0);
      expect(relativeLuminance(Colors.black), 0);
      expect(relativeLuminance(Colors.white), closeTo(1, 0.001));
    });

    test('① 不可用态槽标签（white54）在控制工具条底衬上 ≥ 4.5', () {
      expect(
        actualContrast(kToolSlotDisabledTextColor, kControlToolbarScrimColor),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('② 备注输入框提示色在备注面板底上 ≥ 4.5', () {
      expect(
        actualContrast(kNoteFieldHintColor, kNoteEditorPanelColor),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('④ 倍速气泡空态色在气泡底衬上 ≥ 4.5', () {
      expect(
        actualContrast(kSpeedHistoryEmptyTextColor, kSpeedBubbleScrimColor),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('⑤ 轨道设置条关闭态文字在设置开关底衬上 ≥ 4.5', () {
      expect(
        actualContrast(kSettingsToggleOffTextColor, kSettingsToggleScrimColor),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('⑥ 音画同步禁用档位钮前景在共享气泡底衬上 ≥ 4.5', () {
      expect(
        actualContrast(kAvSyncTierDisabledTextColor, kSpeedBubbleScrimColor),
        greaterThanOrEqualTo(4.5),
      );
    });
  });
}
