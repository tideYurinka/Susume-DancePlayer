import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/note_editor.dart'
    show noteTextEditorTargetProvider;
import 'package:dance_learning_app/player/note_sticker_overlay.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetMinSize;
import 'package:dance_learning_app/player/note_sticker_overlay_registration.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/semantics_assertions.dart';

void main() {
  const contentRect = Rect.fromLTWH(0, 0, 800, 600);
  const note = NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手');

  /// 注入窗内备注并泵入宿主 Stack；四角工具按角序渲染。
  /// 工具回调按宿主接线实现（删除经模块命令、编辑器开唯一编辑器面），跳转
  /// 记一次调用（进编辑态归宿主编排），返回记录器供断言。
  Future<
    ({
      NoteStickerOverlayRegistration registration,
      ProviderContainer container,
      List<String> taps,
    })
  >
  pumpOverlay(
    WidgetTester tester, {
    int positionMs = 3000,
    NoteStickerOverlayRegistration? registration,
  }) async {
    final noteRegistration = registration ?? NoteStickerOverlayRegistration();
    final taps = <String>[];
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(annotationEditorProvider)
        .restoreDocument(const AnnotationRestoreDocument(notes: [note]));
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
                faceDirection: FaceDirection.original,
                registration: noteRegistration,
                onDelete: (n) {
                  taps.add('delete');
                  final notes = container.read(noteStickersProvider);
                  final index = notes.indexWhere(
                    (item) => item.startMs == n.startMs,
                  );
                  if (index < 0) return;
                  container
                      .read(annotationEditorProvider)
                      .submit(RemoveNote(index: index));
                },
                onOpenEditor: (n) {
                  taps.add('openEditor');
                  container
                      .read(noteTextEditorTargetProvider.notifier)
                      .open(n.startMs);
                },
                onJumpToFragment: (_) => taps.add('jump'),
                onToggleLock: (n) {
                  taps.add('toggleLock');
                  final notes = container.read(noteStickersProvider);
                  final index = notes.indexWhere(
                    (item) => item.startMs == n.startMs,
                  );
                  if (index < 0) return;
                  container
                      .read(annotationEditorProvider)
                      .submit(ToggleNoteLock(index: index));
                },
              ),
            ],
          ),
        ),
      ),
    );
    return (registration: noteRegistration, container: container, taps: taps);
  }

  group('四角工具呈现（选中态出现、取消选中消失）', () {
    testWidgets('选中态：四个角工具齐备', (tester) async {
      final registration = (await pumpOverlay(tester)).registration;
      registration.select();
      await tester.pump();
      expect(find.byKey(const Key('note_sticker_tool_delete')), findsOneWidget);
      expect(
        find.byKey(const Key('note_sticker_tool_open_editor')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('note_sticker_tool_jump')), findsOneWidget);
      expect(find.byKey(const Key('note_sticker_tool_lock')), findsOneWidget);
    });

    testWidgets('角工具分居贴纸四角（左上/右上/左下/右下）', (tester) async {
      final registration = (await pumpOverlay(tester)).registration;
      registration.select();
      await tester.pump();
      final border = tester.getRect(
        find.byKey(const Key('note_sticker_selected')),
      );
      final delete = tester.getRect(
        find.byKey(const Key('note_sticker_tool_delete')),
      );
      final editor = tester.getRect(
        find.byKey(const Key('note_sticker_tool_open_editor')),
      );
      final jump = tester.getRect(
        find.byKey(const Key('note_sticker_tool_jump')),
      );
      final lock = tester.getRect(
        find.byKey(const Key('note_sticker_tool_lock')),
      );
      expect(delete.center.dx < border.center.dx, isTrue, reason: '删除在左上');
      expect(delete.center.dy < border.center.dy, isTrue, reason: '删除在左上');
      expect(editor.center.dx > border.center.dx, isTrue, reason: '编辑器在右上');
      expect(editor.center.dy < border.center.dy, isTrue, reason: '编辑器在右上');
      expect(jump.center.dx < border.center.dx, isTrue, reason: '跳转在左下');
      expect(jump.center.dy > border.center.dy, isTrue, reason: '跳转在左下');
      expect(lock.center.dx > border.center.dx, isTrue, reason: '锁角在右下');
      expect(lock.center.dy > border.center.dy, isTrue, reason: '锁角在右下');
    });

    testWidgets('角工具命中盒 ≥ 48、互不重叠、不遮字；视觉图标仍 24dp 且居原位', (tester) async {
      final registration = (await pumpOverlay(tester)).registration;
      registration.select();
      await tester.pump();

      const keys = [
        'note_sticker_tool_delete',
        'note_sticker_tool_open_editor',
        'note_sticker_tool_jump',
        'note_sticker_tool_lock',
      ];
      final rects = <Rect>[];
      for (final name in keys) {
        final finder = find.byKey(Key(name));
        final rect = tester.getRect(finder);
        expect(
          rect.width,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$name 命中盒宽 ≥ 48',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$name 命中盒高 ≥ 48',
        );
        rects.add(rect);
        final icon = tester.getRect(
          find.descendant(of: finder, matching: find.byType(Icon)),
        );
        expect(
          icon.size,
          const Size(kNoteStickerToolIconSize, kNoteStickerToolIconSize),
          reason: '$name 图标仍 24dp',
        );
      }
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse, reason: '四角命中域不互吞');
        }
      }
      // 图标仍距贴纸边 4dp（命中盒外扩不移动图标，也不盖住正文）。
      final sticker = tester
          .getRect(find.byKey(const Key('note_sticker_selected')))
          .deflate(kNoteStickerSelectionPadding);
      final deleteIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('note_sticker_tool_delete')),
          matching: find.byType(Icon),
        ),
      );
      expect(deleteIcon.bottomRight, sticker.topLeft - const Offset(4, 4));
      final editorIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('note_sticker_tool_open_editor')),
          matching: find.byType(Icon),
        ),
      );
      expect(editorIcon.bottomLeft, sticker.topRight + const Offset(4, -4));
      final jumpIcon = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('note_sticker_tool_jump')),
          matching: find.byType(Icon),
        ),
      );
      expect(jumpIcon.topRight, sticker.bottomLeft + const Offset(-4, 4));
    });

    testWidgets('未选中：无角工具（贴纸纯展示、穿透手势）', (tester) async {
      await pumpOverlay(tester);
      expect(find.byKey(const Key('note_sticker_tool_delete')), findsNothing);
      expect(
        find.byKey(const Key('note_sticker_tool_open_editor')),
        findsNothing,
      );
      expect(find.byKey(const Key('note_sticker_tool_jump')), findsNothing);
      expect(find.byKey(const Key('note_sticker_tool_lock')), findsNothing);
    });

    testWidgets('取消选中：角工具随选中框一起消失', (tester) async {
      final registration = (await pumpOverlay(tester)).registration;
      registration.select();
      await tester.pump();
      registration.deselect();
      await tester.pump();
      expect(find.byKey(const Key('note_sticker_tool_delete')), findsNothing);
      expect(
        find.byKey(const Key('note_sticker_tool_open_editor')),
        findsNothing,
      );
      expect(find.byKey(const Key('note_sticker_tool_jump')), findsNothing);
      expect(find.byKey(const Key('note_sticker_tool_lock')), findsNothing);
    });
  });

  group('角工具语义（验收三动作）', () {
    testWidgets('左上删除：备注消失并入撤销史（撤销后复原）', (tester) async {
      final handle = await pumpOverlay(tester);
      final container = handle.container;
      handle.registration.select();
      await tester.pump();
      await tester.tap(find.byKey(const Key('note_sticker_tool_delete')));
      await tester.pump();
      expect(container.read(noteStickersProvider), isEmpty);
      expect(container.read(noteTextEditorTargetProvider), isNull);
      // 入撤销史：撤销一步备注复原。
      container.read(annotationEditorProvider).undo();
      await tester.pump();
      expect(container.read(noteStickersProvider).single, note);
    });

    testWidgets('右上打开编辑器：与轨片段单击进同一个面（同编辑目标位）', (tester) async {
      final handle = await pumpOverlay(tester);
      final container = handle.container;
      handle.registration.select();
      await tester.pump();
      expect(container.read(noteTextEditorTargetProvider), isNull);
      await tester.tap(find.byKey(const Key('note_sticker_tool_open_editor')));
      await tester.pump();
      expect(
        container.read(noteTextEditorTargetProvider),
        note.startMs,
        reason: '编辑器以备注起点标识目标（与轨片段单击同一面）',
      );
    });

    testWidgets('左下跳转：回调宿主（进编辑态 + 定位高亮归宿主编排）', (tester) async {
      final handle = await pumpOverlay(tester);
      handle.registration.select();
      await tester.pump();
      await tester.tap(find.byKey(const Key('note_sticker_tool_jump')));
      await tester.pump();
      expect(handle.taps, ['jump']);
    });
  });

  group('右下锁角（锁定 / 解锁切换）', () {
    testWidgets('未锁备注：锁角显示开锁图标，点击锁定并入撤销史', (tester) async {
      final handle = await pumpOverlay(tester);
      final container = handle.container;
      expect(container.read(noteStickersProvider).single.locked, isFalse);
      handle.registration.select();
      await tester.pump();
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('note_sticker_tool_lock')));
      await tester.pump();
      expect(container.read(noteStickersProvider).single.locked, isTrue);
      // 入撤销史：撤销一步恢复未锁。
      container.read(annotationEditorProvider).undo();
      await tester.pump();
      expect(container.read(noteStickersProvider).single.locked, isFalse);
    });

    testWidgets('已锁备注：锁角显示闭锁图标，再点解锁；其余角工具仍可用', (tester) async {
      final handle = await pumpOverlay(tester);
      final container = handle.container;
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            AnnotationRestoreDocument(
              notes: [NoteSticker(startMs: 1000, endMs: 5000, locked: true)],
            ),
          );
      handle.registration.select();
      await tester.pump();
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      // 已锁不锁死：其余角工具照常在位（点选/角工具不受锁影响）。
      expect(find.byKey(const Key('note_sticker_tool_delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('note_sticker_tool_lock')));
      await tester.pump();
      expect(container.read(noteStickersProvider).single.locked, isFalse);
    });

    testWidgets('锁定态即时反映：锁角图标随 locked 字段切换（与 22 标识同源）', (tester) async {
      final handle = await pumpOverlay(tester);
      handle.registration.select();
      await tester.pump();
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
      await tester.tap(find.byKey(const Key('note_sticker_tool_lock')));
      await tester.pump();
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
    });

    testWidgets('四角工具报出主动语态中文名', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      final handle = await pumpOverlay(tester);
      handle.registration.select();
      await tester.pump();

      expectButtonSemantics(
        tester,
        const Key('note_sticker_tool_delete'),
        label: '删除这段备注',
        enabled: true,
      );
      expectButtonSemantics(
        tester,
        const Key('note_sticker_tool_open_editor'),
        label: '编辑这段备注的文字',
      );
      expectButtonSemantics(
        tester,
        const Key('note_sticker_tool_jump'),
        label: '定位到该备注片段',
      );
      expectButtonSemantics(
        tester,
        const Key('note_sticker_tool_lock'),
        label: '锁定备注贴纸',
      );

      await tester.tap(find.byKey(const Key('note_sticker_tool_lock')));
      await tester.pump();
      expectButtonSemantics(
        tester,
        const Key('note_sticker_tool_lock'),
        label: '解锁备注贴纸',
      );
      semanticsHandle.dispose();
    });
  });
}
