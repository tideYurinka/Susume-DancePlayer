/// 自动首尾节拍未就绪提示声明与浮层 ✕ 关闭提示浮层。
///
/// 节拍轨未就绪（占位 = 分析中 / 异常 = 失败）时「自动首尾」置灰常驻；
/// 单击按状态区分短暂提示——占位态报「节拍分析中…」身份、异常态报
/// 「无节拍数据」身份。提示纯视觉：与锁定分段提示同构的 [IgnorePointer]
/// 居中胶囊浮层——不拦截触摸、不与手势争 arena，不产生任何模型变更。
library;

import 'package:flutter/material.dart';

import 'notice.dart' show NoticeId, NoticeSpec;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 「节拍分析中…」提示内容。
Widget beatAnalyzingNoticeContent(BuildContext _) =>
    const Text('节拍分析中…', style: kNoticeTextStyle);

/// 「节拍分析中…」提示声明清单项（组合根装配）。
const beatAnalyzingNoticeSpec = NoticeSpec(
  id: NoticeId.beatAnalyzing,
  content: beatAnalyzingNoticeContent,
  noticeKey: Key('beat_analyzing_prompt'),
);

/// 「无节拍数据」提示内容。
Widget beatNoDataNoticeContent(BuildContext _) =>
    const Text('无节拍数据', style: kNoticeTextStyle);

/// 「无节拍数据」提示声明清单项（组合根装配）。
const beatNoDataNoticeSpec = NoticeSpec(
  id: NoticeId.beatNoData,
  content: beatNoDataNoticeContent,
  noticeKey: Key('beat_no_data_prompt'),
);

/// 浮层 ✕ 关闭提示声明：一行声明 = 身份 + 内容 +
/// 定位 key。触发面由提示模块持有（浮层关闭路径经 `noticeTriggerProvider(
/// NoticeId.beatOverlayClose)` 只报身份）；挂载由演出层的唯一宿主承担。
Widget beatOverlayCloseNoticeContent(BuildContext _) => const Text(
      '节拍提示已关闭 · 编辑态顶栏可重新打开',
      style: kNoticeTextStyle,
    );

/// 浮层 ✕ 关闭提示声明清单项（组合根装配）。
const beatOverlayCloseNoticeSpec = NoticeSpec(
  id: NoticeId.beatOverlayClose,
  content: beatOverlayCloseNoticeContent,
  noticeKey: Key('beat_overlay_close_prompt'),
);
