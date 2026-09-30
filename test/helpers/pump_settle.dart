import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 占位态节拍轨不定态进度条是循环动画：`pumpAndSettle` 对其
/// 永不收敛。此助手在 600ms 内未停稳即视为已稳定（循环动画在场），已停
/// 稳路径与 `pumpAndSettle` 行为一致。
Future<void> pumpSettle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(milliseconds: 600),
    );
  } on FlutterError {
    // 循环动画永不收敛（超时断言）：到时即视为已稳定。
  }
}
