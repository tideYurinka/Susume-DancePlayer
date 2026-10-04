import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 文字的实际绘制色（[Text] 自身样式与继承的 `DefaultTextStyle` 合并后的
/// 解析色）——量的是真正画出来的颜色，不是 `Theme` 里声明的值。
Color? paintedTextColor(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder).text.style?.color;

/// 断言该文字在近黑气泡底上可读：绘制色必须是亮色。
///
/// 气泡壳底色为 `black94`；文字若继承到外层亮色主题的正文色（近黑）会读成
/// 「置灰」，故以亮度阈值钉住这一可观察结果。
void expectLightText(WidgetTester tester, Finder finder) =>
    expectLightColor(paintedTextColor(tester, finder));

/// 断言该颜色在黑底气泡上可读（同 [expectLightText] 的判据，供直接取色的
/// 场合复用）。
void expectLightColor(Color? color) {
  expect(color, isNotNull, reason: '必须解析出绘制色');
  expect(
    color!.computeLuminance(),
    greaterThan(0.5),
    reason:
        '气泡底为近黑（black94），文字取到暗色才会可读；'
        '取到外层亮色主题的正文色即呈置灰',
  );
}
