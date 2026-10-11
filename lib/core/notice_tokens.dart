/// 黑底胶囊视觉 token（全站点 black87 pill 收敛为 [NoticeBadge]
/// 单一渲染位，此处为唯一取值来源）。各值等于收敛前的手写字面量，
/// 外观零变化。
///
/// 词汇说明：`lib/player/GLOSSARY.md`「短暂提示」词条指「纯提示不承载交互」的浮层族；
/// 本组 token/[NoticeBadge] 是更底层的**黑底胶囊视觉底座**，除短暂提示族外
/// 也被少量交互内容槽（循环提示的「不循环」按钮、mirror 询问卡）按同款
/// 视觉复用——是有意的跨族复用，非「短暂提示」词条成员。
///
/// - 胶囊（[NoticeBadge] / 各事件驱动徽章共用）：黑底、浮起、圆角 8、
///   内边距 16×10、白字 14。
/// - 卡片级（mirror 询问卡与未来交互面防漂移）：圆角 20、内边距 20、
///   标题 19，以及询问卡的两栏依据配色与间距。
library;

import 'package:flutter/material.dart';

import 'hit_target.dart' show kHitTargetMinSize;

/// 胶囊底色（黑 87% 不透明）。
const Color kNoticeBackground = Colors.black87;

/// 胶囊浮起高度。
const double kNoticeElevation = 4;

/// 胶囊圆角半径。
const double kNoticeRadius = 8;

/// 胶囊水平内边距。
const double kNoticePaddingH = 16;

/// 胶囊垂直内边距。
const double kNoticePaddingV = 10;

/// 胶囊文字颜色。
const Color kNoticeTextColor = Colors.white;

/// 胶囊文字字号。
const double kNoticeFontSize = 14;

/// 胶囊文字样式（底座内纯文本内容的统一样式——各站点引用同一 const，
/// 改色/字号一处生效）。
const TextStyle kNoticeTextStyle = TextStyle(
  color: kNoticeTextColor,
  fontSize: kNoticeFontSize,
);

// ── 角落提示卡紧凑档 ──
// 左下角两张提示卡（循环提示、续播提示）自己的卡体尺寸口子：**同一处定义、
// 两卡共用**，调用方不各自写字号与内边距；全站其它黑底胶囊走上面的默认档。

/// 紧凑胶囊水平内边距。
const double kCornerPromptCardPaddingH = 12;

/// 紧凑胶囊垂直内边距：0——卡高由按钮的命中下限撑起，不留内边距高度
/// （见 [kCornerPromptCardButtonMinSize]）。
const double kCornerPromptCardPaddingV = 0;

/// 紧凑胶囊内边距（传 [NoticeBadge] 的覆盖口）。
const EdgeInsets kCornerPromptCardPadding = EdgeInsets.symmetric(
  horizontal: kCornerPromptCardPaddingH,
  vertical: kCornerPromptCardPaddingV,
);

/// 紧凑字号。
const double kCornerPromptCardFontSize = 12;

/// 紧凑文字样式：`inherit: false` 切断环境 [DefaultTextStyle]——Material
/// `bodyMedium` 的 letterSpacing 会参与合并，实测宽度随之偏离字号档的名义值；
/// 量测与渲染同源（同 `kNoteBubbleTextStyle` 的纪律）。
const TextStyle kCornerPromptCardTextStyle = TextStyle(
  inherit: false,
  color: kNoticeTextColor,
  fontSize: kCornerPromptCardFontSize,
);

/// 卡内文案与按钮之间的间距。
const double kCornerPromptCardGap = 8;

/// 卡内按钮水平内边距。
const EdgeInsets kCornerPromptCardButtonPadding = EdgeInsets.symmetric(
  horizontal: 8,
);

/// 卡内按钮命中下限：宽不限（宽度按文案实测）、高 = 通用命中下限——卡的
/// 48dp 高由它撑起，文本在卡内垂直居中。
const Size kCornerPromptCardButtonMinSize = Size(0, kHitTargetMinSize);

/// 卡内动作按钮样式（两卡共用）：文字色走 `foregroundColor`——ButtonStyle
/// 以它覆盖 `textStyle` 里的颜色，故样式里的白只作正文用。
final ButtonStyle kCornerPromptCardButtonStyle = TextButton.styleFrom(
  foregroundColor: Colors.lightBlueAccent,
  padding: kCornerPromptCardButtonPadding,
  minimumSize: kCornerPromptCardButtonMinSize,
  textStyle: kCornerPromptCardTextStyle,
);
