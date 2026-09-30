import 'package:flutter/material.dart';

/// 帮助域一句话提示的唯一出口（`SnackBar`）：链接复制的三档与图片保存的三档
/// 共走这里，保证「已复制」与「已保存到相册」这类反馈是同一个口径。
void showHelpSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
