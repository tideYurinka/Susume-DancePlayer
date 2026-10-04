/// 「装载未完成」门与「正在装载」提示声明。
///
/// 会写盘的入口被同一道门挡住：置灰、可点、点击报「正在装载」短暂提示身份
/// （判定表见 `tool_slots.dart`，门事实由本模块的
/// [loadGateActiveProvider] 持有）。提示纯视觉：与锁定分段提示同构的居中
/// 轻提示——不拦截触摸、不与手势争 arena，不产生任何模型变更；被挡下的
/// 操作本身不执行。
///
/// **开合归打开恢复持有**（`open_restore.dart`）：建立序列之前置位、打开
/// 恢复（标注对象集放上时间线那一段）落定即落位；无实体文件不置位。页面与
/// 其余模块只读门事实，不开关它。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'tool_slots.dart' show PageWriteEntryId, PageWriteEntryTable;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 「装载未完成」门：打开恢复落定之前为 true——对象集
/// 本身来自尚未装载的文档，此刻所有会写盘的入口读同一状态、被同一道门挡住
/// （置灰、可点、弹「正在装载」）；打开恢复落定后置 false，入口自动恢复可用
/// （无需重开页面）。会话级内存态，
/// 默认 false（未在打开路径上的场景不受门影响）。
class LoadGateModel extends Notifier<bool> {
  @override
  bool build() => false;

  /// 置位（打开恢复在建立序列之前调）。
  void begin() => state = true;

  /// 落位（打开恢复落定即调，含异常与无身份收场）。
  void settle() => state = false;
}

/// 「装载未完成」门注入点。
final loadGateActiveProvider = NotifierProvider<LoadGateModel, bool>(
  LoadGateModel.new,
);

/// 门原因文案（唯一一份：提示浮层与测试共读）。
const String kLoadGateReasonText = '正在装载';

/// 页面级会写盘入口此刻是否被「装载未完成」门挡下。
///
/// 入口的身份唯一来源是 [PageWriteEntryTable]（每个入口都写盘、都吃这道
/// 门）；点按类入口（`silent == false`）顺手弹「正在装载」，手势类入口
/// （`silent == true`）静默不参与、不弹提示。返回 true = 已被挡下、调用方
/// 必须直接返回且不做任何写盘。所有页面级写盘入口共用这一处，不各写一个
/// `if`。
bool loadGateBlocksWrite(WidgetRef ref, PageWriteEntryId id) {
  if (!ref.read(loadGateActiveProvider)) return false;
  if (!PageWriteEntryTable.main.entryOf(id).silent) {
    ref.read(noticeTriggerProvider(NoticeId.loadGate).notifier).show();
  }
  return true;
}

/// 「正在装载」提示内容（文案取既有原因文案常量，唯一一份）。
Widget loadGateNoticeContent(BuildContext _) =>
    const Text(kLoadGateReasonText, style: kNoticeTextStyle);

/// 「正在装载」提示声明清单项（组合根装配）。
const loadGateNoticeSpec = NoticeSpec(
  id: NoticeId.loadGate,
  content: loadGateNoticeContent,
  noticeKey: Key('load_gate_prompt'),
);
