import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSaveSinkProvider;
import 'package:dance_learning_app/player/note_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_playback_engine.dart';

/// 记录型保存 sink（直通）。
class NopSaveSink implements AnnotationSaveSink {
  @override
  void save(AnnotationSectionDiff diff) {}

  @override
  Future<void> flush() async {}
}

/// 备注编辑器面 widget 缝测共用脚手架：起容器（引擎 + 保存 sink 覆写）、
/// 挂面板、造一条既有备注并打开编辑器（起点 10s、窗宽 4s；[text] 缺省
/// 空串——「空文本 = 占位」这一形态仍可造出，用来测它在收起时的去向）。
ProviderContainer noteEditorContainer() => ProviderContainer(
  overrides: [
    playbackEngineProvider.overrideWithValue(
      FakePlaybackEngine(duration: const Duration(minutes: 1)),
    ),
    annotationSaveSinkProvider.overrideWithValue(NopSaveSink()),
  ],
);

Future<void> pumpNoteEditorPanel(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      // 与真实播放页同款（resizeToAvoidBottomInset: false）：键盘感知停靠
      // 只能读窗口 inset 位移，不靠 Scaffold 布局让位。
      child: const MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: NoteTextEditorPanel(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void seedAndOpenNoteEditor(ProviderContainer container, {String text = ''}) {
  container
      .read(annotationEditorProvider)
      .restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(const Duration(minutes: 1)),
          notes: [NoteSticker(startMs: 10000, endMs: 14000, text: text)],
        ),
      );
  container.read(noteTextEditorTargetProvider.notifier).open(10000);
}
