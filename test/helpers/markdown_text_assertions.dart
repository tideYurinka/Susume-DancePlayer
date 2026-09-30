import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Markdown 渲染断言的共用件（文档页与关于页的 widget 测试）：从渲染树上取
/// 纯文本与富文本区间，用来断言「屏幕上看到了什么」，不碰渲染件内部结构。
///
/// 当前树里全部 `Text` 的纯文本。
List<String> plainTexts(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(find.byType(Text)))
    text.data ?? text.textSpan?.toPlainText() ?? '',
];

/// 当前树里全部富文本区间（含嵌套）。
Iterable<TextSpan> textSpans(WidgetTester tester) sync* {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final span = text.textSpan;
    if (span is TextSpan) {
      yield* _descendants(span);
    } else if (text.data != null) {
      yield TextSpan(text: text.data);
    }
  }
}

Iterable<TextSpan> _descendants(TextSpan span) sync* {
  yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is TextSpan) yield* _descendants(child);
  }
}
