import 'package:flutter/material.dart';

/// 三个计划编辑页（舞 DDL / 随舞事件 / 团内检查）共用的全屏表单壳：顶栏
/// 「取消 / 保存」，编辑既有事件时另带「删除」。删除走二次确认弹窗
/// 取消 = 不动，确认后才调 [onDelete]。
class PlanEditorScaffold extends StatelessWidget {
  const PlanEditorScaffold({
    super.key,
    required this.pageKey,
    required this.title,
    required this.saveKey,
    required this.onSave,
    required this.children,
    this.deleteKey,
    this.onDelete,
  });

  final Key pageKey;
  final String title;
  final Key saveKey;
  final VoidCallback onSave;
  final List<Widget> children;
  final Key? deleteKey;
  final VoidCallback? onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final base = (deleteKey as ValueKey<String>).value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: Key('${base}_dialog'),
        content: const Text('删除这条计划事件？删除后不可恢复'),
        actions: [
          TextButton(
            key: Key('${base}_cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: Key('${base}_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: pageKey,
      appBar: AppBar(
        leadingWidth: 72,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        title: Text(title),
        actions: [
          if (onDelete != null)
            TextButton(
              key: deleteKey,
              onPressed: () => _confirmDelete(context),
              child: const Text('删除'),
            ),
          TextButton(key: saveKey, onPressed: onSave, child: const Text('保存')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('plan_editor_scroll'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: children,
        ),
      ),
    );
  }
}
