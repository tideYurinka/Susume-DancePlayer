import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/dancer_roster.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/dancer_roster_chips.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 记录型保存 sink（名册操作不改备注的断言用）。
class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 舞者快捷区（裁决 ㊸）：一排舞者
/// 词条（名字 + 代表色圆点）就是编辑器那一行里的一段——宽度按内容收缩、
/// 上限 260dp、超出左右滑动；词条顺序按最近用过、点前三名不换位、点之外
/// 的名字提到第一位；备注态点词条 = 光标处插入 `@名字 `、名册态点词条 =
/// 弹这位舞者的 24 色选色浮层。增删改色仍走直写控制器（不入撤销史、
/// 不受锁、不改备注）。
void main() {
  late ProviderContainer container;
  late _RecordingSaveSink sink;
  late InMemoryVideoDocumentStorage storage;

  setUp(() {
    sink = _RecordingSaveSink();
    storage = InMemoryVideoDocumentStorage();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: const Duration(minutes: 1)),
        ),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// 种名册（果=红、鸟=蓝、海=绿、山=紫）。
  Future<void> seedRoster() async {
    await VideoDocumentCoordinator(storage).patchMarkers(
      (doc) => doc.withRoster(const [
        DancerRosterEntry(name: '果', color: 0xFFE53935),
        DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
        DancerRosterEntry(name: '海', color: 0xFF43A047),
        DancerRosterEntry(name: '山', color: 0xFF8E24AA),
      ]),
    );
  }

  /// 种一条既有备注（起点 10s、文本「注意手」）、读回已种名册、泵备注
  /// 编辑器并打开目标；[beforeOpen] 在打开目标前插入（如上锁）。
  Future<void> pumpNoteEditor(
    WidgetTester tester, {
    void Function()? beforeOpen,
  }) async {
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            timeline: AnnotationTimeline.wholeVideo(const Duration(minutes: 1)),
            notes: const [
              NoteSticker(startMs: 10000, endMs: 14000, text: '注意手'),
            ],
          ),
        );
    await container
        .read(dancerRosterControllerProvider)
        .startForVideo(VideoDocumentCoordinator(storage));
    beforeOpen?.call();
    container.read(noteTextEditorTargetProvider.notifier).open(10000);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: NoteTextEditorPanel())),
      ),
    );
    await tester.pump();
  }

  /// 泵一个左占位 + 快捷区 + 右探针的横排（宽度与紧贴断言用）；泵前把
  /// 已种名册读回控制器。
  Future<void> pumpStrip(WidgetTester tester) async {
    await container
        .read(dancerRosterControllerProvider)
        .startForVideo(VideoDocumentCoordinator(storage));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                Expanded(child: SizedBox()),
                DancerRosterChipBar(rosterMode: false),
                SizedBox(key: Key('right_probe'), width: 40, height: 30),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect stripRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('note_editor_roster_strip')));

  group('宽度与滑动', () {
    testWidgets('词条少：宽度按内容收缩、右缘紧贴右侧相邻控件', (tester) async {
      await seedRoster();
      await pumpStrip(tester);

      final strip = stripRect(tester);
      final probe = tester.getRect(find.byKey(const Key('right_probe')));
      expect(strip.width, lessThan(260), reason: '词条少时按内容收缩');
      expect(strip.right, probe.left, reason: '紧贴右侧相邻控件、不留空隙');
      expect(tester.takeException(), isNull);
    });

    testWidgets('词条多：宽度封顶 260dp、不撑破一行、无异常', (tester) async {
      await VideoDocumentCoordinator(storage).patchMarkers(
        (doc) => doc.withRoster([
          for (var i = 0; i < 12; i++)
            DancerRosterEntry(name: '舞者名字$i', color: kRosterPalette[i]),
        ]),
      );
      await pumpStrip(tester);

      final strip = stripRect(tester);
      final probe = tester.getRect(find.byKey(const Key('right_probe')));
      expect(strip.width, 260, reason: '宽度上限 260dp');
      expect(strip.right, probe.left, reason: '封顶时也紧贴右侧控件');
      expect(tester.takeException(), isNull);
    });
  });

  group('新建默认色', () {
    test('纯件：取色板里未被占用的第一色；占满回头取首色', () {
      expect(firstUnusedPaletteColor(const []), kRosterPalette.first);
      expect(
        firstUnusedPaletteColor([kRosterPalette.first]),
        kRosterPalette[1],
      );
      expect(
        firstUnusedPaletteColor([
          kRosterPalette[0],
          kRosterPalette[2],
          kRosterPalette[1],
        ]),
        kRosterPalette[3],
        reason: '顺序无关，看占用集合',
      );
      expect(
        firstUnusedPaletteColor(kRosterPalette),
        kRosterPalette.first,
        reason: '24 色占满无未占用色，回落首色',
      );
    });
  });

  group('词条顺序（最近用过）', () {
    test('纯件：显示序 = 最近用过在前，未点过的按名册文件序跟随', () {
      final roster = [
        const DancerRosterEntry(name: '果', color: 1),
        const DancerRosterEntry(name: '鸟', color: 2),
        const DancerRosterEntry(name: '海', color: 3),
      ];
      expect(
        [
          for (final e in orderChipsByRecency(roster, ['海', '果'])) e.name,
        ],
        ['海', '果', '鸟'],
      );
      // recency 里的失效名字（已删舞者）不出现。
      expect(
        [
          for (final e in orderChipsByRecency(roster, ['山', '鸟'])) e.name,
        ],
        ['鸟', '果', '海'],
      );
    });

    test('纯件：点前三名不换位、点之外的名字提到第一位', () {
      final display = ['果', '鸟', '海', '山'];
      // 前三名：顺序不变。
      expect(recencyAfterTap(['山'], display, 0), ['山']);
      expect(recencyAfterTap(['山'], display, 2), ['山']);
      // 之外：提到第一位。
      expect(recencyAfterTap(['山'], display, 3), ['山']);
      expect(recencyAfterTap([], display, 3), ['山']);
    });

    testWidgets('点第四个词条：提到第一位（最近用过）；再点第一名不换位', (tester) async {
      await seedRoster();
      await pumpStrip(tester);

      await tester.tap(find.byKey(const Key('roster_chip_山')));
      await tester.pump();

      await pumpStrip(tester);
      // 显示序：山提到最前，其余按文件序。
      final stripFinder = find.descendant(
        of: find.byKey(const Key('note_editor_roster_strip')),
        matching: find.byKey(const Key('roster_chip_山')),
      );
      expect(stripFinder, findsOneWidget);
      final shanRect = tester.getRect(stripFinder);
      for (final name in ['果', '鸟', '海']) {
        expect(
          shanRect.left,
          lessThan(tester.getRect(find.byKey(Key('roster_chip_$name'))).left),
          reason: '山被提到第一位',
        );
      }

      // 点前三名（山现在第一名）：顺序不再变。
      final shanBefore = tester.getRect(stripFinder);
      final guoBefore = tester.getRect(find.byKey(const Key('roster_chip_果')));
      await tester.tap(find.byKey(const Key('roster_chip_果')));
      await tester.pump();
      await pumpStrip(tester);
      expect(
        tester.getRect(find.byKey(const Key('roster_chip_山'))),
        shanBefore,
        reason: '点前三名不换位：山仍在第一位',
      );
      expect(
        tester.getRect(find.byKey(const Key('roster_chip_果'))),
        guoBefore,
        reason: '点前三名不换位：果仍在第二名',
      );
    });
  });

  group('点词条两态语义', () {
    testWidgets('备注态点词条 = 在光标处插入 `@名字 `，收起即存', (tester) async {
      await seedRoster();
      await pumpNoteEditor(tester);

      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byKey(const Key('note_text_editor_field')),
          matching: find.byType(EditableText),
        ),
      );
      editable.widget.controller.selection = const TextSelection.collapsed(
        offset: 1,
      );
      await tester.tap(find.byKey(const Key('roster_chip_果')));
      await tester.pump();

      expect(editable.widget.controller.text, '注@果 意手');
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pump();
      expect(container.read(noteStickersProvider).single.text, '注@果 意手');
    });

    testWidgets('名册态点词条 = 弹这位舞者的选色浮层：24 色、选色直写并落盘', (tester) async {
      await seedRoster();
      await container
          .read(dancerRosterControllerProvider)
          .startForVideo(VideoDocumentCoordinator(storage));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(child: SizedBox()),
                  DancerRosterChipBar(rosterMode: true),
                  SizedBox(key: Key('right_probe'), width: 40, height: 30),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('roster_chip_鸟')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roster_color_sheet')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key as ValueKey<String>).value.startsWith(
                'roster_palette_color_',
              ),
        ),
        findsNWidgets(kRosterPalette.length),
        reason: '色板 24 色',
      );
      expect(find.text('选代表色'), findsOneWidget);

      await tester.tap(find.byKey(const Key('roster_palette_color_5')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('roster_color_sheet')), findsNothing);
      final controller = container.read(dancerRosterControllerProvider);
      expect(
        controller.roster.firstWhere((e) => e.name == '鸟').color,
        kRosterPalette[5],
      );
      expect(
        (storage.markersSnapshot['roster']['dancers'].firstWhere(
          (e) => (e as Map)['name'] == '鸟',
        ) as Map)['color'],
        kRosterPalette[5],
        reason: '改色直写落盘、只触碰名册段',
      );
    });

    testWidgets('选色浮层删除：舞者删除直写并落盘', (tester) async {
      await seedRoster();
      await container
          .read(dancerRosterControllerProvider)
          .startForVideo(VideoDocumentCoordinator(storage));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  Expanded(child: SizedBox()),
                  DancerRosterChipBar(rosterMode: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('roster_chip_山')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('roster_palette_delete_山')));
      await tester.pumpAndSettle();
      // 先确认：取消 = 名册不变。
      expect(
        find.byKey(const Key('roster_palette_delete_dialog')),
        findsOneWidget,
      );
      expect(find.text('删除后这位舞者将从名册移除；已写的点名会因此失去颜色'), findsOneWidget);
      await tester.tap(find.byKey(const Key('roster_palette_delete_cancel')));
      await tester.pumpAndSettle();
      expect(
        container
            .read(dancerRosterControllerProvider)
            .roster
            .where((e) => e.name == '山'),
        isNotEmpty,
      );

      // 确认后才删除直写并落盘。
      await tester.tap(find.byKey(const Key('roster_palette_delete_山')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('roster_palette_delete_confirm')));
      await tester.pumpAndSettle();

      expect(
        container
            .read(dancerRosterControllerProvider)
            .roster
            .where((e) => e.name == '山'),
        isEmpty,
      );
      expect([
        for (final e in storage.markersSnapshot['roster']['dancers'])
          (e as Map)['name'],
      ], isNot(contains('山')));
    });
  });

  testWidgets('名册写入仍为直写：不入撤销史、不受锁定分段影响、不改备注、不产生备注保存入队', (tester) async {
    await seedRoster();
    await pumpNoteEditor(
      tester,
      beforeOpen: () =>
          container.read(layoutLockedProvider.notifier).replace(true),
    );

    await tester.tap(find.byKey(const Key('note_editor_roster')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roster_chip_海')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('roster_palette_color_3')));
    await tester.pumpAndSettle();

    expect(
      container
          .read(dancerRosterControllerProvider)
          .roster
          .firstWhere((e) => e.name == '海')
          .color,
      kRosterPalette[3],
      reason: '锁定分段不挡名册直写',
    );
    expect(
      container.read(annotationEditHistoryProvider).length,
      0,
      reason: '名册直写不入撤销史',
    );
    expect(
      container.read(noteStickersProvider).single.text,
      '注意手',
      reason: '名册操作不改备注',
    );
    expect(sink.saved, isEmpty, reason: '名册不产生备注保存入队');
  });
}
