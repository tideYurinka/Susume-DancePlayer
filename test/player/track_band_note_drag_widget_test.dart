import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart'
    show ToggleNoteLock;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSelectionDomainProvider,
        annotationSaveSinkProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player/note_editor.dart'
    show noteFragmentHighlightProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
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

/// 「轨片段拖动」widget 缝直测：块体水平拖 = 整体移（宽
/// 度不变）、端点带拖 = 改起止、端点命中域让位到块外空隙（自适应
/// 分配、选中后端点柄更长）、拖动落点吸附拍点、备注内容锁开启时拖动起手
/// 静默不参与、锁定标识渲染。
void main() {
  const total = Duration(minutes: 1);

  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
  });

  /// 泵出一个带就绪节拍网格 + 备注片段的 TrackBand。
  Future<ProviderContainer> pumpBandWithNotes({
    required WidgetTester tester,
    required List<NoteSticker> notes,
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: TrackBand(
              input: TrackBandInput(
                session: buildTrackBandSession(
                  engine: engine,
                  container: container,
                ),
                rowTable: TrackRowTable.normal,
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
            notes: notes,
          ),
        );
    await tester.pumpAndSettle();
    return container;
  }

  /// 在全局 [from] 处起手、向右水平拖动 [dx] 像素（分步移动以越过拖动
  /// slop 触发水平拖动识别，片段拖动逐帧读手指位置）。
  Future<void> dragFromRight(
    WidgetTester tester,
    Offset from,
    double dx,
  ) async {
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  // 时间↔带内像素经共享测试入口（内容区左缘让出轨道片头带），
  // 不在本文件重写换算公式。
  double xOf(Rect rect, int ms) => bandXOf(
    Duration(milliseconds: ms),
    total: total,
    width: rect.width,
    bandLeft: rect.left,
  );

  /// 时间差 → 像素差（同一换算的差值）。
  double pxFor(Rect rect, int ms) => xOf(rect, ms) - xOf(rect, 0);

  testWidgets('块体水平拖动 = 整体移：宽度不变、落点吸附拍点', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await dragFromRight(
      tester,
      Offset(xOf(rect, 14000), rect.center.dy),
      pxFor(rect, 3000),
    );
    final note = container.read(noteStickersProvider).single;
    expect(note.endMs - note.startMs, 8000, reason: '整体移保持原宽');
    expect(note.startMs % 500, 0, reason: '就绪网格落点吸附拍点（每 0.5s 一个拍点）');
    expect(note.startMs, greaterThan(10000), reason: '随手指右移');
    container.dispose();
  });

  testWidgets('宽块渲染端点命中带（块外空隙）；start 带拖动只改起点', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    expect(find.byKey(const Key('note_fragment_0')), findsOneWidget);
    expect(find.byKey(const Key('note_fragment_0_edge_start')), findsOneWidget);
    expect(find.byKey(const Key('note_fragment_0_edge_end')), findsOneWidget);

    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    final blockLeft = xOf(rect, 10000);
    final startBand = tester.getRect(
      find.byKey(const Key('note_fragment_0_edge_start')),
    );
    expect(
      startBand.right,
      closeTo(blockLeft, 0.5),
      reason: '命中域让位到块外空隙（start 带贴块左缘外侧）',
    );
    expect(startBand.width, kNoteEdgeHitWidth, reason: '空隙充足给满端点带');
    await dragFromRight(
      tester,
      Offset(blockLeft - kNoteEdgeHitWidth / 2, rect.center.dy),
      pxFor(rect, 3000),
    );
    final note = container.read(noteStickersProvider).single;
    expect(note.endMs, 18000, reason: 'start 端点拖只动起点');
    expect(note.startMs, greaterThan(10000));
    expect(note.startMs % 500, 0, reason: '端点落点同吸附拍点');
    container.dispose();
  });

  testWidgets('端点带不越出带内可用横向范围：贴带缘一侧全给、不越界', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    final startBand = tester.getRect(
      find.byKey(const Key('note_fragment_0_edge_start')),
    );
    final endBand = tester.getRect(
      find.byKey(const Key('note_fragment_0_edge_end')),
    );
    expect(startBand.left, greaterThanOrEqualTo(rect.left - 0.5));
    expect(endBand.right, lessThanOrEqualTo(rect.right + 0.5));
    container.dispose();
  });

  testWidgets('相邻片段冲突让位：贴邻空隙为零时两端带都不渲染、块体拖可达', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(startMs: 10000, endMs: 18000),
        NoteSticker(startMs: 18000, endMs: 26000),
      ],
    );
    expect(
      find.byKey(const Key('note_fragment_0_edge_end')),
      findsNothing,
      reason: '右邻贴邻（半开共享端点）→ end 侧无空隙、整段让出',
    );
    expect(
      find.byKey(const Key('note_fragment_1_edge_start')),
      findsNothing,
      reason: '左邻贴邻 → start 侧整段让出',
    );
    // 块体拖仍可达：最坏退化成整块归移动。
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await dragFromRight(
      tester,
      Offset(xOf(rect, 22000), rect.center.dy),
      pxFor(rect, 3000),
    );
    final notes = container.read(noteStickersProvider);
    expect(notes[1].endMs - notes[1].startMs, 8000, reason: '块体拖 = 整体平移');
    container.dispose();
  });

  testWidgets('相邻片段冲突让位：窄空隙两侧各让半、两带互不侵占', (tester) async {
    // 间隙 1000ms ≈ 13.3px：两侧目标带宽 14px 都放不进整条空隙，
    // 各取空隙的一半即互不侵占（冲突处让出）。
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [
        NoteSticker(startMs: 10000, endMs: 18000),
        NoteSticker(startMs: 19000, endMs: 26000),
      ],
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    final gapPx = pxFor(rect, 1000);
    final band0 = tester.getRect(
      find.byKey(const Key('note_fragment_0_edge_end')),
    );
    final band1 = tester.getRect(
      find.byKey(const Key('note_fragment_1_edge_start')),
    );
    expect(band0.width, closeTo(gapPx / 2, 0.5), reason: 'end 侧让半');
    expect(band1.width, closeTo(gapPx / 2, 0.5), reason: 'start 侧让半');
    expect(
      band0.right,
      lessThanOrEqualTo(band1.left + 0.5),
      reason: '两带在空隙内互不侵占',
    );
    container.dispose();
  });

  testWidgets('默认缩放窄块：端点带让位块外、块体拖整体移可达（无死区）', (tester) async {
    // 1250ms 块在 60s 满窗 ≈ 16.7px（默认缩放下的一个八拍量级）。
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 8000, endMs: 9250)],
    );
    final blockRect = tester.getRect(find.byKey(const Key('note_fragment_0')));
    expect(blockRect.width, closeTo(bandContentWidth(800) * 1250 / 60000, 0.5));
    expect(
      find.byKey(const Key('note_fragment_0_edge_start')),
      findsOneWidget,
      reason: '窄块不再整段抑制：命中域让位到块外空隙',
    );
    expect(find.byKey(const Key('note_fragment_0_edge_end')), findsOneWidget);

    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    // dx 取 3s：扣拖动 slop（≈1.4s）后请求 ≈8s+1.6s，按拍点吸附落在下一个
    // 拍点（8s 之后第一个）——八拍口径会把这条请求吸回 8s，看着像"没动"。
    await dragFromRight(
      tester,
      Offset(xOf(rect, 8625), rect.center.dy),
      pxFor(rect, 3000),
    );
    final note = container.read(noteStickersProvider).single;
    expect(note.endMs - note.startMs, 1250, reason: '块体拖 = 整体平移');
    expect(note.startMs % 500, 0);
    expect(note.startMs, greaterThan(8000), reason: '块体拖起手可达（不被吞）');
    container.dispose();
  });

  testWidgets('选中后两端出现端点柄：命中域更长、拖柄改时间窗起止', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    expect(find.byKey(const Key('note_fragment_0_handle_start')), findsNothing);
    container
        .read(annotationSelectionDomainProvider)
        .select(NoteFragmentSelection(0));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    final blockLeft = xOf(rect, 10000);
    final startBand = tester.getRect(
      find.byKey(const Key('note_fragment_0_edge_start')),
    );
    expect(startBand.width, kNoteSelectedEdgeHitWidth, reason: '选中端点柄命中域更长');
    expect(
      find.byKey(const Key('note_fragment_0_handle_start')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('note_fragment_0_handle_end')), findsOneWidget);

    await dragFromRight(
      tester,
      Offset(blockLeft - kNoteSelectedEdgeHitWidth / 2, rect.center.dy),
      pxFor(rect, 3000),
    );
    final note = container.read(noteStickersProvider).single;
    expect(note.endMs, 18000, reason: '拖柄 = 端点拖：只动起点');
    expect(note.startMs, greaterThan(10000));
    expect(note.startMs % 500, 0, reason: '落点吸附与互斥钳制沿既有');
    container.dispose();
  });

  testWidgets('可见端点柄落在自身命中带内：按住看见的柄即改起点', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    container
        .read(annotationSelectionDomainProvider)
        .select(NoteFragmentSelection(0));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    final handle = tester.getRect(
      find.byKey(const Key('note_fragment_0_handle_start')),
    );
    final startBand = tester.getRect(
      find.byKey(const Key('note_fragment_0_edge_start')),
    );
    expect(
      startBand.contains(handle.center),
      isTrue,
      reason: '所见即所拖：柄条画在本侧端点命中带内',
    );

    await dragFromRight(tester, handle.center, pxFor(rect, 3000));
    final note = container.read(noteStickersProvider).single;
    expect(note.endMs, 18000, reason: '按住可见柄 = 端点拖：只动起点');
    expect(note.startMs, greaterThan(10000));
    container.dispose();
  });

  // 备注两族不受锁定分段（门禁归属）由模块门禁表套件承担，起手与相对平移
  // 由域直测承担：annotation_editor_gesture_target_test.dart「锁定分段：
  // 被拒 ⇔ 声明含用户锁」；track_band_drag_test.dart「内容锁准入：备注两族
  // 被拒时静默不参与」与「镜像与备注四族 / 抓取偏移与相对平移」。

  testWidgets('内容锁：整体移起手静默不参与、不弹提示', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
    );
    final promptCount = container.read(
      noticeTriggerProvider(NoticeId.noteContentLock),
    );
    final highlightCount = container.read(noteFragmentHighlightProvider);
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await dragFromRight(
      tester,
      Offset(xOf(rect, 14000), rect.center.dy),
      pxFor(rect, 3000),
    );
    expect(
      container.read(noteStickersProvider).single,
      const NoteSticker(startMs: 10000, endMs: 18000, locked: true),
      reason: '已锁备注整体移不起手，时间窗不动',
    );
    expect(
      container.read(noticeTriggerProvider(NoticeId.noteContentLock)),
      promptCount,
      reason: '拖动起手静默不参与：不弹「备注已锁定」提示',
    );
    expect(
      container.read(noteFragmentHighlightProvider),
      highlightCount,
      reason: '起手未发生：定位高亮不清',
    );
    container.dispose();
  });

  testWidgets('内容锁：端点拖起手静默不参与、不弹提示', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
    );
    final promptCount = container.read(
      noticeTriggerProvider(NoticeId.noteContentLock),
    );
    final rect = tester.getRect(find.byKey(const Key('track_notes')));
    await dragFromRight(
      tester,
      Offset(xOf(rect, 10000) - kNoteEdgeHitWidth / 2, rect.center.dy),
      pxFor(rect, 3000),
    );
    expect(
      container.read(noteStickersProvider).single,
      const NoteSticker(startMs: 10000, endMs: 18000, locked: true),
      reason: '已锁备注端点拖不起手，时间窗不动',
    );
    expect(
      container.read(noticeTriggerProvider(NoticeId.noteContentLock)),
      promptCount,
      reason: '端点拖起手同样静默：不弹提示（入口判定一致）',
    );
    container.dispose();
  });

  // 未锁备注整体移的相对平移语义（请求 = 手指时间 − 片段起点）由域直测承担：
  // track_band_drag_test.dart「镜像与备注四族 / 抓取偏移与相对平移」；带侧
  // 边界来源装配由 track_band_fragment_drag_boundary_test.dart 承担。

  testWidgets('锁定标识：已锁片段渲染锁角标、解锁后即时消失', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000, locked: true)],
    );
    expect(
      find.byKey(const Key('note_fragment_0_lock')),
      findsOneWidget,
      reason: '已锁备注的片段渲染锁定标识',
    );
    container
        .read(annotationEditorProvider)
        .submit(const ToggleNoteLock(index: 0));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('note_fragment_0_lock')),
      findsNothing,
      reason: '解锁后标识即时消失（与锁字段一致）',
    );
    container.dispose();
  });

  testWidgets('未锁片段不渲染锁定标识', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    expect(find.byKey(const Key('note_fragment_0_lock')), findsNothing);
    container.dispose();
  });

  testWidgets('行高问行表：备注轨 36dp 常驻（拖动交互不改变行几何）', (tester) async {
    final container = await pumpBandWithNotes(
      tester: tester,
      notes: const [NoteSticker(startMs: 10000, endMs: 18000)],
    );
    expect(
      tester.getSize(find.byKey(const Key('track_notes'))).height,
      TrackRowTable.normal.rectOf(TrackRowId.note).height,
    );
    container.dispose();
  });
}
