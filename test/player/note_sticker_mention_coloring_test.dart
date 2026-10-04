import 'package:dance_learning_app/annotation/dancer_roster.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart'
    show dancerRosterControllerProvider;
import 'package:dance_learning_app/player/note_sticker_layout.dart';
import 'package:dance_learning_app/player/note_sticker_overlay.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationRestoreDocument, annotationEditorProvider;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 「点名语法与贴纸着色」widget 缝直测：渲染时按
/// **当前名册**解析 `@` 语法——语法字符（`@` 与紧随的分隔空格）被隐藏、
/// 名字段用名册代表色、其余段用备注样式色；贴纸盒尺寸 = 按**可见分段**
/// 量测的尺寸。
void main() {
  const contentRect = Rect.fromLTWH(0, 0, 800, 600);

  /// 填充层（非描边层）Text 的 span 颜色序列。
  List<Color> fillSpanColors(WidgetTester tester) {
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.foreground?.style != PaintingStyle.stroke)
        .toList();
    final span = texts.single.textSpan as TextSpan;
    final children = [
      for (final child in span.children ?? const <InlineSpan>[])
        if (child is TextSpan && child.style?.color != null)
          child.style!.color!,
    ];
    return children.isNotEmpty
        ? children
        : [if (span.style?.color != null) span.style!.color!];
  }

  /// 全部文本层（描边层 + 填充层）的可见明文。
  Set<String> renderedPlainTexts(WidgetTester tester) => tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .map((p) => p.text.toPlainText())
      .toSet();

  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required String text,
  }) async {
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            notes: [NoteSticker(startMs: 1000, endMs: 5000, text: text)],
          ),
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              NoteStickerOverlay(
                positionMs: 3000,
                contentRect: contentRect,
                faceDirection: FaceDirection.original,
              ),
            ],
          ),
        ),
      ),
    );
    return container;
  }

  /// 把名册置成 [roster]：走**名册直写控制器**（增 / 删 / 改色三条真实写
  /// 路径），渲染侧只读面是它的活投影——着色取数因此与真机同一条链路。
  Future<void> setRoster(
    ProviderContainer container,
    List<DancerRosterEntry> roster,
  ) async {
    final controller = container.read(dancerRosterControllerProvider);
    for (final name in controller.roster.map((entry) => entry.name).toList()) {
      if (!roster.any((entry) => entry.name == name)) {
        await controller.removeDancer(name);
      }
    }
    for (final entry in roster) {
      await controller.addDancer(entry.name, color: entry.color);
    }
  }

  testWidgets('点名段用名册代表色、@ 与紧随空格被隐藏', (tester) async {
    final container = await pumpHost(tester, text: '@果 走位偏左');
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF123456),
    ]);
    await tester.pump();

    // 可见文本：看不到 @、也看不到那个空格（描边层与填充层一致）。
    expect(renderedPlainTexts(tester), {'果走位偏左'});
    // 「果」用果的代表色，「走位偏左」用备注样式色（默认白）。
    expect(fillSpanColors(tester), const [
      Color(0xFF123456),
      Color(0xFFFFFFFF),
    ]);
  });

  testWidgets('不构成点名的 @ 原样显示、不着色、不报错', (tester) async {
    final container = await pumpHost(tester, text: '@小明 上场');
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF123456),
    ]);
    await tester.pump();

    expect(renderedPlainTexts(tester), {'@小明 上场'});
    expect(fillSpanColors(tester), everyElement(const Color(0xFFFFFFFF)));
  });

  testWidgets('孤立 @ 原样显示（@ 后不是名册名）', (tester) async {
    final container = await pumpHost(tester, text: '邮箱 a@b.com');
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF123456),
    ]);
    await tester.pump();

    expect(renderedPlainTexts(tester), {'邮箱 a@b.com'});
    expect(fillSpanColors(tester), everyElement(const Color(0xFFFFFFFF)));
  });

  testWidgets('多个点名连排渲染为「果鸟海」（分隔空格被隐藏）', (tester) async {
    final container = await pumpHost(tester, text: '@果 @鸟 @海 ');
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF000001),
      DancerRosterEntry(name: '鸟', color: 0xFF000002),
      DancerRosterEntry(name: '海', color: 0xFF000003),
    ]);
    await tester.pump();

    expect(renderedPlainTexts(tester), {'果鸟海'});
    expect(fillSpanColors(tester), const [
      Color(0xFF000001),
      Color(0xFF000002),
      Color(0xFF000003),
    ]);
  });

  testWidgets('名册增 / 删 / 改色后同一条备注的着色实时跟着变', (tester) async {
    final container = await pumpHost(tester, text: '@果 走位偏左');
    // 初始名册为空：@果 不构成点名 → 原样显示、全白。
    expect(renderedPlainTexts(tester), {'@果 走位偏左'});
    expect(fillSpanColors(tester), everyElement(const Color(0xFFFFFFFF)));

    // 增：新名立刻点亮（文本里的 @ + 空格即刻被隐藏）。
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF0000AA),
    ]);
    await tester.pump();
    expect(renderedPlainTexts(tester), {'果走位偏左'});
    expect(fillSpanColors(tester).first, const Color(0xFF0000AA));

    // 改色：立刻换色。
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF0000BB),
    ]);
    await tester.pump();
    expect(fillSpanColors(tester).first, const Color(0xFF0000BB));

    // 删：立刻失色、@ 与空格回来（原样显示）。
    await setRoster(container, const []);
    await tester.pump();
    expect(renderedPlainTexts(tester), {'@果 走位偏左'});
    expect(fillSpanColors(tester), everyElement(const Color(0xFFFFFFFF)));
  });

  testWidgets('盒尺寸 = 按可见分段的量测尺寸（语法字符不参与排版）', (tester) async {
    // 语义档：真值按两侧同一个系统字号缩放值（1.3×）量测——
    // 量测侧若退回 noScaling，渲染盒与真值不再相等。
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await pumpHost(tester, text: '@果 走位偏左');
    await setRoster(container, const [
      DancerRosterEntry(name: '果', color: 0xFF123456),
    ]);
    await tester.pump();

    final rendered = tester.getRect(find.byType(NoteStickerText));
    final fontSize = kNoteStickerBaseFontSize * noteDefaultScale;
    // 独立真值：可见文本「果走位偏左」的同样式、同一缩放值的排版。
    final visibleTp = TextPainter(
      text: TextSpan(text: '果走位偏左', style: noteStickerTextStyle(fontSize)),
      textScaler: const TextScaler.linear(1.3),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    // 含语法字符的原文排版更宽——盒尺寸必须贴可见分段，而非原文。
    final rawTp = TextPainter(
      text: TextSpan(text: '@果 走位偏左', style: noteStickerTextStyle(fontSize)),
      textScaler: const TextScaler.linear(1.3),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    expect(rendered.width, moreOrLessEquals(visibleTp.size.width));
    expect(rendered.height, moreOrLessEquals(visibleTp.size.height));
    expect(rendered.width, lessThan(rawTp.size.width));
    visibleTp.dispose();
    rawTp.dispose();
  });
}
