import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/compare_materials.dart'
    show PracticeClip;
import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        practiceClipsProvider;
import 'package:dance_learning_app/player/track_band.dart';
import 'package:dance_learning_app/player/track_geometry.dart';
import 'package:dance_learning_app/player/track_practice_row.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/note_editor_harness.dart' show NopSaveSink;
import '../helpers/pump_settle.dart';
import '../helpers/track_band_session_harness.dart';
import '../helpers/track_row_geometry.dart';

/// 跨面一致性断言：
/// **带真实渲染出的行键与块体矩形，与各模块对同一输入的答案逐位相等**。
///
/// 同一份输入喂给两处：真实挂载整条带（渲染像素），与各模块的公开答案——
/// 轨道行表（行键与该行的整条矩形：纵向 top/height 即块体 `Positioned` 的
/// 纵向摆位）、练习片段轨域的 [practiceClipBlockRect]、区间片段行共用件
/// [intervalBlockRect]（备注轨与局部镜像轨的块体几何都经它求值）。行域与带
/// 各自漂移即红。像素比对沿用既有跨面断言的亚像素容差（0.01）口径。
///
/// 行集不同、输入同一份：编辑态行集（normal）验备注轨与局部镜像轨两行，
/// 对比态行集（compare）验练习视频轨行。
void main() {
  const total = Duration(minutes: 3);
  const window = TimelineWindow(
    total: total,
    start: Duration(seconds: 30),
    end: Duration(seconds: 90),
  );
  const windowSpan = IntervalSpan(startMs: 30000, endMs: 90000);

  testWidgets('带真实渲染的行键与块体矩形 == 各模块对同一输入的答案', (tester) async {
    // 编辑态行集：备注轨与局部镜像轨在场。
    final normal = await _pumpBand(
      tester,
      rowTable: TrackRowTable.normal,
      total: total,
      window: window,
    );
    _expectRowKeys(tester, normal, TrackRowTable.normal);
    for (var i = 0; i < notes.length; i++) {
      final answer = _intervalAnswer(normal, _spanOfNote(notes[i]), windowSpan);
      _expectBlockRect(
        tester,
        normal,
        rowTable: TrackRowTable.normal,
        label: '备注块 $i',
        key: 'note_fragment_$i',
        rowId: TrackRowId.note,
        answerLeft: answer.left,
        answerWidth: answer.width,
      );
    }
    for (var i = 0; i < mirrorFragments.length; i++) {
      final answer = _intervalAnswer(
        normal,
        _spanOfMirror(mirrorFragments[i]),
        windowSpan,
      );
      _expectBlockRect(
        tester,
        normal,
        rowTable: TrackRowTable.normal,
        label: '镜像块 $i',
        key: 'mirror_fragment_$i',
        rowId: TrackRowId.localMirror,
        answerLeft: answer.left,
        answerWidth: answer.width,
      );
    }

    // 对比态行集：练习视频轨行在场。
    final compare = await _pumpBand(
      tester,
      rowTable: TrackRowTable.compare,
      total: total,
      window: window,
    );
    _expectRowKeys(tester, compare, TrackRowTable.compare);
    for (final clip in clips) {
      final answer = practiceClipBlockRect(clip, axis: compare.geometry.axis);
      expect(answer, isNotNull, reason: '${clip.id} 在本窗口内有可映射几何');
      _expectBlockRect(
        tester,
        compare,
        rowTable: TrackRowTable.compare,
        label: '${clip.id} 块',
        key: 'practice_clip_${clip.id}',
        rowId: TrackRowId.practiceVideo,
        answerLeft: answer!.left,
        answerWidth: answer.width,
      );
    }
  });
}

/// 挂载整条带（一套容器 + 会话）：同一份输入、指定行集；返回带矩形与几何。
Future<({Rect bandRect, TrackBandGeometry geometry})> _pumpBand(
  WidgetTester tester, {
  required TrackRowTable rowTable,
  required Duration total,
  required TimelineWindow window,
}) async {
  final engine = FakePlaybackEngine(duration: total);
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      annotationSaveSinkProvider.overrideWithValue(NopSaveSink()),
      beatTrackStateProvider.overrideWithBuild(
        (ref, _) => uniformReadyBeatState(seconds: total.inSeconds.toDouble()),
      ),
    ],
  );
  addTearDown(container.dispose);
  final session = buildTrackBandSession(engine: engine, container: container);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: TrackBand(
            input: TrackBandInput(session: session, rowTable: rowTable),
          ),
        ),
      ),
    ),
  );
  await pumpSettle(tester);
  container.read(annotationEditorProvider).restoreDocument(
    AnnotationRestoreDocument(
      timeline: AnnotationTimeline.wholeVideo(total),
      localMirrorFragments: mirrorFragments,
      notes: notes,
    ),
  );
  container.read(practiceClipsProvider.notifier).state = clips;
  session.updateWindow(window);
  await pumpSettle(tester);

  final bandRect = tester.getRect(find.byKey(const Key('track_band')));
  return (
    bandRect: bandRect,
    geometry: bandGeometryOf(
      total: total,
      window: window,
      width: bandRect.width,
    ),
  );
}

/// 行键与行矩形：渲染出的每个行键逐位落回行表给的矩形。
void _expectRowKeys(
  WidgetTester tester,
  ({Rect bandRect, TrackBandGeometry geometry}) mounted,
  TrackRowTable table,
) {
  for (final row in table.rows) {
    final rendered = trackRowRect(tester, row.key);
    final answer = table.rectOf(row.id);
    expect(
      rendered.top - mounted.bandRect.top,
      answer.top,
      reason: '${row.key} 行顶 == 行表的答案',
    );
    expect(
      rendered.height,
      answer.height,
      reason: '${row.key} 行高 == 行表的答案',
    );
  }
}

/// 块体整条矩形：横向 == 该域/共用件对同一输入的答案（含窗口裁切），纵向 ==
/// 行表给该行的 top/height（块体的 `Positioned` 纵向摆位就是行矩形）。
void _expectBlockRect(
  WidgetTester tester,
  ({Rect bandRect, TrackBandGeometry geometry}) mounted, {
  required TrackRowTable rowTable,
  required String label,
  required String key,
  required TrackRowId rowId,
  required double answerLeft,
  required double answerWidth,
}) {
  final rendered = tester.getRect(find.byKey(Key(key)));
  final rowAnswer = rowTable.rectOf(rowId);
  expect(
    rendered.left - mounted.bandRect.left,
    closeTo(answerLeft, 0.01),
    reason: '$label 左缘 == 模块的答案',
  );
  expect(
    rendered.width,
    closeTo(answerWidth, 0.01),
    reason: '$label 宽 == 模块的答案（含窗口裁切）',
  );
  expect(
    rendered.top - mounted.bandRect.top,
    closeTo(rowAnswer.top, 0.01),
    reason: '$label 行内顶 == 行表的答案',
  );
  expect(
    rendered.height,
    closeTo(rowAnswer.height, 0.01),
    reason: '$label 行内高 == 行表的答案',
  );
}

/// 区间片段行共用件对同一输入的答案。
IntervalBlockRect _intervalAnswer(
  ({Rect bandRect, TrackBandGeometry geometry}) mounted,
  IntervalSpan span,
  IntervalSpan windowSpan,
) {
  final answer = intervalBlockRect(
    span: span,
    window: windowSpan,
    trackWidth: mounted.geometry.contentWidth,
    contentLeft: mounted.geometry.contentLeft,
  );
  expect(answer, isNotNull, reason: '$span 在本窗口内有可映射几何');
  return answer!;
}

const notes = [
  NoteSticker(startMs: 25000, endMs: 50000),
  NoteSticker(startMs: 85000, endMs: 95000),
];
const mirrorFragments = [
  LocalMirrorFragment(startMs: 20000, endMs: 45000),
  LocalMirrorFragment(startMs: 88000, endMs: 100000),
];
const clips = [
  PracticeClip(
    id: 'clip_left',
    materialId: 'material',
    materialSourceStartMs: 0,
    inMs: 20000,
    outMs: 60000,
  ),
  PracticeClip(
    id: 'clip_right',
    materialId: 'material',
    materialSourceStartMs: 0,
    inMs: 80000,
    outMs: 120000,
  ),
];

IntervalSpan _spanOfNote(NoteSticker note) =>
    IntervalSpan(startMs: note.startMs, endMs: note.endMs);

IntervalSpan _spanOfMirror(LocalMirrorFragment fragment) =>
    IntervalSpan(startMs: fragment.startMs, endMs: fragment.endMs);
