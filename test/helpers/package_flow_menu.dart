import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 从首页 ⋯ 菜单进入「恢复备份」：菜单 → 选包（替身
/// 直接返回），备份包与方案包由包形态识别各自分流。
Future<void> openRestoreBackupFromHomeMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home_more_menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('restore_backup_menu_item')));
  await tester.pumpAndSettle();
}
