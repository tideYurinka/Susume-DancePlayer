/// 集中视觉 token（轨道颜色集中与共享青色参数化）。
///
/// 学习段轨相关颜色（熟练度片段填充/分段线/flag/首尾线/选中/图例/
/// 图标激活高亮）的唯一取色来源——取代散布在 track_band / control_layer /
/// scrub_indicator / speed_panel / player_page 中的字面量。
///
/// - 共享青 [kCyanAccentColor] 为**参数化默认值**：一处定义、
///   处处生效；默认 `#39C5BB`。后续多套配色方案（本批不做切换 UI）
///   只需在此替换/参数化该 token。
/// - 图例灰与轨道未练灰同值（修正既有 shade300/shade600 不一致）。
/// - 本批不引入主题/配色切换 UI；渲染外观除激活边框默认色与图例灰一致性
///   外不变。
library;

import 'package:flutter/material.dart';

import '../core/contrast.dart' as contrast;

// 通用 48 命中盒下限由 `lib/core/hit_target.dart` 声明；本层转出供播放域
// 读取点使用，名字与取值不变。
export '../core/hit_target.dart' show kHitTargetMinSize;

// ── 熟练度五档色──
// 五档色常量与取色入口 `learningMasteryColor` 唯一声明在跨域可读的
// `../core/mastery_colors.dart`；本层原样转出，播放域既有调用点与测试
// 断言的 import 路径不变。
export '../core/mastery_colors.dart'
    show
        kMasteryUnlearnedColor,
        kMasteryLearningColor,
        kMasteryKeepingUpColor,
        kMasteryFamiliarColor,
        kMasteryMasteredColor,
        learningMasteryColor;

// 黑底胶囊视觉 token 唯一声明在跨域可读的 `../core/notice_tokens.dart`
// （`lib/update` 取角落提示卡尺寸）；本层原样转出，播放域既有调用点与测试
// 断言的 import 路径不变。
export '../core/notice_tokens.dart'
    show
        kNoticeBackground,
        kNoticeElevation,
        kNoticeRadius,
        kNoticePaddingH,
        kNoticePaddingV,
        kNoticeTextColor,
        kNoticeFontSize,
        kNoticeTextStyle,
        kCornerPromptCardPaddingH,
        kCornerPromptCardPaddingV,
        kCornerPromptCardPadding,
        kCornerPromptCardFontSize,
        kCornerPromptCardTextStyle,
        kCornerPromptCardGap,
        kCornerPromptCardButtonPadding,
        kCornerPromptCardButtonMinSize,
        kCornerPromptCardButtonStyle;

// ── 字号档：两档边界与唯一话术 ──
// 判据是「读不到它会不会丢失信息」，只有两档：
// - 语义档（随系统字号）：承载语义的文本随系统字号缩放；量测与渲染两侧吃
//   同一个缩放值（调用处 `MediaQuery.textScalerOf`），所在盒子的高度容量
//   相应放开或按缩放重算。点名处见各文件就地标注。
// - 装饰档（固定排版，不承载语义）：刻度、片头与图标旁小字等纯装饰与读数
//   标记保持固定排版；固定排版的理由是量测与渲染同源——样式只此一份、两侧
//   同不吃缩放，盒宽不随字号变化，因此不会把所在盒子撑破。
// 每一处文本按本话术就地标注；非文本的固定几何（图标边长等）不属字号档，
// 就地写明它与字号无关。

/// 学习段选中与节拍动画/数拍数字共用的青色主色（参数化默认 token，
///  `#39C5BB`）。
const Color kCyanAccentColor = Color(0xFF39C5BB);

// ── 键盘焦点反馈 token──

/// 键盘焦点反馈色：控制层关键入口、画面播放开关与轨道端点控制柄共用；
/// 深色画面/浮层上的焦点反馈统一 24% 白，单处声明。
const Color kKeyboardFocusHighlight = Colors.white24;

// ── 局部镜像片段块 token──
// 启用 = 琥珀（启用片段琥珀呈现）、禁用 = 灰、选中态
// 白描边清晰可辨。图标沿用翻映语义（Icons.flip）。

/// 局部镜像片段生效主色（琥珀，同 [kHighlightAmber] 家族但独立 token）。
/// 「Enabled」= 局部镜像**总开关**开（片段为纯区间，无自带启停位）。
const Color kLocalMirrorEnabledColor = Colors.amber;

/// 局部镜像片段生效填充（半透琥珀，块体底色）。
const Color kLocalMirrorEnabledFill = Color(0x66FFB300);

/// 局部镜像片段生效图标色（不透明琥珀，于半透底上清晰）。
const Color kLocalMirrorEnabledIconColor = Color(0xFFFFD54F);

/// 局部镜像片段不生效主色/描边（灰，总开关关）。
const Color kLocalMirrorDisabledColor = Colors.white38;

/// 局部镜像片段不生效图标色（灰，与 [kLocalMirrorDisabledColor] 同值——
/// 不生效时描边与图标同一个灰）。
const Color kLocalMirrorDisabledIconColor = Colors.white38;

/// 局部镜像片段禁用填充（深灰半透）。
const Color kLocalMirrorDisabledFill = Color(0x55757575);

/// 局部镜像片段端点命中带宽（块体两端可拖区，起手即进入端点拖）。
const double kLocalMirrorEdgeHitWidth = 14;

/// 局部镜像片段点按最小命中宽（可调初值 40dp）。
///
/// 片段点按命中域 = 区间对称扩展至不小于本宽（宽段不收缩，见
/// `resolveLocalMirrorTapHit`）。取 40dp 与本轨家族分段线/首尾线抓取宽
/// 同档：既给窄片段（视觉上很小）留出"点附近即中"的裕量，又不会大到让
/// 密集片段的命中域互相大量侵占；块体自身的点按仍以 24dp 级手感即可。
const double kLocalMirrorTapHitWidth = 40;

/// 「窄块」唯一阈值（可调）：局部镜像片段块像素宽不足该值即窄块。
/// 取 40dp，大于 2×[kLocalMirrorEdgeHitWidth] = 28dp——块宽低于后者时两条
/// 端点带覆盖整块、吞掉块体点按的死区必然出现。这是**唯一窄块口径**：
/// 端点带抑制、行级点按放宽、窄块不绘图标都
/// 复用本常量，不再各设标准。
const double kLocalMirrorNarrowWidth = 40;

/// 局部镜像片段块体圆角半径（具名视觉常量——备注块圆角
/// [kNoteBlockCornerRadius] 沿用的就是本条块体纪律，取值同源）。
const double kLocalMirrorBlockCornerRadius = 4;

/// 局部镜像片段块体竖向内边距（具名视觉常量，备注块内边距
/// [kNoteBlockVerticalPadding] 沿用的同款纪律）。
const double kLocalMirrorBlockVerticalPadding = 3;

// ── 标注工具区槽位视觉 token ──
// 底排 13 个标注工具槽的置灰 / 启用取值与节奏各只有这一处来源；槽件只引用
// token，不再出现字面灰值。顶栏工具槽不并入底排（硬门语义，见
// control_layer 的 _PlayTool 注释），但不可用图标色共享
// [kToolSlotDisabledIconColor]。

/// 不可用图标色（统一灰，用户裁决 `white38`——同一排只有这一种灰）。
const Color kToolSlotDisabledIconColor = Colors.white38;

/// 不可用文字色（**深底工具条**专用，保持 `white54`）。
const Color kToolSlotDisabledTextColor = Colors.white54;

/// 启用图标色（统一白，用户裁决 `white70`）。
const Color kToolSlotEnabledIconColor = Colors.white70;

/// 启用文字色（与图标同值）。
const Color kToolSlotEnabledTextColor = Colors.white70;

/// 激活态文字色（激活图标色为各槽可选输入：熟练度色 / 琥珀）。
const Color kToolSlotActiveTextColor = Colors.white;

/// 槽位图标尺寸（统一 24）。
const double kToolSlotIconSize = 24;

/// 槽位标签字号（统一 10；**语义档（随系统字号）**：标签承载语义、随系统
/// 字号缩放，量测宽与渲染同源——顶栏定宽槽的实测与渲染共用 control_layer 的
/// `_kToolSlotLabelStyle` 同一份）。
const double kToolSlotLabelFontSize = 10;

/// 槽位外层水平内边距（统一「外 6」）。
const double kToolSlotOuterPaddingH = 6;

/// 槽位内层水平内边距（统一「内 4」）。
const double kToolSlotInnerPaddingH = 4;

/// 槽位内层垂直内边距（统一「内 4」）。
const double kToolSlotInnerPaddingV = 4;

/// 槽位点击圆角（统一 6）。
const double kToolSlotRadius = 6;

// ── 命中盒下限 token ──
// 通用下限 48 声明在跨域可读的 `lib/core/hit_target.dart`，本层
// 转出该名字。邻接密集区兜底 44 只服务播放域，与兜底清单同住本层；两个名字
// 各只有一个写者。

/// 邻接密集区兜底下限（dp）：邻接密集区（标注工具区槽位排、轨道手柄带
/// 互斥槽、备注贴纸四角、数拍浮层四角）允许以 44 兜底。
///
/// 兜底不是默认值：每一处消费都要在该处注释里说明「为什么这里达不到
/// 48」，并记入下方代价清单，不许默认继承。
const double kHitTargetDenseMinSize = 44;

/// 允许以密集区兜底落地的消费点清单（仓库相对源码路径 → 这一处达不到 48
/// 的代价）：清单只此一处声明。
///
/// 渲染侧不读本表；每一处读取 [kHitTargetDenseMinSize] 的文件都要在这里
/// 点名，清单条目也要能在源码里找到读取点（双向，防单向空过）。新写的
/// 偏小命中盒没点名不许默认继承。
const Map<String, String> kHitTargetDenseAllowedSites = <String, String>{
  'lib/player/control_layer.dart':
      '标注工具区槽位排六/七槽同排、槽间只隔「外 6」，'
      '按 48 外扩相邻命中域会互吞；横屏「转为竖屏」'
      '钮上与顶栏、下与轨道带各只隔 4dp 间隙，纵向容纳不下 48，取 44 兜底'
      '（上探与返回键命中域底缘重叠约 2dp，下探止于轨道带上缘不越界）',
};

// ── 播放器皮肤 ──
// 播放页的黑底是**播放器皮肤**的显式声明，不是「硬编码黑色」：App 当前是
// 单亮色主题、播放器为固定深色皮肤（不引入 themeMode / darkTheme），
// 播放器浮层的对比度复核都在这一定式下做。

/// 播放器皮肤底色（**固定深色皮肤**，不随主题取值）。
const Color kPlayerSkinColor = Colors.black;

// ── 浅底弹出菜单不可用文字色 ──
// 「添加」与「自动分段」两个弹出菜单的底色是近白面板，深底工具条的
// `white54` 在它上面读不出来——不可用文字因此按底色分两个落点（深底工具条
// [kToolSlotDisabledTextColor] / 浅底弹出菜单本条），两个底色各有自己的
// 一个灰。取 Material 低强调文字的 38% 档（浅色主题的 `onSurface` 即不透明
// 黑）；取值是常量、不读 `Theme.of`——视觉 token 层保持无 context，菜单
// 底色换深时本条随之改。

/// 浅底弹出菜单不可用文字色（**浅底弹出菜单专用**，`onSurface` 38% 档）。
const Color kToolMenuDisabledTextColor = Colors.black38;

// ── 八拍锚点 token──
// 锚点在节拍轨上以**第二色大线 + 轨顶小标记**呈现：
// 与白色自动八拍大线一眼可分；不做拖动，也不因锚点升/降级弹额外提示。

/// 八拍锚点线色（第二色，与白色自动大线区分）。
const Color kBeatAnchorLineColor = Color(0xFFFFB300);

/// 八拍锚点轨顶小标记尺寸（方形槽内圆形点，居中锚点 x）。
const double kBeatAnchorMarkerSize = 6;

// ── 节拍轨三态 token──
// 占位态 = 整行不定态进度条（流动光带，不表达百分比）；异常态 = 整行暖色底。

/// 节拍轨占位态流动光带色（琥珀低不透明度，与白色刻度一眼可分）。
const Color kBeatTrackAnalyzingColor = Color(0x66FFB300);

/// 节拍轨异常态整行暖色底（低饱和告警色）。
const Color kBeatTrackErrorBackground = Color(0x40BF360C);

/// 节拍轨异常态行内文案色。
const Color kBeatTrackErrorTextColor = Color(0xFFFFCCBC);

// ── 轨道片头 token──
// 轨道最左、位于时间轴零点**之前**的一列短文字标签（行集之外的一列，不是
// 行）：底色比轨道带深一档、右缘一条浅分界线把标签与内容分开。文字
// **装饰档（固定排版，不承载语义）**：片头只是分区标签，读不到它不丢失
// 信息；固定排版的理由是量测与渲染同源——渲染侧显式吃
// [TextScaler.noScaling]、样式只此一份，盒宽不随系统字号变化。带宽
// （[kTrackPrefixWidth]）是横向几何常量，归 track_geometry.dart。

/// 轨道片头底色（比轨道带黑 60% 深一档）。
const Color kTrackPrefixBackgroundColor = Color(0xB3000000);

/// 轨道片头右缘分界色（浅分隔线，把标签列与时间轴内容分开）。
const Color kTrackPrefixDividerColor = Color(0x33FFFFFF);

/// 轨道片头分界线宽。
const double kTrackPrefixDividerWidth = 1;

/// 轨道片头文字色。
const Color kTrackPrefixLabelColor = Color(0xCCFFFFFF);

/// 轨道片头文字字号。
const double kTrackPrefixFontSize = 10;

/// 轨道片头文字样式（**装饰档（固定排版，不承载语义）**：量测与渲染同源——
/// `inherit` 关断、两侧同不吃缩放、恒不随系统字号变化）。
const TextStyle kTrackPrefixLabelTextStyle = TextStyle(
  inherit: false,
  fontSize: kTrackPrefixFontSize,
  height: 1,
  color: kTrackPrefixLabelColor,
);

/// 预览条（播放头）颜色。
const Color kPreviewLineColor = Colors.white;

/// 预览条像素宽（居中于时间位置）：绘制宽度与命中列半宽同源——命中解析
/// （track_hit_resolution.dart）与绘制（轨道带）读同一个值。
const double kPreviewLineWidth = 2;

/// 分段线默认细线色（半透明白，浅于预览条纯白的低强调分界提示；
/// 值 = `Colors.white.withValues(alpha: 0.55)`，const 化取整为 0x8C）。
const Color kSegmentLineColor = Color(0x8CFFFFFF);

/// 分段线 flag 粗线色（琥珀，状态指示需醒目；与选中分色）。
const Color kSegmentLineFlaggedColor = Colors.amber;

/// 分段线选中态色（选中=激活青——与 flag 琥珀可区分；
/// 取值同 [kCyanAccentColor] 集中 token）。
const Color kSegmentLineSelectedColor = kCyanAccentColor;

/// 插入半拍线色（冷灰蓝——与节拍轨白色刻度、与主青清晰区分；
/// 与节拍动画半拍细分同族的冷灰蓝视觉）。
const Color kHalfBeatLineColor = Color(0xFF8FA8C8);

/// 插入半拍线粗（同拍 1 粗）。
const double kHalfBeatLineThickness = 1;

/// 插入半拍线长（比拍 1 略长、垂直居中。拍 1 刻度绘于节拍轨
/// 行内，本值取略大于节拍轨行的居中短线，真机看版可调）。
const double kHalfBeatLineHeight = 16;

/// flag 且选中的分段线外发光色（青色外发光叠于琥珀粗线；组合态）。
const Color kSegmentLineSelectedGlowColor = kCyanAccentColor;

/// flag 且选中的分段线外发光模糊半径（初值，真机看版可调）。
const double kSegmentLineSelectedGlowBlurRadius = 8;

/// flag 且选中的分段线外发光扩散半径（初值，真机看版可调）。
const double kSegmentLineSelectedGlowSpreadRadius = 2;

/// 视频首线色。
const Color kVideoRangeStartLineColor = Colors.tealAccent;

/// 视频尾线色。
const Color kVideoRangeEndLineColor = Colors.deepOrangeAccent;

/// 图标/选中态琥珀高亮（顶栏工具激活、重点星标、倍速选中、scrub armed
/// 等共用）。
const Color kHighlightAmber = Colors.amber;

/// 学习段格框圆角（剪映式独立格框；初值，真机看版可调）。
const double kSegmentBoxBorderRadius = 6;

/// 学习段格框间缝宽（相邻格框各让 [kSegmentBoxGap] / 2；初值，可调）。
const double kSegmentBoxGap = 4;

/// 学习段格框描边色（半透明白，未练灰相邻段也界限分明）。
/// 值 = `Colors.white.withValues(alpha: 0.5)`，const 化取整为 0x80。
const Color kSegmentBoxStrokeColor = Color(0x80FFFFFF);

/// 学习段格框描边宽（1px 半透明白描边）。
const double kSegmentBoxStrokeWidth = 1;

/// 选中段加粗边框宽。
const double kSegmentSelectedBorderWidth = 3;

/// 段内倍频快标记色：红 = 变快（×2）。
/// 语义固定不按档位分色——颜色只回答快慢、精确档位由段首小字表达。
const Color kSegmentDensityFasterColor = Colors.redAccent;

/// 段内倍频慢标记色：蓝 = 变慢（×½）。
const Color kSegmentDensitySlowerColor = Colors.blueAccent;

/// 段内倍频标记边框宽（画在青色选中框之内，细一档与选中框可辨）。
const double kSegmentDensityBorderWidth = 2;

/// 段内倍频标记相对格框的内缩：标记画在青色选中框**之内**、
/// 不与它同宽同位，两层可分辨。
const double kSegmentDensityBorderInset = 3;

/// 段内倍频段首小字距格框的贴边内缩：贴在标记边框内侧——
/// 由边框内缩 + 边框宽派生，改线宽小字随之跟移，不散落补偿值。
const double kSegmentDensityLabelInset =
    kSegmentDensityBorderInset + kSegmentDensityBorderWidth;

/// 段内倍频段首小字为重点星让位的缩进：星 16 + 其边距 3 × 2
/// − 重叠余量——星占左上角，小字右移不与其重叠。
const double kSegmentDensityLabelStarIndent = 20;

/// 循环范围 repeat 字形边长（端标志只留字形；与
/// 备注锁定角标同尺寸档）。
const double kSegmentLoopGlyphSize = 10;

/// 循环范围 repeat 字形距该端、距底的内缩。
const double kSegmentLoopGlyphInset = 3;

/// 循环字形「放得下」判据：段盒宽 ≥ 13 × n（n = 该段承担的
/// 范围端数：单段选中 = 2，合并范围最外两段 = 1）。13 = 字形 + 内缩的
/// 派生式，不另立常量。
bool segmentLoopGlyphFits({required double boxWidth, required int ends}) =>
    boxWidth >= (kSegmentLoopGlyphSize + kSegmentLoopGlyphInset) * ends;

/// 选中段静态外发光模糊半径（初值，真机看版可调）。
const double kSegmentGlowBlurRadius = 8;

/// 选中段静态外发光不透明度（叠加于 [kCyanAccentColor]；
/// 初值，真机看版可调——发光不刺眼不闪）。
const double kSegmentGlowOpacity = 0.55;

/// 选中段静态外发光扩散半径（初值，可调）。
const double kSegmentGlowSpreadRadius = 1;

/// 询问卡片圆角半径（卡片级）。
const double kNoticeCardRadius = 20;

/// 询问卡片内边距（卡片级，四边同值）。
const double kNoticeCardPadding = 20;

/// 询问卡片标题字号（卡片级）。
const double kNoticeCardTitleSize = 19;

/// 询问卡片标题色（卡片级）。
const Color kNoticeCardTitleColor = Color(0xFFECEFF4);

/// 询问卡片底色：竖向深色渐变（卡片级）。
const LinearGradient kNoticeCardGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF1C1F27), Color(0xFF13161B)],
);

/// 询问卡片描边色（卡片级）。
const Color kNoticeCardBorderColor = Color(0xFF2F3641);

/// 询问卡片投影（卡片级）。
const BoxShadow kNoticeCardShadow = BoxShadow(
  color: Color(0xA6000000),
  blurRadius: 60,
  offset: Offset(0, 26),
);

/// 询问卡片内留边（卡片级）：气泡与屏幕上下缘、左右缘的最小间距。
const double kNoticeCardScreenInsetH = 8;
const double kNoticeCardScreenInsetV = 24;

/// 询问卡片标题与副标题、副标题与两栏之间的竖直间距（卡片级）。
const double kNoticeCardTitleGap = 10;
const double kNoticeCardSubtitleGap = 18;

/// 询问卡片副标题字号与行高（卡片级）。
const double kNoticeCardSubtitleSize = 13;
const double kNoticeCardSubtitleLineHeight = 1.7;

/// 询问卡片副标题色（卡片级）。
const Color kNoticeCardSubtitleColor = Color(0xFF9AA3B2);

/// 询问卡片栏圆角（卡片级）。
const double kNoticeCardColumnRadius = 14;

/// 询问卡片栏底色（卡片级）。
const Color kNoticeCardColumnColor = Color(0xFF1E222A);

/// 询问卡片栏描边色（卡片级）。
const Color kNoticeCardColumnBorderColor = Color(0xFF343B48);

/// 询问卡片栏内边距（卡片级：上 15 / 左右 10 / 下 14）。
const EdgeInsets kNoticeCardColumnPadding = EdgeInsets.fromLTRB(10, 15, 10, 14);

/// 询问卡片两栏间距（卡片级）。
const double kNoticeCardColumnGap = 8;

/// 询问卡片栏标题字号（卡片级）。
const double kNoticeCardColumnTitleSize = 15.5;

/// 询问卡片栏标题色（卡片级）。
const Color kNoticeCardColumnTitleColor = Color(0xFFF2F5F9);

/// 询问卡片栏内横线色（卡片级）。
const Color kNoticeCardDividerColor = Color(0xFF333A46);

/// 询问卡片栏内横线上下留白（卡片级）。
const double kNoticeCardDividerMargin = 11;

/// 询问卡片条目字号、行高与条目间距（卡片级）。
const double kNoticeCardItemSize = 13;
const double kNoticeCardItemLineHeight = 1.72;
const double kNoticeCardItemGap = 3;

/// 询问卡片条目色（卡片级）。
const Color kNoticeCardItemColor = Color(0xFFA9B3C1);

/// 询问卡片条目前「·」的固定列宽、颜色与点文间距（卡片级）。
const double kNoticeCardDotWidth = 8;
const Color kNoticeCardDotColor = Color(0xFF79838F);
const double kNoticeCardDotGap = 5;

/// 备注片段块体基色（备注不再有样式色，块体取具名常量——白色
/// 系基调上的半透底与描边；观感值，真机看版项）。
const Color kNoteFragmentColor = Color(0xFFFFFFFF);

/// 备注片段块体填充不透明度（块体基色上的半透底）。
const double kNoteBlockFillAlpha = 0.25;

/// 备注片段块体描边不透明度。
const double kNoteBlockBorderAlpha = 0.6;

/// 备注片段块体圆角半径（沿用局部镜像片段块体的圆角纪律）。
const double kNoteBlockCornerRadius = 4;

/// 备注片段块体竖向内边距（沿用局部镜像片段块体的内边距纪律）。
const double kNoteBlockVerticalPadding = 3;

/// 备注片段锁定标识边长（块内左上角小锁图标，36dp 行高内可辨）。
const double kNoteLockBadgeSize = 10;

/// 备注片段框内文本字号（观感值，真机看版项——36dp 行内块体的
/// 内嵌文字；默认缩放下多数片段不显字为既定效果，放大才显出）。
const double kNoteInlineTextFontSize = 10;

/// 备注片段框内文本的水平内边距。
const double kNoteInlineTextHorizontalPadding = 3;

/// 备注片段锁定标识与框内文本之间的占位间隙（标识优先占位——
/// 先扣掉角标的位置，再按剩余宽度判文本放不放得下）。
const double kNoteLockTextGap = 2;

/// 备注文本编辑器面：面板底色与圆角（观感值，真机看版项）。
const Color kNoteEditorPanelColor = Color(0xF0101010);
const double kNoteEditorPanelRadius = 12;

// ── 对比度下限 token──
// 文字对比度下限 4.5:1，按文字实际压着的底色（含半透明
// 合成后）算。判定写成纯函数（[relativeLuminance] / [contrastRatio]），
// token 级断言见 `test/player/visual_tokens_test.dart`。半透底衬压在播放器
// 黑底上，视频内容不可断定——可断定的底色取**底衬叠黑**的合成结果；色相
// 家族不变，承载不达标处只动承载可读性的那一层（提高底衬不透明度，或改由
// 文字自身的深色边缘承载）、不把文字调到失真。
// 算术实现在 `../core/contrast.dart`（全仓唯一
// 一份 WCAG 判定）：这里只保留 Color 形态的转出，供控制层 token 断言沿用
// 既有名字与期望值。

/// WCAG 相对亮度（sRGB 通道线性化后按权重求和；纯函数）。
double relativeLuminance(Color c) => contrast.relativeLuminance(c.toARGB32());

/// WCAG 对比度比值（较亮者在上；纯函数，对比度下限的唯一判定入口）。
double contrastRatio(Color a, Color b) =>
    contrast.contrastRatio(a.toARGB32(), b.toARGB32());

/// 控制工具条底衬（黑 55%，原值收编——槽标签不可用态的判定底）。
const Color kControlToolbarScrimColor = Color(0x8C000000);

/// 备注输入框提示文字色（提示/占位专用灰；white38 在备注面板底上仅
/// ≈3.3:1，按 4.5:1 下限提亮到 60% 白）。
const Color kNoteFieldHintColor = Color(0x99FFFFFF);

/// 轨道段说明文字色（白：可读性由 [kLearningCaptionTextStyle] 的单层深色
/// 字阴影承担，见 `track_band.dart`；熟练度五档任一底色上白字外缘读得清）。
const Color kLearningCaptionTextColor = Colors.white;

/// 倍速气泡空态文字色（「暂无历史」占位；white24 在黑 94% 气泡底上仅
/// ≈2:1，按 4.5:1 下限提亮到 54% 白）。
const Color kSpeedHistoryEmptyTextColor = Colors.white54;

/// 倍速气泡底衬（黑 94%，原值收编——气泡族文字与音画同步禁用钮前景的
/// 判定底）。
const Color kSpeedBubbleScrimColor = Color(0xF0000000);

/// 轨道设置开关底衬（黑 60%，原值收编——关闭态文字的判定底）。
const Color kSettingsToggleScrimColor = Color(0x99000000);

/// 轨道设置条关闭态文字色（30% 白在开关底衬上仅 ≈2.7:1，提亮到 60% 白；
/// 装载中的置灰态同用本 token）。
const Color kSettingsToggleOffTextColor = Color(0x99FFFFFF);

/// 音画同步档位钮禁用态前景色（未设时落回主题 onSurface 38% 近黑、在
/// 黑 94% 气泡底上不可辨；54% 白显式禁用灰）。
const Color kAvSyncTierDisabledTextColor = Colors.white54;

/// 名册改色色板（色板是集中视觉常量、24 色；ARGB，
/// 全不透明、暗色播放页可辨）。选色浮层的唯一取色来源。
const List<int> kRosterPalette = [
  0xFFE53935, // 红
  0xFF1E88E5, // 蓝
  0xFF43A047, // 绿
  0xFFFB8C00, // 橙
  0xFF8E24AA, // 紫
  0xFF00ACC1, // 青
  0xFFFDD835, // 黄
  0xFFEC407A, // 粉
  0xFFD81B60, // 玫红
  0xFFC62828, // 深红
  0xFFAD1457, // 酒红
  0xFF6A1B9A, // 深紫
  0xFF4527A0, // 靛蓝
  0xFF1565C0, // 深蓝
  0xFF0277BD, // 海蓝
  0xFF00838F, // 孔雀蓝
  0xFF2E7D32, // 深绿
  0xFF558B2F, // 橄榄绿
  0xFF9E9D24, // 芥绿
  0xFFF9A825, // 金
  0xFFEF6C00, // 深橙
  0xFF6D4C41, // 棕
  0xFF78909C, // 蓝灰
  0xFFFFFFFF, // 纯白
];

/// 色板色名：与 [kRosterPalette] 一一同序——
/// 色板格的唯一信息载体本来只有颜色、读屏听不到色块；选色浮层按此给每格
/// 报出「选代表色：X」。
const List<String> kRosterPaletteNames = [
  '红',
  '蓝',
  '绿',
  '橙',
  '紫',
  '青',
  '黄',
  '粉',
  '玫红',
  '深红',
  '酒红',
  '深紫',
  '靛蓝',
  '深蓝',
  '海蓝',
  '孔雀蓝',
  '深绿',
  '橄榄绿',
  '芥绿',
  '金',
  '深橙',
  '棕',
  '蓝灰',
  '纯白',
];

/// 备注片段端点命中带宽（**未选中**态的目标带宽：命中域让位
/// 到块外空隙、按可用空间自适应分配；与 [kLocalMirrorEdgeHitWidth] 同值
/// 的同款纪律）。
const double kNoteEdgeHitWidth = kLocalMirrorEdgeHitWidth;

/// 备注片段选中态端点柄命中带宽（选中后两端给端点柄、命中域比
/// 未选中的 [kNoteEdgeHitWidth] 更长；真机看版项——默认缩放下 16.7dp 的
/// 块上柄好不好抓以此为准）。
const double kNoteSelectedEdgeHitWidth = 24;

/// 端点柄可见条宽（真机看版项）。
const double kNoteHandleWidth = 3;

/// 端点柄可见条距块缘的竖向留白（真机看版项）。
const double kNoteHandleEdgeInset = 3;

/// 备注轨行级点按最小命中宽（与 [kLocalMirrorTapHitWidth] 同值的
/// 同款纪律——窄片段命中域对称扩展至不小于该宽）。
const double kNoteTapHitWidth = 40;

/// 备注片段定位高亮色（贴纸左下角跳转后打在对应片段上的描边色；
/// 观感值，真机看版项）。
const Color kNoteFragmentHighlightColor = Color(0xFFFFC107);

/// 备注片段定位高亮描边宽。
const double kNoteFragmentHighlightWidth = 2;

/// 备注片段选中描边色（与局部镜像片段选中描边同款白色纪律；
/// 观感值，真机看版项）。
const Color kNoteFragmentSelectedColor = Color(0xFFFFFFFF);

/// 备注片段选中描边宽（与局部镜像片段选中描边同值）。
const double kNoteFragmentSelectedBorderWidth = 1.5;

/// 展开内容浮条（观感值，真机看版项）：浮条与屏幕左右缘的最小
/// 间距、浮条与片段的纵向间隙、内边距、「编辑」入口与文本的间距、
/// 「编辑」入口宽、小尾巴尺寸与字号。
const double kNoteBubbleEdgeMargin = 8;
const double kNoteBubbleGap = 6;
const double kNoteBubbleHorizontalPadding = 10;
const double kNoteBubbleVerticalPadding = 6;
const double kNoteBubbleEditGap = 8;
const double kNoteBubbleEditButtonWidth = 48;
const double kNoteBubbleTailWidth = 10;
const double kNoteBubbleTailHeight = 5;

/// 小尾巴水平钳进浮条时距浮条左右缘的余量（观感值）。
const double kNoteBubbleTailEdgeInset = 4;

/// 展开浮条字号（观感值，真机看版项）。
const double kNoteBubbleFontSize = 14;

/// 展开浮条正文样式（观感值）：量测（`measureTextExtent`）与渲染（Text）
/// 共用同一实例——测的与画的同源，不设第二份取值。
///
/// [TextStyle.inherit] 恒 false，切断环境 [DefaultTextStyle]：`Text` 会与
/// 调用处默认样式（Material `bodyMedium` 带字距与行高）合并，而
/// `measureTextExtent` 量测不合并。两侧不同源时渲染宽于预留正文盒（末字被省略号吃掉），行高又会
/// 把正文顶出盒外（下缘被裁），浮条实际高度也与定位算得的高度不符。
const TextStyle kNoteBubbleTextStyle = TextStyle(
  inherit: false,
  color: Colors.white,
  fontSize: kNoteBubbleFontSize,
);

/// 展开浮条动作入口样式（观感值）：与 [kNoteBubbleTextStyle] 同口径
/// 切断环境样式——入口宽度按实测取（不小于 [kNoteBubbleEditButtonWidth]），
/// 行高与正文同源，浮条高度才与定位算得的高度一致。
const TextStyle kNoteBubbleEditTextStyle = TextStyle(
  inherit: false,
  color: kNoteFragmentHighlightColor,
  fontSize: kNoteBubbleFontSize,
  fontWeight: FontWeight.w600,
);
