/// 取景条：取景调节态
/// 画面**底部**的操作条——标题「取景」、手势提示「拖动圈选画面」、「复位」与
/// 「完成」。取景只剩手势一条路，条上只发这两条命令。
///
/// 本件**只发命令**（复位、完成），不读会话取值，因此也不随拖动逐帧重建；
/// **不含任何缩放倍数读数**。
///
/// 提示降级按**是否真放得下**判定（吃条自身的约束宽度，不按屏幕宽度误判）：
/// 放不下「标题＋提示＋两枚按钮」时，提示换到标题**下一行、居中**，条高按
/// 内容增高、下限 [kCompareFramingBarMinHeight]；列宽再不足时列内两行文字
/// 各自单行省略，两枚按钮的固有宽不被挤掉。
///
/// 落位口径（依据源侧半区的 contain 黑边算术）：横屏源侧半区（该次量测所用视口）389.9 × 361.1dp、
/// **16:9** 源画面高 219.3dp ⇒ 上下各 70.9dp 黑边；距底 8dp 下条高上限
/// 62.9dp，故单行取下限 60dp——整条落在源侧画面之外的**下黑边**里，一点不遮
/// 画面。条水平居中于屏幕：源侧半区只有 389.9dp 宽、放不下本条，故条会越过
/// 分缝压住练习侧预览的一角（任何落位都会压住一点预览，不作承诺）。
///
/// 两处**不承诺**（照实写明，免得当成 bug 追）：① 上面那条算术只对 16:9 源
/// 画面成立——更扁的源画面（如 16:10 黑边仅 58.7dp）条会压住画面下缘；竖屏
/// 源画面甚至没有上下黑边；② 竖屏半区（该次量测所用视口）361.1 × 389.9dp，条高不变、横向居中，
/// 不遮画面的承诺不成立（黑边在左右）。非 16:9 的落位差异不在上述量测口径内
/// （条高与距底都是固定值），留待真机重验。
library;

import 'package:flutter/material.dart';

import '../core/text_extent.dart';

/// 条高下限：单行内容（按钮 48dp＋上下内边距与描边）天然为 60dp；两行或
/// 大字号时按内容增高。落位用的黑边算术见库头「落位口径」。
const double kCompareFramingBarMinHeight = 60;

/// 条上下内边距：单行内容（按钮 48dp）＋上下各 5dp＋上下描边各 1dp = 恰好
/// 下限 60dp（[Container] 的描边宽计入装饰内边距）。
const double kCompareFramingBarVerticalPadding = 5;

/// 距屏幕下缘。与 [kCompareFramingBarMinHeight] 一起决定「整条落在下黑边内」。
const double kCompareFramingBarBottomInset = 8;

const double kCompareFramingBarRadius = 28;

/// 左右内边距。
const double kCompareFramingBarPadding = 16;

/// 不透明深底（黑 78%）——压在视频上也读得清，并让按钮轮廓可辨。
/// 与 `kNotice*` 提示族（黑 87%、圆角 8）不是同一族：本条更大更圆、更透，
/// 是画面上的常驻操作条而非一闪而过的提示。
const Color kCompareFramingBarColor = Color(0xC7000000);

/// 1 像素浅描边（深底压在暗画面上时靠它给出轮廓）。
const Color kCompareFramingBarBorderColor = Color(0x40FFFFFF);

const double kCompareFramingBarBorderWidth = 1;

/// 阴影（让条从画面上浮起来、与画面分离）。
const Color kCompareFramingBarShadowColor = Color(0x73000000);

const double kCompareFramingBarShadowBlur = 12;
const Offset kCompareFramingBarShadowOffset = Offset(0, 4);

const double kCompareFramingBarTitleFontSize = 16;
const FontWeight kCompareFramingBarTitleFontWeight = FontWeight.w600;

/// 手势提示字号与不透明度（次要信息，压在主标题旁）。
const double kCompareFramingBarHintFontSize = 12;
const double kCompareFramingBarHintOpacity = 0.86;

/// 标题与提示同排时的横向间距；换行后同样是两行之间的纵向间距。
const double kCompareFramingBarTitleHintGap = 10;

/// 提示与按钮组之间的间距。
const double kCompareFramingBarHintButtonsGap = 16;

/// 两枚按钮之间的间距。
const double kCompareFramingBarButtonGap = 8;

/// 按钮命中区下限（手指不用瞄准）——高与宽都给足。
const double kCompareFramingBarButtonMinSize = 48;

/// 描边按钮的边框不透明度（显式白色前景，不吃 M3 默认主色）。
const double kCompareFramingBarResetBorderOpacity = 0.6;

/// 按钮左右内边距（在 [kCompareFramingBarButtonMinSize] 之外另给余量）。
const double kCompareFramingBarButtonPadding = 16;

const String kCompareFramingBarTitle = '取景';

const String kCompareFramingBarHint = '拖动圈选画面';

/// 「复位」文案（清取值、回到整帧；取景只有源画面一份）。
const String kCompareFramingBarResetLabel = '复位';

/// 「完成」文案（退出取景态）。
const String kCompareFramingBarDoneLabel = '完成';

/// 取景调节态的底部取景条。纯展示件：前景显式白色（不指定前景会吃 M3
/// `TextButton` 默认 = [ColorScheme.primary]，浅色主题的深紫压在深底与视频
/// 上不可读），两条命令经 [onReset] / [onDone] 回宿主。
class FramingBar extends StatelessWidget {
  const FramingBar({
    super.key,
    required this.onDone,
    required this.onReset,
  });

  /// 「完成」：退出取景态（对比路径回对比-控制层、单画面路径回编辑态）。
  final VoidCallback onDone;

  /// 「复位」：清取值、回到整帧。
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    // 降级判定吃**条自身的约束宽度**（`constraints.maxWidth`），不另取
    // MediaQuery 的屏幕宽度：宿主今天把条挂在 `Positioned(left:0,right:0)`
    // 上，条的可伸张宽就是屏幕宽度，两者同值；但若将来宿主把条放进更窄的
    // 容器，这里仍按真实可用宽判定，不会拿屏幕宽度误判。无界时（不该发生）
    // 退回屏幕宽度，保持既有真机行为。
    final screenWidth = MediaQuery.sizeOf(context).width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : screenWidth;
        final inline = _fitsOnOneLine(context, barWidth);
        return ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kCompareFramingBarMinHeight,
          ),
          child: Container(
            key: const Key('framing_bar'),
            padding: const EdgeInsets.symmetric(
              horizontal: kCompareFramingBarPadding,
              vertical: kCompareFramingBarVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: kCompareFramingBarColor,
              borderRadius: BorderRadius.circular(kCompareFramingBarRadius),
              border: Border.all(
                color: kCompareFramingBarBorderColor,
                width: kCompareFramingBarBorderWidth,
              ),
              boxShadow: const [
                BoxShadow(
                  color: kCompareFramingBarShadowColor,
                  blurRadius: kCompareFramingBarShadowBlur,
                  offset: kCompareFramingBarShadowOffset,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 文字列：放得下时标题与提示同排；放不下时提示换到标题下一行、
                // 居中（两行在列内居中）。列宽不足时两行各自单行省略，两枚
                // 按钮各自的固有宽不被挤掉（按钮是非弹性子件，先拿固有宽）。
                Flexible(
                  child: inline
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _title(),
                            const SizedBox(
                              width: kCompareFramingBarTitleHintGap,
                            ),
                            Flexible(child: _hint()),
                          ],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _title(),
                            const SizedBox(
                              height: kCompareFramingBarTitleHintGap,
                            ),
                            _hint(),
                          ],
                        ),
                ),
                const SizedBox(width: kCompareFramingBarHintButtonsGap),
                OutlinedButton(
                  key: const Key('framing_reset'),
                  onPressed: onReset,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(
                        alpha: kCompareFramingBarResetBorderOpacity,
                      ),
                    ),
                    minimumSize: const Size(
                      kCompareFramingBarButtonMinSize,
                      kCompareFramingBarButtonMinSize,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: kCompareFramingBarButtonPadding,
                    ),
                  ),
                  child: const Text(kCompareFramingBarResetLabel),
                ),
                const SizedBox(width: kCompareFramingBarButtonGap),
                FilledButton(
                  key: const Key('framing_done'),
                  onPressed: onDone,
                  // 主色填充按钮：底色/前景吃主题主色（onPrimary），不覆写。
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(
                      kCompareFramingBarButtonMinSize,
                      kCompareFramingBarButtonMinSize,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: kCompareFramingBarButtonPadding,
                    ),
                  ),
                  child: const Text(kCompareFramingBarDoneLabel),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _title() => const Text(
    kCompareFramingBarTitle,
    key: Key('framing_bar_title'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white,
      fontSize: kCompareFramingBarTitleFontSize,
      fontWeight: kCompareFramingBarTitleFontWeight,
    ),
  );

  Widget _hint() => Text(
    kCompareFramingBarHint,
    key: const Key('framing_bar_hint'),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.white.withValues(alpha: kCompareFramingBarHintOpacity),
      fontSize: kCompareFramingBarHintFontSize,
    ),
  );
}

/// 「标题＋提示＋两枚按钮」在一行里是否真放得下 [availableWidth]。
///
/// 量测与渲染同源：文字宽度按当前 [DefaultTextStyle] 合并后的样式、
/// 当前 `MediaQuery.textScalerOf`（`Text` 侧同样吃这两者）；按钮固有宽
/// = 标签宽 + 左右内边距，再取 [kCompareFramingBarButtonMinSize] 下限
/// （与 [ButtonStyleButton] 的 `padding`/`minimumSize` 同源）。另计条自身
/// 的左右内边距与描边宽（[Container] 的装饰内边距）。
bool _fitsOnOneLine(BuildContext context, double availableWidth) {
  final baseStyle = DefaultTextStyle.of(context).style;
  final textScaler = MediaQuery.textScalerOf(context);

  double textWidth(String text, TextStyle style) => measureTextExtent(
    text,
    style,
    scaler: textScaler,
    maxLines: 1,
  ).width;

  final labelStyle =
      Theme.of(context).textTheme.labelLarge ??
      const TextStyle(
        fontSize: 14,
        letterSpacing: 0.1,
        fontWeight: FontWeight.w500,
      );
  double buttonWidth(String label) {
    final labelWidth = textWidth(label, labelStyle);
    final intrinsic = labelWidth + 2 * kCompareFramingBarButtonPadding;
    return intrinsic > kCompareFramingBarButtonMinSize
        ? intrinsic
        : kCompareFramingBarButtonMinSize;
  }

  final required =
      2 * kCompareFramingBarBorderWidth +
      2 * kCompareFramingBarPadding +
      textWidth(
        kCompareFramingBarTitle,
        baseStyle.merge(
          const TextStyle(
            fontSize: kCompareFramingBarTitleFontSize,
            fontWeight: kCompareFramingBarTitleFontWeight,
          ),
        ),
      ) +
      kCompareFramingBarTitleHintGap +
      textWidth(
        kCompareFramingBarHint,
        baseStyle.merge(
          const TextStyle(fontSize: kCompareFramingBarHintFontSize),
        ),
      ) +
      kCompareFramingBarHintButtonsGap +
      buttonWidth(kCompareFramingBarResetLabel) +
      kCompareFramingBarButtonGap +
      buttonWidth(kCompareFramingBarDoneLabel);
  return required <= availableWidth;
}
