import 'package:dance_learning_app/core/text_extent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(fontSize: 14);

  testWidgets('量出正宽高；maxLines 封顶行数', (tester) async {
    final oneLine = measureTextExtent('abc', style);
    expect(oneLine.width, greaterThan(0));
    expect(oneLine.height, greaterThan(0));

    final twoLines = measureTextExtent('abc\ndef', style);
    expect(twoLines.height, greaterThan(oneLine.height));

    final capped = measureTextExtent('abc\ndef', style, maxLines: 1);
    expect(capped.height, closeTo(oneLine.height, 0.001));
  });

  testWidgets('maxWidth 触发软换行、把文本折高', (tester) async {
    const text = 'aaaa bbbb cccc dddd';
    final unbounded = measureTextExtent(text, style);
    final narrow = measureTextExtent(text, style, maxWidth: 40);
    expect(narrow.height, greaterThan(unbounded.height));
  });

  testWidgets('scaler 放大尺寸；direction 参与排版', (tester) async {
    final base = measureTextExtent('abc', style);
    final scaled = measureTextExtent(
      'abc',
      style,
      scaler: const TextScaler.linear(2),
    );
    expect(scaled.width, greaterThan(base.width));
    expect(scaled.height, greaterThan(base.height));

    final rtl = measureTextExtent('abc', style, direction: TextDirection.rtl);
    expect(rtl.width, base.width);
  });
}
