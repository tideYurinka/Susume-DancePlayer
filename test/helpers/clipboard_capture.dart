import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 装上剪贴板替身：返回收集到的 `Clipboard.setData` 调用，用例结束自动卸下。
/// 「按外部链接处理 = 复制到剪贴板 + 提示」这类断言都读它。
List<MethodCall> mockClipboard(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}
