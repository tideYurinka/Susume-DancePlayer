import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationSelectionDomainProvider,
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSaveSinkProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:dance_learning_app/player/track_band_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/track_row_geometry.dart';

class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「片段行点按语义」widget 缝直测：选中与展开的三条清除
/// 路径、单选槽互斥、展开浮条超宽、选中不持久化；局部镜像轨空白与备注
/// 轨空白语义一致。
void main() {
  const total = Duration(minutes: 1);

  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;
  late TrackBandSession session;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  Future<ProviderContainer> pumpBandWithNotes({
    required WidgetTester tester,
    required List<NoteSticker> notes,
    ValueNotifier<int>? collapses,
  }) async {
    final container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
        beatTrackStateProvider.overrideWithBuild(
          (ref, _) =>
              uniformReadyBeatState(seconds: total.inMilliseconds / 1000),
        ),
      ],
    );
    session = buildTrackBandSession(engine: engine, container: container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: session,
                rowTable: TrackRowTable.normal,
                onCollapse: collapses != null ? () => collapses.value++ : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            timeline: AnnotationTimeline.wholeVideo(total),
            localMirrorFragments: const [
              LocalMirrorFragment(startMs: 30000, endMs: 34000),
            ],
            notes: notes,
          ),
        );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapNote(WidgetTester tester, Rect row, int ms) async {
    await tester.tapAt(
      Offset(
        bandXOf(
          Duration(milliseconds: ms),
          total: total,
          width: row.width,
          bandLeft: row.left,
        ),
        row.center.dy,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('三条清除路径：点轨道空白清选中', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );
    await tester.tapAt(
      Offset(
        bandXOf(
          Duration(milliseconds: 40000),
          total: total,
          width: rect.width,
          bandLeft: rect.left,
        ),
        rect.center.dy,
      ),
    );
    await tester.pump(kDoubleTapWindow);
    expect(
      container.read(annotationSelectionProvider),
      isNull,
      reason: '点轨道空白 = 清除路径一',
    );
    container.dispose();
  });

  testWidgets('三条清除路径：选中另一条片段自动清除前一条', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(startMs: 10000, endMs: 18000, text: '甲'),
        NoteSticker(startMs: 30000, endMs: 36000, text: '乙'),
      ],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);
    await tapNote(tester, rect, 32000);
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>().having((s) => s.index, 'index', 1),
      reason: '选中另一条片段 = 清除路径二（单选槽互斥）',
    );
    container.dispose();
  });

  testWidgets('三条清除路径：播放头越过该备注自身的时间窗清选中', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );

    // 播放头从 0s 走进窗内：只在「跨出」时清，走进来不清。
    await engine.seek(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
      reason: '在播时点选播放头不在其中的片段是常规操作，不得被位置 tick 立刻清掉',
    );

    // 越过 18s 尾缘 → 播放头离开该备注的时间窗。
    await engine.seek(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isNull,
      reason: '播放头离开时间窗 = 清除路径三',
    );
    container.dispose();
  });

  testWidgets('三条清除路径：选中片段随窗口平移离场清选中', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );
    // 窗口平移到 30–40s：这条备注整段离场（选中框与浮条没有承载物）。
    session.updateWindow(
      const TimelineWindow(
        total: total,
        start: Duration(seconds: 30),
        end: Duration(seconds: 40),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(annotationSelectionProvider), isNull);
    container.dispose();
  });

  testWidgets('选中态与局部镜像片段互斥（同一个单选槽）', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );
    container
        .read(annotationSelectionDomainProvider)
        .select(LocalMirrorFragmentSelection(0));
    expect(
      container.read(annotationSelectionProvider),
      isA<LocalMirrorFragmentSelection>(),
      reason: '点选镜像片段后备注选中自动清除',
    );
    container.dispose();
  });

  testWidgets('展开浮条宽度按文本实测、允许超出片段自身宽度', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(startMs: 10000, endMs: 10300, text: '这一句很短的片段也要能读全'),
      ],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 10150);
    final bubble = tester.getSize(find.byKey(const Key('note_expand_bubble')));
    final fragment = tester.getSize(find.byKey(const Key('note_fragment_0')));
    expect(
      bubble.width,
      greaterThan(fragment.width),
      reason: '很短的片段也能读全句：浮条宽按文本实测',
    );
    container.dispose();
  });

  testWidgets('展开浮条正文不被裁切：字形盒落在预留正文盒内（量测与渲染同源）', (tester) async {
    // 同一缺陷类（见 `学习段说明缩字：判定与渲染同源`）：浮条正文盒的宽高按
    // TextPainter 实测（样式不带 height、不合并环境）预留，而渲染的 Text 会
    // 与环境 DefaultTextStyle 合并（Material bodyMedium 带 letterSpacing 0.25、
    // height 1.43）——两侧不同源时渲染宽于/高于预留盒，正文末字被省略号吃掉、
    // 下缘被裁。
    const text = '右肩下沉';
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: text)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);

    final finder = find.descendant(
      of: find.byKey(const Key('note_expand_bubble')),
      matching: find.text(text),
    );
    expect(finder, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '正文单行放不下：量测宽比渲染宽小（末字被省略号吃掉）',
    );
    final box = tester.getSize(finder);
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: text.length),
    );
    expect(boxes, isNotEmpty);
    for (final glyph in boxes) {
      expect(
        glyph.top,
        greaterThanOrEqualTo(-0.01),
        reason: '字形盒越出预留正文盒上缘（环境行高把正文顶下去）',
      );
      expect(
        glyph.bottom,
        lessThanOrEqualTo(box.height + 0.01),
        reason: '字形盒越出预留正文盒下缘：正文下缘被裁',
      );
      expect(
        glyph.right,
        lessThanOrEqualTo(box.width + 0.01),
        reason: '字形盒越出预留正文盒右缘',
      );
    }
    container.dispose();
  });

  testWidgets('超屏部分省略：浮条不越出屏幕边缘', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(
          startMs: 10000,
          endMs: 10300,
          text:
              '一条非常非常非常长的备注内容，用来把浮条宽度顶到屏幕边缘之外，'
              '验证屏幕边缘钳制与超屏省略都生效，而不是把浮条画出屏幕。',
        ),
      ],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 10150);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final bubble = tester.getRect(find.byKey(const Key('note_expand_bubble')));
    expect(bubble.left, greaterThanOrEqualTo(0));
    expect(bubble.right, lessThanOrEqualTo(screen.width));
    container.dispose();
  });

  testWidgets('选中不持久化：重开播放页（全复位）后不残留', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tapNote(tester, rect, 14000);
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );
    container.read(annotationEditorProvider).resetForVideo(total);
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isNull,
      reason: '选中不持久化：重开播放页（全复位）不残留',
    );
    container.dispose();
  });

  testWidgets('局部镜像轨空白点按与备注轨一致：单击收起一次、不动选中', (tester) async {
    final collapses = ValueNotifier<int>(0);
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '甲')],
      collapses: collapses,
    );
    final mirror = tester.getRect(find.byKey(const Key('track_mirror')));
    // 50s 处镜像轨无片段（片段在 30–34s）= 镜像轨空白。
    await tester.tapAt(
      Offset(
        bandXOf(
          Duration(milliseconds: 50000),
          total: total,
          width: mirror.width,
          bandLeft: mirror.left,
        ),
        mirror.center.dy,
      ),
    );
    await tester.pump(kDoubleTapWindow);
    expect(collapses.value, 1, reason: '镜像轨空白 = 带级空白语义（收起一次）');
    expect(container.read(annotationSelectionProvider), isNull);
    container.dispose();
  });
}

/// 双击判定窗口（与 BlankTapArbiter 的 kDoubleTapTimeout 同值口径）。
const Duration kDoubleTapWindow = Duration(milliseconds: 400);
