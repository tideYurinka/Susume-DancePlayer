import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    show MarkersDocument;
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart'
    show dancerRosterControllerProvider;
import 'package:dance_learning_app/player/note_sticker_layout.dart';
import 'package:dance_learning_app/player/note_sticker_overlay.dart';
import 'package:dance_learning_app/player/note_sticker_overlay_registration.dart'
    show NoteStickerOverlayRegistration;
import 'package:dance_learning_app/player/annotation_edit.dart'
    show InsertNote, SetNoteText;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 独立真源：给定可见文本按渲染字号（基准 × 默认系数）的单行量测尺寸。
Size measureStickerText(String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: noteStickerTextStyle(kNoteStickerBaseFontSize * noteDefaultScale),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

void main() {
  const contentRect = Rect.fromLTWH(0, 0, 800, 600);

  /// 注入 [notes]（缺省窗内一条默认备注）并泵入宿主 Stack；返回容器供
  /// 播放状态操作等后续断言使用。
  Future<ProviderContainer> pumpHost(
    WidgetTester tester, {
    required int positionMs,
    FaceDirection faceDirection = FaceDirection.original,
    List<NoteSticker> notes = const [
      NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手'),
    ],
  }) async {
    final engine = FakePlaybackEngine();
    final container = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
    container
        .read(annotationEditorProvider)
        .restoreDocument(AnnotationRestoreDocument(notes: notes));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              NoteStickerOverlay(
                positionMs: positionMs,
                contentRect: contentRect,
                faceDirection: faceDirection,
              ),
            ],
          ),
        ),
      ),
    );
    return container;
  }

  group('贴纸窗内显隐（播放头 ∈ 时间窗即显示，与播放/暂停无关）', () {
    testWidgets('窗内 → 显示备注文本；窗外 → 消失', (tester) async {
      await pumpHost(tester, positionMs: 3000);
      expect(find.byType(NoteStickerText), findsOneWidget);

      // 窗外（终点半开不含）。
      await pumpHost(tester, positionMs: 5000);
      expect(find.byType(NoteStickerText), findsNothing);

      // 窗外（起点之前）。
      await pumpHost(tester, positionMs: 999);
      expect(find.byType(NoteStickerText), findsNothing);

      // 回到窗内（含起点）。
      await pumpHost(tester, positionMs: 1000);
      expect(find.byType(NoteStickerText), findsOneWidget);
    });

    testWidgets('跨越窗边界不残留：端点处切换后连多帧仍干净', (tester) async {
      // 起点前 → 起点（含）：出现且稳定。
      await pumpHost(tester, positionMs: 999);
      expect(find.byType(NoteStickerText), findsNothing);
      await pumpHost(tester, positionMs: 1000);
      expect(find.byType(NoteStickerText), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(NoteStickerText), findsOneWidget);

      // 终点（不含）：消失且连多帧不残留（不闪烁 = 不再复现）。
      await pumpHost(tester, positionMs: 5000);
      expect(find.byType(NoteStickerText), findsNothing);
      await tester.pump();
      await tester.pump();
      expect(find.byType(NoteStickerText), findsNothing);
      // 出窗后再次回窗（反向跨越）同样恢复显示。
      await pumpHost(tester, positionMs: 4999);
      expect(find.byType(NoteStickerText), findsOneWidget);
    });

    testWidgets('显隐与播放状态无关：暂停与播放同一位置同样显示', (tester) async {
      final container = await pumpHost(tester, positionMs: 3000);
      expect(find.byType(NoteStickerText), findsOneWidget);
      container.read(playbackEngineProvider).play();
      await tester.pump();
      expect(find.byType(NoteStickerText), findsOneWidget);
      container.read(playbackEngineProvider).pause();
      await tester.pump();
      expect(find.byType(NoteStickerText), findsOneWidget);
    });
  });

  group('贴纸随面（注解层按面方向水平换算，文字与图标不镜像）', () {
    const registrationRect = Rect.fromLTWH(0, 0, 800, 600);
    /// 跨面几何：贴在画面左侧的那条备注。
    const leftNote = NoteSticker(
      startMs: 1000,
      endMs: 5000,
      text: '这里注意手',
      geometry: NoteGeometry(centerX: 0.25, centerY: 0.4),
    );

    /// 泵入带注册接线的宿主（命中面活着）；[readOnly] = 控制层展开的编辑态。
    Future<NoteStickerOverlayRegistration> pumpRegistered(
      WidgetTester tester, {
      required FaceDirection faceDirection,
      int positionMs = 3000,
      bool readOnly = false,
      List<NoteSticker> notes = const [leftNote],
      NoteStickerOverlayRegistration? registration,
    }) async {
      final noteRegistration =
          registration ?? NoteStickerOverlayRegistration();
      final engine = FakePlaybackEngine();
      final container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);
      container
          .read(annotationEditorProvider)
          .restoreDocument(AnnotationRestoreDocument(notes: notes));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Stack(
              fit: StackFit.expand,
              children: [
                NoteStickerOverlay(
                  positionMs: positionMs,
                  contentRect: registrationRect,
                  faceDirection: faceDirection,
                  readOnly: readOnly,
                  registration: noteRegistration,
                ),
              ],
            ),
          ),
        ),
      );
      return noteRegistration;
    }

    /// 贴纸的像素矩形（渲染层真值）。
    Rect stickerRect(WidgetTester tester) =>
        tester.getRect(find.byType(NoteStickerText));

    /// 贴纸子树是否套了水平翻转变换（文字 / 图标被镜像的判据）。
    bool horizontallyFlipped(WidgetTester tester) {
      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(NoteStickerOverlay),
          matching: find.byType(Transform),
        ),
      );
      return transforms.any((t) => t.transform.entry(0, 0) < 0);
    }

    testWidgets('播放态：贴纸按面方向换算到对侧等距处，文字不镜像、命中与渲染同源',
        (tester) async {
      await pumpRegistered(tester, faceDirection: FaceDirection.original);
      final original = stickerRect(tester);
      expect(original.center.dx, moreOrLessEquals(800 * 0.25));

      final registration = await pumpRegistered(
        tester,
        faceDirection: FaceDirection.mirrored,
      );
      final mirrored = stickerRect(tester);
      // 独立真值：到左右框边的距离互换（0.25 → 0.75）。
      expect(mirrored.center.dx, moreOrLessEquals(800 * 0.75));
      expect(
        mirrored.center.dx - registrationRect.left,
        moreOrLessEquals(registrationRect.right - original.center.dx),
      );
      expect(mirrored.center.dy, moreOrLessEquals(original.center.dy));
      expect(mirrored.size, original.size);
      // 文字与图标不套翻转变换（只有画面件吃镜像）。
      expect(horizontallyFlipped(tester), isFalse);
      // 渲染 = 命中同一处：镜像后的矩形中心命中、换算前的原位置不命中。
      expect(registration.hitTest(mirrored.center), isTrue);
      expect(
        registration.hitTest(Offset(800 * 0.25, original.center.dy)),
        isFalse,
        reason: '命中的是换算后的位置，不存在「画在一处、点在另一处」',
      );
    });

    testWidgets('只读常显（控制层展开）：贴纸仍按面方向换算显示，但不参与命中',
        (tester) async {
      final registration = await pumpRegistered(
        tester,
        faceDirection: FaceDirection.mirrored,
        readOnly: true,
      );
      expect(find.byType(NoteStickerText), findsOneWidget);
      final readOnly = stickerRect(tester);
      expect(readOnly.center.dx, moreOrLessEquals(800 * 0.75));
      expect(horizontallyFlipped(tester), isFalse);
      expect(registration.hitTest(readOnly.center), isFalse);
    });

    testWidgets('选中态：贴纸与角工具都随面换算，工具图标保持正向',
        (tester) async {
      final registration = await pumpRegistered(
        tester,
        faceDirection: FaceDirection.mirrored,
      );
      registration.select();
      await tester.pump();

      final sticker = stickerRect(tester);
      expect(sticker.center.dx, moreOrLessEquals(800 * 0.75));
      // 选中框与角工具围着换算后的贴纸矩形（不是换算前的位置）。
      final selection = tester.getRect(
        find.byKey(const Key('note_sticker_selected')),
      );
      expect(selection.center.dx, moreOrLessEquals(sticker.center.dx));
      expect(selection.center.dy, moreOrLessEquals(sticker.center.dy));
      final deleteTool = tester.getRect(
        find.byKey(const Key('note_sticker_tool_delete')),
      );
      final openEditorTool = tester.getRect(
        find.byKey(const Key('note_sticker_tool_open_editor')),
      );
      // 左上仍是删除、右上仍是打开编辑器（角工具不随镜像换边）。
      expect(deleteTool.center.dx, lessThan(openEditorTool.center.dx));
      expect(deleteTool.center.dy, lessThan(sticker.center.dy));
      expect(openEditorTool.center.dy, lessThan(sticker.center.dy));
      expect(deleteTool.center.dx, lessThan(sticker.center.dx));
      expect(openEditorTool.center.dx, greaterThan(sticker.center.dx));
      expect(horizontallyFlipped(tester), isFalse);
    });

    testWidgets('窗外：随面换算不改变显隐（窗外照旧不渲染、不注册）',
        (tester) async {
      final registration = await pumpRegistered(
        tester,
        faceDirection: FaceDirection.mirrored,
        positionMs: 5000,
      );
      expect(find.byType(NoteStickerText), findsNothing);
      expect(registration.hitTest(const Offset(400, 300)), isFalse);
    });
  });

  group('文本恒定样式渲染（正文恒白 + 描边按底色派生）', () {
    /// 文本层的有效样式（整段或 rich span 根样式）。
    TextStyle? effectiveStyle(Text t) => t.style ?? t.textSpan?.style;

    /// 挂在 [text] 段上的描边样式（不限定在哪一层文本上）。
    List<TextStyle> mentionStrokeStyles(WidgetTester tester, String text) {
      final result = <TextStyle>[];
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final span = t.textSpan;
        if (span is! TextSpan || span.children == null) continue;
        for (final child in span.children!.whereType<TextSpan>()) {
          final style = child.style;
          if (child.text == text &&
              style?.foreground?.style == PaintingStyle.stroke) {
            result.add(style!);
          }
        }
      }
      return result;
    }

    testWidgets('正文恒白、黑描边恒开', (tester) async {
      await pumpHost(tester, positionMs: 3000);
      final styles = tester
          .widgetList<Text>(find.byType(Text))
          .map(effectiveStyle)
          .whereType<TextStyle>()
          .toList();
      // 正文填充恒白。
      expect(
        styles.any((s) => s.color == Colors.white),
        isTrue,
        reason: '正文填充恒白',
      );
      // 黑描边恒开：存在以黑色描边前景画笔渲染的样式。
      expect(
        styles.any(
          (s) =>
              s.foreground?.style == PaintingStyle.stroke &&
              s.foreground?.color == Colors.black,
        ),
        isTrue,
        reason: '黑描边恒开',
      );
    });

    testWidgets('点名段描边按该段底色派生：红色代表色亮度 > 0.40 描黑边',
        (tester) async {
      final container = await pumpHost(
        tester,
        positionMs: 3000,
        notes: const [
          NoteSticker(startMs: 1000, endMs: 5000, text: '@果 注意'),
        ],
      );
      // 名册就位：`@果 ` 构成点名语法单元（解析按当前名册）。
      await container
          .read(dancerRosterControllerProvider)
          .addDancer('果', color: 0xFFE53935);
      await tester.pump();
      // 红代表色 0xFFE53935 感知亮度 ≈ 0.423 > 0.40，点名段描边取黑支。
      final strokes = mentionStrokeStyles(tester, '果');
      expect(strokes, isNotEmpty, reason: '点名段存在描边样式');
      expect(
        strokes.map((s) => s.foreground!.color),
        everyElement(Colors.black),
        reason: '红色代表色亮度 > 0.40 → 描黑边',
      );
    });

    testWidgets('纯白代表色的舞者：点名段走纯白特例描白边', (tester) async {
      final container = await pumpHost(
        tester,
        positionMs: 3000,
        notes: const [
          NoteSticker(startMs: 1000, endMs: 5000, text: '@果 注意'),
        ],
      );
      await container
          .read(dancerRosterControllerProvider)
          .addDancer('果', color: 0xFFFFFFFF);
      await tester.pump();
      // 纯白代表色的点名段：走纯白特例描白边。
      final strokes = mentionStrokeStyles(tester, '果');
      expect(
        strokes.any((s) => s.foreground!.color == Colors.white),
        isTrue,
        reason: '纯白代表色的点名段走白边',
      );
    });

    testWidgets('纯白点名：白边收窄，另有共用线宽黑边', (tester) async {
      final container = await pumpHost(
        tester,
        positionMs: 3000,
        notes: const [
          NoteSticker(startMs: 1000, endMs: 5000, text: '@果 注意'),
        ],
      );
      await container
          .read(dancerRosterControllerProvider)
          .addDancer('果', color: 0xFFFFFFFF);
      await tester.pump();
      // 存在以底色派生色的描边样式：纯白点名段的白边收窄，另有共用线宽的
      // 黑色描边（纯白底色上仍可读）。
      final strokes = mentionStrokeStyles(tester, '果');
      expect(
        strokes.any(
          (s) =>
              s.foreground!.color == Colors.white &&
              (s.foreground!.strokeWidth - kNoteStickerWhiteMentionStrokeWidth)
                      .abs() <
                  0.001,
        ),
        isTrue,
        reason: '纯白点名段的白边收窄',
      );
      expect(
        strokes.any(
          (s) =>
              s.foreground!.color == Colors.black &&
              s.foreground!.strokeWidth == kNoteStickerOutlineWidth,
        ),
        isTrue,
        reason: '存在共用线宽的黑色描边',
      );
    });
  });

  group('默认落点与钳制（渲染像素 = 模块几何交叉断言）', () {
    testWidgets('默认几何：落点 = 具名常量（居中、顶边下移 12%）、字号随系数',
        (tester) async {
      await pumpHost(tester, positionMs: 3000);
      final rendered = tester.getRect(find.byType(NoteStickerText));
      // 独立真值：同一纯函数 + 按渲染字号的真实排版（生产测量的同一路径）。
      final fontSize = kNoteStickerBaseFontSize * noteDefaultScale;
      final tp = TextPainter(
        text: TextSpan(
          text: '这里注意手',
          style: TextStyle(fontSize: fontSize),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final expected = noteStickerRect(
        geometry: const NoteGeometry(),
        contentRect: contentRect,
        stickerSize: tp.size,
        faceDirection: FaceDirection.original,
      );
      expect(rendered.left, moreOrLessEquals(expected.left));
      expect(rendered.top, moreOrLessEquals(expected.top));
      expect(rendered.center.dx,
          moreOrLessEquals(contentRect.width * noteDefaultCenterX));
      expect(rendered.center.dy,
          moreOrLessEquals(contentRect.height * noteDefaultCenterY));
      // 独立字面量锚点：内容矩形 800×600、默认几何（centerX 0.5 / centerY 0.12）
      // → 落点中心写死为 (400, 72)。
      expect(rendered.center.dx, moreOrLessEquals(400));
      expect(rendered.center.dy, moreOrLessEquals(72));
      expect(rendered.size.height, moreOrLessEquals(tp.size.height));
    });

    testWidgets('按实际尺寸钳进内容矩形：大系数贴纸不出画', (tester) async {
      await pumpHost(
        tester,
        positionMs: 3000,
        notes: const [
          NoteSticker(
            startMs: 1000,
            endMs: 5000,
            text: '这里注意手',
            // 默认落点附近 + 3× 字号 → 实际矩形上缘越出内容矩形顶，
            // 钳回框内（仍完整在画面内）。
            geometry: NoteGeometry(centerY: 0.02, scale: 3),
          ),
        ],
      );
      final rendered = tester.getRect(find.byType(NoteStickerText));
      expect(rendered.left, greaterThanOrEqualTo(contentRect.left));
      expect(rendered.top, greaterThanOrEqualTo(contentRect.top));
      expect(rendered.right, lessThanOrEqualTo(contentRect.right));
      expect(rendered.bottom, lessThanOrEqualTo(contentRect.bottom));
    });
  });

  group('几何归一化写入公开标记文件并可往返还原', () {
    test('新建备注默认落点 = 具名常量；随 notes 段编解码往返不失真', () {
      final engine = FakePlaybackEngine();
      final container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);
      container.read(annotationEditorProvider).submit(
            const InsertNote(at: Duration(milliseconds: 3000)),
          );
      final notes = container.read(noteStickersProvider);
      expect(notes, hasLength(1));
      // 默认落点来自具名常量（真机看版项）；几何为内容矩形归一化值。
      expect(
        notes.single.geometry,
        const NoteGeometry(
          centerX: noteDefaultCenterX,
          centerY: noteDefaultCenterY,
          scale: noteDefaultScale,
        ),
      );
      // 公开标记文件元素编解码往返：归一化几何原样还原。
      final restored = NoteSticker.fromJson(notes.single.toJson());
      expect(restored, notes.single);
      expect(restored!.geometry, notes.single.geometry);
    });

    test('真实文件路径往返：几何随 markers `notes` 段还原', () async {
      final dir = await Directory.systemTemp.createTemp('note_sticker_16');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/markers_abc.json');
      const doc = MarkersDocument(
        notes: [
          NoteSticker(
            startMs: 1000,
            endMs: 5000,
            text: '这里注意手',
            geometry: NoteGeometry(
              centerX: noteDefaultCenterX,
              centerY: noteDefaultCenterY,
              scale: noteDefaultScale,
            ),
          ),
        ],
      );
      await file.writeAsString(jsonEncode(doc.toJson()));
      final restored = MarkersDocument.fromJson(
        Map<String, Object?>.from(jsonDecode(await file.readAsString()) as Map),
      );
      expect(restored.notes.single.geometry, doc.notes.single.geometry);
      expect(restored, doc);
    });
  });

  group('贴纸文本单行不裁（真实 app 结构：Material 环境默认样式）', () {
    /// 真实播放页结构：`Material` 环境（默认文本样式带 `letterSpacing` 与
    /// `height`）→ 全屏 Stack。缺陷即在「量测不合并环境样式、渲染合并」时
    /// 显形：渲染宽于量测宽 → 末字软换行到贴纸盒外的第二行被裁掉。
    Future<ProviderContainer> pumpUnderMaterial(
      WidgetTester tester, {
      List<NoteSticker> notes = const [
        NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手'),
      ],
    }) async {
      final engine = FakePlaybackEngine();
      final container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      addTearDown(container.dispose);
      container
          .read(annotationEditorProvider)
          .restoreDocument(AnnotationRestoreDocument(notes: notes));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Material(
              child: Stack(
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
        ),
      );
      return container;
    }

    testWidgets('末字不换行且完整落在贴纸矩形内（填充层与描边层都单行）', (tester) async {
      await pumpUnderMaterial(tester);
      final sticker = tester.getRect(find.byType(NoteStickerText));
      final paragraphs = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .toList();
      // 描边层 + 填充层。
      expect(paragraphs, hasLength(2));
      for (final paragraph in paragraphs) {
        final plain = paragraph.text.toPlainText();
        expect(plain, '这里注意手');
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length),
        );
        // 单行标签：整段只有一个文本框（末字不落到被裁的第二行）。
        expect(boxes, hasLength(1));
        // 末字完整落在贴纸矩形内。
        expect(
          sticker.left + boxes.single.right,
          lessThanOrEqualTo(sticker.right + 0.01),
        );
        expect(
          sticker.top + boxes.single.bottom,
          lessThanOrEqualTo(sticker.bottom + 0.01),
        );
      }
    });

    testWidgets('环境默认样式的字距与行高不改渲染尺寸：语义档两侧吃同一缩放值',
        (tester) async {
      // 语义档：真值不再自建 noScaling，而是按**两侧同一个**
      // 系统字号缩放值（独立字面量）量测；渲染盒 == 按该缩放量测的盒。
      // 1.3× 与 1.6× 各验一次：实现若写死
      // 某个缩放值、不读系统字号，1.6× 一档必红。
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final scale in const [1.3, 1.6]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        await pumpUnderMaterial(tester);
        final sticker = tester.getRect(find.byType(NoteStickerText));
        final fontSize = kNoteStickerBaseFontSize * noteDefaultScale;
        final tp = TextPainter(
          text: TextSpan(text: '这里注意手', style: noteStickerTextStyle(fontSize)),
          textScaler: TextScaler.linear(scale),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        expect(
          sticker.size.width,
          moreOrLessEquals(tp.size.width),
          reason: '$scale× 渲染宽 = 同缩放量测宽',
        );
        expect(
          sticker.size.height,
          moreOrLessEquals(tp.size.height),
          reason: '$scale× 渲染高 = 同缩放量测高',
        );
        tp.dispose();
      }
    });

    testWidgets('含点名语法文本下仍成立：可见文本单行不裁、盒尺寸 = 可见分段量测',
        (tester) async {
      // 语义档：真值按两侧同一个系统字号缩放值（1.3×）量测。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final container = await pumpUnderMaterial(
        tester,
        notes: const [
          NoteSticker(startMs: 1000, endMs: 5000, text: '@果 走位偏左'),
        ],
      );
      await container
          .read(dancerRosterControllerProvider)
          .addDancer('果', color: 0xFF123456);
      await tester.pump();

      final sticker = tester.getRect(find.byType(NoteStickerText));
      final paragraphs = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .toList();
      // 描边层 + 填充层：语法字符被隐藏，两层都只显示「果走位偏左」。
      expect(paragraphs, hasLength(2));
      for (final paragraph in paragraphs) {
        final plain = paragraph.text.toPlainText();
        expect(plain, '果走位偏左');
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: plain.length),
        );
        expect(boxes, hasLength(1));
        expect(
          sticker.left + boxes.single.right,
          lessThanOrEqualTo(sticker.right + 0.01),
        );
        expect(
          sticker.top + boxes.single.bottom,
          lessThanOrEqualTo(sticker.bottom + 0.01),
        );
      }
      // 盒尺寸 = 按**可见分段**（非原文）量测的尺寸；缩放值 = 两侧同一个
      // 系统字号值（1.3×，独立字面量）。
      final fontSize = kNoteStickerBaseFontSize * noteDefaultScale;
      final tp = TextPainter(
        text: TextSpan(text: '果走位偏左', style: noteStickerTextStyle(fontSize)),
        textScaler: const TextScaler.linear(1.3),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      expect(sticker.size.width, moreOrLessEquals(tp.size.width));
      expect(sticker.size.height, moreOrLessEquals(tp.size.height));
      tp.dispose();
    });

    testWidgets('语义档：系统字号 1.3× 下贴纸盒按缩放后的量测值重算',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpUnderMaterial(tester);

      expect(tester.takeException(), isNull);
      final sticker = tester.getRect(find.byType(NoteStickerText));
      // 独立真源：同样式 + 同缩放（1.3）的模块量测。贴纸盒按缩放后的
      // 量测尺寸重算，不沿用 1.0× 的旧盒。
      final tp = TextPainter(
        text: TextSpan(text: '这里注意手', style: noteStickerTextStyle(
          kNoteStickerBaseFontSize * noteDefaultScale,
        )),
        textScaler: const TextScaler.linear(1.3),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      expect(sticker.size.width, moreOrLessEquals(tp.size.width));
      expect(sticker.size.height, moreOrLessEquals(tp.size.height));
      tp.dispose();
      // 不越出画面：贴纸盒仍在内容矩形内（noteStickerRect 钳制）。
      expect(sticker, contentRect.intersect(sticker), reason: '贴纸盒不越出画面');
      // 两侧同源：渲染层吃环境缩放值。
      final textWidget = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(NoteStickerText),
              matching: find.byType(Text),
            )
            .last,
      );
      expect(
        textWidget.textScaler!.scale(10),
        13.0,
      );
    });

    testWidgets('窗内改文本后贴纸盒按新文本量测重算',
        (tester) async {
      final container = await pumpHost(tester, positionMs: 3000);
      final before = tester.getSize(find.byType(NoteStickerText));

      const newText = '这里注意手这里注意手这里注意手';
      container
          .read(annotationEditorProvider)
          .submit(SetNoteText(index: 0, text: newText));
      await tester.pump();

      final after = tester.getSize(find.byType(NoteStickerText));
      final expected = measureStickerText(newText);
      expect(
        after.width,
        moreOrLessEquals(expected.width),
        reason: '缓存按文本失效：盒宽 = 新文本量测宽（不沿用旧值）',
      );
      expect(after.height, moreOrLessEquals(expected.height));
      expect(after.width, greaterThan(before.width));
    });

    testWidgets('名册变化后贴纸盒按新可见文本量测重算', (tester) async {
      final container = await pumpHost(
        tester,
        positionMs: 3000,
        notes: const [NoteSticker(startMs: 1000, endMs: 5000, text: '@果 走')],
      );
      // 名册无名「果」：`@果 ` 不构成点名单元 → 原样显示（含 `@` 与空格）。
      final before = tester.getSize(find.byType(NoteStickerText));

      await container
          .read(dancerRosterControllerProvider)
          .addDancer('果', color: 0xFFE53935);
      await tester.pump();

      final after = tester.getSize(find.byType(NoteStickerText));
      final expected = measureStickerText('果走');
      expect(
        after.width,
        moreOrLessEquals(expected.width),
        reason: '缓存按名册取色失效：可见分段量测（语法字符隐藏）',
      );
      expect(after.width, lessThan(before.width));
    });
  });
}
