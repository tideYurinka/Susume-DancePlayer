import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 把可能滚出视口甚至出懒建缓存的控件滚回视野（可达 = 滚动可及）：
/// 先按向下、再按向上滚入，最后 ensureVisible 贴边。调用方随后自行点按。
Future<void> ensureScrollVisible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    try {
      await tester.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    } on StateError {
      await tester.scrollUntilVisible(
        target,
        -300,
        scrollable: find.byType(Scrollable).first,
      );
    }
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
