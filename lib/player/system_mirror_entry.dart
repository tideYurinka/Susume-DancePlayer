/// **系统镜像**入口的唯一动作：**先断开投屏（含立即停服）再跳**系统自带的
/// 「投屏 / 无线显示」设置；降级链（系统投屏设置 → 显示设置）都走不通时给
/// 一句**短暂提示**。
///
/// ## 两处入口、一个动作
///
/// 投屏态顶栏那枚（`play_tool_table.dart` 的 `kPlayToolSystemMirror`，装配在
/// `play_tool_row.dart`）与投屏准备面板"搜不到接收端"空态里那同一枚都调本
/// 函数——顺序（先断后跳）、降级链与那句提示因此只有一份实现，不会在两处
/// 摆法之间分家。
///
/// ## 为什么先断开
///
/// 投屏与整屏镜像同时在场，电视上会一边放我们的副本、一边被系统镜像顶掉，
/// 两份画面打架（ADR-0004）。断开本身不抛（会话契约），所以"先断后跳"这条
/// 顺序不因为一次收尾失败被跳过：断开在跳之前**等完**。
///
/// ## 边界
///
/// 本文件不认识模式值，也不建控件：模式值仍归其既有单一 owner（断开经
/// `cast_run.dart` 的 `disconnect`，它自己翻模式值）；这里只是"断开 → 跳 →
/// 跳不动就说一句"这条顺序的收口处。
library;

import 'package:flutter/material.dart' show BuildContext, Key, Text, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/system_mirror.dart';
import 'cast_run.dart' show castRunProvider;
import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 「系统设置跳不动」提示内容：降级链两级都没接住时那一句——按了没反应最
/// 难懂，这里是唯一的失败面。
Widget _systemMirrorUnavailableNoticeContent(BuildContext _) =>
    const Text('这台设备打不开系统投屏设置', style: kNoticeTextStyle);

const systemMirrorUnavailableNoticeSpec = NoticeSpec(
  id: NoticeId.systemMirrorUnavailable,
  content: _systemMirrorUnavailableNoticeContent,
  noticeKey: Key('cast_system_mirror_prompt'),
);

/// 系统镜像入口的唯一动作（两处入口共用）。
///
/// 依赖都在 await 之前取好：断开之后投屏态就结束了，控件可能随这次重建被
/// 换掉——不在 await 之后再碰 `ref`。
Future<void> openSystemMirrorEntry(WidgetRef ref) async {
  final launcher = ref.read(systemMirrorLauncherProvider);
  final notice = ref.read(
    noticeTriggerProvider(NoticeId.systemMirrorUnavailable).notifier,
  );
  // 先断开（含停服）再跳：顺序即这条链的契约，且要等它收完。
  await ref.read(castRunProvider.notifier).disconnect();
  if (await launcher.open()) return;
  notice.show();
}
