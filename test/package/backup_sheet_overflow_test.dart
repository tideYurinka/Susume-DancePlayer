import 'package:dance_learning_app/package/backup_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 备份面：内容超高（大字号矮视口）时不溢出，
/// 「取消 / 开始备份」始终完整落在屏内。
void main() {
  testWidgets('大字号 + 矮视口：备份对话框不溢出，操作按钮完整落在屏内', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(361, 480); // 合成档 361×480dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Center(child: BackupSheet())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('backup_sheet')), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '大字号矮视口下无溢出');

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    for (final (label, key) in [
      ('「取消」', 'backup_sheet_cancel'),
      ('「开始备份」', 'backup_sheet_send'),
    ]) {
      final rect = tester.getRect(find.byKey(Key(key)));
      expect(rect.top, greaterThanOrEqualTo(0), reason: '$label不越上缘');
      expect(rect.bottom, lessThanOrEqualTo(screenHeight), reason: '$label不越下缘');
    }
  });
}
