import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/note_sticker_layout.dart';
import 'package:dance_learning_app/player/note_sticker_overlay.dart';
import 'package:dance_learning_app/player/note_sticker_overlay_registration.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

void main() {
  const contentRect = Rect.fromLTWH(0, 0, 800, 600);

  /// 注入窗内备注并泵入宿主 Stack；[registration] 非空时经注册接线挂载
  /// （命中面活着），返回该注册接线供选中 / 命中断言使用。
  Future<NoteStickerOverlayRegistration> pumpOverlay(
    WidgetTester tester, {
    int positionMs = 3000,
    NoteStickerOverlayRegistration? registration,
  }) async {
    final noteRegistration = registration ?? NoteStickerOverlayRegistration();
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          const AnnotationRestoreDocument(
            notes: [NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手')],
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
                positionMs: positionMs,
                contentRect: contentRect,
                faceDirection: FaceDirection.original,
                registration: noteRegistration,
              ),
            ],
          ),
        ),
      ),
    );
    return noteRegistration;
  }

  group('贴纸选中态呈现（青色虚线框）', () {
    testWidgets('未选中：无选中框（纯展示，穿透手势）', (tester) async {
      await pumpOverlay(tester);
      expect(find.byKey(const Key('note_sticker_selected')), findsNothing);
      expect(find.byType(NoteStickerText), findsOneWidget);
    });

    testWidgets('选中：贴纸矩形外圈出现选中框（注册表选中驱动重建）', (tester) async {
      final registration = await pumpOverlay(tester);
      registration.select();
      await tester.pump();
      final border = find.byKey(const Key('note_sticker_selected'));
      expect(border, findsOneWidget);
      // 选中框罩住贴纸文本（外圈留白，不遮字）。
      final borderRect = tester.getRect(border);
      final textRect = tester.getRect(find.byType(NoteStickerText));
      expect(
        borderRect.contains(textRect.topLeft),
        isTrue,
        reason: '选中框包含贴纸文本',
      );
      expect(
        borderRect.contains(textRect.bottomRight),
        isTrue,
        reason: '选中框包含贴纸文本',
      );
      // 退出选中：选中框随通知消失。
      registration.deselect();
      await tester.pump();
      expect(find.byKey(const Key('note_sticker_selected')), findsNothing);
    });

    testWidgets('尺寸变化后选中框随贴纸变宽', (tester) async {
      final registration = await pumpOverlay(tester);
      registration.select();
      await tester.pump();

      final border = find.byKey(const Key('note_sticker_selected'));
      final rectA = tester.getRect(border);

      // 逐帧驱动（播放头推进、贴纸同尺寸）：选中框外观逐位不变。
      await pumpOverlay(tester, positionMs: 3100, registration: registration);
      expect(tester.getRect(border), rectA, reason: '选中框外观逐位不变');

      // 尺寸变化（窗内改文本）→ 选中框跟着变宽。
      ProviderScope.containerOf(
            tester.element(find.byType(NoteStickerOverlay)),
            listen: false,
          )
          .read(annotationEditorProvider)
          .submit(SetNoteText(index: 0, text: '这里注意手这里注意手'));
      await tester.pump();
      expect(
        tester.getRect(border).width,
        greaterThan(rectA.width),
        reason: '选中框随贴纸尺寸变化',
      );
    });

    testWidgets('窗外出窗即无贴纸也无选中框', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Stack(
              fit: StackFit.expand,
              children: [
                NoteStickerOverlay(
                  positionMs: 5000,
                  contentRect: contentRect,
                  faceDirection: FaceDirection.original,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(NoteStickerText), findsNothing);
      expect(find.byKey(const Key('note_sticker_selected')), findsNothing);
    });
  });

  group('宿主挂载与播放头驱动（点选仲裁的命中面活着）', () {
    testWidgets('浮层挂载即按渲染矩形同步注册表：命中判定内生可用', (tester) async {
      final registration = await pumpOverlay(tester);
      final textRect = tester.getRect(find.byType(NoteStickerText));
      expect(registration.selected, isFalse);
      // 渲染矩形中心命中（宿主点选仲裁消费同一命中面）。
      final center = textRect.center;
      expect(registration.hitTest(center), isTrue);
      // 矩形外不命中。
      expect(registration.hitTest(center.translate(0, -100)), isFalse);
    });

    testWidgets('播放头出窗：浮层消失且命中面撤销、选中一并清', (tester) async {
      final registration = await pumpOverlay(tester);
      registration.select();
      await tester.pump();
      expect(registration.selected, isTrue);
      final center = tester.getRect(find.byType(NoteStickerText)).center;
      // 播放头移出时间窗（宿主换 positionMs 重建 → 同步 null）。
      await pumpOverlay(tester, positionMs: 5000, registration: registration);
      expect(find.byType(NoteStickerText), findsNothing);
      expect(registration.selected, isFalse);
      expect(registration.hitTest(center), isFalse);
    });

    testWidgets('真实播放页结构：LayoutBuilder 包裹下挂载不抛 ParentData 异常', (tester) async {
      // 复刻 player_page 接线（外层 Stack → LayoutBuilder → 内层 Stack →
      // 浮层）：Positioned 的直接父级须是 Stack，包裹层不得破坏
      // ParentData 归属（集成回归：control_layer_test 曾暴露 Incorrect
      // use of ParentDataWidget）。
      final registration = NoteStickerOverlayRegistration();
      final container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            const AnnotationRestoreDocument(
              notes: [NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手')],
            ),
          );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Listener(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          NoteStickerOverlay(
                            positionMs: 3000,
                            faceDirection: FaceDirection.original,
                            contentRect: videoContentRectInBox(
                              box: constraints.biggest,
                              aspectRatio: 2,
                            ),
                            registration: registration,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // 挂载成功：窗内贴纸渲染、命中面活着（不抛 ParentData 异常即通过）。
      expect(find.byType(NoteStickerText), findsOneWidget);
      expect(
        registration.hitTest(
          tester.getRect(find.byType(NoteStickerText)).center,
        ),
        isTrue,
      );
    });
  });

  group('内容矩形推导（引擎宽高比 → 信箱内画面区）', () {
    test('已知宽高比：按 contain 居中适配宿主框', () {
      expect(
        videoContentRectInBox(box: const Size(400, 200), aspectRatio: 2),
        const Rect.fromLTWH(0, 0, 400, 200),
      );
      expect(
        videoContentRectInBox(box: const Size(400, 200), aspectRatio: 1),
        const Rect.fromLTWH(100, 0, 200, 200),
      );
      expect(
        videoContentRectInBox(box: const Size(200, 400), aspectRatio: 2),
        const Rect.fromLTWH(0, 150, 200, 100),
      );
    });

    test('宽高比未知（null / 非法）：按宿主框整体兜底，不崩', () {
      expect(
        videoContentRectInBox(box: const Size(400, 200), aspectRatio: null),
        const Rect.fromLTWH(0, 0, 400, 200),
      );
      expect(
        videoContentRectInBox(box: const Size(400, 200), aspectRatio: -1),
        const Rect.fromLTWH(0, 0, 400, 200),
      );
      expect(videoContentRectInBox(box: Size.zero, aspectRatio: 2), Rect.zero);
    });
  });

  group('两类内容类点选仲裁（选中互斥、命中取顶层、点空白不唤控制层）', () {
    test('命中贴纸 → 选中贴纸（顶层优先，即便同时命中节拍浮层）', () {
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: true,
          noteSelected: false,
          metronomeVisible: true,
          metronomeSelected: true,
          hitMetronome: true,
        ),
        PlaybackOverlayTapAction.selectNoteSticker,
      );
    });

    test('未选中节拍浮层被命中 → 选中节拍浮层（贴纸让位后）', () {
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: false,
          metronomeVisible: true,
          metronomeSelected: false,
          hitMetronome: true,
        ),
        PlaybackOverlayTapAction.selectMetronome,
      );
    });

    test('选中态点浮层上 → 保持选中（两类同款）', () {
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: true,
          noteSelected: true,
          metronomeVisible: false,
          metronomeSelected: false,
          hitMetronome: false,
        ),
        PlaybackOverlayTapAction.keepSelected,
      );
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: false,
          metronomeVisible: true,
          metronomeSelected: true,
          hitMetronome: true,
        ),
        PlaybackOverlayTapAction.keepSelected,
      );
    });

    test('选中态点空白 → 仅清选中、不唤出控制层（deselectOnly）', () {
      // 贴纸选中、点空白。
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: true,
          metronomeVisible: false,
          metronomeSelected: false,
          hitMetronome: false,
        ),
        PlaybackOverlayTapAction.deselectOnly,
      );
      // 贴纸选中、空白处但节拍浮层可见未选中（贴纸选中优先清，不转选）。
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: true,
          metronomeVisible: true,
          metronomeSelected: false,
          hitMetronome: false,
        ),
        PlaybackOverlayTapAction.deselectOnly,
      );
      // 节拍浮层选中、点其外空白。
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: false,
          metronomeVisible: true,
          metronomeSelected: true,
          hitMetronome: false,
        ),
        PlaybackOverlayTapAction.deselectOnly,
      );
    });

    test('无选中、点空白（不落任何浮层）→ 宿主默认（唤出控制层）', () {
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: false,
          metronomeVisible: true,
          metronomeSelected: false,
          hitMetronome: false,
        ),
        PlaybackOverlayTapAction.hostDefault,
      );
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: false,
          metronomeVisible: false,
          metronomeSelected: false,
          hitMetronome: false,
        ),
        PlaybackOverlayTapAction.hostDefault,
      );
    });

    test('节拍浮层不可见时不参与仲裁', () {
      // 不可见即不命中、不选中。
      expect(
        resolvePlaybackOverlayTap(
          hitNoteSticker: false,
          noteSelected: false,
          metronomeVisible: false,
          metronomeSelected: false,
          hitMetronome: true,
        ),
        PlaybackOverlayTapAction.hostDefault,
      );
    });
  });
}
