import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
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

  /// 注入窗内备注并泵入宿主 Stack；[readOnly] = 编辑态（控制层展开）。
  Future<NoteStickerOverlayRegistration> pumpOverlay(
    WidgetTester tester, {
    int positionMs = 3000,
    bool readOnly = false,
    NoteStickerOverlayRegistration? registration,
  }) async {
    final noteRegistration =
        registration ?? NoteStickerOverlayRegistration();
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

  group('编辑态只读常显', () {
    testWidgets('编辑态窗内贴纸可见（只读渲染文本）', (tester) async {
      await pumpOverlay(tester, readOnly: true);
      expect(find.byType(NoteStickerText), findsOneWidget);
    });

    testWidgets('编辑态窗外贴纸不可见', (tester) async {
      await pumpOverlay(tester, positionMs: 5000, readOnly: true);
      expect(find.byType(NoteStickerText), findsNothing);
    });
  });

  group('编辑态不参与命中（纯展示，不抢播放页手势）', () {
    testWidgets('编辑态贴纸矩形上命中为假（点其矩形无反应、透传宿主）', (tester) async {
      final registration = await pumpOverlay(tester, readOnly: true);
      final center = tester.getRect(find.byType(NoteStickerText)).center;
      expect(registration.hitTest(center), isFalse);
      expect(registration.selected, isFalse);
    });

    testWidgets('播放态选中 → 进编辑态即清选中、无选中框残留', (tester) async {
      final registration = await pumpOverlay(tester);
      registration.select();
      await tester.pump();
      expect(registration.selected, isTrue);
      // 进入编辑态（控制层展开 → readOnly 重建）。
      await pumpOverlay(tester, readOnly: true, registration: registration);
      expect(registration.selected, isFalse);
      expect(find.byKey(const Key('note_sticker_selected')), findsNothing);
    });

    testWidgets('播放态行为不变：退回播放态后命中恢复、可再选中', (tester) async {
      final registration =
          await pumpOverlay(tester, readOnly: true);
      final center = tester.getRect(find.byType(NoteStickerText)).center;
      expect(registration.hitTest(center), isFalse);
      // 收起控制层（退回播放态）：命中面恢复。
      await pumpOverlay(tester, registration: registration);
      expect(registration.hitTest(center), isTrue);
      registration.select();
      await tester.pump();
      expect(registration.selected, isTrue);
      expect(find.byKey(const Key('note_sticker_selected')), findsOneWidget);
    });
  });
}
