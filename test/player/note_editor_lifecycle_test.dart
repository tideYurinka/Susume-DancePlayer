// 编辑面开与关的生命周期——打开即暂停（不自动恢复）、系统返回
// = 收起即存不退页、删除后即时清编辑目标、撤销恢复不再弹旧文本编辑框。
import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/note_editor_harness.dart';
import '../helpers/video_index_fixtures.dart';

class _NopSaveSink implements AnnotationSaveSink {
  @override
  void save(AnnotationSectionDiff diff) {}

  @override
  Future<void> flush() async {}
}

void main() {
  group('编辑面生命周期', () {
    testWidgets('删除备注后即时清编辑目标：两处入口同经模块，删完面板收起且目标为空', (tester) async {
      final container = noteEditorContainer();
      await pumpNoteEditorPanel(tester, container);
      seedAndOpenNoteEditor(container);
      await tester.pump();
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);

      // 编辑器内「删除」入口（贴纸左上角删除同经 annotationEditor.removeNote，
      // 目标清理由面板按「目标备注消失」统一收口——两处入口自动一致）。
      await tester.tap(find.byKey(const Key('note_editor_delete')));
      await tester.pump();

      expect(find.byKey(const Key('note_text_editor')), findsNothing);
      expect(container.read(noteTextEditorTargetProvider), isNull);
    });

    testWidgets('撤销恢复那条备注后编辑面保持关闭；再点该片段文本正确', (tester) async {
      final container = noteEditorContainer();
      await pumpNoteEditorPanel(tester, container);
      seedAndOpenNoteEditor(container);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '注意手',
      );
      await tester.tap(find.byKey(const Key('note_editor_done')));
      await tester.pump();
      expect(container.read(noteStickersProvider).single.text, '注意手');

      // 删除（目标随之清空）→ 撤销恢复 → 面板不得带着旧文本弹回来。
      container.read(annotationEditorProvider).submit(RemoveNote(index: 0));
      await tester.pump();
      expect(container.read(noteTextEditorTargetProvider), isNull);
      container.read(annotationEditorProvider).undo();
      await tester.pump();
      expect(container.read(noteStickersProvider), hasLength(1));
      expect(find.byKey(const Key('note_text_editor')), findsNothing);

      // 再点该片段（片段单击入口同路 open）正常打开、文本正确。
      container.read(noteTextEditorTargetProvider.notifier).open(10000);
      await tester.pump();
      expect(find.byKey(const Key('note_text_editor')), findsOneWidget);
      expect(
        tester.widget<TextField>(
          find.byKey(const Key('note_text_editor_field')),
        ),
        isA<TextField>().having(
          (field) => field.controller!.text,
          'text',
          '注意手',
        ),
      );
    });

    testWidgets('系统返回键 = 收起即存且不退页：刚打的字已写入备注', (tester) async {
      final container = noteEditorContainer();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const Scaffold(body: NoteTextEditorPanel()),
          ),
        ),
      );
      await tester.pump();
      seedAndOpenNoteEditor(container);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '返回也存',
      );

      // 模拟系统返回键（根路由 maybePop）：面板 PopScope 接管 → 收起即存、
      // 路由不弹出（maybePop 返回 true 表示请求被面板接管并处理）。
      final popped = await navigatorKey.currentState!.maybePop();
      await tester.pump();

      expect(popped, isTrue);
      expect(find.byType(Scaffold), findsOneWidget);
      expect(container.read(noteStickersProvider).single.text, '返回也存');
      expect(container.read(noteTextEditorTargetProvider), isNull);
    });
  });

  group('打开编辑面即暂停（播放页统一接线）', () {
    Future<ProviderContainer> pumpPlayerPage(
      WidgetTester tester,
      FakePlaybackEngine engine,
      GlobalKey<NavigatorState> navigatorKey,
    ) async {
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
            privateJsonStorageProvider.overrideWithValue(
              InMemoryPrivateJsonStorage(),
            ),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
            annotationSaveSinkProvider.overrideWithValue(_NopSaveSink()),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(filePath: '/videos/a.mp4', mirrored: false),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: Builder(
              builder: (context) {
                container = ProviderScope.containerOf(context);
                return PlayerPage(source: Uri.file('/videos/a.mp4'));
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('打开编辑面即暂停视频；收起后不自动恢复', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final container = await pumpPlayerPage(tester, engine, GlobalKey());
      await engine.play();
      expect(engine.isPlaying, isTrue);

      // 三处入口统一汇到 noteTextEditorTargetProvider.open（新建即弹 /
      // 片段再单击 / 贴纸右上角各自以此为唯一写点），播放页在 provider 边沿
      // 统一暂停——一处实现、三处一致。
      container.read(noteTextEditorTargetProvider.notifier).open(10000);
      await tester.pump();
      expect(engine.isPlaying, isFalse);

      container.read(noteTextEditorTargetProvider.notifier).close();
      await tester.pump();
      // 刻意不对称：收起不自动恢复播放。
      expect(engine.isPlaying, isFalse);
    });

    testWidgets('打开编辑面暂停后播放态同步：控制层按钮不再停在「暂停」', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final container = await pumpPlayerPage(tester, engine, GlobalKey());
      expect(engine.isPlaying, isTrue, reason: '进页即开播');

      // 进控制层（编辑态）：单击播放面、等过双击判定窗口。
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      IconButton playButton() =>
          tester.widget<IconButton>(find.byKey(const Key('toolbar_play')));
      expect(playButton().tooltip, '暂停', reason: '在播时控制层按「在播」渲染');

      container.read(noteTextEditorTargetProvider.notifier).open(10000);
      await tester.pump();
      expect(engine.isPlaying, isFalse);
      expect(
        playButton().tooltip,
        '播放',
        reason: '暂停已随引擎播放态边沿同步到 UI，按钮不再停在「暂停」',
      );

      container.read(noteTextEditorTargetProvider.notifier).close();
      await tester.pump();
      expect(engine.isPlaying, isFalse, reason: '收起不自动恢复播放');

      await tester.tap(find.byKey(const Key('toolbar_play')));
      await tester.pump();
      expect(engine.isPlaying, isTrue, reason: '恢复播放一次点按即生效');
    });

    testWidgets('真实播放页上系统返回 = 收起即存且不退页', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      final navigatorKey = GlobalKey<NavigatorState>();
      final container = await pumpPlayerPage(tester, engine, navigatorKey);
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            AnnotationRestoreDocument(
              timeline: AnnotationTimeline.wholeVideo(
                const Duration(minutes: 1),
              ),
              notes: const [NoteSticker(startMs: 10000, endMs: 14000)],
            ),
          );
      container.read(noteTextEditorTargetProvider.notifier).open(10000);
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('note_text_editor_field')),
        '页面级返回也存',
      );

      await navigatorKey.currentState!.maybePop();
      await tester.pump();

      // 播放页仍在（不退页）、刚打的字已写入备注、编辑面收起。
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(container.read(noteStickersProvider).single.text, '页面级返回也存');
      expect(container.read(noteTextEditorTargetProvider), isNull);
    });
  });
}
