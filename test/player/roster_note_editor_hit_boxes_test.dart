import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/dancer_roster.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/player/dancer_roster_chips.dart'
    show kRosterStripMaxWidth;
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/semantics_assertions.dart';

/// 名册与备注编辑器命中盒与内联提示：色板每格与舞者词条、停靠
/// 条四枚按钮的命中矩形 ≥ 下限（视觉尺寸不变）；色板每格报出自己的颜色；
/// 长名字省略不撑破；空白舞者名给内联提示；大字号下色板与词条仍完整在场。
void main() {
  late ProviderContainer container;
  late InMemoryVideoDocumentStorage storage;

  setUp(() {
    storage = InMemoryVideoDocumentStorage();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: const Duration(minutes: 1)),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<void> seedRoster() async {
    await VideoDocumentCoordinator(storage).patchMarkers(
      (doc) => doc.withRoster(const [
        DancerRosterEntry(name: '果', color: 0xFFE53935),
        DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
      ]),
    );
  }

  Future<void> pumpNoteEditor(WidgetTester tester) async {
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            timeline: AnnotationTimeline.wholeVideo(
              const Duration(minutes: 1),
            ),
            notes: const [
              NoteSticker(startMs: 10000, endMs: 14000, text: '注意手'),
            ],
          ),
        );
    await container
        .read(dancerRosterControllerProvider)
        .startForVideo(VideoDocumentCoordinator(storage));
    container.read(noteTextEditorTargetProvider.notifier).open(10000);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: NoteTextEditorPanel())),
      ),
    );
    await tester.pump();
  }

  /// 切到名册态（点「名册」钮）。
  Future<void> enterRosterMode(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('note_editor_roster')));
    await tester.pump();
  }

  /// 打开名册态舞者的选色浮层。
  Future<void> openColorSheet(WidgetTester tester) async {
    await enterRosterMode(tester);
    await tester.tap(find.byKey(const Key('roster_chip_果')));
    await tester.pumpAndSettle();
  }

  /// 关键文本未被裁：文字完整画完、无
  /// 溢出裁切标记。词条长名字的省略号是明示的省略、不算裁——这里核对
  /// 的是停靠钮文字与普通名字这类不允许裁的语义文本。
  void expectTextNotClipped(WidgetTester tester, String text) {
    final finder = find.text(text, findRichText: true);
    expect(finder, findsWidgets, reason: '「$text」在场');
    for (final widget in finder.evaluate()) {
      final paragraph = widget.renderObject! as RenderParagraph;
      expect(
        paragraph.debugHasOverflowShader,
        isFalse,
        reason: '「$text」未被裁',
      );
    }
  }

  group('色板命中盒与语义', () {
    test('色名表与色板同长（平行列表不失配）', () {
      expect(kRosterPaletteNames.length, kRosterPalette.length);
    });

    testWidgets('每格命中矩形 ≥ 48×48', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await openColorSheet(tester);
      for (var i = 0; i < kRosterPalette.length; i++) {
        final rect = tester.getRect(
          find.byKey(Key('roster_palette_color_$i')),
        );
        expect(rect.width, greaterThanOrEqualTo(kHitTargetMinSize),
            reason: '色板第 $i 格命中宽');
        expect(rect.height, greaterThanOrEqualTo(kHitTargetMinSize),
            reason: '色板第 $i 格命中高');
      }
    });

    testWidgets('每格是按钮并报出自己的颜色', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await openColorSheet(tester);
      for (var i = 0; i < kRosterPaletteNames.length; i++) {
        expectButtonSemantics(
          tester,
          Key('roster_palette_color_$i'),
          label: '选代表色：${kRosterPaletteNames[i]}',
        );
      }
    });

    testWidgets('点格选色仍直写并收浮层（命中盒外扩不改行为）', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await openColorSheet(tester);
      await tester.tap(find.byKey(const Key('roster_palette_color_1')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(dancerRosterControllerProvider)
            .roster
            .firstWhere((e) => e.name == '果')
            .color,
        kRosterPalette[1],
      );
      expect(find.byKey(const Key('roster_color_sheet')), findsNothing);
    });
  });

  group('舞者词条命中与排版', () {
    testWidgets('词条命中高 ≥ 48', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await enterRosterMode(tester);
      final rect = tester.getRect(find.byKey(const Key('roster_chip_果')));
      expect(rect.height, greaterThanOrEqualTo(kHitTargetMinSize));
      expect(rect.width, greaterThanOrEqualTo(kHitTargetMinSize));
    });

    testWidgets('长名字省略：词条宽不超过快捷区上限、不撑破一行', (tester) async {
      await VideoDocumentCoordinator(storage).patchMarkers(
        (doc) => doc.withRoster(const [
          DancerRosterEntry(
            name: '这是一个特别特别特别长的舞者名字为了验证省略号行为是否生效',
            color: 0xFFE53935,
          ),
        ]),
      );
      await pumpNoteEditor(tester);
      await enterRosterMode(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(const Key('note_editor_roster_strip'))).width,
        lessThanOrEqualTo(kRosterStripMaxWidth),
      );
      final chip = tester.getRect(
        find.byKey(const Key(
          'roster_chip_这是一个特别特别特别长的舞者名字为了验证省略号行为是否生效',
        )),
      );
      expect(chip.width, lessThanOrEqualTo(kRosterStripMaxWidth));
    });

    testWidgets('大字号 1.3/1.6/2.0：色板与词条仍完整在场、无异常', (tester) async {
      for (final scale in [1.3, 1.6, 2.0]) {
        await seedRoster();
        await pumpNoteEditor(tester);
        tester.view.platformDispatcher.textScaleFactorTestValue = scale;
        await tester.pump();
        await enterRosterMode(tester);
        expect(
          find.byKey(const Key('note_editor_roster_strip')),
          findsOneWidget,
          reason: '$scale× 词条段在场',
        );
        expectTextNotClipped(tester, '返回备注编辑');
        expectTextNotClipped(tester, '删除');
        expectTextNotClipped(tester, '完成');
        expectTextNotClipped(tester, '新建');
        expectTextNotClipped(tester, '果');
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('roster_chip_果')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('roster_palette_color_${kRosterPalette.length - 1}')),
          findsOneWidget,
          reason: '$scale× 色板 24 格完整在场',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();
      }
    });
  });

  group('停靠条按钮命中盒', () {
    testWidgets('名册态四枚按钮命中矩形 ≥ 48×48', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await enterRosterMode(tester);
      for (final key in [
        const Key('note_editor_roster_new'),
        const Key('note_editor_roster'),
        const Key('note_editor_delete'),
        const Key('note_editor_done'),
      ]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.width, greaterThanOrEqualTo(kHitTargetMinSize), reason: '$key 命中宽');
        expect(rect.height, greaterThanOrEqualTo(kHitTargetMinSize), reason: '$key 命中高');
      }
    });

    testWidgets('备注态三枚按钮命中矩形 ≥ 48×48', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      for (final key in [
        const Key('note_editor_roster'),
        const Key('note_editor_delete'),
        const Key('note_editor_done'),
      ]) {
        final rect = tester.getRect(find.byKey(key));
        expect(rect.width, greaterThanOrEqualTo(kHitTargetMinSize), reason: '$key 命中宽');
        expect(rect.height, greaterThanOrEqualTo(kHitTargetMinSize), reason: '$key 命中高');
      }
    });
  });

  group('空白舞者名内联提示', () {
    testWidgets('空白名点「新建」：给内联提示说明为什么没建、名册不变', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await enterRosterMode(tester);
      await tester.tap(find.byKey(const Key('note_editor_roster_new')));
      await tester.pump();
      expect(
        find.byKey(const Key('note_editor_dancer_hint')),
        findsOneWidget,
        reason: '内联提示在场',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('note_editor_dancer_hint')))
            .data,
        isNotEmpty,
      );
      expect(
        container.read(dancerRosterControllerProvider).roster.length,
        2,
        reason: '没建出无名舞者',
      );
    });

    testWidgets('输入名字后建人：提示不再出现', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);
      await enterRosterMode(tester);
      await tester.tap(find.byKey(const Key('note_editor_roster_new')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('note_editor_dancer_field')),
        '海',
      );
      await tester.tap(find.byKey(const Key('note_editor_roster_new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note_editor_dancer_hint')), findsNothing);
    });
  });
}
