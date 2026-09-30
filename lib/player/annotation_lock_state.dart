part of 'annotation_editor.dart';

/// 锁定分段状态归标注编辑模块库：锁开关与「已锁定分段」
/// 提示触发由模块库自持有；hub re-export 只读面，widget import 与 watch
/// 布线零改动。开关切换与提示展示仍由 UI 经公开面驱动；逐 verb 门禁
/// 策略已在 [AnnotationEditor] 交互写入口执行。

/// 锁定分段模型（会话级内存态，默认关）。
/// 开启后阻止逐 verb 门禁表内的编辑（受锁/豁免矩阵见
/// [AnnotationEditor.verbGateReasons] 与库头「锁门禁」契约）；选中、
/// 熟练度/重点与撤销/重做等豁免路径不受锁影响（flag 切换受锁）。
class LayoutLockedModel extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  /// 打开恢复写回。
  void replace(bool value) => state = value;
}

/// 锁定分段开关注入点：轨道设置条内的开关。
final layoutLockedProvider = NotifierProvider<LayoutLockedModel, bool>(
  LayoutLockedModel.new,
);

/// 锁定分段阻止提示：被阻止操作触发时经提示模块的触发面只报
/// 身份（`noticeTriggerProvider(NoticeId.layoutLock)`）
/// ——内容声明装配在 `player_page.dart` 的 `kNoticeSpecs`，挂载在演出层唯一
/// 宿主；被阻止操作本身不执行。备注内容锁的提示同款走触发面（声明同处装配）。
