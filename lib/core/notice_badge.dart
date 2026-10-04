import 'package:flutter/material.dart';

import 'notice_tokens.dart';

/// 黑底胶囊视觉底座（全站点 black87 pill 的单一渲染位）。
///
/// 词汇说明：本组件是视觉底座，不等同 `lib/player/CONTEXT.md`「短暂提示」词条
/// （纯提示、无按钮）——除短暂提示族外，也按同款视觉承载少量交互
/// 内容（如循环提示的「不循环」按钮），显隐与交互由调用侧负责。
///
/// 结构即收敛前的手写 pill：[Material]（[kNoticeBackground] 底、
/// [kNoticeElevation] 浮起、[kNoticeRadius] 圆角）→ [Padding]
/// （水平 [kNoticePaddingH] / 垂直 [kNoticePaddingV]）→ 内容槽
/// [child]。child 由调用侧构建——纯文本、图标+文本 Row、含按钮的
/// Row（如循环提示的「不循环」）均可；显隐逻辑不在本组件内，由
/// 各自的浮层/控制器负责。
///
/// [key] 落在 Material 上（即本组件自身），供测试定位各徽章。
/// 全部视觉取值来自 [notice_tokens.dart] 的 notice token 组——
/// 一处改样式全局生效。
///
/// [padding] 是**卡体尺寸口子**：为空即走
/// 全站默认档（水平 [kNoticePaddingH] / 垂直 [kNoticePaddingV]）；左下角两张
/// 提示卡传紧凑档 [kCornerPromptCardPadding]，其余调用方不传。
///
/// [Material]（默认 canvas 型、非 transparency）按框架语义**吃掉自身矩形内的
/// 点按**：卡上动作（如循环提示的「不循环」）与卡内空白落点都归卡，不穿透到
/// 下层手势面——承载交互内容的卡（编辑态浮在控制层空白手势面之上）靠这一条
/// 才点得动，换成 transparency 型即失效。
class NoticeBadge extends StatelessWidget {
  const NoticeBadge({super.key, required this.child, this.padding});

  /// 胶囊内容（padding 内的 child）。
  final Widget child;

  /// 内边距覆盖口；null = 全站默认档（[kNoticePaddingH] × [kNoticePaddingV]）。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kNoticeBackground,
      elevation: kNoticeElevation,
      borderRadius: BorderRadius.circular(kNoticeRadius),
      child: Padding(
        padding:
            padding ??
            const EdgeInsets.symmetric(
              horizontal: kNoticePaddingH,
              vertical: kNoticePaddingV,
            ),
        child: child,
      ),
    );
  }
}
