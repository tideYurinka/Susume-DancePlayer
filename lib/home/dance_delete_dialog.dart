import 'package:flutter/material.dart';

/// 删除一支舞的二次确认：详情页与找回面共用一处文案与「默认不删」。
/// 确认返回 true；取消或点外面关掉返回 false。
///
/// 删除动作本体只有一条路径（[deleteDanceFrom]：索引先写、文件
/// best-effort、素材连带、练舞统计保留），两个入口共用同一份确认。
Future<bool> confirmDanceDeletion(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('dance_delete_dialog'),
      content: const Text('将连视频副本、公开标记文件、本地私密文件、组员方案与该舞练习素材一并删除；练舞统计保留'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('dance_delete_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
