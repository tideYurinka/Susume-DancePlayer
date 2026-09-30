import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        layoutLockedProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/note_editor.dart'
    show noteTextEditorTargetProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_band_session.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetMinSize;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
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

/// 「片段行点按语义」widget 缝直测：备注片段单击 = 选中
/// （进标注选中单选槽）并在片段上方展开内容浮条；再单击已选中的片段 =
/// 打开编辑器（长按仍是锁定/解锁，不动）。点轨道空白 = 带级空白语义
///（单击收起一次、双击只切播放），行级层不复刻第二份判定窗口。
void main() {
  const total = Duration(minutes: 1);

  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  /// 泵出一个带就绪节拍网格 + 备注片段的 TrackBand，返回宿主与回调记录。
  Future<({
    ProviderContainer container,
    ValueNotifier<int> collapses,
    ValueNotifier<int> doubleTaps,
  })> pumpBandWithNotes({
    required WidgetTester tester,
    required List<NoteSticker> notes,
    TrackBandSession? session,
  }) async {
    final collapses = ValueNotifier<int>(0);
    final doubleTaps = ValueNotifier<int>(0);
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            // 顶部留白：备注轨为最顶行，浮条在其上方展开需要屏上空间
            //（否则屏幕顶缘钳制会把浮条压到片段上）。
            body: Padding(
              padding: const EdgeInsets.only(top: 120),
              child: TrackBand(
                input: TrackBandInput(
                  rowTable: TrackRowTable.normal,
                  onCollapse: () => collapses.value++,
                  onDoubleTap: () => doubleTaps.value++,
                  session:
                      session ??
                      buildTrackBandSession(
                        engine: engine,
                        container: container,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    container.read(annotationEditorProvider).restoreDocument(
          AnnotationRestoreDocument(
            timeline: AnnotationTimeline.wholeVideo(total),
            notes: notes,
          ),
        );
    await tester.pumpAndSettle();
    return (
      container: container,
      collapses: collapses,
      doubleTaps: doubleTaps,
    );
  }

  testWidgets('单击备注片段进选中态并在片段上方展开内容浮条', (tester) async {
    final (:container, :collapses, :doubleTaps) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '注意手')],
    );
    expect(container.read(annotationSelectionProvider), isNull);
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 14000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
      reason: '单击 = 选中（不直接进编辑器）',
    );
    expect(
      find.byKey(const Key('note_expand_bubble')),
      findsOneWidget,
      reason: '选中即展开内容浮条',
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('note_expand_bubble'))).dy,
      lessThan(rect.top),
      reason: '浮条在该片段上方',
    );
    expect(collapses.value, 0, reason: '片段点按不是空白单击、不收起');
    expect(doubleTaps.value, 0);
    container.dispose();
  });

  testWidgets('再单击已选中的片段 = 打开编辑器（编辑器以备注起点标识目标）', (tester) async {
    final (:container, collapses: collapses, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '注意手')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 14000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteTextEditorTargetProvider), isNull);
    expect(collapses.value, 0);
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 14000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteTextEditorTargetProvider), 10000);
    container.dispose();
  });

  testWidgets('展开浮条上的「编辑」入口能打开编辑器', (tester) async {
    final (:container, collapses: _, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '注意手')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 14000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteTextEditorTargetProvider), isNull);
    await tester.tap(find.byKey(const Key('note_expand_bubble_edit')));
    await tester.pumpAndSettle();
    expect(container.read(noteTextEditorTargetProvider), 10000);
    container.dispose();
  });

  testWidgets('展开浮条动作入口命中盒 ≥ 48 高（透明外扩、不遮正文）且仍可点', (tester) async {
    final (:container, collapses: _, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, text: '注意手')],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 14000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();

    final hit = tester.getRect(
      find.byKey(const Key('note_expand_bubble_edit_hit')),
    );
    expect(hit.height, greaterThanOrEqualTo(kHitTargetMinSize));
    expect(hit.width, greaterThanOrEqualTo(kHitTargetMinSize));
    // 外扩对称：命中盒中心 = 入口文案盒中心（观感不动）。
    final entry = tester.getRect(
      find.byKey(const Key('note_expand_bubble_edit')),
    );
    expect(hit.center.dx, closeTo(entry.center.dx, 0.01));
    expect(hit.center.dy, closeTo(entry.center.dy, 0.01));
    // 不遮正文：命中盒与浮条正文矩形不重叠。
    final textRect = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('note_expand_bubble')),
        matching: find.text('注意手'),
      ),
    );
    expect(hit.overlaps(textRect), isFalse, reason: '命中盒不盖正文');

    // 点命中盒下缘的外扩区（入口文案盒之外）仍打开编辑器。
    expect(container.read(noteTextEditorTargetProvider), isNull);
    await tester.tapAt(Offset(hit.center.dx, hit.bottom - 2));
    await tester.pumpAndSettle();
    expect(container.read(noteTextEditorTargetProvider), 10000);
    container.dispose();
  });

  testWidgets('点备注轨空白 = 空白处：单击经判定窗口收起一次、编辑目标不动', (tester) async {
    final (:container, :collapses, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 40000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pump();
    expect(collapses.value, 0, reason: '判定窗口内尚未收起');
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    expect(collapses.value, 1, reason: '空白单击 = 带级空白语义（收起一次）');
    expect(container.read(noteTextEditorTargetProvider), isNull);
    expect(container.read(annotationSelectionProvider), isNull);
    container.dispose();
  });

  testWidgets('备注轨空白双击只切播放、不收起', (tester) async {
    final (:container, :collapses, :doubleTaps) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 40000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 40000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    expect(doubleTaps.value, 1, reason: '双击 = 只切播放');
    expect(collapses.value, 0, reason: '双击不收起');
    container.dispose();
  });

  testWidgets('相邻窄片段多候选取距中心最近；同距取靠前', (tester) async {
    final (:container, collapses: _, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(startMs: 10000, endMs: 10500),
        NoteSticker(startMs: 10800, endMs: 11300),
      ],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    // 两窄片段视觉宽 ≈ 8px / 6px，均远小于最小命中宽 [kNoteTapHitWidth]；
    // 点按 10650 落在间隙，两片段扩展域重叠且距两中心等距（10650 =
    // 10250/11050 中点）→ 同距取靠前。
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 10650), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>().having((s) => s.index, 'index', 0),
      reason: '同距取靠前 → 选中首片段',
    );
    // 点按 10560 更靠近首片段中心——但首片段已被选中：再单击已选中的片
    // 段 = 打开编辑器，顺带见证命中解析仍指向首片段。
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 10560), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(container.read(noteTextEditorTargetProvider), 10000,
        reason: '再单击已选中的首片段 → 打开编辑器（解析更近首片段中心）');
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 10810), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>().having((s) => s.index, 'index', 1),
      reason: '点按更靠近次片段中心 → 选中次片段',
    );
    container.dispose();
  });

  testWidgets('窄片段点附近即命中：命中域对称扩展至最小命中宽', (tester) async {
    final (:container, collapses: _, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 10050)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    // 视觉宽 50ms ≈ 0.7px；点按片段右缘外 300ms 处仍在扩展命中域内。
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 10300), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );
    container.dispose();
  });

  testWidgets('锁定分段开启：单击照常选中（锁只护几何）', (tester) async {
    final (:container, collapses: _, doubleTaps: _) = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    container.read(layoutLockedProvider.notifier).toggle();
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await tester.tapAt(Offset(bandXOf(Duration(milliseconds: 14000), total: total, width: rect.width, bandLeft: rect.left), rect.center.dy));
    await tester.pumpAndSettle();
    expect(
      container.read(annotationSelectionProvider),
      isA<NoteFragmentSelection>(),
    );
    container.dispose();
  });
}
